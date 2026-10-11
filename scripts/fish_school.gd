extends Node3D
## Koi that turn up by themselves once there is a pond for them: about one
## per few square meters of deep water. They wander just under the surface,
## feel ahead for the bank and turn away from it, now and then dart, and
## leave if their water is drained.

const PlantBuilder := preload("res://scripts/plant_builder.gd")
const IslandData := preload("res://scripts/island_data.gd")

const AREA_PER_FISH := 4.0
const MAX_FISH := 14
const MIN_DEPTH := 0.22

var data
var _fish: Array = []    # {node, pos: Vector2, heading, speed, burst, seed}
var _mesh: ArrayMesh
var _rng := RandomNumberGenerator.new()


func setup(island_data) -> void:
	data = island_data
	_rng.seed = 77
	_mesh = PlantBuilder.fish()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fish.gdshader")
	_mesh.surface_set_material(0, mat)


func _deep(p: Vector2) -> bool:
	if not data.in_bounds(p.x, p.y):
		return false
	if data.sample_water(p.x, p.y) < 0.75:
		return false
	return data.sample_wlevel(p.x, p.y) - data.sample_height(p.x, p.y) > MIN_DEPTH


## Count the deep water and add or remove fish to match.
func refresh() -> void:
	var spots: Array[Vector2] = []
	var step := 3
	var cell: float = IslandData.CELL * step
	for j in range(0, IslandData.RES, step):
		for i in range(0, IslandData.RES, step):
			var p: Vector2 = data.grid_pos(i, j)
			if _deep(p):
				spots.append(p)
	var want := mini(MAX_FISH, int(spots.size() * cell * cell / AREA_PER_FISH))
	# fish whose water is gone leave first
	for f in _fish.duplicate():
		if not _deep(f.pos):
			f.node.queue_free()
			_fish.erase(f)
	while _fish.size() > want:
		var f: Dictionary = _fish.pop_back()
		f.node.queue_free()
	while _fish.size() < want and not spots.is_empty():
		var at: Vector2 = spots[_rng.randi() % spots.size()]
		var node := MeshInstance3D.new()
		node.mesh = _mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var seed := _rng.randf()
		node.set_instance_shader_parameter("seed", seed)
		node.scale = Vector3.ONE * _rng.randf_range(1.2, 1.7)
		add_child(node)
		_fish.append({"node": node, "pos": at, "heading": _rng.randf() * TAU, "speed": 0.25, "burst": 0.0, "seed": seed})


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in _fish:
		var pos: Vector2 = f.pos
		var heading: float = f.heading
		var seed: float = f.seed
		# a slow meander, with now and then a quick dart
		heading += sin(t * 0.7 + seed * 20.0) * 0.6 * delta
		f.burst = maxf(0.0, f.burst - delta)
		if _rng.randf() < delta * 0.08:
			f.burst = 0.8
		var want_speed: float = 0.22 + 0.5 * f.burst
		# feel ahead; turn toward whichever side has more water
		var dir := Vector2(sin(heading), cos(heading))
		var ahead := pos + dir * 0.45
		if not _deep(ahead):
			var left := pos + Vector2(sin(heading + 0.9), cos(heading + 0.9)) * 0.45
			var right := pos + Vector2(sin(heading - 0.9), cos(heading - 0.9)) * 0.45
			if _deep(left):
				heading += 3.0 * delta
			elif _deep(right):
				heading -= 3.0 * delta
			else:
				heading += 5.0 * delta
			want_speed *= 0.4
		f.speed = lerpf(f.speed, want_speed, delta * 2.0)
		dir = Vector2(sin(heading), cos(heading))
		var next: Vector2 = pos + dir * f.speed * delta
		if _deep(next):
			pos = next
		f.pos = pos
		f.heading = heading
		var level: float = data.sample_wlevel(pos.x, pos.y)
		var node: MeshInstance3D = f.node
		node.position = Vector3(pos.x, level - 0.1 + sin(t * 0.9 + seed * 9.0) * 0.02, pos.y)
		node.rotation.y = heading
		node.set_instance_shader_parameter("swim", f.speed / 0.5)
