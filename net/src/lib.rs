//! iroh gossip networking for html-boggle, compiled to WebAssembly for the browser.
//!
//! The JS glue turns a room code into a 32-byte gossip topic id (sha256). Everyone
//! who enters the same room code therefore joins the same gossip channel and gets
//! connected automatically. Browser endpoints run relay-only and find each other
//! through iroh's HTTPS address lookup (the `N0` preset publishes and resolves
//! endpoint addresses via `iroh.link`, which works from browser sandboxes).

use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Result};
use iroh::protocol::Router;
use iroh_gossip::{
    api::{Event as GossipEvent, GossipSender},
    net::{GOSSIP_ALPN, Gossip},
    proto::TopicId,
};
use n0_future::StreamExt;
use tracing::level_filters::LevelFilter;
use tracing_subscriber_wasm::MakeConsoleWriter;
use wasm_bindgen::{JsError, JsValue, prelude::wasm_bindgen};

#[wasm_bindgen(start)]
fn start() {
    console_error_panic_hook::set_once();

    tracing_subscriber::fmt()
        .with_max_level(LevelFilter::DEBUG)
        .with_writer(
            MakeConsoleWriter::default().map_trace_level_to(tracing::Level::DEBUG),
        )
        .without_time()
        .with_ansi(false)
        .init();
}

fn to_js_err(err: impl Into<anyhow::Error>) -> JsError {
    JsError::new(&err.into().to_string())
}

/// State shared between the gossip event loop and the JS-facing channel.
struct Shared {
    handler: Option<js_sys::Function>,
    /// Events received before the JS handler was registered.
    pending: Vec<String>,
}

#[wasm_bindgen]
pub struct BoggleNet {
    gossip: Gossip,
    router: Router,
}

#[wasm_bindgen]
impl BoggleNet {
    /// Create an endpoint plus a gossip node.
    pub async fn new() -> Result<BoggleNet, JsError> {
        let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
            .alpns(vec![GOSSIP_ALPN.to_vec()])
            .bind()
            .await
            .map_err(to_js_err)?;

        let gossip = Gossip::builder().spawn(endpoint.clone());
        let router = Router::builder(endpoint)
            .accept(GOSSIP_ALPN, gossip.clone())
            .spawn();

        Ok(BoggleNet { gossip, router })
    }

    /// This endpoint's node id (used by the room registry).
    pub fn node_id(&self) -> String {
        self.router.endpoint().id().to_string()
    }

    /// Subscribe to the gossip topic for a room, dialing the given peers as
    /// bootstrap entries.
    pub async fn join(
        &self,
        topic_hex: String,
        peers: Vec<String>,
    ) -> Result<BoggleChannel, JsError> {
        let bytes: [u8; 32] = hex::decode(&topic_hex)
            .map_err(|err| anyhow!("bad topic hex: {err}"))
            .and_then(|v| v.try_into().map_err(|_| anyhow!("topic must be exactly 32 bytes")))
            .map_err(to_js_err)?;
        let topic_id: TopicId = bytes.into();

        let bootstrap: Vec<iroh::EndpointId> = peers
            .iter()
            .filter_map(|p| p.parse::<iroh::EndpointId>().ok())
            .collect();

        let gossip_topic = self
            .gossip
            .subscribe(topic_id, bootstrap)
            .await
            .map_err(to_js_err)?;
        let (sender, receiver) = gossip_topic.split();

        let shared = Arc::new(Mutex::new(Shared {
            handler: None,
            pending: Vec::new(),
        }));

        // Forward gossip events to JS as JSON strings.
        {
            let shared = Arc::clone(&shared);
            wasm_bindgen_futures::spawn_local(async move {
                let mut receiver = receiver;
                loop {
                    let event = match receiver.try_next().await {
                        Ok(Some(event)) => event,
                        Ok(None) | Err(_) => break,
                    };
                    let json = match event {
                        GossipEvent::NeighborUp(id) => {
                            format!(r#"{{"kind":"up","node":"{id}"}}"#)
                        }
                        GossipEvent::NeighborDown(id) => {
                            format!(r#"{{"kind":"down","node":"{id}"}}"#)
                        }
                        GossipEvent::Received(msg) => {
                            let text = serde_json::to_string(&String::from_utf8_lossy(&msg.content))
                                .unwrap_or_default();
                            format!(
                                r#"{{"kind":"msg","from":"{}","text":{}}}"#,
                                msg.delivered_from, text
                            )
                        }
                        GossipEvent::Lagged => r#"{"kind":"lagged"}"#.to_string(),
                    };
                    let mut shared = shared.lock().unwrap();
                    match &shared.handler {
                        Some(f) => {
                            let _ = f.call1(&JsValue::NULL, &JsValue::from_str(&json));
                        }
                        None => shared.pending.push(json),
                    }
                }
            });
        }

        Ok(BoggleChannel { sender, shared })
    }
}

#[wasm_bindgen]
pub struct BoggleChannel {
    sender: GossipSender,
    shared: Arc<Mutex<Shared>>,
}

#[wasm_bindgen]
impl BoggleChannel {
    /// Broadcast a UTF-8 message to the room. Gossip does not echo our own
    /// messages back to us.
    pub async fn broadcast(&self, text: String) -> Result<(), JsError> {
        self.sender
            .broadcast(text.into_bytes().into())
            .await
            .map_err(to_js_err)?;
        Ok(())
    }

    /// Register the JS callback that receives gossip events as JSON strings.
    pub fn set_event_handler(&mut self, handler: js_sys::Function) {
        let pending: Vec<String> = {
            let mut shared = self.shared.lock().unwrap();
            shared.handler = Some(handler);
            shared.pending.drain(..).collect()
        };
        let shared = self.shared.lock().unwrap();
        let f = shared.handler.as_ref().unwrap();
        for json in pending {
            let _ = f.call1(&JsValue::NULL, &JsValue::from_str(&json));
        }
    }
}
