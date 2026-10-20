class_name GreatswordKit
extends MeleeKit
## The barbarian's basic attack: the warrior's buttons on a two-handed sword
## (docs/CHARACTER_CLASSES_PLAN.md - "slow and heavy, lives on single huge hits").
##
## A tap is a cleave: the light chain is the Great Sword pack's long flourish, spent one wide
## cut per click (three cuts, measured at the blade's tip by the builder), reaching further
## round than the axe. Unlike the axe's chain it always takes the whole body - the pack's legs
## step into every cut - and the body goes forwards as far as the clip itself travels, at the
## clip's own pace (lunge_speed, from the builder's `root_forward`). A click while the cut
## before is still playing carries on from where it has got to, so a full chain plays as the
## one flourish it was made as. Holding past player_heavy_hold_time is the heavy, exactly as
## the warrior's spin is: it goes off at once, a fixed move - two big swings, the first the
## harder (`heavy_combo`), at the clip's own pace and stepping in with it. The kick is the
## warrior's.
##
## No block. A heavy swing cannot be interrupted instead (unstoppable()), from its first frame
## to the end of the recovery - that is the class's defence.
##
## Also runs Whirlwind (level 6) while it spins, and reads Brute Force, Indomitable and
## Berserk - the three passives and the buff act on the swings themselves.

## Whirlwind spinning: seconds left, and until the next round of hits.
var _whirlwind_timer: float = 0.0
var _whirlwind_tick: float = 0.0
## The swing in flight: its clip and the slice of its strike window it plays - what the chain
## carries on from and what the root motion is read along.
var _action_clip: String = ""
var _action_window: Vector2 = Vector2.ZERO


func _init(owner: Player) -> void:
	super(owner)
	light_chain_clip = "cleave_chain"
	light_chain_stages = 3
	# Blade Dance is the warrior's; the barbarian's chain never changes.
	light_chain_clip_extended = "cleave_chain"
	light_chain_stages_extended = 3
	# No harder last cut: the barbarian's big hit is the heavy, not a finisher.
	light_chain_heavy_stage = 3
	heavy_clip = "heavy_combo"
	kick_clip = "kick"
	# The whoosh is timed to each cut rather than played as the move starts.
	whoosh_before_hit = GameSettings.barbarian_whoosh_lead


func is_spinning() -> bool:
	return _whirlwind_timer > 0.0


func tick(delta: float) -> void:
	super(delta)
	if _whirlwind_timer > 0.0:
		_whirlwind_timer -= delta
		_whirlwind_tick -= delta
		if player.is_local and _whirlwind_tick <= 0.0:
			_whirlwind_tick += GameSettings.barbarian_whirlwind_hit_interval
			_whirlwind_hits()


func cancel() -> void:
	_whirlwind_timer = 0.0
	super()


## The clip's own root motion: the distance the swing in flight walks forwards between this
## frame's playhead and the last one's - the cleaves' steps, and the heavy's step in and
## back out. 0 for a clip without (the kick).
func lunge_speed(delta: float) -> float:
	if _action_clip == "" or not player._action_is_melee or player._action_timer <= 0.0:
		return 0.0
	var duration: float = maxf(player._action_duration, 0.01)
	var now: float = _action_clip_seconds(clampf(player._action_elapsed / duration, 0.0, 1.0))
	var before: float = _action_clip_seconds(clampf((player._action_elapsed - delta) / duration, 0.0, 1.0))
	var animator: PlayerAnimator = player.animator
	return (animator.root_forward(_action_clip, now) - animator.root_forward(_action_clip, before)) / maxf(delta, 0.001)


func move_speed_mult() -> float:
	return GameSettings.barbarian_whirlwind_move_mult if _whirlwind_timer > 0.0 else 1.0


## A heavy swing, from its first frame to the end of its recovery, goes through any hit.
func unstoppable() -> bool:
	return player._action_is_heavy and player._action_timer > 0.0


## Indomitable (level 10): nothing interrupts, slows or flinches the barbarian while any
## swing is in flight - a cleave, the kick, Whirlwind - not only the heavy.
func control_immune() -> bool:
	if not player.has_class_skill("barbarian_indomitable"):
		return false
	return _whirlwind_timer > 0.0 or (player._action_timer > 0.0 and player._action_is_melee)


# --- the numbers --------------------------------------------------------------------------------

## How fast the cleaves play, in clip-seconds per second: the pack's own pace, sped up by
## Fervor and Giant Growth as they speed the axe, and by Berserk on top.
func _cleave_pace() -> float:
	return GameSettings.barbarian_cleave_pace * player._attack_speed_mult() * _berserk_speed()


## An average cut's length - the chain's whole strike window over its stages, at that pace.
func _swing_duration() -> float:
	return player.animator.strike_length(light_chain_clip) / float(light_chain_stages) / _cleave_pace()


func _reach() -> float:
	return GameSettings.barbarian_reach


func _cone() -> float:
	return GameSettings.barbarian_cone


func _light_damage_mult() -> float:
	return GameSettings.barbarian_cleave_damage_mult


func _hit_mult() -> float:
	return GameSettings.barbarian_berserk_damage_mult if player.is_berserk() else 1.0


## Brute Force: the heavy's push lands before its blows (see MeleeKit._strike).
func _knock_first() -> bool:
	return player._action_is_heavy and player.has_class_skill("barbarian_brute_force")


func _berserk_speed() -> float:
	return GameSettings.barbarian_berserk_attack_speed_mult if player.is_berserk() else 1.0


## How fast the heavy plays: the clip's own pace, quickened like a swing.
func _heavy_pace() -> float:
	return GameSettings.barbarian_heavy_pace * player._attack_speed_mult() * _berserk_speed()


# --- the cleaves --------------------------------------------------------------------------------

## One click, one cut - full body, rooted, and carried forwards by the clip (lunge_speed). A
## click inside the combo window starts the next cut from where the playhead already is
## rather than jumping to the cut point: PlayerAnimator then continues the clip in flight
## with no fade (SELF_CONTINUE_TOLERANCE), so the chain never dips back towards idle.
##
## The chain only carries on while the cut before is still playing. Once it has ended and the
## body has gone back to rest, the next click starts over at the first cut - the axe's grace
## period (player_combo_grace) would have played the second cut out of the resting pose, and
## the pack's cuts only read as cuts out of the one before.
func _advance_light_chain() -> void:
	var clip: String = light_chain_clip
	if not player.animator.has_clip(clip):
		push_warning("Light attack chain clip '%s' is missing from the player library" % clip)
		return
	var stage: int = _combo_stage if _combo_stage < light_chain_stages else 0
	var carrying_on: bool = _action_clip == clip and player._action_is_melee and player._action_timer > 0.0
	if not carrying_on:
		stage = 0
	var window: Vector2 = player.animator.combo_windows(clip, light_chain_stages)[stage]
	if stage > 0:
		window.x = minf(window.x, _chain_progress_ratio())
	var duration: float = player.animator.strike_length(clip) * (window.y - window.x) / _cleave_pace()
	_attack_swing_sound = &"blade_swing"
	_attack_impact_sound = &"blade_hit"
	_attack_knockback_strength = GameSettings.spell_melee_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	_combo_stage = stage + 1
	_combo_reset_timer = duration + GameSettings.player_combo_grace
	_begin_melee_action(clip, duration, _light_damage_mult(), false, window)


func _begin_melee_action(clip: String, duration: float, damage_mult: float, upper_body: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_action_clip = clip
	_action_window = window
	super(clip, duration, damage_mult, upper_body, window)
	# MeleeKit marks the heavy before Player._begin_action, whose _commit_action clears the
	# mark again; set after, so the chop really is a heavy (Brute Force, _can_start_attack).
	player._action_is_heavy = clip == heavy_clip


## Where in its strike window (0 to 1) the cut in flight has got to.
func _chain_progress_ratio() -> float:
	var progress: float = clampf(player._action_elapsed / maxf(player._action_duration, 0.01), 0.0, 1.0)
	return lerpf(_action_window.x, _action_window.y, progress)


## The stored clip's own time at `progress` (0 to 1) through the swing in flight.
func _action_clip_seconds(progress: float) -> float:
	var animator: PlayerAnimator = player.animator
	return animator.windup_length(_action_clip) + lerpf(_action_window.x, _action_window.y, progress) * animator.strike_length(_action_clip)


# --- the heavy ------------------------------------------------------------------------------------

## The heavy's two swings: the first deals all of barbarian_heavy_damage_mult, the second
## barbarian_heavy_second_swing_share of it.
func _heavy_hit_shares() -> Array[float]:
	return [1.0, GameSettings.barbarian_heavy_second_swing_share]


## Held past player_heavy_hold_time: the heavy goes off at once and plays through, the way
## the warrior's spin does - both swings at the clip's own pace, rooted, moved by its root
## motion, and both landing (_heavy_hit_shares).
func _start_heavy() -> void:
	reset_chain()
	_attack_swing_sound = &"blade_heavy_swing"
	_attack_impact_sound = &"blade_heavy_hit"
	_attack_knockback_strength = GameSettings.barbarian_heavy_knockback
	if player.has_class_skill("barbarian_brute_force"):
		_attack_knockback_strength *= GameSettings.barbarian_brute_force_knockback_mult
	_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength
	var duration: float = player.animator.strike_length(heavy_clip) / _heavy_pace()
	_begin_melee_action(heavy_clip, duration, GameSettings.barbarian_heavy_damage_mult, false)


# --- Whirlwind (level 6) ------------------------------------------------------------------------

## The spin begins: the cast plays the pose and the animator turns the figure; this deals
## the hits, every barbarian_whirlwind_hit_interval from the first frame.
func start_whirlwind(duration: float) -> void:
	reset_chain()
	super.drop_swing()
	_whirlwind_timer = duration
	_whirlwind_tick = 0.0


## One turn's worth: everything within the radius, whichever way it stands.
func _whirlwind_hits() -> void:
	var dmg: float = GameSettings.spell_melee_damage * GameSettings.barbarian_whirlwind_damage_mult
	dmg *= player.get_spell_damage_multiplier() * player._giant_damage_mult() * _hit_mult()
	var connected: int = 0
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var offset: Vector3 = (e as Node3D).global_position - player.global_position
		offset.y = 0.0
		if offset.length() > GameSettings.barbarian_whirlwind_radius:
			continue
		player._melee_strike(e, dmg, false)
		player._apply_basic_attack_knockback(e, GameSettings.barbarian_whirlwind_knockback)
		connected += 1
	player._play_sound(&"blade_swing", player.global_position)
	if connected > 0:
		player._play_sound(&"blade_hit", player.global_position)
		player._shake(GameSettings.camera_shake_melee_strength, GameSettings.camera_shake_melee_duration)
