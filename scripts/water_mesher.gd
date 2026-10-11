extends RefCounted
## Water for one tile: the surface of ponds and streams, and waterfalls
## wherever water reaches the coast.
##
## The surface is meshed a little wider than the painted water, out to where
## the ground rises above the waterline again, so the shoreline is simply
## where the water plane meets the bank. It is clipped at the coast, and the
## coast stretch of its outline is where the waterfalls hang from.

const IslandData := preload("res://scripts/island_data.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

const THRESHOLD := 0.005
const FALL_ROWS := 16
const FALL_HEIGHT := 11.0

static var _noise: FastNoiseLite


class Result:
	var surface: ArrayMesh
	var falls: ArrayMesh
	var veil: ArrayMesh                       # soft spray over the lip
	var fall_bottom := PackedVector3Array()   # where the falls fade out, for mist


## Where the water surface shows: inside the island, and only where it stands
## above the ground. Its outline is then exactly the shoreline, where the
## surface meets the bank, so it never hangs in the air over lower ground.
static func _f(data, k: int) -> float:
	if data.water[k] <= THRESHOLD:
		return -0.05
	return minf(data.sdf[k], data.wlevel[k] - data.height[k])


static func build_tile(data, ti: int, tj: int) -> Result:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 31
		_noise.frequency = 0.6
	var out := Result.new()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var pull := PackedVector2Array()
	var idx := PackedInt32Array()
	var ids := {}
	var coast := {}   # crossing keys that lie on the coast with water behind them
	var segments := []
	var tile: int = IslandData.TILE
	var res: int = IslandData.RES
	for j in range(tj * tile, (tj + 1) * tile):
		for i in range(ti * tile, (ti + 1) * tile):
			var k00 := j * res + i
			var corners := [k00, k00 + 1, k00 + res + 1, k00 + res]
			var poly := []
			for e in 4:
				var a: int = corners[e]
				var b: int = corners[(e + 1) % 4]
				var fa := _f(data, a)
				var fb := _f(data, b)
				if fa > 0.0:
					poly.append(a)
				if (fa > 0.0) != (fb > 0.0):
					poly.append(Vector2i(mini(a, b), maxi(a, b)))
			if poly.size() < 3:
				continue
			var vid := []
			for key in poly:
				vid.append(_vertex(data, verts, uvs, pull, ids, coast, key))
			for k in range(1, poly.size() - 1):
				idx.append_array([vid[0], vid[k], vid[k + 1]])
			for k in poly.size():
				var p0 = poly[k]
				var p1 = poly[(k + 1) % poly.size()]
				if p0 is Vector2i and p1 is Vector2i and coast.has(p0) and coast.has(p1):
					segments.append([p0, p1])
	if idx.is_empty():
		return out
	out.surface = ArrayMesh.new()
	MeshUtil.add_surface(out.surface, verts, MeshUtil.normals(verts, idx), uvs, PackedColorArray(), idx, pull)
	if not segments.is_empty():
		out.falls = _falls(data, verts, ids, segments, out.fall_bottom)
		out.veil = _veil(data, verts, ids, segments)
	return out


static func _vertex(data, verts: PackedVector3Array, uvs: PackedVector2Array, pull: PackedVector2Array,
		ids: Dictionary, coast: Dictionary, key) -> int:
	if ids.has(key):
		return ids[key]
	var p: Vector2
	var level: float
	var wet: float
	if key is int:
		var k: int = key
		p = data.grid_pos_k(k)
		level = data.wlevel[k]
		wet = data.water[k]
	else:
		var a: int = key.x
		var b: int = key.y
		var fa := _f(data, a)
		var fb := _f(data, b)
		var t := fa / (fa - fb)
		p = (data.grid_pos_k(a) as Vector2).lerp(data.grid_pos_k(b), t)
		# the outside corner may have no level of its own; borrow the inside one
		var la: float = data.wlevel[a]
		var lb: float = data.wlevel[b]
		if la <= IslandData.NO_WATER + 1.0:
			la = lb
		if lb <= IslandData.NO_WATER + 1.0:
			lb = la
		level = lerpf(la, lb, t)
		wet = lerpf(data.water[a], data.water[b], t)
		var sa: float = data.sdf[a]
		var sb: float = data.sdf[b]
		if (sa > 0.0) != (sb > 0.0) and maxf(data.water[a], data.water[b]) > 0.15:
			coast[key] = true
	# uv.x: how much this point is painted water; uv.y: distance to the coast.
	# uv2: the pull toward the lip, so water near a fall visibly runs off.
	var d: float = data.sample_sdf(p.x, p.y)
	var out: Vector3 = data.outward(p.x, p.y)
	# toward the coast the surface bends down with the rolled rim, as water
	# does going over a weir, so it meets the fall instead of overhanging
	verts.append(Vector3(p.x, level - IslandData.roll(maxf(d, 0.0)), p.y))
	uvs.append(Vector2(wet, d))
	pull.append(Vector2(out.x, out.z) * (1.0 - smoothstep(0.0, 1.5, d)))
	ids[key] = verts.size() - 1
	return verts.size() - 1


## A soft band of spray laid over the lip: from a little way out on the
## water, over the edge, and a short way down the fall. It hides the seam
## where the surface turns into the fall. uv.y runs across the band, uv.x
## is 1 at the open ends of a run of fall.
static func _veil(data, verts: PackedVector3Array, ids: Dictionary, segments: Array) -> ArrayMesh:
	var vv := PackedVector3Array()
	var vuv := PackedVector2Array()
	var vidx := PackedInt32Array()
	var columns := {}
	var uses := {}
	for seg in segments:
		for key in seg:
			uses[key] = uses.get(key, 0) + 1
	var rim: float = IslandData.roll(0.0)
	# (inward distance, drop below the edge) for each row of the band
	var rows := [Vector2(-0.7, rim - IslandData.roll(0.7)), Vector2(-0.25, rim - IslandData.roll(0.25)),
			Vector2(0.12, -0.12), Vector2(0.3, -0.55), Vector2(0.42, -1.1)]
	for seg in segments:
		var cols := []
		for key in seg:
			if not columns.has(key):
				var edge := verts[ids[key]]
				var out: Vector3 = data.outward(edge.x, edge.z)
				columns[key] = vv.size()
				for r in rows.size():
					var row: Vector2 = rows[r]
					vv.append(edge + out * row.x + Vector3(0.0, row.y + 0.03, 0.0))
					vuv.append(Vector2(1.0 if uses[key] == 1 else 0.0, float(r) / (rows.size() - 1)))
			cols.append(columns[key])
		for r in rows.size() - 1:
			var a: int = cols[0] + r
			var b: int = cols[1] + r
			vidx.append_array([a, b, b + 1, a, b + 1, a + 1])
	var mesh := ArrayMesh.new()
	MeshUtil.add_surface(mesh, vv, MeshUtil.normals(vv, vidx), vuv, PackedColorArray(), vidx)
	return mesh


## A sheet that tips over the rim, arcs outward and falls, thinning out.
## uv.y runs 0 at the lip to 1 where it has faded away.
static func _falls(data, verts: PackedVector3Array, ids: Dictionary, segments: Array, bottom: PackedVector3Array) -> ArrayMesh:
	var fv := PackedVector3Array()
	var fuv := PackedVector2Array()
	var fidx := PackedInt32Array()
	var columns := {}
	# how many segments meet at each column: 1 means the sheet ends there
	var uses := {}
	for seg in segments:
		for key in seg:
			uses[key] = uses.get(key, 0) + 1
	for seg in segments:
		var c0 := _fall_column(data, verts, ids, columns, seg[0], fv, fuv, bottom, uses[seg[0]] == 1)
		var c1 := _fall_column(data, verts, ids, columns, seg[1], fv, fuv, bottom, uses[seg[1]] == 1)
		for r in FALL_ROWS:
			fidx.append_array([c0 + r, c1 + r, c1 + r + 1, c0 + r, c1 + r + 1, c0 + r + 1])
	var mesh := ArrayMesh.new()
	MeshUtil.add_surface(mesh, fv, MeshUtil.normals(fv, fidx), fuv, PackedColorArray(), fidx)
	return mesh


static func _fall_column(data, verts: PackedVector3Array, ids: Dictionary, columns: Dictionary, key,
		fv: PackedVector3Array, fuv: PackedVector2Array, bottom: PackedVector3Array, side: bool) -> int:
	if columns.has(key):
		return columns[key]
	var edge := verts[ids[key]]
	var out: Vector3 = data.outward(edge.x, edge.z)
	# start a little inside the water's edge and just above it, so the fall
	# grows out of the surface instead of butting against it
	var lip := edge - out * 0.25 + Vector3(0.0, 0.015, 0.0)
	var first := fv.size()
	for r in FALL_ROWS + 1:
		var t := float(r) / FALL_ROWS
		var drop := FALL_HEIGHT * pow(t, 1.35)
		var reach := 1.2 * sqrt(t)
		var sway := _noise.get_noise_3d(lip.x, lip.y - drop, lip.z) * 0.35 * t
		var p := lip + out * (reach + sway) + Vector3(0.0, -drop, 0.0)
		fv.append(p)
		# uv.x 1 along the sheet's open sides, where the shader thins it away
		fuv.append(Vector2(1.0 if side else 0.0, t))
		if r == FALL_ROWS:
			bottom.append(p)
	columns[key] = first
	return first
