shader_type spatial;
// What a buff looks like ON the character for as long as it lasts (StatusFx): drawn as the
// material_overlay of every mesh of the player, over their own materials.
//
//   bark     Ironbark: oak bark grown over the skin (bark_texture), with faint green cracks
//   shield   Circle of Protection: a gold rim and a hex shimmer across the body
//   reprisal Reprisal Ward: bright bands of light climbing the body
//   exalted  Exalted Strike charged: a slow gold pulse at the silhouette
//   phoenix  Rally's ward: a flickering ember-gold rim
//   giant    Giant Growth: a faint green rim
//   berserk  the barbarian's Berserk: a blood-red rim throbbing like a pulse
//   charge   a next-attack charge waiting on the WEAPON (only the held overlay sets it): one of
//            ChargeFx.Pattern, in its tint - frost, ice facets, sand running up, violet smoke...
//
// Each is a 0..1 amount, eased in and out by StatusFx, so they stack instead of replacing
// each other. Bark is pigment and covers; the rest are light and only brighten - but a charge
// can be either (smoke, bone and vines cover, the rest shine), so it is laid over the rest.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float bark = 0.0;
uniform float shield = 0.0;
uniform float reprisal = 0.0;
uniform float exalted = 0.0;
uniform float phoenix = 0.0;
uniform float giant = 0.0;
uniform float berserk = 0.0;
uniform vec3 gold : source_color = vec3(1.0, 0.78, 0.36);
// Real bark - the oak of the map's own trees - tiled along the mesh's UVs, so it stays put
// on a moving limb. Procedural ridges used to stand in for it and read as brown stripes.
uniform sampler2D bark_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 bark_tiling = vec2(3.0, 1.5);
uniform vec3 green : source_color = vec3(0.55, 0.9, 0.45);
// Round two's self-buffs. unholy: dark veins over the skin, crimson pulsing in them (Unholy
// Strength). frenzy: an ember rim and heat climbing the body, as hot as `frenzy_heat` - the
// health already lost (Blood Frenzy). pact: violet-black smoke clinging to the silhouette
// (Demonic Pact's debt). Laid over the rest, like a charge.
uniform float unholy = 0.0;
uniform float frenzy = 0.0;
uniform float frenzy_heat = 0.0;
uniform float pact = 0.0;
uniform float charge = 0.0;
uniform vec3 charge_tint : source_color = vec3(1.0);
// ChargeFx.Pattern: PULSE, RAYS, BANDS, FROST, CRYSTAL, SAND, SMOKE, BONE, EMBER, GROWTH, VINES.
uniform int charge_pattern = 0;

varying vec3 v_world;

#include "res://assets/shaders/noise.gdshaderinc"

float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(s)), g.x);
}

// A charge's look at world-relative point `p`: rgb, and how much of it covers.
vec4 charge_layer(float fresnel, vec3 p, float t) {
	vec3 c = charge_tint;
	float a = 0.0;
	if (charge_pattern == 0) {
		// PULSE: a heavy, slow throb - a weight being gathered.
		float throb = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * 2.6), 2.0);
		a = (fresnel + 0.3) * throb;
		c = charge_tint * 2.2;
	} else if (charge_pattern == 1) {
		// RAYS: streaks of light running fast along the blade.
		float s = smoothstep(0.72, 1.0, 0.5 + 0.5 * sin((p.y * 7.0 + p.x * 3.0 + p.z * 3.0) - t * 10.0));
		s *= 0.4 + 0.6 * noise(p.xz * 6.0 + vec2(t * 2.0));
		a = s + fresnel * 0.35;
		c = charge_tint * 2.4;
	} else if (charge_pattern == 2) {
		// BANDS: thin rings of light sliding slowly up.
		float b = smoothstep(0.9, 1.0, 0.5 + 0.5 * sin(p.y * 18.0 - t * 2.0));
		a = b + fresnel * 0.25;
		c = mix(charge_tint, vec3(1.0), 0.4) * 2.0;
	} else if (charge_pattern == 3) {
		// FROST: rime in patches, pale, with glints catching.
		float rime = smoothstep(0.42, 0.72, noise(p.xy * 14.0 + p.zx * 9.0));
		float glint = smoothstep(0.86, 1.0, noise(p.xy * 40.0 + vec2(t * 0.6)));
		a = rime * 0.75 + fresnel * 0.4 + glint * 0.5;
		c = mix(charge_tint, vec3(1.0), rime * 0.5) * (1.1 + glint * 1.5);
	} else if (charge_pattern == 4) {
		// CRYSTAL: grown over with ice facets, bright along their edges.
		float edge = 1.0 - smoothstep(0.0, 0.05, hex_edge(p.xy * 9.0 + p.zx * 4.0));
		a = edge * 0.9 + fresnel * 0.5 + 0.15;
		c = mix(charge_tint, vec3(1.0), edge) * 1.6;
	} else if (charge_pattern == 5) {
		// SAND: grains running UP into the weapon - time going backwards.
		float g = smoothstep(0.7, 0.95, noise(vec2((p.x + p.z) * 30.0, p.y * 18.0 + t * 2.5)));
		a = g + fresnel * 0.3;
		c = charge_tint * 1.9;
	} else if (charge_pattern == 6) {
		// SMOKE: a violet dark that eats the light, with only its rim lit.
		float n = noise(p.xy * 6.0 + vec2(0.0, t * 0.8));
		a = 0.5 + n * 0.35;
		c = mix(vec3(0.03, 0.0, 0.05), charge_tint * 1.8, fresnel * 0.9);
	} else if (charge_pattern == 7) {
		// BONE: pale and dry, split by dark cracks.
		float crack = 1.0 - smoothstep(0.0, 0.05, abs(noise(p.xy * 10.0 + p.zx * 7.0) - 0.5));
		a = 0.55 + crack * 0.35;
		c = mix(charge_tint, vec3(0.12, 0.1, 0.08), crack);
	} else if (charge_pattern == 8) {
		// EMBER: a fuse's heat flickering through it, hot spots crawling.
		float f = noise(vec2(t * 9.0, p.y * 5.0));
		float spot = smoothstep(0.75, 1.0, noise(p.xy * 12.0 + vec2(t * 2.0)));
		a = fresnel * (0.5 + f) + spot * 0.7;
		c = mix(charge_tint, vec3(1.0, 0.9, 0.6), f) * 2.0;
	} else if (charge_pattern == 9) {
		// GROWTH: a thick living rim, swelling and easing.
		float swell = 0.55 + 0.45 * sin(t * 3.0);
		a = (fresnel * 1.3 + 0.12) * swell;
		c = charge_tint * 1.8;
	} else {
		// VINES: dark green spirals wound round it, a faint green life between.
		float v = smoothstep(0.8, 0.95, 0.5 + 0.5 * sin(p.y * 14.0 + atan(p.z, p.x) * 2.0 - t * 0.6));
		a = v * 0.85 + fresnel * 0.25;
		c = mix(charge_tint * 1.5, vec3(0.1, 0.18, 0.05), v * 0.75);
	}
	// Lifted: a weapon is a thin thing seen from behind the shoulder, and at the buffs' own
	// strength a charge on it disappeared in daylight.
	return vec4(c, clamp(a * 1.35 + 0.08, 0.0, 1.0) * charge);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);

	// Bark. The overlay is unshaded (the buffs below are light), so the bark carries its own
	// light: a fixed key from above the camera, deeper grooves where the texture is dark, and
	// a dry pale edge at the silhouette - without it the bark was a flat decal on the body.
	vec3 wood = texture(bark_texture, UV * bark_tiling).rgb;
	float wood_lum = dot(wood, vec3(0.299, 0.587, 0.114));
	float key = clamp(dot(NORMAL, normalize(vec3(0.35, 0.8, 0.45))), 0.0, 1.0);
	// The texture is a dark oak (median luminance about 0.07 once linear): lifted here so it
	// reads as wood in daylight rather than as a burnt shell.
	vec3 bark_col = wood * vec3(1.05, 0.95, 0.8) * (0.6 + key * 0.95) * mix(0.7, 1.25, smoothstep(0.01, 0.12, wood_lum));
	bark_col += vec3(0.32, 0.26, 0.18) * fresnel * 0.35;
	// Living green glowing up out of the deepest grooves - only the darkest few percent of
	// the texture - breathing slowly.
	float groove = 1.0 - smoothstep(0.003, 0.009, wood_lum);
	float crack = groove * (0.55 + 0.45 * sin(TIME * 2.0 + UV.y * 20.0));
	bark_col = mix(bark_col, green * 1.4, crack * 0.4);
	// Patchy at first, growing over everything as the amount rises.
	float cover = smoothstep(1.0 - bark * 1.15, 1.0 - bark * 1.15 + 0.15, noise(UV * 14.0));

	vec3 light = vec3(0.0);
	float light_a = 0.0;

	float hex = 1.0 - smoothstep(0.0, 0.07, hex_edge(v_world.xy * 5.0 + vec2(v_world.z * 3.0, TIME * 0.4)));
	float shimmer = smoothstep(0.55, 1.0, noise(v_world.xy * 4.0 + vec2(TIME * 0.8)));
	float s = shield * (fresnel * 0.9 + hex * shimmer * 0.5 + 0.08);
	light += gold * 1.6 * s;
	light_a += s;

	float band = smoothstep(0.75, 1.0, sin(v_world.y * 9.0 - TIME * 4.0)) * (0.35 + fresnel);
	float r = reprisal * band * 0.8;
	light += mix(gold, vec3(1.0), 0.4) * 1.8 * r;
	light_a += r;

	float pulse = 0.55 + 0.45 * sin(TIME * 5.0);
	float e = exalted * (fresnel * 0.9 + 0.12) * pulse;
	light += gold * 2.0 * e;
	light_a += e;

	float flicker = 0.6 + 0.4 * noise(vec2(TIME * 6.0, v_world.y * 3.0));
	float ph = phoenix * fresnel * flicker;
	light += vec3(1.0, 0.55, 0.2) * 1.8 * ph;
	light_a += ph;

	float gi = giant * (fresnel * 0.8 + 0.05);
	light += green * 1.4 * gi;
	light_a += gi;

	float throb = 0.55 + 0.45 * sin(TIME * 7.0);
	float bz = berserk * (fresnel * 1.0 + 0.06) * throb;
	light += vec3(0.95, 0.1, 0.05) * 2.0 * bz;
	light_a += bz;

	light_a = clamp(light_a, 0.0, 1.0);
	float bark_a = bark * cover * 0.92;
	vec3 color = bark_col;
	if (light_a > 0.0) {
		color = mix(bark_col, light / max(light_a, 0.001), light_a / max(light_a + bark_a * (1.0 - light_a), 0.001));
	}
	float alpha = clamp(max(bark_a, light_a), 0.0, 1.0);
	// The self-buffs of round two, each "over" what is there.
	vec4 extra = vec4(0.0);
	if (unholy > 0.0) {
		// Wide enough to read on armour from the play camera, over a pallor that darkens it all.
		float vein = 1.0 - smoothstep(0.0, 0.1, abs(noise(v_world.xy * 6.0 + v_world.zx * 4.0) - 0.5));
		float beat = 0.5 + 0.5 * sin(TIME * 4.0);
		vec3 c = mix(vec3(0.06, 0.0, 0.03), vec3(0.85, 0.05, 0.1) * 2.2, vein * (0.35 + beat * 0.65));
		extra = vec4(c, (vein * 0.85 + 0.22 + fresnel * 0.2) * unholy);
	}
	if (frenzy > 0.0) {
		float heat = 0.35 + 0.65 * frenzy_heat;
		float climb = smoothstep(0.7, 1.0, sin(v_world.y * 10.0 - TIME * 7.0)) * (0.4 + 0.6 * noise(v_world.xz * 6.0 + vec2(TIME)));
		float flick = 0.7 + 0.3 * noise(vec2(TIME * 8.0, v_world.y * 4.0));
		float fa = (fresnel * 1.1 * flick + climb * 0.4) * heat * frenzy;
		vec3 fc = mix(vec3(1.0, 0.2, 0.05), vec3(1.0, 0.65, 0.2), climb) * 2.2;
		extra = vec4(mix(extra.rgb, fc, fa / max(extra.a + fa, 0.001)), max(extra.a, fa));
	}
	if (pact > 0.0) {
		float wisp = noise(v_world.xy * 5.0 + vec2(0.0, -TIME * 0.9));
		float pa = (fresnel * 0.9 + wisp * 0.3) * pact;
		vec3 pc = mix(vec3(0.05, 0.0, 0.08), vec3(0.6, 0.22, 1.0) * 1.8, fresnel * wisp);
		extra = vec4(mix(extra.rgb, pc, pa / max(extra.a + pa, 0.001)), max(extra.a, pa));
	}
	if (extra.a > 0.0) {
		float ea = clamp(extra.a, 0.0, 1.0);
		float out_a = ea + alpha * (1.0 - ea);
		color = (extra.rgb * ea + color * alpha * (1.0 - ea)) / max(out_a, 0.001);
		alpha = out_a;
	}
	if (charge > 0.0) {
		// Over everything else: "over" compositing, since a charge can cover or shine.
		vec4 ch = charge_layer(fresnel, v_world, TIME);
		float out_a = ch.a + alpha * (1.0 - ch.a);
		color = (ch.rgb * ch.a + color * alpha * (1.0 - ch.a)) / max(out_a, 0.001);
		alpha = out_a;
	}
	ALBEDO = color;
	ALPHA = alpha;
}
