extends RefCounted
## The round-two self-buffs and the casts that had no look of their own (docs/
## SPELL_VFX_ROUND_TWO.md, step 5): Unholy Strength, Demonic Pact, Blood Frenzy, Grapeshot,
## Fork, Undying and Worship. They shared two casts between them - a violet circle under a
## violet pillar, or a red circle - and a buff left nothing on the caster once the cast was
## over; that part is StatusFx's now (status_overlay.gdshader's unholy, frenzy and pact).
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const SummonFx := preload("res://scripts/summon_fx.gd")

const CRIMSON := Color(0.85, 0.08, 0.12)
const VIOLET := Color(0.6, 0.22, 1.0)
const RAGE := Color(1.0, 0.36, 0.12)
const FIRE := Color(1.0, 0.55, 0.2)
const GOLD := Color(1.0, 0.82, 0.42)


static func _expire(root: Node3D, seconds: float) -> void:
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(seconds)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)


static func _burst(particles: GPUParticles3D, at: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	particles.position = at
	particles.tree_entered.connect(func() -> void: particles.emitting = true, CONNECT_ONE_SHOT)
	return particles


static func _flash(root: Node3D, tint: Color, energy: float, reach: float, fall: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.position.y = 1.2
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		root.create_tween().tween_property(light, "light_energy", 0.0, fall), CONNECT_ONE_SHOT)


## Particles pulled in from a shell of `radius` to the node, `tint`, drawn as `slot`.
static func _inflow(tint: Color, slot: String, radius: float, amount: int, size: float) -> GPUParticles3D:
	var pull := GPUParticles3D.new()
	pull.amount = amount
	pull.lifetime = 0.55
	pull.one_shot = true
	pull.explosiveness = 0.75
	pull.local_coords = true
	pull.draw_pass_1 = SpellFx.premul_particle_mesh(size, slot)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process.emission_sphere_radius = radius
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.1
	process.radial_accel_min = -radius * 9.0
	process.radial_accel_max = -radius * 6.0
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.3), Vector2(0.6, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	pull.process_material = process
	return pull


# --- black ------------------------------------------------------------------------------

## Unholy Strength: blood drawn up out of the caster's own body into the weapon arm - the
## life the attacks will be paid with - and a dark throb.
static func unholy_strength() -> Node3D:
	var root := Node3D.new()
	root.name = "UnholyStrength"
	root.add_child(_burst(_inflow(CRIMSON, "spark", 1.0, 40, 0.18), Vector3(0.35, 1.2, -0.2)))
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(0.9, 10, 1.1)
	smoke.position.y = 0.9
	root.add_child(smoke)
	_flash(root, CRIMSON, 3.5, 3.5, 0.5)
	_expire(root, 1.6)
	return root


## Demonic Pact: violet fire breaking out of the ground in a ring round the caster, the smoke
## of it rising - the bargain struck.
static func demonic_pact() -> Node3D:
	var root := Node3D.new()
	root.name = "DemonicPact"
	var fire := ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, 1.1, 34, 0.9)
	var process: ParticleProcessMaterial = fire.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.6
	process.emission_ring_inner_radius = 1.4
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.0
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(0.3, 1.0), Vector2(1.0, 0.3)])
	# The flipbook blends straight alpha (ExplosionFx): a plain, unpremultiplied ramp.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.6, 1.0, 1.0))
	gradient.add_point(0.4, Color(0.55, 0.15, 0.95, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.12, 0.02, 0.2, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	root.add_child(_burst(fire, Vector3(0.0, 0.1, 0.0)))
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(1.8, 16, 1.8)
	smoke.position.y = 1.0
	root.add_child(smoke)
	_flash(root, VIOLET, 4.5, 5.0, 0.6)
	_expire(root, 2.5)
	return root


## Undying catching the fall: dark wings flung open behind the caster as they rise, the dread
## thrown out across `radius`.
static func undying(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Undying"
	for side: float in [-1.0, 1.0]:
		var wing := GPUParticles3D.new()
		wing.amount = 40
		wing.lifetime = 0.8
		wing.one_shot = true
		wing.explosiveness = 0.85
		wing.local_coords = true
		wing.draw_pass_1 = SpellFx.streak_mesh(0.18, 1.3, "mote")
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(0.1, 0.3, 0.1)
		# Up and out to the side, fanned: the spread of the pinions.
		process.direction = Vector3(side, 1.1, 0.35).normalized()
		process.spread = 28.0
		process.initial_velocity_min = 3.5
		process.initial_velocity_max = 6.0
		process.damping_min = 5.0
		process.damping_max = 7.0
		process.particle_flag_align_y = true
		process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.6), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
		process.color_ramp = SpellFx._premul_ramp(VIOLET)
		wing.process_material = process
		root.add_child(_burst(wing, Vector3(side * 0.25, 1.5, 0.15)))
	root.add_child(SpellFx.shockwave(VIOLET.darkened(0.3), maxf(radius, 2.0), 0.4))
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(1.5, 16, 1.4)
	smoke.position.y = 0.8
	root.add_child(smoke)
	_flash(root, VIOLET, 6.0, 6.0, 0.5)
	_expire(root, 2.2)
	return root


# --- red --------------------------------------------------------------------------------

## Blood Frenzy: the heart going - two quick pulses of red force off the caster and embers
## thrown up off the body.
static func blood_frenzy() -> Node3D:
	var root := Node3D.new()
	root.name = "BloodFrenzy"
	var embers: GPUParticles3D = SpellFx.sparks(RAGE, 0.8, 36, 4.0, "spark")
	(embers.process_material as ParticleProcessMaterial).direction = Vector3.UP
	(embers.process_material as ParticleProcessMaterial).spread = 30.0
	(embers.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, 1.0, 0.0)
	root.add_child(_burst(embers, Vector3(0.0, 0.8, 0.0)))
	_flash(root, RAGE, 4.0, 3.5, 0.3)
	root.tree_entered.connect(func() -> void:
		# A heartbeat: two beats, the second a breath after the first.
		root.add_child(SpellFx.shockwave(RAGE, 1.8, 0.25, PI, -1.0, false))
		var tween: Tween = root.create_tween()
		tween.tween_interval(0.22)
		tween.tween_callback(func() -> void:
			var second: Node3D = SpellFx.shockwave(RAGE, 2.4, 0.3, PI, -1.0, false)
			second.position.y = 1.0
			root.add_child(second))
		tween.tween_interval(1.4)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Grapeshot, one target's share: a spray of hot iron pellets flying `distance` along `dir`,
## sparks where they land. Not the Orb of Fire's ball of fire - grapeshot is many and small.
static func grape_volley(distance: float, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "GrapeVolley"
	var heading: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	distance = maxf(distance, 1.0)
	var travel: float = clampf(distance / 45.0, 0.08, 0.35)
	var pellets := GPUParticles3D.new()
	pellets.amount = 9
	pellets.lifetime = travel
	pellets.one_shot = true
	pellets.explosiveness = 0.9
	pellets.local_coords = false
	pellets.draw_pass_1 = SpellFx.streak_mesh(0.14, 0.8, "spark")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.1
	process.direction = heading
	process.spread = 3.5
	process.initial_velocity_min = distance / travel * 0.95
	process.initial_velocity_max = distance / travel * 1.05
	process.gravity = Vector3.ZERO
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(0.9, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(FIRE)
	pellets.process_material = process
	root.add_child(_burst(pellets))
	var land := Node3D.new()
	land.position = heading * distance
	root.add_child(land)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(travel)
		tween.tween_callback(func() -> void:
			land.add_child(_burst(SpellFx.sparks(FIRE, 0.4, 18, 3.5, "spark"))))
		tween.tween_interval(1.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Grapeshot's cast: the muzzle blast - a short cone of fire and smoke off the casting hand.
static func grapeshot_blast() -> Node3D:
	var root := Node3D.new()
	root.name = "GrapeshotBlast"
	var blast := ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, 0.7, 14, 0.35)
	var process: ParticleProcessMaterial = blast.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.direction = Vector3.FORWARD
	process.spread = 25.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 6.0
	process.damping_min = 8.0
	process.damping_max = 12.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	gradient.add_point(0.35, Color(1.0, 0.45, 0.12, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.25, 0.2, 0.18, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	root.add_child(_burst(blast, Vector3(0.3, 1.4, -0.5)))
	_flash(root, FIRE, 4.0, 3.0, 0.15)
	_expire(root, 1.0)
	return root


## Fork: the spell about to be cast splitting in two - two tongues of flame forking up and out
## of the casting hand.
static func fork() -> Node3D:
	var root := Node3D.new()
	root.name = "Fork"
	for side: float in [-1.0, 1.0]:
		var tongue := GPUParticles3D.new()
		tongue.amount = 34
		tongue.lifetime = 0.5
		tongue.one_shot = true
		tongue.explosiveness = 0.6
		tongue.local_coords = true
		tongue.draw_pass_1 = SpellFx.streak_mesh(0.18, 1.0, "spark")
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.05
		process.direction = Vector3(side * 0.6, 1.0, -0.4).normalized()
		process.spread = 6.0
		process.initial_velocity_min = 3.0
		process.initial_velocity_max = 4.5
		process.damping_min = 4.0
		process.damping_max = 5.0
		process.particle_flag_align_y = true
		process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
		process.color_ramp = SpellFx._premul_ramp(FIRE)
		tongue.process_material = process
		root.add_child(_burst(tongue, Vector3(0.3, 1.3, -0.3)))
	_flash(root, FIRE, 3.0, 2.5, 0.3)
	_expire(root, 1.2)
	return root


# --- white ------------------------------------------------------------------------------

## Worship: a curtain of rising light along the edge of the zone for as long as it holds -
## where the protection ends, plain to see. It had Wrath of God's pillar standing in the middle.
static func worship(radius: float, duration: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Worship"
	var curtain := GPUParticles3D.new()
	curtain.amount = clampi(int(radius * 22.0), 50, 220)
	curtain.lifetime = 1.4
	curtain.local_coords = true
	curtain.draw_pass_1 = SpellFx.streak_mesh(0.2, 1.5, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.97
	process.emission_ring_height = 0.05
	process.direction = Vector3.UP
	process.spread = 2.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.2
	process.gravity = Vector3.ZERO
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(GOLD)
	curtain.process_material = process
	curtain.position.y = 0.1
	root.add_child(curtain)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 1.4
	light.omni_range = radius * 1.6
	light.position.y = 2.0
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		curtain.emitting = true
		var tween: Tween = root.create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(func() -> void: curtain.emitting = false)
		tween.tween_property(light, "light_energy", 0.0, 0.6)
		tween.tween_interval(1.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Rally the Fallen, and an ally it lifts: streaks of gold light rising off the ground round
## them, lifting. A pillar of light stood here once - Wrath of God's look.
static func rally(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RallyRise"
	root.add_child(SummonFx._streaks(GOLD, clampi(int(radius * 14.0), 24, 70), radius, 7.0))
	root.add_child(SpellVisuals.rising_motes(Player.FX_WHITE, radius, 50, 1.6))
	_flash(root, GOLD, 4.0, radius * 2.5, 1.0)
	_expire(root, 3.0)
	return root
