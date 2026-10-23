extends RefCounted
## What an enemy looks like while a round-two skill holds it (docs/SPELL_VFX_ROUND_TWO.md,
## step 3), and the moment it goes in and comes out: sealed in Banishing Light's prism, turned
## into a boar (a stand-in for now), encased in ice, carrying a lit powder keg, marked from above.
##
## EnemyBase builds the held look from its replicated `round_two_state` bits (`held`), so every
## screen draws the same; the moments in and out travel as NetFx spells
## ("enemy_state/<name>", see `moment`). These used to be an untextured box, a plain cylinder,
## a glowing cylinder and two bare lights.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const PRISM_SHADER: Shader = preload("res://assets/shaders/banish_prism.gdshader")
const ICE_SHADER: Shader = preload("res://assets/shaders/frost_globe.gdshader")
const GOLD := Color(1.0, 0.9, 0.6)
const ICE := Color(0.72, 0.93, 1.0)
const SWINE_SMOKE := Color(0.55, 0.75, 1.0)
const FUSE := Color(1.0, 0.58, 0.22)


## The look for one held state, by name: "banished", "swine", "encased", "keg", "sanctified".
static func held(state: String) -> Node3D:
	match state:
		"banished": return banished()
		"swine": return swine()
		"encased": return encased()
		"keg": return keg()
		"sanctified": return sanctified()
	return null


## A state starting or ending, where it happens: "<state>_in" / "<state>_out".
static func moment(id: String) -> Node3D:
	match id:
		"swine_in", "swine_out": return _swine_puff()
		"encased_out": return _ice_shatter()
		"banished_out": return _prism_break()
	return Node3D.new()


static func _expire(root: Node3D, seconds: float) -> void:
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_interval(seconds)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)


static func _burst(particles: GPUParticles3D, at: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	particles.position = at
	particles.tree_entered.connect(func() -> void: particles.emitting = true, CONNECT_ONE_SHOT)
	return particles


# --- Banishing Light --------------------------------------------------------------

## A hexagonal prism of light closed over the enemy, turning slowly, motes climbing inside it
## and a soft white glow where the body was.
static func banished() -> Node3D:
	var root := Node3D.new()
	root.name = "BanishPrism"
	var prism := MeshInstance3D.new()
	prism.mesh = _prism_mesh(0.95, 3.0, 6)
	prism.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = PRISM_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", GOLD)
	prism.material_override = material
	root.add_child(prism)
	var core: Node3D = SpellFx.energy_orb_tinted(0.45, Color(1.0, 0.97, 0.88))
	core.position.y = 1.0
	core.scale = Vector3(1.0, 2.2, 1.0)
	root.add_child(core)
	var motes := GPUParticles3D.new()
	motes.amount = 24
	motes.lifetime = 1.6
	motes.local_coords = true
	motes.draw_pass_1 = SpellFx.premul_particle_mesh(0.2, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.75
	process.emission_ring_inner_radius = 0.2
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 5.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.5
	process.gravity = Vector3.ZERO
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(GOLD)
	motes.process_material = process
	root.add_child(motes)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 1.8
	light.omni_range = 4.0
	light.position.y = 1.4
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		# Rises out of the ground round the enemy, then turns for as long as it holds.
		prism.scale = Vector3(1.0, 0.05, 1.0)
		var rise: Tween = root.create_tween()
		rise.tween_property(prism, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var spin: Tween = root.create_tween().set_loops()
		spin.tween_property(prism, "rotation:y", TAU, 9.0).from(0.0), CONNECT_ONE_SHOT)
	return root


## An open prism round the Y axis, `sides` faces, each face's UV.x running 0..1 across it so
## the shader can find the edges.
static func _prism_mesh(radius: float, height: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: int in range(sides):
		var a0: float = TAU * float(side) / float(sides)
		var a1: float = TAU * float(side + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var up := Vector3(0.0, height, 0.0)
		for corner: Array in [[p0, Vector2(0, 0)], [p1, Vector2(1, 0)], [p1 + up, Vector2(1, 1)],
				[p0, Vector2(0, 0)], [p1 + up, Vector2(1, 1)], [p0 + up, Vector2(0, 1)]]:
			st.set_uv(corner[1])
			st.set_normal(((p0 + p1) * 0.5).normalized())
			st.add_vertex(corner[0])
	return st.commit()


## The prism breaking when the seal ends: gold shards thrown out from where it stood.
static func _prism_break() -> Node3D:
	var root := Node3D.new()
	root.name = "PrismBreak"
	var shards: GPUParticles3D = SpellFx.sparks(GOLD, 1.2, 40, 5.0, "shard")
	(shards.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(shards.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.8, 1.2, 0.8)
	root.add_child(_burst(shards, Vector3(0.0, 1.3, 0.0)))
	root.add_child(SpellVisuals.dust_ring(1.2, 0.8, Color(1.0, 0.95, 0.8)))
	var flash := OmniLight3D.new()
	flash.light_color = GOLD
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	flash.position.y = 1.2
	root.add_child(flash)
	root.tree_entered.connect(func() -> void:
		root.create_tween().tween_property(flash, "light_energy", 0.0, 0.3), CONNECT_ONE_SHOT)
	_expire(root, 1.6)
	return root


# --- Curse of the Swine -------------------------------------------------------------

## What the enemy has become: GameSettings.spell_blue_swine_scene once a boar exists there,
## until then the green beast stand-in it always had. The boar itself is left out for now
## (the user, 2026-10-23); the Meshy model in assets/generated/boar/ is kept for later.
static func swine() -> Node3D:
	var path: String = GameSettings.spell_blue_swine_scene
	var scene: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		scene = EnemyBase.BeastDatabase.visual_scene("Green")
	if scene == null:
		return Node3D.new()
	var beast: Node3D = scene.instantiate()
	beast.scale = Vector3.ONE * GameSettings.spell_blue_swine_scale
	return beast


## The turn either way: a puff of pale blue smoke that hides the swap, and glints in it.
static func _swine_puff() -> Node3D:
	var root := Node3D.new()
	root.name = "SwinePuff"
	var smoke := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 1.6, 14, 0.9)
	smoke.explosiveness = 0.95
	var process: ParticleProcessMaterial = smoke.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.8
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(1.0, 1.2)])
	# The flipbook blends straight alpha (ExplosionFx), so its ramp is not premultiplied.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(SWINE_SMOKE.r, SWINE_SMOKE.g, SWINE_SMOKE.b, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(SWINE_SMOKE.r, SWINE_SMOKE.g, SWINE_SMOKE.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	root.add_child(_burst(smoke, Vector3(0.0, 0.7, 0.0)))
	root.add_child(_burst(SpellFx.sparks(SWINE_SMOKE, 0.7, 20, 2.5, "mote"), Vector3(0.0, 0.8, 0.0)))
	_expire(root, 1.6)
	return root


# --- Ice Cage ---------------------------------------------------------------------------

## Encased: a cluster of ice crystals grown up round the enemy, frost spread on the ground and
## a cold mist creeping off it. The crystals use the Frost Globe's ice (frost_globe.gdshader),
## thicker - something is frozen inside, and it should be seen only dimly.
static func encased() -> Node3D:
	var root := Node3D.new()
	root.name = "IceCage"
	var material := ShaderMaterial.new()
	material.shader = ICE_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", ICE)
	material.set_shader_parameter("frost_noise", _frost_noise())
	material.set_shader_parameter("crystal_scale", 0.3)
	material.set_shader_parameter("body", 0.32)
	material.set_shader_parameter("energy", 1.3)
	material.set_shader_parameter("fade", 0.0)
	var crystals := Node3D.new()
	root.add_child(crystals)
	# A big middle block the body stands in, and spars leaning out round it.
	var layout: Array = [
		[Vector3.ZERO, 0.62, 2.3, 0.0, 0.0],
		[Vector3(0.55, 0.0, 0.2), 0.28, 1.6, 0.35, 0.4],
		[Vector3(-0.5, 0.0, 0.3), 0.26, 1.4, -0.3, 2.0],
		[Vector3(0.1, 0.0, -0.6), 0.3, 1.8, 0.28, 3.5],
		[Vector3(-0.35, 0.0, -0.45), 0.22, 1.1, -0.4, 5.0],
		[Vector3(0.45, 0.0, -0.35), 0.2, 0.9, 0.5, 1.2],
	]
	for spec: Array in layout:
		var crystal := MeshInstance3D.new()
		crystal.mesh = _crystal_mesh(float(spec[1]), float(spec[2]))
		crystal.material_override = material
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crystal.position = spec[0]
		crystal.rotation = Vector3(float(spec[3]) * 0.6, float(spec[4]), float(spec[3]))
		crystals.add_child(crystal)
	var rime: MeshInstance3D = SpellFx.ground_decal("decal_frost", Color(0.88, 0.95, 1.0, 0.9), 1.6, 600.0)
	rime.position.y = 0.06
	root.add_child(rime)
	var mist: GPUParticles3D = ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 1.2, 10, 2.2)
	mist.one_shot = false
	var drift: ParticleProcessMaterial = mist.process_material
	drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	drift.emission_ring_axis = Vector3.UP
	drift.emission_ring_radius = 0.9
	drift.emission_ring_inner_radius = 0.6
	drift.emission_ring_height = 0.1
	drift.direction = Vector3(1.0, 0.0, 0.0)
	drift.spread = 180.0
	drift.flatness = 0.9
	drift.initial_velocity_min = 0.2
	drift.initial_velocity_max = 0.5
	drift.gravity = Vector3(0.0, -0.05, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.88, 0.95, 1.0, 0.0))
	gradient.add_point(0.3, Color(0.88, 0.95, 1.0, 0.35))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.88, 0.95, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	drift.color_ramp = ramp
	mist.position.y = 0.25
	root.add_child(mist)
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.82, 1.0)
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position.y = 1.2
	root.add_child(light)
	root.tree_entered.connect(func() -> void:
		mist.emitting = true
		crystals.scale = Vector3(1.0, 0.1, 1.0)
		root.create_tween().tween_property(crystals, "scale:y", 1.0, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT), CONNECT_ONE_SHOT)
	return root


## One ice crystal: a six-sided prism `radius` across, `height` tall to the start of a point.
static func _crystal_mesh(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 6
	var tip := Vector3(0.0, height + radius * 1.4, 0.0)
	for side: int in range(sides):
		var a0: float = TAU * float(side) / float(sides)
		var a1: float = TAU * float(side + 1) / float(sides)
		var b0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var t0 := b0 + Vector3(0.0, height, 0.0)
		var t1 := b1 + Vector3(0.0, height, 0.0)
		for v: Vector3 in [b0, b1, t1, b0, t1, t0, t0, t1, tip]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static var _noise_texture: NoiseTexture2D = null


## The frost veins' noise, as FrostGlobe makes it - made once and shared.
static func _frost_noise() -> NoiseTexture2D:
	if _noise_texture != null:
		return _noise_texture
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 20931
	noise.frequency = 0.022
	noise.fractal_octaves = 3
	_noise_texture = NoiseTexture2D.new()
	_noise_texture.width = 256
	_noise_texture.height = 256
	_noise_texture.seamless = true
	_noise_texture.noise = noise
	return _noise_texture


## The ice giving way when the cage ends: shards and a burst of cold mist.
static func _ice_shatter() -> Node3D:
	var root := Node3D.new()
	root.name = "IceShatter"
	var shards: GPUParticles3D = SpellFx.sparks(ICE, 1.2, 46, 5.0, "shard")
	var process := shards.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.6, 1.0, 0.6)
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.angular_velocity_min = -400.0
	process.angular_velocity_max = 400.0
	root.add_child(_burst(shards, Vector3(0.0, 1.1, 0.0)))
	root.add_child(SpellVisuals.dust_ring(1.3, 1.0, Color(0.88, 0.95, 1.0)))
	_expire(root, 1.6)
	return root


# --- Powder Keg ----------------------------------------------------------------------

## A keg strapped to the enemy, its fuse burning down: sparks spitting off the fuse and its
## light flickering faster as the fuse runs out (GameSettings.spell_red_powder_keg_fuse).
static func keg() -> Node3D:
	var root := Node3D.new()
	root.name = "PowderKeg"
	var holder := Node3D.new()
	holder.position = Vector3(0.0, 1.25, -0.32)
	holder.rotation = Vector3(0.25, 0.0, 0.15)
	root.add_child(holder)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _barrel_mesh(0.2, 0.24, 0.52)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.11)
	wood.roughness = 0.85
	barrel.material_override = wood
	holder.add_child(barrel)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.14)
	iron.metallic = 0.7
	iron.roughness = 0.45
	for y: float in [-0.17, 0.17]:
		var hoop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		# The barrel's own radius where the hoop sits, so it hugs the staves.
		torus.inner_radius = 0.222
		torus.outer_radius = 0.247
		hoop.mesh = torus
		hoop.material_override = iron
		hoop.position.y = y
		holder.add_child(hoop)
	var fuse := MeshInstance3D.new()
	var cord := CylinderMesh.new()
	cord.top_radius = 0.012
	cord.bottom_radius = 0.016
	cord.height = 0.22
	fuse.mesh = cord
	var cord_mat := StandardMaterial3D.new()
	cord_mat.albedo_color = Color(0.22, 0.2, 0.17)
	fuse.material_override = cord_mat
	fuse.position = Vector3(0.05, 0.36, 0.0)
	fuse.rotation.z = -0.4
	holder.add_child(fuse)
	var tip := Node3D.new()
	tip.position = Vector3(0.1, 0.46, 0.0)
	holder.add_child(tip)
	var sparks: GPUParticles3D = SpellFx.sparks(FUSE, 0.05, 16, 2.4, "spark")
	sparks.one_shot = false
	sparks.explosiveness = 0.0
	sparks.lifetime = 0.35
	tip.add_child(sparks)
	var glow := OmniLight3D.new()
	glow.light_color = FUSE
	glow.light_energy = 1.0
	glow.omni_range = 2.2
	tip.add_child(glow)
	var fuse_time: float = maxf(GameSettings.spell_red_powder_keg_fuse, 0.5)
	root.tree_entered.connect(func() -> void:
		sparks.emitting = true
		# The flicker quickens as the fuse burns: a pulse whose period shrinks to a tenth.
		var tween: Tween = root.create_tween()
		var elapsed: float = 0.0
		while elapsed < fuse_time:
			var period: float = lerpf(0.35, 0.06, elapsed / fuse_time)
			tween.tween_property(glow, "light_energy", 3.5, period * 0.4)
			tween.tween_property(glow, "light_energy", 0.8, period * 0.6)
			elapsed += period
		tween.tween_property(glow, "light_energy", 5.0, 0.1), CONNECT_ONE_SHOT)
	return root


## A keg's body: a lathed barrel, `end_radius` at the ends bulging to `belly_radius`.
static func _barrel_mesh(end_radius: float, belly_radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 8
	var sides: int = 14
	var profile: Array[Vector2] = []
	for i: int in range(rings + 1):
		var t: float = float(i) / float(rings)
		profile.append(Vector2(lerpf(end_radius, belly_radius, sin(t * PI)), (t - 0.5) * height))
	for i: int in range(rings):
		for s: int in range(sides):
			var a0: float = TAU * float(s) / float(sides)
			var a1: float = TAU * float(s + 1) / float(sides)
			var p: Array = [
				Vector3(cos(a0) * profile[i].x, profile[i].y, sin(a0) * profile[i].x),
				Vector3(cos(a1) * profile[i].x, profile[i].y, sin(a1) * profile[i].x),
				Vector3(cos(a1) * profile[i + 1].x, profile[i + 1].y, sin(a1) * profile[i + 1].x),
				Vector3(cos(a0) * profile[i + 1].x, profile[i + 1].y, sin(a0) * profile[i + 1].x),
			]
			# Clockwise seen from outside: Godot's front face.
			for index: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(p[index])
	# The lids.
	for end: int in [0, rings]:
		var y: float = profile[end].y
		var r: float = profile[end].x
		for s: int in range(sides):
			var a0: float = TAU * float(s) / float(sides)
			var a1: float = TAU * float(s + 1) / float(sides)
			var verts: Array = [Vector3(0.0, y, 0.0), Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r)]
			for index: int in ([0, 2, 1] if end == 0 else [0, 1, 2]):
				st.add_vertex(verts[index])
	st.generate_normals()
	return st.commit()


# --- Mark of Sanctity --------------------------------------------------------------------

## Marked: a ring of glints turning slowly over the head for as long as the mark lasts, and a
## faint light - every ally can see whom to hit for a shield.
static func sanctified() -> Node3D:
	var root := Node3D.new()
	root.name = "SanctityHalo"
	var ivory := Color(1.0, 0.96, 0.84)
	var halo := GPUParticles3D.new()
	halo.amount = 14
	halo.lifetime = 1.6
	halo.local_coords = true
	halo.draw_pass_1 = SpellFx.premul_particle_mesh(0.26, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.5
	process.emission_ring_inner_radius = 0.47
	process.emission_ring_height = 0.02
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.gravity = Vector3.ZERO
	process.tangential_accel_min = 1.2
	process.tangential_accel_max = 1.2
	process.radial_accel_min = -0.3
	process.radial_accel_max = -0.3
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(0.8, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(ivory)
	halo.process_material = process
	halo.position.y = 2.15
	root.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = ivory
	light.light_energy = 1.2
	light.omni_range = 2.4
	light.position.y = 2.2
	root.add_child(light)
	return root
