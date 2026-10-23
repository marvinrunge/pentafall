# Tower reference images

Reference images for the five round-two towers (`scripts/tower.gd`), for Meshy image-to-3D
(the same route as the golem, `tools/mesh_creatures.py`). Each follows the design of its skill
icon in `assets/icons/`, rendered semi-realistic. The icons were NOT attached: Gemini asked to
accept its terms for image uploads, which is the user's to accept, so the prompts carry the
designs in words (the shared tail below without its first sentence). 1024 px previews, made
2026-10-23; `tower_references_sheet.jpg` shows all five.

Every tower is a STATIC structure: no characters, creatures or insects on or around it
(the user, 2026-10-23 - "wie beim Goblin Sharpshooter keine Charaktere"), nothing that would
have to be rigged or animated. Life, glow and shots are added in the game.

Nothing goes to Meshy until the user approves the image.

All five were approved and meshed on 2026-10-23 (`tools/mesh_creatures.py`, Smart Topology,
15 credits each, the task ids in `assets/generated/<id>/<id>.meshy.json`); they stand in the game
as `scenes/towers/<id>.tscn`. Meshy's FBX copies are not used by the game and wait outside the
project in `.meshy/tower_fbx/` (git-ignored).

| File | Tower | Colour |
|---|---|---|
| `ivory_tower_reference.png` | Ivory Tower | white |
| `glacial_fortress_reference.png` | Glacial Fortress | blue |
| `bontus_monument_reference.png` | Bontu's Monument | black |
| `goblin_sharpshooter_reference.png` | Goblin Sharpshooter | red |
| `hornet_nest_reference.png` | Hornet Nest | green |

## Shared tail (appended to every prompt)

> Use the attached icon only for the design and the shapes; render it as a semi-realistic fantasy game asset - believable materials and proportions, real surface detail (weathering, grain, cracks), colour slightly richer than life, a clear silhouette that reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. A static structure only: no people, no characters, no creatures, no animals, no insects, no ghosts, nothing alive on or around it. Framing: three-quarter view from slightly above, the whole structure centred and fully inside the frame with a wide empty margin on every side, nothing cropped, standing on its own flat base. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no scenery, no other objects. No glow halo outside the object, no bloom, no particles, no smoke, no magic effects in the air. Lighting: soft even neutral studio light, no coloured light, no rim light. No text, no logo, no watermark, no border.

## Prompts

**Ivory Tower** - Game asset concept render of a single isolated tower for a fantasy tower defense game: a slender round tower of polished white ivory and pale marble, about 4.5 metres tall, with three gold bands around it, a few narrow arched windows, an arched door at the foot, and a gilded onion dome on top ending in a gold spire; a squat stepped stone base.

**Glacial Fortress** - Game asset concept render of a single isolated tower for a fantasy tower defense game: a small fortress tower made entirely of blue glacial ice, about 4.5 metres tall - crenellated battlements, an arched doorway, translucent blue ice with white frost and cracks, jagged ice spikes jutting from its base - and a large faceted ice crystal mounted on the top like a launcher, pointing forward.

**Bontu's Monument** - Game asset concept render of a single isolated monument for a fantasy tower defense game: a tall black obsidian obelisk, about 4.5 metres tall, its upper half carved into the head of a crocodile god with a long toothed snout, small eyes inlaid with dull violet amethyst, carved glyph bands down the shaft, standing on a stepped base of dark stone.

**Goblin Sharpshooter** (second version - the user wanted it closed, 2026-10-23: an open
platform would need a visible, animated goblin) - Game asset concept render of a single isolated tower for a fantasy tower defense game: a ramshackle goblin watchtower about 4.5 metres tall, a wooden frame on four crooked stilts with cross-bracing, and on top a fully ENCLOSED wooden cabin - plank walls on all four sides and a sloped plank roof, no open platform, nobody visible - built from mismatched scavenged planks, rope lashings, rusty nails and scrap metal patches, a ragged red cloth banner hanging off the roof, and the tip of a big loaded crossbow bolt and its bow arms sticking out of a narrow shooting slit in the front wall. Closed shutters, no windows anyone could be seen through.

**Hornet Nest** - Game asset concept render of a single isolated object for a fantasy tower defense game: an enormous papery hornet nest, grey-brown with layered paper bands and a few dark entrance holes, about 3 metres tall, hanging from a thick gnarled dead branch that arches over it out of a mossy tree stump - the stump, the branch and the nest one solid piece standing on the ground.
