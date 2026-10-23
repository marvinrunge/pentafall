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
const ChargeFx := preload("res://scripts/charge_fx.gd")
## Oak bark from the map's own trees (assets/nature/_concepts/textures/bark_oak.png, scaled down).
const BARK_TEXTURE := "res://assets/vfx/ironbark_bark.png"

const SHIELD := 1
const REPRISAL := 2
const IRONBARK := 4
const EXALTED := 8
const PHOENIX := 16
const GIANT := 32
const BERSERK := 64
## Demonic Pact's debt (the server's, in status_fx); Unholy Strength and Blood Frenzy (their
## windows ride AttackCharges on the owner's machine, so they come from armed_charge_bits).
const PACT := 128
const UNHOLY := 256
const FRENZY := 512

## Bit -> overlay uniform it drives.
const UNIFORMS: Dictionary = {
	SHIELD: "shield", REPRISAL: "reprisal", IRONBARK: "bark",
	EXALTED: "exalted", PHOENIX: "phoenix", GIANT: "giant", BERSERK: "berserk",
	PACT: "pact", UNHOLY: "unholy", FRENZY: "frenzy",
}
## How fast a buff fades in or out, in amount per second. Bark grows over about half a
## second; light comes on faster.
const RATES: Dictionary = {
	SHIELD: 4.0, REPRISAL: 4.0, IRONBARK: 2.2, EXALTED: 5.0, PHOENIX: 3.0, GIANT: 2.0,
	BERSERK: 5.0, PACT: 3.0, UNHOLY: 3.0, FRENZY: 4.0,
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
## Blood Frenzy: embers thrown up off the body, more of them the lower the health.
var _frenzy_embers: GPUParticles3D = null
## Demonic Pact: violet-black smoke curling up off the one who owes.
var _pact_smoke: GPUParticles3D = null
## A next-attack charge on the weapon (ChargeFx): which one, how far faded in, the particles it
## gives off and the held mesh they come off - the biggest one the character holds.
var _charge_id: String = ""
var _charge_amount: float = 0.0
var _charge_motif: GPUParticles3D = null
var _charge_anchor: GeometryInstance3D = null


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
	_frenzy_embers = _build_drift(Color(1.0, 0.42, 0.12), 26, 0.7)
	_pact_smoke = _build_drift(Color(0.45, 0.12, 0.7), 16, 1.6)


func _process(delta: float) -> void:
	if _player == null:
		return
	var bits: int = int(_player.get("status_fx"))
	# A weapon carrying a charge for its next attack (AttackCharges), published by the player's
	# own machine, which is the one that holds the charges. A charge with a look of its own
	# wears it on the weapon (_update_charge); the rest glow with Exalted Strike's light.
	var armed: int = int(_player.get("armed_charge_bits"))
	if armed & ChargeFx.EXALTED_BIT:
		bits |= EXALTED
	if armed & ChargeFx.bit_of("black_6"):
		bits |= UNHOLY
	if armed & ChargeFx.bit_of("red_7"):
		bits |= FRENZY
	var any: bool = _update_charge(ChargeFx.id_of_bits(armed), delta)
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
	_frenzy_embers.emitting = bits & FRENZY != 0
	_pact_smoke.emitting = bits & PACT != 0
	# Blood Frenzy burns hotter the lower the health - the same rule its damage follows.
	var missing: float = 1.0 - clampf(float(_player.get("hp")) / maxf(float(_player.get("max_hp")), 1.0), 0.0, 1.0)
	_material.set_shader_parameter("frenzy_heat", missing)
	_held_material.set_shader_parameter("frenzy_heat", missing)


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


## The charge on the weapon: its pattern in the held overlay, faded in and out, and its
## particles following the weapon. Returns whether any of it is still showing.
func _update_charge(charge_id: String, delta: float) -> bool:
	if charge_id != "" and charge_id != _charge_id:
		_charge_id = charge_id
		var spec: Dictionary = ChargeFx.look(charge_id)
		var tint: Color = spec.get("tint", Color.WHITE)
		_held_material.set_shader_parameter("charge_tint", Vector3(tint.r, tint.g, tint.b))
		_held_material.set_shader_parameter("charge_pattern", int(spec.get("pattern", 0)))
		if _charge_motif != null:
			_charge_motif.queue_free()
		_charge_motif = ChargeFx.motif(charge_id)
		add_child(_charge_motif)
		_charge_anchor = null
	_charge_amount = move_toward(_charge_amount, 1.0 if charge_id != "" else 0.0, 4.0 * delta)
	_held_material.set_shader_parameter("charge", _charge_amount)
	if _charge_motif != null:
		_charge_motif.emitting = charge_id != ""
		_follow_weapon(_charge_motif)
	return _charge_amount > 0.0


## Puts the motif's emitter on the weapon: at the middle of the biggest thing the character
## holds, as big as it is. A character holding nothing (the mage's hands are its orb) gives it
## off at the casting hand's height instead.
func _follow_weapon(emitter: GPUParticles3D) -> void:
	if _charge_anchor == null or not is_instance_valid(_charge_anchor) or not _charge_anchor.is_inside_tree():
		_charge_anchor = null
		var best: float = 0.0
		for mesh: GeometryInstance3D in _held:
			# Out of the tree is a weapon this class does not carry, kept aside.
			if not is_instance_valid(mesh) or not mesh.is_inside_tree() or not mesh.is_visible_in_tree():
				continue
			var size: Vector3 = mesh.global_transform.basis.get_scale() * mesh.get_aabb().size
			var volume: float = absf(size.x * size.y * size.z)
			if volume > best:
				best = volume
				_charge_anchor = mesh
		if _charge_anchor != null:
			var span: Vector3 = (_charge_anchor.global_transform.basis.get_scale() * _charge_anchor.get_aabb().size).abs()
			var process := emitter.process_material as ParticleProcessMaterial
			if process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
				# The longest side stands up: the box is not turned with the weapon, and a blade
				# swinging through it reads as giving off along its whole length either way.
				var long: float = maxf(span.x, maxf(span.y, span.z))
				process.emission_box_extents = Vector3(0.12, clampf(long * 0.5, 0.15, 0.8), 0.12)
	if _charge_anchor != null:
		var box: AABB = _charge_anchor.get_aabb()
		emitter.global_position = _charge_anchor.global_transform * (box.position + box.size * 0.5)
	else:
		emitter.global_position = _player.global_position + Vector3(0.0, 1.2, 0.0) - _player.global_basis.z * 0.35


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
