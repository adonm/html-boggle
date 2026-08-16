/**
 * e2e-lib.mjs - shared harness for the browser e2e suites: playwright
 * bootstrap, chromium headless shell discovery, the miniserve static
 * server, and the state/waitFor helpers. One place for browser flags,
 * timeouts, and server setup.
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

export const { chromium } = loadPlaywright();

export function findShell() {
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

export const CHROMIUM_ARGS = [
  "--enable-unsafe-swiftshader",
  "--use-angle=swiftshader",
  "--disable-background-timer-throttling",
  "--disable-backgrounding-occluded-windows",
  "--disable-renderer-backgrounding",
  "--disable-features=IntensiveWakeUpThrottling,CalculateNativeWinOcclusion",
];

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function fail(msg) {
  throw new Error("FAIL: " + msg);
}

export async function state(page) {
  return await page.evaluate(() => {
    if (typeof window.__boggleDebugState !== "function") return null;
    try {
      return JSON.parse(window.__boggleDebugState(""));
    } catch {
      return null;
    }
  });
}

export async function waitFor(fn, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const v = await fn();
    if (v) return v;
    await sleep(1000);
  }
  fail(`timed out waiting for ${what}`);
}

export async function launchBrowser() {
  return await chromium.launch({ executablePath: findShell(), args: CHROMIUM_ARGS });
}

/** New isolated browser context + booted page. */
export async function newPage(browser, base, viewport = { width: 960, height: 700 }) {
  const page = await (await browser.newContext({ viewport })).newPage();
  await page.goto(base, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(page), 90_000, "flutter booted");
  return page;
}

/**
 * Start the static server on a random port and wait for it. Returns
 * { server, base, room } - the room code is unique per suite run.
 */
export async function launchServer(roomPrefix) {
  const port = 9000 + Math.floor(Math.random() * 500);
  const base = `http://localhost:${port}`;
  const room = roomPrefix + Date.now().toString(36).slice(-6);
  console.log("starting server on :" + port + " ...");
  const server = spawn(
    "miniserve",
    ["dist", "--port", String(port), "--index", "index.html"],
    { cwd: new URL("..", import.meta.url).pathname, stdio: "ignore" },
  );
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${base}/`);
      if (r.ok) break;
    } catch { /* not up yet */ }
    await sleep(300);
  }
  return { server, base, room };
}
