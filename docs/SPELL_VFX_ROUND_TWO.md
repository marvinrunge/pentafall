# Spell VFX - round two

How the 34 skills of round two (`colour_6` to `colour_12`, see `docs/SPELL_REFERENCE.md`) get
to the standard of the first 25, and how the whole set stops repeating itself. It continues
`docs/SPELL_VFX_PLAN.md`, whose rules all still hold: the four beats (charge, release, body,
settle), one bright core per effect, premultiplied blending (`scripts/spell_fx.gd`), no hard
edges, and readable on the pitch-black night.

## Where it stands (showcase, 2026-10-23)

`docs/screen_art/renders/round_two_vfx_before.jpg` is every new skill 0.45 s after its cast,
from `tools/tests/spell_showcase.tscn -- <out> --glow`. Next to the first 25 (Fireball's
billowing blast, Fire Cone's jet, Lightning Bolt's strike and cracks) the gap is plain.

The code says the same. Round two added 68 lines to `spell_visuals.gd`, and they are one
recipe: the colour's rune circle, plus a dust ring, a light pillar or a blink. Hits and towers
use the three generic network effects (`NetFx.ring`, `impact`, `beam`) - 57 calls across the
scripts.

| Group | Skills | What they show today |
|---|---|---|
| Nothing at all | Glorious Charge, Overrun, Animate Dead, Gravewalk, Awaken, Call of the Herd | an empty frame (the last four partly because the showcase stage has no corpse, tree or trophy) |
| Next-attack charges | Smite, Sunlance, Mark of Sanctity, Crippling Chill, Ice Cage, Time Ebb, Bone Splinters, Powder Keg, Become Immense, Entangling Vines (and Deathtouch) | all identical: Exalted Strike's weapon glow and a faint ground blush, whatever the colour |
| Their hits | the same ten | Sunlance, Bone Splinters = the generic beam; Vines, Time Ebb = the generic ring; Chill = the generic impact |
| Self buffs | Unholy Strength / Demonic Pact; Blood Frenzy / Grapeshot / Fork | two pairs of identical casts (violet circle + pillar; red circle) and no state on the caster afterwards |
| Enemy states | Ice Cage, Powder Keg, Banishing Light, Curse of the Swine | an untextured see-through box, a brown cylinder, a glowing cylinder, a tinted placeholder beast |
| Towers | all five | one grey cylinder with a glowing sphere, recoloured; every shot the generic beam |
| Fair | Mirror Image, Fling, Kraul Harpooner, Worship | read, but Worship and Banishing Light are Wrath of God's circle and pillar again |

The first 25 repeat themselves too. The rune circle is called 34 times in `spell_visuals.gd`
and the light pillar 14 times: Exalted Strike, Rally, Wrath of God, Worship and Banishing Light
are all "gold pentagram plus pillar of light". The circle has become wallpaper, so it no longer
says anything.

## Rule: one signature per skill

Every skill owns **one element no other skill uses** - its signature - and that element
carries the release beat. Shared pieces are allowed only as supporting layers, and the shared
pieces get budgets:

| Shared piece | Kept for | Taken away from |
|---|---|---|
| Rune circle (`magic_circle`) | rooted casts that hold a place: zones, summons, towers going up | instant casts, self buffs, every next-attack charge, moving casts |
| Light pillar | Wrath of God (from the sky) and Exalted Strike (on the weapon) | Rally, Worship, Banishing Light, Unholy Strength, Demonic Pact, black_8 |
| `NetFx.ring` / `impact` / `beam` | small confirmations: a hit spark, an end-of-state pop | any skill's main moment |

Fewer duplicates in the code comes from the same move: a handful of new builders, each with a
table of looks, instead of the same three calls with a different colour. Ten charges are one
builder with ten entries, not ten copies.

## New building blocks

Each serves several skills and gives each its own look. All premultiplied, soft-edged, with a
bright core above the bloom threshold.

1. **Weapon motif** (`StatusFx`, replaces the shared Exalted glow for charges). The armed weapon
   wears the charge's own sign, read from a table, and shows how many uses are left:

   | Charge | On the weapon |
   |---|---|
   | Smite the Monstrous | heavy gold blade-light, slow pulse |
   | Sunlance | sun rays streaming forward off the edge |
   | Mark of Sanctity | a small white sigil turning at the hilt |
   | Crippling Chill | frost creeping up the blade, three pips that crack off one by one |
   | Ice Cage | ice crystals grown along the edge |
   | Time Ebb | blue sand trickling off the weapon *backwards*, up into it |
   | Bone Splinters | bone shards orbiting the weapon |
   | Powder Keg | a lit fuse spitting sparks |
   | Become Immense | green vines thickening, the weapon a size larger |
   | Entangling Vines | thin vines coiled round the haft |
   | Deathtouch | violet smoke dripping from the edge |

2. **On-hit payloads** (`ChargedHits`, replacing its beams and rings):
   Sunlance a gold `ground_slash` lance raking 12 m with a sun flare at its end; Bone Splinters
   real bone-shard projectiles (streak meshes) bursting from each corpse; Entangling Vines roots
   erupting from the ground round each target (a `root_burst` builder, also used by Overrun's
   wake and Hornet Nest); Crippling Chill a frost overlay on the enemy that thickens per hit and
   shatters on the freeze; Smite a crack of light that shatters the boss's telegraph.

3. **Enemy states** (`EnemyBase._build_r2_look`):
   Ice Cage on the `frost_globe` shader as a faceted block with refraction and frost at its
   foot; Time Ebb the enemy dissolving into blue sand that streams back to its spawn and
   re-forms there; Banishing Light a gold prism that closes over the enemy, which fades to a
   white silhouette inside it; Powder Keg a real keg prop with a burning fuse and a flash that
   quickens before it blows; Mark of Sanctity a sigil over the head; Curse of the Swine a puff
   of blue smoke and the new boar model (`assets/generated/boar/`).

4. **A shared "materialise" shader** for everything that appears or rises - Mirror Image,
   Animate Dead, Awaken, Call of the Herd, Bontu's ghoul - one dissolve with per-skill colour
   and edge: Animate Dead black ribbons out of the corpse; Awaken the stone splitting and moss
   falling (golem) or bark tearing (treant); Call of the Herd the trophy shattering into green
   motes that pull together into the beast; Mirror Image a shimmer that splits into copies.

5. **Movement trails** for skills that move the caster or a target: Glorious Charge a golden
   lance of light ahead and shield-wings behind; Overrun a stampede of dust with spectral
   antlers and roots in the wake; Kraul Harpooner a real chain and hook instead of a beam;
   Gravewalk the caster sinking into black smoke and bursting out of the corpse in bone and
   ash; Fling a smoke trail on the thrown enemy.

6. **Self-buff states** on the caster (`StatusFx` overlays, for as long as the buff lasts):
   Unholy Strength dark veins over the skin that flare at each attack's life cost; Blood Frenzy
   a red aura that grows as health falls; Demonic Pact a contract sigil with a flame per kill
   still owed; Worship a ring of kneeling light figures round the zone instead of the pillar;
   Undying a flash of wings as the caster rises.

7. **Towers.** Five real models, one per colour (Ivory Tower, Glacial Fortress, Bontu's
   Monument, Goblin Sharpshooter's perch, Hornet Nest), made like the boar and the golem:
   Gemini reference, the user's approval, then `tools/mesh_creatures.py`-style image-to-3D at
   about 15 credits each (75 for all five, each one only on the user's go). Their shots get
   their own look: Ivory a pulse of light, Glacial ice shards, Sharpshooter real arrows
   (`player_arrow`), Hornet a swarm, Bontu a pit the ghoul climbs from.

## The first 25, while at it

Only where round two collides with them: Rally and Worship give up the pillar (Rally a rising
banner of light, Worship the kneeling figures above), Banishing Light gets the prism, and the
rune circle leaves the instant casts that have it today. Wrath of God keeps the pillar from the
sky as white's hero moment.

## Order

Status (2026-10-23): steps 1 and 2 are built. `scripts/charge_fx.gd` holds every charge's look
(one table: tint, weapon pattern, weapon particles; the arming moment; the hit). The player
publishes WHICH charge is armed (`ChargeFx.bit_of`), `StatusFx` draws it on the weapon through
`status_overlay.gdshader`'s `charge` layer, and every charged hit goes out as
`charge_hit/<id>` instead of a generic ring, beam or impact. Doom Blade's ground scar is now
`SpellVisuals.ground_scar`. Exalted Strike, Rubblebelt and the two windowed self-buffs still
glow with Exalted's gold until step 5.

Step 3 is built too: `scripts/enemy_state_fx.gd` draws the held states from EnemyBase's
`round_two_state` bits (ice crystals on the Frost Globe's shader, Banishing Light's prism on
`banish_prism.gdshader`, a lathed keg with a quickening fuse, a halo of glints) and the moments
in and out as `enemy_state/<moment>` (Curse of the Swine's puff of smoke). Banishing Light lost
Wrath of God's pillar. The boar is left out for now (the user, 2026-10-23): the swine is still
the green beast stand-in; the Meshy boar in `assets/generated/boar/` waits unrigged. Awaken's
golem is its own model (`scenes/bosses/stone_golem.tscn`).

Step 4 is built: `scripts/summon_fx.gd` plays every summon's arrival on every peer (a band of
light climbing the body, `summon_overlay.gdshader`, while it rises or swells; its own ground per
kind; the golem roars), and `scripts/move_fx.gd` draws Glorious Charge's lance, wings and wake,
Overrun's dust and roots, the harpoon's chain and Gravewalk's sinking and bursting. Gone as
duplicates: Displace's blink on Mirror Image and Gravewalk, Zombify's raise_dead on Animate
Dead, the leaf spiral Awaken and Call of the Herd shared. Fling keeps its look for now.

Step 5 is built: Unholy Strength, Blood Frenzy (as hot as the health lost) and Demonic Pact's
debt are drawn on the body (status_overlay.gdshader's unholy, frenzy, pact; StatusFx), and
`scripts/buff_fx.gd` gives Unholy Strength, the Pact, Undying, Blood Frenzy, Grapeshot (hot
pellets, not the Orb of Fire's ball), Fork and Worship (a curtain of light at the zone's edge)
casts of their own. In the first 25 the light pillar is down to Wrath of God and Exalted
Strike (Rally and its revive rise in streaks of light, Giant Growth lost its pillar), and the
instant self-buffs lost their circles (Exalted Strike, Reprisal Ward, Giant Growth, Ironbark).
Circles under projectile and zone casts stay.

1. **Showcase first.** Teach `spell_showcase` to set the stage each new skill needs (corpses,
   a tree and a ring stone, a trophy) and to make the attack a charge rides on, so a sheet
   shows the arming, the hit and the state - today half the new rows are empty or show only
   the arming.
2. **Charges** (blocks 1 and 2): ten skills, one builder each side. The biggest win, because
   they are the most numerous and the most alike.
3. **Enemy states** (block 3), with the boar.
4. **Summons and movement** (blocks 4 and 5), with the golem once it is rigged.
5. **Self buffs** (block 6) and the de-duplication of the first 25.
6. **Towers** (block 7): reference images first, then the user's go per model.

Each step ends with the colour's sheet at noon and at night (`--glow`, and
`tools/tests/vfx_showcase.tscn` for the times of day), shown to the user before the next.

## Not in this plan

Distortion and the shield ripple per hit stay where `SPELL_VFX_PLAN.md` Phase 6 has them.
Sounds, icons and the golem's rigging are their own work.
