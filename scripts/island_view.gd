extends Node3D
## Shows IslandData as a grid of tiles, each with a ground mesh, a body mesh
## (skirt and underside) and grass. rebuild() remeshes only what a change
## touched: the ground where anything changed, the body only where the
## coast did. It also uploads the terrain texture the grass reads.

const IslandData := preload("res://scripts/island_data.gd")
const IslandMesher := preload("res://scripts/island_mesher.gd")
const GrassScatter := preload("res://scripts/grass_scatter.gd")
const WaterMesher := preload("res://scripts/water_mesher.gd")

var data
var texture: ImageTexture
var ground_mat := ShaderMaterial.new()
var cliff_mat := ShaderMaterial.new()
var grass_mat := ShaderMaterial.new()
var water_mat := ShaderMaterial.new()
var falls_mat := ShaderMaterial.new()
var spray_mat := ShaderMaterial.new()
var _mist_mesh: QuadMesh
var _mist_process: ParticleProcessMaterial
var profile := false

## Milliseconds per frame spent remeshing; the rest waits for the next frame.
const BUDGET_MS := 6.0

var _tiles := {}     # Vector2i -> {top, body, grass}
var _pending := {}   # Vector2i -> whether the body needs rebuilding too


func setup(island_data) -> void:
	data = island_data
	ground_mat.shader = load("res://shaders/ground.gdshader")
	cliff_mat.shader = load("res://shaders/cliff.gdshader")
	grass_mat.shader = load("res://shaders/grass.gdshader")
	water_mat.shader = load("res://shaders/water.gdshader")
	falls_mat.shader = load("res://shaders/waterfall.gdshader")
	spray_mat.shader = load("res://shaders/spray.gdshader")
	_make_mist()
	data.refresh_image(data.full_rect())
	texture = ImageTexture.create_from_image(data.image)
	grass_mat.set_shader_parameter("terrain", texture)
	grass_mat.set_shader_parameter("terrain_size", IslandData.SIZE)
	grass_mat.set_shader_parameter("terrain_res", float(IslandData.RES))
	rebuild(data.full_rect(), data.full_rect())
	flush()
	_warm_up()


## Draw the water, falls and mist once, hidden inside the island, so their
## shaders compile at startup instead of stalling the first brush stroke.
func _warm_up() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, -4.0, 0.0)
	for mat in [water_mat, falls_mat, spray_mat]:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.05)
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.material_override = mat
		holder.add_child(m)
	holder.add_child(_mist(PackedVector3Array([Vector3.ZERO])))
	add_child(holder)
	get_tree().create_timer(1.0).timeout.connect(holder.queue_free)


## Queue a rebuild for changed grid points `r`, of which `shape` also moved
## the island body. Normals and the coast look one cell around, so the
## rectangles grow a little first. The terrain texture updates at once, so
## grass follows the brush immediately; meshes catch up within a few frames.
func rebuild(r: Rect2i, shape: Rect2i) -> void:
	r = r.grow(2).intersection(data.full_rect())
	data.refresh_image(r)
	texture.update(data.image)
	var top_tiles := _tiles_in(r)
	var body_tiles := {}
	if shape.has_area():
		for key in _tiles_in(shape.grow(2).intersection(data.full_rect())):
			body_tiles[key] = true
			top_tiles[key] = true
	for key in top_tiles:
		_pending[key] = _pending.get(key, false) or body_tiles.has(key)


func _process(_delta: float) -> void:
	_work(BUDGET_MS)


## Build everything still queued, however long it takes.
func flush() -> void:
	_work(INF)


func _work(budget_ms: float) -> void:
	if _pending.is_empty():
		return
	var start := Time.get_ticks_usec()
	var done := 0
	for key in _pending.keys():
		_rebuild_tile(key, _pending[key])
		_pending.erase(key)
		done += 1
		if (Time.get_ticks_usec() - start) / 1000.0 >= budget_ms:
			break
	if profile:
		print("    built %d tiles in %.1f ms, %d left" % [done, (Time.get_ticks_usec() - start) / 1000.0, _pending.size()])


func _tiles_in(r: Rect2i) -> Dictionary:
	var tile: int = IslandData.TILE
	var last: int = IslandData.TILES - 1
	var out := {}
	var t0 := Vector2i(clampi(r.position.x / tile, 0, last), clampi(r.position.y / tile, 0, last))
	var t1 := Vector2i(clampi((r.end.x - 1) / tile, 0, last), clampi((r.end.y - 1) / tile, 0, last))
	for tj in range(t0.y, t1.y + 1):
		for ti in range(t0.x, t1.x + 1):
			out[Vector2i(ti, tj)] = true
	return out


func _rebuild_tile(key: Vector2i, with_body: bool) -> void:
	var entry = _tiles.get(key)
	# a tile seen for the first time needs its body whatever changed
	var body := with_body or entry == null
	var meshes := IslandMesher.build_tile(data, key.x, key.y, true, body)
	if meshes[0] == null:
		if entry != null:
			for node in entry.values():
				node.queue_free()
			_tiles.erase(key)
		return
	if entry == null:
		entry = {"top": MeshInstance3D.new(), "body": MeshInstance3D.new(),
				"grass": GrassScatter.build_tile(key.x, key.y, grass_mat),
				"water": MeshInstance3D.new(), "falls": MeshInstance3D.new(), "veil": MeshInstance3D.new()}
		entry.top.material_override = ground_mat
		entry.body.material_override = cliff_mat
		entry.water.material_override = water_mat
		entry.water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		entry.falls.material_override = falls_mat
		entry.falls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		entry.veil.material_override = spray_mat
		entry.veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for node in entry.values():
			add_child(node)
		_tiles[key] = entry
	entry.top.mesh = meshes[0]
	if body:
		entry.body.mesh = meshes[1]
	_update_water(entry, key)


func _update_water(entry: Dictionary, key: Vector2i) -> void:
	var w = WaterMesher.build_tile(data, key.x, key.y)
	entry.water.mesh = w.surface
	entry.falls.mesh = w.falls
	entry.veil.mesh = w.veil
	if entry.has("mist"):
		entry.mist.queue_free()
		entry.erase("mist")
	if w.fall_bottom.size() > 0:
		entry.mist = _mist(w.fall_bottom)
		add_child(entry.mist)


## Spray drifting off the bottom of the falls, where the water thins out.
func _mist(points: PackedVector3Array) -> GPUParticles3D:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	var mist := GPUParticles3D.new()
	mist.amount = clampi(int(points.size() * 3), 6, 60)
	mist.lifetime = 5.0
	mist.preprocess = 5.0
	mist.position = box.get_center() + Vector3(0.0, 1.2, 0.0)
	var pm := _mist_process.duplicate() as ParticleProcessMaterial
	pm.emission_box_extents = box.size * 0.5 + Vector3(0.3, 0.6, 0.3)
	mist.process_material = pm
	mist.draw_pass_1 = _mist_mesh
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.visibility_aabb = AABB(Vector3(-8, -12, -8), Vector3(16, 16, 16))
	return mist


func _make_mist() -> void:
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(1.6, 1.6)
	_mist_mesh.material = mat

	_mist_process = ParticleProcessMaterial.new()
	_mist_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mist_process.direction = Vector3(0, -1, 0)
	_mist_process.spread = 40.0
	_mist_process.initial_velocity_min = 0.2
	_mist_process.initial_velocity_max = 0.6
	_mist_process.gravity = Vector3(0, -0.15, 0)
	_mist_process.damping_min = 0.1
	_mist_process.damping_max = 0.3
	_mist_process.scale_min = 0.8
	_mist_process.scale_max = 1.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	_mist_process.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 0.35))
	fade.add_point(0.6, Color(0.95, 0.97, 1.0, 0.22))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	_mist_process.color_ramp = fade_tex
