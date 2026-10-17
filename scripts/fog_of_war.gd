extends Node
## The team's fog of war, for the minimap (GameSettings' Fog of war block).
##
## What the team sees is worked out on every machine from what every machine already knows -
## where the players, the myrs, the team's own summons and the crystal are, all replicated
## anyway - so seeing costs no network at all. Each of them sees a circle; an enemy is on the
## minimap only inside one (Minimap asks is_seen), and the circles go to the minimap's fog
## shader (assets/shaders/minimap_fog.gdshader) as they are.
##
## Ground anyone has seen stays uncovered for the run: an explored mask over the minimap's
## square, EXPLORED_RES cells a side, that only ever fills. Every machine fills its own from
## the same circles, so they agree - except for someone who joins a run under way, who missed
## what was seen before they came. The host sends them its mask (push_to), and it is merged in.
##
## Made by MainController, one per match, so a new run starts dark. Preloaded by path rather
## than given a `class_name`: see scripts/icon_style.gd.

## Cells per side of the explored mask. The minimap square is 360 m, so one cell is ~2.8 m:
## finer than anything the minimap can draw.
const EXPLORED_RES := 128
## Half the side of the square the minimap shows, metres - Minimap.world_radius.
const WORLD_RADIUS := 180.0
## Sight circles handed to the shader; the rest are still counted for is_seen.
const MAX_SHADER_SOURCES := 48

var explored: Image
var explored_texture: ImageTexture
## This update's sight circles, as Vector3(x, z, radius) in world metres.
var sources: Array[Vector3] = []

var _timer: float = 0.0
var _dirty: bool = false
var _shader_sources: PackedVector4Array = PackedVector4Array()
## The explored mask as bytes, one per cell, 0 or 255 - what is written; `explored` is set
## from it when something changed. Bytes rather than Image.set_pixel because a sight circle is
## a thousand cells, and thirty myrs walking at once were thirty thousand pixel calls a tick.
var _bytes: PackedByteArray = PackedByteArray()
## Source node id -> the cell it last uncovered from. A source that has not moved a whole
## cell has nothing new to uncover, which is most of them most of the time.
var _last_cells: Dictionary = {}


func _ready() -> void:
	_bytes.resize(EXPLORED_RES * EXPLORED_RES)
	_bytes.fill(0)
	explored = Image.create_from_data(EXPLORED_RES, EXPLORED_RES, false, Image.FORMAT_L8, _bytes)
	explored_texture = ImageTexture.create_from_image(explored)
	_shader_sources.resize(MAX_SHADER_SOURCES)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = GameSettings.fog_update_interval
	refresh()


## Gathers this moment's sight circles and uncovers what they cover. Called on a timer; a
## test calls it directly.
func refresh() -> void:
	sources.clear()
	for player: Node in get_tree().get_nodes_in_group("player"):
		_add_source(player, GameSettings.fog_vision_player)
	for myr: Node in get_tree().get_nodes_in_group("myrs"):
		_add_source(myr, GameSettings.fog_vision_myr)
	for ally: Node in get_tree().get_nodes_in_group("allies"):
		_add_source(ally, GameSettings.fog_vision_ally)
	var scene: Node = get_tree().current_scene
	var anchor: Variant = scene.get("crystal_anchor") if scene != null else null
	if anchor is Node3D:
		_add_source(anchor as Node3D, GameSettings.fog_vision_crystal)
	if _dirty:
		_dirty = false
		explored.set_data(EXPLORED_RES, EXPLORED_RES, false, Image.FORMAT_L8, _bytes)
		explored_texture.update(explored)


## Whether the team sees `at` right now.
func is_seen(at: Vector3) -> bool:
	for source: Vector3 in sources:
		var dx: float = at.x - source.x
		var dz: float = at.z - source.y
		if dx * dx + dz * dz <= source.z * source.z:
			return true
	return false


## Whether anyone on the team has seen `at` this run.
func is_explored(at: Vector3) -> bool:
	var cell: Vector2i = _cell_of(at.x, at.z)
	if cell.x < 0 or cell.y < 0 or cell.x >= EXPLORED_RES or cell.y >= EXPLORED_RES:
		return false
	return _bytes[cell.y * EXPLORED_RES + cell.x] > 127


## The sight circles in the minimap's UV space, for its fog shader, and how many there are.
func shader_sources() -> PackedVector4Array:
	var count: int = mini(sources.size(), MAX_SHADER_SOURCES)
	for i: int in MAX_SHADER_SOURCES:
		if i < count:
			var s: Vector3 = sources[i]
			_shader_sources[i] = Vector4((s.x + WORLD_RADIUS) / (2.0 * WORLD_RADIUS),
				(s.y + WORLD_RADIUS) / (2.0 * WORLD_RADIUS), s.z / (2.0 * WORLD_RADIUS), 0.0)
		else:
			_shader_sources[i] = Vector4.ZERO
	return _shader_sources


func shader_source_count() -> int:
	return mini(sources.size(), MAX_SHADER_SOURCES)


## The host's explored mask, for a player joining a run under way.
func push_to(peer_id: int) -> void:
	if Net.is_active() and Net.is_server():
		_net_explored.rpc_id(peer_id, explored.get_data())


## Merged rather than replaced: whatever this machine has seen since it joined stays seen.
@rpc("authority", "call_remote", "reliable")
func _net_explored(data: PackedByteArray) -> void:
	if data.size() != EXPLORED_RES * EXPLORED_RES:
		return
	for i: int in data.size():
		if data[i] > _bytes[i]:
			_bytes[i] = data[i]
	explored.set_data(EXPLORED_RES, EXPLORED_RES, false, Image.FORMAT_L8, _bytes)
	explored_texture.update(explored)


func _add_source(node: Node, radius: float) -> void:
	if not node is Node3D or not is_instance_valid(node) or node.is_queued_for_deletion() or radius <= 0.0:
		return
	var at: Vector3 = (node as Node3D).global_position
	var source := Vector3(at.x, at.z, radius)
	sources.append(source)
	var cell: Vector2i = _cell_of(at.x, at.z)
	var id: int = node.get_instance_id()
	if _last_cells.get(id, Vector2i(-99999, -99999)) == cell:
		return
	_last_cells[id] = cell
	_uncover(source, cell)


func _uncover(source: Vector3, centre: Vector2i) -> void:
	var cell_size: float = 2.0 * WORLD_RADIUS / float(EXPLORED_RES)
	var reach: int = int(ceil(source.z / cell_size))
	var radius_cells_squared: float = pow(source.z / cell_size, 2.0)
	for y: int in range(maxi(centre.y - reach, 0), mini(centre.y + reach + 1, EXPLORED_RES)):
		var dy: float = float(y - centre.y)
		var row: int = y * EXPLORED_RES
		for x: int in range(maxi(centre.x - reach, 0), mini(centre.x + reach + 1, EXPLORED_RES)):
			var dx: float = float(x - centre.x)
			if dx * dx + dy * dy <= radius_cells_squared and _bytes[row + x] == 0:
				_bytes[row + x] = 255
				_dirty = true


func _cell_of(x: float, z: float) -> Vector2i:
	var cell_size: float = 2.0 * WORLD_RADIUS / float(EXPLORED_RES)
	return Vector2i(int(floor((x + WORLD_RADIUS) / cell_size)), int(floor((z + WORLD_RADIUS) / cell_size)))
