class_name StatusFx
extends Node3D
## The buffs a player is carrying, drawn on them for as long as they last.
##
## Every one of these used to be invisible once its cast flash was gone: an Ironbark player
## looked exactly like an unprotected one, a charged Exalted Strike gave no sign it was
## waiting, and the only trace of Circle of Protection was a number on the HUD - of the
## player who HAD it, not of the teammate deciding whom to cover next.
##
## Reads `Player.status_fx`, a bit set the server keeps (see Player._update_status_fx) and
## replicates with the vitals, so every screen draws the same buffs on the same people.
## Two layers per buff: an overlay material on the character's own meshes
## (status_overlay.gdshader), and for some a few particles around them.
##
## The overlay is laid on the BODY - the skinned meshes - and, without its bark, on what the
## body holds: a sword, a shield or a bow glows with a buff but does not grow oak bark. Effects
## the character carries (the mage's orb, MageHandOrb) are light of their own and get none of
## it; an overlay drew its quad as a square of bark round the orb.

const OVERLAY_SHADER: Shader = preload("res://assets/shaders/status_overlay.gdshader")
## Oak bark from the map's own trees (assets/nature/_concepts/textures/bark_oak.png, scaled down).
const BARK_TEXTURE := "res://assets/vfx/ironbark_bark.png"

const SHIELD := 1
const REPRISAL := 2
const IRONBARK := 4
const EXALTED := 8
const PHOENIX := 16
const GIANT := 32
const BERSERK := 64

## Bit -> overlay uniform it drives.
const UNIFORMS: Dictionary = {
	SHIELD: "shield", REPRISAL: "reprisal", IRONBARK: "bark",
	EXALTED: "exalted", PHOENIX: "phoenix", GIANT: "giant", BERSERK: "berserk",
}
## How fast a buff fades in or out, in amount per second. Bark grows over about half a
## second; light comes on faster.
const RATES: Dictionary = {
	SHIELD: 4.0, REPRISAL: 4.0, IRONBARK: 2.2, EXALTED: 5.0, PHOENIX: 3.0, GIANT: 2.0,
	BERSERK: 5.0,
}

var _player: Node3D = null
var _material: ShaderMaterial = null
## The same overlay for weapons, shields and bows, with the bark always off.
var _held_material: ShaderMaterial = null
var _amounts: Dictionary = {}
var _meshes: Array[GeometryInstance3D] = []
var _held: Array[GeometryInstance3D] = []
var _overlay_on: bool = false
var _orbit: Node3D = null
var _motes: GPUParticles3D = null
var _embers: GPUParticles3D = null
## Berserk: a blood-red drift off the body.
var _rage: GPUParticles3D = null


func _ready() -> void:
	name = "StatusFx"
	_player = get_parent() as Node3D
	_material = ShaderMaterial.new()
	_material.shader = OVERLAY_SHADER
	_material.set_shader_parameter("bark_texture", load(BARK_TEXTURE))
	_held_material = ShaderMaterial.new()
	_held_material.shader = OVERLAY_SHADER
	for bit: int in UNIFORMS.keys():
		_amounts[bit] = 0.0
	_build_orbit()
	_motes = _build_drift(SpellVisuals.WHITE_GOLD, 14, 0.9)
	_embers = _build_drift(Color(1.0, 0.55, 0.2), 18, 1.4)
	_rage = _build_drift(Color(0.95, 0.12, 0.05), 20, 0.9)


func _process(delta: float) -> void:
	if _player == null:
		return
	var bits: int = int(_player.get("status_fx"))
	# A weapon carrying a charge for its next attack (AttackCharges) glows with Exalted Strike's
	# light, whichever colour charged it - published by the player's own machine, which is the
	# one that holds the charges.
	if int(_player.get("armed_charge_bits")) != 0:
		bits |= EXALTED
	var any: bool = false
	for bit: int in UNIFORMS.keys():
		var target: float = 1.0 if bits & bit else 0.0
		var amount: float = move_toward(float(_amounts[bit]), target, float(RATES[bit]) * delta)
		_amounts[bit] = amount
		_material.set_shader_parameter(UNIFORMS[bit], amount)
		if bit != IRONBARK:
			_held_material.set_shader_parameter(UNIFORMS[bit], amount)
		any = any or amount > 0.0
	_set_overlay(any)

	_orbit.visible = float(_amounts[REPRISAL]) > 0.05
	if _orbit.visible:
		_orbit.rotate_y(delta * 2.4)
		_orbit.scale = Vector3.ONE * float(_amounts[REPRISAL])
	_motes.emitting = bits & EXALTED != 0
	_embers.emitting = bits & PHOENIX != 0
	_rage.emitting = bits & BERSERK != 0


## The overlay goes on only while something is showing, so an unbuffed player draws their
## meshes once rather than twice.
func _set_overlay(on: bool) -> void:
	if on == _overlay_on:
		return
	_overlay_on = on
	if on:
		_meshes.clear()
		_held.clear()
		var animator: Node = _player.get_node_or_null("Animator")
		if animator == null:
			return
		for node: Node in animator.find_children("*", "GeometryInstance3D", true, false):
			if _is_effect(node):
				continue
			if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
				_meshes.append(node as GeometryInstance3D)
			else:
				_held.append(node as GeometryInstance3D)
	for mesh: GeometryInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _material if on else null
	for mesh: GeometryInstance3D in _held:
		if is_instance_valid(mesh):
			mesh.material_overlay = _held_material if on else null


## Whether `node` is part of an effect the character carries rather than of the character.
func _is_effect(node: Node) -> bool:
	while node != null and node != _player:
		if node is MageHandOrb or node is GPUParticles3D:
			return true
		node = node.get_parent()
	return false


## Reprisal Ward: three plates of light circling the chest.
func _build_orbit() -> void:
	_orbit = Node3D.new()
	_orbit.name = "ReprisalOrbit"
	_orbit.position.y = 1.15
	_orbit.visible = false
	add_child(_orbit)
	var mesh: QuadMesh = SpellFx.premul_particle_mesh(0.34, "shard")
	var material := (mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = false
	material.albedo_color = Color(1.0, 0.85, 0.5)
	mesh.material = material
	for i: int in range(3):
		var plate := MeshInstance3D.new()
		plate.mesh = mesh
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle: float = TAU * float(i) / 3.0
		plate.position = Vector3(cos(angle), sin(angle * 2.0) * 0.15, sin(angle)) * 0.8
		_orbit.add_child(plate)


## A slow drift of points up off the body, for buffs that are waiting to go off.
func _build_drift(tint: Color, amount: int, lifetime: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.draw_pass_1 = SpellFx.premul_particle_mesh(0.12, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.35, 0.8, 0.35)
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.scale_curve = SpellFx._curve_texture([
		Vector2(0.0, 0.0), Vector2(0.3, 1.0), Vector2(1.0, 0.0),
	])
	process.color_ramp = SpellFx._premul_ramp(tint)
	particles.process_material = process
	particles.position.y = 1.0
	add_child(particles)
	return particles
