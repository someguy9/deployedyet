// The deploy light: a soft volumetric beam falling from above the hero, with slow drifting rays and
// fine grain. Its colour follows the hero's deploy ticker (amber building, green live, red failed), the
// menu bar's answer as atmosphere. Output is premultiplied, so where there is no light the page shows.

struct Params {
  resolution: vec2f,
  pointer: vec2f,
  tint: vec4f,
  time: f32,
  intensity: f32,
  _pad: vec2f,
}
@group(0) @binding(0) var<uniform> params: Params;

fn hash(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn vnoise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash(i);
  let b = hash(i + vec2f(1.0, 0.0));
  let c = hash(i + vec2f(0.0, 1.0));
  let d = hash(i + vec2f(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p0: vec2f) -> f32 {
  var p = p0;
  var amp = 0.5;
  var sum = 0.0;
  for (var i = 0; i < 5; i++) {
    sum += amp * vnoise(p);
    p = p * 2.03 + vec2f(1.7, 9.2);
    amp *= 0.5;
  }
  return sum;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.resolution.x / max(params.resolution.y, 1.0);
  let t = params.time;

  // Source just above the top edge. The page holds pointer at the centre, so this stays put.
  let source = vec2f(0.5 + (params.pointer.x - 0.5) * 0.18, -0.12);
  // Clamped so a portrait phone keeps a cone with dark sides instead of flooding the whole width.
  let d = (uv - source) * vec2f(max(aspect, 1.0), 1.0);
  let dist = length(d);
  let angle = atan2(d.x, max(d.y, 0.0001)); // 0 = straight down

  // Rays: angular noise, slowly drifting, so the beam has structure without moving much.
  let rays = fbm(vec2f(angle * 7.0 + t * 0.03, t * 0.05));
  let rayMask = smoothstep(0.16, 0.96, rays); // wide edges: rays read as shafts in fog, not stripes
  let cone = exp(-angle * angle * 3.2);
  let hazeCone = exp(-angle * angle * 1.8); // the fog spreads wider than the beam itself
  let falloff = 1.0 / (1.0 + dist * dist * 4.0);

  // Haze: slow fbm so the light sits in air, not on glass.
  let haze = fbm(uv * vec2f(aspect * 2.2, 2.2) + vec2f(t * 0.018, -t * 0.012));

  let tint = params.tint.rgb;

  var light = tint * cone * falloff * (0.5 + 0.5 * rayMask) * 0.5;
  light += tint * haze * falloff * hazeCone * 0.32;
  // Diffusion: a broad bloom around the source, like shooting through a diffusion filter.
  light += tint * exp(-dist * dist * 2.4) * 0.09;
  // Halation: film's faint warm fringe around bright light (red bleeding back through the base).
  light += vec3f(1.0, 0.45, 0.25) * exp(-dist * dist * 6.0) * 0.03;
  // A white-hot core right under the source keeps the colour from reading as a plain tint.
  light += vec3f(1.0) * exp(-dist * dist * 22.0) * 0.2;
  light *= params.intensity;

  // Film response: a soft shoulder, so the brightest light rolls off smoothly instead of clipping.
  light = vec3f(1.0) - exp(-light);

  // Grain: per pixel and proportional to the light, so the page stays clean; strongest in the
  // midtones and fading out of the highlights, the way film grain sits.
  let lum = max(light.r, max(light.g, light.b));
  let grain = (hash(floor(uv * params.resolution) + vec2f(t * 61.0, t * 37.0)) - 0.5) * 0.16;
  let lit = max(light * (1.0 + grain * (1.0 - lum)), vec3f(0.0));
  let alpha = clamp(max(lit.r, max(lit.g, lit.b)), 0.0, 1.0);
  return vec4f(lit, alpha);
}
