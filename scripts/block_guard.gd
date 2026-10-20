class_name BlockGuard
extends ClassDefence
## The warrior's defence: holding the block button raises a guard that soaks most of a hit
## from in front (docs/CHARACTER_CLASSES_PLAN.md - each class has one defence; the
## barbarian has none, the archer rolls, the mage blinks).
##
## Player.is_blocking stays the published state - the animator, the movement speed and the
## replication set all read it - and this is what decides it each frame and what a hit
## asks whether it was stopped.

func _init(owner: Player) -> void:
	player = owner


## Guard state for this frame. Deliberately not gated on a swing being in flight -
## releasing into a guard mid-swing is fine, the swing still finishes because
## Player._can_start_attack() and the animator both keep their own timers.
func update() -> void:
	var wants_to_block: bool = (
		player.is_local
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_pressed("block")
		and player.is_on_floor()
		and not player.is_downed
		and player._stagger_timer <= 0.0
		and player._action_timer <= 0.0
	)
	if wants_to_block:
		player._combat_timer = GameSettings.player_combat_linger
	if wants_to_block and not player.is_blocking:
		# The moment the guard comes up, for a perfect block (KnightGuard) on this machine -
		# Player._track_guard would only see it a frame later.
		player.guard_raised_msec = Time.get_ticks_msec()
		# Raising the guard drops any half-built combo, and a spell being held. Both are
		# two-handed commitments; neither can survive the same hands coming up to guard.
		if player.kit != null:
			player.kit.on_guard_raised()
		player._cancel_spell_charge()
	player.is_blocking = wants_to_block


## Whether the guard actually stops this hit: it has to come from in front, and - per
## GameSettings.player_block_ignores_boss - a Boss swings straight through one.
func blocks_attack_from(source: Node3D) -> bool:
	if not player.is_blocking or not is_instance_valid(source):
		return false
	if _bosses_break_through() and "enemy_data" in source:
		var data = source.enemy_data
		if data != null and data.enemy_class == "Boss":
			return false
	var to_source: Vector3 = source.global_position - player.global_position
	to_source.y = 0.0
	if to_source.length_squared() <= 0.001:
		return true
	return -player.transform.basis.z.dot(to_source.normalized()) >= _cone()


func damage_reduction() -> float:
	return GameSettings.player_block_damage_reduction


## What a shield changes (KnightGuard): how far round the guard covers, and whether a boss
## swings straight through it.
func _cone() -> float:
	return GameSettings.player_block_cone


func _bosses_break_through() -> bool:
	return GameSettings.player_block_ignores_boss


static func sound_for(source: Node3D) -> StringName:
	if is_instance_valid(source) and "enemy_data" in source:
		var data: EnemyData = source.enemy_data as EnemyData
		if data != null:
			if data.enemy_class == "Ranged":
				return &"block_impact_arrow"
			if data.enemy_class == "Mage":
				return &"block_impact_magic"
	return &"block_impact_blunt"
