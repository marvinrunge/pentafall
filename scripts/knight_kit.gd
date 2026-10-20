class_name KnightKit
extends MeleeKit
## The knight's basic attack: the warrior's buttons with a sword and a shield
## (docs/CHARACTER_CLASSES_PLAN.md - the tank).
##
## A tap is a cut: the light chain is the pack's long combo (`slash_chain`, its "slash (2)"),
## spent one cut per click - three cuts, measured at the blade's tip by the builder - the way
## the barbarian spends its cleaves (GreatswordKit). It always takes the whole body, and the
## body goes forwards as far as the clip itself steps (lunge_speed, from the builder's
## `root_forward`), at the clip's own pace. A click while the cut before is still playing
## carries on from where it has got to, so a full chain plays as the one combo it was made as;
## once it has ended, the chain starts over at the first cut. Holding past
## player_heavy_hold_time sets the heavy off at once, as the warrior's spin is: `heavy_slash`,
## the pack's biggest cut, played whole and stepping in with it. The kick is the warrior's. The
## guard is KnightGuard.
##
## First Strike (level 3) is here: after the shield stops a hit, the next swing that comes
## within knight_first_strike_window plays faster and hits harder - the riposte.

## The swing in flight: its clip and the slice of its strike window it plays - what the chain
## carries on from and what the root motion is read along.
var _action_clip: String = ""
var _action_window: Vector2 = Vector2.ZERO
## First Strike: seconds left to riposte in.
var _riposte_timer: float = 0.0


func _init(owner: Player) -> void:
	super(owner)
	light_chain_clip = "slash_chain"
	light_chain_stages = 3
	# Blade Dance is the warrior's; the knight's chain never changes.
	light_chain_clip_extended = "slash_chain"
	light_chain_stages_extended = 3
	# No harder last cut: the knight's big hit is the heavy, not a finisher.
	light_chain_heavy_stage = 3
	heavy_clip = "heavy_slash"
	kick_clip = "kick"
	# The whoosh is timed to each cut rather than played as the move starts.
	whoosh_before_hit = GameSettings.knight_whoosh_lead


func tick(delta: float) -> void:
	super(delta)
	if _riposte_timer > 0.0:
		_riposte_timer -= delta


func on_blocked() -> void:
	if player.has_class_skill("knight_first_strike"):
		_riposte_timer = GameSettings.knight_first_strike_window


## The clip's own root motion: the distance the swing in flight walks forwards between this
## frame's playhead and the last one's - the chain's steps, and the heavy's step in. 0 for a
## clip without (the kick).
func lunge_speed(delta: float) -> float:
	if _action_clip == "" or not player._action_is_melee or player._action_timer <= 0.0:
		return 0.0
	var duration: float = maxf(player._action_duration, 0.01)
	var now: float = _action_clip_seconds(clampf(player._action_elapsed / duration, 0.0, 1.0))
	var before: float = _action_clip_seconds(clampf((player._action_elapsed - delta) / duration, 0.0, 1.0))
	var animator: PlayerAnimator = player.animator
	return (animator.root_forward(_action_clip, now) - animator.root_forward(_action_clip, before)) / maxf(delta, 0.001)


## Whether the next swing is a riposte, spending it if so.
func _take_riposte() -> bool:
	if _riposte_timer <= 0.0:
		return false
	_riposte_timer = 0.0
	player._spawn_cast_flash(Player.FX_WHITE, 1.4)
	return true


## One click, one cut - full body, rooted, and carried forwards by the clip (lunge_speed). A
## click while the cut before is still playing starts the next cut from where the playhead
## already is rather than jumping to the cut point, so the chain never dips back towards idle
## (GreatswordKit._advance_light_chain says why). Once the cut has ended, the next click starts
## over at the first.
func _advance_light_chain() -> void:
	var clip: String = light_chain_clip
	if not player.animator.has_clip(clip):
		push_warning("Knight chain clip '%s' is missing from the player library" % clip)
		return
	var stage: int = _combo_stage if _combo_stage < light_chain_stages else 0
	var carrying_on: bool = _action_clip == clip and player._action_is_melee and player._action_timer > 0.0
	if not carrying_on:
		stage = 0
	var window: Vector2 = player.animator.combo_windows(clip, light_chain_stages)[stage]
	# A cut is paid for the share of the chain it plays: the first is a quick cut, the last the
	# leap and the slam. Paid the same, tapping one cut and letting it play out over and over
	# was the quick first cut again and again - twice the chain's damage a second.
	var damage_mult: float = GameSettings.knight_cut_damage_mult * _stage_share(window)
	if stage > 0:
		window.x = minf(window.x, _chain_progress_ratio())
	var pace: float = GameSettings.knight_cut_pace * player._attack_speed_mult()
	if _take_riposte():
		pace *= GameSettings.knight_first_strike_pace_mult
		damage_mult *= GameSettings.knight_first_strike_damage_mult
	var duration: float = player.animator.strike_length(clip) * (window.y - window.x) / pace
	_attack_swing_sound = &"blade_swing"
	_attack_impact_sound = &"blade_hit"
	_attack_knockback_strength = GameSettings.spell_melee_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	_combo_stage = stage + 1
	_combo_reset_timer = duration + GameSettings.player_combo_grace
	_begin_melee_action(clip, duration, damage_mult, false, window)


## Held past player_heavy_hold_time: the big cut goes off at once and plays through.
func _start_heavy() -> void:
	reset_chain()
	var pace: float = GameSettings.knight_heavy_pace * player._attack_speed_mult()
	var damage_mult: float = GameSettings.knight_heavy_damage_mult
	if _take_riposte():
		pace *= GameSettings.knight_first_strike_pace_mult
		damage_mult *= GameSettings.knight_first_strike_damage_mult
	_attack_swing_sound = &"blade_heavy_swing"
	_attack_impact_sound = &"blade_heavy_hit"
	_attack_knockback_strength = GameSettings.player_heavy_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength
	_begin_melee_action(heavy_clip, player.animator.strike_length(heavy_clip) / pace, damage_mult, false)


func _begin_melee_action(clip: String, duration: float, damage_mult: float, upper_body: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_action_clip = clip
	_action_window = window
	super(clip, duration, damage_mult, upper_body, window)
	# MeleeKit marks the heavy before Player._begin_action, whose _commit_action clears the
	# mark again; set after, so the big cut really is a heavy.
	player._action_is_heavy = clip == heavy_clip


## How much of an average cut the chain's stage `window` is: 1 for a third of the chain.
func _stage_share(window: Vector2) -> float:
	return (window.y - window.x) * float(light_chain_stages)


## Where in its strike window (0 to 1) the cut in flight has got to.
func _chain_progress_ratio() -> float:
	var progress: float = clampf(player._action_elapsed / maxf(player._action_duration, 0.01), 0.0, 1.0)
	return lerpf(_action_window.x, _action_window.y, progress)


## The stored clip's own time at `progress` (0 to 1) through the swing in flight.
func _action_clip_seconds(progress: float) -> float:
	var animator: PlayerAnimator = player.animator
	return animator.windup_length(_action_clip) + lerpf(_action_window.x, _action_window.y, progress) * animator.strike_length(_action_clip)
