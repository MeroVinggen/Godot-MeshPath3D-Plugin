@tool
extends Node3D
class_name MeshPath3DVM

signal vertical_multimesh_updated()

@export_group("Utils")

@export_tool_button("randomize lines") var randomize_lines_btn: Callable = randomize_lines
@export_tool_button("randomize meshes") var randomize_meshes_btn: Callable = randomize_meshes
#@export_tool_button("re-render all") var update_all_btn: Callable = call_re_render_all

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
			# Break the multimesh sharing
			for template in _spawned_lines.keys():
				if not template:
					continue
				var spawned_array: Array = _spawned_lines[template]
				for line in spawned_array:
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
		
		# Position line at current distance along vertical path
		var curve_position: Vector3 = curve.sample_baked(current_distance)
		line.global_position = global_position + curve_position
		
		# Get line height for next offset
		var line_height: float = line.get_height() if line.get_height() > 0 else 1.0
		
		current_distance += line_height + gap
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
		path_copy.curve = template.path.curve.duplicate(true)  # Add true for deep duplicate
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
