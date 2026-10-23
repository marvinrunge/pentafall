extends Node3D
## The mana round the base crystal, as on the title art, in the five mana colours:
##
##   embers   thin sparks rising off it like off a fire - the main part
##   motes    a cloud of small sharp points of light drifting round it, thickest against it
##            and thinning out a few metres away
##   glints   a few four-point stars flashing up close to its faces
##   wisps    a few threads of mana circling it on trails
##
## Four small emitters, all on the same ring round the crystal and all circling it slowly the
## way it turns. Each particle takes one of the five colours at birth from
## `color_initial_ramp`, whose constant interpolation keeps the five apart rather than
## blending them into in-between hues. Everything is premultiplied like the spell effects and
## a little above 1 so the cores just bloom - readable at noon, and some of the only light
## there is at night. Small and sharp throughout: big soft dots read as out of focus.
##
## A child of MainCrystal (see MainController._ready), so the emission bobs with the crystal
## and the mana goes out with it when it is destroyed. The particles themselves are in world
## space: a spark already shed stays where it was shed instead of swinging round with the
## crystal's turn. GraphicsSettings scales every count below with the particle setting.

const MOTE_SHADER := preload("res://assets/shaders/crystal_mote.gdshader")
const EMBER_SHADER := preload("res://assets/shaders/crystal_ember.gdshader")
const WISP_SHADER := preload("res://assets/shaders/crystal_wisp.gdshader")

## The five mana colours, white to green. A little above 1, so the cores just pass the
## glow's HDR threshold and read as lights - not far above it, or the bloom smears every
## mote into a big soft blob. The weak channels are kept low, or the cores go white.
const MANA_COLORS: Array[Color] = [
	Color(2.0, 1.6, 0.75),
	Color(0.25, 0.65, 2.2),
	Color(1.2, 0.25, 2.2),
	Color(2.2, 0.55, 0.1),
	Color(0.35, 2.1, 0.3),
]
## The band round the crystal's axis everything is shed from, metres: inside the wide middle
## of the crystal (where what is born behind its faces is hidden by them) out to a few metres
## past it. The crystal visual is 9.6 m tall round MainCrystal's origin.
const SHED_RADIUS := Vector2(1.4, 4.2)
const SHED_HEIGHT: float = 8.0
## How fast it all circles the crystal, turns per second, the same way the crystal turns.
const ORBIT := Vector2(0.01, 0.035)
## Edge of a mote's quad, metres; the bright core is about a quarter of it.
const MOTE_SIZE: float = 0.36


func _init() -> void:
	name = "CrystalMotes"
	add_child(_embers())
	add_child(_motes())
	add_child(_glints())
	add_child(_wisps())


## Thin sparks rising off the crystal, laid along the way they fly, wandering as they climb.
func _embers() -> GPUParticles3D:
	var particles := _emitter("Embers", 120, 4.5)
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_ring_inner_radius = 1.3
	process.emission_ring_radius = 4.0
	process.emission_ring_height = 7.0
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.2
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.radial_velocity_max = 0.15
	process.turbulence_influence_min = 0.08
	process.turbulence_influence_max = 0.2
	process.particle_flag_align_y = true
	process.scale_min = 0.6
	process.scale_max = 1.0
	var mesh: ArrayMesh = SpellFx.streak_mesh(0.06, 0.55)
	mesh.surface_set_material(0, _effect_material(EMBER_SHADER))
	particles.draw_pass_1 = mesh
	return particles


## Small sharp points of light drifting round it, the cloud the sparks rise through.
func _motes() -> GPUParticles3D:
	var particles := _emitter("Motes", 160, 9.0)
	var process := particles.process_material as ParticleProcessMaterial
	# A lazy start in any direction and a slow wander, so the cloud spreads and thins with
	# distance; only a little push out from the crystal's middle, which near its tips points
	# mostly up and stood a column of motes over it when it was stronger.
	process.radial_velocity_max = 0.2
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.45
	var mesh := QuadMesh.new()
	mesh.size = Vector2(MOTE_SIZE, MOTE_SIZE)
	mesh.material = _effect_material(MOTE_SHADER)
	particles.draw_pass_1 = mesh
	return particles


## Four-point stars flashing up close to the crystal's faces: up fast, most of the way down
## again, then out. Drawn with SpellFx's premultiplied billboard, so the fade is too.
func _glints() -> GPUParticles3D:
	var particles := _emitter("Glints", 40, 2.4)
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_ring_inner_radius = 1.8
	process.emission_ring_radius = 3.0
	process.initial_velocity_max = 0.15
	process.radial_velocity_max = 0.08
	process.angle_min = -20.0
	process.angle_max = 20.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.scale_curve = SpellFx._curve_texture([
		Vector2(0.0, 0.0), Vector2(0.18, 1.0), Vector2(0.4, 0.35), Vector2(1.0, 0.0),
	])
	process.color_ramp = _fade([Vector2(0.0, 0.0), Vector2(0.15, 1.0), Vector2(0.45, 0.4), Vector2(1.0, 0.0)], true)
	particles.draw_pass_1 = SpellFx.premul_particle_mesh(0.8, "mote")
	return particles


## A few threads of mana circling the crystal faster than the rest, comets on ribbon trails.
func _wisps() -> GPUParticles3D:
	var particles := _emitter("Wisps", 10, 8.0)
	particles.trail_enabled = true
	particles.trail_lifetime = 2.2
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_ring_inner_radius = 2.4
	process.emission_ring_radius = 3.8
	process.emission_ring_height = 7.0
	process.radial_velocity_min = 0.0
	process.radial_velocity_max = 0.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.2
	process.orbit_velocity_min = 0.07
	process.orbit_velocity_max = 0.13
	process.turbulence_influence_max = 0.05
	process.scale_min = 1.0
	process.scale_max = 1.0
	process.scale_curve = null
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = 0.1
	ribbon.sections = 20
	ribbon.section_length = 0.3
	ribbon.section_segments = 1
	ribbon.material = _effect_material(WISP_SHADER)
	particles.draw_pass_1 = ribbon
	return particles


# --- what they share -------------------------------------------------------------------

## An emitter on the shed ring, with the colours, the slow drift, the lift, the orbit and the
## fade over its life that every part starts from.
func _emitter(node_name: String, count: int, life: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = count
	particles.lifetime = life
	# Already going when the match starts, not streaming out of the crystal.
	particles.preprocess = life
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Where a particle can be by the end of its life, so it is never culled while on screen.
	particles.visibility_aabb = AABB(Vector3(-12.0, -8.0, -12.0), Vector3(24.0, 22.0, 24.0))
	# Everything here is under a pixel or two long before this.
	particles.visibility_range_end = 140.0

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_inner_radius = SHED_RADIUS.x
	process.emission_ring_radius = SHED_RADIUS.y
	process.emission_ring_height = SHED_HEIGHT
	process.lifetime_randomness = 0.4
	process.radial_velocity_min = 0.05
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.gravity = Vector3(0.0, 0.035, 0.0)
	# Circling the crystal. In 3D the orbit only turns round an axis through a CurveXYZTexture
	# (without one it turns in the XY plane, which is a vertical wheel here), so Y is 1 and the
	# other two are flat at 0.
	process.orbit_velocity_min = ORBIT.x
	process.orbit_velocity_max = ORBIT.y
	var orbit_axis := CurveXYZTexture.new()
	orbit_axis.curve_x = _flat_curve(0.0)
	orbit_axis.curve_y = _flat_curve(1.0)
	orbit_axis.curve_z = _flat_curve(0.0)
	process.orbit_velocity_curve = orbit_axis
	# Wandering rather than flying straight: a slow, wide noise field bends their paths.
	process.turbulence_enabled = true
	process.turbulence_noise_scale = 5.0
	process.turbulence_noise_speed = Vector3(0.0, 0.1, 0.0)
	process.turbulence_influence_min = 0.04
	process.turbulence_influence_max = 0.12
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.scale_curve = SpellFx._curve_texture([
		Vector2(0.0, 0.0), Vector2(0.15, 1.0), Vector2(0.75, 0.8), Vector2(1.0, 0.0),
	])

	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	colors.colors = PackedColorArray(MANA_COLORS)
	var initial := GradientTexture1D.new()
	initial.gradient = colors
	initial.use_hdr = true
	process.color_initial_ramp = initial
	# Fades in and out over its life. Plain, because the crystal's own shaders premultiply.
	process.color_ramp = _fade([Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.6, 0.75), Vector2(1.0, 0.0)], false)
	particles.process_material = process
	return particles


func _effect_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	return material


## White fading in and out over a particle's life, `points` as (time, alpha). `premultiplied`
## for SpellFx's materials, which take the vertex colour as it comes (see SpellFx._premul_ramp).
static func _fade(points: Array, premultiplied: bool) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for point: Vector2 in points:
		offsets.append(point.x)
		var white: float = point.y if premultiplied else 1.0
		colors.append(Color(white, white, white, point.y))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _flat_curve(value: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, value))
	curve.add_point(Vector2(1.0, value))
	return curve
