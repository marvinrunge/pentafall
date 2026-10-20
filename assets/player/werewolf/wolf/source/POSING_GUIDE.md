# Posing the werewolf clips

You set the key poses, Claude does the rest (inbetweens, planted paws, forward movement,
loop, tail and jaw).

## Setup
- Use `werewolf.blend` in this folder (File > Open). If Blender asks about saving
  `beasts.blend`, say **Don't Save**; the werewolf work is all in `werewolf.blend`.
- The scene is `Werewolf_Inspect`, with a 30 fps timeline. The gallop runs frames **1–21**.
- Forward is **−Y**. The character's left is **+X**. The grey floor is the ground.

## The controls (collection `WW_Controls`, drawn in front of the mesh)
| Control | What it does |
|---|---|
| `WW_Body` (cube) | The hips. Move it for body height and position, rotate it for pitch, roll and yaw |
| `WW_Paw_Front_L/R` (spheres) | Wrist position. The foreleg follows by IK |
| `WW_Aim_Front_L/R` (crosses, children of the paws) | Where the forepaw points. Move these to flatten or curl the paw |
| `WW_Paw_Hind_L/R` (spheres) | Ankle (hock) position. The hind leg follows by IK |
| `WW_Aim_Ball_*` / `WW_Aim_Toe_*` | Ball of the foot and toe tips (keep them on the floor while planted) |
| `WW_Elbow_L/R`, `WW_Knee_L/R` (cones) | Which way the elbows (back) and knees (forward) point |
| `WW_Look` (arrow) | Where the head and neck look |
| Bones `Spine`, `Spine1`, `Spine2`, shoulders, fingers | Rotate these in Pose Mode (arch or stretch the back) |

## Workflow
1. Go to a key frame. Move the controls in **Object Mode** (G / R, plus X/Y/Z to lock an axis).
2. Key it: select the controls you changed, press **I** and pick **Location & Rotation**. For
   spine bones: Pose Mode, select them, **I**, then **Rotation**.
3. **Work in place.** Keep `WW_Body` around the same Y. A planted paw slides **backward
   (+Y)** from key to key, about 0.04–0.05 m per frame. It doesn't have to be exact: the
   bake measures the slide, turns it into forward movement and pins the paws.
4. **Aim paws with the crosses, don't rotate the spheres.** Turning a paw sphere a long
   way between two keys (for example −88° at f6 and 142° at f11) makes Blender spin the
   paw the long way round in between, and it dives through the floor (the f8 problem).
   If you did rotate one, Claude converts it to cross positions before baking.
5. Leave the last frame (21) alone. The bake copies frame 1 there so the loop closes.
6. Press Space to play, and save with Ctrl+S. Then tell Claude it's ready.

## The gallop keys (already keyed from Claude's version; change whatever looks wrong)
| Frame | Pose |
|---|---|
| 1 | **Gathered.** Hind paws land under the hips (left first, right about 2 frames later). Forelegs folded under the chest, swinging forward. Back arched |
| 6 | **Hind push.** Both hind paws planted behind the hips and pushing. Body stretching forward, forelegs reaching out |
| 11 | **Front landing.** Left forepaw lands ahead of the shoulders, right right after. Hind legs off the ground, stretched back. Back flat |
| 16 | **Front push.** Forepaws planted behind the shoulders. Hind legs swinging forward under the belly. Back arching again |

More keys between these are fine (for example the suspension at about f18, all paws in the air).

## Which clips stand, which run on all fours
Only the **sprint** (`ww_run4`) and the **sprint jump attack** are on four legs. Everything
else, the bite and the arm swings included, stands hunched upright like the Mixamo clips.

## The bite (`ww_bite`, frames 1–25, one-shot, upright)
Starts and ends in the Mixamo idle's first frame (`ww_stand_ready`), so it blends out of
and back into the idle. It's already blocked in roughly; push it as far as you like:

| Frame | Pose | Jaw |
|---|---|---|
| 1 | **Ready.** The idle pose | +8 (nearly shut) |
| 6 | **Wind-up.** Leans back and down, head up, claws drawn in | +10 (shut) |
| 10 | **Lunge.** Leans forward over the hips, head reaching out and down, claws forward to grab | −24 (wide open) |
| 12 | **Snap.** The hit frame. Head drives into the target | +10 (shut) |
| 16 | **Tug.** Head yanks sideways, jaw clamped | +10 |
| 20 | **Release.** Head comes back up, claws back | −8 (slightly open) |
| 25 | **Ready** again (the same as frame 1) | +8 |

The feet stay planted unless you move `WW_Paw_Hind_*`. The hands are free (they don't
touch the ground here), so `WW_Paw_Front_*` are just where the claws go.

- **The jaw is yours here.** Pose Mode, select the bone `mixamorig:Jaw`, rotate around
  **X** (R, X, then type the angle): **+ closes** (about +10 shuts it), **− opens** (about −24
  is as wide as it looks good). Key it with I, then Rotation. The tail is still added for you.
- **Lunge with the body.** Move `WW_Body` forward and lean it (R, X). The game currently strips hips movement from every clip; that gets sorted out when
  the clips go into Godot, so pose it the way it should look.
- **Frame 25 has to match frame 1** so it lands back in the stance. The bake doesn't copy
  it for one-shots, so leave 25 as it is or copy 1 onto it.

## Fixed for you
- IK pole angles that bend each limb the right way (left and right differ because Mixamo
  mirrors bone roll): elbows 15° / 165°, knees 115° / 55° on the gallop. Each new clip
  measures its own against its start pose (the upright bite: elbows −12° / −185°, knees
  100° / 89°), so frame 1 matches the source within a few degrees.

## Other clips
The same rig works for the bite, the arm swings and the jump attack: Claude sets up a new
clip with `make_rig("<clip>", keys=(...))` and you pose it the same way.
