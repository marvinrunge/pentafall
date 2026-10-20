# Character Classes Plan

A staged plan for letting each player pick one of six playable characters. Every stage
ships something playable on its own; later stages extend the same machinery rather than
replacing it.

**The rule: a class is the WEAPON, a colour is the MAGIC.** A class decides the basic
attack, the defence, the body (health, speed) and a short track of class skills. The skill
tree's five colours and their spells stay exactly as they are and are open to every class -
an archer can play black, a mage can play green. Nothing in a colour may assume a class.

## The classes

| Class | Role | Basic attack | Defence | Status |
|---|---|---|---|---|
| **Warrior** (hatchet) | Fast combo fighter with sustain | Light combo chain, charged spin (heavy), kick | Block | The current orc - exists |
| **Knight** (sword & shield) | Tank | One-handed chain + shield | Block that stops nearly everything | Built (2026-10-18) |
| **Barbarian** (two-handed sword) | Area damage, slow and heavy | Wide slow cleaves, a held two-swing heavy | No block; cannot be interrupted mid heavy swing | Built (2026-10-18) |
| **Archer** | Ranged damage, fragile | Hold to draw, release to shoot; tap for a quick shot | Dodge roll | Built (2026-10-17) |
| **Mage** | Spell damage, fragile | A bolt in the colour of their path | Blink | Built (2026-10-19) |
| **Werewolf** (Ulrich) | Melee by day, a stronger beast by night, calls wolves | Day: like the warrior. Night: claw chain, much harder | Day: block. Night: none - more health instead | New |

The warrior and the barbarian are deliberately apart: the axe is quick and lives on its
combo chain, the barbarian's two-handed sword is slow and lives on single huge hits (which is also where the
death launch and the ragdolls pay off most).

## Class skills

Four per class, colourless, on a short track at the centre of the skill tree - the hub
Blade Dance sits on today, which `docs/SKILL_DESIGN.md` already describes as the one
purchase that changes the basic attack. That is what class skills are.

**They unlock by team level, automatically.** No mana, no skill points: levels are shared
and simultaneous (`docs/ECONOMY.md`), so every player reaches their class's next skill at
the same moment, and a late joiner or a reconnect gets every skill their level already
covers. This is the mechanism Blade Dance already runs on - granted at
`Player.BLADE_DANCE_LEVEL`, derived from the level rather than saved in the build, and
re-applied by `RunState` for anyone who arrives after the level-up.

The ECONOMY target is roughly 15-18 levels across a 25-wave run, front-loaded, so the four
unlocks sit at **levels 3, 6, 10 and 14** - the capstone arriving in the last third of a
run with room to spare. One list in `GameSettings` (`class_skill_levels`), shared by every
class.

The shape is the same for every class: a basic-attack passive first, then an active (or
the defence the class most needs), then a second passive, then a capstone. Actives go on
the quick bar like spells; on unlock one is put in the first free quick slot.

Names follow the rest of the game - real Magic cards or keywords where one fits. All are
proposals.

### Warrior

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Bloodthirst** | Passive | Kills during a combo chain heal a little and speed up the next stage |
| 6 | **Hurl Axe** | Active | The axe is thrown through the enemies in front and comes back, hitting on both legs |
| 10 | **Blade Dance** | Passive | Third stage of the light chain, landing harder (exists - stays at level 10) |
| 14 | **Battle Frenzy** | Active, capstone | For a few seconds the chain does not end as long as every stage connects |

**As built (2026-10-19).** Bloodthirst: a kill by a basic attack heals
`warrior_bloodthirst_heal` of max health on the server (`Player.on_enemy_killed_by_me`, which
now hears whether the fatal hit was a basic attack) and the next stage plays
`warrior_bloodthirst_haste` times faster (`MeleeKit.on_bloodthirst`, told to a remote warrior).
Hurl Axe: the axe's own chop (`strike_downward`) lets go of it on its impact; a networked
`hurled_axe` effect (`HurledAxe`) spins flat out to `warrior_hurl_axe_range` and back to the
thrower, hitting everything near it once each way (the server's hits), the hatchet gone from the
hand meanwhile. Battle Frenzy: for `warrior_battle_frenzy_duration` a chain that keeps
connecting does not lapse, and past its last stage the finisher comes again (`MeleeKit`).
`tools/tests/melee_kit.tscn` covers all three.

### Knight

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **First Strike** | Passive | After a successful block the next attack comes out at once and harder - a riposte |
| 6 | **Shield Bash** | Active | Shield thrust in a cone: short stun and knockback |
| 10 | **Shield Wall** | Passive | A block raised just in time (a perfect block) staggers the attacker |
| 14 | **Phalanx** | Passive, capstone | While blocking, allies and myrs behind you take less damage, and enemies nearby turn on you |

**As built (2026-10-18).** The Meshy "Sunforged Warlord" on Mixamo's Pro Sword and Shield pack
plus the Magic Spell pack for the casts, with the Meshy "Shadowfang" blade and "Stone Warden"
shield as props, all in `assets/player/knight/` (`source/prepare_props.py` builds both glbs:
a metre long and a metre tall, origins where the fist closes).

- **Sword (`scripts/knight_kit.gd`).** MeleeKit's buttons. The light chain is the pack's long
  combo (`slash_chain`, its "slash (2)"): three cuts - a quick one, a backhand, then a leaping
  spin into a slam - spent one per click like the barbarian's cleaves, full body and moved
  forwards by the clip's own root motion; a click while a cut still plays carries on, one
  after it has ended starts over. Each cut is paid for its share of the chain, so the slam
  hits hardest. Holding sets off `heavy_slash` (its "slash", the biggest cut) at once, like
  the warrior's spin, stepping in with its own root motion. Whooshes timed to the blade, as
  the barbarian's.
- **Shield (`scripts/knight_guard.gd`).** The warrior's guard with
  `knight_block_damage_reduction` 0.95 instead of 0.8, the whole front half covered
  (`knight_block_cone` 0) and bosses blocked too. `ClassDefence.damage_reduction` and
  `on_blocked` are the hooks. Standing, the guard is `block_idle`; on the move it is the
  pack's own walks and strafes, played whole - they already walk behind the shield
  (`ClassDatabase` `walk_guards`), so no guard layer is laid over the arms.
- **Skills.** First Strike: after a blocked hit (`Player._notify_blocked`, told to a remote
  knight by RPC since blocks are decided on the server) the next swing within
  `knight_first_strike_window` plays 1.6x faster and hits 1.75x harder. Shield Bash
  (`scripts/knight_skills.gd`): the pack's shield-arm thrust, on its measured thrust
  everything within `knight_bash_range` in front takes a blow and is shoved and stunned.
  Shield Wall: a hit blocked within `knight_perfect_block_window` of the shield coming up
  (`Player.guard_raised_msec`, kept on every copy of the player) stuns the attacker. Phalanx:
  while the shield is up, allies and myrs within `knight_phalanx_radius` BEHIND the knight
  take x0.6 (`Player.phalanx_damage_taken_mult`, asked by players, summons and myrs as the
  anthem is) and enemies within `knight_phalanx_taunt_radius` are taunted onto the knight,
  renewed while it holds. Icons: `first-strike.png`, `shield-bash.png`, `shield-wall.png`,
  `phalanx.png` (the class-skill sheet in `docs/ICON_PROMPTS.md`).
- **Body.** 1.4x health, 0.95x speed. **Damage** 85% of the warrior's a second on one enemy
  (`tools/tests/melee_dps.tscn`): 46.5 tapping and 28.6 with heavies against 54.5 and 33.3 -
  its cuts are whole clips, so each lands at 2.3x (heavy 2.6x).
- **Rig.** 33 bones again - one finger chain a hand, no thumb - so the fingers are merged onto
  it (`mitten_fingers`) and the props are seated in the fist the curled finger makes
  (`_fist_circle`): the sword's blade out of the thumb side, the shield upright and facing the
  hips' forward in the guard pose. The mesh came faceted (82% split) and is smoothed.
- **Weights (2026-10-18).** Mixamo gave this rig next to no Neck: the jaw, the cheek guards
  and the helmet's rim hung on Spine2, so a head turn left the chin and the lower helmet with
  the chest. `SkinWeightFix.rigid_head` (config `rigid_head`) hands the whole head to the Head
  bone from the cheek guards up, fading out down the bare throat to the breastplate; the worst
  edge stretch in the head clips fell from 16x to 3x. The plates in front of and behind the
  crotch were split down the middle between the thighs and tore with every step:
  `even_plates` shares them evenly between the legs and gives half of that to the hips
  (`to_hips` 0.5 - 1.0 is rigid on the belt but lets a raised thigh through). Both are
  geometric rules in the builder config, re-applied on every build.
- **Footsteps.** The pack's forward walk drags the trailing foot just after the lead foot
  lands, and its sideways runs are out of phase on the right foot: `player_footsteps` lists
  those three gaits as known misses.
- `tools/tests/knight_kit.tscn` (windowed) covers all of it on the real map.

### Barbarian

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Brute Force** | Passive | Heavy swings knock back further; what they kill is thrown hardest |
| 6 | **Whirlwind** | Active | Several turns on the move, hitting everything around |
| 10 | **Indomitable** | Passive | Nothing interrupts or flinches you during a heavy swing |
| 14 | **Berserk** | Active, capstone | A few seconds faster and harder-hitting, and no block at all |

**As built (2026-10-18).** The Meshy "Scarred Warchief" (an orc) on Mixamo's Great Sword pack,
with the Meshy "Scarred Sentinel" as the sword, all in `assets/player/barbarian/`.

- **The two-hander (`scripts/greatsword_kit.gd`).** MeleeKit with other clips and numbers
  where it can be: a tap is one cleave of the pack's long slash flourish, spent one cut per
  click over three stages (2.75x the axe's damage a cut, `barbarian_reach` 4.2 m over a much wider
  arc, `barbarian_cone`). Unlike the axe's chain a cut always takes the WHOLE body - the pack
  walks into every cut, and masking the swing onto the walk cycle looked wrong - and moves it
  forwards exactly as far as the clip travels (the builder keeps the hips' forward travel as
  `root_forward` before flattening it; `GreatswordKit.lunge_speed` pays it out, about 1.1 m a
  cut). The cuts play at the pack's own pace (`barbarian_cleave_pace` 1.0, about a second
  each), and a click inside the combo window carries on from the playhead instead of jumping
  to the cut, which the animator continues with no fade (`SELF_CONTINUE_TOLERANCE`) - the
  three clicks play as the one flourish. The last cut runs on into the pack's return to
  guard. The chain carries on only while the cut before is still playing; a click once it has
  ended starts over at the first cut (the axe's `player_combo_grace` would have played the
  next cut out of the resting pose). Holding past `player_heavy_hold_time` is the heavy, set
  off at once exactly like the warrior's spin - no charging: `heavy_combo` (Mixamo's
  "Standing Melee Combo Attack Ver. 1", downloaded on the Warchief), two big swings and the lift
  back to the shoulder at `barbarian_heavy_pace`, rooted and moved by its own root motion (about
  1.7 m in). Both swings land (`MeleeKit._heavy_hit_shares`): the first for
  `barbarian_heavy_damage_mult`, the second for `barbarian_heavy_second_swing_share` of it. It
  replaced the pack's overhead slash (2026-10-19). (A charge was tried and dropped as clunky:
  held at the top of the raise it froze mid-swing, slowed in the opening it dragged.) The kick
  is the warrior's. Titanic Brawl's leap is the warrior's running jump attack, downloaded on
  the Warchief too.
- **Whooshes on the blade.** A barbarian swing's whoosh is not played as the move starts but
  timed to each measured impact, so the sound's loudest moment (`MeleeKit.WHOOSH_PEAK`,
  measured on the recordings) lands when the blade is fastest; `barbarian_whoosh_lead` moves
  it earlier or later. The axe still whooshes on the press (`MeleeKit.whoosh_before_hit` -1).
- **Smooth shading.** Meshy exported the Warchief faceted (split normals at 80% of its vertex
  positions); the builder smooths it (`smooth_normals`, `tools/normal_smoother.gd`).
- **No block; the heavy cannot be stopped.** The block button does nothing (`defence: "none"`,
  a bare `ClassDefence`). From the first frame of the raise to the end of the chop a hit does
  not stagger (`AttackKit.unstoppable`, read by `Player._try_hit_reaction`).
- **Skills.** Brute Force: the heavy's knockback x`barbarian_brute_force_knockback_mult`,
  and the push lands BEFORE the blow (`MeleeKit._strike`), so what it kills is launched with
  the push already counted (`EnemyBase._record_fatal_hit`). Whirlwind: the sword held out
  level (the pack's guard pose) and the whole figure turned `barbarian_whirlwind_turns` times
  by the animator (`PlayerAnimator.WHIRLWIND_CLIP`, so every screen spins it), hitting
  everything within `barbarian_whirlwind_radius` every `barbarian_whirlwind_hit_interval`,
  walking at `barbarian_whirlwind_move_mult`. Indomitable: `is_control_immune()` while ANY
  swing is in flight - cleaves, kick, Whirlwind - so the base rule (the heavy) and the skill
  (everything else, slows included) stay two different things. Berserk: a server-side timer
  like Ironbark, shown as a throbbing red rim (`StatusFx.BERSERK`); while it lasts swings are
  x1.4 faster and x1.35 harder, and every hit taken x1.25 harder - "no block at all" for a
  class that never had one. Icons: `brute-force.png`, `whirlwind.png`, `indomitable.png`,
  `berserk.png`.
- **Body.** 1.3x health, 0.9x speed (`barbarian_health_mult`, `barbarian_speed_mult`).
- **Slower, so harder: the same damage a second.** `tools/tests/melee_dps.tscn -- <class>`
  measures a melee class on one enemy through the real button. The cleaves come about half as
  often as the axe's cuts, so at 1.5x a cut the barbarian dealt 29.8 a second tapping as fast
  as the chain allows against the warrior's 54.5; at 2.75x it is 54.7. Its wider arc and reach
  are what it gains against a crowd. The heavy is set the same way: 2.6x a blow, 33.2 a
  second held again and again against the warrior's spin at 33.3.
- **The builder measures a blade at its tip.** On a two-hander the hand barely moves on a cut
  the tip carries through two metres, and moves fast hauling the sword back up between cuts:
  measured at the hand, the flourish had six "impacts", three of them recoveries. The config's
  `blade` follows a point 0.9 m up the fitted sword instead, and `hit_threshold` 0.6 keeps the
  three real cuts. The old overhead used a new trim, `Trim.WHOLE`: the whole clip is its
  window, the impact its single fastest moment (the knight's heavy still does). A chain is cut
  between its cuts where the blade has played out (`lull_ratios`, the first dip after a cut
  below a third of its speed), not halfway to the next - halfway was often the next wind-up,
  and a stage that was not followed faded to idle from a raised blade.
- **The pack's walks start anywhere in the stride**; blended diagonally the left foot only
  shuffled and the footstep test missed every other step. `align_gait` stores where each loop
  lands its left foot (`left_landing`) and the gait blend spaces start every clip there.
- `tools/tests/barbarian_kit.tscn` (windowed) covers all of it on the real map.

### Archer

The defence comes before the big active: the archer is the most fragile class and needs
the way out sooner.

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Longshot** | Passive | Fully drawn shots pierce through several enemies |
| 6 | **Disengage** | Active | A roll backwards that leaves a slowing snare behind |
| 10 | **Arrow Volley Trap** | Active | A rain of arrows on a target area |
| 14 | **Deadeye** | Passive, capstone | Hits on weak points and heads deal much more damage |

**As built (2026-10-17).** The Meshy "Elven Sentinel" on Mixamo's Pro Longbow pack plus the
Magic Spell pack for the five colour casts, all in `assets/player/archer/`.

- **Bow (`scripts/bow_kit.gd`).** `draw` (quiver to cheek, `archer_draw_time`), then `aim`
  held and overdrawn to a full draw over `archer_full_draw_time`, then `shoot`. A press let
  go during the draw shoots at the anchor - the quick shot, 0.75x the axe's damage; a full
  draw is 2.4x. The arrow (`scripts/player_arrow.gd`) is swept, flies with a little drop,
  sticks in the ground, and is resolved on the shooter's machine like a swing; the other
  screens fly a damage-less copy. It counts as a basic attack: Exalted Strike, Rubblebelt,
  Loxodon Warhammer, Fireshrieker, Icy Manipulator, Vampiric Link and the melee-into-spell
  cooldown refund all apply. The archer keeps the warrior's kick for making room.
  The camera zooms in over the draw (`BowKit.aim_zoom`, field of view only, so the crosshair
  stays put): half way at the anchor, to `archer_aim_zoom_fov_mult` (0.7) at a full draw, and
  back out faster than it went in once the arrow is loosed.
- **The bow points at the crosshair (`scripts/bow_aim.gd`).** The Pro Longbow clips draw side-on
  with the arrow ~23 degrees off the body's forward and 6 degrees below level, whatever the
  camera does. `BowAim`, a `SkeletonModifier3D`, turns the three spine bones after the
  animation until the string-hand-to-grip line points at `Player.aim_hit_point` - yaw, then
  pitch, no roll - turned in over the pull of `draw` (from the hands meeting at the bow to the
  anchor, `PlayerAnimator.BOW_AIM_DRAW_FROM/FULL`; before that the hand is in the quiver and the
  line means nothing) and out after the release (`archer_aim_blend_rate`, clamped by `archer_aim_max_yaw_degrees` / `_pitch_degrees`).
  The camera pitch is replicated (`Player.aim_pitch`) so teammates see the aim too. Godot
  restores the bones after a modifier runs, so `BowRig` draws on `skeleton_updated` and keeps
  that pose for the arrow's launch point. Test: `archer_kit` checks the arrow is within 3
  degrees of the crosshair at full draw.
- **No dip between draw and hold.** The one-shot fades back to locomotion over its last 0.12 s,
  which on a 0.42 s draw was the arms sinking towards rest before `aim` snapped them up again.
  Clips another one carries on from (`draw`, `aim`) hold their last frame for
  `PlayerAnimator.CONTINUED_CLIP_HOLD`, so the follower takes over before any fade starts.
- **The string is drawn live (`scripts/bow_rig.gd`).** The bow is the elf ranged enemy's
  bow with its baked string cut away and scaled to a longbow
  (`assets/player/archer/source/prepare_props.py`); the string runs tip - hand - tip while the
  hand is on it and the nocked arrow shows, read off the action clip's playhead on every
  screen, nothing sent.
- **Roll (`scripts/dodge_roll.gd`).** The block button rolls the way the stick points
  (backwards with none), untouchable for `archer_dodge_invulnerable_time`; the untouchable
  window is set on the server too, where hits land. The roll is the pack's dodge clip for that
  direction, played up to where its hop lands at `archer_dodge_pace`, and the body follows the
  hop (the builder's `root_travel`) stretched to `archer_dodge_distance` - it used to be a
  constant 10 m/s for 0.42 s, which showed the sped-up run under a flicker of dodge.
- **Skills.** Longshot: a full draw pierces `archer_longshot_pierce` enemies. Disengage: a
  roll back of `archer_disengage_distance`, untouchable throughout, and a `snare` zone where it
  started. Arrow Volley Trap: an `arrow_volley` zone (falling arrows) on the aimed ground.
  Deadeye: the top `archer_head_fraction` of an enemy's collision body takes
  `archer_deadeye_damage_mult`. Icons: `longshot.png`, `disengage.png`,
  `arrow-volley-trap.png`, `deadeye.png`.
- **Body.** 0.8x health, 1.25x speed (`archer_health_mult`, `archer_speed_mult`).
- **Fingers.** The elf was rigged on Mixamo as "3 chain fingers" (49 bones): thumb, index and a
  middle chain Mixamo put out at the fingertips, with the middle, ring and little fingers left
  on the Hand bone - so only the index finger closed round the bow and the rest stood out
  straight. The builder hands every vertex past the knuckles that the Hand or the middle chain
  held to the index joints (`"mitten_fingers"`, `SkinWeightFix.mitten_fingers`): all four
  fingers close together. A rig with all five chains (Mixamo's "Standard Skeleton (65)") would
  not need it - worth choosing for the next class uploaded.
  The bow's grip is seated in the closed fist: at the centre of the circle through the index
  knuckle, middle joint and fingertip at full draw (`fist_chain`), still standing upright -
  the old midpoint of the hand and the middle-finger bone put it over the back of the hand,
  and turning it onto the circle's axis laid it across the face at rest.
- `tools/tests/archer_kit.tscn` (windowed) covers all of it on the real map.

### Mage

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Prowess** | Passive | After every spell the next basic bolt is empowered - rewards weaving spells and bolts |
| 6 | **Blink of an Eye** | Active | A short teleport that leaves a decoy behind for a moment |
| 10 | **Spell Mastery** | Passive | Every colour spell holds two charges (was: shorter cooldowns - see below) |
| 14 | **Mana Surge** | Active, capstone | Resets the cooldown of the last spell cast |

Deliberately NOT a "Storm" effect (spells copying themselves): Jeskai already owns that in
Stage 2 of `docs/GUILD_PLAN.md`.

**As built (2026-10-19).** The Meshy "Arcane Wayfarer" - a wanderer in a long white coat, bare
hands, no staff - rigged on Mixamo as the 65-bone skeleton (all five finger chains, so no
`mitten_fingers`) and animated with the Magic Locomotion pack and the Magic Spell pack, all in
`assets/player/mage/` (the spell pack in `magic/`). No props: in place of a weapon the mage
holds a ball of energy over its right palm (`scripts/mage_hand_orb.gd`).

- **Bolts (`scripts/mage_kit.gd`, `scripts/mage_bolt.gd`).** The button works the warrior's way,
  on the release. A tap throws a bolt: the spell pack's one-handed attack 01 every time
  (`bolt_1`; `MageKit.bolt_clips` can take turns between several, and the pack's 02 and 03 are
  in the library as `bolt_2`/`bolt_3`, but 02 turns the body side-on and 03 ends thrown at the
  sky - better throws are to be picked from Mixamo). All three are thrown with the RIGHT hand
  (measured 5.4-7.8 m/s at the release against 1.9-4.2 for the left), squeezed into
  `mage_bolt_duration`, upper body only so the mage
  walks while throwing at `mage_bolt_move_mult`. Nothing leaves on the click: the bolt goes on
  the throw's measured release, from the hand, at what the crosshair is on - straight, no drop -
  for `mage_bolt_damage_mult` (0.65x the axe's damage). Holding past `player_heavy_hold_time`
  throws the **Arcane Blast** at once (`arcane_blast`, the pack's half-turn two-handed throw),
  rooted: a slower, bigger orb that bursts on whatever it meets and hits everything within
  `mage_blast_radius` for `mage_blast_damage_mult`. Like the arrow, the bolt is swept, resolved on
  the thrower's machine and flown as a damage-less picture on the others (`Player._net_spawn_bolt`),
  and counts as a basic attack: Exalted Strike, Rubblebelt, Loxodon Warhammer, Fireshrieker, Icy
  Manipulator, Vampiric Link and the cooldown refund all apply (the refund once per bolt, not
  per enemy a blast catches).
- **The orb in the hand (`MageHandOrb`).** The bolt's own churning orb, smaller, in the path's
  colour, with a little light - attached at runtime wherever the visual is shown (PlayerAnimator
  on every screen, the menu's ClassPreview, the decoy), as the archer's BowRig is. It floats over
  the palm (wrist-to-knuckles, lifted along the palm's normal) on a damped spring computed in the
  character's own space - it trails the hand by about a tenth of a second, never the body - on a
  15 cm leash, and bobs gently at rest. A bolt is thrown from it and the palm grows a new one
  over 0.3 s (also on the other screens, from `_net_spawn_bolt`).
- **The colour of the path (`Player.path_color`).** The colour the player has put the most into
  (`color_investment`), a tie going to the one last chosen in the tree, arcane violet before
  anything is invested. It PAINTS the bolt, the blast, the blink and Mana Surge
  (`MageBolt.TINTS`, white drawn in `SpellVisuals.WHITE_GOLD`) and changes nothing about what
  they do - a class is the weapon, a colour the magic.
- **Blink (`scripts/blink.gd`).** The block button puts the mage `mage_blink_distance` away the
  way the stick points, backwards with none, short of the first solid thing at chest height
  (`Blink.landing`), with a flash at both ends (`mage_blink_from` / `mage_blink` in
  `SpellVisuals._play_mage`, the path's colour riding on the effect id). Untouchable for
  `mage_blink_invulnerable_time` as it lands; works in the air; cuts a throw in flight.
- **Skills (`scripts/mage_skills.gd`).** Prowess: every colour spell cast (`Player._note_spell_cast`,
  on the caster's own machine, channels included) banks a charge, up to
  `mage_prowess_max_charges`; each bolt or blast spends one for x`mage_prowess_damage_mult` and
  is drawn bigger, and all are lost `mage_prowess_window` after the last spell. Waiting charges
  glow at the throwing hand. Blink of an Eye: instant, like Displace - a blink to the aimed
  ground up to `mage_blink_of_an_eye_range`, leaving a decoy where the mage stood: a
  `TemporaryAlly` of kind "decoy" (the Phantasmal Decoy's, unused since), now drawn as the
  mage's own visual in the path's colour, with `mage_decoy_health_mult` of the mage's health for
  `mage_decoy_duration`; enemies within `mage_decoy_taunt_radius` are taunted onto it. Spell
  Mastery: see below. Mana Surge: the last colour spell cast is ready again with every charge;
  resolved in `Player.execute_spell` on the caster's machine, where the cooldowns live. Icons:
  `prowess.png`, `blink-of-an-eye.png`, `spell-mastery.png`, `mana-surge.png`.
- **Spell Mastery is two charges, not shorter cooldowns.** The planned "shorter cooldowns on
  the colour spells" is blue's affinity again - the one place cooldowns get shorter
  (`docs/SKILL_DESIGN.md`, "One number, one node"). Instead every colour spell (channels
  excepted) holds `mage_spell_mastery_charges` charges and still recovers one per cooldown: no
  faster in the long run, but two in a row when it counts. `spell_cooldown_timers` keeps its
  meaning - it runs only while no charge is left, so the cast, the bar and Phyrexian Arena
  needed no change - and the charge coming back while one is still in hand is
  `Player._mastery_recharge`. The quick bar shows the count in the slot's corner (`x2`).
- **Clips.** Casts: white `2H Cast Spell 01` (both hands to the sky; its release measured on the
  LEFT hand, the right one's fastest moment is the crouch before), blue `2H Magic Attack 03`,
  black `05`, red `01`, green `1H cast spell 01`; the big self-buffs and Mana Surge `2H Magic
  Area Attack 02`. Neither pack has reactions or a death - those are the enemy mages' own
  (bare-handed too) - nor Titanic Brawl's leap, which is the warrior's, as for the archer.
- **Body.** 0.75x health, 1.1x speed - the most fragile class; the blink keeps it alive.
- **Mesh.** Faceted as exported (split normals at 81% of its positions), smoothed by the builder.
  Its normal map is left out (`"normal_map": false`): Meshy baked it against the faceted normals,
  and on the smoothed mesh it drew hard creases through the face along its UV islands. The
  albedo carries the detail. The spiky hair is the mesh's own geometry.
- **Footsteps.** The locomotion pack's side and back walks step and close - the trailing foot
  lands within a third of a stride of the lead one, which the footfall detector takes for a toe
  brush - so walking back, left or diagonally forward hears every other step;
  `player_footsteps` lists those three gaits as known misses.
- **Measured** (`tools/tests/mage_kit.tscn`, red affinity 2 for the blast): a bolt 13.0 on one
  enemy, the blast 44.8 on each of two, a Prowess bolt twice a plain one (30.7 vs 15.3), the
  blink 6.0 m, Blink of an Eye 10.7 m to the aimed ground.
- `tools/tests/mage_kit.tscn` (windowed) covers all of it on the real map.

### Werewolf

Built on **Ulrich of the Krallenhorde // Ulrich, Uncontested Alpha** (Eldritch Moon), with
the newer werewolf rule from Midnight Hunt: **human by day, wolf by night** (Daybound /
Nightbound). The form follows the sky's own clock (`DayNightPacing`) - nothing else
decides it.

- **By day, Ulrich of the Krallenhorde:** fights like the warrior - the same melee kit
  (light chain, heavy, kick, block) on a model of its own.
- **By night, Ulrich, Uncontested Alpha:** a claw chain that hits about half again as
  hard, about half again the health, no block. The card goes 4/4 -> 6/6.
- **The swap carries Ulrich's two triggers.** Turning wolf, you leap at the enemy under the
  crosshair (else the strongest one close by) and fight it: it takes one big hit worth the
  wolf's strength, you take its attack back ("fight target non-Werewolf creature"). Turning
  human, the nearest teammate - else yourself - hits harder and gets bonus health for a few
  seconds ("target creature gets +4/+4").

The card is red-green, but the class stays colourless like every other - a werewolf can
walk any path in the tree.

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Wildblood Pack** | Passive | Claw hits on the same enemy land harder one after another |
| 6 | **Moonmist** | Active | Turns day into night for everyone - you become the wolf, and enemies deal you no damage for a moment. Usable by day only, once per day |
| 10 | **Howl of the Night Pack** | Active | A howl that calls a few wolves; they fight beside you until their time runs out or they are killed |
| 14 | **Howlpack Alpha** | Passive, capstone | While you are the wolf, wolves and teammates near you hit harder, and every nightfall a wolf joins you for the night |

Names: Moonmist's card is "transform all Humans, and only Werewolves and Wolves deal combat
damage this turn" - the skill plus its moment of protection. The literal day/night card
is **The Celestus**, if a name that says "flip the clock" outright is preferred. Howl of
the Night Pack and Howlpack Alpha both make Wolf tokens on their cards, and the Alpha
pumps Wolves.

What this has to settle before it is built:

- **Moonmist changes the sky for the whole team.** Nights are dark on purpose and last
  `night_real_minutes` (5 of every 25), so pulling one forward is a team decision as much
  as the werewolf's. The clock jumps to dusk and the next day follows the night as usual.
- **The clock is not networked today.** Every peer starts it at `day_start_hour` and runs
  its own, so a late joiner is out of step. Moonmist and the form both need one clock,
  owned by the server - that comes first in this stage.
- **Wolves are `TemporaryAlly`s**, the class Zombify's ghouls run on. They need a wolf
  model: a new rigged beast through `assets/enemies/beasts/source` (a Meshy model, so
  credits), or a small recoloured existing beast.
- **Overlap to watch:** `docs/SKILL_DESIGN.md` lists Call of the Herd (a summoned beast) as
  a possible green spell. If that is ever built, it and Howl of the Night Pack must not end
  up as the same skill.

**Models.** Two for the class itself, the human and the werewolf, each its own Mixamo
upload, clip table and builder run (`assets/player/werewolf/human/` and `.../wolf/`). Both
are humanoid, so the Mixamo route works for the wolf too. The swap has no Mixamo clip: it
hides behind a burst of fur and smoke while the visual is exchanged. Plus the wolf for the
pack.

### What changes for Blade Dance

Today it is bought at the centre for `GameSettings.melee_combo_unlock_cost` mana of any
colour OR granted at level 10. Under this plan it is the warrior's level-10 class skill
and nothing else: the mana purchase goes, and so does Blade Dance for every other class.
The centre node becomes the class track - read-only, showing each skill and the level it
unlocks at.

**As built (2026-10-19): the class ring.** The hub reads the team level, with a gold arc round
it for the way to the next one. In the five gaps between the colours' spokes sit the class's
five, clockwise from the upper-left gap: its **defence** at level 1 (`ClassDatabase.DEFENCES` -
Block, Shield Guard, Unstoppable, Dodge Roll, Blink - on the block button, so it shows that key)
and then the four class skills at 3, 6, 10 and 14 (`SkillTree._build_class_ring`). Reached:
bright, gold rim, an active's quick-slot key under it; not yet: dimmed, "Lv 10" on it. Round
for what is always on, a rounded square for what goes on the quick bar, as on the rest of the
board. A slot whose skill a class does not have yet (three of the warrior's) stays empty. The
defences wear stand-in icons until `defence-*.png` are drawn (SpellDatabase.ICON_FILES).

## Architecture

**Classes as data.** A `CharacterClass` resource (or a `ClassDatabase` in the style of
`scripts/spell_database.gd`), one per class:

- the visual scene and its animation library
- a clip map from logical names to clips (`light_attack` -> `combo_3` for the warrior,
  `bow_shot` for the archer) - `PlayerAnimator` reads names from this instead of its own
  constants
- weapons and where they are held (right hand; left hand for the shield)
- health, move speed, armour
- which attack kit and which defence the class uses
- its four class skills

**Attacks as kits.** The melee logic in `scripts/player.gd` (light chain, heavy, block,
kick) moves into a melee kit; the archer and the mage get kits of their own. Aiming
through the crosshair already exists for spells, and so does `ProjectilePool`.

Done for the warrior: `scripts/melee_kit.gd` (light chain, heavy, kick, impact frames,
reach) and `scripts/block_guard.gd` (the guard, kept apart because the barbarian has the
kit and no block). Both now extend a base - `AttackKit` (`scripts/attack_kit.gd`) and
`ClassDefence` (`scripts/class_defence.gd`) - and Player holds `kit` and `defence` typed as
those, so the archer's `BowKit` and `DodgeRoll` slot in with no branches in Player. Player keeps what an attack shares with a cast - the committed-action
clock, its network messages, and what a hit does once it lands. The kit's clips and lunge
are fields, so a class on the same moves sets other values. `tools/tests/melee_kit.tscn`
drives it through the real buttons and printed the same 28 lines before and after the move.

**The builder per class.** `tools/player_character_builder.gd` runs from a per-class
config (`CONFIGS`: mesh, textures, clip table, props) and writes
`scenes/characters/<class>/visual.tscn` plus a library (`-- archer` on the command line).
The clip map lives here: every class's table maps the same LOGICAL names (`idle`,
`walk_forward`, `cast_red`, `hit_gut`) to its own files, so PlayerAnimator never asks which
class it is playing; clips one class alone has (`draw`, `dodge_back`) are simply absent from
the others, and a missing `block_idle` leaves the guard layer unbuilt. Its measuring and trimming - travel
speed from root motion, hit ratios inside attack clips - stays as it is. Death and the
spellcasting poses are still borrowed from the enemy rig and shared.

**Moving a weapon by hand (2026-10-18).** As with the enemies' weapons: open the class's
visual scene, select the prop under its BoneAttachment3D (`Hatchet`, `Sword`, `Shield`,
`Greatsword`, `Bow`, `Quiver`), move, turn or scale it, save. It shows in the game at once,
and a rebuild keeps it: the builder reads the nudge back out of the scene before it
overwrites it, into `assets/player/prop_fit.json` (`"<class>/<prop>"`, in the prop's own
frame, on top of the fitted placement). `tools/capture_player_prop_fit.gd` does the same
without a rebuild. To undo one, delete its entry and rebuild that class.

**The warrior in the same layout (2026-10-18).** Its model, maps and clips moved from loose
in `assets/player/` to `assets/player/warrior/`, its visual from `scenes/misc/player_visual.tscn`
to `scenes/characters/warrior/visual.tscn` and its library to
`assets/animations/player/warrior/lib_warrior.tres`. Its weapon is now a prop like everyone
else's: the Meshy "Battle Worn Hatchet" (`assets/player/warrior/source/prepare_hatchet.py` ->
`assets/weapons/player/warrior_hatchet.glb`, 0.85 m), seated in the fist as the knight's sword
is. The edge leads at every fast hit of its attack clips. The metre-long cleaver it replaced
(`player_weapon.glb`, placed by hand-found constants off the rest pose) is no longer used.
Swings are still measured at the hand, so its hit timing and damage are unchanged.

**Choice and network.** The class is picked in the menu (beside the name, so it serves
solo, hosting and joining alike) and can still be changed in the lobby; it is fixed once the
match starts. It is kept in `UserSettings.character_class` and in the peer info
(`Net.peers[id]["class"]`, sent with the name in `_submit_identity`, so a reconnect comes
back as the same class without it riding on the build), and reaches the avatar on the spawn
data as "character_class" metadata, which `PlayerAnimator._ready` reads to load the visual.
Any number of players may pick the same class. The picked class stands on the right of the
menu painting (`scripts/class_preview.gd`): its real visual in its own idle, with its name and
role under it, and it can be dragged round. `tools/tests/class_preview_shot.tscn` renders the
menu once per class.

**Classes as data, as built.** `scripts/class_database.gd` (`ClassDatabase`): the classes
(visual, kit, defence, body multipliers by GameSettings name, the four skills) and the class
skills. Active skills carry spell fields and SpellDatabase's accessors fall back to them, so
the quick bar, cooldowns and `Player._begin_cast` treat them as spells; `get_spell_rank`
answers 1 for an unlocked class skill. Skills are derived from `RunState.team_level` against
`GameSettings.class_skill_levels`, never saved; actives are put on the first free slot when
their level arrives (or on arrival, for a late joiner).

**"Melee" in existing skills becomes "basic attack".** Rubblebelt Rioters ("your next three
melee hits"), Executioner's Capsule (melee execute) and Blade Dance all say melee; anything
that is not the warrior's own should count any class's basic attack, or it is worth
nothing to an archer or a mage.

## Mixamo assets

- Every class has a Meshy model of its own. One character uploaded per class; every
  animation downloaded onto it - FBX, the first
  *with skin*, the rest *without skin*. Bone names then match by construction.
- Leave **In Place unticked** for locomotion: the builder measures travel speed from the
  root motion, as it does for the current set.
- One folder per class (`assets/player/<class>/`): file names such as `standing idle.fbx`
  recur in every pack.
- Each pack needs its own armed locomotion (a two-hander walks differently). Death and
  the casting poses can stay shared.

## Stages

1. **Refactor, no new content.** Class data, clip map, attack kits, class skill track.
   The warrior is the first class and plays exactly as now; Blade Dance moves onto the
   track at level 10. Tests prove nothing changed.
2. **Knight** - closest to what exists: a shield mesh and its own animation set. Built
   (2026-10-18).
3. **Barbarian** - the melee kit with other clips and numbers. Built (2026-10-18), with a
   charged overhead of its own.
4. **Archer** - the ranged kit, arrows, aiming. Built, with the class choice and the class
   track it needed from stages 1 and 7.
5. **Mage** - the caster kit, and the spell balance that goes with it. Built (2026-10-19).
6. **Werewolf** - the server-owned clock first, then the two visuals, the swap with its
   two triggers, Moonmist, and the wolves.
7. **Class choice in the lobby, balance, and tests per class.** `tools/tests/skill_roster`
   asserts every class skill has an observable effect, the way it already does for every
   spell.

## Decisions

| Question | Decision | What follows from it |
|---|---|---|
| Models | **A model of its own per class** (Meshy) | Each class is its own Mixamo upload and its own builder run; nothing is shared between them but the borrowed death and casting clips. The warrior keeps the current orc. The werewolf has two (human and wolf). |
| Switching | **Fixed for the whole run** | Picked in the lobby before the match starts; there is no class change at Upkeep. A reconnect comes back as the same class (it travels with the peer info); a new run is a new choice. |
| Duplicates | **Allowed** - two players may be the same class | The lobby does not lock a class once someone has picked it, and nothing may assume one player per class (no per-class singletons, no "the archer"). |
