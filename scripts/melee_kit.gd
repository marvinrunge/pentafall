class_name MeleeKit
extends AttackKit
## The warrior's basic attack: the light chain, the heavy spin and the kick
## (docs/CHARACTER_CLASSES_PLAN.md, "Attacks as kits").
##
## Lifted out of Player, which still owns everything an attack shares with a cast: the
## committed-action clock (_begin_action, _commit_action, _action_timer), the network
## messages that play it on the other screens, and what a hit does once it lands
## (_deal_damage, _melee_strike, the equipment and guild hooks). This decides WHEN a press
## becomes a swing, WHICH swing, and WHERE its impact frames reach. A class that fights
## with the same moves on other clips - the barbarian's two-hander - is this kit with
## other values in the clip and number fields below.
##
## Two moves, both fired on the button's RELEASE: a tap is a light attack, holding past
## player_heavy_hold_time is the heavy spin. Firing on release is what lets one button
## carry both without the light attack having to wait out the hold threshold to find out
## which it is; player_attack_buffer_time then holds a release that arrives slightly too
## early until the swing in flight can be chained out of.
##
## The light attack is a CHAIN: one stored multi-hit flourish, spent one stage per click,
## so a single tap plays the opening stage and fades back to the resting pose while a
## second well-timed tap continues into the next stage instead of restarting. The clip is
## split into its stages by PlayerAnimator.combo_windows(). Blade Dance
## (Player.melee_combo_extended) swaps the two-stage clip for a three-stage one whose last
## stage lands harder.
##
## Damage does not land on the keypress. Each attack clip carries the moments its weapon
## actually connects (measured at build time by tools/player_character_builder.gd) and
## those are queued as _pending_hits.

# --- what this kit swings: the warrior's axe ------------------------------------------------
var light_chain_clip: String = "combo_3"
var light_chain_stages: int = 2
var light_chain_clip_extended: String = "combo_2"
var light_chain_stages_extended: int = 3
## The third stage and beyond, i.e. only ever the last stage of the extended chain.
var light_chain_heavy_stage: int = 2
var heavy_clip: String = "spin_high"
var kick_clip: String = "kick"
## The heavy spin's step forward, metres, over the swing's progress - see lunge_speed.
var heavy_lunge_distance: float = 0.65
var heavy_lunge_extra_distance: float = 0.35
var heavy_lunge_extra_start: float = 0.50
var heavy_lunge_extra_end: float = 0.70
## When a swing's whoosh is heard. Negative (the axe): as the move starts. Otherwise it is
## timed to each impact the swing will land, so the loudest moment of the sound (WHOOSH_PEAK)
## comes this many seconds before the blade does - 0 is together, with the blade at its
## fastest (GreatswordKit, GameSettings.barbarian_whoosh_lead).
var whoosh_before_hit: float = -1.0
## Where each swing sound is loudest, seconds from its start - measured on the recordings
## (sound_bank.gd: axe-swing1/2 at 0.07 and 0.11 s, axe-heavy-swing at 0.23 s).
const WHOOSH_PEAK := {&"blade_swing": 0.09, &"blade_heavy_swing": 0.23, &"blunt_swing": 0.09}

# --- the chain in progress ------------------------------------------------------------------
## How many stages of the light chain have been spent. Reset by anything that breaks
## the chain, so the next click starts it over from its opening stage.
var _combo_stage: int = 0
## The chain lapses if nothing continues it, so a stage landed a minute ago isn't still
## counted as step one.
var _combo_reset_timer: float = 0.0
## Seconds the attack button has been held, or -1 when it is not down. The swing fires on
## RELEASE, and how long it was held is what picks light versus heavy.
var _attack_hold_timer: float = -1.0
## A resolved-but-not-yet-startable swing ("L"/"H"), held for player_attack_buffer_time so
## a release that lands just before the combo window opens still connects instead of
## being silently dropped.
var _buffered_swing: String = ""
var _buffered_swing_timer: float = 0.0
## Bloodthirst (the warrior's level 3): a kill by the swing in flight quickens the next stage.
var _bloodthirst_ready: bool = false
## Battle Frenzy (the warrior's level 14): seconds left in which the chain does not end, and
## whether the swing in flight has connected yet - what keeps a frenzied chain going.
var _frenzy_timer: float = 0.0
var _swing_connected: bool = false

# --- the swing in flight --------------------------------------------------------------------
## Impact moments still to pay out for the swing in flight, earliest first, in seconds of
## the player's committed action (Player._action_elapsed).
var _pending_hits: Array[float] = []
## What each of those impacts deals, as the damage multiplier apply_hit() takes - one entry per
## _pending_hits entry. All the swing's own multiplier, except for a heavy that lands more than
## once (_heavy_hit_shares).
var _pending_hit_mults: Array[float] = []
## Whooshes still to play for the swing in flight, in seconds of the action (whoosh_before_hit).
var _pending_whooshes: Array[float] = []
var _attack_damage_mult: float = 1.0
## What the move in flight sounds like: the swing through the air, played the moment it
## starts, and the impact, played on each frame that actually connects. A miss is just the
## first with nothing after it. Chosen where the move is started rather than derived from
## the damage multiplier, because the kick is a boot rather than a blade while dealing
## nothing like an enemy club's damage.
var _attack_swing_sound: StringName = &"blade_swing"
var _attack_impact_sound: StringName = &"blade_hit"
var _attack_knockback_strength: float = GameSettings.spell_melee_knockback
## How hard a connecting impact kicks the camera. Chosen alongside the sounds, for the same
## reason: it is a property of the move, not of its damage number.
var _attack_shake_strength: float = 0.0
## AttackCharges.Weight of the swing in flight: the kick is neither, the heavy clip is heavy and
## everything else - the chain, its finisher included - is light. Said by the kit where the
## swing starts rather than read off Player._action_is_heavy, which _commit_action clears.
var _attack_weight: int = AttackCharges.Weight.NONE
## What the swing carries (AttackLoad), taken on its first impact frame - so a swing a cast
## cuts off before it lands spends no charge - and kept for every impact after.
var _load: RefCounted = null
var _load_taken: bool = false


func _init(owner: Player) -> void:
	player = owner


## The chain's and the button's clocks. Every frame, on every machine.
func tick(delta: float) -> void:
	if _frenzy_timer > 0.0:
		_frenzy_timer -= delta
	if _combo_reset_timer > 0.0:
		_combo_reset_timer -= delta
		# In a Battle Frenzy a chain that keeps connecting does not lapse.
		if _combo_reset_timer <= 0.0 and not (_frenzy_timer > 0.0 and _swing_connected):
			_combo_stage = 0
	if _attack_hold_timer >= 0.0:
		_attack_hold_timer += delta
	if _buffered_swing_timer > 0.0:
		_buffered_swing_timer -= delta
		if _buffered_swing_timer <= 0.0:
			_buffered_swing = ""


## Pays out every impact frame the action in flight has reached. Called while an action
## is running; a cast has no hits queued, so this does nothing for one.
func land_due_hits() -> void:
	while not _pending_whooshes.is_empty() and _pending_whooshes[0] <= player._action_elapsed:
		_pending_whooshes.remove_at(0)
		player._play_sound(_attack_swing_sound, player.global_position)
	while not _pending_hits.is_empty() and _pending_hits[0] <= player._action_elapsed:
		_pending_hits.remove_at(0)
		if not _load_taken:
			_load_taken = true
			_load = player.attack_charges.take(_attack_weight)
		var hit_mult: float = _pending_hit_mults.pop_front() if not _pending_hit_mults.is_empty() else _attack_damage_mult
		if apply_hit(hit_mult) > 0:
			_swing_connected = true
			player._reduce_spell_cooldowns(GameSettings.melee_hit_cooldown_reduction)
			# The swing was already heard when the move began; this is the weapon
			# arriving. A whiff simply never reaches this line.
			player._play_sound(_attack_impact_sound, player.global_position)
			player._shake(_attack_shake_strength, GameSettings.camera_shake_melee_duration)


## The local player's buttons. Nothing fires on the press - it only starts the clock.
## Firing on press and then swapping the clip once the hold threshold passed used to cut
## the light swing off mid-stroke, which is the whole reason this is release-driven.
func read_input() -> void:
	if Input.is_action_just_pressed("kick"):
		_try_kick()

	if player.is_blocking:
		drop_swing()
	else:
		# Press and release are checked independently, NOT as an if/elif chain: a click
		# fast enough to land both inside one physics frame reports both as "just"
		# happened, and an elif would take the press and never see the release, silently
		# eating the attack. Handling both in order resolves it as a zero-length hold,
		# i.e. a light tap.
		if Input.is_action_just_pressed("attack"):
			_attack_hold_timer = 0.0
		if Input.is_action_just_released("attack") and _attack_hold_timer >= 0.0:
			_buffered_swing = "H" if _attack_hold_timer >= GameSettings.player_heavy_hold_time else "L"
			_buffered_swing_timer = GameSettings.player_attack_buffer_time
			_attack_hold_timer = -1.0
		_start_heavy_when_held()

	if _buffered_swing != "" and player._can_start_attack():
		var symbol := _buffered_swing
		drop_swing()
		_try_attack(symbol)


## Forgets a press in progress and a buffered release - the button, not the swing.
func drop_swing() -> void:
	_attack_hold_timer = -1.0
	_buffered_swing = ""
	_buffered_swing_timer = 0.0


## The kick on its own, for a kit that borrows it - the archer's BowKit has no swing but
## keeps the boot for making room.
func try_kick() -> void:
	_try_kick()


## Starts the chain over from its opening stage.
func reset_chain() -> void:
	_combo_stage = 0
	_combo_reset_timer = 0.0


func on_bloodthirst() -> void:
	_bloodthirst_ready = true


## Battle Frenzy begins (WarriorSkills.begin_battle_frenzy): for `duration` seconds the chain does
## not end while it keeps connecting.
func start_battle_frenzy(duration: float) -> void:
	_frenzy_timer = duration


func is_frenzied() -> bool:
	return _frenzy_timer > 0.0


## The swing in flight is cut off - its hits that have not landed with it.
func drop_hits() -> void:
	_pending_hits.clear()
	_pending_hit_mults.clear()
	_pending_whooshes.clear()
	_load = null
	_load_taken = true


## Everything at once: the button, the hits still to land and the chain. For a cast that
## cuts a swing off, and for an action cancelled outright.
func cancel() -> void:
	drop_swing()
	drop_hits()
	reset_chain()


## Raising the guard drops any half-built combo and the press in progress.
func on_guard_raised() -> void:
	_combo_stage = 0
	_attack_hold_timer = -1.0


## How fast the heavy spin carries the player forward this frame, metres per second; 0
## for anything else. The light chain's harder last stage shares the heavy's sounds and so
## its step too.
func lunge_speed(delta: float) -> float:
	if not player._action_is_melee or _attack_swing_sound != &"blade_heavy_swing":
		return 0.0
	var duration: float = maxf(player._action_duration, 0.01)
	var previous_progress: float = clampf((player._action_elapsed - delta) / duration, 0.0, 1.0)
	var current_progress: float = clampf(player._action_elapsed / duration, 0.0, 1.0)
	return (_lunge_distance(current_progress) - _lunge_distance(previous_progress)) / maxf(delta, 0.001)


## Once the hold is clearly a heavy, the heavy goes off at once rather than on release. A
## short tap is still resolved on release as a normal fast attack.
func _start_heavy_when_held() -> void:
	if _attack_hold_timer < GameSettings.player_heavy_hold_time or player.is_blocking:
		return
	if not player._can_start_attack():
		return
	drop_swing()
	_start_heavy()


## Starts the swing a completed press/release resolved to. `symbol` is "L" for a tap and
## "H" for a hold.
func _try_attack(symbol: String) -> void:
	if player.is_blocking or not player._can_start_attack():
		return
	if symbol == "H":
		_start_heavy()
	else:
		_advance_light_chain()


## The spin: one committed move rather than a chain step, so it takes the whole body,
## roots the player, and drops whatever light chain was building.
func _start_heavy() -> void:
	reset_chain()
	_attack_swing_sound = &"blade_heavy_swing"
	_attack_impact_sound = &"blade_heavy_hit"
	_attack_knockback_strength = GameSettings.player_heavy_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength
	var duration: float = GameSettings.player_heavy_duration / player._attack_speed_mult()
	_begin_melee_action(heavy_clip, duration, GameSettings.player_heavy_damage_mult, false)


## One click, one stage of the light chain. A click that lands while the chain is still
## live continues it; anything else starts over at the opening stage.
##
## Standing still and moving get genuinely different swings. A player who is not asking to
## go anywhere gets the clip WHOLE - its own footwork included - and is held in place until
## it finishes, which is the version the animation was authored for. A player on the move
## gets the same swing masked to the upper body, with the walk cycle carrying on
## underneath.
##
## Stage durations are proportional to how much of the clip the stage covers, so every
## stage plays at the same speed and a whole chain still runs one swing duration per click.
func _advance_light_chain() -> void:
	var clip: String = light_chain_clip_extended if player.melee_combo_extended else light_chain_clip
	var stages: int = light_chain_stages_extended if player.melee_combo_extended else light_chain_stages
	if not player.animator.has_clip(clip):
		push_warning("Light attack chain clip '%s' is missing from the player library" % clip)
		return

	var moving: bool = player._wants_to_move()
	var stage: int = _combo_stage if _combo_stage < stages else 0
	# Battle Frenzy: past the last stage, a chain whose every cut connected does not start over
	# - the finisher comes again.
	if _combo_stage >= stages and _frenzy_timer > 0.0 and _swing_connected:
		stage = stages - 1
	# Blade Dance's third stage is a planted, full-body flourish - there is no walking
	# version of it to mask onto the legs - so a player on the move never reaches it and
	# simply starts the chain over instead.
	if moving and stage >= light_chain_heavy_stage:
		stage = 0

	var window: Vector2 = player.animator.combo_windows(clip, stages)[stage]
	var duration: float = _swing_duration() * (window.y - window.x) * float(stages)
	if _bloodthirst_ready:
		_bloodthirst_ready = false
		duration /= GameSettings.warrior_bloodthirst_haste
	var damage_mult: float = _light_damage_mult()
	_attack_swing_sound = &"blade_swing"
	_attack_impact_sound = &"blade_hit"
	_attack_knockback_strength = GameSettings.spell_melee_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	if stage >= light_chain_heavy_stage:
		damage_mult = GameSettings.player_combo_finisher_damage_mult
		# The chain's last stage hits harder than the rest, and sounds and feels like it.
		_attack_swing_sound = &"blade_heavy_swing"
		_attack_impact_sound = &"blade_heavy_hit"
		_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength
	_combo_stage = stage + 1
	_combo_reset_timer = duration + GameSettings.player_combo_grace
	_begin_melee_action(clip, duration, damage_mult, moving, window)


func _try_kick() -> void:
	if player.is_blocking or not player._can_start_attack():
		return
	if player.spell_cooldown_timers.get("kick", 0.0) > 0.0:
		return
	player.spell_cooldown_timers["kick"] = GameSettings.spell_cooldown_kick
	# A kick is its own move, not a combo step - it breaks the chain. The negative damage
	# multiplier is what marks it as a kick for apply_hit().
	_combo_stage = 0
	drop_swing()
	# A boot, not a blade - the same blunt pair an enemy's club uses.
	_attack_swing_sound = &"blunt_swing"
	_attack_impact_sound = &"blunt_hit"
	_attack_knockback_strength = GameSettings.spell_melee_kick_knockback
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	# Rooted despite being a single strike: it is a leg animation, and a walk cycle running
	# underneath it would destroy it.
	_begin_melee_action(kick_clip, GameSettings.player_swing_duration * 1.4, -1.0, false)


## Attack cadence, shortened by Fervor exactly as the old flat melee cooldown was.
func _swing_duration() -> float:
	return GameSettings.player_swing_duration / player._attack_speed_mult()


## A swing: commits the player and schedules the impact frames measured inside the stretch
## of clip it actually plays.
func _begin_melee_action(clip: String, duration: float, damage_mult: float, upper_body: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_attack_damage_mult = damage_mult
	_swing_connected = false
	player._pending_cast_id = ""
	player._action_is_heavy = clip == heavy_clip
	if damage_mult < 0.0:
		_attack_weight = AttackCharges.Weight.NONE
	elif clip == heavy_clip:
		_attack_weight = AttackCharges.Weight.HEAVY
	else:
		_attack_weight = AttackCharges.Weight.LIGHT
	_load = null
	_load_taken = false
	# Heard whatever it goes on to hit - now, or timed to the blade (whoosh_before_hit). The
	# impact is a separate sound scheduled with the damage below, so a swing through empty air
	# still makes a noise.
	if whoosh_before_hit < 0.0:
		player._play_sound(_attack_swing_sound, player.global_position)
	# Melee keeps the two tied together: a swing that takes the whole body is a committed
	# move, and one masked to the upper body is walked through.
	player._begin_action(clip, duration, upper_body, not upper_body, true, window)
	_pending_hits = player.animator.hit_times(clip, player._action_duration, window)
	_pending_hit_mults.clear()
	if clip == heavy_clip and not _pending_hits.is_empty():
		var shares: Array[float] = _heavy_hit_shares()
		if shares.size() == _pending_hits.size():
			for share: float in shares:
				_pending_hit_mults.append(damage_mult * share)
		else:
			_pending_hits = [_pending_hits[-1]]
	if _pending_hits.is_empty():
		# Nothing measured in this stretch: still land one hit, halfway through.
		_pending_hits = [player._action_duration * 0.5]
	if _pending_hit_mults.size() != _pending_hits.size():
		_pending_hit_mults.clear()
		for _hit: float in _pending_hits:
			_pending_hit_mults.append(damage_mult)
	_pending_whooshes.clear()
	if whoosh_before_hit >= 0.0:
		var peak: float = float(WHOOSH_PEAK.get(_attack_swing_sound, 0.1))
		for hit: float in _pending_hits:
			_pending_whooshes.append(maxf(hit - peak - whoosh_before_hit, 0.0))


## One impact frame's worth of melee damage. A negative `damage_mult` means "this is the
## kick", which has its own damage and knockback rather than scaling the weapon.
##
## Returns how many enemies it connected with, which is what lets a whiff earn the player
## nothing from the melee-into-spell cooldown refund.
func apply_hit(damage_mult: float) -> int:
	var is_kick: bool = damage_mult < 0.0
	var reach: float = GameSettings.spell_melee_kick_range if is_kick else _reach()
	var knockback: float = GameSettings.spell_melee_kick_knockback if is_kick else _attack_knockback_strength
	var dmg: float = GameSettings.spell_melee_kick_damage if is_kick else GameSettings.spell_melee_damage * damage_mult
	dmg *= player.get_spell_damage_multiplier() * player._giant_damage_mult() * _hit_mult()
	# Loxodon Warhammer: melee scales off the player's own health pool, which is what makes
	# it pair with green's size - Giant Growth and the green affinity both raise the pool.
	dmg += player.max_hp * player.equipment_value("loxodon_warhammer")

	# What the swing is charged with (AttackCharges): Exalted Strike, Become Immense, Deathtouch,
	# Rubblebelt Rioters... Taken once per swing, on its first impact frame, so a cleave's
	# second impact carries the same charge and a cleave through three enemies spends one.
	# A kick is neither weight and never carries one - a buff thrown away by a button pressed
	# for spacing would be worse than no buff.
	var load: RefCounted = null if is_kick else _load
	var cone: float = _cone()
	var exile: bool = false
	if load != null:
		dmg = dmg * load.damage_mult + load.damage_add
		reach += load.reach_bonus
		cone -= load.cone_widen
		knockback *= load.knockback_mult
		exile = load.exile

	var space_state := player.get_world_3d().direct_space_state
	var start: Vector3 = player.camera.global_position
	var end: Vector3 = start - player.camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(start, end, 4)
	var result: Dictionary = space_state.intersect_ray(query)

	var knock_first: bool = not is_kick and _knock_first()
	var forward: Vector3 = -player.transform.basis.z
	if result and result.collider.is_in_group("enemies"):
		var enemy: Node3D = result.collider
		_strike(enemy, dmg, exile, knockback, knock_first, load)
		player.resolve_charged_impact(load, enemy.global_position, forward)
		return 1

	# Nearest first: a charge with a target limit (Deathtouch's) reaches the enemies in front
	# of the blade before the ones at the edge of its arc.
	var struck: Array[Node3D] = []
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and player.global_position.distance_to(e.global_position) <= reach:
			var dir_to_e: Vector3 = (e.global_position - player.global_position).normalized()
			if forward.dot(dir_to_e) > cone:
				struck.append(e)
	var from: Vector3 = player.global_position
	struck.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	for e: Node3D in struck:
		_strike(e, dmg, exile, knockback, knock_first, load)
	# Where the blow fell, for a charge that acts on the ground rather than on an enemy
	# (Sunlance's line, Entangling Vines): the first enemy it met, or the end of the blade.
	var landed: Vector3 = struck[0].global_position if not struck.is_empty() else from + forward * reach
	if load != null and (not struck.is_empty() or _pending_hits.is_empty()):
		player.resolve_charged_impact(load, landed, forward)
	return struck.size()


## The blow and its push on one enemy. The push normally follows the blow; `knock_first`
## turns that round, so a blow that kills throws the body with the push already on it
## (EnemyBase._record_fatal_hit counts a knockback in flight towards the death launch).
func _strike(enemy: Node3D, dmg: float, exile: bool, knockback: float, knock_first: bool, load: RefCounted = null) -> void:
	if knock_first:
		player._apply_basic_attack_knockback(enemy, knockback)
	player._melee_strike(enemy, dmg, exile, load)
	if not knock_first:
		player._apply_basic_attack_knockback(enemy, knockback)


# --- what a class on these moves changes (GreatswordKit) ------------------------------------

## How far the blade reaches and the arc it covers (the dot of facing and direction to the
## enemy has to be above it).
func _reach() -> float:
	return GameSettings.spell_melee_range


func _cone() -> float:
	return GameSettings.spell_melee_cone


## A light-chain stage's damage, as a multiple of spell_melee_damage.
func _light_damage_mult() -> float:
	return 1.0


## Everything the blade and the boot deal is multiplied by this.
func _hit_mult() -> float:
	return 1.0


## Whether a blade's push lands before its damage - see _strike().
func _knock_first() -> bool:
	return false


## A heavy that lands every one of its impacts: what each deals, as a share of the heavy's
## damage, in order. Empty (the spin) - the heavy lands its last impact only. Ignored when the
## clip does not have exactly this many impacts.
func _heavy_hit_shares() -> Array[float]:
	return []


func _lunge_distance(progress: float) -> float:
	if progress <= heavy_lunge_extra_start:
		return heavy_lunge_distance * progress / heavy_lunge_extra_start
	if progress <= heavy_lunge_extra_end:
		var extra_progress: float = (progress - heavy_lunge_extra_start) / (heavy_lunge_extra_end - heavy_lunge_extra_start)
		return heavy_lunge_distance + heavy_lunge_extra_distance * extra_progress
	return heavy_lunge_distance + heavy_lunge_extra_distance
