extends "res://tools/tests/key_art_shot.gd"
## Showcase screenshots at whatever the player's graphics preset is (Ultra for the store
## page): every colour's warband in its own biome, the crystal under attack from all five
## with the five hero classes holding it, and the biomes' beasts. Staged the way
## KeyArtShot stages its key art - the real map under the real sky, bare posed models.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --windowed --resolution 1920x1080 res://tools/tests/showcase_shot.tscn -- <folder> [shot,shot...]
##   ... -- --probe     prints every hero class's and beast's animation clips
##
## On top of KeyArtShot's actors: kind "class" is a hero class's own visual (its id in
## "color"), kind "beast" is a biome's beast, kind "tower" a round-two tower's look (its id
## in "color", front to where it faces), and any actor may name its own "lane" to be placed
## in that lane's coordinates instead of the shot's.

## A bow held drawn: the string at the hand and an arrow on it, with no PlayerAnimator
## behind it to say so.
class NockedBowRig extends BowRig:
	func is_nocked() -> bool:
		return true

## Each hero class at the crystal: which lane it holds and what it is doing there.
const DEFENDERS: Array[Dictionary] = [
	{"class": "knight", "lane": "White", "anim": "block_idle", "phase": 0.5},
	{"class": "mage", "lane": "Blue", "anim": "bolt_2", "phase": 0.45},
	{"class": "barbarian", "lane": "Black", "anim": "heavy_combo", "phase": 0.3},
	{"class": "warrior", "lane": "Red", "anim": "combo_2", "phase": 0.35},
	{"class": "archer", "lane": "Green", "anim": "aim", "phase": 0.5},
]
## Where each lane's warband is shown: the boss's distance out, as the loading art has it -
## the Red lane rises towards the volcano and is cut shorter.
const WARBAND_AT: Dictionary = {"White": 70.0, "Blue": 70.0, "Black": 46.0, "Red": 52.0, "Green": 64.0}
## How far right of the lane's line the warband walks there: the Blue path runs along the
## shore, and on the line itself half the column stood in the water.
const WARBAND_SIDE: Dictionary = {"Blue": 5.0}
const WARBAND_TIME: Dictionary = {"White": 11.0, "Blue": 10.0, "Black": 11.0, "Red": 11.5, "Green": 12.5}


func _boot() -> void:
	var probe: Node = (get_script() as GDScript).new()
	probe.name = "ShowcaseShot"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _probe() -> void:
	super._probe()
	for class_id: String in ClassDatabase.ORDER:
		var visual: Node = (load(ClassDatabase.visual_scene(class_id)) as PackedScene).instantiate()
		var player: AnimationPlayer = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("SHOWCASE hero %s anims %s" % [class_id, player.get_animation_list() if player else "none"])
		visual.free()
	for color: String in COLORS:
		var visual: Node = EnemyBase.BeastDatabase.visual_scene(color).instantiate()
		var player: AnimationPlayer = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("SHOWCASE beast %s anims %s" % [color, player.get_animation_list() if player else "none"])
		visual.free()


# --- shots ----------------------------------------------------------------------------

## A warband in battle order: melee in front, the rest behind, every row at its own point in
## its clip. Front-rank melee and every ranged and mage unit are in `attack` when `fighting`.
func _warband(color: String, front: float, rows: int, cols: int, spacing: float = 2.2,
		side: float = 0.0, fighting: bool = false, lane: String = "") -> Array:
	var out: Array = []
	var back: Array[String] = ["melee", "ranged", "ranged", "mage"]
	for r: int in rows:
		for c: int in cols:
			var jitter := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.6, 0.6))
			var kind: String = "melee" if r == 0 else back[_rng.randi() % back.size()]
			var anim: String = "walk"
			if fighting and (r == 0 or kind != "melee"):
				anim = "attack"
			var actor: Dictionary = _actor(kind, color, front + r * spacing + jitter.x,
				side + (c - (cols - 1) * 0.5) * spacing + jitter.y, anim)
			if lane != "":
				actor["lane"] = lane
			out.append(actor)
	return out


## The crystal under attack: every colour's warband up its own lane against the hero holding
## it, the bosses behind. Without `defenders` the heroes are left out, for a shot that stands
## them somewhere of its own.
func _siege(defenders: bool = true) -> Array:
	var actors: Array = []
	for defender: Dictionary in DEFENDERS:
		var lane: String = defender["lane"]
		if defenders:
			actors.append({"kind": "class", "color": defender["class"], "lane": lane, "at": Vector2(9.0, 0.0),
				"anim": defender["anim"], "phase": defender["phase"], "face": "out"})
		actors.append_array(_warband(lane, 11.0, 5, 5, 1.9, 0.0, true, lane))
		var boss: Dictionary = _actor("boss", lane, 22.0, 1.5, "walk", 0.3)
		boss["lane"] = lane
		actors.append(boss)
	return actors


func _shots() -> Dictionary:
	_rng.seed = 11
	var shots: Dictionary = {}

	# The siege: high over the Black lane's warband onto the whole hub; low behind the knight
	# against the White line; the aerial; the same fight at dusk, lit by the crystal; and two
	# over a warband's heads onto the hero holding that lane, the crystal behind.
	shots["siege_wide"] = {
		"lane": "Black", "time": 15.5, "fov": 58.0,
		"cam": Vector3(25.0, 5.0, 10.0), "look": Vector3(2.0, 0.0, 2.0), "actors": _siege(),
	}
	shots["siege_front"] = {
		"lane": "White", "time": 16.3, "fov": 50.0,
		"cam": Vector3(2.5, -3.5, 2.2), "look": Vector3(17.0, 1.0, 2.6), "actors": _siege(),
	}
	shots["siege_aerial"] = {
		"lane": "Red", "time": 13.0, "fov": 55.0,
		"cam": Vector3(14.0, -6.0, 18.0), "look": Vector3(-1.0, 0.0, 0.0), "actors": _siege(),
	}
	shots["siege_dusk"] = {
		"lane": "Green", "time": 17.6, "fov": 52.0,
		"cam": Vector3(16.0, 5.0, 4.0), "look": Vector3(0.0, 0.0, 3.0), "actors": _siege(),
	}
	shots["siege_barbarian"] = {
		"lane": "Black", "time": 14.5, "fov": 45.0,
		"cam": Vector3(16.0, 2.5, 4.2), "look": Vector3(7.0, 0.0, 1.4), "actors": _siege(),
	}
	shots["siege_mage"] = {
		"lane": "Blue", "time": 10.5, "fov": 45.0,
		"cam": Vector3(16.0, -2.5, 4.2), "look": Vector3(7.0, 0.0, 1.4), "actors": _siege(),
	}
	# All five heroes side by side before the crystal, facing the White warband (behind the
	# camera) while the other lanes fight behind them.
	var line: Array = []
	for actor: Dictionary in _siege(false):
		if actor.get("lane", "") != "White":
			line.append(actor)
	var stances: Array[Dictionary] = [
		{"class": "archer", "anim": "aim", "phase": 0.5},
		{"class": "knight", "anim": "block_idle", "phase": 0.5},
		{"class": "barbarian", "anim": "taunt_battlecry", "phase": 0.45},
		{"class": "warrior", "anim": "combo_2", "phase": 0.3},
		{"class": "mage", "anim": "bolt_2", "phase": 0.45},
	]
	for i: int in stances.size():
		var stance: Dictionary = stances[i]
		line.append({"kind": "class", "color": stance["class"], "lane": "White",
			"at": Vector2(9.0 - absf(float(i) - 2.0) * 0.7, (float(i) - 2.0) * 2.4),
			"anim": stance["anim"], "phase": stance["phase"], "face": "out"})
	shots["heroes_line"] = {
		"lane": "White", "time": 15.0, "fov": 46.0,
		"cam": Vector3(17.0, -2.5, 1.9), "look": Vector3(6.0, 0.0, 1.8), "actors": line,
	}

	# The five towers in an arc across the White lane before the crystal, fronts to the lane,
	# its front rank on them and the other lanes fighting behind.
	var towers: Array = []
	for actor: Dictionary in _siege(false):
		if actor.get("lane", "") != "White":
			towers.append(actor)
	var ids: Array[String] = ["hornet_nest", "glacial_fortress", "ivory_tower", "bontus_monument", "goblin_sharpshooter"]
	for i: int in ids.size():
		towers.append({"kind": "tower", "color": ids[i], "lane": "White",
			"at": Vector2(11.5 - absf(float(i) - 2.0) * 0.9, (float(i) - 2.0) * 3.9), "face": "out"})
	towers.append_array(_warband("White", 16.5, 1, 5, 2.4, 0.0, true, "White"))
	shots["towers_line"] = {
		"lane": "White", "time": 15.0, "fov": 52.0,
		"cam": Vector3(22.0, -3.0, 2.6), "look": Vector3(10.5, 0.0, 2.6), "actors": towers,
	}

	# The crystal alone, close enough to judge its mesh and the motes round it: by day and at
	# night, when it and its motes are most of the light there is.
	shots["crystal_close"] = {
		"lane": "White", "time": 15.0, "fov": 50.0,
		"cam": Vector3(15.0, 4.0, 5.5), "look": Vector3(0.0, 0.0, 5.3), "actors": [],
	}
	shots["crystal_night"] = {
		"lane": "White", "time": 23.0, "fov": 50.0,
		"cam": Vector3(15.0, 4.0, 5.5), "look": Vector3(0.0, 0.0, 5.3), "actors": [],
	}

	# Every colour's warband in its own biome: the whole column behind its boss from high over
	# the lane - the paths are the open ground, the forests either side swallow a camera - and
	# the front ranks close and low.
	for color: String in COLORS:
		var boss_along: float = WARBAND_AT[color]
		var hour: float = WARBAND_TIME[color]
		var side: float = WARBAND_SIDE.get(color, 0.0)
		var march: Array = [_actor("boss", color, boss_along, side + 0.5, "walk", 0.25)]
		march.append_array(_warband(color, boss_along + 5.0, 6, 6, 2.3, side))
		shots["warband_" + color.to_lower()] = {
			"lane": color, "time": hour, "fov": 52.0,
			"cam": Vector3(boss_along - 10.0, side - 3.5, 4.0), "look": Vector3(boss_along + 6.0, side + 0.5, 1.3),
			"actors": march,
		}
		var front: float = boss_along - 10.0
		var ranks: Array = _warband(color, front, 4, 5, 2.2, 0.0)
		ranks.append(_actor("boss", color, front + 13.0, -1.0, "walk", 0.3))
		shots["ranks_" + color.to_lower()] = {
			"lane": color, "time": hour + 0.5, "fov": 42.0,
			"cam": Vector3(front - 6.5, 2.0, 1.2), "look": Vector3(front + 3.0, -0.5, 1.6),
			"actors": ranks,
		}

	# The beasts: a pack on each biome's path - and one fight, two heroes against the
	# volcano's spineback.
	for color: String in COLORS:
		var at: float = WARBAND_AT[color] - 8.0
		shots["beasts_" + color.to_lower()] = {
			"lane": color, "time": float(WARBAND_TIME[color]) - 0.5, "fov": 45.0,
			"cam": Vector3(at - 7.5, -2.5, 1.4), "look": Vector3(at + 1.5, 2.0, 0.9),
			"actors": [
				_actor("beast", color, at + 0.5, 0.5, "special", 0.32, Vector2(at - 6.0, -2.0)),
				_actor("beast", color, at + 4.0, 4.0, "idle", 0.4, Vector2(at - 4.0, 0.0)),
				_actor("beast", color, at + 2.5, -3.0, "walk", 0.6, Vector2(at - 5.0, -2.0)),
			],
		}
	shots["beast_hunt"] = {
		"lane": "Red", "time": 15.0, "fov": 46.0,
		"cam": Vector3(44.0, -8.5, 1.7), "look": Vector3(44.5, 1.0, 1.1),
		"actors": [
			_actor("beast", "Red", 46.5, 2.0, "attack", 0.45, Vector2(43.0, 0.0)),
			{"kind": "class", "color": "knight", "at": Vector2(43.0, 0.0), "anim": "shield_bash", "phase": 0.35, "face": Vector2(46.5, 2.0)},
			{"kind": "class", "color": "archer", "at": Vector2(39.5, 2.5), "anim": "aim", "phase": 0.5, "face": Vector2(46.5, 2.0)},
		],
	}
	return shots


# --- staging --------------------------------------------------------------------------

## Most of these cameras stand in forest, and the first set put tree trunks across half the
## frame. Before staging, the camera is stepped sideways and up until nothing on the
## Environment layer but the terrain stands between it and what it looks at.
func _stage(shot: Dictionary) -> void:
	var lane: String = shot["lane"]
	var cam: Vector3 = shot["cam"]
	var look: Vector3 = shot["look"]
	var target: Vector3 = _lane_point(lane, look.x, look.y, look.z)
	# along, side, height
	var nudges: Array[Vector3] = [Vector3.ZERO]
	for step: float in [1.5, 3.0, 4.5, 6.0]:
		nudges.append_array([Vector3(0.0, step, 0.0), Vector3(0.0, -step, 0.0),
			Vector3(step * 0.5, step, 0.5), Vector3(step * 0.5, -step, 0.5), Vector3(step, 0.0, 0.0)])
	for nudge: Vector3 in nudges:
		var tried: Vector3 = cam + nudge
		if _clear_view(_lane_point(lane, tried.x, tried.y, tried.z), target):
			if nudge != Vector3.ZERO:
				print("SHOWCASE camera nudged by %s" % nudge)
			shot["cam"] = tried
			break
	await super._stage(shot)


## Nothing but the terrain round the camera, nor across the middle of the frame: rays to
## the look point and to either side of it, a third of the way to the frame's edge.
func _clear_view(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = 1.0
	var around := PhysicsShapeQueryParameters3D.new()
	around.shape = ball
	around.transform = Transform3D(Basis.IDENTITY, from)
	around.collision_mask = 1 << 4
	around.exclude = [_terrain.get_rid()]
	if not space.intersect_shape(around, 1).is_empty():
		return false
	var across: Vector3 = (to - from).cross(Vector3.UP).normalized() * from.distance_to(to) * 0.35
	for point: Vector3 in [to, to + across, to - across]:
		var query := PhysicsRayQueryParameters3D.create(from, from.lerp(point, 0.85), 1 << 4)
		query.exclude = [_terrain.get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false
	return true


func _place(lane: String, actor: Dictionary) -> void:
	super._place(String(actor.get("lane", lane)), actor)
	var node: Node3D = _staged.back()
	if actor["kind"] == "class":
		_dress_hero(node, String(actor["color"]))
	elif actor["kind"] == "tower":
		# A tower's front is its -Z, the way Tower turns it to where the caster aimed.
		node.rotate_y(PI)


## The live parts a hero's visual only gets from PlayerAnimator: the archer's string and
## nocked arrow, the mage's orb over the palm.
func _dress_hero(node: Node3D, class_id: String) -> void:
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var bow: Node3D = node.find_child("Bow", true, false) as Node3D
	if bow != null:
		var rig := NockedBowRig.new()
		rig.setup(null, bow, skeleton)
		node.add_child(rig)
	if ClassDatabase.has_hand_orb(class_id):
		var orb := MageHandOrb.new()
		orb.setup(skeleton, null, MageBolt.tint_of("Red"))
		node.add_child(orb)


func _unit_visual(kind: String, color: String) -> Node3D:
	match kind:
		"class":
			return (load(ClassDatabase.visual_scene(color)) as PackedScene).instantiate()
		"tower":
			return (load("res://scenes/towers/%s.tscn" % color) as PackedScene).instantiate()
		"beast":
			var visual: Node3D = EnemyBase.BeastDatabase.visual_scene(color).instantiate()
			for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				for surface: int in mesh_instance.mesh.get_surface_count():
					var source: Material = mesh_instance.get_active_material(surface)
					var tinted: Material = EnemyBase.BeastDatabase.tinted_material(color, source)
					if tinted != source:
						mesh_instance.set_surface_override_material(surface, tinted)
			visual.scale = Vector3.ONE * 1.25
			return visual
	return super._unit_visual(kind, color)
