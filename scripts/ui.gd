extends CanvasLayer
## The tool panel down the left side, in the warm paper look of the rest of
## the diorama. It folds away to a small tab on the edge (the button at its
## top, or the Tab key), and the island slides over to the middle of the
## screen while it is gone.

const Brush := preload("res://scripts/brush.gd")
const Catalog := preload("res://scripts/prop_catalog.gd")

const INK := Color(0.27, 0.21, 0.16)
const PAPER := Color(0.985, 0.965, 0.925, 0.93)
const CHIP := Color(0.93, 0.895, 0.83)
const CHIP_HOVER := Color(0.96, 0.93, 0.87)
const ACCENT := Color(0.47, 0.6, 0.36)

# the Växter page: group title and the kinds in it
const PLANTS := [
	["Träd", ["lovtrad", "gran", "krokigt", "torrtrad", "sagotrad"]],
	["Buskar", ["buske", "blombuske", "ormbunke", "hogtgras"]],
	["Blommor", ["blommor", "klover", "svamp"]],
	["Stenar", ["stenblock", "smasten", "trampsten"]],
	["Vid vattnet", ["vass", "nackros"]],
]

# name, splat target, swatch colour, loose stones target, tooltip
const MATERIALS := [
	["Gräs", Color(0, 0, 0, 0), Color(0.45, 0.62, 0.2), 0.0, "Måla gräs"],
	["Plattor", Color(1, 0, 0, 0), Color(0.6, 0.58, 0.55), 0.0, "Lagda stenplattor"],
	["Stenar", Color(0, 0, 0, 0), Color(0.5, 0.49, 0.47), 1.0, "Lösa stenar i olika storlekar"],
	["Sand", Color(0, 1, 0, 0), Color(0.86, 0.78, 0.58), 0.0, "Måla sand"],
	["Mossa", Color(0, 0, 1, 0), Color(0.38, 0.5, 0.15), 0.0, "Måla mossa"],
	["Jord", Color(0, 0, 0, 1), Color(0.5, 0.37, 0.25), 0.0, "Måla jord"],
]

var brush
var _size_slider: HSlider
var _strength_slider: HSlider
var _group := ButtonGroup.new()
var buttons := {}   # label -> Button, for the test driver
var _pages: Array = []
var _brush_dials: Control
var tabs   # a TabGrid, answering like a TabBar
var ruins
var weather
var main
var rig
var _toast: Label
var _cam_sliders := {}
var _dock: PanelContainer
var _handle: Button
var collapsed := false
var _root_dials: Control
var _scatter_dials: Array = []   # Täthet and Klungor, for painting things out
var _kind_dials := {}             # kind -> its box of style dials

const DOCK_WIDTH := 372
const MARGIN := 16


func setup(b, ruin_layer, weather_node, main_node) -> void:
	main = main_node
	rig = main_node.rig
	brush = b
	ruins = ruin_layer
	weather = weather_node
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_dock = PanelContainer.new()
	_dock.anchor_bottom = 1.0
	_dock.offset_left = MARGIN
	_dock.offset_right = MARGIN + DOCK_WIDTH
	_dock.offset_top = MARGIN
	_dock.offset_bottom = -MARGIN
	root.add_child(_dock)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_dock.add_child(column)

	# file and history along the top, and the button that folds the panel
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for pair in [["Spara", "Spara ön som en fil (Ctrl+S)", _save_dialog], ["Öppna", "Öppna en sparad ö (Ctrl+O)", _open_dialog],
			["Ångra", "Ctrl+Z", func() -> void: brush.undo()], ["Gör om", "Ctrl+Y", func() -> void: brush.redo()]]:
		var fb := Button.new()
		fb.text = pair[0]
		fb.tooltip_text = pair[1]
		fb.focus_mode = Control.FOCUS_NONE
		fb.theme_type_variation = "SmallButton"
		fb.pressed.connect(pair[2])
		top.add_child(fb)
		buttons[pair[0]] = fb
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	var fold := Button.new()
	fold.text = "‹"
	fold.tooltip_text = "Göm panelen (Tab)"
	fold.focus_mode = Control.FOCUS_NONE
	fold.theme_type_variation = "SmallButton"
	fold.pressed.connect(func() -> void: set_collapsed(true))
	top.add_child(fold)
	buttons["Göm"] = fold
	column.add_child(top)

	tabs = TabGrid.new()
	tabs.columns = 4
	tabs.add_theme_constant_override("h_separation", 2)
	tabs.add_theme_constant_override("v_separation", 2)
	for t in ["Mark", "Växter", "Ruiner", "Väder", "Ljus", "Kamera", "Effekter", "Export"]:
		tabs.add_tab(t)
	column.add_child(tabs)
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	scroll.add_child(body)
	var row := _page()
	body.add_child(row)
	var plants := _plants_row()
	plants.visible = false
	body.add_child(plants)
	var ruin_page := _ruins_row()
	ruin_page.visible = false
	body.add_child(ruin_page)
	var weather_page := _weather_row()
	weather_page.visible = false
	body.add_child(weather_page)
	var light_page := _light_row()
	light_page.visible = false
	body.add_child(light_page)
	var camera_page := _camera_row()
	camera_page.visible = false
	body.add_child(camera_page)
	var effects_page := _effects_row()
	effects_page.visible = false
	body.add_child(effects_page)
	var export_page := _export_row()
	export_page.visible = false
	body.add_child(export_page)
	_pages = [row, plants, ruin_page, weather_page, light_page, camera_page, effects_page, export_page]
	tabs.tab_changed.connect(_show_page)

	# folded away, the panel is this little tab on the edge
	_handle = Button.new()
	_handle.text = "Verktyg  ›"
	_handle.tooltip_text = "Visa panelen (Tab)"
	_handle.focus_mode = Control.FOCUS_NONE
	_handle.theme_type_variation = "Handle"
	_handle.offset_top = MARGIN
	_handle.offset_right = 0
	_handle.offset_left = 0
	_handle.visible = false
	_handle.pressed.connect(func() -> void: set_collapsed(false))
	buttons["Visa"] = _handle
	root.add_child(_handle)

	row.add_child(_section("Forma", [
		_tool_button("Höj", Brush.Tool.RAISE, null, "Höj marken (Shift: sänk)"),
		_tool_button("Sänk", Brush.Tool.LOWER, null, "Sänk marken (Shift: höj)"),
		_tool_button("Jämna", Brush.Tool.SMOOTH, null, "Jämna ut gropar och toppar"),
		_tool_button("Platta", Brush.Tool.FLATTEN, null, "Platta till på höjden där du börjar dra"),
	]))
	row.add_child(_section("Ö", [
		_tool_button("Rita land", Brush.Tool.LAND_ADD, null, "Dra ut ön i luften (Shift: sudda)"),
		_tool_button("Sudda land", Brush.Tool.LAND_REMOVE, null, "Ta bort land (Shift: rita)"),
	]))
	row.add_child(_section("Undersida", [
		_tool_button("Sudda under", Brush.Tool.CARVE, null, "Sudda bort öns undersida nedifrån, upp till det ljusa berget under jorden. Fungerar bäst med kameran under ön (Shift: bygg på igen)"),
		_tool_button("Rötter", Brush.Tool.ROOTS, null, "Rita rötter: på marken kryper de över gräs, sten och golv och tippar över kanten; på undersidan och klippan hänger de ner. Reglagen nedanför (Shift: ta bort rötter)"),
	]))
	_root_dials = _root_box()
	_root_dials.visible = false
	row.add_child(_root_dials)
	row.add_child(_section("Vatten", [
		_tool_button("Vatten", Brush.Tool.WATER, null, "Gräv en damm eller bäck. Når vattnet kanten blir det vattenfall (Shift: torka)"),
		_tool_button("Torka", Brush.Tool.DRY, null, "Ta bort vatten och fyll igen gropen (Shift: vatten)"),
	]))
	var paint_buttons := []
	for m in MATERIALS:
		paint_buttons.append(_tool_button(m[0], Brush.Tool.PAINT, m, m[4]))
	row.add_child(_section("Måla", paint_buttons))

	var sliders := _column("Pensel")
	_size_slider = _slider("Storlek", 0.4, 6.0, brush.radius, func(v: float) -> void: brush.radius = v)
	_strength_slider = _slider("Styrka", 0.0, 1.0, brush.strength, func(v: float) -> void: brush.strength = v, "%")
	sliders.add_child(_size_slider.get_parent())
	sliders.add_child(_strength_slider.get_parent())
	var dense := _slider("Täthet", 0.0, 1.0, brush.density, func(v: float) -> void: brush.density = v, "%")
	(dense.get_parent() as Control).tooltip_text = "Hur tätt det som målas ut står"
	var clump := _slider("Klungor", 0.0, 1.0, brush.clumping, func(v: float) -> void: brush.clumping = v, "%")
	(clump.get_parent() as Control).tooltip_text = "Jämnt utspritt, eller samlat i grupper; småsten samlas kring stenblockens fot"
	for sl in [dense, clump]:
		sliders.add_child(sl.get_parent())
		_scatter_dials.append(sl.get_parent())
	body.add_child(sliders)
	_brush_dials = sliders

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 64
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	var hint := Label.new()
	hint.text = "Vänster: verktyg   Shift: omvänt   Höger: rotera   Mitten: panorera   Hjul: zooma   [ ]: storlek   Tab: göm panelen"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = -20
	hint.offset_right = -20
	hint.offset_top = 18
	root.add_child(hint)

	brush.tool_changed.connect(_sync)
	(_group.get_buttons()[0] as Button).button_pressed = true


## The Växter page: what can be placed, grouped, wrapping onto two lines.
func _plants_row() -> Control:
	var flow := _page()
	for group in PLANTS:
		var items := []
		for kind in group[1]:
			items.append(_place_button(kind))
		flow.add_child(_section(group[0], items))
	var eraser := _tool_button("Ta bort", Brush.Tool.REMOVE, null, "Ta bort allt under penseln")
	flow.add_child(_section("Verktyg", [eraser]))
	for kind in Catalog.KINDS:
		if Catalog.KINDS[kind].has("style"):
			var box := _kind_box(kind)
			box.visible = false
			flow.add_child(box)
			_kind_dials[kind] = box
	return flow


## The style dials of one generated kind. Like the roots' dials they set the
## next ones painted and restyle the last stroke's.
func _kind_box(kind: String) -> Control:
	var p = main.props
	var box := _column(Catalog.KINDS[kind].label)
	var st: Dictionary = p.style_for(kind)
	var dials := []
	for spec in Catalog.STONE_DIALS:
		var key: String = spec[1]
		var lo: float = spec[2]
		var hi: float = spec[3]
		if key == "size":
			hi = maxf(hi, float(st.size) * 3.0)
			lo = minf(lo, float(st.size) * 0.3)
		var sl := _slider(spec[0], lo, hi, st[key], func(v: float) -> void: p.set_style(kind, key, v), spec[4])
		sl.drag_started.connect(func() -> void: brush.push_undo())
		(sl.get_parent() as Control).tooltip_text = spec[5] + ". Ändrar också det senast målade"
		box.add_child(sl.get_parent())
		dials.append([sl, key])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "Färg"
	l.custom_minimum_size.x = 86
	line.add_child(l)
	var pick := ColorPickerButton.new()
	var t: Array = st.tint
	pick.color = Color(t[0], t[1], t[2])
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(54, 26)
	pick.focus_mode = Control.FOCUS_NONE
	pick.color_changed.connect(func(c: Color) -> void: p.set_style(kind, "tint", [c.r, c.g, c.b]))
	line.add_child(pick)
	var reset := Button.new()
	reset.text = "Grundstil"
	reset.focus_mode = Control.FOCUS_NONE
	reset.theme_type_variation = "SmallButton"
	reset.pressed.connect(func() -> void:
		brush.push_undo()
		var fresh: Dictionary = (Catalog.KINDS[kind].style as Dictionary).duplicate(true)
		for key in fresh:
			p.set_style(kind, key, fresh[key])
		for d in dials:
			(d[0] as HSlider).set_value_no_signal(fresh[d[1]])
			_show(d[0])
		pick.color = Color(fresh.tint[0], fresh.tint[1], fresh.tint[2]))
	line.add_child(reset)
	box.add_child(line)
	return box


## The Väder page: the hour and the moon, and the weather. Nothing here is
## painted, so the brush dials stay but do nothing.
func _weather_row() -> Control:
	var row := _page()
	var w = weather
	var sky := VBoxContainer.new()
	sky.add_theme_constant_override("separation", 4)
	sky.add_child(_header("Himmel"))
	var hour := _slider("Tid", 0.0, 24.0, w.hour, func(v: float) -> void: w.hour = v, "h", 0.25)
	sky.add_child(hour.get_parent())
	sky.add_child(_slider("Måne", 0.0, 1.0, w.moon_phase, func(v: float) -> void: w.moon_phase = v, "moon").get_parent())
	sky.add_child(_slider("Moln", 0.0, 1.0, w.clouds, func(v: float) -> void: w.clouds = v, "%").get_parent())
	row.add_child(sky)
	var wet := VBoxContainer.new()
	wet.add_theme_constant_override("separation", 4)
	wet.add_child(_header("Väder"))
	wet.add_child(_slider("Dimma", 0.0, 1.0, w.fog, func(v: float) -> void: w.fog = v, "%").get_parent())
	wet.add_child(_slider("Regn", 0.0, 1.0, w.rain, func(v: float) -> void: w.rain = v, "%").get_parent())
	wet.add_child(_slider("Snö", 0.0, 1.0, w.snow, func(v: float) -> void: w.snow = v, "%").get_parent())
	row.add_child(wet)
	var life := VBoxContainer.new()
	life.add_theme_constant_override("separation", 4)
	life.add_child(_header("Liv"))
	life.add_child(_slider("Vind", 0.0, 1.0, w.wind, func(v: float) -> void: w.wind = v, "%").get_parent())
	life.add_child(_slider("Eldflugor", 0.0, 1.0, w.fireflies, func(v: float) -> void: w.fireflies = v, "%").get_parent())
	var flow := Button.new()
	flow.text = "Låt tiden gå"
	flow.toggle_mode = true
	flow.focus_mode = Control.FOCUS_NONE
	flow.tooltip_text = "Ett dygn tar fyra minuter, och månen går genom sina faser på åtta dygn"
	flow.toggled.connect(func(on: bool) -> void: w.time_flows = on)
	life.add_child(flow)
	row.add_child(life)
	# while time flows, the dial follows the clock
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if w.time_flows:
			hour.set_value_no_signal(w.hour)
			_show(hour))
	row.add_child(timer)
	buttons["Låt tiden gå"] = flow
	return row


## The Ljus page: tints laid over the hour's colours, white leaving them as
## they are, and dials for the light itself.
func _light_row() -> Control:
	var row := _page()
	var w = weather
	var tints := GridContainer.new()
	tints.columns = 4
	tints.add_theme_constant_override("h_separation", 8)
	tints.add_theme_constant_override("v_separation", 6)
	var tint_col := VBoxContainer.new()
	tint_col.add_theme_constant_override("separation", 4)
	tint_col.add_child(_header("Färgton"))
	tint_col.add_child(tints)
	var pickers := []
	for pair in [["Himmel", "tint_top"], ["Horisont", "tint_horizon"], ["Under", "tint_bottom"],
			["Moln", "tint_clouds"], ["Sol", "tint_sun"], ["Dimma", "tint_fog"]]:
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size.x = 76
		tints.add_child(l)
		var key: String = pair[1]
		var pick := ColorPickerButton.new()
		pick.color = w.get(key)
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(54, 26)
		pick.focus_mode = Control.FOCUS_NONE
		pick.tooltip_text = "Vit lämnar dygnets färg som den är"
		pick.color_changed.connect(func(c: Color) -> void: w.set(key, c))
		tints.add_child(pick)
		pickers.append([pick, key])
	row.add_child(tint_col)
	var dials := VBoxContainer.new()
	dials.add_theme_constant_override("separation", 4)
	dials.add_child(_header("Ljus"))
	var sliders := []
	for spec in [["Sol", "sun_strength", 0.0, 2.5], ["Omgivning", "ambient", 0.0, 2.5], ["Exponering", "exposure", 0.4, 2.0]]:
		var key: String = spec[1]
		var sl := _slider(spec[0], spec[2], spec[3], w.get(key), func(v: float) -> void: w.set(key, v), "x")
		dials.add_child(sl.get_parent())
		sliders.append([sl, key])
	row.add_child(dials)
	var reset := Button.new()
	reset.text = "Återställ ljuset"
	reset.focus_mode = Control.FOCUS_NONE
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		for p in pickers:
			w.set(p[1], Color.WHITE)
			(p[0] as ColorPickerButton).color = Color.WHITE
		var defaults := {"sun_strength": 1.0, "ambient": 1.0, "exposure": 1.0}
		for s in sliders:
			w.set(s[1], defaults[s[1]])
			(s[0] as HSlider).set_value_no_signal(defaults[s[1]])
			_show(s[0]))
	dials.add_child(reset)
	return row


## The Kamera page: the lens, where the camera stands, and its two waves.
func _camera_row() -> Control:
	var row := _page()
	var r = rig
	var lens := VBoxContainer.new()
	lens.add_theme_constant_override("separation", 4)
	lens.add_child(_header("Lins"))
	lens.add_child(_slider("Brännvidd", 18.0, 200.0, r.focal_mm, func(v: float) -> void: r.focal_mm = v, "mm", 1.0).get_parent())
	lens.add_child(_slider("Fokus", -15.0, 15.0, r.focus_offset, func(v: float) -> void: r.focus_offset = v, "m", 0.1).get_parent())
	lens.add_child(_slider("Bländare", 0.0, 1.0, r.aperture, func(v: float) -> void: r.aperture = v, "%").get_parent())
	row.add_child(lens)
	var place := VBoxContainer.new()
	place.add_theme_constant_override("separation", 4)
	place.add_child(_header("Bild"))
	_cam_sliders.zoom = _slider("Zoom", 10.0, 140.0, r.goal_distance, func(v: float) -> void: r.goal_distance = v, "m", 0.5)
	_cam_sliders.yaw = _slider("Vinkel", 0.0, 360.0, fposmod(rad_to_deg(r.goal_yaw), 360.0), func(v: float) -> void: r.goal_yaw = deg_to_rad(v), "deg", 1.0)
	_cam_sliders.pitch = _slider("Höjd", -20.0, 80.0, rad_to_deg(r.goal_pitch), func(v: float) -> void: r.goal_pitch = deg_to_rad(v), "deg", 1.0)
	for k in ["zoom", "yaw", "pitch"]:
		place.add_child(_cam_sliders[k].get_parent())
	row.add_child(place)
	r.moved.connect(_sync_camera)
	var spin := VBoxContainer.new()
	spin.add_theme_constant_override("separation", 4)
	spin.add_child(_header("Rotation"))
	spin.add_child(_slider("Fart", 0.0, 30.0, r.spin_speed, func(v: float) -> void: r.spin_speed = v, "dps", 0.1).get_parent())
	spin.add_child(_slider("Variation", 0.0, 1.0, r.spin_vary, func(v: float) -> void: r.spin_vary = v, "%").get_parent())
	spin.add_child(_slider("Tid", 2.0, 120.0, r.spin_period, func(v: float) -> void: r.spin_period = v, "s", 1.0).get_parent())
	var way := Button.new()
	way.toggle_mode = true
	way.button_pressed = not r.spin_clockwise
	way.text = "Motsols" if way.button_pressed else "Medsols"
	way.tooltip_text = "Vilket håll kameran går runt ön, sett uppifrån"
	way.focus_mode = Control.FOCUS_NONE
	way.toggled.connect(func(on: bool) -> void:
		r.spin_clockwise = not on
		way.text = "Motsols" if on else "Medsols")
	buttons["Medsols"] = way
	spin.add_child(_wave_box(r, "spin_shape", "spin_phase", way, "Fartens våg: dra punkterna för att forma den"))
	row.add_child(spin)
	var lift := VBoxContainer.new()
	lift.add_theme_constant_override("separation", 4)
	lift.add_child(_header("Höjdvåg"))
	lift.add_child(_slider("Styrka", 0.0, 8.0, r.bob, func(v: float) -> void: r.bob = v, "m", 0.1).get_parent())
	lift.add_child(_slider("Tid", 2.0, 120.0, r.bob_period, func(v: float) -> void: r.bob_period = v, "s", 1.0).get_parent())
	lift.add_child(_wave_box(r, "bob_shape", "bob_phase", null, "Kamerans väg upp och ner: dra punkterna för att forma den"))
	row.add_child(lift)
	return row


## The Effekter page: the finish on the picture (see post.gd). Glow and the
## volumetric light are Godot's own; the shafts, grading and lens are a
## screen pass of ours.
func _effects_row() -> Control:
	var row := _page()
	var p = main.post
	var w = weather
	var dials := []   # [slider, object, key]
	var add := func(box: Control, label: String, obj, key: String, lo: float, hi: float, unit: String, tip: String) -> void:
		var sl := _slider(label, lo, hi, obj.get(key), func(v: float) -> void: obj.set(key, v), unit)
		(sl.get_parent() as Control).tooltip_text = tip
		box.add_child(sl.get_parent())
		dials.append([sl, obj, key])
	var glow := _column("Glöd")
	add.call(glow, "Styrka", p, "glow", 0.0, 2.0, "x", "Hur mycket ljusa ytor glöder")
	add.call(glow, "Bloom", p, "glow_bloom", 0.0, 0.2, "%", "Låter hela bilden blöda lite ljus, inte bara det starkaste")
	add.call(glow, "Tröskel", p, "glow_threshold", 0.3, 2.0, "x", "Hur ljust något måste vara för att glöda")
	row.add_child(glow)
	var light := _column("Ljusstrålar")
	add.call(light, "Strålar", p, "rays", 0.0, 1.5, "%", "Solstrålar som strömmar ut från solen när den syns i bild")
	add.call(light, "Längd", p, "ray_length", 0.2, 1.0, "%", "Hur långt strålarna når från solen")
	add.call(light, "Volymljus", p, "volume", 0.0, 1.0, "%", "Ett dis i luften som solen lyser upp, så att ljuset faller i skaft mellan träd och murar")
	add.call(light, "Ljus i dis", p, "volume_glow", 0.0, 3.0, "x", "Hur starkt solen och månen lyser upp diset")
	row.add_child(light)
	var colour := _column("Färg")
	add.call(colour, "Kontrast", p, "contrast", 0.6, 1.6, "x", "")
	add.call(colour, "Ljushet", p, "brightness", 0.6, 1.5, "x", "")
	add.call(colour, "Mättnad", w, "saturation", 0.0, 2.0, "x", "Mer eller mindre färg; dygnet ändrar den också")
	add.call(colour, "Temperatur", p, "temperature", -1.0, 1.0, "signed", "Kallare åt vänster, varmare åt höger")
	add.call(colour, "Färgton", p, "tint", -1.0, 1.0, "signed", "Grönare åt vänster, mer magenta åt höger")
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	var pickers := []
	for pair in [["Skuggor", "shadow_tint"], ["Högdagrar", "highlight_tint"]]:
		var l := Label.new()
		l.text = pair[0]
		split.add_child(l)
		var key: String = pair[1]
		var pick := ColorPickerButton.new()
		pick.color = p.get(key)
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(46, 26)
		pick.focus_mode = Control.FOCUS_NONE
		pick.tooltip_text = "En färgton i " + pair[0].to_lower() + "; vit lämnar dem som de är"
		pick.color_changed.connect(func(c: Color) -> void: p.set(key, c))
		split.add_child(pick)
		pickers.append(pick)
	colour.add_child(split)
	row.add_child(colour)
	var lens := _column("Lins och film")
	add.call(lens, "Vinjett", p, "vignette", 0.0, 1.0, "%", "Mörkare hörn")
	add.call(lens, "Filmkorn", p, "grain", 0.0, 1.0, "%", "Korn som på film")
	add.call(lens, "Färgfransar", p, "aberration", 0.0, 1.0, "%", "Färgerna glider isär ut mot hörnen, som i en enkel lins")
	add.call(lens, "Skärpa", p, "sharpen", 0.0, 1.0, "%", "Skärper kanterna")
	add.call(lens, "Hörnskugga", p, "occlusion", 0.0, 2.0, "x", "Skuggan i vrår och där saker möter marken")
	row.add_child(lens)
	var reset := Button.new()
	reset.text = "Återställ effekterna"
	reset.focus_mode = Control.FOCUS_NONE
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		p.reset()
		w.saturation = 1.0
		for d in dials:
			(d[0] as HSlider).set_value_no_signal(d[1].get(d[2]))
			_show(d[0])
		for pick in pickers:
			(pick as ColorPickerButton).color = Color.WHITE)
	row.add_child(reset)
	buttons["Återställ effekterna"] = reset
	return row


## The roots' dials. They set the next roots drawn and restyle the last
## ones, so roots can be drawn first and tuned after.
func _root_box() -> Control:
	var box := _column("Rötter")
	var r = main.roots
	var dials := []
	for spec in [["Storlek", "size", 0.25, 3.0, "x", "Skalar hela rotsystemet: längd, bredd och tjocklek tillsammans, så formen blir densamma"],
			["Längd", "length", 1.0, 8.0, "m", "Hur långt rötterna når"],
			["Bredd", "spread", 0.3, 4.0, "m", "Hur brett de breder ut sig"],
			["Tjocklek", "thickness", 0.2, 3.0, "x", "Hur grova de är"],
			["Täthet", "branching", 0.0, 1.0, "%", "Hur tätt rötterna söker sig fram: glest ger få långa rötter, tätt ett fint nät"],
			["Grenar", "max_kids", 1.0, 4.0, "count", "Högst så många grenar ur varje klyka; 1 ger ogrenade rötter", 1.0],
			["Mellanrum", "fork_gap", 0.0, 2.0, "m", "Minsta sträcka längs en rot mellan två klykor"],
			["Vinkel", "fork_angle", 10.0, 90.0, "deg", "Vinkeln som en ny gren lämnar sin rot i", 1.0],
			["Djup", "fork_depth", 1.0, 8.0, "count", "Hur många gånger en rot får dela sig, led efter led", 1.0],
			["Slingring", "curl", 0.0, 1.0, "%", "Raka, eller slingrande som ormar"],
			["Klättra", "climb", 0.0, 1.0, "%", "Hur gärna rötterna klättrar över murar, pelare och stenar i stället för att gå runt dem"],
			["Tyngd", "hang", 0.0, 1.0, "%", "Hängande rötter: rakt ner, eller ut åt sidan. På marken: hur långt de faller över kanten"],
			["Bark", "bark", 0.0, 1.0, "%", "Slät målad färg, eller full barktextur"]]:
		var key: String = spec[1]
		var sl := _slider(spec[0], spec[2], spec[3], r.style[key], func(v: float) -> void: r.set_style(key, v), spec[4], spec[6] if spec.size() > 6 else 0.01)
		sl.drag_started.connect(func() -> void: brush.push_undo())
		(sl.get_parent() as Control).tooltip_text = spec[5] + ". Ändrar också de senast ritade rötterna"
		box.add_child(sl.get_parent())
		dials.append([sl, key])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "Färg"
	l.custom_minimum_size.x = 86
	line.add_child(l)
	var pick := ColorPickerButton.new()
	var t: Array = r.style.tint
	pick.color = Color(t[0], t[1], t[2])
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(54, 26)
	pick.focus_mode = Control.FOCUS_NONE
	pick.tooltip_text = "Rötternas färg"
	pick.color_changed.connect(func(c: Color) -> void: r.set_style("tint", [c.r, c.g, c.b]))
	line.add_child(pick)
	var reset := Button.new()
	reset.text = "Stiliserat"
	reset.tooltip_text = "Tillbaka till grundstilen: grova, mjuka och få grenar"
	reset.focus_mode = Control.FOCUS_NONE
	reset.theme_type_variation = "SmallButton"
	reset.pressed.connect(func() -> void:
		brush.push_undo()
		var fresh: Dictionary = r.RootBuilder.style_of(null)
		for k in fresh:
			r.set_style(k, fresh[k])
		for d in dials:
			(d[0] as HSlider).set_value_no_signal(fresh[d[1]])
			_show(d[0])
		pick.color = Color(fresh.tint[0], fresh.tint[1], fresh.tint[2]))
	line.add_child(reset)
	box.add_child(line)
	return box


## A titled column of dials.
func _column(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_header(title))
	return box


## One tab's page: its parts stacked down the panel.
func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return page


## The Export page: a still, a film of the camera's waves, or a looping
## wallpaper. Everything lands in Bilder\Floating Island.
func _export_row() -> Control:
	var row := _page()
	var r = rig
	var out := VBoxContainer.new()
	out.add_theme_constant_override("separation", 6)
	out.add_child(_header("Upplösning och längd"))
	var res := OptionButton.new()
	for label in ["1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160"]:
		res.add_item(label)
	res.select(1)
	res.focus_mode = Control.FOCUS_NONE
	var length := _slider("Längd", 3.0, 120.0, 12.0, func(_v: float) -> void: pass, "s", 1.0)
	var size_of := func() -> Vector2i:
		return [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)][res.selected]
	out.add_child(res)
	out.add_child(length.get_parent())
	row.add_child(out)
	var make := VBoxContainer.new()
	make.add_theme_constant_override("separation", 6)
	make.add_child(_header("Exportera"))
	var shots := HBoxContainer.new()
	shots.add_theme_constant_override("separation", 6)
	var still := Button.new()
	still.text = "Bild"
	still.tooltip_text = "Spara en stillbild utan panelen"
	still.pressed.connect(func() -> void:
		var path: String = await main.IslandFile.still(main, size_of.call())
		toast("Bilden sparades: " + path.get_file()))
	var film := Button.new()
	film.text = "Film"
	film.tooltip_text = "Spela in kamerans rotation och höjdvåg i ett eget fönster, så lång som Längd"
	film.pressed.connect(func() -> void:
		var path: String = main.IslandFile.film(main, length.value, size_of.call(), false)
		toast("Filmen spelas in i ett eget fönster: " + path.get_file()))
	var wall := Button.new()
	wall.text = "Bakgrund"
	wall.tooltip_text = "En sömlös loop: ett helt varv runt ön med hela vågor, eller en höjdvåg om kameran står still"
	wall.pressed.connect(func() -> void:
		var path: String = main.IslandFile.film(main, length.value, size_of.call(), true)
		toast("Loopen spelas in: " + path.get_file() + ". Lägg den i Lively Wallpaper som bakgrund."))
	for b in [still, film, wall]:
		b.focus_mode = Control.FOCUS_NONE
		shots.add_child(b)
		buttons[b.text] = b
	make.add_child(shots)
	var note := Label.new()
	note.text = "Filmer spelas in i ett eget fönster, ungefär fem gånger långsammare än filmen är lång. Bakgrunden blir en loop för Lively Wallpaper (gratis) eller Wallpaper Engine."
	note.add_theme_font_size_override("font_size", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 200
	note.add_theme_color_override("font_color", Color(INK, 0.65))
	make.add_child(note)
	row.add_child(make)
	return row


func _sync_camera() -> void:
	_cam_sliders.zoom.set_value_no_signal(rig.goal_distance)
	_cam_sliders.yaw.set_value_no_signal(fposmod(rad_to_deg(rig.goal_yaw), 360.0))
	_cam_sliders.pitch.set_value_no_signal(rad_to_deg(rig.goal_pitch))
	for k in ["zoom", "yaw", "pitch"]:
		_show(_cam_sliders[k])


## A wave editor with a reset button under it.
func _wave_box(r, shape_key: String, phase_key: String, beside: Control, tip: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var ed := WaveEditor.new()
	ed.rig = r
	ed.shape_key = shape_key
	ed.phase_key = phase_key
	ed.custom_minimum_size = Vector2(210, 52)
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.tooltip_text = tip
	box.add_child(ed)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	if beside:
		line.add_child(beside)
	var reset := Button.new()
	reset.text = "Sinus"
	reset.tooltip_text = "Tillbaka till en ren sinusvåg"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		var fresh: Array = r.sine_shape()
		var shape: Array = r.get(shape_key)
		for k in shape.size():
			shape[k] = fresh[k]
		ed.queue_redraw())
	line.add_child(reset)
	box.add_child(line)
	return box


## One period of a wave, drawn by hand: drag a point up or down; the curve
## through the points repeats, so the right edge runs on into the left. A
## dot rides the curve where the camera is now.
class WaveEditor extends Control:
	var rig
	var shape_key := ""
	var phase_key := ""
	var _drag := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(_delta: float) -> void:
		queue_redraw()

	func _shape() -> Array:
		return rig.get(shape_key)

	func _amp() -> float:
		return size.y * 0.42

	func _point(k: int) -> Vector2:
		var shape := _shape()
		return Vector2((k + 0.5) / shape.size() * size.x, size.y * 0.5 - float(shape[k]) * _amp())

	func _gui_input(event: InputEvent) -> void:
		var shape := _shape()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var best := 0
				for k in shape.size():
					if absf(_point(k).x - event.position.x) < absf(_point(best).x - event.position.x):
						best = k
				_drag = best
				_set_value(event.position.y)
			else:
				_drag = -1
			accept_event()
		elif event is InputEventMouseMotion and _drag >= 0:
			_set_value(event.position.y)
			accept_event()

	func _set_value(y: float) -> void:
		_shape()[_drag] = clampf((size.y * 0.5 - y) / _amp(), -1.0, 1.0)

	func _draw() -> void:
		var ink := Color(0.27, 0.21, 0.16)
		var w := size.x
		var mid := size.y * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), true)
		draw_line(Vector2(0, mid), Vector2(w, mid), Color(ink, 0.15), 1.0)
		var shape := _shape()
		var pts := PackedVector2Array()
		for k in 81:
			var t := float(k) / 80.0
			# the points sit at the middle of their slots, so shift by half a slot
			var v: float = rig.wave(shape, t - 0.5 / shape.size())
			pts.append(Vector2(t * w, mid - v * _amp()))
		draw_polyline(pts, Color(0.47, 0.6, 0.36), 2.0, true)
		for k in shape.size():
			draw_circle(_point(k), 4.5 if k == _drag else 3.5, Color(1, 1, 1))
			draw_arc(_point(k), 4.5 if k == _drag else 3.5, 0.0, TAU, 16, Color(0.47, 0.6, 0.36), 1.5, true)
		var ph: float = rig.get(phase_key)
		var x := fposmod(ph + 0.5 / shape.size(), 1.0)
		draw_circle(Vector2(x * w, mid - rig.wave(shape, ph) * _amp()), 4.0, ink)


## Fold the panel away to its tab on the edge, or bring it back.
func set_collapsed(on: bool) -> void:
	collapsed = on
	var away := float(DOCK_WIDTH + MARGIN * 2)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if on:
		_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tw.tween_property(_dock, "offset_left", MARGIN - away, 0.22)
		tw.parallel().tween_property(_dock, "offset_right", MARGIN + DOCK_WIDTH - away, 0.22)
		tw.tween_callback(func() -> void:
			_dock.visible = false
			_handle.visible = true)
	else:
		_handle.visible = false
		_dock.visible = true
		_dock.mouse_filter = Control.MOUSE_FILTER_STOP
		tw.tween_property(_dock, "offset_left", MARGIN, 0.22)
		tw.parallel().tween_property(_dock, "offset_right", MARGIN + DOCK_WIDTH, 0.22)


func _process(_delta: float) -> void:
	# keep the island in the middle of the free part of the screen
	var width := get_viewport().get_visible_rect().size.x
	var shift := 0.0
	if visible and not collapsed:
		# negative: the picture moves right, away from the panel on the left
		shift = -(DOCK_WIDTH + MARGIN * 2) * 0.5 / maxf(width, 1.0)
	rig.frame_shift = shift


## The tabs as a grid of buttons, two rows in the narrow panel. It answers
## like a TabBar: current_tab and tab_changed.
class TabGrid extends GridContainer:
	signal tab_changed(tab: int)
	var _group := ButtonGroup.new()
	var _current := 0
	var current_tab: int:
		get:
			return _current
		set(v):
			if v >= 0 and v < get_child_count():
				(get_child(v) as Button).button_pressed = true

	func add_tab(title: String) -> void:
		var k := get_child_count()
		var b := Button.new()
		b.text = title
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "TabButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = k == 0
		b.toggled.connect(func(on: bool) -> void:
			if on and _current != k:
				_current = k
				tab_changed.emit(k))
		add_child(b)


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.0)


func _save_dialog() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.island ; Flytande ö"])
	d.current_dir = main.IslandFile.folder()
	d.current_file = "Min ö.island"
	d.file_selected.connect(func(path: String) -> void:
		if not path.ends_with(".island"):
			path += ".island"
		var err: int = main.IslandFile.save(main, path)
		toast("Sparad: " + path.get_file() if err == OK else "Kunde inte spara (%s)" % error_string(err)))
	add_child(d)
	d.popup_centered()


func _open_dialog() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.island ; Flytande ö"])
	d.current_dir = main.IslandFile.folder()
	d.file_selected.connect(func(path: String) -> void:
		var err: int = main.IslandFile.open(main, path)
		if err == OK:
			_after_open()
		toast("Öppnade " + path.get_file() if err == OK else "Kunde inte öppna (%s)" % error_string(err)))
	add_child(d)
	d.popup_centered()


## A different island is open: build the panel afresh, so every dial
## shows its settings.
func _after_open() -> void:
	main.call_deferred("rebuild_ui")


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_TAB and not k.ctrl_pressed:
		set_collapsed(not collapsed)
		get_viewport().set_input_as_handled()
	elif k and k.pressed and k.ctrl_pressed:
		if k.keycode == KEY_S:
			_save_dialog()
		elif k.keycode == KEY_O:
			_open_dialog()


## The Ruiner page: what to build, and the two dials for ruins: how tall new
## pieces stand and how old everything is.
func _ruins_row() -> Control:
	var row := _page()
	row.add_child(_section("Bygg", [
		_tool_button("Mur", Brush.Tool.WALL, null, "Dra en mur längs marken; börja eller sluta vid en annan bit så hänger de ihop"),
		_tool_button("Pelare", Brush.Tool.PILLAR, null, "Klicka för en pelare"),
		_tool_button("Valv", Brush.Tool.ARCH, null, "Dra från den ena foten till den andra. Längs en mur blir valvet en öppning i muren"),
		_tool_button("Trappa", Brush.Tool.STAIRS, null, "Dra från nedersta steget uppåt"),
		_tool_button("Golv", Brush.Tool.FLOOR, null, "Måla stengolv på marken, eller mer av en våning du börjar på"),
		_tool_button("Övervåning", Brush.Tool.STOREY, null, "Klicka på en trappa, pelare, mur eller ett golv och måla: en ny våning läggs på dess topp. På bar mark hamnar den en Höjd upp"),
	]))
	row.add_child(_section("Öppningar", [
		_tool_button("Dörr", Brush.Tool.DOOR, null, "Klicka på en mur för en dörröppning, dra längs muren för fler"),
		_tool_button("Fönster", Brush.Tool.WINDOW, null, "Klicka på en mur för ett fönster, dra längs muren för fler"),
	]))
	row.add_child(_section("Verktyg", [
		_tool_button("Riv", Brush.Tool.DEMOLISH, null, "Riv det som står under penseln; murar kapas bara där"),
	]))
	var dials := VBoxContainer.new()
	dials.add_theme_constant_override("separation", 4)
	dials.add_child(_header("Ruin"))
	var height := _slider("Höjd", 0.5, 5.0, brush.ruin_height, func(v: float) -> void: brush.ruin_height = v, "m", 0.1)
	dials.add_child(height.get_parent())
	# moss follows the dial live; stones fall when you let go
	var age := _slider("Ålder", 0.0, 1.0, ruins.age, func(v: float) -> void: ruins.material.set_shader_parameter("age", v), "%")
	age.drag_started.connect(func() -> void: brush.push_undo())
	age.drag_ended.connect(func(_changed: bool) -> void: ruins.set_age(age.value))
	ruins.age_changed.connect(func(v: float) -> void:
		age.set_value_no_signal(v)
		_show(age))
	dials.add_child(age.get_parent())
	row.add_child(dials)
	return row


func _place_button(kind: String) -> Button:
	var label: String = Catalog.KINDS[kind].label
	var b := _tool_button(label, Brush.Tool.PLACE, null, label + ": klicka för en, håll och dra för fler (Shift: ta bort " + label.to_lower() + ")")
	for c in b.toggled.get_connections():
		b.toggled.disconnect(c.callable)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			brush.set_tool(Brush.Tool.PLACE, Color(0, 0, 0, 0), 0.0, kind))
	return b


func _show_page(page: int) -> void:
	for k in _pages.size():
		_pages[k].visible = k == page
	# the brush dials mean nothing on the weather page
	_brush_dials.visible = page < 3
	# pick the first tool on the page, so the brush matches what is shown
	for b in (_pages[page] as Control).find_children("*", "Button", true, false):
		if (b as Button).button_group == _group:
			(b as Button).button_pressed = true
			return


func _sync() -> void:
	if _root_dials:
		_root_dials.visible = brush.tool == Brush.Tool.ROOTS
	var placing: bool = brush.tool == Brush.Tool.PLACE
	for d in _scatter_dials:
		(d as Control).visible = placing
	for kind in _kind_dials:
		(_kind_dials[kind] as Control).visible = placing and brush.place_kind == kind
	_size_slider.set_value_no_signal(brush.radius)
	_show(_size_slider)


func _section(title: String, items: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_header(title))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for b in items:
		row.add_child(b)
	box.add_child(row)
	return box


func _header(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(INK, 0.6))
	return l


func _tool_button(label: String, t: int, material, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	buttons[label] = b
	var target := Color(0, 0, 0, 0)
	var stones := 0.0
	if material != null:
		target = material[1]
		stones = material[3]
		b.icon = _swatch(material[2])
	b.toggled.connect(func(on: bool) -> void:
		if on:
			brush.set_tool(t, target, stones))
	return b


## A labelled slider with its value shown beside it: unit "m" shows metres,
## "%" a percentage.
func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable, unit := "m", step := 0.01) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 86
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(100, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	row.add_child(s)
	var shown := Label.new()
	shown.custom_minimum_size.x = 84 if unit == "moon" else 56
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(shown)
	s.set_meta("shown", shown)
	s.set_meta("unit", unit)
	s.value_changed.connect(func(_v: float) -> void: _show(s))
	_show(s)
	return s


static func _show(s: HSlider) -> void:
	var shown: Label = s.get_meta("shown")
	var unit: String = s.get_meta("unit")
	if unit == "%":
		shown.text = "%d %%" % int(round(s.value * 100.0))
	elif unit == "h":
		var minutes := int(round(s.value * 60.0)) % (24 * 60)
		shown.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	elif unit == "x":
		shown.text = ("×%.2f" % s.value).replace(".", ",")
	elif unit == "mm":
		shown.text = "%d mm" % int(round(s.value))
	elif unit == "deg":
		shown.text = "%d°" % int(round(s.value))
	elif unit == "dps":
		shown.text = ("%.1f °/s" % s.value).replace(".", ",")
	elif unit == "s":
		shown.text = "%d s" % int(round(s.value))
	elif unit == "count":
		shown.text = "%d" % int(round(s.value))
	elif unit == "signed":
		shown.text = ("%+.2f" % s.value).replace(".", ",") if absf(s.value) > 0.004 else "0"
	elif unit == "moon":
		var names := ["Nymåne", "Växande", "Halvmåne", "Växande", "Fullmåne", "Avtagande", "Halvmåne", "Avtagande"]
		shown.text = names[int(round(s.value * 8.0)) % 8]
	else:
		shown.text = ("%.1f m" % s.value).replace(".", ",")


static func _swatch(c: Color) -> ImageTexture:
	var n := 16
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
			var a := clampf(n * 0.5 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 15

	var panel := StyleBoxFlat.new()
	panel.bg_color = PAPER
	panel.set_corner_radius_all(20)
	panel.set_content_margin_all(16)
	panel.content_margin_top = 10
	panel.shadow_color = Color(0.1, 0.12, 0.2, 0.18)
	panel.shadow_size = 14
	panel.shadow_offset = Vector2(0, 4)
	th.set_stylebox("panel", "PanelContainer", panel)

	var normal := _chip(CHIP)
	var hover := _chip(CHIP_HOVER)
	var pressed := _chip(ACCENT)
	for cls in ["Button"]:
		th.set_stylebox("normal", cls, normal)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		th.set_stylebox("hover_pressed", cls, pressed)
		th.set_stylebox("focus", cls, StyleBoxEmpty.new())
		th.set_color("font_color", cls, INK)
		th.set_color("font_hover_color", cls, INK)
		th.set_color("font_pressed_color", cls, Color.WHITE)
		th.set_color("font_hover_pressed_color", cls, Color.WHITE)
		th.set_constant("h_separation", cls, 6)
	th.set_color("font_color", "Label", INK)

	var tab_sel := _chip(Color(1, 1, 1, 0.0))
	tab_sel.border_width_bottom = 3
	tab_sel.border_color = ACCENT
	tab_sel.set_corner_radius_all(0)
	var tab_off := _chip(Color(1, 1, 1, 0.0))
	tab_off.set_corner_radius_all(0)
	th.set_stylebox("tab_selected", "TabBar", tab_sel)
	th.set_stylebox("tab_unselected", "TabBar", tab_off)
	th.set_stylebox("tab_hovered", "TabBar", tab_off)
	th.set_stylebox("tab_disabled", "TabBar", tab_off)
	th.set_color("font_selected_color", "TabBar", INK)
	th.set_color("font_unselected_color", "TabBar", Color(INK, 0.7))
	th.set_color("font_hovered_color", "TabBar", INK)
	th.set_color("font_disabled_color", "TabBar", Color(INK, 0.3))
	th.set_font_size("font_size", "TabBar", 16)

	th.set_type_variation("TabButton", "Button")
	var tb_off := _chip(Color(1, 1, 1, 0.0))
	tb_off.set_corner_radius_all(0)
	tb_off.content_margin_left = 2
	tb_off.content_margin_right = 2
	tb_off.border_width_bottom = 3
	tb_off.border_color = Color(ACCENT, 0.0)
	var tb_hover := tb_off.duplicate() as StyleBoxFlat
	tb_hover.border_color = Color(ACCENT, 0.3)
	var tb_on := tb_off.duplicate() as StyleBoxFlat
	tb_on.border_color = ACCENT
	th.set_stylebox("normal", "TabButton", tb_off)
	th.set_stylebox("hover", "TabButton", tb_hover)
	th.set_stylebox("pressed", "TabButton", tb_on)
	th.set_stylebox("hover_pressed", "TabButton", tb_on)
	th.set_color("font_color", "TabButton", Color(INK, 0.7))
	th.set_color("font_hover_color", "TabButton", INK)
	th.set_color("font_pressed_color", "TabButton", INK)
	th.set_color("font_hover_pressed_color", "TabButton", INK)
	th.set_font_size("font_size", "TabButton", 16)

	th.set_type_variation("SmallButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := (th.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		th.set_stylebox(state, "SmallButton", sb)
	th.set_font_size("font_size", "SmallButton", 14)

	th.set_type_variation("Handle", "Button")
	var hd := StyleBoxFlat.new()
	hd.bg_color = PAPER
	hd.corner_radius_top_right = 14
	hd.corner_radius_bottom_right = 14
	hd.content_margin_left = 16
	hd.content_margin_right = 14
	hd.content_margin_top = 10
	hd.content_margin_bottom = 10
	hd.shadow_color = Color(0.1, 0.12, 0.2, 0.18)
	hd.shadow_size = 10
	hd.shadow_offset = Vector2(0, 3)
	var hd_hover := hd.duplicate() as StyleBoxFlat
	hd_hover.bg_color = Color(1, 0.99, 0.96, 0.97)
	th.set_stylebox("normal", "Handle", hd)
	th.set_stylebox("hover", "Handle", hd_hover)
	th.set_stylebox("pressed", "Handle", hd_hover)
	th.set_color("font_color", "Handle", INK)
	th.set_color("font_hover_color", "Handle", INK)
	th.set_color("font_pressed_color", "Handle", INK)

	var sep := StyleBoxLine.new()
	sep.color = Color(INK, 0.12)
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.85, 0.8, 0.72)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _knob(Color(1, 1, 1)))
	th.set_icon("grabber_highlight", "HSlider", _knob(Color(1, 0.98, 0.94)))
	return th


static func _chip(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(11)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func _knob(c: Color) -> ImageTexture:
	var n := 18
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
			var a := clampf(n * 0.5 - 0.5 - r, 0.0, 1.0)
			var edge := clampf(r - (n * 0.5 - 2.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(c.lerp(ACCENT, edge), a))
	return ImageTexture.create_from_image(img)
