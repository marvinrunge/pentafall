extends Control
class_name MainMenu
## The screen the game starts on: play alone, host a LAN game, or find one to join.
##
## Four pages in one Control rather than four scenes, because they share every piece of
## state that matters - the player name, the connection, and the peer list - and a page
## change here is a `visible` flag rather than a scene load that would drop it.
##
## The map is only ever loaded once a decision has been made, so a solo run reaches
## exactly the same scene by the same call as a five-player one. Networking stays inert
## until Host or Join is pressed; see scripts/net.gd.

const MAP_SCENE: String = "res://scenes/misc/main.tscn"

enum Page { MAIN, HOST, BROWSE, LOBBY }

var _pages: Dictionary = {}
var _status_label: Label

var _name_field: LineEdit
## The class, its role under it, and the name: under the figure on the right, as a caption
## the player can change.
var _class_picker: OptionButton
var _class_role: Label
## The picked class standing to the right of the menu.
var _class_preview: ClassPreview
var _server_name_field: LineEdit
var _host_port_field: LineEdit
var _host_password_field: LineEdit

## Listing this game online rather than only on the local network. Hidden entirely on a
## build with no Firebase settings, rather than shown and refused.
var _online_host_check: CheckButton
var _online_browse_check: CheckButton
var _browse_heading: Label
## Which source the browser is showing. The rows from both look the same by design -
## `NetOnline.found_servers()` answers the dictionaries `Net.found_servers()` answers -
## so this decides where they are fetched from and nothing about how they are drawn.
var _online_mode: bool = false

var _server_list: ItemList
var _scan_button: Button
var _join_password_field: LineEdit
var _join_button: Button
var _direct_address_field: LineEdit
var _servers: Array = []

var _reconnect_button: Button

var _lobby_title: Label
var _peer_list: VBoxContainer
var _ready_button: Button
var _start_button: Button

## The same options panel the HUD opens on Escape, over the menu. See scripts/settings_menu.gd.
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const ReadyStyle := preload("res://scripts/ready_style.gd")
const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
const LOGO: Texture2D = preload("res://assets/images/logo_pentafall.png")
const MENU_ART: Texture2D = preload("res://assets/images/menu.jpg")
## The boot splash (assets/images/boot_splash.png - the splash painting with the logo on it),
## faded out over the menu the first time it opens.
const SPLASH: Texture2D = preload("res://assets/images/boot_splash.png")
## Whether this session has already faded the splash into the menu. Static, so returning to
## the menu from a run does not play it again.
static var _splash_shown: bool = false
## The logo's height in the menu column, between these - see _fit_logo.
const LOGO_HEIGHT_MAX := 240.0
const LOGO_HEIGHT_MIN := 110.0
## The column down the left: as wide as the logo at its biggest. The buttons and fields of a
## page are narrower, centred under it - PAGE_WIDTH, wider for the pages with lists.
const COLUMN_WIDTH := 560.0
const PAGE_WIDTH: Dictionary = {Page.MAIN: 320.0, Page.HOST: 360.0, Page.BROWSE: 400.0, Page.LOBBY: 380.0}
## The figure's caption under it on the right - class, role and name - and how far into the
## room under the figure's feet it reaches (the preview's view runs a little below the ground).
const IDENTITY_HEIGHT := 150.0
const IDENTITY_OVERLAP := 30.0
## Worn metal, after the logo's lettering: the rim of the buttons and the class's name.
const METAL := Color(0.62, 0.52, 0.38)
const METAL_LIGHT := Color(0.9, 0.8, 0.6)
var _column: VBoxContainer
var _logo: TextureRect
## The open page - what the logo makes room for, with the status line under it.
var _body: MarginContainer
var _settings_overlay: Control
var _settings_menu: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_show_page(Page.MAIN)

	# Arriving here from a match that dropped rather than from the desktop. The address
	# is still known and the host holds the seat, so the only thing worth showing is the
	# way back in.
	if Net.can_reconnect():
		_set_status("Connection lost. Your seat is held - reconnect to rejoin the run.")
	_refresh_reconnect()

	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_closed.connect(_on_server_closed)
	Net.join_rejected.connect(_on_join_rejected)
	Net.lan_servers_updated.connect(_on_lan_servers_updated)
	Net.lan_scan_finished.connect(_on_lan_scan_finished)
	Net.match_started.connect(_on_match_started)

	NetOnline.servers_updated.connect(_on_online_servers_updated)
	NetOnline.browse_failed.connect(_on_browse_failed)
	NetOnline.status_changed.connect(_set_status)

	# Two windows on one desk, skipping the lobby. See _apply_autostart.
	_apply_autostart.call_deferred()


# --- starting from the command line -------------------------------------------
#
# Testing multiplayer means driving two windows through host, scan, join and two ready
# checks before a single frame of the actual game, every time. These flags do that part.

## Set when this instance was told to host or join on the command line, so the lobby
## starts the match by itself once everyone is in rather than waiting for the button.
var _autostart_seats: int = 0


## Reads `--autohost` / `--autojoin` off the command line and acts on them.
##
## Passed after `++` so Godot hands them through as user args:
##
##     godot --path . ++ --autohost=2          # host, and start once 2 players are ready
##     godot --path . ++ --autojoin=127.0.0.1  # join that address and mark ready
##
## Both accept an optional `:port`. The host counts players rather than starting straight
## away, because a match that begins before the client has connected leaves them joining
## a run in progress instead of starting one together.
func _apply_autostart() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--autohost"):
			_autostart_host(arg)
			return
		if arg.begins_with("--autojoin"):
			_autostart_join(arg)
			return


func _autostart_host(arg: String) -> void:
	var value: String = arg.get_slice("=", 1) if arg.contains("=") else ""
	_autostart_seats = maxi(int(value) if value.is_valid_int() else 2, 1)
	var port: int = Net.DEFAULT_PORT
	if value.contains(":"):
		port = int(value.get_slice(":", 1))
		_autostart_seats = maxi(int(value.get_slice(":", 0)), 1)
	_name_field.text = "Host"
	if Net.host(port, "Host", "Autostart", "") != OK:
		_set_status("Autostart: could not open port %d." % port)
		return
	Net.set_local_ready(true)
	_show_page(Page.LOBBY)
	_set_status("Autostart: hosting on %d, waiting for %d players." % [port, _autostart_seats])


func _autostart_join(arg: String) -> void:
	var value: String = arg.get_slice("=", 1) if arg.contains("=") else "127.0.0.1"
	var address: String = value.get_slice(":", 0)
	var port: int = int(value.get_slice(":", 1)) if value.contains(":") else Net.DEFAULT_PORT
	if address.is_empty():
		address = "127.0.0.1"
	_name_field.text = "Client"
	PlayerRegistry.clear_saved_build()
	if Net.join(address, port, "Client", "") != OK:
		_set_status("Autostart: could not reach %s:%d." % [address, port])
		return
	_show_page(Page.LOBBY)
	_set_status("Autostart: joining %s:%d." % [address, port])


## Readiness and the start, once the peer list says everyone has arrived. Called from
## _on_peer_list_changed, which is the only place that knows the list has moved.
func _autostart_tick() -> void:
	if _autostart_seats <= 0:
		# A client: say ready as soon as the server's list has us in it, then wait for
		# the host to start.
		if Net.is_active() and not Net.is_server() \
				and Net.peers.has(Net.local_id()) and not Net.is_ready(Net.local_id()):
			Net.set_local_ready(true)
		return
	if Net.peers.size() < _autostart_seats or not Net.all_ready():
		return
	# Once only: start_match is what loads the map, and a second call would reload it.
	_autostart_seats = 0
	Net.start_match()


# --- actions ------------------------------------------------------------------

## Single-player is deliberately the shortest path in this file: no peer, no lobby, no
## readiness - straight into the map, exactly as the game booted before this menu.
func _on_solo_pressed() -> void:
	# A solo run is a NEW run, so it must not inherit the build left over from a match
	# this player was dropped out of.
	PlayerRegistry.clear_saved_build()
	GameSettings.player_count = 1
	_enter_map()


## Remembered for the next run, and - in a lobby - told to the host, who tells everyone.
func _on_class_selected(index: int) -> void:
	var class_id: String = String(_class_picker.get_item_metadata(index))
	UserSettings.set_value(&"character_class", class_id)
	_class_role.text = String(ClassDatabase.get_class_data(class_id)["role"])
	_class_preview.show_class(class_id)
	Net.set_local_class(class_id)


func _on_create_pressed() -> void:
	if _hosting_online():
		var online: Error = Net.host_online(
			_player_name(), _server_name_field.text, _host_password_field.text
		)
		if online != OK:
			_set_status(NetOnline.unavailable_reason())
			return
		PlayerRegistry.clear_saved_build()
		# No port and nothing to forward: the status line says so, because "hosting on
		# port 27015" is the one thing a player will otherwise go looking for in their
		# router.
		_set_status("Listing the game online. No port forwarding needed.")
		_show_page(Page.LOBBY)
		return
	var port: int = _host_port()
	var result: Error = Net.host(port, _player_name(), _server_name_field.text, _host_password_field.text)
	if result != OK:
		_set_status("Could not open port %d - something else is already using it." % port)
		return
	PlayerRegistry.clear_saved_build()
	_set_status("Hosting on port %d. Waiting for players." % port)
	_show_page(Page.LOBBY)


func _hosting_online() -> bool:
	return is_instance_valid(_online_host_check) and _online_host_check.button_pressed


func _on_scan_pressed() -> void:
	_servers = []
	_server_list.clear()
	if _online_mode:
		# Nothing to disable: the online browser keeps refreshing on its own while this
		# page is open, so there is no scan window to wait out.
		NetOnline.set_browsing(true)
		NetOnline.refresh_now()
		_set_status("Looking for games online...")
		return
	_scan_button.disabled = true
	_set_status("Scanning the local network...")
	Net.scan_lan()


## Flips the browser between the local network and the online list. The two never merge:
## a LAN game is joined by address and an online game through the handshake, and a list
## that mixed them would have to explain which row is which.
func _on_browse_source_toggled(online: bool) -> void:
	_online_mode = online
	_servers = []
	_server_list.clear()
	_browse_heading.text = "GAMES ONLINE" if online else "GAMES ON THIS NETWORK"
	_scan_button.text = "REFRESH" if online else "SCAN"
	_scan_button.disabled = false
	# There is no address to type for an online game - the host does not know its own
	# until the handshake has run.
	_direct_address_field.editable = not online
	_direct_address_field.placeholder_text = "" if online else "127.0.0.1"
	NetOnline.set_browsing(online)
	if online:
		NetOnline.refresh_now()
		_set_status("Looking for games online...")
	else:
		_set_status("")


func _on_join_pressed() -> void:
	var address: String = _direct_address_field.text.strip_edges()
	var port: int = Net.DEFAULT_PORT
	var in_progress: bool = false
	var selected: PackedInt32Array = _server_list.get_selected_items()
	var chosen: Dictionary = {}
	if selected.size() > 0 and selected[0] < _servers.size():
		chosen = _servers[selected[0]]
		address = String(chosen.get("address", ""))
		port = int(chosen.get("port", Net.DEFAULT_PORT))
		in_progress = bool(chosen.get("in_progress", false))
	if bool(chosen.get("online", false)):
		_join_online(chosen, in_progress)
		return
	if address.is_empty():
		_set_status("Pick a server from the list, or type an address.")
		return
	# Only RECONNECT brings a build back. Picking a match out of the browser is joining
	# as a new player, even if the machine still remembers one.
	PlayerRegistry.clear_saved_build()
	if in_progress:
		# There is no lobby to wait in - the match is already running. The map is loaded
		# FIRST and opens the connection itself once it is standing, because the server
		# pushes the whole existing world the moment a peer connects.
		Net.begin_join(address, port, _player_name(), _join_password_field.text)
		_enter_map()
		return
	if Net.join(address, port, _player_name(), _join_password_field.text) != OK:
		_set_status("Could not reach %s:%d." % [address, port])
		return
	_set_status("Connecting to %s:%d..." % [address, port])
	_show_page(Page.LOBBY)


## The online half of JOIN. Same two cases as the LAN one and for the same reasons: a
## lobby is joined straight away, a match already running is joined from inside the map
## so that nothing is spawned before the map exists to spawn it into.
func _join_online(lobby: Dictionary, in_progress: bool) -> void:
	print("[NetOnline] menu: joining lobby %s (%s)" % [lobby.get("lobby", "?"), lobby.get("name", "?")])
	PlayerRegistry.clear_saved_build()
	NetOnline.set_browsing(false)
	if in_progress:
		Net.begin_join_online(lobby, _player_name(), _join_password_field.text)
		_enter_map()
		return
	if Net.join_online(lobby, _player_name(), _join_password_field.text) != OK:
		_set_status(NetOnline.unavailable_reason())
		return
	_show_page(Page.LOBBY)


func _on_ready_pressed() -> void:
	Net.set_local_ready(not Net.is_ready(Net.local_id()))


func _on_start_pressed() -> void:
	Net.start_match()


func _on_leave_pressed() -> void:
	Net.leave()
	Net.forget_last_join()
	PlayerRegistry.clear_saved_build()
	_refresh_reconnect()
	_set_status("Left the session.")
	_show_page(Page.MAIN)


## Back into the run that dropped, on exactly the terms the browser uses for any other
## match in progress: load the map, then connect.
func _on_reconnect_pressed() -> void:
	var details: Dictionary = Net.last_join
	if details.is_empty():
		return
	# An online run is rejoined through the handshake, not by dialling the address it
	# was never reached at in the first place.
	if String(details.get("transport", "enet")) == "online":
		Net.begin_join_online(
			details["lobby"], String(details["name"]), String(details["password"])
		)
	else:
		Net.begin_join(
			String(details["address"]),
			int(details["port"]),
			String(details["name"]),
			String(details["password"]),
		)
	_enter_map()


func _refresh_reconnect() -> void:
	if is_instance_valid(_reconnect_button):
		_reconnect_button.visible = Net.can_reconnect()


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- net callbacks ------------------------------------------------------------

func _on_peer_list_changed(_peers: Dictionary) -> void:
	_autostart_tick()
	_refresh_lobby()


## Covers both transports. `Net.last_error` is set only when there is something more
## specific to say than "could not reach it" - which, for an online join, there usually
## is: a handshake that timed out is a very different problem from a database that was
## never configured.
func _on_connection_failed() -> void:
	_set_status(Net.last_error if not Net.last_error.is_empty() else "Could not reach that host.")
	_show_page(Page.BROWSE)


func _on_server_closed() -> void:
	Net.forget_last_join()
	PlayerRegistry.clear_saved_build()
	_refresh_reconnect()
	_set_status("The host closed the session.")
	_show_page(Page.MAIN)


func _on_join_rejected(reason: String) -> void:
	_set_status(reason)
	_show_page(Page.BROWSE)


func _on_lan_servers_updated(servers: Array) -> void:
	if _online_mode:
		return
	_render_servers(servers)


func _on_online_servers_updated(servers: Array) -> void:
	if not _online_mode:
		return
	_render_servers(servers)
	if servers.is_empty():
		_set_status("No games listed online right now.")


func _on_browse_failed(reason: String) -> void:
	if _online_mode:
		_set_status(reason)


## One renderer for both sources. An online row has no address to show - it is reached
## through the handshake, not by dialling anything - so it says where it came from
## instead.
func _render_servers(servers: Array) -> void:
	_servers = servers
	_server_list.clear()
	for server in servers:
		var entry: Dictionary = server
		var lock: String = " [locked]" if bool(entry.get("password", false)) else ""
		if bool(entry.get("in_progress", false)):
			lock += " [in progress]"
		var where: String = "online" if bool(entry.get("online", false)) else "%s:%d" % [
			String(entry.get("address", "")),
			int(entry.get("port", Net.DEFAULT_PORT)),
		]
		_server_list.add_item("%s  -  %d/%d  -  %s%s" % [
			String(entry.get("name", "Game")),
			int(entry.get("players", 1)),
			int(entry.get("max", Net.MAX_PLAYERS)),
			where,
			lock,
		])


func _on_lan_scan_finished(servers: Array) -> void:
	_scan_button.disabled = false
	if _online_mode:
		return
	if servers.is_empty():
		_set_status("No games found on this network. You can still type an address.")
	else:
		_set_status("Found %d game%s." % [servers.size(), "" if servers.size() == 1 else "s"])


## Every peer lands here, host included: the host through its own local call and the
## clients through the RPC, so nobody loads the map at a different moment than anyone
## else and the server can spawn one avatar per peer as soon as the map is up.
func _on_match_started() -> void:
	_enter_map()


func _enter_map() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameSettings.intro_tour_pending = true
	LoadingScreenScript.begin(get_tree(), MAP_SCENE)


# --- helpers ------------------------------------------------------------------

func _player_name() -> String:
	var entered: String = _name_field.text.strip_edges()
	return entered if not entered.is_empty() else "Player"


func _host_port() -> int:
	var entered: String = _host_port_field.text.strip_edges()
	if not entered.is_valid_int():
		return Net.DEFAULT_PORT
	return clampi(int(entered), 1024, 65535)


func _set_status(text: String) -> void:
	_status_label.text = text


func _show_page(page: Page) -> void:
	for key in _pages:
		(_pages[key] as Control).visible = key == page
	# The online browser polls, so it is switched off the moment it is not being looked
	# at. Nothing in this game talks to Firebase unless a list or a handshake is on
	# screen.
	if page != Page.BROWSE:
		NetOnline.set_browsing(false)
	elif _online_mode:
		NetOnline.set_browsing(true)
		NetOnline.refresh_now()
	if page == Page.LOBBY:
		_refresh_lobby()
	_fit_logo.call_deferred()
	# Deferred, so a page whose buttons the line above has just shown or hidden is focused
	# on what it actually offers.
	_focus_page.call_deferred()


## Sizes the logo to the room the open page leaves in the column: full size on a short page
## or a tall window, smaller when the Join page has to fit a 720p one.
func _fit_logo() -> void:
	if _logo == null or _body == null or _column == null:
		return
	var separation: float = float(_column.get_theme_constant("separation"))
	var below: float = _body.get_combined_minimum_size().y + _status_label.get_combined_minimum_size().y
	var room: float = _column.size.y - below - separation * 2.0
	_logo.custom_minimum_size.y = clampf(room, LOGO_HEIGHT_MIN, LOGO_HEIGHT_MAX)


## Puts focus on the first thing the visible page offers. Without it nothing in the menu
## had focus, and a gamepad - which can only move focus, never point - could not even
## start a game.
func _focus_page() -> void:
	for key in _pages:
		var page := _pages[key] as Control
		if page.visible:
			var target: Control = SettingsMenuScript.first_focusable(page)
			if target != null:
				target.grab_focus()
			return


func _refresh_lobby() -> void:
	if not is_instance_valid(_peer_list):
		return
	for child in _peer_list.get_children():
		child.queue_free()

	var active: bool = Net.is_active()
	_lobby_title.text = Net.server_name if active else "Not connected"
	_ready_button.disabled = not active
	var local_ready: bool = Net.is_ready(Net.local_id())
	_ready_button.text = "READY - click to cancel" if local_ready else "NOT READY - click when ready"
	ReadyStyle.style_button(_ready_button, local_ready)
	# Only the host starts, and only once every single person has said yes.
	_start_button.visible = Net.is_server()
	_start_button.disabled = not (active and Net.is_server() and Net.all_ready())

	if not active:
		var idle := Label.new()
		idle.text = "Waiting for the connection..."
		idle.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		_peer_list.add_child(idle)
		return

	for id in Net.ordered_ids():
		var peer_id: int = int(id)
		var tag: String = " (you)" if peer_id == Net.local_id() else ""
		var host_tag: String = " - host" if peer_id == 1 else ""
		_peer_list.add_child(ReadyStyle.row("%d. %s%s%s - %s" % [
			Net.seat_of(peer_id) + 1, Net.display_name(peer_id), tag, host_tag,
			ClassDatabase.display_name(Net.class_of(peer_id)),
		], Net.is_ready(peer_id)))


# --- ui -----------------------------------------------------------------------

func _build_ui() -> void:
	_build_backdrop()

	# The picked class, standing on the right of the painting - between the crystal and the
	# right-hand stone, clear of the menu column on the left (`figure_column`). The preview
	# itself spans the whole screen, so a weapon held high or swung out to the side - the
	# barbarian's 1.9 m greatsword - is never cut off by a frame; added before the menu, so the
	# buttons stay on top of anything that reaches across them. It stops above its caption
	# (_build_identity), which stands in the room the figure's feet leave.
	_class_preview = ClassPreview.new()
	_class_preview.figure_column = Vector2(0.52, 1.0)
	_class_preview.anchor_left = 0.0
	_class_preview.anchor_right = 1.0
	_class_preview.anchor_top = 0.0
	_class_preview.anchor_bottom = 1.0
	_class_preview.offset_bottom = -(IDENTITY_HEIGHT - IDENTITY_OVERLAP)
	add_child(_class_preview)
	_class_preview.show_class(Net.local_class())

	# The logo and the menu share one column down the left, over the shaded side of the
	# painting - the buttons straight on it, no panel round them, centred under the logo. The
	# open page hangs under the logo, which is as big as the room the page leaves allows - see
	# _fit_logo - so the longest page still fits a 720p window.
	var column := VBoxContainer.new()
	_column = column
	column.anchor_bottom = 1.0
	column.offset_left = 64.0
	column.offset_right = 64.0 + COLUMN_WIDTH
	column.offset_top = 28.0
	column.offset_bottom = -28.0
	column.add_theme_constant_override("separation", 14)
	column.theme = _menu_theme()
	add_child(column)

	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Drawn at a sixth to a third of its 1600 px: without mipmaps (on in its import) that
	# shrink skips pixels and the lettering's edges come out jagged and over-sharp.
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.custom_minimum_size = Vector2(0.0, LOGO_HEIGHT_MAX)
	column.add_child(logo)
	_logo = logo
	get_viewport().size_changed.connect(_fit_logo)

	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_body)
	_pages[Page.MAIN] = _build_main_page()
	_pages[Page.HOST] = _build_host_page()
	_pages[Page.BROWSE] = _build_browse_page()
	_pages[Page.LOBBY] = _build_lobby_page()
	for key in _pages:
		(_pages[key] as Control).custom_minimum_size.x = float(PAGE_WIDTH[key])
		_body.add_child(_pages[key])

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	column.add_child(_status_label)

	_build_identity()
	_build_settings_overlay()


## Under the figure on the right: the class's name - which is the picker, opened by clicking
## it - its role, and the player's name. Both are the player's whichever page they go on to -
## solo, hosting or joining - and in the lobby the class can still be changed.
func _build_identity() -> void:
	var identity := VBoxContainer.new()
	identity.name = "Identity"
	identity.anchor_left = _class_preview.figure_column.x
	identity.anchor_right = _class_preview.figure_column.y
	identity.anchor_top = 1.0
	identity.anchor_bottom = 1.0
	identity.offset_left = 24.0
	identity.offset_right = -24.0
	identity.offset_top = -IDENTITY_HEIGHT
	identity.offset_bottom = -22.0
	identity.alignment = BoxContainer.ALIGNMENT_END
	identity.add_theme_constant_override("separation", 4)
	add_child(identity)

	_class_picker = OptionButton.new()
	_class_picker.flat = true
	# As wide as the name it shows, so its arrow stands right beside it.
	_class_picker.fit_to_longest_item = false
	_class_picker.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_class_picker.tooltip_text = "Pick your class"
	_class_picker.add_theme_font_size_override("font_size", 30)
	_class_picker.add_theme_color_override("font_color", METAL_LIGHT)
	for state: String in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_class_picker.add_theme_color_override(state, Color(1.0, 0.92, 0.74))
	_class_picker.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_class_picker.add_theme_constant_override("outline_size", 4)
	_class_picker.get_popup().add_theme_font_size_override("font_size", 18)
	for class_id: String in ClassDatabase.ORDER:
		_class_picker.add_item(ClassDatabase.display_name(class_id).to_upper())
		_class_picker.set_item_metadata(_class_picker.item_count - 1, class_id)
		_class_picker.set_item_tooltip(_class_picker.item_count - 1, String(ClassDatabase.get_class_data(class_id)["role"]))
	_class_picker.select(maxi(ClassDatabase.ORDER.find(Net.local_class()), 0))
	_class_picker.item_selected.connect(_on_class_selected)
	identity.add_child(_class_picker)

	_class_role = Label.new()
	_class_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_role.add_theme_font_size_override("font_size", 14)
	_class_role.add_theme_color_override("font_color", Color(0.82, 0.8, 0.74))
	_class_role.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_class_role.add_theme_constant_override("shadow_offset_y", 1)
	_class_role.text = String(ClassDatabase.get_class_data(Net.local_class())["role"])
	identity.add_child(_class_role)

	# The name, typed once and used by whichever page the player ends up on - and remembered
	# for the next time the game starts.
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.74))
	name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_row.add_child(name_label)
	_name_field = LineEdit.new()
	var saved_name: String = UserSettings.player_name.strip_edges()
	_name_field.text = saved_name if saved_name != "" else "Player"
	_name_field.placeholder_text = "Your name"
	_name_field.max_length = 24
	_name_field.custom_minimum_size = Vector2(240.0, 0.0)
	_name_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# text_changed fires for typing only, never for the autostart flags setting the field,
	# so a "Host" or "Client" test window can never overwrite the name the player chose.
	_name_field.text_changed.connect(func(new_text: String) -> void:
		UserSettings.set_value(&"player_name", new_text.strip_edges()))
	name_row.add_child(_name_field)
	identity.add_child(name_row)


## The menu's buttons stand straight on the painting now, with no panel under them: dark glass
## with a rim of the logo's worn metal, brightening under the pointer and the gamepad's focus.
## Set on the column, so every plain button in it wears it - the ready button keeps its own
## colours (ReadyStyle), and the switches keep the default look.
static func _menu_theme() -> Theme:
	var theme := Theme.new()
	var looks: Dictionary = {
		"normal": [Color(0.02, 0.022, 0.03, 0.74), Color(METAL, 0.4), 1],
		"hover": [Color(0.07, 0.06, 0.05, 0.86), Color(METAL, 0.95), 1],
		"pressed": [Color(0.12, 0.1, 0.07, 0.92), METAL_LIGHT, 1],
		"disabled": [Color(0.02, 0.022, 0.03, 0.5), Color(METAL, 0.15), 1],
		"focus": [Color(0.0, 0.0, 0.0, 0.0), METAL_LIGHT, 2],
	}
	for state: String in looks:
		var look: Array = looks[state]
		var box := StyleBoxFlat.new()
		box.bg_color = look[0]
		box.draw_center = state != "focus"
		box.border_color = look[1]
		box.set_border_width_all(int(look[2]))
		box.set_corner_radius_all(4)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 6.0
		box.content_margin_bottom = 6.0
		theme.set_stylebox(state, "Button", box)
	theme.set_color("font_color", "Button", Color(0.9, 0.86, 0.78))
	for state: String in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", Color(1.0, 0.94, 0.82))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.47))
	# The switches inherit from Button but are a label and a toggle, not a box: they keep
	# their own look rather than taking the buttons'.
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 6.0
	none.content_margin_right = 6.0
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		theme.set_stylebox(state, "CheckButton", none)
	# The labels beside the fields, the headings and the status line, over the painting: a
	# shadow under them, as there is no panel behind them any more.
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.85))
	theme.set_constant("shadow_offset_y", "Label", 1)
	return theme


## The painting behind the menu, a shade down the left so the panel reads over it, and - the
## first time the menu opens in a session - the boot splash laid on top and faded out, so
## the picture the engine started on turns into the menu instead of cutting to it.
func _build_backdrop() -> void:
	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color.BLACK
	add_child(black)
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = MENU_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.88))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0.35, 0.0)
	shade_texture.fill_to = Vector2(1.0, 0.0)
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	if _splash_shown:
		return
	_splash_shown = true
	var splash := TextureRect.new()
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.texture = SPLASH
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Over everything the menu builds after this, menu panel included.
	splash.z_index = 10
	add_child(splash)
	var fade := splash.create_tween()
	fade.tween_interval(0.6)
	fade.tween_property(splash, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(splash.queue_free)


## The options panel, hidden until SETTINGS is pressed. An overlay over the whole menu
## rather than a fifth page: the pages are sized for a handful of buttons, and the options
## need the room - and closing it has to land back on whichever page was open.
func _build_settings_overlay() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.name = "SettingsOverlay"
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.visible = false
	add_child(_settings_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.005, 0.008, 0.012, 0.72)
	_settings_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.03, 1.0)
	style.border_color = Color(0.35, 0.42, 0.55, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	_settings_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	_settings_menu = SettingsMenuScript.new()
	margin.add_child(_settings_menu)
	CloseButton.attach(_settings_overlay, panel, func() -> void: _set_settings_open(false))


func _set_settings_open(open: bool) -> void:
	if _settings_overlay == null or _settings_overlay.visible == open:
		return
	_settings_overlay.visible = open
	if open:
		_settings_menu.focus_first()
	else:
		_focus_page()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_overlay != null and _settings_overlay.visible:
		_set_settings_open(false)
		get_viewport().set_input_as_handled()


func _build_main_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_menu_button("HOST A GAME", func() -> void: _show_page(Page.HOST)))
	page.add_child(_menu_button("JOIN A GAME", func() -> void: _show_page(Page.BROWSE)))
	_reconnect_button = _menu_button("RECONNECT", _on_reconnect_pressed)
	_reconnect_button.visible = false
	page.add_child(_reconnect_button)
	page.add_child(_menu_button("PLAY SOLO", _on_solo_pressed))
	page.add_child(_menu_button("SETTINGS", func() -> void: _set_settings_open(true)))
	page.add_child(_menu_button("QUIT", _on_quit_pressed))
	return page


func _build_host_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(_section_label("HOST A GAME"))

	_server_name_field = LineEdit.new()
	_server_name_field.placeholder_text = "Server name"
	page.add_child(_field_row("Server", _server_name_field))

	_host_port_field = LineEdit.new()
	_host_port_field.text = str(Net.DEFAULT_PORT)
	page.add_child(_field_row("Port", _host_port_field))

	_host_password_field = LineEdit.new()
	_host_password_field.secret = true
	_host_password_field.placeholder_text = "Leave empty for no password"
	page.add_child(_field_row("Password", _host_password_field))

	# Offered only on a build that has both halves of online play - the Firebase
	# settings and the WebRTC extension. Without them the game is what it always was,
	# and a switch that cannot work is worse than no switch.
	_online_host_check = CheckButton.new()
	_online_host_check.text = "List this game online"
	_online_host_check.tooltip_text = "Players find the game through the online browser and connect straight to you. No port forwarding."
	_online_host_check.visible = NetOnline.is_available()
	_online_host_check.toggled.connect(_on_host_online_toggled)
	page.add_child(_online_host_check)

	page.add_child(_spacer())
	page.add_child(_menu_button("CREATE LOBBY", _on_create_pressed))
	page.add_child(_menu_button("BACK", func() -> void: _show_page(Page.MAIN)))
	return page


## An online host opens no port, so the port field has nothing to say. Greying it out
## rather than hiding it keeps the page from jumping about as the switch is flipped.
func _on_host_online_toggled(online: bool) -> void:
	_host_port_field.editable = not online
	_set_status(
		"Online: players connect directly to you, found through the browser."
		if online else ""
	)


func _build_browse_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_browse_heading = _section_label("GAMES ON THIS NETWORK")
	page.add_child(_browse_heading)

	_online_browse_check = CheckButton.new()
	_online_browse_check.text = "Search online"
	_online_browse_check.visible = NetOnline.is_available()
	_online_browse_check.toggled.connect(_on_browse_source_toggled)
	page.add_child(_online_browse_check)

	_server_list = ItemList.new()
	_server_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_server_list.custom_minimum_size = Vector2(0.0, 140.0)
	_server_list.item_activated.connect(func(_index: int) -> void: _on_join_pressed())
	page.add_child(_server_list)

	_scan_button = Button.new()
	_scan_button.text = "SCAN"
	_scan_button.custom_minimum_size = Vector2(0.0, 34.0)
	_scan_button.pressed.connect(_on_scan_pressed)
	page.add_child(_scan_button)

	# Discovery is a broadcast, and a broadcast does not always cross a router or a
	# VPN. Typing the host's address has to stay possible when it does not.
	_direct_address_field = LineEdit.new()
	_direct_address_field.placeholder_text = "127.0.0.1"
	page.add_child(_field_row("Address", _direct_address_field))

	_join_password_field = LineEdit.new()
	_join_password_field.secret = true
	_join_password_field.placeholder_text = "Password, if the game has one"
	page.add_child(_field_row("Password", _join_password_field))

	_join_button = Button.new()
	_join_button.text = "JOIN"
	_join_button.custom_minimum_size = Vector2(0.0, 34.0)
	_join_button.pressed.connect(_on_join_pressed)
	page.add_child(_join_button)
	page.add_child(_menu_button("BACK", func() -> void: _show_page(Page.MAIN)))
	return page


func _build_lobby_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_lobby_title = Label.new()
	_lobby_title.add_theme_font_size_override("font_size", 18)
	_lobby_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	page.add_child(_lobby_title)
	page.add_child(_section_label("PLAYERS"))

	_peer_list = VBoxContainer.new()
	_peer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_peer_list)

	_ready_button = Button.new()
	_ready_button.text = "READY"
	_ready_button.custom_minimum_size = Vector2(0.0, 36.0)
	_ready_button.pressed.connect(_on_ready_pressed)
	page.add_child(_ready_button)

	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.custom_minimum_size = Vector2(0.0, 40.0)
	_start_button.pressed.connect(_on_start_pressed)
	page.add_child(_start_button)

	page.add_child(_menu_button("LEAVE", _on_leave_pressed))
	return page


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(action)
	return button


func _field_row(label_text: String, field: LineEdit) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80.0, 0.0)
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
