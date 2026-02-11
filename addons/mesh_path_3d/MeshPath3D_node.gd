@tool
extends Node3D
class_name MeshPath3D

signal multimesh_updated()

@export_group("Utils")

@export_tool_button("randomize") var randomize_mesh_btn: Callable = randomize_meshes
@export_tool_button("re-render") var update_btn: Callable = call_update_multimesh
@export_tool_button("clear") var clear_mesh_btn: Callable = clear_meshes
@export_tool_button("center meshes") var center_meshes_btn: Callable = center_meshes

@export_group("Bake")

@export_tool_button("bake single") var bake_sigle_mesh_btn: Callable = bake_single
@export_tool_button("bake multiple") var bake_multiple_mesh_btn: Callable = bake_multiple
@export_tool_button("bake multiple with collision") var bake_multiple_collision_btn = bake_multiple_with_collision
@export var bake_in_single_sub_container: bool = false
@export var bake_in_separate_sub_containers: bool = false
@export var bake_as_sibling: bool = false

@export_group("Material")

@export var material: Material:
	set(value):
		material = value
		_setup_material_and_processor()
		call_update_multimesh()

@export_group("Path")

@export var path: Path3D:
	set(value):
		if path != value:
			if path and path.curve and path.curve.is_connected("changed", _on_path_changed):
				path.curve.changed.disconnect(_on_path_changed)
			path = value
			if path and path.curve and not path.curve.is_connected("changed", _on_path_changed):
				path.curve.changed.connect(_on_path_changed)
			call_update_multimesh()
@export var path_length: float = 2.0:
	set(value):
		if value == 0:
			return
		path_length = value
		# prevent warn from the func 
		if is_node_ready():
			set_path_length()
@export_tool_button("center path") var center_path_btn = center_curve_to_path
@export_tool_button("setup default path") var setup_default_path_btn = setup_default_path

@export_group("Meshes")

@export var meshes: Array[Mesh] = []:
	set(value):
		meshes = value
		clear_meshes()
		_on_meshes_array_updated()
		call_update_multimesh()
@export var allow_partial: bool = true:
	set(value):
		allow_partial = value
		call_update_multimesh()
@export var random_pick: bool = false:
	set(value):
		random_pick = value

@export_group("Spacing")

@export var gap_min: float = 0.5:
	set(value):
		gap_min = value
		call_update_multimesh()
@export var gap_max: float = -1.0:
	set(value):
		gap_max = value
		call_update_multimesh()
@export var start_margin: float = 0.0:
	set(value):
		start_margin = value
		call_update_multimesh()
@export var end_margin: float = 0.0:
	set(value):
		end_margin = value
		call_update_multimesh()

@export_group("Collision")

enum COLLISION_TYPE {
	staticBody,
	animatableBody,
	characterBody,
	rigidBody,
	area,
}

@export var collision_type: COLLISION_TYPE
@export_tool_button("bake single collision") var add_collision_btn = add_single_collision
@export_tool_button("bake multiple collision") var add_multiple_collision_btn = add_multiple_collision

@export_group("Transform")

# ---- auto rotation by path

@export var mesh_face_path_x: bool = true:
	set(value):
		mesh_face_path_x = value
		call_update_multimesh()
@export var mesh_face_path_y: bool = true:
	set(value):
		mesh_face_path_y = value
		call_update_multimesh()
@export var mesh_face_path_z: bool = true:
	set(value):
		mesh_face_path_z = value
		call_update_multimesh()

# ---- flip
@export var random_flip_x: bool = false
@export var random_flip_y: bool = false
@export var random_flip_z: bool = false

# ---- rotation
@export var mesh_rotation: Vector3 = Vector3.ZERO:
	set(value):
		mesh_rotation = value
		call_update_multimesh()
@export var random_rotation: bool = false
@export var mesh_rotation2: Vector3 = Vector3.ZERO:
	set(value):
		mesh_rotation2 = value

# ---- offset
@export var mesh_offset: Vector3 = Vector3.ZERO:
	set(value):
		mesh_offset = value
		call_update_multimesh()
@export var random_offset: bool = false
@export var mesh_offset2: Vector3 = Vector3.ZERO:
	set(value):
		mesh_offset2 = value

# ---- scale
@export var mesh_scale: Vector3 = Vector3.ONE:
	set(value):
		mesh_scale = value
		call_update_multimesh()
@export var random_scale: bool = false
@export var random_uniform_scale: bool = false
@export var mesh_scale2: Vector3 = Vector3.ZERO:
	set(value):
		mesh_scale2 = value

@export_storage var _mesh_transforms: Array[Transform3D] = []
@export_storage var _placed_meshes: Array[Mesh] = []
@export_storage var _placed_meshes_rotation: Array[Basis] = []
@export_storage var _placed_meshes_offset: Array[Vector3] = []
@export_storage var _placed_meshes_scale: Array[Basis] = []
@export_storage var _last_ordered_index: int = -1
@export_storage var _last_random_index: int = -1
@export_storage var _placed_meshes_gaps: Array[float] = []
@export_storage var _cached_aabb: AABB
@export_storage var _mesh_base_aabbs: Dictionary[Mesh, AABB] = {}

@export_group("Internal")

# godot might trigger some of the setters fire times even on 1 change
## physics frames to wait till next update after update been called, skip 2 frames is optimal
@export var multimesh_update_rate: int = 2

@export_group("")

@export var processor: MeshPath3DProcessor:
	set(value):
		if processor and processor.changed.is_connected(_on_processor_changed):
			processor.changed.disconnect(_on_processor_changed)
		
		processor = value
		
		if processor and not processor.changed.is_connected(_on_processor_changed):
			processor.changed.connect(_on_processor_changed)
		
		_setup_material_and_processor()
		call_update_multimesh()

# mmi - MultiMeshInstance3D
var _mesh_to_mmi_map: Dictionary[Mesh, MultiMeshInstance3D] = {}
var _shedule_multimesh_update: bool = false

var _passed_frames: int = 0


func _physics_process(_delta: float) -> void:
	if not _shedule_multimesh_update:
		return 
		
	_passed_frames += 1
	if _passed_frames == multimesh_update_rate:
		_shedule_multimesh_update = false
		_passed_frames = 0
		_update_multimesh()


func _ready() -> void:
	_on_meshes_array_updated()
	if Engine.is_editor_hint():
		if path and path.curve and not path.curve.is_connected("changed", _on_path_changed):
			path.curve.changed.connect(_on_path_changed)
		call_update_multimesh()
	else:
		call_deferred("call_update_multimesh")


func get_cached_aabb() -> AABB: 
	return _cached_aabb


func get_height() -> float: 
	return _cached_aabb.size.y


func _on_path_changed() -> void:
	path.curve.changed.disconnect(_on_path_changed)
	path_length = path.curve.get_baked_length()
	call_update_multimesh()
	path.curve.changed.connect(_on_path_changed)


func call_update_multimesh() -> void:
	_shedule_multimesh_update = true


func _update_multimesh() -> void:
	clear_rendered_data()
	
	if not path or not path.curve or meshes.is_empty():
		return
	
	var curve: Curve3D = path.curve
	var curve_length: float = curve.get_baked_length()
	
	if curve_length == 0:
		return
	
	var mesh_data: Array[Dictionary] = []
	var current_distance: float = start_margin
	var i: int = 0
	var mesh: Mesh
	var mesh_is_old: bool = false
	var meshes_size: int = meshes.size()
	
	while current_distance < curve_length - end_margin:
		# Use existing mesh
		if i < _placed_meshes.size():
			mesh = _placed_meshes[i]
			mesh_is_old = true
			if not random_pick:
				_last_ordered_index = meshes.find(mesh)
		# add new mesh
		else:
			# Pick next mesh (don't check if it fits!)
			var mesh_index: int
			if not random_pick:
				_last_ordered_index = (_last_ordered_index + 1) % meshes_size
				mesh_index = _last_ordered_index
			else:
				if _last_random_index == -1:
					_last_random_index = randi() % meshes_size
				mesh_index = _last_random_index
			
			mesh = meshes[mesh_index]
			mesh_is_old = false
		
		if not mesh:
			break
		
		# ---- scale (process before calc the placement_distance!)
		var scale_basis: Basis
		
		if mesh_is_old:
			scale_basis = _placed_meshes_scale[i]
		elif random_scale:
			if random_uniform_scale:
				var scale_factor: float = randf_range(mesh_scale.x, mesh_scale2.x)
				scale_basis = Basis.from_scale(Vector3(
					scale_factor,
					scale_factor,
					scale_factor
				))
			else:
				scale_basis = Basis.from_scale(
					_get_random_vector3(mesh_scale, mesh_scale2)
				)
				# add to scal arr below (after checks fro continue & break)
		else:
			scale_basis = Basis.from_scale(mesh_scale)
			# add to scal arr below (after checks fro continue & break)
		
		# ---- rotation & flip
		var rotation_basis: Basis
		
		# -- flip
		var initial_mesh_rotation_x: float = deg_to_rad(180) if random_flip_x and randi_range(0, 1) else 0
		var initial_mesh_rotation_y: float = deg_to_rad(180) if random_flip_y and randi_range(0, 1) else 0
		var initial_mesh_rotation_z: float = deg_to_rad(180) if random_flip_z and randi_range(0, 1) else 0
		# will be added to mesh rotation range start/end
		var initial_mesh_rotation: Vector3 = Vector3(
			initial_mesh_rotation_x,
			initial_mesh_rotation_y,
			initial_mesh_rotation_z,
		)
		
		if mesh_is_old:
			rotation_basis = _placed_meshes_rotation[i]
		elif random_rotation:
			rotation_basis = Basis.from_euler(
				_get_random_vector3(_covert_rotation_to_rad(mesh_rotation) + initial_mesh_rotation, _covert_rotation_to_rad(mesh_rotation2) + initial_mesh_rotation)
			)
		else:
			rotation_basis = Basis.from_euler(_covert_rotation_to_rad(mesh_rotation) + initial_mesh_rotation)
		
		var aabb: AABB = _mesh_base_aabbs[mesh]

		var temp_transform: Transform3D = Transform3D()
		temp_transform.basis = rotation_basis * scale_basis
		var rotated_aabb: AABB = temp_transform * aabb

		var back_offset: float
		var front_offset: float
		var mesh_length: float

		# If fully facing path, use simple Z calculation
		if mesh_face_path_x and mesh_face_path_y and mesh_face_path_z:
			back_offset = rotated_aabb.position.z
			front_offset = rotated_aabb.end.z
			mesh_length = front_offset - back_offset
		else:
			# Project all 8 corners for non-facing
			var curve_forward: Vector3 = curve.sample_baked_with_rotation(current_distance).basis.z
			var corners: Array = []
			for x in [rotated_aabb.position.x, rotated_aabb.end.x]:
				for y in [rotated_aabb.position.y, rotated_aabb.end.y]:
					for z in [rotated_aabb.position.z, rotated_aabb.end.z]:
						corners.append(temp_transform.basis * Vector3(x, y, z))
			
			var projections: Array = corners.map(func(c): return c.dot(curve_forward))
			back_offset = projections.min()
			front_offset = projections.max()
			mesh_length = front_offset - back_offset
		
		var placement_distance: float = current_distance - back_offset
		
		# If doesn't fit and allow_partial is off, leave gap and continue
		if placement_distance + front_offset > curve_length - end_margin and not allow_partial:
			current_distance += mesh_length + gap_min
			if not random_pick:
				i += 1
			continue
		
		# If starting position is past curve, stop (for both modes)
		if current_distance > curve_length - end_margin:
			break
		
		var curve_transform: Transform3D = curve.sample_baked_with_rotation(placement_distance)
		var curve_position: Vector3 = curve_transform.origin

		var curve_euler: Vector3 = curve_transform.basis.get_euler()

		var filtered_euler: Vector3 = Vector3(
			curve_euler.x if mesh_face_path_x else 0,
			curve_euler.y if mesh_face_path_y else 0,
			curve_euler.z if mesh_face_path_z else 0
		)

		var transform_3d: Transform3D = Transform3D()
		
		# ---- offset
		var mesh_offset_value: Vector3
		
		if mesh_is_old:
			mesh_offset_value = _placed_meshes_offset[i]
		elif random_offset:
			mesh_offset_value = _get_random_vector3(mesh_offset, mesh_offset2)
		else:
			mesh_offset_value = mesh_offset
		
		transform_3d.basis = Basis.from_euler(filtered_euler) * rotation_basis * scale_basis
		transform_3d.origin = curve_position
		transform_3d.origin += curve_transform.basis * mesh_offset_value if mesh_offset_value else Vector3.ZERO
		
		_mesh_transforms.append(transform_3d)
		
		mesh_data.append({
			"mesh": mesh,
			"transform": transform_3d
		})
		
		if not mesh_is_old:
			_placed_meshes.append(mesh)
			_placed_meshes_rotation.append(rotation_basis)
			_placed_meshes_offset.append(mesh_offset_value)
			_placed_meshes_scale.append(scale_basis)
			
			if random_pick:
				_last_random_index = -1
		
		var gap_value: float
		if mesh_is_old:
			gap_value = _placed_meshes_gaps[i]
		else:
			gap_value = gap_min if gap_max < 0 else randf_range(gap_min, gap_max)
			_placed_meshes_gaps.append(gap_value)

		print("i=%d, mesh=%s, current_distance=%.2f, back_offset=%.2f, front_offset=%.2f, mesh_length=%.2f, gap=%.2f" % [i, mesh.resource_path.get_file(), current_distance, back_offset, front_offset, mesh_length, gap_value])
		print("  -> placement_distance=%.2f" % placement_distance)
		print("  -> actual_end_position=%.2f (should match next current_distance)" % (placement_distance + front_offset))
		print("  -> back_face_position=%.2f" % (placement_distance + back_offset))
		
		current_distance += mesh_length + gap_value
		i += 1
	
	# Trim excess meshes
	while _placed_meshes.size() > i:
		_placed_meshes.pop_back()
		_placed_meshes_rotation.pop_back()
		_placed_meshes_offset.pop_back()
		_placed_meshes_scale.pop_back()
		_placed_meshes_gaps.pop_back()
	
	# Group by mesh
	var mesh_groups: Dictionary = {}
	for data in mesh_data:
		if not mesh_groups.has(data.mesh):
			mesh_groups[data.mesh] = []
		mesh_groups[data.mesh].append(data.transform)
	
	# add meshes to MultiMeshInstance3D
	for mesh_ in mesh_groups.keys():
		var transforms: Array = mesh_groups[mesh_]
		
		_mesh_to_mmi_map[mesh_].multimesh.instance_count = transforms.size()
		
		for j in range(transforms.size()):
			_mesh_to_mmi_map[mesh_].multimesh.set_instance_transform(j, transforms[j])
			if processor:
				processor.process_mesh(_mesh_to_mmi_map[mesh_].multimesh, j)
	
	# Calculate combined AABB
	if not _mesh_transforms.is_empty():
		_cached_aabb = _calculate_combined_aabb()
	else:
		_cached_aabb = AABB()
	
	multimesh_updated.emit()


func bake_single(parent_ref: Node = null) -> Dictionary[String, Variant]:
	if _placed_meshes.is_empty():
		push_warning("No meshes to bake!")
		return {}
	
	var surface_tool: SurfaceTool = SurfaceTool.new()
	var baked_mesh: ArrayMesh = ArrayMesh.new()
	
	# Use _mesh_transforms which matches _placed_meshes in order
	for i in range(min(_placed_meshes.size(), _mesh_transforms.size())):
		var mesh: Mesh = _placed_meshes[i]
		var mesh_transform: Transform3D = _mesh_transforms[i]
		
		if not mesh:
			continue
		
		for surface_idx in range(mesh.get_surface_count()):
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			
			var arrays: Array = mesh.surface_get_arrays(surface_idx)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] else null
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			
			for j in range(vertices.size()):
				if normals:
					surface_tool.set_normal(mesh_transform.basis * normals[j])
				if uvs:
					surface_tool.set_uv(uvs[j])
				surface_tool.add_vertex(mesh_transform * vertices[j])
			
			if indices:
				for idx in indices:
					surface_tool.add_index(idx)
			
			surface_tool.commit(baked_mesh)
	
	var baked_instance: MeshInstance3D = MeshInstance3D.new()
	baked_instance.mesh = baked_mesh
	baked_instance.name = name + "_Baked"
	baked_instance.material_override = material

	if processor:
		processor.process_bake_single(baked_instance, material)
	
	var container: Node3D = _get_container(parent_ref)
	
	if bake_in_separate_sub_containers:
		var sub_container: Node3D = _create_container(container)
		sub_container.add_child(baked_instance)
	else:
		container.add_child(baked_instance)
	
	baked_instance.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	baked_instance.global_transform = global_transform
	
	return {
		"container": container,
		"baked": baked_instance,
	}


func bake_multiple(parent_ref: Node = null) -> Dictionary[String, Variant]:
	if _placed_meshes.is_empty():
		push_warning("No meshes to bake!")
		return {}
	
	var parent_node: Node = get_parent() if bake_as_sibling else self
	if parent_ref:
		parent_node = parent_ref
	
	var main_container: Node
	if bake_in_single_sub_container:
		main_container = _create_container(parent_node)
	else:
		main_container = parent_node
	
	var baked: Array[MeshInstance3D] = []
	
	for i in range(min(_placed_meshes.size(), _mesh_transforms.size())):
		var mesh: Mesh = _placed_meshes[i]
		if not mesh:
			continue
		
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.name = "Mesh_" + str(i)
		mesh_instance.transform = _mesh_transforms[i]
		mesh_instance.material_override = material
		
		if processor:
			processor.process_bake_multiple(mesh_instance, material, _mesh_to_mmi_map[mesh])
		
		var container: Node = main_container
		if bake_in_separate_sub_containers:
			container = _create_container(main_container)
		
		container.add_child(mesh_instance)
		mesh_instance.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		baked.append(mesh_instance)
	
	return {
		"container": main_container,
		"baked": baked,
	}


func randomize_meshes() -> void:
	var prev_prop_val: bool = random_pick
	clear_meshes()
	random_pick = true # enable for next `call_update_multimesh` call
	call_update_multimesh()
	await multimesh_updated
	random_pick = prev_prop_val # return prev value


# total data clear
func clear_meshes() -> void:
	_last_ordered_index = -1
	_last_random_index = -1
	_placed_meshes.clear()
	_placed_meshes_rotation.clear()
	_placed_meshes_offset.clear()
	_placed_meshes_scale.clear()
	_placed_meshes_gaps.clear()
	
	clear_rendered_data()

# clear only rendered instances from scene (calculated transform), but not their data
func clear_rendered_data() -> void:
	_mesh_transforms.clear()
	
	for mmi in _mesh_to_mmi_map.values():
		mmi.multimesh.instance_count = 0


func _get_random_vector3(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(
		randf_range(from.x, to.x),
		randf_range(from.y, to.y),
		randf_range(from.z, to.z)
	)


func _covert_rotation_to_rad(rotation: Vector3) -> Vector3:
	return Vector3(
		deg_to_rad(rotation.x),
		deg_to_rad(rotation.y),
		deg_to_rad(rotation.z),
	)


func set_path_length() -> void:
	if not path or not path.curve or path.curve.point_count < 2:
		push_warning("require path with curve and at least 2 points")
		return
	
	var current_length: float = path.curve.get_baked_length()
	if current_length == 0:
		return
	
	var scale_factor: float = path_length / current_length
	
	# Keep first point fixed, scale all others from it
	var first_point: Vector3 = path.curve.get_point_position(0)
	
	for i in range(1, path.curve.point_count):
		var point: Vector3 = path.curve.get_point_position(i)
		var offset: Vector3 = point - first_point
		path.curve.set_point_position(i, first_point + offset * scale_factor)


func center_curve_to_path() -> void:
	if not path or not path.curve or path.curve.point_count < 2:
		push_warning("require path with curve and at least 2 point")
		return
	
	# Calculate average of all points
	var sum: Vector3 = Vector3.ZERO
	for i in range(path.curve.point_count):
		sum += path.curve.get_point_position(i)
	var centroid: Vector3 = sum / float(path.curve.point_count)
	
	# Offset all points so centroid becomes (0,0,0)
	for i in range(path.curve.point_count):
		path.curve.set_point_position(i, path.curve.get_point_position(i) - centroid)


func setup_default_path() -> void:
	if path:
		path.curve.clear_points()
		path.curve.add_point(Vector3.ZERO)
		path.curve.add_point(Vector3(1, 0, 0))
	else:
		var new_path: Path3D = Path3D.new()
		
		new_path.curve = Curve3D.new()
		new_path.curve.add_point(Vector3.ZERO)
		new_path.curve.add_point(Vector3(1, 0, 0))
		
		path = new_path
		add_child(path)
		new_path.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner


func _create_collision_body(parent_node: Node) -> CollisionObject3D:
	var collision_body: CollisionObject3D
	
	match collision_type:
		COLLISION_TYPE.staticBody:
			collision_body = StaticBody3D.new()
		COLLISION_TYPE.animatableBody:
			collision_body = AnimatableBody3D.new()
		COLLISION_TYPE.characterBody:
			collision_body = CharacterBody3D.new()
		COLLISION_TYPE.rigidBody:
			collision_body = RigidBody3D.new()
		COLLISION_TYPE.area:
			collision_body = Area3D.new()
	
	parent_node.add_child(collision_body)
	collision_body.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	
	return collision_body


func _create_collision_shape(box_size: Vector3, parent_node: CollisionObject3D) -> CollisionShape3D:
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	collision_shape.shape = box
	
	parent_node.add_child(collision_shape)
	collision_shape.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	
	return collision_shape


#func add_single_collision(parent_ref: Node = null) -> void:
	#if _mesh_transforms.is_empty():
		#push_warning("No meshes placed")
		#return
	#
	#var collision_body: CollisionObject3D = _create_collision_body(_get_container(parent_ref))
	#var combined_aabb: AABB = _calculate_combined_aabb()
	#
	#var collision_shape: CollisionShape3D = _create_collision_shape(combined_aabb.size, collision_body)
	#collision_shape.position = combined_aabb.get_center()

func add_single_collision(parent_ref: Node = null) -> void:
	if _mesh_transforms.is_empty():
		push_warning("No meshes placed")
		return
	
	var container: Node = _get_container(parent_ref)
	
	# Add this block for separate containers:
	if bake_in_separate_sub_containers:
		var sub_container: Node3D = _create_container(container)
		container = sub_container
	
	var collision_body: CollisionObject3D = _create_collision_body(container)
	var combined_aabb: AABB = _calculate_combined_aabb()
	
	var collision_shape: CollisionShape3D = _create_collision_shape(combined_aabb.size, collision_body)
	collision_shape.position = combined_aabb.get_center()

func add_multiple_collision(parent_ref: Node = null) -> void:
	if _mesh_transforms.is_empty():
		push_warning("No meshes placed")
		return
	
	var parent_node: Node = get_parent() if bake_as_sibling else self
	if parent_ref:
		parent_node = parent_ref
	
	var main_container: Node
	if bake_in_single_sub_container:
		main_container = _create_container(parent_node)
	else:
		main_container = parent_node
	
	# Create collision shape per mesh
	for i in range(min(_placed_meshes.size(), _mesh_transforms.size())):
		var mesh: Mesh = _placed_meshes[i]
		if not mesh:
			continue
		
		var mesh_aabb: AABB = _mesh_base_aabbs[mesh]
		var mesh_transform: Transform3D = _mesh_transforms[i]
		
		var container: Node = main_container
		if bake_in_separate_sub_containers:
			container = _create_container(main_container)
		
		var collision_body: CollisionObject3D = _create_collision_body(container)
		collision_body.global_position = global_position + mesh_transform.origin + mesh_transform.basis * mesh_aabb.get_center()
		
		var collision_shape: CollisionShape3D = _create_collision_shape(mesh_aabb.size, collision_body)
		collision_shape.basis = mesh_transform.basis
		collision_shape.position = Vector3.ZERO


func _on_meshes_array_updated() -> void:
	# adding new mmi
	for mesh in meshes:
		if not mesh or _mesh_to_mmi_map.has(mesh):
			continue
		else:
			_mesh_base_aabbs[mesh] = mesh.get_aabb()
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			_update_material_and_processor(mmi)
			add_child(mmi)
			mmi.set_meta("_edit_lock_", true)
			
			var mm: MultiMesh = MultiMesh.new()
			mm.instance_count = 0
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			
			mmi.multimesh = mm
			_mesh_to_mmi_map[mesh] = mmi
	
	# removing mmi for removed meshes
	for mesh in _mesh_to_mmi_map:
		if not meshes.has(mesh):
			_mesh_to_mmi_map.erase(mesh)
			_mesh_base_aabbs.erase(mesh)


func _setup_material_and_processor() -> void:
	for mmi in _mesh_to_mmi_map.values():
		_update_material_and_processor(mmi)


func _update_material_and_processor(mmi: MultiMeshInstance3D) -> void:
	mmi.material_override = material
	if processor:
		processor.process_multimesh(mmi)


# for processor updated props
func _on_processor_changed() -> void:
	_setup_material_and_processor()
	call_update_multimesh()


func bake_multiple_with_collision(parent_ref: Node = null) -> Dictionary[String, Variant]:
	if _placed_meshes.is_empty():
		push_warning("No meshes to bake!")
		return {}
	
	var baked: Array[Dictionary] = []
	var container: Node = _get_container(parent_ref)
	var sub_container: Node3D
	
	for i in range(min(_placed_meshes.size(), _mesh_transforms.size())):
		var mesh: Mesh = _placed_meshes[i]
		if not mesh:
			continue
		
		var mesh_aabb: AABB = _mesh_base_aabbs[mesh]
		var mesh_transform: Transform3D = _mesh_transforms[i]
		
		# Create collision body at mesh position
		var collision_body: CollisionObject3D
		
		if bake_in_separate_sub_containers:
			sub_container = _create_container(container)
			collision_body = _create_collision_body(sub_container)
		else:
			sub_container = null
			collision_body = _create_collision_body(container)
		
		collision_body.position = mesh_transform.origin + mesh_transform.basis * mesh_aabb.get_center()
		
		# Create collision shape
		var collision_shape: CollisionShape3D = _create_collision_shape(mesh_aabb.size, collision_body)
		collision_shape.basis = mesh_transform.basis
		collision_shape.position = Vector3.ZERO
		
		# Create mesh instance as child
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.name = "Mesh_" + str(i)
		mesh_instance.basis = mesh_transform.basis
		mesh_instance.position = mesh_transform.basis * -mesh_aabb.get_center()
		mesh_instance.material_override = material
		
		if processor:
			processor.process_bake_multiple_with_collision(mesh_instance, collision_body, collision_shape, sub_container, material, _mesh_to_mmi_map[mesh])
		
		collision_body.add_child(mesh_instance)
		mesh_instance.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		
		baked.append({
			"sub_container": sub_container,
			"collision_body": collision_body,
			"collision_shape": collision_shape,
			"mesh_instance": mesh_instance,
		})
	
	return {
		"container": container,
		"baked": baked,
	}


func _create_container(parent_node: Node) -> Node3D:
	var container: Node3D = Node3D.new()
	parent_node.add_child(container)
	container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	container.global_transform = global_transform
	return container


func _get_container(parent_ref: Node = null) -> Node:
	var container: Node
	var parent_node: Node
	
	if parent_ref:
		parent_node = parent_ref
	else:
		parent_node = get_parent() if bake_as_sibling else self
	
	if bake_in_single_sub_container:
		container = _create_container(parent_node)
	else:
		container = parent_node
	
	return container


func _calculate_combined_aabb() -> AABB:
	if _mesh_transforms.is_empty() or _placed_meshes.is_empty():
		return AABB()
	
	var combined_aabb: AABB
	for i in range(min(_placed_meshes.size(), _mesh_transforms.size())):
		var mesh: Mesh = _placed_meshes[i]
		if not mesh:
			continue
		var mesh_aabb: AABB = _mesh_base_aabbs[mesh]
		var transformed_aabb: AABB = _mesh_transforms[i] * mesh_aabb
		if i == 0:
			combined_aabb = transformed_aabb
		else:
			combined_aabb = combined_aabb.merge(transformed_aabb)
	return combined_aabb


func center_meshes() -> void:
	if not path or not path.curve or _placed_meshes.is_empty() or _placed_meshes_gaps.is_empty():
		push_warning("Requires path and placed meshes")
		return
	
	var curve_length: float = path.curve.get_baked_length()
	
	# Sum up actual mesh lengths and gaps from the placement arrays
	var total_content: float = 0.0
	
	# Add all mesh lengths (using the same calculation as placement)
	for i in range(_placed_meshes.size()):
		var mesh: Mesh = _placed_meshes[i]
		if not mesh:
			continue
		
		var aabb: AABB = _mesh_base_aabbs[mesh]
		var temp_transform: Transform3D = Transform3D()
		temp_transform.basis = _placed_meshes_rotation[i] * _placed_meshes_scale[i]
		var rotated_aabb: AABB = temp_transform * aabb
		
		# Calculate mesh length along path
		var mesh_length: float = rotated_aabb.end.z - rotated_aabb.position.z
		total_content += mesh_length
	
	# Add all gaps
	for gap in _placed_meshes_gaps:
		total_content += gap
	
	# Remove the last gap (there's no gap after the last mesh)
	if not _placed_meshes_gaps.is_empty():
		total_content -= _placed_meshes_gaps[_placed_meshes_gaps.size() - 1]
	
	# Calculate centering margin
	var free_space: float = curve_length - total_content
	start_margin = max(0, free_space / 2.0)
	end_margin = max(0, free_space / 2.0)
	
	call_update_multimesh()
