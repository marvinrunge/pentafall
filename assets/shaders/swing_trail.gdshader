shader_type spatial;
// A melee swing's trail (SwingTrail): a ribbon from the grip (UV.y 0) to the blade's tip
// (UV.y 1), its age in COLOR.a (1 new, 0 gone). Premultiplied like the rest of the effect
// layer, and soft on every side: it thins out towards the grip, the tip and its own tail.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.92, 0.9, 0.85, 1.0);
uniform float energy : hint_range(0.0, 4.0) = 1.1;
uniform float cover : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float life = COLOR.a;
	float along = UV.y;
	float profile = smoothstep(0.25, 0.75, along) * (1.0 - smoothstep(0.92, 1.0, along));
	float a = clamp(life * life * profile, 0.0, 1.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), 0.4 * life) * energy * a;
	ALPHA = a * cover;
}
