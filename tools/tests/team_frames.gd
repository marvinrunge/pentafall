extends Node
## Regression test: the multiplayer team frames - each other player's head, a red health
## ring that follows their health, and a countdown while they are down.
##
## Run with:  godot --headless --path . res://tools/tests/team_frames.tscn
##
## Stand-ins rather than real players: what is checked is what the column makes of the
## fields it reads (Player.hp, max_hp, is_downed, down_timer, character_class,
## display_name), which a real avatar only adds a scene's worth of setup to.

var _failures: Array[String] = []


class Stand_In:
	extends Node
	var hp: float = 100.0
	var max_hp: float = 100.0
	var is_downed: bool = false
	var down_timer: float = 0.0
	var character_class: String = "knight"
	var label: String = ""

	func display_name() -> String:
		return label


func _ready() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	print("  %s   %s%s" % ["ok " if condition else "FAIL", label, "" if detail == "" else "  (%s)" % detail])
	if not condition:
		_failures.append(label)


func _run() -> void:
	var knight := Stand_In.new()
	knight.label = "Ada"
	var mage := Stand_In.new()
	mage.label = "Bo"
	mage.character_class = "mage"
	add_child(knight)
	add_child(mage)
	var players: Array = []
	var frames := TeamFrames.new()
	frames.source = func() -> Array: return players
	add_child(frames)
	await get_tree().process_frame

	_check("nobody else, no frames", frames.get_child_count() == 0)

	players.assign([knight, mage])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("one frame per other player", frames._frames.size() == 2)
	var first = frames._frames[0]
	_check("the name is shown", first._name.text == "Ada", first._name.text)
	_check("the class head is loaded", first._avatar.texture != null)

	knight.hp = 40.0
	await get_tree().process_frame
	_check("the ring follows health", is_equal_approx(first._ring.share, 0.4), "%.2f" % first._ring.share)
	_check("the ring is red while up", first._ring.color == TeamFrames.RING_HEALTH)
	_check("no countdown while up", not first._countdown.visible)

	knight.is_downed = true
	knight.down_timer = 12.0
	await get_tree().process_frame
	_check("a countdown while down", first._countdown.visible and first._countdown.text == "12",
		first._countdown.text)
	knight.down_timer = 5.2
	await get_tree().process_frame
	_check("the countdown counts down", first._countdown.text == "6", first._countdown.text)
	_check("the ring empties with the time left", is_equal_approx(first._ring.share, 5.2 / 12.0),
		"%.2f" % first._ring.share)
	_check("the head is dimmed while down", first._avatar.modulate != Color.WHITE)

	knight.is_downed = false
	knight.hp = knight.max_hp
	await get_tree().process_frame
	_check("back up: full ring, no countdown",
		is_equal_approx(first._ring.share, 1.0) and not first._countdown.visible)

	players.assign([mage])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a player who leaves loses their frame", frames._frames.size() == 1)

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)
