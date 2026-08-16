/**
 * e2e-sketch.mjs - SketchIt (pictionary) round test:
 *   two players join, pick SketchIt, ready up, start. The drawer (first
 *   player) draws real strokes on the canvas; the guesser submits a wrong
 *   guess then the right one. Both sides must agree on the solved word and
 *   the drawer+guesser scoring.
 *
 * Run:  mise run test-sketch
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
const ROOM = "skch" + Date.now().toString(36).slice(-6);

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
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 600 } })).newPage();
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

  // pick SketchIt (hook sets the starter's mode; it rides in the start msg)
  await pageA.evaluate(() => window.__boggleDebugSetMode("sketchit"));
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
    return a.phase === "play" && a.mode === "sketchit" && a.sketchWord &&
        b.phase === "play" && b.mode === "sketchit" && b.sketchWord
      ? { a, b }
      : null;
  }, 30_000, "sketchit round to start on both pages");

  let a = await state(pageA);
  const word = a.sketchWord;
  // drawer = smallest node id (canonical role order, same on both clients)
  const drawerPage = a.sketchDrawer === a.me ? pageA : pageB;
  const guesserPage = drawerPage === pageA ? pageB : pageA;
  console.log(
    "  word:", word,
    "| drawer:", drawerPage === pageA ? "Alice" : "Bob",
  );

  // The drawer draws real strokes on the canvas with the mouse
  const canvas = drawerPage.getByText(/drawing canvas/);
  await waitFor(async () => ((await canvas.count()) > 0 ? true : null), 15_000, "canvas");
  const box = await canvas.boundingBox();
  if (!box) fail("canvas bounding box missing");
  await drawerPage.mouse.move(box.x + box.width * 0.2, box.y + box.height * 0.4);
  await drawerPage.mouse.down();
  for (let i = 0; i <= 10; i++) {
    await drawerPage.mouse.move(
      box.x + box.width * (0.2 + 0.06 * i),
      box.y + box.height * (0.4 + 0.02 * Math.sin(i)),
    );
    await sleep(30);
  }
  await drawerPage.mouse.up();
  await sleep(500);
  await waitFor(async () => {
    const s = await state(guesserPage);
    return s.sketchStrokes > 0 ? s : null;
  }, 20_000, "strokes to reach the guesser");

  // wrong guess does nothing; the right one solves the round
  await guesserPage.evaluate(() => window.__boggleDebugGuess("zzzznotaword"));
  await sleep(800);
  a = await state(pageA);
  if (a.sketchSolved) fail("round solved by a wrong guess");
  await guesserPage.evaluate((w) => window.__boggleDebugGuess(w), word);
  await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    return x.phase === "results" && y.phase === "results" && x.sketchSolved && y.sketchSolved
      ? { x, y }
      : null;
  }, 30_000, "round to end with the correct guess");
  await sleep(2000); // let the host state settle

  a = await state(pageA);
  const b = await state(pageB);
  console.log("A:", JSON.stringify({ score: a.total, solved: a.sketchSolved, word: a.sketchWord }));
  console.log("B:", JSON.stringify({ score: b.total, solved: b.sketchSolved, word: b.sketchWord }));

  const drawerIdx = a.pids.indexOf(a.sketchDrawer);
  const guesserIdx = 1 - drawerIdx;
  const ok =
    a.sketchWord === word && b.sketchWord === word &&
    a.plist[drawerIdx]?.score === 1 && a.plist[guesserIdx]?.score === 1 &&
    JSON.stringify(a.plist) === JSON.stringify(b.plist); // both sides agree
  console.log(ok ? "PASS: sketchit draw + guess round, scores agree ✅" : "FAIL");
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
