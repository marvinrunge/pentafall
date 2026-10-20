class_name KnightGuard
extends BlockGuard
## The knight's defence: the warrior's guard with a shield in it (docs/CHARACTER_CLASSES_PLAN.md
## - "a block that stops nearly everything"). Raised and held the same way; it takes far more
## of a hit (knight_block_damage_reduction), covers the whole front half (knight_block_cone),
## and a boss's blow does not go through it.
##
## Shield Wall (level 10) lives here too: a hit stopped within knight_perfect_block_window of
## the shield coming up is a perfect block and stuns the attacker. Judged where the hit lands -
## the server - from Player.guard_raised_msec, which every copy of the player keeps.

func _init(owner: Player) -> void:
	super(owner)


func damage_reduction() -> float:
	return GameSettings.knight_block_damage_reduction


func _cone() -> float:
	return GameSettings.knight_block_cone


func _bosses_break_through() -> bool:
	return false


func on_blocked(source: Node3D) -> void:
	if not player.has_class_skill("knight_shield_wall") or not is_instance_valid(source):
		return
	var since_raised: float = float(Time.get_ticks_msec() - player.guard_raised_msec) / 1000.0
	if since_raised > GameSettings.knight_perfect_block_window:
		return
	if source.has_method("apply_stun"):
		source.apply_stun(GameSettings.knight_perfect_block_stun)
	if source.has_method("apply_control_weaken"):
		source.apply_control_weaken(player)
	player._spawn_impact(player.global_position + Vector3(0.0, 1.2, 0.0) - player.global_basis.z * 0.6, Player.FX_WHITE, 1.0)
	NetFx.sound(&"block_impact_blunt", player.global_position)
