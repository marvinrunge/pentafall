extends RefCounted
## What a "your next attack ..." charge looks like (docs/SPELL_VFX_ROUND_TWO.md): on the weapon
## while it waits (StatusFx draws it from `LOOKS`), at the cast that arms it (`arm`), and where
## the charged hit lands (`hit`).
##
## Every charge has a look of its own. They used to share Exalted Strike's gold weapon glow and
## the generic ring, beam and impact, so eleven different skills read as one - a frost charge
## and a bomb charge on the same blade looked identical. The table is the one place a charge's
## look is decided: its tint, the pattern the weapon overlay draws (status_overlay.gdshader's
## `charge_pattern`), and the particles the weapon gives off.
##
## Exalted Strike and Rubblebelt Rioters are not in it and keep Exalted's gold glow
## (EXALTED_BIT); the two windowed self-buffs (Unholy Strength, Blood Frenzy) are drawn on the
## body instead (BODY_IDS, StatusFx).
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

## The charges with a look of their own, in bit order: AttackCharges.armed_bits publishes one
## bit per armed charge, so every screen knows WHICH charge a weapon carries, not only its colour.
const IDS: Array[String] = [
	"white_7", "white_8", "white_9", "blue_7", "blue_8", "blue_9",
	"black_3", "black_7", "red_8", "green_6", "green_7",
]
## Any other armed charge: drawn as Exalted Strike's glow.
const EXALTED_BIT := 1 << 15
## The two windows of every attack (Unholy Strength, Blood Frenzy): a bit each too, but drawn
## on the body by StatusFx rather than on the weapon.
const BODY_IDS: Array[String] = ["black_6", "red_7"]
const BODY_BIT_SHIFT := 13

## status_overlay.gdshader's `charge_pattern`, in the shader's order.
enum Pattern { PULSE, RAYS, BANDS, FROST, CRYSTAL, SAND, SMOKE, BONE, EMBER, GROWTH, VINES }
## How the particles leave the weapon.
enum Motion { RISE, FALL, ORBIT, INFLOW, SPRAY, DRIP, DRIFT }

const SUN := Color(1.0, 0.93, 0.62)
const ICE := Color(0.62, 0.86, 1.0)
const BONE := Color(0.9, 0.85, 0.74)
const VIOLET := Color(0.62, 0.3, 0.85)
const FUSE := Color(1.0, 0.58, 0.22)
const VINE := Color(0.42, 0.78, 0.26)

## Spell id -> its look. `tint` colours the overlay and the particles; `slot` is the particle's
## SpellFx texture, `size` its quad in metres, `amount` how many live at once.
const LOOKS: Dictionary = {
	# Smite the Monstrous: a heavy gold throb, embers of light lifting off.
	"white_7": {"tint": Color(1.0, 0.78, 0.36), "pattern": Pattern.PULSE, "slot": "spark",
		"motion": Motion.RISE, "amount": 20, "size": 0.26, "lifetime": 0.9},
	# Sunlance: rays running along the blade, streaking off it forward.
	"white_8": {"tint": SUN, "pattern": Pattern.RAYS, "slot": "mote",
		"motion": Motion.SPRAY, "amount": 22, "size": 0.32, "lifetime": 0.45},
	# Mark of Sanctity: thin bands of light sliding up the weapon, glints circling it.
	"white_9": {"tint": Color(1.0, 0.97, 0.88), "pattern": Pattern.BANDS, "slot": "mote",
		"motion": Motion.ORBIT, "amount": 14, "size": 0.26, "lifetime": 1.2},
	# Crippling Chill: rime creeping over it, flakes falling off.
	"blue_7": {"tint": ICE, "pattern": Pattern.FROST, "slot": "shard",
		"motion": Motion.FALL, "amount": 20, "size": 0.16, "lifetime": 1.1},
	# Ice Cage: grown over with ice facets, crystals hanging in the air round it.
	"blue_8": {"tint": Color(0.75, 0.93, 1.0), "pattern": Pattern.CRYSTAL, "slot": "shard",
		"motion": Motion.ORBIT, "amount": 11, "size": 0.32, "lifetime": 1.6},
	# Time Ebb: sand running BACKWARDS, up out of the air into the weapon.
	"blue_9": {"tint": Color(0.5, 0.72, 1.0), "pattern": Pattern.SAND, "slot": "mote",
		"motion": Motion.INFLOW, "amount": 31, "size": 0.14, "lifetime": 0.8},
	# Deathtouch: violet dark that eats the light, dripping off the edge.
	"black_3": {"tint": VIOLET, "pattern": Pattern.SMOKE, "slot": "smoke",
		"motion": Motion.DRIP, "amount": 14, "size": 0.72, "lifetime": 1.1},
	# Bone Splinters: the weapon pale and cracked, splinters circling it.
	"black_7": {"tint": BONE, "pattern": Pattern.BONE, "slot": "shard",
		"motion": Motion.ORBIT, "amount": 13, "size": 0.29, "lifetime": 1.3},
	# Powder Keg: a fuse's heat flickering through it, sparks spitting off.
	"red_8": {"tint": FUSE, "pattern": Pattern.EMBER, "slot": "spark",
		"motion": Motion.SPRAY, "amount": 31, "size": 0.19, "lifetime": 0.35},
	# Become Immense: a thick living rim swelling, motes of growth lifting.
	"green_6": {"tint": Color(0.5, 0.95, 0.4), "pattern": Pattern.GROWTH, "slot": "mote",
		"motion": Motion.RISE, "amount": 22, "size": 0.35, "lifetime": 1.0},
	# Entangling Vines: dark green vines wound round the haft, leaves drifting down.
	"green_7": {"tint": VINE, "pattern": Pattern.VINES, "slot": "shard",
		"motion": Motion.DRIFT, "amount": 11, "size": 0.26, "lifetime": 1.6},
}


static func bit_of(spell_id: String) -> int:
	var index: int = IDS.find(spell_id)
	if index >= 0:
		return 1 << index
	var body: int = BODY_IDS.find(spell_id)
	return 1 << (BODY_BIT_SHIFT + body) if body >= 0 else EXALTED_BIT


## The charge a weapon shows when it carries several: the first in IDS order.
static func id_of_bits(bits: int) -> String:
	for index: int in range(IDS.size()):
		if bits & (1 << index):
			return IDS[index]
	return ""


static func look(spell_id: String) -> Dictionary:
	return LOOKS.get(spell_id, {})


# --- on the weapon ----------------------------------------------------------------

## What the weapon gives off while `spell_id` waits on it. StatusFx owns it, moves it to the
## weapon every frame and sizes `emission_box_extents` to the weapon; the particles live in the
## world, so a swing leaves them behind as a trail.
static func motif(spell_id: String) -> GPUParticles3D:
	var spec: Dictionary = look(spell_id)
	var tint: Color = spec.get("tint", Color.WHITE)
	var particles := GPUParticles3D.new()
	particles.name = "ChargeMotif"
	particles.amount = int(spec.get("amount", 12))
	particles.lifetime = float(spec.get("lifetime", 1.0))
	particles.emitting = false
	particles.local_coords = false
	particles.draw_pass_1 = SpellFx.premul_particle_mesh(float(spec.get("size", 0.15)), String(spec.get("slot", "mote")))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.12, 0.4, 0.12)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	match int(spec.get("motion", Motion.RISE)):
		Motion.RISE:
			process.direction = Vector3.UP
			process.spread = 20.0
			process.initial_velocity_min = 0.3
			process.initial_velocity_max = 0.9
			process.gravity = Vector3(0.0, 0.5, 0.0)
		Motion.FALL:
			process.direction = Vector3.DOWN
			process.spread = 25.0
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.4
			process.gravity = Vector3(0.0, -1.6, 0.0)
			process.angular_velocity_min = -180.0
			process.angular_velocity_max = 180.0
		Motion.ORBIT:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_radius = 0.45
			process.emission_ring_inner_radius = 0.3
			process.emission_ring_height = 0.6
			process.direction = Vector3.UP
			process.spread = 0.0
			process.initial_velocity_min = 0.05
			process.initial_velocity_max = 0.15
			process.gravity = Vector3.ZERO
			process.tangential_accel_min = 3.0
			process.tangential_accel_max = 4.5
			process.radial_accel_min = -0.6
			process.radial_accel_max = -0.3
			process.angular_velocity_min = -120.0
			process.angular_velocity_max = 120.0
		Motion.INFLOW:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			process.emission_sphere_radius = 0.75
			process.direction = Vector3.UP
			process.spread = 0.0
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.1
			process.gravity = Vector3(0.0, 0.8, 0.0)
			process.radial_accel_min = -3.2
			process.radial_accel_max = -2.2
		Motion.SPRAY:
			process.direction = Vector3.UP
			process.spread = 70.0
			process.initial_velocity_min = 1.2
			process.initial_velocity_max = 2.6
			process.gravity = Vector3(0.0, -4.0, 0.0)
			process.damping_min = 2.0
			process.damping_max = 4.0
			process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(0.4, 0.6), Vector2(1.0, 0.0)])
		Motion.DRIP:
			# Smoke that covers rather than glows: a dark violet, premultiplied, so it darkens
			# what is behind it.
			process.direction = Vector3.DOWN
			process.spread = 15.0
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.3
			process.gravity = Vector3(0.0, -0.9, 0.0)
			process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.3), Vector2(0.5, 1.0), Vector2(1.0, 0.6)])
			process.color_ramp = _premul_fade(Color(0.08, 0.02, 0.12, 0.7))
		Motion.DRIFT:
			process.direction = Vector3.DOWN
			process.spread = 40.0
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.3
			process.gravity = Vector3(0.0, -0.7, 0.0)
			process.angular_velocity_min = -200.0
			process.angular_velocity_max = 200.0
			process.color_ramp = _premul_fade(Color(0.24, 0.42, 0.14, 0.95))
	particles.process_material = process
	return particles


## A ramp from `colour` to nothing, premultiplied: for particles that are pigment - smoke,
## leaves, earth - and must cover, not shine.
static func _premul_fade(colour: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(colour.r * colour.a, colour.g * colour.a, colour.b * colour.a, colour.a))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


# --- the cast that arms it ---------------------------------------------------------

## The moment a charge is armed, on the caster: the charge's own particles drawn in from a
## ring and gathering at the weapon arm, and its light. The look on the weapon then takes over.
static func arm(spell_id: String) -> Node3D:
	var spec: Dictionary = look(spell_id)
	var tint: Color = spec.get("tint", Color.WHITE)
	var root := Node3D.new()
	root.name = "ChargeArm"
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 3.0
	light.omni_range = 3.0
	light.position = Vector3(0.35, 1.2, -0.2)
	root.add_child(light)
	var gather := GPUParticles3D.new()
	gather.amount = 26
	gather.lifetime = 0.5
	gather.one_shot = true
	gather.explosiveness = 0.75
	gather.local_coords = true
	gather.draw_pass_1 = SpellFx.premul_particle_mesh(float(spec.get("size", 0.15)) * 1.2, String(spec.get("slot", "mote")))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process.emission_sphere_radius = 1.3
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.2
	process.radial_accel_min = -9.0
	process.radial_accel_max = -6.0
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.2), Vector2(0.5, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	gather.process_material = process
	gather.position = light.position
	root.add_child(gather)
	root.tree_entered.connect(func() -> void:
		gather.emitting = true
		var tween: Tween = root.create_tween()
		tween.tween_property(light, "light_energy", 0.0, 0.55)
		tween.tween_interval(0.3)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- where it lands ------------------------------------------------------------------

## The charged hit itself, placed at the foot of whatever it struck (or where the blow fell).
## `size` and `dir` mean what the charge needs: a lance's length and heading, the distance and
## heading to whatever a splinter flies at, the way home for Time Ebb.
static func hit(id: String, size: float, dir: Vector3) -> Node3D:
	match id:
		"white_7": return _smite()
		"white_8": return _sunlance(size, dir)
		"white_9": return _sanctity()
		"blue_7": return _chill(false)
		"blue_7_final": return _chill(true)
		"blue_8": return _ice_cage()
		"blue_9": return _time_ebb(size, dir)
		"black_3": return _deathtouch()
		"black_7": return _bone_volley(size, dir)
		"red_8": return _fuse_lit()
		"green_6": return _immense(size)
		"green_7": return _roots(size)
	return Node3D.new()


## Frees `root` after `seconds`, once it is in the tree. On the node's own tween rather than a
## scene-tree timer, so a root freed early (a scene change) takes its clock with it.
static func _expire(root: Node3D, seconds: float) -> void:
	_later(root, seconds, root.queue_free)


## Runs `what` `seconds` after `root` enters the tree, on root's own tween - gone with root.
static func _later(root: Node3D, seconds: float, what: Callable) -> void:
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(seconds)
		tween.tween_callback(what), CONNECT_ONE_SHOT)


## A one-shot particle system that starts when it enters the tree.
static func _burst(particles: GPUParticles3D, at: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	particles.position = at
	particles.tree_entered.connect(func() -> void: particles.emitting = true, CONNECT_ONE_SHOT)
	return particles


static func _flash(root: Node3D, tint: Color, energy: float, reach: float, height: float = 1.0,
		fall: float = 0.2) -> void:
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.position.y = height
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		root.create_tween().tween_property(light, "light_energy", 0.0, fall), CONNECT_ONE_SHOT)


## Smite the Monstrous: the blow comes down like a hammer of light - gold cracks split the
## ground under the target and sparks are thrown UP out of them.
static func _smite() -> Node3D:
	var root := Node3D.new()
	root.name = "Smite"
	var gold := Color(1.0, 0.78, 0.36)
	root.add_child(SpellVisuals.ground_cracks(1.7, gold, 1.0))
	var sparks: GPUParticles3D = SpellFx.sparks(gold, 0.8, 34, 7.5, "spark")
	(sparks.process_material as ParticleProcessMaterial).spread = 35.0
	root.add_child(_burst(sparks, Vector3(0.0, 0.3, 0.0)))
	root.add_child(SpellFx.shockwave(gold, 2.0, 0.3))
	_flash(root, gold, 6.0, 4.5, 1.2, 0.25)
	_expire(root, 3.5)
	return root


## Sunlance: a lance of sunlight driven on past the hit, a flare where it ends, and the air
## along its line left glittering as it fades. Light, not a wound in the ground - a dark scar
## along the line was Doom Blade's look.
static func _sunlance(length: float, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Sunlance"
	var facing: Vector3 = Vector3(dir.x, 0.0, dir.z)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	length = maxf(length, 2.0)
	var travel: float = 0.16
	var glitter := GPUParticles3D.new()
	glitter.amount = clampi(int(length * 7.0), 30, 110)
	glitter.lifetime = 1.1
	glitter.one_shot = true
	glitter.explosiveness = 0.8
	glitter.local_coords = true
	glitter.draw_pass_1 = SpellFx.premul_particle_mesh(0.42, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Along the node's +Z, where the lance runs once the root is turned.
	process.emission_box_extents = Vector3(0.35, 0.3, length * 0.5)
	process.direction = Vector3.UP
	process.spread = 20.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(SUN)
	glitter.process_material = process
	root.add_child(_burst(glitter, Vector3(0.0, 1.0, length * 0.5)))
	var lance: Node3D = SpellFx.beam(facing, length, SUN, 1.5, 0.4)
	lance.position.y = 1.0
	root.add_child(lance)
	var flare: Node3D = SpellFx.energy_orb_tinted(0.55, SUN)
	flare.position = Vector3(0.0, 1.0, length)
	flare.scale = Vector3.ONE * 0.2
	root.add_child(flare)
	var motes: GPUParticles3D = SpellFx.sparks(SUN, 0.6, 24, 4.0, "mote")
	root.add_child(_burst(motes, Vector3(0.0, 1.0, length)))
	_flash(root, SUN, 5.0, 4.0, 1.0, 0.3)
	root.tree_entered.connect(func() -> void:
		# +Z along the lance: the glitter and the flare are laid out along local +Z.
		root.look_at(root.global_position - facing, Vector3.UP)
		var tween: Tween = root.create_tween()
		tween.tween_interval(travel)
		tween.tween_property(flare, "scale", Vector3.ONE * 1.3, 0.12).set_ease(Tween.EASE_OUT)
		tween.tween_property(flare, "scale", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_interval(3.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Mark of Sanctity: a shaft of light falls onto the target's head, and a halo of glints
## turns there for a moment - singled out from above.
static func _sanctity() -> Node3D:
	var root := Node3D.new()
	root.name = "SanctityMark"
	var ivory := Color(1.0, 0.96, 0.84)
	var shaft: Node3D = SpellFx.beam(Vector3.DOWN, 2.4, ivory, 0.55, 0.35)
	shaft.position.y = 4.4
	root.add_child(shaft)
	var halo := GPUParticles3D.new()
	halo.amount = 22
	halo.lifetime = 1.4
	halo.one_shot = true
	halo.explosiveness = 1.0
	halo.local_coords = true
	halo.draw_pass_1 = SpellFx.premul_particle_mesh(0.34, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.6
	process.emission_ring_inner_radius = 0.56
	process.emission_ring_height = 0.02
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.gravity = Vector3.ZERO
	# Circling without drifting off: a little inward pull keeps the ring its size.
	process.tangential_accel_min = 1.6
	process.tangential_accel_max = 1.6
	process.radial_accel_min = -0.4
	process.radial_accel_max = -0.4
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.15, 1.0), Vector2(0.75, 0.9), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(ivory)
	halo.process_material = process
	root.add_child(_burst(halo, Vector3(0.0, 2.05, 0.0)))
	_flash(root, ivory, 3.5, 3.0, 2.2, 0.4)
	_expire(root, 2.0)
	return root


## Crippling Chill: a puff of frost off the struck body and rime on the ground under it; the
## third, freezing hit shatters outward with a white flash.
static func _chill(final: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Chill"
	var radius: float = 1.4 if final else 0.8
	var shards: GPUParticles3D = SpellFx.sparks(ICE, radius, 34 if final else 16, 5.5 if final else 2.5, "shard")
	(shards.process_material as ParticleProcessMaterial).angular_velocity_min = -300.0
	(shards.process_material as ParticleProcessMaterial).angular_velocity_max = 300.0
	root.add_child(_burst(shards, Vector3(0.0, 1.0, 0.0)))
	root.add_child(SpellVisuals.dust_ring(radius, 1.0, Color(0.85, 0.94, 1.0)))
	var rime: MeshInstance3D = SpellFx.ground_decal("decal_frost", Color(0.86, 0.94, 1.0, 0.8), radius * 1.2, 2.0)
	rime.position.y = 0.06
	root.add_child(rime)
	if final:
		_flash(root, Color(0.85, 0.95, 1.0), 6.0, 4.0, 1.0, 0.18)
	_expire(root, 4.0)
	return root


## Ice Cage: crystals pulled in out of the air from every side, closing on the target.
static func _ice_cage() -> Node3D:
	var root := Node3D.new()
	root.name = "IceCageClose"
	var tint := Color(0.75, 0.93, 1.0)
	var close := GPUParticles3D.new()
	close.amount = 40
	close.lifetime = 0.45
	close.one_shot = true
	close.explosiveness = 0.9
	close.local_coords = true
	close.draw_pass_1 = SpellFx.premul_particle_mesh(0.34, "shard")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process.emission_sphere_radius = 2.2
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.gravity = Vector3.ZERO
	process.radial_accel_min = -22.0
	process.radial_accel_max = -18.0
	process.angular_velocity_min = -240.0
	process.angular_velocity_max = 240.0
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(0.7, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	close.process_material = process
	root.add_child(_burst(close, Vector3(0.0, 1.0, 0.0)))
	root.add_child(SpellVisuals.dust_ring(1.1, 1.2, Color(0.88, 0.95, 1.0)))
	var rime: MeshInstance3D = SpellFx.ground_decal("decal_frost", Color(0.9, 0.96, 1.0, 0.9), 1.5, 3.0)
	rime.position.y = 0.06
	root.add_child(rime)
	# The flash when the crystals meet, not when they set out.
	var meet := OmniLight3D.new()
	meet.light_color = tint
	meet.light_energy = 0.0
	meet.omni_range = 3.5
	meet.position.y = 1.0
	root.add_child(meet)
	var crack: GPUParticles3D = SpellFx.sparks(tint, 0.6, 18, 3.0, "shard")
	crack.emitting = false
	crack.position.y = 1.0
	root.add_child(crack)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(0.38)
		tween.tween_callback(func() -> void: crack.emitting = true)
		tween.tween_property(meet, "light_energy", 5.0, 0.02)
		tween.tween_property(meet, "light_energy", 0.0, 0.2)
		tween.tween_interval(4.4)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Time Ebb: the target comes apart into blue sand that streams back the way it came, and
## gathers again where it spawned - `size` metres along `dir`. A boss, which is only slowed,
## gets the sand swirling back into itself instead (`size` 0).
static func _time_ebb(distance: float, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TimeEbb"
	var tint := Color(0.5, 0.72, 1.0)
	var heading: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
	var sand := GPUParticles3D.new()
	sand.amount = 110
	sand.lifetime = 0.7
	sand.one_shot = true
	sand.explosiveness = 0.85
	sand.local_coords = false
	sand.draw_pass_1 = SpellFx.streak_mesh(0.16, 0.9, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.35, 0.85, 0.35)
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	if heading != Vector3.ZERO and distance > 0.5:
		process.direction = heading
		process.spread = 6.0
		process.initial_velocity_min = minf(distance, 30.0) * 1.4
		process.initial_velocity_max = minf(distance, 30.0) * 1.8
		process.gravity = Vector3.ZERO
	else:
		process.direction = Vector3.UP
		process.spread = 0.0
		process.initial_velocity_min = 0.0
		process.initial_velocity_max = 0.3
		process.gravity = Vector3.ZERO
		process.tangential_accel_min = -6.0
		process.tangential_accel_max = -4.0
		process.radial_accel_min = -2.0
		process.radial_accel_max = -1.0
	sand.process_material = process
	root.add_child(_burst(sand, Vector3(0.0, 1.0, 0.0)))
	root.add_child(SpellFx.shockwave(tint, 1.3, 0.35, PI, -1.0, false))
	_flash(root, tint, 4.0, 3.0, 1.0, 0.3)
	if heading != Vector3.ZERO and distance > 0.5:
		# Where it lands: the sand from the trip pulled in to one point and thrown out as the
		# enemy stands up there again. The light travels the same way, so the eye follows.
		var arrive := Node3D.new()
		arrive.position = heading * distance
		root.add_child(arrive)
		_later(root, 0.35, func() -> void:
			arrive.add_child(SpellFx.cast_glow(tint, 1.4))
			arrive.add_child(_burst(SpellFx.sparks(tint, 0.6, 22, 2.5, "mote"), Vector3(0.0, 1.0, 0.0))))
	_expire(root, 2.5)
	return root


## Deathtouch: the soul torn up out of the body in a violet column, dark smoke left behind.
static func _deathtouch() -> Node3D:
	var root := Node3D.new()
	root.name = "Deathtouch"
	var soul := GPUParticles3D.new()
	soul.amount = 30
	soul.lifetime = 0.8
	soul.one_shot = true
	soul.explosiveness = 0.8
	soul.local_coords = true
	soul.draw_pass_1 = SpellFx.streak_mesh(0.12, 0.9, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 9.0
	process.damping_min = 4.0
	process.damping_max = 7.0
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.6), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(VIOLET)
	soul.process_material = process
	root.add_child(_burst(soul, Vector3(0.0, 1.0, 0.0)))
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(1.0, 12, 1.4)
	root.add_child(_burst(smoke, Vector3(0.0, 0.5, 0.0)))
	_flash(root, VIOLET, 4.5, 3.5, 1.3, 0.35)
	_expire(root, 3.0)
	return root


## Bone Splinters, for one corpse: it bursts into bone, and a volley of splinters flies the
## `distance` along `dir` to whatever it found (none, when it found nothing).
static func _bone_volley(distance: float, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "BoneVolley"
	root.add_child(SpellVisuals.splinters(BONE, 1.0, 34))
	root.add_child(SpellVisuals.dust_ring(0.8, 0.8, Color(0.62, 0.56, 0.48)))
	var heading: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
	if heading != Vector3.ZERO and distance > 0.5:
		var travel: float = 0.22
		var volley := GPUParticles3D.new()
		volley.amount = 11
		volley.lifetime = travel
		volley.one_shot = true
		volley.explosiveness = 0.7
		volley.local_coords = false
		volley.draw_pass_1 = SpellFx.streak_mesh(0.26, 1.1, "shard")
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.25
		process.direction = heading
		process.spread = 4.0
		process.initial_velocity_min = distance / travel * 0.95
		process.initial_velocity_max = distance / travel * 1.05
		process.gravity = Vector3.ZERO
		process.particle_flag_align_y = true
		process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.6), Vector2(0.15, 1.0), Vector2(0.9, 1.0), Vector2(1.0, 0.0)])
		process.color_ramp = SpellFx._premul_ramp(BONE)
		volley.process_material = process
		root.add_child(_burst(volley, Vector3(0.0, 0.6, 0.0)))
		var arrive := Node3D.new()
		arrive.position = heading * distance + Vector3(0.0, 0.4, 0.0)
		root.add_child(arrive)
		_later(root, travel, func() -> void:
			arrive.add_child(_burst(SpellFx.sparks(BONE, 0.5, 16, 3.0, "shard"))))
	_expire(root, 2.0)
	return root


## Powder Keg: a fuse lit on the target - sparks spitting and a curl of grey smoke.
static func _fuse_lit() -> Node3D:
	var root := Node3D.new()
	root.name = "FuseLit"
	root.add_child(_burst(SpellFx.sparks(FUSE, 0.4, 30, 4.5, "spark"), Vector3(0.0, 1.3, 0.0)))
	var smoke := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 0.6, 8, 1.0)
	var process: ParticleProcessMaterial = smoke.process_material
	process.direction = Vector3.UP
	process.spread = 20.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.2
	# The flipbook blends straight alpha (ExplosionFx), so its ramp is not premultiplied.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.35, 0.33, 0.3, 0.6))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.35, 0.33, 0.3, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	root.add_child(_burst(smoke, Vector3(0.0, 1.3, 0.0)))
	_flash(root, FUSE, 3.5, 2.5, 1.3, 0.25)
	_expire(root, 2.0)
	return root


## Become Immense: the blow lands with the weight of something enormous - a bulge of green
## force swelling out of the impact and the ground thrown up round it.
static func _immense(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Immense"
	radius = maxf(radius, 1.5)
	var green := Color(0.5, 0.95, 0.4)
	var bulge: Node3D = SpellFx.energy_orb_tinted(radius * 0.5, green)
	bulge.position.y = 0.6
	bulge.scale = Vector3.ONE * 0.2
	root.add_child(bulge)
	root.add_child(SpellVisuals.dirt_burst(radius * 0.7))
	root.add_child(SpellVisuals.dust_ring(radius * 0.6, 1.0))
	_flash(root, green, 5.0, radius * 2.5, 0.8, 0.3)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_property(bulge, "scale", Vector3.ONE * 1.4, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(bulge, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_interval(1.4)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Entangling Vines: roots whip up out of the ground across `radius`, hold, and sink back.
static func _roots(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Roots"
	radius = maxf(radius, 1.5)
	var mesh: ArrayMesh = _tendril_mesh()
	var count: int = clampi(int(radius * 3.0), 6, 14)
	var tendrils: Array[MeshInstance3D] = []
	for index: int in range(count):
		var tendril := MeshInstance3D.new()
		tendril.mesh = mesh
		var angle: float = TAU * float(index) / float(count) + randf_range(-0.3, 0.3)
		var reach: float = radius * sqrt(randf_range(0.08, 1.0))
		tendril.position = Vector3(cos(angle), 0.0, sin(angle)) * reach + Vector3(0.0, -0.05, 0.0)
		tendril.rotation.y = randf() * TAU
		tendril.scale = Vector3(1.0, 0.0, 1.0) * randf_range(0.8, 1.25)
		tendril.set_meta("height", randf_range(0.8, 1.3))
		root.add_child(tendril)
		tendrils.append(tendril)
	var grit: Node3D = SpellVisuals.dirt_burst(radius * 0.5)
	root.add_child(grit)
	root.add_child(SpellVisuals.dust_ring(radius * 0.7, 1.0, Color(0.42, 0.36, 0.22)))
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween().set_parallel(true)
		for tendril: MeshInstance3D in tendrils:
			var grown: float = float(tendril.get_meta("height")) * tendril.scale.x
			var delay: float = randf_range(0.0, 0.12)
			tween.tween_property(tendril, "scale:y", grown, 0.22).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(tendril, "scale:y", 0.0, 0.5).set_delay(delay + 2.4) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


static var _tendril: ArrayMesh = null


## One root, built once: a tapered tube curling up out of the ground about a metre and a half,
## bark-dark with a living green underside. Pigment, lit like the world - it is wood, not light.
static func _tendril_mesh() -> ArrayMesh:
	if _tendril != null:
		return _tendril
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 12
	var sides: int = 7
	var rings: Array = []
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		# Rising and curling over to one side, the tip hooking down a little.
		var centre := Vector3(sin(t * 2.2) * 0.45 * t, t * 1.5 - t * t * 0.25, cos(t * 3.0) * 0.12 * t)
		var radius: float = lerpf(0.16, 0.015, pow(t, 0.8))
		var ring: Array[Vector3] = []
		for s: int in range(sides):
			var a: float = TAU * float(s) / float(sides)
			ring.append(centre + Vector3(cos(a), 0.0, sin(a)) * radius)
		rings.append(ring)
	for i: int in range(segments):
		for s: int in range(sides):
			var n: int = (s + 1) % sides
			var v0: float = float(i) / float(segments)
			var v1: float = float(i + 1) / float(segments)
			var quad: Array = [
				[rings[i][s], v0], [rings[i][n], v0], [rings[i + 1][n], v1],
				[rings[i][s], v0], [rings[i + 1][n], v1], [rings[i + 1][s], v1],
			]
			for corner: Array in quad:
				st.set_uv(Vector2(float(s) / float(sides), corner[1]))
				st.add_vertex(corner[0])
	st.generate_normals()
	_tendril = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.13, 0.08)
	material.roughness = 0.85
	# A faint living glow, so the roots still read on the pitch-black night.
	material.emission_enabled = true
	material.emission = Color(0.2, 0.42, 0.1)
	material.emission_energy_multiplier = 0.12
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tendril.surface_set_material(0, material)
	return _tendril
