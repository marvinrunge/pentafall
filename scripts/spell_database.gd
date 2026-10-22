extends Node
class_name SpellDatabase
## The single definition of every player spell.
##
## Before this existed the same 25 spells were described in five places that nothing
## kept in sync: `GameSettings.SPELL_COOLDOWNS` (cooldowns), `Player.is_chargeable()`
## (a hardcoded id list), `Player.get_spell_name_for_slot()` (a NAMES dictionary),
## `SkillTree.SPELL_DATA` (names again, plus costs and descriptions), and
## `Player.execute_spell()`'s match statement. Adding a spell meant editing five
## files correctly; disagreeing with yourself was silent.
##
## `execute_spell()`'s match statement deliberately stays where it is - what each
## spell DOES is genuinely bespoke code, and only the data around it was duplicated.
##
## Follows the same shape as `EnemyDatabase` / `BossDatabase`: a `class_name` with
## static accessors, reached through the global class name, not an autoload.
##
## Per-spell numbers live here rather than in `GameSettings` on purpose. The repo
## contract puts reusable tuning in GameSettings but keeps per-entity definitions in
## the database layer (`AGENTS.md`: "Keep enemy definitions in the existing
## data/database layer"), which is exactly what these are. Global spell knobs - charge
## time, tier costs - stay in GameSettings.

const COLORS: Array[String] = ["white", "blue", "black", "red", "green"]
## The highest N a colour's `colour_N` id runs to. Ids are append-only and never renumbered -
## the first twenty-five are named in icons, sounds, visuals and tests ~190 times - so N is the
## spell's identity, not its place on the board. Where it sits is RINGS' business.
const MAX_SPELLS_PER_COLOR: int = 12

## Every colour's spells by ring, inner first; left to right within a ring is the board order.
## The ring is a GAMEPLAY gate (GameSettings.color_ring_investment), which is why it lives here
## and not in the skill tree: the server and Player check it without a SkillTree in sight.
##
## Ring 1 holds the skills that work with no setup and read instantly - each colour's original
## Core pair plus one next-attack skill; ring 2 the original Specialists plus one more; ring 3
## the rest of the round-two backlog (docs/SKILL_DESIGN.md), the tower among them.
const RINGS: Dictionary = {
	"white": [[1, 7, 2], [3, 4, 8, 5], [6, 9, 10, 11, 12]],
	"blue": [[1, 7, 2], [3, 4, 8, 5], [6, 9, 10, 11, 12]],
	"black": [[1, 6, 2], [3, 4, 7, 5], [8, 9, 10, 11, 12]],
	"red": [[1, 8, 2], [3, 4, 7, 5], [6, 9, 10, 11]],
	"green": [[1, 6, 2], [3, 4, 7, 5], [8, 9, 10, 11, 12]],
}

## Fallback for an id that isn't in the table at all.
const DEFAULT_COOLDOWN: float = 1.0
const ICON_ROOT: String = "res://assets/icons/"
const ICON_FILES: Dictionary = {
	"white": "white.png", "blue": "blue.jpg", "black": "black.png", "red": "red.png", "green": "green.png",
	"white_1": "exalted-strike.png", "white_2": "circle-of-protection.png", "white_3": "reprisal-ward.png",
	"white_4": "wrath-of-god.png", "white_5": "rally-the-fallen.png", "blue_1": "unsummon.png",
	# A list is tried in order: the icon drawn for the spell first, then the borrowed one it
	# wore before (docs/ICON_PROMPTS.md), so dropping the new file in is the whole change.
	"blue_2": "frostwave.png", "blue_3": "suction.png", "blue_4": ["wall-of-frost.png", "frost-globe.png"],
	"blue_5": ["displace.png", "flying.png"],
	"black_1": "doom-blade.png", "black_2": "contagion.png", "black_3": ["deathtouch.png", "kill.png"],
	"black_4": "wall-of-souls.png",
	"black_5": "zombify.png", "red_1": "fireball.png", "red_2": "fire-dash.png", "red_3": "rain-of-ember.png",
	"red_4": "fire-cone.png", "red_5": "lightning-bolt.png", "green_1": "titanic-leap.png",
	"green_2": "giant-growth.png", "green_3": "fog.png", "green_4": "roar.png", "green_5": "ironbark.png",
	# Round two (docs/SKILL_DESIGN.md). Each one's own icon first, once drawn, and until then the
	# nearest existing one - so dropping the new file in is the whole change, as above.
	"white_6": ["glorious-charge.png", "circle-of-protection.png"],
	"white_7": ["smite-the-monstrous.png", "exalted-strike.png"],
	"white_8": ["sunlance.png", "wrath-of-god.png"],
	"white_9": ["mark-of-sanctity.png", "circle-of-protection.png"],
	"white_10": ["worship.png", "rally-the-fallen.png"],
	"white_11": ["banishing-light.png", "wrath-of-god.png"],
	"white_12": ["ivory-tower.png", "glorious anthem.png"],
	"blue_6": ["mirror-image.png", "phantasmal-decoy.png"],
	"blue_7": ["crippling-chill.png", "frostwave.png"],
	"blue_8": ["ice-cage.png", "wall-of-frost.png"],
	"blue_9": ["time-ebb.png", "unsummon.png"],
	"blue_10": ["counterspell.png", "rhystic-study.png"],
	"blue_11": ["curse-of-the-swine.png", "suction.png"],
	"blue_12": ["glacial-fortress.png", "orb-of-frost.png"],
	"black_6": ["unholy-strength.png", "phyrexian-arena.png"],
	"black_7": ["bone-splinters.png", "zombify.png"],
	"black_8": ["undying.png", "grave-pact.png"],
	"black_9": ["animate-dead.png", "enchantment-animate-dead.png", "zombify.png"],
	"black_10": ["gravewalk.png", "displace.png"],
	"black_11": ["demonic-pact.png", "phyrexian-arena.png"],
	"black_12": ["bontus-monument.png", "grave-pact.png"],
	"red_6": ["fling.png", "fireball.png"],
	"red_7": ["blood-frenzy.png", "fervor.png"],
	"red_8": ["powder-keg.png", "fireball.png"],
	"red_9": ["grapeshot.png", "lightning-orb.png"],
	"red_10": ["fork.png", "lightning-bolt.png"],
	"red_11": ["goblin-sharpshooter.png", "orb-of-fire.png"],
	"green_6": ["become-immense.png", "giant-growth.png"],
	"green_7": ["entangling-vines.png", "fog.png"],
	"green_8": ["kraul-harpooner.png", "titanic-leap.png"],
	"green_9": ["awaken.png", "kodamas-reach.png"],
	"green_10": ["overrun.png", "trample.png"],
	"green_11": ["call-of-the-herd.png", "roar.png"],
	"green_12": ["hornet-nest.png", "ironbark.png"],
	"flight": "flying.png", "haste": "haste.png",
	"double_strike": "doublestrike.png", "trample_strike": "trample.png", "vigilance": "vigilance.png",
	"roar": "roar.png", "ironbark": "ironbark.png", "melee_combo": "blade-dance.png",
	"aura_glorious_anthem": "glorious anthem.png", "aura_healing_orb": "healing-orb.png",
	# Until it gets its own: the blue spellbook drawn for Sylvan Library, which is not in the
	# game - a book of runes reads as Rhystic Study just as well.
	"aura_rhystic_study": ["rhystic-study.png", "sylvan-library.png"], "aura_orb_of_frost": "orb-of-frost.png",
	"aura_phyrexian_arena": "phyrexian-arena.png", "aura_grave_pact": "grave-pact.png",
	"aura_fervor": "fervor.png", "aura_orb_of_fire": "orb-of-fire.png",
	"aura_lightning_orb": "lightning-orb.png",
	"aura_trample": "trample.png",
	"aura_kodamas_reach": "kodamas-reach.png",
	"guild_azorius": "guild-azorius.png", "guild_dimir": "guild-dimir.png",
	"guild_rakdos": "guild-rakdos.png", "guild_gruul": "guild-gruul.png",
	"guild_selesnya": "guild-selesnya.png",
	# Class skills (ClassDatabase.SKILLS): a dedicated icon first, once drawn, and until then
	# the closest existing one.
	"warrior_blade_dance": "blade-dance.png",
	"warrior_bloodthirst": ["bloodthirst.png", "grave-pact.png"],
	"warrior_hurl_axe": ["hurl-axe.png", "fire-dash.png"],
	"warrior_battle_frenzy": ["battle-frenzy.png", "doublestrike.png"],
	"archer_longshot": ["longshot.png", "vigilance.png"],
	"archer_disengage": ["disengage.png", "haste.png"],
	"archer_volley": ["arrow-volley-trap.png", "rain-of-ember.png"],
	"archer_deadeye": ["deadeye.png", "doublestrike.png"],
	"knight_first_strike": ["first-strike.png", "exalted-strike.png"],
	"knight_shield_bash": ["shield-bash.png", "unsummon.png"],
	"knight_shield_wall": ["shield-wall.png", "circle-of-protection.png"],
	"knight_phalanx": ["phalanx.png", "glorious anthem.png"],
	"barbarian_brute_force": ["brute-force.png", "trample.png"],
	"barbarian_whirlwind": ["whirlwind.png", "fire-dash.png"],
	"barbarian_indomitable": ["indomitable.png", "ironbark.png"],
	"barbarian_berserk": ["berserk.png", "fervor.png"],
	"mage_prowess": ["prowess.png", "lightning-orb.png"],
	"mage_blink_of_an_eye": ["blink-of-an-eye.png", "phantasmal-decoy.png"],
	"mage_spell_mastery": ["spell-mastery.png", "sylvan-library.png"],
	"mage_mana_surge": ["mana-surge.png", "frost-globe.png"],
	# Each class's defence, the first slot of the skill tree's class ring (ClassDatabase.DEFENCES).
	# Until they are drawn, the old keyword icons stand in: none of them is on the board any more.
	"defence_block": ["defence-block.png", "vigilance.png"],
	"defence_shield": ["defence-shield.png", "vigilance.png"],
	"defence_roll": ["defence-roll.png", "haste.png"],
	"defence_blink": ["defence-blink.png", "flying.png"],
	"defence_unstoppable": ["defence-unstoppable.png", "trample.png"],
	# The Upkeep shop's tiles (UpkeepPanel): a myr, a skill point, the crystal's repair and the
	# five enchantments. Until they are drawn, the nearest existing icon - for an enchantment its
	# colour's mana symbol.
	"upkeep_myr": ["upkeep-myr.png", "kodamas-reach.png"],
	"upkeep_skill_point": ["upkeep-skill-point.png", "sylvan-library.png"],
	"upkeep_repair": ["upkeep-repair.png", "healing-orb.png"],
	"enchantment_white": ["enchantment-sphere-of-safety.png", "white.png"],
	"enchantment_blue": ["enchantment-propaganda.png", "blue.jpg"],
	"enchantment_black": ["enchantment-animate-dead.png", "black.png"],
	"enchantment_red": ["enchantment-furnace-of-rath.png", "red.png"],
	"enchantment_green": ["enchantment-overgrowth.png", "green.png"],
}

## Per-spell definition.
##   cooldown       seconds before the spell can be cast again
##   chargeable     held to charge, released to fire (min 20%, max GameSettings charge time)
##   cast_clip      animation the caster plays
##   cast_duration  how long that clip is squeezed into - the per-spell timing knob
##   commit         how long the player is actually tied up, if that is SHORTER than
##                  the animation. Defaults to cast_duration. Only a move with a long
##                  recovery needs it: Titanic Brawl's clip runs on for two seconds of
##                  standing back up after the slam, which should finish playing
##                  without locking the player out of everything while it does
##   roots          true for casts that hold the player still
##   upper_body     whether the cast plays on the upper body only, leaving the legs to
##                  the locomotion layer. Defaults to the opposite of `roots`, because
##                  a full-body clip over a character still sliding around is exactly
##                  the foot-sliding the layering exists to remove. Titanic Brawl is
##                  the one case where the two come apart and so states it outright:
##                  it moves the caster AND needs its own legs, because the movement
##                  it makes IS the brawl leap the clip is playing
##   next_attack    "light", "heavy" or "any": the cast does nothing by itself but CHARGE the
##                  caster's next attack of that weight (AttackCharges). Every class has both
##                  weights - a tap and a hold - so none of these assumes a weapon; what each
##                  charge does when it lands is ChargedHits'
##   tower          the Tower id the cast places (scripts/tower.gd)
##   passive        never cast: a round node in the tree, never put on the quick bar
##
## Two things are deliberately NOT stored here, both because storing them is how they
## drifted in the first place:
##
##   the release moment - when in the clip the effect fires is a property of the
##   ANIMATION, measured at build time by tools/player_character_builder.gd and kept
##   as `hit_ratios` metadata on the clip itself. Several spells share one clip and
##   all want the same moment. The one knob on top of that is `release_on_last`, for
##   a clip whose payload is its FINAL impact rather than its first: Titanic Brawl
##   lands on the slam at 79% of the jump, not on the take-off at 15%.
##
##   the unlock cost - one skill point, like every rank (get_unlock_cost).
## The N in an id is identity, not position: where a spell sits on the board and what it takes
## to reach it is RINGS (above) and GameSettings.color_ring_investment. Ids 1-5 are the
## original roster; 6-12 the round-two backlog of docs/SKILL_DESIGN.md.
const SPELLS: Dictionary = {
	# --- WHITE: protection and restoration ---
	# The only colour built around the myrs and the crystal rather than the player, and
	# the only one whose power goes UP with more allies alive.
	"white_1": {
		"name": "Exalted Strike",
		"desc": "Your next melee hit lands harder and reaches further. Anything it kills is exiled, leaving no corpse.",
		"cooldown": 8.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.5, "roots": false,
	},
	"white_2": {
		"name": "Circle of Protection",
		"desc": "A pool of shield divided between nearby allies. Alone, you take all of it.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.7, "roots": true,
	},
	"white_3": {
		"name": "Reprisal Ward",
		"desc": "For a time, reflect part of all damage taken back at the attacker, and block some attacks outright.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.5, "roots": false,
	},
	"white_4": {
		"name": "Wrath of God",
		"desc": "Heavy damage to every enemy in a wide radius around you.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.85, "roots": true,
	},
	"white_5": {
		"name": "Rally the Fallen",
		"desc": "Revives every downed teammate in range and heals surviving allies - myrs included.",
		"cooldown": 45.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.9, "roots": true,
	},
	# Round two. Like Fire Dash this one MOVES the caster, so it launches when the cast starts.
	"white_6": {
		"name": "Glorious Charge",
		"desc": "Charge forward behind a raised guard. Enemies in the way are carried along and stunned; allies you pass are shielded.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.45, "roots": false,
	},
	"white_7": {
		"name": "Smite the Monstrous",
		"desc": "Your next heavy attack strikes far harder. Landing it on a boss in the middle of a special attack breaks the special.",
		"cooldown": 14.0, "chargeable": false, "next_attack": "heavy",
		"cast_clip": "cast_white", "cast_duration": 0.45, "roots": false,
	},
	"white_8": {
		"name": "Sunlance",
		"desc": "Your next light attack becomes a lance of light that carries on through the line, blinding everything it touches.",
		"cooldown": 10.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_white", "cast_duration": 0.45, "roots": false,
	},
	"white_9": {
		"name": "Mark of Sanctity",
		"desc": "Your next light attack marks its target. Every ally who strikes the marked enemy is shielded.",
		"cooldown": 12.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_white", "cast_duration": 0.45, "roots": false,
	},
	"white_10": {
		"name": "Worship",
		"desc": "Hallowed ground around you. While allies and myrs stand in it, nothing can bring them below 1 health.",
		"cooldown": 30.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.7, "roots": true,
	},
	"white_11": {
		"name": "Banishing Light",
		"desc": "Seals every enemy in a small circle where you aim inside light for a time - out of the fight, then back. Not bosses.",
		"cooldown": 24.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.6, "roots": false,
	},
	"white_12": {
		"name": "Ivory Tower",
		"desc": "Raise a tower where you aim that shields the allies and myrs around it. More towers stand at once with rank.",
		"cooldown": 14.0, "chargeable": false, "tower": "ivory_tower",
		"cast_clip": "cast_white", "cast_duration": 0.6, "roots": true,
	},

	# --- BLUE: control ---
	# Blue never kills quickly. It decides WHERE the fight happens and WHO is allowed to
	# participate.
	"blue_1": {
		"name": "Unsummon",
		"desc": "Shoves every enemy ahead of you far back and stuns them where they land.",
		"cooldown": 9.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.55, "roots": false,
	},
	"blue_2": {
		"name": "Frost Breath",
		"desc": "Freezes every enemy around you and deals moderate damage. Bosses are slowed instead.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.7, "roots": true,
	},
	"blue_3": {
		"name": "Suction",
		"desc": "Drags nearby enemies into one place, packing them for whatever comes next.",
		"cooldown": 11.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": true,
	},
	"blue_4": {
		"name": "Wall of Frost",
		"desc": "Raises a solid ice wall across your aim line. Unsummon deals bonus damage when it slams enemies into the wall.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": false,
	},
	"blue_5": {
		"name": "Displace",
		"desc": "Blink a short distance to the ground you are aiming at.",
		"cooldown": 10.0, "chargeable": false,
		# The one spell with NO cast animation. A blink that has to be announced for
		# two-thirds of a second is not an escape, and the cast pose read as the caster
		# hesitating before a movement skill they had already committed to. An empty
		# cast_clip is the supported way to say "resolve now" - see Player._begin_cast.
		"cast_clip": "", "cast_duration": 0.0, "roots": false,
	},
	"blue_6": {
		"name": "Mirror Image",
		"desc": "Copies of you step out and fight beside you with your own attacks at half strength. Enemies take them for you. More copies with rank.",
		"cooldown": 26.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": false,
	},
	"blue_7": {
		"name": "Crippling Chill",
		"desc": "Your next three light attacks chill what they hit. The third freezes it solid. Bosses are slowed instead.",
		"cooldown": 10.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_blue", "cast_duration": 0.45, "roots": false,
	},
	"blue_8": {
		"name": "Ice Cage",
		"desc": "Your next light attack encases its target in a block of ice the others have to walk around.",
		"cooldown": 14.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_blue", "cast_duration": 0.45, "roots": false,
	},
	"blue_9": {
		"name": "Time Ebb",
		"desc": "Your next heavy attack sends everything it hits back to where it came from. Bosses are only slowed.",
		"cooldown": 18.0, "chargeable": false, "next_attack": "heavy",
		"cast_clip": "cast_blue", "cast_duration": 0.45, "roots": false,
	},
	# Reactive, so it must be quick: no root and the shortest cast in blue.
	"blue_10": {
		"name": "Counterspell",
		"desc": "Cast while a boss or miniboss is winding up a special attack nearby: the special fizzles.",
		"cooldown": 30.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.35, "roots": false,
	},
	"blue_11": {
		"name": "Curse of the Swine",
		"desc": "Turns enemies where you aim into harmless boars for a few seconds. More of them with rank. Not bosses.",
		"cooldown": 24.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.7, "roots": true,
	},
	"blue_12": {
		"name": "Glacial Fortress",
		"desc": "Raise a tower where you aim that fires ice at enemies, slowing them; every fourth shot freezes. More towers stand at once with rank.",
		"cooldown": 14.0, "chargeable": false, "tower": "glacial_fortress",
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": true,
	},

	# --- BLACK: death as a resource ---
	# Kills, and feeds on what the killing leaves: corpses to raise, souls to throw, a plague
	# that runs through a crowd. The only colour that can delete a target outright.
	"black_1": {
		"name": "Doom Blade",
		"desc": "A black blade travels straight ahead, passing through everything in the line. Reaches further with every rank.",
		"cooldown": 7.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.5, "roots": false,
	},
	# Replaced Fear, which scattered the packs every area skill wants and whose damage window
	# was Wall of Souls' vulnerability a second time. See docs/SKILL_DESIGN.md.
	"black_2": {
		"name": "Contagion",
		"desc": "Plague the enemy you are looking at. It burns, and jumps to the nearest enemy every second - the denser the wave, the further it runs.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.55, "roots": false,
	},
	# Was Kill: one target at 45 m. Now the next attack, light or heavy, executes everything it
	# hits up to a limit - one execute for black instead of two (docs/SKILL_DESIGN.md, round
	# two). Still the longest cooldown in the game, and still the one that falls with rank.
	"black_3": {
		"name": "Deathtouch",
		"desc": "Your next attack within a few seconds kills every enemy it hits, up to a limit. Bosses and minibosses only when they are weak enough.",
		"cooldown": 40.0, "chargeable": false, "next_attack": "any",
		"cast_clip": "cast_black", "cast_duration": 0.5, "roots": false,
	},
	"black_4": {
		"name": "Wall of Souls",
		"desc": "A wall of souls. Enemies that cross it take double damage from every source.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.7, "roots": true,
	},
	"black_5": {
		"name": "Zombify",
		"desc": "Raises the corpses lying nearby as ghouls that rush the nearest enemy and fight it.",
		"cooldown": 30.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.9, "roots": true,
	},
	"black_6": {
		"name": "Unholy Strength",
		"desc": "For a time every hit you land costs a little of your life and deals a multiple of it as extra damage. Never takes your last point of health.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.5, "roots": false,
	},
	"black_7": {
		"name": "Bone Splinters",
		"desc": "Your next heavy attack tears apart every corpse near where it lands; each one flies at the nearest enemy as a splinter of bone.",
		"cooldown": 12.0, "chargeable": false, "next_attack": "heavy",
		"cast_clip": "cast_black", "cast_duration": 0.45, "roots": false,
	},
	"black_8": {
		"name": "Undying",
		"desc": "Passive. Once a wave, when you would go down, you rise again at once - briefly untouchable, with a wave of dread that throws the enemies around you back.",
		"cooldown": 0.0, "chargeable": false, "passive": true,
		"cast_clip": "", "cast_duration": 0.0, "roots": false,
	},
	"black_9": {
		"name": "Animate Dead",
		"desc": "Raises the corpse of an elite, a miniboss or a boss near where you aim as your own, until the wave ends.",
		"cooldown": 40.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.9, "roots": true,
	},
	# No cast animation, like Displace: an escape that has to be announced is not one.
	"black_10": {
		"name": "Gravewalk",
		"desc": "Step into the corpse nearest where you aim. It bursts as you arrive, hurting everything around you.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "", "cast_duration": 0.0, "roots": false,
	},
	"black_11": {
		"name": "Demonic Pact",
		"desc": "Every other black spell comes off cooldown now. The demon wants ten kills in return before time runs out - fail, and it takes half your health. That can kill you.",
		"cooldown": 60.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.7, "roots": false,
	},
	"black_12": {
		"name": "Bontu's Monument",
		"desc": "Raise a monument where you aim. Every death near it charges it; full, it raises a ghoul. More monuments stand at once with rank.",
		"cooldown": 16.0, "chargeable": false, "tower": "bontus_monument",
		"cast_clip": "cast_black", "cast_duration": 0.6, "roots": true,
	},

	# --- RED: aggression ---
	# The damage colour, and the only one with no defensive option at all.
	"red_1": {
		"name": "Fireball",
		"desc": "Charged explosive projectile with a scaling blast radius.",
		"cooldown": 5.0, "chargeable": true,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},
	# Like Titanic Brawl, this one MOVES the caster - so it launches when the cast starts
	# rather than on the release frame, and the release is the trail catching light.
	"red_2": {
		"name": "Fire Dash",
		"desc": "Dash forward, leaving a burning trail behind you. Escape and damage in one.",
		"cooldown": 8.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.45, "roots": false,
	},
	"red_3": {
		"name": "Rain of Ember",
		"desc": "Calls down a burning firestorm that scorches everything beneath it.",
		"cooldown": 9.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},
	# HELD, not cast: Fire Cone spends a refill meter while the button is down.
	"red_4": {
		"name": "Fire Cone",
		"desc": "Held. Burns and slows everything in a cone ahead of you while you hold it, then refills before it can be used again.",
		"cooldown": 0.0, "chargeable": false, "channel": true,
		"cast_clip": "cast_red", "cast_duration": 0.4, "roots": false,
	},
	"red_5": {
		"name": "Lightning Bolt",
		"desc": "Calls a bolt down on a small area, striking bosses and elites for double. The precision answer to one big target.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.7, "roots": true,
	},
	"red_6": {
		"name": "Fling",
		"desc": "Seize the enemy you are looking at and hurl it where you aim. It bursts into flame where it lands. Not bosses.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.6, "roots": true,
	},
	"red_7": {
		"name": "Blood Frenzy",
		"desc": "For a time you hit harder the less health you have left.",
		"cooldown": 24.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.5, "roots": false,
	},
	"red_8": {
		"name": "Powder Keg",
		"desc": "Your next light attack sticks a powder keg to its target. It goes off after a few seconds - at once if the target dies first.",
		"cooldown": 9.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_red", "cast_duration": 0.45, "roots": false,
	},
	"red_9": {
		"name": "Grapeshot",
		"desc": "A spray of small bolts at the nearest enemies: one, and one more for every spell you cast in the last few seconds.",
		"cooldown": 6.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.4, "roots": false,
	},
	"red_10": {
		"name": "Fork",
		"desc": "Your next aimed spell, of any colour, is cast twice: at your target, and at the nearest other enemy.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.4, "roots": false,
	},
	"red_11": {
		"name": "Goblin Sharpshooter",
		"desc": "Post a goblin sharpshooter where you aim: very fast, very deadly shots, and it falls to almost anything. More of them at once with rank.",
		"cooldown": 14.0, "chargeable": false, "tower": "goblin_sharpshooter",
		"cast_clip": "cast_red", "cast_duration": 0.6, "roots": true,
	},

	# --- GREEN: primal vitality ---
	# Green fights by being physically present: bigger, harder to ignore, and dangerous
	# to stand next to.
	#
	# Titanic Brawl must NOT root: the leap drives the player's own movement, and holding
	# them still would fight it. See Player.cast_green_titanic_leap.
	#
	# And must NOT be filtered to the upper body either, which is the usual partner of
	# not rooting: this clip is a running jump, so its legs are the whole point. The
	# walk cycle the filter would leave underneath is precisely wrong for a character
	# who is in the air.
	"green_1": {
		"name": "Titanic Brawl",
		"desc": "Leap to where you aim and slam the ground, hurting everything around the landing. Rank adds reach.",
		"cooldown": 8.0, "chargeable": false,
		# 2.6s is the whole clip - leap, slam and the stand-up afterwards - at the pace
		# it was authored at. The leap is a real commitment, though: nothing else may
		# start until the slam has landed, so `commit` covers launch AND landing rather
		# than ending early the way a move with a free recovery does.
		#
		# ROOTS for that whole window, including the stand-up. The flight itself is not
		# affected - Player's leap branch moves the character before the rooting check ever
		# runs - so this only governs the seconds after the landing, where the player used
		# to be able to walk out of their own recovery. A character sliding across the
		# ground while playing an animation of getting to their feet is the one thing that
		# reads as broken rather than as slow.
		"cast_clip": "jump_attack", "cast_duration": 2.6, "commit": 2.6, "roots": true,
		"upper_body": false,
		"release_on_last": true,
	},
	"green_2": {
		"name": "Giant Growth",
		"desc": "Grow enormous for a time, gaining maximum health with the size.",
		"cooldown": 22.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.7, "roots": false,
	},
	"green_3": {
		"name": "Fog",
		"desc": "A bank of fog around you. Arrows and spells cannot find anything inside it, archers and mages in it cannot fire, and enemies wade rather than walk. Blades still reach you.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.6, "roots": false,
	},
	# A shout, so it uses the shout: full body, and long enough to read as one.
	"green_4": {
		"name": "Roar",
		"desc": "Nearby enemies turn on you, pulling them off the crystal and the myrs.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "taunt_battlecry", "cast_duration": 1.2, "commit": 0.9, "roots": true,
		"upper_body": false,
	},
	"green_5": {
		"name": "Ironbark",
		"desc": "Bark over your skin: heavy damage reduction, and nothing can knock you back, stun or freeze you.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.55, "roots": false,
	},
	"green_6": {
		"name": "Become Immense",
		"desc": "Your next attack, light or heavy, grows huge: a bigger swing, arrow or bolt that hits harder and covers more ground.",
		"cooldown": 12.0, "chargeable": false, "next_attack": "any",
		"cast_clip": "cast_green", "cast_duration": 0.45, "roots": false,
	},
	"green_7": {
		"name": "Entangling Vines",
		"desc": "Vines burst from wherever your next light attack lands and root the enemies around it - they still fight, but cannot advance.",
		"cooldown": 12.0, "chargeable": false, "next_attack": "light",
		"cast_clip": "cast_green", "cast_duration": 0.45, "roots": false,
	},
	"green_8": {
		"name": "Kraul Harpooner",
		"desc": "Fire a vine harpoon where you aim. An enemy it hits is dragged to you; a tree or a standing stone drags you to it. Not bosses.",
		"cooldown": 10.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.4, "roots": false,
	},
	"green_9": {
		"name": "Awaken",
		"desc": "Aim at a tree to wake it as a treant, or at a standing stone of the ring to raise a golem. It fights for you for a time.",
		"cooldown": 40.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.8, "roots": true,
	},
	# Moves the caster like Fire Dash, so it launches when the cast starts.
	"green_10": {
		"name": "Overrun",
		"desc": "A short unstoppable charge that throws everything in your way aside and clears a path. Nothing can stop or stun you while it lasts.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.45, "roots": false,
	},
	"green_11": {
		"name": "Call of the Herd",
		"desc": "Call a beast you have hunted: it fights for you until it falls or the wave ends, as big as the one you took the trophy from. Needs a trophy from a slain beast.",
		"cooldown": 30.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.7, "roots": true,
	},
	"green_12": {
		"name": "Hornet Nest",
		"desc": "Raise a nest where you aim. Enemies turn on it, and every blow they land sends hornets out to sting them. More nests stand at once with rank.",
		"cooldown": 16.0, "chargeable": false, "tower": "hornet_nest",
		"cast_clip": "cast_green", "cast_duration": 0.6, "roots": true,
	},
}


## The aura fork: one per colour, two ways to take it, exactly one owned per run.
##
## `attunement` is the stat line - the five auras the game already shipped with, kept
## rather than replaced, because deleting working content to make room for planned
## content is how a game ends up with the same amount of content forever.
## `manifestation` is the visible one from the colour tables: something fighting
## alongside the player rather than a multiplier on the player.
##
## Both halves stay honest. Attunements are stronger on paper; Manifestations do work
## while the player is somewhere else - which, in a five-lane tower defence where you
## can only stand in one lane, is worth more than it looks.
##
## Ranked 1-5 like every other skill on the board (Player.grant_aura_rank) - they used to be
## a one-purchase fork, and this comment said so long after that stopped being true.
const AURAS: Dictionary = {
	"white": {
		"attunement": {
			"id": "aura_glorious_anthem", "name": "Glorious Anthem",
			"desc": "Teammates, myrs and summons near you deal more damage and take less. Not you - it is a song for everyone else.",
		},
		"manifestation": {
			"id": "aura_healing_orb", "name": "Healing Orb",
			"desc": "An orb circles you, healing the most hurt ally in range every few seconds.",
		},
	},
	"blue": {
		"attunement": {
			"id": "aura_rhystic_study", "name": "Rhystic Study",
			"desc": "Every spell you cast grants shield. When the shield breaks, it freezes the enemies around you.",
		},
		"manifestation": {
			"id": "aura_orb_of_frost", "name": "Winter Orb",
			"desc": "An orb circles you, firing ice at nearby enemies for damage and slow.",
		},
	},
	"black": {
		"attunement": {
			"id": "aura_phyrexian_arena", "name": "Phyrexian Arena",
			"desc": "Cast spells that are still on cooldown by paying life instead - more for every second left. Never enough to kill you.",
		},
		"manifestation": {
			"id": "aura_grave_pact", "name": "Grave Pact",
			"desc": "A soul orb follows you. Enemies dying near you give it their souls, and it hurls them at the living.",
		},
	},
	"red": {
		"attunement": {
			"id": "aura_fervor", "name": "Fervor",
			"desc": "You swing and cast faster, permanently.",
		},
		"manifestation": {
			"id": "aura_orb_of_fire", "name": "Orb of Fire",
			"desc": "An orb circles you, hurling balls of fire at nearby enemies that set them burning.",
		},
		# Red's only third aura: off Lightning Bolt, the way the other two hang off the
		# finishers either side of the middle. Orb of Fire is for one target, this for a crowd.
		"manifestation_2": {
			"id": "aura_lightning_orb", "name": "Lightning Orb",
			"desc": "An orb circles you, arcing lightning into the nearest enemy that leaps on to the enemies beside it.",
		},
	},
	"green": {
		"attunement": {
			# Was Sylvan Library: more maximum health and regeneration, i.e. the green and the
			# white affinities a second time. Area is the one number nothing else in the tree
			# grants. Not "Overgrowth", which is already green's team enchantment.
			"id": "aura_kodamas_reach", "name": "Kodama's Reach",
			"desc": "Every spell you cast covers a larger area.",
		},
		"manifestation": {
			# NOT "Trample": the Gruul passive already owns that name, and it is the one
			# that matches the MTG keyword. Two nodes reading "Trample" in the same tree is
			# a naming bug, not a theme.
			"id": "aura_trample", "name": "Stampede",
			"desc": "Enemies near you take continuous damage - but only while you are moving.",
		},
	},
}


static func has_spell(spell_id: String) -> bool:
	return SPELLS.has(spell_id)


## Falls back to the class skills (ClassDatabase.SKILLS): an active class skill sits on the
## quick bar and is cast like a spell, so every accessor the bar and the cast path use
## answers for it too. has_spell() and get_color() deliberately do NOT - they are what keeps
## the colour sweeps (the tree, the cooldown refunds) to the twenty-five colour spells.
static func get_spell(spell_id: String) -> Dictionary:
	return SPELLS.get(spell_id, ClassDatabase.get_skill(spell_id))


## Not `get_name()`: this extends Node, which already has one.
static func get_display_name(spell_id: String) -> String:
	return String(get_spell(spell_id).get("name", "Locked Spell"))


static func get_description(spell_id: String) -> String:
	return String(get_spell(spell_id).get("desc", ""))


static func get_cooldown(spell_id: String) -> float:
	return float(get_spell(spell_id).get("cooldown", DEFAULT_COOLDOWN))


static func is_chargeable(spell_id: String) -> bool:
	return bool(SPELLS.get(spell_id, {}).get("chargeable", false))


## Colour half of an id, e.g. "red_2" -> "red". Empty for anything that isn't a spell
## id, which is what keeps non-spell entries such as the kick's cooldown out of the
## spell-only sweeps.
static func get_color(spell_id: String) -> String:
	if not SPELLS.has(spell_id):
		return ""
	return spell_id.get_slice("_", 0)


## Icon textures, kept after the first load.
##
## `get_icon_path` below probes the filesystem with ResourceLoader.exists() on every call,
## up to twice, and every caller then load()s whatever came back. Neither is expensive on
## its own and neither is free at the rate the skill tree asks for them: one full
## update_ui() pass wants an icon for each of forty nodes. The texture behind an id never
## changes, so the first answer is the only one worth working out.
static var _icon_cache: Dictionary = {}


## The texture for `icon_id`, or null when neither it nor its colour has one.
static func get_icon(icon_id: String, fallback_color: String = "") -> Texture2D:
	var key: String = icon_id + "|" + fallback_color
	if _icon_cache.has(key):
		return _icon_cache[key]
	var path: String = get_icon_path(icon_id, fallback_color)
	var texture: Texture2D = load(path) as Texture2D if path != "" else null
	_icon_cache[key] = texture
	return texture


static func get_icon_path(icon_id: String, fallback_color: String = "") -> String:
	if ICON_FILES.has(icon_id):
		var entry: Variant = ICON_FILES[icon_id]
		var candidates: Array = entry if entry is Array else [entry]
		for file: Variant in candidates:
			var icon_path: String = ICON_ROOT + String(file)
			if ResourceLoader.exists(icon_path):
				return icon_path
	var color: String = fallback_color if fallback_color != "" else get_color(icon_id)
	if ICON_FILES.has(color):
		var fallback_path: String = ICON_ROOT + String(ICON_FILES[color])
		if ResourceLoader.exists(fallback_path):
			return fallback_path
	return ""


## The N of a `colour_N` id, or 0 for a non-spell id. Identity only - see MAX_SPELLS_PER_COLOR.
static func spell_index(spell_id: String) -> int:
	if not SPELLS.has(spell_id):
		return 0
	return int(spell_id.get_slice("_", 1))


static func make_id(color: String, index: int) -> String:
	return "%s_%d" % [color, index]


## Every spell of `color`, in N order. The one loop over a colour's spells: everything that
## used to count to five (the investment sum, the debug unlock, the tree) asks here instead.
static func spells_of(color: String) -> Array[String]:
	var out: Array[String] = []
	for index in range(1, MAX_SPELLS_PER_COLOR + 1):
		var spell_id := make_id(color, index)
		if SPELLS.has(spell_id):
			out.append(spell_id)
	return out


## 1-based ring of a colour spell (RINGS), 0 for anything that is not one.
static func get_ring(spell_id: String) -> int:
	var index: int = spell_index(spell_id)
	var rings: Array = RINGS.get(get_color(spell_id), [])
	for ring: int in rings.size():
		if (rings[ring] as Array).has(index):
			return ring + 1
	return 0


## A colour's spells ring by ring, each ring in board order.
static func get_rings(color: String) -> Array:
	return RINGS.get(color, [])


## "light", "heavy", "any" or "" - which of the caster's next attacks this spell charges.
static func next_attack(spell_id: String) -> String:
	return String(SPELLS.get(spell_id, {}).get("next_attack", ""))


## The Tower id the spell places, or "".
static func tower_of(spell_id: String) -> String:
	return String(SPELLS.get(spell_id, {}).get("tower", ""))


## A passive spell is never cast and never bound to the quick bar (Undying).
static func is_passive(spell_id: String) -> bool:
	return bool(SPELLS.get(spell_id, {}).get("passive", false))


## Skill-point price of a spell's first rank - the same flat price as every rank after it
## (GameSettings.spell_rank_point_cost). It used to be the tier's MANA cost from TIER_COSTS
## (1, 3, 7, 15, 30), which nothing charged any more: the tree read a tier-5 spell as
## unaffordable until the player held thirty points, then took one.
static func get_unlock_cost(spell_id: String) -> int:
	return GameSettings.spell_rank_point_cost if SPELLS.has(spell_id) else 0


## The colour's spells in N order, shaped for the skill tree's board builder:
## {id, name, cost, desc, ring}.
static func get_spells_for_color(color: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spell_id: String in spells_of(color):
		out.append({
			"id": spell_id,
			"name": get_display_name(spell_id),
			"cost": get_unlock_cost(spell_id),
			"desc": get_description(spell_id),
			"ring": get_ring(spell_id),
		})
	return out


## True for a spell that is HELD rather than cast: it starts on the press, runs while
## the button is down, and ends on the release or when its own limit runs out.
static func is_channelled(spell_id: String) -> bool:
	return bool(SPELLS.get(spell_id, {}).get("channel", false))


## The keys a colour's auras sit under, in board order. `manifestation_2` is optional - red
## alone has one (Lightning Orb).
const AURA_SLOTS: Array[String] = ["attunement", "manifestation", "manifestation_2"]


## One colour's auras in board order: attunement, manifestation, and a second manifestation
## where the colour has one. Empty for a colour that has none, which no colour currently does.
static func get_auras(color: String) -> Array[Dictionary]:
	var row: Dictionary = AURAS.get(color, {})
	var out: Array[Dictionary] = []
	for slot: String in AURA_SLOTS:
		if row.has(slot):
			out.append(row[slot])
	return out


## The colour a aura id belongs to, or "" if it is not a aura at all.
static func get_aura_color(aura_id: String) -> String:
	for color: String in AURAS:
		for entry: Dictionary in get_auras(color):
			if String(entry["id"]) == aura_id:
				return color
	return ""


static func get_aura_name(aura_id: String) -> String:
	for color: String in AURAS:
		for entry: Dictionary in get_auras(color):
			if String(entry["id"]) == aura_id:
				return String(entry["name"])
	return ""
