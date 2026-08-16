/**
 * e2e-solo.mjs - single-player mode test:
 *   one browser joins a room alone and plays Capture Chess against itself
 *   (solo seats both sides) through the fool's-mate capture, then Go with
 *   two passes. No second player needed - every game must be startable
 *   and playable solo for testing.
 *
 * Run:  mise run test-solo
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
const ROOM = "solo" + Date.now().toString(36).slice(-6);

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

let browser;
try {
  browser = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  const page = await (await browser.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  await page.goto(BASE, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(page), 90_000, "flutter booted");
  await page.evaluate((r) => window.__boggleDebugJoin(r, "Solo"), ROOM);
  await waitFor(async () => ((await state(page))?.phase === "room" ? true : null), 30_000, "join");

  // ---- solo chess: one player on both sides -------------------------------
  await page.evaluate(() => window.__boggleDebugSetMode("chess"));
  await page.evaluate(() => window.__boggleDebugChessRules("capture"));
  await page.evaluate(() => window.__boggleDebugReady(""));
  await waitFor(async () => ((await state(page))?.allReady ? true : null), 15_000, "ready");
  await page.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => ((await state(page))?.phase === "play" ? true : null), 20_000, "chess start");

  let a = await state(page);
  console.log("  solo chess seats:", JSON.stringify({ white: a.chessWhite, black: a.chessBlack, me: a.me }));
  const okSeats = a.chessWhite === a.me && a.chessBlack === a.me;

  // fool's mate: the solo player moves both colors
  const moves = [["f2", "f3"], ["e7", "e5"], ["g2", "g4"], ["d8", "h4"], ["a2", "a3"], ["h4", "e1"]];
  for (const [from, to] of moves) {
    await page.evaluate(
      (args) => window.__boggleDebugChessMove(args[0], args[1]),
      [from, to],
    );
    await waitFor(async () =>
      ((await state(page))?.chessMoves.endsWith(from + to) ? true : null),
    15_000, `chess move ${from}${to}`);
  }
  await waitFor(async () => ((await state(page))?.phase === "results" ? true : null), 20_000, "chess results");
  a = await state(page);
  console.log("  solo chess:", JSON.stringify({ winner: a.chessWinner, moves: a.chessMoves }));
  const okChess = okSeats && a.chessWinner === "black" &&
    a.chessMoves === "f2f3,e7e5,g2g4,d8h4,a2a3,h4e1";

  // ---- solo standard chess: checkmate via the engine ----------------------
  await page.evaluate(() => window.__boggleDebugChessRules("standard"));
  await page.evaluate(() => window.__boggleDebugReady(""));
  await waitFor(async () => ((await state(page))?.allReady ? true : null), 15_000, "std ready");
  await page.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => ((await state(page))?.phase === "play" ? true : null), 20_000, "std start");
  const stdMoves = [["e2", "e4"], ["e7", "e5"], ["f1", "c4"], ["b8", "c6"], ["d1", "h5"], ["g8", "f6"], ["h5", "f7"]];
  for (const [from, to] of stdMoves) {
    await page.evaluate(
      (args) => window.__boggleDebugChessMove(args[0], args[1]),
      [from, to],
    );
    await waitFor(async () =>
      ((await state(page))?.chessMoves.endsWith(from + to) ? true : null),
    15_000, `std move ${from}${to}`);
  }
  await waitFor(async () => ((await state(page))?.phase === "results" ? true : null), 20_000, "std results");
  a = await state(page);
  console.log("  solo std chess:", JSON.stringify({ winner: a.chessWinner, moves: a.chessMoves, rules: a.chessRules }));
  const okStd = a.chessRules === "standard" && a.chessWinner === "white" &&
    a.chessMoves === "e2e4,e7e5,f1c4,b8c6,d1h5,g8f6,h5f7";

  // ---- solo go: two passes end the game -----------------------------------
  await page.evaluate(() => window.__boggleDebugSetMode("go"));
  await page.evaluate(() => window.__boggleDebugReady(""));
  await waitFor(async () => ((await state(page))?.allReady ? true : null), 15_000, "go ready");
  await page.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => {
    const s = await state(page);
    return s.phase === "play" && s.mode === "go" ? s : null;
  }, 20_000, "go start");
  await page.evaluate(() => window.__boggleDebugGoMove("a1"));
  await page.evaluate(() => window.__boggleDebugGoPass(""));
  await page.evaluate(() => window.__boggleDebugGoPass(""));
  await waitFor(async () => ((await state(page))?.phase === "results" ? true : null), 20_000, "go results");
  a = await state(page);
  console.log("  solo go:", JSON.stringify({ winner: a.goWinner, moves: a.goMoves }));
  const okGo = a.goWinner === "black" && a.goMoves === "a1,pass,pass";

  const ok = okChess && okStd && okGo;
  console.log(ok ? "PASS: solo chess (party + standard) + go rounds ✅" : "FAIL");
  if (!ok) process.exitCode = 1;
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  if (browser) browser.close().catch(() => {});
  server.kill();
}
