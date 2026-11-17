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

const VERSION := 2
const EXTENSION := "island"
const NAME := "Skyholme"
const THUMB := Vector2i(480, 270)

## A folder to keep the islands in instead of the usual one (tests).
static var root := ""


## Where the islands live: Documents\Skyholme (in a browser, the page's own
## storage). The folder of the working name it had before is taken over.
static func folder() -> String:
	if root != "":
		DirAccess.make_dir_recursive_absolute(root)
		return root
	if OS.has_feature("web"):
		DirAccess.make_dir_recursive_absolute("user://islands")
		return "user://islands"
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var dir := docs.path_join(NAME)
	var old := docs.path_join("Floating Island")
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.dir_exists_absolute(old):
		DirAccess.rename_absolute(old, dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func export_folder() -> String:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join(NAME)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d.%02d.%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


## Everything that makes the scene, as one value.
static func capture(main: Node) -> Dictionary:
	return {
		"version": VERSION,
		"ground": main.data.snapshot(),
		"props": main.props.snapshot(),
		"ruins": main.ruins.snapshot(),
		"roots": main.roots.snapshot(),
		"prop_styles": main.props.styles.duplicate(true),
		"root_style": main.roots.style.duplicate(true),
		"weather": main.weather.state(),
		"camera": main.rig.state(),
		"post": main.post.state(),
	}


## Make the scene what `state` says (from capture, or a file).
static func apply(main: Node, state: Dictionary) -> void:
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


## Write the island to `path`. The file starts with a small header (its
## name, when it was saved, a little picture of it), so a gallery of
## islands can be shown without opening each one; then the island itself.
static func save(main: Node, path: String, name := "", thumb = null) -> Error:
	return write(capture(main), path, name, thumb)


## `thumb` is the picture (an Image), or one already packed (the bytes).
static func write(state: Dictionary, path: String, name := "", thumb = null) -> Error:
	var packed := PackedByteArray()
	if thumb is Image:
		packed = (thumb as Image).save_jpg_to_buffer(0.86)
	elif thumb is PackedByteArray:
		packed = thumb
	var head := {
		"skyholme": VERSION,
		"name": name if name != "" else path.get_file().get_basename(),
		"saved": Time.get_unix_time_from_system(),
		"thumb": packed,
	}
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(head)
	f.store_var(state)
	f.close()
	return OK


static func open(main: Node, path: String) -> Error:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	var state = f.get_var()
	# since version 2 a header comes first; older files are the island alone
	if state is Dictionary and state.has("skyholme"):
		state = f.get_var()
	f.close()
	if not state is Dictionary or not state.has("ground"):
		return ERR_FILE_CORRUPT
	apply(main, state)
	return OK


## An island file's header: name, saved (unix time) and thumb (an Image, or
## null). An older file without one answers with its file name and date.
static func header(path: String) -> Dictionary:
	var out := {"path": path, "name": path.get_file().get_basename(), "saved": float(FileAccess.get_modified_time(path)), "thumb": null}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return out
	var head = f.get_var()
	f.close()
	if head is Dictionary and head.has("skyholme"):
		out.name = String(head.get("name", out.name))
		out.saved = float(head.get("saved", out.saved))
		var bytes: PackedByteArray = head.get("thumb", PackedByteArray())
		if not bytes.is_empty():
			var img := Image.new()
			if img.load_jpg_from_buffer(bytes) == OK:
				out.thumb = img
	return out


## Every island in the folder, the one saved last first.
static func library() -> Array:
	var out := []
	var dir := folder()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == EXTENSION:
			out.append(header(dir.path_join(file)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved > b.saved)
	return out


## A path in the folder for an island called `name`, not yet taken.
static func fresh_path(name: String) -> String:
	var clean := name.validate_filename().strip_edges()
	if clean == "":
		clean = "Island"
	var dir := folder()
	var path := dir.path_join(clean + "." + EXTENSION)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s %d.%s" % [clean, n, EXTENSION])
		n += 1
	return path


## The first name of the kind "Ö 3" that no island has yet.
static func fresh_name(word: String) -> String:
	var taken := {}
	for item in library():
		taken[String(item.name)] = true
	var n := 1
	while taken.has("%s %d" % [word, n]):
		n += 1
	return "%s %d" % [word, n]


## A file as it is stored: [header, island], or [] if it cannot be read.
static func _parts(path: String) -> Array:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return []
	var first = f.get_var()
	var out := []
	if first is Dictionary and first.has("skyholme"):
		out = [first, f.get_var()]
	elif first is Dictionary and first.has("ground"):
		out = [{}, first]
	f.close()
	return out


## Give an island another name (its file follows). Returns its new path.
static func rename(path: String, name: String) -> String:
	var parts := _parts(path)
	if parts.is_empty():
		return path
	var to := fresh_path(name)
	if write(parts[1], to, name, parts[0].get("thumb", null)) != OK:
		return path
	DirAccess.remove_absolute(path)
	return to


## A second island like this one, called `name`. Returns its path.
static func copy(path: String, name: String) -> String:
	var parts := _parts(path)
	if parts.is_empty():
		return ""
	var to := fresh_path(name)
	write(parts[1], to, to.get_file().get_basename(), parts[0].get("thumb", null))
	return to


## Take an island away: to the recycle bin where there is one.
static func remove(path: String) -> void:
	if OS.has_feature("web") or OS.move_to_trash(ProjectSettings.globalize_path(path)) != OK:
		DirAccess.remove_absolute(path)


## A small picture of the island as the camera sees it, without the panel
## (and not slid aside for it).
static func thumbnail(main: Node, size := THUMB) -> Image:
	var sub := SubViewport.new()
	sub.size = size
	sub.world_3d = main.get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_2X
	var cam := Camera3D.new()
	var src: Camera3D = main.rig.camera
	cam.fov = src.fov
	cam.near = src.near
	cam.far = src.far
	sub.add_child(cam)
	main.add_child(sub)
	cam.global_transform = src.global_transform
	cam.h_offset = 0.0
	cam.current = true
	sub.add_child(main.Post.make_layer(main.post.material_for(Vector2(size))))
	for k in 2:
		await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	img.convert(Image.FORMAT_RGB8)
	return img


## The current view at `size`, without the panel, as a picture.
static func still_image(main: Node, size: Vector2i) -> Image:
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
	cam.global_transform = src.global_transform
	cam.v_offset = src.v_offset
	cam.current = true
	sub.add_child(main.Post.make_layer(main.post.material_for(Vector2(size))))
	main.post.full_quality = true
	main.post.apply()
	for k in 6:
		await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	main.post.full_quality = false
	return img


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
	main.post.full_quality = true
	main.post.apply()
	# a few frames so screen-space effects settle at the new size
	for k in 4:
		await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	main.post.full_quality = false
	if OS.has_feature("web"):
		var name := "Skyholme %s.png" % stamp()
		download(img.save_png_to_buffer(), name, "image/png")
		return name
	var path := export_folder().path_join("Skyholme %s.png" % stamp())
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


## In a browser there is no file system to save into: an island or a
## picture is handed to the browser as a download instead.
static func download(bytes: PackedByteArray, name: String, mime: String) -> void:
	JavaScriptBridge.download_buffer(bytes, name, mime)


## The island as a download, in the browser.
static func download_island(main: Node, name: String) -> Error:
	var temp := "user://download.island"
	var err := save(main, temp)
	if err == OK:
		download(FileAccess.get_file_as_bytes(temp), name, "application/octet-stream")
	return err


## The browser's own file picker, for opening an island: `done` gets the
## file's bytes. The picker runs in the page, so the file comes back as
## base64 through a callback that must stay alive until then.
static var _upload_callback: JavaScriptObject

static func pick_upload(done: Callable) -> void:
	_upload_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		done.call(Marshalls.base64_to_raw(String(args[0]))))
	var window = JavaScriptBridge.get_interface("window")
	window.floatingIslandUpload = _upload_callback
	JavaScriptBridge.eval("""
		(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.island';
			input.onchange = function () {
				var file = input.files[0];
				if (!file) return;
				var reader = new FileReader();
				reader.onload = function () {
					var bytes = new Uint8Array(reader.result);
					var text = '';
					for (var i = 0; i < bytes.length; i += 0x8000)
						text += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
					window.floatingIslandUpload(btoa(text));
				};
				reader.readAsArrayBuffer(file);
			};
			input.click();
		})();
	""", true)


## Open an island from the bytes of an uploaded file.
static func open_bytes(main: Node, bytes: PackedByteArray) -> Error:
	var temp := "user://upload.island"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return open(main, temp)
