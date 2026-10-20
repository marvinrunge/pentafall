class_name ArcherSkills
extends RefCounted
## What the archer's two ACTIVE class skills do (ClassDatabase.SKILLS), in the shape
## SpellEffects gives the colour spells: static functions on the caster. The two passives,
## Longshot and Deadeye, live where they act - the arrow (BowKit, PlayerArrow).


## Disengage, the caster's half: the long roll backwards, played by the cast itself
## (its cast_clip is the backwards dodge), untouchable for all of it. Runs where the
## caster is driven, on the cast's first frame, like Titanic Brawl's leap.
static func begin_disengage(caster: Player, duration: float) -> void:
	if not caster.is_local:
		return
	var back: Vector3 = caster.global_basis.z
	back.y = 0.0
	caster.start_evade(back.normalized() * GameSettings.archer_disengage_distance, duration, duration)


## Disengage, the world's half: the snare left where the roll began. Resolved on the server
## on the cast's first frame (its release_at is 0), so it lands on the spot the caster left.
static func lay_snare(caster: Player) -> void:
	caster._place_networked({
		"kind": "dot_zone", "type": "snare", "position": caster._ground_snap(caster.global_position),
		"radius": GameSettings.archer_disengage_snare_radius, "dps": 0.0,
		"duration": GameSettings.archer_disengage_snare_duration,
	})
	caster._spawn_impact(caster.global_position + Vector3(0.0, 0.3, 0.0), Player.FX_GREEN, 1.2)


## Arrow Volley Trap: arrows rain on the ground under the crosshair. A placed zone like Rain
## of Ember, so every screen sees the volley and the server alone deals its damage.
static func cast_volley(caster: Player) -> void:
	var target: Vector3 = caster._aim_point(GameSettings.archer_volley_range, Player.AIM_ENEMY_MASK | Player.AIM_WORLD_MASK)
	caster._place_networked({
		"kind": "dot_zone", "type": "arrow_volley", "position": caster._ground_snap(target, Player.AIM_WORLD_MASK),
		"radius": GameSettings.archer_volley_radius,
		"dps": GameSettings.spell_melee_damage * GameSettings.archer_volley_dps_mult * caster.get_spell_damage_multiplier(),
		"duration": GameSettings.archer_volley_duration,
	})
