@tool
extends Node3D
class_name MeshPath3DVM

signal vertical_multimesh_updated()

@export_group("Utils")

@export_tool_button("randomize lines") var randomize_lines_btn: Callable = randomize_lines
@export_tool_button("randomize meshes") var randomize_meshes_btn: Callable = randomize_meshes
#@export_tool_button("re-render all") var update_all_btn: Callable = call_re_render_all

@export_group("Bake")

@export_tool_button("bake single") var bake_single_btn: Callable = bake_single
@export_tool_button("bake multiple") var bake_multiple_btn: Callable = bake_multiple
@export_tool_button("bake multiple with collision") var bake_multiple_collision_btn = bake_multiple_with_collision
@export var bake_in_single_sub_container: bool = false
@export var bake_in_separate_sub_containers: bool = false
@export var bake_as_sibling: bool = false

@export_group("Collision")

@export var collision_type: MeshPath3D.COLLISION_TYPE
@export_tool_button("bake single collision") var add_collision_btn = add_single_collision
@export_tool_button("bake multiple collision") var add_multiple_collision_btn = add_multiple_collision

@export_group("Path")

@export var vertical_path: Path3D:
	set(value):
		if vertical_path != value:
			if vertical_path and vertical_path.curve and vertical_path.curve.is_connected("changed", _on_vertical_path_changed):
				vertical_path.curve.changed.disconnect(_on_vertical_path_changed)
			vertical_path = value
			if vertical_path and vertical_path.curve and not vertical_path.curve.is_connected("changed", _on_vertical_path_changed):
				vertical_path.curve.changed.connect(_on_vertical_path_changed)
			call_update_all_lines()
@export_tool_button("setup default path") var setup_default_path_btn = setup_default_path

@export_group("Template Lines")

@export var template_lines: Array[MeshPath3D] = []:
	set(value):
		template_lines = value
		_clear_all_spawned_lines()
		call_update_all_lines()
@export var random_pick_template: bool = false

@export_group("Spacing")

@export var gap: float = 1.0:
	set(value):
		gap = max(value, -0.5)
		call_update_all_lines()

@export_group("Internal")

@export var share_multimeshes: bool = false:
	set(value):
		if share_multimeshes == value:
			return
		share_multimeshes = value
		
		if not share_multimeshes:
			# Break path and multimesh sharing
			for template in _spawned_lines.keys():
				if not template:
					continue
				var spawned_array: Array = _spawned_lines[template]
				for line in spawned_array:
					# Update existing independent path with template's curve
					if line.path and line.path.curve:
						# Disconnect to prevent update triggers
						if line.path.curve.is_connected("changed", line._on_path_changed):
							line.path.curve.changed.disconnect(line._on_path_changed)
						
						# Copy curve data from template
						line.path.curve = template.path.curve.duplicate(true)
						
						# Reconnect
						line.path.curve.changed.connect(line._on_path_changed)
						
						# Reveal path in tree
						if line.path:
							line.path.remove_meta("_edit_lock_")
							line.path.show()
					
					# Copy mesh placement data from template
					line._placed_meshes = template._placed_meshes.duplicate()
					line._placed_meshes_rotation = template._placed_meshes_rotation.duplicate()
					line._placed_meshes_offset = template._placed_meshes_offset.duplicate()
					line._placed_meshes_scale = template._placed_meshes_scale.duplicate()
					line._placed_meshes_gaps = template._placed_meshes_gaps.duplicate()
					line._mesh_transforms = template._mesh_transforms.duplicate()
					
					# Create new independent multimesh for each MMI
					for mesh in line._mesh_to_mmi_map.keys():
						var old_mm = line._mesh_to_mmi_map[mesh].multimesh
						var new_mm = MultiMesh.new()
						new_mm.transform_format = MultiMesh.TRANSFORM_3D
						new_mm.use_colors = true
						new_mm.mesh = mesh
						new_mm.instance_count = old_mm.instance_count
						# Copy transforms
						for i in range(old_mm.instance_count):
							new_mm.set_instance_transform(i, old_mm.get_instance_transform(i))
						line._mesh_to_mmi_map[mesh].multimesh = new_mm
					line.set_physics_process(true)
		
		call_update_all_lines()

@export var multimesh_update_rate: int = 2

@export_storage var _last_template_index: int = -1

var _spawned_lines_list: Array[MeshPath3D] = []

# Dictionary mapping template -> array of spawned copies\
# @param {MeshPath3D: Array[MeshPath3D]} _spawned_lines
var _spawned_lines: Dictionary[MeshPath3D, Array] = {}

var _shedule_update: bool = false
var _passed_frames: int = 0


func _ready() -> void:
	# Collect existing spawned children
	for child in get_children():
		if child is MeshPath3D and child != vertical_path:
			_spawned_lines_list.append(child)
	
	if Engine.is_editor_hint():
		if vertical_path and vertical_path.curve and not vertical_path.curve.is_connected("changed", _on_vertical_path_changed):
			vertical_path.curve.changed.connect(_on_vertical_path_changed)
		call_update_all_lines()
	else:
		call_deferred("call_update_all_lines")


func _physics_process(_delta: float) -> void:
	if not _shedule_update:
		return
	
	_passed_frames += 1
	if _passed_frames == multimesh_update_rate:
		_shedule_update = false
		_passed_frames = 0
		_update_all_lines()


func _on_vertical_path_changed() -> void:
	call_update_all_lines()


#func call_re_render_all() -> void:
	#_clear_all_spawned_lines()
	#call_update_all_lines()


func randomize_lines() -> void:
	var prev_val: bool = random_pick_template
	random_pick_template = true
	_clear_all_spawned_lines()
	call_update_all_lines()
	await vertical_multimesh_updated
	random_pick_template = prev_val


func randomize_meshes() -> void:
	for line in _spawned_lines_list:
		if line:
			line.randomize_meshes()


func call_update_all_lines() -> void:
	_shedule_update = true


func _update_all_lines() -> void:
	if template_lines.is_empty() or not vertical_path or not vertical_path.curve:
		_clear_all_spawned_lines()
		return
	
	var curve: Curve3D = vertical_path.curve
	var curve_length: float = curve.get_baked_length()
	
	if curve_length == 0:
		_clear_all_spawned_lines()
		return
	
	# Initialize spawned arrays for each template
	for template in template_lines:
		if not template:
			continue
		if not _spawned_lines.has(template):
			_spawned_lines[template] = []
	
	# Remove entries for templates no longer in array
	var templates_to_remove: Array = []
	for template in _spawned_lines.keys():
		if not template_lines.has(template):
			templates_to_remove.append(template)
	for template in templates_to_remove:
		_clear_spawned_lines_for_template(template)
		_spawned_lines.erase(template)
	
	# Single loop - spawn lines picking templates in order or random
	var current_distance: float = 0.0
	var global_line_index: int = 0
	_last_template_index = -1
	
	while current_distance < curve_length:
		# Pick next template in order or random (skip nulls)
		var template: MeshPath3D = null
		var attempts: int = 0
		while not template and attempts < template_lines.size():
			if random_pick_template:
				_last_template_index = randi() % template_lines.size()
			else:
				_last_template_index = (_last_template_index + 1) % template_lines.size()
			template = template_lines[_last_template_index]
			attempts += 1
		
		if not template:
			break
		
		var line: MeshPath3D
		
		# Reuse existing line from flat list
		if global_line_index < _spawned_lines_list.size():
			line = _spawned_lines_list[global_line_index]
		# Spawn new line
		else:
			line = _create_line_copy(template)
			_spawned_lines_list.append(line)
			if not _spawned_lines.has(template):
				_spawned_lines[template] = []
			_spawned_lines[template].append(line)
			# Force immediate update to calculate AABB
			line._update_multimesh()

		# Position line so its AABB bottom aligns with current_distance
		var line_aabb: AABB = line._cached_aabb
		var offset_to_bottom: float = line_aabb.position.y
		var curve_position: Vector3 = curve.sample_baked(current_distance - offset_to_bottom)
		line.global_position = global_position + curve_position

		# Advance to this line's AABB top
		current_distance += line_aabb.size.y + gap
		
		global_line_index += 1
	
	# Remove excess lines
	while _spawned_lines_list.size() > global_line_index:
		var line: MeshPath3D = _spawned_lines_list.pop_back()
		# Also remove from per-template tracking
		for template in _spawned_lines.keys():
			var spawned_array: Array = _spawned_lines[template]
			var idx = spawned_array.find(line)
			if idx != -1:
				spawned_array.remove_at(idx)
				break
		line.queue_free()
	
	# Handle shared multimeshes
	if share_multimeshes:
		_share_multimeshes_between_lines()
	else:
		for template in _spawned_lines.keys():
			if not template:
				continue
			var spawned_array: Array = _spawned_lines[template]
			for line in spawned_array:
				if line.path:
					line.path.show()
	
	vertical_multimesh_updated.emit()


func _create_line_copy(template: MeshPath3D) -> MeshPath3D:
	var new_line: MeshPath3D = MeshPath3D.new()
	add_child(new_line)
	new_line.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	
	# Copy properties from template
	new_line.material = template.material
	if template.path:
		var path_copy: Path3D = Path3D.new()
		path_copy.curve = template.path.curve.duplicate(true)
		new_line.add_child(path_copy)
		if not share_multimeshes:
			path_copy.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		new_line.path = path_copy
		
	new_line.path_length = template.path_length
	new_line.meshes = template.meshes.duplicate()
	new_line.allow_partial = template.allow_partial
	new_line.random_pick = template.random_pick
	new_line.gap_min = template.gap_min
	new_line.gap_max = template.gap_max
	new_line.start_margin = template.start_margin
	new_line.end_margin = template.end_margin
	new_line.collision_type = template.collision_type
	new_line.mesh_face_path_x = template.mesh_face_path_x
	new_line.mesh_face_path_y = template.mesh_face_path_y
	new_line.mesh_face_path_z = template.mesh_face_path_z
	new_line.random_flip_x = template.random_flip_x
	new_line.random_flip_y = template.random_flip_y
	new_line.random_flip_z = template.random_flip_z
	new_line.mesh_rotation = template.mesh_rotation
	new_line.random_rotation = template.random_rotation
	new_line.mesh_rotation2 = template.mesh_rotation2
	new_line.mesh_offset = template.mesh_offset
	new_line.random_offset = template.random_offset
	new_line.mesh_offset2 = template.mesh_offset2
	new_line.mesh_scale = template.mesh_scale
	new_line.random_scale = template.random_scale
	new_line.random_uniform_scale = template.random_uniform_scale
	new_line.mesh_scale2 = template.mesh_scale2
	new_line.processor = template.processor
	
	return new_line


func _share_multimeshes_between_lines() -> void:
	for template in _spawned_lines.keys():
		if not template:
			continue
		var spawned_array: Array = _spawned_lines[template]
		for line in spawned_array:
			# Hide path from tree when synced
			if line.path:
				line.path.set_meta("_edit_lock_", true)
				line.path.hide()
			# Share the multimesh DATA, not the instances
			for mesh in template._mesh_to_mmi_map.keys():
				if line._mesh_to_mmi_map.has(mesh):
					line._mesh_to_mmi_map[mesh].multimesh = template._mesh_to_mmi_map[mesh].multimesh
			line.set_physics_process(false)


func _clear_spawned_lines_for_template(template: MeshPath3D) -> void:
	if not _spawned_lines.has(template):
		return
	
	var spawned_array: Array = _spawned_lines[template]
	for line in spawned_array:
		var idx = _spawned_lines_list.find(line)
		if idx != -1:
			_spawned_lines_list.remove_at(idx)
		line.queue_free()
	spawned_array.clear()


func _clear_all_spawned_lines() -> void:
	for template in _spawned_lines.keys():
		_clear_spawned_lines_for_template(template)
	_spawned_lines.clear()
	_spawned_lines_list.clear()


func setup_default_path() -> void:
	if vertical_path:
		vertical_path.curve.clear_points()
		vertical_path.curve.add_point(Vector3.ZERO)
		vertical_path.curve.add_point(Vector3(0, 1, 0))
	else:
		var new_path: Path3D = Path3D.new()
		new_path.name = "MeshPath3DVM_Path"
		new_path.curve = Curve3D.new()
		new_path.curve.add_point(Vector3.ZERO)
		new_path.curve.add_point(Vector3(0, 1, 0))
		
		vertical_path = new_path
		add_child(new_path)
		new_path.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner


func bake_single(parent_ref: Node = null) -> Dictionary:
	# Custom: merge all lines into one mesh
	var all_meshes: Array[Mesh] = []
	var all_transforms: Array[Transform3D] = []
	
	for line in _spawned_lines_list:
		if not line:
			continue
		for i in range(line._placed_meshes.size()):
			all_meshes.append(line._placed_meshes[i])
			all_transforms.append(Transform3D(line._mesh_transforms[i].basis, line._mesh_transforms[i].origin + line.position))
	
	return _bake_single_merged(all_meshes, all_transforms, parent_ref)


func _bake_single_merged(meshes: Array[Mesh], transforms: Array[Transform3D], parent_ref: Node = null) -> Dictionary:
	if meshes.is_empty():
		push_warning("No meshes to bake!")
		return {}
	
	var surface_tool: SurfaceTool = SurfaceTool.new()
	var baked_mesh: ArrayMesh = ArrayMesh.new()
	
	for i in range(meshes.size()):
		var mesh: Mesh = meshes[i]
		var mesh_transform: Transform3D = transforms[i]
		
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
	
	# Use first template's material if available
	if not template_lines.is_empty() and template_lines[0]:
		baked_instance.material_override = template_lines[0].material
	
	# Get container from VM (this node), not from lines
	var parent_node: Node
	if parent_ref:
		parent_node = parent_ref
	else:
		parent_node = get_parent() if bake_as_sibling else self
	
	var container: Node
	
	if bake_in_single_sub_container:
		container = Node3D.new()
		parent_node.add_child(container)
		container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		container.global_transform = global_transform
	else:
		container = parent_node
	
	if bake_in_separate_sub_containers:
		var sub_container: Node3D = Node3D.new()
		container.add_child(sub_container)
		sub_container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		sub_container.global_transform = global_transform
		sub_container.add_child(baked_instance)
	else:
		container.add_child(baked_instance)
	
	baked_instance.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if bake_as_sibling and not bake_in_single_sub_container:
		baked_instance.global_transform = global_transform
	
	return {
		"container": container,
		"baked": baked_instance,
	}


func bake_multiple() -> Dictionary[String, Variant]:
	var all_baked: Array[MeshInstance3D] = []
	
	var parent_node: Node = get_parent() if bake_as_sibling else self
	var container: Node
	
	if bake_in_single_sub_container:
		container = Node3D.new()
		parent_node.add_child(container)
		container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		container.global_transform = global_transform
	else:
		container = parent_node
	
	for line in _spawned_lines_list:
		if not line:
			continue
		# Temporarily disable line's container options
		var old_sibling = line.bake_as_sibling
		var old_single = line.bake_in_single_sub_container
		var old_separate = line.bake_in_separate_sub_containers
		line.bake_as_sibling = false
		line.bake_in_single_sub_container = false
		line.bake_in_separate_sub_containers = bake_in_separate_sub_containers
		
		var result = line.bake_multiple(container)
		
		# Restore line's settings
		line.bake_as_sibling = old_sibling
		line.bake_in_single_sub_container = old_single
		line.bake_in_separate_sub_containers = old_separate
		
		# Fix positions
		for mesh_instance in result.get("baked", []):
			mesh_instance.global_transform = line.global_transform * mesh_instance.transform
		all_baked.append_array(result.get("baked", []))
	
	return {"container": container, "baked": all_baked}


func bake_multiple_with_collision() -> Dictionary[String, Variant]:
	var all_baked: Array = []
	
	var parent_node: Node = get_parent() if bake_as_sibling else self
	var container: Node
	
	if bake_in_single_sub_container:
		container = Node3D.new()
		parent_node.add_child(container)
		container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
		container.global_transform = global_transform
	else:
		container = parent_node
	
	for line in _spawned_lines_list:
		if not line:
			continue
		# Temporarily disable line's container options
		var old_sibling = line.bake_as_sibling
		var old_single = line.bake_in_single_sub_container
		var old_separate = line.bake_in_separate_sub_containers
		var old_collision = line.collision_type
		line.collision_type = collision_type
		line.bake_as_sibling = false
		line.bake_in_single_sub_container = false
		line.bake_in_separate_sub_containers = bake_in_separate_sub_containers
		
		var result = line.bake_multiple_with_collision(container)
		
		# Restore line's settings
		line.collision_type = old_collision
		line.bake_as_sibling = old_sibling
		line.bake_in_single_sub_container = old_single
		line.bake_in_separate_sub_containers = old_separate
		
		# Fix positions
		for baked_dict in result.get("baked", []):
			var collision_body = baked_dict.get("collision_body")
			if collision_body:
				collision_body.global_transform = line.global_transform * collision_body.transform
		all_baked.append_array(result.get("baked", []))
	
	return {"container": container, "baked": all_baked}


func add_single_collision(parent_ref: Node = null) -> void:
	var combined_aabb = _calculate_all_aabb()
	if template_lines.is_empty() or not template_lines[0]:
		return
	var temp_line = template_lines[0]
	var old_collision = temp_line.collision_type
	temp_line.collision_type = collision_type
	
	var parent_node: Node = get_parent() if bake_as_sibling else self
	var container: Node = _create_container(parent_node) if bake_in_single_sub_container else parent_node
	
	var collision_body = temp_line._create_collision_body(container)
	
	# Add this block for separate containers:
	if bake_in_separate_sub_containers:
		var sub_container: Node3D = _create_container(container)
		collision_body.reparent(sub_container)
	
	var collision_shape = temp_line._create_collision_shape(combined_aabb.size, collision_body)
	collision_body.global_position = combined_aabb.get_center()
	temp_line.collision_type = old_collision


func add_multiple_collision(parent_ref: Node = null) -> void:
	var parent_node: Node
	var container: Node
	
	if parent_ref:
		parent_node = parent_ref
	else:
		parent_node = get_parent() if bake_as_sibling else self
	
	if bake_in_single_sub_container:
		container = _create_container(parent_node)
	else:
		container = parent_node
	
	for line in _spawned_lines_list:
		if line:
			var old_collision = line.collision_type
			var old_separate = line.bake_in_separate_sub_containers
			var old_single = line.bake_in_single_sub_container
			line.collision_type = collision_type
			line.bake_in_separate_sub_containers = bake_in_separate_sub_containers
			line.bake_in_single_sub_container = false  # Force false to use passed container
			
			line.add_multiple_collision(container)
			
			line.collision_type = old_collision
			line.bake_in_separate_sub_containers = old_separate
			line.bake_in_single_sub_container = old_single


func _calculate_all_aabb() -> AABB:
	# Merge all line AABBs
	var combined = AABB()
	for line in _spawned_lines_list:
		if line and not line._mesh_transforms.is_empty():
			var line_aabb = line._calculate_combined_aabb()
			combined = combined.merge(line.global_transform * line_aabb) if combined.has_volume() else line.global_transform * line_aabb
	return combined


func _create_container(parent_node: Node) -> Node3D:
	var container: Node3D = Node3D.new()
	parent_node.add_child(container)
	container.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	container.global_transform = global_transform
	return container
