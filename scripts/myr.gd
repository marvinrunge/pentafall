extends CharacterBody3D
class_name Myr
## Worship (white_10) - see take_damage.
const _round_two := preload("res://scripts/round_two_spells.gd")

enum State {
	IDLE,
	SPAWNING,
	WALKING_TO_MANA,
	HARVESTING,
	WALKING_TO_CRYSTAL,
	DEPOSITING,
	## A worker running from danger: behind its lane's guard, or home (docs/MYR_GUARDS_PLAN.md).
	FLEEING,
	## A guard at - or on its way back to - its post by its lane's well.
	GUARDING,
	## A guard taking on what threatens its lane's workers.
	FIGHTING,
}

## What this myr is. A worker harvests; the two guards do not, and stand at their lane's well
## instead (docs/MYR_GUARDS_PLAN.md). Set from the spawn arguments before _ready, so every peer
## builds the same kind - it never changes after.
const ROLE_WORKER := "worker"
const ROLE_ENFORCER := "enforcer"
const ROLE_LODESTONE := "lodestone"
## A guard's placeholder look until its own model is delivered: the lane's myr model, bigger,
## lit in its own colour - bronze for the Enforcer, a magnetic violet for the Lodestone.
const ROLE_TINTS := {
	ROLE_ENFORCER: Color(1.0, 0.55, 0.15),
	ROLE_LODESTONE: Color(0.62, 0.4, 1.0),
}
const ROLE_NAMES := {
	ROLE_WORKER: "Myr",
	ROLE_ENFORCER: "Myr Enforcer",
	ROLE_LODESTONE: "Lodestone Myr",
}

# color identity (matches scripts/main.gd's LANE_NAMES) -> rigged model. Built
# by tools/myr_character_builder.gd; each scene carries its own animation
# library ("walk", "walk_loaded", "harvest", "hit", "death", and "run" for a
# future speed buff - not wired up anywhere yet).
const VISUAL_SCENES := {
	"White": "res://scenes/myrs/gold_myr.tscn",
	"Blue": "res://scenes/myrs/silver_myr.tscn",
	"Black": "res://scenes/myrs/leaden_myr.tscn",
	"Red": "res://scenes/myrs/iron_myr.tscn",
	"Green": "res://scenes/myrs/copper_myr.tscn",
}

@export var speed: float = GameSettings.myr_speed

## Reused from the minibosses rather than written again - it is the same job (tint a rigged
## model in a colour without touching the material every other copy of that model shares)
## and the same answer.
const CARRY_GLOW_SHADER: Shader = preload("res://assets/shaders/miniboss_glow.gdshader")

var current_state: State = State.SPAWNING
var target_mana_source: Node3D
var target_crystal: Node3D
var lane_index: int = -1
var health: float = GameSettings.myr_max_hp
var max_health: float = GameSettings.myr_max_hp
## What the player calls this one. Empty means they never named it, and the base screen
## shows a positional "Myr 3" instead - a default name stored here would be wrong the
## moment an earlier myr died and the numbering shifted under it.
var display_name: String = ""
## Bought in the base, per myr. Raises health and how much mana it carries home; see
## set_level and carry_amount.
var level: int = 1
var fervor_active: bool = false
var is_dying: bool = false
var role: String = ROLE_WORKER

## Who this myr is across deaths: the Graveyard keeps it by this, and a myr returned from it
## comes back under the same one. Handed out by RunState.next_myr_id, server side.
var record_id: int = 0
## Mana put into it - what it was built for plus every level bought. What a return from the
## Graveyard costs a share of (RunState.return_cost).
var invested: int = 0
## Stats, replicated, shown on its row in the base screen and summed at Upkeep. They survive a
## death and a return.
var mana_delivered: int = 0
var trips: int = 0
var times_fled: int = 0
var deaths: int = 0
## Guards only: what it killed, and the attacks on its workers it took on.
var kills: int = 0
var intercepts: int = 0
## Bumped by the server on every guard blow and replicated, so each peer plays the swing once.
var attack_serial: int = 0

# A lane change requested while this Myr is already out working one is queued
# here rather than applied immediately - it takes effect the next time this
# Myr sets out from the crystal (see the State.DEPOSITING branch of
# _physics_process), so reassigning never yanks it off a delivery in progress.
var _pending_lane_index: int = -1
var _pending_mana_source: Node3D

var visual_anim_player: AnimationPlayer
## Surface materials swapped in to make a loaded myr glow, kept so the glow can be taken
## off again on deposit. Empty whenever the myr is walking out empty-handed.
var _carry_glow_surfaces: Array = []
var _carrying: bool = false
## Blue, Propaganda: seconds this myr is still phased out of reach. Only ever set while
## carrying - see take_damage.
var _phase_left: float = 0.0
var _current_color: String = ""

# The slot at the well this Myr stands in while harvesting, so five Myrs fan out
# around one well the way workers fan around a mine rather than stacking on its
# centre - which is also what kept them wedged against the well's collision.
var _well_slot_offset: Vector3 = Vector3.ZERO

# Timer properties
var harvest_time: float = GameSettings.myr_harvest_time
var deposit_time: float = 1.0
var state_timer: float = 0.0

# Fleeing (workers, server only). See _update_danger.
var _danger_timer: float = randf() * GameSettings.myr_danger_check_interval
## What it was doing when it ran, to go back to; a harvest broken off keeps what it had left.
var _resume_state: State = State.WALKING_TO_MANA
var _harvest_left: float = 0.0
## Where the threat was last seen, and where the myr is running to.
var _flee_from: Vector3 = Vector3.ZERO
var _flee_point: Vector3 = Vector3.ZERO
## Seconds nothing hostile has been inside myr_return_radius.
var _calm_time: float = 0.0
## A LOADED worker in danger does not change course - home is where it was going - it runs.
var _running_home: bool = false

# Guarding (guards, server only). See _guard_process.
var _guard_target: Node3D = null
var _guard_think_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _taunt_timer: float = 0.0
var _seen_attack_serial: int = 0
## On a client: whether the server's copy moved since the last frame, for the walk-or-stand
## choice a velocity makes on the server.
var _puppet_moving: bool = false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Add to group so enemies can find Myrs. Guards are in it too - enemies go for them, heals
	# and shields reach them - and in a group of their own besides (see is_guard).
	add_to_group("myrs")
	if has_meta("myr_role"):
		role = String(get_meta("myr_role"))
	if is_guard():
		add_to_group("myr_guards")
		speed = GameSettings.myr_guard_speed
	max_health = _base_health() + float(level - 1) * GameSettings.myr_level_hp_bonus
	health = max_health
	SignalBus.player_auras_changed.connect(_refresh_fervor_state)
	_refresh_fervor_state()
	
	# Set collision layer and mask
	# Layer 2: Myr (binary: 2)
	collision_layer = 2
	# Mask: Layer 3 (Enemies), Layer 5 (Environment/Static)
	# Layer 3 = 4, Layer 5 = 16. Total mask = 4 + 16 = 20.
	collision_mask = 20
	# A myr spawned already levelled (loaded from a save, or replicated to a client that
	# joined mid-run) never passes through set_level, so the size is applied here too.
	_apply_level_scale()
	_build_synchronizer()
	
	# Read metadata targets set by map generator
	if has_meta("target_mana_source"):
		target_mana_source = get_meta("target_mana_source")
	else:
		# Fallback: search in group
		var sources = get_tree().get_nodes_in_group("mana_sources")
		if sources.size() > 0:
			# Just pick one if none was assigned
			target_mana_source = sources[0]
			
	if has_meta("target_crystal"):
		target_crystal = get_meta("target_crystal")
	else:
		var crystal_nodes = get_tree().get_nodes_in_group("crystal")
		if crystal_nodes.size() > 0:
			target_crystal = crystal_nodes[0]
			
	if has_meta("lane_index"):
		lane_index = get_meta("lane_index")

	# Initialize state
	if lane_index >= 0 and target_mana_source:
		current_state = State.GUARDING if is_guard() else State.WALKING_TO_MANA
		_apply_color_visual(_lane_color())
		update_navigation_target()
	else:
		current_state = State.IDLE


## Whether this is one of the two guards rather than a worker.
func is_guard() -> bool:
	return role != ROLE_WORKER


## What its kind is called, for the base screen.
func role_name() -> String:
	return String(ROLE_NAMES.get(role, "Myr"))


## Health at level 1, by kind.
func _base_health() -> float:
	match role:
		ROLE_ENFORCER:
			return GameSettings.myr_enforcer_hp
		ROLE_LODESTONE:
			return GameSettings.myr_lodestone_hp
	return GameSettings.myr_max_hp


## What the Graveyard keeps of it, and what a return builds it again from. Plain values only -
## it travels to every peer in RunState's state and back through the MyrNetSpawner.
func record() -> Dictionary:
	return {
		"id": record_id, "role": role, "name": display_name, "level": level, "lane": lane_index,
		"invested": invested, "mana_delivered": mana_delivered, "trips": trips,
		"times_fled": times_fled, "deaths": deaths, "kills": kills, "intercepts": intercepts,
	}


## The other way: a myr built from a record (MainController._spawn_myr), before _ready.
func apply_record(data: Dictionary) -> void:
	record_id = int(data.get("id", 0))
	display_name = String(data.get("name", ""))
	level = clampi(int(data.get("level", 1)), 1, GameSettings.myr_max_level)
	invested = int(data.get("invested", 0))
	mana_delivered = int(data.get("mana_delivered", 0))
	trips = int(data.get("trips", 0))
	times_fled = int(data.get("times_fled", 0))
	deaths = int(data.get("deaths", 0))
	kills = int(data.get("kills", 0))
	intercepts = int(data.get("intercepts", 0))

## Called from the base UI, any time, for any Myr. A Myr that hasn't been
## given a lane yet (fresh off the build queue, still IDLE) starts immediately
## - there's no delivery in progress to protect. One that's already working a
## lane instead has the change queued for its next departure from the crystal.
func assign_lane(index: int, source: Node3D) -> void:
	# A guard has no delivery to protect, and a lane with no guard is unguarded right now.
	if lane_index == -1 or is_guard():
		_commit_lane(index, source)
	else:
		_pending_lane_index = index
		_pending_mana_source = source


## Claims one of the well's harvest slots, if there is a free one. MainController owns
## the per-well registry, because a Myr only knows its own lane, not its colleagues'.
func claim_well_slot() -> bool:
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("claim_well_slot"):
		return main_node.claim_well_slot(self, lane_index)
	return true


func release_well_slot() -> void:
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("release_well_slot"):
		main_node.release_well_slot(self)


func set_well_slot_offset(offset: Vector3) -> void:
	_well_slot_offset = offset
	if current_state == State.WALKING_TO_MANA:
		update_navigation_target()

func _commit_lane(index: int, source: Node3D) -> void:
	lane_index = index
	target_mana_source = source
	current_state = State.GUARDING if is_guard() else State.WALKING_TO_MANA
	_guard_target = null
	_apply_color_visual(_lane_color())
	update_navigation_target()
	_pending_lane_index = -1
	_pending_mana_source = null

## Resolves this Myr's own lane color, matching how start_depositing() already
## looks it up (scripts/main.gd's LANE_NAMES).
func _lane_color() -> String:
	var main_node = get_tree().current_scene
	if main_node and "LANE_NAMES" in main_node and lane_index >= 0 and lane_index < main_node.LANE_NAMES.size():
		return main_node.LANE_NAMES[lane_index]
	return ""

## How much this myr brings back per trip. Levels are worth more to a myr that is already
## walking the route than a second myr would be, because the walk is the cost.
func carry_amount() -> int:
	return 1 + (level - 1) * GameSettings.myr_level_carry_bonus


## Sets the level and rebuilds what depends on it.
##
## The health GAIN arrives as health rather than only as headroom: a level bought while
## hurt that left the bar at the same number, only further from full, would read as having
## done nothing.
func set_level(new_level: int) -> void:
	var clamped: int = clampi(new_level, 1, GameSettings.myr_max_level)
	if clamped == level:
		return
	var gained: float = float(clamped - level) * GameSettings.myr_level_hp_bonus
	level = clamped
	max_health = _base_health() + float(level - 1) * GameSettings.myr_level_hp_bonus
	health = minf(max_health, health + maxf(gained, 0.0))
	_apply_level_scale()


## A loaded myr glows in the colour of what it is carrying.
##
## The myr economy is the quietest thing in the game: a myr walks out, stands at a well for
## ten seconds and walks back, and none of that reads at a glance as "this one is bringing
## you mana". The glow is the tell - a myr coming home lit up in its lane's colour is one
## the player can see working, and one an enemy killing it is visibly taking something off.
##
## Applied as a second render PASS on a duplicated material, exactly as EnemyBase does for
## a miniboss: the mesh's own material is shared with every other myr wearing this model,
## so tinting it in place would light up the whole fleet.
func _set_carrying(carrying: bool) -> void:
	if carrying == _carrying:
		return
	_carrying = carrying
	if not carrying:
		_clear_carry_glow()
		return
	_apply_glow(GameSettings.lane_tint(_lane_color()))


## Lights the model with a second render pass in `tint` - the carry glow, and a guard's own
## colour while its placeholder model stands in for the real one.
func _apply_glow(tint: Color) -> void:
	var glow_material := ShaderMaterial.new()
	glow_material.shader = CARRY_GLOW_SHADER
	glow_material.set_shader_parameter("glow_color", tint)

	var skeleton: Skeleton3D = find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	for child: Node in skeleton.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		for surface: int in range(mesh_instance.get_surface_override_material_count()):
			var base_material: Material = mesh_instance.get_active_material(surface)
			if base_material == null:
				continue
			var duplicated: Material = base_material.duplicate()
			duplicated.next_pass = glow_material
			mesh_instance.set_surface_override_material(surface, duplicated)
			_carry_glow_surfaces.append([mesh_instance, surface])


## Puts every surface the glow touched back to the model's own material. Cleared by
## reference rather than by re-duplicating, so a myr that changed colour mid-route (a lane
## reassignment commits on deposit) cannot leave a stale tint behind.
func _clear_carry_glow() -> void:
	for entry: Array in _carry_glow_surfaces:
		var mesh_instance: MeshInstance3D = entry[0]
		if is_instance_valid(mesh_instance):
			mesh_instance.set_surface_override_material(int(entry[1]), null)
	_carry_glow_surfaces.clear()


## Size, as a function of level. The whole node rather than just the visual, so the body a
## bigger myr presents to the enemies chasing it grows with it - a level is supposed to
## make it survive the walk, and half of surviving is being the thing that got noticed.
func _apply_level_scale() -> void:
	var factor: float = 1.0 + float(level - 1) * GameSettings.myr_level_scale_bonus
	match role:
		ROLE_ENFORCER:
			factor *= GameSettings.myr_enforcer_scale
		ROLE_LODESTONE:
			factor *= GameSettings.myr_lodestone_scale
	scale = Vector3.ONE * factor


## What the base screen calls this myr. `fallback_index` is its position in the list, used
## only when the player has not named it.
func label(fallback_index: int) -> String:
	return display_name if display_name.strip_edges() != "" else "%s %d" % [role_name(), fallback_index]


## `amount` is what reached the myr; the two enchantments that protect it are applied here.
##
## White is flat armour and always applies. Blue is intermittent and only while LOADED: the
## hit that starts the phase still lands, and the follow-ups inside the window do not, so
## it buys a myr the seconds it needs to finish a delivery rather than making it tougher.
## A myr walking out empty-handed gets nothing from Blue at all.
func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false) -> void:
	if is_dying or _phase_left > 0.0:
		return
	amount *= 1.0 - RunState.myr_damage_reduction()
	# A knight's Phalanx shelters the myrs behind it as it shelters the team.
	amount *= Player.phalanx_damage_taken_mult(self)
	if _carrying:
		var phase: float = RunState.myr_phase_duration()
		if phase > 0.0:
			_phase_left = phase
	health = maxf(0.0, health - amount)
	# Worship (white_10): nothing takes a myr's last point of health on hallowed ground.
	if health < 1.0 and _round_two.protects(global_position):
		health = 1.0
	NetFx.damage_number(global_position + Vector3(0, 1.2, 0), amount, Color(1.0, 0.25, 0.25), "")
	if health <= 0.0:
		die()
	elif visual_anim_player and visual_anim_player.has_animation("hit"):
		visual_anim_player.play("hit")

## Returns the health actually restored, matching Player.heal - the white skills that heal
## myrs credit that number to the caster's scoreboard, and a myr already at full health should
## not pay out for a heal it could not use.
func heal(amount: float) -> float:
	var previous_health: float = health
	health = minf(max_health, health + amount)
	if health > previous_health:
		NetFx.damage_number(global_position + Vector3(0, 1.2, 0), previous_health - health, Color(0.2, 1.0, 0.4), "")
	return health - previous_health

## Whether anything may pick this myr as a target. Enemies check it in _acquire_target and
## in their special targeting, so a phased myr is walked away from rather than swung at.
func is_targetable() -> bool:
	return not is_dying and _phase_left <= 0.0


func die() -> void:
	if is_dying:
		return
	_phase_left = 0.0
	visible = true
	_myr_death_blast()
	is_dying = true
	# To the Graveyard, from where it can be returned. The server's word, like the death.
	if Net.is_server():
		deaths += 1
		RunState.bury(record())
	remove_from_group("myrs")
	release_well_slot()
	collision_layer = 0
	collision_mask = 0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		visual_anim_player.play("death")
		var death_anim: Animation = visual_anim_player.get_animation("death")
		get_tree().create_timer(death_anim.length).timeout.connect(queue_free)
	else:
		queue_free()

## Black, Animate Dead: a myr that dies takes the neighbourhood with it.
##
## Server-only. Myr._physics_process has no authority guard and every peer runs its own
## copy of the state machine, so an unguarded blast would be dealt once per peer - and the
## FX go out through NetFx from here for the same reason, so every peer sees one blast
## rather than each spawning its own.
func _myr_death_blast() -> void:
	var damage: float = RunState.myr_blast_damage()
	var radius: float = RunState.myr_blast_radius()
	if damage <= 0.0 or radius <= 0.0 or not Net.is_server():
		return
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if global_position.distance_to((enemy as Node3D).global_position) > radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, self, false)
	var tint: Color = GameSettings.lane_tint(_lane_color())
	NetFx.impact(global_position, tint, radius)
	NetFx.ring(global_position, tint, radius)


# --- network -------------------------------------------------------------------------
#
# Every peer used to run its own copy of the state machine, which only ever worked for the
# server: the lane is assigned from the base screen, and that only runs where the click
# happened, so a client's copy sat IDLE at the crystal forever - and an IDLE myr has no
# model, so clients saw no myrs at all. The server's myr is the real one now and a client
# draws it from what the synchroniser says, the same split EnemyBase uses.

## Where this myr is and which way it faces, written on a client by the synchroniser.
var net_position: Vector3:
	get:
		return position
	set(value):
		if not _net_target_position.is_finite():
			position = value
		_net_target_position = value
var net_yaw: float:
	get:
		return rotation.y
	set(value):
		_net_target_yaw = value
## `current_state` as an int - an enum-typed property replicates as one anyway, and this
## keeps the setter from fighting the server's own writes.
var net_state: int:
	get:
		return int(current_state)
	set(value):
		current_state = value as State
## `_carrying` is private and has a side effect; the glow is applied on the client in
## _update_puppet when this changes.
var net_carrying: bool:
	get:
		return _carrying
	set(value):
		_net_carrying = value

var _net_target_position: Vector3 = Vector3.INF
var _net_target_yaw: float = 0.0
var _net_carrying: bool = false
var _puppet_died: bool = false


func _is_puppet() -> bool:
	return Net.is_active() and not Net.is_server()


func _build_synchronizer() -> void:
	if not Net.is_active():
		return
	var config := SceneReplicationConfig.new()
	for property: String in [":net_position", ":net_yaw"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for property: String in [":lane_index", ":net_state", ":net_carrying", ":level",
			":health", ":max_health", ":is_dying", ":display_name", ":record_id", ":invested",
			":mana_delivered", ":trips", ":times_fled", ":deaths", ":kills", ":intercepts", ":attack_serial"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(1)
	sync.replication_interval = GameSettings.enemy_net_interval
	add_child(sync)


## A client's whole job for a myr: follow the server's copy and look like it.
func _update_puppet(delta: float) -> void:
	if _net_target_position.is_finite():
		_puppet_moving = position.distance_squared_to(_net_target_position) > 0.0025
		position = position.lerp(_net_target_position, clampf(12.0 * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _net_target_yaw, clampf(10.0 * delta, 0.0, 1.0))
	if lane_index >= 0:
		_apply_color_visual(_lane_color())
	_apply_level_scale()
	if attack_serial != _seen_attack_serial:
		_seen_attack_serial = attack_serial
		_play_strike()
	if _net_carrying != _carrying:
		_set_carrying(_net_carrying)
	if is_dying:
		if not _puppet_died:
			_puppet_died = true
			remove_from_group("myrs")
			collision_layer = 0
			collision_mask = 0
			if visual_anim_player and visual_anim_player.has_animation("death"):
				visual_anim_player.play("death")
		return
	_update_visual_animation()


func _refresh_fervor_state() -> void:
	fervor_active = false
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.has_method("has_aura") and player.has_aura("aura_fervor"):
			fervor_active = true
			return

## A Myr with no lane/colour assigned yet has no model - showing any shape here
## reads as a real unit already working the field, when it's actually just
## sitting unassigned at the crystal. Gives this Myr the rigged model matching
## `color`, once assign_lane() (or pre-set spawn metadata) makes it known - and
## replaces it if a queued reassignment (_commit_lane, once a delivery finishes)
## changes the colour later. A no-op if `color` is what it already has.
func _apply_color_visual(color: String) -> void:
	if not VISUAL_SCENES.has(color) or color == _current_color:
		return
	if visual_anim_player and is_instance_valid(visual_anim_player):
		visual_anim_player.get_parent().queue_free()
		visual_anim_player = null

	# The old model's surfaces are about to be freed with it, so anything still pointing
	# at them has to go first.
	_carry_glow_surfaces.clear()
	var visual_scene: PackedScene = load(VISUAL_SCENES[color])
	var visual_instance: Node3D = visual_scene.instantiate()
	# Scale correction: imported models are tiny (~0.016m). We scale them up 100x to match a 1-unit base.
	visual_instance.scale = Vector3(100, 100, 100)
	add_child(visual_instance)
	_ground_visual(visual_instance)
	visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
	_current_color = color
	if ROLE_TINTS.has(role):
		_apply_glow(ROLE_TINTS[role])
	_rest_visual_animation()


func _ground_visual(visual_instance: Node3D) -> void:
	var skeleton: Skeleton3D = visual_instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var mesh_instance: MeshInstance3D = null
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		return
	var local_aabb: AABB = mesh_instance.get_aabb()
	var min_y: float = INF
	for corner_idx: int in range(8):
		var corner: Vector3 = local_aabb.position + Vector3(
			local_aabb.size.x * float(corner_idx & 1),
			local_aabb.size.y * float((corner_idx >> 1) & 1),
			local_aabb.size.z * float((corner_idx >> 2) & 1)
		)
		min_y = min(min_y, (mesh_instance.global_transform * corner).y)
	if is_finite(min_y):
		visual_instance.position.y -= min_y - global_position.y

func _play_visual_animation(anim_name: String) -> void:
	if visual_anim_player.current_animation != anim_name or not visual_anim_player.is_playing():
		visual_anim_player.play(anim_name)

## No dedicated idle clip for the empty-handed state - hold the first frame of
## "walk" instead, same reasoning as EnemyBase._rest_visual_animation().
func _rest_visual_animation() -> void:
	if visual_anim_player.current_animation != "walk":
		visual_anim_player.play("walk")
	if visual_anim_player.is_playing():
		visual_anim_player.pause()

func _update_visual_animation() -> void:
	if not visual_anim_player:
		return
	# Let a triggered "hit" reaction finish before any state-driven clip
	# overrides it, same pattern as EnemyBase's attack-swing check.
	if visual_anim_player.current_animation == "hit" and visual_anim_player.is_playing():
		return
	# A guard's blow is played by _play_strike and left to finish, like the hit reaction.
	if is_guard() and visual_anim_player.current_animation == "harvest" and visual_anim_player.is_playing():
		return
	match current_state:
		State.WALKING_TO_MANA:
			_play_visual_animation("walk")
		State.WALKING_TO_CRYSTAL:
			_play_visual_animation("walk_loaded")
		State.HARVESTING, State.DEPOSITING:
			_play_visual_animation("harvest")
		State.FLEEING, State.GUARDING, State.FIGHTING:
			if _is_moving():
				_play_visual_animation("run" if visual_anim_player.has_animation("run") else "walk")
			else:
				_rest_visual_animation()
		_:
			_rest_visual_animation()


func _is_moving() -> bool:
	if _is_puppet():
		return _puppet_moving
	return Vector2(velocity.x, velocity.z).length_squared() > 0.04

func update_navigation_target() -> void:
	if not nav_agent:
		return
	
	match current_state:
		State.WALKING_TO_MANA:
			if target_mana_source:
				# The slot, not the centre: five Myrs heading for the same point on the
				# well is what jammed them against it and against each other.
				nav_agent.target_position = target_mana_source.global_position + _well_slot_offset
		State.WALKING_TO_CRYSTAL:
			if target_crystal:
				nav_agent.target_position = target_crystal.global_position
		State.FLEEING:
			nav_agent.target_position = _flee_point
		State.GUARDING:
			nav_agent.target_position = guard_post()
		State.FIGHTING:
			if is_instance_valid(_guard_target):
				nav_agent.target_position = _guard_target.global_position

func _physics_process(delta: float) -> void:
	if _is_puppet():
		_update_puppet(delta)
		return
	if is_dying:
		return

	var current_speed: float = speed
	if fervor_active:
		current_speed *= GameSettings.aura_fervor_speed_boost
	# Red, Furnace of Rath. Multiplied alongside Fervor rather than instead of it: they are
	# different sources and a team that has bought both should get both.
	current_speed *= RunState.myr_speed_multiplier()

	if _phase_left > 0.0:
		_phase_left -= delta
		# Flickering IS the tell. There is no other way to see that a myr cannot be hit,
		# and the alternative - tinting it - is already spoken for by the carry glow.
		visible = int(_phase_left * 12.0) % 2 == 0
		if _phase_left <= 0.0:
			visible = true

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if is_guard():
		_guard_process(delta, current_speed)
		_update_visual_animation()
		return

	_danger_timer -= delta
	if _danger_timer <= 0.0:
		_danger_timer = GameSettings.myr_danger_check_interval
		_update_danger(GameSettings.myr_danger_check_interval)
	if _running_home and current_state == State.WALKING_TO_CRYSTAL:
		current_speed *= GameSettings.myr_flee_speed_mult
		
	# Process states
	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)
			move_and_slide()
		State.FLEEING:
			if nav_agent.is_navigation_finished():
				velocity.x = 0.0
				velocity.z = 0.0
				move_and_slide()
			else:
				_step_along_path(current_speed * GameSettings.myr_flee_speed_mult, delta)
		State.WALKING_TO_MANA, State.WALKING_TO_CRYSTAL:
			if nav_agent.is_navigation_finished():
				if current_state == State.WALKING_TO_MANA:
					start_harvesting()
				else:
					start_depositing()
			else:
				var next_path_position = nav_agent.get_next_path_position()
				var current_agent_position = global_position
				var new_velocity = (next_path_position - current_agent_position).normalized() * current_speed
				velocity.x = new_velocity.x
				velocity.z = new_velocity.z
				
				# Rotate to face direction
				if velocity.length_squared() > 0.01:
					var target_rotation = atan2(velocity.x, velocity.z)
					rotation.y = lerp_angle(rotation.y, target_rotation, 10.0 * delta)
				
				move_and_slide()
				
		State.HARVESTING:
			velocity.x = 0.0
			velocity.z = 0.0
			_set_carrying(false)
			# move_and_slide() must still run every frame even while stationary -
			# it's the only thing that applies the gravity integrated above and
			# refreshes is_on_floor(). Skipping it let velocity.y fall unbounded
			# for the whole harvest_time, and the next move (WALKING_TO_CRYSTAL)
			# would have to resolve several seconds of pent-up fall speed in one
			# slide, which could jam the Myr into the well's collision instead of
			# walking off - the "stuck at the mana well" symptom.
			move_and_slide()
			state_timer -= delta
			if state_timer <= 0.0:
				current_state = State.WALKING_TO_CRYSTAL
				# Full, and it should look it from across the lane - see _set_carrying.
				_set_carrying(true)
				update_navigation_target()

		State.DEPOSITING:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			state_timer -= delta
			if state_timer <= 0.0:
				if _pending_lane_index != -1:
					_commit_lane(_pending_lane_index, _pending_mana_source)
				else:
					current_state = State.WALKING_TO_MANA
					update_navigation_target()

	_update_visual_animation()

func start_harvesting() -> void:
	current_state = State.HARVESTING
	# A harvest broken off by danger picks up where it stopped.
	state_timer = _harvest_left if _harvest_left > 0.0 else harvest_time
	_harvest_left = 0.0

func start_depositing() -> void:
	current_state = State.DEPOSITING
	state_timer = deposit_time
	_set_carrying(false)
	_running_home = false

	var color := _lane_color()
	mana_delivered += carry_amount()
	trips += 1
	SignalBus.mana_deposited.emit(color if color != "" else "Colorless", carry_amount())


## One step along the agent's path at `move_speed`, facing the way it goes.
func _step_along_path(move_speed: float, delta: float) -> void:
	var next_path_position: Vector3 = nav_agent.get_next_path_position()
	var new_velocity: Vector3 = (next_path_position - global_position).normalized() * move_speed
	velocity.x = new_velocity.x
	velocity.z = new_velocity.z
	if velocity.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 10.0 * delta)
	move_and_slide()


# --- fleeing (workers) ----------------------------------------------------------------
#
# A worker cannot fight and cannot outrun anything at 2 m/s, so it leaves early - before a melee
# enemy has noticed it - and goes back to work once the lane is quiet again. Behind its lane's
# guard when there is a living one, home to the crystal when there is not; a loaded worker keeps
# going home, faster. A lane a player has cleared is a lane its myrs work undisturbed.

## Server, every myr_danger_check_interval.
func _update_danger(interval: float) -> void:
	if lane_index < 0 or current_state in [State.IDLE, State.SPAWNING, State.DEPOSITING]:
		return
	var threat: Node3D = _nearest_threat(GameSettings.myr_flee_radius)
	var calm: bool = threat == null and _nearest_threat(GameSettings.myr_return_radius) == null
	if current_state == State.FLEEING:
		if calm:
			_calm_time += interval
			if _calm_time >= GameSettings.myr_return_delay:
				_end_flee()
			return
		_calm_time = 0.0
		if threat != null:
			_flee_from = threat.global_position
		_refresh_flee_point()
		return
	if _running_home:
		if calm:
			_running_home = false
		return
	if threat == null:
		return
	times_fled += 1
	_flee_from = threat.global_position
	if current_state == State.WALKING_TO_CRYSTAL:
		_running_home = true
		return
	_resume_state = current_state
	if current_state == State.HARVESTING:
		_harvest_left = state_timer
	current_state = State.FLEEING
	_calm_time = 0.0
	_refresh_flee_point()


## The nearest enemy that is a danger to this myr: inside `radius`, or already after it from
## any distance. A storming enemy is deaf to myrs (EnemyBase.begin_storm) and is no danger.
func _nearest_threat(radius: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = radius * radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dying or enemy.is_queued_for_deletion() or enemy.storm_timer > 0.0:
			continue
		var off: Vector3 = enemy.global_position - global_position
		var distance: float = off.x * off.x + off.z * off.z
		if enemy.current_target == self:
			distance = minf(distance, 0.0)
		elif enemy.is_beast():
			# A wild beast keeps to its home and goes only for what comes close; one living near
			# a well must not keep that well's myrs from it for good.
			var beast_reach: float = minf(radius, GameSettings.beast_aggro_radius + GameSettings.myr_beast_flee_margin)
			if distance > beast_reach * beast_reach:
				continue
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best


## Where to run to: behind the lane's guard, on the far side from the threat, while it stands
## strong enough to be shelter - otherwise home.
func _refresh_flee_point() -> void:
	var guard: Node3D = lane_guard()
	if guard != null and guard.health >= guard.max_health * GameSettings.myr_guard_shelter_min_health:
		var away: Vector3 = guard.global_position - _flee_from
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		_flee_point = guard.global_position + away.normalized() * GameSettings.myr_guard_shelter_distance
	elif target_crystal != null:
		_flee_point = target_crystal.global_position
	else:
		_flee_point = global_position
	update_navigation_target()


## Whether it is running to a guard right now, rather than home.
func is_sheltering() -> bool:
	if current_state != State.FLEEING:
		return false
	return target_crystal == null or _flee_point.distance_to(target_crystal.global_position) > 0.5


func _end_flee() -> void:
	_calm_time = 0.0
	# Back to the slot either way: one that was harvesting walks back and picks it up again.
	current_state = State.WALKING_TO_MANA
	update_navigation_target()


## The living guard of this myr's lane, or null.
func lane_guard() -> Node3D:
	if lane_index < 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("myr_guards"):
		if node != self and not node.is_dying and int(node.lane_index) == lane_index:
			return node as Node3D
	return null


# --- guarding (Myr Enforcer, Lodestone Myr) ----------------------------------------------
#
# A guard stands at its post by the lane's well and takes on what comes within its leash, or
# what attacks one of its workers a little further out - then walks back. It never flees. Its
# combat is deliberately this small: walk up, swing on an interval, leave when the thing is dead
# or has left the leash.

## Where a guard stands: by its lane's well, out on the side the enemies come from.
func guard_post() -> Vector3:
	if target_mana_source == null or not is_instance_valid(target_mana_source):
		return global_position
	var well: Vector3 = target_mana_source.global_position
	var outward: Vector3 = well - (target_crystal.global_position if target_crystal != null else Vector3.ZERO)
	outward.y = 0.0
	if outward.length_squared() < 0.01:
		outward = Vector3.FORWARD
	return well + outward.normalized() * GameSettings.myr_guard_post_distance


func _guard_process(delta: float, move_speed: float) -> void:
	if lane_index < 0 or target_mana_source == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_attack_cooldown -= delta
	_taunt_timer -= delta
	_guard_think_timer -= delta
	if _guard_think_timer <= 0.0:
		_guard_think_timer = GameSettings.myr_danger_check_interval
		_guard_think()
	if current_state == State.FIGHTING and is_instance_valid(_guard_target):
		var off: Vector3 = _guard_target.global_position - global_position
		off.y = 0.0
		if off.length() > _strike_reach():
			_step_along_path(move_speed, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			rotation.y = lerp_angle(rotation.y, atan2(off.x, off.z), 10.0 * delta)
			move_and_slide()
			if _attack_cooldown <= 0.0:
				_guard_strike()
		return
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
	else:
		_step_along_path(move_speed, delta)


func _guard_think() -> void:
	var post: Vector3 = guard_post()
	if current_state == State.FIGHTING:
		var target: EnemyBase = _guard_target as EnemyBase
		if target == null or not is_instance_valid(target) or target.is_dying \
				or _flat_distance(target.global_position, post) > GameSettings.myr_guard_leash * GameSettings.myr_guard_rescue_leash_mult:
			_guard_target = null
		else:
			update_navigation_target()
			if role == ROLE_ENFORCER:
				_enforcer_taunt()
			return
	var best: Node3D = _pick_guard_target(post)
	if best != null:
		_guard_target = best
		if _attacks_my_worker(best):
			intercepts += 1
		current_state = State.FIGHTING
		update_navigation_target()
		if role == ROLE_ENFORCER:
			_enforcer_taunt()
		return
	if current_state != State.GUARDING:
		current_state = State.GUARDING
		update_navigation_target()


## The nearest enemy to the post inside the leash, or attacking one of this lane's workers a
## little further out.
func _pick_guard_target(post: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	var leash: float = GameSettings.myr_guard_leash
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dying or enemy.is_queued_for_deletion():
			continue
		var distance: float = _flat_distance(enemy.global_position, post)
		var reach: float = leash * GameSettings.myr_guard_rescue_leash_mult if _attacks_my_worker(enemy) else leash
		if distance <= reach and distance < best_distance:
			best = enemy
			best_distance = distance
	return best


func _attacks_my_worker(enemy: Node3D) -> bool:
	var victim: Variant = enemy.get("current_target")
	return victim is Myr and victim != self and not (victim as Myr).is_guard() and (victim as Myr).lane_index == lane_index


## Myr Enforcer: what is attacking one of its workers nearby is taunted onto it instead.
func _enforcer_taunt() -> void:
	if _taunt_timer > 0.0:
		return
	_taunt_timer = GameSettings.myr_enforcer_taunt_duration * 0.5
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dying or not _attacks_my_worker(enemy):
			continue
		if _flat_distance(enemy.global_position, global_position) > GameSettings.myr_enforcer_taunt_radius:
			continue
		enemy.apply_taunt(self, GameSettings.myr_enforcer_taunt_duration)
		intercepts += 1


func _strike_reach() -> float:
	return GameSettings.myr_guard_attack_range * scale.x


func _guard_strike() -> void:
	var target: EnemyBase = _guard_target as EnemyBase
	if target == null or not is_instance_valid(target) or target.is_dying:
		return
	_attack_cooldown = GameSettings.myr_enforcer_attack_interval if role == ROLE_ENFORCER else GameSettings.myr_lodestone_attack_interval
	attack_serial += 1
	_seen_attack_serial = attack_serial
	_play_strike()
	target.take_damage(guard_damage(), self, true)
	NetFx.impact(target.global_position + Vector3(0.0, 1.0, 0.0), ROLE_TINTS.get(role, Color.WHITE), 0.6)


## One blow: the kind's own damage, grown by level - and for the Lodestone, by the workers
## harvesting around it.
func guard_damage() -> float:
	var base: float = GameSettings.myr_enforcer_damage if role == ROLE_ENFORCER else GameSettings.myr_lodestone_damage
	var mult: float = 1.0 + float(level - 1) * GameSettings.myr_guard_level_damage_bonus
	if role == ROLE_LODESTONE:
		mult *= 1.0 + lodestone_bonus()
	return base * mult


## Lodestone Myr: a share more per worker harvesting within its radius - a harvesting myr is a
## tapped artifact - up to the cap.
func lodestone_bonus() -> float:
	var tapped: int = 0
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		var myr: Myr = node as Myr
		if myr == null or myr == self or myr.is_guard() or myr.is_dying or myr.current_state != State.HARVESTING:
			continue
		if _flat_distance(myr.global_position, global_position) <= GameSettings.myr_lodestone_bonus_radius:
			tapped += 1
	return minf(float(tapped) * GameSettings.myr_lodestone_bonus_per_worker, GameSettings.myr_lodestone_bonus_cap)


## EnemyBase.take_damage tells whoever landed the killing blow.
func on_enemy_killed_by_me(_basic_attack: bool = false) -> void:
	kills += 1


## The swing, on whichever peer: the harvest clip's reach stands in until the guards have their
## own models and an attack clip.
func _play_strike() -> void:
	if visual_anim_player == null or not visual_anim_player.has_animation("harvest"):
		return
	visual_anim_player.stop()
	visual_anim_player.play("harvest", -1, 1.8)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
