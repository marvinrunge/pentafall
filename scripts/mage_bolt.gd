class_name MageBolt
extends Node3D
## A bolt from the mage's hand (MageKit), in flight - or the Arcane Blast, the same thing
## bigger, slower and bursting.
##
## Built like PlayerArrow, for the same reasons: swept rather than a physics body, so a fast
## bolt cannot step through a goblin between two frames; resolved on the thrower's machine,
## so it lands the moment it looks like it lands, with only the damage going to the server
## (Player._basic_strike); and flown on every other screen as a picture (Player._net_spawn_bolt)
## that does nothing but stop where the thrower's stops.
##
## It flies straight - a bolt of mana does not drop - and is drawn in the colour of the
## mage's path (Player.path_color): a ball of living energy (SpellFx.energy_orb - swirling,
## boiling, flickering) with the air shimmering over it, little arcs of lightning crackling
## round it, a tail along its flight, a glitter of motes left hanging in the air behind it and
## a light. Where it ends the ball bursts outward and fades.
## A bolt with a `blast_radius` hits everything inside that radius where it bursts, the enemy
## it struck included; a plain one hits the one it struck.

## Enemies (layer 3) and the environment (layer 5) - never players, myrs or allies.
const HIT_MASK: int = 4 | 16
## The colours a bolt can be, by Player.path_color. "" is a mage who has put nothing into any
## colour yet: plain arcane light.
const TINTS: Dictionary = {
	"": Color(0.74, 0.66, 1.0),
	"white": SpellVisuals.WHITE_GOLD,
	"blue": Player.FX_BLUE,
	"black": Player.FX_BLACK,
	"red": Player.FX_RED,
	"green": Player.FX_GREEN,
}
## Sent over the wire as an index rather than a string.
const COLORS: Array[String] = ["", "white", "blue", "black", "red", "green"]

var velocity: Vector3 = Vector3.ZERO
var shooter: Player = null
## Damage per enemy struck. Zero on every copy but the thrower's.
var authority_damage: float = 0.0
var exile_on_kill: bool = false
var knockback: float = 0.0
var blast_radius: float = 0.0
## How big it is drawn: 1 a bolt, more for the blast and for a bolt Prowess empowered.
var size: float = 1.0
var color: String = ""
var _travelled: float = 0.0
var _range: float = 50.0
var _done: bool = false
var _orb: Node3D = null
## The motes left hanging behind it, in the world rather than on the bolt - so they stay where
## they were shed. Handed to the scene when the bolt ends, to die out on their own.
var _wake: GPUParticles3D = null


## Puts a bolt into the world and sends it on its way.
static func launch(from: Player, origin: Vector3, launch_velocity: Vector3, p_color: String,
		p_size: float, p_blast_radius: float, p_range: float) -> MageBolt:
	var bolt := MageBolt.new()
	bolt.shooter = from
	bolt.velocity = launch_velocity
	bolt.color = p_color
	bolt.size = p_size
	bolt.blast_radius = p_blast_radius
	bolt._range = p_range
	var holder: Node = from.get_tree().current_scene if from.get_tree().current_scene != null else from.get_parent()
	holder.add_child(bolt)
	bolt.global_position = origin
	bolt._face_flight()
	return bolt


static func tint_of(p_color: String) -> Color:
	return TINTS.get(p_color, TINTS[""])


static func color_index(p_color: String) -> int:
	return maxi(COLORS.find(p_color), 0)


func _ready() -> void:
	var tint: Color = tint_of(color)
	# The ball: churning energy in the colour, the air bending over it.
	_orb = SpellFx.energy_orb_tinted(0.13 * size, tint, 0.008 * size)
	var orb_material: ShaderMaterial = SpellFx.energy_orb_material(_orb)
	orb_material.set_shader_parameter("energy", 1.6)
	orb_material.set_shader_parameter("spin", 4.0)
	orb_material.set_shader_parameter("boil_speed", 2.2)
	add_child(_orb)
	# Lightning crackling round it: a few short arcs, each a flash at a random turn.
	add_child(_crackle(tint))
	# A glitter of motes shed into the air behind it.
	_wake = SpellFx.sparks(tint, 0.06 * size, int(18 * size), 0.5, "mote")
	_wake.name = "Wake"
	_wake.one_shot = false
	_wake.explosiveness = 0.0
	_wake.lifetime = 0.45
	(_wake.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, 0.3, 0.0)
	add_child(_wake)
	# The tail: one crossed streak behind the head, its +Y turned back along the flight -
	# the way SpellVisuals.fire_bolt draws the fireball's.
	var tail := MeshInstance3D.new()
	tail.mesh = SpellFx.tail_mesh(0.32 * size, 1.4 * size, Color(tint.r * 1.6, tint.g * 1.6, tint.b * 1.6))
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.rotation.x = -PI * 0.5
	add_child(tail)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.2 * size
	light.omni_range = 2.8 * size
	add_child(light)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit:
		_burst(hit["position"], PlayerArrow._enemy_of(hit["collider"] as Node))
		return
	global_position = to
	_travelled += velocity.length() * delta
	if _travelled >= _range:
		_burst(global_position, null)


## A handful of lightning arcs flashing on and off round the ball, at random turns - the
## lightning orb's arc, with its ends thinned out (slot "arc_tapered") so the arcs fade into
## the air instead of all stopping on one circle round the ball - short-lived, so it reads as
## crackle, not as a shape.
func _crackle(tint: Color) -> GPUParticles3D:
	var arcs := GPUParticles3D.new()
	arcs.name = "Crackle"
	arcs.amount = 4
	arcs.lifetime = 0.12
	arcs.local_coords = true
	# A size larger than the plain arc was drawn at: the taper eats its ends.
	arcs.draw_pass_1 = SpellFx.premul_particle_mesh(0.55 * size, "arc_tapered")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05 * size
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.scale_min = 0.6
	process.scale_max = 1.1
	process.color_ramp = SpellFx._premul_ramp(tint.lerp(Color.WHITE, 0.4))
	arcs.process_material = process
	return arcs


func _face_flight() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var forward: Vector3 = velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	global_basis = Basis.looking_at(forward, up)


## Where the bolt ends: the light at the point, and - on the thrower's copy - the damage.
## `struck` is the enemy it flew into, or null for the ground, a wall or the end of its range.
func _burst(at: Vector3, struck: Node3D) -> void:
	_done = true
	global_position = at
	var tint: Color = tint_of(color)
	var holder: Node = get_parent()
	_pop(holder, at)
	_release_wake(holder)
	if blast_radius > 0.0:
		var flash: Node3D = SpellFx.impact(tint, blast_radius * 0.6)
		holder.add_child(flash)
		flash.global_position = at
		SoundBank.play_at(&"spell_missile_impact", at)
	else:
		# The orbs' own small hit, sized for something that lands every half second; it frees
		# nothing by itself (its shot's root does that), so this one is timed out here.
		var spark: Node3D = OrbitingOrb._bolt_impact(OrbitingOrb.Mode.FROST, tint)
		holder.add_child(spark)
		spark.global_position = at
		spark.get_tree().create_timer(0.7).timeout.connect(spark.queue_free)
		SoundBank.play_at(&"spell_missile_impact", at)
	if authority_damage > 0.0 and is_instance_valid(shooter):
		var struck_any: bool = false
		if blast_radius > 0.0:
			for enemy: Node3D in shooter._enemies_in_radius(at, blast_radius):
				_strike(enemy)
				struck_any = true
		elif struck != null:
			_strike(struck)
			struck_any = true
		# The bolt feeds the spells exactly as the axe does: a hit takes time off them -
		# once per bolt, not per enemy a blast catches (MeleeKit.land_due_hits says why).
		if struck_any:
			shooter._reduce_spell_cooldowns(GameSettings.melee_hit_cooldown_reduction)
	queue_free()


## The ball bursting where it ends: moved into the scene, swelling and fading out in a moment.
func _pop(holder: Node, at: Vector3) -> void:
	if _orb == null:
		return
	remove_child(_orb)
	holder.add_child(_orb)
	_orb.global_position = at
	var material: ShaderMaterial = SpellFx.energy_orb_material(_orb)
	var tween: Tween = _orb.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_orb, "scale", Vector3.ONE * (2.4 if blast_radius > 0.0 else 1.9), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if material != null:
		tween.tween_method(func(value: float) -> void: material.set_shader_parameter("fade", value), 1.0, 0.0, 0.18)
	tween.chain().tween_callback(_orb.queue_free)
	_orb = null


## The wake stays where it was shed: handed to the scene, stops shedding, and is freed once
## the last mote has died.
func _release_wake(holder: Node) -> void:
	if _wake == null:
		return
	var at: Transform3D = _wake.global_transform
	remove_child(_wake)
	holder.add_child(_wake)
	_wake.global_transform = at
	_wake.emitting = false
	_wake.get_tree().create_timer(_wake.lifetime + 0.1).timeout.connect(_wake.queue_free)
	_wake = null


func _strike(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	shooter._basic_strike(enemy, authority_damage, exile_on_kill, false)
	shooter._apply_basic_attack_knockback(enemy, knockback)
