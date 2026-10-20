class_name PlayerCharacterBuilder
extends RefCounted
## Builds a playable class's animated visual and its animation library from that class's
## Mixamo set - one entry in CONFIGS per class (docs/CHARACTER_CLASSES_PLAN.md, "The builder
## per class"). Each class reads its set from assets/player/<class>/ and writes
## scenes/characters/<class>/visual.tscn and assets/animations/player/<class>/lib_<class>.tres;
## the warrior's, the original one, was moved into that layout on 2026-10-18.
##
## Clip names are LOGICAL names shared by every class - "idle", "walk_forward", "cast_red",
## "hit_gut" - so PlayerAnimator and the spells never need to know which class is playing;
## a class's table only says which of its own files plays each one. Clips only one class
## has (the archer's "draw", "aim", "shoot", "dodge_*") are simply absent from the others.
##
## What follows was written for the warrior and still describes it; the archer and the
## barbarian differ where their configs say so (a centimetre-scale rig, a texture embedded in
## the rigged fbx, props instead of a single weapon - and for the barbarian's greatsword,
## swings measured at the blade's tip, the WHOLE trim, root motion kept for its attacks and
## gait clips aligned on the left foot).
##
## A prop moved by hand in a built scene is kept across rebuilds - see PROP_FIT_PATH.
##
## Structurally the same problem tools/character_builder.gd solves for enemies, with
## three differences that are specific to this character and worth stating up front:
##
##  1. This rig is ALREADY at metric scale (~1.905 units head-to-toe), unlike every
##     enemy mesh in this project (~0.02 units, blown up 85-100x). The root scale
##     correction below is therefore ~1.0 and exists only to land exactly on the
##     player's 1.9-tall capsule, not to rescue a tiny import.
##  2. The rigged mesh fbx carries texture *references* but no image data at all, so
##     its PBR maps come from a separate, later Meshy export of the same model
##     (TEXTURE_BASE). _build_material() documents why mixing the two is safe.
##  3. Attack clips are 2.3-4.7s of Mixamo wind-up/recovery against a 0.5s attack
##     cadence. _measure_action_window() records which slice of each is the actual
##     strike, plus the moments of impact, as clip METADATA - the clips themselves are
##     stored whole, and PlayerAnimator plays the window via a custom timeline. The
##     library therefore holds the animations exactly as downloaded.
##
## Run with (no argument builds the warrior; `-- archer`, `-- barbarian` or `-- knight` builds
## that class):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_player_character.gd -- archer
##
## Deadlocks if an editor already holds the project lock; while the editor is open,
## call PlayerCharacterBuilder.build() through Godot MCP's execute_editor_script
## (see tools/character_builder.gd's header for the caching caveat that applies
## to repeated in-editor runs).

const SkinWeightFix = preload("res://tools/skin_weight_fix.gd")
const NormalSmoother = preload("res://tools/normal_smoother.gd")

const PLAYER_ROOT := "res://assets/player/warrior/"
const ANIM_OUT_DIR := "res://assets/animations/player/"
const LIBRARY_PATH := ANIM_OUT_DIR + "warrior/lib_warrior.tres"
const OUTPUT_SCENE := "res://scenes/characters/warrior/visual.tscn"

const MESH_FBX := PLAYER_ROOT + "Meshy_AI_Orc_Warrior_in_Fur_Ar_0829200310_texture.fbx"
## PBR maps live under a different Meshy export id than the rigged mesh - see
## _build_material() for why that is safe. Suffixes: "" (albedo), "_normal",
## "_metallic", "_roughness".
const TEXTURE_BASE := PLAYER_ROOT + "Meshy_AI_Orc_Warrior_in_Fur_Ar_0830103939_texture"

## Matches the 1.9-tall CapsuleShape3D in scenes/misc/player.tscn.
const TARGET_HEIGHT := 1.9

## These Mixamo rigs face +Z: "standing walk forward" carries its hips from
## z = -0.006 to z = +1.318, and a render from the +Z side shows the character's
## face. Godot's forward is -Z, so without this the player moonwalks and stares
## into the camera parked behind them.
##
## The correction goes on the VISUAL, not on the player's forward convention. The
## enemies solve the same mismatch the other way - `EnemyBase` turns with
## `atan2(dir.x, dir.z)` and documents "+Z is forward for these enemies" - but that
## option isn't open here: `Player` is a CharacterBody3D yawed by mouse look, and
## its -Z forward is already baked into the camera rig, the melee cone, the block
## cone and knockback. Rotating the mesh is the one change that touches nothing else.
const FACING_CORRECTION_DEGREES := 180.0

const HIPS_BONE := "mixamorig_Hips"
const WEAPON_HAND_BONE := "mixamorig_RightHand"
const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const HEIGHT_TOP_BONE := "mixamorig_HeadTop_End"
const HEIGHT_BOTTOM_BONE := "mixamorig_LeftToe_End"

const GROUND_SAMPLE_COUNT := 20
## Trimmed clips are rebuilt by resampling rather than by copying keys, so the
## boundaries land exactly on t0/t1 instead of on the nearest original key.
const RESAMPLE_FPS := 30.0

## Trim policy per clip.
enum Trim {
	NONE,   ## keep the clip whole (locomotion, idles, reactions)
	SWING,  ## one strike: keep a tight window centred on the moment of impact
	SPAN,   ## multi-hit flourish: keep the whole stretch where the limb is working
	WHOLE,  ## one blow played whole, wind-up to recovery: the window is the entire clip, and
	        ## the impact its single fastest moment
}

## Fraction of peak limb speed that counts as "the limb is working".
const SWING_SPEED_THRESHOLD := 0.30
## SWING grows outward from the impact frame until the limb has actually settled -
## a fixed window cut some clips while they were still swinging hard (the kick ended
## at 41% of peak speed, cast_black at 42%), which is what a "cut off" animation is.
## It stops at the limits so a strike still fits a 0.5s cadence: a Mixamo swing
## spends most of its runtime drifting back to neutral, and keeping the whole
## above-threshold span (1.9-2.3s measured) would be far too long.
const SWING_SETTLED_FRACTION := 0.25
const SWING_PRE_IMPACT_MAX := 0.60
const SWING_POST_IMPACT_MAX := 0.60
## Never cut closer than this to the impact, however fast the limb is moving there.
const SWING_PRE_IMPACT_MIN := 0.30
const SWING_POST_IMPACT_MIN := 0.30
## SPAN keeps a little breathing room either side so the flourish doesn't pop.
const SPAN_LEAD_IN := 0.12
const SPAN_LEAD_OUT := 0.20
## Clips whose RECOVERY is part of the move rather than dead tail, and so must not be
## trimmed off. A jump attack is the case that needs it: the default lead-out ends the
## window 0.20s after the axe stops moving, which is mid-crouch on the landing, and the
## character then snaps back to idle without ever standing up. Generous values are
## fine - the window is clamped to the clip's own length.
const SPAN_LEAD_OUT_OVERRIDE := {
	"jump_attack": 2.5,
	# The barbarian's chain: its last cut ends in the pack's own return to guard, rather than
	# fading to idle from mid-swing. The knight's ends low and stands back up the same way, and
	# the barbarian's heavy lifts the sword back to its shoulder.
	"cleave_chain": 1.0,
	"slash_chain": 1.0,
	"heavy_combo": 1.0,
}
## Two impacts closer together than this are the same strike, not two hits.
const MIN_HIT_SEPARATION := 0.18
## Clips whose blade whips round between two cuts nearly as fast as it cuts. The knight's chain
## brings the sword back behind its body for the backhand 0.23 s after the first cut, at 84% of
## that cut's speed - the reposition, not a second hit.
const HIT_SEPARATION_OVERRIDE := {
	"slash_chain": 0.3,
}

## clip name -> [source fbx (relative to PLAYER_ROOT), loop, trim policy].
##
## The crouch* set stays excluded. The unarmed set is no longer excluded wholesale:
## the 2026-08-30 "player is always armed" instruction held for everything the player
## does with the weapon, but the armed run reads badly at travel speed, so the two
## unarmed run cycles are pulled in for out-of-combat sprinting only. Everything a
## fight touches - walking under guard, attacking, casting - still uses the armed set.
const CLIPS := {
	# --- locomotion ---
	"idle": ["standing idle.fbx", true, Trim.NONE],
	"idle_look_1": ["standing idle looking ver. 1.fbx", false, Trim.NONE],
	"idle_look_2": ["standing idle looking ver. 2.fbx", false, Trim.NONE],
	"walk_forward": ["standing walk forward.fbx", true, Trim.NONE],
	"walk_back": ["standing walk back.fbx", true, Trim.NONE],
	"walk_left": ["standing walk left.fbx", true, Trim.NONE],
	"walk_right": ["standing walk right.fbx", true, Trim.NONE],
	"run_forward": ["standing run forward.fbx", true, Trim.NONE],
	"run_back": ["standing run back.fbx", true, Trim.NONE],
	# Travel cycles: used when sprinting with no fight in progress. See the note above
	# for why these two are the exception to the armed-only rule.
	"run_forward_unarmed": ["unarmed run forward.fbx", true, Trim.NONE],
	"run_back_unarmed": ["unarmed run back.fbx", true, Trim.NONE],
	"jump": ["standing jump.fbx", false, Trim.NONE],
	# The running take-off, used when the jump starts at a run (PlayerAnimator.begin_jump).
	# Unarmed, like the travel run it leaves from; the axe stays in the hand bone's grip.
	"jump_run": ["unarmed jump running.fbx", false, Trim.NONE],
	# --- attacks (trimmed to the swing) ---
	# The player has exactly two melee moves. The light attack is the combo_3
	# flourish spent one stage per click, and the heavy attack is the 360 spin; the
	# single-swing clips that used to back them are gone along with the old
	# three-press finisher system. combo_2 is the same idea in three stages and is
	# bought in the skill tree.
	"combo_2": ["standing melee combo attack ver. 2.fbx", false, Trim.SPAN],
	"combo_3": ["standing melee combo attack ver. 3.fbx", false, Trim.SPAN],
	"spin_high": ["standing melee attack 360 high.fbx", false, Trim.SPAN],
	"kick": ["standing melee attack kick ver. 1.fbx", false, Trim.SWING],
	# The green ability: a running leap that ends in a ground slam. SPAN rather than
	# SWING because the leap is the point - trimming to the impact alone would keep
	# the slam and throw the jump away.
	"jump_attack": ["standing melee run jump attack.fbx", false, Trim.SPAN],
	# Spell clips: a plain sword chop for the two short physical strikes (Act of
	# Treason, Rabid Bite). Named for the pose, not for a melee move - no melee move
	# uses it.
	"strike_downward": ["standing melee attack downward.fbx", false, Trim.SWING],
	# --- defence & reactions ---
	"block_idle": ["standing block idle.fbx", true, Trim.NONE],
	"block_react": ["standing block react large.fbx", false, Trim.NONE],
	"hit_left": ["standing react large from left.fbx", false, Trim.NONE],
	"hit_right": ["standing react large from right.fbx", false, Trim.NONE],
	"hit_gut": ["standing react large gut.fbx", false, Trim.NONE],
	# Big self-buff / ultimate casts borrow this rather than a spellcasting pose.
	"taunt_battlecry": ["standing taunt battlecry.fbx", false, Trim.SPAN],
}

## Clips the player borrows from the ENEMY rig (57 bones, ~96x smaller), because the
## standing pack has no equivalent: it ships no death animation and no spellcasting
## at all. _adopt_foreign_clip() rescales the hips track and drops anything this rig
## cannot use; rotation tracks transfer by bone name as usual.
##
## The five mage casts adopt more cleanly than the death clip does - every one of
## this rig's 33 bones exists in the source, and each carries exactly ONE position
## track, on Hips, so nothing has to be dropped at all.
##
## clip name -> [source fbx, loop, trim policy]
const FOREIGN_CLIPS := {
	"death": ["res://assets/animations/character/common/death_fallback.fbx", false, Trim.NONE],
	"cast_white": [ANIM_ROOT_SHARED + "mage/attack_white.fbx", false, Trim.SWING],
	"cast_blue": [ANIM_ROOT_SHARED + "mage/attack_blue.fbx", false, Trim.SWING],
	"cast_black": [ANIM_ROOT_SHARED + "mage/attack_black.fbx", false, Trim.SWING],
	"cast_red": [ANIM_ROOT_SHARED + "mage/attack_red.fbx", false, Trim.SWING],
	"cast_green": [ANIM_ROOT_SHARED + "mage/attack_green.fbx", false, Trim.SWING],
}

const ANIM_ROOT_SHARED := "res://assets/animations/character/"

## Kick lands with the foot, not the weapon hand - measuring hand speed would pick
## the wrong frame for it.
const SWING_TRACKING_BONE := {
	"kick": "mixamorig_RightToeBase",
}


# --- the archer -----------------------------------------------------------------------------

## The Meshy "Elven Sentinel", rigged and animated on Mixamo with the Pro Longbow pack and the
## Magic Spell pack (assets/player/archer/magic/). Unlike the orc this rig imports at
## CENTIMETRE scale - 0.0093 units head to toe, like the enemy meshes - so its root scale is
## ~204x. The rigged fbx (export ...830) embeds only the albedo, and the importer is told not
## to extract it (fbx/embedded_image_handling=0): the full PBR set comes from the separate fbx
## export of the same model (...917), whose 20379 triangles carry the same UVs - all of them
## identical to four decimals - and a pixel-identical albedo. The quiver's maps are the
## quiver's own.
const ARCHER_ROOT := "res://assets/player/archer/"
const ARCHER_CLIPS := {
	# --- locomotion: the pack's bow-in-hand set ---
	"idle": ["standing idle 01.fbx", true, Trim.NONE],
	"idle_look_1": ["standing idle 02 looking.fbx", false, Trim.NONE],
	"idle_look_2": ["standing idle 03 examine.fbx", false, Trim.NONE],
	"walk_forward": ["standing walk forward.fbx", true, Trim.NONE],
	"walk_back": ["standing walk back.fbx", true, Trim.NONE],
	"walk_left": ["standing walk left.fbx", true, Trim.NONE],
	"walk_right": ["standing walk right.fbx", true, Trim.NONE],
	# The armed run is the travel run here - a bow does not pin the arms the way the axe did,
	# so there is no unarmed cycle to borrow. The names are the warrior's logical ones.
	"run_forward_unarmed": ["standing run forward.fbx", true, Trim.NONE],
	"run_back_unarmed": ["standing run back.fbx", true, Trim.NONE],
	# The pack has a sideways run, which the warrior's lacks (PlayerAnimator uses these in
	# place of the sped-up sidestep when a library has them).
	"run_left": ["standing run left.fbx", true, Trim.NONE],
	"run_right": ["standing run right.fbx", true, Trim.NONE],
	# No standing jump in the pack: the airborne loop stands in for it, fitted to the hang
	# time like the warrior's jump is.
	"jump": ["fall a loop.fbx", true, Trim.NONE],
	# The landings the airborne loop ends in, standing still and on the move.
	"land": ["fall a land to standing idle 01.fbx", false, Trim.NONE],
	"land_run": ["fall a land to run forward.fbx", false, Trim.NONE],
	# --- the bow (BowKit) ---
	"draw": ["standing draw arrow.fbx", false, Trim.NONE],
	"aim": ["standing aim overdraw.fbx", false, Trim.NONE],
	"shoot": ["standing aim recoil.fbx", false, Trim.NONE],
	"kick": ["standing melee kick.fbx", false, Trim.SWING],
	# --- the dodge roll and Disengage ---
	"dodge_forward": ["standing dodge forward.fbx", false, Trim.NONE],
	"dodge_back": ["standing dodge backward.fbx", false, Trim.NONE],
	"dodge_left": ["standing dodge left.fbx", false, Trim.NONE],
	"dodge_right": ["standing dodge right.fbx", false, Trim.NONE],
	# --- reactions ---
	"hit_gut": ["standing react small from front.fbx", false, Trim.NONE],
	"hit_left": ["standing react small from headshot.fbx", false, Trim.NONE],
	"hit_right": ["standing react small from headshot.fbx", false, Trim.NONE],
	"death": ["standing death backward 01.fbx", false, Trim.NONE],
	# --- the five colours' casts, from the magic pack on this same rig ---
	"cast_white": ["magic/Standing 2H Cast Spell 01.fbx", false, Trim.SWING],
	"cast_blue": ["magic/Standing 1H Magic Attack 01.fbx", false, Trim.SWING],
	"cast_black": ["magic/Standing 1H Magic Attack 02.fbx", false, Trim.SWING],
	"cast_red": ["magic/Standing 2H Magic Attack 01.fbx", false, Trim.SWING],
	"cast_green": ["magic/standing 1H cast spell 01.fbx", false, Trim.SWING],
	"taunt_battlecry": ["magic/Standing 2H Magic Area Attack 01.fbx", false, Trim.SPAN],
}
## Titanic Brawl's leap and slam has no counterpart in either pack, so it is borrowed from the
## warrior's - another Mixamo rig with the same bone names, adopted like the warrior's own
## borrowed clips are.
const ARCHER_FOREIGN_CLIPS := {
	"jump_attack": [PLAYER_ROOT + "standing melee run jump attack.fbx", false, Trim.SPAN],
}

## What each prop is and where it sits, as the prop looks in the rig's REST pose (the T-pose:
## the character faces +Z, its left arm runs along +X with the palm down). `basis` maps the
## prop's own axes into that space, `offset` is metres from the bone's origin in it, and
## `scale` multiplies the prop's own size. See _attach_prop().
##
## The bow is the exception: it is placed from a POSE rather than the rest - see
## _fit_bow(). At full draw in `aim` it stands upright in the left fist with its string side
## (the glb's +Y) towards the drawing hand; `grip` is the point of the glb that sits in the
## fist. Every other clip then carries it rigidly in that hand.
const ARCHER_PROPS := [
	{
		"name": "Bow", "glb": "res://assets/weapons/player/archer_longbow.glb",
		"bone": "mixamorig_LeftHand", "scale": 1.0,
		"fit": {"clip": "aim", "at": 1.5, "grip": Vector3(0.0, -0.075, 0.0),
			"fist_chain": ["mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex4"],
			"draw_hand": "mixamorig_RightHandMiddle1"},
	},
	{
		"name": "Quiver", "glb": "res://assets/weapons/player/archer_quiver.glb",
		"bone": "mixamorig_Spine2",
		# Tilted 25 degrees so the fletchings stand over the RIGHT shoulder, which is where
		# `draw` reaches back for an arrow (the T-pose's right is -X).
		"basis": [Vector3(0.906, 0.423, 0.0), Vector3(-0.423, 0.906, 0.0), Vector3(0.0, 0.0, 1.0)],
		"offset": Vector3(-0.04, -0.06, -0.16), "scale": 0.72,
	},
]

# --- the barbarian --------------------------------------------------------------------------

## The Meshy "Scarred Warchief", rigged and animated on Mixamo with the Great Sword pack. Like
## the archer the rig imports at CENTIMETRE scale (65 bones, fingers included). Its albedo is
## embedded in the rigged fbx (export ...443), and the importer is told not to extract it
## (fbx/embedded_image_handling=0): the full PBR set comes from the separate fbx export of the
## same model (...439), whose 31030 triangles carry the same UVs - 30862 of them identical to
## four decimals, the rest rounding - and the same albedo image.
##
## The pack's file names are numbered ("great sword walk (2).fbx"); they were renamed for what
## each one is when copied in, measured from the hips' root motion: the pack's walk and run
## come one forwards and one backwards, its four strafes are a walk and a run each way.
const BARBARIAN_ROOT := "res://assets/player/barbarian/"
const BARBARIAN_CLIPS := {
	# --- locomotion: the pack's sword-up set ---
	"idle": ["great sword idle.fbx", true, Trim.NONE],
	"idle_look_1": ["great sword idle look.fbx", false, Trim.NONE],
	"idle_look_2": ["great sword idle swing.fbx", false, Trim.NONE],
	"walk_forward": ["great sword walk forward.fbx", true, Trim.NONE],
	"walk_back": ["great sword walk back.fbx", true, Trim.NONE],
	"walk_left": ["great sword walk left.fbx", true, Trim.NONE],
	"walk_right": ["great sword walk right.fbx", true, Trim.NONE],
	# The run is the travel run, as for the archer: there is no unarmed set to borrow, and the
	# pack's run carries the sword well enough at speed.
	"run_forward_unarmed": ["great sword run forward.fbx", true, Trim.NONE],
	"run_back_unarmed": ["great sword run back.fbx", true, Trim.NONE],
	"run_left": ["great sword run left.fbx", true, Trim.NONE],
	"run_right": ["great sword run right.fbx", true, Trim.NONE],
	# The standing jump; the pack's other one is a running leap that carries 1.9 m forward.
	"jump": ["great sword jump.fbx", false, Trim.NONE],
	# --- the two-hander (GreatswordKit) ---
	# The light chain: a long multi-stroke flourish, spent one stage per click like the
	# warrior's combo_3.
	"cleave_chain": ["great sword slash combo.fbx", false, Trim.SPAN],
	# The heavy: two big swings, the first the harder - Mixamo's "Standing Melee Combo Attack
	# Ver. 1", downloaded on this model - played as soon as the hold is long enough.
	"heavy_combo": ["standing melee combo attack ver. 1.fbx", false, Trim.SPAN],
	"kick": ["great sword kick.fbx", false, Trim.SWING],
	# Whirlwind's pose: the sword held out level across the body. The spin is the animator's
	# (PlayerAnimator.WHIRLWIND_CLIP), turning the whole figure.
	"whirlwind": ["great sword guard hold.fbx", false, Trim.NONE],
	# Titanic Brawl (green_1): the warrior's running leap and slam, downloaded on this model.
	"jump_attack": ["standing melee run jump attack.fbx", false, Trim.SPAN],
	# --- reactions ---
	"hit_gut": ["great sword react gut.fbx", false, Trim.NONE],
	"hit_left": ["great sword react side.fbx", false, Trim.NONE],
	"hit_right": ["great sword react side.fbx", false, Trim.NONE],
	"death": ["great sword death.fbx", false, Trim.NONE],
	# --- the five colours' casts ---
	# The pack has one cast: the free LEFT hand thrown forward with the sword kept up in the
	# right. A colour's spell is told apart by its own effect, as everywhere else; borrowed
	# two-handed casts would have swung the sword through the body.
	"cast_white": ["great sword spell cast.fbx", false, Trim.SWING],
	"cast_blue": ["great sword spell cast.fbx", false, Trim.SWING],
	"cast_black": ["great sword spell cast.fbx", false, Trim.SWING],
	"cast_red": ["great sword spell cast.fbx", false, Trim.SWING],
	"cast_green": ["great sword spell cast.fbx", false, Trim.SWING],
	# Berserk and the other big self-buffs: the sword held across the body, powering up.
	"taunt_battlecry": ["great sword power up.fbx", false, Trim.SPAN],
}
## The casts are thrown with the left hand, so that is the hand whose speed finds their release.
const BARBARIAN_TRACKING := {
	"cast_white": "mixamorig_LeftHand", "cast_blue": "mixamorig_LeftHand",
	"cast_black": "mixamorig_LeftHand", "cast_red": "mixamorig_LeftHand",
	"cast_green": "mixamorig_LeftHand",
}
## The greatsword, placed from the pose it is held in - see _fit_in_pose(). The glb's origin
## is where the upper fist closes round the grip (assets/player/barbarian/source/prepare_sword.py).
const BARBARIAN_PROPS := [
	{
		"name": "Greatsword", "glb": "res://assets/weapons/player/barbarian_greatsword.glb",
		"bone": "mixamorig_RightHand", "scale": 1.0,
		"fit": {"kind": "two_hand", "clip": "idle", "at": 0.5, "grip": Vector3.ZERO,
			"upper": "mixamorig_RightHand", "upper_knuckle": "mixamorig_RightHandMiddle1",
			"lower": "mixamorig_LeftHand", "lower_knuckle": "mixamorig_LeftHandMiddle1"},
	},
]

# --- the knight -----------------------------------------------------------------------------

## The Meshy "Sunforged Warlord", rigged and animated on Mixamo with the Pro Sword and Shield
## pack and the Magic Spell pack (assets/player/knight/magic/). Like the archer and the
## barbarian the rig imports at centimetre scale, its albedo comes embedded in the rigged fbx
## (export ...822, not extracted) and the PBR set from the separate fbx export (...815, the same
## UVs on 47725 of 47908 triangles). Rigged with 33 bones: ONE finger chain a hand (the index),
## no thumb - so the fingers are merged onto it (mitten_fingers) to close round sword and shield.
##
## The pack's numbered files were renamed for what each one is when copied in, measured from
## the hips: `walk`/`run` forwards and `(2)` backwards, `strafe (2)`/`(3)` to the left (+X in
## Blender is the character's left), `strafe`/`(4)` to the right.
const KNIGHT_ROOT := "res://assets/player/knight/"
const KNIGHT_CLIPS := {
	# --- locomotion: the pack's sword-and-shield set ---
	"idle": ["sword and shield idle.fbx", true, Trim.NONE],
	"idle_look_1": ["sword and shield idle look.fbx", false, Trim.NONE],
	"idle_look_2": ["sword and shield idle stretch.fbx", false, Trim.NONE],
	"walk_forward": ["sword and shield walk forward.fbx", true, Trim.NONE],
	"walk_back": ["sword and shield walk back.fbx", true, Trim.NONE],
	"walk_left": ["sword and shield walk left.fbx", true, Trim.NONE],
	"walk_right": ["sword and shield walk right.fbx", true, Trim.NONE],
	"run_forward_unarmed": ["sword and shield run forward.fbx", true, Trim.NONE],
	"run_back_unarmed": ["sword and shield run back.fbx", true, Trim.NONE],
	"run_left": ["sword and shield run left.fbx", true, Trim.NONE],
	"run_right": ["sword and shield run right.fbx", true, Trim.NONE],
	"jump": ["sword and shield jump.fbx", false, Trim.NONE],
	# --- sword and shield (KnightKit) ---
	# The light chain: the pack's long combo (its "slash (2)"), three cuts that step, spin and
	# end low, spent one cut per click like the barbarian's cleave_chain.
	"slash_chain": ["sword and shield slash combo.fbx", false, Trim.SPAN],
	# The heavy: one big cut, played whole as soon as the hold is long enough.
	"heavy_slash": ["sword and shield slash heavy.fbx", false, Trim.WHOLE],
	"kick": ["sword and shield kick.fbx", false, Trim.SWING],
	# Shield Bash: the pack's shield-arm thrust (its "casting (2)").
	"shield_bash": ["sword and shield shield bash.fbx", false, Trim.SWING],
	# Titanic Brawl (green_1): the pack's leap and downward cut.
	"jump_attack": ["sword and shield jump attack.fbx", false, Trim.SPAN],
	# --- the guard ---
	"block_idle": ["sword and shield block idle.fbx", true, Trim.NONE],
	"block_react": ["sword and shield block react.fbx", false, Trim.NONE],
	# --- reactions ---
	"hit_gut": ["sword and shield react gut.fbx", false, Trim.NONE],
	"hit_left": ["sword and shield react side.fbx", false, Trim.NONE],
	"hit_right": ["sword and shield react side.fbx", false, Trim.NONE],
	"death": ["sword and shield death.fbx", false, Trim.NONE],
	# --- the five colours' casts, from the magic pack on this same rig ---
	# The one-handed casts are thrown with the SWORD hand - the knight points the blade at what
	# the spell goes for; the white one raises sword and shield together.
	"cast_white": ["magic/Standing 2H Cast Spell 01.fbx", false, Trim.SWING],
	"cast_blue": ["magic/Standing 1H Magic Attack 01.fbx", false, Trim.SWING],
	"cast_black": ["magic/Standing 1H Magic Attack 02.fbx", false, Trim.SWING],
	"cast_red": ["magic/Standing 1H Magic Attack 03.fbx", false, Trim.SWING],
	"cast_green": ["magic/standing 1H cast spell 01.fbx", false, Trim.SWING],
	"taunt_battlecry": ["sword and shield power up.fbx", false, Trim.SPAN],
}
## The shield thrust is the shield hand's.
const KNIGHT_TRACKING := {
	"shield_bash": "mixamorig_LeftHand",
}
## The sword in the right fist and the shield on the left, each placed from the pose it is
## held in (_fit_one_hand, _fit_shield). Both glbs have their origin where the fist closes
## (assets/player/knight/source/prepare_props.py).
const KNIGHT_PROPS := [
	{
		"name": "Sword", "glb": "res://assets/weapons/player/knight_sword.glb",
		"bone": "mixamorig_RightHand", "scale": 1.0,
		"fit": {"kind": "one_hand", "clip": "idle", "at": 0.5,
			"fist_chain": ["mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex4"]},
	},
	{
		"name": "Shield", "glb": "res://assets/weapons/player/knight_shield.glb",
		"bone": "mixamorig_LeftHand", "scale": 1.0,
		"fit": {"kind": "shield", "clip": "block_idle", "at": 0.5,
			"fist_chain": ["mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex4"]},
	},
]

# --- the mage -------------------------------------------------------------------------------

## The Meshy "Arcane Wayfarer", rigged on Mixamo as a 65-bone skeleton (all five finger chains)
## and animated with the Magic Locomotion pack and the Magic Spell pack (assets/player/mage/magic/).
## Bare-handed - no staff - so it has no props. Like the archer the rig imports at centimetre
## scale, its albedo comes embedded in the rigged fbx (export ...512, not extracted) and the PBR
## set from the separate fbx export (...516, the same albedo byte for byte).
##
## The spell pack's three one-handed attacks all throw with the RIGHT hand (measured: right hand
## 5.4-7.8 m/s at the release against 1.9-4.2 for the left), so they are the bolts, thrown in
## turn; its two-handed ones are the heavy blast and the colour casts.
const MAGE_ROOT := "res://assets/player/mage/"
const MAGE_CLIPS := {
	# --- locomotion: the Magic Locomotion pack ---
	"idle": ["standing idle.fbx", true, Trim.NONE],
	"walk_forward": ["standing walk forward.fbx", true, Trim.NONE],
	"walk_back": ["standing walk back.fbx", true, Trim.NONE],
	"walk_left": ["standing walk left.fbx", true, Trim.NONE],
	"walk_right": ["standing walk right.fbx", true, Trim.NONE],
	# The pack's run is the travel run, as for the archer: hands free, nothing to put away.
	"run_forward_unarmed": ["standing run forward.fbx", true, Trim.NONE],
	"run_back_unarmed": ["standing run back.fbx", true, Trim.NONE],
	"run_left": ["standing run left.fbx", true, Trim.NONE],
	"run_right": ["standing run right.fbx", true, Trim.NONE],
	"jump": ["standing jump.fbx", false, Trim.NONE],
	# The pack's running jump, and the landing it comes down into.
	"jump_run": ["standing jump running.fbx", false, Trim.NONE],
	"land_run": ["standing jump running landing.fbx", false, Trim.NONE],
	# --- the bolts (MageKit): the three one-handed throws, one a click in turn ---
	"bolt_1": ["magic/Standing 1H Magic Attack 01.fbx", false, Trim.SWING],
	"bolt_2": ["magic/Standing 1H Magic Attack 02.fbx", false, Trim.SWING],
	"bolt_3": ["magic/Standing 1H Magic Attack 03.fbx", false, Trim.SWING],
	# The heavy: a half turn to gather and both hands thrown forward.
	"arcane_blast": ["magic/Standing 2H Magic Attack 02.fbx", false, Trim.SWING],
	# --- the five colours' casts ---
	# White raises both hands to the sky; blue thrusts both forward and holds (a breath, a
	# wave); black crouches and rises; red throws both hands; green calls with one raised.
	"cast_white": ["magic/Standing 2H Cast Spell 01.fbx", false, Trim.SWING],
	"cast_blue": ["magic/Standing 2H Magic Attack 03.fbx", false, Trim.SWING],
	"cast_black": ["magic/Standing 2H Magic Attack 05.fbx", false, Trim.SWING],
	"cast_red": ["magic/Standing 2H Magic Attack 01.fbx", false, Trim.SWING],
	"cast_green": ["magic/standing 1H cast spell 01.fbx", false, Trim.SWING],
	# The big self-buffs and Mana Surge: arms thrown wide, drawing power in.
	"taunt_battlecry": ["magic/Standing 2H Magic Area Attack 02.fbx", false, Trim.SPAN],
}
## Neither pack has hit reactions or a death, and neither has Titanic Brawl's leap: the
## reactions and the death are the enemy mages' own (bare-handed too), the leap the warrior's.
const MAGE_FOREIGN_CLIPS := {
	"hit_gut": [ANIM_ROOT_SHARED + "mage/hit.fbx", false, Trim.NONE],
	"hit_left": [ANIM_ROOT_SHARED + "mage/hit.fbx", false, Trim.NONE],
	"hit_right": [ANIM_ROOT_SHARED + "mage/hit.fbx", false, Trim.NONE],
	"death": [ANIM_ROOT_SHARED + "mage/death.fbx", false, Trim.NONE],
	"jump_attack": [PLAYER_ROOT + "standing melee run jump attack.fbx", false, Trim.SPAN],
}
## White's release is the two hands going up, which the LEFT one leads; the right one's fastest
## moment is the crouch before it.
const MAGE_TRACKING := {
	"cast_white": "mixamorig_LeftHand",
}

## The warrior's hatchet in the right fist, placed as the knight's sword is (_one_hand_in_pose):
## the glb's origin is in the handle just above the knob, its edge along +X
## (assets/player/warrior/source/prepare_hatchet.py). Until 2026-10-18 the warrior carried a
## metre-long axe placed by hand-found constants off the rest pose instead.
const WARRIOR_PROPS := [
	{
		"name": "Hatchet", "glb": "res://assets/weapons/player/warrior_hatchet.glb",
		"bone": "mixamorig_RightHand", "scale": 1.0,
		"fit": {"kind": "one_hand", "clip": "idle", "at": 0.5,
			"fist_chain": ["mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex4"]},
	},
]

## One entry per class.
const CONFIGS := {
	"warrior": {
		"root": PLAYER_ROOT,
		"mesh": MESH_FBX,
		"texture_base": TEXTURE_BASE,
		"clips": CLIPS,
		"foreign": FOREIGN_CLIPS,
		"library": LIBRARY_PATH,
		"scene": OUTPUT_SCENE,
		# How the chin is handed from the neck to the head - tools/skin_weight_fix.gd's header
		# says what each number does. Re-apply after changing them with
		# tools/fix_player_chins.gd -- warrior (no rebuild needed).
		# Wider than the default: the orc's jowls, from below the ear to under the jaw, were
		# 60-90% on the neck and made a double chin when the head turned. Everything lower is
		# already on the chest (the fur collar), so the band can reach down without the throat
		# twisting the way the elf's did.
		"chin": {"forward_start": -0.03, "forward_full": 0.10, "jaw_low": -0.36, "jaw_high": -0.14, "strength": 1.0},
		"props": WARRIOR_PROPS,
	},
	"archer": {
		"root": ARCHER_ROOT,
		"mesh": ARCHER_ROOT + "Meshy_AI_Elven_Sentinel_of_the_1017104830_texture_obj.fbx",
		"texture_base": ARCHER_ROOT + "Meshy_AI_Elven_Sentinel_of_the_1018213917_texture",
		"clips": ARCHER_CLIPS,
		"foreign": ARCHER_FOREIGN_CLIPS,
		"library": "res://assets/animations/player/archer/lib_archer.tres",
		"scene": "res://scenes/characters/archer/visual.tscn",
		"props": ARCHER_PROPS,
		"chin": {"forward_start": 0.18, "forward_full": 0.32, "jaw_low": -0.20, "jaw_high": -0.07, "strength": 1.0},
		# Rigged as "3 chain fingers", with the middle chain at the fingertips: only the index
		# finger curled round the bow. All four now bend on the index joints
		# (SkinWeightFix.mitten_fingers).
		"mitten_fingers": true,
		# The roll is carried by its clip's own hop, whichever way it goes (DodgeRoll).
		"root_travel": ["dodge_forward", "dodge_back", "dodge_left", "dodge_right"],
	},
	"barbarian": {
		"root": BARBARIAN_ROOT,
		"mesh": BARBARIAN_ROOT + "Meshy_AI_Scarred_Warchief_1018115443_texture_obj.fbx",
		"texture_base": BARBARIAN_ROOT + "Meshy_AI_Scarred_Warchief_1018115439_texture",
		"clips": BARBARIAN_CLIPS,
		"foreign": {},
		"tracking": BARBARIAN_TRACKING,
		# Swings are measured near the sword's tip (1.52 m past the grip), and only the cuts that
		# come near the fastest count as impacts - the tip is fast all through a flourish.
		"blade": {"prop": "Greatsword", "tip": 1.3},
		"hit_threshold": 0.6,
		# The pack's walks start anywhere in the stride; line them up on the left foot.
		"align_gait": true,
		# The cleaves walk forwards as they cut, and the overhead steps in and back out; the body
		# is moved by that, not stood still.
		"root_motion": ["cleave_chain", "heavy_combo"],
		# Meshy exported this model faceted (split normals at 80% of its positions).
		"smooth_normals": true,
		"library": "res://assets/animations/player/barbarian/lib_barbarian.tres",
		"scene": "res://scenes/characters/barbarian/visual.tscn",
		"props": BARBARIAN_PROPS,
	},
	"knight": {
		"root": KNIGHT_ROOT,
		"mesh": KNIGHT_ROOT + "Meshy_AI_Sunforged_Warlord_1018195822_texture_obj.fbx",
		"texture_base": KNIGHT_ROOT + "Meshy_AI_Sunforged_Warlord_1018195815_texture",
		"clips": KNIGHT_CLIPS,
		"foreign": {},
		"tracking": KNIGHT_TRACKING,
		"blade": {"prop": "Sword", "tip": 0.75},
		"hit_threshold": 0.6,
		"align_gait": true,
		# The chain steps forwards with its cuts, the heavy steps into its blow; the body is moved
		# by that, not stood still.
		"root_motion": ["slash_chain", "heavy_slash"],
		# Faceted like the Warchief: split normals at most of its positions.
		"smooth_normals": true,
		"mitten_fingers": true,
		# Mixamo hung the jaw, the cheek guards and the helmet's rim on Spine2 (next to nothing
		# on the Neck), so the lower helmet stayed with the chest when the head turned; all of
		# it goes to the head (tools/skin_weight_fix.gd, rigid_head - neck-to-crown units from
		# the head joint). Full from the bottom of the cheek guards (1.53 m), fading out down the
		# bare throat to the top of the breastplate (1.43 m), so the throat twists along its
		# length - a hard edge under the chin put the whole turn on 3 cm and smeared it. The
		# shoulder spikes and the hair down the back are outside the box.
		"rigid_head": {"low": -0.475, "high": -0.16, "side_full": 0.38, "side_zero": 0.47,
			"back_full": -0.40, "back_zero": -0.53},
		# The plates hanging in front of and behind the crotch were split down the middle between
		# the thighs and tore apart with every step; each is shared evenly between the legs, and
		# half of that goes to the hips so they swing half as far as the thighs (even_plates -
		# thigh-length units from the hips joint). Their tips hang to about 0.76 m. Measured as
		# edge stretch over the gait, kick and leap clips, the evening alone took the worst 1% of
		# the front plate from 2-6x its length down to 1.3-2.9x, and to_hips 0.5 to 0.55-0.97x;
		# 1.0 stops it stretching at all but lets a raised thigh push through it.
		"even_plates": {"low": -0.63, "high": -0.536, "side_full": 0.107, "side_zero": 0.167,
			"depth_zero": 0.26, "depth_full": 0.31, "to_hips": 0.5},
		"library": "res://assets/animations/player/knight/lib_knight.tres",
		"scene": "res://scenes/characters/knight/visual.tscn",
		"props": KNIGHT_PROPS,
	},
	"mage": {
		"root": MAGE_ROOT,
		"mesh": MAGE_ROOT + "Meshy_AI_Arcane_Wayfarer_1018221512_texture_obj.fbx",
		"texture_base": MAGE_ROOT + "Meshy_AI_Arcane_Wayfarer_1018221516_texture",
		"clips": MAGE_CLIPS,
		"foreign": MAGE_FOREIGN_CLIPS,
		"tracking": MAGE_TRACKING,
		# The locomotion pack's walks start anywhere in the stride, as the barbarian's do.
		"align_gait": true,
		"smooth_normals": true,
		# Its normal map was baked against the faceted export: on the smoothed mesh it drew hard
		# creases through the face along its UV islands (tools/tests/class_visual_shot.tscn
		# ... mixamorig_Head 0.55, with and without --no-normal-map). The albedo carries the detail.
		"normal_map": false,
		"library": "res://assets/animations/player/mage/lib_mage.tres",
		"scene": "res://scenes/characters/mage/visual.tscn",
		"props": [],
	},
}

## Hand adjustments to the props, laid on top of the fitted placement - the player's side of
## what assets/weapons/weapon_fit.json is for the enemies. Move a prop in its visual scene in
## the editor and save; build() reads the nudge back out of the scene before it rebuilds
## (capture_prop_fits), so nothing dragged is lost, and tools/capture_player_prop_fit.gd
## writes it here without a rebuild. Keyed "<class>/<prop node>", e.g. "knight/Shield"; each
## entry is the nudge in the prop's own frame (see _prop_fit). Written by a tool, so it is a
## data file rather than more numbers in the configs below.
const PROP_FIT_PATH := "res://assets/player/prop_fit.json"

## The class being built. Set by build() before anything reads it.
static var _class_id: String = "warrior"
static var _cfg: Dictionary = CONFIGS["warrior"]
## The tip of the class's blade in its weapon hand's frame, or zero for a class measured at
## the hand (see _measure_blade_tip). Set by _build_template_library.
static var _blade_tip: Vector3 = Vector3.ZERO


static func build(class_id: String = "warrior") -> bool:
	if not CONFIGS.has(class_id):
		push_error("No builder config for class '%s'" % class_id)
		return false
	# Before the scene is overwritten: a prop moved there by hand is kept.
	capture_prop_fits(class_id)
	_class_id = class_id
	_cfg = CONFIGS[class_id]
	var mesh_path: String = _cfg["mesh"]
	var base_scene: PackedScene = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load player mesh %s" % mesh_path)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = "PlayerVisual"

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if anim_player == null or skeleton == null or mesh_node == null:
		push_error("Player mesh is missing an AnimationPlayer, Skeleton3D or MeshInstance3D")
		return false

	if _cfg.get("smooth_normals", false):
		smooth_normals(mesh_node)
	(mesh_node.mesh as ArrayMesh).surface_set_material(0, _build_material())
	# Mixamo leaves the chin half on the neck; it goes to the head - and whatever else the
	# config asks to have re-weighted (tools/skin_weight_fix.gd).
	SkinWeightFix.apply_class_fixes(mesh_node, skeleton, _cfg)

	# Scale/lift must be set BEFORE grounding: the correction is measured in this
	# same (post-normalization) coordinate frame.
	_normalize_to_target_height(root, skeleton)

	# Both measurement passes below step the clip by hand rather than by letting a
	# frame elapse, so the mixer must not also be advancing itself. Restored before
	# packing so the shipped scene keeps the importer's own callback mode.
	var original_callback_mode := anim_player.callback_mode_process
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var template := _build_template_library(skeleton, anim_player, root)
	if template == null:
		return false

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var library := _ground_correct_library(template, anim_player, root, skeleton)
	anim_player.callback_mode_process = original_callback_mode

	var library_path: String = _cfg["library"]
	var scene_path: String = _cfg["scene"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(library_path.get_base_dir()))
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Failed saving %s" % library_path)
		return false
	anim_player.add_animation_library("", ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists.
	anim_player.autoplay = "idle"

	for spec: Dictionary in _cfg["props"]:
		_attach_prop(skeleton, spec)
	_own_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("PackedScene.pack failed for the player visual")
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_path.get_base_dir()))
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("ResourceSaver.save failed for %s" % scene_path)
		return false

	print("Saved ", scene_path, " with ", library.get_animation_list().size(), " clips.")
	root.queue_free()
	return true


static func _build_template_library(skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var clips: Dictionary = _cfg["clips"]
	# The clip's root motion is in the rig's own units; the animator compares it with the
	# body's real speed in metres. The orc's rig is metric, so this was ~1.0 and went
	# unnoticed - the archer's is centimetre-scale and needs the ~204x.
	var world_scale: float = root.transform.basis.get_scale().y
	var extracted: Dictionary = {}
	for clip_name in clips.keys():
		var spec: Array = clips[clip_name]
		var anim := _extract_animation(String(_cfg["root"]) + spec[0])
		if anim == null:
			push_error("Could not extract clip '%s' from %s" % [clip_name, spec[0]])
			return null
		# Measured BEFORE the root motion is stripped - afterwards there is nothing
		# left to measure, and the animator needs it to match stride to real speed.
		if spec[1]:
			anim.set_meta("travel_speed", _measure_travel_speed(anim) * world_scale)
		if (_cfg.get("root_motion", []) as Array).has(clip_name):
			anim.set_meta("root_forward", _sample_root_forward(anim, skeleton, root))
		if (_cfg.get("root_travel", []) as Array).has(clip_name):
			anim.set_meta("root_travel", _sample_root_travel(anim, skeleton, root))
		if JUMP_CLIPS.has(clip_name):
			var phases: PackedFloat32Array = _measure_jump_phases(anim, skeleton, root)
			if not phases.is_empty():
				anim.set_meta("jump_phases", phases)
		_strip_horizontal_root_motion(anim, HIPS_BONE)
		extracted[clip_name] = anim
	# A blade is measured at its tip rather than at the hand, and where the tip is depends on
	# how the sword sits in the hand - which is fitted on one of these same clips.
	_blade_tip = Vector3.ZERO
	if _cfg.has("blade"):
		_blade_tip = _measure_blade_tip(skeleton, anim_player, extracted)
	for clip_name in clips.keys():
		var spec: Array = clips[clip_name]
		var anim: Animation = extracted[clip_name]
		if spec[2] != Trim.NONE:
			_measure_action_window(anim, clip_name, spec[2], skeleton, anim_player, root)
		anim.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		library.add_animation(clip_name, anim)

	var foreign: Dictionary = _cfg["foreign"]
	for clip_name in foreign.keys():
		var spec: Array = foreign[clip_name]
		var adopted := _adopt_foreign_clip(spec[0], skeleton, clip_name)
		if adopted == null:
			push_warning("Could not adopt '%s' from %s" % [clip_name, spec[0]])
			continue
		if spec[2] != Trim.NONE:
			_measure_action_window(adopted, clip_name, spec[2], skeleton, anim_player, root)
		adopted.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		library.add_animation(clip_name, adopted)
	return library


static func _extract_animation(source_fbx_path: String) -> Animation:
	var source_scene: PackedScene = ResourceLoader.load(source_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if source_scene == null:
		return null
	var source_root: Node = source_scene.instantiate()
	var player: AnimationPlayer = source_root.find_child("AnimationPlayer", true, false)
	if player == null or player.get_animation_list().is_empty():
		source_root.queue_free()
		return null
	var anim: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	source_root.queue_free()
	return anim


## Ported from tools/character_builder.gd - movement is driven by the CharacterBody3D,
## so the clip must not also walk the character across the floor.
static func _strip_horizontal_root_motion(anim: Animation, bone_name: String) -> void:
	var track_idx := _find_position_track(anim, bone_name)
	if track_idx == -1:
		return
	var key_count := anim.track_get_key_count(track_idx)
	if key_count == 0:
		return
	var base_value: Vector3 = anim.track_get_key_value(track_idx, 0)
	for key_idx in key_count:
		var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
		anim.track_set_key_value(track_idx, key_idx, Vector3(base_value.x, value.y, base_value.z))


## How fast the clip's own root motion carries the character along the floor, in
## units/second. Locomotion is driven by the CharacterBody3D, so this is what the
## animator divides real velocity by to pick a playback speed that keeps the feet
## planted instead of skating.
static func _measure_travel_speed(anim: Animation) -> float:
	var track_idx := _find_position_track(anim, HIPS_BONE)
	if track_idx == -1 or anim.length <= 0.0:
		return 0.0
	var key_count := anim.track_get_key_count(track_idx)
	if key_count < 2:
		return 0.0
	var first: Vector3 = anim.track_get_key_value(track_idx, 0)
	var last: Vector3 = anim.track_get_key_value(track_idx, key_count - 1)
	return Vector2(last.x - first.x, last.z - first.z).length() / anim.length


## How far the clip's own root motion has carried the character FORWARDS, in metres, at every
## 1/RESAMPLE_FPS of the clip from its start - for an attack the game moves the body with
## instead of stripping its travel away (CONFIGS[<class>]["root_motion"]; PlayerAnimator.
## root_forward). Read off the hips track before it is flattened. These rigs face +Z in the
## visual's own frame (FACING_CORRECTION_DEGREES turns them round), so forwards is +Z there;
## sideways drift is left out on purpose - the player steers, the clip only paces.
static func _sample_root_forward(anim: Animation, skeleton: Skeleton3D, root: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var track := _find_position_track(anim, HIPS_BONE)
	if track == -1:
		return out
	var to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var world_scale: float = root.transform.basis.get_scale().y
	var start: float = (to_root * anim.position_track_interpolate(track, 0.0)).z
	var t: float = 0.0
	while t <= anim.length + 0.0001:
		out.append(((to_root * anim.position_track_interpolate(track, t)).z - start) * world_scale)
		t += 1.0 / RESAMPLE_FPS
	print("  root   %-13s carries %.2f m forwards over %.2fs" % [anim.resource_name if anim.resource_name != "" else "clip", out[out.size() - 1], anim.length])
	return out


## Like _sample_root_forward, but the distance the hips have gone over the floor in ANY
## direction - for a clip that travels one way that is not forwards, like a sideways dodge
## (CONFIGS[<class>]["root_travel"]; PlayerAnimator.root_travel).
static func _sample_root_travel(anim: Animation, skeleton: Skeleton3D, root: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var track := _find_position_track(anim, HIPS_BONE)
	if track == -1:
		return out
	var to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var world_scale: float = root.transform.basis.get_scale().y
	var start: Vector3 = to_root * anim.position_track_interpolate(track, 0.0)
	var t: float = 0.0
	while t <= anim.length + 0.0001:
		var offset: Vector3 = to_root * anim.position_track_interpolate(track, t) - start
		out.append(Vector2(offset.x, offset.z).length() * world_scale)
		t += 1.0 / RESAMPLE_FPS
	print("  root   %-13s travels %.2f m over %.2fs" % [anim.resource_name if anim.resource_name != "" else "clip", out[out.size() - 1], anim.length])
	return out


## The clips PlayerAnimator plays as a jump, in three phases (begin_jump).
const JUMP_CLIPS := ["jump", "jump_run"]
## A jump clip whose hips rise less than this has no take-off to measure - the archer's
## airborne loop - and is played as it is.
const JUMP_MIN_LIFT := 0.15
## The hips' height, as a share of the clip's own peak, that counts as standing height: the
## take-off is where they come back up through it out of the crouch (the feet leave the
## ground there; below it the legs are still pushing), the touchdown where they sink through
## it again after the peak.
const JUMP_GROUND_SHARE := 0.15


## Where a jump clip leaves the ground, peaks and comes back down, in seconds of clip, read
## off the hips' height in metres. PlayerAnimator plays the crouch before the take-off as the
## run-up, starts the body's own arc on the take-off frame and lines the clip's peak up with
## the arc's, so the clip's lift and the jump's add up at the same moment instead of one after
## the other. Empty for a clip whose hips hardly rise.
static func _measure_jump_phases(anim: Animation, skeleton: Skeleton3D, root: Node3D) -> PackedFloat32Array:
	var track := _find_position_track(anim, HIPS_BONE)
	if track == -1:
		return PackedFloat32Array()
	var to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var world_scale: float = root.transform.basis.get_scale().y
	var base: float = (to_root * anim.position_track_interpolate(track, 0.0)).y
	var step: float = 1.0 / RESAMPLE_FPS
	var heights := PackedFloat32Array()
	var t: float = 0.0
	while t <= anim.length + 0.0001:
		heights.append(((to_root * anim.position_track_interpolate(track, t)).y - base) * world_scale)
		t += step
	var apex: int = 0
	for i in heights.size():
		if heights[i] > heights[apex]:
			apex = i
	if heights[apex] < JUMP_MIN_LIFT:
		return PackedFloat32Array()
	var ground: float = heights[apex] * JUMP_GROUND_SHARE
	# Out of the lowest point of the crouch, up through standing height.
	var dip: int = 0
	for i in apex:
		if heights[i] < heights[dip]:
			dip = i
	var takeoff: float = 0.0
	for i in range(dip + 1, apex + 1):
		if heights[i] >= ground:
			takeoff = _crossing(heights, i, ground) * step if heights[i - 1] < ground else float(i - 1) * step
			break
	var touchdown: float = anim.length
	for i in range(apex + 1, heights.size()):
		if heights[i] <= ground:
			touchdown = _crossing(heights, i, ground) * step
			break
	touchdown = minf(touchdown, anim.length)
	print("  jump   %-13s takes off %.2fs, peaks %.2fs (+%.2f m), lands %.2fs of %.2fs" % [
		anim.resource_name if anim.resource_name != "" else "clip", takeoff, float(apex) * step,
		heights[apex], touchdown, anim.length])
	return PackedFloat32Array([takeoff, float(apex) * step, touchdown])


## Where, in samples, the height passes `level` between sample `i - 1` and sample `i`.
static func _crossing(heights: PackedFloat32Array, i: int, level: float) -> float:
	var a: float = heights[i - 1]
	var b: float = heights[i]
	if is_equal_approx(a, b):
		return float(i)
	return float(i - 1) + clampf((level - a) / (b - a), 0.0, 1.0)


static func _find_position_track(anim: Animation, bone_name: String) -> int:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			return track_idx
	return -1


# --- swing trimming -----------------------------------------------------------

## Works out which part of a Mixamo clip is actually the strike - these ship with
## long neutral-stance lead-ins and recoveries that are unusable at a 0.5s cadence -
## and records it as metadata. It does NOT cut the clip up.
##
## That distinction matters: an earlier version sliced the animation down to the
## window, which meant the saved library contained truncated animations. Opening the
## scene showed 0.63s stumps instead of the 2.40s clips that were downloaded, and
## changing your mind about the window meant a rebuild. The full animation is stored
## and `PlayerAnimator` plays the window through AnimationNodeAnimation's custom
## timeline (start_offset + timeline_length) instead.
##
## Metadata written:
##   trim_start   where the usable window begins, in seconds into the full clip
##   trim_length  how long that window is
##   hit_ratios   moments of impact, normalized WITHIN the window
##
## SWING takes a tight window around the single loudest impact; SPAN takes the whole
## working stretch, which for the combo clips is a genuine multi-hit flourish.
static func _measure_action_window(anim: Animation, clip_name: String, policy: Trim, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D) -> void:
	var tracking: Dictionary = (_cfg.get("tracking", {}) as Dictionary)
	var bone_name: String = tracking.get(clip_name, SWING_TRACKING_BONE.get(clip_name, WEAPON_HAND_BONE))
	# A class with a blade is measured at the blade's tip, wherever the weapon hand is the
	# limb that counts: on a two-hander the hand barely moves on a cut that the tip carries
	# through two metres, and it moves quite fast hauling the sword back up between cuts.
	var tip: Vector3 = _blade_tip if bone_name == WEAPON_HAND_BONE else Vector3.ZERO
	var samples := _sample_bone_speed(anim, skeleton, anim_player, root, bone_name, tip)
	var peak_speed: float = 0.0
	var peak_time: float = 0.0
	for s in samples:
		if s.y > peak_speed:
			peak_speed = s.y
			peak_time = s.x
	if peak_speed <= 0.0:
		push_warning("Could not measure a strike in '%s'; it will play whole" % clip_name)
		anim.set_meta("trim_start", 0.0)
		anim.set_meta("trim_length", anim.length)
		anim.set_meta("hit_ratios", PackedFloat32Array([0.5]))
		return

	var cutoff: float = peak_speed * SWING_SPEED_THRESHOLD
	var t0: float
	var t1: float
	if policy == Trim.SWING:
		t0 = _settle_time(samples, peak_time, -1, peak_speed)
		t1 = _settle_time(samples, peak_time, 1, peak_speed)
	elif policy == Trim.WHOLE:
		t0 = 0.0
		t1 = anim.length
	else:
		var first_time: float = peak_time
		var last_time: float = peak_time
		for s in samples:
			if s.y >= cutoff:
				first_time = minf(first_time, s.x)
				last_time = maxf(last_time, s.x)
		t0 = first_time - SPAN_LEAD_IN
		t1 = last_time + float(SPAN_LEAD_OUT_OVERRIDE.get(clip_name, SPAN_LEAD_OUT))
	t0 = clampf(t0, 0.0, anim.length)
	t1 = clampf(t1, t0 + 1.0 / RESAMPLE_FPS, anim.length)

	var window_length: float = maxf(t1 - t0, 1.0 / RESAMPLE_FPS)
	var hits := PackedFloat32Array()
	var lulls := PackedFloat32Array()
	if policy == Trim.SWING or policy == Trim.WHOLE:
		hits.append(clampf((peak_time - t0) / window_length, 0.0, 1.0))
	else:
		# Impacts can be held to a higher bar than the working stretch: on a blade the tip
		# is fast all through a flourish, and only the cuts themselves are near its peak.
		var hit_cutoff: float = peak_speed * float(_cfg.get("hit_threshold", SWING_SPEED_THRESHOLD))
		var hit_times: Array[float] = []
		for hit_time in _find_impact_times(samples, hit_cutoff, float(HIT_SEPARATION_OVERRIDE.get(clip_name, MIN_HIT_SEPARATION))):
			if hit_time >= t0 and hit_time <= t1:
				hit_times.append(hit_time)
				hits.append(clampf((hit_time - t0) / window_length, 0.0, 1.0))
		# Where each impact has played out before the next (_pause_after): the pause after a
		# cut, which is where a chain spent one cut per click should stop
		# (PlayerAnimator.combo_windows).
		for i in range(hit_times.size() - 1):
			lulls.append(clampf((_pause_after(samples, hit_times[i], hit_times[i + 1]) - t0) / window_length, 0.0, 1.0))
	if hits.is_empty():
		hits.append(0.5)

	anim.set_meta("trim_start", t0)
	anim.set_meta("trim_length", window_length)
	anim.set_meta("hit_ratios", hits)
	if not lulls.is_empty():
		anim.set_meta("lull_ratios", lulls)

	var hit_text := PackedStringArray()
	for h in hits:
		hit_text.append("%.0f%%" % (h * 100.0))
	var lull_text := PackedStringArray()
	for l in lulls:
		lull_text.append("%.0f%%" % (l * 100.0))
	print("  window %-13s full %.2fs, plays [%.2f..%.2f] = %.2fs, hits at %s%s" % [
		clip_name, anim.length, t0, t1, window_length, ", ".join(hit_text),
		"" if lull_text.is_empty() else ", pauses at " + ", ".join(lull_text)])


## Walks away from the impact frame in `direction` until the limb has slowed to
## SWING_SETTLED_FRACTION of its peak, so the clip is cut where the motion is calm
## rather than at an arbitrary offset. Clamped both ways: never closer to the impact
## than the MIN, never further than the MAX.
static func _settle_time(samples: Array[Vector3], peak_time: float, direction: int, peak_speed: float) -> float:
	var limit_min: float = SWING_PRE_IMPACT_MIN if direction < 0 else SWING_POST_IMPACT_MIN
	var limit_max: float = SWING_PRE_IMPACT_MAX if direction < 0 else SWING_POST_IMPACT_MAX
	var settled: float = peak_speed * SWING_SETTLED_FRACTION
	var best: float = peak_time + direction * limit_max
	var i := 0
	while i < samples.size():
		var idx: int = i if direction > 0 else samples.size() - 1 - i
		var sample: Vector3 = samples[idx]
		var offset: float = (sample.x - peak_time) * direction
		i += 1
		if offset < limit_min:
			continue
		if offset > limit_max:
			continue
		if sample.y <= settled:
			# First calm sample past the minimum in this direction - cut here.
			best = sample.x
			break
	return best


## A pause after a strike is a dip in the limb's speed below this share of the strike's own.
const PAUSE_FRACTION := 0.35


## Where the strike at `from` has played out before the one at `to` (seconds): the FIRST dip in
## the limb's speed after it that is well below the strike's (PAUSE_FRACTION) - the end of its
## follow-through. Not simply the slowest moment between the two: a blade also hangs still at
## the top of the next wind-up, which on the knight's leaping slam was the slowest point of all.
## Falls back to the slowest moment when the limb never dips that far.
static func _pause_after(samples: Array[Vector3], from: float, to: float) -> float:
	var strike_speed: float = 0.0
	var slowest_time: float = (from + to) * 0.5
	var slowest_speed: float = INF
	for i in range(1, samples.size() - 1):
		var s: Vector3 = samples[i]
		if is_equal_approx(s.x, from):
			strike_speed = s.y
		if s.x <= from or s.x >= to:
			continue
		if s.y < slowest_speed:
			slowest_speed = s.y
			slowest_time = s.x
		if s.y <= samples[i - 1].y and s.y <= samples[i + 1].y and s.y <= strike_speed * PAUSE_FRACTION:
			return s.x
	return slowest_time


## Local maxima of the limb-speed profile above `cutoff`, thinned so two samples of
## the same strike don't register as two hits.
static func _find_impact_times(samples: Array[Vector3], cutoff: float, separation: float = MIN_HIT_SEPARATION) -> Array[float]:
	var out: Array[float] = []
	var out_speeds: Array[float] = []
	for i in range(1, samples.size() - 1):
		var speed: float = samples[i].y
		if speed < cutoff:
			continue
		if speed < samples[i - 1].y or speed < samples[i + 1].y:
			continue
		if not out.is_empty() and samples[i].x - out[out.size() - 1] < separation:
			# Same strike - keep whichever peak is louder. It used to keep the later one
			# whatever its speed, which put the knight's first cut on the reposition after it.
			if speed > out_speeds[out_speeds.size() - 1]:
				out[out.size() - 1] = samples[i].x
				out_speeds[out_speeds.size() - 1] = speed
			continue
		out.append(samples[i].x)
		out_speeds.append(speed)
	return out


## Speed of `bone_name` in root space, sampled across the clip. Returns
## [Vector3(time, speed, height), ...]. Driving the real AnimationPlayer/Skeleton3D (rather
## than reading the raw track) is what makes this correct for a bone several joints
## down the chain, whose world motion comes mostly from its parents.
##
## `offset` follows a point fixed in the bone's frame instead of the bone itself - the tip of
## a blade held in that hand (_measure_blade_tip).
static func _sample_bone_speed(anim: Animation, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D, bone_name: String, offset: Vector3 = Vector3.ZERO) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return out

	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP := "__swing_measure__"
	temp_library.add_animation(TEMP_CLIP, anim)
	anim_player.add_animation_library("__swing__", temp_library)
	anim_player.play("__swing__/" + TEMP_CLIP)

	var step: float = 1.0 / RESAMPLE_FPS
	var previous := Vector3.ZERO
	var have_previous := false
	var t: float = 0.0
	while t <= anim.length:
		_apply_pose_at(anim_player, t)
		var pos: Vector3 = skeleton_to_root * _bone_global_pose(skeleton, bone_idx) * offset
		if have_previous:
			out.append(Vector3(t, pos.distance_to(previous) / step, pos.y))
		previous = pos
		have_previous = true
		t += step

	anim_player.stop()
	anim_player.remove_animation_library("__swing__")
	return out


# --- borrowed enemy clip ------------------------------------------------------

## Adapts a clip authored on the enemy rig (57 bones, ~0.02 units tall) onto this
## rig (33 bones, ~1.9 units). Rotation tracks carry over untouched - they're
## scale-free and match by bone name. Position tracks do NOT: they'd move this
## rig's joints to enemy-scale offsets and collapse it into a puddle. Only the
## hips track survives, rescaled by the height ratio between the two rigs; every
## other position track is dropped so those bones keep their own rest offsets.
## Tracks for the 24 bones this rig doesn't have are dropped as well.
static func _adopt_foreign_clip(source_fbx_path: String, skeleton: Skeleton3D, clip_name: String) -> Animation:
	var anim := _extract_animation(source_fbx_path)
	if anim == null:
		return null
	var source_skeleton := _skeleton_of(source_fbx_path)
	if source_skeleton == null:
		return null

	var ratio: float = _rig_height(skeleton) / maxf(_rig_height(source_skeleton), 0.00001)
	var dropped := 0
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(track_idx))
		var bone_name := path.get_slice(":", 1)
		if skeleton.find_bone(bone_name) == -1:
			anim.remove_track(track_idx)
			dropped += 1
			continue
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if bone_name != HIPS_BONE:
			anim.remove_track(track_idx)
			dropped += 1
			continue
		for key_idx in anim.track_get_key_count(track_idx):
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, value * ratio)

	_strip_horizontal_root_motion(anim, HIPS_BONE)
	print("  adopt %-13s rig ratio %.1fx, dropped %d incompatible tracks" % [clip_name, ratio, dropped])
	return anim


static func _skeleton_of(fbx_path: String) -> Skeleton3D:
	var scene: PackedScene = ResourceLoader.load(fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if scene == null:
		return null
	return scene.instantiate().find_child("Skeleton3D", true, false)


static func _rig_height(skeleton: Skeleton3D) -> float:
	var top := skeleton.find_bone(HEIGHT_TOP_BONE)
	var bottom := skeleton.find_bone(HEIGHT_BOTTOM_BONE)
	if top == -1 or bottom == -1:
		return 0.0
	return absf(_bone_global_rest(skeleton, top).origin.y - _bone_global_rest(skeleton, bottom).origin.y)


# --- grounding & scale --------------------------------------------------------

## Unlike every enemy in this project, this rig is authored at real-world scale, so
## this is a small trim (~1.0x) onto the player's 1.9-tall capsule rather than the
## 85-100x rescue the enemy meshes need. Measured from the skeleton's own rest pose,
## not the mesh AABB: this mesh's skin binds into a differently-scaled vertex space,
## so its ArrayMesh AABB reports a meaningless 0.004 units tall.
##
## Also yaws the visual 180 degrees - see FACING_CORRECTION_DEGREES.
static func _normalize_to_target_height(root: Node3D, skeleton: Skeleton3D) -> void:
	var height := _rig_height(skeleton)
	if height <= 0.0:
		push_error("Could not measure the player rig's height; leaving scale untouched")
		return
	var factor: float = TARGET_HEIGHT / height
	var basis := Basis(Vector3.UP, deg_to_rad(FACING_CORRECTION_DEGREES)).scaled(Vector3.ONE * factor)
	root.transform = Transform3D(basis, Vector3.ZERO)
	print("Player rig measured %.3f units tall; scaling %.4fx to %.2f, yawed %.0f degrees." % [height, factor, TARGET_HEIGHT, FACING_CORRECTION_DEGREES])


## Per-clip copy with the hips position track shifted vertically so the lowest
## ground-contact point actually touches y=0 - ported from tools/character_builder.gd,
## which documents why this is needed even for a rig's own clips.
static func _ground_correct_library(template_library: AnimationLibrary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var factor: float = root.transform.basis.get_scale().y
	var corrected := AnimationLibrary.new()

	for clip_name in template_library.get_animation_list():
		var anim: Animation = template_library.get_animation(clip_name).duplicate(true)
		# duplicate() drops metadata, so carry the build-time measurements across.
		var source_anim: Animation = template_library.get_animation(clip_name)
		for key in ["hit_ratios", "travel_speed", "trim_start", "trim_length", "root_forward"]:
			if source_anim.has_meta(key):
				anim.set_meta(key, source_anim.get_meta(key))
		var min_foot_y := _measure_min_foot_height(anim_player, skeleton, root, skeleton_to_root, anim)
		if is_finite(min_foot_y):
			_shift_hips_y(anim, HIPS_BONE, -min_foot_y / factor)
		else:
			push_warning("Could not measure foot height for clip '%s'; leaving ungrounded" % clip_name)
		if _cfg.get("align_gait", false) and anim.loop_mode == Animation.LOOP_LINEAR:
			var landing: float = _measure_left_landing(anim_player, skeleton, root, skeleton_to_root, anim)
			if landing >= 0.0:
				anim.set_meta("left_landing", landing)
				print("  gait   %-13s left foot lands at %.0f%% of the cycle" % [clip_name, landing * 100.0])
		corrected.add_animation(clip_name, anim)

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	return corrected


static func _measure_min_foot_height(anim_player: AnimationPlayer, skeleton: Skeleton3D, root: Node3D, skeleton_to_root: Transform3D, anim: Animation) -> float:
	var foot_indices: Array[int] = []
	for bone_name in FOOT_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			foot_indices.append(idx)
	if foot_indices.is_empty():
		return INF

	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP_NAME := "__ground_measure__"
	temp_library.add_animation(TEMP_CLIP_NAME, anim)
	anim_player.add_animation_library("__ground__", temp_library)
	anim_player.play("__ground__/" + TEMP_CLIP_NAME)

	var min_y := INF
	for i in range(GROUND_SAMPLE_COUNT + 1):
		var t: float = anim.length * float(i) / float(GROUND_SAMPLE_COUNT)
		_apply_pose_at(anim_player, t)
		for idx in foot_indices:
			var world_equiv: Transform3D = root.transform * skeleton_to_root * _bone_global_pose(skeleton, idx)
			min_y = minf(min_y, world_equiv.origin.y)

	anim_player.stop()
	anim_player.remove_animation_library("__ground__")
	return min_y


## Where in a looping clip the LEFT foot comes down, as a share of the cycle, or -1 if it never
## clearly lifts. PlayerAnimator starts every gait clip of a blend space there
## (`left_landing` -> AnimationNodeAnimation.start_offset), so blended clips plant the same
## foot together: the Great Sword pack's walks start anywhere in the stride, and blended
## forward-and-right the left foot only shuffled, never lifting or landing.
##
## Clearance is the lower of heel and toe above that foot's own lowest point in the clip; a
## landing is coming below LANDED having been above LIFTED (the footstep thresholds,
## GameSettings.player_footstep_plant_height / _lift_height).
const LEFT_FOOT_BONES := ["mixamorig_LeftFoot", "mixamorig_LeftToeBase"]
const LANDED := 0.01
const LIFTED := 0.025


static func _measure_left_landing(anim_player: AnimationPlayer, skeleton: Skeleton3D, root: Node3D, skeleton_to_root: Transform3D, anim: Animation) -> float:
	var bones: Array[int] = []
	for bone_name: String in LEFT_FOOT_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			return -1.0
		bones.append(idx)
	var temp_library := AnimationLibrary.new()
	temp_library.add_animation("gait", anim)
	anim_player.add_animation_library("__gait__", temp_library)
	anim_player.play("__gait__/gait")
	var heights: Array[float] = []
	var step: float = 1.0 / RESAMPLE_FPS
	var t: float = 0.0
	while t < anim.length:
		_apply_pose_at(anim_player, t)
		var low: float = INF
		for idx in bones:
			low = minf(low, (root.transform * skeleton_to_root * _bone_global_pose(skeleton, idx)).origin.y)
		heights.append(low)
		t += step
	anim_player.stop()
	anim_player.remove_animation_library("__gait__")
	if heights.size() < 4:
		return -1.0
	var floor_y: float = heights.min()
	# Twice round, so a landing just after the loop point is found from a lift just before it.
	var lifted: bool = false
	for i in heights.size() * 2:
		var clearance: float = heights[i % heights.size()] - floor_y
		if clearance > LIFTED:
			lifted = true
		elif lifted and clearance <= LANDED:
			return float(i % heights.size()) * step / anim.length
	return -1.0


static func _shift_hips_y(anim: Animation, bone_name: String, delta_y: float) -> void:
	var track_idx := _find_position_track(anim, bone_name)
	if track_idx == -1:
		return
	for key_idx in anim.track_get_key_count(track_idx):
		var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
		anim.track_set_key_value(track_idx, key_idx, value + Vector3(0.0, delta_y, 0.0))


# --- props --------------------------------------------------------------------

## Hangs one prop of a class's (see ARCHER_PROPS) on `spec.bone`.
##
## The placement is written as the prop looks on the REST pose, in the rig's own model
## space, rather than in the bone's local axes: "the bow runs up the thumb" is something a
## person can read and correct, a quaternion in a Mixamo hand bone's frame is not. The
## bone's rest is then divided back out, so the BoneAttachment3D carries the prop through
## every clip from there.
##
## The prop's size is in metres; dividing by the armature's world scale is what keeps it
## that size on a rig that imports 204x too small.
static func _attach_prop(skeleton: Skeleton3D, spec: Dictionary) -> void:
	var bone_name: String = spec["bone"]
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		push_error("Prop '%s': no bone %s" % [spec["name"], bone_name])
		return
	var scene: PackedScene = ResourceLoader.load(String(spec["glb"]), "", ResourceLoader.CACHE_MODE_REPLACE)
	if scene == null:
		push_error("Prop '%s': could not load %s" % [spec["name"], spec["glb"]])
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sAttachment" % spec["name"]
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)

	var prop: Node3D = scene.instantiate()
	prop.name = String(spec["name"])
	var armature_scale: float = _get_node_global_scale(skeleton).y
	if spec.has("fit") and String(spec["fit"].get("kind", "")) in ["two_hand", "one_hand", "shield"]:
		_place_prop(prop, _fit_in_pose(skeleton, bone_idx, spec, armature_scale))
	elif spec.has("fit"):
		_place_prop(prop, _fit_bow(skeleton, bone_idx, spec, armature_scale))
	else:
		var axes: Array = spec["basis"]
		var basis := Basis(axes[0], axes[1], axes[2]).scaled(Vector3.ONE * float(spec["scale"]) / armature_scale)
		var rest: Transform3D = _bone_global_rest(skeleton, bone_idx)
		var wanted := Transform3D(basis, rest.origin + (spec["offset"] as Vector3) / armature_scale)
		_place_prop(prop, rest.affine_inverse() * wanted)
	attachment.add_child(prop)


## Sets a prop where the builder fitted it (`fitted`, in its bone's frame) plus any hand
## adjustment from PROP_FIT_PATH, and records both on the node: `fitted` is what a later
## nudge is measured from, `placed` is how a scene the editor has touched is told from one
## it has not (capture_prop_fits).
static func _place_prop(prop: Node3D, fitted: Transform3D) -> void:
	prop.transform = fitted * _prop_fit("%s/%s" % [_class_id, prop.name])
	prop.set_meta("fitted", fitted)
	prop.set_meta("placed", prop.transform)


## The hand adjustment for prop `key` ("<class>/<prop node>"), as a transform in the prop's
## own frame - so it reads as "and then turn and shift it a little", and stays with the prop
## if the fit underneath it changes. Rotation as a quaternion, which survives the trip through
## the file exactly (euler did not, for the enemies' weapons); `origin` in the prop model's own
## units; `scale` multiplies the size the config gives. Identity when there is none.
static func _prop_fit(key: String) -> Transform3D:
	var entry: Variant = _read_prop_fits().get(key, {})
	if not (entry is Dictionary):
		return Transform3D.IDENTITY
	var basis := Basis.IDENTITY
	if entry.has("rotation_quat"):
		var q: Array = entry["rotation_quat"]
		basis = Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized())
	if entry.has("scale"):
		basis = basis.scaled(Vector3.ONE * float(entry["scale"]))
	var origin := Vector3.ZERO
	if entry.has("origin"):
		var o: Array = entry["origin"]
		origin = Vector3(float(o[0]), float(o[1]), float(o[2]))
	return Transform3D(basis, origin)


## Reads back every prop of `class_id` that has been moved in its visual scene since that
## scene was built, and writes its nudge to PROP_FIT_PATH. A prop still where the build left
## it is skipped, so an entry edited or deleted in the file by hand is not overwritten by an
## untouched scene. Safe to run any number of times: the nudge is measured from the fitted
## placement the scene records, never from the last capture, so it does not compound.
static func capture_prop_fits(class_id: String) -> void:
	var scene_path: String = CONFIGS[class_id]["scene"]
	if not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var names: Array[String] = []
	for spec: Dictionary in CONFIGS[class_id]["props"]:
		names.append(String(spec["name"]))
	var fits: Dictionary = _read_prop_fits()
	var changed: bool = false
	for prop_name: String in names:
		var prop: Node3D = root.find_child(prop_name, true, false) as Node3D
		if prop == null or not prop.has_meta("fitted") or not prop.has_meta("placed"):
			continue
		if _nudge_entry((prop.get_meta("placed") as Transform3D).affine_inverse() * prop.transform).is_empty():
			continue
		var key: String = "%s/%s" % [class_id, prop_name]
		var entry: Dictionary = _nudge_entry((prop.get_meta("fitted") as Transform3D).affine_inverse() * prop.transform)
		if entry.is_empty():
			fits.erase(key)
		else:
			fits[key] = entry
		print("  %s: moved by hand in %s, captured to %s" % [key, scene_path.get_file(), PROP_FIT_PATH.get_file()])
		changed = true
	root.free()
	if changed:
		var file := FileAccess.open(PROP_FIT_PATH, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write %s" % PROP_FIT_PATH)
			return
		file.store_string(JSON.stringify(fits, "\t") + "\n")
		file.close()


## A transform in the prop's own frame as a PROP_FIT_PATH entry, leaving out what is too small
## to be anything but rounding (a twentieth of a degree, a tenth of a millimetre on a metre-long
## model). Empty when nothing is left.
static func _nudge_entry(nudge: Transform3D) -> Dictionary:
	var entry: Dictionary = {}
	var stretch: Vector3 = nudge.basis.get_scale()
	var size: float = (stretch.x + stretch.y + stretch.z) / 3.0
	if maxf(absf(stretch.x - size), maxf(absf(stretch.y - size), absf(stretch.z - size))) > 0.01 * size:
		push_warning("A prop was stretched unevenly in the editor; kept as an even %.3fx" % size)
	var turn: Quaternion = nudge.basis.orthonormalized().get_rotation_quaternion().normalized()
	if rad_to_deg(2.0 * acos(clampf(absf(turn.w), 0.0, 1.0))) > 0.05:
		entry["rotation_quat"] = [turn.x, turn.y, turn.z, turn.w]
	if nudge.origin.length() > 0.0001:
		entry["origin"] = [nudge.origin.x, nudge.origin.y, nudge.origin.z]
	if absf(size - 1.0) > 0.0001:
		entry["scale"] = size
	return entry


static func _read_prop_fits() -> Dictionary:
	if not FileAccess.file_exists(PROP_FIT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROP_FIT_PATH))
	if not (parsed is Dictionary):
		push_warning("%s is not readable JSON; prop adjustments ignored" % PROP_FIT_PATH)
		return {}
	return parsed


## Places a bow from the pose it is drawn in rather than from the rest: at `fit.at` seconds
## into `fit.clip`, with the skeleton posed there, the bow stands upright, its string side
## points at the drawing hand and its grip sits in the closed fist. The result is expressed in the
## hand bone's frame AT THAT POSE, which is what makes it exact there - and since the bow is
## rigid in the hand, right wherever else the pack's clips carry the hand.
##
## Written this way because the hand's rest frame is no guide to how the Mixamo longbow pack
## holds a bow: a rest-pose guess came out lying across the face at full draw.
static func _fit_bow(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float) -> Transform3D:
	var fit: Dictionary = spec["fit"]
	var anim_player: AnimationPlayer = skeleton.get_parent().find_child("AnimationPlayer", true, false)
	var mode := anim_player.callback_mode_process
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_player.play(String(fit["clip"]))
	_apply_pose_at(anim_player, float(fit["at"]))
	var hand: Transform3D = _bone_global_pose(skeleton, bone_idx)
	var draw_hand: Vector3 = _bone_global_pose(skeleton, skeleton.find_bone(String(fit["draw_hand"]))).origin
	# The grip goes where the curled fingers close: the centre of the circle through the
	# knuckle, the middle joint and the fingertip. (The middle-of-the-hand guess this replaced
	# put it over the back of the hand: the elf's middle-finger joints sit out at the
	# fingertips.) The bow still stands upright there - turned onto the circle's own axis it
	# lay across the face at rest.
	var arc: Array[Vector3] = []
	for bone_name: String in fit["fist_chain"]:
		arc.append(_bone_global_pose(skeleton, skeleton.find_bone(bone_name)).origin)
	anim_player.stop()
	anim_player.callback_mode_process = mode

	var ab: Vector3 = arc[1] - arc[0]
	var ac: Vector3 = arc[2] - arc[0]
	var normal: Vector3 = ab.cross(ac)
	var fist: Vector3 = arc[0] + (normal.cross(ab) * ac.length_squared() + ac.cross(normal) * ab.length_squared()) / (2.0 * normal.length_squared())
	var string_side: Vector3 = (draw_hand - fist).normalized()
	var length_axis: Vector3 = (Vector3.UP - string_side * Vector3.UP.dot(string_side)).normalized()
	var basis := Basis(length_axis, string_side, length_axis.cross(string_side)).scaled(Vector3.ONE * float(spec["scale"]) / armature_scale)
	var wanted := Transform3D(basis, fist - basis * (fit["grip"] as Vector3))
	print("  prop %-8s fitted at %s@%.2f, draw hand %.2fm from the fist, fist %.1f cm across" % [
		spec["name"], fit["clip"], fit["at"], fist.distance_to(draw_hand) * armature_scale,
		2.0 * fist.distance_to(arc[0]) * armature_scale * 100.0])
	return hand.affine_inverse() * wanted


## Places a two-handed weapon from the pose it is held in, the way _fit_bow() places the bow: at
## `fit.at` seconds into `fit.clip` the grip runs from the lower fist up through the upper one
## and on into the blade, the edge faces the way the upper hand's knuckles point, and the
## glb's `grip` point sits in the upper fist. Stored in the upper hand's frame at that pose, so
## the sword is exact there and rigid in that hand everywhere else - the lower hand comes and
## goes from the grip as the pack's clips let go with it.
##
## The glb lies blade along +Y, edges along +X (prepare_sword.py), which is what the basis
## below maps onto.
static func _fit_in_pose(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float) -> Transform3D:
	var fit: Dictionary = spec["fit"]
	var anim_player: AnimationPlayer = skeleton.get_parent().find_child("AnimationPlayer", true, false)
	var mode := anim_player.callback_mode_process
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_player.play(String(fit["clip"]))
	_apply_pose_at(anim_player, float(fit["at"]))
	var placed: Transform3D = _prop_in_pose(skeleton, bone_idx, spec, armature_scale, true)
	anim_player.stop()
	anim_player.callback_mode_process = mode
	return placed


## Where a prop fitted from a pose goes, on whatever pose the skeleton is in now, in the frame
## of bone `bone_idx` - by the fit's kind.
static func _prop_in_pose(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float, report: bool) -> Transform3D:
	match String(spec["fit"].get("kind", "")):
		"one_hand":
			return _one_hand_in_pose(skeleton, bone_idx, spec, armature_scale, report)
		"shield":
			return _shield_in_pose(skeleton, bone_idx, spec, armature_scale, report)
	return _two_hand_in_pose(skeleton, bone_idx, spec, armature_scale, report)


## The circle the curled finger of `chain` (knuckle, middle joint, tip) runs round, on the
## current pose: [its centre - where a held grip runs through the fist - and its axis].
static func _fist_circle(skeleton: Skeleton3D, chain: Array) -> Array:
	var points: Array[Vector3] = []
	for bone_name: String in chain:
		points.append(_bone_global_pose(skeleton, skeleton.find_bone(bone_name)).origin)
	var ab: Vector3 = points[1] - points[0]
	var ac: Vector3 = points[2] - points[0]
	var normal: Vector3 = ab.cross(ac)
	var centre: Vector3 = points[0] + (normal.cross(ab) * ac.length_squared() + ac.cross(normal) * ab.length_squared()) / (2.0 * normal.length_squared())
	return [centre, normal.normalized(), points[0]]


## A one-handed blade in the fist: its grip (the glb's origin) at the centre of the curled
## fingers, the blade along the fist's axis out of the THUMB side, and the edge leading the way
## the knuckles point.
static func _one_hand_in_pose(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float, report: bool) -> Transform3D:
	var hand: Transform3D = _bone_global_pose(skeleton, bone_idx)
	var circle: Array = _fist_circle(skeleton, spec["fit"]["fist_chain"])
	var centre: Vector3 = circle[0]
	var blade: Vector3 = circle[1]
	var knuckle: Vector3 = circle[2] - hand.origin
	var fingers: Vector3 = hand.basis.y.normalized()
	var off_axis: Vector3 = knuckle - fingers * knuckle.dot(fingers)
	# Measured, not reasoned: on these imported Mixamo hands the index knuckle sits off the
	# hand bone's axis towards the LITTLE-finger side of the fist, so the blade goes the other
	# way. Rendered to check - the pommel had come out over the thumb.
	if blade.dot(off_axis) > 0.0:
		blade = -blade
	var edge: Vector3 = (knuckle - blade * knuckle.dot(blade)).normalized()
	var basis := Basis(edge, blade, edge.cross(blade)).scaled(Vector3.ONE * float(spec["scale"]) / armature_scale)
	if report:
		print("  prop %-10s fitted at %s@%.2f in a fist %.1f cm across" % [spec["name"], spec["fit"]["clip"], spec["fit"]["at"],
			2.0 * centre.distance_to(circle[2]) * armature_scale * 100.0])
	return hand.affine_inverse() * Transform3D(basis, centre)


## A shield in the fist: its handle (the glb's origin) at the centre of the curled fingers, and
## in the guard pose it is fitted at standing upright and facing the way the body does - the
## hips' own forward there, so a guard that turns the body turns the shield with it.
static func _shield_in_pose(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float, report: bool) -> Transform3D:
	var hand: Transform3D = _bone_global_pose(skeleton, bone_idx)
	var circle: Array = _fist_circle(skeleton, spec["fit"]["fist_chain"])
	var right: Vector3 = _bone_global_pose(skeleton, skeleton.find_bone("mixamorig_RightUpLeg")).origin \
		- _bone_global_pose(skeleton, skeleton.find_bone("mixamorig_LeftUpLeg")).origin
	right = (right - Vector3.UP * right.dot(Vector3.UP)).normalized()
	var forward: Vector3 = Vector3.UP.cross(right).normalized()
	var basis := Basis(Vector3.UP.cross(forward), Vector3.UP, forward).scaled(Vector3.ONE * float(spec["scale"]) / armature_scale)
	if report:
		print("  prop %-10s fitted at %s@%.2f, facing the hips' forward" % [spec["name"], spec["fit"]["clip"], spec["fit"]["at"]])
	return hand.affine_inverse() * Transform3D(basis, circle[0])


## _fit_in_pose()'s placement, on whatever pose the skeleton is in now, in the frame of bone
## `bone_idx` (the upper hand).
static func _two_hand_in_pose(skeleton: Skeleton3D, bone_idx: int, spec: Dictionary, armature_scale: float, report: bool) -> Transform3D:
	var fit: Dictionary = spec["fit"]
	var hand: Transform3D = _bone_global_pose(skeleton, bone_idx)
	var upper_knuckle: Vector3 = _bone_global_pose(skeleton, skeleton.find_bone(String(fit["upper_knuckle"]))).origin
	var upper: Vector3 = (_bone_global_pose(skeleton, skeleton.find_bone(String(fit["upper"]))).origin + upper_knuckle) * 0.5
	var lower: Vector3 = (_bone_global_pose(skeleton, skeleton.find_bone(String(fit["lower"]))).origin
		+ _bone_global_pose(skeleton, skeleton.find_bone(String(fit["lower_knuckle"]))).origin) * 0.5
	var blade: Vector3 = (upper - lower).normalized()
	var knuckles: Vector3 = upper_knuckle - hand.origin
	var edge: Vector3 = (knuckles - blade * knuckles.dot(blade)).normalized()
	var basis := Basis(edge, blade, edge.cross(blade)).scaled(Vector3.ONE * float(spec["scale"]) / armature_scale)
	var wanted := Transform3D(basis, upper - basis * (fit["grip"] as Vector3))
	if report:
		print("  prop %-10s fitted at %s@%.2f, fists %.2fm apart" % [
			spec["name"], fit["clip"], fit["at"], upper.distance_to(lower) * armature_scale])
	return hand.affine_inverse() * wanted


## Where the blade's tip is in the weapon hand's own frame - the point _measure_action_window
## follows instead of the hand. Fitted exactly as the prop will be (_fit_two_hand), on the
## freshly extracted clips, since the library is not built yet. `blade.tip` is metres from the
## grip along the blade; a little short of the very end, where the cut actually lands.
static func _measure_blade_tip(skeleton: Skeleton3D, anim_player: AnimationPlayer, extracted: Dictionary) -> Vector3:
	var blade: Dictionary = _cfg["blade"]
	var spec: Dictionary = {}
	for prop: Dictionary in _cfg.get("props", []):
		if String(prop["name"]) == String(blade["prop"]):
			spec = prop
	var fit: Dictionary = spec.get("fit", {})
	if fit.is_empty() or not extracted.has(String(fit["clip"])):
		push_warning("No fitted prop '%s' to measure a blade on; swings are measured at the hand" % blade["prop"])
		return Vector3.ZERO
	var temp_library := AnimationLibrary.new()
	temp_library.add_animation("fit", extracted[String(fit["clip"])])
	anim_player.add_animation_library("__blade__", temp_library)
	anim_player.play("__blade__/fit")
	_apply_pose_at(anim_player, float(fit["at"]))
	var bone_idx: int = skeleton.find_bone(String(spec["bone"]))
	var armature_scale: float = _get_node_global_scale(skeleton).y
	var placed: Transform3D = _prop_in_pose(skeleton, bone_idx, spec, armature_scale, false)
	anim_player.stop()
	anim_player.remove_animation_library("__blade__")
	# With any hand adjustment on top, as _place_prop will put it.
	return placed * _prop_fit("%s/%s" % [_class_id, spec["name"]]) * Vector3(0.0, float(blade["tip"]), 0.0)


## The PBR maps come from a SECOND Meshy export (TEXTURE_BASE, 0830103939) than the
## rigged mesh (MESH_FBX, 0829200310) - the rigged one carries texture *references*
## with no image data at all, so on its own the body renders flat grey.
##
## Mixing the two is safe, and that was verified rather than assumed: both exports
## are the same 24014-vertex mesh with the same 20750 triangles, and once the
## differing vertex ORDER is corresponded triangle-by-triangle, all 62250 UV corners
## are identical to the last decimal. Only the vertex ordering was shuffled by the
## re-export, and ordering is exactly what a texture lookup does not care about.
##
## The emission map is deliberately skipped: sampled across the image its maximum is
## 0.027, i.e. black, so wiring it in would cost 4MB of VRAM to add nothing.
static func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0
	mat.roughness = 1.0

	var albedo := _optional_texture(".png")
	if albedo == null:
		push_warning("No albedo for %s - the player will render untextured." % String(_cfg["mesh"]))
	else:
		mat.albedo_texture = albedo
	# A config can leave the normal map out: Meshy bakes it against the model's own normals, and
	# on a model exported faceted and smoothed here (smooth_normals) that map puts creases back
	# along its UV islands - the mage's face had them across the forehead and cheek.
	var normal := _optional_texture("_normal.png") if _cfg.get("normal_map", true) else null
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	# Both maps are greyscale, so any channel would do; red matches how the enemy
	# materials in scenes/melee/*.tscn read theirs.
	var metallic := _optional_texture("_metallic.png")
	if metallic != null:
		mat.metallic = 1.0
		mat.metallic_texture = metallic
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var roughness := _optional_texture("_roughness.png")
	if roughness != null:
		mat.roughness_texture = roughness
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat


## Gives the body smooth normals in place of the faceted ones Meshy shipped it with
## (tools/normal_smoother.gd says how). Public, because tools/fix_player_chins.gd has to put
## the same mesh beside the saved one before it can copy weights across vertex for vertex.
static func smooth_normals(mesh_node: MeshInstance3D) -> void:
	var mesh := mesh_node.mesh as ArrayMesh
	var before: float = NormalSmoother.split_share(mesh)
	mesh_node.mesh = NormalSmoother.smooth(mesh)
	print("  smooth normals: split at %.0f%% of positions -> %.0f%%" % [before * 100.0, NormalSmoother.split_share(mesh_node.mesh as ArrayMesh) * 100.0])


static func _optional_texture(suffix: String) -> Texture2D:
	if not _cfg.has("texture_base"):
		return null
	var path := String(_cfg["texture_base"]) + suffix
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


# --- shared helpers -----------------------------------------------------------

static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			chain.append(current as Node3D)
		current = current.get_parent()
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for n in chain:
		accum = accum * n.transform
	return accum


## Steps the mixer to `time` and applies it. `seek(time, true)` alone leaves the
## mixer's own accumulator untouched in manual callback mode; the advance(0) is
## what actually writes the sampled values onto the skeleton's bone poses.
static func _apply_pose_at(anim_player: AnimationPlayer, time: float) -> void:
	anim_player.seek(time, true)
	anim_player.advance(0.0)


## Composes a bone's global pose from the local poses the mixer just wrote.
##
## Skeleton3D.get_bone_global_pose() must NOT be used here: it reads a cache that
## is only recomputed when the skeleton processes a frame, and a build-time script
## driving the mixer by hand never gives it one - so it keeps returning the REST
## pose no matter where the clip is seeked to. Confirmed directly: local poses from
## get_bone_pose() varied across a swing while get_bone_global_pose() returned one
## constant rest value for every sample.
static func _bone_global_pose(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_pose(b)
	return accum


static func _bone_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_rest(b)
	return accum


static func _get_node_global_scale(node: Node3D) -> Vector3:
	var node_scale := Vector3.ONE
	var current: Node = node
	while current is Node3D:
		node_scale *= (current as Node3D).transform.basis.get_scale()
		current = current.get_parent()
	return node_scale


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
			return node as MeshInstance3D
		for child in node.get_children():
			stack.append(child)
	return null


static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_recursive(child, owner)
