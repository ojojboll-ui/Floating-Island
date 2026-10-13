extends Node3D
## The diorama: island, props, sky, camera, brush and tool panel.
##
## Run with `-- --snapshot=path.png` to render a frame to disk and quit.
## Optional: --yaw=deg --pitch=deg --dist=m --frames=n
## --hour=h --moon_phase=0..1 --clouds= --fog= --rain= --snow= --wind=
## --fireflies= (0..1) --open=file.island --record=seconds [--loop] --test=name (see test_driver.gd) --noui
## --target=x,y,z (what the camera orbits) --tab=n --fold, and any setting of post.gd, e.g. --rays=1

const IslandData := preload("res://scripts/island_data.gd")
const IslandView := preload("res://scripts/island_view.gd")
const PropLayer := preload("res://scripts/prop_layer.gd")
const FishSchool := preload("res://scripts/fish_school.gd")
const RuinLayer := preload("res://scripts/ruin_layer.gd")
const Weather := preload("res://scripts/weather.gd")
const OrbitCamera := preload("res://scripts/orbit_camera.gd")
const Brush := preload("res://scripts/brush.gd")
const UI := preload("res://scripts/ui.gd")
const TestDriver := preload("res://scripts/test_driver.gd")
const IslandFile := preload("res://scripts/island_file.gd")
const Post := preload("res://scripts/post.gd")
const RootLayer := preload("res://scripts/root_layer.gd")

var data
var view
var props
var ruins
var fish
var rig
var brush
var ui
var weather
var post
var roots
var args_age := -1.0   # --age=x for tests
var args_yaw := -12.0   # --view_yaw=deg for tests that set their own view
var args_dist := 12.0
var args_target := Vector3(2.0, 1.5, -2.4)


func _ready() -> void:
	var args := _parse_args()
	# a film export leaves this behind for its own window size; it must not
	# outlive that start
	if FileAccess.file_exists(IslandFile.override_path()):
		DirAccess.remove_absolute(IslandFile.override_path())
	args_age = float(args.get("age", -1.0))
	args_yaw = float(args.get("view_yaw", -12.0))
	args_dist = float(args.get("view_dist", 12.0))
	if args.has("view_target"):
		var xyz: PackedStringArray = String(args["view_target"]).split(",")
		args_target = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))

	data = IslandData.new()
	data.generate_default(7)
	_lay_path()

	props = PropLayer.new()
	add_child(props)
	props.setup(data)
	ruins = RuinLayer.new()
	add_child(ruins)
	ruins.setup(data, props)
	props.ruins = ruins
	_first_props()

	view = IslandView.new()
	add_child(view)
	view.setup(data)
	data.dirty = Rect2i()
	data.dirty_shape = Rect2i()
	props.follow_ground()

	roots = RootLayer.new()
	add_child(roots)
	roots.setup(data, ruins)
	roots.view = view
	roots.props = props
	props.roots = roots

	fish = FishSchool.new()
	add_child(fish)
	fish.setup(data)

	weather = Weather.new()
	add_child(weather)
	weather.setup(data, props, ruins)
	weather.set_terrain(view.texture)
	for key in ["hour", "moon_phase", "clouds", "fog", "rain", "snow", "wind", "fireflies"]:
		if args.has(key):
			weather.set(key, float(args[key]))
	weather.settle()

	rig = OrbitCamera.new()
	add_child(rig)
	if args.has("yaw"):
		rig.goal_yaw = deg_to_rad(float(args["yaw"]))
	if args.has("pitch"):
		rig.goal_pitch = deg_to_rad(float(args["pitch"]))
	if args.has("dist"):
		rig.goal_distance = float(args["dist"])
	if args.has("target"):
		var xyz: PackedStringArray = String(args["target"]).split(",")
		rig.goal_target = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	rig.fit_island(data)
	rig.settle()
	weather.island_rig = rig

	post = Post.new()
	add_child(post)
	post.setup(weather, rig)

	brush = Brush.new()
	add_child(brush)
	brush.setup(data, view, props, ruins, rig.camera)
	brush.roots = roots
	brush.changed.connect(_on_ground_changed)

	ui = UI.new()
	add_child(ui)
	ui.setup(brush, ruins, weather, self)
	ui.visible = not args.has("noui")
	if args.has("tab"):
		ui.tabs.current_tab = int(args["tab"])
	if args.has("fold"):
		ui.set_collapsed(true)
	for key in post.SETTINGS:
		if args.has(key) and not key.ends_with("_tint"):
			post.set(key, float(args[key]))

	if args.has("open"):
		IslandFile.open(self, args["open"])
	if args.has("record"):
		_record(float(args["record"]), args.has("loop"))
	elif args.has("snapshot"):
		_run_snapshot(args)


## Movie Maker run (see island_file.gd): no panel, no brush, play the
## camera's waves from their start for `seconds`, then close. A loop holds the clouds still,
## so the last frame meets the first.
func _record(seconds: float, loop: bool) -> void:
	ui.visible = false
	rig.frame_shift = 0.0
	rig.settle()
	brush.process_mode = Node.PROCESS_MODE_DISABLED
	brush.visible = false
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	rig.set_process_unhandled_input(false)
	rig.spin_phase = 0.0
	rig.bob_phase = 0.0
	weather.time_flows = weather.time_flows and not loop
	weather.hold_clouds = loop
	var frames := int(round(seconds * 30.0))
	for k in frames:
		await get_tree().process_frame
	get_tree().quit()


## Build the panel again from the current settings, on the same tab.
func rebuild_ui() -> void:
	var tab: int = ui.tabs.current_tab
	var folded: bool = ui.collapsed
	ui.queue_free()
	ui = UI.new()
	add_child(ui)
	ui.setup(brush, ruins, weather, self)
	ui.tabs.current_tab = tab
	if folded:
		ui.set_collapsed(true)


func _run_snapshot(args: Dictionary) -> void:
	if args.has("test"):
		await TestDriver.run(self, args["test"])
	await _snapshot(args["snapshot"], int(args.get("frames", 150)))


func _on_ground_changed(_rect: Rect2i) -> void:
	rig.fit_island(data)
	weather.refresh_ground()
	props.follow_ground()
	roots.follow_ground()
	fish.refresh()


## The island as it first appears: the old tree on its knoll and a few
## boulders. They are ordinary placed things, so they can be removed.
func _first_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	props.add("sagotrad", -2.4, -1.8, rng, 6.0, 4)
	for r in [[4.9, 3.3, 1.2], [5.9, 2.2, 0.7], [-0.7, -3.4, 0.8], [-4.6, 2.2, 1.0], [-3.9, 3.0, 0.5]]:
		props.add("stenblock", r[0], r[1], rng, r[2])


## A worn sandy path from the shore up to the tree.
func _lay_path() -> void:
	var a := Vector2(2.6, 5.6)
	var ctrl := Vector2(2.4, 0.6)
	var b := Vector2(-1.4, -1.0)
	for k in 40:
		var t := k / 39.0
		var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
		data.stamp_splat(p, 0.7, Color(0.0, 0.25, 0.0, 0.75), 0.3)
		data.edit_height(p, 0.6, -0.008)
	# a patch of pebbles where the path meets the shore
	data.stamp_splat(Vector2(3.0, 5.4), 1.1, Color(0.6, 0.3, 0.0, 0.1), 0.6)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif a.begins_with("--"):
			out[a.substr(2)] = "1"
	return out


func _snapshot(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("snapshot saved: ", path, "  (", Engine.get_frames_per_second(), " fps)")
	get_tree().quit()
