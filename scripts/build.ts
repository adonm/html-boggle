/**
 * build.ts - assemble dist/:
 *   1. boggle_net: Rust iroh gossip crate -> wasm32-unknown-unknown -> wasm-bindgen (web target)
 *   2. boggle_game: raylib C game -> emcc -> index.html + index.js + index.wasm
 *   3. static: glue.js + vendored sha256.js
 */

const ROOT = new URL("..", import.meta.url);
const DIST = new URL("../dist/", import.meta.url);
const RAYLIB = new URL("../.cache/raylib/", import.meta.url);

async function run(cmd: string[], cwd: URL = ROOT): Promise<void> {
  console.log("$", cmd.join(" "));
  const p = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    cwd,
    stdout: "inherit",
    stderr: "inherit",
  });
  const status = await p.output();
  if (!status.success) throw new Error(`command failed: ${cmd.join(" ")}`);
}

async function optionalRun(cmd: string[], cwd: URL = ROOT): Promise<void> {
  try {
    await run(cmd, cwd);
  } catch {
    console.warn("(non-fatal) skipped:", cmd.join(" "));
  }
}

async function buildNet(): Promise<void> {
  await run(["cargo", "build", "--release", "--target", "wasm32-unknown-unknown",
    "--manifest-path", "net/Cargo.toml"]);
  await Deno.mkdir(new URL("net/", DIST), { recursive: true });
  await run([new URL("../.cache/bin/wasm-bindgen", import.meta.url).pathname,
    "--target", "web", "--out-dir", new URL("net/", DIST).pathname,
    "net/target/wasm32-unknown-unknown/release/boggle_net.wasm"]);
  // Shrink with binaryen (ships with emsdk); non-fatal if unavailable.
  await optionalRun(["wasm-opt", "-O2", "--enable-bulk-memory",
    new URL("net/boggle_net_bg.wasm", DIST).pathname, "-o",
    new URL("net/boggle_net_bg.wasm", DIST).pathname]);
}

async function buildClient(): Promise<void> {
  await run([
    "emcc",
    "-o", new URL("index.html", DIST).pathname,
    "client/main.c",
    new URL("lib/libraylib.a", RAYLIB).pathname,
    `-I${new URL("include", RAYLIB).pathname}`,
    "-DPLATFORM_WEB",
    "-sUSE_GLFW=3",
    "-sASYNCIFY",
    "-sFORCE_FILESYSTEM=1",
    "-sALLOW_MEMORY_GROWTH=1",
    "-sINITIAL_MEMORY=67108864",
    "-sGL_ENABLE_GET_PROC_ADDRESS=1",
    "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,UTF8ToString",
    "-sEXPORTED_FUNCTIONS=_main,_boggle_on_event,_boggle_set_board,_boggle_dbg",
    "-sENVIRONMENT=web",
    "--embed-file", ".cache/words.txt@/words.txt",
    "--shell-file", "client/shell.html",
    "-O2",
    "-Wall",
  ]);
}

async function copyStatic(): Promise<void> {
  await Deno.copyFile(new URL("../glue/glue.js", import.meta.url), new URL("glue.js", DIST));
  await Deno.copyFile(new URL("../glue/sha256.js", import.meta.url), new URL("sha256.js", DIST));
}

export async function build(): Promise<void> {
  await Deno.mkdir(DIST, { recursive: true });
  await buildNet();
  await buildClient();
  await copyStatic();
  console.log("build complete ->", DIST.pathname);
}

if (import.meta.main) await build();
