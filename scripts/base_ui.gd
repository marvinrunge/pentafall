extends Control
class_name BaseUI

@onready var myr_list_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/MyrListContainer
@onready var build_btn: Button = $Panel/MarginContainer/VBoxContainer/BuildButton

var main_controller: Node3D

## The two guards' build buttons (docs/MYR_GUARDS_PLAN.md), under the worker's, and the
## Graveyard's list at the bottom. Built once with the panel, like the close button.
var _enforcer_btn: Button
var _lodestone_btn: Button
var _graveyard_box: VBoxContainer
## Where new worker myrs go by themselves (RunState.myr_auto_assign).
var _auto_assign_option: OptionButton
const AUTO_ASSIGN_LABELS: Dictionary = {
	"fewest": "Well with the fewest myrs",
	"most": "Well with the most myrs",
	"manual": "Nowhere - I assign them",
}


func _ready() -> void:
	hide()
	build_btn.pressed.connect(_on_build_pressed)
	# Built once with the panel. It used to be built in open(), which meant the panel had
	# no way out until it had been opened - and then a fresh button every time after.
	_build_close_button()
	_build_guard_buttons()
	_build_auto_assign_row()
	_graveyard_box = VBoxContainer.new()
	_graveyard_box.name = "GraveyardContainer"
	_graveyard_box.add_theme_constant_override("separation", 6)
	myr_list_container.get_parent().add_child(_graveyard_box)
	SignalBus.graveyard_changed.connect(func() -> void:
		if visible:
			refresh_ui())


func _build_auto_assign_row() -> void:
	var row := HBoxContainer.new()
	row.name = "AutoAssignRow"
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "New myrs go to:"
	row.add_child(label)
	_auto_assign_option = OptionButton.new()
	_auto_assign_option.name = "AutoAssignOption"
	_auto_assign_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mode: String in RunState.MYR_AUTO_ASSIGN_MODES:
		_auto_assign_option.add_item(String(AUTO_ASSIGN_LABELS[mode]))
		_auto_assign_option.set_item_metadata(_auto_assign_option.item_count - 1, mode)
	_auto_assign_option.tooltip_text = "Where a newly built worker myr goes by itself. Any myr can be sent elsewhere below at any time."
	_auto_assign_option.item_selected.connect(func(index: int) -> void:
		main_controller.request_set_myr_auto_assign(String(_auto_assign_option.get_item_metadata(index))))
	row.add_child(_auto_assign_option)
	var parent: Node = build_btn.get_parent()
	parent.add_child(row)
	parent.move_child(row, parent.get_node("GuardButtons").get_index() + 1)


func _build_guard_buttons() -> void:
	var row := HBoxContainer.new()
	row.name = "GuardButtons"
	row.add_theme_constant_override("separation", 10)
	_enforcer_btn = Button.new()
	_enforcer_btn.custom_minimum_size = Vector2(0.0, 40.0)
	_enforcer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enforcer_btn.tooltip_text = "A guard that holds a lane's well and draws attacks off the workers there. Costs 1 less for every worker myr."
	_enforcer_btn.pressed.connect(_on_build_guard_pressed.bind(Myr.ROLE_ENFORCER))
	row.add_child(_enforcer_btn)
	_lodestone_btn = Button.new()
	_lodestone_btn.custom_minimum_size = Vector2(0.0, 40.0)
	_lodestone_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lodestone_btn.tooltip_text = "A guard that fights for a lane's well, harder for every worker harvesting beside it."
	_lodestone_btn.pressed.connect(_on_build_guard_pressed.bind(Myr.ROLE_LODESTONE))
	row.add_child(_lodestone_btn)
	var parent: Node = build_btn.get_parent()
	parent.add_child(row)
	parent.move_child(row, build_btn.get_index() + 1)


func open(main_ref: Node3D) -> void:
	main_controller = main_ref
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_ui()
	build_btn.grab_focus()

func close() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_close_button() -> void:
	CloseButton.attach(self, $Panel, close)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## Lane order, and the mana colour each one is. Used for the assignment icons; the indices
## are MainController.mana_sources' own order, so this cannot drift from the lanes.
const LANE_COLORS: Array[String] = ["white", "blue", "black", "red", "green"]


func refresh_ui() -> void:
	if not main_controller:
		return
		
	# Clear list
	for child in myr_list_container.get_children():
		child.queue_free()
		
	var active_myrs = get_tree().get_nodes_in_group("myrs")
	var workers: int = main_controller.myr_count()

	# The count is shown against the cap, not on its own: "Built: 10" tells the player
	# nothing about why the button stopped working.
	var at_cap: bool = workers >= GameSettings.myr_max_count
	build_btn.text = "Build Myr (Cost: %d Any Mana) - Built: %d/%d" % [
		GameSettings.myr_mana_cost, workers, GameSettings.myr_max_count]
	if at_cap:
		build_btn.text = "Myr Limit Reached (%d/%d)" % [workers, GameSettings.myr_max_count]
	build_btn.disabled = at_cap or RunState.total_mana() < GameSettings.myr_mana_cost

	var mode_index: int = RunState.MYR_AUTO_ASSIGN_MODES.find(RunState.myr_auto_assign)
	if mode_index >= 0 and _auto_assign_option.selected != mode_index:
		_auto_assign_option.select(mode_index)

	# One guard per lane, so the guards' cap is the lane count.
	var guards_full: bool = main_controller.guard_count() >= main_controller.mana_sources.size()
	for pair: Array in [[_enforcer_btn, Myr.ROLE_ENFORCER], [_lodestone_btn, Myr.ROLE_LODESTONE]]:
		var button: Button = pair[0]
		var role: String = pair[1]
		var cost: int = main_controller.guard_cost(role)
		button.text = "Build %s (%d)" % [Myr.ROLE_NAMES[role], cost]
		button.disabled = guards_full or RunState.total_mana() < cost

	# How full each well already is, shown on the lane buttons so "the well is full"
	# is visible before the click that would be refused.
	var slot_suffixes: Array[String] = []
	for lane: int in range(5):
		slot_suffixes.append(" %d/%d" % [main_controller.well_slot_count(lane), RunState.myr_well_slots()])
		
	# Create entries for each Myr
	for i in range(active_myrs.size()):
		var myr = active_myrs[i]
		var hbox = HBoxContainer.new()

		# Named, not numbered. A player who has bought four levels into one myr has a
		# relationship with it, and "Myr 3" is not a name for something you have invested
		# in - it is also wrong the moment an earlier myr dies and the numbering shifts.
		var name_field := LineEdit.new()
		name_field.custom_minimum_size = Vector2(120.0, 0.0)
		name_field.placeholder_text = "%s %d" % [myr.role_name(), i + 1]
		name_field.text = myr.display_name
		name_field.max_length = 18
		name_field.tooltip_text = "Name this myr"
		# Stored as it is typed rather than on submit: the list is rebuilt by any other
		# action in this panel, and a name only committed on Enter would be lost by
		# clicking a lane button next to it.
		name_field.text_changed.connect(func(text: String) -> void: main_controller.request_myr_name(myr, text))
		hbox.add_child(name_field)

		var level_btn := Button.new()
		level_btn.name = "LevelButton"
		var next_level: int = myr.level + 1
		var level_cost: int = GameSettings.myr_level_cost * next_level
		if myr.level >= GameSettings.myr_max_level:
			level_btn.text = "Lv %d MAX" % myr.level
			level_btn.disabled = true
		else:
			level_btn.text = "Lv %d  +%d" % [myr.level, level_cost]
			level_btn.disabled = RunState.total_mana() < level_cost
			level_btn.pressed.connect(_level_up.bind(myr, level_cost))
		if myr.is_guard():
			level_btn.tooltip_text = "%s, level %d: %d health, %d damage a blow" % [
				myr.role_name(), myr.level, int(myr.max_health), int(round(myr.guard_damage()))]
		else:
			level_btn.tooltip_text = "Level %d: %d health, carries %d mana per trip" % [
				myr.level,
				int(myr.max_health),
				myr.carry_amount()]
		level_btn.custom_minimum_size = Vector2(88.0, 34.0)
		hbox.add_child(level_btn)

		# What it has done for the team - the reason to protect this one rather than any one.
		var stats := Label.new()
		stats.name = "Stats"
		stats.custom_minimum_size = Vector2(150.0, 0.0)
		stats.text = _stats_text(myr.record())
		hbox.add_child(stats)

		var current_lane = myr.lane_index

		# One button per lane, drawn with the same mana symbol the HUD and the skill tree
		# use. A row of letters made the player translate "U" into blue every time they
		# assigned a myr, when the icon is the thing they already recognise everywhere else.
		# The slot count stays as text beside it - that is a number, and a number has no
		# icon.
		for lane: int in range(LANE_COLORS.size()):
			var button := Button.new()
			button.icon = SpellDatabase.get_icon(LANE_COLORS[lane])
			# Scaled to the button rather than drawn at its own size, which for these
			# symbols is far larger than a row of five of them can be.
			button.expand_icon = true
			button.custom_minimum_size = Vector2(64.0, 34.0)
			if myr.is_guard():
				# A lane has room for one guard; the button says whose it is.
				var holder: Node3D = main_controller.lane_guard(lane)
				button.text = "Guard" if holder == myr else ("Taken" if holder != null else "")
				button.tooltip_text = "Guard the %s well" % LANE_COLORS[lane]
				button.disabled = holder != null
			else:
				button.text = slot_suffixes[lane].strip_edges()
				button.tooltip_text = "Send this myr to the %s well" % LANE_COLORS[lane]
				button.disabled = current_lane == lane
			button.pressed.connect(_assign.bind(myr, lane))
			hbox.add_child(button)

		myr_list_container.add_child(hbox)

	_refresh_graveyard()


## The Graveyard: every myr that has died and not been returned, with what returning it costs.
## A levelled myr is not lost to one bad wave - it comes back at its level for a third of what
## went into it.
func _refresh_graveyard() -> void:
	for child: Node in _graveyard_box.get_children():
		child.queue_free()
	if RunState.graveyard.is_empty():
		return
	_graveyard_box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Graveyard"
	title.add_theme_font_size_override("font_size", 20)
	_graveyard_box.add_child(title)
	for record: Dictionary in RunState.graveyard:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		var shown_name: String = String(record.get("name", ""))
		if shown_name.strip_edges() == "":
			shown_name = String(Myr.ROLE_NAMES.get(String(record.get("role", Myr.ROLE_WORKER)), "Myr"))
		name_label.text = "%s  -  Lv %d" % [shown_name, int(record.get("level", 1))]
		name_label.custom_minimum_size = Vector2(200.0, 0.0)
		row.add_child(name_label)
		var stats := Label.new()
		stats.text = _stats_text(record)
		stats.custom_minimum_size = Vector2(150.0, 0.0)
		row.add_child(stats)
		var cost: int = RunState.return_cost(record)
		var button := Button.new()
		button.name = "ReturnButton"
		button.text = "Return (%d)" % cost
		button.custom_minimum_size = Vector2(120.0, 34.0)
		var room: bool = main_controller.can_return_myr(record)
		button.disabled = not room or RunState.total_mana() < cost
		button.tooltip_text = "Back at level %d, to its old lane if it is free" % int(record.get("level", 1)) if room \
			else "No room: the myr limit is reached, or every lane has its guard"
		button.pressed.connect(_return.bind(int(record.get("id", 0))))
		row.add_child(button)
		_graveyard_box.add_child(row)


## One line of what a myr (or its record) has done: mana home for a worker, kills and saves for
## a guard, and how often it has died.
static func _stats_text(record: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if String(record.get("role", Myr.ROLE_WORKER)) == Myr.ROLE_WORKER:
		parts.append("%d mana" % int(record.get("mana_delivered", 0)))
	else:
		parts.append("%d kills" % int(record.get("kills", 0)))
		parts.append("%d saves" % int(record.get("intercepts", 0)))
	var died: int = int(record.get("deaths", 0))
	if died > 0:
		parts.append("died %dx" % died)
	return "  -  ".join(parts)
		

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
