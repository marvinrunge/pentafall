shader_type spatial;
// The barbarian's Whirlwind: the air dragged round with the spin - wisps of wind on an open
// cylinder around the body, slanted like a spiral and thinning out at the bottom and the top
// so the band never shows its own edges. UV.x goes once round, UV.y from the bottom (0) to
// the top (1); `phase` turns the wisps round, the caller advancing it with the spin.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.85, 0.82, 0.75, 1.0);
uniform float phase = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 4.0) = 0.6;
uniform float cover : hint_range(0.0, 1.0) = 0.28;
// How many wisps go round, and how much they lean.
uniform float wisps = 4.0;
uniform float slant = 0.35;
// Where the band is seen edge-on - its silhouette - it fades out over this much of the turn
// away from the camera, so the cylinder never shows its own outline.
uniform float edge_fade : hint_range(0.01, 1.0) = 0.6;

// Noise that wraps at x = period, so the cylinder has no seam where UV.x goes from 1 to 0.
float wrapped_noise(vec2 p, float period) {
	return mix(noise(p), noise(p - vec2(period, 0.0)), p.x / period);
}

void fragment() {
	float y = UV.y;
	float x = fract(UV.x + phase + y * slant) * wisps;
	// Long and thin: slow along the turn, quick up the band - streaks of moving air.
	float n = wrapped_noise(vec2(x, y * 6.0), wisps) * 0.7
		+ wrapped_noise(vec2(x * 2.0, y * 11.0 + 7.0), wisps * 2.0) * 0.3;
	float wisp = smoothstep(0.5, 0.82, n);
	float vertical = smoothstep(0.0, 0.4, y) * (1.0 - smoothstep(0.5, 1.0, y));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = clamp(wisp * vertical * smoothstep(0.0, edge_fade, facing) * intensity, 0.0, 1.0);
	ALBEDO = tint.rgb * energy * a;
	ALPHA = a * cover;
}
