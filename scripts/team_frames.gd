class_name TeamFrames
extends VBoxContainer
## The OTHER players of a multiplayer run, down the left edge under the mana row: each one's
## class head in a circle, their health as a red ring that empties as they are hurt, and -
## while they are down - the seconds left before they respawn at the base, which is exactly
## how long a rescue still has.
##
## Everything is read straight off each avatar, every frame. hp and max_hp arrive over the
## host's VitalsSync, is_downed through _net_downed, and the down timer ticks on every peer
## (Player._physics_process), so a client's countdown runs with the host's. Solo there is
## nobody else, and the column is empty.
##
## A downed frame has to be noticed in the middle of a fight, so it does more than grey out: it
## pulses, wears the same cross the minimap draws where they lie (DownedMark), and says how far
## away they are.

const IconStyle := preload("res://scripts/icon_style.gd")
## The stylised class heads, one per ClassDatabase id.
const AVATAR_PATH := "res://assets/icons/avatars/%s.png"
const AVATAR_SIZE := 52.0
const RING_WIDTH := 4.0
const RING_HEALTH := Color(0.9, 0.12, 0.1)
const RING_TRACK := Color(0.0, 0.0, 0.0, 0.6)
## While down the ring turns into the countdown: pale, emptying with the time left.
const RING_DOWNED := Color(0.85, 0.85, 0.9, 0.85)
const DOWNED_TINT := Color(0.65, 0.65, 0.72)

## Who to show. The registry's players other than this machine's own; a test hands in
## stand-ins instead, as anything with the fields read in _Frame.show_player.
var source: Callable = _other_players

var _frames: Array[_Frame] = []
var _hud_scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)


func set_hud_scale(value: float) -> void:
	_hud_scale = value
	for frame: _Frame in _frames:
		frame.set_scale_factor(value)


func _process(_delta: float) -> void:
	var players: Array = source.call()
	while _frames.size() < players.size():
		var frame := _Frame.new()
		frame.set_scale_factor(_hud_scale)
		add_child(frame)
		_frames.append(frame)
	while _frames.size() > players.size():
		_frames.pop_back().queue_free()
	for index: int in players.size():
		_frames[index].show_player(players[index])


func _other_players() -> Array:
	var others: Array = []
	var local: Node3D = PlayerRegistry.get_local()
	for player: Node3D in PlayerRegistry.players:
		if is_instance_valid(player) and player != local:
			others.append(player)
	return others


## One player: the round head with its ring, and the name beside it.
class _Frame:
	extends HBoxContainer

	var _ring: _Ring
	var _avatar: TextureRect
	var _countdown: Label
	var _name: Label
	var _class_id: String = ""
	## The longest down timer seen in this fall - the full length the countdown ring empties
	## from. Reset when they are up again.
	var _down_total: float = 0.0
	var _scale: float = 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 8)
		_ring = _Ring.new()
		add_child(_ring)
		_avatar = TextureRect.new()
		_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_avatar.material = IconStyle.circle_material()
		_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar.show_behind_parent = true
		_ring.add_child(_avatar)
		_countdown = Label.new()
		_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_countdown.add_theme_color_override("font_color", Color.WHITE)
		_countdown.add_theme_color_override("font_outline_color", Color.BLACK)
		_countdown.add_theme_constant_override("outline_size", 6)
		_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(_countdown)
		_name = Label.new()
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name.add_theme_color_override("font_outline_color", Color.BLACK)
		_name.add_theme_constant_override("outline_size", 4)
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_name)

	func set_scale_factor(value: float) -> void:
		_scale = value
		var side: float = AVATAR_SIZE * value
		_ring.custom_minimum_size = Vector2(side, side)
		var inset: float = RING_WIDTH * value
		_avatar.position = Vector2(inset, inset)
		_avatar.size = Vector2(side - inset * 2.0, side - inset * 2.0)
		_countdown.position = Vector2.ZERO
		_countdown.size = Vector2(side, side)
		_countdown.add_theme_font_size_override("font_size", int(round(22.0 * value)))
		_name.add_theme_font_size_override("font_size", int(round(14.0 * value)))
		_ring.width = RING_WIDTH * value

	func show_player(player: Object) -> void:
		var class_id: String = String(player.get("character_class"))
		if class_id != _class_id:
			_class_id = class_id
			var path: String = AVATAR_PATH % class_id
			_avatar.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
		_name.text = String(player.call("display_name")) if player.has_method("display_name") else ""
		var downed: bool = bool(player.get("is_downed"))
		_ring.downed = downed
		if downed:
			var left: float = maxf(float(player.get("down_timer")), 0.0)
			_down_total = maxf(_down_total, left)
			_ring.share = left / _down_total if _down_total > 0.0 else 0.0
			_ring.color = RING_DOWNED
			_countdown.text = str(int(ceil(left)))
			_countdown.visible = true
			_avatar.modulate = DOWNED_TINT.lerp(Color.WHITE, 0.35 * DownedMark.pulse())
			_name.modulate = Color.WHITE
			var distance: float = _distance_to(player)
			if distance >= 0.0:
				_name.text += "\n%d m" % int(round(distance))
		else:
			_down_total = 0.0
			var max_hp: float = float(player.get("max_hp"))
			_ring.share = clampf(float(player.get("hp")) / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
			_ring.color = RING_HEALTH
			_countdown.visible = false
			_avatar.modulate = Color.WHITE
			_name.modulate = Color.WHITE
		_ring.queue_redraw()

	## Metres from this machine's own player to `player`, or -1 when either has no position.
	func _distance_to(player: Object) -> float:
		var local: Node3D = PlayerRegistry.get_local()
		if local == null or not (player is Node3D):
			return -1.0
		return local.global_position.distance_to((player as Node3D).global_position)


## The ring around a head: a dark track, and over it an arc from twelve o'clock clockwise
## that is as long as the share it is given - health, or the time left while down.
class _Ring:
	extends Control

	var share: float = 1.0
	var color: Color = RING_HEALTH
	var width: float = RING_WIDTH
	## Down: a pulsing halo outside the ring and the cross on its shoulder.
	var downed: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5 - width * 0.5
		draw_arc(centre, radius, 0.0, TAU, 64, RING_TRACK, width, true)
		if share > 0.0:
			var start: float = -PI * 0.5
			draw_arc(centre, radius, start, start + TAU * share, maxi(8, int(64.0 * share)), color, width, true)
		if downed:
			var beat: float = DownedMark.pulse()
			draw_arc(centre, radius + width * (1.0 + beat), 0.0, TAU, 64,
				Color(DownedMark.CROSS_COLOR, 0.35 + 0.5 * beat), width, true)
			var half: float = minf(size.x, size.y) * 0.17
			DownedMark.draw_cross(self, Vector2(size.x - half, half), half)
