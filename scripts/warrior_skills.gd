class_name WarriorSkills
extends RefCounted
## What the warrior's two ACTIVE class skills do (ClassDatabase.SKILLS), in the shape SpellEffects
## gives the colour spells: static functions on the caster. The two passives live where they act:
## Bloodthirst in Player.on_enemy_killed_by_me (where a kill is known) and MeleeKit (the quicker
## stage), Blade Dance in MeleeKit's extended chain.


## Hurl Axe, on the throw's release: the axe leaves the hand the way the warrior faces, flies out
## and comes back (HurledAxe). A networked effect, so it flies on every screen; the server deals
## its hits, where enemies think, like any cast effect.
static func cast_hurl_axe(caster: Player) -> void:
	var direction: Vector3 = -caster.global_basis.z
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	caster._place_networked({
		"kind": "hurled_axe",
		"position": caster.global_position + Vector3(0.0, 1.2, 0.0) + direction * 0.6,
		"direction": direction,
		"range": GameSettings.warrior_hurl_axe_range * caster.reach_area_mult(),
		"speed": GameSettings.warrior_hurl_axe_speed,
		"radius": GameSettings.warrior_hurl_axe_radius,
		"damage": GameSettings.spell_melee_damage * GameSettings.warrior_hurl_axe_damage_mult * caster.get_spell_damage_multiplier(),
	})


## Battle Frenzy, as the battle cry starts: the chain on the warrior's own machine stops ending
## (MeleeKit.start_battle_frenzy). Runs where the caster is driven, on the cast's first frame, like
## Whirlwind - the chain is a swing, resolved on the swinger's machine.
static func begin_battle_frenzy(caster: Player) -> void:
	if not caster.is_local or not (caster.kit is MeleeKit):
		return
	(caster.kit as MeleeKit).start_battle_frenzy(GameSettings.warrior_battle_frenzy_duration)


## ...and what everyone sees of it, on the battle cry's release.
static func cast_battle_frenzy(caster: Player) -> void:
	caster._play_sound(&"spell_roar", caster.global_position)
	caster._spawn_impact(caster.global_position + Vector3(0.0, 1.0, 0.0), Player.FX_RED, 1.4)
	NetFx.ring(caster.global_position, Color(0.95, 0.35, 0.12), 3.0)
