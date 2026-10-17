shader_type canvas_item;

// The minimap picture under the fog of war (scripts/fog_of_war.gd): ground nobody on the team
// has seen is dark, seen ground nobody is watching now is dimmed, and the circles the team
// sees right now are clear. Also rounds the corners the way rounded_icon.gdshader does, since
// it replaces that shader on the picture.
//
// UV is the minimap square: the world from -world_radius to +world_radius on x and z, the same
// square the explored mask and the sight circles are given in.
uniform float radius_ratio : hint_range(0.0, 0.5) = 0.25;
uniform sampler2D explored : filter_linear, repeat_disable;
// xy = centre in UV, z = radius in UV. Only the first `source_count` are read.
uniform vec4 sources[48];
uniform int source_count = 0;
uniform float unexplored_darkness = 0.85;
uniform float unseen_darkness = 0.45;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float seen_ever = texture(explored, UV).r;
	float seen_now = 0.0;
	for (int i = 0; i < source_count; i++) {
		vec4 s = sources[i];
		float d = distance(UV, s.xy);
		// A soft rim, a few percent of the radius wide.
		seen_now = max(seen_now, 1.0 - smoothstep(s.z * 0.92, s.z, d));
	}
	float darkness = mix(unexplored_darkness, unseen_darkness, seen_ever);
	darkness = mix(darkness, 0.0, seen_now);
	tex.rgb *= 1.0 - darkness;
	vec2 corner = abs(UV - vec2(0.5)) - (vec2(0.5) - vec2(radius_ratio));
	float dist = length(max(corner, vec2(0.0))) - radius_ratio;
	tex.a *= 1.0 - smoothstep(0.0, fwidth(dist), dist);
	COLOR = tex * COLOR;
}
