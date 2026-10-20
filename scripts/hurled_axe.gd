class_name HurledAxe
extends Node3D
## Hurl Axe's axe (WarriorSkills.cast_hurl_axe): out along its direction to its range, spinning
## flat like a boomerang, then back to whoever threw it - hitting what it passes on BOTH legs,
## once each way.
##
## A networked effect (MainController.build_effect), so it is built and flown on every peer from
## the same start; only the server deals the hits. While it is out, the thrower's own hatchet is
## not in their hand.

const AXE_SCENE: PackedScene = preload("res://assets/weapons/player/warrior_hatchet.glb")
## How fast it turns, radians per second.
const SPIN := 24.0
## Its size in flight against the hatchet in the hand.
const FLIGHT_SCALE := 1.4
## Back in the hand once it is this close to the thrower's chest.
const CATCH_DISTANCE := 1.0
## On its way back it is a little quicker than on its way out, so it never trails the thrower.
const RETURN_SPEED_MULT := 1.2
## However the thrower moves, it is back in the hand by then.
const MAX_LIFETIME := 4.0

var _caster: Node3D
var _direction: Vector3 = Vector3.FORWARD
var _range: float = 10.0
var _speed: float = 20.0
var _radius: float = 1.5
var _damage: float = 0.0
var _returning: bool = false
var _travelled: float = 0.0
var _life: float = 0.0
## Enemies already struck on the leg in flight, by instance id. Cleared at the turn.
var _struck: Dictionary = {}
var _spinner: Node3D
var _held_axe: Node3D


static func create(direction: Vector3, reach: float, speed: float, radius: float, damage: float, caster: Node3D) -> HurledAxe:
	var axe := HurledAxe.new()
	axe.name = "HurledAxe"
	axe._direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	axe._range = reach
	axe._speed = speed
	axe._radius = radius
	axe._damage = damage
	axe._caster = caster
	return axe


func _ready() -> void:
	_spinner = Node3D.new()
	add_child(_spinner)
	# Laid flat and turned about the vertical, like a boomerang. Thrown end over end it was only
	# ever seen edge-on from the camera behind the thrower - a thin dark line in the dusk.
	var model: Node3D = AXE_SCENE.instantiate()
	model.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	# The glb's origin is the fist, at the end of the handle; the middle of the axe is the hub.
	# Bigger in flight than in the hand: at its true 0.85 m it was a speck ten metres out.
	model.scale = Vector3.ONE * FLIGHT_SCALE
	model.position = Vector3(0.0, 0.0, 0.42 * FLIGHT_SCALE)
	_spinner.add_child(model)
	# A little warm light of its own, so it is seen at night (the nights are dark on purpose).
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.72, 0.45)
	glint.light_energy = 1.2
	glint.omni_range = 3.0
	glint.shadow_enabled = false
	add_child(glint)
	if is_instance_valid(_caster):
		_held_axe = _caster.find_child("Hatchet", true, false) as Node3D
		if _held_axe != null:
			_held_axe.visible = false
	NetFx.sound(&"blade_heavy_swing", global_position)


func _exit_tree() -> void:
	if is_instance_valid(_held_axe):
		_held_axe.visible = true


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME or not is_instance_valid(_caster):
		queue_free()
		return
	if not _returning:
		var step: float = _speed * delta
		global_position += _direction * step
		_travelled += step
		if _travelled >= _range:
			_returning = true
			_struck.clear()
	else:
		var hand: Vector3 = _caster.global_position + Vector3(0.0, 1.2, 0.0)
		var to_hand: Vector3 = hand - global_position
		if to_hand.length() <= CATCH_DISTANCE:
			queue_free()
			return
		global_position += to_hand.normalized() * minf(_speed * RETURN_SPEED_MULT * delta, to_hand.length())
	_spinner.rotate_y(SPIN * delta)
	if Net.is_server():
		_strike()


## Everything within reach of the axe that this leg has not struck yet. Server only.
func _strike() -> void:
	if not _caster.has_method("_deal_damage"):
		return
	for enemy: Node3D in _caster._enemies_in_radius(global_position, _radius + 0.6):
		var id: int = enemy.get_instance_id()
		if _struck.has(id):
			continue
		# Chest height is where the axe flies; the enemy's origin is at its feet.
		var offset: Vector3 = enemy.global_position + Vector3(0.0, 1.0, 0.0) - global_position
		if Vector2(offset.x, offset.z).length() > _radius or absf(offset.y) > 1.6:
			continue
		_struck[id] = true
		_caster._deal_damage(enemy, _damage, false)
		NetFx.impact(enemy.global_position + Vector3(0.0, 1.2, 0.0), Player.FX_RED, 0.7)
		NetFx.sound(&"blade_hit", enemy.global_position)
