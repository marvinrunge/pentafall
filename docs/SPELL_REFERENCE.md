# Spell Reference

This document describes the currently implemented player abilities. Runtime values in
`scripts/game_settings.gd`, `scripts/player.gd`, and `scripts/projectile.gd` take
precedence over older skill-tree tooltip text.

## General Rules

| Rule | Value |
|---|---:|
| Active spells per color | 11-12 (ids `colour_1`-`colour_12`; red to 11), one of them passive (Undying) |
| Infinite affinity nodes per color | 1 |
| Affinity rank cost | 1 matching mana |
| Active spell rank cost | 1 skill point per rank |
| Active spell level gates | Team levels 1, 3, 5, 7, 9 |
| Maximum charge time | 3 seconds (`GameSettings.spell_charge_max_time`) |
| Minimum released charge | 20% |
| Multicolor access | Any color can be ranked and unlocked |
| Active hotbar branch | Selected by clicking an unlocked spell or binding it from the skill tree |

## Color Affinities

Affinity ranks are unlimited and use diminishing returns towards a ceiling per colour
(`GameSettings.affinity_first_rank` / `affinity_cap`): the first rank gives the first value,
and every rank after closes the same share of the remaining gap to the ceiling.

| Color | Card | Mana | Mechanic | Identity |
|---|---|---|---|---|
| White | Holy Strength | `{W}` | +% of max HP regenerated per second | Protection, restoration, and enduring light. |
| Blue | Curiosity | `{U}` | +% cooldown recovery | Mind-speed, mental acuity, and tactical flow. |
| Black | Vampiric Link | `{B}` | +% lifesteal from basic attacks (swings and kick) | Dark bargains, parasitic drain, and vital siphon. |
| Red | Reckless Charge | `{R}` | +% total player damage | Explosive aggression, raw power, and volatility. |
| Green | Wild Growth | `{G}` | +% maximum HP | Primal vitality, physical mass, and resilience. |

| Colour | Rank 1 | Rank 5 | Rank 10 | Ceiling |
|---|---:|---:|---:|---:|
| White (max HP / s) | 0.6% | 2.0% | 2.7% | 3% |
| Blue (cooldown recovery) | 8% | 27% | 36% | 40% |
| Black (lifesteal, basic attacks) | 5% | 18% | 25% | 30% |
| Red (damage) | 10% | 34% | 45% | 50% |
| Green (max HP) | 10% | 34% | 45% | 50% |

## Basic Attack

| Ability | Cooldown | Range | Damage | Knockback | Details |
|---|---:|---:|---:|---:|---|
| Basic Attack | 0.5s | 3.5m | 20 | 6 | Hits the aimed enemy or one enemy in the forward cone. Holding the attack button repeats it for 40 base DPS. |

## Red - Aggression

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Fireball | 1 | 5s | Yes | Charged | Blast radius | Charged explosive projectile with a scaling blast radius. |
| 2 | Fire Dash | 1 | 8s | No | Trail damage | Dash | Dashes forward and leaves a burning trail. |
| 3 | Rain of Ember | 1 | 9s | No | 40 DPS for 5s | Ground zone | Creates a burning zone that damages enemies inside it. |
| 4 | Fire Cone | 1 | Refill | No | 55 DPS / slow | Frontal cone | Hold to burn and slow enemies while moving. The meter lasts up to 5s and then refills. |
| 5 | Lightning Bolt | 1 | 12s | No | Single-target damage | Aimed area | Calls lightning down on a precisely aimed target area. Bosses and elites take roughly double. |

## Blue - Control

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Unsummon | 1 | 9s | No | Wall impact only | Cone | Applies 21 knockback plus 7.5 of upward lift, so enemies are thrown off the ground and land stunned. No damage of its own: an enemy thrown into a wall or obstacle takes 80 impact damage (120 more against Wall of Frost). |
| 2 | Frost Breath | 1 | 12s | No | Damage / slow | Area | Freezes nearby enemies and damages them; bosses are briefly slowed instead. |
| 3 | Suction | 1 | 11s | No | Pull | Area | Pulls nearby enemies into one location for 6s (10s at rank 5) - always shorter than the cooldown. Overlapping vortexes cover more ground but never pull one enemy harder. |
| 4 | Wall of Frost | 1 | 16s | No | Projectile block / combo | Placed wall | Raises an ice wall. Unsummon deals bonus damage when it slams enemies into it. |
| 5 | Displace | 1 | 10s | No | Mobility | Blink | Blink a short distance to the aimed ground point; 0.6s of invulnerability on arrival. |

## Green - Strength

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Titanic Brawl | 1 | 8s | No | Landing damage | Leap, reach | Leaps to the crosshair (10 m reach, 18 m at rank 5) and slams the ground on landing. |
| 2 | Giant Growth | 1 | 22s | No | Maximum HP | Self | Grows the player temporarily and increases maximum health. |
| 3 | Fog | 1 | 18s | No | Ranged suppression / slow | Zone around caster | Raises fog around the caster. Projectiles and spells aimed at anything inside it are lost, archers and mages standing in it cannot fire, and every enemy wades rather than walks. Melee still hits. |
| 4 | Roar | 1 | 16s | No | Taunt | Area | Forces nearby enemies to target the player. |
| 5 | Ironbark | 1 | 20s | No | Damage reduction | Self | Reduces damage and prevents knockback, stun, and freeze. |

## White - Protection

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Exalted Strike | 1 | 8s | No | Melee buff | Self | The next 2 melee hits (3 at rank 5) deal x4 and reach further; kills are exiled. |
| 2 | Circle of Protection | 1 | 18s | No | Temporary shield | Ally area | Shields every nearby ally for 8s, a little more per ally present. Recasting refreshes rather than stacks. |
| 3 | Reprisal Ward | 1 | 16s | No | Reflect / block | Self | Reflects damage and grants a chance to block attacks. |
| 4 | Wrath of God | 1 | 20s | No | Area damage | Area | Deals heavy damage to nearby enemies. |
| 5 | Rally the Fallen | 1 | 45s | No | Revive / heal | Ally area | Revives downed teammates and heals surviving allies and myrs. |

## Black - Death as a Resource

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Doom Blade | 1 | 7s | No | Line damage | 20m line, 36m at rank 5 | Sends a black blade along the camera aim line through enemies. Rank buys reach, not width. |
| 2 | Contagion | 1 | 12s | No | Damage over time, spreading | Aimed target, 4.5m jumps | Plagues the enemy in the sights; every second it jumps to the nearest uninfected enemy, up to 8 victims (12 at rank 5). Replaced Fear. |
| 3 | Deathtouch | 1 | 40s (24s at rank 5) | No | Execute | Next attack | The next attack within 8s kills every non-boss it hits, up to 3 (7 at rank 5); bosses and minibosses only below 25% health (35% at rank 5). Was Kill. |
| 4 | Wall of Souls | 1 | 20s | No | Damage amplifier | Wall | Enemies crossing the wall take increased damage. |
| 5 | Zombify | 1 | 30s | No | Melee damage | Corpse area | Raises corpses as ghouls that sprint at the nearest enemy and fight it (22 damage per swing every 1.2s at rank 1). With Mayhem Devil they also burst when killed or on expiry (90 damage in 3.5m). |

## Charge Formulas

Currently, only Fireball is chargeable. Its charge multiplier ranges from `0.2` to
`1.0` when the cast is released - a full-power Fireball therefore takes the whole
3-second window, and the charge fires by itself once it closes.

The caster is not idle while it builds: the cast clip's lead-in is stretched across the
charge window, so the wind-up is visibly held for as long as the button is down, and the
release continues that same animation into the cast (`Player._begin_spell_windup`).

| Spell | Formula |
|---|---|
| Fireball damage | `base damage x (0.6 + 1.2 x charge) x rank multiplier` |
| Fireball radius | `base radius x (0.8 + 0.7 x charge) x rank area multiplier` |

## Round two (2026-10-22)

Every colour's skills 6-12 - see `docs/SKILL_DESIGN.md`, *Idea backlog - round two*, for what each
is for; the numbers are `GameSettings`' *ROUND TWO* block. "Next light / heavy / attack" charges the
caster's next attack of that weight - every class has both (a tap and a hold).

| Id | Spell | Trigger | Cooldown | Effect |
|---|---|---|---:|---|
| white_6 | Glorious Charge | Cast (moves) | 12s | Charge 9m; enemies on the path carried, damaged and stunned 1.2s; allies on it shielded. |
| white_7 | Smite the Monstrous | Next heavy | 14s | x2.5 damage; on a boss mid-special, breaks the special. |
| white_8 | Sunlance | Next light | 10s | A 12m line of light from the hit: 60 damage, blind 2s. |
| white_9 | Mark of Sanctity | Next light | 12s | Marks the target 8s; every ally who hits it gets a 10 shield (cap 40). |
| white_10 | Worship | Cast | 30s | 6m zone, 6s: players and myrs inside cannot drop below 1 HP. |
| white_11 | Banishing Light | Cast, aimed | 24s | Every non-boss in 3.5m sealed away for 4s. |
| white_12 | Ivory Tower | Tower | 14s | Shields players (heals myrs) within 10m every 3s. |
| blue_6 | Mirror Image | Cast | 26s | 1 -> 3 copies fighting with the caster's class attack at half damage, 10s. |
| blue_7 | Crippling Chill | Next 3 light | 10s | Two hits chill, the third freezes 2s (bosses slowed). |
| blue_8 | Ice Cage | Next light | 14s | Target encased in an ice block 4s. |
| blue_9 | Time Ebb | Next heavy | 18s | Everything hit is sent back to where it spawned; bosses, minibosses and beasts slowed 3s. |
| blue_10 | Counterspell | Cast | 30s | A boss, miniboss or beast special winding up within 25m fizzles. |
| blue_11 | Curse of the Swine | Cast, aimed | 24s | Up to 3 -> 8 non-bosses in 4m become harmless boars for 5s. |
| blue_12 | Glacial Fortress | Tower | 14s | Ice shots: 18 damage and slow, every 4th freezes 1.5s. |
| black_6 | Unholy Strength | Self, 8s | 20s | Every attack costs 2% max HP and adds 3x that as damage. |
| black_7 | Bone Splinters | Next heavy | 12s | Corpses within 5m of the impact fly at the nearest enemies, 45 each. |
| black_8 | Undying | Passive | - | Once a wave: instead of going down, back up at 30% -> 60% HP, 3s invulnerable, enemies thrown back. |
| black_9 | Animate Dead | Cast, aimed | 40s | The nearest elite/miniboss/boss corpse rises as an ally until the wave ends. |
| black_10 | Gravewalk | Instant | 12s | Teleport into the corpse nearest the aim (25m); it bursts for 70 in 4m. |
| black_11 | Demonic Pact | Cast | 60s | Every other black spell off cooldown; 10 kills owed in 15s -> 20s, else lose 50% -> 35% max HP (can kill). |
| black_12 | Bontu's Monument | Tower | 16s | 5 deaths within 12m raise a ghoul. |
| red_6 | Fling | Cast, targeted | 12s | Throw the enemy in the sights (not a boss) up to 22m; it bursts for 90 in 4m. |
| red_7 | Blood Frenzy | Self, 8s | 24s | Damage x1 at full health up to x1.8 -> x2.4 at none. |
| red_8 | Powder Keg | Next light | 9s | Bomb on the target: 90 in 3.5m after 3s, at once if it dies. |
| red_9 | Grapeshot | Cast | 6s | One bolt (28) per spell cast in the last 5s, at the nearest enemies, up to 8. |
| red_10 | Fork | Cast | 20s | The next aimed spell is cast again at the nearest other enemy. |
| red_11 | Goblin Sharpshooter | Tower | 14s | 32 damage every 0.35s within 26m; 60 health. |
| green_6 | Become Immense | Next attack | 12s | x1.8 damage, +1.5m reach, wider arc, double-size projectile bursting over 2.5m. |
| green_7 | Entangling Vines | Next light | 12s | Roots everything within 4m of the hit for 3s. |
| green_8 | Kraul Harpooner | Cast, aimed | 10s | Drag the enemy in the sights to you, or yourself to a tree or standing stone. |
| green_9 | Awaken | Cast, aimed | 40s | A tree becomes a treant, a ring stone a golem, fighting for 20s. |
| green_10 | Overrun | Cast (moves) | 18s | 12m unstoppable charge; enemies in the way thrown aside. |
| green_11 | Call of the Herd | Cast | 30s | Spends a trophy from a slain beast: that beast, at its size, fights until it falls or the wave ends. |
| green_12 | Hornet Nest | Tower | 16s | 900 health, draws enemies; whoever hits it is stung. |

Towers: 1 / 2 / 2 / 3 / 3 of a kind standing at ranks 1-5; one more replaces the oldest.
