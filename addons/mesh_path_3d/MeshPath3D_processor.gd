@tool
@abstract
extends Resource
class_name MeshPath3DProcessor


func process_multimesh(multimesh_instance: MultiMeshInstance3D) -> void:
	pass


func process_mesh(multimesh: MultiMesh, mesh_index: int) -> void:
	pass


func process_bake_single(baked_instance: MeshInstance3D, material: Material) -> void:
	pass


func process_bake_multiple(mesh_instance: MeshInstance3D, material: Material, multimesh_instance: MultiMeshInstance3D) -> void:
	pass


func process_bake_multiple_with_collision(mesh_instance: MeshInstance3D, collision_body: CollisionObject3D, collision_shape: CollisionShape3D, sub_container: Node3D, material: Material, multimesh_instance: MultiMeshInstance3D) -> void:
	pass
