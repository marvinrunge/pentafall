extends Control
class_name BaseUI
## The base screen at the crystal: building, levelling, naming and assigning the myrs, the two
## guards, and the Graveyard (docs/MYR_GUARDS_PLAN.md).
##
## One card per myr, stacked: its portrait framed in its lane's colour, its name, kind, level and
## health, what it has done for the team, and its lane - the lane it works lit up, not greyed out
## as if it were the one choice that was unavailable. The five wells' occupancy is said once, at
## the top, rather than on every row. Built in code: the layout follows the roster, and nothing
## about it is worth authoring in a .tscn.
##
## The cards are rebuilt when the roster changes - a myr built, levelled, sent elsewhere, killed
## or returned - and otherwise only refreshed in place, so a name being typed is never thrown
## away by a delivery arriving.

const IconStyle := preload("res://scripts/icon_style.gd")
const MYR_PORTRAIT: Texture2D = preload("res://assets/icons/upkeep-myr.png")

## Lane order, as the icon ids of their mana symbols and as the colour names; the indices are
## MainController.mana_sources' own order, so this cannot drift from the lanes.
const LANE_COLORS: Array[String] = ["white", "blue", "black", "red", "green"]
const LANE_NAMES: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const AUTO_ASSIGN_LABELS: Dictionary = {
	"fewest": "Well with the fewest myrs",
	"most": "Well with the most myrs",
	"manual": "Nowhere - I assign them",
}
const GOLD := Color(0.9, 0.67, 0.2)
const TEXT_DIM := Color(0.7, 0.72, 0.78)
const PANEL_BG := Color(0.04, 0.045, 0.055, 0.97)
const CARD_BG := Color(0.075, 0.08, 0.1, 0.96)
const NO_LANE_TINT := Color(0.45, 0.47, 0.52)
const DEAD_COLOR := Color(0.95, 0.45, 0.4)
## How often the cards' health and stats are refreshed in place, seconds.
const LIVE_INTERVAL := 0.25
const PANEL_WIDTH := 860.0
const PORTRAIT_SIZE := 60.0

var main_controller: Node3D
var build_btn: Button
var _enforcer_btn: Button
var _lodestone_btn: Button
## Where new worker myrs go by themselves (RunState.myr_auto_assign).
var _auto_assign_option: OptionButton
var _graveyard_box: VBoxContainer
var _workers_box: VBoxContainer
var _guards_box: VBoxContainer
var _scroll: ScrollContainer
var _counts_label: Label
var _pool_labels: Array[Label] = []
var _lane_counts: Array[Label] = []
var _lane_guards: Array[Label] = []
## Per live card: the myr and the parts refreshed in place.
var _cards: Array[Dictionary] = []
var _roster_key: String = ""
var _live_timer: float = 0.0


func _ready() -> void:
	hide()
	_build_ui()
	SignalBus.graveyard_changed.connect(func() -> void:
		if visible:
			refresh_ui())
	SignalBus.mana_changed.connect(func(_pool: Dictionary) -> void:
		if visible:
			_refresh_affordability())


func open(main_ref: Node3D) -> void:
	main_controller = main_ref
	var was_open: bool = visible
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_ui()
	build_btn.grab_focus()
	# The gameplay HUD steps aside, as it does for the skill tree - the hotbar sat over the
	# Graveyard and the mission banner over the controls.
	if not was_open:
		SignalBus.menu_opened.emit("base", true)


func close() -> void:
	if not visible:
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SignalBus.menu_opened.emit("base", false)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or main_controller == null:
		return
	_live_timer -= delta
	if _live_timer > 0.0:
		return
	_live_timer = LIVE_INTERVAL
	if _current_roster_key() != _roster_key:
		refresh_ui()
		return
	for card: Dictionary in _cards:
		var myr: Myr = card["myr"]
		if not is_instance_valid(myr):
			continue
		_set_health(card["health"], myr)
		(card["stats"] as Label).text = _stats_text(myr.record())


# --- building the panel --------------------------------------------------------------

func _build_ui() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, GOLD, 2, 8))
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	# --- the title, the pool, the way out --------------------------------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	rows.add_child(header)
	var title := Label.new()
	title.text = "BASE"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	header.add_child(title)
	var pool := HBoxContainer.new()
	pool.add_theme_constant_override("separation", 10)
	pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(pool)
	for lane: int in LANE_COLORS.size():
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.add_child(_icon(SpellDatabase.get_icon(LANE_COLORS[lane]), 20.0))
		var amount := Label.new()
		amount.add_theme_font_size_override("font_size", 16)
		amount.add_theme_color_override("font_color", GameSettings.lane_tint(LANE_NAMES[lane]).lightened(0.25))
		chip.add_child(amount)
		pool.add_child(chip)
		_pool_labels.append(amount)
	header.add_child(CloseButton.build(close))

	# --- the five wells, once ---------------------------------------------------------
	var lanes := HBoxContainer.new()
	lanes.add_theme_constant_override("separation", 8)
	rows.add_child(lanes)
	for lane: int in LANE_COLORS.size():
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", _box(CARD_BG, GameSettings.lane_tint(LANE_NAMES[lane]).darkened(0.2), 1, 6, 6))
		var tile_row := HBoxContainer.new()
		tile_row.add_theme_constant_override("separation", 6)
		tile.add_child(tile_row)
		tile_row.add_child(_icon(SpellDatabase.get_icon(LANE_COLORS[lane]), 26.0))
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		tile_row.add_child(text)
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 15)
		text.add_child(count)
		var guard := Label.new()
		guard.add_theme_font_size_override("font_size", 12)
		text.add_child(guard)
		tile.tooltip_text = "The %s well: workers harvesting it, and its guard" % LANE_NAMES[lane].to_lower()
		lanes.add_child(tile)
		_lane_counts.append(count)
		_lane_guards.append(guard)

	# --- building -----------------------------------------------------------------------
	var builds := HBoxContainer.new()
	builds.add_theme_constant_override("separation", 10)
	rows.add_child(builds)
	build_btn = _build_button("Myr", Color.WHITE, "A worker: harvests the well it is sent to and carries the mana home.")
	build_btn.pressed.connect(_on_build_pressed)
	builds.add_child(build_btn)
	_enforcer_btn = _build_button(Myr.ROLE_NAMES[Myr.ROLE_ENFORCER], Myr.ROLE_TINTS[Myr.ROLE_ENFORCER],
		"A guard that holds a lane's well and draws attacks off the workers there. Costs 1 less for every worker myr.")
	_enforcer_btn.pressed.connect(_on_build_guard_pressed.bind(Myr.ROLE_ENFORCER))
	builds.add_child(_enforcer_btn)
	_lodestone_btn = _build_button(Myr.ROLE_NAMES[Myr.ROLE_LODESTONE], Myr.ROLE_TINTS[Myr.ROLE_LODESTONE],
		"A guard that fights for a lane's well, harder for every worker harvesting beside it.")
	_lodestone_btn.pressed.connect(_on_build_guard_pressed.bind(Myr.ROLE_LODESTONE))
	builds.add_child(_lodestone_btn)

	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 10)
	rows.add_child(settings)
	_counts_label = Label.new()
	_counts_label.add_theme_color_override("font_color", TEXT_DIM)
	_counts_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(_counts_label)
	var go_to := Label.new()
	go_to.text = "New myrs go to"
	go_to.add_theme_color_override("font_color", TEXT_DIM)
	settings.add_child(go_to)
	_auto_assign_option = OptionButton.new()
	_auto_assign_option.name = "AutoAssignOption"
	_auto_assign_option.custom_minimum_size = Vector2(240.0, 0.0)
	for mode: String in RunState.MYR_AUTO_ASSIGN_MODES:
		_auto_assign_option.add_item(String(AUTO_ASSIGN_LABELS[mode]))
		_auto_assign_option.set_item_metadata(_auto_assign_option.item_count - 1, mode)
	_auto_assign_option.tooltip_text = "Where a newly built worker myr goes by itself. Any myr can be sent elsewhere on its card at any time."
	_auto_assign_option.item_selected.connect(func(index: int) -> void:
		main_controller.request_set_myr_auto_assign(String(_auto_assign_option.get_item_metadata(index))))
	settings.add_child(_auto_assign_option)

	# --- the roster ---------------------------------------------------------------------
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_scroll)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 8)
	_scroll.add_child(lists)
	_workers_box = VBoxContainer.new()
	_workers_box.name = "Workers"
	_workers_box.add_theme_constant_override("separation", 6)
	lists.add_child(_workers_box)
	_guards_box = VBoxContainer.new()
	_guards_box.name = "Guards"
	_guards_box.add_theme_constant_override("separation", 6)
	lists.add_child(_guards_box)
	_graveyard_box = VBoxContainer.new()
	_graveyard_box.name = "GraveyardContainer"
	_graveyard_box.add_theme_constant_override("separation", 6)
	lists.add_child(_graveyard_box)


func _build_button(label: String, tint: Color, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label
	button.icon = MYR_PORTRAIT
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_constant_override("h_separation", 10)
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, tint)
	button.add_theme_color_override("icon_disabled_color", Color(tint, 0.35))
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = tooltip
	return button


# --- filling it ----------------------------------------------------------------------

func refresh_ui() -> void:
	if not main_controller:
		return
	_roster_key = _current_roster_key()
	_cards.clear()
	for box: VBoxContainer in [_workers_box, _guards_box, _graveyard_box]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()

	var workers: Array[Myr] = []
	var guards: Array[Myr] = []
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		var myr: Myr = node as Myr
		if myr == null or myr.is_dying:
			continue
		if myr.is_guard():
			guards.append(myr)
		else:
			workers.append(myr)

	_section(_workers_box, "WORKERS", "" if not workers.is_empty() else "No myrs yet - build one above, and it goes to work by itself.")
	for index: int in workers.size():
		_workers_box.add_child(_myr_card(workers[index], index + 1))
	if not guards.is_empty():
		_section(_guards_box, "GUARDS", "")
		for index: int in guards.size():
			_guards_box.add_child(_myr_card(guards[index], index + 1))
	if not RunState.graveyard.is_empty():
		_section(_graveyard_box, "GRAVEYARD", "Back at their level, for a third of what went into them.")
		for record: Dictionary in RunState.graveyard:
			_graveyard_box.add_child(_grave_card(record))

	var mode_index: int = RunState.MYR_AUTO_ASSIGN_MODES.find(RunState.myr_auto_assign)
	if mode_index >= 0 and _auto_assign_option.selected != mode_index:
		_auto_assign_option.select(mode_index)
	_refresh_lanes()
	_refresh_affordability()
	_fit_scroll(workers.size() + guards.size() + RunState.graveyard.size())


## What the cards are built from - a change here rebuilds them. Names are not in it: a rebuild
## while a name is being typed would take the field away from under the keyboard.
func _current_roster_key() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		var myr: Myr = node as Myr
		if myr != null:
			parts.append("%d:%s:%d:%d:%s" % [myr.record_id, myr.role, myr.lane_index, myr.level, myr.is_dying])
	parts.append("g%d" % RunState.graveyard.size())
	parts.append(RunState.myr_auto_assign)
	return "|".join(parts)


## The prices and what can be afforded, which a delivery or a kill can change at any moment.
func _refresh_affordability() -> void:
	if main_controller == null:
		return
	for lane: int in _pool_labels.size():
		_pool_labels[lane].text = str(int(RunState.mana_pool.get(LANE_NAMES[lane], 0)))
	var mana: int = RunState.total_mana()
	var workers: int = main_controller.myr_count()
	var guards: int = main_controller.guard_count()
	var lanes: int = main_controller.mana_sources.size()
	_counts_label.text = "Workers %d / %d     Guards %d / %d" % [workers, GameSettings.myr_max_count, guards, lanes]
	build_btn.text = "Myr   %d" % GameSettings.myr_mana_cost
	build_btn.disabled = workers >= GameSettings.myr_max_count or mana < GameSettings.myr_mana_cost
	if workers >= GameSettings.myr_max_count:
		build_btn.text = "Myr   (limit reached)"
	for pair: Array in [[_enforcer_btn, Myr.ROLE_ENFORCER], [_lodestone_btn, Myr.ROLE_LODESTONE]]:
		var button: Button = pair[0]
		var role: String = pair[1]
		var cost: int = main_controller.guard_cost(role)
		button.text = "%s   %d" % [Myr.ROLE_NAMES[role], cost]
		button.disabled = guards >= lanes or mana < cost
	for card: Dictionary in _cards:
		var myr: Myr = card["myr"]
		var level_btn: Button = card["level"]
		if not is_instance_valid(myr) or myr.level >= GameSettings.myr_max_level:
			continue
		level_btn.disabled = mana < GameSettings.myr_level_cost * (myr.level + 1)


func _refresh_lanes() -> void:
	for lane: int in _lane_counts.size():
		_lane_counts[lane].text = "%d / %d" % [main_controller.well_slot_count(lane), RunState.myr_well_slots()]
		var guard: Node3D = main_controller.lane_guard(lane)
		if guard != null:
			_lane_guards[lane].text = guard.role_name()
			_lane_guards[lane].add_theme_color_override("font_color", Myr.ROLE_TINTS.get(guard.role, Color.WHITE))
		else:
			_lane_guards[lane].text = "unguarded"
			_lane_guards[lane].add_theme_color_override("font_color", Color(TEXT_DIM, 0.6))


## Sized to what it holds, up to a share of the window, scrolling past that.
func _fit_scroll(cards: int) -> void:
	var wanted: float = float(cards) * 84.0 + 3.0 * 34.0
	var room: float = get_viewport_rect().size.y * 0.58
	_scroll.custom_minimum_size = Vector2(0.0, clampf(wanted, 90.0, room))


func _section(box: VBoxContainer, title: String, note: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", GOLD)
	row.add_child(label)
	if note != "":
		var hint := Label.new()
		hint.text = note
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", TEXT_DIM)
		row.add_child(hint)
	box.add_child(row)


# --- the cards -----------------------------------------------------------------------

func _myr_card(myr: Myr, index: int) -> Control:
	var lane_tint: Color = GameSettings.lane_tint(LANE_NAMES[myr.lane_index]) if myr.lane_index >= 0 else NO_LANE_TINT
	var card := _card_frame(lane_tint, 1.0)
	var row: HBoxContainer = card.get_child(0)

	row.add_child(_portrait(myr.role, lane_tint, false))

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(220.0, 0.0)
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	# Named, not numbered. A player who has bought four levels into one myr has a relationship
	# with it, and "Myr 3" is not a name for something you have invested in - it is also wrong
	# the moment an earlier myr dies and the numbering shifts.
	var name_field := LineEdit.new()
	name_field.placeholder_text = "%s %d" % [myr.role_name(), index]
	name_field.text = myr.display_name
	name_field.max_length = 18
	name_field.tooltip_text = "Name this myr"
	name_field.flat = true
	name_field.add_theme_font_size_override("font_size", 17)
	# Stored as it is typed rather than on submit: a lane button pressed next to it would
	# otherwise lose a name only committed on Enter.
	name_field.text_changed.connect(func(text: String) -> void: main_controller.request_myr_name(myr, text))
	info.add_child(name_field)
	var kind := HBoxContainer.new()
	kind.add_theme_constant_override("separation", 8)
	info.add_child(kind)
	var role_label := Label.new()
	role_label.text = "Worker" if not myr.is_guard() else myr.role_name()
	role_label.add_theme_font_size_override("font_size", 13)
	role_label.add_theme_color_override("font_color", Myr.ROLE_TINTS.get(myr.role, TEXT_DIM))
	kind.add_child(role_label)
	var pips := LevelPips.new()
	pips.level = myr.level
	pips.tooltip_text = "Level %d of %d" % [myr.level, GameSettings.myr_max_level]
	kind.add_child(pips)
	var health := ProgressBar.new()
	health.show_percentage = false
	health.custom_minimum_size = Vector2(200.0, 8.0)
	health.add_theme_stylebox_override("background", _box(Color(0.0, 0.0, 0.0, 0.6), Color(0, 0, 0, 0), 0, 3))
	info.add_child(health)
	_set_health(health, myr)

	var stats := Label.new()
	stats.name = "Stats"
	stats.custom_minimum_size = Vector2(150.0, 0.0)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_font_size_override("font_size", 14)
	stats.text = _stats_text(myr.record())
	row.add_child(stats)

	var level_btn := Button.new()
	level_btn.name = "LevelButton"
	level_btn.custom_minimum_size = Vector2(96.0, 44.0)
	if myr.level >= GameSettings.myr_max_level:
		level_btn.text = "Max level"
		level_btn.disabled = true
	else:
		var cost: int = GameSettings.myr_level_cost * (myr.level + 1)
		level_btn.text = "Level up\n%d" % cost
		level_btn.pressed.connect(_level_up.bind(myr, cost))
	if myr.is_guard():
		level_btn.tooltip_text = "%s, level %d: %d health, %d damage a blow" % [
			myr.role_name(), myr.level, int(myr.max_health), int(round(myr.guard_damage()))]
	else:
		level_btn.tooltip_text = "Level %d: %d health, carries %d mana per trip" % [
			myr.level, int(myr.max_health), myr.carry_amount()]
	row.add_child(level_btn)

	row.add_child(_lane_picker(myr))
	_cards.append({"myr": myr, "health": health, "stats": stats, "level": level_btn})
	return card


func _grave_card(record: Dictionary) -> Control:
	var lane: int = int(record.get("lane", -1))
	var role: String = String(record.get("role", Myr.ROLE_WORKER))
	var lane_tint: Color = GameSettings.lane_tint(LANE_NAMES[lane]) if lane >= 0 and lane < LANE_NAMES.size() else NO_LANE_TINT
	# Not faded as a whole: the portrait greys and the stripe darkens, but the Return button has
	# to read as the live button it is.
	var card := _card_frame(lane_tint.darkened(0.5), 1.0)
	var row: HBoxContainer = card.get_child(0)
	row.add_child(_portrait(role, lane_tint, true))

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(info)
	var shown_name: String = String(record.get("name", ""))
	if shown_name.strip_edges() == "":
		shown_name = String(Myr.ROLE_NAMES.get(role, "Myr"))
	var name_label := Label.new()
	name_label.text = shown_name
	name_label.add_theme_font_size_override("font_size", 17)
	info.add_child(name_label)
	var kind := HBoxContainer.new()
	kind.add_theme_constant_override("separation", 8)
	info.add_child(kind)
	var role_label := Label.new()
	role_label.text = ("Worker" if role == Myr.ROLE_WORKER else String(Myr.ROLE_NAMES.get(role, "Myr"))) + "  -  fallen"
	role_label.add_theme_font_size_override("font_size", 13)
	role_label.add_theme_color_override("font_color", DEAD_COLOR)
	kind.add_child(role_label)
	var pips := LevelPips.new()
	pips.level = int(record.get("level", 1))
	kind.add_child(pips)

	var stats := Label.new()
	stats.custom_minimum_size = Vector2(150.0, 0.0)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_font_size_override("font_size", 14)
	stats.text = _stats_text(record)
	row.add_child(stats)

	var cost: int = RunState.return_cost(record)
	var room: bool = main_controller.can_return_myr(record)
	var button := Button.new()
	button.name = "ReturnButton"
	button.text = "Return\n%d" % cost
	button.custom_minimum_size = Vector2(110.0, 44.0)
	button.disabled = not room or RunState.total_mana() < cost
	button.tooltip_text = "Back at level %d, to its old lane if it is free" % int(record.get("level", 1)) if room \
		else "No room: the myr limit is reached, or every lane has its guard"
	button.pressed.connect(_return.bind(int(record.get("id", 0))))
	row.add_child(button)
	return card


## A card: dark, with a stripe down its left edge in its lane's colour.
func _card_frame(stripe: Color, alpha: float) -> PanelContainer:
	var card := PanelContainer.new()
	var style := _box(CARD_BG, Color(stripe, 0.85), 1, 6, 8)
	style.border_width_left = 5
	card.add_theme_stylebox_override("panel", style)
	card.modulate = Color(1.0, 1.0, 1.0, alpha)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(row)
	return card


## The myr's portrait, in a frame of its lane's colour; a guard's lit in its own, a fallen one
## grey.
func _portrait(role: String, lane_tint: Color, fallen: bool) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.5), lane_tint, 2, 8, 2))
	var picture := _icon(MYR_PORTRAIT, PORTRAIT_SIZE)
	if fallen:
		picture.modulate = Color(0.45, 0.45, 0.5)
	elif Myr.ROLE_TINTS.has(role):
		# A guard is framed in its own colour as well as lit in it: the lane already has the
		# card's stripe, and a portrait tinted alone read as muddy rather than as a kind.
		picture.modulate = Color.WHITE.lerp(Myr.ROLE_TINTS[role], 0.35)
		frame.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.5), Myr.ROLE_TINTS[role], 2, 8, 2))
	frame.add_child(picture)
	return frame


## The five lanes as their mana symbols. The one the myr works is lit and framed in its colour;
## the others are there to press. A full well, or a lane another guard holds, cannot be.
func _lane_picker(myr: Myr) -> Control:
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 4)
	for lane: int in LANE_COLORS.size():
		var button := Button.new()
		button.icon = SpellDatabase.get_icon(LANE_COLORS[lane])
		button.expand_icon = true
		button.custom_minimum_size = Vector2(40.0, 40.0)
		var tint: Color = GameSettings.lane_tint(LANE_NAMES[lane])
		var current: bool = myr.lane_index == lane
		if current:
			var lit := _box(Color(tint, 0.35), tint.lightened(0.3), 3, 6, 4)
			for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
				button.add_theme_stylebox_override(state, lit)
			button.tooltip_text = "Works the %s well" % LANE_NAMES[lane].to_lower() if not myr.is_guard() \
				else "Guards the %s well" % LANE_NAMES[lane].to_lower()
			button.focus_mode = Control.FOCUS_NONE
		else:
			var full: bool
			if myr.is_guard():
				full = main_controller.lane_guard(lane) != null
				button.tooltip_text = "Guard the %s well" % LANE_NAMES[lane].to_lower() if not full \
					else "The %s well already has its guard" % LANE_NAMES[lane].to_lower()
			else:
				full = main_controller.well_slot_count(lane) >= RunState.myr_well_slots()
				button.tooltip_text = "Send it to the %s well" % LANE_NAMES[lane].to_lower() if not full \
					else "The %s well is full" % LANE_NAMES[lane].to_lower()
			button.disabled = full
			button.add_theme_color_override("icon_normal_color", Color(1.0, 1.0, 1.0, 0.75))
			button.add_theme_color_override("icon_disabled_color", Color(1.0, 1.0, 1.0, 0.2))
			button.pressed.connect(_assign.bind(myr, lane))
		picker.add_child(button)
	return picker


func _set_health(bar: ProgressBar, myr: Myr) -> void:
	bar.max_value = maxf(myr.max_health, 1.0)
	bar.value = myr.health
	var share: float = clampf(myr.health / maxf(myr.max_health, 1.0), 0.0, 1.0)
	var fill: Color = Color(0.9, 0.25, 0.2).lerp(Color(0.35, 0.85, 0.4), share)
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	if style == null or not bar.has_theme_stylebox_override("fill"):
		style = _box(fill, Color(0, 0, 0, 0), 0, 3)
		bar.add_theme_stylebox_override("fill", style)
	style.bg_color = fill
	bar.tooltip_text = "%d / %d health" % [int(myr.health), int(myr.max_health)]


## What a myr (or its record) has done for the team: mana home and trips for a worker, kills
## and saves for a guard, and how often it has died - the reason to protect this one.
static func _stats_text(record: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if String(record.get("role", Myr.ROLE_WORKER)) == Myr.ROLE_WORKER:
		lines.append("%d mana home" % int(record.get("mana_delivered", 0)))
		var trips: int = int(record.get("trips", 0))
		var fled: int = int(record.get("times_fled", 0))
		lines.append("%d trip%s  -  fled %d" % [trips, "" if trips == 1 else "s", fled])
	else:
		lines.append("%d kill%s" % [int(record.get("kills", 0)), "" if int(record.get("kills", 0)) == 1 else "s"])
		lines.append("%d attack%s taken on" % [int(record.get("intercepts", 0)), "" if int(record.get("intercepts", 0)) == 1 else "s"])
	var died: int = int(record.get("deaths", 0))
	if died > 0:
		lines.append("died %d time%s" % [died, "" if died == 1 else "s"])
	return "\n".join(lines)


func _icon(texture: Texture2D, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.material = IconStyle.rounded_material()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _box(fill: Color, border: Color, border_width: int, radius: int, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


# --- actions -------------------------------------------------------------------------

## Buys one level for `myr`. Spent and applied on the server, which is where the mana and
## the myr both live; a client's request is forwarded (MainController.request_myr_level).
func _level_up(myr: Node3D, _cost: int) -> void:
	if myr.level >= GameSettings.myr_max_level:
		return
	main_controller.request_myr_level(myr)
	SignalBus.objective_progress.emit("level_myr")
	_refresh_soon()


func _on_build_guard_pressed(role: String) -> void:
	main_controller.request_build_guard(role)
	SignalBus.objective_progress.emit("build_guard")
	_refresh_soon()


func _return(record_id: int) -> void:
	main_controller.request_return_myr(record_id)
	_refresh_soon()


func _on_build_pressed() -> void:
	main_controller.request_build_myr()
	SignalBus.objective_progress.emit("build_myr")
	_refresh_soon()


func _assign(myr: Node3D, lane: int) -> void:
	if main_controller:
		main_controller.request_myr_lane(myr, lane)
		SignalBus.objective_progress.emit("assign_myr")
		_refresh_soon()


## Now, and again once a client's request has made the round trip to the server and the
## result has replicated back.
func _refresh_soon() -> void:
	refresh_ui()
	if not Net.is_server():
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if visible:
				refresh_ui())


## A myr's level as five pips, the filled ones its level - read at a glance across the cards
## where "Lv 3" had to be read.
class LevelPips:
	extends Control

	var level: int = 1
	const RADIUS := 4.5
	const GAP := 4.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(GameSettings.myr_max_level * (RADIUS * 2.0 + GAP), RADIUS * 2.0 + 4.0)

	func _draw() -> void:
		for index: int in GameSettings.myr_max_level:
			var centre := Vector2(RADIUS + float(index) * (RADIUS * 2.0 + GAP), size.y * 0.5)
			if index < level:
				draw_circle(centre, RADIUS, BaseUI.GOLD)
			else:
				draw_arc(centre, RADIUS - 0.75, 0.0, TAU, 16, Color(BaseUI.GOLD, 0.45), 1.5, true)
