/**
 * e2e-wt.mjs - Word Tiles (scrabble-style) test:
 *   two players join, pick Word Tiles, ready up, start. The first seat's
 *   rack is read from the served bag; a dictionary word it can spell is
 *   played through the center star via hook, then pass-pass ends the game.
 *   Both clients must agree on the derived scores and the winner.
 *
 * Run:  mise run test-wt
 */


import { readFileSync } from "node:fs";
import {
  launchBrowser,
  launchServer,
  newPage,
  state,
  waitFor,
  sleep,
  fail,
} from "./e2e-lib.mjs";

const { server, base, room } = await launchServer("wtts");

// can the word be spelled with the multiset of rack letters?
function spellable(word, rack) {
  const letters = rack.join("").toLowerCase().split("");
  for (const ch of word.toLowerCase()) {
    const i = letters.indexOf(ch);
    if (i < 0) return false;
    letters.splice(i, 1);
  }
  return true;
}

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

  await pageA.evaluate(() => window.__boggleDebugSetMode("wordtiles"));
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
    return a.phase === "play" && a.mode === "wordtiles" &&
        b.phase === "play" && b.mode === "wordtiles" && a.wtMyRack
      ? { a, b }
      : null;
  }, 30_000, "word tiles round to start on both pages");

  // first seat plays a 3-4 letter word through the center star
  let a = await state(pageA);
  const firstPage = a.wtSeats ? (a.me === a.wtSeats[0] ? pageA : pageB) : pageA;
  const first = await state(firstPage);
  const rack = first.wtMyRack.split(",").filter(Boolean);
  const dict = readFileSync(
    new URL("../app/assets/words.txt", import.meta.url).pathname,
    "utf8",
  ).split("\n").filter(Boolean);
  const word = dict.find(
    (w) => (w.length === 3 || w.length === 4) && spellable(w, rack),
  );
  if (!word) fail("no playable word found in the served rack " + rack.join(""));
  console.log("  rack:", rack.join(","), "| playing:", word.toUpperCase());

  // place the word vertically through the center: (5,5)..(5,5+len-1)
  const tiles = [];
  for (let i = 0; i < word.length; i++) {
    tiles.push([5, 5 + i, word[i].toUpperCase()]);
  }
  await firstPage.evaluate((t) => window.__boggleDebugWtPlay(JSON.stringify(t)), tiles);
  await waitFor(async () => ((await state(firstPage))?.wtMoves === 1 ? true : null), 20_000, "play to register");
  await sleep(1200); // let it sync to the other client

  // pass-pass ends the game
  const secondPage = firstPage === pageA ? pageB : pageA;
  await secondPage.evaluate(() => window.__boggleDebugWtPass(""));
  await waitFor(async () => ((await state(firstPage))?.wtMoves === 2 ? true : null), 20_000, "pass to sync");
  await firstPage.evaluate(() => window.__boggleDebugWtPass(""));
  await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    return x.phase === "results" && y.phase === "results" ? { x, y } : null;
  }, 30_000, "pass-pass to end the game");

  // poll until both sides agree
  const settle = await waitFor(async () => {
    const x = await state(pageA);
    const y = await state(pageB);
    const seat0 = x.wtSeats[0];
    const ok =
      x.wtWinner === seat0 && y.wtWinner === seat0 &&
      x.wtScores[seat0] > 0 && y.wtScores[seat0] === x.wtScores[seat0] &&
      (x.wtScores[x.wtSeats[1]] ?? 0) === 0 &&
      JSON.stringify(x.wtScores) === JSON.stringify(y.wtScores) &&
      x.plist[x.pids.indexOf(seat0)]?.score === 1 &&
      JSON.stringify(x.plist) === JSON.stringify(y.plist);
    return ok ? { x, y, ok } : null;
  }, 30_000, "word tiles results to agree on both pages");

  const { x: wa, y: wb, ok } = settle;
  console.log("A:", JSON.stringify({ winner: wa.wtWinner, scores: wa.wtScores }));
  console.log("B:", JSON.stringify({ winner: wb.wtWinner, scores: wb.wtScores }));
  console.log(ok ? "PASS: word tiles play through the star, scores agree ✅" : "FAIL");
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
