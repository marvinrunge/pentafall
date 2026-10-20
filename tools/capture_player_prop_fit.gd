extends SceneTree
## Captures the player props you have moved by hand in the editor, so the move survives the
## next rebuild - the player's side of tools/capture_weapon_fit.gd.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/capture_player_prop_fit.gd
##
## The workflow:
##
##   1. open the class's visual scene (scenes/characters/<class>/visual.tscn), select the prop
##      under its BoneAttachment3D - Hatchet, Sword, Shield, Greatsword, Bow, Quiver - and
##      move, turn or scale it; save
##   2. it is in the game at once; every rebuild keeps it
##
## A rebuild captures on its own before it overwrites the scene
## (PlayerCharacterBuilder.capture_prop_fits), so running this is only needed to get the move
## into PlayerCharacterBuilder.PROP_FIT_PATH without one - to commit it, say. Props nobody has
## moved since the last build are left as the file has them.

const Builder = preload("res://tools/player_character_builder.gd")


func _init() -> void:
	for class_id: String in Builder.CONFIGS:
		Builder.capture_prop_fits(class_id)
	print("Done; adjustments are in %s." % Builder.PROP_FIT_PATH)
	quit()
