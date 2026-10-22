extends RefCounted
## What a charged attack does - the payload half of "your next attack ..." (docs/SKILL_DESIGN.md,
## round two). AttackCharges holds the charges on the attacker's machine; this says what each one
## is worth there (profile) and what it does when it lands (on the server: executes, on_struck,
## resolve_impact).
##
## Two halves on two machines, because that is where the two decisions are made. How big, how
## hard and how far an attack reaches is decided where the attack is resolved - the attacker's
## machine, exactly like the rest of a basic attack - and is folded into the damage it sends.
## What the hit DOES to the world (kills, roots, cages, sends an enemy home) is world state, so
## the server does it, told only WHICH charges rode on the hit (`on_hit`, spell ids) and reading
## the rank off the attacker's synced build itself. profile() is a pure function of id, rank and
## GameSettings, so both machines agree on every number without one being sent.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

## A charge spent by the LAST use of a multi-use charge carries this suffix on the wire, so the
## server can tell Crippling Chill's freezing third hit from the two that only chill.
const FINAL_SUFFIX := ":final"
## Two self-buffs ride the same machinery as a window of every attack rather than one: Unholy
## Strength (life into damage) and Blood Frenzy (damage from missing health). Each is decided on
## the attacker's machine per attack, so it lives here with the charges rather than as a second
## way of changing an attack's damage. Rubblebelt Rioters' three hits are the third.
const TRIGGERS: Dictionary = {"guild_gruul": "any", "black_6": "any", "red_7": "any"}
## Uses that never run out inside a window.
const WINDOWED_USES := 100000


## Which attacks `id` waits for: "light", "heavy", "any", or "" for none.
static func trigger(id: String) -> String:
	var base: String = base_id(id)
	if TRIGGERS.has(base):
		return String(TRIGGERS[base])
	return SpellDatabase.next_attack(base)


## Everything a charge is worth at `rank`. Keys:
##   uses          how many attacks it rides on
##   window        seconds it waits before it lapses (-1 for as long as it takes)
##   targets       how many enemies one attack may apply its per-enemy payload to (-1 all)
##   damage_mult   multiplies the attack's damage, on the attacker's machine
##   reach_bonus   metres added to a melee reach
##   cone_widen    subtracted from the melee cone's dot threshold (a wider arc)
##   size_mult     an arrow's or a bolt's drawn size
##   burst_radius  a projectile bursts over this radius where it lands (0: it does not)
##   exile         what it kills leaves no corpse
##   enemy         it has a per-enemy payload the server applies (on_struck / executes)
##   impact        it has a once-per-attack payload at the impact point (resolve_impact)
static func profile(spell_id: String, rank: int) -> Dictionary:
	var out: Dictionary = {
		"uses": 1, "window": -1.0, "targets": -1, "damage_mult": 1.0, "reach_bonus": 0.0,
		"cone_widen": 0.0, "size_mult": 1.0, "burst_radius": 0.0, "exile": false,
		"enemy": false, "impact": false,
	}
	match base_id(spell_id):
		"white_1":
			out["uses"] = GameSettings.rank_count(GameSettings.spell_white_exalted_charges, GameSettings.spell_white_exalted_charges_max, rank)
			out["damage_mult"] = GameSettings.spell_white_exalted_damage_mult * GameSettings.rank_damage_mult(rank)
			out["reach_bonus"] = GameSettings.spell_white_exalted_reach_bonus * GameSettings.rank_area_mult(rank)
			out["exile"] = true
		"white_7":
			out["damage_mult"] = GameSettings.spell_white_smite_damage_mult * GameSettings.rank_damage_mult(rank)
			out["enemy"] = true
		"white_8":
			out["impact"] = true
		"white_9":
			out["targets"] = 1
			out["enemy"] = true
		"blue_7":
			out["uses"] = GameSettings.spell_blue_crippling_chill_uses
			out["enemy"] = true
		"blue_8":
			out["targets"] = 1
			out["enemy"] = true
		"blue_9":
			out["enemy"] = true
		"black_3":
			out["window"] = GameSettings.spell_black_deathtouch_window
			out["targets"] = GameSettings.rank_count(GameSettings.spell_black_deathtouch_targets, GameSettings.spell_black_deathtouch_targets_max, rank)
			out["enemy"] = true
		"black_7":
			out["impact"] = true
		"red_8":
			out["targets"] = 1
			out["enemy"] = true
		"green_6":
			out["damage_mult"] = GameSettings.spell_green_immense_damage_mult * GameSettings.rank_damage_mult(rank)
			out["reach_bonus"] = GameSettings.spell_green_immense_reach_bonus * GameSettings.rank_area_mult(rank)
			out["cone_widen"] = GameSettings.spell_green_immense_cone_widen
			out["size_mult"] = GameSettings.spell_green_immense_size_mult
			out["burst_radius"] = GameSettings.spell_green_immense_burst_radius * GameSettings.rank_area_mult(rank)
		"green_7":
			out["impact"] = true
		"guild_gruul":
			# Rubblebelt Rioters rides the same machinery: three hits after a charge-in, harder.
			out["uses"] = GameSettings.guild_gruul_rampage_hits
			out["damage_mult"] = GameSettings.guild_gruul_rampage_damage_mult
		"black_6":
			# Unholy Strength: every attack in the window. Its damage is life paid, so it is
			# worked out per attack from the attacker's health (AttackCharges.take); the life
			# itself is taken on the server, once per attack (resolve_impact).
			out["uses"] = WINDOWED_USES
			out["window"] = GameSettings.spell_black_unholy_duration * GameSettings.rank_duration_mult(rank)
			out["impact"] = true
		"red_7":
			# Blood Frenzy: every attack in the window, harder the lower the attacker's health.
			out["uses"] = WINDOWED_USES
			out["window"] = GameSettings.spell_red_frenzy_duration * GameSettings.rank_duration_mult(rank)
	return out


## The spell id a wire id names, without FINAL_SUFFIX.
static func base_id(id: String) -> String:
	return id.trim_suffix(FINAL_SUFFIX)


## The rank `source` holds `id` at, as the server sees its build. Rubblebelt is a guild node.
static func rank_of(source: Node, id: String) -> int:
	if source == null or not is_instance_valid(source):
		return 0
	var base: String = base_id(id)
	if base == "guild_gruul":
		return 1 if source.has_method("has_guild") and source.has_guild("guild_gruul") else 0
	return int(source.get_spell_rank(base)) if source.has_method("get_spell_rank") else 0


## The ids of `ids` the server will act on: ones `source` actually owns, that ride on an attack
## at all. The trust is the same as damage's - the attacker claims, the server checks the claim
## is possible - and no more.
static func validated(source: Node, ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ids:
		var base: String = base_id(id)
		if trigger(base) != "" and rank_of(source, id) > 0:
			out.append(id)
	return out


## Deathtouch (black_3): whether this hit simply kills. Every non-boss it reaches, elites
## included; a boss or a miniboss only once it is weak enough - Kill's old window, unchanged.
## Asked by EnemyBase.take_damage right after Executioner's Capsule, the same way: the kill and
## the hit are one decision.
static func executes(enemy: EnemyBase, source: Node, ids: PackedStringArray) -> bool:
	if not ids.has("black_3") or enemy == null or enemy.enemy_data == null:
		return false
	if not enemy.is_boss() and not enemy.is_miniboss:
		return true
	var threshold: float = GameSettings.rank_fraction(
		GameSettings.spell_black_deathtouch_boss_threshold, GameSettings.spell_black_deathtouch_boss_threshold_max,
		rank_of(source, "black_3"))
	return enemy.health <= enemy.max_health * threshold


## The per-enemy payloads, on the server, after the damage and before the death branch.
## `fatal` is whether this very hit is about to kill the enemy.
static func on_struck(enemy: EnemyBase, source: Node, ids: PackedStringArray, fatal: bool) -> void:
	if enemy == null or ids.is_empty():
		return
	for id: String in ids:
		var rank: int = maxi(rank_of(source, id), 1)
		match base_id(id):
			"white_7":
				# Smite the Monstrous: the heavy blow that breaks a boss's special mid-cast.
				if not fatal and (enemy.is_boss() or enemy.is_miniboss):
					enemy.interrupt_special(source)
			"white_9":
				enemy.apply_sanctity_mark(GameSettings.spell_white_sanctity_duration * GameSettings.rank_duration_mult(rank))
			"blue_7":
				enemy.apply_crippling_chill(id.ends_with(FINAL_SUFFIX),
					GameSettings.spell_blue_crippling_chill_freeze * GameSettings.rank_duration_mult(rank))
			"blue_8":
				if not fatal:
					enemy.encase(GameSettings.spell_blue_ice_cage_duration * GameSettings.rank_duration_mult(rank))
			"blue_9":
				if not fatal:
					enemy.send_to_origin(GameSettings.spell_blue_time_ebb_boss_slow * GameSettings.rank_duration_mult(rank))
			"red_8":
				var damage: float = GameSettings.spell_red_powder_keg_damage * GameSettings.rank_damage_mult(rank)
				var radius: float = GameSettings.spell_red_powder_keg_radius * GameSettings.rank_area_mult(rank)
				if source is Player:
					damage *= (source as Player).get_spell_damage_multiplier()
				enemy.attach_powder_keg(source, GameSettings.spell_red_powder_keg_fuse, damage, radius, fatal)


## The once-per-attack payloads, on the server, where the attack landed: `at` the impact point,
## `direction` the way the attack was going.
static func resolve_impact(caster: Player, ids: PackedStringArray, at: Vector3, direction: Vector3) -> void:
	if caster == null or ids.is_empty():
		return
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -caster.global_basis.z
	for id: String in ids:
		var rank: int = maxi(rank_of(caster, id), 1)
		match base_id(id):
			"white_8":
				_sunlance(caster, rank, at, flat)
			"black_7":
				_bone_splinters(caster, rank, at)
			"green_7":
				_entangling_vines(caster, rank, at)
			"black_6":
				caster.lose_life(caster.max_hp * GameSettings.spell_black_unholy_life_per_hit, false)


## Sunlance: the light goes on through the line past the hit, burning and blinding.
static func _sunlance(caster: Player, rank: int, at: Vector3, direction: Vector3) -> void:
	var length: float = GameSettings.spell_white_sunlance_length * caster.area_mult_at_rank(rank)
	var half_width: float = GameSettings.spell_white_sunlance_width * 0.5
	var damage: float = GameSettings.spell_white_sunlance_damage * GameSettings.rank_damage_mult(rank) * caster.get_spell_damage_multiplier()
	var blind: float = GameSettings.spell_white_sunlance_blind * GameSettings.rank_duration_mult(rank)
	for enemy: Node3D in caster._enemies_in_radius(at + direction * length * 0.5, length * 0.5 + half_width):
		var offset: Vector3 = enemy.global_position - at
		offset.y = 0.0
		var along: float = offset.dot(direction)
		if along < -half_width or along > length:
			continue
		if (offset - direction * along).length() > half_width + 0.4:
			continue
		caster._deal_damage(enemy, damage, false)
		if enemy is EnemyBase and is_instance_valid(enemy):
			(enemy as EnemyBase).apply_blind(blind)
	NetFx.beam(at + Vector3(0.0, 1.0, 0.0), direction, length, Color(1.0, 0.95, 0.7))
	NetFx.sound(&"spell_sunlance", at)


## Bone Splinters: every corpse near the impact comes apart and flies at the nearest enemy.
static func _bone_splinters(caster: Player, rank: int, at: Vector3) -> void:
	var radius: float = GameSettings.spell_black_bone_splinters_radius * caster.area_mult_at_rank(rank)
	var damage: float = GameSettings.spell_black_bone_splinters_damage * GameSettings.rank_damage_mult(rank) * caster.get_spell_damage_multiplier()
	var left: int = GameSettings.spell_black_bone_splinters_max
	for corpse: EnemyBase in EnemyBase.corpses():
		if left <= 0:
			break
		if corpse.global_position.distance_to(at) > radius:
			continue
		var from: Vector3 = corpse.global_position + Vector3(0.0, 0.6, 0.0)
		EnemyBase.consume_corpse(corpse)
		left -= 1
		var victim: Node3D = _nearest_enemy(caster, from, GameSettings.spell_black_bone_splinters_seek)
		NetFx.impact(from, Color(0.85, 0.8, 0.7), 0.6)
		if victim == null:
			continue
		var to: Vector3 = victim.global_position + Vector3(0.0, 1.0, 0.0)
		NetFx.beam(from, (to - from).normalized(), from.distance_to(to), Color(0.88, 0.84, 0.74))
		caster._deal_damage(victim, damage, false)
	NetFx.sound(&"spell_bone_splinters", at)


## Entangling Vines: roots everything around where the attack landed. Bosses shrug it off.
static func _entangling_vines(caster: Player, rank: int, at: Vector3) -> void:
	var radius: float = GameSettings.spell_green_vines_radius * caster.area_mult_at_rank(rank)
	var duration: float = GameSettings.spell_green_vines_root * GameSettings.rank_duration_mult(rank)
	for enemy: Node3D in caster._enemies_in_radius(at, radius):
		if enemy is EnemyBase and not (enemy as EnemyBase).is_immune_to_control():
			(enemy as EnemyBase).apply_root(duration)
	NetFx.ring(at, Color(0.3, 0.72, 0.22), radius)
	NetFx.impact(at, Color(0.26, 0.6, 0.2), radius * 0.6)
	NetFx.sound(&"spell_entangling_vines", at)


static func _nearest_enemy(caster: Player, from: Vector3, within: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = within
	for enemy: Node3D in caster._enemies_in_radius(from, within):
		var distance: float = enemy.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best
