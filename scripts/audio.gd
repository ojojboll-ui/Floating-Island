extends Node
## Everything heard: music, the island's own sounds, and the hands at work.
##
## The music is generative and never repeats: a slow chord turns every two
## bars (a soft bowed pad), a harp spreads each chord out, and a music box
## wanders a pentatonic tune over it, resting between phrases. After a few
## minutes it falls quiet for a while, so only the island is heard, and
## comes back. Night slows it, lowers it and lets a bell in; rain thins the
## tune out. Every note is one of the single notes in audio/notes, pitched
## (tools/make_sounds.py makes them all).
##
## The island's sounds follow the weather and the clock: wind always, birds
## by day, crickets at night, rain when it rains, a brook once there is
## water. The hands: a click for buttons, and a sound for each tool while
## it is drawn.
##
## Three buses, Musik, Natur and Effekter, with their levels set in the
## settings and kept on this computer.

const Settings := preload("res://scripts/settings.gd")
const Brush := preload("res://scripts/brush.gd")

const BUSES := ["Musik", "Natur", "Effekter"]
const LEVELS := {"Musik": 0.7, "Natur": 0.8, "Effekter": 0.8}

# D major pentatonic, as semitones above D
const SCALE := [0, 2, 4, 7, 9]
# the chords, two bars each: root (semitones above D) and the notes in it
const CHORDS := [[0, [0, 4, 7]], [9, [9, 12, 16]], [5, [5, 9, 12]], [7, [7, 11, 14]],
	[0, [0, 4, 7]], [5, [5, 9, 12]], [9, [9, 12, 16]], [7, [7, 11, 14]]]
const BEAT := 0.92          # seconds, by day
const VOICES := 18

var main
var _notes := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _loops := {}            # name -> AudioStreamPlayer
var _fx := {}               # name -> AudioStream
var _fx_player: Array[AudioStreamPlayer] = []
var _stroke: AudioStreamPlayer
var _stroke_tool := -1
var _rng := RandomNumberGenerator.new()

# the music's clock
var _beat_wait := 1.5
var _beat := 0
var _bar := 0
var _melody := 7            # where the tune is, in scale steps above D4
var _phrase_left := 0
var _rest_left := 0
var _section_left := 0.0    # seconds of music before it rests
var _silence_left := 0.0    # seconds of quiet before it comes back
var _water_seen := 0.0
var _water_check := 0.0


func setup(main_node) -> void:
	main = main_node
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in BUSES:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")
		set_level(name, float(Settings.get_value("sound", name, LEVELS[name])), false)
	# the music in a room: a soft, long reverb
	var music := AudioServer.get_bus_index("Musik")
	if AudioServer.get_bus_effect_count(music) == 0:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.78
		verb.damping = 0.45
		verb.spread = 0.9
		verb.wet = 0.32
		verb.dry = 0.85
		AudioServer.add_bus_effect(music, verb)
	for n in ["musicbox_a5", "harp_a3", "pad_d3", "bell_d4"]:
		_notes[n] = load("res://audio/notes/%s.wav" % n)
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Musik"
		add_child(p)
		_voices.append(p)
	for n in ["wind", "birds", "crickets", "rain", "brook"]:
		var s := load("res://audio/nature/%s.wav" % n) as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Natur"
		p.volume_db = -80.0
		add_child(p)
		p.play(_rng.randf() * s.get_length())
		_loops[n] = p
	for n in ["click", "place", "earth", "water", "paint", "remove", "shutter", "chime"]:
		_fx[n] = load("res://audio/fx/%s.wav" % n)
	for k in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Effekter"
		add_child(p)
		_fx_player.append(p)
	_stroke = AudioStreamPlayer.new()
	_stroke.bus = "Effekter"
	add_child(_stroke)
	_section_left = _rng.randf_range(150.0, 240.0)
	# every button clicks, wherever it is made
	get_tree().node_added.connect(_on_node)
	for b in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node(b)


## A bus's level, 0..1 (as shown on its slider), and remember it.
func set_level(bus: String, v: float, remember := true) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001) * v))
	AudioServer.set_bus_mute(i, v <= 0.001)
	if remember:
		Settings.set_value("sound", bus, v)


func level(bus: String) -> float:
	return float(Settings.get_value("sound", bus, LEVELS[bus]))


## Hook the brush, once it exists (and again if it is made afresh).
func hear_brush(brush) -> void:
	brush.stroke_began.connect(_on_stroke_began)
	brush.stroke_ended.connect(_on_stroke_ended)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _fx_player[0]
	for q in _fx_player:
		if not q.playing:
			p = q
			break
	p.stream = _fx[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	p.play()


func _on_node(n: Node) -> void:
	if n is BaseButton and not n.has_meta("quiet"):
		n.set_meta("quiet", true)
		(n as BaseButton).pressed.connect(func() -> void: play("click", -10.0, 1.0))


# ---------------------------------------------------------------- the hands

const STROKE_SOUND := {
	Brush.Tool.RAISE: "earth", Brush.Tool.LOWER: "earth", Brush.Tool.SMOOTH: "earth", Brush.Tool.FLATTEN: "earth",
	Brush.Tool.LAND_ADD: "earth", Brush.Tool.LAND_REMOVE: "remove", Brush.Tool.CARVE: "earth",
	Brush.Tool.PAINT: "paint", Brush.Tool.WATER: "water", Brush.Tool.DRY: "earth", Brush.Tool.REMOVE: "remove",
	Brush.Tool.DEMOLISH: "remove", Brush.Tool.ROOTS: "paint", Brush.UNROOT: "remove",
}


func _on_stroke_began(tool: int, _at: Vector3) -> void:
	if tool == Brush.Tool.PLACE:
		play("place", -4.0)
		_stroke_tool = tool
		return
	if tool in [Brush.Tool.PILLAR, Brush.Tool.WALL, Brush.Tool.ARCH, Brush.Tool.STAIRS, Brush.Tool.FLOOR, Brush.Tool.STOREY]:
		play("place", -6.0, 0.8)
		_stroke_tool = -1
		return
	_stroke_tool = tool
	_stroke_loop()


func _stroke_loop() -> void:
	var name: String = STROKE_SOUND.get(_stroke_tool, "")
	if name == "":
		return
	_stroke.stream = _fx[name]
	_stroke.volume_db = -9.0
	_stroke.pitch_scale = _rng.randf_range(0.9, 1.1)
	_stroke.play()


func _on_stroke_ended(tool: int) -> void:
	if tool in [Brush.Tool.WALL, Brush.Tool.ARCH, Brush.Tool.STAIRS, Brush.Tool.FLOOR, Brush.Tool.STOREY]:
		play("place", -3.0, 0.7)
	_stroke_tool = -1


# ---------------------------------------------------------------- the clock

func _process(delta: float) -> void:
	_nature(delta)
	# a long stroke keeps sounding, a little different each time round
	if _stroke_tool >= 0 and _stroke_tool != Brush.Tool.PLACE and not _stroke.playing:
		_stroke_loop()
	if _stroke_tool == Brush.Tool.PLACE and main.brush._stroking and _rng.randf() < delta * 5.0:
		play("place", -12.0, 1.2)
	_music(delta)


func _nature(delta: float) -> void:
	var w = main.weather
	var night := _night()
	var wet: float = clampf(w.rain, 0.0, 1.0)
	_water_check -= delta
	if _water_check <= 0.0:
		_water_check = 2.0
		var sum := 0.0
		var water: PackedFloat32Array = main.data.water
		for k in range(0, water.size(), 97):
			sum += water[k]
		_water_seen = clampf(sum / maxf(water.size() / 97.0, 1.0) * 40.0, 0.0, 1.0)
	var want := {
		"wind": 0.2 + 0.5 * clampf(w.wind, 0.0, 1.0),
		"birds": (1.0 - night) * (1.0 - wet) * (1.0 - clampf(w.snow * 2.0, 0.0, 1.0)) * 0.55,
		"crickets": night * (1.0 - wet) * (1.0 - clampf(w.snow * 3.0, 0.0, 1.0)) * 0.28,
		"rain": wet * 0.9,
		"brook": _water_seen * 0.5,
	}
	var k := 1.0 - exp(-delta * 0.8)
	for n: String in want:
		var p: AudioStreamPlayer = _loops[n]
		var now := db_to_linear(p.volume_db)
		p.volume_db = linear_to_db(maxf(lerpf(now, want[n], k), 0.0001))


## 0 by day, 1 at night, easing over dusk and dawn.
func _night() -> float:
	var h: float = main.weather.hour
	return clampf(maxf(smoothstep(19.0, 21.5, h), 1.0 - smoothstep(4.5, 6.5, h)), 0.0, 1.0)


func _music(delta: float) -> void:
	if _silence_left > 0.0:
		_silence_left -= delta
		return
	_section_left -= delta
	if _section_left <= 0.0 and _beat == 0 and _bar % 2 == 0:
		# rest a while: only the island is heard
		_silence_left = _rng.randf_range(35.0, 80.0)
		_section_left = _rng.randf_range(150.0, 260.0)
		return
	_beat_wait -= delta
	if _beat_wait > 0.0:
		return
	var night := _night()
	var beat := BEAT * lerpf(1.0, 1.3, night)
	_beat_wait += beat
	var chord: Array = CHORDS[(_bar / 2) % CHORDS.size()]
	if _beat == 0 and _bar % 2 == 0:
		_chord_change(chord, night)
	_tune(chord, night, beat)
	_beat += 1
	if _beat >= 4:
		_beat = 0
		_bar += 1


func _chord_change(chord: Array, night: float) -> void:
	var wet: float = main.weather.rain
	# the pad holds the chord for the two bars
	for st: int in chord[1]:
		_note("pad_d3", 146.83, 146.83 * pow(2.0, (st % 12) / 12.0), -17.0 + wet * 3.0)
	# the harp spreads it out, now and then
	if _rng.randf() < 0.7 - wet * 0.3:
		var root := 146.83 * pow(2.0, int(chord[0]) / 12.0)
		var tones: Array = chord[1]
		for k in 4:
			var st: int = tones[k % 3] + (12 if k == 3 else 0)
			_note("harp_a3", 220.0, 146.83 * pow(2.0, st / 12.0), -12.0 - k * 1.5, k * 0.17 * lerpf(1.0, 1.4, night))
		if root < 0:
			pass
	# a bell at night, at the top of a long cycle
	if night > 0.5 and _bar % 8 == 0 and _rng.randf() < 0.8:
		_note("bell_d4", 293.66, 146.83 * pow(2.0, int(chord[0]) / 12.0), -15.0, 0.1)


func _tune(chord: Array, night: float, beat: float) -> void:
	var wet: float = main.weather.rain
	if _rest_left > 0:
		_rest_left -= 1
		return
	if _phrase_left <= 0:
		# a new phrase, after a rest
		_phrase_left = _rng.randi_range(5, 11)
		_rest_left = _rng.randi_range(3, 8)
		return
	var chance := 0.62 - night * 0.22 - wet * 0.25
	if _rng.randf() > chance:
		return
	_phrase_left -= 1
	# a step or two up or down the scale, leaning toward the chord's notes on
	# the first beat
	_melody = clampi(_melody + [-2, -1, -1, 1, 1, 2, 0][_rng.randi() % 7], 2, 13)
	var st := _scale_step(_melody)
	if _beat == 0:
		var best: int = st
		var tones: Array = chord[1]
		for t: int in tones:
			for oct in [12, 24]:
				if absi(t + oct - st) < absi(best - st) or best == st:
					best = t + oct
		st = best if absi(best - st) <= 2 else st
	var octave := 12 if night < 0.5 else 0
	var f := 293.66 * pow(2.0, (st + octave) / 12.0)
	var swing := beat * 0.5 if _rng.randf() < 0.25 else 0.0
	_note("musicbox_a5", 880.0, f, -11.0 - night * 2.0, swing)


func _scale_step(step: int) -> int:
	return SCALE[posmod(step, 5)] + 12 * floori(step / 5.0)


## Play one of the notes at `freq` (it was made at `base`), after `wait`.
func _note(name: String, base: float, freq: float, volume_db: float, wait := 0.0) -> void:
	if wait > 0.0:
		get_tree().create_timer(wait).timeout.connect(func() -> void: _note(name, base, freq, volume_db))
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _notes[name]
	p.pitch_scale = freq / base
	p.volume_db = volume_db + _rng.randf_range(-1.5, 1.0)
	p.play()
