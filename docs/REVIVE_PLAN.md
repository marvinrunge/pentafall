# Revive Plan

Reviving a downed teammate has, in practice, never worked: nobody sees where the teammate is
lying, and whoever gets there and kneels for the channel is surrounded and killed - in this game
standing still for three seconds is death, ranged enemies above all.

Planned 2026-10-24, not implemented yet. Independent of the other plans.

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

## 1. Finding them

- **Minimap:** a downed teammate is drawn as its own mark - a pulsing white-and-red cross with a
  ring around it that empties as `down_timer` runs out. Drawn through the fog: a teammate is
  always known.
- **Screen edge:** an arrow at the edge of the screen pointing at each downed teammate off
  screen, with the distance in metres and the same emptying ring. A small reusable HUD piece
  (`EdgeMarker`), so the Last Stand reveal can use it too if wanted.
- **One line** on the banner and in the log: *"Anna is down!"* - the one announcement worth the
  noise, because it asks for something.

## 2. Surviving the channel

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
2. Edge arrows.
3. The "is down" line.
4. The Revive Ward.
5. A test: the ward pushes, reduces and drops at the right moments, and only while channelling.

## Open questions

1. Is 50% the right reduction, or should the helper be untouchable for the 3 seconds?
2. The "is down" line - wanted, given the cut to announcements?
