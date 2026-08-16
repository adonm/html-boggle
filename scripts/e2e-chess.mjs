/**
 * e2e-chess.mjs - Chess (capture-the-king) test:
 *   two players join, pick chess, ready up, start. White's first move is made
 *   through the real UI (tap squares); a third browser joins mid-game and
 *   spectates. Black wins with the capture-the-king fool's mate; all three
 *   clients must agree on the move log and the winner.
 *
 * Run:  mise run test-chess
 */

import { createRequire } from "node:module";
import { globSync } from "node:fs";
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
  const roots = [`${process.env.HOME}/.cache/ms-playwright`, "/root/.cache/ms-playwright"];
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
const PORT = 9000 + Math.floor(Math.random() * 500);
const BASE = `http://localhost:${PORT}`;
const ROOM = "chss" + Date.now().toString(36).slice(-6);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CHROMIUM_ARGS = [
  "--enable-unsafe-swiftshader",
  "--use-angle=swiftshader",
  "--disable-background-timer-throttling",
  "--disable-backgrounding-occluded-windows",
  "--disable-renderer-backgrounding",
  "--disable-features=IntensiveWakeUpThrottling,CalculateNativeWinOcclusion",
];

function fail(msg) {
  throw new Error("FAIL: " + msg);
}

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

console.log("starting server on :" + PORT + " ...");
const server = spawn(
  "miniserve",
  ["dist", "--port", String(PORT), "--index", "index.html"],
  { cwd: new URL("..", import.meta.url).pathname, stdio: "ignore" },
);
{
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${BASE}/`);
      if (r.ok) break;
    } catch { /* not up yet */ }
    await sleep(300);
  }
}

let browserA, browserB, browserC;
try {
  browserA = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  browserB = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  for (const p of [pageA, pageB]) {
    await p.goto(BASE, { waitUntil: "load", timeout: 60_000 });
    await waitFor(() => state(p), 90_000, "flutter booted");
  }
  await pageA.evaluate((r) => window.__boggleDebugJoin(r, "Alice"), ROOM);
  await pageB.evaluate((r) => window.__boggleDebugJoin(r, "Bob"), ROOM);
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.players === 2 && b.players === 2 ? { a, b } : null;
  }, 90_000, "players to connect");

  await pageA.evaluate(() => window.__boggleDebugSetMode("chess"));
  // ready up (retry: a ready toggle can race the first gossip connect)
  for (let attempt = 0; attempt < 4; attempt++) {
    if (!(await state(pageA))?.myReady) {
      await pageA.evaluate(() => window.__boggleDebugReady(""));
    }
    if (!(await state(pageB))?.myReady) {
      await pageB.evaluate(() => window.__boggleDebugReady(""));
    }
    await sleep(2000);
    if ((await state(pageA))?.allReady) break;
  }
  await waitFor(async () => ((await state(pageA))?.allReady ? true : null), 30_000, "everyone ready");
  await pageA.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.phase === "play" && a.mode === "chess" && b.phase === "play" && b.mode === "chess"
      ? { a, b }
      : null;
  }, 30_000, "chess round to start on both pages");

  // Roles are canonical: sorted node ids - white = smallest, black = next.
  let a = await state(pageA);
  const b0 = await state(pageB);
  if (JSON.stringify(a.pids.sort()) !== JSON.stringify(b0.pids.sort())) {
    fail("player lists disagree before the game starts");
  }
  const whiteId = [...a.pids].sort()[0];
  const blackId = [...a.pids].sort()[1];
  const whitePage = a.me === whiteId ? pageA : pageB;
  const blackPage = whitePage === pageA ? pageB : pageA;
  console.log(
    "  white:",
    whitePage === pageA ? "Alice" : "Bob",
    "| black:",
    blackPage === pageA ? "Alice" : "Bob",
  );

  // White's first move through the real UI: tap e2, then e4.
  await whitePage.getByText(/chess square e2/).click();
  await sleep(300);
  await whitePage.getByText(/chess square e4/).click();
  await waitFor(async () =>
    ((await state(blackPage))?.chessMoves.includes("e2e4") ? true : null),
  20_000, "white's UI move to reach black");

  // Scholar's mate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# (checkmate).
  // Each move must arrive at the opponent before their reply, or the
  // turn check on the sender's own (lagging) log rejects it.
  async function move(page, from, to, otherPage) {
    await page.evaluate(
      (args) => window.__boggleDebugChessMove(args[0], args[1]),
      [from, to],
    );
    await waitFor(async () =>
      ((await state(otherPage))?.chessMoves.endsWith(from + to) ? true : null),
    20_000, `move ${from}${to} to sync`);
    await waitFor(async () =>
      ((await state(page))?.chessMoves.endsWith(from + to) ? true : null),
    20_000, `move ${from}${to} applied locally`);
  }
  await move(blackPage, "e7", "e5", whitePage);
  await move(whitePage, "f1", "c4", blackPage);
  await move(blackPage, "b8", "c6", whitePage);
  await move(whitePage, "d1", "h5", blackPage);
  await move(blackPage, "g8", "f6", whitePage);
  await move(whitePage, "h5", "f7", blackPage);

  // Spectator joins mid-game and must see the same board and moves.
  browserC = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  const pageC = await (await browserC.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  await pageC.goto(BASE, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(pageC), 90_000, "spectator booted");
  await pageC.evaluate((r) => window.__boggleDebugJoin(r, "Carl"), ROOM);
  await waitFor(async () => ((await state(pageC))?.players === 3 ? true : null), 60_000, "spectator to join");

  await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    return x.phase === "results" && y.phase === "results" ? { x, y } : null;
  }, 30_000, "checkmate to end the game");

  // poll until everyone (including the spectator) agrees
  const settle = await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    const z = await state(pageC);
    const blackIdx = x.pids.indexOf(blackId);
    const whiteIdx = x.pids.indexOf(whiteId);
    const ok =
      x.chessWinner === "white" && y.chessWinner === "white" && z.chessWinner === "white" &&
      x.chessMoves === "e2e4,e7e5,f1c4,b8c6,d1h5,g8f6,h5f7" &&
      x.chessMoves === y.chessMoves && y.chessMoves === z.chessMoves &&
      x.plist[whiteIdx]?.score === 1 && x.plist[blackIdx]?.score === 0 &&
      JSON.stringify(x.plist) === JSON.stringify(y.plist) &&
      JSON.stringify(y.plist) === JSON.stringify(z.plist) &&
      z.players === 3 && z.phase === "results"; // spectator sees it all
    return ok ? { x, y, z, ok } : null;
  }, 30_000, "all three clients to agree");

  const { x: fa, y: fb, z: fc, ok } = settle;
  console.log("A:", JSON.stringify({ winner: fa.chessWinner, synced: fa.synced, sent: fa.stateSent, recv: fa.stateReceived }));
  console.log("B:", JSON.stringify({ winner: fb.chessWinner, synced: fb.synced, sent: fb.stateSent, recv: fb.stateReceived }));
  console.log("C:", JSON.stringify({ winner: fc.chessWinner, moves: fc.chessMoves, phase: fc.phase, synced: fc.synced, sent: fc.stateSent, recv: fc.stateReceived, players: fc.players }));
  console.log(ok ? "PASS: chess scholar's-mate checkmate with a mid-game spectator ✅" : "FAIL");
  if (!ok) process.exitCode = 1;
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  const closeSafe = (b) =>
    b?.close().catch(() => {});
  await closeSafe(browserA);
  await closeSafe(browserB);
  await closeSafe(browserC);
  server.kill();
}
