shader_type spatial;
// Banishing Light: a hexagonal prism of light sealed round an enemy (EnemyStateFx.banished).
// The faces are nearly clear, the edges where they meet burn bright, bands of light climb the
// faces, and the whole prism thins out into light at the top and the bottom - no hard rim
// anywhere (the effect layer's rule). Premultiplied like the rest of the layer, so it reads
// against the noon sky as well as by night.
//
// UV.x runs 0..1 across EACH face (EnemyStateFx builds it so), UV.y 0..1 up the prism.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float energy = 2.2;
// 0 sealed, 1 gone: drives the prism rising out of the ground and dissolving away.
uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = 1.0 - smoothstep(0.0, 0.07, min(UV.x, 1.0 - UV.x));
	float band = smoothstep(0.8, 1.0, sin(UV.y * 22.0 - TIME * 3.0) * 0.5 + 0.5);
	// Thinning into light at both ends instead of stopping at a cut.
	float ends = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.62, 1.0, UV.y));
	float a = (edge * 0.85 + band * 0.25 + 0.07) * ends * (1.0 - fade);
	vec3 c = mix(tint.rgb, vec3(1.0), edge * 0.6) * energy;
	ALBEDO = c * a;
	ALPHA = a;
}
