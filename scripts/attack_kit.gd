class_name AttackKit
extends RefCounted
## What Player asks of a class's basic attack (docs/CHARACTER_CLASSES_PLAN.md, "Attacks as
## kits"): the warrior's MeleeKit, the barbarian's GreatswordKit, the archer's BowKit, the
## mage's MageKit. Every
## hook is a no-op here, so a kit only writes the ones it has something to say about.
##
## Player keeps what an attack shares with a cast - the committed-action clock
## (_begin_action, _commit_action, _action_timer), the messages that play it on the other
## screens and what a hit does once it lands. A kit decides when a press becomes an attack,
## which one, and what it reaches.

var player: Player


## The kit's own clocks. Every frame on the machine that drives this player.
func tick(_delta: float) -> void:
	pass


## Pays out whatever the action in flight has reached by now (Player._action_elapsed).
func land_due_hits() -> void:
	pass


## The local player's buttons, once per frame when nothing is stopping them.
func read_input() -> void:
	pass


## Forgets a press in progress - the button, not an attack already under way.
func drop_swing() -> void:
	pass


## The attack in flight was cut off: whatever it had not landed yet never will.
func drop_hits() -> void:
	pass


## Starts any chain the kit keeps over from the top.
func reset_chain() -> void:
	pass


## Everything at once, for a cast or a stagger that cuts the attack off outright.
func cancel() -> void:
	drop_swing()
	drop_hits()
	reset_chain()


func on_guard_raised() -> void:
	pass


## How fast the attack in flight carries a rooted player forward this frame, m/s.
func lunge_speed(_delta: float) -> float:
	return 0.0


## How far the camera should be zoomed in for the attack in flight, 0 (not at all) to 1
## (all the way, GameSettings.archer_aim_zoom_fov_mult). Player eases towards it.
func aim_zoom() -> float:
	return 0.0


## The share of the player's speed left to them while this kit is busy. Below 1 also stops
## a sprint.
func move_speed_mult() -> float:
	return 1.0


## Whether a hit taken now leaves the attack in flight alone instead of staggering the
## player out of it (Player._try_hit_reaction). The barbarian's heavy swing.
func unstoppable() -> bool:
	return false


## The player's guard just stopped a hit (Player._notify_blocked) - the knight's First Strike.
func on_blocked() -> void:
	pass


## A colour spell of the player's just went off, on their own machine (Player._note_spell_cast)
## - the mage's Prowess.
func on_spell_cast(_spell_id: String) -> void:
	pass


## The player's basic attack just killed something, with Bloodthirst (Player._bloodthirst) - the
## warrior's quicker next stage.
func on_bloodthirst() -> void:
	pass


## Whether, right now, nothing may slow, stagger or interrupt the player at all - what
## Player.is_control_immune() adds to Ironbark. The barbarian's Indomitable, mid-swing.
func control_immune() -> bool:
	return false
