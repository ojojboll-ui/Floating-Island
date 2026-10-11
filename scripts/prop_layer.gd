extends Node3D
## Everything placed on the island. Each thing is a small record (kind, spot,
## turn, size, variant, tint) plus the node built from it. Records are what
## undo snapshots and, later, saving keep; nodes are rebuilt from them.
##
## Placing something marks the ground around it (moss, soil, where grass
## gives way). Things follow the ground when it is sculpted, lilies ride the
## water, and anything whose land or water goes away is hidden until it
## comes back.

const Catalog := preload("res://scripts/prop_catalog.gd")
const IslandData := preload("res://scripts/island_data.gd")

var data
var ruins   # the ruin layer, which shares the ground's "occupied" claims
var records: Array = []
var _nodes := {}   # id -> Node3D
var _next_id := 1
## Counts every change to the stones (boulders, pebbles, stepping stones),
## so the roots can tell when to crawl over them anew.
var revision := 0
## The style each generated kind is drawn with now (the panel's dials).
var styles := {}
## The things placed by the last stroke, which the dials restyle too.
var last_stroke: Array = []
const STONES := ["stenblock", "smasten", "trampsten"]
## Kinds grown by the tree builder: they bend round stones and walls, and
## two of one kind planted on top of each other grow into one.
const WOODY := ["lovtrad", "gran", "krokigt", "torrtrad", "sagotrad", "buske", "blombuske"]
var roots   # the root layer, whose height raster of stones and ruins trees grow round
var _woody_rev := 0
## Things that rest on whatever is under them: a wall, a stone, the ground.
const RESTING := ["fackla", "ljus", "lykta", "ryggsack", "koffert", "gryta", "flaskor", "bocker", "svampkorg", "tunna", "hacka", "yxa"]
var _flames: Array = []   # [light, base energy]
var _env_seen := ""


func setup(island_data) -> void:
	data = island_data
	Catalog.context = self


## Size range midpoint, so marks scale with how big this one turned out.
static func _ratio(rec: Dictionary) -> float:
	var k: Dictionary = Catalog.KINDS[rec.kind]
	if k.has("style"):
		return float(rec.size) / float(k.style.size)
	var h: Array = Catalog.KINDS[rec.kind].height
	return float(rec.size) / ((h[0] + h[1]) * 0.5)


## spread scales how far apart things of one layer must stand: 1 is the
## kind's own spacing, more is sparser.
## merge: a single click, which may plant a tree on top of one of its kind.
func can_place(kind: String, x: float, z: float, spread := 1.0, merge := false) -> bool:
	var c := _check(kind, x, z, spread, merge)
	return c[0] and (c[1] as Array).is_empty()


## What placing `kind` at (x, z) would mean: 0 it fits, 1 it fits once the
## things in its way are taken away, 2 it cannot go there at all (water,
## a wall, off the island).
func place_check(kind: String, x: float, z: float, spread := 1.0, merge := false) -> int:
	var c := _check(kind, x, z, spread, merge)
	if not c[0]:
		return 2
	return 0 if (c[1] as Array).is_empty() else 1


## Put `kind` down at (x, z), painting over whatever is in its way: those
## things are taken away first. Things the same stroke put down, and things
## of the same kind when scattering, are never painted over, so a stroke
## does not eat its own work. Returns the new record, or {}.
func place_over(kind: String, x: float, z: float, rng: RandomNumberGenerator, spread := 1.0, merge := false,
		scatter := false, variant := -1, rot := NAN, jit := NAN) -> Dictionary:
	var c := _check(kind, x, z, spread, merge)
	if not c[0]:
		return {}
	var gone: Array = []
	for b in c[1]:
		var r: Dictionary = b[0]
		if r.id in last_stroke or (scatter and r.kind == kind):
			return {}
		# a brush scattering small things never takes away something bigger
		# (pebbles round a boulder keep the boulder); a click does
		var bigger: bool = Catalog.KINDS[r.kind].layer == "big" and Catalog.KINDS[kind].layer != "big"
		if scatter and bigger:
			return {}
		gone.append(r)
	if not gone.is_empty():
		_remove(gone, Vector2(x, z), 1.5)
	return add(kind, x, z, rng, -1.0, variant, rot, jit)


## [whether the ground allows it, the things standing in its way]
func _check(kind: String, x: float, z: float, spread := 1.0, merge := false) -> Array:
	var k: Dictionary = Catalog.KINDS[kind]
	var blockers: Array = []
	if not data.in_bounds(x, z):
		return [false, blockers]
	var d: float = data.sample_sdf(x, z)
	var w: float = data.sample_water(x, z)
	match k.where:
		"land":
			if d < 0.3 or w > 0.12:
				return [false, blockers]
		"shore":
			if d < 0.1 or w < 0.04 or w > 0.75:
				return [false, blockers]
		"water":
			if w < 0.6 or data.sample_wlevel(x, z) - data.sample_height(x, z) < 0.1:
				return [false, blockers]
		_:
			if d < 0.2:
				return [false, blockers]
	# nothing grows out of a wall or a stair
	if k.where != "water" and data.sample_occupied(x, z) > 0.6 and _ruin_under(x, z):
		return [false, blockers]
	var here := Vector2(x, z)
	for r in records:
		var other: Dictionary = Catalog.KINDS[r.kind]
		var dist := here.distance_to(Vector2(r.x, r.z))
		if kind == "gryta" and r.kind == "eldstad":
			continue
		if other.layer == k.layer:
			var need := (float(k.spacing) + float(other.spacing)) * 0.5 * spread
			if merge and r.kind == kind and kind in WOODY:
				# on top of one of its own kind: the two grow into one
				need = 0.3
			elif merge and kind in STONES and r.kind in STONES:
				# a stone set on a stone: they stack into one rock
				need = 0.12
			elif kind in WOODY and r.kind in STONES:
				# right beside a boulder: the tree will bend round it
				need = float(r.size) * 0.5 + 0.2
			elif kind in STONES and r.kind in WOODY:
				need = float(style_for(kind).size) * 0.5 + 0.2
			if dist < need:
				blockers.append([r, dist / maxf(need, 0.01)])
		elif merge and kind in STONES and r.kind in STONES:
			if dist < 0.08:
				blockers.append([r, dist / 0.08])
		elif other.layer == "big" and k.layer == "small":
			# small things may nestle against a boulder, right up to its side
			var keep: float = float(r.size) * 0.42 + 0.04 if r.kind in STONES else float(other.occupied) * _ratio(r) + 0.15
			if dist < keep:
				blockers.append([r, dist / maxf(keep, 0.01)])
		elif k.layer == "big" and other.layer == "small":
			if dist < float(k.occupied) + 0.1:
				blockers.append([r, dist / (float(k.occupied) + 0.1)])
	return [true, blockers]


func _ruin_under(x: float, z: float) -> bool:
	return ruins != null and ruins.covers(Vector2(x, z))


## rot and jit, when given, are the ghost's, so what lands is what was shown.
func add(kind: String, x: float, z: float, rng: RandomNumberGenerator, size := -1.0, variant := -1, rot := NAN, jit := NAN) -> Dictionary:
	var k: Dictionary = Catalog.KINDS[kind]
	var stones_moved := false
	var rec := {
		"id": _next_id, "kind": kind, "x": x, "z": z,
		"rot": rng.randf() * TAU if is_nan(rot) else rot,
		"size": size if size > 0.0 else (rng.randf_range(k.height[0], k.height[1]) if k.has("height") else 1.0),
		"variant": variant if variant >= 0 else rng.randi() % Catalog.variants(kind),
		"hue": rng.randf(),
	}
	_next_id += 1
	if k.has("style"):
		rec.style = style_for(kind).duplicate(true)
		rec.jit = rng.randf_range(-1.0, 1.0) if is_nan(jit) else jit
		if size <= 0.0:
			rec.size = _styled_size(rec)
	if kind in STONES:
		rec.lift = stone_lift(x, z)
		stones_moved = true
	elif kind in RESTING:
		rec.lift = rest_lift(x, z)
	if kind == "gryta":
		var fire = fire_near(x, z)
		if fire != null:
			# a pot set down by a fire hangs over it
			rec.x = fire.x
			rec.z = fire.z
			rec.over_fire = true
			rec.lift = 0.0
	records.append(rec)
	last_stroke.append(rec.id)
	if kind in Catalog.TREES:
		_shade_changed(Vector2(x, z))
	if kind in WOODY:
		_woody_rev += 1
	_mark(rec)
	_spawn(rec)
	if stones_moved:
		# the stones it now touches learn about it too
		for r in records:
			if r.kind in STONES and r.id != rec.id and Vector2(r.x, r.z).distance_to(Vector2(x, z)) < 4.0:
				_place(r)
	return rec


## Remove things of `kind` (or of any kind, if empty) within `radius`.
## The two stones nearest `rec` that overlap it, as centre and radius
## (vec4, w 0 for none), for the shader's seams.
func _stack_mates(rec: Dictionary) -> Array:
	var found: Array = []
	var me := _stone_sphere(rec)
	for r in records:
		if r.id == rec.id or not r.kind in STONES or not _nodes.has(r.id):
			continue
		var other := _stone_sphere(r)
		var gap := Vector3(me.x, me.y, me.z).distance_to(Vector3(other.x, other.y, other.z)) - me.w - other.w
		if gap < 0.05:
			found.append([gap, other])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = [Vector4.ZERO, Vector4.ZERO]
	for k in mini(2, found.size()):
		out[k] = found[k][1]
	return out


## A stone as a ball: centre and radius, in the world.
func _stone_sphere(rec: Dictionary) -> Vector4:
	var node: Node3D = _nodes.get(rec.id)
	var tall: float = node.get_meta("tall", float(rec.size)) if node else float(rec.size) * 0.6
	var base := node.global_position if node else Vector3(rec.x, ground_at(rec.x, rec.z), rec.z)
	var r := (float(rec.size) * 0.5 + tall * 0.5) * 0.5
	return Vector4(base.x, base.y + tall * 0.5, base.z, r)


## How high a small thing set down at (x, z) rests: on top of a wall, a
## pillar or a stone if it is on one, else on the ground.
func rest_lift(x: float, z: float) -> float:
	var g := ground_at(x, z)
	var top := obstacle_top(x, z)
	return maxf(0.0, top - g) if top > g + 0.05 else 0.0


## How high something of `kind` rests at (x, z).
func lift_for(kind: String, x: float, z: float) -> float:
	if kind in STONES:
		return stone_lift(x, z)
	if kind in RESTING:
		return rest_lift(x, z)
	return 0.0


## The fire pit within reach of (x, z), for a pot to hang over; or null.
func fire_near(x: float, z: float) -> Variant:
	for r in records:
		if r.kind == "eldstad" and Vector2(r.x, r.z).distance_to(Vector2(x, z)) < 1.2:
			return r
	return null


## How high a stone set down at (x, z) rests: on the ground, or, set on
## another stone (or a wall), sunk halfway into its top so the two read as
## one rock.
func stone_lift(x: float, z: float) -> float:
	var g := ground_at(x, z)
	var top := obstacle_top(x, z)
	if top < g + 0.08:
		return 0.0
	return (top - g) * 0.55


func ground_at(x: float, z: float) -> float:
	return data.sample_height(x, z)


## The top of a stone, wall or pillar at (x, z), or -INF.
func obstacle_top(x: float, z: float) -> float:
	if roots == null:
		return -INF
	roots.ensure_raster()
	return roots.ruin_top(x, z)


## For a woody plant: [which way to lean, where its foot moves], in world
## space, from the others of its kind standing close enough to merge with.
func merge_with(rec: Dictionary) -> Array:
	var lean := Vector3.ZERO
	var base := Vector3.ZERO
	var reach := float(Catalog.KINDS[rec.kind].spacing) * 0.9
	var nearest := INF
	for r in records:
		if r.id == rec.id or r.kind != rec.kind:
			continue
		var off := Vector3(float(rec.x) - float(r.x), 0.0, float(rec.z) - float(r.z))
		var d := off.length()
		if d >= reach:
			continue
		if d < 0.001:
			off = Vector3(1.0, 0.0, 0.0)
			d = 0.001
		lean += off / d * (1.0 - d / reach)
		if d < nearest and d < 1.0:
			nearest = d
			# very close: the two feet meet, a forked trunk
			base = -off / d * (1.0 - d) * 0.45
	return [lean.limit_length(1.0), base]


## What a woody plant's shape depends on round it: the stones and walls
## within reach, and its own kind standing close.
func _env_key(rec: Dictionary) -> String:
	var key := ""
	for j in range(-3, 4):
		for i in range(-3, 4):
			var h := obstacle_top(float(rec.x) + i * 0.8, float(rec.z) + j * 0.8)
			key += "%.1f," % h if h > -1e9 else "-,"
	var m := merge_with(rec)
	return key + str((m[0] as Vector3).snapped(Vector3.ONE * 0.05)) + str((m[1] as Vector3).snapped(Vector3.ONE * 0.05))


## Something changed round the woody plants: rebuild those it touches.
func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in _flames:
		var l := f[0] as OmniLight3D
		if is_instance_valid(l):
			var ph: float = f[2]
			l.light_energy = float(f[1]) * (0.82 + 0.12 * sin(t * 11.0 + ph) + 0.08 * sin(t * 23.0 + ph * 2.0))
	if roots == null:
		return
	roots.ensure_raster()
	var seen := "%d/%d/%d" % [roots._raster_rev, roots._stones_rev, _woody_rev]
	if seen == _env_seen:
		return
	_env_seen = seen
	for rec in records:
		if rec.kind in WOODY and _nodes.has(rec.id) and _env_key(rec) != rec.get("_env", ""):
			_respawn(rec)


func _respawn(rec: Dictionary) -> void:
	var node: Node = _nodes.get(rec.id)
	if node:
		node.queue_free()
	_nodes.erase(rec.id)
	_spawn(rec)


## The style a generated kind is drawn with now.
func style_for(kind: String) -> Dictionary:
	if not styles.has(kind):
		styles[kind] = (Catalog.KINDS[kind].style as Dictionary).duplicate(true)
	return styles[kind]


func _styled_size(rec: Dictionary) -> float:
	var st: Dictionary = rec.style
	return maxf(0.02, float(st.size) * (1.0 + float(st.variation) * 0.6 * float(rec.get("jit", 0.0))))


## A stroke begins: what it places is what the dials restyle.
func begin_stroke() -> void:
	last_stroke = []


## A dial moved: the kind's style, and the things the last stroke placed.
func set_style(kind: String, key: String, value) -> void:
	style_for(kind)[key] = value
	for rec in records:
		if rec.kind == kind and rec.id in last_stroke:
			rec.style = style_for(kind).duplicate(true)
			rec.size = _styled_size(rec)
			var node: Node = _nodes.get(rec.id)
			if node:
				node.queue_free()
			_nodes.erase(rec.id)
			_spawn(rec)
	if kind in STONES:
		revision += 1
	if kind in Catalog.TREES:
		for rec in stroke_records(kind):
			_shade_changed(Vector2(rec.x, rec.z))


## Things placed by the last stroke of `kind`.
func stroke_records(kind: String) -> Array:
	return records.filter(func(r): return r.kind == kind and r.id in last_stroke)


func records_near(kind: String, here: Vector2, reach: float) -> Array:
	return records.filter(func(r): return r.kind == kind and here.distance_to(Vector2(r.x, r.z)) <= reach)


## A tree came or went: the stones near it take on more or less moss.
func _shade_changed(here: Vector2) -> void:
	for r in records:
		if r.kind in STONES and here.distance_to(Vector2(r.x, r.z)) < 4.0:
			_place(r)


## How much a stone's moss grows from where it lies: by water, in a tree's shade.
func _damp(rec: Dictionary) -> float:
	var x: float = rec.x
	var z: float = rec.z
	var wet := 0.0
	for o in [Vector2.ZERO, Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
		wet = maxf(wet, data.sample_water(x + o.x, z + o.y))
	var shade := 0.0
	for r in records:
		if r.kind in Catalog.TREES:
			var d := Vector2(x, z).distance_to(Vector2(r.x, r.z))
			shade = maxf(shade, 1.0 - smoothstep(1.5, 4.0, d))
	return clampf(wet + shade * 0.6, 0.0, 1.0)


func remove_near(x: float, z: float, radius: float, kind := "") -> int:
	var here := Vector2(x, z)
	var gone := []
	for r in records:
		if (kind == "" or r.kind == kind) and here.distance_to(Vector2(r.x, r.z)) <= radius:
			gone.append(r)
	if gone.is_empty():
		return 0
	_remove(gone, here, radius)
	return gone.size()


## Take `gone` away, and let the ground round `here` grow back.
func _remove(gone: Array, here: Vector2, radius: float) -> void:
	var trees_gone := false
	for r in gone:
		if r.kind in STONES:
			revision += 1
		trees_gone = trees_gone or r.kind in Catalog.TREES
		if r.kind in WOODY:
			_woody_rev += 1
		records.erase(r)
		var node: Node = _nodes.get(r.id)
		if node:
			node.queue_free()
		_nodes.erase(r.id)
	# grass may grow back where they stood: clear the area and let everything
	# still standing claim its own ground again
	var reach := radius + 1.5
	if trees_gone:
		_shade_changed(here)
	data.clear_occupied(here, reach)
	reclaim(here, reach)
	if ruins:
		ruins.reclaim(here, reach)


## Let things near `here` claim their ground again after it was cleared.
func reclaim(here: Vector2, reach: float) -> void:
	for r in records:
		if here.distance_to(Vector2(r.x, r.z)) <= reach + 1.5:
			_claim(r)


## The stones' meshes as they lie, each with its place.
func stone_meshes() -> Array:
	var out: Array = []
	for r in records:
		if not r.kind in STONES:
			continue
		var node: Node3D = _nodes.get(r.id)
		if node == null or not node.visible:
			continue
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh:
				out.append([(mi as MeshInstance3D).mesh, (mi as MeshInstance3D).global_transform])
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			out.append([(node as MeshInstance3D).mesh, node.global_transform])
	return out


func snapshot() -> Array:
	return records.duplicate(true)


func restore(state: Array) -> void:
	revision += 1
	_woody_rev += 1
	for node in _nodes.values():
		node.queue_free()
	_nodes.clear()
	records = state.duplicate(true)
	for r in records:
		_next_id = maxi(_next_id, int(r.id) + 1)
		_spawn(r)


## Set every thing's height from the ground (or water) under it.
func follow_ground() -> void:
	for r in records:
		_place(r)


func _spawn(rec: Dictionary) -> void:
	_flames = _flames.filter(func(f): return is_instance_valid(f[0]))
	if rec.kind in WOODY:
		rec["_env"] = _env_key(rec)
	if rec.kind in STONES:
		revision += 1
	var node := Catalog.build(rec)
	add_child(node)
	_nodes[rec.id] = node
	_place(rec)
	for l in node.find_children("*", "OmniLight3D", true, false):
		if l.has_meta("flicker"):
			_flames.append([l, l.get_meta("flicker"), randf() * TAU])


func _place(rec: Dictionary) -> void:
	var node: Node3D = _nodes.get(rec.id)
	if node == null:
		return
	var k: Dictionary = Catalog.KINDS[rec.kind]
	var x: float = rec.x
	var z: float = rec.z
	var gy: float = data.sample_height(x, z)
	if k.where == "water":
		var w: float = data.sample_water(x, z)
		node.position = Vector3(x, data.sample_wlevel(x, z) + 0.004, z)
		node.visible = w > 0.4
	else:
		var tall: float = node.get_meta("tall", float(rec.size))
		var at := Vector3(x, gy - float(k.sink) * tall + float(rec.get("lift", 0.0)), z)
		if rec.kind in STONES:
			(node as GeometryInstance3D).set_instance_shader_parameter("moss_boost", _damp(rec))
			var mates := _stack_mates(rec)
			(node as GeometryInstance3D).set_instance_shader_parameter("touch_a", mates[0])
			(node as GeometryInstance3D).set_instance_shader_parameter("touch_b", mates[1])
		if rec.kind in STONES and not node.position.is_equal_approx(at):
			revision += 1
		node.position = at
		if rec.kind == "filt":
			# a blanket lies along the slope
			var n: Vector3 = data.surface_normal(x, z)
			var right := n.cross(Vector3.FORWARD).normalized()
			node.basis = Basis(right, n, right.cross(n)).orthonormalized() * Basis(Vector3.UP, float(rec.rot)) * Basis().scaled(Vector3.ONE * float(rec.size))
		node.visible = data.sample_sdf(x, z) > 0.15
	(node.get_meta("shaded") as GeometryInstance3D).set_instance_shader_parameter("ground_y", gy)


func _mark(rec: Dictionary) -> void:
	var k: Dictionary = Catalog.KINDS[rec.kind]
	var at := Vector2(rec.x, rec.z)
	if k.has("mark"):
		var m: Array = k.mark
		data.stamp_splat(at, float(m[1]) * _ratio(rec), m[0], 0.85)
	_claim(rec)


func _claim(rec: Dictionary) -> void:
	var occ: float = Catalog.KINDS[rec.kind].get("occupied", 0.0)
	if occ > 0.0:
		data.stamp_occupied(Vector2(rec.x, rec.z), occ * _ratio(rec))
