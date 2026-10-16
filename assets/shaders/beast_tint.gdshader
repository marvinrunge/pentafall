// A wild beast's skin, recoloured to fit a biome it has no model of its own for
// (BeastDatabase.VARIANTS, docs/BEASTS_PLAN.md). The same textures the imported
// StandardMaterial3D draws with - albedo, normal map, and glTF's packed roughness (green) and
// metallic (blue) - with the albedo turned in HSV: hue rotated, saturation and value scaled.
// One model on disk serves several biomes this way; no texture is copied.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = true;
uniform bool use_orm = true;
uniform float roughness = 1.0;
uniform float metallic = 1.0;

// In turns: 0.5 is half way round the colour wheel.
uniform float hue_shift = 0.0;
uniform float saturation = 1.0;
uniform float value = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 hsv = rgb_to_hsv(texture(albedo_texture, UV).rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	hsv.z = clamp(hsv.z * value, 0.0, 1.0);
	ALBEDO = hsv_to_rgb(hsv);
	if (use_orm) {
		vec4 orm = texture(orm_texture, UV);
		ROUGHNESS = orm.g * roughness;
		METALLIC = orm.b * metallic;
	} else {
		ROUGHNESS = roughness;
		METALLIC = metallic;
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
}
