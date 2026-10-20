class_name BowAim
extends SkeletonModifier3D
## Points the nocked arrow at the crosshair by twisting the spine (docs/CHARACTER_CLASSES_PLAN.md).
##
## The Pro Longbow clips draw side-on with the arrow some 23 degrees off the body's forward
## and a little below level, whatever the camera does - so the bow pointed off to one side of
## the crosshair, and never up or down at all. This runs after the animation every frame and
## turns the upper body until the line from the string hand to the bow's grip - the arrow as
## BowRig draws it - points at `aim_point`: yaw about the skeleton's up, then pitch about the
## arrow's own right, so it never rolls. The turn is shared over the three spine bones, so the
## twist reads as a torso turning rather than one joint kinking, and the legs below keep
## whatever the locomotion is doing.
##
## PlayerAnimator drives `amount` (0 off, 1 fully aimed) from the action clip, so every screen
## aims a player's bow the same way, and `aim_point` from Player.aim_hit_point.

const SPINE_BONES: Array[String] = ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
## How much of the turn each spine bone takes, bottom to top.
const SPINE_SHARE: Array[float] = [0.3, 0.3, 0.4]
## Moving the spine moves the string hand too, so the line is measured again and the rest
## made up. Two passes land within a fraction of a degree.
const PASSES := 2

## 0 to 1: how far towards the crosshair the arrow is turned this frame.
var amount: float = 0.0
## What the arrow should point at, world space.
var aim_point: Vector3 = Vector3.ZERO

var _bow: Node3D
var _rig: BowRig
var _spine: PackedInt32Array = []
var _bow_hand: int = -1
var _string_hand: int = -1


func setup(skeleton: Skeleton3D, bow: Node3D, rig: BowRig) -> void:
	name = "BowAim"
	_bow = bow
	_rig = rig
	for bone_name: String in SPINE_BONES:
		var bone: int = skeleton.find_bone(bone_name)
		if bone != -1:
			_spine.append(bone)
	var attachment := bow.get_parent() as BoneAttachment3D
	_bow_hand = skeleton.find_bone(attachment.bone_name) if attachment != null else -1
	_string_hand = skeleton.find_bone(BowRig.STRING_HAND_BONE)
	if _string_hand == -1:
		_string_hand = skeleton.find_bone("mixamorig_RightHand")


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or amount <= 0.0 or _spine.is_empty() or _bow_hand == -1 or _string_hand == -1:
		return
	# Everything below is in the skeleton's own space: the rig imports scaled and rotated, so
	# the world's up and the aim point are carried into it rather than the bones out.
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	var target: Vector3 = to_skeleton * aim_point
	var up: Vector3 = (to_skeleton.basis * Vector3.UP).normalized()
	var max_yaw: float = deg_to_rad(GameSettings.archer_aim_max_yaw_degrees)
	var max_pitch: float = deg_to_rad(GameSettings.archer_aim_max_pitch_degrees)
	for pass_index: int in PASSES:
		var nock: Vector3 = skeleton.get_bone_global_pose(_string_hand).origin
		var grip: Vector3 = skeleton.get_bone_global_pose(_bow_hand) * (_bow.transform * _rig.grip_point())
		var arrow: Vector3 = grip - nock
		var wanted: Vector3 = target - nock
		if arrow.length_squared() < 1e-8 or wanted.length_squared() < 1e-8:
			return
		arrow = arrow.normalized()
		wanted = wanted.normalized()
		var yaw: float = clampf(_flat_angle(arrow, wanted, up), -max_yaw, max_yaw) * amount
		var pitch_wanted: float = clampf(_elevation(wanted, up), -max_pitch, max_pitch)
		var pitch: float = (pitch_wanted - _elevation(arrow, up)) * amount
		var turn := Quaternion(up, yaw)
		var right: Vector3 = (turn * arrow).cross(up)
		if right.length_squared() > 1e-8:
			turn = Quaternion(right.normalized(), pitch) * turn
		if pass_index > 0 and turn.get_angle() < 0.002:
			return
		for i: int in _spine.size():
			_rotate_bone(skeleton, _spine[i], Quaternion.IDENTITY.slerp(turn, SPINE_SHARE[i]))


## Turns `bone` by `turn`, given in skeleton space, about its own head.
func _rotate_bone(skeleton: Skeleton3D, bone: int, turn: Quaternion) -> void:
	var global_rotation: Quaternion = turn * skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_rotation: Quaternion = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent != -1 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * global_rotation).normalized())


## The signed angle from `from` to `to` about `up`, both flattened onto the plane under it.
static func _flat_angle(from: Vector3, to: Vector3, up: Vector3) -> float:
	var a: Vector3 = from - up * from.dot(up)
	var b: Vector3 = to - up * to.dot(up)
	if a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
		return 0.0
	return a.signed_angle_to(b, up)


## How far above (positive) or below the horizontal `direction` points, radians.
static func _elevation(direction: Vector3, up: Vector3) -> float:
	return asin(clampf(direction.dot(up), -1.0, 1.0))
