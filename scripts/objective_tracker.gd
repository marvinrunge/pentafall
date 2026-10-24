class_name ObjectiveTracker
extends PanelContainer
## The first-steps checklist above the minimap (docs/ONBOARDING_PLAN.md): the next one or two
## objectives of ObjectiveDatabase this profile has not finished yet, each with a line on how.
##
## A checklist, not an announcement: nothing goes on the banner or into the log. A finished one
## ticks and turns green for a moment, then the next slides up into its place. Everything is
## this machine's own - what is done is kept in UserSettings, per profile, and only the local
## player's own actions tick it (SignalBus.objective_progress).

## How many open objectives are shown at once.
const SHOWN := 2
## How long a finished one stays up, ticked, before the next takes its place.
const TICK_SECONDS := 1.4
const TITLE_COLOR := Color(1.0, 0.92, 0.7)
const HINT_COLOR := Color(0.78, 0.8, 0.86)
const DONE_COLOR := Color(0.55, 1.0, 0.6)
const WIDTH := 300.0

## What it sits above - the HUD's minimap frame. Null in a test, which places it itself.
var anchor: Control = null
## Whether the run has somebody else in it, for the multiplayer-only objectives. A test sets it.
var multiplayer_run: Callable = func() -> bool: return Net.is_active() and PlayerRegistry.players.size() > 1
## Whether a menu is up over the game, which puts the list away like the rest of the HUD. The
## HUD hands in its own; it is not one of the HUD's GAMEPLAY_HUD_PATHS because this list shows
## and hides itself, and would come back on top of the base screen the moment a myr built there
## ticked it.
var menus_open: Callable = func() -> bool: return false

## Whether there is anything to show and the player wants it shown.
var _wanted: bool = false

var _done: Dictionary = {}
## Finished objectives still up with their tick, id -> true.
var _ticking: Dictionary = {}
var _rows: VBoxContainer
var _hud_scale: float = 1.0
var _shown_ids: Array[String] = []
var _hint_labels: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", style)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	_load_done()
	SignalBus.objective_progress.connect(complete)
	# Somebody joining is what brings the multiplayer-only ones in.
	SignalBus.players_changed.connect(func(_count: int) -> void: _rebuild())
	UserSettings.changed.connect(func(key: StringName) -> void:
		if key == &"objectives_done":
			_load_done()
			_rebuild()
		elif key == &"show_objectives":
			_rebuild())
	_rebuild()


func set_hud_scale(value: float) -> void:
	_hud_scale = value
	if is_inside_tree():
		_rebuild()


func _process(_delta: float) -> void:
	# The keys in the hints follow the device in use - a pad picked up mid-run renames them.
	for objective_id: String in _hint_labels:
		var label: Label = _hint_labels[objective_id]
		label.text = ObjectiveDatabase.hint_for(_objective(objective_id))
	visible = _wanted and not bool(menus_open.call())
	if anchor != null and visible:
		var frame: Rect2 = anchor.get_global_rect()
		var margin: float = float(anchor.get_theme_constant("margin_right")) if anchor is MarginContainer else 0.0
		global_position = Vector2(frame.end.x - margin - size.x, frame.position.y - size.y - 8.0 * _hud_scale)


## The objectives shown right now, in order - open ones and any still up with their tick.
func shown_ids() -> Array[String]:
	return _shown_ids.duplicate()


func is_done(objective_id: String) -> bool:
	return _done.has(objective_id)


## The local player did what `objective_id` asks. Kept for good, whether or not it was shown
## yet - doing the fourth step first is still doing it.
func complete(objective_id: String) -> void:
	if _done.has(objective_id) or not ObjectiveDatabase.has_objective(objective_id):
		return
	var was_shown: bool = _shown_ids.has(objective_id)
	_done[objective_id] = true
	if was_shown:
		_ticking[objective_id] = true
	_save_done()
	if was_shown:
		if is_inside_tree():
			get_tree().create_timer(TICK_SECONDS).timeout.connect(func() -> void:
				_ticking.erase(objective_id)
				_rebuild())
	_rebuild()


func _rebuild() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	_hint_labels.clear()
	_shown_ids.clear()
	var open: int = 0
	for objective: Dictionary in ObjectiveDatabase.OBJECTIVES:
		var objective_id: String = String(objective["id"])
		var ticking: bool = _ticking.has(objective_id)
		if _done.has(objective_id) and not ticking:
			continue
		if bool(objective.get("multiplayer_only", false)) and not bool(multiplayer_run.call()):
			continue
		if not ticking:
			if open >= SHOWN:
				continue
			open += 1
		_shown_ids.append(objective_id)
		_rows.add_child(_row(objective, ticking))
	_wanted = UserSettings.show_objectives and not _shown_ids.is_empty()
	visible = _wanted and not bool(menus_open.call())
	custom_minimum_size = Vector2(WIDTH * _hud_scale, 0.0)
	reset_size()


func _row(objective: Dictionary, ticked: bool) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.text = ("✔  " if ticked else "◇  ") + String(objective["text"])
	title.add_theme_font_size_override("font_size", int(round(17.0 * _hud_scale)))
	title.add_theme_color_override("font_color", DONE_COLOR if ticked else TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	if not ticked:
		var hint := Label.new()
		hint.text = ObjectiveDatabase.hint_for(objective)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", int(round(13.0 * _hud_scale)))
		hint.add_theme_color_override("font_color", HINT_COLOR)
		hint.add_theme_color_override("font_outline_color", Color.BLACK)
		hint.add_theme_constant_override("outline_size", 3)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hint)
		_hint_labels[String(objective["id"])] = hint
	return box


func _objective(objective_id: String) -> Dictionary:
	for objective: Dictionary in ObjectiveDatabase.OBJECTIVES:
		if String(objective["id"]) == objective_id:
			return objective
	return {}


func _load_done() -> void:
	_done.clear()
	for objective_id: String in UserSettings.objectives_done.split(",", false):
		_done[objective_id.strip_edges()] = true


func _save_done() -> void:
	var ids: PackedStringArray = PackedStringArray()
	for objective: Dictionary in ObjectiveDatabase.OBJECTIVES:
		if _done.has(String(objective["id"])):
			ids.append(String(objective["id"]))
	UserSettings.set_value(&"objectives_done", ",".join(ids))
