class_name KnightSkills
extends RefCounted
## What the knight's ACTIVE class skill does (ClassDatabase.SKILLS), in the shape SpellEffects
## gives the colour spells. The three passives live where they act: First Strike in KnightKit,
## Shield Wall in KnightGuard, Phalanx in Player (phalanx_damage_taken_mult, _update_phalanx).


## Shield Bash, the world's half: on the clip's measured thrust, everything in front of the
## knight within knight_bash_range and knight_bash_cone takes a blow, is shoved back and
## stunned. Resolved on the server like any cast effect, where enemies think.
static func cast_shield_bash(caster: Player) -> void:
	var forward: Vector3 = -caster.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var damage: float = GameSettings.spell_melee_damage * GameSettings.knight_bash_damage_mult * caster.get_spell_damage_multiplier()
	var struck: int = 0
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, GameSettings.knight_bash_range):
		var offset: Vector3 = enemy.global_position - caster.global_position
		offset.y = 0.0
		if offset.length_squared() > 0.0001 and forward.dot(offset.normalized()) < GameSettings.knight_bash_cone:
			continue
		caster._deal_damage(enemy, damage, true)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback((offset.normalized() if offset.length_squared() > 0.0001 else forward) * GameSettings.knight_bash_knockback)
		if enemy.has_method("apply_stun"):
			enemy.apply_stun(GameSettings.knight_bash_stun)
		if enemy.has_method("apply_control_weaken"):
			enemy.apply_control_weaken(caster)
		struck += 1
	var front: Vector3 = caster.global_position + forward * 1.2 + Vector3(0.0, 1.0, 0.0)
	caster._spawn_impact(front, Player.FX_WHITE, 1.4)
	NetFx.sound(&"blunt_hit" if struck > 0 else &"blunt_swing", front)
