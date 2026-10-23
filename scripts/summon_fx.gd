extends RefCounted
## A summon arriving (docs/SPELL_VFX_ROUND_TWO.md, step 4, "materialise"): every creature a
## round-two skill calls takes shape the same way - a band of light climbing its body
## (summon_overlay.gdshader) while it rises out of the ground or swells into being - and each
## kind brings its own ground: a golem breaks out of split stone, a treant out of torn earth and
## bark, the raised dead out of black smoke, a called beast out of green motes drawn together,
## a mirror image out of shards of light.
##
## Played by TemporaryAlly on every peer when it is built, so nothing travels for it. Zombify's
## ghoul keeps the look it always had (SpellVisuals.raise_dead).
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const OVERLAY_SHADER: Shader = preload("res://assets/shaders/summon_overlay.gdshader")

## Kind -> how it arrives: its band's tint, roughly how tall it stands, whether it rises out of
## the ground (or swells into being), and how long that takes.
const ARRIVALS: Dictionary = {
	"golem": {"tint": Color(0.55, 0.85, 0.4), "height": 2.8, "rise": true, "time": 0.9},
	"treant": {"tint": Color(0.5, 0.95, 0.35), "height": 2.6, "rise": true, "time": 0.9},
	"raised": {"tint": Color(0.6, 0.25, 1.0), "height": 2.2, "rise": true, "time": 0.8},
	"beast": {"tint": Color(0.5, 0.95, 0.4), "height": 1.6, "rise": false, "time": 0.6},
	"mirror": {"tint": Color(0.5, 0.8, 1.0), "height": 1.8, "rise": false, "time": 0.35},
}


static func arrives(kind: String) -> bool:
	return ARRIVALS.has(kind)


## Plays the arrival of `ally`, whose model is `visual`. The overlay goes on the model's meshes
## and comes off again, leaving whatever overlay they had (the undead cracks, a decoy's tint).
static func arrive(ally: Node3D, visual: Node3D, kind: String) -> void:
	var spec: Dictionary = ARRIVALS.get(kind, {})
	if spec.is_empty() or visual == null or not ally.is_inside_tree():
		return
	var tint: Color = spec["tint"]
	var height: float = float(spec["height"]) * maxf(float(ally.get("visual_scale")), 0.5)
	var time: float = float(spec["time"])
	var material := ShaderMaterial.new()
	material.shader = OVERLAY_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("base_y", ally.global_position.y)
	material.set_shader_parameter("height", height)
	material.set_shader_parameter("progress", 0.0)
	var meshes: Array[MeshInstance3D] = []
	var previous: Array[Material] = []
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		meshes.append(mesh)
		previous.append(mesh.material_overlay)
		mesh.material_overlay = material

	var resting: Vector3 = visual.position
	var scale: Vector3 = visual.scale
	var tween: Tween = visual.create_tween()
	if bool(spec["rise"]):
		visual.position = resting - Vector3(0.0, height * 0.85, 0.0)
		tween.tween_property(visual, "position", resting, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		visual.scale = scale * 0.08
		tween.tween_property(visual, "scale", scale, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value),
		0.0, 1.0, time * 1.15)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("fade", value), 0.0, 1.0, 0.45)
	tween.tween_callback(func() -> void:
		for index: int in range(meshes.size()):
			if is_instance_valid(meshes[index]) and meshes[index].material_overlay == material:
				meshes[index].material_overlay = previous[index])

	var ground: Node3D = _ground(kind, tint)
	var scene: Node = ally.get_tree().current_scene
	if ground != null and scene != null:
		scene.add_child(ground)
		ground.global_position = ally.global_position


## What the ground does as `kind` arrives, freeing itself.
static func _ground(kind: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SummonGround"
	match kind:
		"golem":
			# Split stone, rock and moss thrown up, dust rolling out.
			var stone := Color(0.62, 0.62, 0.58)
			root.add_child(SpellVisuals.ground_cracks(2.2, tint, 1.5))
			root.add_child(SpellVisuals.dirt_burst(1.8))
			root.add_child(SpellVisuals.dust_ring(2.0, 1.4, Color(0.6, 0.58, 0.52)))
			root.add_child(SpellVisuals.splinters(stone, 1.2, 30))
		"treant":
			# Torn earth and bark; whirling leaves are Giant Growth's.
			root.add_child(SpellVisuals.dirt_burst(1.6))
			root.add_child(SpellVisuals.splinters(Color(0.4, 0.28, 0.16), 1.2, 30))
			root.add_child(SpellVisuals.dust_ring(1.6, 1.2))
		"raised":
			# Black ribbons pouring up out of the ground and the corpse standing up in them.
			var smoke: GPUParticles3D = SpellVisuals.void_smoke(1.6, 16, 1.8)
			smoke.tree_entered.connect(func() -> void: smoke.emitting = true, CONNECT_ONE_SHOT)
			root.add_child(smoke)
			root.add_child(_streaks(tint, 30, 1.0, 6.0))
			var blight: MeshInstance3D = SpellFx.ground_decal("decal_blight", Color(0.12, 0.05, 0.16, 0.85), 1.8, 2.0)
			blight.position.y = 0.06
			root.add_child(blight)
		"beast":
			# The trophy's spirit drawn back together: green motes pulled in from all round.
			root.add_child(SpellFx.cast_glow(tint, 3.0))
			var gather := GPUParticles3D.new()
			gather.amount = 50
			gather.lifetime = 0.6
			gather.one_shot = true
			gather.explosiveness = 0.8
			gather.local_coords = true
			gather.draw_pass_1 = SpellFx.premul_particle_mesh(0.3, "mote")
			var process := ParticleProcessMaterial.new()
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			process.emission_sphere_radius = 3.2
			process.direction = Vector3.UP
			process.spread = 0.0
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.0
			process.radial_accel_min = -22.0
			process.radial_accel_max = -16.0
			process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.3), Vector2(0.6, 1.0), Vector2(1.0, 0.0)])
			process.color_ramp = SpellFx._premul_ramp(tint)
			gather.process_material = process
			gather.position.y = 0.9
			gather.tree_entered.connect(func() -> void: gather.emitting = true, CONNECT_ONE_SHOT)
			root.add_child(gather)
			root.add_child(SpellVisuals.dust_ring(1.6, 1.0))
		"mirror":
			var shards: GPUParticles3D = SpellFx.sparks(tint, 0.8, 30, 4.0, "shard")
			shards.position.y = 1.0
			shards.tree_entered.connect(func() -> void: shards.emitting = true, CONNECT_ONE_SHOT)
			root.add_child(shards)
	var flash := OmniLight3D.new()
	flash.light_color = tint
	flash.light_energy = 4.0
	flash.omni_range = 5.0
	flash.position.y = 1.2
	root.add_child(flash)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.8)
		tween.tween_interval(3.5)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Streaks of `tint` rising fast out of the ground: the raised dead's ribbons.
static func _streaks(tint: Color, amount: int, radius: float, speed: float) -> GPUParticles3D:
	var streaks := GPUParticles3D.new()
	streaks.amount = amount
	streaks.lifetime = 0.9
	streaks.one_shot = true
	streaks.explosiveness = 0.6
	streaks.local_coords = true
	streaks.draw_pass_1 = SpellFx.streak_mesh(0.12, 1.1, "mote")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.3
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = speed * 0.6
	process.initial_velocity_max = speed
	process.damping_min = speed * 0.8
	process.damping_max = speed * 1.2
	process.tangential_accel_min = 2.0
	process.tangential_accel_max = 4.0
	process.particle_flag_align_y = true
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.5), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(tint)
	streaks.process_material = process
	streaks.position.y = 0.1
	streaks.tree_entered.connect(func() -> void: streaks.emitting = true, CONNECT_ONE_SHOT)
	return streaks
