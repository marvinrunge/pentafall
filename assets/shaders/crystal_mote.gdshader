shader_type spatial;
// One mote of mana round the base crystal (CrystalMotes): a small sharp point of light on a
// camera-facing particle quad, in the colour its particle was born with.
//
// No texture: the shape is a small solid core whose edge falls off over a couple of pixels,
// with only a faint glow round it - a spark, not a soft blob. The first take was a wide
// gaussian halo and read as out-of-focus dots; a plain steep gaussian was sharp but shrank
// the visible part to two or three pixels. The glow still runs out to nothing within the
// quad, so there is no ring at its edge. Where a mote drifts into the crystal or the ground
// it thins out over `soft_depth` instead of being cut by the surface.
//
// Premultiplied, like the effect layer (docs/SPELL_VFX_PLAN.md): ALBEDO is the light it adds,
// ALPHA how much of what is behind it it covers. The particle colours are a little above 1,
// so the cores just catch the bloom; `cover` keeps the covering under the light, so a mote
// is mostly added light at night and still covers enough of a noon sky to read against it.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// How much of the background the mote covers, relative to the light it adds.
uniform float cover : hint_range(0.0, 1.0) = 0.85;
// The core's radius as a share of the quad's half-width: solid out to x, gone by y.
uniform vec2 core = vec2(0.1, 0.3);
// How strong the glow round the core is.
uniform float halo : hint_range(0.0, 1.0) = 0.1;
// How hard the motes twinkle, 0 for steady, and how fast.
uniform float twinkle : hint_range(0.0, 1.0) = 0.5;
uniform float twinkle_speed = 4.0;
// Metres something solid has to be behind a mote before it shows in full.
uniform float soft_depth = 0.2;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;

varying float phase;

void vertex() {
	// Faces the camera, keeping the particle's scale (BILLBOARD_PARTICLES with keep_scale).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// Each particle twinkles on its own beat.
	phase = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453) * 6.2832;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	// The glow is already near zero at the quad's edge; the last factor takes it the rest of
	// the way, so not even the corners show a line.
	float shape = 1.0 - smoothstep(core.x, core.y, sqrt(r2));
	shape = max(shape, halo * exp(-r2 * 8.0)) * (1.0 - smoothstep(0.55, 1.0, r2));
	shape *= 1.0 - twinkle * (0.5 + 0.5 * sin(TIME * twinkle_speed + phase));

	float soft = 1.0;
	if (soft_depth > 0.0) {
		float behind_depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, behind_depth) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, behind_depth);
#endif
		vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		behind.xyz /= behind.w;
		soft = clamp((VERTEX.z - behind.z) / soft_depth, 0.0, 1.0);
	}
	// COLOR.a is the particle's fade over its life; premultiplied here, so the ramps can
	// stay plain colours.
	float amount = shape * soft * COLOR.a;
	ALBEDO = COLOR.rgb * amount;
	ALPHA = clamp(amount * cover, 0.0, 1.0);
}
