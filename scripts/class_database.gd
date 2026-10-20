extends RefCounted
class_name ClassDatabase
## The playable classes and their class skills (docs/CHARACTER_CLASSES_PLAN.md).
##
## "A class is the WEAPON, a colour is the MAGIC": a class decides the body (health, speed),
## the visual and its clips, the basic attack, the defence and four colourless class
## skills. Nothing here touches the five colours - any class walks any path in the tree.
##
## Same shape as SpellDatabase: static tables and accessors behind a class_name, no autoload.
##
## Only classes that are actually built are listed. The plan has six; the warrior, the knight,
## the barbarian, the archer and the mage exist, and the menu offers exactly what is here.

const DEFAULT_CLASS := "warrior"

## Menu order.
const ORDER: Array[String] = ["warrior", "knight", "barbarian", "archer", "mage"]

##   name, role       what the class picker shows
##   visual           the scene PlayerAnimator instances (tools/player_character_builder.gd)
##   kit              the basic attack: "melee" (MeleeKit), "sword_shield" (KnightKit),
##                    "greatsword" (GreatswordKit), "bow" (BowKit) or "bolt" (MageKit)
##   defence          "block" (BlockGuard), "shield" (KnightGuard), "dodge" (DodgeRoll),
##                    "blink" (Blink) or "none"
##   health_mult      on GameSettings.player_max_hp; speed_mult on player_base_speed. Names
##                    of GameSettings properties rather than numbers, so balance stays there
##   skills           the four class skills, in unlock order (GameSettings.class_skill_levels)
##   hand_orb         true for a class that holds a ball of energy over its right palm instead
##                    of a weapon (MageHandOrb) - the mage
##   walk_guards      true for a class whose walk clips already hold the guard up, so blocking
##                    on the move plays them whole instead of laying `block_idle` over the arms
##                    (PlayerAnimator) - the knight, whose pack walks behind the shield
const CLASSES: Dictionary = {
	"warrior": {
		"name": "Warrior", "role": "Axe. A fast combo fighter who blocks.",
		"visual": "res://scenes/characters/warrior/visual.tscn",
		"kit": "melee", "defence": "block",
		"health_mult": "", "speed_mult": "",
		# Blade Dance, the level-10 skill, is granted by Player._on_team_level_changed as it
		# always was; the other three are WarriorSkills and the axe's own (MeleeKit).
		"skills": ["warrior_bloodthirst", "warrior_hurl_axe", "warrior_blade_dance", "warrior_battle_frenzy"],
	},
	"knight": {
		"name": "Knight", "role": "Sword and shield. The tank - a guard that stops nearly everything.",
		"visual": "res://scenes/characters/knight/visual.tscn",
		"kit": "sword_shield", "defence": "shield",
		"health_mult": "knight_health_mult", "speed_mult": "knight_speed_mult",
		"walk_guards": true,
		"skills": ["knight_first_strike", "knight_shield_bash", "knight_shield_wall", "knight_phalanx"],
	},
	"barbarian": {
		"name": "Barbarian", "role": "Greatsword. Slow, crushing blows - a heavy swing cannot be stopped.",
		"visual": "res://scenes/characters/barbarian/visual.tscn",
		"kit": "greatsword", "defence": "none",
		"health_mult": "barbarian_health_mult", "speed_mult": "barbarian_speed_mult",
		"skills": ["barbarian_brute_force", "barbarian_whirlwind", "barbarian_indomitable", "barbarian_berserk"],
	},
	"archer": {
		"name": "Archer", "role": "Longbow. Ranged damage, fragile - rolls out of trouble.",
		"visual": "res://scenes/characters/archer/visual.tscn",
		"kit": "bow", "defence": "dodge",
		"health_mult": "archer_health_mult", "speed_mult": "archer_speed_mult",
		"skills": ["archer_longshot", "archer_disengage", "archer_volley", "archer_deadeye"],
	},
	"mage": {
		"name": "Mage", "role": "Bare hands. Bolts in the colour of your path - fragile, and blinks away.",
		"visual": "res://scenes/characters/mage/visual.tscn",
		"kit": "bolt", "defence": "blink",
		"health_mult": "mage_health_mult", "speed_mult": "mage_speed_mult",
		"hand_orb": true,
		"skills": ["mage_prowess", "mage_blink_of_an_eye", "mage_spell_mastery", "mage_mana_surge"],
	},
}

## Class skills. Actives carry the same fields a SpellDatabase row does, so the quick bar,
## the cooldown sweep and Player._begin_cast treat them exactly like spells - SpellDatabase's
## accessors fall back to this table for an id they do not know. Passives are never cast.
##
##   release_at   where in the cast its effect lands, as a share of cast_duration. A
##                spell's release comes from its clip's measured impact; a roll has none,
##                and Disengage must leave its snare where the roll STARTED.
const SKILLS: Dictionary = {
	"warrior_bloodthirst": {
		"class": "warrior", "kind": "passive", "name": "Bloodthirst",
		"desc": "Every kill your axe makes heals you a little, and the next cut of the chain comes faster.",
	},
	"warrior_hurl_axe": {
		"class": "warrior", "kind": "active", "name": "Hurl Axe",
		"desc": "Throw the axe through everything in front of you: it spins out and comes back, hitting both ways.",
		"cooldown": 9.0, "chargeable": false,
		# The axe's own chop, let go of: it leaves the hand on the chop's measured impact.
		"cast_clip": "strike_downward", "cast_duration": 0.6, "roots": false, "upper_body": true,
	},
	"warrior_blade_dance": {
		"class": "warrior", "kind": "passive", "name": "Blade Dance",
		"desc": "A third stage on the light chain, landing harder.",
	},
	"warrior_battle_frenzy": {
		"class": "warrior", "kind": "active", "name": "Battle Frenzy",
		"desc": "For a few seconds the chain does not end: as long as every cut connects, the finisher comes again and again.",
		"cooldown": 40.0, "chargeable": false,
		"cast_clip": "taunt_battlecry", "cast_duration": 0.9, "roots": true, "upper_body": false,
	},
	"knight_first_strike": {
		"class": "knight", "kind": "passive", "name": "First Strike",
		"desc": "After your shield stops a blow, your next swing comes out at once and harder - a riposte.",
	},
	"knight_shield_bash": {
		"class": "knight", "kind": "active", "name": "Shield Bash",
		"desc": "Drive the shield into everything in front of you: a blow, a shove and a moment's stun.",
		"cooldown": 10.0, "chargeable": false,
		"cast_clip": "shield_bash", "cast_duration": 0.6, "roots": true, "upper_body": false,
	},
	"knight_shield_wall": {
		"class": "knight", "kind": "passive", "name": "Shield Wall",
		"desc": "Raise the shield just as a blow comes and it is a perfect block: the attacker is stunned.",
	},
	"knight_phalanx": {
		"class": "knight", "kind": "passive", "name": "Phalanx",
		"desc": "While your shield is up, allies and myrs behind you take less damage, and the enemies around you turn on you.",
	},
	"barbarian_brute_force": {
		"class": "barbarian", "kind": "passive", "name": "Brute Force",
		"desc": "The heavy knocks enemies back much further - and what it kills is thrown hardest of all.",
	},
	"barbarian_whirlwind": {
		"class": "barbarian", "kind": "active", "name": "Whirlwind",
		"desc": "Spin with the sword held out, turning again and again on the move and hitting everything around you.",
		"cooldown": 14.0, "chargeable": false,
		"cast_clip": "whirlwind", "cast_duration": 2.4, "roots": false, "upper_body": false,
		"release_at": 0.0,
	},
	"barbarian_indomitable": {
		"class": "barbarian", "kind": "passive", "name": "Indomitable",
		"desc": "Nothing interrupts, slows or staggers you while you swing - any swing, not only the heavy one.",
	},
	"barbarian_berserk": {
		"class": "barbarian", "kind": "active", "name": "Berserk",
		"desc": "Fly into a rage: for a few seconds you swing faster and hit harder - and every blow you take lands harder too.",
		"cooldown": 45.0, "chargeable": false,
		"cast_clip": "taunt_battlecry", "cast_duration": 1.0, "roots": true, "upper_body": false,
	},
	"archer_longshot": {
		"class": "archer", "kind": "passive", "name": "Longshot",
		"desc": "A fully drawn arrow passes through several enemies instead of stopping at the first.",
	},
	"archer_disengage": {
		"class": "archer", "kind": "active", "name": "Disengage",
		"desc": "A long roll backwards, untouchable while it lasts. Where you stood, a snare slows everything that walks into it.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "dodge_back", "cast_duration": 0.6, "roots": true, "upper_body": false,
		"release_at": 0.0,
	},
	"archer_volley": {
		"class": "archer", "kind": "active", "name": "Arrow Volley Trap",
		"desc": "Loose a volley into the sky: arrows rain on the ground you aim at for a few seconds, hitting everything there.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "shoot", "cast_duration": 0.45, "roots": false,
		"release_at": 0.2,
	},
	"archer_deadeye": {
		"class": "archer", "kind": "passive", "name": "Deadeye",
		"desc": "Arrows that strike an enemy's head deal far more damage.",
	},
	"mage_prowess": {
		"class": "mage", "kind": "passive", "name": "Prowess",
		"desc": "Every spell you cast empowers your next bolt - up to three, so weave spells and bolts.",
	},
	# Instant, like Displace: a blink has no wind-up to wait for. Resolved on the server, which
	# places the decoy and moves the mage through their own machine (Player.teleport_to).
	"mage_blink_of_an_eye": {
		"class": "mage", "kind": "active", "name": "Blink of an Eye",
		"desc": "Blink to the ground you aim at. An illusion of you stays behind, and the enemies around it turn on it.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "", "cast_duration": 0.0, "roots": false,
	},
	"mage_spell_mastery": {
		"class": "mage", "kind": "passive", "name": "Spell Mastery",
		"desc": "Every colour spell holds two charges: cast it twice in a row, and it recovers one charge at a time.",
	},
	"mage_mana_surge": {
		"class": "mage", "kind": "active", "name": "Mana Surge",
		"desc": "Draw the mana back in: the last colour spell you cast is ready again at once, every charge of it.",
		"cooldown": 40.0, "chargeable": false,
		"cast_clip": "taunt_battlecry", "cast_duration": 0.9, "roots": false, "upper_body": true,
		"release_at": 0.55,
	},
}


## Each class's defence (its row's `defence`), as the skill tree's class ring shows it: the
## first of the class's five, there from level 1, on the block button rather than a quick slot.
## Its ids are icon ids too (SpellDatabase.ICON_FILES).
const DEFENCES: Dictionary = {
	"block": {
		"id": "defence_block", "name": "Block",
		"desc": "Hold the block button to raise the guard: most of a hit from in front is stopped.",
	},
	"shield": {
		"id": "defence_shield", "name": "Shield Guard",
		"desc": "Hold the block button to raise the shield: nearly all of a hit from in front is stopped - a boss's too.",
	},
	"dodge": {
		"id": "defence_roll", "name": "Dodge Roll",
		"desc": "Press the block button to roll the way you are steering, backwards with no direction - nothing touches you at its start.",
	},
	"blink": {
		"id": "defence_blink", "name": "Blink",
		"desc": "Press the block button to be somewhere else, the way you are steering - nothing touches you as you land.",
	},
	"none": {
		"id": "defence_unstoppable", "name": "Unstoppable",
		"desc": "No block: a heavy swing cannot be interrupted, from its first frame to the end of its recovery.",
	},
}


## `class_id`'s defence (DEFENCES), with whether it is on the block button.
static func defence_of(class_id: String) -> Dictionary:
	var kind: String = String(get_class_data(class_id).get("defence", "none"))
	var defence: Dictionary = (DEFENCES.get(kind, DEFENCES["none"]) as Dictionary).duplicate()
	defence["on_block_button"] = kind != "none"
	return defence


static func has_class(class_id: String) -> bool:
	return CLASSES.has(class_id)


## Any unknown id - an old save, a peer on a newer build - plays the default class rather
## than spawning a body with no visual.
static func resolve(class_id: String) -> String:
	return class_id if CLASSES.has(class_id) else DEFAULT_CLASS


static func get_class_data(class_id: String) -> Dictionary:
	return CLASSES.get(resolve(class_id), CLASSES[DEFAULT_CLASS])


static func display_name(class_id: String) -> String:
	return String(get_class_data(class_id)["name"])


static func visual_scene(class_id: String) -> String:
	return String(get_class_data(class_id)["visual"])


## A body multiplier from GameSettings, by the property name the class row gives. 1.0 when
## the class has none.
static func body_mult(class_id: String, key: String) -> float:
	var setting: String = String(get_class_data(class_id).get(key, ""))
	if setting == "":
		return 1.0
	return float(GameSettings.get(setting))


## Whether `class_id` holds a ball of energy over its palm (MageHandOrb).
static func has_hand_orb(class_id: String) -> bool:
	return bool(get_class_data(class_id).get("hand_orb", false))


## Whether `class_id`'s walk clips already hold the guard up (see the table's `walk_guards`).
static func walk_guards(class_id: String) -> bool:
	return bool(get_class_data(class_id).get("walk_guards", false))


static func skills_of(class_id: String) -> Array:
	return get_class_data(class_id)["skills"]


static func is_skill(skill_id: String) -> bool:
	return SKILLS.has(skill_id)


static func get_skill(skill_id: String) -> Dictionary:
	return SKILLS.get(skill_id, {})


static func is_active(skill_id: String) -> bool:
	return String(get_skill(skill_id).get("kind", "")) == "active"


## The team level `skill_id` unlocks at, or 0 for an id no class lists.
static func unlock_level(skill_id: String) -> int:
	for class_id: String in CLASSES:
		var index: int = (CLASSES[class_id]["skills"] as Array).find(skill_id)
		if index >= 0 and index < GameSettings.class_skill_levels.size():
			return GameSettings.class_skill_levels[index]
	return 0


## Whether `class_id` has `skill_id` at team level `level`. Derived, never stored: levels are
## shared and simultaneous, so a late joiner or a reconnect has every skill their level covers
## the moment they arrive.
static func has_skill(class_id: String, skill_id: String, level: int) -> bool:
	if not skills_of(class_id).has(skill_id):
		return false
	var at: int = unlock_level(skill_id)
	return at > 0 and level >= at
