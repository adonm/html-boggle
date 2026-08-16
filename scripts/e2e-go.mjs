/**
 * e2e-go.mjs - Go (9x9) test:
 *   two players join, pick Go, ready up, start. Black's first stone goes
 *   through the real UI (tap the board); a capture sequence follows via
 *   hooks (white a1 is captured by black a2), then pass-pass ends the game.
 *   Both clients must agree on the move log, the winner, and area scoring.
 *
 * Run:  mise run test-go
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

const { server, base, room } = await launchServer("gost");

let browserA, browserB;
try {
  browserA = await launchBrowser();
  browserB = await launchBrowser();
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 700 } })).newPage();
  for (const p of [pageA, pageB]) {
    await p.goto(base, { waitUntil: "load", timeout: 60_000 });
    await waitFor(() => state(p), 90_000, "flutter booted");
  }
  await pageA.evaluate((r) => window.__boggleDebugJoin(r, "Alice"), room);
  await pageB.evaluate((r) => window.__boggleDebugJoin(r, "Bob"), room);
  await waitFor(async () => {
    const a = await state(pageA);
    const b = await state(pageB);
    return a.players === 2 && b.players === 2 ? { a, b } : null;
  }, 90_000, "players to connect");

  await pageA.evaluate(() => window.__boggleDebugSetMode("go"));
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
    return a.phase === "play" && a.mode === "go" && b.phase === "play" && b.mode === "go"
      ? { a, b }
      : null;
  }, 30_000, "go round to start on both pages");

  let a = await state(pageA);
  const blackPage = a.me === a.goBlack ? pageA : pageB;
  const whitePage = blackPage === pageA ? pageB : pageA;
  console.log(
    "  black:", blackPage === pageA ? "Alice" : "Bob",
    "| white:", whitePage === pageA ? "Alice" : "Bob",
  );

  // Black's first stone through the real UI: tap the c9 cell on the board.
  const cell = blackPage.getByText(/go cell c9/);
  await waitFor(async () => ((await cell.count()) > 0 ? true : null), 15_000, "go board");
  await cell.click();
  await waitFor(async () =>
    ((await state(whitePage))?.goMoves.includes("c9") ? true : null),
  20_000, "black's UI stone to reach white");

  // capture sequence: W a1, B b1, W d1, B a2 captures white a1
  async function goMove(page, coord, otherPage) {
    if (coord === "pass") {
      await page.evaluate(() => window.__boggleDebugGoPass(""));
    } else {
      await page.evaluate((c) => window.__boggleDebugGoMove(c), coord);
    }
    await waitFor(async () =>
      ((await state(otherPage))?.goMoves.endsWith(coord) ? true : null),
    20_000, `go move ${coord} to sync`);
    await waitFor(async () =>
      ((await state(page))?.goMoves.endsWith(coord) ? true : null),
    20_000, `go move ${coord} applied locally`);
  }
  await goMove(whitePage, "a1", blackPage);
  await goMove(blackPage, "b1", whitePage);
  await goMove(whitePage, "d1", blackPage);
  await goMove(blackPage, "a2", whitePage);
  // two passes end the game
  await goMove(whitePage, "pass", blackPage);
  await goMove(blackPage, "pass", whitePage);

  await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    return x.phase === "results" && y.phase === "results" ? { x, y } : null;
  }, 30_000, "pass-pass to end the game");

  // poll until both sides agree
  const settle = await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    const blackIdx = x.pids.indexOf(x.goBlack);
    const ok =
      x.goWinner === "black" && y.goWinner === "black" &&
      x.goMoves === "c9,a1,b1,d1,a2,pass,pass" &&
      x.goMoves === y.goMoves &&
      x.plist[blackIdx]?.score === 1 && // black scored the win
      JSON.stringify(x.plist) === JSON.stringify(y.plist);
    return ok ? { x, y, ok } : null;
  }, 30_000, "go results to agree on both pages");

  const { x: ga, y: gb, ok } = settle;
  console.log("A:", JSON.stringify({ winner: ga.goWinner, moves: ga.goMoves }));
  console.log("B:", JSON.stringify({ winner: gb.goWinner, moves: gb.goMoves }));
  console.log(ok ? "PASS: go round with a capture, pass-pass end, scores agree ✅" : "FAIL");
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
