extends CanvasLayer
## The start, behind a loading screen.
##
## A shader is compiled the first time something drawn with it comes into
## view, and on a computer that has never run the program each of those stalls
## the picture for a moment, again and again as new things are placed. So this
## draws one of everything once, out of sight behind the screen: every kind of
## thing that can be placed, every shader on a little ball, the falling
## weather and the mist. Godot keeps what it compiled (user://shader_cache),
## so later starts pass in a moment.
##
## It also picks Snabbläge for a weak computer: at once when the graphics are
## built into the processor, or after a few seconds of watching the picture
## when it cannot keep up. Only when nobody has chosen on this computer yet
## (see post.gd).

signal finished

const Catalog := preload("res://scripts/prop_catalog.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

## Spatial shaders nothing else here draws (the island draws its ground,
## cliff, grass and clouds, the things their own), each on a ball so it is
## compiled before it is needed.
const SHADERS := ["fish", "ghost", "ghost_front", "roots", "spray", "water", "waterfall", "mist_layers"]
## A picture slower than this (seconds a frame) cannot keep up.
const SLOW_FRAME := 1.0 / 32.0

var main
var _bar: ProgressBar
var _note: Label
var _shade: ColorRect
var _stage: Node3D


## Warm up for `main_node`. `chosen`: Snabbläge was already chosen on this
## computer (or on the command line), so leave it be. `force_weak` pretends
## the graphics are built in (tests).
func run(main_node, chosen: bool, force_weak := false) -> void:
	main = main_node
	layer = 128
	_build_screen()
	await _frames(2)
	var started := Time.get_ticks_msec()
	var reason := ""
	# decided first, so the shaders are warmed in the variants they will be
	# drawn in (with or without MSAA)
	if not chosen and (force_weak or weak_gpu()):
		main.post.fast = true
		reason = "Snabbläge är på: grafiken är inbyggd i processorn. Du kan slå av det under Grafik."
	await _warm()
	print("warm-up: %d ms" % (Time.get_ticks_msec() - started))
	_stage.queue_free()
	var tw := create_tween()
	tw.tween_property(_shade, "modulate:a", 0.0, 0.5)
	await tw.finished
	_shade.visible = false
	if not chosen and not main.post.fast and await _too_slow():
		main.post.fast = true
		reason = "Snabbläge är på: datorn hann inte med bilden. Du kan slå av det under Grafik."
	if reason != "":
		print(reason)
		main.ui.toast(reason)
		if main.ui.buttons.has("Snabbläge"):
			(main.ui.buttons["Snabbläge"] as Button).set_pressed_no_signal(true)
	finished.emit()
	queue_free()


## Graphics built into the processor, or drawn by the processor itself.
static func weak_gpu() -> bool:
	var type := RenderingServer.get_video_adapter_type()
	if type in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU]:
		return true
	var name := RenderingServer.get_video_adapter_name().to_lower()
	return name.contains("llvmpipe") or name.contains("swiftshader") or name.contains("basic render")


func _build_screen() -> void:
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.16, 0.2, 0.26)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	_shade.add_child(box)
	var title := Label.new()
	title.text = "Ön vaknar…"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.94, 0.9))
	box.add_child(title)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(_bar)
	_note = Label.new()
	_note.text = "Grafiken förbereds. Första gången på en ny dator tar det en stund."
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	box.add_child(_note)


## Everything drawn once, a few at a time so the bar moves between them, in
## a row before the camera where the screen hides it.
func _warm() -> void:
	var cam: Camera3D = main.rig.camera
	_stage = Node3D.new()
	main.add_child(_stage)
	var jobs: Array[Callable] = []
	for kind: String in Catalog.KINDS:
		jobs.append(func() -> Node3D: return _thing(kind))
	for name: String in SHADERS:
		jobs.append(func() -> Node3D: return _ball(name))
	jobs.append(_weather)
	_bar.max_value = jobs.size()
	var slot := 0
	for job in jobs:
		var node: Node3D = job.call()
		if node != null:
			node.position += Vector3(float(slot % 7) - 3.0, float(slot / 7 % 5) - 2.0, 0.0) * 0.7
			_stage.add_child(node)
			slot += 1
		_bar.value += 1
		if int(_bar.value) % 3 == 0:
			await _frames(2)
	# the last ones, the shadow pass and the mist all drawn a few times over
	var volume: float = main.post.volume
	main.post.volume = maxf(volume, 0.3)
	await _frames(6)
	main.post.volume = volume
	# then everything, the island too, lit by a fire's light (and with its
	# shadow, where fires cast one): the lighter look (the web) draws each
	# shader again for a light that reaches it, so the first fire or torch
	# placed would otherwise stall the picture for seconds. The things' own
	# lights stay off until here, or every shader near them would be built
	# for them, and none for the dark.
	var lights: Array[OmniLight3D] = []
	var centre: Vector3 = main.rig.island_center
	for at: Vector3 in [centre + Vector3(0.0, 2.0, 0.0), _stage.global_position]:
		var l := OmniLight3D.new()
		l.omni_range = maxf(float(main.rig.island_radius) * 1.6, 8.0)
		l.light_energy = 0.5
		add_child(l)
		l.global_position = at
		lights.append(l)
	await _frames(4)
	if not MeshUtil.lite():
		for l in lights:
			l.shadow_enabled = true
		await _frames(4)
	for l in lights:
		l.queue_free()


## One of a kind of thing, as the layer would build it, about half a metre.
func _thing(kind: String) -> Node3D:
	var k: Dictionary = Catalog.KINDS[kind]
	var rec := {"id": -1, "kind": kind, "x": 0.0, "z": 0.0, "rot": 0.6, "variant": 0, "hue": 0.5, "size": 1.0}
	if k.has("height"):
		rec.size = (float(k.height[0]) + float(k.height[1])) * 0.5
	if k.has("style"):
		rec.style = main.props.style_for(kind).duplicate(true)
		rec.jit = 0.0
		rec.size = main.props._styled_size(rec)
	var node := Catalog.build(rec)
	var tall := maxf(float(node.get_meta("tall", 1.0)), 0.1)
	for l in node.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = false
	node.scale *= 0.5 / maxf(tall, 0.5)
	return node


func _ball(name: String) -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/%s.gdshader" % name)
	mi.material_override = mat
	return mi


## The falling things and the mist, copies of the weather's own sharing its
## materials, so the same shaders are compiled.
func _weather() -> Node3D:
	var group := Node3D.new()
	for p: GPUParticles3D in main.find_children("*", "GPUParticles3D", true, false):
		var c := p.duplicate() as GPUParticles3D
		c.position = Vector3.ZERO
		c.amount_ratio = 1.0
		c.emitting = true
		group.add_child(c)
	for f: FogVolume in main.find_children("*", "FogVolume", true, false):
		var c := f.duplicate() as FogVolume
		c.position = Vector3.ZERO
		c.size = Vector3(2.0, 2.0, 2.0)
		c.visible = true
		group.add_child(c)
	return group


## Whether the picture cannot keep up: the middle frame time over two
## seconds, after a moment to settle.
func _too_slow() -> bool:
	await _frames(30)
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for k in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1e6)
		last = now
	times.sort()
	var middle := times[times.size() / 2]
	print("frame time at start: %.1f ms" % (middle * 1000.0))
	return middle > SLOW_FRAME


## Keep the stage in the middle of the picture, 5 m out: the camera is
## shifted sideways clear of the panel (so straight ahead of it is off to
## one side), and it still settles while the screen is up.
func _aim_stage() -> void:
	if not is_instance_valid(_stage):
		return
	var cam: Camera3D = main.rig.camera
	var middle: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	_stage.global_transform = Transform3D(cam.global_basis, cam.project_position(middle, 5.0))


func _frames(n: int) -> void:
	for k in n:
		_aim_stage()
		await RenderingServer.frame_post_draw
