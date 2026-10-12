extends Node3D
## Roots drawn with the brush: crawling over the ground, tipping over the
## edge, or hanging from the underside and cliffs. Each stroke is one
## record: where the roots start, their style (see RootBuilder.STYLE) and a
## seed. The meshes are grown from the records (see root_builder.gd), so
## undo and saving only need the records.
##
## The style dials on the Mark page set `style` for the next roots drawn and
## also restyle the last roots drawn, so they can be tuned after drawing.
##
## Roots on the ground also crawl over the ruins and the boulders and stones:
## a height raster is taken from their meshes as they stand, whenever they change, and the roots
## climb the face of a wall, cross its top and come down the other side.
##
## Each start remembers what it starts on. On the ground or the underside it
## keeps only where it is across the island and takes its height from the
## island as it is now, so roots follow when the ground is shaped or the
## underside worn away. On a cliff side it keeps its height.

const RootBuilder := preload("res://scripts/root_builder.gd")
const IslandMesher := preload("res://scripts/island_mesher.gd")

enum On { SIDE, UNDER, GROUND }

const RASTER_CELL := 0.1
const RASTER_N := 320          # covers the 32 m grid

var data
var ruins
var props
var view                   # to update the terrain texture the grass reads
var records: Array = []     # {seed, anchors: [[x, y, z, On]], style}
var style: Dictionary = RootBuilder.style_of(null)
var material: ShaderMaterial
var _nodes := {}            # seed -> MeshInstance3D
var _built := {}            # seed -> what that mesh was grown from
var _preview: MeshInstance3D
var _showing := false       # a stroke is being drawn and previewed
var _task := -1             # the preview growing on a worker thread
var _grown := {}
var _waiting: Array = []    # the next preview to grow, once the worker is free
var _raster := PackedFloat32Array()   # top of the ruins per cell, -INF where none
var _raster_rev := -1
var _raster_dirty := false
var _stones_rev := -1
var _lying := {}            # seed -> where its roots lie on the ground: x, z, radius in turn


func setup(island_data, ruin_layer) -> void:
	data = island_data
	ruins = ruin_layer
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/roots.gdshader")
	material.set_shader_parameter("albedo_tex", _texture("Bark_TwistedTree.png"))
	material.set_shader_parameter("normal_tex", _texture("Bark_TwistedTree_Normal.png"))
	_preview = MeshInstance3D.new()
	_preview.material_override = material
	add_child(_preview)
	_raster.resize(RASTER_N * RASTER_N)
	_raster.fill(-INF)


static func _texture(file: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/quaternius/" + file))
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Whether p is inside the island: under the ground and above the underside.
func inside(p: Vector3) -> bool:
	if not data.in_bounds(p.x, p.z) or data.sample_sdf(p.x, p.z) <= 0.0:
		return false
	return p.y <= data.sample_height(p.x, p.z) and p.y >= IslandMesher.underside(data, p.x, p.z)


## The surface a crawling root lies on: the ground, or the stones of a ruin
## standing on it. NAN off the island.
func ground(x: float, z: float) -> float:
	if not data.in_bounds(x, z) or data.sample_sdf(x, z) <= 0.05:
		return NAN
	return maxf(data.sample_height(x, z), ruin_top(x, z))


## The bare ground at (x, z), without ruins or stones; NAN off the island.
func bare_ground(x: float, z: float) -> float:
	if not data.in_bounds(x, z) or data.sample_sdf(x, z) <= 0.05:
		return NAN
	return data.sample_height(x, z)


## The top of the ruins at (x, z), or -INF. Safe from a worker thread: the
## raster is only replaced, never changed in place, while roots grow.
func ruin_top(x: float, z: float) -> float:
	var i := int(floor((x + RASTER_N * RASTER_CELL * 0.5) / RASTER_CELL))
	var j := int(floor((z + RASTER_N * RASTER_CELL * 0.5) / RASTER_CELL))
	if i < 0 or j < 0 or i >= RASTER_N or j >= RASTER_N:
		return -INF
	return _raster[j * RASTER_N + i]


## The raster as the ruins and stones stand now (not while roots grow on a
## worker that reads it).
func ensure_raster() -> void:
	if ruins and _task < 0 and (ruins.revision != _raster_rev or (props and props.revision != _stones_rev)):
		_take_raster()


## Take the ruins' tops from their meshes: every triangle that faces up
## raises the cells whose centres it covers to its own height there. Side
## faces are left out, or a wall would seem as wide as its stones lean.
func _take_raster() -> void:
	_raster_dirty = true
	_raster_rev = ruins.revision
	_stones_rev = props.revision if props else -1
	var r := PackedFloat32Array()
	r.resize(RASTER_N * RASTER_N)
	r.fill(-INF)
	var half := RASTER_N * RASTER_CELL * 0.5
	var solids: Array = ruins.meshes()
	if props:
		solids.append_array(props.stone_meshes())
	for entry in solids:
		var mesh: Mesh = entry[0]
		var xf: Transform3D = entry[1]
		# a generated stone gives its rough outline, a few big triangles
		var parts: Array = []
		if mesh.has_meta("hull"):
			parts.append([mesh.get_meta("hull"), PackedInt32Array()])
		else:
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				parts.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()])
		for part in parts:
			var verts: PackedVector3Array = part[0]
			var idx: PackedInt32Array = part[1]
			var world := PackedVector3Array()
			world.resize(verts.size())
			for k in verts.size():
				world[k] = xf * verts[k]
			var count := idx.size() if not idx.is_empty() else verts.size()
			for t in range(0, count - 2, 3):
				var a := world[idx[t] if not idx.is_empty() else t]
				var b := world[idx[t + 1] if not idx.is_empty() else t + 1]
				var c := world[idx[t + 2] if not idx.is_empty() else t + 2]
				var up := (b - a).cross(c - a)
				if up.y < 0.0:
					up = -up
				if up.length_squared() < 1e-10 or up.normalized().y < 0.35:
					continue
				var top := maxf(a.y, maxf(b.y, c.y))
				var i0 := clampi(int((minf(a.x, minf(b.x, c.x)) + half) / RASTER_CELL), 0, RASTER_N - 1)
				var i1 := clampi(int((maxf(a.x, maxf(b.x, c.x)) + half) / RASTER_CELL), 0, RASTER_N - 1)
				var j0 := clampi(int((minf(a.z, minf(b.z, c.z)) + half) / RASTER_CELL), 0, RASTER_N - 1)
				var j1 := clampi(int((maxf(a.z, maxf(b.z, c.z)) + half) / RASTER_CELL), 0, RASTER_N - 1)
				# a triangle smaller than a cell still marks the cell it sits in
				var mid := (a + b + c) / 3.0
				var km := clampi(int((mid.z + half) / RASTER_CELL), 0, RASTER_N - 1) * RASTER_N + clampi(int((mid.x + half) / RASTER_CELL), 0, RASTER_N - 1)
				r[km] = maxf(r[km], top)
				var a2 := Vector2(a.x, a.z)
				var b2 := Vector2(b.x, b.z)
				var c2 := Vector2(c.x, c.z)
				for j in range(j0, j1 + 1):
					for i in range(i0, i1 + 1):
						var p := Vector2((i + 0.5) * RASTER_CELL - half, (j + 0.5) * RASTER_CELL - half)
						var bc := _barycentric(p, a2, b2, c2)
						if bc.x < -0.02 or bc.y < -0.02 or bc.z < -0.02:
							continue
						var y := a.y * bc.x + b.y * bc.y + c.y * bc.z
						var k := j * RASTER_N + i
						if y > r[k]:
							r[k] = y
	_raster = r


static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## A start for a point the brush picked on the island.
func anchor_at(p: Vector3) -> Array:
	var on := On.SIDE
	var g := ground(p.x, p.z)
	# on the bare ground, or on a ruin's top
	var near_ground: bool = data.sample_sdf(p.x, p.z) > 0.05 and absf(p.y - data.sample_height(p.x, p.z)) < 0.35
	if near_ground or (not is_nan(g) and absf(p.y - g) < 0.35):
		on = On.GROUND
	elif p.y - IslandMesher.underside(data, p.x, p.z) < 0.35:
		on = On.UNDER
	return [p.x, p.y, p.z, on]


func add(anchors: Array, seed: int) -> void:
	if anchors.is_empty():
		return
	records.append({"seed": seed, "anchors": anchors.duplicate(true), "style": style.duplicate(true)})
	clear_preview()
	_refresh()


## A style dial moved: new roots get it, and so do the last roots drawn.
func set_style(key: String, value) -> void:
	style[key] = value
	if not records.is_empty():
		records.back().style = style.duplicate(true)
		_refresh()


## Show the roots a stroke would grow, while it is being drawn. They grow
## on a worker thread, so the brush keeps moving; a newer stroke shape waits
## for the one growing now and replaces any that waited before it.
func preview(anchors: Array, seed: int) -> void:
	_showing = true
	_waiting = [_resolve(anchors), style.duplicate(true), seed]
	_set_look(_preview, style)
	_start_preview()


func clear_preview() -> void:
	_showing = false
	_waiting = []
	_preview.mesh = null


func _start_preview() -> void:
	if _task >= 0 or _waiting.is_empty():
		return
	var args := _waiting
	_waiting = []
	_task = WorkerThreadPool.add_task(func() -> void:
		_grown = RootBuilder.grow(args[0], args[1], args[2], inside, ground, bare_ground))


func _process(_delta: float) -> void:
	# the ruins changed: take their tops again and regrow the roots on them
	ensure_raster()
	if _raster_dirty and _task < 0:
		_raster_dirty = false
		_refresh()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _showing:
			_preview.mesh = RootBuilder.to_mesh(_grown)
		_start_preview()


## Take away every root that starts within r of c.
func remove_near(c: Vector3, r: float) -> bool:
	var keep: Array = []
	for rec in records:
		var near := false
		for a in rec.anchors:
			if Vector3(a[0], a[1], a[2]).distance_to(c) < r:
				near = true
		if not near:
			keep.append(rec)
	if keep.size() == records.size():
		return false
	records = keep
	_refresh()
	return true


func snapshot() -> Array:
	return records.duplicate(true)


func restore(state: Array) -> void:
	records = state.duplicate(true)
	_refresh()


## The ground changed: regrow the roots whose starts moved or lost their rock.
func follow_ground() -> void:
	_refresh()


## [position, outward, crawls] for each start that still has something to
## start on. Starts saved before roots could crawl say true or false for
## the underside.
func _resolve(anchors: Array) -> Array:
	var out: Array = []
	for a in anchors:
		var x: float = a[0]
		var z: float = a[2]
		var on: int = (On.UNDER if a[3] else On.SIDE) if a[3] is bool else a[3]
		if not data.in_bounds(x, z) or data.sample_sdf(x, z) <= -0.2:
			continue
		var y: float = a[1]
		if on == On.GROUND:
			y = ground(x, z)
			if is_nan(y):
				continue
			# drawn on the bare ground beside a ruin, it stays on the ground,
			# even where the ruin's stones lean out over it
			var bare: float = data.sample_height(x, z)
			if absf(float(a[1]) - bare) < absf(float(a[1]) - y):
				# and never under one: step out to the nearest open ground
				var free := _out_from_under(x, z)
				x = free.x
				z = free.y
				y = data.sample_height(x, z)
		elif on == On.UNDER:
			y = IslandMesher.underside(data, x, z)
		var d: float = data.sample_sdf(x, z)
		# near the coast the roots lean out from the cliff; under the middle
		# they hang straight
		var lean: Vector3 = data.outward(x, z) * (1.0 - smoothstep(0.0, 3.0, d))
		out.append([Vector3(x, y, z), lean, on == On.GROUND])
	return out


## Whether any of the record's roots start on the ground (and so may cross
## ruins, and must regrow when the ruins change).
static func _crawls(rec: Dictionary) -> bool:
	for a in rec.anchors:
		if not a[3] is bool and a[3] == On.GROUND:
			return true
	return false


## (x, z), or the nearest spot within a metre that no ruin or stone covers.
func _out_from_under(x: float, z: float) -> Vector2:
	if ruin_top(x, z) <= data.sample_height(x, z) + 0.15:
		return Vector2(x, z)
	for ring in range(1, 11):
		var r := ring * RASTER_CELL
		for s in 16:
			var a := TAU * s / 16.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if data.sample_sdf(px, pz) > 0.1 and ruin_top(px, pz) <= data.sample_height(px, pz) + 0.15:
				# a little further, so the root's own girth clears it too
				return Vector2(x + cos(a) * (r + 0.15), z + sin(a) * (r + 0.15))
	return Vector2(x, z)


## The record's style, filling in what older records lack.
static func _style_of(rec: Dictionary) -> Dictionary:
	var s: Dictionary = rec.get("style", {}).duplicate(true)
	if rec.has("length") and not s.has("length"):
		s.length = rec.length
		s.spread = rec.spread
	return RootBuilder.style_of(s)


static func _set_look(mi: MeshInstance3D, s: Dictionary) -> void:
	var tint: Array = s.tint
	mi.set_instance_shader_parameter("tint", Vector3(tint[0], tint[1], tint[2]))
	mi.set_instance_shader_parameter("bark", s.bark)


func _refresh() -> void:
	var seen := {}
	var changed := false
	for rec in records:
		var seed: int = rec.seed
		seen[seed] = true
		var st := _style_of(rec)
		var resolved := _resolve(rec.anchors)
		if _nodes.has(seed):
			_set_look(_nodes[seed], st)
		# colour and bark are only the look: changing them never regrows
		var shape := st.duplicate()
		shape.erase("tint")
		shape.erase("bark")
		var key := str(resolved) + str(shape) + ("%d/%d" % [_raster_rev, _stones_rev] if _crawls(rec) else "")
		if _built.get(seed, "") == key:
			continue
		_built[seed] = key
		if not _nodes.has(seed):
			var mi := MeshInstance3D.new()
			mi.material_override = material
			add_child(mi)
			_nodes[seed] = mi
		_set_look(_nodes[seed], st)
		var grown := RootBuilder.grow(resolved, st, seed, inside, ground, bare_ground)
		_nodes[seed].mesh = RootBuilder.to_mesh(grown)
		_lying[seed] = grown.get("lying", PackedFloat32Array())
		changed = true
	for seed in _nodes.keys():
		if not seen.has(seed):
			_nodes[seed].queue_free()
			_nodes.erase(seed)
			_built.erase(seed)
			_lying.erase(seed)
			changed = true
	if changed:
		_keep_grass_away()


## Clear the grass where roots lie on the ground: a soft strip a little
## wider than each root. Only the terrain texture the grass reads changes,
## so nothing has to be rebuilt.
func _keep_grass_away() -> void:
	var cell: float = data.CELL
	var half: float = data.SIZE * 0.5
	var mask := PackedFloat32Array()
	mask.resize(data.RES * data.RES)
	for seed in _lying:
		var marks: PackedFloat32Array = _lying[seed]
		for m in range(0, marks.size(), 3):
			var x := marks[m]
			var z := marks[m + 1]
			var reach := marks[m + 2] + 0.25
			var i0 := maxi(int((x - reach + half) / cell), 0)
			var i1 := mini(int((x + reach + half) / cell) + 1, data.RES - 1)
			var j0 := maxi(int((z - reach + half) / cell), 0)
			var j1 := mini(int((z + reach + half) / cell) + 1, data.RES - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var d := Vector2(i * cell - half - x, j * cell - half - z).length()
					var w := 1.0 - smoothstep(marks[m + 2] + 0.04, reach, d)
					var k: int = j * data.RES + i
					if w > mask[k]:
						mask[k] = w
	# only the cells that changed go to the texture
	var lo := Vector2i(data.RES, data.RES)
	var hi := Vector2i(-1, -1)
	for k in mask.size():
		if absf(mask[k] - data.root_mask[k]) > 0.001:
			var p := Vector2i(k % data.RES, k / data.RES)
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	data.root_mask = mask
	if hi.x < 0:
		return
	data.refresh_image(Rect2i(lo, hi - lo + Vector2i.ONE))
	if view:
		view.texture.update(data.image)
