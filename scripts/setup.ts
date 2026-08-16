/**
 * setup.ts - fetch and cache everything the build needs (one-time, idempotent):
 *   .cache/bin/wasm-bindgen  wasm-bindgen-cli matching net/Cargo.toml
 *   .cache/words.txt      public-domain word list, filtered to 2..16 lowercase letters
 *
 * Everything is extracted with pure Deno code (no unzip/tar dependency).
 */

const CACHE = new URL("../.cache/", import.meta.url);
const WASM_BINDGEN_VERSION = "0.2.122";
const WORDS_URL = "https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt";

async function download(url: string): Promise<Uint8Array> {
  console.log("downloading", url);
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

/* ------------------------ minimal tar.gz extraction ------------------------ */

async function extractTarGz(
  data: Uint8Array,
  outDir: URL,
  pick: (name: string) => boolean,
): Promise<void> {
  const ds = new DecompressionStream("gzip");
  const stream = new Blob([new Uint8Array(data)]).stream().pipeThrough(ds);
  const tar = new Uint8Array(await new Response(stream).arrayBuffer());
  let off = 0;
  while (off + 512 <= tar.length) {
    if (tar[off] === 0 && tar[off + 100] === 0) break; // zero block
    const name = new TextDecoder().decode(
      tar.subarray(off, off + 100),
    ).replace(/\0.*$/, "");
    const sizeStr = new TextDecoder().decode(tar.subarray(off + 124, off + 136)).replace(
      /\0.*$/,
      "",
    );
    const size = parseInt(sizeStr, 8);
    const dataStart = off + 512;
    if (name && size > 0 && pick(name)) {
      const base = name.split("/").pop() ?? name;
      const path = new URL(base, outDir);
      await Deno.mkdir(new URL(".", path), { recursive: true });
      await Deno.writeFile(path, tar.subarray(dataStart, dataStart + size));
    }
    off = dataStart + Math.ceil(size / 512) * 512;
  }
}

/* --------------------------------- steps ---------------------------------- */

function bindgenTarget(): string {
  const { os, arch } = Deno.build;
  if (os === "linux" && arch === "x86_64") return "x86_64-unknown-linux-musl";
  if (os === "darwin" && arch === "aarch64") return "aarch64-apple-darwin";
  if (os === "darwin" && arch === "x86_64") return "x86_64-apple-darwin";
  if (os === "windows" && arch === "x86_64") return "x86_64-pc-windows-msvc";
  throw new Error(`no prebuilt wasm-bindgen for ${os}/${arch}`);
}

async function ensureWasmBindgen(): Promise<void> {
  const bin = new URL(`bin/wasm-bindgen${Deno.build.os === "windows" ? ".exe" : ""}`, CACHE);
  if (await exists(bin)) {
    console.log("wasm-bindgen already cached");
    return;
  }
  const target = bindgenTarget();
  const url =
    `https://github.com/rustwasm/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}/` +
    `wasm-bindgen-${WASM_BINDGEN_VERSION}-${target}.tar.gz`;
  const tarball = await download(url);
  await extractTarGz(
    tarball,
    new URL("bin/", CACHE),
    (name) => name.endsWith("/wasm-bindgen") || name.endsWith("/wasm-bindgen.exe"),
  );
  await Deno.chmod(bin, 0o755);
  console.log("wasm-bindgen ready at", bin.pathname);
}

async function ensureWords(): Promise<void> {
  const out = new URL("words.txt", CACHE);
  if (await exists(out)) {
    console.log("words.txt already cached");
    return;
  }
  const raw = new TextDecoder().decode(await download(WORDS_URL));
  const lines = raw
    .split("\n")
    .map((w) => w.trimEnd())
    .filter((w) => /^[a-z]{2,16}$/.test(w));
  await Deno.writeFile(out, new TextEncoder().encode(lines.join("\n") + "\n"));
  console.log(`words.txt ready: ${lines.length} words`);
}

async function exists(path: URL): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  await Deno.mkdir(CACHE, { recursive: true });
  await ensureWasmBindgen();
  await ensureWords();

  // Sanity check the flutter toolchain (provided by mise).
  const p = new Deno.Command("flutter", { args: ["--version"], stdout: "piped" });
  const res = await p.output();
  console.log("---");
  console.log(new TextDecoder().decode(res.stdout).split("\n")[0] ?? "flutter not found!");
  if (!res.success) throw new Error("flutter not on PATH - run this through `mise run setup`");
  console.log("setup complete");
}

if (import.meta.main) await main();
