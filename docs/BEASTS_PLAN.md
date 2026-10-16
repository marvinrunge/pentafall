# Beasts Plan

Wild beasts that live in the biomes, independent of the waves: they roam a home spot, fight
whoever comes close, and pay the team for the hunt. The rigged quadrupeds are in
`assets/enemies/beasts/` (how they were built: `assets/enemies/beasts/source/`, and
`scenes/test/monster_viewer.tscn` plays their clips).

The Emerald Sabertooth stays out - only the three reptiles are used.

## Decisions (2026-10-16)

| Question | Decision |
|---|---|
| Behaviour | **Territorial**: wander around a home point, attack only what comes close, give up and walk home (healing) when dragged too far. **Specials are used**: the ravagers pounce, the Spineback spins with its tail. They do NOT hunt myrs and do NOT change with the night. |
| Rewards | **Mana of the biome's colour**, **XP like an elite**, and a rare drop from a **new beast equipment pool**. No hunt buff. |
| White and Black | **Recoloured duplicates** of the existing beasts (shader tint), each with its own name. Red and Blue get tinted the same way so every biome's beast fits its biome. |
| When | **Always** - waves and Upkeep alike, with a cap per biome and a respawn timer. |

## Who lives where

| Biome | Beast | Look | Special |
|---|---|---|---|
| Green | Thornhide Ravager | original | pounce |
| Red | Spineback Terror (working name *Cinderspine Terror*) | sandy plates pushed to rust red | tail spin |
| Blue | Blisterback Ravager (working name *Tidal Blisterback*) | purple legs and green blisters pushed to blue/teal | pounce |
| White | Spineback, recoloured (*Ashen Spineback*) | bone white, pale plates | tail spin |
| Black | Thornhide, recoloured (*Gloomhide Ravager*) | charcoal with a sickly violet cast | pounce |

Names are proposals. A beast's colour identity is its biome's colour, so its mana, its
equipment pool and its tint all follow from one field.

## What already exists, and what it means here

- **Enemies** are `EnemyBase` (`scripts/enemy_base.gd`) spawned through
  `MainController.request_enemy` -> `EnemyNetSpawner`, which already replicates spawns,
  health, hits and deaths to clients. Beasts reuse that path instead of a second enemy
  system - status effects, spells, damage numbers, health bars and the crowd LOD then work
  on them unchanged.
- **Three things in EnemyBase must not apply to a beast:**
  1. With no target in range an enemy walks to the crystal (`evaluate_target` falls back to
     `target_crystal`). A beast falls back to its home instead.
  2. Every death emits `SignalBus.enemy_died`, which `WaveManager` counts down to end the
     wave. A beast's death must not, or killing one would end a wave early.
  3. `EnemyRagdoll` is built for the humanoid rigs. A beast plays its own `death` clip (the
     belly flop) and keeps the corpse.
- **Clip names already match**: `idle`, `walk`, `run`, `attack`, `special`, `hit`, `death`
  (30 fps, see `beast_anim.py`).
- **Payouts** go through `RunState.on_enemy_killed` (XP, mana, the boss equipment roll).
  Ordinary enemies pay 0 mana (`mana_per_basic`), elites 4, bosses 25 - so a beast's mana
  is a real, coloured income source, and choosing which biome to hunt in is a choice.
- **Equipment** is found, never bought (`scripts/equipment_database.gd`): 8 pieces, each
  tied to boss colours, dropped at 60% by wave bosses, shared by the team, worn from the
  **I** menu. Beasts get their own pool so they never take a boss's drop away.
- **Which biome a point is in**: the lanes are a pentagon of wedges around the crystal
  (`MainController.LANE_NAMES`, `_lane_outward`); `BiomeAtmosphere` already works out the
  wedge for the camera. The spawner uses the same angle test.

## Behaviour

| State | What it does |
|---|---|
| **Roam** | Walks between random points within `beast_roam_radius` of its home, idling between legs. Never leaves its biome. |
| **Fight** | A player, myr or decoy inside `beast_aggro_radius` - or anyone who hits it - becomes its target. Bites in melee; uses its special on a cooldown. |
| **Return** | Once it is more than `beast_leash_radius` from home, or has no target for a few seconds, it drops the fight, runs home ignoring everything, and regenerates to full on the way. A beast cannot be dragged into a lane or to the crystal. |

Specials, both with a telegraph so they can be dodged:
- **Pounce** (ravagers): crouch, leap at the target's position, damage and a short stagger in a
  small circle where it lands. Uses the `special` clip and its forward travel.
- **Tail spin** (Spineback and its recolour): a full turn on the spot, damage and knockback in a
  ring around it.

Beasts do not join squads, do not take formation slots, and ignore taunts from the crystal
logic (Roar still taunts them - it is a player ability).

## Spawning (`WildlifeManager`, server only)

- One cap per biome (`beast_max_per_biome`, start at 2) and a respawn timer per biome
  (`beast_respawn_min`..`beast_respawn_max`, start 60-120 s after a death).
- A spawn point is a random navmesh point inside the biome's wedge that is
  - at least `beast_lane_clearance` from the lane's enemy path, so beasts never stand on the road,
  - at least `beast_spawn_player_distance` from every player, so nothing pops in on screen,
  - outside the hub around the crystal.
  The point is the beast's home.
- The first beasts appear when the run starts; from then on beasts live through waves and
  Upkeep alike.
- Stats sit at elite level and scale with the wave like everything else
  (`enemy_health_per_wave`), so a beast stays worth the detour in the late game.
- Spawned with `request_enemy({..., "beast": species, "variant": biome})`; the arguments carry
  everything a client needs to rebuild the same beast.

## Rewards

| What | Amount | Setting |
|---|---|---|
| XP | 40 at 1x, like an elite, times the beast's size | `xp_per_beast`, `beast_reward_size_exponent` |
| Mana | 6 of the biome's colour at 1x, times its size | `mana_per_beast` |
| Equipment | its biome's piece, only if the team does not have it yet; 12% per 1x of size (a 5x giant ~ a boss's 60%) | `equipment_beast_drop_chance` |

All of it through `RunState.on_enemy_killed` (its Beast branch) and `try_drop_beast_equipment`,
host only. The mana number floats off the corpse like an elite's; a drop is announced like a
boss's (`RunState._apply_equipment_drop`). (Overgrowth no longer multiplies income - it is
myr slots and boss mana now - so it does not touch a beast's mana.)

### The beast equipment pool - built

One piece per biome colour (`EquipmentDatabase.BEAST_ITEMS`, `beast_colors` where a boss
piece has `colors`), all real MTG artifacts, each a mechanic rather than a plain number,
checked against `docs/SKILL_DESIGN.md` (*one number, one node*). Worn from the same **I**
menu, in the same team stash. Judged on the server in `EnemyBase._wearer_melee` (melee) and
`die()` (the Deathmantle), since two of them ask what only the server knows.

| Colour | Piece | Effect | Setting |
|---|---|---|---|
| White | Leonin Scimitar | Melee hits on an enemy attacking a myr or another player deal +50% | `equipment_leonin_scimitar_bonus` |
| Blue | Explorer's Scope | Your minimap shows the beasts in their biome's colour, sized by their size | `equipment_explorers_scope_reveal` (flag) |
| Black | Nim Deathmantle | A beast you kill rises as your ghoul for 25 s (Zombify's kind; on the melee rig of its colour, like every ghoul) | `equipment_nim_deathmantle_duration` |
| Red | Bonesplitter | Melee hits on an enemy still at full health deal double | `equipment_bonesplitter_bonus` |
| Green | Vorrac Battlehorns | Melee hits stun beasts, elites and minibosses for 0.5 s, once per 4 s per enemy; never bosses | `equipment_vorrac_battlehorns_stun`, `_cooldown` |

Two drafts were changed by the check: Explorer's Scope was "beasts show on the minimap", but
the minimap already shows every enemy; and Black's Basilisk Collar (melee marks, next spell
hits harder) would have been black's second damage amplifier, where SKILL_DESIGN gives black
exactly one (Wall of Souls) - so Black raises the dead instead, which is black's own thing.

## Recolouring - built

`assets/shaders/beast_tint.gdshader` draws the imported material's own textures (albedo,
normal map, glTF's packed roughness/metallic) with the albedo turned in HSV: hue rotated,
saturation and value scaled. Per biome in `BeastDatabase.VARIANTS` (`tint`), applied in
`EnemyBase._prepare_beast_visual` through `BeastDatabase.tinted_material`, one shared material
per biome. One GLB per species stays the only mesh on disk. `tools/tests/beast_lineup_shot.tscn`
renders all five side by side to judge them.

New Meshy models for White and Black later replace a variant without touching the rest.

## Stages

| # | Stage | Done when |
|---|---|---|
| 1 | **A beast is an enemy kind**: `EnemyData` class `Beast`, `BeastDatabase` (species, GLB, stats, special, variants), EnemyBase loads the GLB visual, plays the beast clips, skips the ragdoll and the wave counter, never targets the crystal | One beast spawned on the test stage can be fought and killed, plays walk/attack/hit/death, and the wave is unaffected |
| 2 | **Territorial behaviour + specials**: roam, aggro, leash, return-and-heal, pounce, tail spin, telegraphs | A headless test drags a beast past its leash and sees it return at full health; both specials hit what stands in them |
| 3 | **`WildlifeManager`**: caps, respawn timers, spawn points per biome wedge, replication | On the real map every biome holds its beasts off the lane, respawns work, a client sees the same beasts |
| 4 | **Rewards**: XP, biome mana, beast equipment pool and its drop | Killing a beast pays exactly once (host only), announces it, and can drop a piece the team does not own |
| 5 | **Variants**: tint shader, five looks, names | A lineup screenshot of all five reads as five biomes |
| 6 | **Tuning + docs**: numbers in `GameSettings`, crowd-perf check with beasts alive, `docs/AI_WORKSPACE.md`, `docs/ECONOMY.md` | Perf baseline holds; docs describe the system |

**Status (2026-10-16): stages 1-5 built and tested, plus sizes; stage 6's docs are done.** The
numbers are first guesses, not tuned in play, and no crowd-perf run has been made with beasts
alive (ten beasts against a 300-enemy target is not expected to show, but it is unmeasured).

Stage 1 is the largest risk (EnemyBase is built around humanoid rigs); once a beast fights
on the test stage, the rest builds on it.

### Stage 1 - built (2026-10-16)

- `scripts/beast_database.gd`: species (GLB, clip speeds, stats, special) and the biome ->
  species/name table. `EnemyDatabase.get_enemy_data(color, "Beast")` hands out its data.
- `EnemyBase` with `is_beast()`: loads the GLB in metres, marks idle/walk/run as loops,
  fits the collision box to the model, plays `idle` at rest, takes its walk/run speeds from
  the table, falls back to a top-level `Home` node instead of the crystal (and never swings
  at it), uses `beast_aggro_radius`, is not thrown on death and does not emit
  `SignalBus.enemy_died` (the wave's countdown) - neither on death nor on exile.
- `GameSettings`: `beast_aggro_radius`, `beast_home_arrive_distance`.
- Test: `tools/tests/beast_stage.tscn` (light stage, baked navmesh, a training dummy as the
  player). Windowed with a folder after `--` it saves idle/attack/dead frames.
- The rigs must be exported standing at the .blend origin: the glTF exporter samples the rig
  node into every clip, so an offset there comes back however the node is placed.

### Stage 2 - built (2026-10-16)

- Territory (EnemyBase, BEASTS section): `_home_position` is the middle of the territory and
  the end of the leash; `_beast_goal` (the node standing in for target_crystal) is where it
  walks when calm. At its goal it rests `beast_roam_wait_min..max` s, then wanders to a
  navmesh point within `beast_roam_radius` of home at `beast_roam_speed`. A fight that ends
  sends it home. "Arrived" also counts when the agent calls the route finished - it does so
  about 2.2 m short, and a beast that never arrived never rested or wandered again.
- Provoked: a player who hurts it is its target for `beast_provoke_duration` s, from any
  distance. Leash: beyond `beast_leash_radius` of home it breaks off, runs home ignoring
  hits and taunts, heals `beast_return_heal_per_second` on the way and arrives full.
- Specials through `_emit_boss_fx` (clip + telegraph on every peer, cancelled by
  `_cancel_special` like a boss's): the **pounce** marks the spot the target stands on, flies
  the body there during the clip's flight (landing short by the rig's own travel and the
  jaws' reach) and hits a `beast_pounce_radius` circle, slowing players it lands on; the
  **tail spin** marks a `beast_spin_radius` ring round the beast and hits at the sweep's
  fastest moment. Opener after `beast_special_first_delay` (0.5 s - the pounce is used
  while the target is still a few strides off), then every `beast_special_cooldown`. A
  freeze or stun breaks either off. Timings come from the clips (`BeastDatabase.SPECIALS`).
- The test covers all of it, including dodging the mark and the leash.

### Stage 3 - built (2026-10-16)

- `scripts/wildlife_manager.gd`, started by `MainController._start_match` once the navmesh is
  in (server only; the EnemyNetSpawner rebuilds each beast on the clients). Each biome keeps
  `beast_max_per_biome` beasts: the first `beast_first_spawn_delay` s into the match,
  `beast_spawn_stagger` s apart, and a dead one replaced after `beast_respawn_min..max` s.
- A home is a random navmesh point in the biome's wedge (`beast_wedge_margin_degrees` off its
  seams) that is at least `beast_lane_clearance` from every lane's enemy path (each lane's
  route from its spawner to the crystal, read once at start), `beast_min_crystal_distance`
  from the crystal, `beast_spawn_player_distance` from every player and `beast_home_spacing`
  from every other home; not in water (TerraBrush's `waterFactor`); and with a route to the
  crystal, so never an island of navmesh on a rock.
- Test: `tools/tests/beast_spawns.tscn` on the real map (timers cut short). Windowed with a
  folder after `--` it saves a midday frame of one beast per biome.

### Size (2026-10-16, user request)

- Every beast rolls a size of 1x-5x (`BeastDatabase.roll_size`): the largest possible climbs
  from `beast_size_cap_start` (wave 1) to `beast_size_max` at `beast_size_cap_full_wave`, and
  small stays more likely (`beast_size_skew`). It travels as `beast_size` in the spawn args.
- Health x size^1.3, damage x size^0.7, speed x size^0.35, animation slower; reach (bite,
  pounce, spin, arrival) x size, aggro/roam/leash x sqrt(size). From 3x: "ALPHA" tag.
- Big beasts need room: lane clearance, hub distance and home spacing grow with size, and a
  home must be free of trees and rocks for the beast's length. A rolled size is kept for up to
  6 checks while room is sought.
- Stage 4 should scale rewards with size.

## Sounds (2026-10-16)

Seven ElevenLabs events in `tools/sfx_prompts.json` (`beast_growl`, `beast_roar`, `beast_bite`,
`beast_pounce`, `beast_tail_spin`, `beast_hurt`, `beast_death`), three takes each under
`assets/soundeffects/generated/`, one picked per event in SoundBank (`tools/apply_sfx_picks.py`,
picked at random so far). One set for all beasts: `EnemyBase._beast_sound` plays them on every
screen through `NetFx.sound`, pitched down by size (GameSettings' Voice block). Growl now and
then while calm with a player in earshot; roar on turning onto a target (with a cooldown); bite
at the jaws' impact, hit or miss; pounce from launch, tail whoosh half a second before the
sweep hits; hurt with the flinch; death as it falls.

## Open questions

- Balance in play: sizes, health and damage exponents, rewards, drop chance, leash and aggro
  radii are first guesses (all in GameSettings' BEASTS block and the Beast equipment block).
- A giant's 10-14 m body among trees: homes are chosen on open ground, but a chase can still
  drag one between trunks; the recovery check is the backstop. Watch for it in play.
- A Deathmantle ghoul rises on the humanoid rig of the beast's colour, like every ghoul does.
  A beast-shaped ghoul would need TemporaryAlly to drive the beast GLB.
- Corpses follow the ordinary corpse cap; a beast's could stay longer as a trophy.
- New Meshy models for White and Black would replace their tinted borrowings (costs credits).
