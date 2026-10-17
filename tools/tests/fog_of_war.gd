extends "res://tools/tests/vfx_stage.gd"
## Regression test: the minimap's fog of war (scripts/fog_of_war.gd).
##
## Run with:  godot --headless --path . res://tools/tests/fog_of_war.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## On the light stage, with training dummies standing in for a player and for myrs:
##   1. A player sees its circle and uncovers it; ground beyond it is neither seen nor explored.
##   2. Walking away leaves the old ground explored but no longer seen.
##   3. A myr sees its own, smaller circle.
##   4. The minimap puts the fog on its map picture and hands it the sight circles.
##   5. A joining player's mask is merged with the host's, never replaced.
##   6. Thirty myrs on the move cost little per update.

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const Dummy := preload("res://tools/tests/beast_dummy.gd")

var _failures: Array[String] = []


func _ready() -> void:
	build_stage()
	_run.call_deferred()


func _run() -> void:
	for i: int in ready_frames():
		await get_tree().physics_frame
	var fog: Node = FogOfWar.new()
	fog.name = "FogOfWar"
	add_child(fog)
	var player: Node3D = Dummy.new()
	add_child(player)
	player.global_position = Vector3(-100.0, 0.0, -100.0)
	fog.refresh()

	# 1. its own circle
	var near := Vector3(-100.0 + GameSettings.fog_vision_player * 0.8, 0.0, -100.0)
	var beyond := Vector3(-100.0 + GameSettings.fog_vision_player * 1.3, 0.0, -100.0)
	_check("a player sees within its sight", fog.is_seen(near), "")
	_check("...and not beyond it", not fog.is_seen(beyond), "")
	_check("what it sees is explored", fog.is_explored(near), "")
	_check("what it never saw is dark", not fog.is_explored(beyond) and not fog.is_explored(Vector3(120.0, 0.0, 120.0)), "")

	# 2. walking away
	player.global_position = Vector3(100.0, 0.0, 100.0)
	fog.refresh()
	_check("the old ground stays explored", fog.is_explored(near), "")
	_check("...but is no longer seen", not fog.is_seen(near), "")
	_check("the new ground is seen", fog.is_seen(Vector3(110.0, 0.0, 100.0)) and fog.is_explored(Vector3(110.0, 0.0, 100.0)), "")

	# 3. a myr's smaller circle
	var myr := Node3D.new()
	myr.add_to_group("myrs")
	add_child(myr)
	myr.global_position = Vector3(0.0, 0.0, 120.0)
	fog.refresh()
	_check("a myr sees its own circle", fog.is_seen(Vector3(GameSettings.fog_vision_myr * 0.8, 0.0, 120.0)), "")
	_check("...smaller than a player's", not fog.is_seen(Vector3(GameSettings.fog_vision_myr * 1.2, 0.0, 120.0)), "")
	myr.queue_free()

	# 4. the minimap's picture wears the fog
	var frame := Control.new()
	add_child(frame)
	var picture := TextureRect.new()
	picture.name = "MinimapPicture"
	frame.add_child(picture)
	var minimap := Minimap.new()
	frame.add_child(minimap)
	await get_tree().process_frame
	fog.refresh()
	minimap._update_fog()
	var material := picture.material as ShaderMaterial
	_check("the minimap puts the fog on its picture", material != null and material.shader == Minimap.FOG_SHADER, "material %s" % picture.material)
	if material != null:
		_check("...with this moment's sight circles", int(material.get_shader_parameter("source_count")) == fog.shader_source_count()
			and fog.shader_source_count() >= 1, "count %s" % material.get_shader_parameter("source_count"))
		_check("...and the explored map", material.get_shader_parameter("explored") == fog.explored_texture, "")
	frame.queue_free()

	# 5. a joiner's mask is merged
	var joiner: Node = FogOfWar.new()
	add_child(joiner)
	var host_data: PackedByteArray = fog.explored.get_data()
	joiner._net_explored(host_data)
	_check("a joining player gets the host's explored ground", joiner.is_explored(near), "")
	_check("...and keeps its own", joiner.is_explored(Vector3(110.0, 0.0, 100.0)), "")
	joiner.queue_free()

	# 6. cost
	var walkers: Array[Node3D] = []
	for i: int in 30:
		var walker := Node3D.new()
		walker.add_to_group("myrs")
		add_child(walker)
		walker.global_position = Vector3(-150.0 + i * 10.0, 0.0, -50.0)
		walkers.append(walker)
	var total: int = 0
	var updates: int = 20
	for step: int in updates:
		for walker: Node3D in walkers:
			walker.global_position += Vector3(0.0, 0.0, 4.0)
		var started: int = Time.get_ticks_usec()
		fog.refresh()
		total += Time.get_ticks_usec() - started
	var each: float = float(total) / float(updates) / 1000.0
	_check("an update with thirty myrs on the move is cheap", each < 4.0, "%.2f ms" % each)
	print("  %.2f ms per update, thirty myrs walking" % each)

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
