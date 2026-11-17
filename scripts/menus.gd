extends CanvasLayer
## The title screen, the pause menu, the settings and the gallery of
## islands: everything round the island that is not the tool panel.
##
## The title lies over the live island, which turns slowly a little way
## off; leaving it glides the camera in and slides the tool panel out. The
## others are paper sheets over a dimmed picture, stacked: the settings
## opened from the pause menu close back to it. Escape closes the sheet on
## top, or opens the pause menu.

const Brand := preload("res://scripts/brand.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")
const Settings := preload("res://scripts/settings.gd")
const IslandFile := preload("res://scripts/island_file.gd")

const INK := Color(0.27, 0.21, 0.16)
const ACCENT := Color(0.47, 0.6, 0.36)
const CARD := Vector2(248, 140)

var main
var buttons := {}   # label -> Button, for the test driver
var on_title := false
## Sections of the settings sheet that other parts fill (the sound levels).
var settings_extra: VBoxContainer
var _root: Control
var _title: Control
var _logo: TextureRect
var _logo_shadow: TextureRect
var _logo_px := 0
var _tagline: Label
var _menu: HBoxContainer
var _begin: Button
var _veil: ColorRect
var _stack: Array[Control] = []
var _pause: Control
var _settings: Control
var _gallery: Control
var _about: Control
var _cards: HFlowContainer
var _soft_leaves: CheckButton
var _fullscreen: CheckButton
var _blank: ImageTexture
var _toast: Label


func setup(main_node, theme: Theme) -> void:
	main = main_node
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)
	_build_title()
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(0.1, 0.12, 0.2, 0.34)
	_veil.modulate.a = 0.0
	_veil.visible = false
	_veil.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close())
	_root.add_child(_veil)
	_toast = Label.new()
	_toast.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 64
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)
	_pause = _build_pause()
	_settings = _build_settings()
	_gallery = _build_gallery()
	_about = _build_about()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if not MeshUtil.web() and bool(Settings.get_value("general", "fullscreen", false)):
		set_fullscreen(true)


# ---------------------------------------------------------------- title

func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.visible = false
	_title.modulate.a = 0.0
	_root.add_child(_title)
	# a soft dusk over the top of the sky, so the name reads against cloud
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.12, 0.2, 0.4, 0.42))
	grad.set_color(1, Color(0.12, 0.2, 0.4, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 128
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_right = 1.0
	shade.anchor_bottom = 0.46
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(shade)
	_logo_shadow = TextureRect.new()
	_logo_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_logo_shadow)
	_logo = TextureRect.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_logo)
	_tagline = Label.new()
	_tagline.text = "Bygg en liten värld i skyn"
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.add_theme_color_override("font_color", Color(1.0, 0.985, 0.95, 0.95))
	_tagline.add_theme_color_override("font_shadow_color", Color(0.08, 0.12, 0.28, 0.4))
	_tagline.add_theme_constant_override("shadow_offset_y", 2)
	_tagline.add_theme_constant_override("shadow_outline_size", 6)
	_tagline.theme_type_variation = "Tagline"
	_tagline.add_theme_font_size_override("font_size", 27)
	_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_tagline)

	_menu = HBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.offset_top = -70
	_menu.offset_bottom = -70
	_title.add_child(_menu)
	_begin = _menu_button(_menu, "Fortsätt", "Fortsätt där du slutade", func() -> void: leave_title(), true)
	_menu_button(_menu, "Ny ö", "Börja på en ny ö. Den du har finns kvar under Mina öar", func() -> void:
		await main.new_island()
		leave_title())
	_menu_button(_menu, "Mina öar", "Alla öar du har byggt", open_gallery)
	_menu_button(_menu, "Inställningar", "", open_settings)
	var quit := _menu_button(_menu, "Avsluta", "", func() -> void: main.quit_game())
	quit.visible = not MeshUtil.web()

	var version := Label.new()
	version.text = "v" + String(ProjectSettings.get_setting("application/config/version", "0.9"))
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	version.add_theme_font_size_override("font_size", 13)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_left = -18
	version.offset_right = -18
	version.offset_top = -14
	version.offset_bottom = -14
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(version)


func _menu_button(into: Control, label: String, tip: String, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "PrimaryButton" if primary else "TitleButton"
	b.pressed.connect(action)
	into.add_child(b)
	buttons[label] = b
	return b


## The name and its line under it, sized to the window.
func _layout() -> void:
	var size := _root.get_viewport_rect().size
	var w := int(clampf(size.x * 0.38, 380.0, 1000.0))
	if absi(w - _logo_px) > 6:
		_logo_px = w
		var img := (load("res://brand/logo.png") as Texture2D).get_image()
		img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		_logo.texture = ImageTexture.create_from_image(img)
	var ts := _logo.texture.get_size()
	var at := Vector2((size.x - ts.x) * 0.5, size.y * 0.035)
	_logo.position = at
	_logo.size = ts
	_tagline.position = Vector2(0.0, at.y + ts.y + 2.0)
	_tagline.size = Vector2(size.x, 30.0)


## Show the title over the island: the camera stands back and turns, the
## tool panel is away.
func show_title() -> void:
	on_title = true
	_begin.text = "Fortsätt" if main.island_path != "" else "Börja bygga"
	_begin.tooltip_text = "Fortsätt där du slutade" if main.island_path != "" else ""
	buttons["Ny ö"].visible = main.island_path != ""
	_title.visible = true
	main.rig.stand_back = 1.3
	main.rig.frame_drop = 0.07
	main.rig.drift = -2.4 if main.rig.spin_speed <= 0.0 else 0.0
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_title, "modulate:a", 1.0, 0.9)


func leave_title() -> void:
	if not on_title:
		return
	on_title = false
	main.rig.stand_back = 1.0
	main.rig.frame_drop = 0.0
	main.rig.drift = 0.0
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: _title.visible = false)
	main.start_play()


# ---------------------------------------------------------------- sheets

## A paper sheet in the middle of the screen with a heading; returns the
## sheet and the column to fill.
func _sheet(title: String, width: float) -> Array:
	var p := PanelContainer.new()
	p.theme_type_variation = "Sheet"
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size.x = width
	p.visible = false
	_root.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	var head := Label.new()
	head.text = title
	head.theme_type_variation = "Heading"
	box.add_child(head)
	return [p, box]


func _open(p: Control) -> void:
	if not _stack.is_empty():
		if _stack.back() == p:
			return
		_stack.back().visible = false
	_stack.append(p)
	_present(p)
	_veil.visible = true
	create_tween().tween_property(_veil, "modulate:a", 1.0, 0.18)


func _present(p: Control) -> void:
	p.visible = true
	p.modulate.a = 0.0
	p.scale = Vector2(0.97, 0.97)
	# its size is only known once laid out
	await get_tree().process_frame
	p.pivot_offset = p.size * 0.5
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.16)
	tw.tween_property(p, "scale", Vector2.ONE, 0.2)


## Close the sheet on top (and with the last one, the dimming).
func close() -> void:
	if _stack.is_empty():
		return
	var p: Control = _stack.pop_back()
	p.visible = false
	if p.has_meta("once"):
		p.queue_free()
	if _stack.is_empty():
		var tw := create_tween()
		tw.tween_property(_veil, "modulate:a", 0.0, 0.16)
		tw.tween_callback(func() -> void:
			if _stack.is_empty():
				_veil.visible = false)
	else:
		_present(_stack.back())


func close_all() -> void:
	while not _stack.is_empty():
		close()


func is_open() -> bool:
	return not _stack.is_empty()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		if not _stack.is_empty():
			close()
		elif not on_title:
			open_pause()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- pause

func _build_pause() -> Control:
	var made := _sheet("Paus", 300.0)
	var box: VBoxContainer = made[1]
	box.add_theme_constant_override("separation", 8)
	(box.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var items := [
		["Tillbaka till ön", "", func() -> void: close(), true],
		["Mina öar ", "Alla öar du har byggt", open_gallery, false],
		["Spara en kopia…", "Spara ön som en fil någon annanstans, till exempel för att skicka den till någon", func() -> void:
			close_all()
			save_copy_dialog(), false],
		["Öppna en fil…", "Öppna en ö från en fil", func() -> void:
			close_all()
			open_file_dialog(), false],
		["Inställningar ", "", open_settings, false],
		["Om Skyholme", "Vem som gjort vad, och licenserna", func() -> void: _open(_about), false],
		["Till titelskärmen", "", func() -> void:
			close_all()
			main.enter_title(), false],
		["Avsluta ", "Ön sparas av sig själv", func() -> void: main.quit_game(), false],
	]
	for it in items:
		var b := _menu_button(box, it[0], it[1], it[2], it[3])
		b.theme_type_variation = "PrimaryButton" if it[3] else "SheetButton"
		b.text = String(it[0]).strip_edges()
	buttons["Avsluta "].visible = not MeshUtil.web()
	return made[0]


func open_pause() -> void:
	_open(_pause)


# ---------------------------------------------------------------- settings

func _build_settings() -> Control:
	var made := _sheet("Inställningar", 420.0)
	var box: VBoxContainer = made[1]
	var p = main.post

	box.add_child(_heading("Språk"))
	var lang := OptionButton.new()
	lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lang.add_item("Svenska")
	lang.add_item("English")
	lang.select(0 if TranslationServer.get_locale().begins_with("sv") else 1)
	lang.focus_mode = Control.FOCUS_NONE
	lang.item_selected.connect(func(i: int) -> void:
		var code := "sv" if i == 0 else "en"
		TranslationServer.set_locale(code)
		Settings.set_value("general", "language", code)
		# the panel puts some of its words together, so it is built afresh
		main.rebuild_ui())
	buttons["Språk"] = lang
	box.add_child(lang)
	settings_extra = VBoxContainer.new()
	settings_extra.add_theme_constant_override("separation", 10)
	box.add_child(settings_extra)

	box.add_child(_heading("Ljud"))
	for bus in ["Musik", "Natur", "Effekter"]:
		box.add_child(_level(bus))
	box.add_child(_heading("Bild"))
	_fullscreen = _check(box, "Helskärm", "Fyll hela skärmen (F11)", is_fullscreen(), func(on: bool) -> void: set_fullscreen(on))
	_fullscreen.visible = not MeshUtil.web()
	_check(box, "Snabbläge", "Billigare kantutjämning, inget studsande ljus, mindre och skarpare solskuggor, grövre dimma och skärpedjup: ungefär 3 ms snabbare per bild. Slås på av sig själv när datorn inte hinner med, tills du väljer här", p.fast, func(on: bool) -> void:
		p.fast = on
		p.fast_chosen = true
		p.save_prefs())
	_soft_leaves = _check(box, "Mjuka bladkanter", "Jämnare kanter på löven. Kronorna blir då ljusare och plattare inuti, och en skog kostar ungefär 2 ms mer per bild. Gör ingenting i Snabbläge", p.soft_leaves, func(on: bool) -> void:
		p.soft_leaves = on
		p.save_prefs())
	_check(box, "Visa bildfrekvens", "Bilder per sekund och millisekunder per bild, nere till höger", p.show_fps, func(on: bool) -> void:
		p.show_fps = on
		p.save_prefs())

	var how := "Vulkan"
	if MeshUtil.lite():
		how = "WebGL 2" if MeshUtil.web() else "OpenGL"
	var info := Label.new()
	info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.text = "%s  ·  %s" % [RenderingServer.get_video_adapter_name(), how]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 200
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(INK, 0.65))
	box.add_child(info)
	var note := Label.new()
	note.text = "Inställningarna sparas på datorn, inte i ön. Bilder och filmer som exporteras får alltid full kvalitet."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 200
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(INK, 0.65))
	box.add_child(note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var done := _menu_button(row, "Klar", "", func() -> void: close(), true)
	done.theme_type_variation = "PrimaryButton"
	box.add_child(row)
	return made[0]


## A slider for one of the sound buses.
func _level(bus: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = bus
	l.custom_minimum_size.x = 96
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = main.audio.level(bus)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(160, 22)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: main.audio.set_level(bus, v))
	row.add_child(s)
	buttons["ljud:" + bus] = s
	return row


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(INK, 0.6))
	return l


func _check(into: Control, label: String, tip: String, on: bool, changed: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = on
	c.toggled.connect(changed)
	into.add_child(c)
	buttons[label] = c
	return c


func open_settings() -> void:
	sync_graphics()
	_open(_settings)


## The switches as the settings stand (they are read from this computer's
## file after the sheet is built, and Snabbläge may turn on by itself).
func sync_graphics() -> void:
	var p = main.post
	if buttons.has("Språk"):
		(buttons["Språk"] as OptionButton).select(0 if TranslationServer.get_locale().begins_with("sv") else 1)
	for pair in [["Snabbläge", p.fast], ["Mjuka bladkanter", p.soft_leaves], ["Visa bildfrekvens", p.show_fps], ["Helskärm", is_fullscreen()]]:
		if buttons.has(pair[0]):
			(buttons[pair[0]] as Button).set_pressed_no_signal(pair[1])


func _process(_delta: float) -> void:
	# soft leaf edges do nothing in Snabbläge (which may turn on by itself)
	if _soft_leaves:
		_soft_leaves.disabled = main.post.fast


func is_fullscreen() -> bool:
	if MeshUtil.web():
		return false
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool) -> void:
	if MeshUtil.web():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	Settings.set_value("general", "fullscreen", on)
	if _fullscreen:
		_fullscreen.set_pressed_no_signal(on)


# ---------------------------------------------------------------- about

## Who made what: the program, the lettering, the textures, and the
## engine's own notice, which must be shown with it.
func _build_about() -> Control:
	var made := _sheet("Om Skyholme", 560.0)
	var box: VBoxContainer = made[1]
	var logo := TextureRect.new()
	var img := (load("res://brand/logo_ink.png") as Texture2D).get_image()
	img.resize(300, int(img.get_height() * 300.0 / img.get_width()), Image.INTERPOLATE_LANCZOS)
	logo.texture = ImageTexture.create_from_image(img)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(logo)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var text := Label.new()
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 15)
	var engine := ""
	for part: Dictionary in Engine.get_copyright_info():
		if String(part.name) == "Godot Engine":
			for p: Dictionary in part.parts:
				engine = ", ".join(p.copyright)
	text.text = "
".join([
		tr("Version %s") % String(ProjectSettings.get_setting("application/config/version", "")),
		"",
		tr("Allt på ön, musiken och ljuden är skapat av programmet självt."),
		"",
		tr("Typsnitt: IM FELL English av Igino Marini (iginomarini.com), SIL Open Font License 1.1."),
		tr("Barkens strukturer: Quaternius (quaternius.com), CC0."),
		"",
		tr("Byggt med Godot Engine (godotengine.org), MIT-licens:"),
		"Copyright " + engine,
		"",
		Engine.get_license_text(),
	])
	scroll.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var done := _menu_button(row, "Stäng ", "", func() -> void: close())
	done.text = "Stäng"
	done.theme_type_variation = "SheetButton"
	box.add_child(row)
	return made[0]


# ---------------------------------------------------------------- gallery

func _build_gallery() -> Control:
	var made := _sheet("Mina öar", 880.0)
	var box: VBoxContainer = made[1]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(848, 452)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_cards = HFlowContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 14)
	_cards.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_cards)
	var row := HBoxContainer.new()
	var note := Label.new()
	note.text = "Öarna sparas av sig själva medan du bygger."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(INK, 0.65))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	var done := _menu_button(row, "Stäng", "", func() -> void: close())
	done.theme_type_variation = "SheetButton"
	box.add_child(row)
	return made[0]


func open_gallery() -> void:
	# the island being built is saved first, so its card is up to date
	if main.playing:
		await main.save_island()
	_fill_gallery()
	_open(_gallery)


func _fill_gallery() -> void:
	for c in _cards.get_children():
		c.queue_free()
	var fresh := Button.new()
	fresh.theme_type_variation = "Card"
	fresh.custom_minimum_size = CARD + Vector2(16, 66)
	fresh.focus_mode = Control.FOCUS_NONE
	fresh.text = "+\nNy ö"
	fresh.add_theme_font_size_override("font_size", 22)
	fresh.pressed.connect(func() -> void:
		close_all()
		await main.new_island()
		leave_title())
	buttons["+ Ny ö"] = fresh
	_cards.add_child(fresh)
	for item: Dictionary in IslandFile.library():
		_cards.add_child(_card(item))


func _card(item: Dictionary) -> Control:
	var card := Button.new()
	card.theme_type_variation = "CardOpen" if item.path == main.island_path else "Card"
	card.custom_minimum_size = CARD + Vector2(16, 66)
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = "Öppna"
	card.pressed.connect(func() -> void: _pick(item.path))
	buttons["ö:" + String(item.name)] = card
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	var frame := Panel.new()
	frame.custom_minimum_size = CARD
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var round := StyleBoxFlat.new()
	round.bg_color = Color(0.62, 0.76, 0.9)
	round.set_corner_radius_all(11)
	frame.add_theme_stylebox_override("panel", round)
	var pic := TextureRect.new()
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item.thumb != null:
		pic.texture = ImageTexture.create_from_image(item.thumb)
	else:
		if _blank == null:
			_blank = Brand.texture(Brand.emblem_svg(false), 256)
		pic.texture = _blank
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(pic)
	v.add_child(frame)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", -2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Label.new()
	name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name.text = item.name
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 16)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name)
	var when := Label.new()
	when.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var t := Time.get_datetime_dict_from_unix_time(int(item.saved) + Time.get_time_zone_from_system().bias * 60)
	when.text = "%04d-%02d-%02d  %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]
	when.add_theme_font_size_override("font_size", 12)
	when.add_theme_color_override("font_color", Color(INK, 0.6))
	when.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(when)
	row.add_child(texts)
	var more := MenuButton.new()
	more.text = "•••"
	more.tooltip_text = "Byt namn, kopiera eller ta bort"
	more.flat = false
	more.theme_type_variation = "SmallButton"
	more.focus_mode = Control.FOCUS_NONE
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pm := more.get_popup()
	pm.add_item("Byt namn", 0)
	pm.add_item("Gör en kopia", 1)
	pm.add_item("Ta bort", 2)
	pm.id_pressed.connect(func(id: int) -> void: _card_action(id, item))
	buttons["•••:" + String(item.name)] = more
	row.add_child(more)
	v.add_child(row)
	return card


## What the three dots on a card offer: another name, a copy, or away
## with it.
func _card_action(id: int, item: Dictionary) -> void:
	if id == 0:
		_ask_text("Vad ska ön heta?", item.name, func(text: String) -> void: _rename(item, text))
	elif id == 1:
		IslandFile.copy(item.path, tr("%s kopia") % item.name)
		_fill_gallery()
	elif id == 2:
		_ask(tr("Ta bort %s? Den läggs i papperskorgen.") % item.name, "Ta bort", func() -> void: _remove(item))


func _rename(item: Dictionary, text: String) -> void:
	var path := IslandFile.rename(item.path, text)
	if item.path == main.island_path:
		main.island_path = path
		main.island_name = text
		Settings.set_value("general", "last_island", path)
	_fill_gallery()


func _remove(item: Dictionary) -> void:
	var open_one: bool = item.path == main.island_path
	IslandFile.remove(item.path)
	if open_one:
		# the island that was open is gone: start on a new one
		main.island_path = ""
		await main.new_island()
	_fill_gallery()


func _pick(path: String) -> void:
	var err: Error = await main.open_island(path)
	if err != OK:
		toast(tr("Kunde inte öppna (%s)") % error_string(err))
		return
	close_all()
	if on_title:
		leave_title()


## A small sheet with a question and two buttons.
func _ask(text: String, ok: String, on_ok: Callable) -> void:
	var made := _sheet("", 380.0)
	var p: Control = made[0]
	p.set_meta("once", true)
	var box: VBoxContainer = made[1]
	var q := box.get_child(0) as Label
	q.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	q.text = text
	q.add_theme_font_size_override("font_size", 17)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size.x = 320
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var no := _menu_button(row, "Avbryt", "", func() -> void: close())
	no.theme_type_variation = "SheetButton"
	var yes := _menu_button(row, ok, "", func() -> void:
		close()
		on_ok.call())
	yes.theme_type_variation = "PrimaryButton"
	box.add_child(row)
	_open(p)


## A small sheet asking for a line of text.
func _ask_text(title: String, value: String, on_ok: Callable) -> void:
	var made := _sheet(title, 380.0)
	var p: Control = made[0]
	p.set_meta("once", true)
	var box: VBoxContainer = made[1]
	(box.get_child(0) as Label).add_theme_font_size_override("font_size", 17)
	var line := LineEdit.new()
	line.text = value
	line.max_length = 40
	line.select_all_on_focus = true
	box.add_child(line)
	var accept := func() -> void:
		var text := line.text.strip_edges()
		close()
		if text != "" and text != value:
			on_ok.call(text)
	line.text_submitted.connect(func(_t: String) -> void: accept.call())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var no := _menu_button(row, "Avbryt", "", func() -> void: close())
	no.theme_type_variation = "SheetButton"
	var yes := _menu_button(row, "OK", "", accept)
	yes.theme_type_variation = "PrimaryButton"
	box.add_child(row)
	_open(p)
	line.grab_focus.call_deferred()


# ---------------------------------------------------------------- words and files

## A line of words that shows for a moment at the top of the picture.
## `text` is shown as it is: translate it first (tr).
func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.0)


## Save the island as a file somewhere else (in a browser: download it).
func save_copy_dialog() -> void:
	var file: String = (main.island_name if main.island_name != "" else "Skyholme") + ".island"
	if MeshUtil.web():
		var err: int = IslandFile.download_island(main, file)
		toast(tr("Ön laddas ner som %s") % file if err == OK else tr("Kunde inte spara (%s)") % error_string(err))
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.island ; Skyholme"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	d.current_file = file
	d.file_selected.connect(func(path: String) -> void:
		if not path.ends_with(".island"):
			path += ".island"
		var thumb: Image = await IslandFile.thumbnail(main)
		var err: int = IslandFile.save(main, path, main.island_name, thumb)
		toast(tr("Sparad: %s") % path.get_file() if err == OK else tr("Kunde inte spara (%s)") % error_string(err)))
	add_child(d)
	d.popup_centered()


## Open an island from a file (in a browser: upload it). It becomes one of
## the islands in the gallery; the file itself is left as it is.
func open_file_dialog() -> void:
	if MeshUtil.web():
		IslandFile.pick_upload(func(bytes: PackedByteArray) -> void:
			var err: int = IslandFile.open_bytes(main, bytes)
			if err == OK:
				main.adopt_opened("")
			toast(tr("Ön öppnades") if err == OK else tr("Kunde inte öppna (%s)") % error_string(err)))
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.island ; Skyholme"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	d.file_selected.connect(func(path: String) -> void:
		var err: int = await main.open_island(path)
		toast(tr("Öppnade %s") % path.get_file() if err == OK else tr("Kunde inte öppna (%s)") % error_string(err)))
	add_child(d)
	d.popup_centered()
