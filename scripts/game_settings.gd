extends Node

# ============================================================
# MAP
# ============================================================
@export var map_base_radius: float = 50.0

# ============================================================
# DAY / NIGHT
# ============================================================
## The in-game hour a run begins at. Applied to Sky3D by MainController._ready.
##
## A run used to open at 20:45, which is past DayNightPacing's 20:00 dusk - so the game
## started in the dark, with the night music and the night clock rate, before the player had
## done anything. That was not a decision: it is whatever time the Sky3D node happened to be
## scrubbed to when scenes/misc/main.tscn was last saved, and any editor session that touches
## the sky can move it again.
##
## 7:00 is morning proper rather than 6:00 dawn: the sun is up and low, which is the best
## light the arena gets, and it leaves thirteen of the fourteen daylight hours ahead - close
## to a full day_real_minutes before the first night falls.
##
## The .tscn still carries a matching value so the EDITOR preview is not night either. This
## one is what the game actually uses, the same split DayNightPacing documents for
## minutes_per_day.
@export var day_start_hour: float = 7.0

# ============================================================
# CRYSTAL
# ============================================================
@export var crystal_max_hp: float = 1000.0

# ============================================================
# PLAYER
# ============================================================
@export var player_max_hp: float = 100.0
## How many players the map spawns. 1 is single-player; the lobby will set this once
## Phase 1 of docs/MULTIPLAYER_PLAN.md lands. Everything downstream already scales -
## enemy damage, target selection and the Upkeep vote threshold all read the count.
@export var player_count: int = 1
## Matched to what the animation pack was authored for, rather than chosen first and
## patched over afterwards. run_forward covers 2.47 m/s at its own recorded speed, so
## moving at 2.5 plays that cycle at 1.0x - the legs turn over exactly as animated,
## with no stretching and no sliding.
##
## This is a large cut from the original 6.0, and it is the whole cost of playing the
## clips untouched: a 144 m lane now takes about a minute to cross on foot. Raising it
## does not break anything, it just reintroduces sped-up playback in proportion.
@export var player_base_speed: float = 2.5
@export var player_sprint_speed_mult: float = 1.5
@export var player_jump_velocity: float = 4.5
## The crouch before a jump leaves the ground, real seconds at most (PlayerAnimator.begin_jump):
## the clip's own run-up is squeezed into this and the body's arc starts on its take-off frame.
## Short, because it is time between the press and the jump.
@export var player_jump_runup: float = 0.12
## How fast the jump clip's own landing plays once the feet are down, x its natural pace.
@export var player_jump_landing_pace: float = 1.2
## Out of the world (Player._is_out_of_world): below this height, or further than this from
## the centre along either axis, a player is put back at their seat by the crystal. The
## lowest ground is about -10 m and the MapBounds fence stands at 250 m.
@export var player_out_of_world_y: float = -30.0
@export var player_out_of_world_extent: float = 270.0
## Seconds of invulnerability after being put back, so the landing is not a hit.
@export var player_out_of_world_grace: float = 2.0
@export var player_mouse_sensitivity: float = 0.002
@export var player_gamepad_look_sensitivity: float = 2.5
## The player's own look preferences, from the Controls tab (UserSettings loads and saves
## them). The two scales multiply the base sensitivities above, so 1.0 is the tuned feel.
@export var mouse_sensitivity_scale: float = 1.0
@export var gamepad_look_sensitivity_scale: float = 1.0
@export var invert_look_y: bool = false
## Harvesting by hand, at a well, the way a myr does it: hold to take ONE mana, carry it,
## and it only counts once it is delivered to the crystal (within player_base_proximity).
## Standing at a well holding the key used to bank mana on the spot, again and again, which
## out-earned the myrs it was meant to sit beside. Held, not pressed, and it breaks the
## moment the player moves (see Player._update_mana_harvest).
@export var player_mana_harvest_distance: float = 6.0
@export var player_mana_harvest_time: float = 3.0
## What one delivered load banks, in the well's own colour.
@export var player_mana_harvest_amount: int = 1

# --- DOWNED / REVIVE ---
## Multiplayer: how long a downed player can be picked up before they respawn at the
## base. The clock keeps running while a teammate channels - help that arrives too
## late arrives too late.
@export var player_downed_duration: float = 20.0
## Solo there is nobody to channel, so the downed state is only a short death penalty.
@export var player_downed_solo_duration: float = 5.0
## The helper's channel. Broken by the HELPER moving, attacking or casting - not by
## taking damage, so rescues under fire stay possible.
@export var player_revive_channel_time: float = 3.0
@export var player_revive_range: float = 3.0
@export var player_base_proximity: float = 5.0
## How far from the crystal each player's spawn point sits.
##
## Players used to spawn at the world origin - solo literally at Vector3(0, 1, 0), which is
## INSIDE the crystal, and in a party on a 2.5-unit ring that is still inside its visual. The
## five points are now one per lane, so everyone starts facing the direction their enemies
## come from and nobody starts embedded in the objective.
##
## Must stay below player_base_proximity: spawning outside it would open a run with the "Press
## E to Manage Base" prompt already gone, and the first thing a player does is shop.
@export var player_spawn_ring_radius: float = 4.2
## Myrs only, for the same reason - the player never carries anything now.
@export var player_carry_speed_penalty: float = 0.5
@export var player_base_hp_regen: float = 1.0

# ============================================================
# PLAYER CAMERA
# ============================================================
## Classic over-the-shoulder third person. The offset shifts the whole orbit to the
## player's right so the character sits left of screen centre and the aim line stays
## clear; the height is the point the camera orbits around; the distance is the
## SpringArm3D's length, which still shortens automatically when geometry gets
## between the camera and the player.
##
## Pulled in from 4.5 on 2026-08-30. The offset and height are not guesses: 0.85 at
## 3.2 reproduces the 15-degree off-axis angle the old 1.2-at-4.5 rig framed the
## character with, and 1.80 is what that rig's orbit height actually was once the
## spring arm's own hidden +0.2 is folded in. So this is the same shot, just nearer.
@export var player_camera_shoulder_offset: float = 0.85
@export var player_camera_height: float = 1.80
@export var player_camera_distance: float = 3.2
## Ctrl + mouse wheel zoom: the nearest and farthest the camera goes, and one notch.
@export var camera_zoom_min: float = 2.2
@export var camera_zoom_max: float = 5.5
@export var camera_zoom_step: float = 0.4
## Degrees added to the field of view while sprinting, and while dashing or leaping.
@export var camera_sprint_fov_add: float = 6.0
@export var camera_dash_fov_add: float = 11.0
## The view dips on landing: metres per m/s of fall speed, and at most.
@export var camera_land_dip_per_speed: float = 0.035
@export var camera_land_dip_max: float = 0.3
## Depth of field in play (High preset and up): sharp to this many metres, softening over
## the transition, at this strength - subtle, or the map reads as a miniature.
@export var camera_dof_far_distance: float = 45.0
@export var camera_dof_far_transition: float = 30.0
@export var camera_dof_far_amount: float = 0.06
## How strongly the scene behind an open menu is blurred.
@export var camera_menu_blur_amount: float = 0.16
## Hit-stop (Player._hit_stop): real seconds the world holds when a blade connects, light and
## heavy, how slow it runs meanwhile, and the gap before the next stop can start.
@export var hit_stop_enabled: bool = true
@export var hit_stop_light: float = 0.045
@export var hit_stop_heavy: float = 0.08
@export var hit_stop_time_scale: float = 0.05
@export var hit_stop_cooldown: float = 0.06

## How far, in degrees, the crosshair may sit off an enemy's body and still pick it for a
## single-target spell (Kill, Contagion). Small on purpose: this forgives a twitchy mouse on
## a distant target, it does not choose one - the old 57-degree cone is how Kill used to
## take whichever enemy happened to be beside the one in the sights.
@export var player_aim_assist_degrees: float = 4.0
## Furthest a client's aim ray may start from its own character before the server ignores
## it and falls back on its own copy of that camera. The real rig sits ~3.5 m back.
@export var player_aim_origin_max_offset: float = 8.0

# ============================================================
# PLAYER ANIMATION
# ============================================================
## Seconds of uninterrupted standing still before the player plays one of the
## "idle looking" variations instead of the plain idle loop.
@export var player_idle_variation_delay_min: float = 8.0
@export var player_idle_variation_delay_max: float = 16.0
## How far a locomotion clip may be sped up or slowed down to match real velocity
## before the feet start reading as skating either way.
@export var player_locomotion_speed_min: float = 0.6
## 1.5 rather than the old 1.8 or the 2.6 that a 5 m/s base needed. With base speed
## matched to the clips, ordinary movement and blocking both land on 1.0x and never
## come near this; it exists for sprint, which at 1.5x base wants exactly 1.5x playback
## - a genuine sprint turning the legs over faster, not a walk pretending to be one.
@export var player_locomotion_speed_max: float = 1.5
## Cross-fade lengths. Locomotion changes often, so it gets the longer blend;
## a strike has to land on the frame it says it does.
@export var player_anim_blend_locomotion: float = 0.16
## Long enough that one swing chaining into the next reads as a blend rather than a
## snap, short enough that a strike still lands on the frame it says it does.
@export var player_anim_blend_action: float = 0.12
## Time constant for easing the locomotion blend point toward where the player is actually
## going. The point is derived from post-collision velocity, which carries floor-snap and
## wall-slide noise, and a strafe turning into a forward run should read as a weight shift
## rather than a snap. Short enough that it never lags behind the stick in a way anyone feels.
@export var player_anim_blend_point_smoothing: float = 0.09
## Footstep detection (PlayerAnimator._track_footfalls), as a foot's clearance in metres:
## the lower of its heel and its toe above the ground. A foot counts as LANDED once it
## comes below the first and as lifted again only above the second.
##
## Measured off the clips, where both were chosen: a planted foot sits at 0-0.5 cm, but
## the sidestep in walk_left only lifts its trailing foot 3.7 cm, so a lift threshold much
## above 2.5 cm misses every other step there. With this pair all six walk and run cycles
## land exactly two steps each, on the frame heel or toe touches down.
##
## Both are measured above the foot's own floor in the clips playing, not above zero (see
## PlayerAnimator._gait_foot_floor): the archer's clips set a foot down up to 2.7 cm up.
@export var player_footstep_plant_height: float = 0.01
@export var player_footstep_lift_height: float = 0.025
## The soonest a footstep may follow the one before it, as a fraction of the current stride
## (both feet). Real steps come half a stride apart - 0.38 / 0.62 on the most lopsided
## clip, the back-pedal - while a toe brushing the ground mid-swing on a blended gait comes
## about 0.25-0.28 after the other foot's landing. A third sits between the two.
@export var player_footstep_min_stride_fraction: float = 0.33

# ============================================================
# PLAYER MELEE COMBO
# ============================================================
## One stage of the light attack chain occupies this long; the stage is speed-scaled
## onto it, so a full chain runs one of these per click regardless of how the clip
## splits up.
@export var player_swing_duration: float = 0.5
## Swings fire when the attack button is RELEASED. A release before this counts as a
## tap and swings light; at or after it, heavy. Nothing is in flight while the button
## is down, so unlike the old fire-on-press scheme this has no upper bound tied to
## the swing's impact frame - it only has to be long enough that a deliberate tap
## does not overshoot it.
@export var player_heavy_hold_time: float = 0.25
## How long a resolved swing waits for the combo window to open before it is dropped.
## Without this, releasing a fraction too early is silently ignored and the chain
## feels like it is eating inputs.
@export var player_attack_buffer_time: float = 0.25
## The last FRACTION of a swing during which another attack chains instead of being
## dropped. Every chained swing cuts the one before it short at exactly this point,
## so a wide window throws the follow-through away on every hit of a combo: at 0.5
## the swing was cut the instant it landed, which read as the animations being
## truncated. 0.3 lets ~70% of each swing play. It costs nothing in feel because
## player_attack_buffer_time already holds an early release until the window opens.
@export var player_combo_window: float = 0.30
## SECONDS after a swing ends that the recorded combo symbols survive. Kept separate
## from player_combo_window, which is a fraction - the two used to be added together,
## mixing units.
@export var player_combo_grace: float = 0.45
## The heavy attack is a full 360 spin (1.22s of usable clip) rather than a single
## chop, so it gets its own, longer commitment instead of the light chain's cadence.
@export var player_heavy_duration: float = 0.9
@export var player_heavy_damage_mult: float = 2.0
@export var player_heavy_knockback: float = 12.0
## Damage multiplier on the THIRD stage of the light chain, which only exists once
## the chain extension has been bought in the skill tree.
@export var player_combo_finisher_damage_mult: float = 1.5
## Skill points the tree charges for that extension.
@export var skill_point_cost_melee_combo: int = 3
## Legacy mana price, kept only so old saves and the tree's display do not break.
@export var melee_combo_unlock_cost: int = 12
## Seconds taken off every spell cooldown by each melee impact frame that connects.
## This is the melee/spell interlock: swinging between casts brings them back faster.
## Paid per impact frame, so a stage that lands two of them refunds twice over. A
## whiff refunds nothing. The kick's own cooldown is never refunded (see
## Player._reduce_spell_cooldowns).
@export var melee_hit_cooldown_reduction: float = 0.35

## Movement multiplier during a light attack STARTED ON THE MOVE, which is the only
## melee move the player can walk through - it plays on the upper body while the legs
## keep their walk cycle. A light attack started standing still takes the whole body
## and holds the player there instead, as do heavy attacks, kicks and staggers (see
## MeleeKit._advance_light_chain and Player._begin_action).
@export var player_attack_move_mult: float = 1.0

# ============================================================
# ERROR REPORTS
# ============================================================
## Whether ErrorReporter sends crash and error reports to the Firebase project
## (crash_reports/). Its local log in user://error_reports/ is written either way.
@export var error_reports_upload: bool = true
## Exported builds upload; runs from the editor binary - the editor, the validation suite,
## tool scenes - only keep their reports locally unless this is on, so that testing the
## reporter itself does not need an export.
@export var error_reports_upload_from_editor: bool = false

# ============================================================
# SOUND EFFECTS
# ============================================================
## Voices SoundBank keeps alive. Positional ones carry world impacts; the flat ones
## are for the few events with no place on the map. A wave lands far more hits than
## this per second, but they overlap for a fraction of a second each - the pool only
## has to cover that overlap, and the oldest voice is recycled past it.
@export var sfx_positional_voices: int = 16
@export var sfx_flat_voices: int = 4
@export var sfx_volume_db: float = -6.0
@export var music_enabled: bool = true
@export var music_volume_db: float = -6.0
## Random detune either side of 1.0, so a handful of recordings survive being heard
## thousands of times without reading as a loop.
@export var sfx_pitch_jitter: float = 0.08
## Minimum gap between two triggers of the SAME event. Thirty enemies connecting on
## one frame is one impact sound, not thirty stacked into a clipping mess.
@export var sfx_min_retrigger: float = 0.05
## The same, for events that share a clock (SoundBank.RETRIGGER_GROUPS) - the aura orbs.
## Long enough that three orbs firing together are heard as one shot.
@export var sfx_group_min_retrigger: float = 0.35
## Beyond this the sound is inaudible; unit_size sets how quickly it falls off on
## the way there.
@export var sfx_max_distance: float = 45.0
@export var sfx_unit_size: float = 8.0
## Overlapping plays allowed on a voice an emitter owns (SoundBank.play_from) - the
## footsteps. Two is a step plus the tail of the one before it.
@export var sfx_emitter_voice_polyphony: int = 2
## A sustained ambience sits under the action rather than in it, so it is quieter
## than an impact - but it carries further, because it is what tells the player
## where the crystal is from across the map.
@export var sfx_ambience_volume_db: float = -14.0
@export var sfx_ambience_max_distance: float = 70.0

# --- Sounds the whole map hears ---
#
# The lane spawners sit at radius 179 from the crystal, so two opposite ones are ~341
# units apart. At the ordinary sfx_max_distance of 45 a boss arriving in the red lane is
# not quiet from the crystal, it is SILENT - which is what these numbers fix.
#
# Still positional, deliberately: it matters WHICH lane the boss came from, and a flat 2D
# sound throws that away. What changes is only how far the falloff reaches.
@export var sfx_global_max_distance: float = 420.0
## unit_size is the distance at which attenuation starts biting. INVERSE_DISTANCE
## attenuates roughly by unit_size/distance, so 110 over the 341-unit worst case leaves
## about -10 dB - clearly audible, still obviously far away.
@export var sfx_global_unit_size: float = 110.0
## Voices held back for these events. A boss arrival is 4.5 seconds long and the ordinary
## pool is round-robin: during a wave, sixteen impacts recycle every voice in well under
## that, and the arrival gets cut off mid-roar. A sound nobody hears the end of is not
## much better than one nobody hears at all.
@export var sfx_global_voices: int = 3

## The kick a fireball detonation gives the camera. Still under the leap's slam - a
## fireball usually goes off across the map rather than under the player's feet - but
## well above a melee hit, because it is a detonation and should read as one.
@export var spell_red_fireball_shake_strength: float = 0.45
@export var spell_red_fireball_shake_duration: float = 0.35

# ============================================================
# GREEN: TITANIC BRAWL
# ============================================================
## The launch impulse. The forward speed is worked out per leap from the distance to the
## crosshair (see spell_green_leap_range below); the rise is
## tuned against the clip rather than to taste - the jump_attack clip lands its slam
## at 79% of a 1.1s cast, i.e. 0.87s in, and at the engine's 9.8 gravity an initial
## 4.25/s puts the character back on the floor at exactly that moment. Retune it
## alongside spell green_1's cast_duration, never on its own.
@export var spell_green_leap_rise: float = 4.25
## How far the leap can carry, at rank 1 and at max rank. It lands under the crosshair
## within that reach (SpellEffects.cast_green_titanic_leap); the old fixed leap covered
## about 9.5 m (leap_speed over the 0.87 s flight). The minimum stops a crosshair at the
## caster's feet from turning the leap into a hop on the spot.
@export var spell_green_leap_range: float = 10.0
@export var spell_green_leap_range_max: float = 18.0
@export var spell_green_leap_range_min: float = 2.5
## How long the player's own movement input stays suspended. Ends early at the slam.
@export var spell_green_leap_duration: float = 1.1
## The slam. Heavy single-target damage spread over an area, which is what makes it
## worth a leap rather than a swing.
@export var spell_green_leap_damage: float = 90.0
@export var spell_green_leap_radius: float = 6.0
## How hard the slam throws, for a caster with player_max_hp; scaled by the caster's actual
## max HP. Straight up at the centre (12 lifts about 2.4 m against the knockback's own 30 m/s2
## braking), sideways at the edge (SpellEffects._slam_ground).
@export var spell_green_leap_knockback: float = 12.0
## The hardest shake in the game, and the only one the player lands on themselves:
## the slam happens directly under the camera, so it can carry more than a detonation
## going off at range without reading as a glitch.
@export var spell_green_leap_shake_strength: float = 0.75
@export var spell_green_leap_shake_duration: float = 0.45

# ============================================================
# PLAYER KICK
# ============================================================
@export var spell_melee_kick_damage: float = 12.0
@export var spell_melee_kick_range: float = 2.6
@export var spell_melee_kick_knockback: float = 14.0
@export var spell_cooldown_kick: float = 1.5

# ============================================================
# PLAYER BLOCK
# ============================================================
## Fraction of incoming damage a successful block removes.
@export var player_block_damage_reduction: float = 0.8
## Minimum dot() between the player's facing and the direction to the attacker for
## a hit to count as coming from the front. 0.35 is roughly a 140-degree arc.
@export var player_block_cone: float = 0.35
@export var player_block_speed_mult: float = 0.4

## Movement while a fight is still live, as a fraction of base speed.
##
## Exists because the animation follows the same rule: mid-fight the legs stay on the
## armed walk cycle, which covers 0.99 m/s. Running at full base speed on a walk cycle
## is exactly the foot-sliding this pass set out to remove, so combat movement is
## brought down to meet the clip rather than the clip stretched to meet it.
@export var player_combat_speed_mult: float = 0.45

## How long after the last swing, cast or block the player still counts as fighting.
## Long enough that walking between two hits does not flicker back to the travel run,
## short enough that leaving a fight lets you break into a run promptly.
@export var player_combat_linger: float = 0.5
## Bosses swing straight through a guard - blocking one does nothing.
@export var player_block_ignores_boss: bool = true
## How long the guard-flinch clip is squeezed into. Does not take control away -
## the player keeps blocking through it.
@export var player_block_react_duration: float = 0.35

# ============================================================
# CHARACTER CLASSES - docs/CHARACTER_CLASSES_PLAN.md
# ============================================================
## The team levels the four class skills unlock at, shared by every class: a basic-attack
## passive, then the active (or the defence) the class most needs, a second passive, and a
## capstone. Derived from the level, never bought or saved.
@export var class_skill_levels: Array[int] = [3, 6, 10, 14]

# --- Archer: the bow (BowKit) ---
## The draw from the quiver to the anchor at the cheek. A press released before it ends
## still shoots - at the end of the draw, as a quick shot - so this is also how long a
## tap takes to leave the bow.
@export var archer_draw_time: float = 0.42
## How long the anchor has to be held on top of the draw to reach a full draw. Damage
## grows from the quick shot's to the full draw's over it.
@export var archer_full_draw_time: float = 0.9
## Arrow damage as multiples of spell_melee_damage, so the bow moves with the axe when the
## melee number is retuned. A tap is weaker than an axe swing and a full draw much
## stronger: the archer earns its damage by standing still and holding.
@export var archer_quick_shot_damage_mult: float = 0.75
@export var archer_full_draw_damage_mult: float = 2.4
## How long the release and recoil play, i.e. how soon the next draw can start.
@export var archer_shoot_duration: float = 0.32
## Movement while drawing or holding, as a fraction of base speed: the archer can
## reposition with an arrow nocked, but not run.
@export var archer_draw_move_mult: float = 0.55
## The camera zooms in over the draw (BowKit.aim_zoom): its field of view at a full draw, as
## a fraction of the normal one, and how fast it eases in and back out (per second, higher
## is snappier). Out is faster than in, so the release lets go with the arrow.
@export var archer_aim_zoom_fov_mult: float = 0.7
@export var archer_aim_zoom_in_rate: float = 6.0
@export var archer_aim_zoom_out_rate: float = 14.0
## The spine turns the nocked arrow onto the crosshair (BowAim): how fast it turns back out
## after the shot (full turn per second - it turns in with the draw itself), and the most it will twist sideways and bend up or down,
## degrees - past those the arrow points as near as it can rather than folding the archer.
@export var archer_aim_blend_rate: float = 6.0
@export var archer_aim_max_yaw_degrees: float = 70.0
@export var archer_aim_max_pitch_degrees: float = 55.0
## Metres per second. Fast enough to read as an arrow, slow enough to see it fly.
@export var archer_arrow_speed: float = 55.0
@export var archer_quick_arrow_speed_mult: float = 0.75
## A full draw flies flatter; a quick shot drops a little over distance.
@export var archer_arrow_gravity: float = 2.5
@export var archer_arrow_range: float = 70.0
## Knockback of an arrow is a nudge - it is the axe that throws enemies around.
@export var archer_arrow_knockback: float = 2.0
## How long a spent arrow stays stuck in the ground or a wall.
@export var archer_arrow_stuck_lifetime: float = 4.0

# --- Archer: the defence (DodgeRoll) ---
## The roll is the pack's dodge clip for the way it goes, up to where its hop has landed, and
## the body follows that hop (DodgeRoll). The clips hop 1.9-2.3 m in 0.85-1.0 s; the distance
## stretches that (past ~1.4x the feet visibly slide), the pace plays it quicker - at 1.5 a
## roll takes about 0.6 s. It used to be 4.2 m in 0.42 s at a constant speed, far past
## anything the clip could show: what played was the run, sped up, under a flicker of dodge.
@export var archer_dodge_distance: float = 3.0
@export var archer_dodge_pace: float = 1.5
## Untouchable for this much of the roll, from its start.
@export var archer_dodge_invulnerable_time: float = 0.32
@export var archer_dodge_cooldown: float = 1.1

# --- Archer: class body ---
## The most fragile class (docs/CHARACTER_CLASSES_PLAN.md): less health than the warrior,
## clearly quicker on its feet.
@export var archer_health_mult: float = 0.8
@export var archer_speed_mult: float = 1.25

# --- Archer: class skills ---
## Longshot (level 3): a FULL draw passes through this many enemies before it stops.
@export var archer_longshot_pierce: int = 3
## Disengage (level 6): a long roll backwards, leaving a snare where you stood. Its
## cooldown and cast length are on its ClassDatabase row, like a spell's.
@export var archer_disengage_distance: float = 8.0
@export var archer_disengage_snare_radius: float = 3.5
@export var archer_disengage_snare_duration: float = 4.0
@export var archer_disengage_snare_slow_mult: float = 0.35
## Arrow Volley Trap (level 10): arrows rain on the aimed-at ground for a few seconds.
@export var archer_volley_radius: float = 5.0
@export var archer_volley_duration: float = 3.0
## Damage per second to everything inside, as a multiple of spell_melee_damage.
@export var archer_volley_dps_mult: float = 1.6
@export var archer_volley_range: float = 45.0
## Deadeye (level 14): an arrow that lands on the top of an enemy's body - its head -
## deals this much more. The share of the body's height that counts as the head:
@export var archer_deadeye_damage_mult: float = 2.0
@export var archer_head_fraction: float = 0.22

# --- Barbarian: the two-hander (GreatswordKit) ---
## How fast the light chain's cleaves play, as a share of the Great Sword pack's own pace:
## 1 is exactly as fast as the clip - which is also how far the body walks with each cut, so
## the feet stay planted at any pace. About a second a cut.
@export var barbarian_cleave_pace: float = 1.0
## A cleave's damage as a multiple of spell_melee_damage. Set so the barbarian's light attack
## deals what the warrior's does PER SECOND on one enemy: the cleaves come about half as often
## as the axe's cuts, so each one hits about twice as hard (tools/tests/melee_dps.tscn, attack
## tapped as fast as it chains: warrior 54.5 a second, barbarian 29.8 at 1.5 -> 2.75). Its
## wider arc and reach are what it gains against a crowd.
@export var barbarian_cleave_damage_mult: float = 2.75
## Reach in metres and the arc a swing covers: a hit lands on an enemy when the dot of the
## facing and the direction to it is above this (spell_melee_cone is the axe's 0.5, about
## 60 degrees either side; 0.15 is about 80).
@export var barbarian_reach: float = 4.2
@export var barbarian_cone: float = 0.15
## The heavy: holding past player_heavy_hold_time sets off its two swings at once, as the
## warrior's spin is set off - no charging. The first swing's damage as a multiple of
## spell_melee_damage, and the second's as a share of the first. Set so held heavies deal what
## the warrior's spins do a second (tools/tests/melee_dps.tscn: 26.0 at 2.6, warrior 33.3).
@export var barbarian_heavy_damage_mult: float = 3.3
@export var barbarian_heavy_second_swing_share: float = 0.6
## How fast the heavy plays, as a share of the clip's own pace - 1 is exactly as fast as the
## clip, which is also how far the body steps in with it. At 1.4 the two swings and the lift
## back to the shoulder take about 2.9 s.
@export var barbarian_heavy_pace: float = 1.4
@export var barbarian_heavy_knockback: float = 16.0
## The whoosh of every barbarian swing is timed to the blade: its loudest moment lands on the
## measured impact, when the sword is at its fastest. This moves it, in seconds: positive is
## that much EARLIER than the blade, negative later. 0 is together.
@export var barbarian_whoosh_lead: float = 0.0

# --- Barbarian: class body ---
## The heaviest class (docs/CHARACTER_CLASSES_PLAN.md): more health than the warrior,
## slower on its feet. No block - a heavy swing cannot be interrupted instead.
@export var barbarian_health_mult: float = 1.3
@export var barbarian_speed_mult: float = 0.9

# --- Barbarian: class skills ---
## Brute Force (level 3): the heavy's knockback is multiplied by this, and lands before
## the blow - so what the blow kills is thrown by it, and thrown hardest.
@export var barbarian_brute_force_knockback_mult: float = 1.8
## Whirlwind (level 6): spinning with the sword held out, hitting everything around every
## hit interval. Its cooldown and length are on its ClassDatabase row, like a spell's.
@export var barbarian_whirlwind_radius: float = 3.6
@export var barbarian_whirlwind_hit_interval: float = 0.4
## Damage per hit, as a multiple of spell_melee_damage.
@export var barbarian_whirlwind_damage_mult: float = 0.9
@export var barbarian_whirlwind_knockback: float = 5.0
## The share of the barbarian's speed left to them while spinning, and how many whole turns
## the spin makes over its length.
@export var barbarian_whirlwind_move_mult: float = 0.8
@export var barbarian_whirlwind_turns: float = 4.0
## Berserk (level 14): for the duration, swings this much faster and this much harder - and
## every hit taken this much harder too, the barbarian's version of "no block at all".
@export var barbarian_berserk_duration: float = 8.0
@export var barbarian_berserk_attack_speed_mult: float = 1.4
@export var barbarian_berserk_damage_mult: float = 1.35
@export var barbarian_berserk_damage_taken_mult: float = 1.25

# --- Warrior: class skills (ClassDatabase, WarriorSkills) ---
## Bloodthirst (level 3): a kill by the axe heals this share of the warrior's max health, and the
## chain's next stage plays this many times faster.
@export var warrior_bloodthirst_heal: float = 0.03
@export var warrior_bloodthirst_haste: float = 1.3
## Hurl Axe (level 6): the axe flies this far and this fast, out and back, and hits everything
## within the radius of it on each leg for this multiple of spell_melee_damage. Its cooldown is
## on its ClassDatabase row, like a spell's.
@export var warrior_hurl_axe_range: float = 11.0
@export var warrior_hurl_axe_speed: float = 20.0
@export var warrior_hurl_axe_radius: float = 1.5
@export var warrior_hurl_axe_damage_mult: float = 1.6
## Battle Frenzy (level 14): for this long, a chain that keeps connecting does not end - past its
## last stage the finisher comes again (MeleeKit).
@export var warrior_battle_frenzy_duration: float = 6.0

# --- Knight: sword and shield (KnightKit) ---
## A light cut's and the heavy's damage, as multiples of spell_melee_damage. The knight is the
## tank: set so it deals about 85% of what the warrior does a second on one enemy
## (tools/tests/melee_dps.tscn), paid for by the guard below and the bigger body. A cut of the
## chain is this times its share of the chain (KnightKit._stage_share) - the quick first cut
## less, the closing leap and slam more. At 2.3 it dealt 55.0 a second tapping, 38.6 letting
## each cut play out and 28.6 holding for heavies (2.6), against the warrior's 54.5, 34.8, 33.3;
## 1.95 brings the first two to 46.7 and 32.7.
@export var knight_cut_damage_mult: float = 1.95
@export var knight_heavy_damage_mult: float = 2.6
## How fast the chain's cuts and the heavy play, as a share of the pack's own pace (1 = the clip's).
@export var knight_cut_pace: float = 1.0
@export var knight_heavy_pace: float = 1.0
## The whoosh of every knight swing is timed to the blade, as the barbarian's is: this moves its
## loudest moment earlier (positive) or later (negative) than the blade at its fastest.
@export var knight_whoosh_lead: float = 0.0

# --- Knight: the guard (KnightGuard) ---
## The shield stops nearly everything: this much of a hit from in front, against the warrior's
## player_block_damage_reduction - and a boss's too, which goes straight through the axe's guard.
@export var knight_block_damage_reduction: float = 0.95
## How far round the shield covers: a hit is blocked when the dot of the facing and the
## direction to the attacker is at least this (the warrior's player_block_cone is 0.35; 0 is
## the whole front half).
@export var knight_block_cone: float = 0.0

# --- Knight: class body ---
## The tank (docs/CHARACTER_CLASSES_PLAN.md): the most health of any class, a little slower.
@export var knight_health_mult: float = 1.4
@export var knight_speed_mult: float = 0.95

# --- Knight: class skills ---
## First Strike (level 3): after the shield stops a hit, the knight's next swing - if it comes
## within the window - plays this much faster and hits this much harder: the riposte.
@export var knight_first_strike_window: float = 1.5
@export var knight_first_strike_pace_mult: float = 1.6
@export var knight_first_strike_damage_mult: float = 1.75
## Shield Bash (level 6): a thrust of the shield into everything in front, within the range and
## the cone: damage as a multiple of spell_melee_damage, a shove and a stun. Its cooldown and
## length are on its ClassDatabase row, like a spell's.
@export var knight_bash_range: float = 3.2
@export var knight_bash_cone: float = 0.3
@export var knight_bash_damage_mult: float = 1.2
@export var knight_bash_knockback: float = 12.0
@export var knight_bash_stun: float = 1.2
## Shield Wall (level 10): a hit blocked within this many seconds of the shield coming up is a
## perfect block, and stuns whoever struck it for the second number.
@export var knight_perfect_block_window: float = 0.35
@export var knight_perfect_block_stun: float = 1.5
## Phalanx (level 14): while the knight holds the shield up, allies and myrs within the radius
## and BEHIND the knight take this share of their damage, and enemies within the taunt radius
## turn on the knight (renewed while the guard is up).
@export var knight_phalanx_radius: float = 6.0
@export var knight_phalanx_damage_taken_mult: float = 0.6
@export var knight_phalanx_taunt_radius: float = 8.0
@export var knight_phalanx_taunt_duration: float = 1.5

# --- Mage: the bolts (MageKit) ---
## How long one bolt's throw plays, seconds - the cadence of a tap. The three throws are
## squeezed into it whatever their own length, so a bolt always leaves at the same beat.
@export var mage_bolt_duration: float = 0.55
## A bolt's damage as a multiple of spell_melee_damage. Set like the archer's quick shot: a
## ranged basic attack deals well under the axe a second (the mage's damage is its spells).
@export var mage_bolt_damage_mult: float = 0.65
## Metres per second, and how far a bolt flies before it fades. Straight - no drop.
@export var mage_bolt_speed: float = 42.0
@export var mage_bolt_range: float = 50.0
@export var mage_bolt_knockback: float = 1.5
## Movement while throwing a bolt, as a fraction of base speed: the mage walks while it
## casts, but does not run.
@export var mage_bolt_move_mult: float = 0.7
## The heavy - holding past player_heavy_hold_time - is the Arcane Blast: a slower orb that
## bursts on whatever it meets, hitting everything in the radius. Rooted, both hands.
@export var mage_blast_duration: float = 0.95
@export var mage_blast_damage_mult: float = 1.9
@export var mage_blast_radius: float = 2.6
@export var mage_blast_speed: float = 26.0
@export var mage_blast_knockback: float = 7.0

# --- Mage: the defence (Blink) ---
## The block button blinks the mage this far the way the stick points (backwards with none),
## stopping short of anything solid. Untouchable for a moment as it arrives.
@export var mage_blink_distance: float = 6.0
@export var mage_blink_invulnerable_time: float = 0.3
@export var mage_blink_cooldown: float = 2.5

# --- Mage: class body ---
## The other fragile class (docs/CHARACTER_CLASSES_PLAN.md): the least health of any class,
## a little quicker than the warrior; the blink is what keeps it alive.
@export var mage_health_mult: float = 0.75
@export var mage_speed_mult: float = 1.1

# --- Mage: class skills ---
## Prowess (level 3): every colour spell cast gives a charge, up to the most below; each bolt
## or blast spends one and hits this much harder. Charges are lost this many seconds after the
## last spell, so it rewards weaving spells and bolts rather than banking them.
@export var mage_prowess_max_charges: int = 3
@export var mage_prowess_damage_mult: float = 2.0
@export var mage_prowess_window: float = 10.0
## Blink of an Eye (level 6): a long blink to the aimed ground, leaving an illusion of the
## mage where they stood. Enemies within the taunt radius turn on it; it lasts the duration
## or until its health is spent. Cooldown on its ClassDatabase row, like a spell's.
@export var mage_blink_of_an_eye_range: float = 14.0
@export var mage_decoy_duration: float = 5.0
@export var mage_decoy_health_mult: float = 0.6
@export var mage_decoy_taunt_radius: float = 9.0
## Spell Mastery (level 10): every colour spell holds this many charges. Mechanical, not a
## cooldown cut - blue's affinity is the one place cooldowns get shorter (docs/SKILL_DESIGN.md,
## "One number, one node"): the spell still recovers one charge per cooldown, it can only be
## cast again at once.
@export var mage_spell_mastery_charges: int = 2

# ============================================================
# PLAYER HIT REACTION
# ============================================================
## A hit only staggers the player when it takes at least this fraction of max HP in
## one go; chip damage would otherwise leave the character permanently flinching.
@export var player_hit_react_damage_pct: float = 0.12
## Minimum gap between staggers, so a burst of large hits can't lock the player out.
@export var player_hit_react_cooldown: float = 1.2
## How long a stagger takes control away. The raw reaction clips run 1.0-1.8s,
## which would be punishing; they get squeezed into this instead.
@export var player_hit_react_duration: float = 0.55

# ============================================================
# PLAYER SPELLS
# ============================================================
@export var spell_melee_range: float = 3.5
@export var spell_melee_cone: float = 0.5
@export var spell_melee_damage: float = 20.0
@export var spell_melee_knockback: float = 6.0
@export var skill_unlock_cost: int = 1
@export var spell_stab_debuff_damage: float = 5.0
@export var spell_stab_debuff_duration: float = 8.0
@export var spell_unsummon_teleport_distance: float = 15.0

# Infinite color affinity ranks, each with diminishing returns towards a ceiling.
@export var affinity_rank_mana_cost: int = 1
## Affinity bonuses, per colour (see GameSettings.affinity_bonus). The ranks never end, so a
## flat share per rank - 10% each, until 2026-10-11 - always ran away: rank 10 was twice the
## spells (blue), double damage (red), and full lifesteal on everything (black). Now the
## first rank gives `affinity_first_rank` and every rank after closes the same share of the
## remaining gap to `affinity_cap`:
##   white  max HP regenerated per second, on top of player_base_hp_regen  0.6% .. 3%/s
##          (it was +10% of a 1 HP/s base - two HP a second at rank 10, which bought nothing)
##   blue   faster cooldown recovery                                       8%  .. 40%
##   black  lifesteal, from BASIC ATTACKS only - sword swings and the kick;  5%  .. 30%
##          spells, auras and Green Leap do not count
##   red    total damage                                                   10% .. 50%
##   green  maximum HP                                                     10% .. 50%
## Roughly a third of the ceiling at rank 5 and nine tenths of it at rank 10.
@export var affinity_first_rank: Dictionary = {"white": 0.006, "blue": 0.08, "black": 0.05, "red": 0.10, "green": 0.10}
@export var affinity_cap: Dictionary = {"white": 0.03, "blue": 0.40, "black": 0.30, "red": 0.50, "green": 0.50}
## How much a player must have INVESTED IN A COLOUR to reach its Nth tier of spell, and
## its Nth rank of any of them. One ladder for both, because unlocking and deepening are
## the same question asked twice - "how committed are you to this colour" - and answering
## it with two unrelated systems is what made the old tree hard to reason about.
##
## Investment is counted by Player.color_investment: the colour's affinity ranks plus every
## rank held in its five spells. Not the affinity node alone - a player who has poured six
## points into Fireball has committed to red whether or not they bought a second affinity
## rank, and the ladder should see that.
##
## This REPLACED a team-level gate. The old rule froze a player out of their own colour on
## a clock they could not influence; this one is entirely in their hands, which is why the
## numbers can be this steep.
@export var color_investment_ladder: Array[int] = [1, 2, 5, 7, 10]
## What a colour needs invested before a spell of ring 1, 2 or 3 (SpellDatabase.RINGS) can be
## bought - and, met, what reveals that ring without a neighbour being owned. The ladder above
## still gates every rank after; a spell takes whichever of the two is higher. Gates are on
## the colour as a whole, never on a particular skill: nothing is anything's prerequisite.
## Points arrive one per team level (~30 a run) plus Upkeep, so ring 3 at 9 is about a quarter
## of the way into a run spent mostly in one colour.
@export var color_ring_investment: Array[int] = [1, 4, 9]
@export var aura_skill_point_cost: int = 3
## Guild nodes (docs/GUILD_PLAN.md Stage 1): how much BOTH neighbouring colours need
## invested before one is reachable. Matches color_investment_ladder's own step 3 (the
## plan's literal "5 in each colour"), kept as its own number because a guild gate is a
## design knob of its own, not a point on the ladder every spell rank already climbs.
@export var guild_investment_requirement: int = 5

## Azorius Justiciar (white+blue): an enemy you freeze, stun or knock back deals this
## much less damage for guild_azorius_weaken_duration seconds afterwards.
@export var guild_azorius_weaken_mult: float = 0.3
@export var guild_azorius_weaken_duration: float = 5.0
## Gruul: Rubblebelt Rioters (red+green) - after Titanic Brawl or Fire Dash, this many of
## the player's next melee hits are empowered.
## Dimir Guildmage: how many of its ghouls may stand at once. Every enemy dying frozen,
## stunned or diseased rises - a rank-5 Contagion alone could raise a dozen a cast, with
## no cap and a TemporaryAlly each. Past the cap, the dead stay dead.
@export var guild_dimir_max_ghouls: int = 6
@export var guild_gruul_rampage_hits: int = 3
@export var guild_gruul_rampage_damage_mult: float = 1.5
@export var guild_gruul_rampage_knockback_mult: float = 1.5
## Selesnya: Trostani, Selesnya's Voice (green+white) - the radius a self-shield or
## self-heal also reaches the caster's own myrs at.
@export var guild_selesnya_radius: float = 10.0

## How long a chargeable spell (SpellDatabase "chargeable") can be held before it fires
## on its own, and therefore how long a full-power cast takes to build. The release
## scales the payload by how much of this window was actually held - Fireball's radius
## and damage both ride that fraction (Player.cast_red_fireball) - with a floor of 20%
## for a tap, so a quick cast is weak rather than nothing.
##
## The cast clip's discarded lead-in is stretched across this window, so the caster
## visibly winds the spell up for as long as it is held (Player._begin_spell_windup).
##
## Cut from 5.0 on 2026-09-10. Fireball is the only chargeable spell, and five seconds was a
## long commitment mid-fight for what it buys: charge multiplies damage 0.6 -> 1.8 and radius
## 2.4 -> 4.5, which is a real payoff, but not one worth standing still five seconds for while
## a lane walks past you. Three keeps the same range of outcomes on a hold a fight can afford.
##
## Everything downstream is expressed as a FRACTION of this, so nothing else moves: the
## charge_pct the spell scales by is unchanged, and _begin_spell_windup stretches the cast
## clip's lead-in across whatever this says - the raise simply plays faster.
@export var spell_charge_max_time: float = 3.0

# Per-spell cooldowns moved to scripts/spell_database.gd, which owns one row per
# spell. Tier costs stay here: they are shared tuning, not per-spell data.

# --- MTG 5-Color Tier Costs ---
const TIER_COSTS: Array[int] = [1, 3, 7, 15, 30, 50]

func get_tier_cost(tier_index: int) -> int:
	if tier_index >= 0 and tier_index < TIER_COSTS.size():
		return TIER_COSTS[tier_index]
	return 1

# --- RED SKILLS ---
@export var spell_red_shock_damage: float = 70.0
@export var spell_red_fireball_base_radius: float = 3.0
@export var spell_red_fireball_base_damage: float = 60.0
@export var spell_red_rain_ember_duration: float = 5.0
@export var spell_red_rain_ember_radius: float = 6.0
## Rain of Ember: raised from 25 on 2026-10-11 - a tier-3 zone that dealt less than Fire
## Dash's tier-2 trail.
@export var spell_red_rain_ember_dps: float = 40.0
## Fervor - red's Attunement. Swing AND cast speed at rank 5. Not movement: that is the
## Swiftfoot Boots' number alone (see the EQUIPMENT section).
@export var aura_fervor_speed_boost: float = 1.15

# --- BLUE SKILLS ---
@export var spell_blue_unsummon_knockback: float = 21.0
## How hard the shove also throws them UPWARD. A purely horizontal push slid enemies
## along the floor like furniture; lifting them makes the same shove read as a blast that
## picked them up, and it is what turns the landing into an event the player can watch.
##
## Not a full launch: at this against gravity the arc peaks about a metre up and is over
## in well under a second, so the stun that follows still lands on an enemy standing on
## the ground rather than one floating out of reach.
@export var spell_blue_unsummon_lift: float = 7.5
## Only the old Unsummon PROJECTILE (projectile.gd type 2) reads this, and nothing fires that
## any more. The cone Unsummon deals no damage of its own - only an enemy it throws into a
## wall or obstacle takes damage (spell_blue_unsummon_impact_damage), by design.
@export var spell_blue_unsummon_damage: float = 35.0
@export var spell_blue_unsummon_impact_damage: float = 80.0
@export var spell_blue_freeze_breath_shatter_damage: float = 90.0
@export var spell_blue_freeze_breath_shatter_radius: float = 4.0
## Rhystic Study - blue's Attunement. Every cast banks this much shield, up to the cap.
## It used to cut cooldowns by 30% as well, which is the blue AFFINITY's number - so that
## half went, and the shield grew to carry the node on its own.
##
## Rank 1 -> rank 5, walked with rank_fraction (2026-10-16). It used to be 20 per cast up to
## 60 at rank 1, scaled by the damage curve to 40 up to 120 at rank 5: three casts of the
## first rank already banked 60% of a player's health, which made the 3-point aura the
## strongest defence in the game the moment it was bought.
@export var aura_rhystic_study_shield_amount: float = 7.0
@export var aura_rhystic_study_shield_amount_max: float = 18.0
@export var aura_rhystic_study_shield_max: float = 22.0
@export var aura_rhystic_study_shield_max_max: float = 55.0
## ...and when the shield breaks, whatever is standing close enough to have broken it is
## frozen (bosses slowed) for this long, at rank 1. The duration curve lengthens it.
@export var aura_rhystic_study_shatter_radius: float = 4.0
@export var aura_rhystic_study_shatter_freeze: float = 1.5

# --- GREEN SKILLS ---
## Kodama's Reach - green's Attunement (was Sylvan Library). Every spell's area at rank 5.
## It used to grant maximum health and regeneration, the green and the white AFFINITIES'
## numbers; area is the one thing no other node in the tree gives. Not called Overgrowth,
## which is already green's team enchantment.
@export var aura_kodamas_reach_area_mult: float = 1.3

# --- WHITE SKILLS ---
@export var spell_white_swords_exile_pct: float = 0.5
@export var spell_white_swords_damage_cap: float = 120.0
@export var spell_white_swords_ally_heal: float = 60.0
@export var spell_white_path_to_exile_exec_mult: float = 0.5
@export var spell_white_pacifism_debuff_mult: float = 0.5
## Glorious Anthem - white's Attunement, and a TEAM aura: teammates, myrs and summons within
## the radius deal more and take less (rank-5 values). Not the white player themselves - it
## used to be a shield and +15% damage on the caster, i.e. red's number and a third shield.
## Several Anthems do not stack; the strongest one reaching an ally applies.
@export var aura_glorious_anthem_radius: float = 14.0
@export var aura_glorious_anthem_ally_damage_mult: float = 1.2
@export var aura_glorious_anthem_ally_damage_taken_mult: float = 0.8

# --- BLACK SKILLS ---
@export var spell_black_drain_life_damage: float = 70.0
@export var spell_black_drain_life_lifesteal: float = 0.65
## Phyrexian Arena - black's Attunement, "Phyrexian mana": a spell on cooldown can be cast
## anyway, for this share of maximum health per second of cooldown left (rank 1 -> rank 5).
## Refused if it would leave the player below 1 health. It used to be +25% damage and +15%
## speed paid for by a constant drain - red's number and the boots' number.
##
## Raised 2026-10-16 from 1.2% -> 0.7%: an 8 s Titanic Brawl skipped for under 10% of health
## at rank 1 meant cooldowns barely existed. Now a full cooldown costs about a third of
## health at rank 1 and still half that at rank 5.
@export var aura_phyrexian_arena_life_per_second: float = 0.035
@export var aura_phyrexian_arena_life_per_second_max: float = 0.018

# ============================================================
# SKILL ROSTER - docs/SKILL_DESIGN.md
# ============================================================
# Five rankable skills per colour plus a aura fork, exactly as the colour tables
# specify. What each skill DOES lives in Player; only its numbers live here, and only
# the ones a designer would want to reach for. Cooldowns are the one exception: they
# belong to the spell row in scripts/spell_database.gd, alongside the animation timing
# they have to agree with.

# --- WHITE: protection and restoration ---
## Exalted Strike (white_1). Charges are consumed by melee hits, not by time, so the
## buff cannot be wasted by walking around with it. Raised on 2026-10-11 (x2.4 and one charge
## -> x4 and two): one harder swing every 8 seconds was worth +28 damage, the weakest
## tier-1 spell by a factor of four.
@export var spell_white_exalted_damage_mult: float = 4.0
@export var spell_white_exalted_reach_bonus: float = 2.0
@export var spell_white_exalted_charges: int = 2
## Circle of Protection (white_2). A BASE shield per ally, grown a little for every
## ally beyond the first - white's power goes UP with more allies alive, and dividing
## one pool said the opposite. Bound to player_max_hp like every white/green HP number.
## Circle of Protection (white_2). Cut from 2.2 on 2026-09-10, and that number was a bug rather
## than a balance choice: the spell used to be one POOL of 220 divided between everyone in range
## (spell_white_circle_shield_total), and when it became a shield PER ALLY the 220 came along
## unchanged. A five-player cast went from granting 220 shield in total to granting 1540, and
## even solo it was 2.2 whole health bars from one button.
##
## 0.35 of max HP is 35 a head at rank 1 and 70 at rank 5 - about three ordinary hits, four with
## the crowd bonus. Compare the tier-5 defensive skills it was outclassing: Ironbark is 60%
## reduction for six seconds, and Rally's ward brings you back at 40% health.
@export var spell_white_circle_shield_hp_mult: float = 0.35
@export var spell_white_circle_ally_bonus: float = 0.10
@export var spell_white_circle_radius: float = 12.0
## ...and it EXPIRES. Nothing else in the roster is permanent, and a shield that is not was the
## other half of the problem: with an 18s cooldown and no duration the correct play was to stand
## in the base spamming it until the pool was arbitrarily large, which is not a decision.
##
## Comfortably shorter than the 18s cooldown even at rank 5 with Vigilance (8 x 1.5 x 1.2 =
## 14.4s), so the shield cannot be kept up permanently by recasting either.
@export var spell_white_circle_duration: float = 8.0
## Reprisal Ward (white_3)
@export var spell_white_reprisal_reflect: float = 0.45
@export var spell_white_reprisal_block_chance: float = 0.3
@export var spell_white_reprisal_duration: float = 8.0
## Wrath of God (white_4). White's one panic button, so it hits hard and rarely.
@export var spell_white_wrath_radius: float = 10.0
@export var spell_white_wrath_damage: float = 170.0
## Rally the Fallen (white_5). The heal is bound to player_max_hp. The ward is the
## solo floor: with nobody to revive, the cast instead guarantees the caster survives
## the next would-be death inside its window, at this fraction of max HP.
@export var spell_white_rally_radius: float = 15.0
@export var spell_white_rally_heal_hp_mult: float = 2.5
@export var spell_white_rally_ward_duration: float = 10.0
@export var spell_white_rally_ward_hp_fraction: float = 0.4

# --- BLUE: control ---
## Unsummon (blue_1). Cone in front, not a circle: blue decides where the fight happens,
## and a shove that also cleared what is behind you would need no aiming at all.
@export var spell_blue_unsummon_range: float = 12.0
@export var spell_blue_unsummon_cone_dot: float = 0.2
@export var spell_blue_unsummon_stun: float = 1.5
## Frost Breath (blue_2). Bosses are SLOWED, never frozen - see the colour table.
@export var spell_blue_frostwave_radius: float = 8.5
@export var spell_blue_frostwave_damage: float = 65.0
@export var spell_blue_frostwave_freeze: float = 3.0
## Cut from 4.0 on 2026-09-09. Frost Breath already deals damage, freezes every ordinary
## enemy outright, and scales its radius, damage and duration - a full panic button and a
## damage spell in one, which left it competing with White's Wrath and with blue's own
## control kit. The boss clause is the half that was doing too much: a boss slowed for four
## seconds on a repeatable cooldown is a boss that never gets to act. It still buys real
## time, just not a whole phase of one.
@export var spell_blue_frostwave_boss_slow: float = 2.5
## Suction (blue_3). A zone that keeps dragging enemies inward for its whole duration
## rather than pulling once. The pull is slow on purpose: walking out of it is the
## counterplay, and a yank that nothing can escape removes it.
@export var spell_blue_suction_radius: float = 12.0
@export var spell_blue_suction_pull_speed: float = 4.0
## Suction is the one spell whose whole identity is DURATION: a vortex that keeps pulling
## for as long as it stands, rather than a shove. Its rank curve is written out rather than
## riding rank_duration_mult, because the numbers are the design - 6 / 7 / 8 / 9 / 10
## seconds - and a generic multiplier would only approximate them.
##
## Always SHORTER than the cooldown (11s, SpellDatabase). It used to run 10 to 30 seconds,
## longer than the cooldown from rank 2 on, and since the pull outruns every enemy's walk,
## two or three vortexes back to back held a lane shut for the whole wave (until
## 2026-10-11).
@export var spell_blue_suction_duration: float = 6.0
@export var spell_blue_suction_duration_max: float = 10.0
## Wall of Frost (blue_4). Real collision, plus bonus damage when Unsummon slams an
## enemy into it instead of ordinary terrain.
@export var spell_blue_wall_of_frost_length: float = 8.5
@export var spell_blue_wall_of_frost_duration: float = 10.0
@export var spell_blue_wall_of_frost_unsummon_bonus_damage: float = 120.0
## Displace (blue_5). A short blink to the aimed ground point, capped so it stays a
## mobility tool rather than a cross-lane teleport.
@export var spell_blue_displace_distance: float = 9.0
## Seconds the player cannot be hurt after arriving - the escape is what a tier-5 blink is
## for, and one that lands in the swing it was dodging escaped nothing.
@export var spell_blue_displace_invulnerability: float = 0.6

# --- BLACK: parasitic drain ---
## Doom Blade (black_1). Passes THROUGH - only what the line actually touches is hit,
## which is what makes it a skill shot rather than a cone.
@export var spell_black_doom_blade_damage: float = 115.0
## Rank 1 and rank 5 reach. Ranking the blade makes it REACH further - it stays a thin line
## (the width barely moves), so a ranked blade is a longer skill shot, not a wider cone.
@export var spell_black_doom_blade_length: float = 20.0
@export var spell_black_doom_blade_length_max: float = 36.0
@export var spell_black_doom_blade_width: float = 1.6
## Contagion (black_2, replaced Fear). A plague put on one enemy that burns it and, every
## `spread_interval`, jumps to the nearest uninfected enemy within `spread_radius` - so the
## denser the wave, the further it runs. Each new victim catches the full duration.
##
## Fear went because it scattered the very packs every area skill in the roster wants, and
## its damage window was Wall of Souls' vulnerability a second time.
@export var spell_black_contagion_range: float = 24.0
@export var spell_black_contagion_dps: float = 22.0
@export var spell_black_contagion_duration: float = 7.0
@export var spell_black_contagion_spread_radius: float = 4.5
@export var spell_black_contagion_spread_interval: float = 1.0
## How many enemies one cast can reach in total, rank 1 -> rank 5. A cap, or a single
## cast into a late wave would take the whole lane.
@export var spell_black_contagion_max_victims: int = 8
## 16 until 2026-10-11 - with damage and duration also rising, x6 a cast at rank 5.
@export var spell_black_contagion_max_victims_max: int = 12
## Deathtouch (black_3, was Kill). The boss clause is what stops an execute trivialising the
## wave bosses; the cooldown (spell_database.gd) is still the longest in the game for the same
## reason. Bosses AND minibosses die only below this share of health - minibosses used to be
## deleted at full health, being no "Boss" class. 0.33 -> 0.25 on 2026-10-11 (and the ceiling
## 0.5 -> 0.35): half a boss's bar at once every 24 seconds was half of every boss fight.
@export var spell_black_deathtouch_boss_threshold: float = 0.25
## How long the charge waits for an attack, and how many enemies one attack may execute.
@export var spell_black_deathtouch_window: float = 8.0
@export var spell_black_deathtouch_targets: int = 3
## Wall of Souls (black_4)
@export var spell_black_wall_length: float = 14.0
@export var spell_black_wall_duration: float = 12.0
@export var spell_black_wall_mark_duration: float = 8.0
@export var spell_black_wall_mark_mult: float = 2.0
## Zombify (black_5). Raises corpses that are already lying on the field as ghouls that
## sprint at the nearest enemy and FIGHT it, swinging with their model's attack clip, until
## their time runs out or something kills them. With Mayhem Devil (black+red guild node)
## that end is a burst for `burst_damage` in `burst_radius`; without it they just crumble.
@export var spell_black_zombify_count: int = 3
@export var spell_black_zombify_hp: float = 160.0
@export var spell_black_zombify_duration: float = 14.0
@export var spell_black_zombify_speed: float = 7.0
## One swing's damage, and the time from one swing to the next.
@export var spell_black_zombify_hit_damage: float = 22.0
@export var spell_black_zombify_attack_interval: float = 1.2
@export var spell_black_zombify_burst_damage: float = 90.0
@export var spell_black_zombify_burst_radius: float = 3.5
## With nothing to chase a ghoul stays with the player who raised it: it sets off once it is
## further than `follow_far` away and stops again inside `follow_near`.
@export var spell_black_zombify_follow_near: float = 5.0
@export var spell_black_zombify_follow_far: float = 9.0

# --- RED: aggression ---
## Fire Dash (red_2). Escape and damage in one, which is why the trail is worth as much
## as the distance.
@export var spell_red_dash_speed: float = 26.0
@export var spell_red_dash_duration: float = 0.38
@export var spell_red_dash_trail_dps: float = 45.0
@export var spell_red_dash_trail_duration: float = 4.0
@export var spell_red_dash_trail_radius: float = 2.2
## Fire Cone (red_4). A refill meter rather than a normal cooldown: hold to spend up to
## this many seconds of flame, then wait for the meter to fill again.
##
## Retuned 2026-09-09 from 145 dps at 9.0 length. At 145 a full 5-second channel was 725
## damage to EVERY enemy in the cone before rank scaling - more than Lightning Bolt's single
## target number, three times Fire Dash's trail and nearly six times Rain of Ember's dps, on
## a spell the player can walk with. Red's four fire skills all wanted the same job; this one
## is now the one that holds a line rather than the one that clears it, which is what the
## slow below is for. Cut to 55 on 2026-10-11: at 85 it dealt 425 per enemy over a full channel,
## two and a half to three times any other area spell per 10 seconds; 275 keeps it the best
## of them without making the rest of the colour pointless.
@export var spell_red_fire_cone_dps: float = 55.0
@export var spell_red_fire_cone_length: float = 7.0
@export var spell_red_fire_cone_dot: float = 0.55
@export var spell_red_fire_cone_max_duration: float = 5.0
## The control half of Fire Cone's new job. Refreshed every frame the enemy is in the cone
## and lapsing shortly after it sweeps off them, so keeping something slowed means keeping
## the flame ON it - which is the sustained-pressure shape the damage no longer provides.
@export var spell_red_fire_cone_slow_mult: float = 0.6
@export var spell_red_fire_cone_slow_duration: float = 0.4
## Lightning Bolt (red_5). Precision against one big target: the smallest area in the
## game and the largest single number.
@export var spell_red_bolt_damage: float = 230.0
@export var spell_red_bolt_radius: float = 2.8
@export var spell_red_bolt_delay: float = 0.55
## What the bolt is FOR. Against a boss or an elite it hits for this much more, which is the
## one thing no other red skill does: Fireball, Rain, Fire Dash and Fire Cone are all area
## damage, and against a single large target they are all mediocre. 230 flat was strictly
## worse than parking a Fire Cone on the same boss; 460 at rank 1 through 598 at rank 5 is a
## number worth rooting yourself and eating the telegraph delay for.
##
## Ordinary enemies feel none of this - the bolt stays a bad way to clear a wave, on purpose.
@export var spell_red_bolt_elite_mult: float = 2.0
@export var spell_red_bolt_elite_mult_max: float = 2.6
## Effectively unlimited: the bolt lands wherever the crosshair meets the ground, however
## far that is. It is the one spell aimed at a POINT rather than around the caster, and a
## 30-unit cap meant the strike silently landed short of what the player was looking at -
## which reads as the spell missing rather than as a range limit.
@export var spell_red_bolt_range: float = 500.0

# --- GREEN: primal vitality ---
## Giant Growth (green_2). The bonus HP is a multiple of player_max_hp, so green's own
## affinity and every other max-HP effect scale it.
@export var spell_green_giant_scale: float = 1.5
@export var spell_green_giant_bonus_hp_mult: float = 1.6
@export var spell_green_giant_duration: float = 12.0
## Fog (green_3). Defensive GROUND rather than an offensive zone - the crystal-defence
## half of green, with Roar.
@export var spell_green_fog_radius: float = 7.0
@export var spell_green_fog_duration: float = 8.0
## Fog's problem was never its strength, it was that suppressed damage is INVISIBLE: the
## player sees enemies swinging and nothing happening, which reads as the spell having failed
## rather than as the spell working. Two answers, both here: the prevented damage is now shown
## as a floating number (Player/EnemyBase), and enemies wade through the cloud rather than
## walking through it - a slow the player can see at a glance without reading numbers.
##
## Milder than frost's 0.3 on purpose. Fog is not a control spell that also blocks damage; it
## is ground the player holds, and the wading is legibility, not the effect.
@export var spell_green_fog_slow_mult: float = 0.65
## Roar (green_4)
@export var spell_green_roar_radius: float = 14.0
@export var spell_green_roar_duration: float = 6.0
## Ironbark (green_5). The only CC immunity in all thirty skills - without it, being
## stunned or frozen has no counter at all.
@export var spell_green_ironbark_reduction: float = 0.6
@export var spell_green_ironbark_duration: float = 6.0

# --- AURAS: THE ORBS ---
# The second half of every colour's aura fork. The Attunements (Fervor, Rhystic
# Study and the rest, above) are stat lines; these are presence - something visibly
# fighting alongside the player. All four orbs are ONE implementation (OrbitingOrb).
#
# They share one small halo above the player's LEFT shoulder - the camera looks over the
# right one, so that side of the frame is never the aim line. They used to circle the
# player up to three metres out at head height, straight through the camera's view.
## Radius of the halo. At least 0.6: each orb takes a fifth of the ring, and
## tools/tests/orb_orbits.gd needs a clear gap between neighbours that a smaller ring
## cannot give.
@export var aura_orb_radius: float = 0.62
## Centre of the halo, in the player's own space: -X is the left shoulder, +Z is towards
## the camera behind them. Slightly IN FRONT of the head: a halo leaning back towards the
## lens drew its nearest orb as a large blob in the top corner of the screen.
@export var aura_orb_halo_centre: Vector3 = Vector3(-0.6, 2.35, -0.3)
## Radians per second. Slow: a halo that spins reads as a mechanism, not a familiar.
@export var aura_orb_speed: float = 0.8
## Rise and fall around the ring, as a fraction of its radius.
@export var aura_orb_tilt: float = 0.12
## Each orb's own light. A glow on the player rather than a lamp - four of them used to
## light the ground in four moving colours.
@export var aura_orb_light_energy: float = 0.45
@export var aura_orb_light_range: float = 2.2
## Extra decibels for an orb that belongs to another player - background, not the local
## player's own doing. On top of SoundBank.EVENT_GAIN_DB.
@export var aura_orb_remote_gain_db: float = -6.0
## Winter Orb - blue's Manifestation
@export var aura_orb_of_frost_damage: float = 34.0
@export var aura_orb_of_frost_interval: float = 1.4
@export var aura_orb_of_frost_range: float = 14.0
@export var aura_orb_of_frost_slow: float = 2.5
## Orb of Fire - red's Manifestation
@export var aura_orb_of_fire_damage: float = 42.0
@export var aura_orb_of_fire_interval: float = 1.6
@export var aura_orb_of_fire_range: float = 14.0
@export var aura_orb_of_fire_burn_dps: float = 18.0
@export var aura_orb_of_fire_burn_duration: float = 4.0
## Metres per second the ball of fire flies at. The hit lands when it arrives.
@export var aura_orb_of_fire_bolt_speed: float = 26.0
## Lightning Orb - red's second Manifestation. An arc into the nearest enemy that leaps on to
## the nearest one not yet struck, `chains` times (one more at rank 3 and at rank 5), each
## jump dealing `chain_falloff` of the one before. Lower per hit than Orb of Fire and no burn:
## its damage is in the spread, so it is the orb for a crowd, fire the orb for one target.
@export var aura_lightning_orb_damage: float = 28.0
@export var aura_lightning_orb_interval: float = 2.0
@export var aura_lightning_orb_range: float = 13.0
@export var aura_lightning_orb_chains: int = 2
@export var aura_lightning_orb_chain_range: float = 6.0
@export var aura_lightning_orb_chain_falloff: float = 0.8
## Healing Orb - white's Manifestation. Always picks the LOWEST-health ally in range,
## which is what makes it feel like a healer rather than a regeneration stat. The amount
## is a multiple of player_max_hp, like every white/green HP number. Halved on 2026-10-11:
## 0.26 a pulse was 13-26% of a player's health every second, passive, out-healing every
## other source in the game.
@export var aura_healing_orb_hp_mult: float = 0.13
@export var aura_healing_orb_interval: float = 2.0
@export var aura_healing_orb_radius: float = 14.0
## Trample - green's Manifestation. Gated on MOVING, so it rewards the colour that
## fights by being physically present.
@export var aura_trample_dps: float = 40.0
@export var aura_trample_radius: float = 3.2
## Grave Pact - black's Manifestation, the Soul Orb. Every enemy that dies within
## `radius` of the player gives up its soul to the orb, which throws the souls it holds at
## the nearest enemy one at a time. It used to heal and stack a damage bonus - two numbers
## the black affinity (lifesteal) and red (damage) already own.
@export var aura_grave_pact_radius: float = 12.0
@export var aura_grave_pact_soul_damage: float = 40.0
## How many souls the orb can hold. A cap, so clearing a wave does not bank a minute of fire.
@export var aura_grave_pact_max_souls: int = 6
## Seconds between two souls leaving the orb.
@export var aura_grave_pact_release_interval: float = 0.55
@export var aura_grave_pact_range: float = 16.0

# --- RANK CEILINGS ---
# The handful of skill numbers the generic curves cannot express, each with the value it
# reaches at rank 5. Fractions and counts, per docs/SKILL_DESIGN.md's "Scales with rank".
## Exalted Strike: charges held, not damage - the damage rides the generic curve.
@export var spell_white_exalted_charges_max: int = 3
## Reprisal Ward: both halves are chances, so both walk to a ceiling.
@export var spell_white_reprisal_reflect_max: float = 0.9
@export var spell_white_reprisal_block_chance_max: float = 0.5
## Rally the Fallen: how many downed teammates one cast can pick up.
@export var spell_white_rally_revives: int = 1
@export var spell_white_rally_revives_max: int = 5
## Deathtouch: the ONLY skill whose cooldown scales, and the only one where a higher rank
## widens the boss window rather than adding damage.
@export var spell_black_deathtouch_cooldown_max_rank_mult: float = 0.6
@export var spell_black_deathtouch_boss_threshold_max: float = 0.35
@export var spell_black_deathtouch_targets_max: int = 7
## Wall of Souls: x2 damage is the headline at rank 1; x4 would eclipse every other
## black skill, so the mark walks to x3.
@export var spell_black_wall_mark_mult_max: float = 3.0
## Zombify: bodies raised per cast. 7 until 2026-10-11 - each ghoul also hits twice as hard
## at rank 5, so the count is the one axis kept short.
@export var spell_black_zombify_count_max: int = 5
## Ironbark: reduction is a fraction, and 1.0 would be immunity.
@export var spell_green_ironbark_reduction_max: float = 0.8
## Giant Growth: how much bigger, which is the half of the skill the player sees.
@export var spell_green_giant_scale_max: float = 1.9
## The size also slows the swing - the trade that makes the growth read as weight. Capped
## so a rank-5 giant attacks at most this many times slower; without a ceiling the slow
## would outgrow the damage it is paying for.
@export var spell_green_giant_attack_slow_cap: float = 1.75

## Doom Blade: "width (barely)" in the design doc, so barely.
@export var spell_black_doom_blade_width_max: float = 1.9

# --- ROUND TWO (docs/SKILL_DESIGN.md, "Idea backlog - round two") ---
# Every number of the thirty-four skills round two added, colour by colour, with the ceilings
# beside them rather than in RANK CEILINGS above - a block one reads top to bottom per skill.

## What counts as the archer's HEAVY attack for a "next heavy attack" charge: a draw at least
## this full. 1.0 is a full draw; anything less is the quick shot, the light one.
@export var archer_heavy_draw_threshold: float = 1.0
## How far from the attacker the impact half of a charged attack may land and still be taken on
## trust (Player._request_charged_impact) - the longest reach of any basic attack, and some.
@export var charged_impact_max_reach: float = 70.0

## Glorious Charge (white_6): a charge behind the guard, carrying the enemies in the way.
@export var spell_white_charge_distance: float = 9.0
@export var spell_white_charge_duration: float = 0.45
@export var spell_white_charge_width: float = 2.4
@export var spell_white_charge_damage: float = 30.0
@export var spell_white_charge_stun: float = 1.2
@export var spell_white_charge_shield: float = 18.0
@export var spell_white_charge_shield_duration: float = 5.0
## Smite the Monstrous (white_7): the charged heavy's damage multiplier, before rank.
@export var spell_white_smite_damage_mult: float = 2.5
## Sunlance (white_8): the line past the hit, and how long what it touches is blind.
@export var spell_white_sunlance_length: float = 12.0
@export var spell_white_sunlance_width: float = 1.6
@export var spell_white_sunlance_damage: float = 60.0
@export var spell_white_sunlance_blind: float = 2.0
## Mark of Sanctity (white_9): how long the mark lasts, and the shield each ally's hit on the
## marked enemy earns - at most once per interval per ally, and never past the cap.
@export var spell_white_sanctity_duration: float = 8.0
@export var spell_white_sanctity_shield: float = 10.0
@export var spell_white_sanctity_shield_cap: float = 40.0
@export var spell_white_sanctity_shield_duration: float = 5.0
@export var spell_white_sanctity_interval: float = 0.5
## Worship (white_10): hallowed ground round the caster.
@export var spell_white_worship_radius: float = 6.0
@export var spell_white_worship_duration: float = 6.0
## Banishing Light (white_11): a circle where the caster aims.
@export var spell_white_banish_range: float = 30.0
@export var spell_white_banish_radius: float = 3.5
@export var spell_white_banish_duration: float = 4.0

## Mirror Image (blue_6): copies, how long they last, how much of the caster's attack they deal.
@export var spell_blue_mirror_count: int = 1
@export var spell_blue_mirror_count_max: int = 3
@export var spell_blue_mirror_duration: float = 10.0
@export var spell_blue_mirror_health: float = 120.0
@export var spell_blue_mirror_damage_share: float = 0.5
## Crippling Chill (blue_7): three light attacks; the first two chill, the third freezes.
@export var spell_blue_crippling_chill_uses: int = 3
@export var spell_blue_crippling_chill_slow: float = 2.0
@export var spell_blue_crippling_chill_freeze: float = 2.0
## Ice Cage (blue_8): how long the target stands encased.
@export var spell_blue_ice_cage_duration: float = 4.0
## Time Ebb (blue_9): what a boss, a miniboss or a beast gets instead of going home.
@export var spell_blue_time_ebb_boss_slow: float = 3.0
## Counterspell (blue_10): how far from the caster a special can be countered.
@export var spell_blue_counterspell_range: float = 25.0
## Curse of the Swine (blue_11).
@export var spell_blue_swine_range: float = 30.0
@export var spell_blue_swine_radius: float = 4.0
@export var spell_blue_swine_duration: float = 5.0
@export var spell_blue_swine_count: int = 3
@export var spell_blue_swine_count_max: int = 8
## How slowly a boar walks, and what it is drawn as: the boar model once it exists (a Meshy mesh
## waiting on the user's approval), and until then the smallest beast at this scale.
@export var spell_blue_swine_slow: float = 0.45
@export var spell_blue_swine_scene: String = "res://assets/enemies/beasts/boar/boar.tscn"
@export var spell_blue_swine_scale: float = 0.4

## Unholy Strength (black_6): life paid per hit, as a share of maximum health, and how many
## times the life paid each hit adds as damage (before rank).
@export var spell_black_unholy_duration: float = 8.0
@export var spell_black_unholy_life_per_hit: float = 0.02
@export var spell_black_unholy_damage_per_life: float = 3.0
## Bone Splinters (black_7): which corpses, how hard, how many, and how far a splinter seeks.
@export var spell_black_bone_splinters_radius: float = 5.0
@export var spell_black_bone_splinters_damage: float = 45.0
@export var spell_black_bone_splinters_max: int = 12
@export var spell_black_bone_splinters_seek: float = 14.0
## Undying (black_8): the health the player rises with, the grace after it, the dread wave.
@export var spell_black_undying_health: float = 0.3
@export var spell_black_undying_health_max: float = 0.6
@export var spell_black_undying_invulnerable: float = 3.0
@export var spell_black_undying_radius: float = 6.0
@export var spell_black_undying_knockback: float = 18.0
## Animate Dead (black_9): how near the aim a corpse is looked for, and what it rises as.
@export var spell_black_animate_range: float = 30.0
@export var spell_black_animate_search: float = 8.0
@export var spell_black_animate_damage: float = 45.0
## The share of the corpse's own health it rises with, and how big a raised BOSS is drawn
## beside its living size.
@export var spell_black_animate_health_share: float = 0.6
@export var spell_black_animate_boss_scale: float = 0.6
## The longest an animated corpse stands, if the wave goes on that long.
@export var spell_black_animate_duration: float = 120.0
## Gravewalk (black_10).
@export var spell_black_gravewalk_range: float = 25.0
@export var spell_black_gravewalk_radius: float = 4.0
@export var spell_black_gravewalk_damage: float = 70.0
## Demonic Pact (black_11): the kills owed, the time to pay, and the debt if not.
@export var spell_black_pact_kills: int = 10
@export var spell_black_pact_window: float = 15.0
@export var spell_black_pact_window_max: float = 20.0
@export var spell_black_pact_debt: float = 0.5
@export var spell_black_pact_debt_max: float = 0.35

## Fling (red_6): what can be seized, where it can be thrown, what it does when it lands.
@export var spell_red_fling_range: float = 25.0
@export var spell_red_fling_throw_range: float = 22.0
@export var spell_red_fling_height: float = 5.0
@export var spell_red_fling_radius: float = 4.0
@export var spell_red_fling_damage: float = 90.0
## Blood Frenzy (red_7): the damage multiplier at no health left (it scales linearly to it from
## full health, where it is 1).
@export var spell_red_frenzy_duration: float = 8.0
@export var spell_red_frenzy_mult: float = 1.8
@export var spell_red_frenzy_mult_max: float = 2.4
## Powder Keg (red_8).
@export var spell_red_powder_keg_fuse: float = 3.0
@export var spell_red_powder_keg_damage: float = 90.0
@export var spell_red_powder_keg_radius: float = 3.5
## Grapeshot (red_9): one bolt, and one more per spell cast inside the window, up to the cap.
@export var spell_red_grapeshot_window: float = 5.0
@export var spell_red_grapeshot_max: int = 8
@export var spell_red_grapeshot_damage: float = 28.0
@export var spell_red_grapeshot_range: float = 22.0
## Fork (red_10): how far the copy looks for its second target.
@export var spell_red_fork_range: float = 22.0

## Become Immense (green_6): the charged attack's size, before rank.
@export var spell_green_immense_damage_mult: float = 1.8
@export var spell_green_immense_reach_bonus: float = 1.5
@export var spell_green_immense_cone_widen: float = 0.25
@export var spell_green_immense_size_mult: float = 2.0
@export var spell_green_immense_burst_radius: float = 2.5
## Entangling Vines (green_7).
@export var spell_green_vines_radius: float = 4.0
@export var spell_green_vines_root: float = 3.0
## Kraul Harpooner (green_8): its reach, and how fast it drags.
@export var spell_green_harpoon_range: float = 28.0
@export var spell_green_harpoon_pull: float = 22.0
@export var spell_green_harpoon_self_speed: float = 26.0
## Awaken (green_9): what can be woken, and what it rises as.
@export var spell_green_awaken_range: float = 30.0
@export var spell_green_awaken_duration: float = 20.0
@export var spell_green_awaken_health: float = 600.0
@export var spell_green_awaken_damage: float = 45.0
## A woken treant (and, until it has a model of its own, the golem) beside the green boss's size.
@export var spell_green_awaken_scale: float = 0.45
## Overrun (green_10): the charge, and how hard it throws what it meets aside.
@export var spell_green_overrun_distance: float = 12.0
@export var spell_green_overrun_duration: float = 0.8
@export var spell_green_overrun_width: float = 2.6
@export var spell_green_overrun_knockback: float = 16.0
## Call of the Herd (green_11): trophies carried, how long one lies before it fades, how near
## a player has to walk to take it, and the longest a called beast stays.
@export var spell_green_herd_trophies: int = 1
@export var spell_green_herd_trophies_max: int = 3
@export var spell_green_herd_trophy_lifetime: float = 45.0
@export var spell_green_herd_pickup_radius: float = 1.8
@export var spell_green_herd_duration: float = 120.0

## Towers (white_12, blue_12, black_12, red_11, green_12): how many of one kind a player can have
## standing at once, rank 1 and rank 5 (rank_count: 1/2/2/3/3), and how far away they can go up.
@export var tower_count: int = 1
@export var tower_count_max: int = 3
@export var tower_place_range: float = 25.0
## Ivory Tower: shields allies and myrs in range every interval.
@export var tower_ivory_health: float = 400.0
@export var tower_ivory_radius: float = 10.0
@export var tower_ivory_interval: float = 3.0
@export var tower_ivory_shield: float = 15.0
@export var tower_ivory_shield_duration: float = 4.0
## Glacial Fortress: ice shots that slow; every Nth freezes.
@export var tower_glacial_health: float = 300.0
@export var tower_glacial_range: float = 18.0
@export var tower_glacial_interval: float = 1.0
@export var tower_glacial_damage: float = 18.0
@export var tower_glacial_slow: float = 2.0
@export var tower_glacial_freeze_every: int = 4
@export var tower_glacial_freeze: float = 1.5
## Bontu's Monument: deaths in range charge it; full, it raises a ghoul.
@export var tower_bontu_health: float = 350.0
@export var tower_bontu_radius: float = 12.0
@export var tower_bontu_charges: int = 5
@export var tower_bontu_ghoul_health: float = 120.0
@export var tower_bontu_ghoul_damage: float = 22.0
@export var tower_bontu_ghoul_duration: float = 12.0
## Goblin Sharpshooter: glass cannon.
@export var tower_goblin_health: float = 60.0
@export var tower_goblin_range: float = 26.0
@export var tower_goblin_interval: float = 0.35
@export var tower_goblin_damage: float = 32.0
## Hornet Nest: a tank that stings whoever hits it.
@export var tower_hornet_health: float = 900.0
@export var tower_hornet_radius: float = 6.0
@export var tower_hornet_sting: float = 14.0
@export var tower_hornet_sting_cooldown: float = 0.4

## How fast a fleeing enemy runs compared with how fast it advances. No spell makes an
## enemy flee since Fear left the roster; EnemyBase.apply_fear is kept for whatever does next.
@export var enemy_flee_speed_mult: float = 1.15

# ============================================================
# EQUIPMENT
# ============================================================
# Found, not bought: a slain boss can drop one piece, from the pool its colour fits (see
# EquipmentDatabase). What drops is the TEAM's - every player can put it on - and the five
# keyword passives that used to sit between the colours in the skill tree became the first
# five pieces. One number per item, which is all any of them needs.
## Chance a slain wave boss drops a piece the team does not have yet.
@export var equipment_boss_drop_chance: float = 0.6
## How many pieces one player may wear at once. 0 = no limit.
@export var equipment_max_equipped: int = 2
## Swiftfoot Boots: movement speed bonus.
@export var equipment_swiftfoot_boots_speed: float = 0.2
## Cobbled Wings: extra jump height, and holding jump on the way down glides at this
## fraction of gravity.
@export var equipment_cobbled_wings_jump: float = 1.0
@export var equipment_cobbled_wings_glide_gravity_mult: float = 0.25
## Fireshrieker: chance a melee hit lands a second time.
@export var equipment_fireshrieker_chance: float = 0.25
## Amulet of Vigor: spells with a duration last this much longer.
@export var equipment_amulet_of_vigor_duration: float = 0.3
## Loxodon Warhammer: melee hits add this share of the player's maximum health.
@export var equipment_loxodon_warhammer_hp_share: float = 0.12
## Icy Manipulator: chance a melee hit freezes the enemy (bosses are slowed), and for how long.
@export var equipment_icy_manipulator_chance: float = 0.15
@export var equipment_icy_manipulator_freeze: float = 1.5
## Executioner's Capsule: a melee hit kills any non-boss left below this share of its health.
@export var equipment_executioners_capsule_threshold: float = 0.15
## Whispersilk Cloak: seconds enemies overlook the player after each kill of theirs.
@export var equipment_whispersilk_cloak_duration: float = 2.0

# --- Beast equipment ---------------------------------------------------------------------------
# Found on the wild beasts instead of the bosses (docs/BEASTS_PLAN.md), one piece per biome. The
# chance a kill drops one is this times the beast's size, so a 5x giant drops about as
# reliably as a boss; like a boss's, only pieces the team does not have yet are in the draw.
@export var equipment_beast_drop_chance: float = 0.12
## Vorrac Battlehorns (green): seconds a melee hit stuns a beast, an elite or a miniboss - and
## how long before the same one can be stunned by it again, so it is a stagger, not a lock.
@export var equipment_vorrac_battlehorns_stun: float = 0.5
@export var equipment_vorrac_battlehorns_cooldown: float = 4.0
## Bonesplitter (red): extra damage, as a share, of a melee hit on an enemy still at full health.
@export var equipment_bonesplitter_bonus: float = 1.0
## Explorer's Scope (blue): the wearer's minimap shows the beasts in their biome's colour, sized
## by how big they are. A flag: anything above 0 is on.
@export var equipment_explorers_scope_reveal: float = 1.0
## Leonin Scimitar (white): extra damage, as a share, of a melee hit on an enemy that is
## attacking a myr or another player.
@export var equipment_leonin_scimitar_bonus: float = 0.5
## Nim Deathmantle (black): seconds a beast the wearer killed fights on as their ghoul.
@export var equipment_nim_deathmantle_duration: float = 25.0


# ============================================================
# SKILL RANKS
# ============================================================
# Every active skill is bought up to five times. Rank 1 is the skill working; ranks 2-5
# scale the two or three numbers its row in docs/SKILL_DESIGN.md lists under "Scales with
# rank". The auras are deliberately NOT rankable - the moment a aura becomes a
# slider it stops being a decision.
#
# The price is flat, one skill point per rank, and the SCARCITY IS THE TEAM LEVEL instead
# - the MOBA shape. A flat price with no gate would make maxing one skill strictly
# correct; a rising price would make it a sums puzzle. A level gate makes it a question of
# WHEN, which is the one form of the question that changes as a run goes on: early you
# take breadth because depth is not available yet, and late you choose what to deepen.
@export var spell_max_rank: int = 5
@export var spell_rank_point_cost: int = 1

## Rank 5 is roughly x2 damage, x1.6 area/range, x1.5 duration - the curve suggested in
## the design doc, kept in one place so twenty-five skills cannot each drift from it.
const RANK_DAMAGE_CURVE: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
const RANK_AREA_CURVE: Array[float] = [1.0, 1.15, 1.3, 1.45, 1.6]
const RANK_DURATION_CURVE: Array[float] = [1.0, 1.125, 1.25, 1.375, 1.5]


func _rank_index(rank: int) -> int:
	return clampi(rank - 1, 0, spell_max_rank - 1)


func rank_damage_mult(rank: int) -> float:
	return RANK_DAMAGE_CURVE[_rank_index(rank)]


func rank_area_mult(rank: int) -> float:
	return RANK_AREA_CURVE[_rank_index(rank)]


## NOT applied to damage over time or to buffs that would otherwise stand most of the
## time (Rain of Ember, Fire Dash's trail, Contagion, Zombify, Giant Growth, Fog - since
## 2026-10-11): their rank already pays out in damage, heal or area, and a longer duration on
## top multiplied into it - Zombify reached ~x7 its rank-1 damage, Contagion x6. Control
## (freezes, stuns, taunts) and shields keep it.
func rank_duration_mult(rank: int) -> float:
	return RANK_DURATION_CURVE[_rank_index(rank)]


## For anything that is already a FRACTION - damage reduction, a block chance, a reflect
## share. These cannot be multiplied: x2 on Ironbark's 0.6 reduction is 1.2, which is
## immunity. They walk from their rank-1 value to an explicit ceiling instead, so the
## ceiling is a number a designer chose rather than one the curve happened to produce.
func rank_fraction(base: float, ceiling: float, rank: int) -> float:
	if spell_max_rank <= 1:
		return base
	return lerpf(base, ceiling, float(_rank_index(rank)) / float(spell_max_rank - 1))


## For anything counted in whole things - corpses raised, charges held, allies revived.
## Rounded rather than floored so the middle ranks are not all silently identical.
func rank_count(base: int, top: int, rank: int) -> int:
	return int(roundf(rank_fraction(float(base), float(top), rank)))


## The share of an aura's listed bonus that rank 1 already pays out. Rank 5 always pays
## the full listed number; this is only where the walk to it STARTS.
const AURA_RANK1_SHARE := 0.4

## For a aura aura's MULTIPLIER - Fervor's x1.15 speed, Phyrexian Arena's x1.25 damage,
## Rhystic Study's x0.7 cooldown. `ceiling` is what the aura is documented as giving, and
## rank 5 is what reaches it.
##
## Exists because these were written as `lerpf(1.0, ceiling, rank_damage_mult(rank) - 1.0)`,
## and rank_damage_mult(1) is 1.0 - so the lerp weight at rank 1 was ZERO and the first rank
## of every one of these auras granted nothing at all. Phyrexian Arena rank 1 was the worst
## of them: it drained health for a damage and speed bonus that was still exactly x1.0.
##
## Multiplying by rank_damage_mult() instead would be wrong in the other direction: it would
## take Fervor's x1.15 to x2.3, and Rhystic Study's x0.7 cooldown to x1.4 - a COST. A bonus
## expressed as a multiplier has to walk from a smaller bonus to its listed one, which is
## what rank_fraction already does for every other fraction in the game. This is that, with
## the rank-1 starting point derived from the ceiling rather than written out per aura.
##
## Direction-agnostic on purpose: a ceiling below 1.0 (a cooldown multiplier) walks DOWN to
## it from a weaker discount, exactly as a ceiling above 1.0 walks up.
func aura_bonus_mult(ceiling: float, rank: int) -> float:
	return 1.0 + (ceiling - 1.0) * rank_fraction(AURA_RANK1_SHARE, 1.0, rank)


## The team level this rank needs. Rank 1 is the unlock itself.
## What the colour-investment ladder asks for at tier or rank `step` (1-based). Clamped
## rather than wrapped, so a sixth step - if one is ever added - inherits the last rung
## instead of silently costing nothing.
func color_investment_requirement(step: int) -> int:
	if color_investment_ladder.is_empty():
		return 0
	var index: int = clampi(step - 1, 0, color_investment_ladder.size() - 1)
	return color_investment_ladder[index]


## What `color_ring_investment` asks for to buy into ring `ring` (1-based). Clamped like the
## ladder; ring 0 (not a colour spell) asks for nothing.
func ring_investment_requirement(ring: int) -> int:
	if ring <= 0 or color_ring_investment.is_empty():
		return 0
	return color_ring_investment[clampi(ring - 1, 0, color_ring_investment.size() - 1)]


# ============================================================
# WAVES
# ============================================================
## Pause before the first battle group of a wave lands.
@export var wave_initial_warning_time: float = 2.5
## Superseded by upkeep_duration - kept only as the pause before the very first wave.
@export var wave_rest_period: float = 3.0

# --- Time limit ------------------------------------------------------------------------
#
# A wave cannot outlast its time limit. The clock starts when its last battle group has
# landed; when it runs out, whatever is left of the wave drops everything and storms the
# crystal, faster and deaf to players, myrs and taunts. After wave_storm_duration seconds
# Upkeep begins as if the wave had been cleared - but its leftovers are not removed: they
# stay as stragglers, still storming, still paid for, no longer counted. Without it a wave
# whose last enemy was stuck somewhere never ended, and a team could keep an early wave alive
# on purpose, kiting its enemies about while the myrs banked mana.

## The limit at wave 1, how much longer each later wave gets, and the cap, seconds. Generous
## on purpose: the storm is a backstop for a stalled wave, not a clock to fight every wave on.
@export var wave_time_limit_base: float = 240.0
@export var wave_time_limit_per_wave: float = 6.0
@export var wave_time_limit_max: float = 540.0
@export var wave_storm_duration: float = 20.0
@export var wave_storm_speed_mult: float = 1.35
## The HUD shows the countdown for the last this-many seconds of the limit.
@export var wave_deadline_warning: float = 30.0
## The Last Stand (WaveManager._check_last_stand): once the whole wave is on the map and no more
## than this share of it is left standing - and never more than `max_remaining` - what is left
## storms the crystal at once and is revealed on the minimap, instead of hiding in the fog until
## the time limit. Wave 1 (15 enemies) stands at 3 left; a late wave at 10.
@export var wave_last_stand_fraction: float = 0.15
@export var wave_last_stand_max_remaining: int = 10
## A storming enemy that has stood still this long, away from the crystal, is caught on
## something (a standing stone, a trunk) and is moved on along its way - see
## EnemyBase._check_storm_stuck. Never killed: a kill nobody made would pay the team for nothing.
@export var enemy_storm_stuck_seconds: float = 3.0
## How far from the crystal a storming enemy may stand still without counting as stuck - the
## ones at the crystal are standing there to hit it.
@export var enemy_storm_stuck_crystal_distance: float = 14.0
## How far along its path a stuck stormer is put.
@export var enemy_storm_unstick_distance: float = 4.0


## The time limit of wave `wave_number` (1-based), seconds.
func wave_time_limit(wave_number: int) -> float:
	return minf(wave_time_limit_base + wave_time_limit_per_wave * float(maxi(wave_number - 1, 0)), wave_time_limit_max)

# --- Battle groups ---------------------------------------------------------------------
#
# A wave is a handful of BATTLE GROUPS, not a spawn queue. Each group is a run of adjacent
# (which on the colour wheel means ALLIED) colours whose squads spawn simultaneously, in
# formation, converge on a hold line short of the crystal, wait for each other and charge
# together. The per-enemy spawn delays and cluster spacing that used to live here are gone
# with the queue: spacing is now the formation's own business (SquadDoctrine) and a squad
# arrives all at once.

## Gap between one battle group landing and the next. Long enough that two groups are two
## distinct pushes rather than one shapeless mass, short enough that they overlap by the
## time they reach the crystal - a lane is ~180 units and a melee walks it in about a
## minute, so everything deployed inside a wave is fighting at the same time regardless.
##
## This replaces a per-COLOUR delay that was applied after the previous colour had finished
## trickling in, which is how a wave of ten spawn groups ended up spread over more than a
## minute of deployment and was fought colour by colour. A late wave is now two or three
## groups, all on the map inside twenty seconds - the same enemies, arriving as an army.
##
## This is the gap once the waves are hard. Early on it is much shorter - see
## wave_first_group_delay - because the first waves send every colour on its own, and five
## lone colours ten seconds apart made the opening of a run a minute of waiting.
@export var wave_delay_between_groups: float = 10.0
## The gap between groups in wave 1. It grows evenly from this to wave_delay_between_groups,
## which it reaches at wave_group_delay_full_wave.
@export var wave_first_group_delay: float = 1.0
@export var wave_group_delay_full_wave: int = 10
## From this wave on, ALLIED NEIGHBOURS pair up: two adjacent lanes arrive together, form
## up between their lanes and charge as one. Before it, every colour comes in on its own.
@export var wave_alliance_start_wave: int = 4
## From this wave on, groups can be three adjacent colours - a shard of the wheel.
@export var wave_shard_start_wave: int = 9
## From this wave on, all five colours can arrive in a single push.
@export var wave_grand_alliance_start_wave: int = 16
## How far from the crystal a warband forms up before charging. The lane spawners sit at
## ~180 and the mana wells at ~112, so this puts the hold line just inside the wells -
## close enough that the player can see it happening and go and break it up.
@export var wave_rally_radius: float = 100.0
## How far towards its battle group's centre a squad converges to form up, as a fraction of
## the way from its own lane. 1.0 would be a single shared point on the arc between the
## lanes, which costs each squad a sideways detour about as long as the lane itself - ground
## with nothing on it. At 0.75 two neighbours end up about thirty units apart, which reads
## as one army massing, and the lanes close the rest of the gap during the charge.
@export var wave_rally_convergence: float = 0.75
## Longest a squad will stand at the rendezvous waiting for the rest of its warband. A
## safety net against a partner that is alive but pinned, not a pacing knob.
@export var wave_rally_timeout: float = 12.0
## How fast a formation wheels onto a new heading, in radians per second of blend. Low
## enough that turning towards a rendezvous off the lane's axis reads as a manoeuvre rather
## than as the whole squad's slots teleporting around its anchor.
@export var wave_squad_turn_speed: float = 1.2
## How close a squad's anchor has to get to a waypoint to count as having arrived.
@export var wave_squad_arrive_radius: float = 4.0
## How much faster than the formation's march speed a member may move while catching up to
## its slot. 1.0 would mean anyone who fell behind stays behind forever.
@export var wave_squad_catchup_mult: float = 1.35
## How far short of its break radius a squad starts running. A formation that walked into
## contact at marching pace would make the charge invisible on the one colour that has no
## warband to charge out of a rendezvous with.
@export var wave_squad_charge_lead: float = 18.0
## Below this share of its original size a squad stops being a formation and its survivors
## go and fight. Three enemies walking in rank towards a crystal they cannot threaten only
## makes the wave take longer to finish.
@export var wave_squad_disband_fraction: float = 0.35
## How much bigger a wave gets per player beyond the first. Enemy DAMAGE already scales
## with head count (get_player_scaling_factor), but wave SIZE never did - five players
## against a solo-sized wave shred it without the crystal ever being threatened, and earn
## solo-sized income while doing it. At 0.45 a five-player wave is 2.8x a solo one.
@export var wave_size_per_extra_player: float = 0.45
## Extra enemy health per player beyond the first. 0.15 gives 1.6x at five players.
@export var enemy_health_per_extra_player: float = 0.15
## Extra enemy health per WAVE, linear: wave 20 fights x2.14 the wave-1 health. Linear
## rather than compounding, so late waves get beefier without the curve running away.
@export var enemy_health_per_wave: float = 0.06
@export var wave_dynamic_base_difficulty: int = 5
@export var wave_dynamic_difficulty_per_wave: int = 2
@export var wave_boss_interval: int = 5
@export var wave_boss_delay: float = 2.0
@export var wave_elite_start_wave: int = 2
@export var wave_elite_count_base: int = 1

# --- Minibosses -------------------------------------------------------------------------
#
# A rung above Elite, and deliberately its own separate system rather than a bigger Elite
# tier: Elites only ever change numbers (see EnemyBase.apply_elite_modifier), and a miniboss
# is meant to be SEEN before it's felt - visibly larger, glowing in its colour, and the one
# thing in its squad the melee screen is actually built around. At most one per wave, so it
# reads as a notable arrival rather than a stat roll.
#
## First wave a miniboss may appear. Held back past the opening so the player has already
## seen a plain formation before meeting a reinforced one.
@export var wave_miniboss_start_wave: int = 6
## Chance per wave, from wave_miniboss_start_wave on, that one appears at all.
@export var wave_miniboss_chance: float = 0.35
## Extra melee units added to a miniboss's own squad, on top of the wave's normal
## composition. The formation itself (melee screen in front, see SquadDoctrine) does the
## rest - a denser screen in front of a miniboss reads as an honour guard for free, no new
## formation geometry required.
@export var wave_miniboss_escort_bonus: int = 3
@export var wave_miniboss_health_mult: float = 4.0
@export var wave_miniboss_damage_mult: float = 1.6
## Traded down a little against the health and damage bump, the same bargain Elite's own
## Juggernaut modifier makes - a miniboss that also outran its screen would leave the
## escort behind immediately.
@export var wave_miniboss_speed_mult: float = 0.9
## Visibly larger than its rank-and-file, but well short of a real boss (model_scale 2.1-2.9)
## - a miniboss is still a member of its squad, not a second boss in the same wave.
@export var wave_miniboss_scale_mult: float = 1.35
## Only a Mage miniboss gets a special (see EnemyBase._perform_miniboss_special) - a melee
## or ranged one is a stat-scaled version of the ordinary attack it already has, same swing,
## same bow. A caster gets a telegraphed signature spell instead, on its own long cooldown
## on top of its normal casting - the payoff for finding one in the mage core.
@export var wave_miniboss_special_cooldown_mult: float = 2.6
## Radius/strength multiplier applied to whichever of the five per-colour mage effects the
## special reuses (see perform_mage_spell) - the special is a bigger version of the same
## spell its ordinary cast already throws, not a new mechanic per colour.
@export var wave_miniboss_special_power_mult: float = 2.2
## How long the ground telegraph stands before the special resolves. Not driven off an
## animation clip length the way a real boss's is (BossDatabase.SPECIALS) - the ordinary
## Melee/Ranged/Mage models were never built with a dedicated cast clip to time against, so
## this is a fixed, tunable window instead. Long enough to react to, short enough that the
## mage is not standing rooted through half the fight.
@export var wave_miniboss_special_windup: float = 1.8

# ============================================================
# ENEMIES
# ============================================================
@export var enemy_aggro_radius: float = 12.0
## How much further than its own attack range an enemy may still connect at the
## moment its swing actually lands. Damage now pays out on the clip's measured
## impact frame rather than on the frame the swing started, so a target that walks
## away during the wind-up escapes it - this is the forgiveness on that. Set it very
## high to go back to the old "committed swings always hit" behaviour.
@export var enemy_attack_impact_range_grace: float = 1.35
## How fast an enemy swings its facing around, in lerp weight per second.
@export var enemy_turn_speed: float = 8.0

# --- enemy hit reaction ---
# Every enemy library ships a flinch clip, but until 2026-09-02 it only ever played
# while knockback was still carrying the body - so anything killed at range, which is
# most of what a Mage or Ranged enemy ever takes, never visibly reacted at all.
## A hit only flinches an enemy when it takes at least this fraction of its maximum
## health in one go; chip damage would otherwise leave a wave permanently twitching.
@export var enemy_hit_react_damage_pct: float = 0.08
## Minimum gap between two flinches, so a fast weapon cannot chain them.
@export var enemy_hit_react_cooldown: float = 1.0
## How long the flinch takes; the clip is squeezed into it the same way the player's
## reactions are.
@export var enemy_hit_react_duration: float = 0.4

# --- Locomotion animation ---------------------------------------------------------------
#
# Every locomotion clip carries a measured `stride_speed`: how far it actually carries the
# character per second at playback 1.0 (tools/animation_stride.gd). An enemy picks whichever
# of its clips is closest to the speed it is really travelling and plays it at exactly the
# rate that speed needs, so the feet stop sliding. The knobs below are the limits of that.

## How far a clip may be stretched from its own natural pace to match the enemy's real
## speed. A cycle pushed much past these stops reading as the same movement: slower than
## the minimum floats, faster than the maximum turns into a scribble. Anything outside the
## range is clamped, and some slide comes back - which is correct, because the honest fix
## for a clip that is twice too slow is a different clip, not a faster one.
@export var enemy_anim_match_min: float = 0.6
## 1.8 rather than a rounder number for a measured reason: the fastest thing in the game
## is a Red goblin with Haste, charging - 3.25 base x 1.3 x 1.5 = 6.34 units per second -
## and its run cycle covers 2.43, so anything below 1.8 leaves that one case visibly
## skating while every other enemy is already matched. Nothing needs more than this.
@export var enemy_anim_match_max: float = 1.8
## Relative speed change needed before the playback rate is re-applied. Purely to avoid
## re-issuing play() on every single frame of an acceleration; well below what the eye
## resolves on a walk cycle.
@export var enemy_anim_match_epsilon: float = 0.02
## Whether a flinch also throws away the swing in flight. True is what "getting hit"
## normally means, and the cooldown above is what keeps it from becoming a stunlock -
## set false to make flinches purely cosmetic and leave the old balance untouched.
@export var enemy_hit_react_interrupts_attack: bool = true
@export var enemy_melee_detection_range: float = 15.0
@export var enemy_ranged_detection_range: float = 35.0
@export var enemy_target_eval_interval: float = 0.5
@export var enemy_path_update_interval: float = 0.3
## When a formation breaks up, each member asks for its route at a random moment within this
## many seconds rather than all in one tick (EnemyBase.leave_formation).
@export var enemy_repath_spread: float = 0.75
## Enemy replication (EnemyBase._build_synchronizer). Movement goes out every `interval`
## seconds, every `far_interval` for an enemy far from every player; health, death and the
## plague timer only when they change, at most every `delta_interval`. It used to be all of
## it, every frame, to every client - roughly a megabyte a second per client at 300 enemies.
@export var enemy_net_interval: float = 0.05
@export var enemy_net_far_interval: float = 0.2
@export var enemy_net_delta_interval: float = 0.05
## A client's copy (EnemyBase._smooth_puppet): eased towards the reported position over
## about `smoothing` seconds, carried forward by the reported velocity for at most
## `extrapolate_max` seconds of report age, and snapped when it is further off than
## `snap_distance` - a recovery or a knockback, not a walk.
@export var enemy_net_smoothing: float = 0.08
@export var enemy_net_extrapolate_max: float = 0.3
@export var enemy_net_snap_distance: float = 4.0
## A formation slot's ground is found by a ray reaching this far above and below the squad's
## origin, and accepted when it is within the tolerance of the origin's height
## (WaveManager._slot_ground); otherwise the navmesh is asked.
@export var wave_slot_ground_probe: float = 8.0
@export var wave_slot_ground_tolerance: float = 3.0
## Milliseconds per frame a battle group may spend spawning its units (WaveManager.
## _pump_spawn_queue); the rest go in on the following frames.
@export var wave_spawn_budget_ms: float = 4.0
@export var enemy_mage_spell_cooldown_mult: float = 4.0
@export var enemy_frost_slow_mult: float = 0.3
@export var enemy_white_mage_heal: float = 30.0
@export var enemy_white_mage_range: float = 15.0
@export var enemy_red_mage_range: float = 20.0
@export var enemy_blue_mage_range: float = 20.0
@export var enemy_blue_mage_slow_duration: float = 4.0
@export var enemy_blue_mage_slow_mult: float = 0.6
@export var enemy_green_mage_range: float = 10.0
@export var enemy_green_mage_buff_scale: float = 1.5
@export var enemy_green_mage_buff_damage: float = 1.5
@export var enemy_black_mage_revive_hp_mult: float = 0.5
@export var enemy_elite_haste_speed_mult: float = 1.3
@export var enemy_elite_haste_attack_speed_mult: float = 0.75
@export var enemy_elite_regenerator_health_mult: float = 1.25
@export var enemy_elite_regenerator_heal_pct_per_second: float = 0.025
@export var enemy_elite_juggernaut_health_mult: float = 1.6
@export var enemy_elite_juggernaut_damage_mult: float = 1.25
@export var enemy_elite_juggernaut_speed_mult: float = 0.8
@export var enemy_elite_crystal_hunter_damage_mult: float = 1.35
@export var enemy_max_corpses: int = 100

## Recovery (EnemyBase._check_recovery): an enemy that has left the walkable map is put back
## on the nearest point of the navmesh rather than killed - a wave cannot end while one of
## its enemies is stuck under the ground or off the edge, and killing it would hand out a
## kill nobody made. Checked this often, seconds; an enemy this far BELOW the navmesh is back
## at once (it fell through the ground), one this far beside it only after it has been off
## for `off_seconds` (a knockback carrying it briefly over an edge is not a fall).
@export var enemy_recovery_check_interval: float = 0.5
@export var enemy_recovery_below_distance: float = 2.0
@export var enemy_recovery_off_distance: float = 3.0
@export var enemy_recovery_off_seconds: float = 1.5
## An enemy standing still this long without fighting has its way to the crystal checked;
## if there is none it is put back where it last was on its path (EnemyBase._check_recovery).
## Moving less than `enemy_stranded_move_epsilon` between two recovery checks is standing.
## An enemy within this of where the last recovery check found it on the navmesh is still on
## it, without asking the navmesh again (EnemyBase._near_last_good_position).
@export var enemy_recovery_still_tolerance: float = 0.5
@export var enemy_stranded_seconds: float = 8.0
@export var enemy_stranded_move_epsilon: float = 0.3
## How close a path has to end to the crystal to count as reaching it.
@export var enemy_reach_crystal_tolerance: float = 3.0
## Isolated navmesh patches smaller than this, in square metres, are not baked - the tops of
## trunks and boulders (MainController.bake_map_navigation).
@export var navmesh_min_island_area: float = 60.0

## Physics level of detail (EnemyBase._physics_process). An enemy further than this from
## every player walks its path without the physics engine and thinks only every
## `enemy_far_think_stride` physics ticks. Kept above enemy_ranged_detection_range, so
## anything close enough to notice a player - and shoot at one - is always fully simulated.
## The hysteresis is how much further it has to get before dropping back to far again.
@export var enemy_physics_lod_distance: float = 40.0
@export var enemy_physics_lod_hysteresis: float = 5.0
@export var enemy_far_think_stride: int = 3
## Slower than this, an enemy counts as standing (EnemyBase._standing_settled): it stops, and
## standing on the floor it skips move_and_slide altogether.
@export var enemy_min_move_speed: float = 0.15
## Near a player but not fighting one (EnemyBase._near_but_not_engaged): further than this
## from every player and not targeting one, an enemy thinks every
## `enemy_near_idle_think_stride` physics ticks. It still moves every tick.
## Animation level of detail (EnemyBase._process): an enemy in view and within this many
## metres of the camera animates every frame; one further off every `far_stride` frames; one
## out of view every `offscreen_stride` frames. The skipped time is not lost - see there.
@export var enemy_anim_full_distance: float = 25.0
@export var enemy_anim_far_stride: int = 2
@export var enemy_anim_offscreen_stride: int = 4
@export var enemy_engaged_distance: float = 12.0
@export var enemy_near_idle_think_stride: int = 2
## Crowd queueing (EnemyBase._queue_in_crowd): an enemy that walks and makes less than this
## share of the ground it meant to cover, `enemy_blocked_ticks` physics ticks running, stands
## and waits `enemy_blocked_wait` seconds before trying again.
@export var enemy_blocked_progress: float = 0.25
@export var enemy_blocked_ticks: int = 8
@export var enemy_blocked_wait: float = 0.4
## How far above and below a far enemy's feet its ground ray reaches (EnemyBase._ground_below).
## Enough for a tick of walking up or down the steepest slope the navmesh takes; short
## enough to start below the top of a rock rather than above it.
@export var enemy_far_ground_probe_up: float = 0.8
@export var enemy_far_ground_probe_down: float = 2.0

## The most physics ticks the engine runs in one frame to catch up (Godot's default is 8).
## When a tick costs more than its own 16.7 ms, catching up only makes the next frame
## longer still: at 8 a crowd that overran the budget fell to 5 fps. At 3 the game runs
## briefly slower instead, and recovers.
@export var max_physics_steps_per_frame: int = 3

## Death launch (EnemyBase._start_death_launch): a killed enemy is thrown away from what
## killed it, in an arc, lands, skids and stays where it comes to rest - so a kill has weight.
## How hard is the fatal hit's damage as a fraction of the enemy's full health, read between
## `severity_min` (a light finishing tap: the smallest throw) and `severity_full` (anything at
## or over it: the biggest). A knockback already on the enemy counts towards it too.
@export var enemy_death_launch_severity_min: float = 0.1
@export var enemy_death_launch_severity_full: float = 0.9
## Horizontal and upward speed, m/s, at the two ends of that range.
@export var enemy_death_launch_speed_min: float = 2.0
@export var enemy_death_launch_speed_max: float = 7.0
@export var enemy_death_launch_up_min: float = 1.5
@export var enemy_death_launch_up_max: float = 4.5
## How quickly a body that has landed skids to a stop, m/s per second.
@export var enemy_death_launch_friction: float = 14.0
## The impact frame: the body holds still this long before it flies, which is what makes
## the hit read as a hit rather than as the body simply setting off.
@export var enemy_death_hitstop: float = 0.07
## How much of its death clip a thrown body has played by the time it lands. The clip is
## sped up through the flight to get there: at its own pace a body that flew for a second
## came down still standing and only then keeled over.
@export var enemy_death_launch_clip_at_landing: float = 0.7
## How far the body leans into the throw at the top of its arc, degrees.
@export var enemy_death_launch_lean_degrees: float = 55.0
## A landing faster than this, m/s downward, throws up dust (and above twice it, a thud).
@export var enemy_death_land_dust_speed: float = 4.0

# ============================================================
# BEASTS
# ============================================================
# Wild beasts living in the biomes, independent of the waves (docs/BEASTS_PLAN.md). They are
# enemies of class "Beast" (scripts/beast_database.gd): they never walk to the crystal, never
# count towards a wave, and fall back to their home - where they were put down - when
# nothing is in reach. Their own stats are per species in BeastDatabase.SPECIES.

## How close a player, myr or decoy has to come before a beast goes for it, metres.
@export var beast_aggro_radius: float = 11.0
## Within this of where it is walking - home, or a spot it wanders to - a beast has arrived, metres.
@export var beast_home_arrive_distance: float = 2.0

# --- Size ------------------------------------------------------------------------------------
#
# Every beast is rolled a size when it spawns, 1x up to beast_size_max, and the later the wave
# the bigger it may come: the largest size possible climbs from beast_size_cap_start at wave 1
# to beast_size_max at beast_size_cap_full_wave, and within that cap small stays more likely
# than big (beast_size_skew). See BeastDatabase.roll_size.
#
# Size is strength. Health grows faster than damage, so a giant is mostly a long fight rather
# than a one-shot; it reaches as far as it is big, and notices, wanders and chases about the
# square root of that further. It also animates slower, the way a boss does.

@export var beast_size_max: float = 5.0
@export var beast_size_cap_start: float = 1.5
@export var beast_size_cap_full_wave: int = 25
## Exponent on the roll's random draw: 1 is even across the range, higher favours small.
@export var beast_size_skew: float = 2.0
## Health and damage multiply by size to these powers: at 5x, about 8x health and 3x damage.
@export var beast_size_health_exponent: float = 1.3
@export var beast_size_damage_exponent: float = 0.7
## Movement speed multiplies by size to this power - a giant covers more ground per stride.
@export var beast_size_speed_exponent: float = 0.35
## Animation playback slows by size to this power, clamped to beast_size_anim_min.
@export var beast_size_anim_exponent: float = 0.4
@export var beast_size_anim_min: float = 0.5
## From this size on a beast is an alpha, and its health bar says so.
@export var beast_alpha_size: float = 3.0

# --- Voice -------------------------------------------------------------------------------------
#
# One set of beast sounds (SoundBank's beast_* events), played on every screen through
# NetFx.sound and pitched down by size: size to beast_voice_pitch_exponent, never below
# beast_voice_pitch_min - a 5x giant at about 0.62.

@export var beast_voice_pitch_exponent: float = 0.3
@export var beast_voice_pitch_min: float = 0.55
## Seconds between idle growls while a beast rests or wanders (random in between) - only
## voiced with a player within beast_growl_hear_distance metres, so nobody pays the network
## for a growl nobody can hear.
@export var beast_growl_interval_min: float = 8.0
@export var beast_growl_interval_max: float = 18.0
@export var beast_growl_hear_distance: float = 45.0
## Seconds before a beast roars at a new target again.
@export var beast_roar_cooldown: float = 8.0

# --- Spawning (WildlifeManager) ---------------------------------------------------------------
#
# Each biome keeps up to beast_max_per_biome beasts, waves and Upkeep alike. A beast's home is a
# navmesh point inside its biome's wedge, well off the lane the waves walk, away from the hub,
# from water, from the other beasts' homes, and out of every player's sight when it appears.

@export var beast_max_per_biome: int = 2
## Seconds into the match before the first beasts appear, and between two in the same biome.
@export var beast_first_spawn_delay: float = 20.0
@export var beast_spawn_stagger: float = 8.0
## Seconds after a beast dies before its biome replaces it (random in between).
@export var beast_respawn_min: float = 60.0
@export var beast_respawn_max: float = 120.0
## How often the biomes are checked for a beast to add, seconds.
@export var beast_spawn_check_interval: float = 2.0
## A home is at least this far from any lane's enemy path, metres.
@export var beast_lane_clearance: float = 22.0
## ...this far from the crystal - the hub belongs to the defence...
@export var beast_min_crystal_distance: float = 75.0
## ...this far from every player, so nothing pops into being on screen...
@export var beast_spawn_player_distance: float = 45.0
## ...and this far from every other beast's home, so territories do not overlap.
@export var beast_home_spacing: float = 30.0
## Degrees kept clear of the seams between two biomes' wedges.
@export var beast_wedge_margin_degrees: float = 6.0
## Random points tried per biome per check before it waits for the next one.
@export var beast_spawn_attempts: int = 12
## Milliseconds of home-searching per physics tick. A check runs over as many ticks as it needs,
## so this bounds what spawning can add to one frame (one try can overrun it by its own queries).
@export var beast_spawn_budget_ms: float = 2.0

# --- Territory -------------------------------------------------------------------------------
#
# A beast wanders about its home, fights what comes close or hits it, and gives up on a fight
# that drags it too far away: it runs home, ignoring everything, and heals on the way. Nothing
# can lure one into a lane or to the crystal.

## How far from home a beast wanders between rests, metres.
@export var beast_roam_radius: float = 8.0
## Its pace while wandering, m/s - a walk, where a fight is a run.
@export var beast_roam_speed: float = 0.7
## How long it rests at each spot before wandering on, seconds (random in between).
@export var beast_roam_wait_min: float = 4.0
@export var beast_roam_wait_max: float = 10.0
## The leash: further than this from home, metres, and it breaks off and runs home.
@export var beast_leash_radius: float = 25.0
## Healed per second while it runs home, as a share of its maximum health. It arrives full
## whatever this is; this is how much a fight can still get out of it on the way.
@export var beast_return_heal_per_second: float = 0.25
## A player who hurts a beast is its target for this long, seconds, even from beyond its
## aggro radius - shooting one from afar does not go unanswered.
@export var beast_provoke_duration: float = 8.0

# --- Specials -------------------------------------------------------------------------------
#
# Each species has one, on its `special` clip (BeastDatabase.SPECIES): the ravagers pounce, the
# Spineback spins with its tail. Both telegraph where they hit, like a boss special, and both
# can be dodged.

## Seconds after a beast first has a target before its special can come, and between two. The
## first is short on purpose: the pounce is an opener, used while the target is still a few
## strides off - two seconds into a fight a beast has long since closed to biting range.
@export var beast_special_first_delay: float = 0.5
@export var beast_special_cooldown: float = 9.0
## The pounce: only at a target between these distances, metres - closer than that it bites.
@export var beast_pounce_min_range: float = 4.5
@export var beast_pounce_max_range: float = 10.0
## Playback speed of the pounce clip. Its landing is 0.44 of the way in, so at 0.8 the
## telegraph fills in about 0.9 s - the time there is to step out of it.
@export var beast_pounce_clip_speed: float = 0.8
@export var beast_pounce_radius: float = 2.2
@export var beast_pounce_damage_mult: float = 1.6
## Seconds the pounce slows whoever it lands on.
@export var beast_pounce_slow: float = 1.0
## The tail spin: used on a target within this, metres.
@export var beast_spin_range: float = 3.5
## The ring the tail sweeps, metres from the beast.
@export var beast_spin_radius: float = 3.4
@export var beast_spin_clip_speed: float = 1.0
@export var beast_spin_damage_mult: float = 1.4

# ============================================================
# BOSSES
# ============================================================
# Bosses animate slower the bigger they are: a boss whose model_scale equals
# boss_anim_reference_scale plays at 1.0x, larger ones play slower and smaller
# ones faster. boss_anim_scale_strength dials how strongly size matters (0.0
# disables the effect entirely, 1.0 makes playback speed inversely proportional
# to scale). Result is clamped so a very large boss never crawls to a halt.
@export var boss_anim_reference_scale: float = 2.4
@export var boss_anim_scale_strength: float = 1.0
@export var boss_anim_speed_min: float = 0.55
@export var boss_anim_speed_max: float = 1.35
## A boss walks at the pace its walk clip steps (BossDatabase.walk_speed) times this.
@export var boss_walk_pace: float = 1.0

# Special (dodgeable) attacks. Each boss telegraphs a danger zone for
# boss_special_windup_* seconds before the hit lands - that window is the dodge.
@export var boss_special_cooldown: float = 9.0
@export var boss_special_first_delay: float = 5.0
## Unused since each special carries its own `min_range` (BossDatabase.SPECIALS). Kept as the
## documented default a new special should be written against: the big area attacks are all
## held back to this so the melee special owns the point-blank band.
@export var boss_special_min_range: float = 3.0
@export var boss_special_damage_mult: float = 2.0
# Bigger bosses wind up proportionally longer (they also animate slower), so the
# telegraph stays readable instead of the hit landing before the animation reads.
@export var boss_special_windup_scale_with_anim: bool = true

# --- Boss phases -------------------------------------------------------------------------
#
# Every boss fights in three phases, split at these shares of its maximum health. A phase
# change is one-way (like Enrage always was) and is never skipped over silently: a hit big
# enough to cross both lines at once goes straight to phase 3 with one transition, not two.
# What each phase actually changes lives per colour in BossDatabase.SPECIALS / PHASES.
@export var boss_phase2_threshold: float = 0.66
@export var boss_phase3_threshold: float = 0.33
## The transition: the boss stops, roars, and lets out a telegraphed shockwave. It waits for
## whatever special is already in flight to finish rather than cutting it off.
@export var boss_phase_shockwave_radius: float = 8.0
@export var boss_phase_shockwave_damage_mult: float = 0.6
@export var boss_phase_shockwave_windup: float = 1.2
@export var boss_phase_transition_seconds: float = 1.6
## A special that has just come into play is ready this soon after the transition, so the new
## phase announces itself with its new attack rather than waiting out a full cooldown.
@export var boss_phase_special_delay: float = 2.0

## White's Shield Wall (phase 2 on): damage arriving from in front of the paladin, inside this
## arc, is reduced by this much. Walk round him. Gone while he is exhausted.
@export var boss_shield_wall_reduction: float = 0.7
@export var boss_shield_wall_arc_degrees: float = 120.0

## Green's saplings (phase 2): stationary small treants (the boss's own model, at
## boss_sapling_scale_mult of the boss's size, with Green melee stats) that each heal the treant by
## boss_sapling_heal_pct of its maximum health if they are still standing after
## boss_sapling_heal_delay seconds. Ordinary Green melee health, so a player who turns to them
## can clear one well inside the window.
@export var boss_sapling_count: int = 3
@export var boss_sapling_heal_delay: float = 10.0
@export var boss_sapling_heal_pct: float = 0.05
@export var boss_sapling_scale_mult: float = 0.4
@export var boss_sapling_ring_radius: float = 4.5

## Regeneration: a boss nothing has hurt for boss_regen_delay seconds heals this share of its
## maximum health per second until it is hit again. Hit-and-run used to be free - see
## EnemyBase._tick_boss_regen.
@export var boss_regen_delay: float = 8.0
@export var boss_regen_pct_per_second: float = 0.02

## Black's Raise Dead: what a raised corpse gets back of an ordinary Black melee's health.
@export var boss_raise_dead_health_mult: float = 0.5

# --- Boss modifiers ----------------------------------------------------------------------
#
# A named, MTG-flavoured trait a boss can spawn with - Elite's own equivalent
# (apply_elite_modifier) never touches bosses at all (_assign_elites excludes them), and a
# boss's whole kit is its two telegraphed specials rather than ordinary stats, so a boss
# modifier reshapes THAT: how often each special comes round, how hard it hits, how wide it
# reaches, whether it wins out over its partner. At most one per boss, same as Elite - see
# EnemyBase.apply_boss_modifier for what each one actually does.
@export var boss_modifier_chance: float = 0.4
## The boss at wave_boss_interval (wave 5) is always plain; modifiers start from the one
## after it, the same one-quiet-example-first pattern wave_elite_start_wave and
## wave_miniboss_start_wave already use.
@export var boss_modifier_start_wave: int = 10

## Riot: both specials recycle much faster and the clip itself plays faster - shorter
## windups as well as shorter cooldowns - traded against noticeably less damage per hit.
## Frantic rather than dangerous.
@export var boss_modifier_riot_cooldown_mult: float = 0.65
@export var boss_modifier_riot_damage_mult: float = 0.8
@export var boss_modifier_riot_anim_speed_mult: float = 1.3

## Annihilator: the opposite trade. Long waits between specials, but each one hits far
## harder and reaches further - patience is rewarded, standing in it is not.
@export var boss_modifier_annihilator_cooldown_mult: float = 1.5
@export var boss_modifier_annihilator_damage_mult: float = 1.9
@export var boss_modifier_annihilator_radius_mult: float = 1.15

## Cataclysm: the big area special comes round much faster and the short-range melee one
## much slower - a boss that would rather control space than get close.
@export var boss_modifier_cataclysm_big_cooldown_mult: float = 0.6
@export var boss_modifier_cataclysm_melee_cooldown_mult: float = 1.6

## Bloodthirst: the inverse of Cataclysm - the melee special (the one that can actually
## damage the crystal) comes round much faster, the big one much slower. An aggressive
## boss that would rather close the distance and go for the objective.
@export var boss_modifier_bloodthirst_melee_cooldown_mult: float = 0.55
@export var boss_modifier_bloodthirst_big_cooldown_mult: float = 1.4

## Enrage: now that every boss has phases, Enrage is a boss that gets to them EARLY and hits
## harder once it is there. Its phase 2 begins at the first share of max health and its phase 3
## at the second (instead of boss_phase2_threshold / boss_phase3_threshold), and reaching
## phase 3 latches a permanent damage step on top. One-way, like every phase change.
@export var boss_modifier_enrage_phase2_threshold: float = 0.75
@export var boss_modifier_enrage_health_threshold: float = 0.45
@export var boss_modifier_enrage_damage_mult: float = 1.25

## Lifelink: heals a share of a special's nominal damage back whenever that special lands
## on at least one player. Flat per resolve rather than per player hit, so it does not
## scale up against a bigger team the way a per-target heal would.
@export var boss_modifier_lifelink_pct: float = 0.35

## Absolute floor under every special's windup, regardless of how much a modifier or the
## boss's own size shrinks it - the one number this whole system is not allowed to push a
## telegraph below, so "faster" never quietly becomes "undodgeable."
@export var boss_modifier_min_windup_seconds: float = 0.6

# ============================================================
# COMBAT FEEDBACK
# ============================================================
# Ground decals marking a boss special attack's danger zone during its windup.
# Turning this off removes the visual tell, making specials much harder to dodge.
@export var show_attack_indicators: bool = true
## How a telegraph is drawn when shown at all - see AttackIndicator.STYLES. Set from the
## options menu through UserSettings.
@export var attack_indicator_style: String = "themed"
@export var attack_indicator_height: float = 0.08
@export var camera_shake_enabled: bool = true
@export var camera_shake_strength_mult: float = 1.0
# Heavy hits (boss melee and boss specials) shake harder than chip damage.
@export var camera_shake_heavy_strength: float = 0.42
@export var camera_shake_heavy_duration: float = 0.45
@export var camera_shake_light_strength: float = 0.12
@export var camera_shake_light_duration: float = 0.22
@export var camera_shake_frequency: float = 26.0
## The player's own melee connecting. Much smaller than being hit: this fires on every
## landed swing, several times a second through a chain, so anything larger reads as
## the camera being broken rather than as weight.
@export var camera_shake_melee_strength: float = 0.09
## The heavy spin and the chain's third stage, which land far less often.
@export var camera_shake_melee_heavy_strength: float = 0.2
@export var camera_shake_melee_duration: float = 0.16

## SSAO (GraphicsSettings.apply_ssao): metres it reaches, how dark, and how hard the falloff.
@export var graphics_ssao_radius: float = 1.2
@export var graphics_ssao_intensity: float = 1.8
@export var graphics_ssao_power: float = 1.5
## Volumetric fog (Ultra, GraphicsSettings.apply_volumetric_fog): how thick, and how far out
## it is computed - light shafts, not haze.
@export var graphics_volumetric_fog_density: float = 0.012
@export var graphics_volumetric_fog_length: float = 64.0

# ============================================================
# GRAPHICS - BLOOM
# ============================================================
## What GraphicsSettings.apply_glow puts on the map's environment when the player has
## Bloom / Glow on. The Sky3D environment ships with no glow at all, and the engine's
## defaults bloom the whole daytime sky - the point is the opposite: only what is brighter
## than `graphics_glow_hdr_threshold` blooms, which is the hot core of a spell and the sun.
@export var graphics_glow_intensity: float = 0.9
@export var graphics_glow_strength: float = 1.0
## Bloom lifts EVERYTHING by this fraction, threshold or not, so it stays off: a spell
## glowing is the effect, the whole frame glowing is fog.
@export var graphics_glow_bloom: float = 0.0
@export var graphics_glow_hdr_threshold: float = 1.0
@export var graphics_glow_hdr_scale: float = 2.0
## Screen: never brighter than white, so it cannot wash a noon sky out - and, unlike soft
## light, it still shows against a DARK one. Soft light was tried first and is a contrast
## blend: on the night half of the Sky3D cycle it added nothing at all (measured with
## tools/tests/vfx_showcase.tscn -- <out.png> --glow, mean pixel change 0.3/255).
@export var graphics_glow_blend_mode: Environment.GlowBlendMode = Environment.GLOW_BLEND_MODE_SCREEN

## Terrain parallax (the TerraBrush shader patch, see GraphicsSettings.apply_terrain_parallax).
## Depth is how far, in metres, the darkest point of a ground texture's height map sits below
## its brightest: enough for stones to stand out of the mud, not so much that the ground looks
## like it is made of pebbles. Range is how far from the camera it reaches - it fades out over
## the last 40% of that, and nothing beyond pays for it.
@export var graphics_terrain_parallax_depth: float = 0.1
@export var graphics_terrain_parallax_range: float = 30.0

## Grass distance (GraphicsSettings.grass_distance): how far grass is drawn at Near, Medium
## and Far, in metres. Far is the distance the foliage layers were authored with; a value
## above that is held to it.
@export var graphics_grass_distances: Array[float] = [25.0, 35.0, 50.0]

## Particle effects (GraphicsSettings.particle_quality): how many particles every effect
## spawns at each setting - Low, Medium, High, Ultra - as a fraction of what it was authored
## with. Below 1 thins the effect out; Ultra raises its count. An effect authored with only a
## handful never drops below `graphics_particle_min_amount`, so nothing vanishes outright.
@export var graphics_particle_quality_scale: Array[float] = [0.3, 0.6, 1.0, 1.6]
@export var graphics_particle_min_amount: int = 3

## Ragdolls (EnemyRagdoll, GraphicsSettings.ragdoll_quality): how many may simulate at once
## at each setting - Off, Limited, Full. Past the cap a kill gets the ordinary thrown death.
@export var ragdoll_max_active: Array[int] = [0, 6, 16]
## At Limited only the big kills go limp: a throw at least this fast sideways, m/s (the
## death launch runs from enemy_death_launch_speed_min to _max).
@export var ragdoll_limited_min_launch_speed: float = 4.5
## A ragdoll simulates at least this long, and freezes once it is still or this long at most.
@export var ragdoll_min_seconds: float = 1.0
@export var ragdoll_max_seconds: float = 4.0

# ============================================================
# RUN REWARDS
# ============================================================
# ============================================================
# XP, LEVELS AND SKILL POINTS
# ============================================================
## XP is shared by the whole team and every kill feeds one pool, so levels arrive for
## everyone at the same moment. Each level grants every player one skill point.
@export var xp_per_basic: float = 10.0
@export var xp_per_elite: float = 40.0
@export var xp_per_boss: float = 250.0
@export var xp_per_camp: float = 120.0
## A wild beast, at 1x - an elite's worth. Its XP and mana grow with its size to
## beast_reward_size_exponent, so a 5x giant pays about a boss's XP.
@export var xp_per_beast: float = 40.0
@export var beast_reward_size_exponent: float = 1.0
## Total XP to reach level N is base*(N-1) + growth*(N-1)^2 - superlinear, so early
## levels land every wave or two and late ones take three or four. Target is roughly
## 15-18 levels across a full run.
@export var xp_level_base: float = 90.0
@export var xp_level_growth: float = 26.0

# ============================================================
# TEAM MANA
# ============================================================
## Banked automatically on kill, in the dead enemy's own colour. There is no pickup:
## the pool is shared, so there is nobody for a drop to belong to and no reason to make
## anyone walk to it.
##
## ORDINARY enemies pay nothing. They used to pay 1 each, which sounds small and was not:
## a wave of ninety trash enemies banked ~100 mana in two minutes, against the ~0.5 a
## level-1 myr brings home in the same time. Kill income was the economy and the myrs were
## a rounding error, which is the opposite of the intent. What is left pays out only for
## the kills that were worth making - and pays visibly, see RunState.on_enemy_killed.
@export var mana_per_basic: int = 0
## What the pool starts a run with, in EVERY colour (docs/ONBOARDING_PLAN.md). One of each
## rather than a lump of one: the five colours are in the pool from the first second, and a
## myr costs colourless, so it still buys two - the first objective, before any elite has died.
@export var run_starting_mana_per_color: int = 1
@export var mana_per_elite: int = 4
@export var mana_per_boss: int = 25
## A wild beast at 1x, in its biome's colour; grows with size like its XP. Which biome the team
## hunts in decides which colour it earns.
@export var mana_per_beast: int = 6
@export var mana_per_camp: int = 12

# ============================================================
# UPKEEP
# ============================================================
## The build phase between waves: the only time mana can be spent, and the one moment
## each wave the whole team is in the same place. Replaces a 3-second rest that was long
## enough for nothing.
## How often the server pushes the economy to clients. Kills arrive far faster than a
## HUD can read, so the pool is flushed at a fixed rate rather than once per enemy.
@export var run_state_sync_interval: float = 0.25
@export var upkeep_duration: float = 30.0
## What the team pays for one skill point FOR EVERY PLAYER, in any colour.
@export var upkeep_skill_point_cost: int = 25
## Crystal repair. The only way to undo leakage, and deliberately a PURCHASE rather than
## an automatic scaling: the crystal is one shared objective whose maximum stays the same
## whether one player is defending it or five, so a team that leaks pays to fix it out of
## the same pool it wanted to spend on enchantments. That trade is the point.
@export var upkeep_crystal_repair_amount: float = 200.0
@export var upkeep_crystal_repair_cost: int = 8

# ============================================================
# ENCHANTMENTS
# ============================================================
## Permanent, stackable, global. Bought at Upkeep in their own colour, which is what
## makes lane choice strategic rather than only tactical.
@export var enchantment_base_cost: int = 8
@export var enchantment_cost_step: int = 6
## Red - Furnace of Rath: every player deals more damage. The benchmark buy.
@export var enchantment_red_damage: float = 0.08
## ...and myrs move faster. The myr economy's one real bottleneck is the round trip -
## ~112 of its ~123 seconds is walking - so this is the stack that buys throughput.
@export var enchantment_red_myr_speed: float = 0.07
## Blue - Propaganda: enemies attack and cast more slowly. Scales into the late game.
@export var enchantment_blue_attack_slow: float = 0.06
## ...and a LOADED myr phases out of reach for this long, per stack, each time it is hit.
## The hit that starts the phase still lands - this buys the follow-ups, not the first
## swing - and it does nothing at all for a myr walking out empty. Blue defends the cargo;
## White (below) defends the creature.
@export var enchantment_blue_myr_phase: float = 0.5
## Black - Animate Dead: a fallen player is back sooner. Each stack takes this share off
## the time spent down (multiplayer: until the respawn at the base; solo: the death
## penalty) AND off a teammate's revive channel. It was Exquisite Blood - team lifesteal -
## until 2026-10-20: that doubled Vampiric Link, black's own affinity, and healed from every
## area hit, so a spell into a full wave paid it out many times over.
@export var enchantment_black_undeath: float = 0.12
## The most Animate Dead takes off however many stacks are bought - 12% a stack reaches it
## at the fifth. Stacks past that still grow the myrs' death blast.
@export var enchantment_black_undeath_cap: float = 0.6
## ...and a myr that dies takes the neighbourhood with it. The one myr effect that pays
## out when every other one has already failed.
@export var enchantment_black_myr_blast_damage: float = 35.0
@export var enchantment_black_myr_blast_radius: float = 3.5
@export var enchantment_black_myr_blast_radius_per_stack: float = 0.4
## White - Sphere of Safety: enemies near the crystal hurt it less. Does nothing while
## the team is winning; saves the run when they are not.
@export var enchantment_white_reduction: float = 0.08
@export var enchantment_white_radius: float = 2.0
## ...and myrs take less damage, by the same fraction per stack the crystal gets. Flat
## armour that always applies, loaded or not.
@export var enchantment_white_myr_reduction: float = 0.08
## Ceiling on that reduction however many stacks are bought. Short of immunity on purpose:
## a myr that cannot die removes the reason to protect the lane it walks.
@export var enchantment_white_myr_reduction_cap: float = 0.7
## Green - Overgrowth: the ECONOMY enchantment, and the only one that changes what the
## team can build rather than a number on a fight.
##
## Extra myr slots on EVERY well, per stack. The hard cap on the myr economy is not the
## myr count (10) but the five-times-five harvesting slots underneath it, so this is the
## stack that actually lets a team commit to myrs.
@export var enchantment_green_well_slots: int = 1
## Boss mana, per stack. There used to be a general "+12% to all income" here as well, and
## the two compounded: at two stacks a 25-mana boss paid 53. Overgrowth is the slots and
## the bosses now, and nothing else, so what a stack is worth can be read off the row.
@export var enchantment_green_boss_mana: float = 0.15

## The colour each lane reads as on screen, here so anything that has to tint itself by lane -
## a loaded myr's glow, a banner, a well - can agree without copying them again.
const LANE_TINTS: Dictionary = {
	"White": Color(0.95, 0.95, 0.85),
	"Blue": Color(0.25, 0.55, 1.0),
	"Black": Color(0.65, 0.35, 0.8),
	"Red": Color(1.0, 0.25, 0.2),
	"Green": Color(0.25, 0.85, 0.35),
}


## A colour's affinity bonus at `rank` - see affinity_cap for what it is a share of.
func affinity_bonus(color: String, rank: int) -> float:
	var cap: float = float(affinity_cap.get(color, 0.0))
	if rank <= 0 or cap <= 0.0:
		return 0.0
	var keep: float = 1.0 - float(affinity_first_rank.get(color, 0.0)) / cap
	return cap * (1.0 - pow(clampf(keep, 0.0, 1.0), float(rank)))


func lane_tint(color: String) -> Color:
	return LANE_TINTS.get(color, Color.WHITE)


const ENCHANTMENT_NAMES: Dictionary = {
	"White": "Sphere of Safety",
	"Blue": "Propaganda",
	"Black": "Animate Dead",
	"Red": "Furnace of Rath",
	"Green": "Overgrowth",
}
## What each enchantment does, as a TEMPLATE rather than a sentence: RunState fills in the
## numbers for the stacks actually owned and for the one being sold. A static description
## cannot answer the only question the Upkeep shop is asked - "is another stack worth it?"
## - which is exactly the question a stackable effect lives or dies on.
##
## Both halves of each colour are named, the original effect and the myr one, because a
## player choosing between colours is choosing between whole packages.
const ENCHANTMENT_DESCRIPTIONS: Dictionary = {
	"White": "Enemies near the crystal deal %s less damage to it; myrs take %s less damage",
	"Blue": "Enemies attack and cast %s more slowly; a loaded myr phases out of reach for %s after each hit",
	"Black": "Time spent downed and the revive channel are %s shorter; a dying myr explodes for %s",
	"Red": "Every player deals %s more damage; myrs move %s faster",
	"Green": "%s on every well; bosses drop %s more mana",
}


# ============================================================
# MYRS
# ============================================================
@export var myr_max_hp: float = 75.0
@export var myr_speed: float = 2.0
@export var myr_harvest_time: float = 10.0
@export var myr_deposit_time: float = 1.0
@export var myr_mana_cost: int = 2
## How many myrs can exist at once. A hard cap rather than a soft economic one: past this
## the base screen stops being a list anybody reads, and five wells of five slots cannot
## usefully absorb more than this many anyway.
@export var myr_max_count: int = 10
## Levels are bought per myr in the base. Rank 1 is the myr as built.
@export var myr_max_level: int = 5
## Flat health added per level past the first. A levelled myr is meant to SURVIVE a leaked
## enemy, which is the thing that actually costs the player a harvest run.
@export var myr_level_hp_bonus: float = 25.0
## Extra mana carried home per trip, per level. At 1 a level-3 myr brings back three where
## it used to bring one - the levelling is worth more than a second myr long before the
## count cap is reached, which is the point of having a cap at all.
@export var myr_level_carry_bonus: int = 1
## Mana the next level costs, multiplied by the level being bought - so 2, 4, 6, 8.
@export var myr_level_cost: int = 2
## How much bigger each level past the first makes a myr. The one part of a level the
## player can see from across the lane without opening the base screen - a myr carrying
## three mana should not look like one carrying one. At 0.09 a maxed myr is 1.36x, which
## still reads as the same creature.
@export var myr_level_scale_bonus: float = 0.09
## A well has room for this many Myrs standing around it, Warcraft-mine style. More
## than that is what wedged them against the model, so the base UI refuses the sixth.
@export var myr_well_max_slots: int = 5
## How far from the well's centre the harvest slots sit. Far enough that five bodies
## never overlap each other or the well's own collision.
@export var myr_well_slot_radius: float = 2.3

# --- Fleeing (docs/MYR_GUARDS_PLAN.md) --------------------------------------------------
# A worker cannot fight, and at 2 m/s it cannot outrun anything either - so it leaves early.
# Behind its lane's guard if it has a living one, home to the crystal if not; a loaded one
# simply runs the rest of the way home and delivers.
## A hostile enemy closer than this sends a worker running - further out than a melee enemy
## notices it (enemy_melee_detection_range), so it is gone before it is seen. Any enemy that
## has already picked it as its target sends it running from any distance (the ranged ones).
@export var myr_flee_radius: float = 20.0
## A wild beast is only run from this close - its own aggro radius and this margin - since it
## keeps to its home and only goes for what comes near it.
@export var myr_beast_flee_margin: float = 5.0
## ...and it goes back to work once nothing hostile has been inside THIS for myr_return_delay
## seconds. A second, wider radius so it does not dither on the edge of the first.
@export var myr_return_radius: float = 28.0
@export var myr_return_delay: float = 3.0
## How much faster than its walk a fleeing myr runs.
@export var myr_flee_speed_mult: float = 1.5
## How often a myr looks around for danger, seconds. Server only.
@export var myr_danger_check_interval: float = 0.25
## A guard below this share of its health is no shelter; the workers run home instead.
@export var myr_guard_shelter_min_health: float = 0.25
## How far behind its guard - on the side away from the threat - a sheltering worker stands.
@export var myr_guard_shelter_distance: float = 2.5

# --- Guards ------------------------------------------------------------------------------
# Myrs that do not harvest: assigned a lane like a worker, they stand at its well and take on
# what threatens the workers there. At most one per lane, on a cap of their own (one per lane),
# never in the ten workers' or the wells' slots. Bodyguards, not a defensive line: leashed to
# their post, tuned for a few enemies and not a squad, and a storming wave walks past them.
## How far from its post a guard will go after something, and how far the post stands from
## the well, out towards where the enemies come from.
@export var myr_guard_leash: float = 10.0
@export var myr_guard_post_distance: float = 4.0
## An enemy attacking one of the lane's workers is taken on this much further out than the leash.
@export var myr_guard_rescue_leash_mult: float = 1.5
@export var myr_guard_speed: float = 3.2
## Reach of a guard's blow, from its centre, before its size is counted.
@export var myr_guard_attack_range: float = 2.2
## Extra damage per level past the first, as a share. Health grows by myr_level_hp_bonus, as
## a worker's does.
@export var myr_guard_level_damage_bonus: float = 0.15
## Myr Enforcer: the tank and the shelter. Affinity for artifacts - it costs one less for every
## worker myr the team has standing, never less than the floor.
@export var myr_enforcer_hp: float = 250.0
@export var myr_enforcer_damage: float = 12.0
@export var myr_enforcer_attack_interval: float = 1.2
@export var myr_enforcer_cost: int = 7
@export var myr_enforcer_cost_min: int = 2
## Enemies inside this that are attacking one of its workers are taunted onto the Enforcer,
## through the same taunt Roar uses, for this long; re-applied while it fights.
@export var myr_enforcer_taunt_radius: float = 8.0
@export var myr_enforcer_taunt_duration: float = 3.0
## How much bigger than a worker the placeholder model is drawn (the real one comes later).
@export var myr_enforcer_scale: float = 1.5
## Lodestone Myr: the fighter. Draws on the workers harvesting around it - a harvesting myr is
## a tapped artifact - for more damage per blow, up to the cap.
@export var myr_lodestone_hp: float = 120.0
@export var myr_lodestone_damage: float = 20.0
@export var myr_lodestone_attack_interval: float = 1.0
@export var myr_lodestone_cost: int = 4
@export var myr_lodestone_bonus_per_worker: float = 0.25
@export var myr_lodestone_bonus_cap: float = 1.0
@export var myr_lodestone_bonus_radius: float = 8.0
@export var myr_lodestone_scale: float = 1.25

# --- The Graveyard -----------------------------------------------------------------------
## A dead myr - worker or guard - can be returned from the team's Graveyard for this share of
## everything that was put into it (built and levelled), never less than a new myr. A maxed
## worker (30 invested) comes back for 10.
@export var myr_return_cost_fraction: float = 0.3333

# ============================================================
# PROJECTILES
# ============================================================
@export var projectile_pool_size: int = 20
@export var projectile_base_speed: float = 30.0
@export var projectile_base_damage: float = 50.0
@export var projectile_base_lifetime: float = 2.5
@export var projectile_shock_speed_mult: float = 1.5
@export var projectile_unsummon_speed_mult: float = 0.8
@export var projectile_enemy_speed_mult: float = 0.5
@export var projectile_enemy_damage_mult: float = 0.2

# ============================================================
# MINIMAP
# ============================================================
@export var minimap_update_interval: float = 0.15

# --- Fog of war (scripts/fog_of_war.gd) ------------------------------------------------------
#
# The minimap only shows what the team can see. Players, myrs, the team's own summons and the
# crystal each see a circle around them, shared by everyone; an enemy - wave or beast - is on
# the minimap only inside one of those circles. Ground anyone has seen stays uncovered for the
# rest of the run, dimmed while nobody is looking at it; ground nobody has seen is dark.
# Explorer's Scope still shows the beasts anywhere.
@export var fog_of_war_enabled: bool = true
## Sight radii, metres.
@export var fog_vision_player: float = 45.0
@export var fog_vision_myr: float = 25.0
@export var fog_vision_ally: float = 15.0
@export var fog_vision_crystal: float = 60.0
## How often the sight circles and the explored map are brought up to date, seconds.
@export var fog_update_interval: float = 0.2
## How dark the minimap draws ground nobody has seen, and seen ground nobody is watching now
## (0 = as the map, 1 = black).
@export var fog_unexplored_darkness: float = 0.85
@export var fog_unseen_darkness: float = 0.45

# ============================================================
# UI & DEBUG
# ============================================================
@export var show_damage_numbers: bool = true
## Debug: everything in the skill tree is free and ungated. Costs nothing, requires
## no affinity rank, and spends no mana - for trying builds out without farming them.
## Deliberately not persisted: it resets to off every launch, so it cannot be left on
## by accident. Toggled from the in-game options panel.
@export var debug_free_skills: bool = false
## Debug: the wave a run starts at, 1 being the ordinary opening. Set from the in-game
## options panel, which can also jump the current run there on the spot. Not persisted,
## for the same reason as debug_free_skills - but it does outlive a restart, so testing
## wave 15 over and over does not mean setting it again every run.
@export var debug_start_wave: int = 1
## Debug: how high the options panel's team level can be set (RunState.debug_set_team_level),
## for trying a class's skills - they arrive at class_skill_levels - without levelling up.
@export var debug_max_team_level: int = 30
## Set by the main menu on its way into a run, cleared by the map once it has looked: the
## intro camera flight plays for a run entered from the menu, never on Restart or in a test
## scene that loads the map directly. See IntroTour.
var intro_tour_pending: bool = false
## Seconds between the crystal's health reaching zero and the game-over panel: the time the
## crystal's destruction plays out in (MainController._destroy_crystal).
@export var crystal_death_seconds: float = 3.6
@export var damage_number_pool_size: int = 40
@export var show_enemy_health_bars: bool = true
@export var enemy_health_bar_height: float = 2.35
@export var debug_mode: bool = true

# ============================================================
# MULTIPLAYER SCALING
# ============================================================
@export var scale_by_players: bool = true
## Enemy DAMAGE at one player, rising to 100% at five.
##
## Deliberately shallow. Damage is the worst of the three difficulty levers to lean on,
## because it is the only one that changes what a hit COSTS - at 0.2 a Cleric's swing was
## worth 20% solo and 100% in a full team, so a player could never learn what any attack
## is actually worth; it depended on how many friends had logged in. Worse, with five
## players you are usually alone in your own lane, so it punished the individual for the
## team growing.
##
## The solo assist now comes almost entirely from facing FEWER enemies
## (wave_size_per_extra_player), which is the same help without the side effects. This
## keeps a small cushion on top, because one player genuinely cannot cover five lanes and
## some leakage is unavoidable.
@export var min_damage_scale: float = 0.75

## Multiplier on a wave's enemy budget for the number of players present. Counts the
## registry rather than the group, so an avatar mid-spawn cannot briefly inflate a wave.
##
## The PRIMARY difficulty lever, because it is the only one that uses the map: more
## enemies means more lanes under real pressure at once, which is the entire reason a
## five-player team exists. It also leaves every enemy feeling exactly as it does solo.
func get_wave_size_factor(player_count: int) -> float:
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * wave_size_per_extra_player


## Multiplier on an enemy's maximum health for the number of players present.
##
## The correction that wave size alone cannot make. Count scaling assumes players SPREAD
## OUT - one per lane, each fighting alone, killing at solo speed. The moment they group
## up, on a boss or a collapsing lane, five players focus-fire and delete each enemy
## roughly five times faster, and more enemies does not help with that.
##
## Kept modest on purpose: this is the lever that makes things spongy, and melee suffers
## most from sponginess because every swing is a committed animation.
func get_enemy_health_factor(player_count: int) -> float:
	if not scale_by_players:
		return 1.0
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * enemy_health_per_extra_player


## Wave scaling, separate from count scaling: the run getting longer is its own
## difficulty axis. Wave 1 (index 0) is exactly base health.
func get_wave_health_factor(wave: int) -> float:
	return 1.0 + float(maxi(wave, 0)) * enemy_health_per_wave


## `tree` is no longer read: PlayerRegistry already keeps the roster this used to
## rebuild. `get_nodes_in_group` allocates a fresh Array on every call, and this is called
## on every enemy attack - once per swing, per arrow, per boss special. The registry
## answers the same question by walking five entries in place. The parameter stays so the
## call sites do not all have to change.
func get_player_scaling_factor(_tree: SceneTree) -> float:
	if not scale_by_players:
		return 1.0
	var player_count = max(1, PlayerRegistry.count())
	var clamp_count = clamp(player_count, 1, 5)
	return lerp(min_damage_scale, 1.0, (clamp_count - 1) / 4.0)

# ============================================================
# BOSSES
# ============================================================
## Animation playback speed for a boss of the given model_scale - bigger bosses
## animate slower. See the boss_anim_* settings for the tunables.
func get_boss_anim_speed(model_scale: float) -> float:
	if boss_anim_scale_strength <= 0.0 or model_scale <= 0.0:
		return 1.0
	var ratio: float = boss_anim_reference_scale / model_scale
	return clampf(pow(ratio, boss_anim_scale_strength), boss_anim_speed_min, boss_anim_speed_max)

# ============================================================
# SKILL UPGRADES
# ============================================================
func get_skill_upgrade_cost(current_level: int) -> int:
	return skill_unlock_cost + (current_level * current_level * 2)

func get_skill_multiplier(current_level: int) -> float:
	return 1.0 + (current_level - 1) * 0.2


func _ready() -> void:
	Engine.max_physics_steps_per_frame = max_physics_steps_per_frame
