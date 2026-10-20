class_name PlayerAnimator
extends Node3D
## Owns the player's animated visual and decides which clip is playing.
##
## `Player` tells this node what happened ("swing this attack", "you were hit from
## the left", "you're moving at 4.2 units/s while sprinting") and this node resolves
## that into clips, playback speeds and blends. Keeping the choice here rather than
## in player.gd means the combat code never has to reason about which clip outranks
## which.
##
## Runs on an AnimationTree built in code (see _build_tree) rather than on bare
## AnimationPlayer.play() calls, because a light attack has to play on the UPPER BODY
## ONLY while the legs keep walking - two clips at once on one skeleton, which a
## single AnimationPlayer cannot do. The graph is:
##
##   loco_<clip> ─┐
##   loco_<clip> ─┼─ loco (Transition) ── loco_speed (TimeScale) ──┐
##   loco_<clip> ─┘                                                ├─ shot (OneShot) ── out
##   action (Animation) ── action_speed (TimeScale) ───────────────┘
##
## `shot` carries a bone filter covering everything from the spine up. With the
## filter on, the fired clip drives only those bones and the legs keep whatever
## `loco` is playing; with it off, the fired clip takes the whole body. That switch
## is exactly the difference between a light attack (swing while walking) and a
## heavy attack or kick (a committed move that also roots the player - see
## Player._begin_action).
##
## Clip metadata comes from tools/player_character_builder.gd:
##   travel_speed  how fast a locomotion clip's own root motion moved the character
##   hit_ratios    normalized moments of impact within an attack clip
##
## A multi-hit clip can also be played one STAGE at a time rather than whole: see
## combo_windows(), which is what turns a single stored flourish into the player's
## click-by-click light attack chain.
##
## The scale, ground offset and 180-degree facing correction of the visual are baked
## into the class's visual scene (scenes/characters/<class>/visual.tscn), so this node sits at the
## CharacterBody3D's own origin with no correction of its own.
##
## Which visual is the player's CLASS (ClassDatabase), read off the "character_class"
## metadata the spawn put on the Player before it entered the tree - this node is ready
## before its parent is. Every class's library uses the same logical clip names, so nothing
## below needs to know which one is playing; a clip a class lacks (the archer has no block)
## simply leaves its layer unbuilt.

## The whole strike window of a clip, as the [start, end] ratio pair every action
## call takes. Anything narrower is one stage of a chain (see combo_windows).
const FULL_WINDOW := Vector2(0.0, 1.0)

const IDLE_CLIP := "idle"
const BLOCK_CLIP := "block_idle"
const JUMP_CLIP := "jump"
## The running take-off, the landing from a jump while moving, and from one standing still -
## each optional: a class whose packs have none plays the jump clip's own landing.
const JUMP_RUN_CLIP := "jump_run"
const LAND_CLIP := "land"
const LAND_RUN_CLIP := "land_run"
const DEATH_CLIP := "death"
const IDLE_VARIATIONS := ["idle_look_1", "idle_look_2"]

## Travel cycles, used only when sprinting with no fight in progress. The armed run
## reads badly at speed - the weapon pins the arms and the whole stride goes stiff -
## so covering ground borrows the unarmed cycles instead. Anything a fight touches
## stays on the armed set.
const RUN_FORWARD_TRAVEL := "run_forward_unarmed"
const RUN_BACK_TRAVEL := "run_back_unarmed"

## The non-directional states the locomotion layer can cross-fade into. `reset` restarts
## the clip on entry: wanted for the one-shot-ish ones, unwanted for the loops.
##
## Travel is NOT here. The four walk clips and the two run clips are blended rather than
## chosen, so they live inside the two BlendSpace2Ds below instead of being transition
## inputs of their own - see GAIT_SPACES.
const STATE_CLIPS := {
	"idle": false,
	"block_idle": false,
	"idle_look_1": true,
	"idle_look_2": true,
	"jump": true,
	"jump_run": true,
	"land": true,
	"land_run": true,
	"death": true,
}
## STATE_CLIPS a class may well not have.
const OPTIONAL_STATES := ["block_idle", "jump_run", "land", "land_run"]

const WALK_SPACE := "walk_space"
const RUN_SPACE := "run_space"

## The two gaits, each a BlendSpace2D over [forward, back, left, right].
##
## Replaces picking ONE cardinal clip per frame, which had no diagonal at all and flickered
## on every one. `_pick_locomotion_clip` decided with `absf(local.z) >= absf(local.x)`, and on
## a keyboard diagonal those two are exactly equal - the input is (0.7071, -0.7071) - so the
## comparison resolved on whatever floating-point noise `move_and_slide` had left in the
## velocity, differently most frames. Each flip restarted the transition's 0.16s cross-fade,
## so the character sat in a cross-fade that never finished. Mouse-turning made it permanent
## rather than causing it: movement is body-relative, so turning keeps the local direction
## pinned at exactly 45 degrees and there is no way to rotate off the boundary.
##
## The run row reuses the two WALK strafe clips because the pack ships no sideways run. A
## diagonal sprint therefore blends a real run with a sped-up walk, which is the same
## compromise the old picker made - it just no longer has to choose between them.
const GAIT_SPACES := {
	WALK_SPACE: {
		"forward": "walk_forward", "back": "walk_back",
		"left": "walk_left", "right": "walk_right",
	},
	RUN_SPACE: {
		"forward": "run_forward_unarmed", "back": "run_back_unarmed",
		"left": "walk_left", "right": "walk_right",
	},
}

## Everything from the spine up. The complement of this - hips and both leg chains -
## stays with the locomotion layer during a filtered action, which is what lets the
## legs keep walking through a swing. Hips in particular MUST stay with locomotion:
## it carries the vertical bob and the builder's per-clip ground correction.
const LOWER_BODY_BONES := [
	"mixamorig_Hips",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot",
	"mixamorig_LeftToeBase", "mixamorig_LeftToe_End",
	"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot",
	"mixamorig_RightToeBase", "mixamorig_RightToe_End",
]

const LOCO_NODE := "loco"
const LOCO_SPEED_NODE := "loco_speed"
const ACTION_NODE := "action"
const ACTION_SPEED_NODE := "action_speed"
const SHOT_NODE := "shot"
## The guard, as a layer of its own between locomotion and the action one-shot.
const GUARD_NODE := "guard"
const GUARD_POSE_NODE := "guard_pose"

const PARAM_WALK_POINT := "parameters/%s/blend_position" % WALK_SPACE
const PARAM_RUN_POINT := "parameters/%s/blend_position" % RUN_SPACE

const PARAM_LOCO_REQUEST := "parameters/%s/transition_request" % LOCO_NODE
const PARAM_LOCO_SPEED := "parameters/%s/scale" % LOCO_SPEED_NODE
const PARAM_ACTION_SPEED := "parameters/%s/scale" % ACTION_SPEED_NODE
const PARAM_SHOT_REQUEST := "parameters/%s/request" % SHOT_NODE
const PARAM_GUARD_AMOUNT := "parameters/%s/blend_amount" % GUARD_NODE

## Clips that carry straight on from another one's last frame - the archer's draw ends on
## the anchor `aim` starts from, and `shoot` lets go from either. Fired after one of those,
## they cut in with no fade: a fade would blend in from the RESTING pose, and the arms
## dipped to the hips and back up between the draw and the hold.
const CONTINUES_FROM := {
	"aim": ["draw"],
	"shoot": ["draw", "aim"],
}

## How long, real seconds, a clip that another one carries on from (any clip listed in
## CONTINUES_FROM) holds its last frame past its end. The one-shot starts fading back to the
## locomotion layer once less than its fade time is left - on the archer's 0.42 s draw, that
## was the last 0.12 s of it sliding towards the resting pose before `aim` snapped the arms
## back up to the anchor. With the hold the clip that follows takes over first.
const CONTINUED_CLIP_HOLD := 0.3

## The barbarian's Whirlwind plays a POSE - the sword held out level across the body - and
## this node turns the whole figure round under it, GameSettings.barbarian_whirlwind_turns
## times over the action. Driven off the shot, so every screen that plays the cast spins it.
const WHIRLWIND_CLIP := "whirlwind"

## The rate the builder samples `root_forward` at (PlayerCharacterBuilder.RESAMPLE_FPS).
const ROOT_MOTION_FPS := 30.0
## A clip fired again while it is still playing, from (within this many clip-seconds of) where
## it already is, carries straight on: the barbarian's chain spending its next cut from the
## playhead. A fade there would blend in from the resting pose and dip mid-swing.
const SELF_CONTINUE_TOLERANCE := 0.12

## The stretch of `draw`, seconds of clip, over which BowAim turns in: from the hands meeting
## at the bow with the arrow (before that the hand is in the quiver, and the line from it to
## the grip points anywhere) to the anchor at the cheek. Measured on the Pro Longbow clip.
const BOW_AIM_DRAW_FROM := 0.55
const BOW_AIM_DRAW_FULL := 0.95

## How long the arms take to come up into the guard and back down. Short, because this
## follows a button being held rather than an animation being played - anything slower
## reads as the character being late to raise their shield.
const GUARD_BLEND_SECONDS := 0.12

## Below this planar speed the player counts as standing still.
const MOVING_SPEED_EPSILON := 0.15
## The jump's phases (begin_jump): rising faster than this with no jump of this machine's is
## somebody else's take-off; off the ground longer than FALL_GRACE without one is a fall.
const FALL_START_SPEED := 0.8
const FALL_GRACE := 0.15
## Seconds after the take-off before touching the ground counts as landing - the first
## physics frames still report the floor.
const LANDING_MIN_AIR := 0.08
## How far short of the touchdown frame a fall that outlasts the clip holds, seconds of clip.
const TOUCHDOWN_HOLD := 0.05
## A running landing hands over to the gait this far through, where it is already running.
const LAND_RUN_HANDOFF := 0.6
## The fastest the jump clip is ever run, clip-seconds per second - only reached catching up a
## playhead that started mid-arc (a teammate's jump, first seen in the air).
const MAX_JUMP_RATE := 60.0

## A foot touched down, at `at`: the world-space point on the ground under its ankle.
##
## Read off the pose actually being shown rather than scheduled from clip timings. The legs
## are a blend of up to two clips at a speed fitted to the ground being covered, and the
## clips in a blend space each keep their own clock, so no table of "step at 25%" survives
## contact with what is on screen. The bones always agree with the eye.
signal footfall(at: Vector3)

## [ankle, toe] for each foot. The heel is not a bone of its own; see _heel_height.
const FOOT_BONES := [
	["mixamorig_LeftFoot", "mixamorig_LeftToeBase"],
	["mixamorig_RightFoot", "mixamorig_RightToeBase"],
]

var _anim: AnimationPlayer
var _visual: Node3D
var _hand_orb: MageHandOrb = null
## GAIT_SPACES as this class plays them - see _class_gait_spaces.
var _gait_spaces: Dictionary = GAIT_SPACES
## The action layer's playhead, in seconds of stored clip, and the clip it is in. Kept
## alongside the tree because the tree does not say where a one-shot has got to, and the
## archer's bowstring has to know whether the hand is on it (BowRig).
var _shot_clip: String = ""
var _shot_position: float = 0.0
var _shot_speed: float = 0.0
var _shot_end: float = 0.0
var _shot_start: float = 0.0
var _skeleton: Skeleton3D
## The archer's spine turning the arrow onto the crosshair (BowAim). Null for a class
## with no bow.
var _bow_aim: BowAim
var _tree: AnimationTree
var _action_anim: AnimationNodeAnimation
var _shot: AnimationNodeOneShot
## False when the library has no block clip to hold, in which case the layer is not
## built at all and everything below is inert.
var _has_guard: bool = false
## Where the guard blend currently sits, 0 to 1. Held here rather than read back off the
## tree because it is driven towards a target every frame.
var _guard_amount: float = 0.0
## The class's walks already hold the guard up (ClassDatabase.walk_guards): blocking on the
## move plays them whole, with no guard layer over the arms.
var _walk_guards: bool = false

## Only used to keep an idle variation from starting under a swing; gameplay's own
## commitment timers live in Player.
var _action_timer: float = 0.0
var _is_dead: bool = false

var _idle_timer: float = 0.0
var _next_idle_variation: float = 0.0
var _idle_variation_timer: float = 0.0

var _current_loco: String = ""
## The blend point actually in use, eased toward the target every frame. Smoothed because the
## velocity this is derived from carries floor-snap and wall-slide noise out of move_and_slide,
## and because a strafe turning into a forward run should read as a weight shift rather than a
## snap. Short enough (see GameSettings.player_anim_blend_point_smoothing) that it never lags
## behind the input in a way a player can feel.
var _blend_point: Vector2 = Vector2(0.0, 1.0)
## Which gait is current, kept so the walk/run switch can be hysteretic - a speed sitting on
## the threshold would otherwise chatter between two spaces the way the old picker chattered
## between two clips.
var _running: bool = false
## The jump in flight (begin_jump): which phase, which clip, how far into it the locomotion
## layer has played, and the run-up's and the arc's timings.
enum JumpPhase { NONE, RUNUP, AIR, LANDING }
var _jump_phase: int = JumpPhase.NONE
var _jump_clip: String = ""
var _jump_pos: float = 0.0
var _jump_runup: float = 0.0
var _jump_rise: float = 0.0
var _jump_fall: float = 0.0
var _jump_air_time: float = 0.0
## How long the body has been off the ground with no jump started - a step off a ledge is
## given a moment before it counts as a fall, or every bump in the ground would play one.
var _airborne_time: float = 0.0
## clip+stage-count -> the stage windows it splits into. Purely derived from the
## clip's impact metadata, so it is worked out once and kept.
var _combo_window_cache: Dictionary = {}
## gait space -> the cycle length its clips are stretched onto (see _build_gait_space).
var _gait_cycle: Dictionary = {}

## Bone indices of FOOT_BONES, one [ankle, toe] pair per foot. Empty when the rig has no
## such bones, which leaves footfall silent rather than broken.
var _feet: Array[PackedInt32Array] = []
## How far the ankle sits above the ground when the foot is flat - so the ankle's height
## minus this is the heel's. Taken from the rest pose, which stands flat-footed.
var _heel_height: float = 0.0
## Per foot: on the ground as far as footfall is concerned. Starts, and is reset to, true,
## so a foot has to be seen in the air before its landing counts.
var _foot_down: Array[bool] = []
## How long one full stride (both feet) currently takes on screen, and how long since the
## last footfall - see _track_footfalls for what the two are compared for.
var _stride_seconds: float = 0.0
var _since_footfall: float = INF
## Gait clip -> [left, right]: the lowest each foot gets in that clip, never below zero.
## The warrior's clips plant both feet at 0-0.5 cm, but the archer's set theirs down
## anywhere up to 2.3 cm off the ground - the right foot most of all - and against a
## fixed 1 cm plant height that foot was never seen to land. See _measure_foot_floors.
var _foot_floors: Dictionary = {}
## The same, per visual scene: measuring means posing every gait clip, so each class's
## clips are measured once a session rather than once a player.
static var _foot_floor_cache: Dictionary = {}


func _ready() -> void:
	var owner_class: String = ClassDatabase.resolve(String(get_parent().get_meta("character_class", ""))) if get_parent() != null else ClassDatabase.DEFAULT_CLASS
	var visual_path: String = ClassDatabase.visual_scene(owner_class)
	var visual_scene: PackedScene = load(visual_path) as PackedScene
	if visual_scene == null:
		push_error("Class '%s' has no visual at %s; falling back to the warrior" % [owner_class, visual_path])
		visual_scene = load(ClassDatabase.visual_scene(ClassDatabase.DEFAULT_CLASS)) as PackedScene
	_visual = visual_scene.instantiate()
	add_child(_visual)
	_anim = _visual.find_child("AnimationPlayer", true, false)
	_skeleton = _visual.find_child("Skeleton3D", true, false)
	if _anim == null or _skeleton == null:
		push_error("%s is missing its AnimationPlayer or Skeleton3D; the player will not animate" % visual_path)
		return
	_gait_spaces = _class_gait_spaces(_anim.get_animation_library(""))
	_walk_guards = ClassDatabase.walk_guards(owner_class)
	_build_tree()
	# A class that carries a bow gets its string and its nocked arrow drawn live.
	var bow: Node3D = _visual.find_child("Bow", true, false) as Node3D
	if bow != null:
		var rig := BowRig.new()
		rig.setup(self, bow, _skeleton)
		_visual.add_child(rig)
		_bow_aim = BowAim.new()
		_bow_aim.setup(_skeleton, bow, rig)
		_skeleton.add_child(_bow_aim)
	# A class that holds magic instead of a weapon gets its orb over the palm (the mage).
	if ClassDatabase.has_hand_orb(owner_class):
		_hand_orb = MageHandOrb.new()
		_hand_orb.setup(_skeleton, get_parent() as Player)
		_visual.add_child(_hand_orb)
	_find_feet()
	_measure_foot_floors(visual_path)
	_roll_next_idle_variation()
	_request_loco(IDLE_CLIP)


## Builds the blend graph described in this file's header. Done in code rather than
## authored as a .tres so the node set stays derived from STATE_CLIPS/GAIT_SPACES and the
## bone filter stays derived from the actual skeleton - adding a clip or re-rigging
## does not leave a stale resource behind.
func _build_tree() -> void:
	var library: AnimationLibrary = _anim.get_animation_library("")
	# The AnimationTree drives the skeleton from here on; leaving the player running
	# as well would have two mixers writing the same bones.
	_anim.stop()

	var graph := AnimationNodeBlendTree.new()

	var loco := AnimationNodeTransition.new()
	loco.xfade_time = GameSettings.player_anim_blend_locomotion
	# A jump straight after a landing restarts the jump clip it is still in (_restart_loco);
	# every other request goes through _request_loco, which never asks for the current one.
	loco.allow_transition_to_self = true

	# The transition's inputs are the STATES plus the two gait spaces. A blend tree accepts a
	# BlendSpace2D as a node like any other, and a transition input is an ordinary graph
	# connection, so travel becomes two inputs instead of six.
	var inputs: Array[String] = []
	var resets: Array[bool] = []
	for clip in STATE_CLIPS.keys():
		if library.has_animation(clip):
			inputs.append(clip)
			resets.append(bool(STATE_CLIPS[clip]))
		elif not OPTIONAL_STATES.has(clip):
			# A class with no guard has no block clip, and that is not a fault.
			push_warning("Locomotion clip '%s' is missing from the player library" % clip)
	for space_name in _gait_spaces.keys():
		if _build_gait_space(graph, library, String(space_name)):
			inputs.append(String(space_name))
			resets.append(false)

	loco.set("input_count", inputs.size())
	for i in inputs.size():
		loco.set("input_%d/name" % i, inputs[i])
		loco.set("input_%d/reset" % i, resets[i])
	graph.add_node(LOCO_NODE, loco, Vector2(280.0, 0.0))
	for i in inputs.size():
		# A gait space is already a node in the graph; a state clip needs one building.
		if _gait_spaces.has(inputs[i]):
			graph.connect_node(LOCO_NODE, i, inputs[i])
			continue
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = inputs[i]
		graph.add_node("loco_" + inputs[i], clip_node, Vector2(0.0, 80.0 * i))
		graph.connect_node(LOCO_NODE, i, "loco_" + inputs[i])

	var loco_speed := AnimationNodeTimeScale.new()
	graph.add_node(LOCO_SPEED_NODE, loco_speed, Vector2(480.0, 0.0))
	graph.connect_node(LOCO_SPEED_NODE, 0, LOCO_NODE)

	_action_anim = AnimationNodeAnimation.new()
	graph.add_node(ACTION_NODE, _action_anim, Vector2(280.0, 240.0))
	var action_speed := AnimationNodeTimeScale.new()
	graph.add_node(ACTION_SPEED_NODE, action_speed, Vector2(480.0, 240.0))
	graph.connect_node(ACTION_SPEED_NODE, 0, ACTION_NODE)

	# The guard sits BETWEEN locomotion and the action one-shot, so that the three layers
	# stack in the order the player experiences them: the legs do whatever they are doing,
	# the arms hold the block on top of that, and a swing or a flinch plays over both and
	# hands the arms back to the guard when it finishes.
	#
	# That last part is the reason it is a layer at all rather than another locomotion
	# state. `block_react` is fired through the one-shot like any other action, so with the
	# guard living in the locomotion transition a parried hit played its flinch and left
	# the character standing with their arms down - the hit was blocked, and they had
	# visibly stopped blocking.
	_build_guard_layer(graph, library)

	_shot = AnimationNodeOneShot.new()
	_shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_shot.fadein_time = GameSettings.player_anim_blend_action
	_shot.fadeout_time = GameSettings.player_anim_blend_action
	_shot.autorestart = false
	for bone_name in _upper_body_bones():
		_shot.set_filter_path(NodePath("%s:%s" % [_visual.get_path_to(_skeleton), bone_name]), true)
	graph.add_node(SHOT_NODE, _shot, Vector2(880.0, 0.0))
	graph.connect_node(SHOT_NODE, 0, GUARD_NODE if _has_guard else LOCO_SPEED_NODE)
	graph.connect_node(SHOT_NODE, 1, ACTION_SPEED_NODE)
	graph.connect_node("output", 0, SHOT_NODE)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_visual.add_child(_tree)
	# root_node resolves the clips' "Skeleton3D:<bone>" track paths, so it has to be
	# the visual root, exactly as the AnimationPlayer's own root_node is.
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", library)
	_tree.tree_root = graph
	_tree.active = true


## One gait as a BlendSpace2D: forward at +Y, back at -Y, right at +X, left at -X.
##
## Four points on the axes rather than eight around a circle. The domain is then a diamond,
## and `_blend_point` normalizes by the L1 norm so a 45-degree input lands at (0.5, 0.5) -
## exactly the midpoint of the forward-right edge, a clean 50/50 blend. Normalizing the usual
## way would hand it (0.707, 0.707), which is OUTSIDE the diamond and gets clamped back to the
## same place anyway, only without the weights being anything this file could compute for
## itself - and `_blended_travel_speed` needs them.
##
## The four clips are PHASE-LOCKED: each is stretched onto the forward clip's cycle length and
## the space is synced, so all four advance together whatever their weight. Left alone, each
## clip in a blend space keeps its own clock, and these four are 1.23-1.37 s long - within a
## few cycles a diagonal was blending one clip's left foot landing with the other's left foot
## halfway through its swing, which sank the feet several centimetres into the ground and never
## properly lifted them, and left no footstep for `footfall` to hear. Every clip puts the left
## foot down about a fifth of the way into its cycle and the right one about three quarters
## in, so once they share one clock a blend steps when both of its halves do.
##
## Returns false when the clips are missing, so a stripped library falls back to the states
## rather than leaving a dead transition input nothing can play.
func _build_gait_space(graph: AnimationNodeBlendTree, library: AnimationLibrary, space_name: String) -> bool:
	var clips: Dictionary = _gait_spaces[space_name]
	for clip in clips.values():
		if not library.has_animation(String(clip)):
			push_warning("Gait '%s' is missing clip '%s'; falling back" % [space_name, clip])
			return false

	var space := AnimationNodeBlendSpace2D.new()
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	space.sync = true
	var cycle: float = library.get_animation(String(clips["forward"])).length
	_gait_cycle[space_name] = cycle
	for entry in [
		["forward", Vector2(0.0, 1.0)], ["back", Vector2(0.0, -1.0)],
		["right", Vector2(1.0, 0.0)], ["left", Vector2(-1.0, 0.0)],
	]:
		var point := AnimationNodeAnimation.new()
		point.animation = String(clips[entry[0]])
		point.use_custom_timeline = true
		# Every clip starts where its left foot comes down, when the builder measured that
		# (`left_landing`), so the blended clips plant the same foot together.
		var gait_clip: Animation = library.get_animation(String(clips[entry[0]]))
		point.start_offset = float(gait_clip.get_meta("left_landing", 0.0)) * gait_clip.length
		point.timeline_length = cycle
		point.stretch_time_scale = true
		point.loop_mode = Animation.LOOP_LINEAR
		space.add_blend_point(point, entry[1])
	graph.add_node(space_name, space, Vector2(60.0, 520.0 if space_name == RUN_SPACE else 360.0))
	return true


## GAIT_SPACES for this library. A class whose pack ships a real sideways run (the
## archer's "run_left"/"run_right") runs sideways with it instead of with the sped-up
## sidestep the warrior has to make do with.
static func _class_gait_spaces(library: AnimationLibrary) -> Dictionary:
	var spaces: Dictionary = GAIT_SPACES.duplicate(true)
	if library != null and library.has_animation("run_left") and library.has_animation("run_right"):
		spaces[RUN_SPACE]["left"] = "run_left"
		spaces[RUN_SPACE]["right"] = "run_right"
	return spaces


## The guard overlay: `block_idle` on the upper body only, over whatever the legs are
## doing underneath.
##
## A Blend2 filtered to the same bones the action one-shot uses, so "upper body" means one
## thing in this file. Filtered paths take input 1; everything else passes input 0 through
## untouched, which is what leaves the walk driving the legs.
func _build_guard_layer(graph: AnimationNodeBlendTree, library: AnimationLibrary) -> void:
	# A class that does not block (the archer rolls) has no clip for it, and no layer.
	_has_guard = library.has_animation(BLOCK_CLIP)
	if not _has_guard:
		return
	var pose := AnimationNodeAnimation.new()
	pose.animation = BLOCK_CLIP
	graph.add_node(GUARD_POSE_NODE, pose, Vector2(480.0, 140.0))

	var guard := AnimationNodeBlend2.new()
	guard.filter_enabled = true
	for bone_name in _upper_body_bones():
		guard.set_filter_path(NodePath("%s:%s" % [_visual.get_path_to(_skeleton), bone_name]), true)
	graph.add_node(GUARD_NODE, guard, Vector2(700.0, 0.0))
	graph.connect_node(GUARD_NODE, 0, LOCO_SPEED_NODE)
	graph.connect_node(GUARD_NODE, 1, GUARD_POSE_NODE)


## Moves the guard towards `wanted` rather than snapping it, so the arms come up over
## GUARD_BLEND_SECONDS instead of popping into place on the frame the button went down.
func _drive_guard(wanted: bool, delta: float) -> void:
	if not _has_guard:
		return
	var target: float = 1.0 if wanted else 0.0
	if is_equal_approx(_guard_amount, target):
		return
	_guard_amount = move_toward(_guard_amount, target, delta / GUARD_BLEND_SECONDS)
	_tree.set(PARAM_GUARD_AMOUNT, _guard_amount)


## Every bone that is not hips-or-below. Derived from the skeleton rather than
## listed, so a rig change cannot silently leave a bone unmasked.
func _upper_body_bones() -> Array[String]:
	var out: Array[String] = []
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if not LOWER_BODY_BONES.has(bone_name):
			out.append(bone_name)
	return out


# --- queries the combat code needs -------------------------------------------
#
# Deliberately no is_acting()/is_staggered() here. `Player` runs its own timers for
# how long a swing commits it and how long a stagger locks it out, and those are
# gameplay facts, not animation ones - exposing a second copy from this node would
# invite the two to disagree.

## Where a held spell should sit: midway between the two hands, in world space.
##
## Read off the live skeleton rather than from an offset on the body, because the point of a
## charge effect is that the character is visibly holding it - an orb pinned to the chest
## drifts away from the hands the moment the cast clip moves them, and `cast_red`'s lead-in
## does exactly that over the whole charge.
##
## Falls back to a point in front of the chest if either hand is missing from the rig, so a
## re-rig degrades to "roughly right" instead of dropping the effect at the character's feet.
func hand_midpoint() -> Transform3D:
	var fallback := Transform3D(global_transform.basis, global_position + Vector3(0.0, 1.25, 0.0) - global_transform.basis.z * 0.45)
	if _skeleton == null:
		return fallback
	var left: int = _skeleton.find_bone("mixamorig_LeftHand")
	var right: int = _skeleton.find_bone("mixamorig_RightHand")
	if left == -1 or right == -1:
		return fallback
	var to_world: Transform3D = _skeleton.global_transform
	var left_pos: Vector3 = (to_world * _skeleton.get_bone_global_pose(left)).origin
	var right_pos: Vector3 = (to_world * _skeleton.get_bone_global_pose(right)).origin
	return Transform3D(global_transform.basis, (left_pos + right_pos) * 0.5)


## Where one hand is, in world space - the right one or the left. Where the mage's bolt leaves
## (MageKit). Falls back to between the hands, like hand_midpoint.
func hand_point(right: bool) -> Vector3:
	if _skeleton == null:
		return hand_midpoint().origin
	var bone: int = _skeleton.find_bone("mixamorig_RightHand" if right else "mixamorig_LeftHand")
	if bone == -1:
		return hand_midpoint().origin
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## Where the action layer is: the clip and the playhead in seconds of it, or "" when
## nothing is playing there.
func action_clip() -> String:
	return _shot_clip


func action_position() -> float:
	return _shot_position


## How far `clip`'s own root motion has carried the character forwards, in metres, by
## `clip_seconds` into the stored clip - for an attack the body is moved with rather than
## planted (the builder's `root_forward`, sampled at its RESAMPLE_FPS). 0 for a clip without.
func root_forward(clip: String, clip_seconds: float) -> float:
	return _root_sample(clip, "root_forward", clip_seconds)


## How far `clip`'s own root motion has carried the character over the floor, in metres and in
## whatever direction, by `clip_seconds` - for a move that travels one way that is not
## forwards, like the archer's sideways dodge (the builder's `root_travel`). 0 for a clip without.
func root_travel(clip: String, clip_seconds: float) -> float:
	return _root_sample(clip, "root_travel", clip_seconds)


## When `clip` has done its travelling (root_travel): the first moment it is within
## `settled` of the whole distance. The clip's length for one that does not travel.
func root_travel_end(clip: String, settled: float = 0.97) -> float:
	if not has_clip(clip):
		return 0.0
	var samples: PackedFloat32Array = _anim.get_animation(clip).get_meta("root_travel", PackedFloat32Array())
	if samples.size() < 2 or samples[samples.size() - 1] <= 0.0:
		return _clip_length(clip)
	var goal: float = samples[samples.size() - 1] * settled
	for i in samples.size():
		if samples[i] >= goal:
			return minf(float(i) / ROOT_MOTION_FPS, _clip_length(clip))
	return _clip_length(clip)


func _root_sample(clip: String, meta: String, clip_seconds: float) -> float:
	if not has_clip(clip):
		return 0.0
	var samples: PackedFloat32Array = _anim.get_animation(clip).get_meta(meta, PackedFloat32Array())
	if samples.is_empty():
		return 0.0
	var at: float = clampf(clip_seconds * ROOT_MOTION_FPS, 0.0, float(samples.size() - 1))
	var i: int = mini(int(at), samples.size() - 2) if samples.size() > 1 else 0
	if samples.size() == 1:
		return samples[0]
	return lerpf(samples[i], samples[i + 1], at - float(i))


## How far the arrow should be turned onto the crosshair for the clip on the action layer:
## from the moment it is on the string in `draw`, through `aim`, until it is gone in `shoot`
## - the same stretch BowRig shows the arrow for. Read off the animator rather than the kit,
## because the kit only runs on the machine playing this archer, and every screen has to
## aim the bow.
func _bow_aim_wanted() -> float:
	match _shot_clip:
		"draw":
			return smoothstep(BOW_AIM_DRAW_FROM, BOW_AIM_DRAW_FULL, _shot_position)
		"aim":
			return 1.0
		"shoot":
			return 1.0 if _shot_position < BowRig.SHOOT_RELEASED_AT + 0.1 else 0.0
	return 0.0


func _update_bow_aim(delta: float) -> void:
	if _bow_aim == null:
		return
	var wanted: float = 0.0 if _is_dead else _bow_aim_wanted()
	# In with the draw itself - already eased, and paced by the clip, so a quicker draw turns
	# in quicker - and out at the blend rate once the arrow has gone.
	if wanted >= _bow_aim.amount:
		_bow_aim.amount = wanted
	else:
		_bow_aim.amount = move_toward(_bow_aim.amount, wanted, GameSettings.archer_aim_blend_rate * delta)
	_bow_aim.active = _bow_aim.amount > 0.0
	if _bow_aim.active:
		var player := get_parent() as Player
		if player != null and player.camera != null:
			_bow_aim.aim_point = player.aim_hit_point(GameSettings.archer_arrow_range)


## The ball of energy over the palm, for a class that holds one (ClassDatabase.has_hand_orb),
## else null.
func hand_orb() -> MageHandOrb:
	return _hand_orb


## Where an arrow leaves the bow, in world space: at the nock, i.e. the drawing hand. Falls
## back to between the hands for a class with no bow.
func bow_nock_point() -> Vector3:
	var rig: BowRig = _visual.find_child("BowRig", false, false) as BowRig if _visual != null else null
	if rig != null:
		return rig.nock_point()
	return hand_midpoint().origin


func _process(delta: float) -> void:
	_update_bow_aim(delta)
	if _shot_clip != "":
		_shot_position += delta * _shot_speed
		if _shot_position >= _shot_end:
			_shot_clip = ""
	_update_spin()


## Whirlwind's turn (WHIRLWIND_CLIP): the figure faces the body's way again the moment the
## spin ends or is cut off.
func _update_spin() -> void:
	var progress: float = whirlwind_progress()
	var angle: float = TAU * GameSettings.barbarian_whirlwind_turns * progress if progress >= 0.0 else 0.0
	if not is_equal_approx(rotation.y, angle):
		rotation.y = angle


## How far through Whirlwind's spin this figure is, 0..1, or -1 while it is not spinning. Read
## by WhirlwindFx, on every screen, the same way the turn above is.
func whirlwind_progress() -> float:
	if _shot_clip != WHIRLWIND_CLIP or _shot_end <= _shot_start:
		return -1.0
	return clampf((_shot_position - _shot_start) / (_shot_end - _shot_start), 0.0, 1.0)


## When, in seconds from the start of playback, `clip` lands its hits if the slice
## `window` of its strike window is stretched to `duration`. Empty for clips the
## builder found no impact in, and for a stage that contains none of them.
##
## `hit_ratios` are normalized within the strike WINDOW, not the whole stored clip,
## and an action always plays exactly the requested slice of that window over
## `duration` - so scaling by duration is right, and must not be "corrected" to use
## the full clip length.
func hit_times(clip: String, duration: float, window: Vector2 = FULL_WINDOW) -> Array[float]:
	var out: Array[float] = []
	var span: float = window.y - window.x
	if span <= 0.0:
		return out
	for ratio in _hit_ratios(clip):
		# Half-open on the upper edge so an impact sitting exactly on a stage boundary
		# pays out once, in the stage that follows it - except at the very end of the
		# clip, where there is no following stage to hand it to.
		if ratio < window.x or (ratio >= window.y and window.y < 1.0):
			continue
		out.append(clampf((ratio - window.x) / span, 0.0, 1.0) * duration)
	return out


## Splits `clip`'s strike window into `stages` consecutive slices, each an
## [start, end] pair of ratios within that window, in playback order.
##
## The cuts land in the widest gaps between measured impacts, so a stage always holds
## whole strikes - which is what lets one stored flourish be spent one click at a time.
## Within a gap the cut is where the weapon is slowest (the builder's `lull_ratios`): the
## pause after a strike, not halfway to the next one. Halfway was often the next strike's
## wind-up already, and a click that was not followed faded back to idle from a raised
## blade - the chain looked cut off. A library built before the pauses were measured cuts
## at the midpoint. A clip with fewer impacts than stages has nothing to measure against,
## so it is divided evenly instead.
func combo_windows(clip: String, stages: int) -> Array[Vector2]:
	var count: int = maxi(stages, 1)
	var cache_key: String = "%s#%d" % [clip, count]
	if _combo_window_cache.has(cache_key):
		return _combo_window_cache[cache_key]

	var windows: Array[Vector2] = []
	var hits: PackedFloat32Array = _hit_ratios(clip)
	if count == 1 or hits.size() < count:
		for i in count:
			windows.append(Vector2(float(i) / float(count), float(i + 1) / float(count)))
	else:
		# x is a gap's width, y where it would be cut. Sorted by width, so the widest pauses
		# in the flourish are the ones that become stage boundaries.
		var lulls: PackedFloat32Array = _anim.get_animation(clip).get_meta("lull_ratios", PackedFloat32Array())
		var gaps: Array[Vector2] = []
		for i in hits.size() - 1:
			var cut: float = lulls[i] if lulls.size() == hits.size() - 1 else (hits[i] + hits[i + 1]) * 0.5
			gaps.append(Vector2(hits[i + 1] - hits[i], cut))
		gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
		var cuts: Array[float] = []
		for i in count - 1:
			cuts.append(gaps[i].y)
		cuts.sort()
		var start: float = 0.0
		for cut in cuts:
			windows.append(Vector2(start, cut))
			start = cut
		windows.append(Vector2(start, 1.0))

	_combo_window_cache[cache_key] = windows
	return windows


func _hit_ratios(clip: String) -> PackedFloat32Array:
	if _anim == null or not _anim.has_animation(clip):
		return PackedFloat32Array()
	return _anim.get_animation(clip).get_meta("hit_ratios", PackedFloat32Array())


## When, in seconds from the start of playback, `clip` should pay out if it is
## stretched to `duration`. The first measured impact frame, or the middle of the
## clip when the builder found none. Casts use this for their release moment, which
## is why SpellDatabase carries no release ratio of its own: the clip already knows.
## `use_last` picks the FINAL impact instead, for a clip whose payload is its last
## beat rather than its first - a jump attack lands on the slam, not the take-off.
func release_time(clip: String, duration: float, use_last: bool = false) -> float:
	var times := hit_times(clip, duration)
	if times.is_empty():
		return duration * 0.5
	return times[times.size() - 1] if use_last else times[0]


# --- things the combat code makes happen -------------------------------------

## Where `clip` releases, in seconds from the START of the stored clip rather than as a
## time within the played window - the same relationship hit_offsets() has to hit_times().
## What a cast continuing out of its own wind-up needs, since its playhead is measured
## against the whole clip rather than against the strike window alone.
func release_offset(clip: String, use_last: bool = false) -> float:
	var offsets: Array[float] = hit_offsets(clip)
	if offsets.is_empty():
		return windup_length(clip) + strike_length(clip) * 0.5
	return offsets[-1] if use_last else offsets[0]


## Fires `clip` over `duration` seconds, speeding it up or slowing it down to fit.
##
## `upper_body` decides whether the legs keep walking underneath. Pass true for a
## move the player can walk through (the light attack chain), false for one that
## takes the whole body - and for those, root the player, because a full-body clip
## over a moving character is exactly the foot-sliding this layering exists to
## remove.
##
## `window` narrows playback to one slice of the clip's strike window, which is how
## a multi-hit flourish is spent one stage per click (see combo_windows). The
## one-shot's own fade-out carries the character from wherever that stage ended back
## to its resting pose, so a stage never has to finish on a neutral frame.
func play_action(clip: String, duration: float, upper_body: bool, window: Vector2 = FULL_WINDOW) -> void:
	if _tree == null or _is_dead or not has_clip(clip):
		return
	# Play only the strike, out of a clip that is stored whole. The Mixamo originals
	# wind all the way back down to a rest pose, which is far too long at this
	# cadence - but cutting the stored clip down instead would leave the library full
	# of stumps, so the window is applied here via the custom timeline.
	var full_length: float = _action_length(clip)
	var span: float = clampf(window.y - window.x, 0.01, 1.0)
	var played: float = full_length * span
	var speed: float = played / maxf(duration, 0.01)
	var timeline: float = played + (CONTINUED_CLIP_HOLD * speed if _is_continued(clip) else 0.0)
	_fire_shot(clip, windup_length(clip) + window.x * full_length, timeline, speed, duration, upper_body)


## True for a clip some other clip carries straight on from (CONTINUES_FROM).
static func _is_continued(clip: String) -> bool:
	for followers: Array in CONTINUES_FROM.values():
		if followers.has(clip):
			return true
	return false


## How much clip sits IN FRONT of `clip`'s strike window - the wind-up the trim
## discards. Zero for a clip whose window starts at its own first frame.
func windup_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return float(_anim.get_animation(clip).get_meta("trim_start", 0.0))


## How long `clip`'s strike window runs, in seconds of stored clip.
func strike_length(clip: String) -> float:
	return _action_length(clip)


## Where `clip`'s impacts fall, in seconds from the START of the stored clip rather
## than as ratios within its strike window - which is what a play beginning outside
## that window, like a charged swing continuing out of its own lead-in, needs.
func hit_offsets(clip: String) -> Array[float]:
	var out: Array[float] = []
	var window_start: float = windup_length(clip)
	var window_length: float = _action_length(clip)
	for ratio in _hit_ratios(clip):
		out.append(window_start + ratio * window_length)
	return out


## Starts the heavy's wind-up: the lead-in, crawling by at `duration`'s pace.
##
## Where it STOPS is the design: exactly where the strike window begins, i.e. where
## the builder measured the limb starting to work. Everything the player came to see
## - the acceleration, the impact, the follow-through - is therefore still ahead of
## them when they let go. Measured on spin_high, the lead-in is 8 frames over which
## the hand travels 0.13, against 5.35 for the swing proper: holding it reads as a
## slow raise while costing the swing nothing.
##
## The shot's TIMELINE deliberately runs past that stop, all the way through the
## strike window, even though the wind-up will never reach it at this speed. A
## one-shot ends when its own clip does, fading back to the locomotion layer - so a
## timeline that stopped at the top of the raise would drop the character to idle at
## the exact moment a full-length charge completes, and the swing would then have to
## blend in from idle rather than continue the raise. release_windup() speeds this
## same shot up instead of firing another one.
## `upper_body` is the same switch play_action() takes: false for a move that owns the
## whole body (the heavy's raise, which roots the player anyway), true for one the player
## can keep walking through - a held spell, where the legs staying on their cycle is what
## lets the caster reposition while the charge builds.
func play_windup(clip: String, duration: float, upper_body: bool = false) -> bool:
	var lead_in: float = windup_length(clip)
	if _tree == null or _is_dead or lead_in <= 0.0:
		return false
	_fire_shot(clip, 0.0, lead_in + strike_length(clip), lead_in / maxf(duration, 0.01), duration, upper_body)
	return true


## Turns the wind-up in flight into the swing, by changing nothing but its speed.
## `remaining` is how much stored clip is still ahead, `duration` how long it should
## take. No new shot is fired, so the character continues from the exact pose the
## raise had reached, at any point in the hold.
func release_windup(remaining: float, duration: float) -> void:
	if _tree == null or _is_dead:
		return
	_action_timer = maxf(duration, 0.01)
	set_action_speed(remaining / _action_timer)


## Retimes the shot in flight, in clip-seconds per real second, without restarting it
## or touching how long it is expected to run. The wind-up drives this every frame:
## it starts fast and eases towards a hold, so the raise is a snap rather than a crawl
## at one rate the whole way.
func set_action_speed(clip_seconds_per_second: float) -> void:
	if _tree == null:
		return
	_shot_speed = clip_seconds_per_second
	_tree.set(PARAM_ACTION_SPEED, clip_seconds_per_second)


## Aborts whatever the action layer is playing and lets the locomotion layer take
## the whole body back. For a move that is dropped rather than finished - a charge
## the player gave up on - where letting the one-shot run on would leave the
## character still winding up something that is no longer happening.
func stop_action() -> void:
	if _tree == null:
		return
	_action_timer = 0.0
	_shot_clip = ""
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Fires `clip` from `start_offset`, giving the shot a `timeline_length`-second
## window of it to play through at `speed` clip-seconds per real second. The one
## place the action layer is actually driven from.
##
## Speed is passed rather than derived from `hold_seconds` because the two come apart
## for a wind-up: it is given a timeline long enough to cover the swing that follows,
## but crawls through only the lead-in during the hold.
func _fire_shot(clip: String, start_offset: float, timeline_length: float, speed: float, hold_seconds: float, upper_body: bool) -> void:
	_action_timer = maxf(hold_seconds, 0.01)
	_cancel_idle_variation()
	var continues: bool = _shot_clip != "" and (CONTINUES_FROM.get(clip, []) as Array).has(_shot_clip)
	if clip == _shot_clip and absf(start_offset - _shot_position) <= SELF_CONTINUE_TOLERANCE:
		continues = true

	_shot.fadein_time = 0.0 if continues else GameSettings.player_anim_blend_action
	_shot.filter_enabled = upper_body
	_action_anim.animation = clip
	_action_anim.use_custom_timeline = true
	_action_anim.stretch_time_scale = false
	_action_anim.loop_mode = Animation.LOOP_NONE
	_action_anim.start_offset = start_offset
	_action_anim.timeline_length = timeline_length
	_tree.set(PARAM_ACTION_SPEED, speed)
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_shot_clip = clip
	_shot_position = start_offset
	_shot_start = start_offset
	_shot_speed = speed
	_shot_end = start_offset + timeline_length


## Plays a flinch, squeezed into `duration` the same way an action is. The raw
## Mixamo reactions run 1.0-1.8s, which is far too long to take control away for,
## hence the squeeze rather than natural playback. Always full-body: `Player` roots
## the character for the same window.
func play_reaction(clip: String, duration: float) -> void:
	play_action(clip, duration, false)


## Which of the three reaction clips matches a hit arriving from `world_direction`
## (pointing from the player towards whatever hit them).
func reaction_clip_for(world_direction: Vector3) -> String:
	var local := global_transform.basis.inverse() * world_direction
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return "hit_gut"
	local = local.normalized()
	# -Z is forward; a hit from roughly ahead or behind folds the player forward.
	if absf(local.x) < 0.6:
		return "hit_gut"
	return "hit_right" if local.x > 0.0 else "hit_left"


func play_death() -> void:
	if _tree == null or _is_dead:
		return
	_is_dead = true
	_action_timer = 0.0
	_shot_clip = ""
	_cancel_idle_variation()
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_tree.set(PARAM_LOCO_SPEED, 1.0)
	# Death rides the locomotion layer rather than the one-shot: a one-shot fades
	# back out at the end, and a corpse has to hold its final pose.
	_request_loco(DEATH_CLIP)


func revive() -> void:
	if _tree == null:
		return
	_is_dead = false
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_request_loco(IDLE_CLIP)


# --- per-frame locomotion ----------------------------------------------------

## Called every physics frame by `Player`. `planar_velocity` is in world space; it
## is resolved against the player's own facing here so strafing picks the sideways
## clips.
##
## Unlike the pre-AnimationTree version this does NOT stand down while an action is
## playing: the legs have to keep walking underneath a filtered swing. A full-body
## action masks this layer out anyway, and `Player` roots the character for those, so
## what is chosen here is idle.
func update_locomotion(
	delta: float,
	planar_velocity: Vector3,
	sprinting: bool,
	on_floor: bool,
	blocking: bool,
	in_combat: bool,
	vertical_velocity: float = 0.0,
) -> void:
	if _tree == null or _is_dead:
		return

	if _action_timer > 0.0:
		_action_timer -= delta

	var speed := planar_velocity.length()

	# Driven here, above every branch below, so that the arms come back DOWN on any path
	# out of blocking - jumping, dying, letting go, being staggered - without each of
	# those having to remember to lower them.
	#
	# Only while MOVING. Standing still under guard stays on the full-body `block_idle`
	# state: it is the pose the whole thing is modelled on, and overlaying it on an idle
	# lower body would be the same arms over a slightly different stance for no gain.
	# Nor for a class whose walks already hold the guard (the knight): `block_idle` is a
	# crouched stance, and its arms and spine over an upright walk read as neither.
	var moving: bool = speed > MOVING_SPEED_EPSILON
	_drive_guard(blocking and moving and not _walk_guards, delta)

	if blocking:
		_cancel_idle_variation()
		# block_idle has no travel of its own (travel_speed 0), so holding it while the
		# player is actually moving plants both feet and slides the whole character
		# across the ground. Walking under guard keeps the legs driving and the guard
		# layer above puts the block back on the arms - which is what was missing:
		# blocking on the move used to be an ordinary walk with the shield down. A class
		# whose walks are already behind the shield just walks (_walk_guards).
		if moving:
			_drive_gait(WALK_SPACE, planar_velocity, speed, delta)
			_track_footfalls(delta)
		else:
			_request_loco(BLOCK_CLIP)
			_tree.set(PARAM_LOCO_SPEED, 1.0)
			_settle_feet()
		return

	if _drive_jump(delta, on_floor, speed, vertical_velocity):
		_settle_feet()
		return

	if speed > MOVING_SPEED_EPSILON:
		_cancel_idle_variation()
		_drive_gait(_pick_gait(speed, sprinting, in_combat), planar_velocity, speed, delta)
		_track_footfalls(delta)
		return

	_tree.set(PARAM_LOCO_SPEED, 1.0)
	_settle_feet()
	_update_idle(delta)


# --- the jump ------------------------------------------------------------------------------

## A jump, in the three phases the builder measured on its clip ("jump_phases": take-off, peak
## and touchdown, seconds of clip):
##   RUNUP   the crouch before the take-off, squeezed into GameSettings.player_jump_runup -
##           Player starts the body's arc only when it ends (takeoff), on the clip's own
##           take-off frame, so the legs push and the body leaves the ground together;
##   AIR     take-off to peak over the arc's rise and peak to touchdown over its fall, each
##           stretched on its own, so the clip's lift and the arc's peak at the same moment
##           and the one strengthens the other instead of arriving after it;
##   LANDING the rest of the clip from the touchdown frame once the feet are really down - or
##           the class's own landing clip (land / land_run) when it has one.
## The locomotion layer plays the clip; this drives its speed every frame towards where the
## phase says it should be, and tracks the playhead itself (_jump_pos).
##
## `running` picks the running take-off when the class has one. Returns the run-up's length in
## real seconds: 0 when the clip takes off on its first frames or has no phases, and Player
## then takes off at once.
func begin_jump(running: bool) -> float:
	if _tree == null or _is_dead:
		return 0.0
	var clip: String = JUMP_RUN_CLIP if running and has_clip(JUMP_RUN_CLIP) else JUMP_CLIP
	if not has_clip(clip):
		return 0.0
	_start_jump_clip(clip)
	var phases: PackedFloat32Array = jump_phases(clip)
	if phases.is_empty():
		_jump_phase = JumpPhase.AIR
		_jump_air_time = 0.0
		return 0.0
	_jump_phase = JumpPhase.RUNUP
	# Never slower than the clip's own crouch: a short one keeps its own pace.
	_jump_runup = minf(GameSettings.player_jump_runup, phases[0])
	return _jump_runup


## The body has left the ground at `vertical_velocity`: the arc's rise and fall are what the
## clip's air phase is fitted to.
func takeoff(vertical_velocity: float) -> void:
	if _tree == null or _is_dead:
		return
	if _jump_phase == JumpPhase.NONE:
		begin_jump(false)
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_jump_rise = maxf(vertical_velocity, 0.01) / maxf(gravity, 0.01)
	_jump_fall = _jump_rise
	_jump_air_time = 0.0
	_jump_phase = JumpPhase.AIR


## The run-up was given up (the player was knocked down, or walked off an edge in it).
func cancel_jump() -> void:
	_jump_phase = JumpPhase.NONE


## [take-off, peak, touchdown] in seconds of `clip`, or empty.
func jump_phases(clip: String) -> PackedFloat32Array:
	if not has_clip(clip):
		return PackedFloat32Array()
	return _anim.get_animation(clip).get_meta("jump_phases", PackedFloat32Array())


## True while the run gait is playing - the jump taken from it is the running one.
func in_run_gait() -> bool:
	return _running


func is_jumping() -> bool:
	return _jump_phase != JumpPhase.NONE


## Which jump phase is playing and where in its clip, for tests and debugging.
func jump_state() -> Dictionary:
	return {"phase": _jump_phase, "clip": _jump_clip, "position": _jump_pos}


func _start_jump_clip(clip: String) -> void:
	_cancel_idle_variation()
	_jump_clip = clip
	_jump_pos = 0.0
	_restart_loco(clip)


## One frame of the jump in flight - or of a fall nobody jumped into. False when there is
## none and the ordinary locomotion below should run.
func _drive_jump(delta: float, on_floor: bool, speed: float, vertical_velocity: float) -> bool:
	if _jump_phase == JumpPhase.NONE:
		if on_floor:
			_airborne_time = 0.0
			return false
		_airborne_time += delta
		# Off the ground with no jump started: a teammate's jump (on this machine their
		# take-off is only seen as the body rising) or a step off a ledge.
		if vertical_velocity > FALL_START_SPEED:
			_begin_airborne(speed, vertical_velocity, false)
		elif _airborne_time > FALL_GRACE:
			_begin_airborne(speed, vertical_velocity, true)
		else:
			return false
	var phases: PackedFloat32Array = jump_phases(_jump_clip)
	var target: float = _jump_pos
	match _jump_phase:
		JumpPhase.RUNUP:
			if phases.is_empty():
				_set_jump_rate(0.0, delta)
				return true
			_jump_runup -= delta
			# Reaches the take-off frame as the run-up ends, then waits there for takeoff().
			var left: float = maxf(_jump_runup, 0.0)
			target = phases[0] if left <= 0.0 else _jump_pos + (phases[0] - _jump_pos) * minf(delta / left, 1.0)
		JumpPhase.AIR:
			_jump_air_time += delta
			if on_floor and _jump_air_time > LANDING_MIN_AIR:
				_land(speed)
				return _jump_phase != JumpPhase.NONE
			if phases.is_empty():
				# A falling loop (the archer's): plays as it is for as long as the fall lasts.
				_set_jump_rate(1.0, delta)
				return true
			if _jump_air_time <= _jump_rise:
				target = lerpf(phases[0], phases[1], _jump_air_time / maxf(_jump_rise, 0.01))
			else:
				# Held a touch short of the touchdown frame if the fall outlasts the clip's -
				# a drop off a ledge - so the landing still has its beat to play.
				var fall: float = clampf((_jump_air_time - _jump_rise) / maxf(_jump_fall, 0.01), 0.0, 1.0)
				target = lerpf(phases[1], phases[2], fall) - (0.0 if fall < 1.0 else TOUCHDOWN_HOLD)
				target = maxf(target, phases[1])
		JumpPhase.LANDING:
			var length: float = _clip_length(_jump_clip)
			var ends: float = length * (LAND_RUN_HANDOFF if _jump_clip == LAND_RUN_CLIP else 1.0)
			# Moving off a standing landing: the legs go straight back to the gait.
			if speed > MOVING_SPEED_EPSILON and _jump_clip != LAND_RUN_CLIP:
				_jump_phase = JumpPhase.NONE
				return false
			if _jump_pos >= ends - 0.01 or not on_floor:
				_jump_phase = JumpPhase.NONE
				return false
			_set_jump_rate(GameSettings.player_jump_landing_pace, delta)
			return true
	# Faster than real time is fine (catching up a playhead started mid-arc); backwards is not.
	_set_jump_rate(clampf((target - _jump_pos) / maxf(delta, 0.0001), 0.0, MAX_JUMP_RATE), delta)
	return true


## Off the ground without a jump of this machine's: the jump clip from its take-off frame
## (rising) or from its peak (falling), fitted to an arc as fast as the body is moving.
func _begin_airborne(speed: float, vertical_velocity: float, falling: bool) -> void:
	var running: bool = _running and speed > MOVING_SPEED_EPSILON and has_clip(JUMP_RUN_CLIP)
	if not has_clip(JUMP_RUN_CLIP if running else JUMP_CLIP):
		return
	_start_jump_clip(JUMP_RUN_CLIP if running else JUMP_CLIP)
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_jump_fall = GameSettings.player_jump_velocity / maxf(gravity, 0.01)
	if falling:
		# A fall starts at the peak: there was no rise to play.
		_jump_rise = 0.0
	else:
		_jump_rise = maxf(vertical_velocity, 0.0) / maxf(gravity, 0.01)
	_jump_air_time = 0.0
	_jump_phase = JumpPhase.AIR


## The feet are down: the class's own landing clip, or the rest of the jump clip.
func _land(speed: float) -> void:
	var moving: bool = speed > MOVING_SPEED_EPSILON
	var landing: String = LAND_RUN_CLIP if moving else LAND_CLIP
	if has_clip(landing):
		_start_jump_clip(landing)
		_jump_phase = JumpPhase.LANDING
		return
	if moving or jump_phases(_jump_clip).is_empty():
		_jump_phase = JumpPhase.NONE
		return
	_jump_phase = JumpPhase.LANDING


func _set_jump_rate(rate: float, delta: float) -> void:
	_tree.set(PARAM_LOCO_SPEED, rate)
	_jump_pos += rate * delta


## Standing still: the plain idle loop, with an occasional "looking around" clip so
## the character doesn't read as a statue between waves. Any movement, attack or hit
## cancels a variation back to the plain loop (see _cancel_idle_variation).
func _update_idle(delta: float) -> void:
	if _idle_variation_timer > 0.0:
		_idle_variation_timer -= delta
		if _idle_variation_timer > 0.0:
			return
		_request_loco(IDLE_CLIP)
		_roll_next_idle_variation()
		return

	# Not while a swing is still in flight - the character would start idly looking
	# around mid-attack.
	if _action_timer <= 0.0:
		_idle_timer += delta
	if _idle_timer >= _next_idle_variation:
		var variation: String = IDLE_VARIATIONS[randi() % IDLE_VARIATIONS.size()]
		if has_clip(variation):
			_idle_variation_timer = _clip_length(variation)
			_request_loco(variation)
			return
		_roll_next_idle_variation()
		return

	_request_loco(IDLE_CLIP)


func _cancel_idle_variation() -> void:
	_idle_timer = 0.0
	if _idle_variation_timer > 0.0:
		_idle_variation_timer = 0.0
		_roll_next_idle_variation()


func _roll_next_idle_variation() -> void:
	_idle_timer = 0.0
	_next_idle_variation = randf_range(
		GameSettings.player_idle_variation_delay_min,
		GameSettings.player_idle_variation_delay_max
	)


# --- footsteps ---------------------------------------------------------------

func _find_feet() -> void:
	for pair in FOOT_BONES:
		var ankle: int = _skeleton.find_bone(pair[0])
		var toe: int = _skeleton.find_bone(pair[1])
		if ankle == -1 or toe == -1:
			push_warning("Player rig has no '%s'/'%s'; footsteps will be silent" % pair)
			_feet.clear()
			_foot_down.clear()
			return
		_feet.append(PackedInt32Array([ankle, toe]))
		_foot_down.append(true)
	var to_self: Transform3D = _skeleton_to_self()
	var ankle_rest: Vector3 = to_self * _skeleton.get_bone_global_rest(_feet[0][0]).origin
	var toe_rest: Vector3 = to_self * _skeleton.get_bone_global_rest(_feet[0][1]).origin
	_heel_height = ankle_rest.y - toe_rest.y


## How many poses of each gait clip _measure_foot_floors looks at.
const FOOT_FLOOR_SAMPLES := 60
const FOOT_FLOOR_PERCENTILE := 0.1


## Fills _foot_floors by playing each gait clip on the bare AnimationPlayer, with the tree
## switched off for the moment it takes, and noting how low each foot gets.
func _measure_foot_floors(key: String) -> void:
	if _feet.is_empty():
		return
	if _foot_floor_cache.has(key):
		_foot_floors = _foot_floor_cache[key]
		return
	_tree.active = false
	for clips: Dictionary in _gait_spaces.values():
		for clip_value in clips.values():
			var clip: String = String(clip_value)
			if _foot_floors.has(clip) or not has_clip(clip):
				continue
			var length: float = _clip_length(clip)
			var samples: Array[PackedFloat32Array] = []
			for i in _feet.size():
				samples.append(PackedFloat32Array())
			_anim.play(clip)
			for k in FOOT_FLOOR_SAMPLES:
				_anim.seek(length * float(k) / FOOT_FLOOR_SAMPLES, true)
				for i in _feet.size():
					samples[i].append(_foot_clearance(i))
			var lows: PackedFloat32Array = []
			for foot: PackedFloat32Array in samples:
				foot.sort()
				lows.append(maxf(foot[int(FOOT_FLOOR_PERCENTILE * (foot.size() - 1))], 0.0))
			_foot_floors[clip] = lows
	_anim.stop()
	_tree.active = true
	_foot_floor_cache[key] = _foot_floors


## Foot `i`'s clearance - the lower of its heel and its toe above the ground.
func _foot_clearance(i: int) -> float:
	var to_self: Transform3D = _skeleton_to_self()
	var ankle: Vector3 = to_self * _skeleton.get_bone_global_pose(_feet[i][0]).origin
	var toe: Vector3 = to_self * _skeleton.get_bone_global_pose(_feet[i][1]).origin
	return minf(ankle.y - _heel_height, toe.y)


## Where foot `i` stands when it is down in the gait playing now: the two clips' floors,
## by the same weights the blend gives them (see _blended_travel_speed).
func _gait_foot_floor(i: int) -> float:
	var clips: Dictionary = _gait_spaces.get(_current_loco, {})
	var weight: float = absf(_blend_point.x) + absf(_blend_point.y)
	if clips.is_empty() or weight < 0.0001:
		return 0.0
	var forward_back: String = String(clips["forward"] if _blend_point.y >= 0.0 else clips["back"])
	var sideways: String = String(clips["right"] if _blend_point.x >= 0.0 else clips["left"])
	return (
		absf(_blend_point.y) * _clip_foot_floor(forward_back, i)
		+ absf(_blend_point.x) * _clip_foot_floor(sideways, i)
	) / weight


func _clip_foot_floor(clip: String, i: int) -> float:
	var lows: PackedFloat32Array = _foot_floors.get(clip, PackedFloat32Array())
	return lows[i] if i < lows.size() else 0.0


## Emits `footfall` for each foot that has come down since the last frame.
##
## A foot's CLEARANCE is the lower of its heel and its toe, so a landing counts whichever
## end meets the ground first - heel-first going forward, toe-first going back, the edge of
## the foot on a sidestep. Measured in this node's own space, which is the ground under the
## character and is unscaled by Giant Growth, so the thresholds hold at any size.
##
## Hysteresis rather than one threshold: a planted foot rolling from heel to toe hovers a
## centimetre off the ground, and has to be seen properly lifted before the next landing
## counts, or one step would be heard two or three times. Both heights are above the
## foot's own floor in the clips playing (_gait_foot_floor), not above zero: a clip that
## plants a foot 2 cm up still plants it.
##
## And a touchdown too soon after the last footstep is not one. Some blends brush a toe
## along the ground mid-swing - sprinting diagonally mixes the run with a sped-up sidestep,
## whose trailing foot taps the ground once before it properly lands - and nothing about
## the pose at that moment tells the brush from a real toe-first landing; a back-pedal or
## a sidestep lands exactly like that. WHEN it happens does: real steps alternate half a
## stride apart, and the brush comes a quarter of a stride after the other foot's.
func _track_footfalls(delta: float) -> void:
	if _feet.is_empty():
		return
	_since_footfall += delta
	for i in _feet.size():
		var clearance: float = _foot_clearance(i) - _gait_foot_floor(i)
		if _foot_down[i]:
			if clearance > GameSettings.player_footstep_lift_height:
				_foot_down[i] = false
		elif clearance < GameSettings.player_footstep_plant_height:
			_foot_down[i] = true
			if _since_footfall < _stride_seconds * GameSettings.player_footstep_min_stride_fraction:
				continue
			_since_footfall = 0.0
			var ankle: Vector3 = _skeleton_to_self() * _skeleton.get_bone_global_pose(_feet[i][0]).origin
			footfall.emit(global_transform * Vector3(ankle.x, 0.0, ankle.z))


## Whenever the legs are not walking - standing, guarding in place, in the air - both feet
## count as planted. The first step after any of those is then heard only once its foot
## has actually left the ground, and a landing from a jump is not two footsteps.
func _settle_feet() -> void:
	for i in _foot_down.size():
		_foot_down[i] = true
	_since_footfall = INF


func _skeleton_to_self() -> Transform3D:
	return global_transform.affine_inverse() * _skeleton.global_transform


# --- clip selection ----------------------------------------------------------

## Points a gait space at this velocity and times it to the ground actually being covered.
func _drive_gait(space: String, planar_velocity: Vector3, speed: float, delta: float) -> void:
	_request_loco(space)
	_drive_blend_point(_blend_point_for(planar_velocity), space, delta)
	var native: float = _blended_travel_speed(space, _blend_point)
	var playback: float = 1.0
	if native > 0.01:
		playback = clampf(
			speed / native,
			GameSettings.player_locomotion_speed_min,
			GameSettings.player_locomotion_speed_max
		)
	_tree.set(PARAM_LOCO_SPEED, playback)
	_stride_seconds = float(_gait_cycle.get(space, 0.0)) / playback


## The speed band the run cycle takes over at, with hysteresis: break into a run above the
## first, drop back to a walk only below the second.
##
## Two numbers rather than one because a single threshold is a boundary a speed can sit on -
## a slow debuff or a haste bonus landing near it would flip the gait every frame, which is
## the same failure the diagonal had. The pair sit either side of the old 1.5, so ordinary
## movement and blocking still land where they did.
const RUN_ENTER_SPEED := 1.65
const RUN_EXIT_SPEED := 1.35


## Which gait to blend in. Unlike the old picker this depends only on SPEED and whether a
## fight is on - never on direction - so turning with the mouse cannot change it.
##
## `in_combat` is what separates travelling from fighting. A player mid-fight keeps the armed
## walk however fast they are going; a player who has stopped swinging and is holding sprint
## gets the travel cycle.
func _pick_gait(speed: float, sprinting: bool, in_combat: bool) -> String:
	if in_combat:
		_running = false
		return WALK_SPACE
	if sprinting:
		_running = true
	elif _running:
		_running = speed > RUN_EXIT_SPEED
	else:
		_running = speed >= RUN_ENTER_SPEED
	return RUN_SPACE if _running else WALK_SPACE


## Where in a gait space this velocity sits, as the L1-normalized [right, forward] pair.
##
## L1 rather than the usual normalize: it puts a 45-degree input exactly on the diamond's edge
## at (0.5, 0.5), which is both a clean 50/50 blend and a pair of weights this file can read
## back off directly - `_blended_travel_speed` is those same two numbers.
func _blend_point_for(planar_velocity: Vector3) -> Vector2:
	var local: Vector3 = global_transform.basis.inverse() * planar_velocity
	# -Z is forward for a Node3D, so forward is the NEGATED local z.
	var point := Vector2(local.x, -local.z)
	var l1: float = absf(point.x) + absf(point.y)
	if l1 < 0.0001:
		return _blend_point
	return point / l1


## Eases the live blend point toward `target` and hands it to whichever space is playing.
func _drive_blend_point(target: Vector2, space: String, delta: float) -> void:
	var tau: float = maxf(GameSettings.player_anim_blend_point_smoothing, 0.001)
	_blend_point = _blend_point.lerp(target, 1.0 - exp(-delta / tau))
	_tree.set(PARAM_RUN_POINT if space == RUN_SPACE else PARAM_WALK_POINT, _blend_point)


## How fast the BLEND is travelling under its own power, in units/second.
##
## The old _speed_scale_for divided by one clip's travel_speed, which is meaningless once two
## clips are playing at once: a forward-right diagonal is half walk_forward (0.99 m/s) and half
## walk_right (1.06), so its real stride covers 1.03 and dividing by either one alone asks the
## legs to turn over at the wrong rate. The blend weights are exactly |x| and |y| of the L1
## point, so the blended figure is one line.
func _blended_travel_speed(space: String, point: Vector2) -> float:
	var clips: Dictionary = _gait_spaces[space]
	var forward_back: String = String(clips["forward"] if point.y >= 0.0 else clips["back"])
	var sideways: String = String(clips["right"] if point.x >= 0.0 else clips["left"])
	var native: float = (
		absf(point.y) * _locked_travel_speed(space, forward_back)
		+ absf(point.x) * _locked_travel_speed(space, sideways)
	)
	return native


## A clip's travel speed once it is stretched onto `space`'s shared cycle (see
## _build_gait_space): the same stride spread over a longer or shorter loop.
func _locked_travel_speed(space: String, clip: String) -> float:
	var cycle: float = float(_gait_cycle.get(space, 0.0))
	if cycle <= 0.0:
		return _travel_speed(clip)
	return _travel_speed(clip) * _clip_length(clip) / cycle


func _travel_speed(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return _anim.get_animation(clip).get_meta("travel_speed", 0.0)


## How much of `clip` an action actually plays: the measured strike window when the
## builder found one, otherwise the whole clip (reactions and the like are untrimmed).
func _action_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	var anim := _anim.get_animation(clip)
	return float(anim.get_meta("trim_length", anim.length))


func _clip_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return _anim.get_animation(clip).length


## The transition node cross-fades on its own, but re-requesting the state it is
## already in would restart that fade every frame.
func _restart_loco(clip: String) -> void:
	_current_loco = clip
	_tree.set(PARAM_LOCO_REQUEST, clip)


func _request_loco(clip: String) -> void:
	if _current_loco == clip:
		return
	_current_loco = clip
	_tree.set(PARAM_LOCO_REQUEST, clip)
