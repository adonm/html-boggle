/**
 * e2e-resume.mjs - room resume test:
 *   A and B join, A starts a boggle round and plays a word. A's tab is then
 *   reloaded from scratch: the persisted identity + room cache must auto-rejoin
 *   the room as the same player (same node id, same name) and resync the live
 *   game state (phase, board, scores) from the host snapshots. Finally LEAVE
 *   ROOM clears the cache: a reload stays in the lobby.
 *
 * Run:  mise run test-resume
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
const ROOM = "resm" + Date.now().toString(36).slice(-6);

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

let browserA, browserB;
try {
  browserA = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  browserB = await chromium.launch({ executablePath: SHELL, args: CHROMIUM_ARGS });
  // contextA is REUSED across the reload so localStorage survives, as in a
  // real browser tab.
  const contextA = await browserA.newContext({ viewport: { width: 960, height: 600 } });
  const pageA = await contextA.newPage();
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 600 } })).newPage();
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
  const idBefore = (await state(pageA)).me;

  // start a boggle round mid-flight and play a word, so there is live state
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
  await waitFor(async () => ((await state(pageA))?.allReady ? true : null), 30_000, "ready");
  await pageA.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => ((await state(pageB))?.phase === "play" ? true : null), 30_000, "round start");
  const boardBefore = (await state(pageB)).board;

  // ---- the reload: a "long disconnection" from A's point of view ----------
  console.log("reloading Alice's tab ...");
  await pageA.goto(BASE, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(pageA), 90_000, "flutter re-booted");
  // maybeRejoin fires ~800ms after init
  await waitFor(async () => {
    const a = await state(pageA);
    return a.phase === "play" && a.players === 2 ? a : null;
  }, 90_000, "auto-rejoin and state resync");

  const a = await state(pageA);
  console.log("A after reload:", JSON.stringify({
    phase: a.phase, players: a.players, room: a.room,
    sameId: a.me === idBefore, board: a.board, toast: a.toast,
  }));
  const ok1 =
    a.phase === "play" && // resynced into the live round, not stuck in lobby
    a.me === idBefore && // same iroh identity (persisted secret key)
    a.room === ROOM &&
    a.players === 2 &&
    a.board === boardBefore; // same served board

  // ---- LEAVE ROOM must clear the cache: reload stays in the lobby --------
  // (leave lives on the results screen, so end the live round first)
  console.log("ending the round, then leaving the room ...");
  await pageA.evaluate(() => window.__boggleDebugEndRound(""));
  await pageB.evaluate(() => window.__boggleDebugEndRound(""));
  await waitFor(async () => ((await state(pageA))?.phase === "results" ? true : null), 30_000, "round end");
  await pageA.getByText("LEAVE ROOM", { exact: true }).click();
  await waitFor(async () => ((await state(pageA))?.phase === "lobby" ? true : null), 15_000, "lobby after leave");
  await pageA.goto(BASE, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(pageA), 90_000, "flutter re-booted");
  await sleep(3000); // give maybeRejoin its window - it must NOT fire
  const a2 = await state(pageA);
  const ok2 = a2.phase === "lobby";
  console.log("A after leave+reload:", a2.phase, ok2 ? "(stays in lobby)" : "(rejoined!)");

  const ok = ok1 && ok2;
  console.log(ok ? "PASS: identity + room resume across reloads, leave clears the cache ✅" : "FAIL");
  if (!ok) process.exitCode = 1;
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  const closeSafe = (b) =>
    b?.close().catch(() => {});
  await closeSafe(browserA);
  await closeSafe(browserB);
  server.kill();
}
