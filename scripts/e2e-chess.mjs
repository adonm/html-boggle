/**
 * e2e-chess.mjs - Capture Chess test:
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

  // White's first move through the real UI: tap f2, then f3.
  await whitePage.getByText(/chess square f2/).click();
  await sleep(300);
  await whitePage.getByText(/chess square f3/).click();
  await waitFor(async () =>
    ((await state(blackPage))?.chessMoves.includes("f2f3") ? true : null),
  20_000, "white's UI move to reach black");

  // Fool's mate, capture-the-king style: ...e5 g4 Qh4 a3 Qxe1.
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
  await move(whitePage, "g2", "g4", blackPage);
  await move(blackPage, "d8", "h4", whitePage);
  await move(whitePage, "a2", "a3", blackPage);
  await move(blackPage, "h4", "e1", whitePage);

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
  }, 30_000, "king capture to end the game");
  await sleep(2500); // let the host state settle everywhere

  a = await state(pageA);
  const b = await state(pageB);
  const c = await state(pageC);
  console.log("A:", JSON.stringify({ winner: a.chessWinner, moves: a.chessMoves, score: a.total }));
  console.log("B:", JSON.stringify({ winner: b.chessWinner, moves: b.chessMoves, score: b.total }));
  console.log("C:", JSON.stringify({ winner: c.chessWinner, moves: c.chessMoves, phase: c.phase }));

  const blackIdx = a.pids.indexOf(blackId);
  const whiteIdx = a.pids.indexOf(whiteId);
  const ok =
    a.chessWinner === "black" && b.chessWinner === "black" && c.chessWinner === "black" &&
    a.chessMoves === "f2f3,e7e5,g2g4,d8h4,a2a3,h4e1" &&
    a.chessMoves === b.chessMoves && b.chessMoves === c.chessMoves &&
    a.plist[blackIdx]?.score === 1 && a.plist[whiteIdx]?.score === 0 &&
    JSON.stringify(a.plist) === JSON.stringify(b.plist) &&
    JSON.stringify(b.plist) === JSON.stringify(c.plist) &&
    c.players === 3 && c.phase === "results"; // spectator sees it all
  console.log(ok ? "PASS: capture-the-king game with a mid-game spectator ✅" : "FAIL");
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
