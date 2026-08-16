/**
 * e2e-sketch.mjs - SketchIt (pictionary) round test:
 *   two players join, pick SketchIt, ready up, start. The drawer (first
 *   player) draws real strokes on the canvas; the guesser submits a wrong
 *   guess then the right one. Both sides must agree on the solved word and
 *   the drawer+guesser scoring.
 *
 * Run:  mise run test-sketch
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

const { server, base, room } = await launchServer("skch");

let browserA, browserB;
try {
  browserA = await launchBrowser();
  browserB = await launchBrowser();
  const pageA = await (await browserA.newContext({ viewport: { width: 960, height: 600 } })).newPage();
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

  // the play navbar shows the room context and the how-to guide
  await waitFor(async () =>
    ((await drawerPage.getByText(new RegExp(`ROOM ${room} · 2 players`)).count()) > 0 ? true : null),
  15_000, "play navbar with room + players");
  await drawerPage.getByText("How to play").click();
  await waitFor(async () =>
    ((await drawerPage.getByText(/HOW TO PLAY:/).count()) > 0 ? true : null),
  10_000, "how-to dialog");
  await drawerPage.getByText("DONE", { exact: true }).click();
  await sleep(300);

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
