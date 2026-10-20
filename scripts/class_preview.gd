extends Control
class_name ClassPreview
## The picked class standing in the main menu (MainMenu): its own model in its own idle,
## lit like a figure on a plinth, over the right of the menu painting. Drag to turn it.
##
## A SubViewport with a world of its own and a transparent background, so the painting
## stays behind the figure and nothing in the menu's 2D tree has to know about 3D. The
## model is the class's real visual (ClassDatabase.visual_scene) - the same scene the game
## plays - so what is picked is exactly what walks onto the map, props and all.

## Where the figure stands, turned three-quarters to the viewer. The visuals face -Z.
const REST_YAW := PI - 0.5
## Radians of turn per pixel dragged.
const DRAG_TURN := 0.012
## How fast the figure eases back to REST_YAW once let go, and how long after letting go
## it starts to.
const SETTLE_RATE := 2.2
const SETTLE_DELAY := 2.5
## Seconds between the occasional look around (the class's idle_look clips).
const LOOK_EVERY := Vector2(7.0, 12.0)
const FADE_SECONDS := 0.35
## How much of the world the camera shows, in metres up from the feet: from a little below the
## ground to above the highest a class holds its weapon at rest - the barbarian's greatsword
## stands about 2.8 m up. The camera is fitted to this whatever the preview's size.
const VIEW_BOTTOM := -0.3
const VIEW_TOP := 3.0
const CAMERA_DISTANCE := 5.4

## The column of the preview the figure stands in, as left and right shares of its width.
## The preview can be wider than that - the whole menu - so nothing the figure holds is ever
## cut off by the frame; the camera is slid sideways to keep the figure in the column, and the
## dark backing sits under it. The caption - the class's name and role - is the menu's, which
## makes the name the class picker (MainMenu._build_identity).
var figure_column := Vector2(0.0, 1.0)

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _visual: Node3D
var _anim: AnimationPlayer
var _class_id: String = ""
var _yaw: float = REST_YAW
var _dragging: bool = false
var _since_drag: float = INF
var _look_timer: float = 0.0
## Scenes already loaded, so flicking through the picker does not reload a model each time.
var _scenes: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_build_backing()
	_build_viewport()
	_look_timer = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)


## Shows `class_id`, fading the figure across. Does nothing for the class already shown.
func show_class(class_id: String) -> void:
	class_id = ClassDatabase.resolve(class_id)
	if class_id == _class_id:
		return
	_class_id = class_id
	if _visual != null:
		_visual.queue_free()
		_visual = null
		_anim = null
	var path: String = ClassDatabase.visual_scene(class_id)
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene: PackedScene = _scenes[path] as PackedScene
	if scene == null:
		push_warning("Class preview: no visual at %s" % path)
		return
	_visual = scene.instantiate()
	_pivot.add_child(_visual)
	_anim = _visual.find_child("AnimationPlayer", true, false)
	if _anim != null:
		_anim.animation_finished.connect(_on_clip_finished)
		if _anim.has_animation("idle"):
			_anim.play("idle")
	# A bow's string is drawn at runtime (BowRig); at rest it is the straight line between
	# the tips, which needs no animator to say whether a hand is on it.
	var bow: Node3D = _visual.find_child("Bow", true, false) as Node3D
	var skeleton: Skeleton3D = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if bow != null and skeleton != null:
		var rig := BowRig.new()
		rig.setup(null, bow, skeleton)
		_visual.add_child(rig)
	# The mage's orb over the palm, in plain arcane light - nobody is on a path in the menu.
	if ClassDatabase.has_hand_orb(class_id) and skeleton != null:
		var orb := MageHandOrb.new()
		orb.setup(skeleton)
		_visual.add_child(orb)
	_yaw = REST_YAW
	_pivot.rotation.y = _yaw
	var fade := create_tween()
	_viewport_container().modulate.a = 0.0
	fade.tween_property(_viewport_container(), "modulate:a", 1.0, FADE_SECONDS)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	if not _dragging:
		_since_drag += delta
		if _since_drag > SETTLE_DELAY:
			_yaw = lerp_angle(_yaw, REST_YAW, 1.0 - exp(-SETTLE_RATE * delta))
	_pivot.rotation.y = _yaw
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
		_look_around()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		_since_drag = 0.0
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw += (event as InputEventMouseMotion).relative.x * DRAG_TURN
		accept_event()


## One of the class's idle variations, when it is standing in the plain idle.
func _look_around() -> void:
	if _anim == null or _anim.current_animation != "idle":
		return
	var looks: Array[String] = []
	for clip: String in ["idle_look_1", "idle_look_2"]:
		if _anim.has_animation(clip):
			looks.append(clip)
	if not looks.is_empty():
		_anim.play(looks.pick_random(), 0.3)


func _on_clip_finished(_clip: StringName) -> void:
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle", 0.3)


func _viewport_container() -> SubViewportContainer:
	return _viewport.get_parent() as SubViewportContainer


# --- building -----------------------------------------------------------------------------

## A soft dark pool behind the figure, so it reads against the busy painting rather than
## being lost in the battle behind it.
func _build_backing() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.62))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.0, 0.32))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.55)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	var backing := TextureRect.new()
	backing.texture = texture
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backing.anchor_left = figure_column.x
	backing.anchor_right = figure_column.y
	backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backing.stretch_mode = TextureRect.STRETCH_SCALE
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)

	# The painting's light: a warm low sun from the front left, a cool fill from the right
	# and a rim from behind that picks the figure out of the dark backing.
	for light: Array in [
		[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.82, 0.62), 1.5, true],
		[Vector3(-15.0, 140.0, 0.0), Color(0.6, 0.7, 0.95), 0.45, false],
		[Vector3(-25.0, 180.0, 0.0), Color(1.0, 0.7, 0.5), 1.1, false],
	]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = light[0]
		sun.light_color = light[1]
		sun.light_energy = light[2]
		sun.shadow_enabled = light[3]
		_viewport.add_child(sun)

	# The field of view spans VIEW_BOTTOM..VIEW_TOP at the figure's distance; a level camera,
	# so the feet stay put at the bottom of the frame whatever the class holds above them.
	var camera := Camera3D.new()
	var middle: float = (VIEW_BOTTOM + VIEW_TOP) * 0.5
	camera.fov = rad_to_deg(2.0 * atan((VIEW_TOP - VIEW_BOTTOM) * 0.5 / CAMERA_DISTANCE))
	camera.position = Vector3(0.0, middle, CAMERA_DISTANCE)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, middle, 0.0))
	camera.current = true
	_camera = camera
	_viewport.size_changed.connect(_place_figure)
	_place_figure()

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_viewport.add_child(_contact_shadow())


## Slides the camera sideways so the figure stands in the middle of `figure_column`, at the
## preview's current aspect (the camera keeps its height, so the width it sees follows it).
func _place_figure() -> void:
	if _camera == null or _viewport.size.y <= 0:
		return
	var half_height: float = tan(deg_to_rad(_camera.fov) * 0.5) * CAMERA_DISTANCE
	var half_width: float = half_height * float(_viewport.size.x) / float(_viewport.size.y)
	var column_middle: float = (figure_column.x + figure_column.y) * 0.5
	_camera.h_offset = (0.5 - column_middle) * 2.0 * half_width


## A soft dark ellipse on the ground under the feet - there is no floor in this world for
## the light to cast onto, and a figure with nothing under it floats.
static func _contact_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.5, 1.1)
	plane.material = material
	var shadow := MeshInstance3D.new()
	shadow.mesh = plane
	shadow.position.y = 0.01
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow
