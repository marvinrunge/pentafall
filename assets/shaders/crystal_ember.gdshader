shader_type spatial;
// A spark rising off the base crystal (CrystalMotes): a thin hard line with a hot head, on the
// two crossed quads of SpellFx.streak_mesh, laid along the way it flies (particle_flag_align_y)
// - the sparks coming off the crystal on the title art, in the colour the particle was born with.
//
// Sharp across, not a soft smear: the line is solid through its middle and gone a few pixels
// out. Along it, the head (UV.y 0, the way it travels) is the brightest part and the tail thins
// into nothing, so neither end stops in a cut.
//
// Premultiplied, like the effect layer (docs/SPELL_VFX_PLAN.md): ALBEDO is the light it adds,
// ALPHA how much of what is behind it it covers. COLOR.a is the particle's fade over its life.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// How much of the background a spark covers, relative to the light it adds.
uniform float cover : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float across = 1.0 - smoothstep(0.1, 0.55, abs(UV.x * 2.0 - 1.0));
	float along = smoothstep(0.0, 0.06, UV.y) * pow(1.0 - UV.y, 1.6);
	float amount = across * along * COLOR.a;
	ALBEDO = COLOR.rgb * amount;
	ALPHA = clamp(amount * cover, 0.0, 1.0);
}
