# Myr Matrix Plan

The crystal's surroundings say little about the myrs that are the team's economy. **Myr Matrix**
(Mirrodin block) - a great artifact lattice full of holes that myrs climb in and out of - would
make the hub the myrs' home: new ones come out of it, idle ones swarm it, dead ones sleep in it.

Planned 2026-10-24, not implemented yet. The model is generated with Meshy (`tools/meshy_asset.ps1`).
Ties into MYR_GUARDS_PLAN's Graveyard, but does not need it to start.

## Where it stands

Three options were on the table:

| | Floating over the crystal | Standing at the hub | Whole hub redone in Mirrodin style |
|---|---|---|---|
| Look | the most epic | grounded, readable | the most coherent |
| Cost | hides the crystal, the one thing everybody looks at | one model, one spot | many assets; the stone ring is gameplay (Awaken, Vine Harpoon) and stays |
| Job | decoration | the myr workshop | decoration |

**Recommendation: standing at the hub**, a few metres beside the crystal, inside the stone ring
and out of the lanes' way. The crystal keeps floating free as the objective; the Matrix becomes
the place the myrs belong to. The full Mirrodin hub stays a later, optional step.

## What it does

- **Interact point of the base screen** moves to the Matrix (the crystal's stays too, at first).
  The onboarding objective "Build a myr" then points at something that looks like it builds myrs.
- **A new myr** climbs out of a hole and walks off to its lane.
- **Idle myrs** - built but not given a lane - climb about on it and through its holes. Today an
  idle myr has no model at all and stands invisible at the crystal.
- **The Graveyard** (once MYR_GUARDS_PLAN is in): each dead myr is a dark, dormant myr in one of
  the cells. Returned, it lights up in its lane's colour and climbs out.

### How the myrs move on it

Cosmetic only. The Matrix spawns its own **visual copies** (the myr model, no body, no AI) for
idle and dead myrs from data every peer already has replicated, and moves them along hand-placed
curves (`Path3D`) through the holes. The real myr nodes are untouched: no new physics, no
navigation over a lattice, nothing new to send over the network. Capped at the myr limit.

## The model

Meshy prompt, first draft:

> A colossal ancient artifact lattice, Myr Matrix from Magic: The Gathering's Mirrodin: an
> open cage-like structure of curved darksteel ribs and plates, riddled with round holes and
> hexagonal cells, roughly 8 m tall, faint cyan light glowing inside the cells, weathered dark
> grey-blue metal with bronze trim, strong readable silhouette, isolated object, no ground plane

- Colourless on purpose: dark metal, the cyan of the myrs' eye rings, no lane colour.
- Holes large enough for a 1 m myr; a `Path3D` per route is placed by hand after import.
- Collision: a simple convex hull, players walk around it.

## Later, optional: a Mirrodin hub

If the Matrix looks right, the hub could follow it piece by piece, still keeping the stone ring:
the five **artifact lands** of Mirrodin as markers where each lane leaves the hub - Ancient Den
(White), Seat of the Synod (Blue), Vault of Whispers (Black), Great Furnace (Red), Tree of Tales
(Green) - and a darksteel floor around the crystal (Darksteel Citadel). The crystal itself has a
fitting name in **Mirrodin's Core**: a land that stores charge counters and gives mana of any
colour - exactly what the crystal does with the team's pool.

## Order

1. Generate the model, import it, place it, collision.
2. Move the base screen's interact point to it.
3. Idle myrs on it (visual copies on paths).
4. New myrs climbing out.
5. Graveyard myrs in its cells (needs MYR_GUARDS_PLAN step 3).
6. Optional: the Mirrodin hub.

## Open questions

1. Standing at the hub (recommended) or floating over the crystal?
2. Does the crystal get a name - Mirrodin's Core?
