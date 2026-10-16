extends RefCounted
## The wild beasts: which creature lives in which biome, its model, and its numbers.
##
## A beast is an ordinary EnemyBase of class "Beast", spawned with its biome's colour as its
## colour identity - the colour is the one field everything else follows from: which species
## and look (VARIANTS), and later its mana and its equipment pool. See docs/BEASTS_PLAN.md.
##
## The models are the rigged Meshy quadrupeds in assets/enemies/beasts (built by the Blender
## scripts in its source folder). Their clips are idle, walk, run, attack, special, hit and
## death at 30 fps, in metres, facing +Z - no 100x import scale like the character scenes.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd for why a new
## global class is a hazard on the headless runs that validate the project.

## species id -> definition.
##   scene        the GLB
##   walk_speed   how far the walk clip carries the beast per second at playback 1.0, m/s
##   run_speed    the same for run. Both follow from the clip's stride and timing in
##                assets/enemies/beasts/source/beast_params.py: stride / (stance share * cycle).
##                The walk's stance is 0.62 of its cycle, the run's 0.4.
##   special      what its `special` clip is: "pounce" or "tail_spin"
##   health, speed, attack_damage, attack_speed, attack_range   as EnemyData
const SPECIES: Dictionary = {
	"thornhide": {
		"scene": "res://assets/enemies/beasts/thornhide_ravager/thornhide_ravager.glb",
		"walk_speed": 0.36 / (0.62 * 38.0 / 30.0),
		"run_speed": 0.75 / (0.4 * 20.0 / 30.0),
		"special": "pounce",
		"health": 420.0, "speed": 2.7, "attack_damage": 18.0, "attack_speed": 1.6, "attack_range": 2.8,
	},
	"blisterback": {
		"scene": "res://assets/enemies/beasts/blisterback_ravager/blisterback_ravager.glb",
		"walk_speed": 0.36 / (0.62 * 38.0 / 30.0),
		"run_speed": 0.75 / (0.4 * 20.0 / 30.0),
		"special": "pounce",
		"health": 400.0, "speed": 2.7, "attack_damage": 18.0, "attack_speed": 1.6, "attack_range": 2.8,
	},
	"spineback": {
		"scene": "res://assets/enemies/beasts/spineback_terror/spineback_terror.glb",
		"walk_speed": 0.3 / (0.62 * 40.0 / 30.0),
		"run_speed": 0.6 / (0.4 * 20.0 / 30.0),
		"special": "tail_spin",
		"health": 520.0, "speed": 2.2, "attack_damage": 20.0, "attack_speed": 1.8, "attack_range": 3.0,
	},
}

## The specials, as moments of their `special` clip (normalised time 0..1), from how
## beast_anim.py authors them:
##   pounce     crouch until `takeoff`, in the air until `land`, where the bite lands; then a
##              bite-and-shake and a hop back. The rig's root travels `reach` metres forward
##              by the landing and back again by the end.
##   tail_spin  a full turn on the spot; the tail is fastest, and hits, at `impact`.
const SPECIALS: Dictionary = {
	"pounce": {"takeoff": 0.22, "land": 0.44, "reach": 0.6},
	"tail_spin": {"impact": 0.5},
}

## Biome colour -> which species lives there, what it is called, and how its skin is turned
## to fit the biome (assets/shaders/beast_tint.gdshader: `hue` in turns, `sat` and `val` as
## multipliers; no `tint` draws the model as it was made). White and Black have no models of
## their own yet and borrow one; Red and Blue are tinted too, since neither model came out in
## its biome's colour.
const VARIANTS: Dictionary = {
	"Green": {"species": "thornhide", "name": "Thornhide Ravager"},
	# Sandy plates pushed round to rust.
	"Red": {"species": "spineback", "name": "Spineback Terror", "tint": {"hue": -0.06, "sat": 1.25, "val": 0.8}},
	# Yellow hide to deep blue; the purple legs come round to sea green, the blisters to violet.
	"Blue": {"species": "blisterback", "name": "Blisterback Ravager", "tint": {"hue": 0.5, "sat": 0.75, "val": 0.82}},
	# Bleached to bone.
	"White": {"species": "spineback", "name": "Ashen Spineback", "tint": {"hue": 0.0, "sat": 0.18, "val": 1.35}},
	# Charcoal, with a sickly violet cast in what colour is left.
	"Black": {"species": "thornhide", "name": "Gloomhide Ravager", "tint": {"hue": 0.5, "sat": 0.45, "val": 0.42}},
}

const TINT_SHADER := preload("res://assets/shaders/beast_tint.gdshader")

## One tinted material per source material and biome, shared by every beast drawn with it.
static var _tinted: Dictionary = {}


## The material a beast of this biome wears instead of `source`, or `source` itself when its
## variant is drawn as made.
static func tinted_material(color_id: String, source: Material) -> Material:
	var tint: Dictionary = (VARIANTS.get(color_id, {}) as Dictionary).get("tint", {})
	if tint.is_empty() or not source is StandardMaterial3D:
		return source
	var key: String = "%s|%d" % [color_id, source.get_instance_id()]
	if _tinted.has(key):
		return _tinted[key]
	var standard := source as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.shader = TINT_SHADER
	material.set_shader_parameter("albedo_texture", standard.albedo_texture)
	material.set_shader_parameter("use_normal", standard.normal_enabled and standard.normal_texture != null)
	material.set_shader_parameter("normal_texture", standard.normal_texture)
	# glTF packs roughness in green and metallic in blue of one texture, and that is what the
	# shader reads; the plain numbers multiply it the way StandardMaterial3D's do.
	material.set_shader_parameter("use_orm", standard.roughness_texture != null)
	material.set_shader_parameter("orm_texture", standard.roughness_texture)
	material.set_shader_parameter("roughness", standard.roughness)
	material.set_shader_parameter("metallic", standard.metallic)
	material.set_shader_parameter("hue_shift", float(tint.get("hue", 0.0)))
	material.set_shader_parameter("saturation", float(tint.get("sat", 1.0)))
	material.set_shader_parameter("value", float(tint.get("val", 1.0)))
	_tinted[key] = material
	return material

## The colour each biome's beast is drawn in where a flat colour is needed (health bar
## tags, payouts) - the same per-colour tints EnemyDatabase uses.
const VISUAL_COLORS: Dictionary = {
	"White": Color(0.9, 0.9, 0.9),
	"Blue": Color(0.1, 0.3, 0.8),
	"Black": Color(0.2, 0.2, 0.2),
	"Red": Color(0.8, 0.1, 0.1),
	"Green": Color(0.1, 0.6, 0.1),
}


## A size for a beast spawning in `wave` (GameSettings' Size block): 1x up to a cap that climbs
## with the wave, small more likely than big. `draw` is the random number to use, 0..1 - left
## at -1 it is rolled here; a test passes its own to see the whole range.
static func roll_size(wave: int, draw: float = -1.0) -> float:
	var progress: float = clampf(float(wave - 1) / float(maxi(GameSettings.beast_size_cap_full_wave - 1, 1)), 0.0, 1.0)
	var cap: float = lerpf(GameSettings.beast_size_cap_start, GameSettings.beast_size_max, progress)
	var x: float = randf() if draw < 0.0 else clampf(draw, 0.0, 1.0)
	return 1.0 + (cap - 1.0) * pow(x, maxf(GameSettings.beast_size_skew, 0.01))


static func has_variant(color_id: String) -> bool:
	return VARIANTS.has(color_id)


static func species_of(color_id: String) -> String:
	return String((VARIANTS.get(color_id, VARIANTS["Green"]) as Dictionary)["species"])


static func species(color_id: String) -> Dictionary:
	return SPECIES[species_of(color_id)]


static func special_kind(color_id: String) -> String:
	return String(species(color_id)["special"])


static func special(color_id: String) -> Dictionary:
	return SPECIALS.get(special_kind(color_id), {})


static func display_name(color_id: String) -> String:
	return String((VARIANTS.get(color_id, VARIANTS["Green"]) as Dictionary)["name"])


## The model for this biome's beast. Loaded on first use rather than preloaded, so a
## script that only reads the table does not pull three 10 MB models in with it.
static func visual_scene(color_id: String) -> PackedScene:
	return load(String(species(color_id)["scene"])) as PackedScene


## Walk and run speed of the clips at playback 1.0 - EnemyBase's locomotion table for a beast,
## which has no stride_speed metadata on its clips the way the built characters do.
static func locomotion(color_id: String) -> Dictionary:
	var spec: Dictionary = species(color_id)
	return {"walk": float(spec["walk_speed"]), "run": float(spec["run_speed"])}


## A fresh EnemyData for this biome's beast. No per-colour stat modifiers on top, unlike the
## wave enemies: a beast's numbers are its species'.
static func enemy_data(color_id: String) -> EnemyData:
	var spec: Dictionary = species(color_id)
	var data := EnemyData.new()
	data.color_identity = color_id
	data.enemy_class = "Beast"
	data.display_name = display_name(color_id)
	data.health = float(spec["health"])
	data.speed = float(spec["speed"])
	data.attack_damage = float(spec["attack_damage"])
	data.attack_speed = float(spec["attack_speed"])
	data.attack_range = float(spec["attack_range"])
	data.model_scale = 1.0
	data.visual_color = VISUAL_COLORS.get(color_id, Color.WHITE)
	return data
