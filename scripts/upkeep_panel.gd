extends CanvasLayer
class_name UpkeepPanel
## The build phase between waves: the only time team mana can be spent, and the one
## moment each wave the whole team is in the same place.
##
## Three purchases, and the consensus each needs rises with how permanent it is:
##
##   Myr             any player. Nobody objects to a worker, and making it a vote is
##                   pure friction.
##   Skill point     any player. It gives a point to EVERY player, so there is nothing
##                   to argue about.
##   Enchantment     majority vote. Permanent, colour-locked, and it shapes the whole
##                   run, so the team agrees or it does not happen.
##
## Unaffordable items stay visible and say what is MISSING rather than only greying
## out - "needs 6 more Black" is what sends the team to the black lane next wave, and
## that is the loop keeping colour alive now that builds are bought with points.
##
## Single-player skips the voting entirely: with one player there is no majority to
## reach, so the panel is simply a shop.
##
## Over the network the SERVER holds every proposal, every tally and every mana
## reservation; clients send requests and render what they are told. Anything else lets
## two peers pass contradictory votes with the same mana.

const ReadyStyle := preload("res://scripts/ready_style.gd")
const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const COLOR_HEX: Dictionary = {
	"White": Color(0.95, 0.91, 0.72),
	"Blue": Color(0.35, 0.62, 0.95),
	"Black": Color(0.62, 0.42, 0.75),
	"Red": Color(0.92, 0.34, 0.24),
	"Green": Color(0.32, 0.78, 0.42),
}

var _root: Control
## The five mana amounts in the header, in COLORS order.
var _pool_labels: Array[Label] = []
var _level_label: Label
var _timer_label: Label
var _shop_rows: HBoxContainer
## Holds the proposals; hidden while there are none.
var _vote_section: VBoxContainer
var _vote_rows: VBoxContainer
var _log_label: RichTextLabel
## The line under the tiles: what the pointed-at item is, costs or lacks.
var _detail_title: Label
var _detail_cost: Label
var _detail_body: Label
## Each tile's words by its key, rebuilt with the tiles, and which one the line is showing.
var _items: Dictionary = {}
var _shown_item: String = ""
var _ready_button: Button
## One chip per connected player in the footer - who the team is still waiting for.
var _ready_rows: HFlowContainer

var _time_left: float = 0.0
var _active: bool = false
## Enchantment colour -> {"yes": int, "no": int, "voted": Dictionary}. Mana is reserved
## while a proposal is open, so two proposals can never overdraw the pool.
var _proposals: Dictionary = {}
## Colours that already failed a vote this Upkeep and may not be re-proposed, so one
## player cannot spam the same enchantment until people click yes to make it stop.
var _blocked: Dictionary = {}
var _reserved: Dictionary = {}
var _log_lines: Array[String] = []
var _local_ready: bool = false
## peer id -> ready. Server-owned; clients receive it.
var _ready_peers: Dictionary = {}
## peer ids that have already voted on a colour, so nobody votes twice.
var _voters: Dictionary = {}
## What the myrs did in the wave just finished (docs/MYR_GUARDS_PLAN.md): one line under the
## header, worked out on every peer from the myrs' replicated stats and the Graveyard, against
## the totals at the previous Upkeep.
var _myr_summary: Label
var _myr_snapshot: Dictionary = {"mana": 0, "fled": 0, "dead": {}}


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()
	SignalBus.upkeep_started.connect(_on_upkeep_started)
	# The panel closes on the SIGNAL, not only on the local decision to close it. Both
	# ways Upkeep ends - the clock running out and everybody pressing ready - are judged
	# by the server, which then called _finish() on itself alone; every client was left
	# staring at a panel that would not go away while the next wave walked in behind it.
	# WaveManager already relays `upkeep_finished` to every peer, so listening to it is
	# the whole fix. Re-entry is harmless: _finish() returns immediately once _active is
	# false, which it sets before emitting.
	SignalBus.upkeep_finished.connect(_finish)
	SignalBus.mana_changed.connect(func(_pool: Dictionary): _refresh())
	SignalBus.enchantment_changed.connect(func(_c: String, _s: int): _refresh())


func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	_timer_label.text = "%0.0f s" % maxf(_time_left, 0.0)
	# The clock runs everywhere so the countdown reads correctly, but only the server
	# may act on it - two peers ending Upkeep would start the wave twice.
	if _time_left <= 0.0 and Net.is_server():
		_finish()


# --- lifecycle ----------------------------------------------------------------

func _on_upkeep_started(duration: float) -> void:
	_active = true
	_time_left = duration
	_proposals.clear()
	_blocked.clear()
	_reserved.clear()
	_log_lines.clear()
	_local_ready = false
	_ready_peers.clear()
	_voters.clear()
	_summarise_myrs()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	# A gamepad cannot point, so it starts on Ready - A ends the phase, and the stick or
	# D-pad walks up to the shop from there. Half a second late, because A is also jump: a
	# player mid-hop as the last enemy fell would otherwise skip the whole shop.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if _active and is_instance_valid(_ready_button) and get_viewport().gui_get_focus_owner() == null:
			_ready_button.grab_focus())


## The myrs' line for the wave just finished: the mana they brought home, how often they had
## to run, and who fell. Hidden when they did nothing at all - a run with no myrs yet.
func _summarise_myrs() -> void:
	var now: Dictionary = myr_totals()
	var mana: int = int(now["mana"]) - int(_myr_snapshot["mana"])
	var fled: int = int(now["fled"]) - int(_myr_snapshot["fled"])
	var fallen: PackedStringArray = PackedStringArray()
	var dead: Dictionary = now["dead"]
	for record_id: int in dead:
		if not (_myr_snapshot["dead"] as Dictionary).has(record_id):
			fallen.append(String(dead[record_id]))
	_myr_snapshot = now
	var parts: PackedStringArray = PackedStringArray()
	if mana > 0:
		parts.append("brought home %d mana" % mana)
	if fled > 0:
		parts.append("ran from danger %d time%s" % [fled, "" if fled == 1 else "s"])
	if not fallen.is_empty():
		parts.append("lost " + ", ".join(fallen))
	if _myr_summary != null:
		_myr_summary.text = "Myrs last wave: " + "; ".join(parts) if not parts.is_empty() else ""
		_myr_summary.visible = not parts.is_empty()


## Everything the myrs have done this run, the living and the Graveyard together - a returned
## myr carries its stats back out, so nothing is counted twice.
func myr_totals() -> Dictionary:
	var mana: int = 0
	var fled: int = 0
	for myr: Node in get_tree().get_nodes_in_group("myrs"):
		if bool(myr.get("is_dying")):
			continue
		mana += int(myr.get("mana_delivered"))
		fled += int(myr.get("times_fled"))
	var dead: Dictionary = {}
	for record: Dictionary in RunState.graveyard:
		mana += int(record.get("mana_delivered", 0))
		fled += int(record.get("times_fled", 0))
		var shown: String = String(record.get("name", ""))
		if shown.strip_edges() == "":
			shown = String(Myr.ROLE_NAMES.get(String(record.get("role", Myr.ROLE_WORKER)), "Myr"))
		dead[int(record.get("id", 0))] = shown
	return {"mana": mana, "fled": fled, "dead": dead}


## Ends Upkeep and starts the next wave. Any proposal still open simply lapses and its
## reservation is released - a team that cannot agree keeps its mana and loses only a
## wave of compounding, which is punishment enough.
func _finish() -> void:
	if not _active:
		return
	_active = false
	_proposals.clear()
	_reserved.clear()
	_voters.clear()
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SignalBus.upkeep_finished.emit()


func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	if not Net.is_active():
		if _local_ready:
			_finish()
		return
	_set_ready.rpc_id(1, _local_ready)
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _set_ready(ready: bool) -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = Net.local_id()
	_ready_peers[sender] = ready
	if _all_ready():
		_finish()
	else:
		_broadcast_ready.rpc(_ready_peers)
		_refresh()


@rpc("authority", "call_remote", "reliable")
func _broadcast_ready(state: Dictionary) -> void:
	_ready_peers = state
	_refresh()


## Counts only CONNECTED peers, so one drop-out cannot hold the phase open forever.
func _all_ready() -> bool:
	if not Net.is_active():
		return _local_ready
	for id in Net.ordered_ids():
		if not bool(_ready_peers.get(int(id), false)):
			return false
	return not Net.peers.is_empty()


# --- purchases ----------------------------------------------------------------

func _local_player() -> Node:
	return PlayerRegistry.get_local()


## Any player: in an emergency you want whoever notices to be able to act,
## and making the team vote while the crystal is at 10% would be agonising.
func _buy_repair() -> void:
	SignalBus.objective_progress.emit("upkeep_purchase")
	if Net.is_active() and not Net.is_server():
		_request_repair.rpc_id(1)
		return
	_request_repair()


@rpc("any_peer", "call_local", "reliable")
func _request_repair() -> void:
	if not Net.is_server():
		return
	var main_controller: Node = get_tree().current_scene
	if main_controller == null or not main_controller.has_method("repair_crystal"):
		return
	if main_controller.crystal_missing() <= 1.0:
		return
	if not RunState.spend({"Colorless": GameSettings.upkeep_crystal_repair_cost}):
		return
	var restored: float = main_controller.repair_crystal(GameSettings.upkeep_crystal_repair_amount)
	_announce("Repaired the crystal for %d" % int(restored))


func _buy_skill_point() -> void:
	SignalBus.objective_progress.emit("upkeep_purchase")
	if Net.is_active() and not Net.is_server():
		_request_skill_point.rpc_id(1)
		return
	_request_skill_point()


@rpc("any_peer", "call_local", "reliable")
func _request_skill_point() -> void:
	if not Net.is_server():
		return
	if not RunState.spend({"Colorless": GameSettings.upkeep_skill_point_cost}):
		return
	# Every player, not only whoever clicked - that is what makes it uncontroversial.
	if Net.is_active():
		_grant_point_to_all.rpc()
	_grant_point_to_all()
	_announce("Bought a skill point for everyone (%d)" % GameSettings.upkeep_skill_point_cost)


@rpc("authority", "call_remote", "reliable")
func _grant_point_to_all() -> void:
	# Counted as well as handed out, so a player who is not here to receive it still gets
	# it when they come back. See RunState.points_awarded.
	RunState.points_awarded += 1
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player.has_method("grant_skill_points"):
			player.grant_skill_points(1)


## Proposing reserves the mana rather than spending it, so a second proposal cannot be
## made with money the first one is already counting on.
func _propose(color: String) -> void:
	SignalBus.objective_progress.emit("upkeep_purchase")
	if Net.is_active() and not Net.is_server():
		_request_propose.rpc_id(1, color)
		return
	_request_propose(color)


@rpc("any_peer", "call_local", "reliable")
func _request_propose(color: String) -> void:
	if not Net.is_server():
		return
	if _proposals.has(color) or _blocked.has(color):
		return
	var cost: Dictionary = RunState.enchantment_cost(color)
	if not RunState.can_afford(_with_reservations(cost)):
		return
	_reserved[color] = cost
	var proposer: int = multiplayer.get_remote_sender_id() if Net.is_active() else 1
	if proposer == 0:
		proposer = Net.local_id()
	_proposals[color] = {"yes": 1, "no": 0}
	_voters[color] = {proposer: true}
	if _vote_threshold() <= 1:
		_resolve(color, true)
		return
	_broadcast_proposals()


func _vote(color: String, approve: bool) -> void:
	if Net.is_active() and not Net.is_server():
		_request_vote.rpc_id(1, color, approve)
		return
	_request_vote(color, approve)


@rpc("any_peer", "call_local", "reliable")
func _request_vote(color: String, approve: bool) -> void:
	if not Net.is_server() or not _proposals.has(color):
		return
	var voter: int = multiplayer.get_remote_sender_id() if Net.is_active() else 1
	if voter == 0:
		voter = Net.local_id()
	# One vote each. Without this a single client could carry any motion alone.
	var cast: Dictionary = _voters.get(color, {})
	if cast.has(voter):
		return
	cast[voter] = true
	_voters[color] = cast

	var proposal: Dictionary = _proposals[color]
	var key: String = "yes" if approve else "no"
	proposal[key] = int(proposal[key]) + 1
	# Resolves the instant a majority is reached rather than waiting out the timer.
	if int(proposal["yes"]) >= _vote_threshold():
		_resolve(color, true)
	elif int(proposal["no"]) >= _vote_threshold():
		_resolve(color, false)
	else:
		_broadcast_proposals()


func _resolve(color: String, passed: bool) -> void:
	_proposals.erase(color)
	_reserved.erase(color)
	_voters.erase(color)
	if passed and RunState.buy_enchantment(color):
		_announce("%s passed - now %d stacks" % [RunState.enchantment_name(color), RunState.enchantment_stacks(color)])
	else:
		_blocked[color] = true
		_announce("%s was rejected" % RunState.enchantment_name(color))
	_broadcast_proposals()


func _withdraw(color: String) -> void:
	if Net.is_active() and not Net.is_server():
		_request_withdraw.rpc_id(1, color)
		return
	_request_withdraw(color)


@rpc("any_peer", "call_local", "reliable")
func _request_withdraw(color: String) -> void:
	if not Net.is_server():
		return
	_proposals.erase(color)
	_reserved.erase(color)
	_voters.erase(color)
	_broadcast_proposals()


## Proposals and their tallies are the server's; this is how clients learn them.
func _broadcast_proposals() -> void:
	if Net.is_active():
		_apply_proposals.rpc(_proposals, _blocked)
	_refresh()


@rpc("authority", "call_remote", "reliable")
func _apply_proposals(proposals: Dictionary, blocked: Dictionary) -> void:
	_proposals = proposals
	_blocked = blocked
	_refresh()


## Purchases are announced rather than logged locally, so every player sees the same
## history of what the team's mana went on.
func _announce(line: String) -> void:
	if Net.is_active():
		_apply_log.rpc(line)
	_apply_log(line)


@rpc("authority", "call_remote", "reliable")
func _apply_log(line: String) -> void:
	_log(line)
	_refresh()


func _vote_threshold() -> int:
	var players: int = maxi(get_tree().get_nodes_in_group("player").size(), 1)
	return players / 2 + 1


## `cost` plus everything currently reserved by open proposals, so affordability is
## judged against what is actually still free.
func _with_reservations(cost: Dictionary) -> Dictionary:
	var total: Dictionary = cost.duplicate()
	for color: String in _reserved.keys():
		for key: String in _reserved[color].keys():
			total[key] = int(total.get(key, 0)) + int(_reserved[color][key])
	return total


func _log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 6:
		_log_lines.remove_at(0)


# --- ui -----------------------------------------------------------------------
#
# Compact: the header, one row of item tiles, what the pointed-at tile is said once under them,
# and the proposals only while there are any. It used to be a full-screen 1040 x 580 list with
# every description written out at once - at 720p it ran off the right of the screen, and the
# proposals were the column that did not fit.

## An item tile's icon button, square, in pixels.
const TILE_SIZE := 50.0
## What the detail line says with no tile pointed at.
const IDLE_TITLE := "Spend the team's mana"


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.018, 0.025, 0.6)
	_root.add_child(backdrop)

	# Centred by a container rather than placed at a fixed offset. The panel used to be
	# positioned once at its authored size; a PanelContainer grows to fit its content but
	# never shrinks back, and every rebuild briefly holds the old rows and the new ones at
	# once - so after a vote resolved (three rebuilds in a row: the tally, the mana, the
	# enchantment) the panel had grown down and to the right, off the screen.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Centred in the upper two thirds, clear of the middle of the screen: the HUD's own prompts
	# ("Press [E] to Manage Base", the mission banner) sit there and drew over it.
	centre.anchor_bottom = 0.66
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.045, 0.055, 0.97), Color(0.9, 0.67, 0.2)))
	centre.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	# --- header: the name, the pool, the level, the clock ---------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	rows.add_child(header)
	var heading := Label.new()
	heading.text = "UPKEEP"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(1.0, 0.8, 0.36))
	header.add_child(heading)
	var pool := HBoxContainer.new()
	pool.add_theme_constant_override("separation", 8)
	pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(pool)
	for color: String in COLORS:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		var pip := TextureRect.new()
		pip.texture = SpellDatabase.get_icon(color.to_lower())
		pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pip.custom_minimum_size = Vector2(16.0, 16.0)
		chip.add_child(pip)
		var amount := Label.new()
		amount.add_theme_font_size_override("font_size", 14)
		amount.add_theme_color_override("font_color", COLOR_HEX[color])
		chip.add_child(amount)
		pool.add_child(chip)
		_pool_labels.append(amount)
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84))
	header.add_child(_level_label)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	header.add_child(_timer_label)

	_myr_summary = Label.new()
	_myr_summary.name = "MyrSummary"
	_myr_summary.add_theme_font_size_override("font_size", 13)
	_myr_summary.add_theme_color_override("font_color", Color(0.72, 0.86, 0.95))
	_myr_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_myr_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_myr_summary)

	# --- the items ------------------------------------------------------------
	_shop_rows = HBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 8)
	_shop_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(_shop_rows)

	# --- what the pointed-at item is ------------------------------------------
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.028, 0.035, 0.9), Color(0.3, 0.3, 0.33)))
	rows.add_child(detail)
	var detail_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + side, 8)
	detail.add_child(detail_margin)
	var detail_rows := VBoxContainer.new()
	detail_rows.add_theme_constant_override("separation", 2)
	detail_margin.add_child(detail_rows)
	var detail_head := HBoxContainer.new()
	detail_rows.add_child(detail_head)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 15)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_head.add_child(_detail_title)
	_detail_cost = Label.new()
	_detail_cost.add_theme_font_size_override("font_size", 13)
	detail_head.add_child(_detail_cost)
	_detail_body = Label.new()
	_detail_body.add_theme_font_size_override("font_size", 12)
	_detail_body.add_theme_color_override("font_color", Color(0.68, 0.7, 0.75))
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Two lines' room whatever is shown, so pointing along the row does not make it jump.
	_detail_body.custom_minimum_size = Vector2(0.0, 32.0)
	detail_rows.add_child(_detail_body)

	# --- proposals, only while there are any ----------------------------------
	_vote_section = VBoxContainer.new()
	_vote_section.add_theme_constant_override("separation", 4)
	rows.add_child(_vote_section)
	_vote_section.add_child(_section_label("PROPOSALS"))
	_vote_rows = VBoxContainer.new()
	_vote_rows.add_theme_constant_override("separation", 4)
	_vote_section.add_child(_vote_rows)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", 11)
	rows.add_child(_log_label)

	# --- footer: ready check --------------------------------------------------
	_ready_rows = HFlowContainer.new()
	_ready_rows.add_theme_constant_override("h_separation", 6)
	_ready_rows.add_theme_constant_override("v_separation", 4)
	rows.add_child(_ready_rows)
	_ready_button = Button.new()
	_ready_button.custom_minimum_size = Vector2(0.0, 34.0)
	_ready_button.pressed.connect(_on_ready_pressed)
	rows.add_child(_ready_button)
	_show_item("")


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.62, 0.64, 0.7))
	return label


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _refresh() -> void:
	if _pool_labels.is_empty():
		return

	for index: int in range(COLORS.size()):
		_pool_labels[index].text = "%d" % int(RunState.mana_pool.get(COLORS[index], 0))

	var progress: Vector2 = RunState.xp_progress()
	var points: int = 0
	var local: Node = _local_player()
	if local != null and "skill_points" in local:
		points = int(local.skill_points)
	_level_label.text = "Lv %d  %d%%  |  %d pts" % [
		RunState.team_level, int(round(100.0 * progress.x / maxf(progress.y, 1.0))), points]

	# Every button below is rebuilt, and a rebuilt button is a new node - so whatever had
	# focus (the Yes just pressed, on a pad the only way to point at anything) is gone.
	# Remembered by what it IS and handed back to its replacement.
	var focus_key: String = ""
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and _root.is_ancestor_of(focused):
		focus_key = String(focused.get_meta("focus_key", ""))

	_rebuild_shop()
	_rebuild_votes()
	_rebuild_ready_rows()
	_log_label.text = "\n".join(_log_lines.slice(-2)) if not _log_lines.is_empty() else ""
	_log_label.visible = not _log_lines.is_empty()
	_ready_button.text = "READY - waiting for the rest" if _local_ready else "NOT READY - press to start the next wave"
	ReadyStyle.style_button(_ready_button, _local_ready)
	# The tile the pointer is on was rebuilt too; say what the new one says.
	_show_item(_shown_item)

	if focus_key != "":
		var target: Control = _find_focus_key(_root, focus_key)
		if target == null or (target is BaseButton and (target as BaseButton).disabled):
			target = _ready_button
		target.grab_focus()


func _find_focus_key(node: Node, key: String) -> Control:
	for child: Node in node.get_children():
		if child is Control and String(child.get_meta("focus_key", "")) == key:
			return child as Control
		var found: Control = _find_focus_key(child, key)
		if found != null:
			return found
	return null


## Removed from the tree NOW, not only queued: a queued child still counts towards the
## container's size until the end of the frame. See _build_ui.
static func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _rebuild_ready_rows() -> void:
	_clear(_ready_rows)
	_ready_rows.visible = Net.is_active()
	if not Net.is_active():
		return
	for id in Net.ordered_ids():
		var peer_id: int = int(id)
		var ready: bool = _local_ready if peer_id == Net.local_id() else bool(_ready_peers.get(peer_id, false))
		var tag: String = " (you)" if peer_id == Net.local_id() else ""
		var chip: PanelContainer = ReadyStyle.row(Net.display_name(peer_id) + tag, ready)
		chip.custom_minimum_size = Vector2(150.0, 0.0)
		_ready_rows.add_child(chip)


func _rebuild_shop() -> void:
	_clear(_shop_rows)
	_items.clear()

	# No myrs here: they are built, levelled, assigned and returned at the base, by the crystal.
	# A myr bought here could be neither given a lane nor seen - an unassigned myr has no model -
	# and it went past the myr cap, spending the mana on nothing.
	_shop_rows.add_child(_purchase_tile("point", "upkeep_skill_point",
		"Skill point for everyone", "+1 point to every player, not just the buyer.",
		{"Colorless": GameSettings.upkeep_skill_point_cost}, _buy_skill_point, Color(0.9, 0.85, 0.5)))

	# Only offered when there is something to fix, so a healthy team is not tempted to
	# waste mana on it and a hurt one cannot miss it.
	var main_controller: Node = get_tree().current_scene
	if main_controller != null and main_controller.has_method("crystal_missing") and main_controller.crystal_missing() > 1.0:
		_shop_rows.add_child(_purchase_tile("repair", "upkeep_repair",
			"Repair the crystal (%d missing)" % int(main_controller.crystal_missing()),
			"Restores %d integrity. The only way to undo a leak." % int(GameSettings.upkeep_crystal_repair_amount),
			{"Colorless": GameSettings.upkeep_crystal_repair_cost}, _buy_repair, Color(0.55, 0.85, 1.0)))

	for color: String in COLORS:
		var stacks: int = RunState.enchantment_stacks(color)
		var vote: String = "" if not Net.is_active() else "  A majority has to agree."
		_shop_rows.add_child(_purchase_tile(color, "enchantment_" + color.to_lower(),
			"%s  (%s enchantment, %d %s)" % [RunState.enchantment_name(color), color, stacks, "stack" if stacks == 1 else "stacks"],
			RunState.enchantment_description(color) + vote, RunState.enchantment_cost(color),
			_propose.bind(color), COLOR_HEX[color], stacks))


## One item: its icon as the button, its price under it, its stacks on it. Unaffordable ones
## stay and name what is missing, because knowing what you CANNOT buy is what drives the next
## wave's lane choice. The words are in the detail line, for the tile the pointer is on.
func _purchase_tile(key: String, icon_id: String, title: String, description: String, cost: Dictionary,
		on_press: Callable, tint: Color, stacks: int = 0) -> Control:
	var missing: Dictionary = RunState.shortfall(_with_reservations(cost))
	_items[key] = {"title": title, "desc": description, "tint": tint, "cost": cost, "missing": missing}

	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 2)
	var button := Button.new()
	button.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	button.icon = SpellDatabase.get_icon(icon_id)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta("focus_key", "shop:" + key)
	button.mouse_entered.connect(_show_item.bind(key))
	button.focus_entered.connect(_show_item.bind(key))
	button.mouse_exited.connect(_show_item.bind(""))
	if missing.is_empty():
		button.pressed.connect(on_press)
	else:
		button.disabled = true
		button.modulate = Color(0.55, 0.56, 0.6)
	tile.add_child(button)
	if stacks > 0:
		var badge := Label.new()
		badge.text = "x%d" % stacks
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		badge.add_theme_constant_override("outline_size", 4)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.position += Vector2(-2.0, 0.0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)

	var price := Label.new()
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 11)
	if missing.is_empty():
		price.text = _short_cost(cost)
		price.add_theme_color_override("font_color", tint if not cost.has("Colorless") else Color(0.8, 0.82, 0.86))
	else:
		price.text = "-" + _short_cost(missing)
		price.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	tile.add_child(price)
	return tile


## "2 any", "8 W": a price small enough to sit under a tile.
func _short_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for color: String in cost.keys():
		parts.append("%d %s" % [int(cost[color]), "any" if color == "Colorless" else color.substr(0, 1)])
	return " ".join(parts)


func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for color: String in cost.keys():
		parts.append("%d %s" % [int(cost[color]), "any" if color == "Colorless" else color])
	return ", ".join(parts)


## Says what item `key` is, costs or lacks - or, with "", what the panel is for.
func _show_item(key: String) -> void:
	if not is_instance_valid(_detail_title):
		return
	_shown_item = key if _items.has(key) else ""
	if _shown_item == "":
		_detail_title.text = IDLE_TITLE
		_detail_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
		_detail_cost.text = ""
		_detail_body.text = "Point at an item for what it does. Myrs and skill points are bought at once; an enchantment is %s." % (
			"put to a vote" if Net.is_active() else "permanent for the run")
		return
	var item: Dictionary = _items[_shown_item]
	_detail_title.text = String(item["title"])
	_detail_title.add_theme_color_override("font_color", item["tint"])
	_detail_body.text = String(item["desc"])
	var missing: Dictionary = item["missing"]
	if missing.is_empty():
		_detail_cost.text = _cost_text(item["cost"])
		_detail_cost.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	else:
		_detail_cost.text = "needs %s more" % _cost_text(missing)
		_detail_cost.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))


func _rebuild_votes() -> void:
	_clear(_vote_rows)
	_vote_section.visible = not _proposals.is_empty()
	for color: String in _proposals.keys():
		var proposal: Dictionary = _proposals[color]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = SpellDatabase.get_icon("enchantment_" + color.to_lower())
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(22.0, 22.0)
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s   %d yes / %d no  (need %d)" % [
			RunState.enchantment_name(color), int(proposal["yes"]), int(proposal["no"]), _vote_threshold()]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", COLOR_HEX[color])
		row.add_child(label)
		for vote: Array in [["Yes", "yes", _vote.bind(color, true)], ["No", "no", _vote.bind(color, false)], ["x", "withdraw", _withdraw.bind(color)]]:
			var button := Button.new()
			button.text = String(vote[0])
			button.add_theme_font_size_override("font_size", 12)
			button.custom_minimum_size = Vector2(26.0 if vote[1] == "withdraw" else 40.0, 24.0)
			button.set_meta("focus_key", "vote:%s:%s" % [color, vote[1]])
			button.pressed.connect(vote[2])
			row.add_child(button)
		_vote_rows.add_child(row)
