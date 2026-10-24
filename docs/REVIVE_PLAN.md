# Revive Plan

Reviving a downed teammate has, in practice, never worked: nobody sees where the teammate is
lying, and whoever gets there and kneels for the channel is surrounded and killed - in this game
standing still for three seconds is death, ranged enemies above all.

Planned and implemented 2026-10-24 (part 1): `scripts/downed_mark.gd` draws the mark,
`Minimap._draw` and `TeamFrames` use it, `Player.down_total` is what the countdown empties from;
test `tools/tests/team_frames.tscn`.

## What exists

- Downed: `player_downed_duration` 20 s in multiplayer (5 s solo, nobody to channel), then a
  respawn at the base. Enemies already ignore a downed player.
- The channel (`Player._update_revive_channel`): `player_revive_channel_time` 3 s within
  `player_revive_range` 3 m, broken by the helper moving, attacking, casting, kicking or jumping -
  not by taking damage.
- Black's enchantment **Animate Dead** already shortens downed time and the channel; white's
  skill **Rally the Fallen** revives from range. So the enchantment that helps reviving exists -
  it is black's, not white's.
- The minimap draws every player as the same green arrow, downed or not.
- `TeamFrames` shows each teammate's class head with a health ring; downed, the head is greyed
  and the ring counts down the seconds left.

## 1. Finding them

- **Minimap:** a downed teammate is drawn as its own mark - a pulsing white-and-red cross with a
  ring around it that empties as `down_timer` runs out. Drawn through the fog: a teammate is
  always known.
- **Team frames:** the column of teammates down the left edge (`TeamFrames`) already greys a
  downed teammate's head and turns its ring into the countdown - too quietly to be noticed in a
  fight. A downed frame now **pulses**, carries the same cross as the minimap mark, and shows the
  distance to them in metres underneath.

No screen-edge arrows and no "is down" line on the banner or in the log (decided 2026-10-24):
the map and the frames are enough.

## 2. Surviving the channel - not now

**Decided 2026-10-24: nothing is built for this for now.** Finding the downed teammate comes
first; the idea below stays here in case testing shows it is still needed.


A **Revive Ward**, for everyone, no skill or enchantment needed - reviving is basic teamwork and
should work without a build behind it:

- When the channel starts, a white dome rises over helper and downed player
  (`player_revive_ward_radius` ~3.5 m).
- Enemies inside are **pushed out** once, at the start (`player_revive_ward_push`).
- While the channel runs, the helper takes **50% less damage** (`player_revive_ward_reduction`).
- The dome falls the moment the channel ends or breaks.

It does not make the helper safe; it buys the three seconds. A swarm still wins, and leaving the
area to kite them off first stays a real choice.

## 3. Optional, if the ward is not enough

- White's **Sphere of Safety** could also strengthen the ward per stack. Only if testing shows
  the base ward is too weak - Animate Dead already speeds the revive itself.

## Order

1. Minimap mark with the countdown ring.
2. The pulsing team frame with cross and distance.
3. A test: mark and frame highlight appear for a downed teammate, count down, and go when they
   are up or respawned.
