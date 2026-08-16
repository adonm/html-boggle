/**
 * e2e-solo.mjs - single-player mode test:
 *   one browser joins a room alone and plays Chess against itself (solo
 *   seats both sides) through the scholar's mate checkmate, then Go with
 *   two passes. No second player needed - every game must be startable
 *   and playable solo for testing.
 *
 * Run:  mise run test-solo
 */


import {
  launchBrowser,
  launchServer,
  newPage,
  state,
  waitFor,
  sleep,
  fail,
} from "./e2e-lib.mjs";

const { server, base, room } = await launchServer("solo");

let browser;
try {
  browser = await launchBrowser();
  const page = await (await browser.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  await page.goto(base, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(page), 90_000, "flutter booted");
  await page.evaluate((r) => window.__boggleDebugJoin(r, "Solo"), room);
  await waitFor(async () => ((await state(page))?.phase === "room" ? true : null), 30_000, "join");

  // ---- solo chess: one player on both sides -------------------------------
  await page.evaluate(() => window.__boggleDebugSetMode("chess"));
  await page.evaluate(() => window.__boggleDebugReady(""));
  await waitFor(async () => ((await state(page))?.allReady ? true : null), 15_000, "ready");
  await page.evaluate(() => window.__boggleDebugStart(""));
  await waitFor(async () => ((await state(page))?.phase === "play" ? true : null), 20_000, "chess start");

  let a = await state(page);
  console.log("  solo chess seats:", JSON.stringify({ white: a.chessWhite, black: a.chessBlack, me: a.me }));
  const okSeats = a.chessWhite === a.me && a.chessBlack === a.me;

  // scholar's mate: the solo player moves both colors to a checkmate
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
  console.log("  solo chess:", JSON.stringify({ winner: a.chessWinner, moves: a.chessMoves }));
  const okChess = okSeats && a.chessWinner === "white" &&
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

  const ok = okChess && okGo;
  console.log(ok ? "PASS: solo chess checkmate + go rounds ✅" : "FAIL");
  if (!ok) process.exitCode = 1;
} catch (err) {
  console.error(err.message ?? err);
  process.exitCode = 1;
} finally {
  if (browser) browser.close().catch(() => {});
  server.kill();
}
