class_name BowKit
extends AttackKit
## The archer's basic attack: hold to draw, release to shoot; a tap is a quick shot
## (docs/CHARACTER_CLASSES_PLAN.md).
##
## Built on the three clips of the Pro Longbow pack, measured on the rig (hands apart, in
## metres): `draw` reaches over the shoulder, nocks at about half way and ends at the anchor
## with the string at the cheek (0.69); `aim` holds that anchor and slowly OVERDRAWS, the
## hands parting from 0.69 to 0.81 over its 3.8 s; `shoot` lets go a tenth of a second in and
## recovers. So the draw plays at its own pace, the hold plays `aim` fast enough to reach the
## overdraw in archer_full_draw_time and then stops on it, and the release fires the arrow on
## the press of `shoot`.
##
## A press released during the draw still shoots - at the anchor, as a quick shot - so a tap
## is the archer's fast, light attack, and holding is the slow, heavy one. Holding the button
## through a release starts the next draw on its own.
##
## The arrow is resolved on this machine, like the axe: it flies here, hits here, and only the
## damage travels to the server (Player._deal_damage). The other screens get the same arrow as
## a visual from _net_spawn_arrow.

enum State { IDLE, DRAWING, HOLDING, SHOOTING }

var draw_clip: String = "draw"
var aim_clip: String = "aim"
var shoot_clip: String = "shoot"
## How far into `aim` a full draw gets, seconds of clip - the hands are 0.79 m apart there,
## all but the whole overdraw. Well short of the clip's end on purpose: the action one-shot
## starts fading back to idle once less than its fade time is left, so the hold has to sit
## where there is always more than that ahead of it.
var aim_overdraw_at: float = 3.15
## The hold does not stop dead at a full draw: the one-shot reads a time scale of exactly 0
## as finished and drops the pose. It creeps on at this many clip-seconds a second instead,
## which is invisible and never reaches the end within HOLD_LIMIT.
const HOLD_CREEP := 0.02
## The longest a draw can be held before the arrow goes on its own.
const HOLD_LIMIT := 20.0

var _state: State = State.IDLE
## The attack button is down - read from input, kept here so the draw knows at its end
## whether to hold or let go.
var _held: bool = false
var _draw_elapsed: float = 0.0
var _hold_elapsed: float = 0.0
var _at_full_draw: bool = false
## A press that came while the release was still playing, kept for
## player_attack_buffer_time so a quick double-tap is not lost.
var _buffered_timer: float = 0.0
## The kick is the warrior's, borrowed whole: the archer keeps the boot for making room.
var _boot: MeleeKit


func _init(owner: Player) -> void:
	player = owner
	_boot = MeleeKit.new(owner)
	_boot.kick_clip = "kick"


## How far the draw has got, 0 at the anchor and 1 at a full draw. 0 while drawing.
func charge() -> float:
	if _state != State.HOLDING:
		return 0.0
	return clampf(_hold_elapsed / maxf(GameSettings.archer_full_draw_time, 0.01), 0.0, 1.0)


func is_drawing() -> bool:
	return _state == State.DRAWING or _state == State.HOLDING


func tick(delta: float) -> void:
	_boot.tick(delta)
	if _buffered_timer > 0.0:
		_buffered_timer -= delta
	match _state:
		State.DRAWING:
			_draw_elapsed += delta
			if _draw_elapsed >= _draw_duration():
				if _held:
					_anchor()
				else:
					_release()
		State.HOLDING:
			_hold_elapsed += delta
			if player.is_local:
				SignalBus.bow_draw_changed.emit(charge(), true)
			if not _at_full_draw and _hold_elapsed >= GameSettings.archer_full_draw_time:
				_at_full_draw = true
				player._set_action_speed(HOLD_CREEP)
			if _hold_elapsed >= HOLD_LIMIT:
				_release()
		State.SHOOTING:
			if player._action_timer <= 0.0:
				_state = State.IDLE


func land_due_hits() -> void:
	_boot.land_due_hits()


func read_input() -> void:
	if Input.is_action_just_pressed("kick"):
		if is_drawing():
			_abandon()
		_boot.try_kick()

	# Press first, release after, so a click that lands both inside one frame still draws -
	# and, having let go, shoots as a quick shot at the end of the draw.
	if Input.is_action_just_pressed("attack"):
		_held = true
		_buffered_timer = GameSettings.player_attack_buffer_time
	if _state == State.SHOOTING and player._action_timer <= 0.0:
		_state = State.IDLE
	if (_held or _buffered_timer > 0.0) and _state == State.IDLE and player._can_start_attack():
		_buffered_timer = 0.0
		_begin_draw()
	if _held and (Input.is_action_just_released("attack") or not Input.is_action_pressed("attack")):
		_held = false
		if _state == State.HOLDING:
			_release()


func drop_swing() -> void:
	_held = false
	_buffered_timer = 0.0
	if is_drawing():
		_abandon()


func drop_hits() -> void:
	_boot.drop_hits()


func cancel() -> void:
	_boot.cancel()
	_held = false
	if is_drawing():
		_end_charge_bar()
	_state = State.IDLE


func move_speed_mult() -> float:
	return GameSettings.archer_draw_move_mult if is_drawing() else 1.0


## The camera closes in as the arrow comes back: half way by the anchor, all the way at a
## full draw, and straight back out once it is loosed (or the draw is given up).
func aim_zoom() -> float:
	match _state:
		State.DRAWING:
			return 0.5 * clampf(_draw_elapsed / maxf(_draw_duration(), 0.01), 0.0, 1.0)
		State.HOLDING:
			return 0.5 + 0.5 * charge()
	return 0.0


# --- the shot ---------------------------------------------------------------------------------

## Fervor quickens the draw the way it quickens a swing.
func _draw_duration() -> float:
	return GameSettings.archer_draw_time / player._attack_speed_mult()


func _begin_draw() -> void:
	_state = State.DRAWING
	_draw_elapsed = 0.0
	_hold_elapsed = 0.0
	_at_full_draw = false
	player._pending_cast_id = ""
	# Upper body: the legs keep walking under a draw, at archer_draw_move_mult. Marked as a
	# basic attack (is_melee), which is what lets a spell cut it off (Player._yield_melee_to_cast).
	player._begin_action(draw_clip, _draw_duration(), true, false, true)


## The draw reached the cheek with the button still down: hold there and overdraw.
func _anchor() -> void:
	_state = State.HOLDING
	_hold_elapsed = 0.0
	player._begin_action(aim_clip, HOLD_LIMIT, true, false, true)
	player._set_action_speed(aim_overdraw_at / maxf(GameSettings.archer_full_draw_time, 0.01))


func _release() -> void:
	var drawn: float = charge()
	_end_charge_bar()
	_state = State.SHOOTING
	player._begin_action(shoot_clip, GameSettings.archer_shoot_duration, true, false, true)
	_loose(drawn)


## A draw given up on - a kick, a menu, the button lost - with no arrow.
func _abandon() -> void:
	_end_charge_bar()
	_state = State.IDLE
	player._action_timer = 0.0
	player._action_duration = 0.0
	player._action_is_melee = false
	player._stop_action_everywhere()


func _end_charge_bar() -> void:
	if player.is_local:
		SignalBus.bow_draw_changed.emit(0.0, false)


## The arrow itself: from the bow hand, at what the crosshair is on.
func _loose(drawn: float) -> void:
	var damage_mult: float = lerpf(GameSettings.archer_quick_shot_damage_mult, GameSettings.archer_full_draw_damage_mult, drawn)
	var damage: float = GameSettings.spell_melee_damage * damage_mult
	damage *= player.get_spell_damage_multiplier() * player._giant_damage_mult()
	# The rest of what a basic attack carries, exactly as the axe's apply_hit() spends it:
	# Loxodon Warhammer's share of the health pool, an Exalted Strike charge, a Rubblebelt hit.
	damage += player.max_hp * player.equipment_value("loxodon_warhammer")
	var exalted: bool = player.exalted_charges > 0
	if exalted:
		player.exalted_charges -= 1
		damage *= player._exalted_damage_mult
		player._spawn_cast_flash(Color(1.0, 0.97, 0.75), 2.0)
	if player._rampage_hits_left > 0:
		player._rampage_hits_left -= 1
		damage *= GameSettings.guild_gruul_rampage_damage_mult

	var full: bool = drawn >= 1.0
	var pierce: int = GameSettings.archer_longshot_pierce if full and player.has_class_skill("archer_longshot") else 1
	var speed: float = GameSettings.archer_arrow_speed * lerpf(GameSettings.archer_quick_arrow_speed_mult, 1.0, drawn)
	var origin: Vector3 = player.animator.bow_nock_point()
	var target: Vector3 = player.aim_hit_point(GameSettings.archer_arrow_range)
	var direction: Vector3 = (target - origin).normalized()
	if direction.length_squared() < 0.5:
		direction = -player.global_basis.z
	var arrow := PlayerArrow.launch(player, origin, direction * speed, pierce)
	arrow.authority_damage = damage
	arrow.exile_on_kill = exalted
	arrow.deadeye = player.has_class_skill("archer_deadeye")
	player._play_sound(&"arrow_shot", origin)
	if Net.is_active() and player.is_local:
		player._net_spawn_arrow.rpc(origin, direction * speed, pierce)
