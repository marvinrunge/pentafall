shader_type spatial;
// A ball of living energy on one camera-facing quad (SpellFx.energy_orb): the mage's bolts and
// blast, the orb held over the mage's palm, the Fireball in flight and between the hands while
// it charges.
//
// What it replaces was a lit sphere of one emissive colour - a flat disc at any distance, and
// nothing moved on it. Here everything moves:
//
//   SWIRL    the field turns, faster near the middle than at the rim, so the ball spins like
//            a vortex rather than rotating like a solid.
//   BOIL     two layers of noise flow through it in different directions, bent outward as if
//            wrapped round a sphere, so the surface churns.
//   VEINS    thin bright filaments where the noise crosses its middle - the lightning-like
//            threads that make it read as energy rather than as a coloured blob.
//   FLICKER  the whole ball pulses and its edge is eaten into by the noise, so the silhouette
//            itself crackles.
//
// It has no outline. The ball fades out over nearly half its radius, where its boil decides,
// and covers what is behind it only where it is hot - so its edge is light thinning into the
// halo, never a ring. The first takes faded the ball over a fifth of its radius, at its darkest
// colour, still covering a third of the background: a dark rim like a glass marble's. The halo
// runs out to nothing at the edge of the quad, where it used to be cut off in a circle that
// showed at night. And where the ball meets something solid - the palm it floats over, the
// ground it hits - it thins out over `soft_depth` instead of being sliced by it.
//
// Three colours, out to in: `edge_color` at the rim, `body_color` through the body and
// `core_color` at the white-hot middle. The halo outside the ball is body colour.
//
// Premultiplied, like the rest of the effect layer (docs/SPELL_VFX_PLAN.md): ALBEDO is the light
// it adds, ALPHA how much of what is behind it covers - so it reads against a noon sky and in a
// pitch-black night alike.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform vec4 body_color : source_color = vec4(0.74, 0.66, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.22, 0.08, 0.55, 1.0);
// Overall brightness of the light added.
uniform float energy : hint_range(0.0, 8.0) = 1.4;
// How far the field is twisted, radians from the rim to the middle, and how fast it turns.
uniform float swirl = 2.2;
uniform float spin = 1.6;
// Noise cells across the ball, and how fast the boil flows.
uniform float boil_scale = 2.6;
uniform float boil_speed = 1.3;
// How hard the brightness pulses, 0 for steady.
uniform float flicker : hint_range(0.0, 1.0) = 0.3;
// How much of the quad's half-width the ball itself fills; the rest is halo.
uniform float ball_size : hint_range(0.3, 1.0) = 0.62;
// How strong the halo round the ball is.
uniform float halo : hint_range(0.0, 2.0) = 0.7;
// Metres something solid has to be behind the ball before it shows in full; 0 for never.
uniform float soft_depth = 0.0;
// Per orb, so two in flight never churn in step.
uniform float seed = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;

#include "res://assets/shaders/noise.gdshaderinc"

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 3; i++) {
		total += noise(p) * amplitude;
		p = OCTAVE_TURN * p * 2.03 + vec2(5.3, 1.7);
		amplitude *= 0.5;
	}
	return total / 0.9625;
}

void vertex() {
	// Faces the camera, keeping the node's own scale - one quad reads round from every side.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float quad_r = length(q);
	if (quad_r >= 1.0) {
		discard;
	}
	// In units of the ball: 1 at its surface, past 1 the halo.
	float r = quad_r / ball_size;
	float t = TIME + seed;

	// Swirl: turned more the nearer the middle.
	float turn = spin * t + swirl * (1.0 - clamp(r, 0.0, 1.0));
	vec2 spun = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * (q / ball_size);
	// Wrapped round a sphere: the sample stretches toward the rim, which is what makes a flat
	// quad read as a ball.
	float depth = sqrt(max(1.0 - min(r * r, 1.0), 0.0));
	vec2 sphere = spun / (depth + 0.45);

	vec2 flow = vec2(t * boil_speed, -t * boil_speed * 0.6);
	float n1 = fbm(sphere * boil_scale + flow + seed);
	float n2 = fbm(sphere * boil_scale * 2.2 - flow * 1.4 + vec2(17.0, 3.0) + seed * 0.7);
	// Stretched to its full range: fbm sits mostly round the middle, and a ball whose noise
	// barely moves its colour reads as a flat disc - which is what the first take of this did.
	float plasma = smoothstep(0.28, 0.72, n1 * 0.62 + n2 * 0.38);
	float veins = 1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5));

	float pulse = 1.0 + flicker * (noise(vec2(t * 9.0, seed * 3.1)) - 0.5) * 2.0;

	// The ball: thinning out from half its radius to a little past its surface, further where
	// the boil is hot and less where it is cold, so the edge wanders and is never a circle.
	float edge_at = 1.0 - 0.22 * (1.0 - plasma);
	float ball = 1.0 - smoothstep(edge_at - 0.5, edge_at + 0.1, r);
	// Heat, 0 at the rim to 1 in the middle - but mostly the boil: dark and bright streaks
	// churn through the whole body, and only a small middle runs white-hot.
	float heat = clamp((1.0 - r) * 0.7 + (plasma - 0.5) * 1.1 + 0.2 + smoothstep(0.35, 0.0, r) * 0.45, 0.0, 1.0);
	vec3 colour = heat < 0.6
		? mix(edge_color.rgb, body_color.rgb, heat / 0.6)
		: mix(body_color.rgb, core_color.rgb, (heat - 0.6) / 0.4);
	// Brighter where the boil reaches the fading edge - wherever that is just now, so it is
	// licks of light at the rim rather than a ring round it.
	float lick = ball * (1.0 - ball) * 4.0 * smoothstep(0.5, 0.9, plasma);
	colour += body_color.rgb * lick * 0.45 + core_color.rgb * veins * ball * 0.5;

	// The halo: light falling off outside the ball, nearly see-through, and down to nothing -
	// with nothing left to cut - at the edge of the quad.
	float out_of_ball = clamp((1.0 - quad_r) / (1.0 - ball_size), 0.0, 1.0);
	float glow = pow(out_of_ball, 2.4) * (1.0 - ball);

	vec3 light = (colour * ball + body_color.rgb * glow * halo * 0.45) * energy * pulse;
	// Covers what is behind it only where it is hot, and the faded edge hardly at all: what is
	// left there is light, so it glows into the background instead of darkening it.
	float cover = clamp(ball * ball * (0.22 + 0.68 * heat) + glow * halo * 0.08, 0.0, 1.0);

	// Something solid just behind it - the palm, the ground at the end of a flight - thins it
	// out rather than cutting a line through it.
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
	ALBEDO = light * fade * soft;
	ALPHA = cover * fade * soft;
}
