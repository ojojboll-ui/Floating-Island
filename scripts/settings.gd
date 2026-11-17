extends RefCounted
## What is chosen on this computer rather than in an island: the window,
## sound levels, the language, which island was open last. It lives in
## user://settings.cfg, beside the graphics settings that post.gd keeps
## there (each writer reads the file afresh before it writes, so neither
## overwrites the other's part).

const PATH := "user://settings.cfg"

## Off in test and film runs: nothing is read from the file or written.
static var remember := true
static var _unsaved := {}


static func get_value(section: String, key: String, fallback: Variant) -> Variant:
	var id := section + "/" + key
	if _unsaved.has(id):
		return _unsaved[id]
	if not remember:
		return fallback
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return fallback
	return cfg.get_value(section, key, fallback)


static func set_value(section: String, key: String, value: Variant) -> void:
	_unsaved[section + "/" + key] = value
	if not remember:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(section, key, value)
	cfg.save(PATH)


## The settings file from before the program had its own folder (the
## working name's), brought along once.
static func adopt_old() -> void:
	if not remember or FileAccess.file_exists(PATH):
		return
	for old in ["Godot/app_userdata/Floating Island", "godot/app_userdata/Floating Island"]:
		var path := OS.get_data_dir().path_join(old).path_join("settings.cfg")
		if FileAccess.file_exists(path):
			DirAccess.copy_absolute(path, ProjectSettings.globalize_path(PATH))
			return
