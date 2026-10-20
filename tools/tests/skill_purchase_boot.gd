extends Node
## Boot node. change_scene_to_file() frees whatever is the current scene, and that is
## THIS node - so the checks live on a separate node parented to the tree root, which
## survives the scene swap.


func _ready() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var reporter: Node = load("res://tools/tests/skill_purchase.gd").new()
	reporter.name = "Reporter"
	# The solo seat plays the menu's class, and Blade Dance and the warrior's wind-ups are
	# checked below - so the warrior is put there for the run and the player's own pick put
	# back before the test quits (see archer_kit.gd).
	reporter.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "warrior"
	get_tree().root.add_child(reporter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")
