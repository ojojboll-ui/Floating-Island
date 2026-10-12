extends Node3D
## Orbit camera with a miniature look: a long lens from far away, and depth
## of field focused on the orbit target so both the near edge and the far
## side go soft. The blur band follows the zoom, so closer looks smaller.
##
## Right drag orbits, middle drag pans, the wheel zooms. The Kamera tab sets
## the lens (focal length, focus, aperture) and two waves:
##   the spin: the camera circles the island, clockwise unless reversed,
##   its speed rising and falling along a wave;
##   the bob: the camera rises and sinks along a wave, straight up and down.
## Each wave has a shape that can be drawn by hand: a ring of points, one
## period long, joined by a smooth periodic curve. Both start as a sine.
##
## The camera always orbits the middle of the island and stands back in
## proportion to its size, so a grown island stays framed (see fit_island).

signal moved   # the orbit changed from the mouse, for the panel to follow

const WAVE_POINTS := 8
const BASE_RADIUS := 7.5      # the size of the first island; zoom is relative to it

var target := Vector3(0.0, 1.2, 0.0)     # pan, relative to the island's middle
var yaw := deg_to_rad(40.0)
var pitch := deg_to_rad(32.0)
var distance := 56.0

var goal_target := target
var goal_yaw := yaw
var goal_pitch := pitch
var goal_distance := distance

# lens
var focal_mm := 62.0          # on a 24 mm high frame; 62 mm is the old 22° view
var focus_offset := 0.0       # metres nearer (−) or further (+) than the orbit target
var aperture := 0.5           # 0 everything sharp .. 1 a very shallow miniature

# spin
var spin_speed := 0.0         # mean speed, degrees per second
var spin_clockwise := true
var spin_vary := 0.5          # how far the speed swings either side of the mean, 0..1
var spin_period := 20.0       # seconds for one wave of the speed
var spin_shape: Array = sine_shape()
var spin_phase := 0.0

# bob
var bob := 0.0                # metres up and down
var bob_period := 12.0
var bob_shape: Array = sine_shape()
var bob_phase := 0.0

# the island's middle and size, eased toward as it changes
var island_center := Vector3.ZERO
var island_radius := BASE_RADIUS
var _fit_center := Vector3.ZERO
var _fit_radius := BASE_RADIUS

# how far the island's picture moves left (negative: right), as a share of
# the screen's width, to sit in the middle of what the panel leaves free
var frame_shift := 0.0
var _shift := 0.0

var camera: Camera3D
var attrs: CameraAttributesPractical
var _orbiting := false
var _panning := false


static func sine_shape() -> Array:
	var out := []
	for k in WAVE_POINTS:
		out.append(sin(TAU * k / WAVE_POINTS))
	return out


## The wave `shape` at `phase` (0..1): a periodic Catmull-Rom curve through
## its points.
static func wave(shape: Array, phase: float) -> float:
	var n := shape.size()
	var x := fposmod(phase, 1.0) * n
	var i := int(floor(x))
	var t := x - i
	var p0: float = shape[(i - 1 + n) % n]
	var p1: float = shape[i % n]
	var p2: float = shape[(i + 1) % n]
	var p3: float = shape[(i + 2) % n]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## The mean of a wave over one period (the spin's average speed needs it).
static func wave_mean(shape: Array) -> float:
	var s := 0.0
	for k in 64:
		s += wave(shape, k / 64.0)
	return s / 64.0


## Spin speed now, degrees per second, never below standstill.
func spin_now() -> float:
	return maxf(0.0, spin_speed * (1.0 + spin_vary * wave(spin_shape, spin_phase)))


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 500.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_far_enabled = true
	camera.attributes = attrs
	add_child(camera)
	camera.current = true
	_apply()


## Jump straight to the goals, skipping the easing (for snapshots).
func settle() -> void:
	target = goal_target
	yaw = goal_yaw
	pitch = goal_pitch
	distance = goal_distance
	_fit_center = island_center
	_fit_radius = island_radius
	_shift = frame_shift
	_apply()


## Measure the island: the middle of its land and how far it reaches.
func fit_island(data) -> void:
	var sum := Vector2.ZERO
	var count := 0
	var pts: Array[Vector2] = []
	var step := 4
	for j in range(0, data.RES, step):
		for i in range(0, data.RES, step):
			var k: int = data.index(i, j)
			if data.sdf[k] > 0.0:
				var p: Vector2 = data.grid_pos(i, j)
				sum += p
				count += 1
				pts.append(p)
	if count == 0:
		return
	var c := sum / count
	var reach := 0.0
	for p in pts:
		reach = maxf(reach, p.distance_to(c))
	island_center = Vector3(c.x, 0.0, c.y)
	island_radius = maxf(reach + 0.5, 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					goal_distance = maxf(10.0, goal_distance * 0.9)
					moved.emit()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					goal_distance = minf(140.0, goal_distance * 1.1)
					moved.emit()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			goal_yaw -= mm.relative.x * 0.006
			goal_pitch = clampf(goal_pitch + mm.relative.y * 0.005, deg_to_rad(-25.0), deg_to_rad(80.0))
			moved.emit()
		elif _panning:
			var right := camera.global_basis.x
			var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
			goal_target += (-right * mm.relative.x + ahead * mm.relative.y) * _scaled_distance() * 0.0012


func _process(delta: float) -> void:
	# the spin moves the goal itself, so the mouse and the spin add up
	if spin_speed > 0.0:
		var dir := -1.0 if spin_clockwise else 1.0
		var step := deg_to_rad(spin_now()) * delta * dir
		goal_yaw += step
		yaw += step
		spin_phase = fmod(spin_phase + delta / maxf(spin_period, 0.5), 1.0)
		moved.emit()
	if bob > 0.0:
		bob_phase = fmod(bob_phase + delta / maxf(bob_period, 0.5), 1.0)
	var k := 1.0 - exp(-delta * 10.0)
	target = target.lerp(goal_target, k)
	yaw = lerpf(yaw, goal_yaw, k)
	pitch = lerpf(pitch, goal_pitch, k)
	distance = lerpf(distance, goal_distance, k)
	var kf := 1.0 - exp(-delta * 3.0)
	_fit_center = _fit_center.lerp(island_center, kf)
	_fit_radius = lerpf(_fit_radius, island_radius, kf)
	_shift = lerpf(_shift, frame_shift, 1.0 - exp(-delta * 8.0))
	_apply()


func _scaled_distance() -> float:
	return distance * _fit_radius / BASE_RADIUS


func _apply() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var d := _scaled_distance()
	var aim := Vector3(_fit_center.x + target.x, target.y, _fit_center.z + target.z)
	var lift := wave(bob_shape, bob_phase) * bob if bob > 0.0 else 0.0
	camera.global_position = aim + dir * d + Vector3(0.0, lift, 0.0)
	camera.look_at(aim, Vector3.UP)
	camera.fov = rad_to_deg(2.0 * atan(12.0 / focal_mm))
	# slide the picture sideways, clear of the panel; the screen at the aim
	# is this wide in metres
	var aspect: float = camera.get_viewport().get_visible_rect().size.aspect() if camera.is_inside_tree() else 16.0 / 9.0
	camera.h_offset = _shift * 2.0 * d * tan(deg_to_rad(camera.fov) * 0.5) * aspect
	# A band of sharpness round the focus point. A wider aperture narrows it
	# and blurs harder outside it; it is a fixed size in metres, so zooming
	# in shrinks it relative to the frame and the scene reads ever smaller.
	var focus := camera.global_position.distance_to(aim) + focus_offset
	var band := lerpf(10.0, 0.8, sqrt(aperture)) * _fit_radius / BASE_RADIUS
	attrs.dof_blur_amount = lerpf(0.0, 0.32, aperture)
	attrs.dof_blur_near_enabled = aperture > 0.01
	attrs.dof_blur_far_enabled = aperture > 0.01
	attrs.dof_blur_near_distance = maxf(focus - band, 0.5)
	attrs.dof_blur_near_transition = band * 2.0
	attrs.dof_blur_far_distance = focus + band * 0.66
	attrs.dof_blur_far_transition = band * 3.0


## Make the waves fit a loop, for a wallpaper: one full turn of the island
## (or one bob, if it does not turn), with whole waves in it, so the last
## frame meets the first. Returns the loop's length in seconds.
func fit_loop(fallback: float) -> float:
	var loop := fallback
	if spin_speed > 0.0:
		var mean := spin_speed * (1.0 + spin_vary * wave_mean(spin_shape))
		var turn := 360.0 / maxf(mean, 0.1)
		var waves := maxi(1, int(round(turn / spin_period)))
		loop = waves * spin_period
		# speed the mean up or down a touch so a turn takes exactly the loop
		spin_speed *= turn / loop
	elif bob > 0.0:
		loop = bob_period
	if bob > 0.0:
		bob_period = loop / maxi(1, int(round(loop / bob_period)))
	spin_phase = 0.0
	bob_phase = 0.0
	return loop


const SAVED := ["focal_mm", "focus_offset", "aperture", "spin_speed", "spin_clockwise", "spin_vary",
	"spin_period", "spin_shape", "bob", "bob_period", "bob_shape"]


## Ready-made views: name, then angle, height (degrees), zoom (metres),
## focal length (mm), aperture. The first is the view the program starts with.
const PRESETS := [
	["Standard", 40.0, 32.0, 56.0, 62.0, 0.5],
	["Miniatyr", 35.0, 42.0, 70.0, 90.0, 0.95],
	["Ovanifrån", 20.0, 74.0, 60.0, 50.0, 0.2],
	["Låg vinkel", 50.0, 7.0, 40.0, 35.0, 0.45],
	["Underifrån", 30.0, -16.0, 52.0, 45.0, 0.3],
	["Närbild", 40.0, 22.0, 24.0, 55.0, 0.75],
	["Vidvinkel", 40.0, 26.0, 26.0, 24.0, 0.15],
	["Teleobjektiv", 40.0, 30.0, 120.0, 160.0, 0.35],
]


## Ease to one of the PRESETS, panned back to the island's middle. The spin
## and the height wave are left as they are.
func apply_preset(i: int) -> void:
	var p: Array = PRESETS[i]
	goal_target = Vector3(0.0, 1.2, 0.0)
	goal_yaw = deg_to_rad(p[1])
	goal_pitch = deg_to_rad(p[2])
	goal_distance = p[3]
	focal_mm = p[4]
	aperture = p[5]
	focus_offset = 0.0
	moved.emit()


## Back to the view the program starts with.
func reset_view() -> void:
	apply_preset(0)


func state() -> Dictionary:
	var out := {"target": [goal_target.x, goal_target.y, goal_target.z], "yaw": goal_yaw, "pitch": goal_pitch,
		"distance": goal_distance}
	for key in SAVED:
		var v = get(key)
		out[key] = v.duplicate() if v is Array else v
	return out


func set_state(s: Dictionary) -> void:
	goal_target = Vector3(s.target[0], s.target[1], s.target[2])
	goal_yaw = s.yaw
	goal_pitch = s.pitch
	goal_distance = s.distance
	for key in SAVED:
		if s.has(key):
			var v = s[key]
			set(key, v.duplicate() if v is Array else v)
	moved.emit()
