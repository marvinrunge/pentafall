@tool
extends EditorScenePostImport
## Import script for models Meshy exported faceted: every mesh in the imported scene comes out
## with smooth normals (tools/normal_smoother.gd - auto smooth, real creases kept). Set as
## `import_script/path` in the model's .import, so everything that loads the model - the
## character builders, a weapon instanced into a scene - gets the smooth one.
##
## Characters already built keep the copy saved in their scene; tools/smooth_scene_meshes.gd
## brings those in line.

const NormalSmoother = preload("res://tools/normal_smoother.gd")


func _post_import(scene: Node) -> Object:
	var nodes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		nodes.append(scene)
	for node: Node in nodes:
		var instance := node as MeshInstance3D
		if instance.mesh is ArrayMesh:
			instance.mesh = NormalSmoother.smooth(instance.mesh as ArrayMesh)
	return scene
