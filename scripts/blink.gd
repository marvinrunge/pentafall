class_name Blink
extends ClassDefence
## The mage's defence: the block button blinks instead (docs/CHARACTER_CLASSES_PLAN.md).
##
## The archer's roll travels; a blink does not - the mage is simply somewhere else, the way the
## stick points (backwards with none, out of whatever was in front), mage_blink_distance away
## or short of the first thing solid in the way. Untouchable for mage_blink_invulnerable_time
## from the moment it lands, so a blow already on its way finds nobody.
##
## Moved here, on the machine that drives the player: position is the owner's to publish. The
## untouchable window is set on the server too, where the hits land (Player._net_evade_guard,
## the roll's). Blink of an Eye, the level-6 skill, is the long version with a decoy left
## behind (MageSkills).

## Chest height: the line the blink is checked along, so a knee-high rock does not stop it but
## a wall does.
const CHECK_HEIGHT := 1.0
## Kept between the mage and whatever stopped the blink, metres - a capsule's radius and a bit.
const WALL_MARGIN := 0.6
## The environment (layer 5) - never enemies, players or allies, which a blink passes.
const BLOCK_MASK: int = 16

var _cooldown: float = 0.0


func _init(owner: Player) -> void:
	player = owner


func update() -> void:
	if _cooldown > 0.0:
		_cooldown -= player.get_physics_process_delta_time()
	if not player.is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not Input.is_action_just_pressed("block"):
		return
	if not can_blink():
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	blink(input)


## Ready, and not tied up in anything a blink may not cut short. A bolt in flight may be -
## blinking out of a throw is the point - a cast, a channel or a held spell may not. Unlike the
## roll it works in the air: there is nothing to push off.
func can_blink() -> bool:
	if _cooldown > 0.0 or player.is_downed or player._stagger_timer > 0.0:
		return false
	if player.is_charging or player._channel_id != "" or player._is_evading():
		return false
	return player._action_timer <= 0.0 or player._action_is_melee


## Blinks along `input` (the move stick, body-relative: +y is back) - backwards with none.
func blink(input: Vector2) -> void:
	if input.length_squared() < 0.04:
		input = Vector2(0.0, 1.0)
	_cooldown = GameSettings.mage_blink_cooldown
	var direction: Vector3 = player.global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	blink_to(player, landing(player, direction.normalized(), GameSettings.mage_blink_distance))


## Where a blink of up to `distance` along `direction` (flat) from `who` ends: short of the
## first solid thing at chest height, then put down on the ground there.
static func landing(who: Player, direction: Vector3, distance: float) -> Vector3:
	var from: Vector3 = who.global_position + Vector3(0.0, CHECK_HEIGHT, 0.0)
	var to: Vector3 = from + direction * distance
	var query := PhysicsRayQueryParameters3D.create(from, to, BLOCK_MASK)
	query.exclude = [who.get_rid()]
	var hit: Dictionary = who.get_world_3d().direct_space_state.intersect_ray(query)
	var reach: float = distance
	if hit:
		reach = maxf(from.distance_to(hit["position"]) - WALL_MARGIN, 0.0)
	var flat: Vector3 = who.global_position + direction * reach
	return who._ground_snap(flat + Vector3(0.0, CHECK_HEIGHT, 0.0), BLOCK_MASK)


## The blink itself, on the machine that owns `who`: gone from here in a flash of the path's
## colour, there in another, untouchable for a moment. Whatever the mage was throwing is let
## go - a bolt does not follow them through.
static func blink_to(who: Player, target: Vector3) -> void:
	var from: Vector3 = who.global_position
	who.kit.cancel()
	who._stop_action_everywhere()
	who._action_timer = 0.0
	who._action_duration = 0.0
	who._action_is_melee = false
	who._action_is_heavy = false
	who._action_roots_player = false
	who.global_position = target
	who.velocity = Vector3.ZERO
	who._invulnerable_timer = maxf(who._invulnerable_timer, GameSettings.mage_blink_invulnerable_time)
	if Net.is_active() and not Net.is_server():
		who._net_evade_guard.rpc_id(1, GameSettings.mage_blink_invulnerable_time)
	show_blink(who, from, target)


## The flash at both ends, on every screen, in the path's colour - which rides on the effect's
## id (SpellVisuals._play_mage).
static func show_blink(who: Player, from: Vector3, to: Vector3) -> void:
	var suffix: String = "/" + who.path_color()
	NetFx.spell("mage_blink_from" + suffix, from, 1.0, who._fx_peer())
	NetFx.spell("mage_blink" + suffix, to, 1.0, who._fx_peer())
	NetFx.sound(&"spell_cast", to)
