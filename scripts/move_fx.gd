extends RefCounted
## The round-two skills that move a body (docs/SPELL_VFX_ROUND_TWO.md, step 4): what a charge
## leaves behind it, the harpoon's chain, the walk through the grave. They used to be a dust
## ring, a straight beam or Displace's blink, and Glorious Charge drew nothing at all.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const ChargeFx := preload("res://scripts/charge_fx.gd")

const GOLD := Color(1.0, 0.82, 0.42)
const KRAUL := Color(0.42, 0.85, 0.3)
const VIOLET := Color(0.6, 0.25, 1.0)
const BONE := Color(0.9, 0.85, 0.74)


## Frees `root` `seconds` after it enters the tree, on its own tween.
static func _expire(root: Node3D, seconds: float) -> void:
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(seconds)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)


static func _trail(tint: Color, slot: String, size: float, amount: int, lifetime: float,
		extents: Vector3) -> GPUParticles3D:
	var trail := GPUParticles3D.new()
	trail.amount = amount
	trail.lifetime = lifetime
	trail.local_coords = false
	trail.draw_pass_1 = SpellFx.premul_particle_mesh(size, slot)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 30.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0.0, 0.3, 0.0)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	trail.process_material = process
	return trail


# --- Glorious Charge -----------------------------------------------------------------

## Ridden by the caster for the length of the charge: a lance of gold light held out in front,
## wings of light streaming back off the shoulders, and a wake of gold glints left in the air.
static func glorious_charge(duration: float) -> Node3D:
	var root := Node3D.new()
	root.name = "GloriousCharge"
	for side: float in [-1.0, 1.0]:
		var wing := GPUParticles3D.new()
		wing.amount = 26
		wing.lifetime = 0.45
		wing.local_coords = false
		wing.draw_pass_1 = SpellFx.streak_mesh(0.12, 0.9, "mote")
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(0.05, 0.35, 0.05)
		# Back and out from the shoulder: local +Z is behind a body that faces -Z.
		process.direction = Vector3(side * 0.8, 0.5, 1.0).normalized()
		process.spread = 12.0
		process.initial_velocity_min = 2.0
		process.initial_velocity_max = 3.5
		process.damping_min = 3.0
		process.damping_max = 4.0
		process.particle_flag_align_y = true
		process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
		process.color_ramp = SpellFx._premul_ramp(GOLD)
		wing.process_material = process
		wing.position = Vector3(side * 0.35, 1.45, 0.1)
		root.add_child(wing)
	var wake: GPUParticles3D = _trail(GOLD, "mote", 0.24, 40, 0.8, Vector3(0.4, 0.8, 0.2))
	wake.position.y = 1.0
	root.add_child(wake)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 3.0
	light.omni_range = 4.5
	light.position = Vector3(0.0, 1.2, -0.8)
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		# The lance points where the caster faces, known only once it rides them.
		var lance: Node3D = SpellFx.beam(-root.global_basis.z, 2.6, GOLD, 0.7, duration + 0.15)
		lance.position = Vector3(0.0, 1.2, 0.0)
		root.add_child(lance)
		var tween: Tween = root.create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(func() -> void:
			for child: Node in root.get_children():
				if child is GPUParticles3D:
					(child as GPUParticles3D).emitting = false)
		tween.parallel().tween_property(light, "light_energy", 0.0, 0.3)
		tween.tween_interval(1.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- Overrun -------------------------------------------------------------------------

## Ridden by the caster for the length of the stampede: a heavy wake of dust, earth thrown up
## at every stride, and roots whipping up out of the ground behind - dropped into the world, so
## they stay where the charge went.
static func overrun(duration: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Overrun"
	var dust := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 1.8, 30, 1.2)
	dust.one_shot = false
	var process: ParticleProcessMaterial = dust.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.6, 0.1, 0.3)
	process.direction = Vector3(0.0, 0.4, 1.0)
	process.spread = 35.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.0, 0.2, 0.0)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(1.0, 1.4)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.5, 0.42, 0.28, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.5, 0.42, 0.28, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	dust.position.y = 0.3
	root.add_child(dust)
	var life: GPUParticles3D = _trail(Color(0.5, 0.95, 0.4), "mote", 0.26, 30, 0.9, Vector3(0.5, 0.7, 0.3))
	life.position.y = 0.9
	root.add_child(life)
	root.tree_entered.connect(func() -> void:
		dust.emitting = true
		var tween: Tween = root.create_tween()
		# A burst of roots and clods every few strides, left in the world behind.
		var steps: int = maxi(int(duration / 0.2), 1)
		for step: int in range(steps):
			tween.tween_interval(0.2)
			tween.tween_callback(func() -> void:
				var scene: Node = root.get_tree().current_scene if root.is_inside_tree() else null
				if scene == null:
					return
				var roots: Node3D = ChargeFx.hit("green_7", 0.9, Vector3.ZERO)
				scene.add_child(roots)
				roots.global_position = root.global_position
				var clods: Node3D = SpellVisuals.dirt_burst(0.8)
				scene.add_child(clods)
				clods.global_position = root.global_position)
		tween.tween_callback(func() -> void:
			dust.emitting = false
			life.emitting = false)
		tween.tween_interval(1.4)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- Kraul Harpooner -----------------------------------------------------------------

## A chain shot out `length` metres along `dir` with a barbed hook on the end, holding a moment
## and reeling back in - iron links, the hook glinting green.
static func harpoon_chain(length: float, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "HarpoonChain"
	var heading: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	length = maxf(length, 1.0)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.24, 0.23, 0.21)
	iron.metallic = 0.8
	iron.roughness = 0.4
	var link_mesh := TorusMesh.new()
	link_mesh.inner_radius = 0.04
	link_mesh.outer_radius = 0.065
	link_mesh.rings = 8
	link_mesh.ring_segments = 6
	link_mesh.material = iron
	var pitch: float = 0.11
	var count: int = clampi(int(length / pitch), 2, 300)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = link_mesh
	multimesh.instance_count = count
	# Built along local +Z. A torus lies flat round Y, so its ring already runs along the chain;
	# stretched along Z into a link, and every other one turned on edge about the chain.
	for index: int in range(count):
		var basis := Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.6))
		if index % 2 == 1:
			basis = Basis(Vector3.BACK, PI * 0.5) * basis
		multimesh.set_instance_transform(index, Transform3D(basis, Vector3(0.0, 0.0, float(index) * pitch)))
	var chain := MultiMeshInstance3D.new()
	chain.multimesh = multimesh
	root.add_child(chain)
	var hook := Node3D.new()
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.32
	cone.material = iron
	tip.mesh = cone
	tip.rotation.x = PI * 0.5
	hook.add_child(tip)
	var glint: Node3D = SpellFx.energy_orb_tinted(0.12, KRAUL)
	hook.add_child(glint)
	root.add_child(hook)
	var out_time: float = clampf(length / 60.0, 0.08, 0.25)
	root.tree_entered.connect(func() -> void:
		root.look_at(root.global_position + heading, Vector3.UP)
		# look_at points -Z along the heading; the chain is built along +Z.
		root.rotate_object_local(Vector3.UP, PI)
		multimesh.visible_instance_count = 0
		var tween: Tween = root.create_tween()
		tween.tween_method(func(t: float) -> void:
			var shown: int = int(float(count) * t)
			multimesh.visible_instance_count = shown
			hook.position = Vector3(0.0, 0.0, float(shown) * pitch), 0.0, 1.0, out_time)
		tween.tween_callback(func() -> void:
			root.add_child(SpellFx.impact(KRAUL, 0.6, "spark"))
			(root.get_child(root.get_child_count() - 1) as Node3D).position = hook.position)
		tween.tween_interval(0.12)
		tween.tween_method(func(t: float) -> void:
			var shown: int = int(float(count) * (1.0 - t))
			multimesh.visible_instance_count = shown
			hook.position = Vector3(0.0, 0.0, float(shown) * pitch), 0.0, 1.0, 0.25)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- Gravewalk -----------------------------------------------------------------------

## Where the caster leaves: they sink into black smoke that pours down into the ground.
static func grave_sink() -> Node3D:
	var root := Node3D.new()
	root.name = "GraveSink"
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(1.4, 14, 1.2)
	(smoke.process_material as ParticleProcessMaterial).direction = Vector3.DOWN
	(smoke.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, -2.0, 0.0)
	smoke.position.y = 1.4
	root.add_child(smoke)
	var pull := GPUParticles3D.new()
	pull.amount = 26
	pull.lifetime = 0.5
	pull.one_shot = true
	pull.explosiveness = 0.7
	pull.local_coords = true
	pull.draw_pass_1 = SpellFx.streak_mesh(0.1, 0.8, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.4, 0.9, 0.4)
	process.direction = Vector3.DOWN
	process.spread = 5.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 7.0
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(VIOLET)
	pull.process_material = process
	pull.position.y = 1.2
	pull.tree_entered.connect(func() -> void: pull.emitting = true, CONNECT_ONE_SHOT)
	root.add_child(pull)
	var blight: MeshInstance3D = SpellFx.ground_decal("decal_blight", Color(0.1, 0.04, 0.14, 0.85), 1.3, 1.2)
	blight.position.y = 0.06
	root.add_child(blight)
	_expire(root, 2.5)
	return root


## Where the caster arrives: the corpse bursts - bone flung out, black smoke and a violet flash
## - across `radius`, the burst's real reach, and they stand up out of it.
static func grave_burst(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "GraveBurst"
	radius = maxf(radius, 1.5)
	root.add_child(SpellVisuals.splinters(BONE, radius * 0.6, 40))
	var smoke: GPUParticles3D = SpellVisuals.void_smoke(radius * 0.8, 18, 1.5)
	smoke.position.y = 0.6
	root.add_child(smoke)
	root.add_child(SpellVisuals.dust_ring(radius * 0.8, 1.0, Color(0.3, 0.22, 0.3)))
	root.add_child(SpellFx.shockwave(VIOLET, radius, 0.35))
	var blight: MeshInstance3D = SpellFx.ground_decal("decal_blight", Color(0.1, 0.04, 0.14, 0.9), radius, 2.5)
	blight.position.y = 0.06
	root.add_child(blight)
	var flash := OmniLight3D.new()
	flash.light_color = VIOLET
	flash.light_energy = 5.0
	flash.omni_range = radius * 2.5
	flash.position.y = 1.0
	root.add_child(flash)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.35)
		tween.tween_interval(3.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root
