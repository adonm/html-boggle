/**
 * e2e-scatter.mjs - Scattergories round test:
 *   two players join, pick Scattergories, ready up, start; both submit
 *   overlapping and unique words; the round is force-ended and both must
 *   agree on duplicate cancellation scoring.
 *
 * Run:  mise run test-scatter
 */

import { createRequire } from "node:module";
import { globSync, readFileSync } from "node:fs";
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
const ROOM = "scat" + Date.now().toString(36).slice(-6);

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

  // pick the game via the real UI (dropdown), with the hook as fallback
  console.log("picking Scattergories...");
  try {
    const anchor = pageA.locator('input[aria-label*="game"]');
    await waitFor(async () => ((await anchor.count()) > 0 ? true : null), 15_000, "game dropdown");
    await anchor.click();
    await sleep(400);
    await pageA.getByText("Scattergories", { exact: true }).click();
    await waitFor(async () =>
      ((await state(pageA))?.mode === "scattergories" ? true : null),
    10_000, "mode selection");
  } catch {
    console.log("  dropdown click flaky - setting via debug hook");
    await pageA.evaluate(() => window.__boggleDebugSetMode("scattergories"));
  }
  await sleep(300);

  // ready up + start (the starter's mode choice is served in the start msg)
  await pageA.evaluate(() => window.__boggleDebugReady(""));
  await pageB.evaluate(() => window.__boggleDebugReady(""));
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.allReady && b.allReady ? { a, b } : null;
  }, 30_000, "everyone ready");
  await pageA.getByRole("button", { name: "START ROUND", exact: true }).click({ timeout: 10_000 }).catch(() => {});
  if (!(await waitFor(async () => ((await state(pageA))?.phase === "play" ? true : null), 8_000).catch(() => null))) {
    console.log("  start click flaky - starting via debug hook");
    await pageA.evaluate(() => window.__boggleDebugStart(""));
  }
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.phase === "play" && a.mode === "scattergories" && b.phase === "play" && b.mode === "scattergories"
      ? { a, b }
      : null;
  }, 30_000, "scattergories round to start on both pages");
  console.log("  letter:", (await state(pageA)).letter);
  const letter = (await state(pageA)).letter.toLowerCase();
  // pick real dictionary words that start with the served letter
  const dictWords = readFileSync(
    new URL("../app/assets/words.txt", import.meta.url).pathname,
    "utf8",
  ).split("\n").filter(Boolean);
  const matches = dictWords.filter((w) => w.startsWith(letter) && w.length >= 3);
  if (matches.length < 3) fail("not enough dictionary words for letter " + letter);
  const [w1, w2, w3] = matches;
  console.log("  words:", w1, w2, w3);

  // submissions: A submits w1+w2+w3 (one via the UI), B submits w1 ->
  // w1 cancels, A scores w2+w3.
  await pageA.evaluate((w) => window.__boggleDebugSubmitScat(w), w1);
  await pageB.evaluate((w) => window.__boggleDebugSubmitScat(w), w1);
  await pageA.evaluate((w) => window.__boggleDebugSubmitScat(w), w2);
  // UI submission for coverage: type into the real input
  const input = pageA.locator('input[aria-label*="Scattergories word"]');
  await waitFor(async () => ((await input.count()) > 0 ? true : null), 15_000, "scatter input");
  await input.click();
  await sleep(300);
  await pageA.keyboard.type(w3, { delay: 30 });
  await pageA.keyboard.press("Enter");
  await waitFor(async () => (await state(pageA)).sgCount >= 3 ? true : null, 15_000, "A's submissions");

  // force the round to end and wait for the tally on both sides
  await pageA.evaluate(() => window.__boggleDebugEndRound(""));
  await pageB.evaluate(() => window.__boggleDebugEndRound(""));
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.phase === "results" && b.phase === "results" ? { a, b } : null;
  }, 30_000, "round to end on both pages");

  // poll until both sides agree (messages can lag the results phase)
  const settle = await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    const ok =
      a.sgDupes === w1 && // exactly the overlap cancels
      a.sgScore === 2 && // w2 + w3 unique for A
      b.sgScore === 0 && // B's only word was the duplicate
      JSON.stringify(a.sgScores) === JSON.stringify(b.sgScores); // both agree
    return ok ? { a, b, ok } : null;
  }, 20_000, "tally to agree on both pages");
  const { a, b, ok } = settle;
  console.log("A:", JSON.stringify({ score: a.sgScore, count: a.sgCount, dupes: a.sgDupes }));
  console.log("B:", JSON.stringify({ score: b.sgScore, count: b.sgCount, dupes: b.sgDupes }));
  console.log(ok ? "PASS: scattergories round with duplicate cancellation ✅" : "FAIL");
  if (!ok) process.exitCode = 1;
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  const closeSafe = (b) =>
    b ? Promise.race([b.close(), sleep(5000)]).catch(() => {}) : Promise.resolve();
  await closeSafe(browserA);
  await closeSafe(browserB);
  server.kill();
}
