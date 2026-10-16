extends StaticBody3D
## A training dummy that enemies take for a player: on the player's physics layer, in the
## "player" group, and it takes damage - which it only counts. For tests on the light stage,
## where there is no real Player to stand in front of anything.

var damage_taken: float = 0.0
var is_downed: bool = false
## What it "wears", item id -> value, answered the way Player.equipment_value answers.
var equipment: Dictionary = {}


func equipment_value(item_id: String) -> float:
	return float(equipment.get(item_id, 0.0))


func _init() -> void:
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)


func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false) -> void:
	damage_taken += amount
