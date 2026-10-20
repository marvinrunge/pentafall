class_name BarbarianSkills
extends RefCounted
## What the barbarian's two ACTIVE class skills do (ClassDatabase.SKILLS), in the shape
## SpellEffects gives the colour spells: static functions on the caster. The two passives,
## Brute Force and Indomitable, live where they act - the swings (GreatswordKit).


## Whirlwind: the spin, played by the cast itself (its cast_clip is the sword held out, which
## PlayerAnimator turns round), hitting everything around for as long as it lasts. Runs where
## the caster is driven, on the cast's first frame, like Disengage's roll - the hits are a
## swing's, resolved on the swinger's machine.
static func begin_whirlwind(caster: Player, duration: float) -> void:
	if not caster.is_local or not (caster.kit is GreatswordKit):
		return
	(caster.kit as GreatswordKit).start_whirlwind(duration)


## Berserk: resolved on the server like any buff, which is where the damage it adds to every
## hit taken lands. The barbarian's own machine learns of it from the status bits
## (Player.is_berserk) - the faster, harder swings are resolved there.
static func cast_berserk(caster: Player) -> void:
	caster._berserk_timer = GameSettings.barbarian_berserk_duration
	caster._play_sound(&"spell_roar", caster.global_position)
	caster._spawn_impact(caster.global_position + Vector3(0.0, 1.0, 0.0), Player.FX_RED, 1.6)
	NetFx.ring(caster.global_position, Color(0.85, 0.12, 0.08), 3.0)
