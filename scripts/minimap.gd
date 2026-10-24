extends ColorRect
class_name Minimap

# The world size to map (radius from center)
# The outer edge of the pentagon is at distance ~164 from the center.
# We'll use 180 to give it a little padding.
@export var world_radius: float = 180.0

@export var player_color: Color = Color.GREEN
@export var enemy_color: Color = Color.RED
@export var myr_color: Color = Color.CYAN
@export var base_color: Color = Color.WHITE

var _redraw_timer: float = 0.0

## A beast's mark under Explorer's Scope, per biome - bright enough to read on the map, which
## is why Black is a violet rather than black.
const SCOPE_COLORS: Dictionary = {
	"White": Color(1.0, 0.97, 0.82),
	"Blue": Color(0.35, 0.65, 1.0),
	"Black": Color(0.72, 0.42, 0.95),
	"Red": Color(1.0, 0.5, 0.2),
	"Green": Color(0.45, 0.95, 0.4),
}

## The ring round a revealed enemy (one storming the crystal), and how fast it pulses.
const REVEALED_COLOR := Color(1.0, 0.85, 0.35)
const REVEALED_PULSE_HZ := 1.5

const FOG_SHADER := preload("res://assets/shaders/minimap_fog.gdshader")
## The rounded corners' share of the side, as the picture had them (IconStyle.CORNER_RATIO).
const FOG_CORNER_RATIO := 0.25

## The fog of war's own material for the map picture under the dots, made when a FogOfWar
## first turns up (a match; there is none in the menus).
var _fog_material: ShaderMaterial = null

func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0:
		_redraw_timer = GameSettings.minimap_update_interval
		_update_fog()
		queue_redraw()


## The match's fog of war (scripts/fog_of_war.gd), or null - outside a match, or switched off.
func _fog() -> Node:
	if not GameSettings.fog_of_war_enabled:
		return null
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null("FogOfWar") if scene != null else null


## Puts the fog on the map picture the HUD laid under this node (MinimapPicture), replacing its
## plain rounded-corner material, and hands it this moment's sight circles.
func _update_fog() -> void:
	var fog: Node = _fog()
	var picture: TextureRect = get_parent().get_node_or_null("MinimapPicture") as TextureRect if get_parent() != null else null
	if fog == null or picture == null:
		return
	if _fog_material == null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = FOG_SHADER
		_fog_material.set_shader_parameter("radius_ratio", FOG_CORNER_RATIO)
	if picture.material != _fog_material:
		picture.material = _fog_material
	_fog_material.set_shader_parameter("explored", fog.explored_texture)
	_fog_material.set_shader_parameter("sources", fog.shader_sources())
	_fog_material.set_shader_parameter("source_count", fog.shader_source_count())
	_fog_material.set_shader_parameter("unexplored_darkness", GameSettings.fog_unexplored_darkness)
	_fog_material.set_shader_parameter("unseen_darkness", GameSettings.fog_unseen_darkness)

func _draw() -> void:
	var center = size / 2.0
	var scale_factor = (size.x / 2.0) / world_radius
	
	# Draw the base at the center
	draw_circle(center, 4.0, base_color)
	
	# Draw Myrs
	var myrs = get_tree().get_nodes_in_group("myrs")
	for myr in myrs:
		var pos = _world_to_map(myr.global_position, center, scale_factor)
		draw_circle(pos, 2.5, myr_color)
		
	# Draw Enemies. With Explorer's Scope on, the wild beasts stand out: in their biome's colour
	# and as big as they are, so a hunt can be picked from the map.
	var scope: bool = false
	var local: Node = PlayerRegistry.get_local()
	if local != null and local.has_method("equipment_value"):
		scope = float(local.equipment_value("explorers_scope")) > 0.0
	# Under the fog of war only what the team sees is drawn - Explorer's Scope's beasts aside, and
	# the enemies storming the crystal (EnemyBase.revealed): the last of a wave is never left for
	# the team to hunt for in the fog.
	var fog: Node = _fog()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * REVEALED_PULSE_HZ)
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var scoped: bool = scope and enemy is EnemyBase and (enemy as EnemyBase).is_beast()
		var revealed: bool = enemy is EnemyBase and (enemy as EnemyBase).revealed and not (enemy as EnemyBase).is_dying
		if fog != null and not scoped and not revealed and not fog.is_seen(enemy.global_position):
			continue
		var pos = _world_to_map(enemy.global_position, center, scale_factor)
		if scoped:
			var beast := enemy as EnemyBase
			draw_circle(pos, 3.0 + 1.3 * beast._beast_size, SCOPE_COLORS.get(beast.enemy_data.color_identity, enemy_color))
			continue
		draw_circle(pos, 3.0, enemy_color)
		if revealed:
			draw_arc(pos, 5.0 + 2.0 * pulse, 0.0, TAU, 20, Color(REVEALED_COLOR, 0.45 + 0.55 * pulse), 1.5)
		
	# Draw Players
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		var pos = _world_to_map(player.global_position, center, scale_factor)
		# A teammate who is down is a cross with their time left round it, not an arrow - the
		# one thing on the map that asks somebody to come (DownedMark, docs/REVIVE_PLAN.md).
		if bool(player.get("is_downed")):
			DownedMark.draw_countdown(self, pos, 9.0, DownedMark.share_left(player), 2.0)
			DownedMark.draw_cross(self, pos, 5.5)
			continue
		
		# Draw view direction indicator as a triangle (arrow)
		var forward_3d = -player.global_transform.basis.z
		var forward_2d = Vector2(forward_3d.x, forward_3d.z).normalized()
		var right_2d = forward_2d.rotated(PI/2.0)
		
		var p1 = pos + forward_2d * 8.0
		var p2 = pos - forward_2d * 6.0 + right_2d * 5.0
		var p3 = pos - forward_2d * 6.0 - right_2d * 5.0
		
		draw_polygon(PackedVector2Array([p1, p2, p3]), PackedColorArray([player_color]))

func _world_to_map(world_pos: Vector3, center: Vector2, scale_factor: float) -> Vector2:
	# Godot 3D coordinates: X is right, Z is backward (or forward if negative)
	# Minimap 2D coordinates: X is right, Y is down
	# So X maps to X, and Z maps to Y.
	return center + Vector2(world_pos.x, world_pos.z) * scale_factor
