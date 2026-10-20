extends Node
## Regression test for the jump (PlayerAnimator.begin_jump): the clip's crouch is the run-up,
## the body leaves the ground on the clip's take-off frame, the clip's peak and the body's arc
## peak together - so the clip's own lift adds to the jump at the right moment instead of
## after it - and the landing plays once the feet are down. Run as the warrior, whose packs
## have a standing and a running jump.
##
## Run with (windowed - a player only reads its buttons with the mouse captured):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/player_jump.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, plus MEASURE lines.
##
##   1. the clips carry their phases (take-off, peak, touchdown);
##   2. standing: during the run-up the body stays on the ground and the clip crouches;
##   3. it leaves the ground once the run-up (GameSettings.player_jump_runup) is over;
##   4. the hips peak within a few frames of the body's arc;
##   5. the landing plays from the touchdown, after the feet are down;
##   6. at a run, the running take-off is used.

var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	# The solo seat plays the menu's class - see archer_kit.gd for why it is set this way and
	# put back before the test quits.
	var probe: Node = load("res://tools/tests/player_jump.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "warrior"
	probe.name = "PlayerJumpTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null("WaveManager") == null or PlayerRegistry.get_local() == null:
		return
	_started = true
	await _run(scene, PlayerRegistry.get_local() as Player)
	UserSettings.set_value(&"character_class", String(get_meta("player_class", "warrior")))
	await get_tree().create_timer(0.6).timeout
	get_tree().quit()


func _run(main: Node, player: Player) -> void:
	await _frames(60)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var waves: Node = main.get_node("WaveManager")
	waves.set_physics_process(false)
	waves.set_process(false)
	await _frames(30)
	var animator: PlayerAnimator = player.animator

	# 1. the phases
	var phases: PackedFloat32Array = animator.jump_phases(PlayerAnimator.JUMP_CLIP)
	_check("the jump clip carries its phases", phases.size() == 3 and phases[0] < phases[1] and phases[1] < phases[2],
		str(phases))
	_check("...and so does the running take-off", animator.jump_phases(PlayerAnimator.JUMP_RUN_CLIP).size() == 3,
		str(animator.jump_phases(PlayerAnimator.JUMP_RUN_CLIP)))

	# 2-5. standing
	var standing: Dictionary = await _jump(player)
	_check("the run-up keeps the body on the ground", standing["runup_lift"] < 0.01,
		"%.3f m" % standing["runup_lift"])
	_check("...while the clip crouches", standing["runup_phase_seen"], "")
	var runup: float = minf(GameSettings.player_jump_runup, phases[0])
	_check("the body leaves the ground once the run-up is over",
		absf(standing["takeoff_t"] - runup) <= 3.0 / Engine.physics_ticks_per_second,
		"left at %.3f s, run-up %.3f s" % [standing["takeoff_t"], runup])
	# Within about seven frames: the clip's own lift is lopsided round its measured peak, and
	# where the sum of the two peaks drifts by a few frames from run to run.
	_check("the hips peak with the body's arc", absf(standing["hips_peak_t"] - standing["body_peak_t"]) <= 0.12,
		"hips %.2f s, body %.2f s" % [standing["hips_peak_t"], standing["body_peak_t"]])
	_check("the clip adds its own lift at the peak", standing["hips_peak"] > standing["body_peak"] + 0.3,
		"hips %.2f m, body %.2f m" % [standing["hips_peak"], standing["body_peak"]])
	_check("the landing starts once the feet are down", standing["landing_ok"],
		"landing phase from %.2f s, down at %.2f s, clip at %.2f (touchdown %.2f)" % [
			standing["landing_t"], standing["down_t"], standing["landing_pos"], phases[2]])
	print("MEASURE standing jump: body %.2f m at %.2f s, hips +%.2f m at %.2f s" % [
		standing["body_peak"], standing["body_peak_t"], standing["hips_peak"], standing["hips_peak_t"]])
	await _seconds(1.0)

	# 6. at a run
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _seconds(1.2)
	var running: Dictionary = await _jump(player)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check("at a run the running take-off plays", running["clip"] == PlayerAnimator.JUMP_RUN_CLIP, running["clip"])
	_check("...peaking with the body's arc too", absf(running["hips_peak_t"] - running["body_peak_t"]) <= 0.12,
		"hips %.2f s, body %.2f s" % [running["hips_peak_t"], running["body_peak_t"]])
	_report()


## Presses jump and follows it to the ground and a little past, frame by frame.
func _jump(player: Player) -> Dictionary:
	var animator: PlayerAnimator = player.animator
	var floor_y: float = player.global_position.y
	var rest_hips: float = _hips(player) - floor_y
	var out := {"runup_lift": 0.0, "runup_phase_seen": false, "takeoff_t": -1.0, "body_peak": 0.0,
		"body_peak_t": 0.0, "hips_peak": 0.0, "hips_peak_t": 0.0, "landing_t": -1.0, "down_t": -1.0,
		"landing_pos": 0.0, "landing_ok": false, "clip": ""}
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var t: float = 0.0
	var airborne: bool = false
	for i: int in int(1.8 * Engine.physics_ticks_per_second):
		await _frames(1)
		t += step
		var state: Dictionary = animator.jump_state()
		var body: float = player.global_position.y - floor_y
		var hips: float = _hips(player) - floor_y - rest_hips
		if out["clip"] == "":
			out["clip"] = String(state["clip"])
		if int(state["phase"]) == PlayerAnimator.JumpPhase.RUNUP:
			out["runup_phase_seen"] = true
			out["runup_lift"] = maxf(float(out["runup_lift"]), body)
		if not airborne and body > 0.02:
			airborne = true
			out["takeoff_t"] = t - step
		if body > float(out["body_peak"]):
			out["body_peak"] = body
			out["body_peak_t"] = t
		if hips > float(out["hips_peak"]):
			out["hips_peak"] = hips
			out["hips_peak_t"] = t
		if airborne and float(out["down_t"]) < 0.0 and body <= 0.01 and t > float(out["takeoff_t"]) + 0.2:
			out["down_t"] = t
		if float(out["landing_t"]) < 0.0 and int(state["phase"]) == PlayerAnimator.JumpPhase.LANDING:
			out["landing_t"] = t
			out["landing_pos"] = float(state["position"])
	var phases: PackedFloat32Array = animator.jump_phases(String(out["clip"]))
	# A standing landing: the touchdown frame reached, and not before the feet are down. A
	# running one hands straight over to the gait and has no landing phase to check.
	if String(out["clip"]) == PlayerAnimator.JUMP_CLIP and phases.size() == 3:
		out["landing_ok"] = float(out["landing_t"]) >= float(out["down_t"]) - 2.0 * step \
			and absf(float(out["landing_pos"]) - phases[2]) < 0.15
	return out


func _hips(player: Player) -> float:
	var skeleton: Skeleton3D = player.find_child("Skeleton3D", true, false) as Skeleton3D
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips"))).origin.y


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures.append("%s: %s" % [label, detail])


func _report() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
