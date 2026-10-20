# Skill icon prompts (Gemini image generation)

Prompts for the skill tree nodes that still have no icon of their own. Every filename below is
already wired in `SpellDatabase.ICON_FILES`: until its file exists, `get_icon_path` falls back to
what the node shows now (a borrowed icon, or the colour's mana symbol), so adding the file is the
whole change.

## All nine in one image (recommended)

1. Start a Gemini chat and attach 3-4 existing icons as style references, e.g.
   `assets/icons/unsummon.png`, `fire-cone.png`, `wall-of-souls.png`, `roar.png`.
2. Send the prompt below. It asks for a 3 x 3 sheet in a fixed order.
3. Save the sheet and cut it into the nine files:
   `python tools/slice_icon_sheet.py <sheet.png>` (writes into `assets/icons/`, skips files that
   already exist unless `--force`).
4. Open the project in the editor once so Godot imports the new files.

```
Create ONE square image (1:1, as large as possible) that is a sprite sheet of 9 ability
icons for a fantasy action game inspired by Magic: The Gathering, laid out as an exact
3 x 3 grid of equal square cells, separated by straight, plain, near-black gutters about
2% of the image wide. Each cell holds exactly one complete icon, centred, filling the cell.

Style - match the attached reference icons exactly, the same for all 9:
painterly digital illustration, polished like a high-end ARPG / mobile spell icon; one bold
central subject with a strong silhouette, readable at 48 px; dramatic lighting, magical
glow and rim light, rich saturated colours; soft dark vignette background tinted in the
icon's colour, slightly rounded square. No text, letters, numbers, labels, borders, frames,
UI elements or watermark anywhere in the image.
Colour language: white = warm gold and ivory light; blue = icy cyan and deep ocean blue;
black = violet, sickly purple and shadow; red = fire orange, crimson and ember; green =
vivid leaf green and earthy brown. Two-colour icons blend both palettes.

Cells, row by row, left to right:
1. Wall of Frost (blue): a thick, jagged wall of blue ice crystals erupting from the ground
   in a straight line, low three-quarter view, frost mist at its base, cyan glow inside.
2. Contagion (black): a sickly violet plague cloud leaping from one skull-like silhouette to
   the next in a chain of three, glowing purple-green spores, the infection spreading.
3. Kodama's Reach (green): a small white forest spirit (kodama, round head, simple face),
   arms outstretched, green roots and rings of light spreading out across mossy ground.
4. Azorius Justiciar (white + blue): a stern armoured law-mage raising a glowing sceptre,
   chains of white-gold light and blue arcane runes binding the air before him.
5. Dimir Guildmage (blue + black): a hooded mage with a hidden face, one hand of cold blue
   frost, the other of violet death magic, a ghostly figure rising from frozen ground.
6. Mayhem Devil (black + red): a grinning red-skinned horned imp gleefully holding a skull
   that bursts into fire and violet sparks.
7. Rubblebelt Rioters (red + green): a raging barbarian brute mid-swing with a stone club,
   shattered rocks and embers flying, wild green energy around his fists.
8. Trostani, Selesnya's Voice (green + white): a serene dryad whose body merges into a
   blossoming white tree, golden light flowing from her open hands.
9. Displace (blue): a mage dissolving into blue light particles on the left and reappearing
   solid on the right, a streak of arcane distortion between them.
```

If one cell comes out wrong, regenerate just that one with the matching single-icon line below
(after the style block) and save it under its filename by hand.

## The class skills, all sixteen in one image (done 2026-10-19)

The four classes' skills (`ClassDatabase.SKILLS`, passives included), one class a row in unlock
order. Made once and cut with `python tools/slice_icon_sheet.py <sheet.png> --set classes`;
kept here for redoing one. Class skills are colourless, so each row has a material palette of
its own instead of a mana colour. Attach `blade-dance.png`, `exalted-strike.png`,
`unsummon.png` and `roar.png` as style references.

```
Create ONE square image (1:1, as large as possible) that is a sprite sheet of 16 ability icons for a fantasy action game inspired by Magic: The Gathering, laid out as an exact 4 x 4 grid of equal square cells, separated by straight, plain, near-black gutters about 2% of the image wide. Each cell holds exactly one complete icon, centred, filling the cell.

Style - match the attached reference icons exactly, the same for all 16:
painterly digital illustration, polished like a high-end ARPG / mobile spell icon; one bold central subject with a strong silhouette, readable at 48 px; dramatic lighting, glow and rim light, rich colours; soft dark vignette background, slightly rounded square. No text, letters, numbers, labels, borders, frames, crosshairs, UI elements or watermark anywhere in the image.

These are CLASS skills, not mana colours, so each row has its own material palette:
Row 1 Knight = polished steel and warm brass. Row 2 Barbarian = dark iron, worn leather, blood red. Row 3 Archer = bronze, weathered wood and amber. Row 4 Mage = silver and pale arcane lavender light.

Cells, row by row, left to right:

Row 1 - Knight (sword and shield):
1. First Strike: a sword thrusting straight out from behind a raised shield in a lightning-fast riposte, a bright spark at the blade tip, a motion streak behind it.
2. Shield Bash: a heavy kite shield slammed forward toward the viewer, a shockwave ring and dust bursting off its face.
3. Shield Wall: a raised shield catching an enemy axe at the perfect instant, the axe rebounding in a flash of light, small stars of a stun around it.
4. Phalanx: a towering armoured shield bearer in front, smaller allied figures sheltered behind the shield inside a protective dome of light, glowing enemy eyes in the dark turning toward the shield.

Row 2 - Barbarian (two-handed greatsword):
5. Brute Force: a massive greatsword overhead slam hurling an enemy silhouette backwards through the air, cracked ground and flying debris.
6. Whirlwind: a barbarian spinning with a greatsword held out level, a circular blur of steel and a dust tornado around him.
7. Indomitable: a scarred barbarian planted mid-swing, arrows and blows glancing off a faint shimmer around him, completely unflinching.
8. Berserk: a roaring barbarian wreathed in a blood-red rage aura, glowing veins and burning eyes, greatsword raised high.

Row 3 - Archer (longbow):
9. Longshot: a single arrow piercing straight through three shields lined up one behind another, a streak of light along its path.
10. Disengage: an elven archer rolling backwards away from danger, a glowing snare of thorny cords left on the ground where she stood.
11. Arrow Volley Trap: dozens of arrows raining down from the sky onto a marked circle on the ground.
12. Deadeye: a narrowed eye reflected in a polished arrowhead, focused on the helmet of a distant enemy, a glint of light on the tip.

Row 4 - Mage (bare-handed spellcaster):
13. Prowess: an open hand crackling with arcane power, three small glowing orbs circling it as charges build into a bolt.
14. Blink of an Eye: a robed mage vanishing in a flash of lavender light, while a translucent glowing illusion of him stays behind and shadowy enemies turn toward the illusion.
15. Spell Mastery: an open spellbook with two identical glowing spell sigils floating above it, twin copies of the same rune.
16. Mana Surge: a mage with arms thrown wide drawing streams of five-coloured mana (gold, blue, violet, red, green) back into his chest in a burst of light.
```

## One icon at a time

Send the **style block** once, then one **icon line** per message, and save each result as a
square PNG under `assets/icons/` with the filename from the table. Size does not matter much
(the existing ones are about 210 px).

`tools/tests/skill_tree_full_shot.tscn` photographs the tree with every node bought, which is the
quickest way to see which nodes still wear a mana symbol.

## Style block

```
I need square ability icons for a fantasy action game inspired by Magic: The Gathering.
Match the style of the attached reference icons exactly:
- painterly digital illustration, polished like a high-end ARPG / mobile spell icon
- ONE bold central subject with a strong silhouette, readable at 48 px
- dramatic lighting, magical glow and rim light, rich saturated colours
- soft dark vignette background tinted in the icon's colour, slightly rounded square
- no text, no letters, no numbers, no border or frame, no UI elements, no watermark
- 1:1 square, 512x512
Colour language: white = warm gold and ivory light; blue = icy cyan and deep ocean blue;
black = violet, sickly purple and shadow; red = fire orange, crimson and ember;
green = vivid leaf green and earthy brown. Two-colour guild icons blend both palettes,
split or swirled together.
Reply with one icon per message. I will describe each one next.
```

## Icon lines

| File | Node | Prompt |
|---|---|---|
| `wall-of-frost.png` | Blue: Wall of Frost | `Icon: "Wall of Frost". A thick, jagged wall of blue ice crystals erupting from the ground in a straight line, seen at a low three-quarter angle, frost mist rolling at its base, cold cyan glow inside the ice. Blue palette.` |
| `contagion.png` | Black: Contagion | `Icon: "Contagion". A sickly violet plague cloud leaping from one skull-like silhouette to the next in a chain of three, glowing purple-green spores and drips, the infection visibly spreading. Black palette.` |
| `kodamas-reach.png` | Green aura: Kodama's Reach | `Icon: "Kodama's Reach". A small white forest spirit (kodama, round head, simple face) with arms outstretched, green roots and ripples of light spreading outward across mossy ground in widening rings. Green palette.` |
| `guild-azorius.png` | Guild White/Blue: Azorius Justiciar | `Icon: "Azorius Justiciar". A stern armoured law-mage holding up a glowing gavel-sceptre, chains of white-gold light and blue arcane runes binding the air in front of him. White and blue palette, gold and sapphire.` |
| `guild-dimir.png` | Guild Blue/Black: Dimir Guildmage | `Icon: "Dimir Guildmage". A hooded shadow mage whose face is hidden, one hand of cold blue frost, the other of violet death magic, a ghostly figure rising from frozen ground below. Blue and black palette.` |
| `guild-rakdos.png` | Guild Black/Red: Mayhem Devil | `Icon: "Mayhem Devil". A grinning red-skinned imp devil with horns, gleefully holding a bursting skull that explodes into fire and violet sparks. Black and red palette, crimson and purple.` |
| `guild-gruul.png` | Guild Red/Green: Rubblebelt Rioters | `Icon: "Rubblebelt Rioters". A huge raging barbarian brute mid-swing with a stone-and-bone club, shattered rocks and embers flying, wild green energy around his fists. Red and green palette.` |
| `guild-selesnya.png` | Guild Green/White: Trostani | `Icon: "Trostani, Selesnya's Voice". A serene dryad woman whose body merges into a blossoming white tree, golden light flowing from her open hands onto small figures below. Green and white palette, leaf green and soft gold.` |

## Optional: icons that borrow a picture

| File | Node | Now uses | Prompt |
|---|---|---|---|
| `displace.png` | Blue: Displace (blink) | `flying.png` (wings) | `Icon: "Displace". A mage figure dissolving into blue light particles on the left and reappearing solid on the right, a streak of arcane distortion between the two. Blue palette.` |
| `rhystic-study.png` | Blue aura: Rhystic Study | `sylvan-library.png` (blue rune book) | `Icon: "Rhystic Study". An open ancient tome floating, its pages radiating a protective blue shield bubble edged with frost crystals. Blue palette.` |

Both are wired too: the new file wins over the borrowed one as soon as it exists.

## Upkeep, the warrior's new skills and the class defences - sixteen in one image

Everything added on 2026-10-19 that still wears a stand-in: the Upkeep shop's eight tiles
(`UpkeepPanel`), the warrior's Bloodthirst, Hurl Axe and Battle Frenzy, and the five classes'
defences - the level-1 slot of the skill tree's class ring (`ClassDatabase.DEFENCES`). Cut with
`python tools/slice_icon_sheet.py <sheet.png> --set upkeep`. Attach `blade-dance.png`,
`first-strike.png`, `circle-of-protection.png` and `roar.png` as style references.

`upkeep-myr.png` was redone on its own on 2026-10-20: the sheet's first Myr was a generic copper
robot, not the game's. That one was made with a render of `scenes/myrs/silver_myr.tscn` attached
as the first image ("draw exactly this creature") and the style references as the second;
Gemini framed it, so it was cropped 72 px in from each edge of the 2048 px image before scaling.

```
Create ONE square image (1:1, as large as possible) that is a sprite sheet of 16 ability icons for a fantasy action game inspired by Magic: The Gathering, laid out as an exact 4 x 4 grid of equal square cells, separated by straight, plain, near-black gutters about 2% of the image wide. Each cell holds exactly one complete icon, centred, filling the cell.

Style - match the attached reference icons exactly, the same for all 16:
painterly digital illustration, polished like a high-end ARPG / mobile spell icon; one bold central subject with a strong silhouette, readable at 48 px; dramatic lighting, glow and rim light, rich colours; soft dark vignette background, slightly rounded square. No text, letters, numbers, labels, borders, frames, crosshairs, UI elements or watermark anywhere in the image.

Palettes: row 1 cells 1-3 are colourless - copper, silver and warm gold. The five enchantments use their mana colour: white = warm gold and ivory light; blue = icy cyan and deep ocean blue; black = violet, bone and sickly green-black; red = fire orange and crimson; green = emerald, moss and amber. The warrior row (cells 9-11) is rust red and dark iron. The defences (cells 12-16) each use their class's material: warrior = dark iron and fur; knight = polished steel and warm brass; barbarian = dark iron, worn leather, blood red; archer = bronze, weathered wood and amber; mage = silver and pale arcane lavender light.

Cells, row by row, left to right:

Row 1 - the Upkeep shop:
1. Build a Myr: the game's Myr - a slender humanoid artifact robot in blue-grey silver metal with a huge smooth elongated head swept back like a teardrop, a glowing cyan ring as its eye and cyan rings on its shoulders, cradling a glowing white mana crystal in its clawed hands.
2. Skill point for everyone: a radiant golden rune stone floating above an open hand, sparks of light rising off it like stars.
3. Repair the crystal: a large faceted crystal whose cracks are sealing over with lines of golden light, small shards drifting back into place.
4. Sphere of Safety (white enchantment): a shimmering dome of warm golden light over a crystal on a pedestal, enemy claws glancing off its surface.

Row 2 - the enchantments:
5. Propaganda (blue enchantment): a tall blue war banner with a glowing hypnotic eye sigil, shadowy enemies before it slowed and dazed, trailing blue ripples.
6. Animate Dead (black enchantment): a fallen warrior's hand bursting up out of a grave, violet necromantic light and swirling souls pulling the body back to its feet.
7. Furnace of Rath (red enchantment): a roaring iron furnace mouth blazing with doubled flames, sparks and embers bursting out.
8. Overgrowth (green enchantment): thick emerald vines and roots overgrowing a stone mana well, glowing green blossoms and seeds of mana.

Row 3 - the warrior:
9. Bloodthirst: an orc's hatchet dripping with glowing red, a stream of red life flowing back up the blade into the wielder's arm.
10. Hurl Axe: a hatchet spinning flat through the air in a wide curving arc like a boomerang, a motion trail showing it coming back.
11. Battle Frenzy: a roaring orc warrior mid-swing, several blurred afterimages of his axe in a fan, a fierce red rage aura.
12. Block (warrior's defence): a hatchet raised crosswise in front of a fur-clad arm, catching an enemy blade in a burst of sparks.

Row 4 - the defences:
13. Shield Guard (knight): a kite shield raised high, a huge blow shattering harmlessly against its face in a ring of light.
14. Unstoppable (barbarian): a barbarian in the middle of a massive greatsword swing, enemy blows breaking against the blazing arc of his swing without slowing it.
15. Dodge Roll (archer): an elven archer rolling sideways, an enemy strike cutting through the empty air where she stood, a dust trail behind her.
16. Blink (mage): a robed mage vanishing in lavender light and reappearing a few steps away, a fading afterimage left behind.
```
