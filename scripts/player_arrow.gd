class_name PlayerArrow
extends Node3D
## An arrow from the archer's bow (BowKit), in flight.
##
## Swept, not a physics body: each frame it casts a ray from where it was to where it is
## going, so a fast arrow cannot step through a goblin between two frames, and nothing has
## to be awake on the physics server for it. It falls a little (archer_arrow_gravity) and
## always points along its flight.
##
## The same arrow flies on every screen. Only the shooter's copy carries `authority_damage`
## and deals it - the rest are the picture of it (Player._net_spawn_arrow) and simply stop
## where the shooter's stops, because they fly the same path into the same enemies.
##
## An arrow that meets the ground or a wall stays stuck in it for a while; one that meets an
## enemy is gone, unless it still has pierce left (Longshot), in which case it carries on.

## Enemies (layer 3) and the environment (layer 5) - never players, myrs or allies.
const HIT_MASK: int = 4 | 16
## Metres. Tip at -Z, nock at the origin.
const LENGTH := 0.78

static var _mesh: ArrayMesh = null

var velocity: Vector3 = Vector3.ZERO
var shooter: Player = null
## Damage per enemy struck. Zero on every copy but the shooter's.
var authority_damage: float = 0.0
var exile_on_kill: bool = false
var deadeye: bool = false
var _pierce_left: int = 1
var _travelled: float = 0.0
var _stuck_timer: float = -1.0
var _struck: Array[RID] = []
## instance id -> true for every enemy this arrow has already hit.
var _struck_enemies: Dictionary = {}


## Puts an arrow into the world and sends it on its way. `pierce` is how many enemies it may
## pass into before it stops.
static func launch(from: Player, origin: Vector3, launch_velocity: Vector3, pierce: int) -> PlayerArrow:
	var arrow := PlayerArrow.new()
	arrow.shooter = from
	arrow.velocity = launch_velocity
	arrow._pierce_left = maxi(pierce, 1)
	var holder: Node = from.get_tree().current_scene if from.get_tree().current_scene != null else from.get_parent()
	holder.add_child(arrow)
	arrow.global_position = origin
	arrow._face_flight()
	return arrow


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = arrow_mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _stuck_timer >= 0.0:
		_stuck_timer -= delta
		if _stuck_timer <= 0.0:
			queue_free()
		return
	velocity.y -= GameSettings.archer_arrow_gravity * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	# The tip leads the node by the arrow's length, so the sweep reaches from the tip's
	# old place to its new one: what the eye sees touching is what gets hit.
	var tip_offset: Vector3 = velocity.normalized() * LENGTH
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + tip_offset, to + tip_offset, HIT_MASK)
	var exclude: Array[RID] = _struck.duplicate()
	if is_instance_valid(shooter):
		exclude.append(shooter.get_rid())
	# An enemy can be more than one collider (a body and a shield, say). One already struck
	# is passed through rather than struck again: its colliders are excluded one by one and
	# the ray cast again, within this same step.
	var hit: Dictionary = {}
	var enemy: Node3D = null
	for attempt in 6:
		query.exclude = exclude
		hit = space.intersect_ray(query)
		if not hit:
			break
		enemy = _enemy_of(hit["collider"] as Node)
		if enemy == null or not _struck_enemies.has(enemy.get_instance_id()):
			break
		exclude.append(hit["rid"])
		_struck.append(hit["rid"])
		hit = {}
	if hit:
		var at: Vector3 = hit["position"]
		if enemy != null:
			_strike(enemy, at, hit["rid"])
			_struck_enemies[enemy.get_instance_id()] = true
			_pierce_left -= 1
			if _pierce_left <= 0:
				queue_free()
				return
			# Through it and on: what the ray has already touched is excluded, so the next
			# step finds the enemy behind.
			_struck.append(hit["rid"])
		else:
			global_position = at - tip_offset
			_stuck_timer = GameSettings.archer_arrow_stuck_lifetime
			if is_instance_valid(shooter):
				SoundBank.play_at(&"arrow_hit", at)
			return
	global_position = to
	_travelled += velocity.length() * delta
	_face_flight()
	if _travelled >= GameSettings.archer_arrow_range * 1.5:
		queue_free()


func _face_flight() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var forward: Vector3 = velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	global_basis = Basis.looking_at(forward, up)


func _strike(enemy: Node3D, at: Vector3, _rid: RID) -> void:
	SoundBank.play_at(&"arrow_hit", at)
	if authority_damage <= 0.0 or not is_instance_valid(shooter):
		return
	var damage: float = authority_damage
	if deadeye and is_headshot(enemy, at):
		damage *= GameSettings.archer_deadeye_damage_mult
		NetFx.impact(at, Color(1.0, 0.9, 0.55), 0.45)
	shooter._basic_strike(enemy, damage, exile_on_kill, false)
	shooter._apply_basic_attack_knockback(enemy, GameSettings.archer_arrow_knockback)
	# The bow feeds the spells exactly as the axe does: a connecting hit takes time off them.
	shooter._reduce_spell_cooldowns(GameSettings.melee_hit_cooldown_reduction)


## The enemy a collider belongs to, or null for the world.
static func _enemy_of(node: Node) -> Node3D:
	while node != null and not node.is_in_group("enemies"):
		node = node.get_parent()
	return node as Node3D


## Whether `at` is on the top archer_head_fraction of the enemy's body. The body's top is
## read off its own collision shapes, so a giant's head is a giant's head.
static func is_headshot(enemy: Node3D, at: Vector3) -> bool:
	var feet: float = enemy.global_position.y
	var top: float = body_top(enemy)
	if top <= feet:
		return false
	return at.y >= top - (top - feet) * GameSettings.archer_head_fraction


static func body_top(enemy: Node3D) -> float:
	var top: float = -INF
	for child: Node in enemy.get_children():
		if not child is CollisionShape3D:
			continue
		var shape_node := child as CollisionShape3D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var half: float = 0.0
		var shape: Shape3D = shape_node.shape
		if shape is BoxShape3D:
			half = (shape as BoxShape3D).size.y * 0.5
		elif shape is CapsuleShape3D:
			half = (shape as CapsuleShape3D).height * 0.5
		elif shape is CylinderShape3D:
			half = (shape as CylinderShape3D).height * 0.5
		elif shape is SphereShape3D:
			half = (shape as SphereShape3D).radius
		else:
			continue
		top = maxf(top, shape_node.global_position.y + half * shape_node.global_basis.get_scale().y)
	if top == -INF:
		top = enemy.global_position.y + Player.AIM_BODY_HEIGHT * enemy.scale.y
	return top


## The arrow: an ash shaft, a steel head and three pale fletchings. Built once and shared by
## every arrow - in flight, nocked on the bow (BowRig) and falling in a volley. Points along
## -Z with the nock at the origin, unless `along_y`, for particles that align their Y axis
## with their velocity.
static func arrow_mesh(along_y: bool = false) -> ArrayMesh:
	if _mesh != null and not along_y:
		return _mesh
	var built := ArrayMesh.new()
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.55, 0.42, 0.28)
	shaft_mat.roughness = 0.8
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.62, 0.64, 0.66)
	head_mat.metallic = 0.85
	head_mat.roughness = 0.35
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.albedo_color = Color(0.9, 0.88, 0.8)
	fletch_mat.roughness = 0.9
	fletch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var head_length := 0.07
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.0055
	shaft.bottom_radius = 0.0055
	shaft.height = LENGTH - head_length
	shaft.radial_segments = 6
	shaft.rings = 1
	_append(built, shaft, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -(LENGTH - head_length) * 0.5)), shaft_mat)
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.016
	head.height = head_length
	head.radial_segments = 6
	head.rings = 1
	_append(built, head, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -LENGTH + head_length * 0.5)), head_mat)
	for i in 3:
		var vane := QuadMesh.new()
		vane.size = Vector2(0.03, 0.12)
		var around := Basis(Vector3.FORWARD, TAU * i / 3.0)
		var lay := Basis(Vector3.RIGHT, -PI * 0.5)
		# Laid flat along the shaft, then pushed out to one side so it stands off it like a
		# feather rather than straddling it.
		_append(built, vane, Transform3D(around * lay, around * Vector3(0.019, 0.0, 0.0) + Vector3(0.0, 0.0, -0.08)), fletch_mat)

	if along_y:
		# Tip up along +Y, for a particle aligned to its velocity.
		var turned := ArrayMesh.new()
		var to_y := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		for s in built.get_surface_count():
			var tool := MeshDataTool.new()
			tool.create_from_surface(built, s)
			for v in tool.get_vertex_count():
				tool.set_vertex(v, to_y * tool.get_vertex(v))
				tool.set_vertex_normal(v, to_y.basis * tool.get_vertex_normal(v))
			tool.commit_to_surface(turned)
			turned.surface_set_material(s, built.surface_get_material(s))
		return turned
	_mesh = built
	return built


static func _append(target: ArrayMesh, primitive: PrimitiveMesh, xform: Transform3D, material: Material) -> void:
	var arrays: Array = primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xform * verts[i]
		normals[i] = (xform.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.surface_set_material(target.get_surface_count() - 1, material)
