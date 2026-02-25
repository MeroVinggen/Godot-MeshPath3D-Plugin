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
	center_meshes: bool = false,
	optional_params: Dictionary[String, Variant] = {},
) -> Variant:
	var mesh_path: MeshPath3D = MeshPath3D.new()
	
	# -- setup path
	var path = Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(pos_from)
	path.curve.add_point(pos_to)
	mesh_path.path = path
	# no need to add the path as child node, it works
	
	# -- setup mehs & path
	mesh_path.meshes = meshes
	
	container.add_child(mesh_path)
	
	# -- setup additional params
	for param: String in optional_params:
		mesh_path[param] = optional_params[param]
	
	mesh_path.call_update_multimesh()
	
	await mesh_path.multimesh_updated
	
	if center_meshes:
		mesh_path.center_meshes()
		await mesh_path.multimesh_updated
	
	var bake_result: Variant = mesh_path[BAKE_METHOD_KEYS[bake_method]].call(container)
	
	mesh_path.queue_free()
	
	return bake_result


# @return {Dictionary[container: Node3D, bake: MeshInstance3D | Array[MeshInstance3D] 
#	| Array[Dictionary[
#		collision_body: CollisionObject3D,
#		collision_shape: CollisionShape3D,
#		mesh_instance: MeshInstance3D,
#	]]}
func generate_baked_mesh_path_vm(
	container: Node,
	bake_method: BAKE_METHOD,
	pos_from: Vector3, 
	pos_to: Vector3,
	template_lines: Array[MeshPath3D],
	center_meshes: bool = false,
	optional_params: Dictionary[String, Variant] = {},
) -> Variant:
	var mesh_path_vm: MeshPath3DVM = MeshPath3DVM.new()
	
	# -- setup path
	var path = Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(pos_from)
	path.curve.add_point(pos_to)
	mesh_path_vm.vertical_path = path
	# no need to add the path as child node, it works
	
	# -- setup lines
	mesh_path_vm.template_lines = template_lines
	
	# -- setup additional params
	for param: String in optional_params:
		mesh_path_vm[param] = optional_params[param]
	
	container.add_child(mesh_path_vm)
	
	await mesh_path_vm.vertical_multimesh_updated
	
	if center_meshes:
		mesh_path_vm.call_center_all_lines_meshes()
		await mesh_path_vm.centering_finished
	
	var bake_result: Variant = mesh_path_vm[BAKE_METHOD_KEYS[bake_method]].call(container)
	
	mesh_path_vm.queue_free()
	
	return bake_result


# @return {Dictionary[container: Node3D, bake: MeshInstance3D | Array[MeshInstance3D] 
#	| Array[Dictionary[
#		collision_body: CollisionObject3D,
#		collision_shape: CollisionShape3D,
#		mesh_instance: MeshInstance3D,
#	]]}
func generate_baked_mesh_path_vm_with_lines(
	container: Node,
	bake_method: BAKE_METHOD,
	pos_from: Vector3, 
	pos_to: Vector3,
	template_lines_params: Array[Dictionary],
	center_meshes: bool = false,
	optional_params: Dictionary[String, Variant] = {},
) -> Variant:
	var meshPath_nodes: Array[MeshPath3D] = []
	var meshPath_tmp: MeshPath3D
	var path_tmp: Path3D
	var path_start_point: Vector3
	var path_end_point: Vector3
	
	for line_params: Dictionary[String, Variant] in template_lines_params:
		meshPath_tmp = MeshPath3D.new()
		
		# all path points will be shifted, coz meshPath pos will be Vector3.ZERO and path is relative to it
		path_start_point = line_params.path_from if line_params.has("path_from") else Vector3.ZERO
		path_end_point = (line_params.path_to if line_params.has("path_to") else Vector3(5.0, 0.0, 0.0)) - path_start_point
		
		path_tmp = Path3D.new()
		path_tmp.curve = Curve3D.new()
		path_tmp.curve.add_point(Vector3.ZERO)
		path_tmp.curve.add_point(path_end_point)
		meshPath_tmp.path = path_tmp
		meshPath_tmp.path_length = path_tmp.curve.get_baked_length()
		
		# using assign to beat the typing check
		var meshes: Array[Mesh] = []
		meshes.assign(line_params.meshes)
		meshPath_tmp.meshes = meshes
		line_params.erase("meshes")
		line_params.erase("path_from")
		line_params.erase("path_to")
		
		for param: String in line_params:
			meshPath_tmp[param] = line_params[param]
		
		meshPath_nodes.append(meshPath_tmp)
	
	var bake_result: Dictionary = await MeshPath3D_utils.generate_baked_mesh_path_vm(
		container,
		MeshPathUtils.BAKE_METHOD.bake_multiple_with_collision,
		pos_from,
		pos_to,
		meshPath_nodes,
		center_meshes,
		optional_params,
	)
	
	return bake_result


#func align_bake_at_bottom_by_box_shape(result: Dictionary, ground_shape: CollisionShape3D, vertical_wall: bool) -> void:
	#var baked = result.get("baked")
	#if not baked is Array: return
	#
	#var ground_box: BoxShape3D = ground_shape.shape as BoxShape3D
	#if not ground_box: return
	#
	#var ground_top_y: float = ground_shape.global_position.y + ground_box.size.y * 0.5
	#
	#if vertical_wall:
		## Find lowest shape, apply same offset to all
		#var min_bottom_y: float = INF
		#for item in baked:
			#if not item is Dictionary: continue
			#var shape: CollisionShape3D = item.get("collision_shape")
			#if not shape or not shape.shape is BoxShape3D: continue
			#var box: BoxShape3D = shape.shape
			#min_bottom_y = min(min_bottom_y, shape.global_position.y - box.size.y * 0.5)
		#
		#if min_bottom_y == INF: return
		#
		#var diff_y: float = ground_top_y - min_bottom_y
		#for item in baked:
			#if not item is Dictionary: continue
			#var body: Node3D = item.get("collision_body")
			#if body: body.global_position.y += diff_y
	#else:
		## Align each shape individually
		#for item in baked:
			#if not item is Dictionary: continue
			#var shape: CollisionShape3D = item.get("collision_shape")
			#var body: Node3D = item.get("collision_body")
			#if not shape or not body or not shape.shape is BoxShape3D: continue
			#var box: BoxShape3D = shape.shape
			#var diff_y: float = ground_top_y + box.size.y * 0.5 - shape.global_position.y
			#body.global_position.y += diff_y


func align_bake_at_bottom_by_pos(result: Dictionary, ground_y: float, vertical_wall: bool = false) -> void:
	var baked = result.get("baked")
	if not baked is Array: return
	
	if vertical_wall:
		var min_bottom_y: float = INF
		for item in baked:
			if not item is Dictionary: continue
			var shape: CollisionShape3D = item.get("collision_shape")
			if not shape or not shape.shape is BoxShape3D: continue
			var box: BoxShape3D = shape.shape
			min_bottom_y = min(min_bottom_y, shape.global_position.y - box.size.y * 0.5)
		
		if min_bottom_y == INF: return
		
		var diff_y: float = ground_y - min_bottom_y
		for item in baked:
			if not item is Dictionary: continue
			var body: Node3D = item.get("collision_body")
			if body: body.global_position.y += diff_y
	else:
		for item in baked:
			if not item is Dictionary: continue
			var shape: CollisionShape3D = item.get("collision_shape")
			var body: Node3D = item.get("collision_body")
			if not shape or not body or not shape.shape is BoxShape3D: continue
			var box: BoxShape3D = shape.shape
			body.global_position.y = ground_y + box.size.y * 0.5
