extends RefCounted
## Gives the chin back to the head on a Mixamo-rigged player model.
##
## Mixamo's auto-skinning leaves the lower face split between Head and Neck: measured on the
## rest pose, the orc's chin followed the head 40% of the way and the elf's 50-60%, and the
## mouth 60-80%. So when a clip turns the head, the chin stays behind with the neck and the
## jaw smears. This moves the Neck share of every vertex in front of the neck and above the
## jaw line onto Head, fading out across a band under the chin so the throat still bends
## with the neck.
##
## Where a vertex is, is measured on the REST pose in the head joint's frame and in units of
## the rig's own neck-to-crown length, so one set of numbers serves an orc and an elf of
## different sizes and import scales.
##
## Only the skin weights are touched - written straight into the mesh's surface storage
## (`_surfaces`), so the vertex data, the LODs and the shadow mesh's own copy all stay as the
## importer made them. Marks the mesh, and a marked mesh is left alone, so it is never
## applied on top of itself. Preloaded by path, never by class_name (a headless build run
## does not rescan for new global classes).
##
## TUNING IT BY HAND: the settings below are the defaults; a class overrides any of them in
## its builder config (PlayerCharacterBuilder.CONFIGS[<class>]["chin"]). Change the numbers,
## then re-apply and look:
##
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/fix_player_chins.gd -- warrior
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 700x700 res://tools/tests/head_turn_shot.tscn -- C:/temp/chin res://scenes/characters/warrior/visual.tscn warrior
##
## fix_player_chins always starts again from the ORIGINAL Mixamo weights in the class's
## source fbx, so every run replaces the last attempt rather than adding to it, and
## `"strength": 0.0` puts the original weighting back exactly. All distances are shares of the
## rig's neck-to-crown length (about 27 cm on the orc), measured from the head joint, which
## sits roughly level with the bottom of the ears.
##
##   forward_start  how far in front of the head joint the change begins. Lower it if the
##                  back of the jaw, below the ear, still lags; raise it if the side of the
##                  neck creases when the head turns.
##   forward_full   where the change is complete. Keep it above forward_start; the gap between
##                  the two is how soft the fade is from the side of the neck to the face.
##   jaw_low        the height below which nothing changes: the throat. Raise it (towards 0)
##                  if the throat twists with the head; lower it if the underside of the chin
##                  still stretches.
##   jaw_high       the height above which the change is complete: the chin and mouth. Keep
##                  it above jaw_low; the gap is how soft the fade is down the throat.
##   strength       how much of the Neck share moves at all, 0 to 1. 1 hands the chin
##                  entirely to the head; 0.6 leaves 40% of it following the neck.

const HEAD := "mixamorig_Head"
const NECK := "mixamorig_Neck"
const CROWN := "mixamorig_HeadTop_End"
const MARK := "chin_reweighted"

## The defaults - see the header for what each one does. Fitted on both rigs by rendering
## head turns: a band that reached further down the throat creased the side of the neck.
const DEFAULTS := {
	"forward_start": 0.18,
	"forward_full": 0.32,
	"jaw_low": -0.20,
	"jaw_high": -0.07,
	"strength": 1.0,
}


## Re-weights `mesh_node` (skinned to `skeleton`) and its shadow mesh, with `settings`
## overriding any of DEFAULTS. Returns how many vertices changed, or -1 if the mesh was
## already done.
static func reweight_chin(mesh_node: MeshInstance3D, skeleton: Skeleton3D, settings: Dictionary = {}) -> int:
	var mesh: ArrayMesh = mesh_node.mesh as ArrayMesh
	if mesh == null or mesh_node.skin == null:
		return 0
	if mesh.has_meta(MARK):
		return -1
	var head: int = skeleton.find_bone(HEAD)
	var neck: int = skeleton.find_bone(NECK)
	var crown: int = skeleton.find_bone(CROWN)
	if head == -1 or neck == -1 or crown == -1:
		push_warning("Chin re-weight: the rig has no Head/Neck/HeadTop_End")
		return 0
	var tuned: Dictionary = DEFAULTS.duplicate()
	tuned.merge(settings, true)
	var changed: int = _reweight_mesh(mesh, mesh_node.skin, skeleton, head, neck, crown, tuned)
	if mesh.shadow_mesh is ArrayMesh and not mesh.shadow_mesh.has_meta(MARK):
		_reweight_mesh(mesh.shadow_mesh as ArrayMesh, mesh_node.skin, skeleton, head, neck, crown, tuned)
		mesh.shadow_mesh.set_meta(MARK, true)
	mesh.set_meta(MARK, true)
	return changed


## How much of a vertex's Neck weight goes to Head, from where it sits on the rest pose.
static func transfer_share(rest_position: Vector3, head_rest: Transform3D, unit: float, tuned: Dictionary) -> float:
	# The head joint's own axes are whatever Mixamo gave the rig; measure in the rig's model
	# space instead (up +Y, forward +Z - these rigs face +Z), only centred on the joint.
	var local: Vector3 = rest_position - head_rest.origin
	var forward: float = _ramp(local.z / unit, float(tuned["forward_start"]), float(tuned["forward_full"]))
	var height: float = _ramp(local.y / unit, float(tuned["jaw_low"]), float(tuned["jaw_high"]))
	return clampf(float(tuned["strength"]), 0.0, 1.0) * forward * height


## 0 below `from`, 1 above `to`, eased between. A from/to the wrong way round still works.
static func _ramp(value: float, from: float, to: float) -> float:
	if is_equal_approx(from, to):
		return 1.0 if value >= to else 0.0
	return smoothstep(0.0, 1.0, clampf((value - from) / (to - from), 0.0, 1.0))


static func _reweight_mesh(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D, head: int, neck: int, crown: int, tuned: Dictionary) -> int:
	var head_rest: Transform3D = skeleton.get_bone_global_rest(head)
	var unit: float = skeleton.get_bone_global_rest(crown).origin.y - skeleton.get_bone_global_rest(neck).origin.y
	# Bind index -> skeleton bone, and the binds that are the head and the neck.
	var bind_bone: PackedInt32Array = PackedInt32Array()
	for b in skin.get_bind_count():
		var bind_name: String = skin.get_bind_name(b)
		bind_bone.append(skeleton.find_bone(bind_name) if bind_name != "" else skin.get_bind_bone(b))
	var head_bind: int = bind_bone.find(head)
	if head_bind == -1:
		push_warning("Chin re-weight: Head is not one of the mesh's binds")
		return 0

	var storage: Array = mesh.get("_surfaces")
	var changed: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		var surface: Dictionary = storage[s]
		var skin_data: PackedByteArray = surface.get("skin_data", PackedByteArray())
		# Per vertex the storage holds `per` bone indices then `per` weights, all 16-bit.
		if skin_data.size() != verts.size() * per * 4:
			push_warning("Chin re-weight: unexpected skin data layout (%d bytes for %d vertices)" % [skin_data.size(), verts.size()])
			continue
		for v in verts.size():
			var base: int = v * per
			var rest := Vector3.ZERO
			var neck_slot: int = -1
			var head_slot: int = -1
			var empty_slot: int = -1
			for k in per:
				var w: float = weights[base + k]
				var bind: int = bones[base + k]
				if w <= 0.0:
					if empty_slot == -1:
						empty_slot = k
					continue
				rest += w * (skeleton.get_bone_global_rest(bind_bone[bind]) * skin.get_bind_pose(bind) * verts[v])
				if bind_bone[bind] == neck:
					neck_slot = k
				elif bind == head_bind:
					head_slot = k
			if neck_slot == -1:
				continue
			var share: float = transfer_share(rest, head_rest, unit, tuned)
			if share <= 0.001:
				continue
			var moved: float = weights[base + neck_slot] * share
			weights[base + neck_slot] -= moved
			if head_slot == -1:
				# The vertex had no head weight at all: the slot the neck frees up takes it
				# if the neck goes entirely, otherwise the first empty one.
				head_slot = neck_slot if weights[base + neck_slot] <= 0.0001 else empty_slot
				if head_slot == -1:
					weights[base + neck_slot] += moved
					continue
				bones[base + head_slot] = head_bind
				if head_slot != neck_slot:
					weights[base + head_slot] = 0.0
			weights[base + head_slot] += moved
			_write_vertex(skin_data, v, per, bones, weights)
			changed += 1
		surface["skin_data"] = skin_data
		storage[s] = surface
	mesh.set("_surfaces", storage)
	return changed


## Every weight fix a class's builder config asks for, in the order the builder has always
## applied them - shared by the builder and tools/fix_player_chins.gd so the two never drift.
static func apply_class_fixes(mesh_node: MeshInstance3D, skeleton: Skeleton3D, config: Dictionary) -> void:
	reweight_chin(mesh_node, skeleton, config.get("chin", {}))
	if config.has("rigid_head"):
		print("  rigid head: %d vertices handed to the head" % rigid_head(mesh_node, skeleton, config["rigid_head"]))
	if config.has("even_plates"):
		print("  even plates: %d vertices shared evenly between the legs" % even_plates(mesh_node, skeleton, config["even_plates"]))
	if config.get("mitten_fingers", false):
		print("  mitten fingers: %d vertices moved onto the index joints" % mitten_fingers(mesh_node, skeleton))


# --- the helmet -----------------------------------------------------------------------------

const HEAD_MARK := "head_rigid"

## Hands everything of the head - a helmet, the face under it, the roots of the hair - WHOLLY
## to the Head bone, for a rig where Mixamo let the lower half of it follow the chest.
##
## The knight's Sunforged Warlord was skinned with almost no Neck at all: the ring of jaw,
## cheek guards and helmet rim below the head joint sat on Spine2, so a head turn left the
## chin and the lower helmet behind with the chest and bent the helmet. reweight_chin only
## moves Neck weight in front of the neck, so it cannot reach this. Here every bone's share
## goes, inside a box round the head and above a height ramp under the chin.
##
## Measured as reweight_chin does: on the REST pose, from the head joint, in units of the
## rig's neck-to-crown length, up +Y and forward +Z. Settings (all required):
##   low, high          the height ramp: nothing changes below `low`, all of it above `high`.
##                      `low` sits at the underside of the chin, above the collar of the chest.
##   side_full,         sideways: all of it within side_full of the middle, none past
##   side_zero          side_zero - keeps the shoulder plates out.
##   back_full,         backwards (negative forward): all of it in front of back_full, none
##   back_zero          behind back_zero - the hair hanging down the back stays with it.
## Returns how many vertices changed, or -1 if the mesh was already done.
static func rigid_head(mesh_node: MeshInstance3D, skeleton: Skeleton3D, settings: Dictionary) -> int:
	var head: int = skeleton.find_bone(HEAD)
	var neck: int = skeleton.find_bone(NECK)
	var crown: int = skeleton.find_bone(CROWN)
	if head == -1 or neck == -1 or crown == -1:
		push_warning("Rigid head: the rig has no Head/Neck/HeadTop_End")
		return 0
	var head_rest: Vector3 = skeleton.get_bone_global_rest(head).origin
	var unit: float = skeleton.get_bone_global_rest(crown).origin.y - skeleton.get_bone_global_rest(neck).origin.y
	var reweigh := func(rest: Vector3, by_bone: Dictionary) -> Dictionary:
		var local: Vector3 = (rest - head_rest) / unit
		var share: float = _ramp(local.y, float(settings["low"]), float(settings["high"])) \
			* (1.0 - _ramp(absf(local.x), float(settings["side_full"]), float(settings["side_zero"]))) \
			* (1.0 - _ramp(-local.z, -float(settings["back_full"]), -float(settings["back_zero"])))
		if share <= 0.001:
			return {}
		var out: Dictionary = {}
		var moved: float = 0.0
		for bone: int in by_bone:
			if bone == head:
				continue
			out[bone] = float(by_bone[bone]) * (1.0 - share)
			moved += float(by_bone[bone]) * share
		if moved <= 0.0001:
			return {}
		out[head] = float(by_bone.get(head, 0.0)) + moved
		return out
	return _apply_once(mesh_node, skeleton, HEAD_MARK, [head], reweigh)


# --- the plates between the legs -------------------------------------------------------------

const PLATES_MARK := "plates_evened"

## Shares the plates that hang between the legs - a tabard, the middle tassets front and back -
## EVENLY between the two legs, so they swing with the middle of the pair instead of tearing
## down their middle when the legs part.
##
## Mixamo split the knight's front and back plates exactly down the centre line: the left half
## on LeftUpLeg, the right on RightUpLeg, so every step pulled the halves apart. Here, inside
## the region below, each vertex's left-leg and right-leg shares are set to their average;
## its Hips share is left as it is.
##
## Measured on the REST pose from the Hips joint, in units of the thigh's length (UpLeg to
## Leg), up +Y and forward +Z. Settings (all required):
##   low, high          the height ramp: nothing below `low`, all of it above `high` - the
##                      bottom of the plates, so the thighs under them stay their own.
##   side_full,         sideways: all of it within side_full of the middle, none past
##   side_zero          side_zero - the plates' width, short of the plates over each hip.
##   depth_zero,        forwards or backwards from the joint: none closer than depth_zero, all
##   depth_full         of it past depth_full - the plates hang in front of and behind the
##                      thighs, the inside of the thighs and the crotch do not.
##   to_hips            (optional, default 0) how much of the evened leg share then goes to
##                      Hips, 0 to 1: stiffer plates that swing less with the thighs.
## Returns how many vertices changed, or -1 if the mesh was already done.
static func even_plates(mesh_node: MeshInstance3D, skeleton: Skeleton3D, settings: Dictionary) -> int:
	var hips: int = skeleton.find_bone("mixamorig_Hips")
	var left: int = skeleton.find_bone("mixamorig_LeftUpLeg")
	var right: int = skeleton.find_bone("mixamorig_RightUpLeg")
	var knee: int = skeleton.find_bone("mixamorig_LeftLeg")
	if hips == -1 or left == -1 or right == -1 or knee == -1:
		push_warning("Even plates: the rig has no Hips/UpLeg/Leg")
		return 0
	var hips_rest: Vector3 = skeleton.get_bone_global_rest(hips).origin
	var unit: float = skeleton.get_bone_global_rest(left).origin.distance_to(skeleton.get_bone_global_rest(knee).origin)
	var reweigh := func(rest: Vector3, by_bone: Dictionary) -> Dictionary:
		var local: Vector3 = (rest - hips_rest) / unit
		var share: float = _ramp(local.y, float(settings["low"]), float(settings["high"])) \
			* (1.0 - _ramp(absf(local.x), float(settings["side_full"]), float(settings["side_zero"]))) \
			* _ramp(absf(local.z), float(settings["depth_zero"]), float(settings["depth_full"]))
		var on_left: float = float(by_bone.get(left, 0.0))
		var on_right: float = float(by_bone.get(right, 0.0))
		var stiffen: float = float(settings.get("to_hips", 0.0)) * share
		if share <= 0.001 or (absf(on_left - on_right) <= 0.001 and (stiffen <= 0.001 or on_left + on_right <= 0.001)):
			return {}
		var shift: float = (on_left - on_right) * 0.5 * share
		var out: Dictionary = by_bone.duplicate()
		out[left] = (on_left - shift) * (1.0 - stiffen)
		out[right] = (on_right + shift) * (1.0 - stiffen)
		out[hips] = float(by_bone.get(hips, 0.0)) + (on_left + on_right) * stiffen
		return out
	return _apply_once(mesh_node, skeleton, PLATES_MARK, [hips, left, right], reweigh)


## Runs `reweigh` over `mesh_node`'s mesh and its shadow mesh once, marking both. `needed` are
## the bones the new weights may land on, which must be among the mesh's binds.
static func _apply_once(mesh_node: MeshInstance3D, skeleton: Skeleton3D, mark: String, needed: Array, reweigh: Callable) -> int:
	var mesh: ArrayMesh = mesh_node.mesh as ArrayMesh
	if mesh == null or mesh_node.skin == null:
		return 0
	if mesh.has_meta(mark):
		return -1
	var changed: int = _reweigh_mesh(mesh, mesh_node.skin, skeleton, needed, reweigh)
	if mesh.shadow_mesh is ArrayMesh and not mesh.shadow_mesh.has_meta(mark):
		_reweigh_mesh(mesh.shadow_mesh as ArrayMesh, mesh_node.skin, skeleton, needed, reweigh)
		mesh.shadow_mesh.set_meta(mark, true)
	mesh.set_meta(mark, true)
	return changed


## Rewrites every vertex `reweigh` has new weights for. `reweigh(rest, by_bone)` gets the
## vertex's rest position in the skeleton's model space and its weights keyed by skeleton bone,
## and answers with the new weights the same way, or {} to leave the vertex alone. The heaviest
## of them that fit the vertex's slots are kept and renormalised.
static func _reweigh_mesh(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D, needed: Array, reweigh: Callable) -> int:
	var bind_bone: PackedInt32Array = PackedInt32Array()
	for b in skin.get_bind_count():
		var bind_name: String = skin.get_bind_name(b)
		bind_bone.append(skeleton.find_bone(bind_name) if bind_name != "" else skin.get_bind_bone(b))
	var bone_bind: Dictionary = {}
	for b in bind_bone.size():
		if not bone_bind.has(bind_bone[b]):
			bone_bind[bind_bone[b]] = b
	for bone: int in needed:
		if not bone_bind.has(bone):
			push_warning("Skin weight fix: %s is not one of the mesh's binds" % skeleton.get_bone_name(bone))
			return 0

	var storage: Array = mesh.get("_surfaces")
	var changed: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		var surface: Dictionary = storage[s]
		var skin_data: PackedByteArray = surface.get("skin_data", PackedByteArray())
		if skin_data.size() != verts.size() * per * 4:
			continue
		for v in verts.size():
			var base: int = v * per
			var rest := Vector3.ZERO
			var by_bone: Dictionary = {}
			for k in per:
				var w: float = weights[base + k]
				if w <= 0.0:
					continue
				var bone: int = bind_bone[bones[base + k]]
				rest += w * (skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(bones[base + k]) * verts[v])
				by_bone[bone] = float(by_bone.get(bone, 0.0)) + w
			var wanted: Dictionary = reweigh.call(rest, by_bone)
			if wanted.is_empty():
				continue
			var ordered: Array = wanted.keys().filter(func(bone: int) -> bool: return float(wanted[bone]) > 0.0001)
			ordered.sort_custom(func(a: int, b: int) -> bool: return float(wanted[a]) > float(wanted[b]))
			var total: float = 0.0
			for k in mini(per, ordered.size()):
				total += float(wanted[ordered[k]])
			for k in per:
				if k < ordered.size():
					bones[base + k] = int(bone_bind[ordered[k]])
					weights[base + k] = float(wanted[ordered[k]]) / maxf(total, 0.0001)
				else:
					bones[base + k] = 0
					weights[base + k] = 0.0
			_write_vertex(skin_data, v, per, bones, weights)
			changed += 1
		surface["skin_data"] = skin_data
		storage[s] = surface
	mesh.set("_surfaces", storage)
	return changed


static func _write_vertex(skin_data: PackedByteArray, v: int, per: int, bones: PackedInt32Array, weights: PackedFloat32Array) -> void:
	var offset: int = v * per * 4
	for k in per:
		skin_data.encode_u16(offset + k * 2, bones[v * per + k])
		skin_data.encode_u16(offset + per * 2 + k * 2, clampi(roundi(weights[v * per + k] * 65535.0), 0, 65535))


# --- the fingers ----------------------------------------------------------------------------

## Marks a mesh whose fingers have been merged, so it is never done twice.
const MITTEN_MARK := "fingers_merged"
## The share of a finger segment, either side of a joint, over which a vertex is handed from
## one bone to the next - so a bent joint creases rather than tears.
const JOINT_BLEND := 0.2


## Makes the four fingers of each hand bend together on the INDEX finger's joints, like a
## mitten, for a rig Mixamo gave only three finger chains.
##
## The elf archer was rigged as "3 chain fingers" (49 bones): thumb, index and middle. The
## index joints sit on the knuckles where they belong, but Mixamo put the middle chain out at
## the fingertips (its first joint three quarters of the way down the finger) and left the
## middle, ring and little fingers almost entirely on the Hand bone - so in every pose that
## closes the hand only the index finger curled, and the other three stood out straight. Here
## every vertex past the knuckles that the Hand or the middle chain held moves onto the index
## segment beside it (by how far along the hand it lies, blended across each joint). The
## thumb is left alone. Returns how many vertices changed, or -1 if already done.
static func mitten_fingers(mesh_node: MeshInstance3D, skeleton: Skeleton3D) -> int:
	var mesh: ArrayMesh = mesh_node.mesh as ArrayMesh
	if mesh == null or mesh_node.skin == null:
		return 0
	if mesh.has_meta(MITTEN_MARK):
		return -1
	var changed: int = 0
	for side: String in ["Left", "Right"]:
		changed += _mitten_mesh(mesh, mesh_node.skin, skeleton, side)
		if mesh.shadow_mesh is ArrayMesh:
			_mitten_mesh(mesh.shadow_mesh as ArrayMesh, mesh_node.skin, skeleton, side)
	if mesh.shadow_mesh is ArrayMesh:
		mesh.shadow_mesh.set_meta(MITTEN_MARK, true)
	mesh.set_meta(MITTEN_MARK, true)
	return changed


static func _mitten_mesh(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D, side: String) -> int:
	var prefix: String = "mixamorig_%sHand" % side
	var hand: int = skeleton.find_bone(prefix)
	var index: Array[int] = []
	for i in [1, 2, 3]:
		index.append(skeleton.find_bone("%sIndex%d" % [prefix, i]))
	if hand == -1 or index.has(-1):
		return 0
	# Bind index -> skeleton bone.
	var bind_bone: PackedInt32Array = PackedInt32Array()
	for b in skin.get_bind_count():
		var bind_name: String = skin.get_bind_name(b)
		bind_bone.append(skeleton.find_bone(bind_name) if bind_name != "" else skin.get_bind_bone(b))
	var index_bind: Array[int] = []
	for bone in index:
		index_bind.append(bind_bone.find(bone))
	if index_bind.has(-1):
		return 0
	# What moves: the Hand and the middle chain. What stays: the index and the thumb.
	var movable: Dictionary = {hand: true}
	for i in [1, 2, 3, 4]:
		var middle: int = skeleton.find_bone("%sMiddle%d" % [prefix, i])
		if middle != -1:
			movable[middle] = true
	var thumb: Dictionary = {}
	for i in [1, 2, 3, 4]:
		var bone: int = skeleton.find_bone("%sThumb%d" % [prefix, i])
		if bone != -1:
			thumb[bone] = true
	# Where along the hand (its own +Y, which runs down the fingers) each index joint sits.
	var hand_inverse: Transform3D = skeleton.get_bone_global_rest(hand).affine_inverse()
	var joints: Array[float] = []
	for bone in index:
		joints.append((hand_inverse * skeleton.get_bone_global_rest(bone).origin).y)
	var tip: int = skeleton.find_bone("%sIndex4" % prefix)
	var end: float = (hand_inverse * skeleton.get_bone_global_rest(tip).origin).y if tip != -1 else joints[2] + (joints[2] - joints[1])

	var storage: Array = mesh.get("_surfaces")
	var changed: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		var surface: Dictionary = storage[s]
		var skin_data: PackedByteArray = surface.get("skin_data", PackedByteArray())
		if skin_data.size() != verts.size() * per * 4:
			continue
		for v in verts.size():
			var base: int = v * per
			var rest := Vector3.ZERO
			var movable_weight: float = 0.0
			var on_thumb: bool = false
			for k in per:
				var w: float = weights[base + k]
				if w <= 0.0:
					continue
				var bone: int = bind_bone[bones[base + k]]
				rest += w * (skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(bones[base + k]) * verts[v])
				if movable.has(bone):
					movable_weight += w
				elif thumb.has(bone) and w > 0.05:
					on_thumb = true
			if movable_weight <= 0.001 or on_thumb:
				continue
			var along: float = (hand_inverse * rest).y
			# Nothing moves short of the knuckles; all of it a little past them.
			var knuckle_band: float = (joints[1] - joints[0]) * JOINT_BLEND
			var share: float = _ramp(along, joints[0] - knuckle_band, joints[0] + knuckle_band)
			if share <= 0.001:
				continue
			var moved: float = movable_weight * share
			# The weights of this vertex by bind, rebuilt with the moved share on the index.
			var by_bind: Dictionary = {}
			for k in per:
				var w: float = weights[base + k]
				if w <= 0.0:
					continue
				var bind: int = bones[base + k]
				var keep: float = w * (1.0 - share) if movable.has(bind_bone[bind]) else w
				by_bind[bind] = float(by_bind.get(bind, 0.0)) + keep
			var segments: Dictionary = _segment_shares(along, joints, end)
			for i: int in segments:
				var bind: int = index_bind[i]
				by_bind[bind] = float(by_bind.get(bind, 0.0)) + moved * float(segments[i])
			var ordered: Array = by_bind.keys()
			ordered.sort_custom(func(a: int, b: int) -> bool: return float(by_bind[a]) > float(by_bind[b]))
			var total: float = 0.0
			for k in mini(per, ordered.size()):
				total += float(by_bind[ordered[k]])
			for k in per:
				if k < ordered.size():
					bones[base + k] = int(ordered[k])
					weights[base + k] = float(by_bind[ordered[k]]) / maxf(total, 0.0001)
				else:
					bones[base + k] = 0
					weights[base + k] = 0.0
			_write_vertex(skin_data, v, per, bones, weights)
			changed += 1
		surface["skin_data"] = skin_data
		storage[s] = surface
	mesh.set("_surfaces", storage)
	return changed


## How a point `along` the hand splits between the three index segments (0, 1, 2): wholly the
## segment it lies on, blended into the next across JOINT_BLEND of a segment either side of
## each joint.
static func _segment_shares(along: float, joints: Array[float], end: float) -> Dictionary:
	var shares: Dictionary = {}
	var bounds: Array[float] = [joints[0], joints[1], joints[2], end]
	for joint in [1, 2]:
		var band: float = (bounds[joint] - bounds[joint - 1]) * JOINT_BLEND
		if along < bounds[joint] - band:
			shares[joint - 1] = 1.0
			return shares
		if along < bounds[joint] + band:
			var t: float = _ramp(along, bounds[joint] - band, bounds[joint] + band)
			shares[joint - 1] = 1.0 - t
			shares[joint] = t
			return shares
	shares[2] = 1.0
	return shares
