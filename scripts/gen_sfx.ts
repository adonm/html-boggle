/**
 * gen_sfx.ts - synthesize the game's sound effects as small WAV files into
 * app/assets/sfx/. Pure Deno: sines + envelopes, no external assets, no
 * licensing concerns. Run: deno run -A scripts/gen_sfx.ts
 */

const SR = 22050;

function wav(samples: Float64Array): Uint8Array {
  const n = samples.length;
  const data = new DataView(new ArrayBuffer(44 + n * 2));
  const writeStr = (off: number, s: string) => {
    for (let i = 0; i < s.length; i++) data.setUint8(off + i, s.charCodeAt(i));
  };
  writeStr(0, "RIFF");
  data.setUint32(4, 36 + n * 2, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  data.setUint32(16, 16, true);
  data.setUint16(20, 1, true); // PCM
  data.setUint16(22, 1, true); // mono
  data.setUint32(24, SR, true);
  data.setUint32(28, SR * 2, true);
  data.setUint16(32, 2, true);
  data.setUint16(34, 16, true);
  writeStr(36, "data");
  data.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    data.setInt16(44 + i * 2, Math.round(v * 32767), true);
  }
  return new Uint8Array(data.buffer);
}

/** sum of tones: each [freqHz, startSec, durSec, gain] */
function tones(
  parts: [number, number, number, number][],
  dur: number,
): Float64Array {
  const n = Math.floor(SR * dur);
  const out = new Float64Array(n);
  for (const [f, t0, d, g] of parts) {
    const start = Math.floor(t0 * SR);
    const len = Math.floor(d * SR);
    for (let i = 0; i < len; i++) {
      const t = i / SR;
      const env = Math.min(1, t / 0.008) * Math.exp(-t * (d > 0.2 ? 6 : 14));
      const sweep = f * (1 + t * (d > 0.15 ? -0.15 : 0));
      out[start + i] += g * env * Math.sin(2 * Math.PI * sweep * t);
    }
  }
  return out;
}

const files: [string, Float64Array][] = [
  // round start: two rising notes
  ["start", tones([[392, 0, 0.12, 0.5], [523, 0.09, 0.22, 0.6]], 0.34)],
  // stone / chess move: woodblock-ish
  ["tick", tones([[900, 0, 0.05, 0.9], [1200, 0.002, 0.03, 0.4]], 0.07)],
  // ui tap
  ["tap", tones([[500, 0, 0.03, 0.5]], 0.05)],
  // word accepted / correct guess
  ["success", tones([[660, 0, 0.09, 0.6], [880, 0.07, 0.2, 0.6]], 0.3)],
  // reject / invalid
  ["fail", tones([[220, 0, 0.09, 0.7], [180, 0.07, 0.12, 0.6]], 0.22)],
  // game won: arpeggio
  ["win", tones([[523, 0, 0.12, 0.5], [659, 0.09, 0.12, 0.5], [784, 0.18, 0.12, 0.5], [1047, 0.27, 0.3, 0.6]], 0.6)],
  // round over (timeout)
  ["end", tones([[392, 0, 0.16, 0.6], [311, 0.15, 0.28, 0.6]], 0.45)],
];

for (const [name, samples] of files) {
  await Deno.writeFile(
    new URL(`../app/assets/sfx/${name}.wav`, import.meta.url),
    wav(samples),
  );
  console.log(`${name}.wav  ${(samples.length / SR).toFixed(2)}s`);
}
