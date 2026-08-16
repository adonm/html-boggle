/**
 * glue.js - bridges the Flutter app with iroh gossip (Rust/wasm).
 * No server component: peer discovery uses the public pkarr relays that iroh
 * itself uses for address lookup.
 *
 * The Flutter app (Dart) drives this bridge through:
 *   window.__boggleGlue.join(room, topicHex, name) -> Promise<nodeId>
 *   window.__boggleGlue.send(json)
 * and receives events through window.__boggleToFlutter(json), a sink that the
 * Dart side installs via dart:js_interop.
 *
 * Discovery protocol (serverless):
 *   1. The Dart side derives the room keypair source from the room code
 *      (sha256), and the gossip topic id the same way.
 *   2. Everyone periodically PUTs the room's pkarr packet (TXT records holding
 *      the hex node ids of everyone they know to be alive), signed with the
 *      room key, to https://dns.iroh.link/pkarr/<z32(room key)>.
 *   3. Everyone periodically GETs the same packet and asks gossip to connect
 *      to any new ids.
 *   The member set is a grow-only merge that converges: whoever enters the
 *   room ends up in the same gossip swarm.
 */

import init, { BoggleNet } from "./net/boggle_net.js";

const PKARR_RELAY = "https://dns.iroh.link/pkarr/";
const SYNC_INTERVAL_MS = 5_000;

/** N0 public relays; we pin the fastest one for the whole session. */
const N0_RELAYS = [
  "use1-1.relay.n0.iroh.link.",
  "usw1-1.relay.n0.iroh.link.",
  "euc1-1.relay.n0.iroh.link.",
  "aps1-1.relay.n0.iroh.link.",
];

/**
 * Persisted identity: the same 32-byte secret key on every visit, so
 * reconnecting to a room restores your node id and the room recognizes you.
 * Stored per-tab (sessionStorage): it survives reloads within the tab but
 * lets other tabs in the same browser be different players.
 */
function loadSecret() {
  const key = "boggle.secretKey";
  try {
    const existing = sessionStorage.getItem(key);
    if (existing && existing.length === 64) return existing;
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
    sessionStorage.setItem(key, hex);
    return hex;
  } catch {
    return "";
  }
}
const DEFAULT_RELAY = N0_RELAYS[0];

/**
 * Pick the N0 relay with the lowest measured latency. A fetch to the relay
 * root returns 404 quickly, but the round trip (TCP+TLS) is what matters, and
 * that dominates the timing. Failures (offline relay, CORS rejections) just
 * lose the race. Cached per tab session.
 */
async function pickRelay() {
  try {
    const cached = sessionStorage.getItem("boggle.relay");
    if (cached) return cached;
  } catch {
    /* sessionStorage unavailable */
  }
  const probe = async (url) => {
    const t0 = performance.now();
    try {
      await fetch(`https://${url}`, {
        mode: "no-cors",
        cache: "no-store",
        signal: AbortSignal.timeout(6_000),
      });
    } catch {
      /* unreachable or CORS rejection; timing still counts */
    }
    return { url, ms: performance.now() - t0 };
  };
  const results = await Promise.all(N0_RELAYS.map(probe));
  const best = results.sort((a, b) => a.ms - b.ms)[0]?.url ?? DEFAULT_RELAY;
  try {
    sessionStorage.setItem("boggle.relay", best);
  } catch {
    /* ignore */
  }
  console.log("[boggle] relay probe:", results, "->", best);
  return best;
}

function bytesToHex(bytes) {
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}

function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

function emit(obj) {
  const f = window.__boggleToFlutter;
  if (typeof f === "function") {
    try {
      f(JSON.stringify(obj));
    } catch (err) {
      console.error("[boggle] flutter sink failed", err);
    }
  }
}

const glue = {
  net: null,
  channel: null,
  room: "",
  nodeId: "",
  syncTimer: 0,
  liveIds: new Set(), // node ids we believe are currently in the room
  dialedIds: new Set(), // ids we dialed successfully (or are connected to)
  lastPut: 0, // last pkarr PUT (ms)
  stats: { sent: 0, recv: 0, up: 0, down: 0, byType: {} }, // debug counters

  /** Called by the Flutter app. Resolves with our node id. */
  async join(room, topicHex, name) {
    await init();
    if (!this.net) this.net = await BoggleNet.new_with_secret(loadSecret(), await pickRelay());
    console.log("[boggle] endpoint bound", this.net.node_id());
    const nodeId = this.net.node_id();

    this.room = room;
    this.nodeId = nodeId;
    this.liveIds = new Set([nodeId]);
    this.dialedIds = new Set();

    // First pkarr round: publish ourselves and fetch existing members so
    // they can be used as bootstrap peers for the gossip subscription.
    const known = await this.syncPkarr(room, nodeId, true);

    this.channel = await this.net.join(topicHex, [...known].filter((id) => id !== nodeId));
    console.log("[boggle] gossip topic joined");
    this.channel.set_event_handler((evt) => this.handle(evt));

    clearInterval(this.syncTimer);
    this.syncTimer = setInterval(() => this.discover(room, nodeId), SYNC_INTERVAL_MS);

    console.log(`[boggle] joined room "${room}" as ${nodeId}`);
    return nodeId;
  },

  /** Called by the Flutter app: broadcast a JSON app message. */
  send(json) {
    this.stats.sent++;
    this.channel?.broadcast(json).catch((err) => console.warn("[boggle] send failed", err));
  },

  /**
   * One discovery round: PUT the merged member list we know to be alive, GET
   * the current packet, and ask gossip to connect to any new ids.
   */
  async discover(room, nodeId) {
    const seen = await this.syncPkarr(room, nodeId, false);
    if (!this.channel) return;
    for (const id of seen) {
      if (id === nodeId || this.dialedIds.has(id)) continue;
      this.dialedIds.add(id); // optimistically; removed on failure below
      try {
        await this.channel.join_peers([id]);
        console.log("[boggle] joining peer", id.slice(0, 12));
      } catch {
        this.dialedIds.delete(id); // retry next cycle (address not published yet?)
      }
    }
  },

  /**
   * One pkarr read/write round. Order matters: GET FIRST, then PUT. If we
   * PUT before GET, our own fresh write masks the others' (both clients then
   * read only their own packet forever). With GET first, the latest write is
   * usually the other player's, and the merged union converges.
   * Returns the set of ids seen in the room packet.
   */
  async syncPkarr(room, nodeId, forcePut) {
    const z32 = this.net.room_pubkey_z32(room);
    const url = PKARR_RELAY + z32;
    const seen = new Set();

    // GET the current packet.
    try {
      const res = await fetch(url);
      if (res.ok) {
        const ids = this.net.unpack_room(room, bytesToHex(new Uint8Array(await res.arrayBuffer())));
        for (const id of ids) {
          seen.add(id);
          if (id !== nodeId) this.liveIds.add(id);
        }
      }
      // 404 = nobody published yet
    } catch (err) {
      console.warn("[boggle] pkarr GET unreachable:", err.message);
    }

    // PUT our merged view of the live member set. Throttled: only on changes
    // or when the last PUT is stale, with jitter so simultaneous joiners don't
    // stay in lock-step.
    const stale = Date.now() - this.lastPut > 5_000 + Math.random() * 3_000;
    if (forcePut || (stale && seen.size !== this.liveIds.size)) {
      try {
        const body = this.net.pack_room(room, [...this.liveIds]);
        const res = await fetch(url, { method: "PUT", body: hexToBytes(body) });
        if (!res.ok) console.warn("[boggle] pkarr PUT failed:", res.status);
        this.lastPut = Date.now();
      } catch (err) {
        console.warn("[boggle] pkarr PUT unreachable:", err.message);
      }
    }
    return seen;
  },

  handle(evtJson) {
    let evt;
    try {
      evt = JSON.parse(evtJson);
    } catch {
      return;
    }
    this.stats.recv++;
    if (evt.kind === "msg") {
      // App messages are JSON sent by peers; tag them with the sender node id.
      try {
        const data = JSON.parse(evt.text);
        this.stats.byType[data.t] = (this.stats.byType[data.t] ?? 0) + 1;
        if (!data.node) data.node = evt.from;
        if (data.t === "hello" || data.t === "claim" || data.t === "award") {
          this.liveIds.add(data.node);
        } else if (data.t === "bye") {
          this.liveIds.delete(data.node);
        }
        emit(data);
      } catch {
        /* ignore malformed payloads */
      }
    } else if (evt.kind === "up") {
      this.stats.up++;
      this.liveIds.add(evt.node);
      emit(evt);
    } else if (evt.kind === "down") {
      this.stats.down++;
      this.liveIds.delete(evt.node);
      this.dialedIds.delete(evt.node); // allow re-dialing
      emit(evt);
      // Connection lost: kick a discovery round right away so the overlay
      // re-forms as fast as possible.
      if (this.room && this.net) this.discover(this.room, this.nodeId).catch(() => {});
    } else {
      emit(evt);
    }
  },
};

window.__boggleGlue = glue;
/** Debug: JSON stats of everything received by type. */
window.__boggleGlueStats = () => JSON.stringify(glue.stats);

window.addEventListener("beforeunload", () => {
  if (glue.channel) {
    glue
      .channel
      .broadcast(JSON.stringify({ t: "bye", node: glue.nodeId }))
      .catch(() => {});
  }
});
