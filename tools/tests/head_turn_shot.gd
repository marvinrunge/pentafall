extends Node3D
## Close-ups of a player visual's face with the head turned and tilted on top of a clip, for
## checking how the skin around the jaw follows the head (tools/skin_weight_fix.gd).
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 800x800 res://tools/tests/head_turn_shot.tscn -- <folder> <visual.tscn> <tag> [fix]
##
## With `fix`, the chin re-weight is applied in memory first (nothing is saved), so the same
## run can show before and after. Writes <folder>/<tag>_<turn>.png for each head turn.

const SkinWeightFix = preload("res://tools/skin_weight_fix.gd")
const SETTLE_FRAMES := 6
## [name, yaw, pitch] in degrees, added to the head bone on top of the idle pose.
const TURNS := [["rest", 0.0, 0.0], ["left", 55.0, 0.0], ["right", -55.0, 0.0], ["up", 0.0, -30.0], ["down_left", 40.0, 25.0]]

var _camera: Camera3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.46, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -150, 0)
	key.light_energy = 1.3
	add_child(key)
	_camera = Camera3D.new()
	_camera.fov = 22.0
	add_child(_camera)
	_camera.current = true
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0]
	DirAccess.make_dir_recursive_absolute(folder)
	var visual: Node3D = (load(args[1]) as PackedScene).instantiate()
	add_child(visual)
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false)
	if args.size() > 3 and args[3] == "fix":
		for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			if (node as MeshInstance3D).skin != null:
				# A copy, so the shared imported resource is not changed for anything else.
				var mesh_node := node as MeshInstance3D
				mesh_node.mesh = mesh_node.mesh.duplicate(true)
				print("re-weighted %d vertices" % SkinWeightFix.reweight_chin(mesh_node, skeleton))
	var anim: AnimationPlayer = visual.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("idle")
	anim.seek(0.5, true)
	anim.advance(0.0)
	var head: int = skeleton.find_bone("mixamorig_Head")
	var base_rotation: Quaternion = skeleton.get_bone_pose_rotation(head)
	# Where the face points in the untouched pose - the rig faces +Z at rest, and the idle
	# stance turns the body, so the visual's own axes say nothing about it. The camera stays
	# put for every turn, so each one is seen against the same view.
	var head_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head)
	var rest_basis: Basis = skeleton.get_bone_global_rest(head).basis
	var face: Vector3 = (head_pose.basis * rest_basis.inverse() * Vector3(0.0, 0.0, 1.0))
	face.y = 0.0
	face = face.normalized()
	var face_side: Vector3 = face.cross(Vector3.UP).normalized()
	var head_world: Vector3 = head_pose.origin
	_camera.position = head_world + Vector3(0.0, 0.05, 0.0) + (face + face_side * 0.35).normalized() * 1.25
	_camera.look_at(head_world + Vector3(0.0, 0.05, 0.0))
	for turn: Array in TURNS:
		# Turned in the character's own frame: yaw about up, pitch about the shoulder line.
		var parent_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.get_bone_parent(head))
		var up_local: Vector3 = (parent_global.basis.inverse() * visual.global_basis.y).normalized()
		var side_local: Vector3 = (parent_global.basis.inverse() * visual.global_basis.x).normalized()
		var extra := Quaternion(up_local, deg_to_rad(turn[1])) * Quaternion(side_local, deg_to_rad(turn[2]))
		skeleton.set_bone_pose_rotation(head, extra * base_rotation)
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [folder, args[2], turn[0]])
	get_tree().quit()
