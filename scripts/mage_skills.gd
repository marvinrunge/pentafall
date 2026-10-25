class_name MageSkills
extends RefCounted
## What the mage's two ACTIVE class skills do (ClassDatabase.SKILLS), in the shape SpellEffects
## gives the colour spells: static functions on the caster. The two passives live where they
## act - Prowess in MageKit (on_spell_cast, the next shot), Spell Mastery in Player
## (_start_spell_cooldown, the charges).


## Blink of an Eye: the long blink, to the ground under the crosshair, leaving an illusion of
## the mage where they stood - a decoy (TemporaryAlly) the enemies around it are taunted onto.
## Resolved on the server like Displace, the blue spell it is the mage's cousin of: the decoy
## and the taunt are the server's, and the move goes through the owner's machine
## (Player.teleport_to).
static func cast_blink_of_an_eye(caster: Player) -> void:
	var from: Vector3 = caster.global_position
	var aimed: Vector3 = caster._aim_point(GameSettings.mage_blink_of_an_eye_range, SpellEffects.ENVIRONMENT_MASK)
	var offset: Vector3 = aimed - from
	offset.y = 0.0
	var distance: float = minf(offset.length(), GameSettings.mage_blink_of_an_eye_range)
	var direction: Vector3 = offset.normalized() if offset.length_squared() > 0.01 else -caster.global_basis.z
	var target: Vector3 = Blink.landing(caster, direction, distance)

	var decoy: Node3D = caster._place_networked({
		"kind": "decoy", "position": from, "yaw": caster.rotation.y,
		"hp": caster.max_hp * GameSettings.mage_decoy_health_mult,
		"duration": GameSettings.mage_decoy_duration,
		"class": caster.character_class, "color": caster.path_color(),
	})
	if decoy != null:
		for enemy: Node3D in caster._enemies_in_radius(from, GameSettings.mage_decoy_taunt_radius):
			if enemy.has_method("apply_taunt"):
				enemy.apply_taunt(decoy, GameSettings.mage_decoy_duration)

	caster.teleport_to(target)
	caster._invulnerable_timer = maxf(caster._invulnerable_timer, GameSettings.mage_blink_invulnerable_time)
	Blink.show_blink(caster, from, target)
	NetFx.sound(&"spell_decoy", from)


## Mana Surge: the last colour spell this mage cast is ready again, every charge of it. Runs on
## the caster's own machine (Player.execute_spell), because that is where the cooldowns are
## kept - the server never sees them.
static func surge(caster: Player) -> void:
	var spell_id: String = caster.last_color_spell_id
	var recharged: bool = spell_id != "" and caster.recharge_spell(spell_id)
	if not recharged:
		caster._notify(surge_miss(caster))


## What Mana Surge would find nothing to do with - "" when the last colour spell is waiting.
## Asked before the cast (Player.spell_miss), so a surge with nothing to recharge is not cast.
static func surge_miss(caster: Player) -> String:
	var spell_id: String = caster.last_color_spell_id
	if spell_id == "":
		return "Nothing to recharge"
	if not caster.spell_cooldown_timers.has(spell_id) and not caster._mastery_spent.has(spell_id):
		return "%s is already ready" % SpellDatabase.get_display_name(spell_id)
	return ""
	NetFx.spell("mage_surge/" + caster.path_color(), caster.global_position, 1.0, caster._fx_peer())
	NetFx.sound(&"spell_rally_fallen", caster.global_position)
