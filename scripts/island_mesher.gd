extends RefCounted
## Turns one tile of IslandData into two meshes: the ground on top, and the
## soil-and-rock body below it. They are built separately because most edits
## (sculpting inland, painting) only change the top. The coastline comes
## from marching squares over the signed distance field, so the outline is
## smooth and any painted shape is meshed the same way.
##
## Below the coast hangs a straight skirt (soil under the grass, then rock),
## and below that the underside tapers toward a point. The skirt's last row
## and the underside's outer edge sit at the same positions, so they meet
## without cracks.
##
## Every position and normal is a function of the grid alone, never of what
## else is in the tile, so neighbouring tiles meet without seams.

const IslandData := preload("res://scripts/island_data.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

const SKIRT_DEPTH := 1.3
const SKIRT_ROWS := 6
const BODY_DEPTH := 8.5

static var _noise: FastNoiseLite
static var _chunks: FastNoiseLite


class Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, uv: Vector2, c: Color, uv2 := Vector2.ZERO) -> int:
		verts.append(p)
		uv2s.append(uv2)
		normals.append(n)
		uvs.append(uv)
		colors.append(c)
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		indices.append(a)
		indices.append(b)
		indices.append(c)

	func to_mesh() -> ArrayMesh:
		if indices.is_empty():
			return null
		var mesh := ArrayMesh.new()
		MeshUtil.add_surface(mesh, verts, normals, uvs, colors, indices, uv2s)
		return mesh


## Per-tile scratch: grid values for the tile plus a one-point border, so
## normals can use central differences without leaving the cache.
class Grid:
	var data
	var i0: int
	var j0: int
	var w: int
	var surf := PackedFloat32Array()   # top surface height
	var under := PackedFloat32Array()  # underside height
	var top_n := PackedVector3Array()
	var under_n := PackedVector3Array()

	func local(k: int) -> int:
		return (k / IslandData.RES - j0) * w + (k % IslandData.RES - i0)


static func _init_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 21
	_noise.frequency = 0.22
	_noise.fractal_octaves = 4
	_chunks = FastNoiseLite.new()
	_chunks.seed = 22
	_chunks.noise_type = FastNoiseLite.TYPE_CELLULAR
	_chunks.frequency = 0.32
	_chunks.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE


static func _grid(data, ti: int, tj: int, with_body: bool) -> Grid:
	var tile: int = IslandData.TILE
	var res: int = IslandData.RES
	var cell: float = IslandData.CELL
	var g := Grid.new()
	g.data = data
	g.i0 = ti * tile - 1
	g.j0 = tj * tile - 1
	g.w = tile + 3
	var n := g.w * g.w
	g.surf.resize(n)
	g.top_n.resize(n)
	if with_body:
		g.under.resize(n)
		g.under_n.resize(n)
	for lj in g.w:
		for li in g.w:
			var i := clampi(g.i0 + li, 0, res - 1)
			var j := clampi(g.j0 + lj, 0, res - 1)
			var k := j * res + i
			g.surf[lj * g.w + li] = data.surface(k)
			if with_body:
				var p: Vector2 = data.grid_pos(i, j)
				g.under[lj * g.w + li] = -SKIRT_DEPTH - maxf(0.0, _hang(data.inland[k], p.x, p.y) - data.carve[k])
	for lj in g.w:
		for li in g.w:
			var l := lj * g.w + li
			var lx0 := lj * g.w + maxi(li - 1, 0)
			var lx1 := lj * g.w + mini(li + 1, g.w - 1)
			var lz0 := maxi(lj - 1, 0) * g.w + li
			var lz1 := mini(lj + 1, g.w - 1) * g.w + li
			g.top_n[l] = Vector3(-(g.surf[lx1] - g.surf[lx0]) / (2.0 * cell), 1.0, -(g.surf[lz1] - g.surf[lz0]) / (2.0 * cell)).normalized()
			if with_body:
				g.under_n[l] = Vector3((g.under[lx1] - g.under[lx0]) / (2.0 * cell), -1.0, (g.under[lz1] - g.under[lz0]) / (2.0 * cell)).normalized()
	return g


## [top mesh, body mesh] for tile (ti, tj); either is null when not asked for
## or when the tile holds no land.
static func build_tile(data, ti: int, tj: int, want_top: bool, want_body: bool) -> Array:
	_init_noise()
	var g := _grid(data, ti, tj, want_body)
	var top := Surface.new()
	var body := Surface.new()
	var top_ids := {}
	var under_ids := {}
	var columns := {}
	var tile: int = IslandData.TILE
	var res: int = IslandData.RES
	var sdf: PackedFloat32Array = data.sdf
	var has_land := false
	for j in range(tj * tile, (tj + 1) * tile):
		for i in range(ti * tile, (ti + 1) * tile):
			var k00 := j * res + i
			var corners := [k00, k00 + 1, k00 + res + 1, k00 + res]
			# Walk the cell's corners in order and keep the part that is land.
			# Corner keys are ints, coast crossings are Vector2i edge keys.
			var poly := []
			for e in 4:
				var a: int = corners[e]
				var b: int = corners[(e + 1) % 4]
				var sa := sdf[a]
				var sb := sdf[b]
				if sa > 0.0:
					poly.append(a)
				if (sa > 0.0) != (sb > 0.0):
					poly.append(Vector2i(mini(a, b), maxi(a, b)))
			if poly.size() < 3:
				continue
			has_land = true
			var tids := []
			if want_top or want_body:
				for key in poly:
					tids.append(_top_vertex(g, top, top_ids, key))
				if want_top:
					for k in range(1, poly.size() - 1):
						top.tri(tids[0], tids[k], tids[k + 1])
			if want_body:
				var uids := []
				for key in poly:
					uids.append(_under_vertex(g, body, under_ids, key))
				for k in range(1, poly.size() - 1):
					body.tri(uids[0], uids[k + 1], uids[k])
				for k in poly.size():
					var p0 = poly[k]
					var p1 = poly[(k + 1) % poly.size()]
					if p0 is Vector2i and p1 is Vector2i:
						_skirt_segment(g, top, top_ids, body, columns, p0, p1)
	if not has_land:
		return [null, null]
	return [top.to_mesh() if want_top else null, body.to_mesh() if want_body else null]


## (water level, water amount) for the ground shader. Dry points report a
## level well below their own ground, so blending toward them never wets it.
static func _wet(g: Grid, k: int) -> Vector2:
	var w: float = g.data.water[k]
	if w <= 0.0:
		return Vector2(g.surf[g.local(k)] - 1.0, 0.0)
	return Vector2(g.data.wlevel[k], w)


## Where a coast crossing sits along its grid edge, 0 at key.x.
static func _crossing_t(g: Grid, key: Vector2i) -> float:
	var sa: float = g.data.sdf[key.x]
	var sb: float = g.data.sdf[key.y]
	return sa / (sa - sb)


static func _top_vertex(g: Grid, s: Surface, ids: Dictionary, key) -> int:
	if ids.has(key):
		return ids[key]
	var data = g.data
	var id: int
	if key is int:
		var k: int = key
		var p: Vector2 = data.grid_pos_k(k)
		var l := g.local(k)
		# uv.x carries the distance to the coast so the shader can treat the rim
		id = s.add(Vector3(p.x, g.surf[l], p.y), g.top_n[l], Vector2(data.sdf[k], data.rocks[k]), data.splat[k], _wet(g, k))
	else:
		var t := _crossing_t(g, key)
		var la := g.local(key.x)
		var lb := g.local(key.y)
		var p: Vector2 = (data.grid_pos_k(key.x) as Vector2).lerp(data.grid_pos_k(key.y), t)
		var c: Color = (data.splat[key.x] as Color).lerp(data.splat[key.y], t)
		var n := g.top_n[la].lerp(g.top_n[lb], t).normalized()
		id = s.add(Vector3(p.x, lerpf(g.surf[la], g.surf[lb], t), p.y), n, Vector2(0.0, lerpf(data.rocks[key.x], data.rocks[key.y], t)), c, _wet(g, key.x).lerp(_wet(g, key.y), t))
	ids[key] = id
	return id


static func _under_vertex(g: Grid, s: Surface, ids: Dictionary, key) -> int:
	if ids.has(key):
		return ids[key]
	var data = g.data
	var p: Vector2
	var y: float
	var n: Vector3
	var d := 0.0
	if key is int:
		var k: int = key
		var l := g.local(k)
		p = data.grid_pos_k(k)
		y = g.under[l]
		n = g.under_n[l]
		d = data.sdf[k]
	else:
		var t := _crossing_t(g, key)
		var la := g.local(key.x)
		var lb := g.local(key.y)
		p = (data.grid_pos_k(key.x) as Vector2).lerp(data.grid_pos_k(key.y), t)
		y = -SKIRT_DEPTH
		n = g.under_n[la].lerp(g.under_n[lb], t).normalized()
	var fade := smoothstep(0.0, 1.2, d)
	var off := Vector2.ZERO
	if fade > 0.0:
		off = Vector2(_noise.get_noise_3d(p.x, y, p.y + 40.0), _noise.get_noise_3d(p.x + 40.0, y, p.y)) * 0.7 * fade
	# uv.x: depth below the rim, which the cliff shader uses for its soil band
	var id := s.add(Vector3(p.x + off.x, y, p.y + off.y), n, Vector2(-y, 0.0), Color(0, 0, 0, 0))
	ids[key] = id
	return id


## The full hang at grid point k, before any wearing away: the most that
## can be carved there.
static func hang_at(data, k: int) -> float:
	_init_noise()
	var p: Vector2 = data.grid_pos_k(k)
	return _hang(data.inland[k], p.x, p.y)


## The height of the underside at (x, z), as meshed (without the small
## sideways wobble of its vertices).
static func underside(data, x: float, z: float) -> float:
	_init_noise()
	var d: float = data.sample_inland(x, z)
	return -SKIRT_DEPTH - maxf(0.0, _hang(d, x, z) - data.sample_carve(x, z))


## How far the underside hangs below the skirt at coast distance d (the true
## distance, see IslandData.inland). It keeps growing the further inland, so
## a bigger island hangs deeper in proportion: steeply near the coast, then
## on at the same slope.
static func _hang(d: float, x: float, z: float) -> float:
	if d <= 0.0:
		return 0.0
	var u := d / 6.0
	var t := clampf(u, 0.0, 1.0)
	var base := BODY_DEPTH * (pow(t, 0.6) + 0.9 * maxf(u - 1.0, 0.0))
	var fade := smoothstep(0.0, 1.5, d)
	var lumps := _noise.get_noise_2d(x * 1.3, z * 1.3) * 1.8
	var steps := _chunks.get_noise_2d(x, z) * 1.4
	return maxf(0.0, base + (lumps + steps) * fade * (0.4 + t))


static func _skirt_segment(g: Grid, top: Surface, top_ids: Dictionary, body: Surface, columns: Dictionary, k0, k1) -> void:
	var c0 := _column(g, top, top_ids, body, columns, k0)
	var c1 := _column(g, top, top_ids, body, columns, k1)
	var a := body.verts[c0]
	var b := body.verts[c1]
	var c := body.verts[c1 + 1]
	var out: Vector3 = g.data.outward(a.x, a.z)
	var flip := MeshUtil.face_normal(a, b, c).dot(out) < 0.0
	for r in SKIRT_ROWS:
		var i0 := c0 + r
		var i1 := c1 + r
		var i2 := c1 + r + 1
		var i3 := c0 + r + 1
		if flip:
			body.tri(i0, i2, i1)
			body.tri(i0, i3, i2)
		else:
			body.tri(i0, i1, i2)
			body.tri(i0, i2, i3)


## One column of skirt vertices hanging from a coast vertex. Normals come
## from the column's own shape: along the coast, and down the column.
static func _column(g: Grid, top: Surface, top_ids: Dictionary, body: Surface, columns: Dictionary, key) -> int:
	if columns.has(key):
		return columns[key]
	var top_p := top.verts[top_ids[key]]
	var out: Vector3 = g.data.outward(top_p.x, top_p.z)
	var along := Vector3.UP.cross(out)
	var ledge := maxf(0.0, _noise.get_noise_2d(top_p.x * 1.4, top_p.z * 1.4)) * 0.9
	# where water pours over, the rim is worn back instead of bulging out,
	# so the fall hangs clear of the rock
	var worn := smoothstep(0.05, 0.4, g.data.sample_water(top_p.x, top_p.z))
	var pts: Array[Vector3] = []
	for r in SKIRT_ROWS + 1:
		var t := float(r) / SKIRT_ROWS
		var y := lerpf(top_p.y, -SKIRT_DEPTH, t)
		# the soil under the grass bulges out a little before tucking back in,
		# and along the coast some stretches jut out as rock ledges
		var bulge := sin(t * PI) * (0.1 + ledge + 0.3 * _noise.get_noise_3d(top_p.x * 2.0, y * 2.0, top_p.z * 2.0))
		bulge = lerpf(bulge, -0.3 * sin(t * PI), worn)
		pts.append(Vector3(top_p.x, y, top_p.z) + out * bulge)
	var first := body.verts.size()
	for r in SKIRT_ROWS + 1:
		var down := pts[mini(r + 1, SKIRT_ROWS)] - pts[maxi(r - 1, 0)]
		var n := along.cross(down).normalized()
		if n.dot(out) < 0.0:
			n = -n
		body.add(pts[r], n, Vector2(top_p.y - pts[r].y, 0.0), Color(0, 0, 0, 0))
	columns[key] = first
	return first
