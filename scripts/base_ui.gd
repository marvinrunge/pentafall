extends Control
class_name BaseUI

@onready var myr_list_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/MyrListContainer
@onready var build_btn: Button = $Panel/MarginContainer/VBoxContainer/BuildButton

var main_controller: Node3D


func _ready() -> void:
	hide()
	build_btn.pressed.connect(_on_build_pressed)
	# Built once with the panel. It used to be built in open(), which meant the panel had
	# no way out until it had been opened - and then a fresh button every time after.
	_build_close_button()


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

	# The count is shown against the cap, not on its own: "Built: 10" tells the player
	# nothing about why the button stopped working.
	var at_cap: bool = active_myrs.size() >= GameSettings.myr_max_count
	build_btn.text = "Build Myr (Cost: %d Any Mana) - Built: %d/%d" % [
		GameSettings.myr_mana_cost, active_myrs.size(), GameSettings.myr_max_count]
	if at_cap:
		build_btn.text = "Myr Limit Reached (%d/%d)" % [active_myrs.size(), GameSettings.myr_max_count]
	build_btn.disabled = at_cap or RunState.total_mana() < GameSettings.myr_mana_cost

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
		name_field.placeholder_text = "Myr %d" % (i + 1)
		name_field.text = myr.display_name
		name_field.max_length = 18
		name_field.tooltip_text = "Name this myr"
		# Stored as it is typed rather than on submit: the list is rebuilt by any other
		# action in this panel, and a name only committed on Enter would be lost by
		# clicking a lane button next to it.
		name_field.text_changed.connect(func(text: String) -> void: main_controller.request_myr_name(myr, text))
		hbox.add_child(name_field)

		var level_btn := Button.new()
		var next_level: int = myr.level + 1
		var level_cost: int = GameSettings.myr_level_cost * next_level
		if myr.level >= GameSettings.myr_max_level:
			level_btn.text = "Lv %d MAX" % myr.level
			level_btn.disabled = true
		else:
			level_btn.text = "Lv %d  +%d" % [myr.level, level_cost]
			level_btn.disabled = RunState.total_mana() < level_cost
			level_btn.pressed.connect(_level_up.bind(myr, level_cost))
		level_btn.tooltip_text = "Level %d: %d health, carries %d mana per trip" % [
			myr.level,
			int(myr.max_health),
			myr.carry_amount()]
		level_btn.custom_minimum_size = Vector2(88.0, 34.0)
		hbox.add_child(level_btn)

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
			button.text = slot_suffixes[lane].strip_edges()
			button.tooltip_text = "Send this myr to the %s well" % LANE_COLORS[lane]
			button.disabled = current_lane == lane
			button.pressed.connect(_assign.bind(myr, lane))
			hbox.add_child(button)

		myr_list_container.add_child(hbox)
		

## Buys one level for `myr`. Spent and applied on the server, which is where the mana and
## the myr both live; a client's request is forwarded (MainController.request_myr_level).
func _level_up(myr: Node3D, _cost: int) -> void:
	if myr.level >= GameSettings.myr_max_level:
		return
	main_controller.request_myr_level(myr)
	SignalBus.objective_progress.emit("level_myr")
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
