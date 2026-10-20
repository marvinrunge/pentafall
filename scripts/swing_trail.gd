class_name SwingTrail
extends MeshInstance3D
## The smear a melee weapon leaves when it swings (docs/GRAPHICS_FEEL_PLAN.md): a ribbon
## between the hand and the blade's tip over the last moment of the swing, fading by age.
##
## Driven by how fast the tip actually moves, not by any attack state, so it shows for every
## swing - a cleave, a heavy, a kick with a weapon in hand - on every screen, with nothing sent
## over the network. Whirlwind has its own smear (WhirlwindFx) and none is drawn during it.

const SHADER := preload("res://assets/shaders/swing_trail.gdshader")
## Seconds a sample stays in the ribbon.
const LIFETIME := 0.14
## The tip has to move this fast (m/s) for a sample to be taken: a swing, not a walk.
const MIN_TIP_SPEED := 5.0

var _player: Player = null
var _weapon: Node3D = null
var _samples: Array[Dictionary] = []
var _last_tip: Vector3 = Vector3.ZERO
var _immediate: ImmediateMesh = null


func _ready() -> void:
	name = "SwingTrail"
	_player = get_parent() as Player
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_immediate = ImmediateMesh.new()
	mesh = _immediate
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material_override = material


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _samples.is_empty() and now - float(_samples[0]["t"]) > LIFETIME:
		_samples.pop_front()
	var weapon: Node3D = _weapon_node()
	var spinning: bool = _player != null and _player.animator != null and _player.animator.whirlwind_progress() >= 0.0
	if weapon != null and weapon.is_visible_in_tree() and not spinning:
		var ends: Array[Vector3] = _blade(weapon)
		var speed: float = ends[1].distance_to(_last_tip) / maxf(delta, 0.0001)
		if speed >= MIN_TIP_SPEED and _last_tip != Vector3.ZERO:
			_samples.append({"t": now, "grip": ends[0], "tip": ends[1]})
		elif not _samples.is_empty() and now - float(_samples[-1]["t"]) > 0.05:
			_samples.clear()
		_last_tip = ends[1]
	_rebuild(now)


func _rebuild(now: float) -> void:
	_immediate.clear_surfaces()
	if _samples.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample: Dictionary in _samples:
		var life: float = 1.0 - clampf((now - float(sample["t"])) / LIFETIME, 0.0, 1.0)
		_immediate.surface_set_color(Color(1.0, 1.0, 1.0, life))
		_immediate.surface_set_uv(Vector2(life, 0.0))
		_immediate.surface_add_vertex(sample["grip"])
		_immediate.surface_set_color(Color(1.0, 1.0, 1.0, life))
		_immediate.surface_set_uv(Vector2(life, 1.0))
		_immediate.surface_add_vertex(sample["tip"])
	_immediate.surface_end()


## [grip, tip] in world space: the hand, and the corner of the weapon's meshes farthest from it.
func _blade(weapon: Node3D) -> Array[Vector3]:
	var hand: Vector3 = weapon.global_position
	var tip: Vector3 = hand
	var best: float = -1.0
	for node: Node in weapon.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_inside_tree():
			continue
		var box: AABB = instance.get_aabb()
		for corner: int in 8:
			var point: Vector3 = instance.global_transform * box.get_endpoint(corner)
			var distance: float = point.distance_squared_to(hand)
			if distance > best:
				best = distance
				tip = point
	return [hand, tip]


## The weapon in the right hand: the bone attachment on it that carries a mesh.
func _weapon_node() -> Node3D:
	if _weapon != null and is_instance_valid(_weapon) and _weapon.is_inside_tree():
		return _weapon
	_weapon = null
	if _player == null:
		return null
	for node: Node in _player.find_children("*", "BoneAttachment3D", true, false):
		var attachment := node as BoneAttachment3D
		if attachment.is_inside_tree() and attachment.bone_name.contains("RightHand") \
				and not attachment.find_children("*", "MeshInstance3D", true, false).is_empty():
			_weapon = attachment
			break
	return _weapon
