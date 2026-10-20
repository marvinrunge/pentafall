class_name MageHandOrb
extends Node3D
## The ball of energy the mage holds over the palm of the throwing hand, in place of a weapon -
## the same churning orb a bolt flies as (SpellFx.energy_orb), smaller, in the colour of the
## mage's path (Player.path_color), with a little light of its own on the hand and the face.
##
## Attached at runtime like the archer's BowRig, wherever a class's visual is shown: by
## PlayerAnimator in the game (every screen, so teammates see it), by ClassPreview in the menu,
## and on Blink of an Eye's decoy. It follows the hand rather than being a child of the bone.
## Where it wants to be is worked out on the skeleton's `skeleton_updated`, after the pose of the
## frame is final: a point off the palm - between the wrist and the knuckles, lifted along the
## palm's normal - so it floats over the open hand in every pose instead of sitting in it.
##
## It gets there on a damped spring, so it trails the hand a moment and swings a little past
## where a quick move stops, and it bobs gently while the hand is still - floating, not glued
## on. The spring runs in the character's own space: the orb lags the HAND, never the body, so
## running, turning or blinking carry it along at once.
##
## A bolt is thrown from it: MageKit launches the bolt where the orb is and spend() empties the
## palm, and the next orb swells back over REGROW_TIME.

## The ball's radius, metres, and how far off the palm it floats.
const RADIUS := 0.062
const LIFT := 0.1
## Its light on the hand and the face: enough to read at night, not enough to dye the mage.
const LIGHT_ENERGY := 0.4
## Seconds an emptied palm takes to grow its orb back.
const REGROW_TIME := 0.3
## The spring it follows the palm on: how hard it is pulled (per second squared) and how much
## of its swing is damped (per second). About a tenth of a second behind the hand, with a
## slight overshoot - a damping ratio of 0.7.
const FOLLOW_STIFFNESS := 160.0
const FOLLOW_DAMPING := 17.7
## The leash: never further than this behind the palm, metres. A throw whips the hand through
## the air at several metres a second, and on the spring alone the orb fell 39 cm behind it.
const MAX_TRAIL := 0.15
## The hover: metres it drifts each way, sideways and up and down.
const BOB := Vector2(0.006, 0.012)
## How often the path's colour is looked at again, seconds.
const COLOR_CHECK := 0.25
const HAND := "mixamorig_RightHand"
const MIDDLE := "mixamorig_RightHandMiddle1"
const INDEX := "mixamorig_RightHandIndex1"
const PINKY := "mixamorig_RightHandPinky1"

## The player whose path paints it, or null - the menu's preview, a decoy - for `fixed_tint`.
var player: Player = null
var fixed_tint: Color = MageBolt.tint_of("")
var _skeleton: Skeleton3D = null
var _bones: PackedInt32Array = PackedInt32Array()
var _orb: Node3D = null
var _material: ShaderMaterial = null
var _light: OmniLight3D = null
var _grown: float = 1.0
var _color: String = "-"
var _color_timer: float = 0.0
## Where it wants to be and where it is, in the space of the visual it rides on (its parent),
## and how fast it is moving there.
var _target_local: Vector3 = Vector3.ZERO
var _local: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _placed: bool = false
var _time: float = 0.0


## `skeleton` is the visual's; `owner_player` paints it with their path, or pass null and a
## `tint` for a fixed colour.
func setup(skeleton: Skeleton3D, owner_player: Player = null, tint: Color = MageBolt.tint_of("")) -> void:
	name = "MageHandOrb"
	_skeleton = skeleton
	player = owner_player
	fixed_tint = tint
	for bone_name: String in [HAND, MIDDLE, INDEX, PINKY]:
		_bones.append(skeleton.find_bone(bone_name))
	skeleton.skeleton_updated.connect(_place)


func _ready() -> void:
	# Free of the visual's transform - which for these centimetre-scale rigs is scaled about 100
	# times. Turning top_level on keeps the node's global transform as it was, that scale
	# included, so it is put back to plain here, and _place only ever sets a position.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_light = OmniLight3D.new()
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = 1.8
	_light.shadow_enabled = false
	add_child(_light)
	_set_color(_path_color())


func _process(delta: float) -> void:
	_time += delta
	if _grown < 1.0:
		_grown = minf(_grown + delta / REGROW_TIME, 1.0)
	_color_timer -= delta
	if _color_timer <= 0.0:
		_color_timer = COLOR_CHECK
		var color: String = _path_color()
		if color != _color:
			_set_color(color)
	var down: bool = player != null and is_instance_valid(player) and player.is_downed
	visible = not down
	if _orb != null:
		# Swells back with an overshoot, so a new orb pops into the palm rather than fading in.
		var grow: float = ease(_grown, 0.4) * (1.0 + 0.15 * sin(_grown * PI))
		_orb.scale = Vector3.ONE * maxf(grow, 0.001)
	_light.light_energy = LIGHT_ENERGY * _grown


## The orb has just been thrown: the palm is empty and a new one starts to grow.
func spend() -> void:
	_grown = 0.0


## Where the orb floats now, in the world.
func palm_point() -> Vector3:
	return global_position


func _path_color() -> String:
	if player != null and is_instance_valid(player):
		return player.path_color()
	return ""


func _set_color(color: String) -> void:
	_color = color
	var tint: Color = MageBolt.tint_of(color) if player != null else fixed_tint
	if _orb != null:
		_orb.queue_free()
	_orb = SpellFx.energy_orb_tinted(RADIUS, tint)
	_material = SpellFx.energy_orb_material(_orb)
	# Held, not flying: calmer than a bolt, and dim enough not to glare in the shoulder camera.
	_material.set_shader_parameter("energy", 1.15)
	_material.set_shader_parameter("spin", 2.2)
	_material.set_shader_parameter("boil_speed", 1.5)
	_material.set_shader_parameter("flicker", 0.25)
	add_child(_orb)
	_light.light_color = tint


## The spring towards the palm, in small fixed steps so a long frame cannot fling it. Run right
## after the target moved (_place), so the leash holds against where the hand really is this
## frame rather than where it was before the pose was updated.
func _follow(delta: float) -> void:
	if not _placed:
		return
	var left: float = minf(delta, 0.1)
	while left > 0.0:
		var step: float = minf(left, 1.0 / 120.0)
		_velocity += ((_target_local - _local) * FOLLOW_STIFFNESS - _velocity * FOLLOW_DAMPING) * step
		_local += _velocity * step
		left -= step
	var frame: Transform3D = (get_parent() as Node3D).global_transform
	# The parent's space is the visual's, scaled about 100 times on the centimetre-scale rigs.
	var leash: float = MAX_TRAIL / maxf(frame.basis.get_scale().x, 0.0001)
	var behind: Vector3 = _local - _target_local
	if behind.length() > leash:
		_local = _target_local + behind.normalized() * leash
	var hover := Vector3(sin(_time * 1.7) * BOB.x, sin(_time * 2.3) * BOB.y, cos(_time * 1.3) * BOB.x)
	global_transform = Transform3D(Basis.IDENTITY, frame * _local + hover)


## Over the palm: the middle of the hand, between the wrist and the knuckle of the middle
## finger, lifted along the palm's normal - the cross of the knuckles' line (pinky to index)
## with the hand's length (wrist to knuckles), which for a RIGHT hand points out of the palm.
func _place() -> void:
	if _skeleton == null or _bones.has(-1):
		return
	var to_world: Transform3D = _skeleton.global_transform
	var wrist: Vector3 = to_world * _skeleton.get_bone_global_pose(_bones[0]).origin
	var knuckle: Vector3 = to_world * _skeleton.get_bone_global_pose(_bones[1]).origin
	var index: Vector3 = to_world * _skeleton.get_bone_global_pose(_bones[2]).origin
	var pinky: Vector3 = to_world * _skeleton.get_bone_global_pose(_bones[3]).origin
	var along: Vector3 = knuckle - wrist
	var across: Vector3 = index - pinky
	var palm: Vector3 = across.cross(along)
	if palm.length_squared() < 1.0e-8:
		palm = Vector3.UP
	var target: Vector3 = wrist.lerp(knuckle, 0.6) + palm.normalized() * LIFT
	var parent := get_parent() as Node3D
	if parent == null:
		return
	_target_local = parent.global_transform.affine_inverse() * target
	if not _placed:
		# The first time it simply appears there.
		_placed = true
		_local = _target_local
		_velocity = Vector3.ZERO
		global_transform = Transform3D(Basis.IDENTITY, target)
		return
	_follow(get_process_delta_time())
