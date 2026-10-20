class_name WhirlwindFx
extends Node3D
## The barbarian's Whirlwind as something that happens to the air and the ground, not only a
## figure turning on the spot: the clip is a single held pose that PlayerAnimator turns round,
## and on its own that read as stiff - the legs above all, standing still while the body spun.
##
## Four layers, all driven off the animator's spin (PlayerAnimator.whirlwind_progress), which
## every screen plays - so every player sees them, the barbarian's own machine or not:
##   - a smear behind the blade, a flat ring at the sword's own height and reach;
##   - wisps of wind dragged round the body, one band low round the legs and one round the
##     chest, so the legs are wrapped in moving air rather than standing still in it;
##   - dust stirred up off the ground and swept round with the spin;
##   - grit and clods flung out sideways.
##
## Top-level and unrotated: the figure under the player turns, the player's facing does not,
## and the smear is placed by where the blade actually IS rather than by either of them.

const TRAIL_SHADER := preload("res://assets/shaders/whirlwind_trail.gdshader")
const WIND_SHADER := preload("res://assets/shaders/whirlwind_wind.gdshader")
const DUST_TINT := Color(0.55, 0.45, 0.32)
## Per second: up quickly with the first turn, and dying away a little slower than that.
const FADE_IN := 7.0
const FADE_OUT := 2.5
## The wind bands: [radius, bottom, height, turns per second of their own].
const WIND_BANDS := [[1.05, 0.02, 1.0, 1.6], [1.5, 0.55, 1.35, 1.2]]
const RING_SEGMENTS := 96
## How tall the upright smear is: a little more than the blade is broad, so it reads as a
## sweep rather than as a ribbon.
const TRAIL_BAND_HEIGHT := 0.42

var _player: Player = null
var _sword: Node3D = null
var _intensity: float = 0.0
var _trail: MeshInstance3D = null
var _trail_band: MeshInstance3D = null
var _trail_material: ShaderMaterial = null
var _trail_band_material: ShaderMaterial = null
var _wind_materials: Array[ShaderMaterial] = []
var _wind_phase: float = 0.0
var _dust: GPUParticles3D = null
var _grit: GPUParticles3D = null


func _ready() -> void:
	name = "WhirlwindFx"
	_player = get_parent() as Player
	top_level = true
	visible = false
	_build_trail()
	_build_wind()
	_dust = _build_dust()
	add_child(_dust)
	_grit = _build_grit()
	add_child(_grit)


func _process(delta: float) -> void:
	if _player == null or _player.animator == null:
		return
	var progress: float = _player.animator.whirlwind_progress()
	var spinning: bool = progress >= 0.0
	_intensity = move_toward(_intensity, 1.0 if spinning else 0.0,
		delta * (FADE_IN if spinning else FADE_OUT))
	global_transform = Transform3D(Basis.IDENTITY, _player.global_position)
	_dust.emitting = spinning
	_grit.emitting = spinning
	visible = _intensity > 0.001 or _dust.emitting
	if not visible:
		return
	_place_trail()
	_trail_material.set_shader_parameter("intensity", _intensity)
	_trail_band_material.set_shader_parameter("intensity", _intensity)
	_wind_phase += delta
	for index: int in _wind_materials.size():
		var material: ShaderMaterial = _wind_materials[index]
		material.set_shader_parameter("intensity", _intensity)
		# Negative: the wisps travel the way the blade goes round (rising angle).
		material.set_shader_parameter("phase", fposmod(-_wind_phase * float(WIND_BANDS[index][3]), 1.0))


## The smear follows the blade: its angle round the body, its height and its reach, read off
## the sword's own mesh every frame (the tip is the corner of the blade farthest from the hand).
func _place_trail() -> void:
	var tip: Vector3 = _blade_tip()
	var flat: Vector3 = tip - global_position
	var reach: float = Vector2(flat.x, flat.z).length()
	if reach < 0.3:
		return
	var head: float = fposmod(atan2(-flat.z, flat.x), TAU)
	_trail_material.set_shader_parameter("head", head)
	_trail_band_material.set_shader_parameter("head", head)
	var height: float = clampf(flat.y, 0.4, 1.8)
	_trail.position = Vector3(0.0, height, 0.0)
	_trail.scale = Vector3(reach * 1.06, 1.0, reach * 1.06)
	# The upright band stands a little inside the tip, where the broad of the blade passes.
	_trail_band.position = Vector3(0.0, height - TRAIL_BAND_HEIGHT * 0.5, 0.0)
	_trail_band.scale = Vector3(reach * 0.92, 1.0, reach * 0.92)


func _blade_tip() -> Vector3:
	# Looked up again once the one held is gone or out of the tree: the class's visual can
	# be swapped after the player is built, and the old one leaves with its sword.
	if _sword == null or not is_instance_valid(_sword) or not _sword.is_inside_tree():
		_sword = _find_sword()
	if _sword == null:
		return _player.global_position + Vector3(1.6, 1.1, 0.0)
	var hand: Vector3 = _sword.global_position
	var best: Vector3 = hand
	var best_distance: float = -1.0
	for mesh: Node in _sword.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if not instance.is_inside_tree():
			continue
		var box: AABB = instance.get_aabb()
		for corner: int in 8:
			var point: Vector3 = instance.global_transform * box.get_endpoint(corner)
			var distance: float = point.distance_squared_to(hand)
			if distance > best_distance:
				best_distance = distance
				best = point
	return best


func _find_sword() -> Node3D:
	for attachment: Node in _player.find_children("*", "BoneAttachment3D", true, false):
		if attachment.is_inside_tree() and String(attachment.name).to_lower().contains("sword"):
			return attachment as Node3D
	return null


func _build_trail() -> void:
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.mesh = _ring_mesh(0.25)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = TRAIL_SHADER
	_trail_material.render_priority = SpellFx.FX_RENDER_PRIORITY
	_trail.material_override = _trail_material
	add_child(_trail)
	_trail_band = MeshInstance3D.new()
	_trail_band.name = "TrailBand"
	_trail_band.mesh = _band_mesh(1.0, TRAIL_BAND_HEIGHT)
	_trail_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_band_material = _trail_material.duplicate() as ShaderMaterial
	_trail_band_material.set_shader_parameter("upright", true)
	_trail_band.material_override = _trail_band_material
	add_child(_trail_band)


func _build_wind() -> void:
	for band: Array in WIND_BANDS:
		var instance := MeshInstance3D.new()
		instance.name = "Wind%d" % _wind_materials.size()
		instance.mesh = _band_mesh(float(band[0]), float(band[2]))
		instance.position.y = float(band[1])
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = WIND_SHADER
		material.render_priority = SpellFx.FX_RENDER_PRIORITY
		# The low band is dust-laden air, the high one cleaner.
		var dusty: float = 0.45 if float(band[1]) < 0.3 else 0.0
		material.set_shader_parameter("tint", Color(0.85, 0.8, 0.7).lerp(DUST_TINT, dusty))
		instance.material_override = material
		_wind_materials.append(material)
		add_child(instance)


## Earth kicked up round the feet and swept along with the spin: puffs of the smoke flipbook,
## born on a ring round the barbarian, dragged sideways and lifted a little as they spread.
## World-space, so a barbarian spinning across the field leaves a wake of it behind.
func _build_dust() -> GPUParticles3D:
	var dust := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 1.5, 30, 1.2)
	dust.name = "Dust"
	dust.one_shot = false
	dust.emitting = false
	var process: ParticleProcessMaterial = dust.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.6
	process.emission_ring_inner_radius = 0.5
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.9
	# Negative with gravity pointing up: Godot pushes along cross(outward, gravity), and this
	# way round that is the spin's own direction.
	process.tangential_accel_min = -8.0
	process.tangential_accel_max = -5.0
	process.radial_accel_min = 1.0
	process.radial_accel_max = 2.5
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.gravity = Vector3(0.0, 0.35, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.1
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.35), Vector2(1.0, 1.5)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(DUST_TINT.r, DUST_TINT.g, DUST_TINT.b, 0.0))
	gradient.add_point(0.15, Color(DUST_TINT.r, DUST_TINT.g, DUST_TINT.b, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(DUST_TINT.r * 0.85, DUST_TINT.g * 0.85, DUST_TINT.b * 0.85, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	dust.position.y = 0.15
	return dust


## Grit and clods flung off the ground at the edge of the spin, outwards and round with it.
func _build_grit() -> GPUParticles3D:
	var grit := GPUParticles3D.new()
	grit.name = "Grit"
	grit.amount = 22
	grit.lifetime = 0.7
	grit.local_coords = false
	grit.emitting = false
	grit.draw_pass_1 = SpellFx.premul_particle_mesh(1.3, "dirt_fine")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.4
	process.emission_ring_inner_radius = 0.7
	process.emission_ring_height = 0.05
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 4.5
	process.tangential_accel_min = 10.0
	process.tangential_accel_max = 16.0
	process.radial_accel_min = 3.0
	process.radial_accel_max = 6.0
	process.gravity = Vector3(0.0, -14.0, 0.0)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -240.0
	process.angular_velocity_max = 240.0
	process.scale_min = 0.5
	process.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.15, 0.09, 0.95))
	gradient.add_point(0.75, Color(0.18, 0.13, 0.08, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	# Premultiplied: earth is pigment and covers what is behind it.
	for stop: int in gradient.get_point_count():
		var c: Color = gradient.get_color(stop)
		gradient.set_color(stop, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	grit.process_material = process
	grit.position.y = 0.1
	return grit


## A flat ring in the XZ plane, outer radius 1 (scaled to the blade's reach), UV.x once round
## at (cos, 0, -sin) of UV.x * TAU, UV.y from `inner` out to the rim.
static func _ring_mesh(inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in RING_SEGMENTS:
		var u0: float = float(segment) / RING_SEGMENTS
		var u1: float = float(segment + 1) / RING_SEGMENTS
		var quad: Array = [[u0, 0.0], [u1, 0.0], [u1, 1.0], [u0, 0.0], [u1, 1.0], [u0, 1.0]]
		for corner: Array in quad:
			var angle: float = float(corner[0]) * TAU
			var radius: float = lerpf(inner, 1.0, float(corner[1]))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(corner[0]), float(corner[1])))
			st.add_vertex(Vector3(cos(angle) * radius, 0.0, -sin(angle) * radius))
	return st.commit()


## An open cylinder of `radius` from 0 up to `height`, UV.x once round, UV.y bottom to top.
static func _band_mesh(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in RING_SEGMENTS:
		var u0: float = float(segment) / RING_SEGMENTS
		var u1: float = float(segment + 1) / RING_SEGMENTS
		var quad: Array = [[u0, 0.0], [u1, 0.0], [u1, 1.0], [u0, 0.0], [u1, 1.0], [u0, 1.0]]
		for corner: Array in quad:
			var angle: float = float(corner[0]) * TAU
			st.set_normal(Vector3(cos(angle), 0.0, -sin(angle)))
			st.set_uv(Vector2(float(corner[0]), float(corner[1])))
			st.add_vertex(Vector3(cos(angle) * radius, float(corner[1]) * height, -sin(angle) * radius))
	return st.commit()
