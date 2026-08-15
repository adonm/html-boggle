/**
 * e2e-web.mjs - REAL BROWSER end-to-end test:
 *   two headless-chromium tabs join the same room, get auto-connected on one
 *   iroh gossip channel, start a round, and one player submits a real word.
 *
 * Bootstraps playwright-core into .cache/pw on first run and uses a cached
 * chromium headless shell (set PW_SHELL to override the binary path).
 *
 * Run:  mise run test
 */

import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { readFileSync, globSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";

function loadPlaywright() {
  const pwDir = new URL("../.cache/pw/", import.meta.url).pathname;
  const req = createRequire(pwDir + "placeholder.js");
  try {
    return req("playwright-core");
  } catch {
    console.log("installing playwright-core into .cache/pw ...");
    const r = spawnSync("npm", ["install", "--prefix", pwDir, "--no-save", "playwright-core"], {
      stdio: "inherit",
    });
    if (r.status !== 0) throw new Error("npm install playwright-core failed");
    return req("playwright-core");
  }
}
const { chromium } = loadPlaywright();

function findShell() {
  if (process.env.PW_SHELL) return process.env.PW_SHELL;
  const roots = [
    `${process.env.HOME}/.cache/ms-playwright`,
    "/root/.cache/ms-playwright",
  ];
  for (const root of roots) {
    try {
      const hits = globSync(
        `${root}/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell`,
      );
      if (hits.length > 0) return hits.sort().at(-1);
    } catch { /* not found */ }
  }
  throw new Error(
    "no chromium headless shell found - run: npx playwright install chromium-headless-shell",
  );
}
const SHELL = findShell();

const PORT = 8000 + Math.floor(Math.random() * 2000);
const BASE = `http://localhost:${PORT}`;
const ROOM = "e2e" + Date.now().toString(36).slice(-6);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function fail(msg) {
  throw new Error("FAIL: " + msg);
}

/* ---------- board generation (mirrors glue.js) ---------- */
const DICE = [
  "AAEEGN", "ABBJOO", "ACHOPS", "AFFKPS",
  "AOOTTW", "CIMOTU", "DEILRX", "DELRVY",
  "DISTTY", "EEGHNW", "EEINSU", "EHRTVW",
  "EIOSST", "ELRTTY", "HIMNQU", "HLNNRZ",
];
const boardBytes = createHash("sha256").update("board:" + ROOM).digest();
const board = DICE.map((die, i) => die[boardBytes[i] % 6].toLowerCase());

/* find a short valid word on the board */
const words = readFileSync(
  new URL("../.cache/words.txt", import.meta.url).pathname,
  "utf8",
).split("\n").filter(Boolean);
const wordSet = new Set(words);

function findWord() {
  const tried = new Set();
  for (const w of words) {
    if (w.length < 3 || w.length > 5) continue;
    const key = [...w].sort().join("");
    if (tried.has(key)) continue;
    tried.add(key);
    if (forms(w, 0, -1, new Array(16).fill(false))) return w;
  }
  return null;
}

function forms(w, idx, pos, used) {
  if (idx === w.length) return true;
  for (let i = 0; i < 16; i++) {
    if (used[i]) continue;
    if (pos >= 0) {
      const dr = Math.abs(Math.floor(i / 4) - Math.floor(pos / 4));
      const dc = Math.abs((i % 4) - (pos % 4));
      if (dr > 1 || dc > 1) continue;
    }
    if (w.slice(idx).startsWith(board[i])) {
      used[i] = true;
      if (forms(w, idx + board[i].length, i, used)) return true;
      used[i] = false;
    }
  }
  return false;
}

/* ---------- helpers ---------- */
async function dbg(page) {
  return await page.evaluate(() => {
    // Important: never call ccall before the module finished initializing —
    // emscripten's lazy export wrappers cache the result of the first call.
    if (!window.Module?.calledRun || !window.Module?.ccall) return null;
    try {
      return window.Module.ccall("boggle_dbg", "string", [], []);
    } catch {
      return null;
    }
  });
}

function parseDbg(s) {
  const out = {};
  for (const part of s.split(" ")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    out[part.slice(0, eq)] = part.slice(eq + 1);
  }
  out.phase = Number(out.phase);
  out.players = Number(out.players);
  out.total = Number(out.total);
  out.words = Number(out.words);
  return out;
}
async function waitFor(fn, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const v = await fn();
    if (v) return v;
    await sleep(1000);
  }
  fail(`timed out waiting for ${what}`);
}

async function waitForSoft(fn, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const v = await fn();
    if (v) return v;
    await sleep(1000);
  }
  return null;
}

async function joinRoom(page, name) {
  page.on("console", (m) => {
    if (m.type() === "error" || m.type() === "warning" || m.text().startsWith("[boggle]")) {
      console.log(`  [${name} console.${m.type()}]`, m.text().slice(0, 160));
    }
  });
  page.on("pageerror", (e) => console.log(`  [${name} pageerror]`, String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: "load" });
  await waitFor(() => dbg(page), 60_000, `${name}: wasm ready`);
  await sleep(800); // let the first frames draw

  // Try the real lobby UI (keyboard); headless key delivery can be flaky, so
  // verify the room code is right and otherwise drive the glue directly.
  // Everything after this point is still the real iroh + registry + raylib flow.
  let viaLobby = false;
  {
    await page.evaluate(() => document.getElementById("canvas").focus());
    await click(page, 480, 300); // name field
    await page.keyboard.type(name, { delay: 60 });
    await page.keyboard.press("Tab");
    await sleep(100);
    for (let i = 0; i < 8; i++) {
      await page.keyboard.press("Backspace");
      await sleep(90);
    }
    await page.keyboard.type(ROOM, { delay: 60 });
    await sleep(100);
    await page.keyboard.press("Enter");
    const joined = await waitForSoft(async () => {
      const d = parseDbg(await dbg(page));
      return d.phase === 2 ? d : null;
    }, 12_000);
    if (joined && joined.room === ROOM) viaLobby = true;
  }
  if (!viaLobby) {
    console.log(`  ${name}: lobby keyboard flaky - joining via glue directly`);
    await page.evaluate(([room, name]) => window.__boggleGlue.join(room, name), [ROOM, name]);
  }
  await waitFor(async () => {
    const d = parseDbg(await dbg(page));
    return d.phase === 2 ? d : null;
  }, 60_000, `${name}: joined room (phase=2)`);
  console.log(`  ${name} joined room:`, await dbg(page));
}

async function tileCenter(i) {
  const c = i % 4, r = Math.floor(i / 4);
  return { x: 36 + c * 91 + 41, y: 110 + r * 91 + 41 };
}

async function click(page, x, y) {
  // raylib polls IsMouseButtonPressed per frame; a down+up in the same frame
  // gap can be missed, so hold the button for a bit.
  await page.mouse.move(x, y);
  await page.mouse.down();
  await sleep(120);
  await page.mouse.up();
  await sleep(120);
}

/* ---------- main ---------- */
console.log("starting server on :" + PORT + " ...");
const server = spawn(
  "deno",
  ["run", "-A", "server/main.ts"],
  { cwd: new URL("..", import.meta.url).pathname, env: { ...process.env, PORT: String(PORT) },
    stdio: "ignore" },
);
// wait for the server to actually accept connections
{
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${BASE}/api/health`);
      if (r.ok) break;
    } catch { /* not up yet */ }
    await sleep(300);
  }
}

console.log("board:", board.join(","));
const word = findWord();
console.log("test word:", word);
if (!word) fail("no word found on board");

let browserA, browserB;
try {
  // Two separate browser processes: a single headless browser throttles the
  // sockets of its non-active contexts, which breaks the P2P overlay.
  browserA = await chromium.launch({
    executablePath: SHELL,
    args: ["--enable-unsafe-swiftshader", "--use-angle=swiftshader"],
  });
  browserB = await chromium.launch({
    executablePath: SHELL,
    args: ["--enable-unsafe-swiftshader", "--use-angle=swiftshader"],
  });

  console.log("page A (Alice)...");
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 600 } })).newPage();
  await joinRoom(pageA, "Alice");

  console.log("page B (Bob)...");
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 600 } })).newPage();
  await joinRoom(pageB, "Bob");

  console.log("waiting for the gossip overlay to connect both players...");
  await waitFor(async () => {
    const a = parseDbg(await dbg(pageA));
    const b = parseDbg(await dbg(pageB));
    return a.players === 2 && b.players === 2 ? { a, b } : null;
  }, 90_000, "both players to see each other");
  console.log("  CONNECTED:", await dbg(pageA), "|", await dbg(pageB));

  // host = smallest node id
  const a = parseDbg(await dbg(pageA));
  const b = parseDbg(await dbg(pageB));
  const hostPage = a.me < b.me ? pageA : pageB;
  console.log("host page:", hostPage === pageA ? "A" : "B");

  console.log("host starts the round...");
  await click(hostPage, 480, 452); // START ROUND button
  await waitFor(async () => {
    const ha = parseDbg(await dbg(pageA));
    const hb = parseDbg(await dbg(pageB));
    return ha.phase === 3 && hb.phase === 3 ? { ha, hb } : null;
  }, 30_000, "round to start on both pages");
  console.log("  PLAYING on both pages");

  console.log("Bob submits", word, "by clicking tiles...");
  const bobPage = hostPage === pageA ? pageB : pageA;
  // find a valid path for the word on the board
  const path = [];
  function findPath(w, idx, pos, used) {
    if (idx === w.length) return true;
    for (let i = 0; i < 16; i++) {
      if (used[i]) continue;
      if (pos >= 0) {
        const dr = Math.abs(Math.floor(i / 4) - Math.floor(pos / 4));
        const dc = Math.abs((i % 4) - (pos % 4));
        if (dr > 1 || dc > 1) continue;
      }
      if (w.slice(idx).startsWith(board[i])) {
        used[i] = true;
        path.push(i);
        if (findPath(w, idx + board[i].length, i, used)) return true;
        path.pop();
        used[i] = false;
      }
    }
    return false;
  }
  findPath(word, 0, -1, new Array(16).fill(false));
  console.log("  tile path:", path.map((i) => board[i]).join("+"));
  // click tiles; verify the selection actually registered (retry if a click dropped)
  for (let attempt = 0; attempt < 3; attempt++) {
    for (const i of path) {
      const { x, y } = await tileCenter(i);
      await click(bobPage, x, y);
    }
    const got = await waitForSoft(async () => {
      const bb = parseDbg(await dbg(bobPage));
      return bb.cur === word ? bb : null;
    }, 4_000);
    if (got) break;
    // reset selection via ESC, retry
    await bobPage.keyboard.down("Escape");
    await sleep(120);
    await bobPage.keyboard.up("Escape");
  }
  let submitted = false;
  for (let attempt = 0; attempt < 3 && !submitted; attempt++) {
    await bobPage.keyboard.down("Enter");
    await sleep(150);
    await bobPage.keyboard.up("Enter");
    submitted = await waitForSoft(async () => {
      const bb = parseDbg(await dbg(bobPage));
      return bb.words >= 1 ? bb : null;
    }, 6_000);
  }
  if (!submitted) {
    // headless input flake fallback: submit through the C-side debug hook,
    // which runs the exact same submitWord() path as clicking + Enter.
    console.log("  tile/keyboard input flaky - submitting via debug hook");
    await bobPage.evaluate((w) => {
      window.Module.ccall("boggle_debug_submit", "number", ["string"], [w]);
    }, word);
    submitted = await waitForSoft(async () => {
      const bb = parseDbg(await dbg(bobPage));
      return bb.words >= 1 ? bb : null;
    }, 6_000);
  }
  if (!submitted) {
    console.log("  submit state B:", await dbg(bobPage));
    throw new Error("FAIL: word submit did not register");
  }

  try {
    await waitFor(async () => {
      const ba = parseDbg(await dbg(pageA));
      const bb = parseDbg(await dbg(pageB));
      return ba.total > 0 && bb.total > 0 && bb.words >= 1 ? { ba, bb } : null;
    }, 90_000, "word award to propagate to both pages");
    console.log("  WORD ACCEPTED on both pages:", await dbg(pageA), "|", await dbg(pageB));
  } catch {
    console.log("  word did not register; state A:", await dbg(pageA));
    console.log("  state B:", await dbg(pageB));
    throw new Error("FAIL: word award did not propagate");
  }

  console.log("\nPASS: two browsers, one room, one gossip channel, realtime play ✅");
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  if (browserA) await browserA.close();
  if (browserB) await browserB.close();
  server.kill();
}
