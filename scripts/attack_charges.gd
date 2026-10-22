extends RefCounted
## The charges a player's next attacks carry - "your next heavy attack ...", "your next three
## light attacks ..." (docs/SKILL_DESIGN.md, round two). One per player, held on the machine
## that plays them, because that is the machine that resolves its basic attacks: the axe's
## impact frames, the arrow and the bolt all live there (MeleeKit, PlayerArrow, MageBolt), and a
## charge has to be spent where the attack is.
##
## The spell that grants a charge still resolves on the server like every spell; the server
## hands the charge back to the owner (Player.arm_next_attack). Exalted Strike used to keep its
## charges on the server's copy of the player - which on a client was the copy that never
## attacked, so a client's Exalted Strike did nothing at all.
##
## Every class has both weights of attack: a tap and a hold (the axe's chain and spin, the
## knight's cut and heavy slash, the barbarian's cleave and double swing, the archer's quick
## shot and full draw, the mage's bolt and Arcane Blast). A charge names the weight it waits
## for, so no skill assumes a weapon. The kick is neither and spends nothing.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

const ChargedHits := preload("res://scripts/charged_hits.gd")
const AttackLoad := preload("res://scripts/attack_load.gd")

enum Weight { NONE, LIGHT, HEAVY }

## Spell id -> {"rank", "uses", "seconds_left" (-1: no window)}.
var _armed: Dictionary = {}
var _player: Node = null


func _init(owner: Node) -> void:
	_player = owner


## Arms `spell_id` at `rank`. A recast SETS the uses rather than adding to them, as Exalted
## Strike always did - a charge banked across a wave has no timing to get right.
func arm(spell_id: String, rank: int) -> void:
	var profile: Dictionary = ChargedHits.profile(spell_id, rank)
	var uses: int = maxi(int(profile.get("uses", 1)), 1)
	_armed[spell_id] = {
		"rank": rank,
		"uses": uses,
		"total": uses,
		"seconds_left": float(profile.get("window", -1.0)),
	}


## Spends one use of every armed charge waiting for an attack of `weight`, and returns what the
## attack carries - null when nothing rides on it.
func take(weight: int) -> RefCounted:
	if weight == Weight.NONE or _armed.is_empty():
		return null
	var load: RefCounted = null
	for spell_id: String in _armed.keys():
		var trigger: String = _trigger_of(spell_id)
		if not (trigger == "any" or (trigger == "light" and weight == Weight.LIGHT) \
				or (trigger == "heavy" and weight == Weight.HEAVY)):
			continue
		var entry: Dictionary = _armed[spell_id]
		var uses: int = int(entry["uses"]) - 1
		# The last use of a charge that had several is the one that says so (Crippling Chill's
		# third hit freezes).
		var wire_id: String = spell_id + (ChargedHits.FINAL_SUFFIX if uses <= 0 and int(entry.get("total", 1)) > 1 else "")
		if load == null:
			load = AttackLoad.new()
			load.weight = weight
		var rank: int = int(entry["rank"])
		load.add(wire_id, ChargedHits.profile(spell_id, rank))
		_add_live_numbers(load, spell_id, rank)
		if uses <= 0:
			_armed.erase(spell_id)
		else:
			entry["uses"] = uses
		# A window of every attack (Unholy Strength, Blood Frenzy) flashes when it is cast,
		# not on each of the attacks it then rides on.
		if int(entry.get("total", 1)) < ChargedHits.WINDOWED_USES:
			_flash(spell_id)
	return load


## The part of a charge that depends on the attacker as they are right now: Unholy Strength's
## life paid (a share of maximum health, so the damage is worked out where the attack is), and
## Blood Frenzy's multiplier from the health already lost.
func _add_live_numbers(load: RefCounted, spell_id: String, rank: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var max_hp: float = maxf(float(_player.get("max_hp")), 1.0)
	match spell_id:
		"black_6":
			var hp: float = float(_player.get("hp"))
			var paid: float = minf(max_hp * GameSettings.spell_black_unholy_life_per_hit, maxf(hp - 1.0, 0.0))
			load.damage_add += paid * GameSettings.spell_black_unholy_damage_per_life * GameSettings.rank_damage_mult(rank)
		"red_7":
			var missing: float = clampf(1.0 - float(_player.get("hp")) / max_hp, 0.0, 1.0)
			var top: float = GameSettings.rank_fraction(GameSettings.spell_red_frenzy_mult, GameSettings.spell_red_frenzy_mult_max, rank)
			load.damage_mult *= lerpf(1.0, top, missing)


## Deathtouch's window running out.
func tick(delta: float) -> void:
	for spell_id: String in _armed.keys():
		var entry: Dictionary = _armed[spell_id]
		var left: float = float(entry["seconds_left"])
		if left < 0.0:
			continue
		left -= delta
		if left <= 0.0:
			_armed.erase(spell_id)
		else:
			entry["seconds_left"] = left


func uses_left(spell_id: String) -> int:
	return int((_armed.get(spell_id, {}) as Dictionary).get("uses", 0))


## -1 for a charge with no window, 0 for one that is not armed.
func seconds_left(spell_id: String) -> float:
	if not _armed.has(spell_id):
		return 0.0
	return float(_armed[spell_id]["seconds_left"])


func armed_ids() -> Array:
	return _armed.keys()


## One bit per colour that has a charge waiting (white 1, blue 2, black 4, red 8, green 16) -
## published with the player's own state so every screen can show the weapon carrying it.
func armed_bits() -> int:
	var bits: int = 0
	for spell_id: String in _armed:
		var index: int = SpellDatabase.COLORS.find(SpellDatabase.get_color(spell_id))
		if index >= 0:
			bits |= 1 << index
		elif spell_id == "guild_gruul":
			bits |= 1 << 3
	return bits


## Going down drops every charge.
func clear() -> void:
	_armed.clear()


func _trigger_of(spell_id: String) -> String:
	return ChargedHits.trigger(spell_id)


## The moment a charge goes into an attack: a flash in its colour, the way Exalted always had.
func _flash(spell_id: String) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("_spawn_cast_flash"):
		return
	var tint: Color = Color(1.0, 0.97, 0.75)
	match SpellDatabase.get_color(spell_id):
		"blue": tint = Color(0.55, 0.8, 1.0)
		"black": tint = Color(0.62, 0.35, 0.8)
		"red": tint = Color(1.0, 0.5, 0.25)
		"green": tint = Color(0.45, 0.9, 0.4)
	if spell_id == "guild_gruul":
		tint = Color(1.0, 0.55, 0.2)
	_player._spawn_cast_flash(tint, 2.0)
