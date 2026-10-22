extends Node3D
## What a slain wild beast leaves for Call of the Herd (green_11, docs/SKILL_DESIGN.md round
## two): a glowing trophy in its biome's colour that remembers the beast - its species, its
## skin and its size - until a player walks over it. The player who takes it carries it until
## they call that beast.
##
## The game's first thing on the ground that is picked up by walking over it; mana is banked on
## the kill and equipment is announced, so neither ever needed one. Server-decided like every
## pickup must be: the spawner puts it on every screen, the server sees who touched it and
## gives it to them (Player.take_trophy), then frees it.
##
## Only dropped while somebody on the team owns Call of the Herd (RunState.on_enemy_killed's
## beast branch), so the ground does not fill with things nobody can use.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

var beast_color: String = "Green"
var beast_size: float = 1.0
var _life: float = 0.0
var _spin: Node3D = null


static func create(color: String, size: float) -> Node3D:
	var trophy: Node3D = (load("res://scripts/beast_trophy.gd") as GDScript).new()
	trophy.beast_color = color
	trophy.beast_size = size
	return trophy


func _ready() -> void:
	name = "BeastTrophy"
	_life = GameSettings.spell_green_herd_trophy_lifetime
	var tint: Color = EnemyBase.BeastDatabase.VISUAL_COLORS.get(beast_color, Color(0.4, 0.8, 0.3)).lightened(0.35)
	_spin = Node3D.new()
	_spin.position = Vector3(0.0, 0.9, 0.0)
	add_child(_spin)
	# A fang of light: a small elongated gem, bigger for a bigger beast, in the biome's colour.
	var gem := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.28, 0.6, 0.28) * clampf(sqrt(beast_size), 1.0, 2.0)
	gem.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 2.4
	gem.material_override = mat
	_spin.add_child(gem)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.5
	light.omni_range = 3.0
	_spin.add_child(light)


func _process(delta: float) -> void:
	if is_instance_valid(_spin):
		_spin.rotate_y(delta * 1.6)
		_spin.position.y = 0.9 + sin(Time.get_ticks_msec() * 0.003) * 0.12
	if not Net.is_server():
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or player.get("is_downed") == true:
			continue
		if player.global_position.distance_to(global_position) > GameSettings.spell_green_herd_pickup_radius:
			continue
		if player.has_method("take_trophy") and player.take_trophy(beast_color, beast_size):
			NetFx.ring(global_position, Color(0.5, 0.9, 0.4), 1.4)
			queue_free()
			return
