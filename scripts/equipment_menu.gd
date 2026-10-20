extends CanvasLayer
## The equipment screen (I): everything the team has found, and what this player wears.
##
## Equipment is not bought in the skill tree - it drops from bosses and belongs to the team
## (RunState.equipment_unlocked). This is where a player looks through what has been found
## and puts pieces on or takes them off, which is a personal choice (Player.equipped_items),
## so two players can wear different things from the same stash.
##
## Pieces nobody has found yet are still listed, greyed out with the boss that drops them:
## knowing that the red boss carries the boots is what makes the red lane worth a detour.
##
## Built in code, like MainMenu and SettingsMenu. Added by the HUD, so it exists wherever a
## run does and nowhere else. Deliberately no `class_name` - see scripts/icon_style.gd.

const EquipmentDatabase := preload("res://scripts/equipment_database.gd")
const IconStyle := preload("res://scripts/icon_style.gd")
const InputHint := preload("res://scripts/input_hint.gd")

## Found pieces only, as icon tiles; the one under the mouse or the gamepad is described below.
const TILE_SIZE := Vector2(72.0, 72.0)
const ICON_SIZE := 60.0
const GOLD := Color(1.0, 0.85, 0.35)

var _root: Control
var _grid: GridContainer
var _summary: Label
var _debug_button: Button
## id -> {panel, icon, name, status}, so a refresh restyles instead of rebuilding.
var _cards: Dictionary = {}
var _detail: Control
var _detail_name: Label
var _detail_desc: Label
var _detail_status: Label
var _empty: Label
var _shown_item: String = ""


func _ready() -> void:
	layer = 110
	visible = false
	_build()
	SignalBus.equipment_unlocked_changed.connect(func(_item: String) -> void: _refresh())
	SignalBus.equipment_changed.connect(func(_player: Node) -> void: _refresh())


func _input(event: InputEvent) -> void:
	# On a gamepad this opens from the L3 wheel (ActionWheel), which sends the action itself;
	# B and Start close it.
	var toggle: bool = event.is_action_pressed("equipment")
	if toggle or (visible and event.is_action_pressed("ui_cancel")):
		# Not over another menu: the skill tree and the settings each own the screen while
		# open, and the skill tree moves its selection with the same D-pad.
		if not visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		set_open(not visible)
		get_viewport().set_input_as_handled()


## Opening and closing in one place, the same way SkillTree.set_open does it - both have to
## leave the mouse the way the game needs it, and tell the HUD to step aside.
func set_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	SignalBus.menu_opened.emit("equipment", open)
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
		# Somewhere for a gamepad to start from; A then puts that piece on.
		for item_id: String in EquipmentDatabase.ORDER:
			var tile: Control = _cards[item_id]["panel"]
			if tile.visible:
				tile.grab_focus()
				break
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.022, 0.028, 0.95)
	_root.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.14
	panel.anchor_bottom = 0.14
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.045, 1.0)
	style.border_color = Color(0.72, 0.62, 0.36, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	CloseButton.attach(_root, panel, func() -> void: set_open(false))

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	column.add_child(_summary)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(centre)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	centre.add_child(_grid)

	for item_id: String in EquipmentDatabase.ORDER:
		_grid.add_child(_build_card(item_id))

	_empty = Label.new()
	_empty.text = "Nothing found yet - bosses drop equipment for the whole team."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	column.add_child(_empty)

	# The piece under the mouse (or the gamepad), described.
	var detail := PanelContainer.new()
	var detail_box := StyleBoxFlat.new()
	detail_box.bg_color = Color(0.05, 0.055, 0.07, 1.0)
	detail_box.border_color = Color(0.3, 0.32, 0.38)
	detail_box.set_border_width_all(1)
	detail_box.set_corner_radius_all(6)
	for side: String in ["left", "right", "top", "bottom"]:
		detail_box.set("content_margin_" + side, 10.0)
	detail.add_theme_stylebox_override("panel", detail_box)
	detail.custom_minimum_size = Vector2(0.0, 92.0)
	column.add_child(detail)
	_detail = detail
	var detail_column := VBoxContainer.new()
	detail.add_child(detail_column)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 17)
	_detail_name.add_theme_color_override("font_color", GOLD)
	detail_column.add_child(_detail_name)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 13)
	_detail_desc.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	detail_column.add_child(_detail_desc)
	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 12)
	detail_column.add_child(_detail_status)

	# A way to try the pieces on without farming bosses for them, for whoever is testing.
	# Only on a machine that may unlock anything - the server - and only in debug builds.
	_debug_button = Button.new()
	_debug_button.text = "Unlock all (debug)"
	_debug_button.custom_minimum_size = Vector2(0.0, 32.0)
	_debug_button.pressed.connect(func() -> void:
		for item_id: String in EquipmentDatabase.ORDER:
			RunState.unlock_equipment(item_id))
	column.add_child(_debug_button)


func _build_card(item_id: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = TILE_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Focusable, so a gamepad can walk the grid; A on the focused card is the click.
	card.focus_mode = Control.FOCUS_ALL
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle(item_id)
		elif event.is_action_pressed("ui_accept"):
			_toggle(item_id)
			card.accept_event())
	card.focus_entered.connect(func() -> void:
		_shown_item = item_id
		_refresh())
	card.mouse_entered.connect(func() -> void:
		_shown_item = item_id
		_refresh())
	card.focus_exited.connect(func() -> void: _refresh())

	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = EquipmentDatabase.icon(item_id)
	# Round, like every other passive: equipment is always on and never goes on the bar.
	icon.material = IconStyle.circle_material()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	_cards[item_id] = {"panel": card, "icon": icon}
	return card


func _toggle(item_id: String) -> void:
	var player: Node = PlayerRegistry.get_local()
	if player == null or not player.has_method("set_equipped"):
		return
	if not RunState.is_equipment_unlocked(item_id):
		return
	var wear: bool = not bool(player.is_equipped(item_id))
	if player.set_equipped(item_id, wear):
		SoundBank.play(&"skill_unlock")


func _refresh() -> void:
	if not visible:
		return
	var player: Node = PlayerRegistry.get_local()
	var found: int = 0
	var worn: int = 0
	for item_id: String in EquipmentDatabase.ORDER:
		var unlocked: bool = RunState.is_equipment_unlocked(item_id)
		var equipped: bool = player != null and player.has_method("is_equipped") and bool(player.is_equipped(item_id))
		if unlocked:
			found += 1
		if equipped:
			worn += 1
		_style_card(item_id, unlocked, equipped)
		(_cards[item_id]["panel"] as Control).visible = unlocked
	if _shown_item == "" or not RunState.is_equipment_unlocked(_shown_item):
		_shown_item = ""
		for item_id: String in EquipmentDatabase.ORDER:
			if RunState.is_equipment_unlocked(item_id):
				_shown_item = item_id
				break
	_empty.visible = found == 0
	_show_detail(player)

	var limit: int = GameSettings.equipment_max_equipped
	var worn_text: String = ("%d/%d worn" % [worn, limit]) if limit > 0 else ("%d worn" % worn)
	_summary.text = "%d of %d found, %s" % [found, EquipmentDatabase.ORDER.size(), worn_text]
	_debug_button.visible = GameSettings.debug_mode and Net.is_server() and found < EquipmentDatabase.ORDER.size()


func _show_detail(player: Node) -> void:
	var item_id: String = _shown_item
	_detail.visible = item_id != ""
	if item_id == "":
		return
	var equipped: bool = player != null and player.has_method("is_equipped") and bool(player.is_equipped(item_id))
	var action: String = InputHint.pad("bottom") if InputHint.gamepad else "click"
	_detail_name.text = EquipmentDatabase.display_name(item_id)
	_detail_desc.text = EquipmentDatabase.description(item_id)
	_detail_status.text = ("Equipped - %s to take off" % action) if equipped else ("Found - %s to equip" % action)
	_detail_status.add_theme_color_override("font_color", GOLD if equipped else Color(0.6, 0.9, 0.62))


func _style_card(item_id: String, unlocked: bool, equipped: bool) -> void:
	var card: Dictionary = _cards[item_id]
	var panel: PanelContainer = card["panel"]
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	for side: String in ["left", "right", "top", "bottom"]:
		box.set("content_margin_" + side, 6.0)
	if equipped:
		box.bg_color = Color(0.13, 0.11, 0.05, 1.0)
		box.border_color = GOLD
	else:
		box.bg_color = Color(0.06, 0.07, 0.09, 1.0)
		box.border_color = Color(0.7, 0.72, 0.8) if item_id == _shown_item else Color(0.38, 0.42, 0.5)
	# The card a gamepad is on. A PanelContainer draws no focus ring of its own.
	if panel.has_focus():
		box.border_color = Color(1.0, 1.0, 1.0)
		box.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", box)
	(card["icon"] as TextureRect).modulate = Color.WHITE if unlocked else Color(0.3, 0.31, 0.34)
