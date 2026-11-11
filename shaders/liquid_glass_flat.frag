#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// liquid_glass.frag for a pane that only frosts, tints and glows, with its
// bend, rim, line, haze and parting all at zero, drawing the same. The large
// shader's registers left a phone's GPU too few threads to hide its reads.
// The uniforms are liquid_glass.frag's, less those such a pane leaves at zero.
uniform vec2 uSize;
uniform vec4 uFrame;
uniform vec4 uSample;
uniform vec4 uClamp;
uniform vec2 uTexels;
uniform vec4 uVeil;
uniform vec4 uShape;
uniform vec3 uOptics;
uniform vec4 uTint;
uniform vec4 uGlow;
uniform vec2 uGlowSpread;
uniform sampler2D uTexture;

out vec4 fragColor;

#include "liquid_glass_frost.glsl"

vec4 sampleBehind(vec2 point) {
  if (uShape.w >= kSteadyFrost) {
    return sampleGlass(point);
  }
  vec2 spread = vec2(uShape.w, -uShape.w);
  return 0.25 * (sampleGlass(point + spread.xx)
      + sampleGlass(point + spread.yy)
      + sampleGlass(point + spread.xy)
      + sampleGlass(point + spread.yx));
}

void main() {
  vec2 point = uFrame.xy + FlutterFragCoord().xy * uFrame.zw;
  vec2 halfSize = uShape.xy * 0.5;
  vec4 base = veiled(sampleFrosted(point, uShape.w));
  float alpha = base.a;
  vec3 color = base.rgb / max(alpha, 1e-4);
  color = graded(color);

  vec4 tint = tinted(color, alpha, halfSize);
  vec3 glass = tint.rgb;
  float coverage = tint.a;

  glass += glowAt(point, coverage);

  fragColor = vec4(min(glass, vec3(coverage)), coverage);
}
