@tool
extends Node
class_name MeshPathUtils

enum BAKE_METHOD {
	bake_single,
	bake_multiple,
	bake_multiple_with_collision,
}

# @param {Array[String]}
var BAKE_METHOD_KEYS: Array = BAKE_METHOD.keys()


# @return {Dictionary[container: Node3D, bake: MeshInstance3D | Array[MeshInstance3D] 
#	| Array[Dictionary[
#		collision_body: CollisionObject3D,
#		collision_shape: CollisionShape3D,
#		mesh_instance: MeshInstance3D,
#	]]}
func generate_baked_mesh_path(
	container: Node,
	bake_method: BAKE_METHOD,
	pos_from: Vector3, 
	pos_to: Vector3,
	meshes: Array[Mesh],
	optional_params: Dictionary[String, Variant] = {},
) -> Variant:
	var mesh_path: MeshPath3D = MeshPath3D.new()
	
	# -- setup path
	var path = Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(pos_from)
	path.curve.add_point(pos_to)
	mesh_path.path = path
	# no need to add path a child not, it works
	
	# -- setup mehs & path
	mesh_path.meshes = meshes
	
	# -- setup additional params
	for param: String in optional_params:
		mesh_path[param] = optional_params[param]
	
	container.add_child(mesh_path)
	
	mesh_path.call_update_multimesh()
	
	await mesh_path.multimesh_updated
	
	var bake_result: Variant = mesh_path[BAKE_METHOD_KEYS[bake_method]].call()
	
	mesh_path.queue_free()
	
	return bake_result
