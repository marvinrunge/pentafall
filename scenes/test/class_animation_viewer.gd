extends Node3D
## Animation viewer for the playable classes (ClassDatabase): every clip of a class's visual,
## the way the game stores it, the way the game PLAYS it, or straight from its source fbx.
##
## Open scenes/test/class_animation_viewer.tscn and press F6.
##
## Three ways to look at a clip (the "Ansicht" picker):
##   Ganzer Clip      the clip as stored in the class's library - root motion stripped, the
##                    hips shifted so the feet touch the floor (tools/player_character_builder.gd).
##   Wie im Spiel     only the slice the game plays of an attack or a cast (`trim_start`,
##                    `trim_length`); everything else whole. The game also stretches that slice
##                    to the move's duration - the speed slider is how to try that.
##   Original-FBX     the source file exactly as downloaded, root motion and all - to tell
##                    whether something looks wrong in the download or in what the builder did.
## The timeline shows the played slice (blue), the measured impacts (red) and, for a light
## chain, where the game cuts it into stages (yellow).
##
## Controls: left-drag orbit, right/middle-drag pan, wheel zoom, F reframe, V next view,
## Up/Down clip, Space play/pause, Left/Right one frame, L loop.
##
## Opens on the newest class, the barbarian. From the command line the class, clip and view
## can be picked: `-- <class> [clip] [stored|game|raw]`.

const Builder = preload("res://tools/player_character_builder.gd")
const FPS := 30.0
const RAW_LIBRARY := "raw"
## The class shown first when none is named on the command line.
const START_CLASS := "barbarian"

## The light chains and how many stages the game spends them in (MeleeKit / GreatswordKit).
const CHAIN_STAGES := {"combo_3": 2, "combo_2": 3, "cleave_chain": 3}

## What each logical clip is for in the game.
const PURPOSE := {
	"idle": "Stehen", "idle_look_1": "Stehen, Variation", "idle_look_2": "Stehen, Variation",
	"walk_forward": "Gehen vorwärts", "walk_back": "Gehen rückwärts",
	"walk_left": "Gehen seitwärts links", "walk_right": "Gehen seitwärts rechts",
	"run_forward": "Rennen (Kampf) vorwärts", "run_back": "Rennen (Kampf) rückwärts",
	"run_forward_unarmed": "Sprint vorwärts", "run_back_unarmed": "Sprint rückwärts",
	"run_left": "Sprint seitwärts links", "run_right": "Sprint seitwärts rechts",
	"jump": "Sprung",
	"combo_3": "Leichter Angriff (Kette, 2 Stufen)", "combo_2": "Leichter Angriff mit Blade Dance (3 Stufen)",
	"spin_high": "Schwerer Angriff (Drehung)",
	"cleave_chain": "Leichter Angriff (Kette, 3 Hiebe)", "overhead": "Schwerer Angriff (aufgeladen: Ausholen = Halten)",
	"whirlwind": "Whirlwind-Pose (im Spiel dreht sich die Figur)",
	"kick": "Tritt", "jump_attack": "Titanic Brawl (grün): Sprung + Aufprall",
	"strike_downward": "Act of Treason / Rabid Bite",
	"block_idle": "Block halten", "block_react": "Treffer im Block",
	"hit_gut": "Treffer von vorn", "hit_left": "Treffer von links", "hit_right": "Treffer von rechts",
	"death": "Tod",
	"cast_white": "Zauber Weiß", "cast_blue": "Zauber Blau", "cast_black": "Zauber Schwarz",
	"cast_red": "Zauber Rot", "cast_green": "Zauber Grün",
	"taunt_battlecry": "Große Buffs (z. B. Berserk)",
	"draw": "Bogen spannen", "aim": "Bogen halten", "shoot": "Schuss",
	"dodge_forward": "Rolle vorwärts", "dodge_back": "Rolle rückwärts / Disengage",
	"dodge_left": "Rolle links", "dodge_right": "Rolle rechts",
}

## Camera directions to cycle with V: front-right, front, side, back.
const VIEWS := [150.0, 180.0, 90.0, 0.0]

enum Mode { STORED, GAME, RAW }

var _class_ids: Array[String] = []
var _visual: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _clips: PackedStringArray = PackedStringArray()
## Whether each clip loops in the game - read before the Loop box starts changing it.
var _loops_in_game: Dictionary = {}
var _current := ""
var _mode: Mode = Mode.GAME
var _speed := 1.0
var _loop := true
var _view := 0
var _follow := false

# the slice of the clip the timeline shows, in clip seconds
var _range_start := 0.0
var _range_end := 1.0

# camera orbit state
var _cam: Camera3D
var _target := Vector3(0, 1.0, 0)
var _yaw := deg_to_rad(150.0)
var _pitch := deg_to_rad(-10.0)
var _dist := 4.2

# ui
var _class_list: OptionButton
var _mode_list: OptionButton
var _clip_box: VBoxContainer
var _clip_scroll: ScrollContainer
var _play_btn: Button
var _loop_btn: CheckBox
var _follow_btn: CheckBox
var _speed_label: Label
var _timeline: Control
var _time_label: Label
var _info_label: Label
var _scrubbing := false


func _ready() -> void:
	_build_world()
	_build_ui()
	for class_id: String in ClassDatabase.ORDER:
		_class_ids.append(class_id)
		_class_list.add_item(ClassDatabase.display_name(class_id))
	var args := OS.get_cmdline_user_args()
	_class_list.select(maxi(_class_ids.find(args[0] if args.size() > 0 else START_CLASS), 0))
	if args.size() > 1:
		_current = args[1]
	if args.size() > 2:
		_mode = (["stored", "game", "raw"].find(args[2]) if ["stored", "game", "raw"].has(args[2]) else Mode.GAME) as Mode
		_mode_list.select(_mode)
	_load_class()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.45, 0.58)
	mat.sky_horizon_color = Color(0.68, 0.7, 0.72)
	mat.ground_horizon_color = Color(0.68, 0.7, 0.72)
	mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	# checker floor: 1 m tiles, so foot sliding and sinking into the ground are easy to see
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _checker_texture()
	fm.uv1_scale = Vector3(60, 60, 1)
	fm.roughness = 0.95
	floor_mesh.material = fm
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	add_child(floor)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_update_camera()


func _checker_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var a := (((x >> 5) + (y >> 5)) & 1) == 0
			img.set_pixel(x, y, Color(0.42, 0.42, 0.4) if a else Color(0.32, 0.32, 0.31))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ the class

func _class_id() -> String:
	return _class_ids[_class_list.selected] if not _class_ids.is_empty() else ClassDatabase.DEFAULT_CLASS


func _config() -> Dictionary:
	return Builder.CONFIGS.get(_class_id(), {})


func _load_class() -> void:
	if _visual != null:
		_visual.queue_free()
	var scene := load(ClassDatabase.visual_scene(_class_id())) as PackedScene
	if scene == null:
		_info_label.text = "Kein Visual für %s" % _class_id()
		return
	_visual = scene.instantiate() as Node3D
	add_child(_visual)
	_player = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null:
		_info_label.text = "Kein AnimationPlayer im Visual"
		return
	_player.autoplay = ""
	_player.animation_finished.connect(func(_n: StringName) -> void: _play_btn.text = "Play")
	_clips = _ordered_clips()
	_loops_in_game.clear()
	for clip in _clips:
		_loops_in_game[clip] = _player.get_animation(clip).loop_mode != Animation.LOOP_NONE
	_rebuild_clip_buttons()
	_target = Vector3(0, 1.0, 0)
	_update_camera()
	var start: String = _current if _clips.has(_current) else (_clips[0] if not _clips.is_empty() else "")
	if start != "":
		_play(start)


## The library's clips in the order the builder config lists them - locomotion, attacks,
## reactions, casts - then anything else.
func _ordered_clips() -> PackedStringArray:
	var library: AnimationLibrary = _player.get_animation_library("")
	var names: PackedStringArray = library.get_animation_list() if library != null else PackedStringArray()
	var ordered := PackedStringArray()
	var config := _config()
	for table: String in ["clips", "foreign"]:
		for clip: String in (config.get(table, {}) as Dictionary).keys():
			if names.has(clip) and not ordered.has(clip):
				ordered.append(clip)
	for clip in names:
		if not ordered.has(clip) and clip != "RESET":
			ordered.append(clip)
	return ordered


## The source fbx a clip was built from, or "" for one borrowed from another rig - those
## cannot be shown raw on this skeleton.
func _source_path(clip: String) -> String:
	var config := _config()
	var own: Dictionary = config.get("clips", {})
	if own.has(clip):
		return String(config["root"]) + String(own[clip][0])
	return ""


func _stored(clip: String) -> Animation:
	return _player.get_animation(clip) if _player != null and _player.has_animation(clip) else null


# ------------------------------------------------------------------ playback

func _play(clip: String) -> void:
	_current = clip
	var anim := _stored(clip)
	if anim == null:
		return
	var played_name := clip
	_range_start = 0.0
	_range_end = anim.length
	if _mode == Mode.RAW:
		var raw := _raw_clip(clip)
		if raw == null:
			_info_label.text = "%s\n\nKein Original für diesen Clip: er ist von einem anderen Rig geliehen." % clip
			_mode = Mode.STORED
			_mode_list.select(Mode.STORED)
		else:
			played_name = "%s/%s" % [RAW_LIBRARY, clip]
			_range_end = raw.length
	elif _mode == Mode.GAME and anim.has_meta("trim_start"):
		_range_start = float(anim.get_meta("trim_start"))
		_range_end = _range_start + float(anim.get_meta("trim_length", anim.length - _range_start))
	var played := _player.get_animation(played_name)
	played.loop_mode = Animation.LOOP_LINEAR if _loop else Animation.LOOP_NONE
	_player.speed_scale = _speed
	_player.play_section(played_name, _range_start, _range_end)
	_player.seek(_range_start, true)
	if not _follow:
		_target = Vector3(0, 1.0, 0)
		_update_camera()
	_play_btn.text = "Pause"
	for b in _clip_box.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.name == clip)
	_update_info()
	_timeline.queue_redraw()


## The clip straight from its source fbx, added to a second library on first use.
func _raw_clip(clip: String) -> Animation:
	if not _player.has_animation_library(RAW_LIBRARY):
		_player.add_animation_library(RAW_LIBRARY, AnimationLibrary.new())
	var library: AnimationLibrary = _player.get_animation_library(RAW_LIBRARY)
	if library.has_animation(clip):
		return library.get_animation(clip)
	var path := _source_path(clip)
	if path == "":
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate()
	var source: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var anim: Animation = null
	if source != null and not source.get_animation_list().is_empty():
		anim = source.get_animation(source.get_animation_list()[0]).duplicate(true)
	root.free()
	if anim != null:
		library.add_animation(clip, anim)
	return anim


func _toggle_pause() -> void:
	if _player == null or _current == "":
		return
	if _player.is_playing():
		_player.pause()
		_play_btn.text = "Play"
		return
	if not _loop and _player.current_animation_position >= _range_end - 0.001:
		_player.seek(_range_start, true)
	_player.play()
	_play_btn.text = "Pause"


func _step(frames: int) -> void:
	if _player == null or _player.current_animation == "":
		return
	_player.pause()
	_player.seek(clampf(_player.current_animation_position + frames / FPS, _range_start, _range_end), true)
	_play_btn.text = "Play"


func _seek_fraction(f: float) -> void:
	if _player == null or _player.current_animation == "":
		return
	_player.seek(lerpf(_range_start, _range_end, clampf(f, 0.0, 1.0)), true)


func _process(_delta: float) -> void:
	if _player == null or _current == "":
		return
	var pos := _player.current_animation_position if _player.current_animation != "" else _range_start
	_time_label.text = "%.2f s  (Frame %d)   Ausschnitt %.2f - %.2f s" % [
		pos, roundi(pos * FPS) + 1, _range_start, _range_end]
	_timeline.queue_redraw()
	if _follow and _skeleton != null:
		var hips := _skeleton.find_bone("mixamorig_Hips")
		if hips != -1:
			var at := (_skeleton.global_transform * _skeleton.get_bone_global_pose(hips)).origin
			_target = Vector3(at.x, 1.0, at.z)
			_update_camera()


func _update_info() -> void:
	var anim := _stored(_current)
	if anim == null:
		return
	var lines := PackedStringArray()
	lines.append("%s" % _current)
	lines.append(String(PURPOSE.get(_current, "")))
	var source := _source_path(_current)
	lines.append("Quelle: %s" % (source.get_file() if source != "" else "von einem anderen Rig geliehen"))
	lines.append("Länge: %.2f s, im Spiel %s" % [anim.length, "geloopt" if _loops_in_game.get(_current, false) else "einmalig"])
	if anim.has_meta("trim_start"):
		var t0 := float(anim.get_meta("trim_start"))
		var tl := float(anim.get_meta("trim_length", 0.0))
		lines.append("Im Spiel gespielt: %.2f - %.2f s" % [t0, t0 + tl])
		var hits := PackedStringArray()
		for ratio: float in anim.get_meta("hit_ratios", PackedFloat32Array()):
			hits.append("%.2f s" % (t0 + ratio * tl))
		lines.append("Treffer: %s" % ", ".join(hits))
	if anim.has_meta("travel_speed"):
		lines.append("Schrittweite: %.2f m/s" % float(anim.get_meta("travel_speed")))
	if anim.has_meta("left_landing"):
		lines.append("Linker Fuß setzt auf bei %.0f%%" % (float(anim.get_meta("left_landing")) * 100.0))
	_info_label.text = "\n".join(lines)


# ------------------------------------------------------------------ timeline

## Clip seconds of the measured impacts and, for a light chain, of its stage cuts.
func _marks() -> Dictionary:
	var anim := _stored(_current)
	var hits: Array[float] = []
	var cuts: Array[float] = []
	if anim == null or _mode == Mode.RAW or not anim.has_meta("trim_start"):
		return {"hits": hits, "cuts": cuts}
	var t0 := float(anim.get_meta("trim_start"))
	var tl := float(anim.get_meta("trim_length", 0.0))
	var ratios: PackedFloat32Array = anim.get_meta("hit_ratios", PackedFloat32Array())
	for ratio in ratios:
		hits.append(t0 + ratio * tl)
	if CHAIN_STAGES.has(_current):
		for cut in _stage_cuts(ratios, int(CHAIN_STAGES[_current])):
			cuts.append(t0 + cut * tl)
	return {"hits": hits, "cuts": cuts}


## Where a chain is cut into its stages, as ratios of its window - the same rule as
## PlayerAnimator.combo_windows(): at the midpoints of the widest gaps between impacts.
func _stage_cuts(hits: PackedFloat32Array, stages: int) -> Array[float]:
	var cuts: Array[float] = []
	if stages <= 1:
		return cuts
	if hits.size() < stages:
		for i in range(1, stages):
			cuts.append(float(i) / float(stages))
		return cuts
	var gaps: Array[Vector2] = []
	for i in hits.size() - 1:
		gaps.append(Vector2(hits[i + 1] - hits[i], (hits[i] + hits[i + 1]) * 0.5))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	for i in stages - 1:
		cuts.append(gaps[i].y)
	cuts.sort()
	return cuts


func _draw_timeline() -> void:
	var bar := _timeline.size
	var span := maxf(_range_end - _range_start, 0.001)
	_timeline.draw_rect(Rect2(Vector2.ZERO, bar), Color(0.1, 0.1, 0.12, 0.85))
	var anim := _stored(_current)
	var x_of := func(t: float) -> float: return (t - _range_start) / span * bar.x
	if anim != null and _mode == Mode.STORED and anim.has_meta("trim_start"):
		var t0 := float(anim.get_meta("trim_start"))
		var t1 := t0 + float(anim.get_meta("trim_length", 0.0))
		var a: float = x_of.call(t0)
		var b: float = x_of.call(t1)
		_timeline.draw_rect(Rect2(a, 0.0, b - a, bar.y), Color(0.25, 0.45, 0.85, 0.45))
	var marks := _marks()
	for t: float in marks["cuts"]:
		var x: float = x_of.call(t)
		_timeline.draw_line(Vector2(x, 0.0), Vector2(x, bar.y), Color(1.0, 0.85, 0.2), 2.0)
	for t: float in marks["hits"]:
		var x: float = x_of.call(t)
		_timeline.draw_line(Vector2(x, bar.y * 0.25), Vector2(x, bar.y), Color(1.0, 0.25, 0.2), 3.0)
	if _player != null and _player.current_animation != "":
		var x: float = x_of.call(_player.current_animation_position)
		_timeline.draw_line(Vector2(x, 0.0), Vector2(x, bar.y), Color.WHITE, 2.0)


func _on_timeline_input(event: InputEvent) -> void:
	var drag := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_scrubbing = (event as InputEventMouseButton).pressed
		drag = _scrubbing
		if _scrubbing and _player != null:
			_player.pause()
			_play_btn.text = "Play"
	elif event is InputEventMouseMotion and _scrubbing:
		drag = true
	if drag:
		_seek_fraction((event as InputEventMouse).position.x / maxf(_timeline.size.x, 1.0))


# ------------------------------------------------------------------ camera

func _update_camera() -> void:
	_pitch = clampf(_pitch, deg_to_rad(-85), deg_to_rad(85))
	_dist = clampf(_dist, 0.5, 60.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


func _next_view() -> void:
	_view = (_view + 1) % VIEWS.size()
	_yaw = deg_to_rad(float(VIEWS[_view]))
	_pitch = deg_to_rad(-10.0)
	_update_camera()


func _select_offset(offset: int) -> void:
	if _clips.is_empty():
		return
	var i := (_clips.find(_current) + offset + _clips.size()) % _clips.size()
	_play(_clips[i])
	var button := _clip_box.get_node_or_null(NodePath(_clips[i])) as Control
	if button != null:
		_clip_scroll.ensure_control_visible(button)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= mm.relative.x * 0.008
			_pitch += mm.relative.y * 0.008
			_update_camera()
		elif mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var b := _cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0015
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.9
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist /= 0.9
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE: _toggle_pause()
			KEY_LEFT: _step(-1)
			KEY_RIGHT: _step(1)
			KEY_UP: _select_offset(-1)
			KEY_DOWN: _select_offset(1)
			KEY_F:
				_target = Vector3(0, 1.0, 0)
				_dist = 4.2
				_update_camera()
			KEY_V: _next_view()
			KEY_L: _loop_btn.button_pressed = not _loop_btn.button_pressed


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(340, 0)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var title := Label.new()
	title.text = "Klassen-Animationen"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)

	_class_list = OptionButton.new()
	_class_list.item_selected.connect(func(_i: int) -> void: _load_class())
	v.add_child(_class_list)

	_mode_list = OptionButton.new()
	_mode_list.add_item("Ganzer Clip (gespeichert)", Mode.STORED)
	_mode_list.add_item("Wie im Spiel (Ausschnitt)", Mode.GAME)
	_mode_list.add_item("Original-FBX (mit Root Motion)", Mode.RAW)
	_mode_list.select(_mode)
	_mode_list.item_selected.connect(func(i: int) -> void:
		_mode = i as Mode
		if _current != "":
			_play(_current))
	v.add_child(_mode_list)

	_clip_scroll = ScrollContainer.new()
	_clip_scroll.custom_minimum_size = Vector2(0, 380)
	_clip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_clip_scroll)
	_clip_box = VBoxContainer.new()
	_clip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip_scroll.add_child(_clip_box)

	var row := HBoxContainer.new()
	v.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "Pause"
	_play_btn.custom_minimum_size = Vector2(70, 0)
	_play_btn.pressed.connect(_toggle_pause)
	row.add_child(_play_btn)
	var back := Button.new()
	back.text = "<"
	back.tooltip_text = "Einen Frame zurück (Pfeil links)"
	back.pressed.connect(func() -> void: _step(-1))
	row.add_child(back)
	var fwd := Button.new()
	fwd.text = ">"
	fwd.tooltip_text = "Einen Frame vor (Pfeil rechts)"
	fwd.pressed.connect(func() -> void: _step(1))
	row.add_child(fwd)
	_loop_btn = CheckBox.new()
	_loop_btn.text = "Loop"
	_loop_btn.button_pressed = _loop
	_loop_btn.toggled.connect(func(on: bool) -> void:
		_loop = on
		if _current != "":
			_play(_current))
	row.add_child(_loop_btn)
	_follow_btn = CheckBox.new()
	_follow_btn.text = "Folgen"
	_follow_btn.tooltip_text = "Kamera folgt der Hüfte (für Original-FBX mit Root Motion)"
	_follow_btn.toggled.connect(func(on: bool) -> void:
		_follow = on
		if not on:
			_target = Vector3(0, 1.0, 0)
			_update_camera())
	row.add_child(_follow_btn)

	_speed_label = Label.new()
	_speed_label.text = "Tempo: 1.00x"
	v.add_child(_speed_label)
	var speed := HSlider.new()
	speed.min_value = 0.05
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = 1.0
	speed.value_changed.connect(func(s: float) -> void:
		_speed = s
		_speed_label.text = "Tempo: %.2fx" % s
		if _player != null:
			_player.speed_scale = s)
	v.add_child(speed)

	var help := Label.new()
	help.text = "Links ziehen: drehen   Rechts/Mitte: verschieben\nRad: Zoom   F: zurücksetzen   V: Ansicht\nHoch/Runter: Clip   Leertaste: Play/Pause\nPfeile links/rechts: Frame   L: Loop"
	help.modulate = Color(1, 1, 1, 0.6)
	help.add_theme_font_size_override("font_size", 12)
	v.add_child(help)

	# clip info, top right
	var info_panel := PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -340.0
	info_panel.offset_right = -12.0
	info_panel.offset_top = 12.0
	layer.add_child(info_panel)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(320, 0)
	info_panel.add_child(_info_label)

	# timeline across the bottom
	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 370.0
	bottom.offset_right = -12.0
	bottom.offset_top = -86.0
	bottom.offset_bottom = -12.0
	layer.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_time_label = Label.new()
	bv.add_child(_time_label)
	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0, 30)
	_timeline.mouse_filter = Control.MOUSE_FILTER_STOP
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_on_timeline_input)
	bv.add_child(_timeline)
	var legend := Label.new()
	legend.text = "blau: im Spiel gespielter Ausschnitt   rot: gemessener Treffer   gelb: Stufen-Schnitt der Kette   weiß: Abspielposition"
	legend.modulate = Color(1, 1, 1, 0.6)
	legend.add_theme_font_size_override("font_size", 12)
	bv.add_child(legend)
	_no_focus(layer)


## Keyboard shortcuts belong to the viewer: a clicked button keeping focus would take Space,
## the arrows and Up/Down for itself.
func _no_focus(root: Node) -> void:
	for node in root.find_children("*", "Control", true, false):
		(node as Control).focus_mode = Control.FOCUS_NONE


func _rebuild_clip_buttons() -> void:
	for c in _clip_box.get_children():
		_clip_box.remove_child(c)  # free the name right away; new buttons reuse it
		c.queue_free()
	for clip in _clips:
		var b := Button.new()
		b.name = clip
		var purpose := String(PURPOSE.get(clip, ""))
		b.text = clip if purpose == "" else "%s  -  %s" % [clip, purpose]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _play(clip))
		_clip_box.add_child(b)
