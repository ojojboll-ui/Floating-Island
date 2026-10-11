extends SceneTree
## Lists every glTF in assets/quaternius with its size and material names.
## godot --headless --path . --script res://tools/probe_models.gd


func _init() -> void:
	var dir := "res://assets/quaternius/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gltf"):
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(dir + f), state) != OK:
			print(f, "  FAILED")
			continue
		var root := doc.generate_scene(state)
		var box := AABB()
		var mats := []
		var first := true
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			var b: AABB = mi.transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
			for s in m.get_surface_count():
				var mat := m.surface_get_material(s)
				mats.append(mat.resource_name if mat else "-")
		print("%-28s size %5.2f x %5.2f x %5.2f  base y %5.2f  %s" % [f, box.size.x, box.size.y, box.size.z, box.position.y, ", ".join(mats)])
		root.free()
	quit()
