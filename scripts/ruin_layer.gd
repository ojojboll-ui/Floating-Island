extends Node3D
## The ruins on the island: walls, pillars, arches, stairs and floors, each a
## small record (its path, end points or cells, a seed, a height) and a mesh
## built from it at the current age. Changing the age rebuilds them all;
## sculpting the ground rebuilds the ones standing on it.
##
## Pieces join up the way they do in Tiny Glade. An arch drawn along a wall
## is set into it and opens a doorway. A floor started on top of a stair, a
## pillar, a wall or another floor becomes a storey at that height, and
## whatever is built on it stands on it.
##
## Walls are cut, not deleted, by the eraser: the part under the brush goes
## and what is left either side stays as two walls.

const RuinBuilder := preload("res://scripts/ruin_builder.gd")

## The age changed (the dial, or undo and redo putting an older one back).
signal age_changed(value: float)

const SNAP := 0.6
const CELL := RuinBuilder.FLOOR_CELL

var data
var props
var records: Array = []
var age := 0.35
var material := ShaderMaterial.new()
## What ruins stand on: the ground, or a raised floor where there is one.
var ground: Ground
## The storey new pieces are being built on (NAN: the ground). The brush
## sets it at the start of each stroke.
var build_base := NAN

var _nodes := {}    # id -> MeshInstance3D
var _next_id := 1
var _preview: MeshInstance3D
var _floor_index := {}   # Vector2i cell -> Array of raised floor levels
## Counts every change to the pieces' meshes, so others (the roots) can tell
## when the ruins changed.
var revision := 0


## Ground height as ruins see it: terrain, raised to the highest floor below
## `limit` that covers the spot.
class Ground:
	var data
	var layer
	var limit := INF

	func sample_height(x: float, z: float) -> float:
		return maxf(data.sample_height(x, z), layer.floor_top(x, z, limit))

	func sample_sdf(x: float, z: float) -> float:
		return data.sample_sdf(x, z)


func setup(island_data, prop_layer) -> void:
	data = island_data
	props = prop_layer
	ground = _ground_below(-INF)
	material.shader = load("res://shaders/ruin_stone.gdshader")
	material.set_shader_parameter("age", age)
	_preview = MeshInstance3D.new()
	_preview.material_override = material
	add_child(_preview)


## What a piece stands on: the storey it was built on, or the bare ground.
func _ground_for(r: Dictionary) -> Ground:
	if r.has("base"):
		return _ground_below(float(r.base) + 0.05)
	return ground


func _build_ground() -> Ground:
	return ground if is_nan(build_base) else _ground_below(build_base + 0.05)


func _ground_below(limit: float) -> Ground:
	var g := Ground.new()
	g.data = data
	g.layer = self
	g.limit = limit
	return g


func set_age(value: float) -> void:
	age = value
	material.set_shader_parameter("age", age)
	age_changed.emit(age)
	for r in records:
		_rebuild(r)


# --- floors as ground ----------------------------------------------------------

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func floor_top(x: float, z: float, limit := INF) -> float:
	var levels: Array = _floor_index.get(cell_of(Vector2(x, z)), [])
	var best := -INF
	for l in levels:
		if l < limit - 0.05:
			best = maxf(best, l)
	return best


func _reindex() -> void:
	_floor_index.clear()
	for r in records:
		if r.kind == "floor" and r.raised:
			for c in r.cells:
				var key := Vector2i(c[0], c[1])
				if not _floor_index.has(key):
					_floor_index[key] = []
				_floor_index[key].append(float(r.level))


# --- adding ------------------------------------------------------------------

func add_wall(points: PackedVector2Array, height: float, seed: int) -> void:
	var path := RuinBuilder.smooth_path(points)
	if path.size() < 2 or RuinBuilder.path_length(path) < 0.6:
		return
	var pts := []
	for p in path:
		pts.append([p.x, p.y])
	_add({"kind": "wall", "pts": pts, "seed": seed, "height": height})


func add_pillar(at: Vector2, height: float, seed: int) -> void:
	_add({"kind": "pillar", "at": [at.x, at.y], "seed": seed, "height": height})


## An arch. Drawn along a wall it is set into that wall as a doorway;
## anywhere else it stands on two pillars of its own.
func add_arch(a: Vector2, b: Vector2, height: float, seed: int) -> void:
	if a.distance_to(b) < 0.8:
		return
	var rec := {"kind": "arch", "a": [a.x, a.y], "b": [b.x, b.y], "seed": seed, "height": height}
	var host := _host_wall(a, b)
	if not host.is_empty():
		rec.wall = host.wall.id
		rec.s0 = host.s0
		rec.s1 = host.s1
		var path := _path(host.wall)
		var pa: Vector2 = RuinBuilder._along(path, host.s0)[0]
		var pb: Vector2 = RuinBuilder._along(path, host.s1)[0]
		rec.a = [pa.x, pa.y]
		rec.b = [pb.x, pb.y]
	_add(rec)
	if rec.has("wall"):
		_rebuild(_record(rec.wall))


## The wall both ends of an arch lie along, if any, and where along it.
func _host_wall(a: Vector2, b: Vector2) -> Dictionary:
	for r in records:
		if r.kind != "wall":
			continue
		var path := _path(r)
		var pa := _project(path, a)
		var pb := _project(path, b)
		if pa[1] > 0.8 or pb[1] > 0.8:
			continue
		var s0 := minf(pa[0], pb[0])
		var s1 := maxf(pa[0], pb[0])
		var length := RuinBuilder.path_length(path)
		s0 = maxf(s0, 0.3)
		s1 = minf(s1, length - 0.3)
		if s1 - s0 >= 0.8:
			return {"wall": r, "s0": s0, "s1": s1}
	return {}


## [arc length of the nearest point on the path, distance to it]
static func _project(path: PackedVector2Array, p: Vector2) -> Array:
	var best_s := 0.0
	var best_d := INF
	var acc := 0.0
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		var seg := a.distance_to(b)
		var t := clampf((p - a).dot(b - a) / maxf(seg * seg, 0.0001), 0.0, 1.0)
		var d := a.lerp(b, t).distance_to(p)
		if d < best_d:
			best_d = d
			best_s = acc + t * seg
		acc += seg
	return [best_s, best_d]


func add_stairs(a: Vector2, b: Vector2, height: float, seed: int) -> void:
	if a.distance_to(b) < 0.5:
		return
	_add({"kind": "stairs", "a": [a.x, a.y], "b": [b.x, b.y], "seed": seed, "height": height})


func _add(rec: Dictionary) -> void:
	if not is_nan(build_base):
		rec.base = build_base
	rec.id = _next_id
	_next_id += 1
	records.append(rec)
	_mark(rec)
	_spawn(rec)


## Start a floor stroke: raised at `level`, or on the ground if level is NAN.
func begin_floor(level: float, seed: int) -> Dictionary:
	var raised := not is_nan(level)
	var rec := {"kind": "floor", "cells": [], "level": level if raised else 0.0, "raised": raised, "seed": seed, "height": 0.0}
	if not is_nan(build_base):
		rec.base = build_base
	rec.id = _next_id
	_next_id += 1
	records.append(rec)
	_spawn(rec)
	return rec


## Add the cells under a brush to a floor being painted.
func paint_floor(rec: Dictionary, c: Vector2, radius: float) -> void:
	var have := {}
	for cell in rec.cells:
		have[Vector2i(cell[0], cell[1])] = true
	var lo := cell_of(c - Vector2(radius, radius))
	var hi := cell_of(c + Vector2(radius, radius))
	var added := false
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var key := Vector2i(i, j)
			var centre := (Vector2(key) + Vector2(0.5, 0.5)) * CELL
			if have.has(key) or centre.distance_to(c) > radius:
				continue
			if not data.in_bounds(centre.x, centre.y) or data.sample_sdf(centre.x, centre.y) < 0.2:
				continue
			rec.cells.append([i, j])
			added = true
	if added and rec.raised:
		_reindex()


func refresh(rec: Dictionary) -> void:
	_rebuild(rec)


## A floor stroke is done: keep it if it has any cells, mark the ground, and
## rebuild whatever now stands on it.
func finish_floor(rec: Dictionary) -> void:
	if rec.cells.is_empty():
		_drop(rec)
		return
	_reindex()
	_mark(rec)
	_rebuild_in(_bounds(rec))


## Show what a stroke would build, without committing it.
func preview(kind: String, a: Vector2, b: Vector2, points: PackedVector2Array, height: float, seed: int) -> void:
	var m: ArrayMesh = null
	match kind:
		"wall":
			var path := RuinBuilder.smooth_path(points)
			if path.size() >= 2:
				m = RuinBuilder.wall(_build_ground(), path, seed, height, age)
		"arch":
			var host := _host_wall(a, b)
			if host.is_empty():
				m = RuinBuilder.arch(_build_ground(), a, b, seed, height, age)
			else:
				m = RuinBuilder.arch_in_wall(_ground_for(host.wall), _path(host.wall), host.s0, host.s1, seed, height, age)
		"stairs":
			m = RuinBuilder.stairs(_build_ground(), a, b, seed, age, false, height)
	_preview.mesh = m
	_preview.visible = m != null


func clear_preview() -> void:
	_preview.mesh = null


## The nearest end of an existing piece within reach, for joining pieces up.
func snap_point(p: Vector2) -> Vector2:
	var best := p
	var best_d := SNAP
	for r in records:
		if r.kind == "floor":
			continue
		for e in _ends(r):
			var d := p.distance_to(e)
			if d < best_d:
				best_d = d
				best = e
	return best


static func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func _ends(r: Dictionary) -> Array:
	match r.kind:
		"wall":
			return [_v(r.pts[0]), _v(r.pts[r.pts.size() - 1])]
		"pillar":
			return [_v(r.at)]
		"floor":
			return []
		_:
			return [_v(r.a), _v(r.b)]


func _path(r: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in r.pts:
		out.append(_v(p))
	return out


func _record(id: int) -> Dictionary:
	for r in records:
		if r.id == id:
			return r
	return {}


# --- what can be built on: tops of pieces ------------------------------------------

## A raised floor the mouse ray meets before the ground: {pos, level, t}.
## Floors are flat and whole, so their top is where it looks to be.
func pick_support(o: Vector3, d: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for r in records:
		if r.kind != "floor" or not r.raised or absf(d.y) < 0.0001:
			continue
		var level := float(r.level)
		var t := (level - o.y) / d.y
		if t <= 0.0 or t >= best_t:
			continue
		var q := o + d * t
		if _on_top(r, Vector2(q.x, q.z)):
			best_t = t
			best = {"pos": q, "level": level, "t": t}
	return best


## The piece the mouse ray hits, by its actual shape and however ruined it
## is: walk down the ray and stop inside the first footprint whose stones
## reach that high. {record, pos} or empty.
func pick_piece(o: Vector3, d: Vector3, t_max: float) -> Dictionary:
	var t := 0.0
	while t < t_max:
		var q := o + d * t
		var p := Vector2(q.x, q.z)
		for r in records:
			if r.kind == "floor" and not r.raised:
				continue
			if not _on_top(r, p, 0.12):
				continue
			var g := _ground_for(r)
			var foot: float = g.sample_height(p.x, p.y) - 0.2
			if r.kind == "floor":
				foot = float(r.level) - 0.3
			if q.y >= foot and q.y <= _top(r) + 0.05:
				return {"record": r, "pos": q}
		t += 0.05
	return {}


## Where a storey goes when it is started on piece r: on top of it, or for
## a floor, a full storey above.
func storey_level(r: Dictionary, storey_height: float) -> float:
	if r.kind == "floor" and r.raised:
		return float(r.level) + storey_height
	return _top(r)


## Height of a piece's top as built at full height, or NAN if it has none.
func _top(r: Dictionary) -> float:
	var g := _ground_for(r)
	match r.kind:
		"floor":
			return float(r.level) if r.raised else NAN
		"pillar":
			var at := _v(r.at)
			return g.sample_height(at.x, at.y) - 0.1 + float(r.height)
		"stairs":
			return RuinBuilder.stairs_top(g, _v(r.a), _v(r.b), float(r.height))
		"wall":
			var path := _path(r)
			var mid: Vector2 = RuinBuilder._along(path, RuinBuilder.path_length(path) * 0.5)[0]
			return g.sample_height(mid.x, mid.y) - 0.12 + float(r.height)
		"arch":
			var a := _v(r.a)
			var b := _v(r.b)
			return maxf(g.sample_height(a.x, a.y), g.sample_height(b.x, b.y)) - 0.1 + float(r.height) + a.distance_to(b) * 0.5 + 0.2
	return NAN


func _on_top(r: Dictionary, p: Vector2, margin := 0.0) -> bool:
	match r.kind:
		"floor":
			for c in r.cells:
				if cell_of(p) == Vector2i(c[0], c[1]):
					return true
			return false
		"pillar":
			return p.distance_to(_v(r.at)) < 0.5 + margin
		"stairs":
			if margin > 0.0:
				return _segment_distance(p, _v(r.a), _v(r.b)) < 0.65 + margin
			var a := _v(r.a)
			var b := _v(r.b)
			var count: int = RuinBuilder._stair_shape(_ground_for(r), a, b, float(r.height))[0]
			return p.distance_to(a.lerp(b, (count - 0.5) / count)) < 0.65
		"wall":
			var path := _path(r)
			for k in path.size() - 1:
				if _segment_distance(p, path[k], path[k + 1]) < 0.3 + margin:
					return true
		"arch":
			return _segment_distance(p, _v(r.a), _v(r.b)) < 0.4 + margin
	return false


## The lowest storey above this spot, or NAN.
func _storey_over(p: Vector2, above: float) -> float:
	var best := NAN
	for l in _floor_index.get(cell_of(p), []):
		if l > above + 0.2 and (is_nan(best) or l < best):
			best = l
	return best


## The pieces' meshes as they stand (crumbled by age), each with its place.
func meshes() -> Array:
	var out: Array = []
	for node in _nodes.values():
		var mi := node as MeshInstance3D
		if mi and mi.mesh and not mi.is_queued_for_deletion():
			out.append([mi.mesh, mi.global_transform])
	return out


## The highest top of any ruin standing on this spot, or -INF.
func top_at(p: Vector2) -> float:
	var best := -INF
	for r in records:
		if r.kind == "floor" and not r.raised:
			continue
		if _on_top(r, p, 0.0 if r.kind != "stairs" else 0.1):
			var t := _top(r)
			if r.kind == "stairs":
				# the step under this spot, not the top one
				var a := _v(r.a)
				var b := _v(r.b)
				var along := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
				var g := _ground_for(r).sample_height(a.x, a.y)
				t = g + (t - g) * ceilf(along * 8.0) / 8.0
			if not is_nan(t):
				best = maxf(best, t)
	return best


## Whether a raised floor rests on this spot (from above).
func _under_storey(p: Vector2, above: float) -> bool:
	for l in _floor_index.get(cell_of(p), []):
		if l > above + 0.2:
			return true
	return false


## Whether a storey rests on piece r, so its top must stay whole.
func _carries(r: Dictionary) -> bool:
	match r.kind:
		"pillar":
			return _under_storey(_v(r.at), _ground_for(r).sample_height(r.at[0], r.at[1]))
		"stairs":
			var a := _v(r.a)
			var b := _v(r.b)
			var count: int = RuinBuilder._stair_shape(_ground_for(r), a, b, float(r.height))[0]
			var top := a.lerp(b, (count - 0.5) / count)
			return _under_storey(top, _ground_for(r).sample_height(a.x, a.y))
		"wall":
			for p in r.pts:
				if _under_storey(_v(p), _ground_for(r).sample_height(p[0], p[1])):
					return true
	return false


## Whether something other than a floor holds it up at `p`, reaching up to
## `level`.
func _holds(p: Vector2, level := -INF) -> bool:
	for r in records:
		match r.kind:
			"pillar":
				if p.distance_to(_v(r.at)) < 0.6:
					return true
			"stairs", "wall":
				if _on_top(r, p) and _top(r) >= level - 0.45:
					return true
			"arch":
				if p.distance_to(_v(r.a)) < 0.6 or p.distance_to(_v(r.b)) < 0.6:
					return true
	return false


# --- doors and windows ---------------------------------------------------------

const DOOR_HALF := 0.45
const WINDOW_HALF := 0.3


## Open a door or a window in `wall` where `pos` meets it. It goes in only
## where it fits: clear of the ends, other holes and arches, and for a
## window, in a wall tall enough. Returns whether one was made.
func add_hole(wall: Dictionary, pos: Vector3, type: String, sill := 1.0) -> bool:
	var path := _path(wall)
	var length := RuinBuilder.path_length(path)
	var s: float = _project(path, Vector2(pos.x, pos.z))[0]
	var hw := DOOR_HALF if type == "door" else WINDOW_HALF
	if s < hw + 0.4 or s > length - hw - 0.4:
		return false
	if type == "window" and float(wall.height) < 1.75:
		return false
	for h in _holes(wall):
		# leave a pier of wall at least half a metre wide between round heads
		if absf(float(h.s) - s) < hw + float(h.hw) + 0.4 + 0.5:
			return false
	for a in records:
		if a.kind == "arch" and a.get("wall", -1) == wall.id:
			if s > float(a.s0) - hw - 0.55 and s < float(a.s1) + hw + 0.55:
				return false
	var at: Vector2 = RuinBuilder._along(path, s)[0]
	if not wall.has("holes"):
		wall.holes = []
	wall.holes.append({"type": type, "at": [at.x, at.y], "sill": sill})
	_rebuild(wall)
	return true


## The holes of a wall as the builder wants them: where along the wall, how
## wide, from what height and where its round head springs, and whether a
## sill goes in.
func _holes(wall: Dictionary) -> Array:
	var out := []
	var path := _path(wall)
	var height := float(wall.height)
	for h in wall.get("holes", []):
		var s: float = _project(path, _v(h.at))[0]
		if h.type == "door":
			# a round-headed doorway, as tall as the wall allows
			var spring := clampf(height - 0.75, 0.9, 1.45)
			out.append({"s": s, "hw": DOOR_HALF, "bottom": -0.3, "spring": spring, "sill": false})
		else:
			# the sill where it was asked for, as far as the wall allows
			var bottom := clampf(float(h.get("sill", 1.0)), 0.5, height - 1.1)
			out.append({"s": s, "hw": WINDOW_HALF, "bottom": bottom, "spring": bottom + 0.45, "sill": true})
	return out


# --- removing ----------------------------------------------------------------

## Take away ruins under a brush. Walls and floors lose only what is under it.
func remove_near(c: Vector2, radius: float) -> bool:
	var changed := false
	for r in records.duplicate():
		match r.kind:
			"wall":
				if _cut_wall(r, c, radius):
					changed = true
			"floor":
				var keep := []
				for cell in r.cells:
					var centre := (Vector2(cell[0], cell[1]) + Vector2(0.5, 0.5)) * CELL
					if centre.distance_to(c) > radius:
						keep.append(cell)
				if keep.size() != r.cells.size():
					changed = true
					r.cells = keep
					if keep.is_empty():
						_drop(r)
					else:
						_rebuild(r)
			_:
				var near := false
				for e in _ends(r):
					near = near or e.distance_to(c) <= radius
				if r.kind != "pillar":
					near = near or _segment_distance(c, _v(r.a), _v(r.b)) <= radius
				if near:
					changed = true
					_drop(r)
					if r.has("wall"):
						_rebuild(_record(r.wall))
	if changed:
		_reindex()
		var reach := radius + 1.0
		data.clear_occupied(c, reach)
		reclaim(c, reach + 2.0)
		props.reclaim(c, reach + 2.0)
		_rebuild_in(Rect2(c, Vector2.ZERO).grow(radius + 1.0))
	return changed


func _cut_wall(r: Dictionary, c: Vector2, radius: float) -> bool:
	var pieces := []
	var current := []
	var cut := false
	for p in r.pts:
		if _v(p).distance_to(c) <= radius:
			cut = true
			if current.size() >= 2:
				pieces.append(current)
			current = []
		else:
			current.append(p)
	if current.size() >= 2:
		pieces.append(current)
	if not cut:
		return false
	_drop(r)
	var arches := []
	for a in records:
		if a.kind == "arch" and a.get("wall", -1) == r.id:
			arches.append(a)
	var k := 0
	for piece in pieces:
		# a stub too short to stand as a wall goes too
		var stub := PackedVector2Array()
		for q in piece:
			stub.append(_v(q))
		if RuinBuilder.path_length(stub) < 0.8:
			continue
		var rec := {"kind": "wall", "pts": piece, "seed": int(r.seed) + 101 * (k + 1), "height": r.height}
		if r.has("base"):
			rec.base = r.base
		# doors and windows in this stretch stay with it
		var kept := []
		var stub_len := RuinBuilder.path_length(stub)
		for h in r.get("holes", []):
			var pr := _project(stub, _v(h.at))
			if pr[1] < 0.3 and pr[0] > 0.6 and pr[0] < stub_len - 0.6:
				kept.append(h)
		if not kept.is_empty():
			rec.holes = kept
		rec.id = _next_id
		_next_id += 1
		records.append(rec)
		k += 1
		# arches set in this stretch move over to it
		for a in arches:
			var host := _host_wall(_v(a.a), _v(a.b))
			if not host.is_empty() and host.wall.id == rec.id:
				a.wall = rec.id
				a.s0 = host.s0
				a.s1 = host.s1
		_spawn(rec)
	# arches whose wall is gone stand on their own
	for a in arches:
		if a.wall == r.id:
			a.erase("wall")
		_rebuild(a)
	return true


func _drop(r: Dictionary) -> void:
	revision += 1
	records.erase(r)
	var node: Node = _nodes.get(r.id)
	if node:
		node.queue_free()
	_nodes.erase(r.id)


# --- state -------------------------------------------------------------------

func snapshot() -> Array:
	return [records.duplicate(true), age]


func restore(state: Array) -> void:
	revision += 1
	for node in _nodes.values():
		node.queue_free()
	_nodes.clear()
	records = (state[0] as Array).duplicate(true)
	age = state[1]
	material.set_shader_parameter("age", age)
	age_changed.emit(age)
	_reindex()
	for r in records:
		_next_id = maxi(_next_id, int(r.id) + 1)
		_spawn(r)


## Rebuild the pieces standing on grid points `rect` (the ground moved).
func follow_ground(rect: Rect2i) -> void:
	var lo: Vector2 = data.grid_pos(rect.position.x, rect.position.y)
	var hi: Vector2 = data.grid_pos(rect.end.x, rect.end.y)
	_rebuild_in(Rect2(lo, hi - lo).grow(1.5))


func _rebuild_in(area: Rect2) -> void:
	for r in records:
		if area.intersects(_bounds(r)):
			_rebuild(r)


func _bounds(r: Dictionary) -> Rect2:
	var pts: Array = _ends(r)
	if r.kind == "wall":
		pts = Array(_path(r))
	elif r.kind == "floor":
		pts = []
		for c in r.cells:
			pts.append(Vector2(c[0], c[1]) * CELL)
			pts.append((Vector2(c[0], c[1]) + Vector2.ONE) * CELL)
	if pts.is_empty():
		return Rect2()
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box.grow(1.0)


func _spawn(r: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.material_override = material
	add_child(node)
	_nodes[r.id] = node
	_rebuild(r)


func _rebuild(r: Dictionary) -> void:
	if r.is_empty():
		return
	var node: MeshInstance3D = _nodes.get(r.id)
	if node == null:
		return
	revision += 1
	var seed: int = r.seed
	match r.kind:
		"wall":
			node.mesh = RuinBuilder.wall(_ground_for(r), _path(r), seed, r.height, age, _openings(r), _carries(r), _holes(r))
		"pillar":
			var ph := float(r.height)
			var carried := _storey_over(_v(r.at), _ground_for(r).sample_height(r.at[0], r.at[1]))
			if not is_nan(carried):
				ph = maxf(ph, carried - 0.3 - (_ground_for(r).sample_height(r.at[0], r.at[1]) - 0.1))
			node.mesh = RuinBuilder.pillar(_ground_for(r), _v(r.at), seed, ph, age, null, _carries(r))
		"arch":
			var host := _record(r.get("wall", -1))
			if host.is_empty():
				node.mesh = RuinBuilder.arch(_ground_for(r), _v(r.a), _v(r.b), seed, r.height, age)
			else:
				node.mesh = RuinBuilder.arch_in_wall(_ground_for(host), _path(host), r.s0, r.s1, seed, r.height, age)
		"stairs":
			node.mesh = RuinBuilder.stairs(_ground_for(r), _v(r.a), _v(r.b), seed, age, _carries(r), float(r.height))
		"floor":
			var below := _ground_below(float(r.level)) if r.raised else ground
			node.mesh = RuinBuilder.paving(below, r.cells, float(r.level), r.raised, seed, age, _holds)


## The doorways the arches set into this wall cut through it.
func _openings(wall: Dictionary) -> Array:
	var out := []
	for a in records:
		if a.kind == "arch" and a.get("wall", -1) == wall.id:
			var shape := RuinBuilder.opening_shape(a.s1 - a.s0, a.height)
			var radius: float = shape[1]
			var keep := RuinBuilder.arch_keep(RuinBuilder.arch_count(radius), a.seed, age, RuinBuilder.WALL_HOLD)
			out.append([(a.s0 + a.s1) * 0.5, radius, shape[0], keep])
	return out


# --- marking the ground --------------------------------------------------------

## Soil, moss and a little loose stone around the foot of a ruin, and no
## grass growing up through it.
func _mark(r: Dictionary) -> void:
	var foot := Color(0.12, 0.0, 0.4, 0.4)
	match r.kind:
		"wall":
			for p in _sampled(_path(r), 0.3):
				data.stamp_splat(p, 0.8, foot, 0.55)
		"pillar":
			data.stamp_splat(_v(r.at), 1.0, foot, 0.7)
		"arch":
			data.stamp_splat(_v(r.a), 1.0, foot, 0.7)
			data.stamp_splat(_v(r.b), 1.0, foot, 0.7)
			# a worn track through the arch
			for p in _sampled(PackedVector2Array([_v(r.a), _v(r.b)]), 0.3):
				data.stamp_splat(p, 0.6, Color(0.0, 0.15, 0.1, 0.6), 0.35)
		"stairs":
			for p in _sampled(PackedVector2Array([_v(r.a), _v(r.b)]), 0.3):
				data.stamp_splat(p, 1.0, foot, 0.5)
		"floor":
			if not r.raised:
				for c in r.cells:
					data.stamp_splat((Vector2(c[0], c[1]) + Vector2(0.5, 0.5)) * CELL, 0.5, Color(0.1, 0.1, 0.2, 0.5), 0.5)
	_claim(r)


func _claim(r: Dictionary) -> void:
	match r.kind:
		"wall":
			for p in _sampled(_path(r), 0.25):
				data.stamp_occupied(p, 0.4)
		"pillar":
			data.stamp_occupied(_v(r.at), 0.5)
		"arch":
			data.stamp_occupied(_v(r.a), 0.5)
			data.stamp_occupied(_v(r.b), 0.5)
		"stairs":
			for p in _sampled(PackedVector2Array([_v(r.a), _v(r.b)]), 0.3):
				data.stamp_occupied(p, 0.75)
		"floor":
			if not r.raised:
				for c in r.cells:
					data.stamp_occupied((Vector2(c[0], c[1]) + Vector2(0.5, 0.5)) * CELL, 0.4)


## Let pieces near `c` claim their ground again after it was cleared.
func reclaim(c: Vector2, reach: float) -> void:
	for r in records:
		if _bounds(r).grow(reach).has_point(c):
			_claim(r)


## Whether a ruin stands on this spot.
func covers(p: Vector2) -> bool:
	for r in records:
		match r.kind:
			"wall":
				var path := _path(r)
				for k in path.size() - 1:
					if _segment_distance(p, path[k], path[k + 1]) < 0.4:
						return true
			"pillar":
				if p.distance_to(_v(r.at)) < 0.5:
					return true
			"arch":
				if p.distance_to(_v(r.a)) < 0.5 or p.distance_to(_v(r.b)) < 0.5:
					return true
			"stairs":
				if _segment_distance(p, _v(r.a), _v(r.b)) < 0.7:
					return true
			"floor":
				if not r.raised and _on_floor_cell(r, p):
					return true
	return false


func _on_floor_cell(r: Dictionary, p: Vector2) -> bool:
	var key := cell_of(p)
	for c in r.cells:
		if key == Vector2i(c[0], c[1]):
			return true
	return false


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
	return a.lerp(b, t).distance_to(p)


static func _sampled(path: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for i in n:
			out.append(a.lerp(b, float(i) / n))
	if path.size() > 0:
		out.append(path[path.size() - 1])
	return out
