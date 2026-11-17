extends CanvasLayer
## A few first steps for someone new: a small parchment card at the foot of
## the picture with one hint at a time. Each goes when it has been done (a
## stroke drawn, the camera turned, something planted, the weather or the
## light visited) and the next comes; the last fades by itself. Once seen
## through, or put away with its cross, it does not come back (the
## settings file remembers).

const Settings := preload("res://scripts/settings.gd")
const Brush := preload("res://scripts/brush.gd")

const STEPS := [
	["draw", "Välj ett verktyg i panelen och dra med vänster musknapp över ön."],
	["turn", "Håll höger musknapp och dra för att vrida på ön. Hjulet zoomar."],
	["plant", "Under Växter finns träd, buskar och blommor. Klicka på ön för att plantera."],
	["mood", "Väder och Ljus ändrar stämningen: prova en kväll med eldflugor."],
	["export", "När du är nöjd sparar Export bilder, filmer och bakgrunder av ön."],
]

var main
var _card: PanelContainer
var _text: Label
var _step := -1
var _turned := 0.0


func setup(main_node, theme: Theme) -> void:
	main = main_node
	layer = 4
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)
	_card = PanelContainer.new()
	_card.theme_type_variation = "Sheet"
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_bottom = -22
	_card.offset_top = -22
	_card.custom_minimum_size.x = 520
	_card.visible = false
	root.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_card.add_child(row)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.x = 420
	_text.add_theme_font_size_override("font_size", 18)
	row.add_child(_text)
	var away := Button.new()
	away.text = "×"
	away.tooltip_text = "Inga fler tips"
	away.theme_type_variation = "SmallButton"
	away.focus_mode = Control.FOCUS_NONE
	away.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	away.pressed.connect(func() -> void: _finish())
	row.add_child(away)
	main.brush.stroke_ended.connect(_on_stroke)
	main.rig.moved.connect(func() -> void: _turned += 1.0)


## Start the hints, if they have not been seen on this computer.
func begin() -> void:
	if _step >= 0 or bool(Settings.get_value("general", "tips_done", false)):
		return
	_show(0)


func _show(step: int) -> void:
	_step = step
	if step >= STEPS.size():
		_finish()
		return
	_text.text = STEPS[step][1]
	_card.visible = true
	_card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_card, "modulate:a", 1.0, 0.5)
	if STEPS[step][0] == "export":
		get_tree().create_timer(14.0).timeout.connect(func() -> void:
			if _step == step:
				_finish())


func _done(what: String) -> void:
	if _step < 0 or _step >= STEPS.size() or STEPS[_step][0] != what:
		return
	var next := _step + 1
	_step = -2
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: _show(next))


func _finish() -> void:
	_step = STEPS.size()
	Settings.set_value("general", "tips_done", true)
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _card.visible = false)


func _on_stroke(tool: int) -> void:
	_done("draw")
	if tool == Brush.Tool.PLACE:
		_done("plant")


func _process(_delta: float) -> void:
	visible = main.playing and not main.menus.is_open()
	# in the middle of the free part of the picture, beside the panel
	var shift := 202.0 if main.ui and main.ui.visible and not main.ui.collapsed else 0.0
	_card.offset_left = shift
	_card.offset_right = shift
	if _turned > 40.0:
		_done("turn")
	if main.ui and main.ui.tabs and main.ui.tabs.current_tab in [4, 5]:
		_done("mood")
	if main.ui and main.ui.tabs and main.ui.tabs.current_tab == 8:
		_done("export")
