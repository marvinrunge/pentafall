extends Node
## Regression test: do enemies Unsummon throws come back down onto the ground?
##
## On the real map, once its navmesh is in: a pack of melee enemies in front of the player,
## Unsummon cast into them, and every body's height above the terrain under it logged each
## physics tick for eight seconds - on the flat ground at the crystal, out on a lane's slope,
## and on that slope again with the player gone the moment the throw lands, so the pack
## walks on at the far physics level of detail (EnemyBase._slide), which sets bodies down by
## a ray of its own. A body may fly while the knockback carries it; after that it has to
## stand on the ground: not sunk into it, and not hanging over it.
##
## Run with:  godot --headless --path . res://tools/tests/unsummon_ground.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

## Deeper than this under the terrain counts as sunk, at any moment.
const SUNK := 0.25
## Higher than this over it, once the throw is over, counts as hanging.
const HANGING := 0.4
## Seconds after the cast by which every body has to be down: the knockback runs out in
## under a second, and the stun it comes with ends at 1.5 s.
const DOWN_BY := 2.5
const WATCH := 8.0

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []
var _terrain_body: StaticBody3D = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/unsummon_ground.gd").new()
	probe.name = "UnsummonGroundTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	var player: Node3D = PlayerRegistry.get_local()
	if player == null:
		return
	var probe: Vector3 = player.global_position + Vector3(6.0, 0.0, 6.0)
	if NavigationServer3D.map_get_closest_point(player.get_world_3d().navigation_map, probe) == Vector3.ZERO:
		return
	_started = true
	await _run(player as Player)
	get_tree().quit()


func _run(player: Player) -> void:
	var scene: Node = get_tree().current_scene
	_terrain_body = scene.call("_find_collision_body", scene.get_node("TerraBrush"))
	var waves: Node = scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().physics_frame
	var crystal: Vector3 = (scene.get("crystal_anchor") as Node3D).global_position
	var spawner: Vector3 = ((scene.get("enemy_spawners") as Array)[2] as Node3D).global_position
	var out: Vector3 = Vector3(spawner.x - crystal.x, 0.0, spawner.z - crystal.z).normalized()
	# The crystal's flat ground, then halfway down the Black lane where it climbs.
	for spot: Array in [["crystal", crystal + out * 14.0, false], ["lane", crystal + out * 70.0, false],
			["lane, player gone", crystal + out * 70.0, true]]:
		await _throw(player, String(spot[0]), spot[1] as Vector3, out, bool(spot[2]))

	if _failures.is_empty():
		print("TEST RESULT: PASS (Unsummon's throws land on the ground, at the crystal and on a slope)")
	else:
		print("TEST RESULT: FAIL")
		for failure: String in _failures:
			print("  - " + failure)


func _throw(player: Player, label: String, at: Vector3, out: Vector3, leave: bool) -> void:
	at.y = _terrain(at)
	player.global_position = at + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	# Facing out along the lane, the pack in front of it.
	player.rotation.y = atan2(-out.x, -out.z)
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var pack: Array[EnemyBase] = []
	for row: int in 2:
		for col: int in 4:
			var spot: Vector3 = at + out * (3.0 + row * 2.2) + side * ((col - 1.5) * 1.8)
			spot.y = _terrain(spot)
			var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
			enemy.set_meta("enemy_color", "Red")
			enemy.set_meta("enemy_type", "Melee")
			get_tree().current_scene.add_child(enemy)
			enemy.global_position = spot + Vector3.UP * 0.05
			pack.append(enemy)
	# Standing: some ticks to land, find their floor and settle, as a pack in a fight does.
	for _i: int in 45:
		await get_tree().physics_frame
	SpellEffects.cast_blue_unsummon(player)
	var deepest: Dictionary = {}
	var hung: Dictionary = {}
	var elapsed: float = 0.0
	var left: bool = false
	while elapsed < WATCH:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if leave and not left and elapsed > 0.3:
			# Mid-throw, as a player who casts and runs: well past the physics LOD distance.
			left = true
			player.global_position = at - out * 60.0
			player.global_position.y = _terrain(player.global_position) + 0.2
		for enemy: EnemyBase in pack:
			if not is_instance_valid(enemy) or enemy.is_dying:
				continue
			var ground: float = _terrain(enemy.global_position)
			if not is_finite(ground):
				continue
			var above: float = enemy.global_position.y - ground
			deepest[enemy] = minf(float(deepest.get(enemy, 0.0)), above)
			if elapsed > DOWN_BY and above > HANGING:
				hung[enemy] = maxf(float(hung.get(enemy, 0.0)), above)
	var index: int = 0
	for enemy: EnemyBase in pack:
		index += 1
		if not is_instance_valid(enemy):
			continue
		var low: float = float(deepest.get(enemy, 0.0))
		print("UNSUMMON %s #%d deepest %.2f m, %s%s" % [label, index, low,
			"hanging %.2f m after %.1f s" % [hung[enemy], DOWN_BY] if hung.has(enemy) else "down",
			", far" if enemy._far else ""])
		if low < -SUNK:
			_failures.append("%s: enemy %d sank %.2f m into the ground" % [label, index, -low])
		if hung.has(enemy):
			_failures.append("%s: enemy %d still %.2f m over the ground %.1f s after the cast" % [label, index, hung[enemy], DOWN_BY])
		enemy.queue_free()
	await get_tree().physics_frame


## The terrain's height under `at`: the first thing on the Environment layer from high above
## that is the terrain itself - trees, rocks and the crystal's box are stepped through.
func _terrain(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 60.0, at.z), Vector3(at.x, at.y - 60.0, at.z), EnemyBase.ENVIRONMENT_LAYER)
	var exclude: Array[RID] = []
	for _i: int in 16:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return NAN
		if hit.collider == _terrain_body:
			return (hit.position as Vector3).y
		exclude.append(hit.rid)
	return NAN
