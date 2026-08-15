# html-boggle

A realtime multiplayer **Boggle** for the browser — rendered with **raylib** (C → WebAssembly
via emscripten), networked with **iroh gossip** (Rust → WebAssembly), tooled with **mise** and
**Deno**. No server component: two people entering the same room code land on the same gossip
channel with nothing but public pkarr relays in between.

```
+-----------------------------------------------------------------+
| browser A                          browser B                     |
|  raylib game (C wasm)              raylib game (C wasm)          |
|       |  EM_JS                         |  EM_JS                  |
|  glue.js  <---------------------->  glue.js                      |
|       |  wasm-bindgen                 |  wasm-bindgen            |
|  iroh gossip (Rust wasm)   <==gossip==>   iroh gossip (Rust wasm)|
|       | (relayed, end-to-end encrypted via n0 relays)            |
|       +-- pkarr PUT/GET of the room's member list --+            |
|           https://dns.iroh.link/pkarr (public infra)             |
+-----------------------------------------------------------------+
```

## The "automatic rigging"

Two people entering the same room code are connected to the same gossip channel with zero
setup, because everything is derived deterministically from the room code:

1. **Topic**: `topic id = sha256("topic:" + ROOM)` → iroh gossip `TopicId`. Same code, same topic.
2. **Board**: `board = sha256("board:" + ROOM)` → one face per classic Boggle die. Same code,
   same 4×4 board on every screen.
3. **Rendezvous (serverless)**: a second keypair is derived from the room code
   (`sha256("boggle-room:" + ROOM)`). Every player publishes the ids of everyone they know to
   be alive as TXT records in that keypair's pkarr packet on the public pkarr relay
   (`https://dns.iroh.link/pkarr`), and polls the same packet for new ids to dial. Reads come
   before writes so concurrent publishers converge instead of masking each other. No server of
   ours is involved — the pkarr relays are the same public infrastructure iroh itself uses for
   address lookup.

All actual game traffic (presence, word claims, awards, scores, round control) flows over the
gossip channel — encrypted end-to-end, relayed through the public n0 relays because browsers
can't open UDP sockets. The pkarr packet only carries node ids at join time.

Roles: the member with the lexicographically smallest node id is the **host** (deterministic,
so everyone agrees). The host starts rounds, arbitrates word claims, and publishes
authoritative snapshots. All clients run identical rules, so when the host leaves the next
smallest node id seamlessly takes over.

## Quickstart

```sh
mise trust          # first time only (or `mise trust` on first run prompt)
mise install        # deno 2, rust 1.96, emsdk 3.1.71, node 26
mise run setup      # rust wasm target + cached raylib web lib, wasm-bindgen-cli, word list
mise run build      # iroh wasm module + raylib wasm game -> dist/
mise run dev        # build + watch + serve http://localhost:8000
mise run test       # e2e: two headless browsers join one room and play a word
```

Open http://localhost:8000 in two browser tabs (or two machines — the dev server binds
`0.0.0.0`), enter the same room code in both, and play. Browsers need internet access for the
public iroh/pkarr relays. `mise run test` bootstraps playwright-core into `.cache/pw` and needs
a chromium headless shell (`npx playwright install chromium-headless-shell`).

## Publishing (GitHub Pages)

Pushing to `main` builds the game with [mise-action](https://github.com/jdx/mise-action)
(`.github/workflows/ci.yml`) and deploys `dist/` to GitHub Pages. To enable it:

1. Repo settings → Pages → Source: **GitHub Actions** (one-time).
2. Push to `main`.

The site works from any base path (project pages like `user.github.io/html-boggle/` are fine —
all asset URLs are relative) and is fully multiplayer: the game has no server component, so
static hosting loses nothing. There is also a manually-triggered
[`e2e.yml`](.github/workflows/e2e.yml) that runs the full two-browser test in CI.

## Layout

| Path              | What                                                        |
| ----------------- | ----------------------------------------------------------- |
| `mise.toml`       | pinned tools + `setup` / `build` / `dev` / `serve` / `test` tasks |
| `client/main.c`   | the raylib game: lobby, board, input, scoring, host logic   |
| `client/shell.html`| emscripten shell (letterboxed canvas)                       |
| `client/jsmn.h`   | vendored [jsmn](https://github.com/zserge/jsmn) JSON parser (MIT) |
| `net/`            | Rust crate: iroh 1.0 + iroh-gossip 0.101 → wasm-bindgen, pkarr rendezvous |
| `glue/glue.js`    | bridge: room→topic/board/key derivations, pkarr discovery, C↔wasm events |
| `glue/sha256.js`  | vendored [js-sha256](https://github.com/emn178/js-sha256) (MIT) |
| `server/main.ts`  | Deno static file server for `dist/` (dev convenience only)  |
| `scripts/`        | `setup.ts`, `build.ts`, `dev.ts` (pure Deno), `e2e-web.mjs` (playwright) |

## Gossip message protocol

Messages are JSON strings broadcast on the room's gossip topic. Every message carries a
monotonic sequence number — iroh-gossip's PlumTree dedupes by content hash, so identical
repeats (periodic hellos, claim retries) would otherwise be dropped.

| Message | Who | Purpose |
| ------- | --- | ------- |
| `hello` | everyone, every 5 s | presence, name exchange |
| `bye`   | everyone, on leave | farewell (also gossip `NeighborDown`) |
| `start` | host | round start with `deadline` (unix ms) |
| `claim` | players | propose a word |
| `award` | host | word accepted: `word`, `points` |
| `reject`| host | word denied: `reason` = `taken` / `invalid` |
| `state` | host | authoritative snapshot (members, scores, words, phase, deadline) — sent when membership changes, every 10 s during play, and at round end |

Scoring is classic Boggle: 3–4 letters = 1, 5 = 2, 6 = 3, 7 = 5, 8+ = 11. Rounds are 3
minutes; scores accumulate, found words reset each round. Word validation uses a public-domain
word list (dwyl/english-words, filtered to 3–16 letters, sorted and compiled into the wasm).

## Notes & limitations

- Browser iroh is **relay-only** (no direct hole-punching). Traffic is end-to-end encrypted
  but transits the public n0 relay servers. Everyone pins the same relay so runtime
  home-relay changes can't silently drop live connections.
- The room's pkarr packet is signed with a key anyone who knows the room code can derive —
  same trust model as the room code itself. Anyone who knows a code can join that room.
- Word submissions are optimistic on non-host clients and host-arbitrated; claims are retried
  until acknowledged and host snapshots self-heal state after connection drops.
- The dictionary is client-side; there is no anti-cheat. This is a party game.
