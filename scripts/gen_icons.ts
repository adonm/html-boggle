/**
 * gen_icons.ts - render the Huddle mark (2x2 rounded tiles) as PNG icons
 * for the web manifest + favicon. Pure Deno: a minimal PNG encoder (RGBA,
 * zlib via CompressionStream) and a rounded-rect coverage test with 3x3
 * supersampling for antialiasing. Run: deno run -A scripts/gen_icons.ts
 */

const BRAND = [
  [0xE9, 0x54, 0x20], // orange
  [0x21, 0x96, 0xF3], // blue
  [0x4C, 0xAF, 0x50], // green
  [0x9C, 0x27, 0xB0], // purple
];

/** signed distance of a rounded square centered at (cx, cy) */
function sdRoundBox(x: number, y: number, cx: number, cy: number, half: number, r: number) {
  const qx = Math.abs(x - cx) - (half - r);
  const qy = Math.abs(y - cy) - (half - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - r + Math.min(Math.max(qx, qy), 0);
}

/** coverage of the 2x2 huddle block at pixel (x, y) in [size] space */
function blockCoverage(x: number, y: number, size: number, block: number, gap: number): number {
  const half = (block - gap) / 2;
  const origin = (size - block) / 2;
  const outer = block * 0.14;
  const inner = block * 0.035;
  let cov = 0;
  for (const [tx, ty] of [
    [0, 0],
    [1, 0],
    [0, 1],
    [1, 1],
  ]) {
    const cx = origin + tx * (half + gap) + half / 2;
    const cy = origin + ty * (half + gap) + half / 2;
    const r = (tx === 0 && ty === 0) || (tx === 1 && ty === 1) ? outer : inner;
    // smooth edge over 1.5px
    const d = sdRoundBox(x, y, cx, cy, half / 2, r);
    cov = Math.max(cov, Math.min(1, Math.max(0, 0.5 - d / 1.5)));
  }
  return cov;
}

/** color at (x, y) for a given pixel size */
function pixelColor(x: number, y: number, size: number, darkBg: boolean): [number, number, number, number] {
  const tile = 0.74;
  const gap = 0.06;
  const block = size * tile;
  // supersample 3x3
  let r = 0, g = 0, b = 0, a = 0;
  for (let sy = 0; sy < 3; sy++) {
    for (let sx = 0; sx < 3; sx++) {
      const cov = blockCoverage(x + (sx + 0.5) / 3, y + (sy + 0.5) / 3, size, block, size * gap);
      if (cov <= 0) continue;
      const half = (block - size * gap) / 2;
      const origin = (size - block) / 2;
      const qx = Math.floor((x - origin) / (half + size * gap));
      const qy = Math.floor((y - origin) / (half + size * gap));
      const idx = Math.min(3, Math.max(0, qy * 2 + qx));
      const shade = 0.78 + 0.22 * Math.min(1, Math.max(0, 0.5 + (x + y) / (size * 2.2) - 0.35));
      r += BRAND[idx][0] * shade * cov;
      g += BRAND[idx][1] * shade * cov;
      b += BRAND[idx][2] * shade * cov;
      a += cov;
    }
  }
  const n = 9;
  if (darkBg) {
    // dark background behind the mark
    const over = a / n;
    return [
      Math.round(r / n + 0x24 * (1 - over)),
      Math.round(g / n + 0x24 * (1 - over)),
      Math.round(b / n + 0x24 * (1 - over)),
      255,
    ];
  }
  return [
    Math.round(r / n),
    Math.round(g / n),
    Math.round(b / n),
    Math.round((a / n) * 255),
  ];
}

// ------------------------------------------------------------------- PNG

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length);
  const dv = new DataView(out.buffer);
  dv.setUint32(0, data.length);
  for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
  out.set(data, 8);
  dv.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}

async function encodePng(size: number, darkBg: boolean): Promise<Uint8Array> {
  // RGBA scanlines with filter byte 0
  const raw = new Uint8Array(size * (size * 4 + 1));
  let o = 0;
  for (let y = 0; y < size; y++) {
    raw[o++] = 0;
    for (let x = 0; x < size; x++) {
      const [r, g, b, a] = pixelColor(x, y, size, darkBg);
      raw[o++] = r;
      raw[o++] = g;
      raw[o++] = b;
      raw[o++] = a;
    }
  }
  // CompressionStream('deflate') in Deno emits a complete zlib stream
  // (header + deflate + adler32), so no wrapping is needed.
  const zlib = new Uint8Array(
    await new Response(
      new Blob([raw]).stream().pipeThrough(new CompressionStream("deflate")),
    ).arrayBuffer(),
  );

  const ihdr = new Uint8Array(13);
  const h = new DataView(ihdr.buffer);
  h.setUint32(0, size);
  h.setUint32(4, size);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const out = new Uint8Array(8 + 25 + 12 + zlib.length + 12);
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  out.set(sig, 0);
  let p = 8;
  const ihdrChunk = chunk("IHDR", ihdr);
  out.set(ihdrChunk, p);
  p += ihdrChunk.length;
  const idatChunk = chunk("IDAT", zlib);
  out.set(idatChunk, p);
  p += idatChunk.length;
  out.set(chunk("IEND", new Uint8Array(0)), p);
  return out;
}

// ------------------------------------------------------------------ write

const web = new URL("../app/web/", import.meta.url);

async function write(name: string, size: number, darkBg: boolean) {
  const bytes = await encodePng(size, darkBg);
  await Deno.writeFile(new URL(name, web), bytes);
  console.log(`${name}  ${size}x${size}  ${bytes.length} bytes`);
}

await write("favicon.png", 32, true);
await write("icons/Icon-192.png", 192, false);
await write("icons/Icon-512.png", 512, false);
await write("icons/Icon-maskable-192.png", 192, true);
await write("icons/Icon-maskable-512.png", 512, true);
