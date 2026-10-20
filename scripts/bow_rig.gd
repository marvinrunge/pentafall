class_name BowRig
extends Node3D
## The archer's bowstring and the arrow on it, drawn every frame from the pose on screen.
##
## The bow mesh (assets/weapons/player/archer_longbow.glb) has no string of its own - it was
## cut away when the prop was made (assets/player/archer/source/prepare_props.py) - because a
## string baked into the mesh stays straight while the hand pulls an arrow back. Here it runs
## from each tip to the nock: the drawing hand while the hand is on the string, the straight
## line between the tips otherwise. The nocked arrow shows for the same stretch, from the
## hand to the grip.
##
## When the hand is on the string is read from the action layer's own clip and playhead
## (PlayerAnimator.action_clip/action_position) against the moments measured on the Pro
## Longbow clips: `draw` nocks at about half a second in, `aim` holds the whole time, and
## `shoot` lets go a tenth of a second in. Every screen runs this off its own animator, so a
## teammate's archer draws on your screen exactly as on theirs, with nothing sent.

## Seconds into `draw` where the arrow is on the string, and into `shoot` where it is gone.
const DRAW_NOCKED_AT := 0.5
const SHOOT_RELEASED_AT := 0.1
## Where the fingers hold the string: the middle knuckle, just past the wrist.
const STRING_HAND_BONE := "mixamorig_RightHandMiddle1"
const STRING_RADIUS := 0.0022

var _animator: PlayerAnimator
var _bow: Node3D
var _skeleton: Skeleton3D
var _hand_bone: int = -1
## The bone the bow's attachment hangs on: the bow is placed from it rather than read off
## the attachment, see _on_skeleton_updated.
var _bow_bone: int = -1
## Where the string hand and the bow were on the last pose shown, world space.
var _hand_world: Vector3 = Vector3.ZERO
var _bow_world: Transform3D = Transform3D.IDENTITY
var _posed: bool = false
## The two tips and the grip, in the bow's own space.
var _tip_top: Vector3
var _tip_bottom: Vector3
var _grip: Vector3
var _upper: MeshInstance3D
var _lower: MeshInstance3D
var _arrow: MeshInstance3D


func setup(animator: PlayerAnimator, bow: Node3D, skeleton: Skeleton3D) -> void:
	name = "BowRig"
	_animator = animator
	_bow = bow
	_skeleton = skeleton
	_hand_bone = skeleton.find_bone(STRING_HAND_BONE)
	if _hand_bone == -1:
		_hand_bone = skeleton.find_bone("mixamorig_RightHand")
	var attachment := bow.get_parent() as BoneAttachment3D
	_bow_bone = skeleton.find_bone(attachment.bone_name) if attachment != null else -1
	_measure_bow()
	skeleton.skeleton_updated.connect(_on_skeleton_updated)


func _ready() -> void:
	top_level = true
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.86, 0.83, 0.74)
	string_mat.roughness = 0.7
	for i in 2:
		var piece := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = STRING_RADIUS
		cylinder.bottom_radius = STRING_RADIUS
		cylinder.height = 1.0
		cylinder.radial_segments = 4
		cylinder.rings = 1
		cylinder.material = string_mat
		piece.mesh = cylinder
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		if i == 0:
			_upper = piece
		else:
			_lower = piece
	_arrow = MeshInstance3D.new()
	_arrow.mesh = PlayerArrow.arrow_mesh()
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = false
	add_child(_arrow)


## The tips are the two ends of the bow's length (its X) at the top of its curve (its +Y,
## the string side); the grip is the middle of the back. Read off the mesh rather than
## hard-coded so a re-made bow still strings itself.
func _measure_bow() -> void:
	var box := AABB()
	var first := true
	for node: Node in _bow.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local: AABB = _to_bow(mesh_node) * mesh_node.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	var half_length: float = box.size.x * 0.5 - 0.012
	var centre_x: float = box.position.x + box.size.x * 0.5
	var string_y: float = box.end.y - 0.012
	var centre_z: float = box.position.z + box.size.z * 0.5
	_tip_top = Vector3(centre_x + half_length, string_y, centre_z)
	_tip_bottom = Vector3(centre_x - half_length, string_y, centre_z)
	_grip = Vector3(centre_x, box.position.y + box.size.y * 0.25, centre_z)


## `node`'s transform in the bow's own space, from the local transforms in between - so it
## can be measured during the spawn, before anything has a global transform to ask for.
func _to_bow(node: Node3D) -> Transform3D:
	var accum := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != _bow:
		if current is Node3D:
			accum = (current as Node3D).transform * accum
		current = current.get_parent()
	return accum


## Whether the drawing hand is on the string right now. Never, for a bow with no animator
## behind it - the menu's ClassPreview, where the archer only stands.
func is_nocked() -> bool:
	if _animator == null:
		return false
	match _animator.action_clip():
		"draw":
			return _animator.action_position() >= DRAW_NOCKED_AT
		"aim":
			return true
		"shoot":
			return _animator.action_position() < SHOOT_RELEASED_AT
	return false


## Where the string is pulled to: the hand when nocked, the middle of the string otherwise.
## The arrow leaves from here - BowKit looses it on the frame `shoot` starts, nocked.
func nock_point() -> Vector3:
	if not _posed:
		_read_pose()
	if _hand_bone != -1 and is_nocked():
		return _hand_world
	return _bow_world * ((_tip_top + _tip_bottom) * 0.5)


## The grip - where the arrow rests on the bow - in the bow's own space. BowAim measures the
## arrow from the string hand to here, the same line the nocked arrow is drawn along.
func grip_point() -> Vector3:
	return _grip


func _hand_position() -> Vector3:
	if not _posed:
		_read_pose()
	return _hand_world


## The hand and the bow as the skeleton has them right now.
func _read_pose() -> void:
	var to_world: Transform3D = _skeleton.global_transform
	if _hand_bone != -1:
		_hand_world = (to_world * _skeleton.get_bone_global_pose(_hand_bone)).origin
	if _bow_bone != -1:
		_bow_world = to_world * _skeleton.get_bone_global_pose(_bow_bone) * _bow.transform
	else:
		_bow_world = _bow.global_transform
	_posed = true


## Drawn on the skeleton's own update rather than in _process: BowAim turns the spine as a
## skeleton modifier, and Godot puts the bones back once the update is over - so a bone read
## any later is the pose WITHOUT the aim, and the string came away from the hand that drew it.
## Here, inside the update, the bones are the ones on screen. The pose is kept for nock_point,
## which the arrow is loosed from in between.
func _on_skeleton_updated() -> void:
	_read_pose()
	if not is_instance_valid(_bow) or not _bow.is_visible_in_tree():
		visible = false
		return
	visible = true
	var to_world: Transform3D = _bow_world
	var top: Vector3 = to_world * _tip_top
	var bottom: Vector3 = to_world * _tip_bottom
	var nocked: bool = is_nocked() and _hand_bone != -1
	var nock: Vector3 = _hand_world if nocked else (top + bottom) * 0.5
	_stretch(_upper, top, nock)
	_stretch(_lower, bottom, nock)
	_arrow.visible = nocked
	if nocked:
		var grip: Vector3 = to_world * _grip
		var along: Vector3 = grip - nock
		if along.length_squared() > 0.0001:
			var up: Vector3 = (top - bottom).normalized()
			if absf(along.normalized().dot(up)) > 0.98:
				up = Vector3.UP
			_arrow.global_transform = Transform3D(Basis.looking_at(along.normalized(), up), nock)


## Lays a unit cylinder from `a` to `b`.
static func _stretch(piece: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var span: Vector3 = b - a
	var length: float = span.length()
	if length < 0.0001:
		piece.visible = false
		return
	piece.visible = true
	var y: Vector3 = span / length
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	piece.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
