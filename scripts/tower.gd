extends StaticBody3D
## A tower one of the five round-two tower spells puts up (docs/SKILL_DESIGN.md, round two):
##   Ivory Tower          white  shields the allies and myrs around it
##   Glacial Fortress     blue   ice shots that slow; every fourth freezes
##   Bontu's Monument     black  deaths near it charge it; full, it raises a ghoul
##   Goblin Sharpshooter  red    very fast, very deadly shots - and it falls to anything
##   Hornet Nest          green  a tank that draws the wave and stings whoever hits it
##
## A body enemies can see and hit, the way a myr is one: on layer 2 (what an enemy's AggroArea
## and its projectiles look at) and in the `decoys` group (what EnemyBase.evaluate_target counts
## alongside the myrs). Bosses do not aim their specials at decoys, so a tower is never what a
## boss special is cast at - deliberate, and the same rule summons have.
##
## Everything it does is the server's; the spawner puts a copy on every screen and the health
## rides on its own synchronizer. How many of one kind a player has standing is the casting
## player's business (Player.place_tower), not the tower's.
##
## The look is `scenes/towers/<id>.tscn` - the Meshy model of the tower's reference
## (docs/screen_art/source/tower_references.md), its front turned to where the caster aimed -
## and a placeholder built here for a tower without one.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const IDS: Array[String] = ["ivory_tower", "glacial_fortress", "bontus_monument", "goblin_sharpshooter", "hornet_nest"]
const COLORS: Dictionary = {
	"ivory_tower": "white", "glacial_fortress": "blue", "bontus_monument": "black",
	"goblin_sharpshooter": "red", "hornet_nest": "green",
}
const TINTS: Dictionary = {
	"white": Color(1.0, 0.94, 0.72), "blue": Color(0.5, 0.78, 1.0), "black": Color(0.6, 0.32, 0.78),
	"red": Color(1.0, 0.45, 0.2), "green": Color(0.5, 0.9, 0.35),
}

var tower_id: String = ""
var rank: int = 1
var owner_player: Node3D = null
var health: float = 100.0
var max_health: float = 100.0

var _timer: float = 0.0
var _shots: int = 0
var _charges: int = 0
## Hornet Nest: attacker instance id -> msec its next sting is due.
var _stung: Dictionary = {}
var _bar: MeshInstance3D = null
## How tall and wide the look stands and where its shots leave, local to the tower: the
## placeholder's until a scene's meshes and its `Muzzle` marker say otherwise (_fit_to).
var _height: float = 3.0
var _radius: float = 0.8
var _muzzle_at: Vector3 = Vector3(0.0, 2.8, 0.0)


## A tower of `id` at `p_rank`, credited to `caster`. Not yet in the tree; MainController's
## build_effect places it.
static func create(id: String, p_rank: int, caster: Node3D) -> StaticBody3D:
	var tower: StaticBody3D = (load("res://scripts/tower.gd") as GDScript).new()
	tower.tower_id = id
	tower.rank = maxi(p_rank, 1)
	tower.owner_player = caster
	tower.max_health = _base_health(id) * GameSettings.rank_damage_mult(tower.rank)
	tower.health = tower.max_health
	return tower


static func _base_health(id: String) -> float:
	match id:
		"ivory_tower": return GameSettings.tower_ivory_health
		"glacial_fortress": return GameSettings.tower_glacial_health
		"bontus_monument": return GameSettings.tower_bontu_health
		"goblin_sharpshooter": return GameSettings.tower_goblin_health
		"hornet_nest": return GameSettings.tower_hornet_health
	return 200.0


func _ready() -> void:
	name = "Tower_%s" % tower_id
	add_to_group("towers")
	add_to_group("allies")
	add_to_group("decoys")
	collision_layer = 2
	collision_mask = 0
	_build_visual()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _radius
	cylinder.height = _height
	shape.shape = cylinder
	shape.position = Vector3(0.0, _height * 0.5, 0.0)
	add_child(shape)
	_build_bar()
	_build_synchronizer()
	if tower_id == "bontus_monument" and Net.is_server():
		SignalBus.enemy_died_at.connect(_on_death_near)


func is_targetable() -> bool:
	return health > 0.0


func _color() -> String:
	return String(COLORS.get(tower_id, "white"))


func _tint() -> Color:
	return TINTS.get(_color(), Color.WHITE)


# --- the look ----------------------------------------------------------------------------

func _build_visual() -> void:
	var path: String = "res://scenes/towers/%s.tscn" % tower_id
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		if scene != null:
			var look := scene.instantiate() as Node3D
			add_child(look)
			_fit_to(look)
			return
	add_child(_placeholder())


## The top of the scene's meshes is the tower's height, and the narrower side of its footprint
## sizes the body enemies walk into - kept under 1.3 m so a melee enemy (2 m reach, measured
## from the centre) still strikes it from where it stops. Its `Muzzle` marker, where it has one
## (the fortress's crystal, the sharpshooter's crossbow), is where shots leave - near the top
## if not.
func _fit_to(look: Node3D) -> void:
	var bounds := AABB()
	var first: bool = true
	for node: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var box: AABB = (global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first and bounds.end.y > 0.5:
		_height = bounds.end.y
		_radius = clampf(minf(bounds.size.x, bounds.size.z) * 0.42, 0.6, 1.3)
	var marker := look.get_node_or_null("Muzzle") as Node3D
	_muzzle_at = to_local(marker.global_position) if marker != null else Vector3(0.0, _height * 0.9, 0.0)


## Until the mesh from the card arrives: a stone column, a band of the colour's light at the
## top and a soft glow round it - readable as "a tower of that colour" from across the lane.
func _placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.44, 0.42)
	stone.roughness = 0.9
	if tower_id == "goblin_sharpshooter" or tower_id == "hornet_nest":
		stone.albedo_color = Color(0.38, 0.27, 0.16)
	var height: float = 2.6 if tower_id != "goblin_sharpshooter" else 2.0
	var column := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.7
	mesh.height = height
	column.mesh = mesh
	column.material_override = stone
	column.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(column)
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.38
	sphere.height = 0.76
	crown.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.albedo_color = _tint()
	glow.emission_enabled = true
	glow.emission = _tint()
	glow.emission_energy_multiplier = 2.2
	crown.material_override = glow
	crown.position = Vector3(0.0, height + 0.3, 0.0)
	root.add_child(crown)
	var light := OmniLight3D.new()
	light.light_color = _tint()
	light.light_energy = 1.6
	light.omni_range = 5.0
	light.position = Vector3(0.0, height + 0.3, 0.0)
	root.add_child(light)
	return root


func _build_bar() -> void:
	_bar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.12)
	_bar.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _tint()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.material_override = mat
	_bar.position = Vector3(0.0, _height + 0.6, 0.0)
	add_child(_bar)


func _build_synchronizer() -> void:
	if not Net.is_active():
		return
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(":health"))
	config.property_set_replication_mode(NodePath(":health"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(1)
	add_child(sync)


# --- what it does ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_instance_valid(_bar) and max_health > 0.0:
		_bar.scale.x = clampf(health / max_health, 0.05, 1.0)
	if not Net.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	match tower_id:
		"ivory_tower":
			_timer = GameSettings.tower_ivory_interval
			_shield_allies()
		"glacial_fortress":
			_timer = GameSettings.tower_glacial_interval
			_ice_shot()
		"goblin_sharpshooter":
			_timer = GameSettings.tower_goblin_interval
			_sharp_shot()
		"hornet_nest":
			# A nest is something the wave turns on: every few seconds it calls the enemies
			# round it, the way Roar does for a player.
			_timer = 3.0
			for enemy: Node3D in _enemies_within(GameSettings.tower_hornet_radius * 1.6):
				if enemy.has_method("apply_taunt"):
					enemy.apply_taunt(self, 2.5)
		_:
			_timer = 1.0


func _credit() -> Node3D:
	return owner_player if is_instance_valid(owner_player) else null


func _area() -> float:
	return GameSettings.rank_area_mult(rank)


func _damage(base: float) -> float:
	var damage: float = base * GameSettings.rank_damage_mult(rank)
	if owner_player is Player:
		damage *= (owner_player as Player).get_spell_damage_multiplier()
	return damage


func _enemies_within(radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.global_position.distance_to(global_position) <= radius:
			out.append(enemy)
	return out


func _nearest_enemy(radius: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = radius
	for enemy: Node3D in _enemies_within(radius):
		var distance: float = enemy.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _muzzle() -> Vector3:
	return to_global(_muzzle_at)


func _shield_allies() -> void:
	var radius: float = GameSettings.tower_ivory_radius * _area()
	var shield: float = GameSettings.tower_ivory_shield * GameSettings.rank_damage_mult(rank)
	var any: bool = false
	for node: Node in get_tree().get_nodes_in_group("player"):
		var ally := node as Node3D
		if ally == null or ally.global_position.distance_to(global_position) > radius:
			continue
		if ally.has_method("grant_protection_shield"):
			ally.grant_protection_shield(shield, GameSettings.tower_ivory_shield_duration)
			any = true
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		var myr := node as Node3D
		if myr != null and myr.global_position.distance_to(global_position) <= radius and myr.has_method("heal"):
			myr.heal(shield * 0.5)
			any = true
	if any:
		NetFx.ring(global_position, _tint(), radius)


func _ice_shot() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.tower_glacial_range * _area())
	if target == null:
		return
	_shots += 1
	var to: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	NetFx.beam(_muzzle(), (to - _muzzle()).normalized(), _muzzle().distance_to(to), _tint())
	if target.has_method("take_damage"):
		target.take_damage(_damage(GameSettings.tower_glacial_damage), _credit())
	if not is_instance_valid(target):
		return
	if _shots % maxi(GameSettings.tower_glacial_freeze_every, 1) == 0 and target.has_method("apply_equipment_freeze"):
		target.apply_equipment_freeze(GameSettings.tower_glacial_freeze)
		NetFx.impact(to, _tint(), 0.9)
	elif target.has_method("apply_frost_slow"):
		target.apply_frost_slow(GameSettings.tower_glacial_slow)


func _sharp_shot() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.tower_goblin_range * _area())
	if target == null:
		return
	var to: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	NetFx.beam(_muzzle(), (to - _muzzle()).normalized(), _muzzle().distance_to(to), Color(0.95, 0.85, 0.6))
	if target.has_method("take_damage"):
		target.take_damage(_damage(GameSettings.tower_goblin_damage), _credit())


## Bontu's Monument: a death in reach is a charge; a full monument raises a ghoul.
func _on_death_near(at: Vector3) -> void:
	if not is_inside_tree() or at.distance_to(global_position) > GameSettings.tower_bontu_radius * _area():
		return
	_charges += 1
	NetFx.impact(_muzzle(), _tint(), 0.4)
	if _charges < GameSettings.tower_bontu_charges:
		return
	_charges = 0
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("request_effect"):
		return
	var colors: Array = ["White", "Blue", "Black", "Red", "Green"]
	scene.request_effect({
		"kind": "undead", "position": global_position + Vector3(1.5, 0.0, 0.0),
		"hp": GameSettings.tower_bontu_ghoul_health * GameSettings.rank_damage_mult(rank),
		"duration": GameSettings.tower_bontu_ghoul_duration,
		"damage": 0.0,
		"hit_damage": _damage(GameSettings.tower_bontu_ghoul_damage),
		"color": colors[randi() % colors.size()], "class": "Melee",
		"caster": int(owner_player.get_multiplayer_authority()) if is_instance_valid(owner_player) else 0,
	})
	NetFx.ring(global_position, _tint(), 2.5)


func take_damage(amount: float, source: Node3D = null, _is_melee: bool = false, _exile: bool = false) -> void:
	if not Net.is_server() or health <= 0.0:
		return
	health -= amount * Player.anthem_damage_taken_mult(self)
	NetFx.damage_number(global_position + Vector3(0.0, _height + 0.2, 0.0), amount, Color(0.85, 0.85, 0.95), "")
	if tower_id == "hornet_nest" and source is EnemyBase and is_instance_valid(source):
		_sting(source)
	if health <= 0.0:
		NetFx.impact(global_position + Vector3(0.0, _height * 0.5, 0.0), _tint(), 1.4)
		queue_free()


## Hornet Nest: whoever hits it is stung, once every sting_cooldown, and everything near it too.
func _sting(attacker: Node3D) -> void:
	var key: int = attacker.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if now < int(_stung.get(key, 0)):
		return
	_stung[key] = now + int(GameSettings.tower_hornet_sting_cooldown * 1000.0)
	var damage: float = _damage(GameSettings.tower_hornet_sting)
	for enemy: Node3D in _enemies_within(GameSettings.tower_hornet_radius * _area()):
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage if enemy == attacker else damage * 0.5, _credit())
	NetFx.impact(attacker.global_position + Vector3(0.0, 1.2, 0.0), Color(0.95, 0.85, 0.3), 0.7)
