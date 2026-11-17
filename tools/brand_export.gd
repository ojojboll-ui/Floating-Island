extends SceneTree
## Writes the wordmark and the emblem out as files (brand/): SVG masters and
## PNGs, the program icon and the icon for Windows.
##   godot --headless --path . -s tools/brand_export.gd

const Brand := preload("res://scripts/brand.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path("res://brand")
	DirAccess.make_dir_recursive_absolute(dir)
	var ink := Color(0.27, 0.21, 0.16)
	var marks := {
		"wordmark_light": Brand.wordmark_svg(),
		"wordmark_dark": Brand.wordmark_svg(ink),
		"emblem": Brand.emblem_svg(),
		"emblem_bare": Brand.emblem_svg(false),
	}
	for name: String in marks:
		var f := FileAccess.open(dir.path_join(name + ".svg"), FileAccess.WRITE)
		f.store_string(marks[name])
		f.close()
	Brand.image(marks.wordmark_light, 1600).save_png(dir.path_join("wordmark_light.png"))
	Brand.image(marks.wordmark_dark, 1600).save_png(dir.path_join("wordmark_dark.png"))
	Brand.image(marks.emblem, 1024).save_png(dir.path_join("emblem_1024.png"))
	Brand.image(marks.emblem, 256).save_png(ProjectSettings.globalize_path("res://icon.png"))
	# the picture Godot shows while the program starts: the name where the
	# loading screen has it (warmup.gd), a little above the middle
	var word := Brand.image(marks.wordmark_dark, 460)
	var splash := Image.create_empty(word.get_width(), word.get_height() + 54, false, Image.FORMAT_RGBA8)
	splash.blit_rect(word, Rect2i(Vector2i.ZERO, word.get_size()), Vector2i.ZERO)
	splash.save_png(dir.path_join("splash.png"))
	# a proof sheet: the light wordmark on sky, the dark on paper, and the
	# emblem at the sizes an icon is shown in
	var sheet := Image.create_empty(1400, 900, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.62, 0.84))
	sheet.fill_rect(Rect2i(0, 450, 1400, 450), Color(0.985, 0.965, 0.925))
	var light := Brand.image(marks.wordmark_light, 900)
	sheet.blend_rect(light, Rect2i(Vector2i.ZERO, light.get_size()), Vector2i(60, 70))
	var dark := Brand.image(marks.wordmark_dark, 900)
	sheet.blend_rect(dark, Rect2i(Vector2i.ZERO, dark.get_size()), Vector2i(60, 520))
	var small := Brand.image(Brand.wordmark_svg(ink, false), 180)
	sheet.blend_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(60, 820))
	var big := Brand.image(marks.emblem, 256)
	sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(1010, 60))
	var y := 340
	for px in [128, 64, 32, 16]:
		var e := Brand.image(marks.emblem, px)
		sheet.blend_rect(e, Rect2i(Vector2i.ZERO, e.get_size()), Vector2i(1010, y))
		y += px + 16
	sheet.save_png(dir.path_join("proof.png"))
	print("brand files written to ", dir)
	quit()
