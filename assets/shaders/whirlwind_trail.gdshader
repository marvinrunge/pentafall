shader_type spatial;
// The barbarian's Whirlwind: the smear the greatsword leaves behind it as it goes round - a
// flat ring at blade height, bright right behind the blade and thinning away over the last
// part of a turn. Drawn on a ring mesh (WhirlwindFx._ring_mesh): UV.x goes once round
// (angle = UV.x * TAU, at (cos, 0, -sin) - the way rotation.y turns +X), UV.y from the
// inner edge (0) to the blade's tip (1).
//
// Premultiplied like the rest of the effect layer, and soft on every side: the leading
// edge, the end of the smear, the hilt end and the tip all fade rather than stop.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.92, 0.88, 0.8, 1.0);
// Where the blade is now, radians, in the mesh's own angle convention. Set every frame.
uniform float head = 0.0;
// How far round behind the blade the smear reaches, radians.
uniform float trail_length : hint_range(0.1, 6.0) = 2.8;
// The whole effect's fade in and out, 0..1.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 4.0) = 1.2;
// How much of what is behind the smear it covers - what makes it read against a bright sky.
uniform float cover : hint_range(0.0, 1.0) = 0.28;
// The same smear on an upright band at the blade's reach (UV.y bottom to top), which is what
// reads from a player's camera: a flat ring at waist height is nearly edge-on from there.
// Upright, it is brightest across its middle and fades out where it is seen edge-on.
uniform bool upright = false;

void fragment() {
	float theta = UV.x * TAU;
	float behind = mod(head - theta, TAU);
	float t = behind / trail_length;
	float along = 1.0 - smoothstep(0.0, 1.0, t);
	along *= along;
	// The leading edge rises over a stretch of the turn instead of standing as a hard line
	// at the blade - with the brightest part of the smear just behind it.
	along *= smoothstep(0.0, 0.9, behind);
	float r = UV.y;
	float radial = upright
		? smoothstep(0.0, 0.5, r) * (1.0 - smoothstep(0.5, 1.0, r))
		: smoothstep(0.08, 0.6, r) * (1.0 - smoothstep(0.8, 1.0, r));
	if (upright) {
		radial *= smoothstep(0.0, 0.5, abs(dot(normalize(NORMAL), normalize(VIEW))));
	}
	// Streaks along the cut, carried round with the blade: the smear is the air the edge
	// went through, not a painted disc the sword sweeps over.
	float streak = mix(0.35, 1.0, noise(vec2(r * 16.0, behind * 1.4 + 5.0)));
	float a = clamp(along * radial * streak * intensity, 0.0, 1.0);
	vec3 colour = mix(tint.rgb, vec3(1.0), 0.45 * (1.0 - t)) * energy;
	ALBEDO = colour * a;
	ALPHA = a * cover;
}
