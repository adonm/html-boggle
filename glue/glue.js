/**
 * glue.js - bridges the raylib game (C/wasm) with iroh gossip (Rust/wasm) and
 * the room registry (HTTP).
 *
 * Deterministic derivations, so that anyone entering the same room code ends up
 * on the same gossip channel with the same board:
 *   topic id  = sha256("topic:" + room)   (32 bytes -> iroh gossip TopicId)
 *   board     = sha256("board:" + room)   (16 bytes -> one face per Boggle die)
 *
 * C side (client/main.c) calls:
 *   window.__boggleGlue.join(room, name)
 *   window.__boggleGlue.send(json)
 *   window.__boggleGlue.now()
 * and receives events through Module.ccall("boggle_on_event", ...).
 */

import init, { BoggleNet } from "./net/boggle_net.js";

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
  pingTimer: 0,

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

      const res = await fetch("/api/join", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ room, nodeId, name: String(name).slice(0, 40) }),
      });
      if (!res.ok) throw new Error("registry error " + res.status);
      const data = await res.json();
      const members = Array.isArray(data.members) ? data.members : [];
      console.log("[boggle] registry: room", room, "members", members.length);

      this.channel = await this.net.join(
        topicFor(room),
        members.map((m) => m.nodeId).filter((id) => id !== nodeId),
      );
      console.log("[boggle] gossip topic joined");
      this.channel.set_event_handler((evt) => this.handle(evt));

      this.room = room;
      this.nodeId = nodeId;
      clearInterval(this.pingTimer);
      this.pingTimer = setInterval(() => this.ping(), 10_000);

      console.log(`[boggle] joined room "${room}" as ${nodeId}, peers: ${members.length}`);
      callC("boggle_on_event", JSON.stringify({ kind: "joined", room, node: nodeId }));
    } catch (err) {
      console.error("[boggle] join failed", err);
      this.fail("Join failed: " + (err?.message ?? err));
    }
  },

  fail(reason) {
    callC("boggle_on_event", JSON.stringify({ kind: "joinFail", reason: String(reason) }));
  },

  handle(evtJson) {
    let evt;
    try {
      evt = JSON.parse(evtJson);
    } catch {
      return;
    }
    if (evt.kind === "msg") {
      // App messages are JSON sent by peers; tag them with the sender node id.
      try {
        const data = JSON.parse(evt.text);
        if (!data.node) data.node = evt.from;
        callC("boggle_on_event", JSON.stringify(data));
      } catch {
        /* ignore malformed payloads */
      }
    } else {
      callC("boggle_on_event", evtJson);
    }
  },

  send(json) {
    this.channel?.broadcast(json).catch((err) => console.warn("[boggle] send failed", err));
  },

  now() {
    return Date.now();
  },

  ping() {
    if (!this.room || !this.nodeId) return;
    fetch("/api/ping", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ room: this.room, nodeId: this.nodeId }),
    }).catch(() => {});
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
