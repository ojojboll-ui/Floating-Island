extends RefCounted
## Stones of every size, generated: boulders, pebbles and stepping stones
## are one shape with different settings.
##
## A stone is what is left of a ball when a few flat cuts take slices off it
## (the idea behind Rock Forge's "blocks sliced by cutting planes"): seen
## from the middle, the surface in each direction lies at the nearest of the
## cut planes. A soft minimum over the planes rounds their meeting edges, so
## the stone reads as hewn but worn, as in the Quaternius rocks. A flat cut
## underneath lets it sit on the ground.
##
## The style (see STYLE) sets the size, how much stones vary, how angular,
## flat and long they are, and the moss, texture and colour, which the
## shader (rock.gdshader) reads per stone.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const STYLE := {
	"size": 1.4,          # metres across
	"variation": 0.3,     # how much one stone differs in size from the next
	"angular": 0.5,       # 0 a worn pebble .. 1 a hewn block with sharp facets
	"flat": 0.25,         # 0 as tall as wide .. 1 a slab
	"long": 0.2,          # 0 round .. 1 twice as long as wide
	"moss": 0.5,
	"texture": 0.5,       # cracks and layers in the stone
	"tint": [0.5, 0.49, 0.47],
}

static var _icos := {}     # subdivisions -> [unit vertices, indices]
static var _meshes := {}   # style and variant -> ArrayMesh


static func style_of(base: Dictionary, s) -> Dictionary:
	var out := base.duplicate(true)
	if s is Dictionary:
		for k in s:
			out[k] = s[k]
	return out


## The stone for a style and a variant, one metre across, resting on y = 0.
## Shapes are cached: many pebbles share a handful of them.
static func mesh(style: Dictionary, variant: int, detail := 3) -> ArrayMesh:
	var shape := style.duplicate()
	for look in ["moss", "texture", "tint", "size", "variation"]:
		shape.erase(look)
	var key := "%s|%d|%d" % [str(shape), variant, detail]
	if _meshes.has(key):
		return _meshes[key]
	var m := _build(style, variant, detail)
	_meshes[key] = m
	return m


static func _build(style: Dictionary, seed: int, detail: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.1
	noise.fractal_octaves = 2
	var angular: float = style.angular
	# the cuts: more of them, and sharper where they meet, the more angular
	var planes: Array = []
	var count := int(round(lerpf(6.0, 16.0, angular)))
	for c in count:
		var n := Vector3(rng.randfn(), rng.randfn() * 0.8, rng.randfn()).normalized()
		planes.append([n, rng.randf_range(0.72, 1.0)])
	planes.append([Vector3.DOWN, 0.55])   # the flat underside
	# a slab is worn flat on top too, where feet and weather have smoothed it
	if float(style.flat) > 0.5:
		planes.append([Vector3.UP, lerpf(1.1, 0.55, (float(style.flat) - 0.5) * 2.0)])
	var soft := lerpf(0.14, 0.012, angular)
	var base: Array = _icosphere(detail)
	var verts: PackedVector3Array = (base[0] as PackedVector3Array).duplicate()
	var idx: PackedInt32Array = base[1]
	var stretch := Vector3(1.0 + float(style.long) * 0.9, lerpf(0.95, 0.2, float(style.flat)), 1.0)
	for k in verts.size():
		var dir := verts[k]
		# soft minimum of the distance to each cut along this direction
		var sum := 0.0
		for p in planes:
			var facing: float = maxf((p[0] as Vector3).dot(dir), 0.04)
			sum += exp(-(float(p[1]) / facing) / soft)
		var r := -soft * log(sum)
		r = minf(r, 1.25)
		r *= 1.0 + 0.07 * (1.0 - angular) * noise.get_noise_3dv(dir * 1.6)
		# knobs and dents all over, however hewn the stone
		r *= 1.0 + 0.035 * noise.get_noise_3dv(dir * 4.5 + Vector3(9.0, 0.0, 0.0))
		verts[k] = dir * r * stretch
	# one metre across, resting on y = 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var across := maxf(hi.x - lo.x, hi.z - lo.z)
	var mid := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	for k in verts.size():
		verts[k] = (verts[k] - mid) / across
	var nrm := MeshUtil.normals_by_position(verts, idx)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(Color.WHITE)
	var out := ArrayMesh.new()
	MeshUtil.add_surface(out, verts, nrm, uvs, colors, idx)
	return out


## A sphere of near-even triangles: an icosahedron split `n` times.
static func _icosphere(n: int) -> Array:
	if _icos.has(n):
		return _icos[n]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for k in verts.size():
		verts[k] = verts[k].normalized()
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _split in n:
		var mids := {}
		var next := []
		for f in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mids[key] = verts.size() - 1
				m.append(mids[key])
			next.append([f[0], m[0], m[2]])
			next.append([f[1], m[1], m[0]])
			next.append([f[2], m[2], m[1]])
			next.append([m[0], m[1], m[2]])
		faces = next
	var idx := PackedInt32Array()
	for f in faces:
		# wound for Godot's front faces
		idx.append_array([f[0], f[2], f[1]])
	_icos[n] = [verts, idx]
	return _icos[n]
