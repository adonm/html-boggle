/**
 * e2e-resume.mjs - room resume test:
 *   A and B join, A starts a boggle round and plays a word. A's tab is then
 *   reloaded from scratch: the persisted identity + room cache must auto-rejoin
 *   the room as the same player (same node id, same name) and resync the live
 *   game state (phase, board, scores) from the host snapshots. Finally LEAVE
 *   room clears the cache: a reload stays in the lobby.
 *
 * Run:  mise run test-resume
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

const { server, base, room } = await launchServer("resm");

let browserA, browserB;
try {
  browserA = await launchBrowser();
  browserB = await launchBrowser();
  // contextA is REUSED across the reload so localStorage survives, as in a
  // real browser tab.
  const contextA = await browserA.newContext({ viewport: { width: 960, height: 600 } });
  const pageA = await contextA.newPage();
  const pageB = await (await browserB.newContext({ viewport: { width: 960, height: 600 } })).newPage();
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
  // The app must PROMPT before rejoining (no surprise rejoin).
  console.log("reloading Alice's tab ...");
  await pageA.goto(base, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(pageA), 90_000, "flutter re-booted");
  await waitFor(async () => {
    const a = await state(pageA);
    return a.rejoinRoom === room ? a : null;
  }, 60_000, "rejoin prompt to be offered");
  // still in the lobby until the user answers
  const beforeClick = await state(pageA);
  if (beforeClick.phase !== "lobby") fail("rejoined without the prompt");
  await pageA.getByText("REJOIN", { exact: true }).click();
  await waitFor(async () => {
    const a = await state(pageA);
    return a.phase === "play" && a.players === 2 ? a : null;
  }, 90_000, "prompted rejoin and state resync");

  const a = await state(pageA);
  console.log("A after reload:", JSON.stringify({
    phase: a.phase, players: a.players, room: a.room,
    sameId: a.me === idBefore, board: a.board, toast: a.toast,
  }));
  const ok1 =
    a.phase === "play" && // resynced into the live round, not stuck in lobby
    a.me === idBefore && // same iroh identity (persisted secret key)
    a.room === room &&
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
  await pageA.goto(base, { waitUntil: "load", timeout: 60_000 });
  await waitFor(() => state(pageA), 90_000, "flutter re-booted");
  await sleep(3000); // give offerRejoin its window - it must NOT fire
  const a2 = await state(pageA);
  const ok2 = a2.phase === "lobby" && (a2.rejoinRoom ?? "") === "";
  console.log("A after leave+reload:", a2.phase, ok2 ? "(stays in lobby, no prompt)" : "(rejoined!)");

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
