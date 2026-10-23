extends "res://tools/tests/vfx_stage.gd"
## Every spell cast for real on the light VfxStage and photographed at a few moments after
## its release, one sheet per colour - the "look at all 25 as a set" view
## docs/SPELL_VFX_PLAN.md asks for.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/spell_showcase.tscn -- <out_prefix> [white,red] [rank5] [--glow]
## Writes <out_prefix>_<colour>.png: one row per spell, one column per moment. The colour
## list narrows the run; without it all five sheets are written.
##
## A real Player casts through `_run_spell_effect`, the server's own entry point, against
## real enemies, so whatever the game builds for a spell is what is photographed. Each tile
## is its own cast on a fresh player and a fresh pack: a software renderer is too slow to
## catch several moments of one cast in sequence, and a leftover from the last spell would
## be photographed as part of the next.

const TILE := Vector2i(480, 270)
## Seconds after the release, unless a spell names its own.
const MOMENTS: Array[float] = [0.12, 0.45, 1.3]
## Where the crosshair meets the ground, in front of the caster. Every aimed spell lands here.
const AIM_DISTANCE := 12.0
const COLOURS: Array[String] = ["white", "blue", "black", "red", "green"]

## Moments of their own, for spells whose interesting part is later than the default's.
const SPELL_MOMENTS: Dictionary = {
	"red_1": [0.25, 0.6, 1.4],
	"red_5": [0.3, 0.62, 1.1],
	"green_1": [0.1, 0.4, 1.1],
	"blue_4": [0.2, 0.8, 2.0],
	"black_4": [0.2, 0.8, 2.0],
	"red_3": [0.4, 1.2, 2.5],
	"green_3": [0.4, 1.2, 2.5],
	"blue_3": [0.3, 1.0, 2.2],
	"white_6": [0.15, 0.35, 0.9],
	"green_10": [0.2, 0.55, 1.3],
	"green_9": [0.3, 0.8, 1.6],
	"green_11": [0.2, 0.5, 1.3],
	"black_9": [0.3, 0.7, 1.4],
	"black_6": [0.15, 0.6, 2.0],
	"black_11": [0.2, 0.8, 2.0],
	"red_7": [0.12, 0.5, 2.0],
	"white_10": [0.3, 1.2, 3.0],
}

const ChargeFx := preload("res://scripts/charge_fx.gd")
const ChargedHits := preload("res://scripts/charged_hits.gd")
const RoundTwoSpells := preload("res://scripts/round_two_spells.gd")
## Next-attack charges are shown in three moments of their own: the charge waiting on the weapon
## (CHARGE_ARMED, before any swing), then the seconds after the charged hit LANDS - the
## showcase swings for it, so a sheet shows what the charge does, not only that it was armed.
const CHARGE_ARMED := -1.0
const CHARGE_MOMENTS: Array = [CHARGE_ARMED, 0.1, 0.7]
## Seconds the charge sits on the weapon before the swing - long enough to fade in.
const CHARGE_SHOW := 0.6

var _player: Player = null
var _camera: Camera3D = null
var _caption: Label = null
var _rank: int = 1


func _ready() -> void:
	build_stage()
	_start.call_deferred()


func _start() -> void:
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	await _shoot_all()


func _shoot_all() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var prefix: String = "spell_showcase"
	if not args.is_empty() and not args[0].begins_with("--"):
		prefix = args[0]
	var colours: Array[String] = COLOURS.duplicate()
	for arg: String in args:
		if arg.begins_with("rank"):
			_rank = clampi(int(arg.substr(4)), 1, GameSettings.spell_max_rank)
		elif arg.split(",")[0] in COLOURS:
			colours.clear()
			for colour: String in arg.split(","):
				colours.append(colour)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	for colour: String in colours:
		var spells: Array[String] = SpellDatabase.spells_of(colour).filter(func(id: String) -> bool:
			return not SpellDatabase.is_passive(id))
		var sheet := Image.create(TILE.x * MOMENTS.size(), TILE.y * spells.size(), false, Image.FORMAT_RGB8)
		for row: int in range(spells.size()):
			var spell_id: String = spells[row]
			var moments: Array = CHARGE_MOMENTS if _is_charge(spell_id) else SPELL_MOMENTS.get(spell_id, MOMENTS)
			for column: int in range(moments.size()):
				var frame: Image = await _shoot(spell_id, float(moments[column]))
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i(column * TILE.x, row * TILE.y))
		var path: String = "%s_%s.png" % [prefix, colour]
		sheet.save_png(path)
		print("SPELL SHEET: %s" % path)
	get_tree().quit()


## One cast, one photograph `after` seconds past its release.
func _shoot(spell_id: String, after: float) -> Image:
	var keep: Array[Node] = get_children()
	_spawn_player(spell_id)
	await _set_the_scene(spell_id)
	_frame_camera(spell_id)
	if after == CHARGE_ARMED:
		# The charge waiting on the weapon: close on the caster.
		_camera.global_position = STAGE + Vector3(1.9, 1.9, 1.7)
		_camera.look_at(STAGE + Vector3(0.0, 1.1, -0.4))
	_camera.current = true
	await _cast(spell_id)
	if _is_charge(spell_id):
		await _swing_charge(spell_id, after)
	else:
		await get_tree().create_timer(after).timeout
	var moment: String = "armed" if after == CHARGE_ARMED else ("hit +%.2fs" % after if _is_charge(spell_id) else "+%.2fs" % after)
	_caption.text = "%s  %s  %s" % [spell_id.to_upper(), String(SpellDatabase.SPELLS[spell_id]["name"]), moment]
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	print("  %s %s" % [spell_id, moment])
	_clear(keep)
	return frame


## Whether `spell_id` charges the next attack (one with a look of its own on the weapon).
func _is_charge(spell_id: String) -> bool:
	return ChargeFx.IDS.has(spell_id)


## Lets the charge sit on the weapon, then - unless the moment is the waiting charge itself -
## makes the swing it waits for and waits `after` seconds past the moment it landed.
func _swing_charge(spell_id: String, after: float) -> void:
	await get_tree().create_timer(CHARGE_SHOW).timeout
	if after == CHARGE_ARMED:
		return
	var uses: int = _player.attack_charges.uses_left(spell_id)
	_player.kit._try_attack("H" if ChargedHits.trigger(spell_id) == "heavy" else "L")
	var waited: float = 0.0
	while _player.attack_charges.uses_left(spell_id) == uses and waited < 2.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await get_tree().create_timer(after).timeout


func _spawn_player(spell_id: String) -> void:
	var packed: PackedScene = load("res://scenes/misc/player.tscn") as PackedScene
	_player = packed.instantiate() as Player
	_player.set_meta("is_local", true)
	add_child(_player)
	_player.global_position = STAGE
	_player.spell_ranks[spell_id] = _rank
	# The crosshair on the ground AIM_DISTANCE ahead, so every aimed spell lands in frame.
	var drop: float = _player.aim_origin().y - STAGE.y
	_player.camera_pivot.rotation.x = -atan2(drop, AIM_DISTANCE)


## What each spell needs in front of it to show what it does.
func _set_the_scene(spell_id: String) -> void:
	match spell_id:
		"black_5":
			# Corpses to raise, made the way the game makes them.
			for offset: Vector3 in [Vector3(2.0, 0.0, -3.0), Vector3(-2.0, 0.0, -4.5), Vector3(0.5, 0.0, -7.0)]:
				var corpse: EnemyBase = _enemy(offset)
				await get_tree().physics_frame
				corpse.die()
			await get_tree().create_timer(1.2).timeout
		"white_1", "white_3", "white_5", "green_2", "green_5", "blue_5", "black_4", "green_3":
			pass
		_:
			for offset: Vector3 in [Vector3(-2.0, 0.0, -6.0), Vector3(1.5, 0.0, -7.5), Vector3(3.0, 0.0, -4.5),
					Vector3(-3.5, 0.0, -9.0), Vector3(0.5, 0.0, -11.0)]:
				_enemy(offset)
			if spell_id in ["black_2", "red_6", "green_8"]:
				# Single targets: the enemy in the sights.
				_enemy(_under_crosshair(11.0))
			if spell_id in ["white_11", "blue_11"]:
				# Aimed areas: a knot of enemies where the crosshair meets the ground.
				var aim: Vector3 = _under_crosshair(AIM_DISTANCE)
				for offset: Vector3 in [Vector3.ZERO, Vector3(1.4, 0.0, 0.6), Vector3(-1.2, 0.0, -0.8)]:
					_enemy(aim + offset)
			await _set_round_two_scene(spell_id)
			for _i: int in range(6):
				await get_tree().physics_frame


## The new skills' stages: an enemy in reach for every charge to land on, and what the rest
## act on - corpses, an elite's corpse, a standing stone, a beast's trophy.
func _set_round_two_scene(spell_id: String) -> void:
	if _is_charge(spell_id):
		var target: EnemyBase = _enemy(Vector3(0.0, 0.0, -2.2))
		if spell_id == "blue_9":
			# Time Ebb sends it home: somewhere in frame, well away.
			target.origin_position = ground_at(Vector2(STAGE.x + 7.0, STAGE.z - 12.0))
		if spell_id == "green_7":
			for offset: Vector3 in [Vector3(1.6, 0.0, -3.0), Vector3(-1.5, 0.0, -2.8), Vector3(0.4, 0.0, -4.2)]:
				_enemy(offset)
	match spell_id:
		"black_7", "black_10":
			# Corpses: near the swing for Bone Splinters, ahead in the sights for Gravewalk.
			var spots: Array = [Vector3(1.4, 0.0, -3.2), Vector3(-1.6, 0.0, -2.6), Vector3(0.6, 0.0, -4.0)]
			if spell_id == "black_10":
				spots = [_under_crosshair(10.0)]
			for offset: Vector3 in spots:
				var corpse: EnemyBase = _enemy(offset)
				await get_tree().physics_frame
				corpse.die()
			await get_tree().create_timer(1.2).timeout
		"black_9":
			# Animate Dead only raises an elite's (or bigger) corpse.
			var elite: EnemyBase = _enemy(_under_crosshair(10.0))
			await get_tree().physics_frame
			elite.elite_modifier = "showcase"
			elite.die()
			await get_tree().create_timer(1.2).timeout
		"green_9":
			_standing_stone(_under_crosshair(8.5))
		"green_11":
			_player.beast_trophies.append({"color": "Green", "size": 1.0})
		"red_7":
			# Blood Frenzy burns hotter the lower the health: show it well down.
			_player.hp = _player.max_hp * 0.3


## A stand-in for one of the ring's standing stones, as RoundTwoSpells._scenery_kind knows
## them: a body named StoneCollision on the ground's layer.
func _standing_stone(offset: Vector3) -> void:
	var stone := StaticBody3D.new()
	stone.name = "StoneCollision"
	stone.collision_layer = RoundTwoSpells.ENVIRONMENT_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.8, 0.7)
	shape.shape = box
	stone.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.5, 0.5, 0.48)
	mesh.material_override = rock
	stone.add_child(mesh)
	add_child(stone)
	stone.global_position = ground_at(Vector2(STAGE.x + offset.x, STAGE.z + offset.z)) + Vector3(0.0, 1.4, 0.0)


func _cast(spell_id: String) -> void:
	match spell_id:
		"red_2":
			SpellEffects.cast_red_fire_dash(_player)
			await get_tree().create_timer(GameSettings.spell_red_dash_duration).timeout
		"green_1":
			SpellEffects.cast_green_titanic_leap(_player)
			await get_tree().create_timer(GameSettings.spell_green_leap_duration).timeout
		"white_6", "green_10":
			# The charges that move the caster start on the cast, as Player._begin_cast does;
			# the moments are counted from the start, so the sheet shows the run itself.
			RoundTwoSpells.launch(_player, spell_id)
	_player._run_spell_effect(spell_id, 1.0)


func _frame_camera(spell_id: String) -> void:
	var at := STAGE + Vector3(0.0, 0.8, -5.5)
	var from := STAGE + Vector3(8.0, 5.5, 3.0)
	match spell_id:
		"white_1", "white_3", "white_5", "green_2", "green_5", "black_6", "black_11", "red_7", "red_10", "red_9":
			# Self buffs: close on the caster.
			at = STAGE + Vector3(0.0, 1.1, 0.0)
			from = STAGE + Vector3(3.2, 2.4, 3.6)
		"red_5", "red_1":
			from = STAGE + Vector3(11.0, 6.0, 0.0)
			at = STAGE + Vector3(0.0, 2.5, -9.0)
		"white_8", "blue_9", "black_7":
			# Charges whose hit reaches far: a lance, a trip home, a volley of splinters.
			at = STAGE + Vector3(1.0, 0.8, -6.5)
			from = STAGE + Vector3(9.0, 6.0, 1.5)
		_:
			if _is_charge(spell_id):
				# The weapon and the one it hits, close.
				at = STAGE + Vector3(0.0, 1.0, -1.6)
				from = STAGE + Vector3(4.2, 2.8, 1.8)
	_camera.global_position = from
	_camera.look_at(at)


func _enemy(offset: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	get_node("Enemies").add_child(enemy)
	enemy.global_position = ground_at(Vector2(STAGE.x + offset.x, STAGE.z + offset.z))
	return enemy


## The ground under the crosshair, `distance` metres along it - where an enemy has to stand
## to be the one Kill and Contagion pick.
func _under_crosshair(distance: float) -> Vector3:
	var spot: Vector3 = _player.aim_origin() + _player.aim_direction() * distance
	spot.y = STAGE.y
	return spot - STAGE


## Everything the cast left behind goes, so the next tile starts from the bare stage.
func _clear(keep: Array[Node]) -> void:
	for holder: String in ["Enemies", "Effects"]:
		for child: Node in get_node(holder).get_children():
			child.free()
	for child: Node in get_children():
		if not keep.has(child):
			child.free()
	for p: Projectile in ProjectilePool.pool:
		if p.active and p.has_method("deactivate"):
			p.deactivate()
	_player = null
