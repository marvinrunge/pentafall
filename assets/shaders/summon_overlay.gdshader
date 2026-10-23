shader_type spatial;
// A summon taking shape (SummonFx.arrive): laid as the material_overlay of the creature's own
// meshes for the second it arrives. A band of light climbs the body from the feet to the head
// as `progress` runs 0 -> 1 - the body below it already made, a glow above it still forming -
// and everything fades with `fade` once it stands there. One shader for every summon; the
// tint is the summon's (moss green for a golem, violet for the raised dead, ...).
//
// The band is in metres of world height above the creature's feet (`base_y`, `height`), so a
// 2.8 m golem and a 1.5 m beast take the same time and look the same.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.5, 0.95, 0.4);
uniform float progress : hint_range(0.0, 1.2) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float base_y = 0.0;
uniform float height = 2.0;
uniform float band = 0.22;

varying float v_height;

#include "res://assets/shaders/noise.gdshaderinc"

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float h = (v_height - base_y) / max(height, 0.01);
	float front = progress * 1.1;
	// The band itself, ragged with noise so it reads as forming rather than as a scan line.
	float ragged = (noise(UV * 18.0 + vec2(TIME * 0.7)) - 0.5) * 0.08;
	float d = h - front + ragged;
	float edge = 1.0 - smoothstep(0.0, band, abs(d));
	// Above the band: still forming, a faint glow. Below: made, nothing.
	float above = smoothstep(0.0, 0.05, d) * 0.45;
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float a = clamp(edge * 0.95 + above * (0.4 + fresnel * 0.6), 0.0, 1.0) * (1.0 - fade);
	ALBEDO = mix(tint, vec3(1.0), edge * 0.5) * (1.4 + edge * 1.6);
	ALPHA = a;
}
