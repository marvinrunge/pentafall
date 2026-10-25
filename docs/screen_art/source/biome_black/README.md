# Black biome: graveyard set

More set dressing for the black lane (drowned willow swamp: decay, crypts), from the user's
asset sheet `graveyard_sheet.jpg` (2026-10-23; `graveyard_mood.jpg` is the mood it is
after). The same route is meant for every biome: a sheet, a `cuts.json`, a `props.json`.

1. `python tools/cut_sheet_references.py docs/screen_art/source/biome_black/cuts.json`
   cuts each object out of the sheet into `<id>.png`, on the sheet's own dark backdrop,
   neighbours and labels painted over (Meshy removes a plain background itself).
2. The user approves a reference: `python tools/mesh_biome_props.py docs/screen_art/source/biome_black --approve <id>`.
3. `python tools/mesh_biome_props.py docs/screen_art/source/biome_black --go <id> ...`
   meshes the approved ones, about 15 credits each, into `assets/generated/biome-black-<id>/`.

## Taken from the sheet

| id | what | tris | height |
|---|---|---|---|
| `mausoleum` | the domed mausoleum, a landmark | 10000 | 6.5 m |
| `gothic_arch` | freestanding pointed arch, a ruin | 3000 | 4.5 m |
| `window_wall` | ruined wall with three Gothic windows | 3500 | 3.5 m |
| `stair_ruin` | stair with an arcaded balustrade | 4000 | 2.4 m |
| `crypt_gate` | iron gate between two stone pillars | 5000 | 3.2 m |
| `headstone_gothic`, `headstone_round`, `headstone_tall` | headstones | 700-900 | 1.1-1.4 m |
| `cross_celtic`, `cross_plain` | stone crosses | 700-1000 | 1.4-1.7 m |
| `tomb_lidded`, `tomb_great` | sarcophagi | 1500-1800 | 1.0-1.2 m |
| `lantern` | iron lantern (the light is the game's) | 1200 | 0.6 m |
| `brazier` | fire bowl, flames painted out - weak, see below | 1000 | 0.7 m |
| `rubble` | broken pillar pieces | 1500 | 0.9 m |

## Left out

- **The loose dome** - the mausoleum's own.
- **The iron fences and the open gate** - bars a few pixels wide; Meshy fills between
  them or loses them. The closed gate is taken as the one try at it.
- **The dead trees and bushes** - thin branches, the same problem; `nature-black-dead-snag`
  in the nature set covers a dead tree.
- **The paved floor** - ground, for the terrain textures, not a mesh.
- **The second lantern, the spiked brazier, the small headstone and cross, the flat slab
  and the small rubble** - near-duplicates of what is taken.

The brazier's flames hid the back of its rim; painted out, they leave a dark smudge in the
bowl. Better made from a clean image of an empty bowl than meshed from this one.
The headstones and crosses are small on the sheet (about 110 x 185 px), so their textures
come out softer than the big pieces'.
