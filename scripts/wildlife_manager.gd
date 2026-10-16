extends Node
## Keeps each biome stocked with its wild beasts, independent of the waves (stage 3 of
## docs/BEASTS_PLAN.md). Server only: a beast is spawned through MainController.request_enemy
## like every enemy, and the EnemyNetSpawner rebuilds it on each client.
##
## The map is a pentagon of wedges around the crystal, one biome each, in LANE_NAMES order,
## each with its lane's enemy path running down the middle. A beast's home is picked at random
## inside its own biome's wedge and kept clear of everything that is not wilderness:
##   - the lanes' enemy paths, so a beast never stands on the road a wave walks;
##   - the hub around the crystal;
##   - water (rivers, the swamp), which a body would stand at the bottom of;
##   - every other beast's home, so territories do not overlap;
##   - every player, so nothing appears in front of anyone.
## A home that leads nowhere (no route from it to the crystal - an island of navmesh on a rock)
## is refused too: a beast there could never be reached, nor walk home.
##
## Each biome keeps up to beast_max_per_biome beasts. A dead one is replaced after
## beast_respawn_min..max seconds; the first ones arrive beast_first_spawn_delay into the
## match, beast_spawn_stagger apart. Waves and Upkeep do not matter to any of it.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const BeastDatabase := preload("res://scripts/beast_database.gd")

## Half the angle of one biome's wedge: five of them make the full turn.
const WEDGE_HALF_DEGREES := 36.0

## Per lane: name, direction from the crystal, the spawner's distance, the enemy path.
var _lanes: Array[Dictionary] = []
## Lane name -> the beasts living there now.
var _beasts: Dictionary = {}
## Lane name -> seconds before that biome may add a beast.
var _cooldowns: Dictionary = {}
## Lane name -> the size rolled for its next beast, kept until a home big enough is found -
## rolled afresh every check, a giant would lose to the small sizes in a dense forest every
## time - and how many checks it has gone without one.
var _pending_sizes: Dictionary = {}
var _pending_misses: Dictionary = {}
## Checks a rolled size may go without finding room before it is rolled again.
const SIZE_PATIENCE := 6
var _main: Node = null
var _crystal: Vector3 = Vector3.ZERO
var _crystal_goal: Vector3 = Vector3.INF
var _map: RID
var _map_half_extent: float = 256.0
var _check_timer: float = 0.0


## Reads the lanes off the map. Called by MainController once the navmesh is in.
func setup(main: Node) -> void:
	_main = main
	if not Net.is_server():
		set_physics_process(false)
		return
	_map = (main as Node3D).get_world_3d().navigation_map
	var anchor: Node3D = main.get("crystal_anchor") as Node3D
	_crystal = anchor.global_position
	_crystal_goal = NavigationServer3D.map_get_closest_point(_map, _crystal)
	var terrain: Node = main.get_node_or_null("TerraBrush")
	if terrain != null:
		_map_half_extent = float(terrain.get("zonesSize")) * 0.5
	var names: Array = MainController.LANE_NAMES
	var spawners: Array = main.get("enemy_spawners")
	for i: int in mini(names.size(), spawners.size()):
		var spawner: Node3D = spawners[i] as Node3D
		var outward: Vector3 = spawner.global_position - _crystal
		outward.y = 0.0
		if outward.length_squared() < 1.0:
			continue
		var road: PackedVector3Array = NavigationServer3D.map_get_path(_map,
			NavigationServer3D.map_get_closest_point(_map, spawner.global_position), _crystal_goal, true)
		var lane_name: String = String(names[i])
		_lanes.append({"name": lane_name, "dir": outward.normalized(), "reach": outward.length(), "road": road})
		_beasts[lane_name] = []
		_cooldowns[lane_name] = GameSettings.beast_first_spawn_delay + GameSettings.beast_spawn_stagger * float(i) / float(maxi(names.size(), 1))


func _physics_process(delta: float) -> void:
	if _lanes.is_empty():
		return
	for lane_name: String in _cooldowns:
		_cooldowns[lane_name] = float(_cooldowns[lane_name]) - delta
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = GameSettings.beast_spawn_check_interval
	for lane: Dictionary in _lanes:
		_tend(lane)


## One biome: forget the dead, and add a beast if there is room and its time has come.
func _tend(lane: Dictionary) -> void:
	var lane_name: String = lane["name"]
	var living: Array = []
	for beast: Variant in _beasts[lane_name]:
		if is_instance_valid(beast) and not (beast as EnemyBase).is_dying:
			living.append(beast)
	if living.size() < (_beasts[lane_name] as Array).size():
		# One has died: the biome is replaced after a while, not at once.
		_cooldowns[lane_name] = maxf(float(_cooldowns[lane_name]),
			randf_range(GameSettings.beast_respawn_min, GameSettings.beast_respawn_max))
	_beasts[lane_name] = living
	if living.size() >= GameSettings.beast_max_per_biome or float(_cooldowns[lane_name]) > 0.0:
		return
	if not _pending_sizes.has(lane_name) or int(_pending_misses.get(lane_name, 0)) >= SIZE_PATIENCE:
		_pending_sizes[lane_name] = BeastDatabase.roll_size(_current_wave())
		_pending_misses[lane_name] = 0
	var size: float = float(_pending_sizes[lane_name])
	var home: Vector3 = _find_home(lane, size)
	if not home.is_finite():
		_pending_misses[lane_name] = int(_pending_misses[lane_name]) + 1
		return
	_pending_sizes.erase(lane_name)
	var beast: Node3D = _main.request_enemy({"color": lane_name, "type": "Beast", "position": home, "beast_size": size})
	if beast == null:
		return
	beast.rotation.y = randf() * TAU
	living.append(beast)
	_cooldowns[lane_name] = GameSettings.beast_spawn_stagger
	print("Beast spawned: %s in %s at %s, size %.2f" % [BeastDatabase.display_name(lane_name), lane_name, home, size])


func _current_wave() -> int:
	var waves: Node = _main.get_node_or_null("WaveManager")
	return maxi(int(waves.get("current_wave")), 1) if waves != null else 1


## A home for a new beast of `size` in this biome, or INF if none of this check's tries was good
## enough.
func _find_home(lane: Dictionary, size: float) -> Vector3:
	var half: float = deg_to_rad(WEDGE_HALF_DEGREES - GameSettings.beast_wedge_margin_degrees)
	var far: float = minf(float(lane["reach"]) * 0.97, _map_half_extent - 15.0)
	var near: float = min_crystal_distance(size)
	if far <= near:
		return Vector3.INF
	for attempt: int in GameSettings.beast_spawn_attempts:
		var dir: Vector3 = (lane["dir"] as Vector3).rotated(Vector3.UP, randf_range(-half, half))
		var wanted: Vector3 = _crystal + dir * randf_range(near, far)
		var spot: Vector3 = NavigationServer3D.map_get_closest_point(_map, wanted)
		if _flat(spot, wanted) > 3.0:
			continue # no ground there - a cliff, a wall, the map's edge
		if _good_home(spot, lane, size):
			return spot
	return Vector3.INF


## How much room a beast of `size` keeps. It roams the square root of its size further (as
## EnemyBase._beast_sense) and is its size longer, so a giant needs a wider berth from the lanes,
## the hub and the other territories than a 1x one.
static func lane_clearance(size: float) -> float:
	return GameSettings.beast_lane_clearance * sqrt(size) + BODY_HALF_LENGTH * (size - 1.0)


static func min_crystal_distance(size: float) -> float:
	return GameSettings.beast_min_crystal_distance + GameSettings.beast_roam_radius * (sqrt(size) - 1.0)


static func home_spacing(size_a: float, size_b: float) -> float:
	return GameSettings.beast_home_spacing * sqrt(maxf(size_a, size_b))


## Half a 1x beast's length, metres - the 2.8-3 m models.
const BODY_HALF_LENGTH := 1.5


func _good_home(spot: Vector3, lane: Dictionary, size: float) -> bool:
	if not in_wedge(spot, lane["dir"], GameSettings.beast_wedge_margin_degrees):
		return false
	if _flat(spot, _crystal) < min_crystal_distance(size):
		return false
	for other: Dictionary in _lanes:
		if distance_to_path(spot, other["road"]) < lane_clearance(size):
			return false
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is Node3D and _flat(spot, (player as Node3D).global_position) < GameSettings.beast_spawn_player_distance:
			return false
	for lane_name: String in _beasts:
		for beast: Variant in _beasts[lane_name]:
			if is_instance_valid(beast) and _flat(spot, (beast as EnemyBase)._home_position) \
					< home_spacing(size, (beast as EnemyBase)._beast_size):
				return false
	if _in_water(spot):
		return false
	if not _open_ground(spot, size):
		return false
	# Last, being the one that costs a route: a home that leads nowhere is an island.
	var route: PackedVector3Array = NavigationServer3D.map_get_path(_map, spot, _crystal_goal, true)
	return not route.is_empty() and route[route.size() - 1].distance_to(_crystal_goal) <= GameSettings.enemy_reach_crystal_tolerance


## Nothing but the ground itself within a beast's length of `spot`: no tree, rock or wall. A
## giant put down among trunks would stand wedged between them from its first step.
func _open_ground(spot: Vector3, size: float) -> bool:
	var radius: float = BODY_HALF_LENGTH * size
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Lifted so the sphere's bottom only grazes the ground, which a slope would otherwise fill.
	query.transform = Transform3D(Basis(), spot + Vector3.UP * (radius + 0.5))
	# Layer 1 as well: which layer TerraBrush's placed objects collide on is not settled
	# (.agents/learnings.md), and a tree it leaves out is a tree a giant spawns inside.
	query.collision_mask = EnemyBase.ENVIRONMENT_LAYER | 1
	var terrain: Object = _main.get("_terrain_body")
	if terrain is CollisionObject3D:
		query.exclude = [(terrain as CollisionObject3D).get_rid()]
	return (_main as Node3D).get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _in_water(spot: Vector3) -> bool:
	var terrain: Node = _main.get_node_or_null("TerraBrush")
	if terrain == null or not terrain.has_method("getPositionInformation"):
		return false
	var info: Object = terrain.call("getPositionInformation", spot.x, spot.z)
	return info != null and float(info.call("get_waterFactor")) > 0.05


## The beasts living in a biome now, for tests and debugging.
func beasts_in(lane_name: String) -> Array:
	return (_beasts.get(lane_name, []) as Array).filter(func(b: Variant) -> bool: return is_instance_valid(b))


## Whether `spot` lies in the wedge facing `dir` from the crystal, `margin` degrees in from its seams.
func in_wedge(spot: Vector3, dir: Vector3, margin: float = 0.0) -> bool:
	var flat := Vector3(spot.x - _crystal.x, 0.0, spot.z - _crystal.z)
	if flat.length_squared() < 0.01:
		return false
	return rad_to_deg(flat.angle_to(dir)) <= WEDGE_HALF_DEGREES - margin


func lane_dir(lane_name: String) -> Vector3:
	for lane: Dictionary in _lanes:
		if lane["name"] == lane_name:
			return lane["dir"]
	return Vector3.ZERO


## The flat distance from `spot` to the nearest point of a path.
static func distance_to_path(spot: Vector3, path: PackedVector3Array) -> float:
	var best: float = INF
	var at := Vector2(spot.x, spot.z)
	for i: int in range(path.size() - 1):
		var a := Vector2(path[i].x, path[i].z)
		var b := Vector2(path[i + 1].x, path[i + 1].z)
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)))
	if path.size() == 1:
		best = at.distance_to(Vector2(path[0].x, path[0].z))
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
