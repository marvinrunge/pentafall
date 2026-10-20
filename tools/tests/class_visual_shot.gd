extends Node3D
## Renders a player class's visual in chosen poses - for fitting its props to the hands and
## checking a new clip set reads right, without the map around it.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 900x900 res://tools/tests/class_visual_shot.tscn -- <folder> <visual.tscn> idle@0.5,aim@1.2
##
## Each pose is `clip@seconds`; writes <folder>/<clip>_<seconds>_<view>.png for the views
## front, side (the character's left) and back.
##
## With a bone and a distance after the poses, the camera frames that bone instead, from that
## many metres - for a close look at a hand on a weapon:
##   ... -- <folder> <visual.tscn> idle@0.5 mixamorig_LeftHand 0.7
##
## `--no-normal-map` anywhere among the args draws the character without its normal map - to
## tell what the map adds from what the mesh's own normals do. `--hand-orb` gives it the mage's
## orb over the palm (MageHandOrb), which the game attaches at runtime. `--status=<bits>` puts
## the buffs of those StatusFx bits on it (4 is Ironbark), overlay and all, the way a player in
## the game carries them.

const SETTLE_FRAMES := 6

var _camera: Camera3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.52)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.5
	add_child(fill)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	_camera.current = true
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0]
	DirAccess.make_dir_recursive_absolute(folder)
	var visual: Node3D = (load(args[1]) as PackedScene).instantiate()
	var status: int = 0
	for arg: String in args:
		if arg.begins_with("--status="):
			status = int(arg.get_slice("=", 1))
	if status != 0:
		# StatusFx reads its parent's `status_fx` and lays its overlay on what is under the
		# parent's "Animator" - a stand-in for the player with just those two.
		var holder := Node3D.new()
		var script := GDScript.new()
		script.source_code = "extends Node3D
var status_fx: int = %d
" % status
		script.reload()
		holder.set_script(script)
		add_child(holder)
		var animator := Node3D.new()
		animator.name = "Animator"
		holder.add_child(animator)
		animator.add_child(visual)
		holder.add_child(StatusFx.new())
	else:
		add_child(visual)
	if args.has("--hand-orb"):
		var orb := MageHandOrb.new()
		orb.setup(visual.find_child("Skeleton3D", true, false) as Skeleton3D)
		visual.add_child(orb)
	if args.has("--no-normal-map"):
		for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as StandardMaterial3D
				if material != null:
					material = material.duplicate() as StandardMaterial3D
					material.normal_enabled = false
					mesh_instance.set_surface_override_material(surface, material)
	var anim: AnimationPlayer = visual.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for pose: String in args[2].split(","):
		var clip: String = pose.get_slice("@", 0)
		var at: float = float(pose.get_slice("@", 1))
		anim.play(clip)
		anim.seek(at, true)
		anim.advance(0.0)
		await get_tree().process_frame
		var target := Vector3(0.0, 1.0, 0.0)
		var distance: float = 4.2
		var views: Array = [["front", Vector3(0.0, 0.1, -1.0)], ["side", Vector3(1.0, 0.1, 0.0)], ["back", Vector3(0.0, 0.1, 1.0)]]
		# The flags can stand anywhere, so the bone and distance are counted without them.
		var plain: PackedStringArray = PackedStringArray()
		for arg: String in args:
			if not arg.begins_with("--"):
				plain.append(arg)
		if plain.size() > 4:
			var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false)
			var bone: int = skeleton.find_bone(plain[3])
			target = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
			distance = float(plain[4])
			views.append(["right", Vector3(-1.0, 0.1, 0.0)])
			views.append(["above", Vector3(0.0, 1.0, -0.3)])
		# The character faces -Z: "front" looks at its face from -Z.
		for view: Array in views:
			_camera.position = target + (view[1] as Vector3).normalized() * distance
			_camera.look_at(target)
			for i in SETTLE_FRAMES:
				await get_tree().process_frame
			var image: Image = get_viewport().get_texture().get_image()
			image.save_png("%s/%s_%s_%s.png" % [folder, clip, pose.get_slice("@", 1), view[0]])
	get_tree().quit()
