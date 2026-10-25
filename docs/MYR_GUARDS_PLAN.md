# Myr Guards Plan

Myrs are the team's economy and they cannot defend themselves. A myr spends ~112 of its
~123-second round trip walking, then ten seconds standing still at a well in the middle of
a lane, and anything that wanders past kills it. Solo, they die before their second trip
and never pay for themselves; a levelled one takes its whole investment with it.

Implemented 2026-10-24 - see "As built" at the end for where each part lives and where it
differs from the plan. Test: `tools/tests/myr_guards.tscn`.

This plan keeps myrs fully autonomous - assigned and watched from the base, never steered -
and makes them worth building by keeping them alive and making a death recoverable.

## Decisions (2026-10-24)

| Question | Decision |
|---|---|
| Danger | **Workers flee.** Behind their lane's guard if it has a living one, otherwise home to the crystal. They do not fight. |
| Guards | Two new myrs that do not harvest: **Myr Enforcer** (tank) and **Lodestone Myr** (fighter). At most **one guard per lane**, on its own cap, not the ten-worker one. |
| Guard scope | **Bodyguards, not a defensive line.** Leashed to their well, they engage only what threatens a worker. The middle stays contested. |
| Death | A dead myr goes to the **Graveyard** (Magic's, not a memorial). It can be returned at Upkeep for **a third of everything invested in it**, never less than a new myr. |
| Names and stats | Every myr tracks what it has earned and how often it died; the base screen shows it, and Upkeep summarises the last wave. |
| Models | Guards start as scaled, tinted placeholders; the real Enforcer and Lodestone models are delivered later (in since 2026-10-25). |

## What already exists

- `scripts/myr.gd` - the worker: a server-run state machine (`WALKING_TO_MANA`,
  `HARVESTING`, `WALKING_TO_CRYSTAL`, `DEPOSITING`), replicated to clients by its own
  synchroniser. Every model already carries an unused **`run`** clip - fleeing is what it
  was built for.
- `scripts/temporary_ally.gd` - ghouls, mirrors, beasts: find a target, run at it, swing,
  return on a leash. The guard's combat is this, not a second implementation.
- `EnemyBase.evaluate_target` - enemies take the nearest player, myr or decoy inside their
  detection range (melee **15 m**, ranged **35 m**), and their taunt (`taunt_timer`,
  `taunt_source`, Roar) already overrides that. Enemies in the **storm** phase ignore myrs.
- `scripts/base_ui.gd` and the `MainController.request_*` RPCs - build, level, lane and
  name, all spent and applied on the server.

## 1. Fleeing

Myrs walk at 2 m/s, slower than the enemies, so the decision has to come early.

**Triggers** (server, checked a few times a second, not every frame):
1. A hostile enemy inside `myr_flee_radius` (~20 m) - out before a melee enemy (15 m) ever
   notices.
2. A hostile enemy whose `current_target` is this myr, at any distance - the ranged ones.

An enemy in the storm phase is not hostile to a myr and is ignored; otherwise every wave
walking past would stop the economy.

**Where to:**
- The lane has a living guard above `myr_guard_shelter_min_health` (~25%): to the point
  behind the guard, on the side away from the threat.
- No guard, or a dying one: home to the crystal.
- A loaded myr runs home and delivers on arrival - fleeing never costs it the cargo.

It runs (`run` clip, `myr_flee_speed_mult` ~1.5). It goes back to work once nothing hostile
has been inside the larger `myr_return_radius` (~28 m) for `myr_return_delay` (~3 s) - two
radii so it does not dither on the edge. It keeps its well slot while away, and a harvest it
broke off resumes where it stopped.

Side effect, and the intended one: a lane a player has cleared is a lane the myrs work
undisturbed.

## 2. Guards

A guard is assigned a lane in the base like a worker and stands at that lane's well. It
leaves its post only within `myr_guard_leash` (~10 m), attacks only enemies that target a
worker or come inside that radius, and walks back afterwards. It never flees.

| | Myr Enforcer | Lodestone Myr |
|---|---|---|
| Role | Tank, the shelter | Fighter, clears stragglers |
| Health | ~250 | ~120 |
| Damage | modest | high, grows with the well |
| Cost | **Affinity**: 7 colourless, -1 per living worker myr, at least 2 | 4 colourless |
| Special | Enemies that attack a worker within its radius are taunted onto it (the existing taunt) | +damage for each worker **harvesting** within its radius - a harvesting myr is a tapped artifact - capped |

Damage is tuned for a few enemies, not a squad: a whole squad overruns a lone guard. That,
the leash, and the storm phase are what keep guards from holding waves.

**Enchantments:** White's damage reduction and Red's speed apply to guards; Blue's phase
does not (it protects cargo, and a guard carries none); Black's death blast does.

Guards live in their own group (`myr_guards`), so they hold no well slot and do not count
towards `myr_max_count`, but enemies target them as they target myrs.

## 3. The Graveyard

A myr that dies - worker or guard - is not forgotten: it goes to the team's Graveyard with
its name, level, lane and stats, held in `RunState` and replicated.

At Upkeep the base screen lists the Graveyard. Returning a myr costs

    max(myr_mana_cost, round(invested * myr_return_cost_fraction))

with `myr_return_cost_fraction` = 1/3, where `invested` is its build cost plus every level
bought. A maxed worker (30 invested) comes back for 10; a level 3 (12) for 4. It comes back
at the crystal at its full level and heads for its old lane.

- It needs a free place under its cap. A team that filled ten slots with new myrs chooses.
- Its stats survive, and its death count goes up.
- The Graveyard lasts the run.

## 4. Stats

Per myr, replicated: mana delivered, trips, times fled, deaths. Per guard: kills, attacks
intercepted. The base screen shows them on each row - *"Marvin - Lv 5 - 87 mana - died 2x"*.

The top of the Upkeep panel gets one line for the wave just finished: mana the myrs brought
in, how often they fled, who fell. That is also the balancing instrument.

## 5. The myr keeper

With five players one of them looks after the myrs - likely the defender or the healer, who
already has the tools: Phalanx shelters myrs behind the knight, Selesnya shares self-heals
with them, Ivory Tower shields them. No new skills until this has been played.

## Settings

All in `GameSettings`, a new block next to MYRS: `myr_flee_radius`, `myr_return_radius`,
`myr_return_delay`, `myr_flee_speed_mult`, `myr_guard_shelter_min_health`,
`myr_return_cost_fraction`, and per guard health, damage, attack interval, leash, cost,
the Enforcer's affinity discount and floor, and the Lodestone's per-myr bonus and cap.

## Order

1. **Stats** per myr and the Upkeep wave summary - small, and from then on every later step
   can be measured.
2. **Fleeing**, home to the crystal only (there are no guards yet).
3. **Graveyard** and returning.
4. **Guards** with placeholder models, and workers sheltering behind them.
5. The delivered **models** through `tools/myr_character_builder.gd`, plus base-screen icons.

Each step gets a test under `tools/tests/`, like the other systems.

## Later, only if the numbers ask for it

- A **relay** halfway down a lane: myrs deposit there, the mana flows on. Halves the walk.
- A **solo** adjustment to myr health or cost.

## As built (2026-10-24)

- **Where:** all in `scripts/myr.gd` - a myr has a `role` (`worker`, `enforcer`, `lodestone`),
  set from its spawn arguments. Workers flee (`_update_danger`, `State.FLEEING`); guards guard
  (`_guard_process`, `State.GUARDING` / `FIGHTING`). `MainController` builds, assigns and returns
  them (`request_build_guard`, `guard_cost`, `request_return_myr`, `lane_guard`); `RunState` holds
  the Graveyard (`bury`, `unbury`, `return_cost`) and sends it to every peer with the rest of the
  run's state. The base screen (`BaseUI`) has the two guard buttons, a stats column and the
  Graveyard; the Upkeep panel has the myrs' line for the last wave (`UpkeepPanel._summarise_myrs`).
- **Guards are myrs, not TemporaryAllies.** The plan said to reuse `TemporaryAlly`'s combat. A
  guard turned out to share far more with a worker - lane, level, name, stats, the Graveyard, the
  base screen's row, the enchantments, the synchroniser - than with a summon, and its combat
  (walk up, swing on an interval, walk back) is a few dozen lines. So it is a myr with a role.
  Guards are in the `myrs` group as well as `myr_guards`: enemies go for them, heals and shields
  reach them. The worker cap (`myr_count`) and the wells' slots do not count them.
- **Returning** works from the base screen at any time, like building a myr, not only at Upkeep.
- **New workers find a lane by themselves** (added 2026-10-25): the base screen's "New myrs go
  to" picks the well with the fewest workers (the default), the one with the most that still has
  room, or none. A tie goes to a lane with a guard. `MainController.auto_lane`,
  `RunState.myr_auto_assign`. Myrs are bought only at the base now - the Upkeep panel no longer
  sells them.
- **Guards level** like workers: +`myr_level_hp_bonus` health and +`myr_guard_level_damage_bonus`
  damage per level.
- **A wild beast** is only run from when it comes within its own aggro radius plus
  `myr_beast_flee_margin`, or goes for the myr - one living near a well would otherwise keep that
  well's myrs off it for good.
- **Models (step 5, 2026-10-25):** each guard has its own model in every lane -
  `scenes/myrs/myr_enforcer.tscn` (Meshy "Azure Sentinel") and `scenes/myrs/lodestone_myr.tscn`
  ("Desert Sentinel") - built by `MyrCharacterBuilder.build_guards()`
  (`--script tools/build_myr_characters.gd -- guards`, which leaves the hand-tuned worker scenes
  alone). Both were rigged on Mixamo with the mutant creature pack downloaded onto the same rig,
  so their clips (`assets/animations/<guard>/`: walk, run, idle, death, and the blow) need no
  retarget. The PBR maps come from Meshy's separate texture export of the same model (same
  albedo, same UVs). The builder sizes a guard's scene itself and `Myr` keeps that size rather
  than its flat 100x, so `myr_enforcer_scale` / `myr_lodestone_scale` still say how much bigger
  than a worker each is: about 1.5x and 1.2x on the skeleton, much broader. A standing guard
  plays its idle instead of a frozen walk frame. The tint glow is gone; `ROLE_TINTS` stays as
  the guards' colour on the base screen and on their hits. The meshes are Meshy's full ones (Enforcer
  13.5k triangles, Lodestone 37.5k, a worker 8-9.5k). Halving them with Godot's own simplifier
  (its first LOD made the mesh) was tried on 2026-10-25 and dropped: it looked clearly worse on
  every myr. Godot's LODs already thin them out at a distance.
- **The blow:** the Enforcer punches, the Lodestone swipes (Mixamo "mutant punch" / "mutant
  swiping"). As with an enemy, the clip is stretched over the attack interval and the damage
  lands on its measured impact frame (`hit_ratio`, 27% / 46%), not when the swing starts
  (`Myr._guard_strike` -> `_land_strike`); the guard stands still until then, and a target that
  stepped out of reach in between is missed. `tools/tests/myr_guards_shot.tscn` shows both next
  to a worker, and each blow at its start, impact and follow-through.
- **Not done:** the base screen still shows the worker's painted portrait for a guard, framed
  and tinted in its colour. The creature pack's roar is in `assets/animations/<guard>/` but
  unused - a candidate for the Enforcer's taunt.

