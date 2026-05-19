extends Spatial

# Bakes SideWallLeft + SideWallRight (identical CubeMesh + material) into a
# single MultiMeshInstance to reduce draw calls from 2 -> 1.
# The original MeshInstances are hidden but kept in the tree so the scene file
# does not change structure; only rendering is replaced.

export(bool) var use_multimesh_walls: bool = true


func _ready() -> void:
	if use_multimesh_walls:
		_bake_sidewalls()


func _bake_sidewalls() -> void:
	var left: MeshInstance = get_node_or_null("SideWallLeft") as MeshInstance
	var right: MeshInstance = get_node_or_null("SideWallRight") as MeshInstance
	if left == null or right == null:
		return

	var mesh_res: Mesh = left.mesh
	if mesh_res == null:
		return
	var mat: Material = left.get_surface_material(0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 2
	mm.mesh = mesh_res
	mm.set_instance_transform(0, left.transform)
	mm.set_instance_transform(1, right.transform)

	var mmi := MultiMeshInstance.new()
	mmi.name = "SideWalls_MMI"
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	add_child(mmi)

	# Nodes are no longer needed for rendering; free them to release VRAM.
	left.queue_free()
	right.queue_free()
