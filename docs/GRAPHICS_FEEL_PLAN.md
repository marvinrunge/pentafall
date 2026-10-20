# Graphics and game feel plan

How to make Pentafall look richer and feel weightier, in the order worth doing it. Written
2026-10-20 against v0.11.0. Nothing here is built yet.

Two constraints hold for every item:

- **Performance.** The target is 300 enemies on the user's RTX 2070 Super (Vulkan). Every
  rendering item is tied to the graphics preset (Low / Medium / High / Ultra) and measured
  with the FPS overlay's GPU ms before and after. Anything that costs more than ~1 ms at
  High goes to Ultra only.
- **The art direction already decided.** Semi-realistic, nights near pitch-black on purpose
  (light comes from torches, crystals and mushrooms, not from exposure), spell VFX
  premultiplied with soft edges, and Sky3D owning the sky and its fog.

## Where it stands

| Area | Today |
|---|---|
| Tonemap | AgX, exposure 0.82, white 6.0 |
| Glow | on from Medium, tuned in GameSettings |
| AO / indirect light | none (no SSAO, SSIL, SDFGI) |
| Fog | Sky3D's own fog quad only; no volumetric fog |
| Colour grading | none |
| Camera attributes | an empty CameraAttributesPractical: no DOF, no auto exposure |
| Anti-aliasing | MSAA 2x/4x, or FSR2 as upscaler |
| Camera | fixed shoulder cam (3.2 m, 0.85 m right, 1.8 m up), spring arm, shake system, the archer's aim zoom |
| Hit feedback | shake, damage numbers, sounds, knockback, death launch with a 0.07 s freeze on the body |
| Missing | enemy hit flash, weapon swing trails, hit-stop on the attacker, scroll zoom, gamepad rumble |

## Phase 1 - quick wins (about 2 days)

The biggest change per hour of work. All cheap on the GPU.

1. **Colour grading.** Environment adjustments (contrast 1.08, saturation 1.1) plus a
   colour-correction LUT, blended by Sky3D's time of day: warm golden afternoon, a little
   desaturated cool blue at night. Gives the whole picture one mood. Cost ~0.
2. **SSAO.** Grounds characters, rocks, trees and grass in the terrain - today everything
   looks slightly pasted on. Half resolution at High, full at Ultra, off at Low. ~0.5-1 ms.
3. **Hit-stop.** On a connecting hit the attacker's animation and the target freeze for
   40 ms (light) / 70 ms (heavy, crit, Titanic slam). The single biggest "weight" change in
   melee games. Local only: the time scale of the two animators, never `Engine.time_scale`
   (that would stall multiplayer and the other players).
4. **Enemy hit flash.** The struck enemy flashes white-hot for 0.08 s (a shared overlay
   material, the same mechanism as the miniboss glow). Tells the player instantly that the
   hit landed.
5. **Camera feel.**
   - Mouse wheel / D-pad zoom: camera distance 2.2-5.5 m, saved in the settings.
   - Sprint FOV +6 degrees, eased in and out.
   - A short FOV punch on dashes and leaps (Fire Dash, Titanic Leap, Hurl Axe throw).
   - A small dip of the camera on landing from a jump, scaled by the fall.
6. **Menu blur.** When the skill tree, Upkeep or the options are open, the game behind them
   is blurred (DOF near/far on the camera). Makes the menus feel like part of the game and
   lifts them off the background.

## Phase 2 - the look (about 3-4 days)

1. **Distance depth of field.** A soft far blur beyond ~45 m during play: the far side of the
   map and the horizon go soft, the fight stays sharp. Subtle - a tilt-shift look is the
   failure to avoid. Ultra and High only.
2. **Volumetric fog for the lights.** Low-density Godot volumetric fog so torches, crystals
   and the mana wells cast visible light shafts at night, and the sun cuts god rays through
   the trees at dawn and dusk. Needs testing against Sky3D's fog quad (render priority, the
   same question the spell VFX already solved). Ultra only, maybe High. ~1.5-3 ms.
3. **Softer shadows.** The sun's shadow with a light angular size (soft PCSS edges), the
   cascade splits tuned to the camera distance. Characters' shadows currently have hard
   edges at every distance.
4. **Anti-aliasing for foliage.** MSAA does nothing for alpha-tested grass and leaves; that
   is the shimmer in the meadows. Offer TAA (High) and FSR2 at native resolution (Ultra)
   as the AA, MSAA stays as an option.
5. **Weapon swing trails.** The Whirlwind smear generalised: a soft trail behind the blade
   tip for every melee swing (the builder already measures the blade tip for the barbarian
   and the knight). Coloured by the hit's colour on spells, steel-pale otherwise.
6. **Dust and debris.** Dust puffs from footsteps on dirt (the footstep system already knows
   the ground texture), a dust ring on jump landings, a skid puff on dodge rolls.

## Phase 3 - polish and moments (about 3-5 days)

1. **Kill moments.** Boss kill and the last enemy of a wave: 0.3 s slow motion (only in
   single-player; in multiplayer a camera punch and a sound instead), a radial blur pulse.
2. **Boss entrance camera.** A 2-3 s camera move to the boss as it arrives (the boss intro
   banners already exist), with DOF on the boss and the HUD faded out.
3. **Low-health state.** A pulsing red vignette and a low-pass filter on the music and sound
   below 25% health; a short desaturation while downed.
4. **Damage direction.** A red arc on the screen edge pointing at where a hit came from.
5. **Gamepad rumble.** On hits dealt and taken, scaled by weight; the gamepad layout is
   already in place.
6. **Ambience.** Fireflies near water and mushrooms at night, falling leaves under the
   autumn trees, dust motes in sunbeams - small particle systems that only exist near the
   camera.
7. **Grass bending.** Players and enemies push the grass aside where they walk (TerraBrush
   grass shader, a small trail texture around the camera).

## Not recommended

- **SDFGI.** Real-time GI over the whole TerraBrush terrain costs 3-6 ms and adds light
  leaking and noise; SSAO + good grading gets most of the look for a tenth of the cost.
- **Screen-space reflections.** Almost nothing in the map is glossy; the water has its own
  shader.
- **Permanent chromatic aberration or film grain.** Read as cheap on a semi-realistic look;
  only as a short pulse on a heavy hit, if at all.
- **Auto exposure.** It would undo the dark nights the design wants.

## How each item is checked

- Before / after screenshots at noon, dusk and midnight in the same spot (the existing
  screenshot scripts).
- GPU ms on the FPS overlay with 300 enemies (the crowd test) at each preset.
- Feel items (hit-stop, flash, zoom, FOV) with a short test each in `tools/tests/`, the way
  the class kits are covered.
