extends RefCounted
## The island as fields on a square grid. Everything visible is rebuilt from
## these: the coast from sdf, the surface from height, the ground materials
## from splat, and where plants may grow from occupied.
##
## Edits mark a dirty rectangle of grid points; IslandView rebuilds only the
## tiles it touches. The same fields are mirrored into `image` (one RGBA float
## texel per grid point) so shaders can read the terrain directly.

const SIZE := 32.0
const RES := 161
const CELL := SIZE / (RES - 1)
const TILE := 16                       # cells per tile side
const TILES := (RES - 1) / TILE
const ROLL_DEPTH := 0.32               # how far the grass rolls down at the rim
const ROLL_WIDTH := 0.8
const MIN_HEIGHT := -0.8              # keeps the ground above the cliff band
const MAX_HEIGHT := 6.0
const NO_WATER := -100.0
const POND_DEPTH := 0.5               # how deep the brush digs under the waterline
const WATERLINE := 0.16              # new water sits this far below the ground it fills
const BANK_RISE := 0.7               # how high the bank climbs toward the brush edge
const MAX_BANK := 0.2                # the most a bank is ever heaped up

var sdf := PackedFloat32Array()       # meters to the coast, positive on land
var height := PackedFloat32Array()    # ground height before the rim roll
var splat := PackedColorArray()       # r stone, g sand, b moss, a dirt; grass is what is left
var rocks := PackedFloat32Array()      # loose natural stones, painted on top of splat
var occupied := PackedFloat32Array()  # 1 where something stands and nothing grows
var water := PackedFloat32Array()     # 0..1, how much a point is under water
var wlevel := PackedFloat32Array()    # water surface height where water > 0
var carve := PackedFloat32Array()     # metres the underside is worn away from below
## Where roots lie on the ground and keep the grass away. Drawn from the
## root records (see root_layer.gd), so it is not part of the snapshot.
var root_mask := PackedFloat32Array()

## Grid points changed since the last rebuild. Empty when clean.
var dirty := Rect2i()
## The part of that where the island body (skirt and underside) changes too:
## the coast moved, or the ground right at the coast was sculpted.
var dirty_shape := Rect2i()

## r surface height, g sdf, b occupied, a grass weight
var image: Image

var _wobble := FastNoiseLite.new()


func _init() -> void:
	var n := RES * RES
	sdf.resize(n)
	height.resize(n)
	splat.resize(n)
	rocks.resize(n)
	occupied.resize(n)
	water.resize(n)
	wlevel.resize(n)
	carve.resize(n)
	root_mask.resize(n)
	splat.fill(Color(0, 0, 0, 0))
	rocks.fill(0.0)
	occupied.fill(0.0)
	water.fill(0.0)
	wlevel.fill(NO_WATER)
	carve.fill(0.0)
	root_mask.fill(0.0)
	image = Image.create_empty(RES, RES, false, Image.FORMAT_RGBAF)
	_wobble.seed = 99
	_wobble.frequency = 0.9


func index(i: int, j: int) -> int:
	return j * RES + i


func grid_pos(i: int, j: int) -> Vector2:
	return Vector2(-SIZE * 0.5 + i * CELL, -SIZE * 0.5 + j * CELL)


func grid_pos_k(k: int) -> Vector2:
	return grid_pos(k % RES, k / RES)


func full_rect() -> Rect2i:
	return Rect2i(0, 0, RES, RES)


func generate_default(seed: int) -> void:
	var edge := FastNoiseLite.new()
	edge.seed = seed
	edge.frequency = 0.6
	edge.fractal_octaves = 3
	var hills := FastNoiseLite.new()
	hills.seed = seed + 1
	hills.frequency = 0.07
	hills.fractal_octaves = 3
	var lobe := Vector2(4.4, 2.9)
	for j in RES:
		for i in RES:
			var k := index(i, j)
			var p := grid_pos(i, j)
			var ang := atan2(p.y, p.x)
			var radius := 6.4 * (1.0 + 0.13 * edge.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0))
			var d_main := radius - p.length()
			var d_lobe := 3.3 - p.distance_to(lobe)
			sdf[k] = minf(_smooth_max(d_main, d_lobe, 1.6), _border_limit(i, j))
			var inland := smoothstep(0.0, 4.0, d_main)
			var h := 0.2 + inland * (0.35 + 0.45 * hills.get_noise_2d(p.x, p.y))
			# the knoll the tree stands on
			h += 1.1 * exp(-p.distance_squared_to(Vector2(-2.4, -1.8)) / 7.0)
			height[k] = h
	dirty = full_rect()
	dirty_shape = full_rect()


# --- reading -----------------------------------------------------------------

## The rim roll: grass curls down toward the coast instead of ending in a
## hard edge. Applied on top of height, so it follows the coast when the
## island is reshaped.
static func roll(d: float) -> float:
	var rim := 1.0 - smoothstep(0.0, ROLL_WIDTH, d)
	return ROLL_DEPTH * rim * rim


func surface(k: int) -> float:
	return height[k] - roll(sdf[k])


func in_bounds(x: float, z: float) -> bool:
	return absf(x) < SIZE * 0.5 and absf(z) < SIZE * 0.5


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + SIZE * 0.5) / CELL
	var fz := (z + SIZE * 0.5) / CELL
	var i := clampi(int(floor(fx)), 0, RES - 2)
	var j := clampi(int(floor(fz)), 0, RES - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a := arr[index(i, j)]
	var b := arr[index(i + 1, j)]
	var c := arr[index(i, j + 1)]
	var d := arr[index(i + 1, j + 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func sample_sdf(x: float, z: float) -> float:
	return _bilinear(sdf, x, z)


## Ground surface height, rim roll included.
func sample_height(x: float, z: float) -> float:
	return _bilinear(height, x, z) - roll(_bilinear(sdf, x, z))


func sample_base_height(x: float, z: float) -> float:
	return _bilinear(height, x, z)


## Surface height as it was in an earlier copy of the height field.
func sample_height_in(heights: PackedFloat32Array, x: float, z: float) -> float:
	return _bilinear(heights, x, z) - roll(_bilinear(sdf, x, z))


func sample_base_height_in(heights: PackedFloat32Array, x: float, z: float) -> float:
	return _bilinear(heights, x, z)


func sample_occupied(x: float, z: float) -> float:
	return _bilinear(occupied, x, z)


func sample_water(x: float, z: float) -> float:
	return _bilinear(water, x, z)


## Water surface height near (x, z): the level of the wettest grid point
## around it, so dry neighbours do not drag it down.
func sample_wlevel(x: float, z: float) -> float:
	var i := clampi(int(round((x + SIZE * 0.5) / CELL)), 1, RES - 2)
	var j := clampi(int(round((z + SIZE * 0.5) / CELL)), 1, RES - 2)
	var best := -1.0
	var level := NO_WATER
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var k := index(i + di, j + dj)
			if water[k] > best:
				best = water[k]
				level = wlevel[k]
	return level


func sample_splat(x: float, z: float) -> Color:
	var fx := (x + SIZE * 0.5) / CELL
	var fz := (z + SIZE * 0.5) / CELL
	var i := clampi(int(floor(fx)), 0, RES - 2)
	var j := clampi(int(floor(fz)), 0, RES - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var top := splat[index(i, j)].lerp(splat[index(i + 1, j)], tx)
	var bottom := splat[index(i, j + 1)].lerp(splat[index(i + 1, j + 1)], tx)
	return top.lerp(bottom, tz)


func surface_normal(x: float, z: float) -> Vector3:
	var e := CELL * 0.5
	var hx := sample_height(x + e, z) - sample_height(x - e, z)
	var hz := sample_height(x, z + e) - sample_height(x, z - e)
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


## Horizontal direction pointing out to sea from (x, z).
func outward(x: float, z: float) -> Vector3:
	var e := CELL * 0.5
	var gx := sample_sdf(x + e, z) - sample_sdf(x - e, z)
	var gz := sample_sdf(x, z + e) - sample_sdf(x, z - e)
	return Vector3(-gx, 0.0, -gz).normalized()


# --- editing -----------------------------------------------------------------

## Pull the ground materials toward `target` inside a soft, wobbly disc.
func stamp_splat(center: Vector2, radius: float, target: Color, strength: float) -> void:
	_stamp(center, radius, func(k: int, w: float) -> void:
		splat[k] = splat[k].lerp(target, w * strength))


func clear_occupied(center: Vector2, radius: float) -> void:
	var r := _cell_range(center, radius)
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			if grid_pos(i, j).distance_to(center) <= radius:
				occupied[index(i, j)] = 0.0
	_mark(r)


func stamp_occupied(center: Vector2, radius: float) -> void:
	_stamp(center, radius, func(k: int, w: float) -> void:
		occupied[k] = maxf(occupied[k], w))


func edit_height(center: Vector2, radius: float, amount: float) -> void:
	var apply := func(k: int, w: float) -> void:
		height[k] = clampf(height[k] + amount * w, MIN_HEIGHT, MAX_HEIGHT)
	_stamp(center, radius, apply, true)


func edit_flatten(center: Vector2, radius: float, target: float, amount: float) -> void:
	var apply := func(k: int, w: float) -> void:
		height[k] = lerpf(height[k], target, clampf(amount * w, 0.0, 1.0))
	_stamp(center, radius, apply, true)


func edit_smooth(center: Vector2, radius: float, amount: float) -> void:
	var before := height.duplicate()
	var apply := func(k: int, w: float) -> void:
		var i := k % RES
		var j := k / RES
		if i == 0 or j == 0 or i == RES - 1 or j == RES - 1:
			return
		var avg := (before[k - 1] + before[k + 1] + before[k - RES] + before[k + RES]) * 0.25
		height[k] = lerpf(before[k], avg, clampf(amount * w, 0.0, 1.0))
	_stamp(center, radius, apply, true)


## Grow or carve the coastline with a slightly wobbly disc. The disc is
## merged into the distance field with max/min, so the field stays a usable
## distance to the coast and the underside deepens with the new land.
func edit_land(center: Vector2, radius: float, add: bool) -> void:
	var reach := radius + 1.5
	var r := _cell_range(center, reach)
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var k := index(i, j)
			var p := grid_pos(i, j)
			var circle := radius * (1.0 + 0.12 * _wobble.get_noise_2d(p.x * 0.7, p.y * 0.7)) - p.distance_to(center)
			if add:
				sdf[k] = minf(maxf(sdf[k], circle), _border_limit(i, j))
			else:
				sdf[k] = minf(sdf[k], -circle)
	_mark(r, true)



## Fill with water at `level`, digging a bowl under it; or, with add false,
## drain it and fill the hollow back up to the old waterline. Where new water
## meets lower ground the level follows the ground down, so a stroke dragged
## downhill becomes a stream.
func edit_water(center: Vector2, radius: float, level: float, amount: float, add: bool) -> void:
	var apply := func(k: int, w: float) -> void:
		var step := clampf(w * amount, 0.0, 1.0)
		if add:
			# new water takes the stroke's level, but never stands more than a
			# low bank's height above the ground it lands on: on falling ground
			# it follows the slope down instead of being walled in
			var cap := surface(k) - WATERLINE + MAX_BANK
			wlevel[k] = minf(level, cap) if water[k] < 0.02 else minf(wlevel[k], level)
			# rise toward the brush's own soft profile, never past it, so a pond
			# is a bowl and not a pit with straight walls
			water[k] = maxf(water[k], lerpf(water[k], w, clampf(amount, 0.0, 1.0)))
			var lv := wlevel[k]
			# The ground the brush wants: the bed under deep water, rising
			# through the waterline to a sloping bank at the brush's edge.
			var wanted := lv + WATERLINE + BANK_RISE * (1.0 - w) - (POND_DEPTH + WATERLINE) * smoothstep(0.0, 1.0, water[k])
			height[k] = maxf(minf(height[k], wanted + roll(sdf[k])), MIN_HEIGHT - 0.2)
			# where the ground at the edge lies lower than the water, heap up a
			# low bank so the water stays in
			if water[k] < 0.5 and surface(k) < lv + WATERLINE:
				var top := minf(lv + WATERLINE, surface(k) + MAX_BANK)
				height[k] = lerpf(height[k], top + roll(sdf[k]), step)
		elif water[k] > 0.0:
			var refill := wlevel[k] + WATERLINE + roll(sdf[k])
			height[k] = lerpf(height[k], maxf(height[k], refill), step)
			water[k] = maxf(0.0, water[k] - step)
			if water[k] <= 0.0:
				wlevel[k] = NO_WATER
	_stamp(center, radius, apply, true)
	if add:
		_relax_water(_cell_range(center, radius * 1.4).grow(1), 2)


## Even out the water surface: a stream then slopes smoothly from level to
## level instead of stepping. A pond, already flat, is left as it is.
func _relax_water(r: Rect2i, passes: int) -> void:
	r = r.intersection(Rect2i(1, 1, RES - 2, RES - 2))
	for n in passes:
		var before := wlevel.duplicate()
		for j in range(r.position.y, r.end.y):
			for i in range(r.position.x, r.end.x):
				var k := j * RES + i
				if water[k] <= 0.0:
					continue
				var sum := 0.0
				var count := 0
				for nk in [k - 1, k + 1, k - RES, k + RES]:
					if water[nk] > 0.0:
						sum += before[nk]
						count += 1
				if count > 0:
					wlevel[k] = lerpf(before[k], sum / count, 0.5)


## Paint ground materials: the splat toward `target`, loose stones toward
## `rocks_target`. Grass is whatever both leave over.
func paint(center: Vector2, radius: float, target: Color, rocks_target: float, amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	var apply := func(k: int, w: float) -> void:
		splat[k] = splat[k].lerp(target, w * a)
		rocks[k] = lerpf(rocks[k], rocks_target, w * a)
	_stamp(center, radius, apply)


func snapshot() -> Array:
	return [sdf.duplicate(), height.duplicate(), splat.duplicate(), occupied.duplicate(), water.duplicate(), wlevel.duplicate(), rocks.duplicate(), carve.duplicate()]


func restore(state: Array) -> void:
	sdf = state[0].duplicate()
	height = state[1].duplicate()
	splat = state[2].duplicate()
	occupied = state[3].duplicate()
	water = state[4].duplicate()
	wlevel = state[5].duplicate()
	rocks = state[6].duplicate()
	# islands saved before the underside could be worn away have no carve
	if state.size() > 7:
		carve = state[7].duplicate()
	else:
		carve.fill(0.0)
	dirty = full_rect()
	dirty_shape = full_rect()


func refresh_image(r: Rect2i) -> void:
	r = r.intersection(full_rect())
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var k := index(i, j)
			var s := splat[k]
			var grass := maxf(0.0, 1.0 - (s.r + s.g + s.b + s.a) - rocks[k]) * (1.0 - smoothstep(0.05, 0.3, water[k]))
			image.set_pixel(i, j, Color(surface(k), sdf[k], maxf(occupied[k], root_mask[k]), grass))


func _cell_range(center: Vector2, reach: float) -> Rect2i:
	var i0 := clampi(int((center.x - reach + SIZE * 0.5) / CELL), 0, RES - 1)
	var i1 := clampi(int((center.x + reach + SIZE * 0.5) / CELL) + 1, 0, RES - 1)
	var j0 := clampi(int((center.y - reach + SIZE * 0.5) / CELL), 0, RES - 1)
	var j1 := clampi(int((center.y + reach + SIZE * 0.5) / CELL) + 1, 0, RES - 1)
	return Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)


func _stamp(center: Vector2, radius: float, apply: Callable, shapes_coast := false) -> void:
	var r := _cell_range(center, radius * 1.4)
	var near_coast := false
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var p := grid_pos(i, j)
			var d := p.distance_to(center) * (1.0 + 0.35 * _wobble.get_noise_2d(p.x, p.y))
			var w := 1.0 - smoothstep(radius * 0.45, radius, d)
			if w > 0.0:
				var k := index(i, j)
				apply.call(k, w)
				near_coast = near_coast or absf(sdf[k]) < 0.6
	_mark(r, shapes_coast and near_coast)


## Wear the underside away from below (amount > 0), or build it back. It
## never goes higher than `cap(k)`, the full hang at that point, which leaves
## the underside level with the foot of the skirt: the light rock under the
## soil.
func edit_carve(center: Vector2, radius: float, amount: float, cap: Callable) -> void:
	var r := _cell_range(center, radius * 1.4)
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var p := grid_pos(i, j)
			var d := p.distance_to(center) * (1.0 + 0.35 * _wobble.get_noise_2d(p.x, p.y))
			var w := 1.0 - smoothstep(radius * 0.45, radius, d)
			if w > 0.0:
				var k := index(i, j)
				if sdf[k] > -1.0:
					carve[k] = clampf(carve[k] + w * amount, 0.0, cap.call(k))
	_mark(r.grow(1).intersection(full_rect()), true)


func sample_carve(x: float, z: float) -> float:
	return _bilinear(carve, x, z)


func _mark(r: Rect2i, shape: bool = false) -> void:
	dirty = r if not dirty.has_area() else dirty.merge(r)
	if shape:
		dirty_shape = r if not dirty_shape.has_area() else dirty_shape.merge(r)


## Land must stay clear of the grid edge so the coast is always closed.
func _border_limit(i: int, j: int) -> float:
	var cells := mini(mini(i, RES - 1 - i), mini(j, RES - 1 - j))
	return (cells - 3) * CELL


static func _smooth_max(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return lerpf(b, a, h) + k * h * (1.0 - h)
