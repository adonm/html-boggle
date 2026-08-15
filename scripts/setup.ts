/**
 * setup.ts - fetch and cache everything the build needs (one-time, idempotent):
 *   .cache/raylib/        raylib 5.5 webassembly lib + headers (official release zip)
 *   .cache/bin/wasm-bindgen  wasm-bindgen-cli matching net/Cargo.toml
 *   .cache/words.txt      public-domain word list, filtered to 3..16 lowercase letters
 *
 * Everything is extracted with pure Deno code (no unzip/tar dependency).
 */

const CACHE = new URL("../.cache/", import.meta.url);
const RAYLIB_ZIP =
  "https://github.com/raysan5/raylib/releases/download/5.5/raylib-5.5_webassembly.zip";
const WASM_BINDGEN_VERSION = "0.2.122";
const WORDS_URL = "https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt";

async function download(url: string): Promise<Uint8Array> {
  console.log("downloading", url);
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

/* ------------------------- minimal zip extraction ------------------------- */

function findSig(data: Uint8Array, sig: number[], from: number): number {
  outer: for (let i = from; i >= 0; i--) {
    for (let j = 0; j < sig.length; j++) if (data[i + j] !== sig[j]) continue outer;
    return i;
  }
  return -1;
}

async function inflateRaw(compressed: Uint8Array): Promise<Uint8Array> {
  const ds = new DecompressionStream("deflate-raw");
  const stream = new Blob([new Uint8Array(compressed)]).stream().pipeThrough(ds);
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

interface ZipEntry {
  name: string;
  offset: number;
  size: number;
  csize: number;
  method: number;
}

async function extractZip(data: Uint8Array, outDir: URL): Promise<void> {
  const eocd = findSig(data, [0x50, 0x4b, 0x05, 0x06], data.length - 22);
  if (eocd < 0) throw new Error("zip: EOCD not found");
  const view = new DataView(data.buffer, data.byteOffset);
  const count = view.getUint16(eocd + 10, true);
  let cd = view.getUint32(eocd + 16, true);

  const entries: ZipEntry[] = [];
  for (let i = 0; i < count; i++) {
    if (view.getUint32(cd, true) !== 0x02014b50) throw new Error("zip: bad central directory");
    const method = view.getUint16(cd + 10, true);
    const csize = view.getUint32(cd + 20, true);
    const size = view.getUint32(cd + 24, true);
    const nameLen = view.getUint16(cd + 28, true);
    const extraLen = view.getUint16(cd + 30, true);
    const commentLen = view.getUint16(cd + 32, true);
    const offset = view.getUint32(cd + 42, true);
    const name = new TextDecoder().decode(data.subarray(cd + 46, cd + 46 + nameLen));
    entries.push({ name, offset, size, csize, method });
    cd += 46 + nameLen + extraLen + commentLen;
  }

  for (const e of entries) {
    if (e.name.endsWith("/")) continue;
    // local file header: 30 bytes + name + extra
    const nameLen = view.getUint16(e.offset + 26, true);
    const extraLen = view.getUint16(e.offset + 28, true);
    const dataStart = e.offset + 30 + nameLen + extraLen;
    const raw = data.subarray(dataStart, dataStart + e.csize);
    const content = e.method === 0 ? raw : await inflateRaw(raw);
    const path = new URL(e.name.replace(/^raylib-5\.5_webassembly\//, ""), outDir);
    await Deno.mkdir(new URL(".", path), { recursive: true });
    await Deno.writeFile(path, content);
  }
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

async function ensureRaylib(): Promise<void> {
  const out = new URL("raylib/", CACHE);
  if (await exists(new URL("raylib/include/raylib.h", CACHE))) {
    console.log("raylib already cached");
    return;
  }
  const zip = await download(RAYLIB_ZIP);
  await extractZip(zip, out);
  console.log("raylib ready at", out.pathname);
}

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
    .filter((w) => /^[a-z]{3,16}$/.test(w));
  await Deno.writeFile(out, new TextEncoder().encode(lines.join("\n") + "\n"));
  console.log(
    `words.txt ready: ${lines.length} words (${lines.join("").length / 1024 / 1024} MB text)`,
  );
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
  await ensureRaylib();
  await ensureWasmBindgen();
  await ensureWords();

  // Sanity check the emscripten toolchain (provided by mise).
  const p = new Deno.Command("emcc", { args: ["--version"], stdout: "piped" });
  const res = await p.output();
  console.log("---");
  console.log(new TextDecoder().decode(res.stdout).split("\n")[0] ?? "emcc not found!");
  if (!res.success) throw new Error("emcc not on PATH - run this through `mise run setup`");
  console.log("setup complete");
}

if (import.meta.main) await main();
