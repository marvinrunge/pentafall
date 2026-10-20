class_name DodgeRoll
extends ClassDefence
## The archer's defence: the block button rolls instead (docs/CHARACTER_CLASSES_PLAN.md).
##
## A roll goes the way the player is steering - with no direction held it goes backwards,
## out of whatever was in front - and for the first archer_dodge_invulnerable_time of it
## nothing can touch them. It is the archer's answer to the warrior's guard: a guard soaks
## most of every hit for as long as it is held, a roll takes the whole of the hits that land
## in its window and none of the rest.
##
## The roll is the dodge clip for the way it goes, played up to where its hop has landed, and
## the body goes with the hop: fast where the clip's feet push off, slowing as it lands - its
## own root motion (PlayerAnimator.root_travel), stretched to archer_dodge_distance. The
## movement and the untouchable window are Player.start_evade(), which Disengage uses for its
## longer roll as well.

const CLIPS := {
	"forward": "dodge_forward", "back": "dodge_back", "left": "dodge_left", "right": "dodge_right",
}

var _cooldown: float = 0.0
## The roll in flight: its clip (empty when none, or when the clip has no hop to follow), the
## way it goes, how far the clip's hop is stretched, and how long it has been going.
var _roll_clip: String = ""
var _roll_direction: Vector3 = Vector3.ZERO
var _roll_stretch: float = 1.0
var _roll_elapsed: float = 0.0


func _init(owner: Player) -> void:
	player = owner


func update() -> void:
	var delta: float = player.get_physics_process_delta_time()
	if _cooldown > 0.0:
		_cooldown -= delta
	_steer_roll(delta)
	if not player.is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not Input.is_action_just_pressed("block"):
		return
	if not can_roll():
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	roll(input)


## Ready, on the ground and not tied up in anything a roll may not cut short. A basic attack
## may be: rolling out of a draw is the point. A cast, a channel or a held spell may not.
func can_roll() -> bool:
	if _cooldown > 0.0 or player.is_downed or player._stagger_timer > 0.0 or not player.is_on_floor():
		return false
	if player.is_charging or player._channel_id != "" or player._is_evading():
		return false
	return player._action_timer <= 0.0 or player._action_is_melee


## Rolls along `input` (the move stick, body-relative: +y is back) - backwards with none.
func roll(input: Vector2) -> void:
	if input.length_squared() < 0.04:
		input = Vector2(0.0, 1.0)
	_cooldown = GameSettings.archer_dodge_cooldown
	var direction: Vector3 = (player.global_basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	direction = direction.normalized()
	var clip: String = clip_for(input)
	var animator: PlayerAnimator = player.animator
	# Up to where the hop has landed: the rest of the clip is the archer straightening up, and
	# a roll the player cannot move out of for that long reads as being stuck.
	var landed: float = animator.root_travel_end(clip)
	var hop: float = animator.root_travel(clip, landed)
	var clip_length: float = maxf(animator.strike_length(clip), 0.01)
	_roll_clip = clip if hop > 0.01 else ""
	_roll_direction = direction
	_roll_stretch = GameSettings.archer_dodge_distance / hop if hop > 0.01 else 1.0
	_roll_elapsed = 0.0
	player.start_evade(
		direction * GameSettings.archer_dodge_distance, landed / GameSettings.archer_dodge_pace,
		GameSettings.archer_dodge_invulnerable_time, clip, Vector2(0.0, clampf(landed / clip_length, 0.01, 1.0))
	)
	# The first frame goes with the hop as well, not at the roll's average speed.
	_steer_roll(player.get_physics_process_delta_time())


## While the roll is in flight, the body goes as fast as the clip's hop does at this point of
## it. Runs before the player moves (Player._physics_process calls update() first).
func _steer_roll(delta: float) -> void:
	if _roll_clip == "":
		return
	if not player._is_evading():
		_roll_clip = ""
		return
	_roll_elapsed += delta
	var pace: float = GameSettings.archer_dodge_pace
	var animator: PlayerAnimator = player.animator
	var travelled: float = animator.root_travel(_roll_clip, _roll_elapsed * pace) - animator.root_travel(_roll_clip, (_roll_elapsed - delta) * pace)
	player._evade_velocity = _roll_direction * travelled * _roll_stretch / maxf(delta, 0.001)


## The clip that rolls the way `input` points: whichever axis it leans on most.
static func clip_for(input: Vector2) -> String:
	if absf(input.x) > absf(input.y):
		return CLIPS["right"] if input.x > 0.0 else CLIPS["left"]
	return CLIPS["back"] if input.y > 0.0 else CLIPS["forward"]
