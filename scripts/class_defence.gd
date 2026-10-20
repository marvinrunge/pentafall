class_name ClassDefence
extends RefCounted
## What Player asks of a class's defence - the block button. The warrior's BlockGuard raises a
## guard; the archer's DodgeRoll rolls out of the way, the mage's Blink is simply elsewhere
## (docs/CHARACTER_CLASSES_PLAN.md - each class has one defence; the barbarian has none).

var player: Player


## Reads the button and decides this frame's defence. Local player only.
func update() -> void:
	pass


## Whether this hit is stopped by the defence. A roll never stops a hit - it makes the
## player untouchable instead, through Player._invulnerable_timer.
func blocks_attack_from(_source: Node3D) -> bool:
	return false


## The share of a stopped hit the defence takes away.
func damage_reduction() -> float:
	return 0.0


## A hit was just stopped (blocks_attack_from said so), by `source`. Where the damage lands -
## the server - so anything it does to the attacker is real there.
func on_blocked(_source: Node3D) -> void:
	pass
