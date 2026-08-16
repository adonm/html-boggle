//! iroh gossip networking for html-boggle, compiled to WebAssembly for the browser.
//!
//! The JS glue turns a room code into a 32-byte gossip topic id (sha256). Everyone
//! who enters the same room code therefore joins the same gossip channel.
//!
//! Peer discovery needs no server: a second keypair is derived from the room
//! code, and every player publishes the room's member list (their node ids) as
//! TXT records in that keypair's pkarr packet on the public pkarr relay
//! (https://dns.iroh.link). Players poll the same packet and dial every id
//! they find, so everyone entering a room converges on one gossip swarm.

use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Result};
use iroh::protocol::Router;
use iroh_dns::pkarr::SignedPacket;
use iroh_gossip::{
    api::{Event as GossipEvent, GossipSender},
    net::{GOSSIP_ALPN, Gossip},
    proto::TopicId,
};
use n0_future::StreamExt;
use sha2::{Digest, Sha256};
use tracing::level_filters::LevelFilter;
use tracing_subscriber_wasm::MakeConsoleWriter;
use wasm_bindgen::{JsError, JsValue, prelude::wasm_bindgen};

/// pkarr relay used as the serverless room rendezvous.
pub const PKARR_RELAY_URL: &str = "https://dns.iroh.link/pkarr/";

/// TTL (seconds) of the room packet; everyone re-publishes periodically.
const ROOM_TTL: u32 = 600;

/// A TXT record holds hex-encoded node ids, chunked at 192 chars (3 ids) so a
/// record stays well under the 255-byte TXT string limit.
const CHUNK_HEX: usize = 192;

/// Room member list limit: must fit the 1000-byte pkarr DNS packet.
const MAX_ROOM_MEMBERS: usize = 16;

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

/// Deterministic keypair for a room: everyone who knows the room code can
/// derive it, so anyone can sign/read the room's pkarr packet.
fn room_secret(room: &str) -> iroh::SecretKey {
    let mut hasher = Sha256::new();
    hasher.update(b"boggle-room:");
    hasher.update(room.as_bytes());
    let bytes: [u8; 32] = hasher.finalize().into();
    iroh::SecretKey::from_bytes(&bytes)
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
    ///
    /// `relay_url` pins the home relay for this session (glue.js picks the
    /// fastest N0 public relay at startup). We deliberately avoid the N0
    /// default relay map: the periodic net_report would switch "home" relays
    /// at runtime, which drops all connections relayed through the old relay.
    pub async fn new(relay_url: String) -> Result<BoggleNet, JsError> {
        let relay: iroh::RelayUrl = if relay_url.trim().is_empty() {
            "https://use1-1.relay.n0.iroh.link."
                .parse()
                .map_err(to_js_err)?
        } else {
            let url = relay_url.trim();
            let url = if url.contains("://") {
                url.to_string()
            } else {
                format!("https://{url}")
            };
            url.parse().map_err(to_js_err)?
        };
        let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
            .relay_mode(iroh::RelayMode::custom([relay]))
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

    /// This endpoint's node id.
    pub fn node_id(&self) -> String {
        self.router.endpoint().id().to_string()
    }

    /// The z32 public key under which the room's pkarr packet is stored.
    pub fn room_pubkey_z32(&self, room: String) -> String {
        room_secret(&room).public().to_z32()
    }

    /// Build the signed pkarr packet (hex-encoded relay payload) carrying the
    /// merged member list for a room.
    pub fn pack_room(&self, room: String, node_ids: Vec<String>) -> Result<String, JsError> {
        let key = room_secret(&room);

        // keep only valid node ids (z32 strings), deduplicated and sorted for
        // determinism
        let mut keys: Vec<iroh::PublicKey> = Vec::new();
        for id in node_ids {
            let Ok(pk) = id.parse::<iroh::PublicKey>() else { continue };
            if !keys.contains(&pk) {
                keys.push(pk);
            }
        }
        keys.sort();
        keys.truncate(MAX_ROOM_MEMBERS);

        let merged: String = keys.iter().map(|pk| hex::encode(pk.as_bytes())).collect();

        // chunk the hex string into TXT records (id-aligned: chunk is a
        // multiple of 64 hex chars)
        let mut values: Vec<String> = Vec::new();
        let mut rest = merged.as_str();
        while !rest.is_empty() {
            let take = rest.len().min(CHUNK_HEX);
            values.push(rest[..take].to_string());
            rest = &rest[take..];
        }

        let packet =
            SignedPacket::from_txt_strings(&key, "@", values, ROOM_TTL).map_err(to_js_err)?;
        Ok(hex::encode(packet.to_relay_payload()))
    }

    /// Parse a pkarr relay payload (hex) for a room and return the member node
    /// ids (z32 strings) found in it.
    pub fn unpack_room(&self, room: String, body_hex: String) -> Vec<String> {
        let Ok(bytes) = hex::decode(body_hex.trim()) else {
            return Vec::new();
        };
        let key = room_secret(&room);
        let Ok(packet) = SignedPacket::from_relay_payload(&key.public(), &bytes) else {
            return Vec::new();
        };
        let merged: String = packet.txt_records("@").join("");
        let mut ids = Vec::new();
        for chunk in merged.as_bytes().chunks(64) {
            let Ok(chunk) = std::str::from_utf8(chunk) else { continue };
            let Ok(bytes) = hex::decode(chunk) else { continue };
            let bytes: [u8; 32] = match bytes.try_into() {
                Ok(b) => b,
                Err(_) => continue,
            };
            let Ok(pk) = iroh::PublicKey::from_bytes(&bytes) else { continue };
            ids.push(pk.to_string());
        }
        ids
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

    /// Ask gossip to connect to peers discovered through the room's pkarr
    /// packet after the initial subscription.
    pub async fn join_peers(&self, peers: Vec<String>) -> Result<(), JsError> {
        let ids: Vec<iroh::EndpointId> = peers
            .iter()
            .filter_map(|p| p.parse::<iroh::EndpointId>().ok())
            .collect();
        if ids.is_empty() {
            return Ok(());
        }
        self.sender.join_peers(ids).await.map_err(to_js_err)?;
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
