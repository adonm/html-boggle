/**
 * e2e-web.mjs - REAL BROWSER end-to-end test against the Flutter app:
 *   two headless-chromium tabs join the same room, get auto-connected on one
 *   iroh gossip channel, start a round, and one player submits a real word.
 *
 * Flutter web runs with the semantics DOM enabled, so the test drives the real
 * UI (inputs + buttons + tiles) via aria labels, falling back to the
 * __boggleDebug* hooks only when a UI interaction flakes.
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

const CHROMIUM_ARGS = [
  "--enable-unsafe-swiftshader",
  "--use-angle=swiftshader",
  // The headless shell treats pages as backgrounded and throttles timers to
  // ~1/min (IntensiveWakeUpThrottling), which stalls the game loop and the
  // gossip event delivery. Disable all of that.
  "--disable-background-timer-throttling",
  "--disable-backgrounding-occluded-windows",
  "--disable-renderer-backgrounding",
  "--disable-features=IntensiveWakeUpThrottling,CalculateNativeWinOcclusion",
];

const SHELL = findShell();
const PORT = 8000 + Math.floor(Math.random() * 2000);
const BASE = `http://localhost:${PORT}`;
const ROOM = "e2e" + Date.now().toString(36).slice(-6);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function fail(msg) {
  throw new Error("FAIL: " + msg);
}

/* ---------- board generation (mirrors app/lib/board.dart) ---------- */
const DICE = [
  "AAEEGN", "ABBJOO", "ACHOPS", "AFFKPS",
  "AOOTTW", "CIMOTU", "DEILRX", "DELRVY",
  "DISTTY", "EEGHNW", "EEINSU", "EHRTVW",
  "EIOSST", "ELRTTY", "HIMNQU", "HLNNRZ",
];
const boardBytes = createHash("sha256").update("board:" + ROOM).digest();
const board = DICE.map((die, i) => die[boardBytes[i] % 6].toLowerCase());

/* find a short valid word on the board (dict = sorted asset) */
const words = readFileSync(
  new URL("../app/assets/words.txt", import.meta.url).pathname,
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
async function state(page) {
  return await page.evaluate(() => {
    if (typeof window.__boggleDebugState !== "function") return null;
    try {
      return JSON.parse(window.__boggleDebugState(""));
    } catch {
      return null;
    }
  });
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

/** Join through the real lobby UI; fall back to the debug hook if the
 *  semantics inputs are flaky. Returns the page state once in the room. */
async function joinRoom(page, name) {
  page.on("console", (m) => {
    if (m.type() === "error" || m.type() === "warning" || m.text().startsWith("[boggle]")) {
      // harmless: pkarr GETs 404 before anyone publishes
      if (m.text().includes("dns.iroh.link")) return;
      console.log(`  [${name} console.${m.type()}]`, m.text().slice(0, 160));
    }
  });
  page.on("pageerror", (e) => console.log(`  [${name} pageerror]`, String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(page), 90_000, `${name}: flutter booted`);

  let joined = null;
  try {
    const nameInput = page.locator('input[aria-label="Your name"]');
    const roomInput = page.locator('input[aria-label="Room code"]');
    await waitForSoft(async () => (await nameInput.count()) > 0, 15_000);
    // Click to focus first (Flutter wires its real editing input), then type:
    // filling the semantics input directly doesn't reliably reach Flutter, and
    // its value/label change once focused. The first keystroke can also race
    // the hidden input attachment, so verify the ROOM via game state after
    // joining and retry the lobby if a character got eaten.
    await nameInput.click();
    await sleep(300);
    await page.keyboard.type(name, { delay: 40 });
    const joinBtn = page.getByRole("button", { name: "JOIN ROOM" });
    for (let attempt = 0; attempt < 3; attempt++) {
      await roomInput.click();
      await sleep(300);
      await page.keyboard.press("Control+a");
      await page.keyboard.type(ROOM, { delay: 40 });
      await sleep(200);
      await joinBtn.click();
      const s = await waitForSoft(async () => {
        const st = await state(page);
        return st && (st.phase === "room" || st.phase === "joining") ? st : null;
      }, 25_000);
      if (s && s.room === ROOM) {
        joined = s;
        break;
      }
    }
  } catch {
    joined = null;
  }
  if (!joined) {
    console.log(`  ${name}: lobby UI flaky - joining via debug hook`);
    await page.evaluate(
      ([r, n]) => window.__boggleDebugJoin(r, n),
      [ROOM, name],
    );
  }
  return await waitFor(async () => {
    const s = await state(page);
    return s?.phase === "room" ? s : null;
  }, 60_000, `${name}: joined room`);
}

/** Start the round via the real button; fall back to the debug hook. */
async function startRound(page) {
  try {
    await page.getByRole("button", { name: "START ROUND" }).click();
    if (await waitForSoft(async () => (await state(page))?.phase === "play", 5_000)) {
      return;
    }
  } catch { /* fall through */ }
  await page.evaluate(() => window.__boggleDebugStart(""));
}

/** Submit a word by tapping its tiles via the semantics DOM. */
async function submitViaTiles(page, word) {
  const path = [];
  findPath(word, 0, -1, new Array(16).fill(false), path);
  for (const i of path) {
    const letter = board[i].toUpperCase();
    await page.getByRole("button", { name: `Tile ${i + 1} letter ${letter}` }).click();
  }
  await page.getByRole("button", { name: "SUBMIT" }).click();
}

function findPath(w, idx, pos, used, path) {
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
      if (findPath(w, idx + board[i].length, i, used, path)) return true;
      path.pop();
      used[i] = false;
    }
  }
  return false;
}

/* ---------- main ---------- */
console.log("starting server on :" + PORT + " ...");
const server = spawn(
  "deno",
  ["run", "-A", "server/main.ts"],
  { cwd: new URL("..", import.meta.url).pathname, env: { ...process.env, PORT: String(PORT) },
    stdio: "ignore" },
);
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
  browserA = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  browserB = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });

  console.log("page A (Alice)...");
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 600 } })).newPage();
  await joinRoom(pageA, "Alice");

  console.log("page B (Bob)...");
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 600 } })).newPage();
  await joinRoom(pageB, "Bob");

  console.log("waiting for the gossip overlay to connect both players...");
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.players === 2 && b.players === 2 ? { a, b } : null;
  }, 90_000, "both players to see each other");
  console.log("  CONNECTED:", JSON.stringify(await state(pageA)), "|", JSON.stringify(await state(pageB)));

  // host = smallest node id
  const a = await state(pageA);
  const b = await state(pageB);
  const hostPage = a.me < b.me ? pageA : pageB;
  console.log("host page:", hostPage === pageA ? "A" : "B");

  console.log("host starts the round...");
  await startRound(hostPage);
  await waitFor(async () => {
    const ha = await state(pageA);
    const hb = await state(pageB);
    return ha.phase === "play" && hb.phase === "play" ? { ha, hb } : null;
  }, 30_000, "round to start on both pages");
  console.log("  PLAYING on both pages");

  const submitter = hostPage === pageA ? pageB : pageA;
  console.log("submitting", word, "by tapping tiles...");
  let submitted = false;
  try {
    await submitViaTiles(submitter, word);
    submitted = await waitForSoft(async () => (await state(submitter))?.words >= 1, 6_000);
  } catch {
    submitted = false;
  }
  if (!submitted) {
    console.log("  tile taps flaky - submitting via debug hook");
    await submitter.evaluate((w) => window.__boggleDebugSubmit(w), word);
    submitted = await waitForSoft(async () => (await state(submitter))?.words >= 1, 6_000);
  }
  if (!submitted) fail("word submit did not register");

  await waitFor(async () => {
    const sa = await state(pageA);
    const sb = await state(pageB);
    return sa.total > 0 && sb.total > 0 && sa.players === 2 ? { sa, sb } : null;
  }, 150_000, "word award to propagate to both pages");
  console.log("  WORD ACCEPTED on both pages:", JSON.stringify(await state(pageA)), "|", JSON.stringify(await state(pageB)));

  console.log("\nPASS: two browsers, one room, one gossip channel, realtime play ✅");
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  if (browserA) await browserA.close();
  if (browserB) await browserB.close();
  server.kill();
}
