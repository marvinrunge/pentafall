# Onboarding Plan

A new player does not find out on their own that the crystal is also the myr workshop, or that
the wells in the biomes can be worked by hand. In a duo test the experienced player had to say
all of it out loud. This plan puts that voice into the game: a little starting mana, and a
short list of first objectives on the HUD, Minecraft-advancement style, that walks a player
through the economy one step at a time.

Planned 2026-10-24, not implemented yet. Independent of the other plans; the objectives that
need them (guards, revive) are simply added when those exist.

## 1. Starting mana

The run starts with **one mana of every colour** (5 in all) instead of an empty pool - the
crystal starts a little charged.

- `GameSettings.run_starting_mana_per_color = 1`, applied in `RunState.reset()`.
- One of each rather than two colourless: it shows the five colours in the pool from the first
  second, and since a myr costs colourless it still buys **two myrs** (2 + 2, one left over).
- It is what makes the first objective doable right away, before any elite has died.

## 2. Objectives

### What the player sees

A small tracker on the HUD, under the minimap: the current one or two objectives, each one line
plus a hint line in smaller type with the right key (`InputHint.key`). A finished one ticks,
flashes and slides out; the next slides in. No banner, no log spam - this is a checklist, not
an announcement.

### The chain

| # | Objective | Hint | Done when |
|---|---|---|---|
| 1 | Build a myr | Go to the crystal and press Interact | a myr is built |
| 2 | Send it to a mana well | Pick a lane for it in the base screen | a myr is given a lane |
| 3 | Bring mana home yourself | Hold Interact at a well, carry it to the crystal | a hand-harvested load is banked |
| 4 | Spend a skill point | Open the skill tree | a rank is bought |
| 5 | Level up a myr | In the base screen | a myr reaches level 2 |
| 6 | Buy something at Upkeep | Between waves | any Upkeep purchase |
| 7 | Build a guard myr | *(once MYR_GUARDS_PLAN is in)* | a guard is built |
| 8 | Revive a teammate | *(multiplayer only)* | a revive channel completes |

Data-driven: one table in a new `scripts/objective_database.gd` (id, text, hint, condition
signal, `multiplayer_only`, `requires`), so 7 and 8 are rows, not code. Each condition hangs off
a signal that already exists or is added once (`SignalBus.mana_deposited` with a hand-harvest
source, myr built / levelled / assigned, `spell_rank_changed`, revive completed).

### Whose objective

**Per player**: the point is to teach each player, and a veteran who builds every myr must not
tick the newcomer's list for them. Team purchases count for the player who clicked.

### When it shows

- On by default for a profile that has not finished the chain; finished objectives are stored in
  `UserSettings` and do not come back next run.
- A setting to hide it, and a button to reset it (to show a friend on the same machine).
- Server-independent: every peer tracks only its own player.

### Small helpers that go with it

- While objective 1 or 5 is active, a soft marker over the crystal's interact point.
- While objective 3 is active, the wells pulse on the minimap.

## Order

1. Starting mana (one setting, one line in `RunState.reset`).
2. The tracker UI and objectives 1-6.
3. Persistence and the setting.
4. Objectives 7 and 8 as their features land.
5. A test: the chain advances on the right signals and never on a teammate's action.

## Decided (2026-10-24)

1. Objectives are **per player**.

## Open questions

1. Anything missing from the chain - equipping an item, killing an elite, visiting a guild camp?
