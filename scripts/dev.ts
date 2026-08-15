/**
 * dev.ts - build once, serve dist/, rebuild on source changes.
 */

import { build } from "./build.ts";

const ROOT = new URL("..", import.meta.url);

console.log("building...");
await build();

const server = new Deno.Command("deno", {
  args: ["run", "-A", "--watch=server/main.ts", "server/main.ts"],
  cwd: ROOT,
  stdout: "inherit",
  stderr: "inherit",
});

const proc = server.spawn();

let timer: ReturnType<typeof setTimeout> | undefined;
let building = false;

async function scheduleRebuild(path: string) {
  if (timer) clearTimeout(timer);
  timer = setTimeout(async () => {
    if (building) return;
    building = true;
    console.log(`\n[dev] change in ${path} - rebuilding...`);
    try {
      await build();
    } catch (err) {
      console.error("[dev] rebuild failed:", err);
    }
    building = false;
  }, 300);
}

const watchers = ["glue", "net/src", "app/lib", "app/web", "app/assets"].map((dir) => ({
  dir,
  watcher: Deno.watchFs(new URL(`../${dir}/`, import.meta.url).pathname, { recursive: true }),
}));

const watchLoops = watchers.map(async ({ dir, watcher }) => {
  for await (const event of watcher) {
    if (event.kind === "access") continue;
    for (const p of event.paths) scheduleRebuild(p);
    void dir;
  }
});

console.log(`[dev] serving http://localhost:${Deno.env.get("PORT") ?? 8000}`);
await Promise.race([
  proc.status,
  Promise.all(watchLoops),
]);
