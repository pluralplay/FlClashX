// Reading the capture behind a pane, shared by liquid_glass.frag and
// liquid_glass_flat.frag; each declares the uniforms it reads first.

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);
// Fewer taps leave a swirl over sharp text; 64 leave a faint one at 3x, too
// fine to see. A count taken from a uniform costs as much as 96 constant taps,
// so a narrower frost takes a constant count of its own, its taps no further
// apart than 64 leave those of the widest.
const int kFrostTaps = 64;
const float kGoldenAngle = 2.39996322973;
// 1.2 times the engine's kernel reach of (sigma - 0.5) * sqrt(3) pixels, which
// on a Vogel disc fits its blur best.
const float kFrostReach = 2.07846096908;
// A frost this wide in dp reads the backdrop's luma once, as a haze does.
const float kSteadyFrost = 8.0;

vec4 veiled(vec4 color) {
  return color * (1.0 - uVeil.a) + vec4(uVeil.rgb * uVeil.a, uVeil.a);
}

vec4 texel(vec2 pixel) {
  return texture(
    uTexture,
    clamp(pixel, uClamp.xy, min(uClamp.zw, uSize - 0.5)) / uSize
  );
}

vec4 sampleGlass(vec2 point) {
  return texel((point - uSample.xy) / uSample.zw);
}

#define FROST_DISC(taps)                                                     \
  float decay = exp(-falloff / float(taps));                                  \
  float weight = sqrt(decay);                                                 \
  vec2 turn = vec2(cos(kGoldenAngle), sin(kGoldenAngle));                     \
  vec2 ray = vec2(1.0, 0.0);                                                  \
  vec4 sum = vec4(0.0);                                                       \
  float total = 0.0;                                                          \
  for (int i = 0; i < taps; i++) {                                            \
    float spread = sqrt((float(i) + 0.5) / float(taps));                      \
    sum += texel(center + ray * reach * spread) * weight;                     \
    total += weight;                                                          \
    weight *= decay;                                                          \
    ray = vec2(ray.x * turn.x - ray.y * turn.y, ray.x * turn.y + ray.y * turn.x); \
  }                                                                           \
  return sum / total;

vec4 frostDisc16(vec2 center, vec2 reach, float falloff) {
  FROST_DISC(16)
}

vec4 frostDisc32(vec2 center, vec2 reach, float falloff) {
  FROST_DISC(32)
}

vec4 frostDisc64(vec2 center, vec2 reach, float falloff) {
  FROST_DISC(kFrostTaps)
}

// The engine's Gaussian of a frost sigma in device pixels, past what the
// texture holds, read on a Vogel disc.
vec4 sampleFrosted(vec2 point, float frost) {
  vec2 sigma = frost / uSample.zw;
  sigma = sqrt(max(sigma * sigma - uTexels.y * uTexels.y, vec2(0.0)));
  vec2 reach = max(sigma - 0.5, 0.0) * kFrostReach;
  if (reach.x <= 0.0 || reach.y <= 0.0) {
    return sampleGlass(point);
  }
  vec2 ratio = reach / sigma;
  float falloff = 0.5 * ratio.x * ratio.y;
  vec2 center = (point - uSample.xy) / uSample.zw;
  float widest = max(sigma.x, sigma.y);
  if (widest <= 2.0) {
    return frostDisc16(center, reach, falloff);
  }
  if (widest <= 3.5) {
    return frostDisc32(center, reach, falloff);
  }
  return frostDisc64(center, reach, falloff);
}

vec3 graded(vec3 color) {
  return mix(vec3(dot(color, kLuma)), color, uOptics.y) * uOptics.z;
}

// Each shader samples what lies behind its pane in its own way.
vec4 sampleBehind(vec2 point);

// The tint over frosted color, deepened where the backdrop clashes with it,
// premultiplied, with its coverage in alpha.
vec4 tinted(vec3 color, float alpha, vec2 halfSize) {
  float clash = 0.0;
  if (uGlow.w != 0.0) {
    vec4 behind = sampleBehind(halfSize)
        + sampleBehind(halfSize * vec2(0.4, 0.6))
        + sampleBehind(halfSize * vec2(1.6, 0.6))
        + sampleBehind(halfSize * vec2(0.4, 1.4))
        + sampleBehind(halfSize * vec2(1.6, 1.4));
    behind = veiled(behind * 0.2);
    float behindLuma = dot(behind.rgb / max(behind.a, 1e-4), kLuma);
    clash = clamp(
      (sign(uGlow.w) * (dot(uTint.rgb, kLuma) - behindLuma) - 0.3) / 0.5,
      0.0,
      1.0
    );
  }
  float cover = uTint.a + (1.0 - uTint.a) * clash * abs(uGlow.w);
  float coverage = alpha * (1.0 - cover) + cover;
  return vec4(color * alpha * (1.0 - cover) + uTint.rgb * cover, coverage);
}

float glowAt(vec2 point, float coverage) {
  vec2 toGlow = point - uGlow.xy;
  float reach = max(uGlowSpread.x * uGlowSpread.x, 1.0);
  return uGlow.z * coverage
      * mix(exp(-dot(toGlow, toGlow) / reach), 1.0, uGlowSpread.y);
}
