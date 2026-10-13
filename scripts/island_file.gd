extends RefCounted
## Saving and opening islands, and exporting pictures and films.
##
## An island file holds everything that makes the scene: the ground fields,
## what is planted, the ruins and their age, the weather and light, and the
## camera. It is a compressed Godot variant file, so the big float arrays
## stay small.
##
## Films are made by a second copy of the program in Godot's Movie Maker
## mode: it opens the island from a temporary file, plays the camera's spin
## and bob at a fixed frame rate and writes every frame, so the film is
## smooth even where the live view would stutter. A wallpaper is one full
## turn with whole waves in it (see OrbitCamera.fit_loop), so it loops.

const VERSION := 1
const EXTENSION := "island"


static func folder() -> String:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("Floating Island")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func export_folder() -> String:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Floating Island")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d.%02d.%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


static func save(main: Node, path: String) -> Error:
	var state := {
		"version": VERSION,
		"ground": main.data.snapshot(),
		"props": main.props.snapshot(),
		"ruins": main.ruins.snapshot(),
		"roots": main.roots.snapshot(),
		"prop_styles": main.props.styles,
		"root_style": main.roots.style,
		"weather": main.weather.state(),
		"camera": main.rig.state(),
		"post": main.post.state(),
	}
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(state)
	f.close()
	return OK


static func open(main: Node, path: String) -> Error:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	var state = f.get_var()
	f.close()
	if not state is Dictionary or not state.has("ground"):
		return ERR_FILE_CORRUPT
	main.data.restore(state.ground)
	main.view.rebuild(main.data.full_rect(), main.data.full_rect())
	main.view.flush()
	main.data.dirty = Rect2i()
	main.data.dirty_shape = Rect2i()
	main.props.styles = (state.get("prop_styles", {}) as Dictionary).duplicate(true)
	main.props.restore(state.props)
	main.ruins.restore(state.ruins)
	main.roots.style = main.roots.RootBuilder.style_of(state.get("root_style", null))
	main.roots.restore(state.get("roots", []))
	main.props.follow_ground()
	main.fish.refresh()
	main.weather.set_state(state.weather)
	main.weather.refresh_ground()
	if state.has("post"):
		main.post.set_state(state.post)
	else:
		main.post.reset()
	main.rig.set_state(state.camera)
	main.rig.fit_island(main.data)
	main.rig.settle()
	main.brush.clear_history()
	return OK


## Render the current view at `size`, without the panel, and save it.
static func still(main: Node, size: Vector2i) -> String:
	var sub := SubViewport.new()
	sub.size = size
	sub.world_3d = main.get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_4X
	var cam := Camera3D.new()
	var src: Camera3D = main.rig.camera
	cam.fov = src.fov
	cam.near = src.near
	cam.far = src.far
	cam.attributes = src.attributes
	sub.add_child(cam)
	main.add_child(sub)
	# the live view is shifted clear of the panel by h_offset; the export is not
	cam.global_transform = src.global_transform
	cam.current = true
	sub.add_child(main.Post.make_layer(main.post.material_for(Vector2(size))))
	# full quality for the picture, whatever Snabbläge says for the live view
	var was_fast: bool = main.post.fast
	main.post.weather.env.ssil_enabled = true
	# a few frames so screen-space effects settle at the new size
	for k in 4:
		await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	main.post.weather.env.ssil_enabled = not was_fast
	var path := export_folder().path_join("Ö %s.png" % stamp())
	img.save_png(path)
	return path


## Start a film or a wallpaper loop rendering in a second window. Returns the
## path the film will be written to.
## Where a temporary override.cfg goes: the project folder when run from
## the editor, beside the program in an exported build (its res:// is packed
## and read-only, and Godot looks for the file beside the program).
static func override_path() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("override.cfg")
	return ProjectSettings.globalize_path("res://override.cfg")


static func film(main: Node, seconds: float, size: Vector2i, wallpaper: bool) -> String:
	var temp := OS.get_user_data_dir().path_join("export.island")
	if wallpaper:
		# fit the waves to a loop for the film only; the live camera keeps its own
		var live: Dictionary = main.rig.state()
		seconds = main.rig.fit_loop(seconds)
		save(main, temp)
		main.rig.set_state(live)
	else:
		save(main, temp)
	var name := ("Bakgrund %s.avi" if wallpaper else "Film %s.avi") % stamp()
	var out := export_folder().path_join(name)
	# Movie Maker records at the project's window size, so the second copy
	# gets its size from a temporary override.cfg; it removes the file as
	# soon as it has started (see main._ready).
	var cfg := FileAccess.open(override_path(), FileAccess.WRITE)
	cfg.store_string("[display]\n\nwindow/size/viewport_width=%d\nwindow/size/viewport_height=%d\n" % [size.x, size.y])
	cfg.close()
	var args := PackedStringArray([
		"--write-movie", out,
		"--fixed-fps", "30",
		"--", "--open=" + temp, "--record=%.2f" % seconds,
	])
	if not OS.has_feature("template"):
		# run from the editor's project folder: the copy needs to be told where it is
		args = PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]) + args
	if wallpaper:
		args.append("--loop")
	OS.create_process(OS.get_executable_path(), args)
	return out
