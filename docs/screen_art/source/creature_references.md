# Creature reference images (boar, stone golem)

Reference images for two Meshy image-to-3D models for the colour skills. Nothing goes to
Meshy until the user approves the image (see the nature pipeline's approval rule).

| File | Skill | Model |
|---|---|---|
| `boar_reference.png` | Curse of the Swine (blue) | what an enemy turns into for a few seconds |
| `stone_golem_reference.png` | Awaken (green) | raised from a standing stone of the crystal ring |

Approvals (Meshy only ever gets exactly these pixels):

- `boar_reference.png`: approved by the user 2026-10-22,
  sha256 `c98b46337f05c6f9cc6e95f1c7a4b3f67f10511876443ef8287a4e2eb97c39a1`.
- `stone_golem_reference.png`: approved by the user 2026-10-22,
  sha256 `5438fc00df1187e857f2269d791683acb8f771d6e55a80d8e6338bdc9e25e807`.

## Meshed 2026-10-22

The user gave the go for both; `python tools/mesh_creatures.py --go` spent 15 + 15 credits.

| | Triangles | Raw size (x, y up, z) | Split share | Note |
|---|---|---|---|---|
| `assets/generated/boar/` | 6,073 | 0.29 x 0.62 x 1.0 m | 0 % (smooth) | the bristle mane came out as a few hard black fins |
| `assets/generated/stone_golem/` | 10,928 | 1.0 x 0.92 x 0.36 m | 0 % (smooth) | A-pose held, eyes and moss in the texture |

Mixamo would not take Meshy's FBX (2026-10-23), so `stone_golem_mixamo.zip` holds an OBJ +
MTL + 2k base colour PNG at 2.8 m, exported from the GLB with Blender 5.2 headless
(`G:\Program Files\Blender Foundation\Blender 5.2\blender.exe`).

The boar is left out for now (the user, 2026-10-23): not rigged and not used in the game;
Curse of the Swine keeps its green beast stand-in.

The user rigged the golem on Mixamo and downloaded the Creature Pack for it (2026-10-23):
`assets/enemies/bosses/stone_golem/stone_golem.fbx` (with skin, albedo `stone_golem_0.png` from
Meshy's texture) and seven clips in `assets/animations/boss/golem/` (walk, run, idle, swipe as
attack, jump attack as special, roar, dying). `tools/boss_character_builder.gd` has a `golem`
set and a `stone_golem` entry; `scenes/bosses/stone_golem.tscn` is built from them, and
`TemporaryAlly` stands it 2.8 m tall for Awaken instead of the grey treant.

Meshy normalises the size (no `auto_size`), so both get their real scale (boar about 1 m at
the shoulder, golem about 2.8 m) when they are rigged. Neither needs the smoothing import
script.

## Meshy and rigging proposal (run 2026-10-22)

**Script.** Neither existing tool fits: `tools/meshy_asset.ps1` is text-to-3D only and
`tools/mesh_goblin_caves.py` is hard-wired to the goblin kit. On the go, a new
`tools/mesh_creatures.py` (a copy of the goblin script for these two, already dry-run) is
added. It sends the same image-to-3D request as the nature set (`meshy_request`), refuses a
reference whose SHA-256 differs from the approved one above, and writes to
`assets/generated/<name>/`.

**Command** (from the repo root, PowerShell):

    $env:MESHY_API_KEY = [Environment]::GetEnvironmentVariable('Meshy API Key','User')
    python tools/mesh_creatures.py --go

Dry run (free, sends nothing) - the request bodies it would send:

| | boar | stone_golem |
|---|---|---|
| model | Smart Topology, `meshy-t2` | Smart Topology, `meshy-t2` |
| `target_polycount` | 6,000 (several on the field at once) | 10,000 (one at a time, close up) |
| texture | 2k PBR | 2k PBR |
| `pose_mode` | - | `a-pose` (for Mixamo) |
| formats | glb + fbx | glb + fbx |

**Cost.** 15 credits each, **30 in total** (Meshy API pricing page, checked 2026-10-22:
meshy-t2 mesh with 2K texture = 15 credits). Running `--go boar` first spends 15 and shows
the quality before the golem.

**After the download.** Check the split share for faceting and set the smoothing import
script if needed (characters smoothed all over).

**Rigging, boar - Blender beast pipeline** (`assets/enemies/beasts/source/`, via Blender MCP):
add a `boar` entry to `beast_params.py`, import `boar.fbx` into `beasts.blend`, run
`beast_rig.py` and `beast_anim.py` for the usual clips (idle, walk, run, attack, special,
hit, death), set `scene.render.fps = 30` before export, and export from the origin to
`assets/enemies/beasts/boar/boar.glb`. No Meshy credits.

**Rigging, golem - Mixamo + boss character builder.** The user uploads
`assets/generated/stone_golem/stone_golem.fbx` to mixamo.com (Adobe sign-in, which Claude
cannot do) and places the auto-rigger markers. The rigged FBX "with skin" goes to
`assets/enemies/bosses/stone_golem/stone_golem.fbx`, and `tools/boss_character_builder.gd`
gets `"stone_golem": {"mesh": ".../stone_golem.fbx", "set": "mutant"}` - the treant's clip
set, so it moves like the treant it replaces. Build with `BossCharacterBuilder.build_all()`
(through Godot MCP while the editor is open). Meshy's own rigging (5 credits) was not
chosen: its skeleton is not `mixamorig_*`, so the mutant clips would not fit.

**Swap-in.** `scripts/temporary_ally.gd` (golem: the grey treant) and the Curse of the
Swine placeholder then point at the new scenes. Those files belong to the skills session,
so the swap waits until that work has landed.

`stones_crop.jpg` is cut from `site/images/screenshots/siege_wide.jpg` and was attached to
the golem prompt so the rock matches the ring.

## Gemini prompts

Both follow `mesh_concept_prompt` in `tools/nature/nature_pipeline.py`: one object, front
three-quarter view, wide margin, flat grey background, no shadow, no glow halo, and a
neutral pose a rig can be fitted to.

### Boar

The first, "harmless" boar was rejected by the user (2026-10-22: no big tusks, too tame).
`boar_reference.png` is the second try, from this prompt (Gemini 1024 px preview; the
full-size download was blocked by Google's traffic check):

> Make a new image, much wilder. Game asset concept render of a single isolated huge wild boar for a semi-realistic dark fantasy game, as the reference for a 3D model. A massive, menacing old tusker: a heavy front-loaded body with a high muscular hump over the shoulders, a long wedge-shaped head held low, and BIG prominent tusks - long ivory-yellow lower tusks curving up and outward past the snout like sabres, plus thick upper tusks curling up beside them. A thick shaggy mane of long dark bristles standing up along the neck and spine, coarse dark brown-black fur, a scarred grizzled snout, small fierce amber eyes, ears laid back, nostrils flared. It looks dangerous and untamed, not cute, not friendly, not a farm pig. Pose: standing still on all four legs in a neutral pose for rigging - all four legs straight and vertical, clearly separated from each other and from the belly, hooves flat, head level, mouth closed, tail hanging down. About 1 metre tall at the shoulder and 1.7 metres long. Style: semi-realistic fantasy game asset - believable anatomy, real surface detail, colour slightly richer than life, a bold silhouette that reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. Framing: front three-quarter view from slightly above, the boar turned about 35 degrees to the left of the camera, the whole animal centred and fully inside the frame with a wide empty margin on every side, nothing cropped, all four legs and hooves fully visible. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no cast shadow, no contact shadow, no other objects, no scenery. Lighting: soft even neutral studio light, no coloured light, no rim light, no bloom. No text, no logo, no watermark, no border.

### Stone golem (with `stones_crop.jpg` attached)

> Game asset concept render of a single isolated stone golem for a semi-realistic fantasy game, as the reference for a 3D model that will be rigged as a humanoid. The golem is built from the same weathered standing-stone rock as the attached reference image: pale to mid grey granite with lichen speckles, darker rain streaks, rounded worn edges, patches of green moss on the shoulders, head and in the joints. Match only the rock's colour and surface from the reference, not its shapes. The body is a few big rough-hewn stones: the torso one large upright monolith slab, tapering towards the waist; the head a smaller rounded stone sitting low between the shoulders, with two deep eye hollows holding a dim moss-green light inside (no glow outside the stone); shoulders and upper arms massive boulders, forearms long stone pillars, big blocky hands with thick stone fingers; legs short sturdy stone pillars on broad flat feet. Thin roots and moss bind the stones together at the joints. Calm, ancient, protective, not evil. About 2.8 metres tall, heavy and broad-shouldered. Pose: neutral A-pose for rigging - standing straight, facing forward, arms straight and held out and down at about 45 degrees, clearly apart from the body, hands open with the fingers slightly apart, legs straight and apart at hip width, feet flat, head level. Style: semi-realistic fantasy game asset - believable natural stone, real surface detail (fractures, weathering, lichen), colour slightly richer than life, a clear silhouette that reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. Framing: front three-quarter view from slightly above, the golem turned about 30 degrees to the left of the camera, centred and fully inside the frame with a wide empty margin on every side, nothing cropped, hands and feet fully visible. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no rubble, no scenery, no particles or dust. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom. No text, no logo, no watermark, no border.
