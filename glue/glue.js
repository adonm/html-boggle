/**
 * glue.js - bridges the raylib game (C/wasm) with iroh gossip (Rust/wasm).
 * No server component: peer discovery uses the public pkarr relays that iroh
 * itself uses for address lookup.
 *
 * Deterministic derivations, so that anyone entering the same room code ends up
 * on the same gossip channel with the same board and the same rendezvous key:
 *   topic id  = sha256("topic:" + room)   (32 bytes -> iroh gossip TopicId)
 *   board     = sha256("board:" + room)   (16 bytes -> one face per Boggle die)
 *   room key  = keypair(sha256("boggle-room:" + room))  (pkarr rendezvous key)
 *
 * Discovery protocol (serverless):
 *   1. Every player derives the room keypair from the room code.
 *   2. Everyone periodically PUTs the room's pkarr packet (TXT records holding
 *      the hex node ids of everyone they know to be alive), signed with the
 *      room key, to https://dns.iroh.link/pkarr/<z32(room key)>.
 *   3. Everyone periodically GETs the same packet and dials (over the gossip
 *      ALPN) every id they haven't connected to yet.
 *   The member set is a grow-only merge that converges: whoever enters the
 *   room ends up in the same gossip swarm.
 *
 * C side (client/main.c) calls:
 *   window.__boggleGlue.join(room, name)
 *   window.__boggleGlue.send(json)
 *   window.__boggleGlue.now()
 * and receives events through Module.ccall("boggle_on_event", ...).
 */

import init, { BoggleNet } from "./net/boggle_net.js";

const PKARR_RELAY = "https://dns.iroh.link/pkarr/";
const SYNC_INTERVAL_MS = 5_000;

// Classic 4x4 Boggle dice set (one die carries "Qu").
const DICE = [
  "AAEEGN",
  "ABBJOO",
  "ACHOPS",
  "AFFKPS",
  "AOOTTW",
  "CIMOTU",
  "DEILRX",
  "DELRVY",
  "DISTTY",
  "EEGHNW",
  "EEINSU",
  "EHRTVW",
  "EIOSST",
  "ELRTTY",
  "HIMNQU",
  "HLNNRZ",
];

const sha256 = globalThis.sha256; // vendored js-sha256 (MIT), loaded before this module

function normRoom(room) {
  return String(room).toLowerCase().replace(/[^a-z0-9]/g, "");
}

function topicFor(room) {
  return sha256("topic:" + room); // hex, 64 chars = 32 bytes
}

function boardFor(room) {
  const bytes = sha256.array("board:" + room);
  return DICE.map((die, i) => die[bytes[i] % 6].toLowerCase()).join(",");
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

function callC(fn, arg) {
  const M = window.Module;
  // Never call ccall before the module finished initializing: emscripten's
  // lazy export wrappers cache the result of the first call.
  if (M && M.calledRun && M.ccall) {
    try {
      M.ccall(fn, "number", ["string"], [arg]);
    } catch (err) {
      console.error("ccall failed", fn, err);
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

  async join(roomRaw, name) {
    const room = normRoom(roomRaw);
    if (!room) {
      this.fail("Room code must be letters and numbers");
      return;
    }
    try {
      // Board is deterministic per room: set it before anything else.
      callC("boggle_set_board", boardFor(room));

      await init();
      console.log("[boggle] net wasm initialized");
      if (!this.net) this.net = await BoggleNet.new();
      console.log("[boggle] endpoint bound", this.net.node_id());
      const nodeId = this.net.node_id();

      this.room = room;
      this.nodeId = nodeId;
      this.liveIds = new Set([nodeId]);
      this.dialedIds = new Set();

      // First pkarr round: publish ourselves and fetch existing members so
      // they can be used as bootstrap peers for the gossip subscription.
      const known = await this.syncPkarr(room, nodeId, true);

      this.channel = await this.net.join(
        topicFor(room),
        [...known].filter((id) => id !== nodeId),
      );
      console.log("[boggle] gossip topic joined");
      this.channel.set_event_handler((evt) => this.handle(evt));

      clearInterval(this.syncTimer);
      this.syncTimer = setInterval(() => this.discover(room, nodeId), SYNC_INTERVAL_MS);

      console.log(`[boggle] joined room "${room}" as ${nodeId}`);
      callC("boggle_on_event", JSON.stringify({ kind: "joined", room, node: nodeId }));
    } catch (err) {
      console.error("[boggle] join failed", err);
      this.fail("Join failed: " + (err?.message ?? err));
    }
  },

  fail(reason) {
    callC("boggle_on_event", JSON.stringify({ kind: "joinFail", reason: String(reason) }));
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
        const ids = this.net.unpack_room(
          room,
          bytesToHex(new Uint8Array(await res.arrayBuffer())),
        );
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
        callC("boggle_on_event", JSON.stringify(data));
      } catch {
        /* ignore malformed payloads */
      }
    } else if (evt.kind === "up") {
      this.stats.up++;
      this.liveIds.add(evt.node);
      callC("boggle_on_event", evtJson);
    } else if (evt.kind === "down") {
      this.stats.down++;
      this.liveIds.delete(evt.node);
      this.dialedIds.delete(evt.node); // allow re-dialing
      callC("boggle_on_event", evtJson);
      // Connection lost: kick a discovery round right away so the overlay
      // re-forms as fast as possible.
      if (this.room && this.net) this.discover(this.room, this.nodeId).catch(() => {});
    } else {
      callC("boggle_on_event", evtJson);
    }
  },

  send(json) {
    this.stats.sent++;
    this.channel?.broadcast(json).catch((err) => console.warn("[boggle] send failed", err));
  },

  now() {
    return Date.now();
  },
};

window.__boggleGlue = glue;

window.addEventListener("beforeunload", () => {
  if (glue.channel) {
    glue
      .channel
      .broadcast(JSON.stringify({ t: "bye", node: glue.nodeId }))
      .catch(() => {});
  }
});
