/**
 * build.ts - assemble dist/:
 *   1. boggle_net: Rust iroh gossip crate -> wasm32-unknown-unknown -> wasm-bindgen (web target)
 *   2. boggle_app: Flutter web app (Yaru themed) -> app/build/web
 *   3. static: glue.js (JS bridge between Flutter and the iroh wasm)
 */

const ROOT = new URL("..", import.meta.url);
const DIST = new URL("../dist/", import.meta.url);
const APP = new URL("../app/", import.meta.url);
const APP_WEB = new URL("build/web/", APP);

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

async function buildNet(): Promise<void> {
  await run([
    "cargo",
    "build",
    "--release",
    "--target",
    "wasm32-unknown-unknown",
    "--manifest-path",
    "net/Cargo.toml",
  ]);
  await Deno.mkdir(new URL("net/", DIST), { recursive: true });
  await run([
    new URL("../.cache/bin/wasm-bindgen", import.meta.url).pathname,
    "--target",
    "web",
    "--out-dir",
    new URL("net/", DIST).pathname,
    "net/target/wasm32-unknown-unknown/release/boggle_net.wasm",
  ]);
}

async function genWordsAsset(): Promise<void> {
  // The word list is an app asset; words_alpha.txt is NOT sorted, so sort it
  // here (the game binary-searches the dictionary).
  const words = (await Deno.readTextFile(new URL("../.cache/words.txt", import.meta.url).pathname))
    .split("\n")
    .map((w) => w.trimEnd())
    .filter((w) => /^[a-z]{3,16}$/.test(w))
    .sort();
  await Deno.writeTextFile(new URL("assets/words.txt", APP), words.join("\n") + "\n");
  console.log(`words asset: ${words.length} words`);
}

async function buildFlutter(): Promise<void> {
  await run(["flutter", "build", "web", "--release"], APP);
}

async function copyDir(src: URL, dst: URL): Promise<void> {
  for await (const entry of Deno.readDir(src)) {
    const s = new URL(entry.name, ensureSlash(src));
    const d = new URL(entry.name, ensureSlash(dst));
    if (entry.isDirectory) {
      await Deno.mkdir(d, { recursive: true });
      await copyDir(s, d);
    } else if (entry.isFile) {
      await Deno.copyFile(s, d);
    }
  }
}

function ensureSlash(u: URL): URL {
  return u.pathname.endsWith("/") ? u : new URL(u.pathname + "/", u);
}

export async function build(): Promise<void> {
  await Deno.remove(DIST, { recursive: true }).catch(() => {});
  await Deno.mkdir(DIST, { recursive: true });
  await buildNet();
  await genWordsAsset();
  await buildFlutter();
  await copyDir(APP_WEB, DIST);
  await Deno.copyFile(new URL("../glue/glue.js", import.meta.url), new URL("glue.js", DIST));
  // GitHub Pages runs Jekyll over the artifact by default; .nojekyll opts out.
  await Deno.writeFile(new URL(".nojekyll", DIST), new Uint8Array(0));
  // Custom domain: must live INSIDE the published artifact, or workflow
  // deploys would drop the boggle.adonm.dev binding.
  await Deno.writeFile(new URL("CNAME", DIST), new TextEncoder().encode("boggle.adonm.dev\n"));
  console.log("build complete ->", DIST.pathname);
}

if (import.meta.main) await build();
