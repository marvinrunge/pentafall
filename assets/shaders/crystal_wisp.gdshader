shader_type spatial;
// A thread of mana circling the base crystal (CrystalMotes): a comet on a particle trail
// (RibbonTrailMesh), brightest at its head and thinning along its tail into nothing.
//
// A thin hard line across like the sparks, so it reads as a streak of light rather than a soft
// band. UV.y runs along the trail, 1 at the particle; UV.x across it.
//
// Premultiplied, like the effect layer (docs/SPELL_VFX_PLAN.md): ALBEDO is the light it adds,
// ALPHA how much of what is behind it it covers. COLOR.a is the particle's fade over its life.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, particle_trails;

// How much of the background a thread covers, relative to the light it adds.
uniform float cover : hint_range(0.0, 1.0) = 0.85;
// Brightness of the light it adds; a thread is thinner than a spark and needs more of it.
uniform float energy = 1.6;

void fragment() {
	float across = 1.0 - smoothstep(0.1, 0.6, abs(UV.x * 2.0 - 1.0));
	float amount = across * UV.y * UV.y * COLOR.a;
	ALBEDO = COLOR.rgb * amount * energy;
	ALPHA = clamp(amount * cover, 0.0, 1.0);
}
