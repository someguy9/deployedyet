// Renders the hero's deploy light headlessly (vgpu + Dawn) to PNGs, one per state, composited over the
// page colour. Browser screenshots can't see WebGPU canvases, so this is how the shader gets reviewed.
// Run: node scripts/render-light.mjs <out-dir> [width height]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { init, effect, target } from "vgpu/node";
import { prepareShader } from "@vgpu/wgsl/prepare";

const out = process.argv[2] ?? ".";
mkdirSync(out, { recursive: true });
const source = prepareShader(readFileSync(new URL("../src/lib/light.wgsl", import.meta.url), "utf8"), "light.wgsl");
const [W, H] = [Number(process.argv[3] ?? 1280), Number(process.argv[4] ?? 800)]; // optional size, e.g. 1200 630 for og.png
const PAGE = [11, 12, 15]; // --color-paper, #0b0c0f: the site's real near-black
const TINTS = { building: [1, 0.68, 0.3], live: [0.34, 0.92, 0.55], failed: [1, 0.38, 0.32] };

function png(width, height, rgba) {
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) { raw[y * (width * 4 + 1)] = 0; rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4); }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

const gpu = await init();
try {
  const fx = effect(gpu, source);
  const tgt = target(gpu, { size: [W, H] });
  for (const [name, tint] of Object.entries(TINTS)) {
    fx.set({ params: { resolution: [W, H], pointer: [0.5, 0.3], tint: [...tint, 1], time: 4.2, intensity: 1, _pad: [0, 0] } }).draw(tgt);
    const px = Buffer.from(await tgt.color.read({ mipLevel: 0, region: "all" })); // RGBA8, premultiplied
    for (let i = 0; i < px.length; i += 4) { // premultiplied light over the page
      const a = px[i + 3] / 255;
      for (let c = 0; c < 3; c++) px[i + c] = Math.min(255, px[i + c] + PAGE[c] * (1 - a));
      px[i + 3] = 255;
    }
    writeFileSync(`${out}/light-${name}.png`, png(W, H, px));
    console.log("wrote", `${out}/light-${name}.png`);
  }
  await gpu.settled();
} finally {
  gpu.dispose();
}
