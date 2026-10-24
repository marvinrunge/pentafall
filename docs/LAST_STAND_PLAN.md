# Last Stand Plan

Two changes to the end and the noise of a wave. Planned 2026-10-24, not implemented yet.

1. **Last Stand** - the end of a wave is triggered by how much of it has been killed, not
   only by the clock. The last few enemies storm the crystal and are revealed on the
   minimap, so nobody has to comb the fog for a white soldier stuck on a standing stone.
2. **Fewer announcements** - the per-lane arrival banners and the boss arrival banner go,
   from the screen and from the Tab log, and the code behind them with them.

## The problem

Near the end of a wave a few enemies are usually stuck somewhere - in a forest, or (wave 1,
often) a white soldier hung up on a stone of the standing-stone ring. Pathfinding has had
several rounds of fixes and none got it to 100%. The team then searches the whole map in the
fog of war.

The safety net that exists does not help in practice: a wave's time limit
(`GameSettings.wave_time_limit`) starts when its last group lands and is **240 s at wave 1**,
then the wave storms the crystal for `wave_storm_duration` (20 s). It is a backstop for a
stalled wave, not something to wait out every wave. Explorer's Scope, the item that comes to
mind, shows wild beasts only, never wave enemies.

## 1. Last Stand

### Trigger

Server only, in `WaveManager`, checked on every enemy death once the wave is fully on the
map (`is_spawning` false, `_spawn_queue` empty):

    remaining <= min(last_stand_max_remaining, ceil(wave_total * last_stand_fraction))

| Setting | Default | Why |
|---|---|---|
| `wave_last_stand_fraction` | 0.15 | The last 15% of the wave. Wave 1 (~15 enemies) stands at 3 left. |
| `wave_last_stand_max_remaining` | 10 | A late wave of a couple of hundred would otherwise send thirty at the crystal at once. |

A percentage rather than a flat 10, because early waves are barely bigger than ten: a flat
threshold would lift the fog in wave 1 before the fighting began. `wave_total` is the wave's
planned unit count (`_count_units` at `start_next_wave`), kept in a new field - stragglers
from an earlier wave never count towards it.

### What happens

It **is** the existing storm (`_begin_storm`), started early: what is left drops its formation
and goes for the crystal, faster and deaf to players, myrs and taunts; after
`wave_storm_duration` the wave counts as done and anything still standing becomes a straggler,
exactly as today. No second mechanic. Its meaning changes from "time's up" to "the wave's last
stand", and the team defends the crystal against it rather than hunting for it.

Two additions:

- **Revealed.** A storming enemy is drawn on the minimap even in the fog
  (`Minimap._draw`, next to Explorer's Scope's exception), with a pulsing outline so it reads
  as revealed rather than seen. Clients have the enemy and its position, but `storm_timer`
  lives on the server only, so `begin_storm` sets a new `revealed` flag that is added to the
  enemy's synchroniser (on change).
- **Unstuck on the way out.** `begin_storm` asks for one immediate recovery check
  (`EnemyBase._check_recovery`) on an enemy that has stood still, so the soldier on the stone
  is put back on the navmesh and actually comes. Never killed - a kill nobody made would pay
  the team for nothing, the rule recovery already follows.

### What stays

The time limit stays, unchanged, as the backstop: a team that kites a wave on purpose (to let
the myrs bank mana) never reaches the kill threshold, and the clock still ends it.

## 2. Fewer announcements

### Removed

From `WaveManager`, raised by the server on group deployment and relayed to every peer through
`SignalBus.lane_warning_requested`, which is also what writes the Tab log:

- `"<COLOUR> <BANNER> - <n> STRONG"` per battle group, with `- MINIBOSS SIGHTED`
- `"<A + B> ALLIANCE MASSING - <n> STRONG"`
- `"<A + B> ALLIANCE CHARGES"` (`_on_warband_charged`, on `EnemySquad.charge_started`)
- `"<COLOUR> BOSS HAS ARRIVED"` - the boss health bar already says so

With them goes what only they used: `_announce_group`, `_on_warband_charged`, `_color_list`,
`_get_lane_color`, the `charge_started` connection in `_create_squad` (and the signal on
`EnemySquad` if nothing else listens), and the `banner` field of every `SquadDoctrine` entry.

### Kept

- One short Last Stand line, `"THE WAVE MAKES ITS LAST STAND"`, when the kill threshold starts
  the storm. A storm started by the time limit keeps `"TIME'S UP - THE WAVE STORMS THE
  CRYSTAL"`. So `_announce` and `_net_announce` stay.
- Level-ups, equipment found, the mission, "Wave n begins / cleared", Upkeep, game over.
- Boss phase banners (`"FIRE GIANT - KINDLED"`).

### Also to touch

- `scripts/hud.gd`: the Tab-log comments name boss arrivals and lane warnings as examples.
- `tools/tests/scoreboard.gd`, `scoreboard_shot.gd`, `day_start.gd`: use the removed texts as
  fixtures - swap them for a level-up or an equipment line.
- `docs/BOSS_DESIGN.md`, `scripts/game_settings.gd`: mention the arrival banner.

## Order

1. Remove the announcements (pure deletion, smallest diff, easy to verify).
2. Last Stand trigger on top of the existing storm.
3. Minimap reveal of storming enemies.
4. The recovery nudge at storm start.
5. A test under `tools/tests/`: a wave with one enemy pinned in place - the Last Stand starts
   at the threshold, the pinned one is recovered and storms, the wave closes.

## Later, separate and not urgent

**Stuck hotspots.** Recovery already prints every reposition with its position. Collected over
a few runs and drawn onto the map, they would show whether it is always the same stone or the
same patch of forest, and the navmesh could be fixed exactly there.

## Decided (2026-10-24)

1. The Last Stand gets one short line on the banner and in the log.
2. Boss phase banners stay.
3. 15% of the wave, at most 10 enemies.
