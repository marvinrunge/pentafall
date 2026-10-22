extends RefCounted
## What one attack carries from the moment it is loosed to every enemy it reaches: the charges
## riding on it (AttackCharges.take), folded into the numbers the attack's own machine needs and
## the ids the server needs.
##
## One per attack - a swing, an arrow, a bolt - never shared, so a charge rides on exactly the
## attack that spent it. The per-enemy claim is what keeps a payload from landing twice on one
## enemy (a cleave's two impact frames, a blast and the bolt that caused it) and what enforces a
## target limit such as Deathtouch's in the order the attack found its enemies.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const ChargedHits := preload("res://scripts/charged_hits.gd")

## AttackCharges.Weight of the attack this is.
var weight: int = 0
## Every charge riding on it, as wire ids (ChargedHits.FINAL_SUFFIX on a last use).
var ids: PackedStringArray = PackedStringArray()
var damage_mult: float = 1.0
## Added after the multiplier: Unholy Strength's life turned into damage.
var damage_add: float = 0.0
var reach_bonus: float = 0.0
var cone_widen: float = 0.0
var size_mult: float = 1.0
var burst_radius: float = 0.0
var knockback_mult: float = 1.0
var exile: bool = false

## Spell id -> how many enemies its per-enemy payload may still reach (-1: every one).
var _enemy_budget: Dictionary = {}
## Spell id -> {enemy instance id: true}.
var _claimed: Dictionary = {}
var _impact_ids: PackedStringArray = PackedStringArray()
var _impact_sent: bool = false


## Folds one charge's profile into the load.
func add(id: String, profile: Dictionary) -> void:
	ids.append(id)
	damage_mult *= float(profile.get("damage_mult", 1.0))
	reach_bonus += float(profile.get("reach_bonus", 0.0))
	cone_widen += float(profile.get("cone_widen", 0.0))
	size_mult *= float(profile.get("size_mult", 1.0))
	burst_radius = maxf(burst_radius, float(profile.get("burst_radius", 0.0)))
	exile = exile or bool(profile.get("exile", false))
	if ChargedHits.base_id(id) == "guild_gruul":
		knockback_mult *= GameSettings.guild_gruul_rampage_knockback_mult
	if bool(profile.get("enemy", false)):
		_enemy_budget[id] = int(profile.get("targets", -1))
		_claimed[id] = {}
	if bool(profile.get("impact", false)):
		_impact_ids.append(id)


func is_empty() -> bool:
	return ids.is_empty()


## Whether `spell_id` (any use of it) rides on this attack.
func carries(spell_id: String) -> bool:
	for id: String in ids:
		if ChargedHits.base_id(id) == spell_id:
			return true
	return false


## The per-enemy payloads this hit on `enemy` carries to the server: each one that has not
## reached this enemy yet and still has targets left, which it then spends.
func claim_for(enemy: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if enemy == null:
		return out
	var key: int = enemy.get_instance_id()
	for id: String in _enemy_budget:
		var seen: Dictionary = _claimed[id]
		if seen.has(key):
			continue
		var left: int = int(_enemy_budget[id])
		if left == 0:
			continue
		seen[key] = true
		if left > 0:
			_enemy_budget[id] = left - 1
		out.append(id)
	return out


## The once-per-attack payloads, the first time they are asked for; empty after.
func claim_impact() -> PackedStringArray:
	if _impact_sent:
		return PackedStringArray()
	_impact_sent = true
	return _impact_ids
