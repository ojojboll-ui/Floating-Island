extends RefCounted
## Roots grown by space colonization (Runions, Lane and Prusinkiewicz,
## "Modeling Trees with a Space Colonization Algorithm", 2007). A cloud of
## attraction points is scattered where the roots should go; each point
## pulls on the root node nearest to it, a node pulled by any points grows a
## new node toward their average direction, and a point a root reaches is
## used up. Where points pull one node from different sides it forks.
##
## Roots started on the ground crawl: the cloud lies flat on the ground
## around them and every node is laid on the surface, half sunk in, over
## grass, stone or paving alike. Where a crawling root runs off the coast it
## tips over the edge and hangs; where it meets a wall or a pillar it climbs
## the face, crosses the top and comes down the far side. Roots started on the underside or a cliff
## hang from the first: the cloud is a curtain below them.
##
## Four rules shape the forks, for a tidier, stylized branching: at most
## `max_kids` branches leave any one node; two forks along a root are at
## least `fork_gap` apart; a new branch leaves its parent at `fork_angle`;
## and a root splits at most `fork_depth` times, generation after
## generation. A root's own course may bend at most CONTINUE_ANGLE a step.
##
## Thickness follows the pipe model: a root is as thick as the roots it
## feeds together (r^PIPE adds up). The style dictionary (see STYLE) sets
## length, width, thickness, how much it branches, how it curls, how heavily
## it hangs, and its colour and bark.
##
## Vertex colour red is how far along the root a point is (0 at its start,
## 1 at the longest tip) for the sway; green is 1 where the root hangs free.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const STEP := 0.2           # metres a root grows per round
const INFLUENCE := 1.6      # how far an attraction point reaches
const KILL := 0.3           # a point this close to a root is used up
const ROUNDS := 140
const PIPE := 2.0           # lower is thicker at the base
const NEAR_CELL := 0.3      # cell of the grid that keeps nodes from piling up
const CONTINUE_ANGLE := deg_to_rad(40.0)

## The default style: chunky, smooth and few-branched, for the stylized look.
const STYLE := {
	"size": 1.0,            # scales the whole root system
	"length": 2.5,          # metres
	"spread": 1.1,          # metres the roots fan out
	"thickness": 0.8,       # times the base radius
	"branching": 0.35,      # how densely the attraction points lie: 0 sparse .. 1 dense
	"max_kids": 2,          # branches per fork
	"fork_gap": 0.5,        # metres between forks along a root
	"fork_angle": 40.0,     # degrees a branch leaves its parent at
	"fork_depth": 4,        # how many times a root may split, generation after generation
	"curl": 0.3,            # 0 straight .. 1 snaking
	"climb": 0.5,           # 0 roots go round walls and stones .. 1 they climb over them
	"hang": 0.6,            # 0 reach out sideways .. 1 straight down
	"bark": 0.6,            # 0 smooth painted colour .. 1 full bark texture
	"tint": [0.45, 0.3, 0.2],
}


static func style_of(s) -> Dictionary:
	var out := STYLE.duplicate(true)
	if s is Dictionary:
		for k in s:
			out[k] = s[k]
	return out


## anchors: where roots start, each [position, outward, crawls]. `inside`
## answers whether a point is inside the island; `ground` gives the surface
## height at (x, z), or NAN off the island.
static func build(anchors: Array, style: Dictionary, seed: int, inside: Callable, ground: Callable, bare := Callable()) -> ArrayMesh:
	return to_mesh(grow(anchors, style, seed, inside, ground, bare))


static func to_mesh(m: Dictionary) -> ArrayMesh:
	if m.is_empty() or m.i.is_empty():
		return null
	var out := ArrayMesh.new()
	MeshUtil.add_surface(out, m.v, m.n, m.uv, m.c, m.i)
	return out


## The roots as mesh arrays. Touches nothing but its arguments and reads the
## island, so it can run on a worker thread while the brush is drawing.
## `bare` gives the height of the bare ground, without ruins or stones, so
## the Klättra dial can find their tops.
static func grow(anchors: Array, style: Dictionary, seed: int, inside: Callable, ground: Callable, bare := Callable()) -> Dictionary:
	if anchors.is_empty():
		return {}
	var st := style_of(style)
	# Storlek scales the whole root system: every distance in it, so the
	# shape stays the same, only bigger or smaller
	var sc: float = st.size
	var step := STEP * sc
	var influence := INFLUENCE * sc
	var kill := KILL * sc
	var near_cell := maxf(NEAR_CELL * sc, step * 0.5)
	var length: float = st.length * sc
	var spread: float = st.spread * sc
	var hang: float = st.hang
	var curl: float = st.curl
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# the attraction points
	var attract := PackedVector3Array()
	var agrid := {}
	var density := lerpf(6.0, 34.0, st.branching)
	for a in anchors:
		var at: Vector3 = a[0]
		var out: Vector3 = a[1]
		var crawls: bool = a[2]
		var count := int(clampf(density * length * (0.6 + spread * 0.3), 8.0, 320.0))
		for c in count:
			var q: Vector3
			if crawls:
				# flat on the ground around the start, reaching `length`; any
				# off the coast hang below the rim so roots tip over the edge
				var r := length * sqrt(rng.randf_range(0.04, 1.0))
				var ang := rng.randf() * TAU
				q = at + Vector3(cos(ang) * r, 0.0, sin(ang) * r) * (spread / (1.4 * sc) * 0.5 + 0.5)
				var h: float = ground.call(q.x, q.z)
				if is_nan(h):
					# off the coast: just past the edge and below it, so roots
					# fall over the edge rather than reach out into the air
					var lo := 0.0
					var hi := 1.0
					for _halving in 7:
						var m := (lo + hi) * 0.5
						var p := at.lerp(q, m)
						if is_nan(ground.call(p.x, p.z)):
							hi = m
						else:
							lo = m
					var flat := Vector3(q.x - at.x, 0.0, q.z - at.z).normalized()
					q = at.lerp(q, hi) + flat * rng.randf_range(0.1, 0.5)
					q.y = at.y - (0.4 + rng.randf()) * length * maxf(hang, 0.15)
				else:
					q.y = h
			else:
				# a curtain below the start, wider toward the bottom, leaning
				# out from the cliff; lighter roots reach out more than down
				var depth := length * pow(rng.randf(), 0.75) * lerpf(0.35, 1.0, hang)
				var widen := spread * (0.25 + 0.75 * depth / length) * lerpf(1.8, 1.0, hang)
				var r := widen * sqrt(rng.randf())
				var ang := rng.randf() * TAU
				q = at + Vector3(cos(ang) * r, -depth, sin(ang) * r) + out * (0.3 + depth * 0.25)
				if inside.call(q):
					continue
			var key := _cell(q, influence)
			if not agrid.has(key):
				agrid[key] = PackedInt32Array()
			agrid[key].append(attract.size())
			attract.append(q)
	# Klättra: more points on top of the walls, pillars and stones in reach,
	# so roots that would go round them are drawn up and over
	var climb: float = st.climb
	if climb > 0.0 and bare.is_valid():
		for a in anchors:
			if not a[2]:
				continue
			var at: Vector3 = a[0]
			var tries := int(clampf(density * length * 0.8, 8.0, 240.0) * climb)
			for c in tries:
				var r := length * sqrt(rng.randf_range(0.04, 1.0))
				var ang := rng.randf() * TAU
				var q := at + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
				var g: float = ground.call(q.x, q.z)
				var b0: float = bare.call(q.x, q.z)
				if is_nan(g) or is_nan(b0) or g - b0 < 0.3:
					continue
				q.y = g
				var key := _cell(q, influence)
				if not agrid.has(key):
					agrid[key] = PackedInt32Array()
				agrid[key].append(attract.size())
				attract.append(q)
	var alive := PackedByteArray()
	alive.resize(attract.size())
	alive.fill(1)
	# each point remembers the node nearest to it, and is only compared with
	# the nodes grown since
	var closest := PackedInt32Array()
	closest.resize(attract.size())
	closest.fill(-1)
	var closest_d := PackedFloat32Array()
	closest_d.resize(attract.size())
	closest_d.fill(influence)

	# the nodes: position, parent, path length from the start, and whether
	# the node lies on the ground
	var pos := PackedVector3Array()
	var parent := PackedInt32Array()
	var along := PackedFloat32Array()
	var lies := PackedByteArray()
	var grid := {}
	var fresh := PackedInt32Array()
	# for the fork rules: children so far, the first child, the generation
	var kidc := PackedInt32Array()
	var first_kid := PackedInt32Array()
	var gen := PackedInt32Array()
	var climbs := PackedByteArray()   # nodes on a wall or stone face
	# a root that has taken to a wall keeps going the way it climbs, over the
	# top and down the far side, pulled or not: node -> [direction, steps left]
	var momentum := {}
	var max_kids: int = int(st.max_kids)
	var fork_gap: float = st.fork_gap
	var fork_angle: float = deg_to_rad(st.fork_angle)
	var fork_depth: int = int(st.fork_depth)
	for a in anchors:
		var at: Vector3 = a[0]
		var out: Vector3 = a[1]
		var crawls: bool = a[2]
		if crawls:
			_add(pos, parent, along, lies, grid, near_cell, at, -1, 0.0, true)
			_kin(kidc, first_kid, gen, parent, -1, 0)
			climbs.append(0)
		else:
			# start a little inside the rock, so the root grows out of it
			var buried := at - (out * 0.5 + Vector3.DOWN).normalized() * 0.15
			_add(pos, parent, along, lies, grid, near_cell, buried, -1, 0.0, false)
			_kin(kidc, first_kid, gen, parent, -1, 0)
			climbs.append(0)
			var first := buried + (Vector3.DOWN + out * 0.6).normalized() * step * 2.0
			_add(pos, parent, along, lies, grid, near_cell, first, pos.size() - 1, step * 2.0, false)
			_kin(kidc, first_kid, gen, parent, pos.size() - 2, 0)
			climbs.append(0)
		fresh.append(pos.size() - 1)

	var wander := lerpf(0.03, 0.4, curl)
	# off a face by the girth a root may have there (see the cap on climbing
	# nodes below), so it lies against the stones, not inside them
	var stand_off: float = 0.3 * 0.35 * st.thickness * sc + 0.02
	var gravity := lerpf(0.05, 0.6, hang)
	for _round in ROUNDS:
		var grown_last := fresh
		for ni in fresh:
			var p := pos[ni]
			var cell := _cell(p, influence)
			for dz in range(-1, 2):
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var key := cell + Vector3i(dx, dy, dz)
						if not agrid.has(key):
							continue
						for ai in agrid[key]:
							if alive[ai] == 0:
								continue
							var d := p.distance_to(attract[ai])
							if d < closest_d[ai]:
								closest_d[ai] = d
								closest[ai] = ni
		fresh = PackedInt32Array()
		var pull := {}   # node -> summed direction
		for ai in attract.size():
			if alive[ai] == 0 or closest[ai] < 0:
				continue
			if closest_d[ai] < kill:
				alive[ai] = 0
				continue
			var ni := closest[ai]
			pull[ni] = pull.get(ni, Vector3.ZERO) + (attract[ai] - pos[ni]) / closest_d[ai]
		for ni in grown_last:
			if momentum.has(ni) and kidc[ni] == 0:
				if not pull.has(ni):
					pull[ni] = momentum[ni][0]
				else:
					# the more it likes to climb, the less it lets itself be
					# pulled back before it is over
					var sum: Vector3 = pull[ni]
					pull[ni] = sum + (momentum[ni][0] as Vector3) * maxf(1.0, sum.length()) * (0.5 + 2.0 * climb)
		if pull.is_empty():
			break
		for ni in pull:
			# the fork rules: room for another branch here?
			var forking := kidc[ni] >= 1
			if kidc[ni] >= max_kids:
				continue
			if forking and (gen[ni] >= fork_depth or not _gap_clear(ni, parent, first_kid, kidc, fork_gap, step)):
				continue
			var dir: Vector3 = (pull[ni] as Vector3).normalized()
			var jitter := Vector3(rng.randfn(), rng.randfn() * 0.5, rng.randfn()) * wander
			var on_ground := lies[ni] == 1
			if not on_ground:
				dir += Vector3.DOWN * gravity
			dir = (dir + jitter).normalized()
			# a branch leaves at the fork angle; a root's own course bends gently
			if parent[ni] >= 0:
				var heading := (pos[ni] - pos[parent[ni]]).normalized()
				if on_ground:
					# on the ground a fork turns aside, never up into the air
					heading.y = 0.0
					heading = heading.normalized() if heading.length() > 0.01 else Vector3.FORWARD
					dir.y = 0.0
				dir = _at_angle(heading, dir, fork_angle, rng) if forking else _within(heading, dir, CONTINUE_ANGLE)
			# a root never grows up into the air
			if not on_ground and dir.y > 0.05:
				dir.y = 0.05
				dir = dir.normalized()
			var next: Vector3 = pos[ni] + dir * step
			var lie := false
			var climbing := false
			var going := Vector3.ZERO
			if on_ground:
				# keep to the surface, whatever it is; off the coast, tip over
				var flat := Vector3(dir.x, 0.0, dir.z)
				flat = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
				var here := pos[ni]
				# Klättra: a root running beside a wall now and then turns to it
				if climb > 0.0 and climbs[ni] == 0 and rng.randf() < climb * 0.35:
					var best_rise := step * 1.2
					var best := Vector3.ZERO
					for s8 in 8:
						var a8 := TAU * s8 / 8.0
						var d8 := Vector3(cos(a8), 0.0, sin(a8))
						var q8 := here + d8 * step * 1.5
						var g8: float = ground.call(q8.x, q8.z)
						if not is_nan(g8) and g8 - here.y > best_rise and d8.dot(flat) > -0.2:
							best_rise = g8 - here.y
							best = d8
					if best != Vector3.ZERO:
						flat = best
				var target := here + flat * step
				var h: float = ground.call(target.x, target.z)
				if not is_nan(h):
					var rise := h - here.y
					var under_here: float = ground.call(here.x, here.z)
					if rise < step * 1.2 and not is_nan(under_here) and here.y - under_here > step * 1.2:
						# partway down a face: keep going down it, winding from side to side
						var down := minf(step * 0.8, here.y - under_here)
						next = here + Vector3.DOWN * down + _wind(here, flat, curl, step)
						next = _to_face(next, -flat, next.y, ground, stand_off)
						climbing = true
						going = flat
					elif absf(rise) <= step * 1.2:
						next = Vector3(target.x, h, target.z)
					elif rise > 0.0 and climbs[ni] == 0 and rng.randf() > climb:
						# Klättra says go round: along the face, the side the pull leans to
						var side := flat.cross(Vector3.UP).normalized()
						if side.dot(pull[ni]) < 0.0:
							side = -side
						var aside := here + (side * 0.8 - flat * 0.2).normalized() * step
						var hr: float = ground.call(aside.x, aside.z)
						if is_nan(hr) or absf(hr - here.y) > step * 1.2:
							continue
						next = Vector3(aside.x, hr, aside.z)
					elif rise > 0.0 and climbs[ni] == 1:
						# already on the face: on up it from right here, and over the
						# top once the top is near
						if rise <= step * 2.0:
							var over := here + flat * (stand_off + step * 0.6)
							var ho: float = ground.call(over.x, over.z)
							next = Vector3(over.x, ho if not is_nan(ho) else h, over.z)
						else:
							next = here + Vector3.UP * step * 0.8 + _wind(here, flat, curl, step)
							next = _to_face(next, flat, next.y, ground, stand_off)
							climbing = true
						going = flat
					else:
						# a wall or a drop: find its face, and climb up or down it,
						# standing off the face by about the root's own thickness
						var a := 0.0
						var b := 1.0
						for _halving in 7:
							var m := (a + b) * 0.5
							var p := here + flat * step * m
							var hm: float = ground.call(p.x, p.z)
							if is_nan(hm) or absf(hm - here.y) > step * 0.6:
								b = m
							else:
								a = m
						var edge := here + flat * step * (a if rise > 0.0 else b)
						edge += flat * (-stand_off if rise > 0.0 else stand_off)
						next = Vector3(edge.x, here.y + signf(rise) * minf(absf(rise), step * 0.8), edge.z)
						climbing = true
						going = flat
						if rise > 0.0:
							# up the face, winding from side to side, kept against it
							next += _wind(here, flat, curl, step)
							next = _to_face(next, flat, next.y, ground, stand_off)
					lie = true
			if not lie and inside.call(next):
				# round the rock: slide down and away instead
				next = pos[ni] + (dir + Vector3.DOWN * 1.5).normalized() * step
				if inside.call(next):
					continue
			if _near(pos, grid, near_cell, next, step * 0.4):
				continue
			_add(pos, parent, along, lies, grid, near_cell, next, ni, along[ni] + step, lie)
			_kin(kidc, first_kid, gen, parent, ni, gen[ni] + (1 if forking else 0))
			climbs.append(1 if climbing else 0)
			var new_k := pos.size() - 1
			if climbing and going != Vector3.ZERO:
				momentum[new_k] = [going, 8]
			elif momentum.has(ni) and momentum[ni][1] > 1 and lie:
				# over the top and on: a few more steps the same way
				momentum[new_k] = [momentum[ni][0], momentum[ni][1] - 1]
			fresh.append(pos.size() - 1)
		if fresh.is_empty():
			break

	# nothing may end up inside a wall or a stone: a node on or against
	# them that did (in a corner, under a stone leaning out) steps out to the
	# nearest open spot at its own height
	for k in pos.size():
		if lies[k] == 1:
			var g: float = ground.call(pos[k].x, pos[k].z)
			if not is_nan(g) and g > pos[k].y + 0.05:
				pos[k] = _step_out(pos[k], ground, stand_off)

	# thickness by the pipe model, children after parents
	var n := pos.size()
	var tip: float = 0.028 * st.thickness * sc
	var most: float = 0.3 * st.thickness * sc
	var radius := PackedFloat32Array()
	radius.resize(n)
	var feed := PackedFloat32Array()
	feed.resize(n)
	var kids: Array = []
	kids.resize(n)
	for k in n:
		kids[k] = []
	for k in range(n - 1, -1, -1):
		# on a face a root stays slender, or it reads as a post stuck to the wall
		radius[k] = minf(pow(feed[k], 1.0 / PIPE) if feed[k] > 0.0 else tip, most * (0.35 if climbs[k] == 1 else 1.0))
		if parent[k] >= 0:
			feed[parent[k]] += pow(radius[k], PIPE)
			kids[parent[k]].append(k)
	# roots on a face lie against it, as close as their own girth allows:
	# each climbing node finds the nearest face at its height and is set
	# just off it
	for k in n:
		if climbs[k] == 1:
			pos[k] = _hug(pos[k], ground, radius[k] + 0.015)
	# then smooth them along the face, put back against it after each pass,
	# so they run in soft curves instead of zigzags
	var first_child := PackedInt32Array()
	first_child.resize(n)
	first_child.fill(-1)
	for k in n:
		if parent[k] >= 0 and first_child[parent[k]] < 0:
			first_child[parent[k]] = k
	for _pass in 4:
		var moved := pos.duplicate()
		for k in n:
			if climbs[k] == 1 and parent[k] >= 0 and first_child[k] >= 0:
				var mid := pos[parent[k]] * 0.25 + pos[k] * 0.5 + pos[first_child[k]] * 0.25
				moved[k] = _hug(mid, ground, radius[k] + 0.015)
		pos = moved
	# over a crest (a wall's top edge, a stone's shoulder) a root rolls
	# round in a curve instead of folding at the edge: each node where it
	# turns round an outside edge moves out from the stone along the bend's
	# bisector, its neighbours half as far
	var main_kid := PackedInt32Array()
	main_kid.resize(n)
	main_kid.fill(-1)
	for k in n:
		for c in kids[k]:
			if main_kid[k] < 0 or radius[c] > radius[main_kid[k]]:
				main_kid[k] = c
	for _rounding in 1:
		var shift := PackedVector3Array()
		shift.resize(n)
		for k in n:
			var pk := parent[k]
			var ck := main_kid[k]
			if lies[k] == 0 or pk < 0 or ck < 0:
				continue
			var din := (pos[k] - pos[pk]).normalized()
			var dout := (pos[ck] - pos[k]).normalized()
			var turn := 1.0 - din.dot(dout)
			if turn < 0.15:
				continue
			var outward := (din - dout).normalized()
			# only round an outside edge: stone behind the bend, air in front
			var behind := pos[k] - outward * 0.08
			var front := pos[k] + outward * 0.08
			var gb: float = ground.call(behind.x, behind.z)
			var gf: float = ground.call(front.x, front.z)
			if is_nan(gb) or behind.y > gb - 0.01 or (not is_nan(gf) and front.y < gf):
				continue
			var d := minf(turn, 1.0) * 0.12 * sc
			shift[k] += outward * d
			shift[pk] += outward * d * 0.5
			shift[ck] += outward * d * 0.5
		for k in n:
			pos[k] += shift[k]
	# roots on the ground lie half sunk into it
	for k in n:
		if lies[k] == 1:
			pos[k].y += radius[k] * 0.3
	var longest := 0.001
	for k in n:
		longest = maxf(longest, along[k])
	# where the roots lie on the ground, and how thick: x, z, radius in turn
	var lying := PackedFloat32Array()
	for k in n:
		if lies[k] == 1:
			lying.append_array([pos[k].x, pos[k].z, radius[k]])

	# chains: follow the thickest child on; every other child starts a chain
	# of its own from the fork
	var mesh := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
		"c": PackedColorArray(), "i": PackedInt32Array(), "lying": lying, "nodes": pos, "lies": lies, "climbs": climbs, "radius": radius}
	var starts: Array = []
	for k in n:
		if parent[k] < 0:
			starts.append([k, -1])
	while not starts.is_empty():
		var s: Array = starts.pop_back()
		var chain := PackedInt32Array()
		if s[1] >= 0:
			chain.append(s[1])
		var k: int = s[0]
		while true:
			chain.append(k)
			var ks: Array = kids[k]
			if ks.is_empty():
				break
			var main: int = ks[0]
			for c in ks:
				if radius[c] > radius[main]:
					main = c
			for c in ks:
				if c != main:
					starts.append([c, k])
			k = main
		if chain.size() >= 2:
			_tube(mesh, chain, pos, radius, along, lies, climbs, longest, curl, rng.randf() * TAU, s[1] >= 0, ground)
	return mesh


## A step sideways along a wall face, swinging back and forth with height,
## so roots wind up and down walls instead of running straight.
static func _wind(here: Vector3, flat: Vector3, curl: float, step: float) -> Vector3:
	var along_face := flat.cross(Vector3.UP)
	if along_face.length() < 0.01:
		return Vector3.ZERO
	var phase := (here.x + here.z) * 1.3
	return along_face.normalized() * sin(here.y * 2.6 / (step / STEP) + phase) * step * lerpf(0.5, 1.3, curl)


## p moved along `toward` (the direction into the wall) until it stands
## `stand_off` from a face whose top is above `level`; p itself if no face
## is near.
static func _to_face(p: Vector3, toward: Vector3, level: float, ground: Callable, stand_off: float) -> Vector3:
	var lo := -0.6
	var hi := 0.6
	var g_lo: float = ground.call(p.x + toward.x * lo, p.z + toward.z * lo)
	var g_hi: float = ground.call(p.x + toward.x * hi, p.z + toward.z * hi)
	if is_nan(g_lo) or is_nan(g_hi) or g_lo > level or g_hi <= level:
		return p
	for _halving in 8:
		var m := (lo + hi) * 0.5
		var g: float = ground.call(p.x + toward.x * m, p.z + toward.z * m)
		if not is_nan(g) and g > level:
			hi = m
		else:
			lo = m
	var at := p + toward * (lo - stand_off)
	return Vector3(at.x, p.y, at.z)


## p moved sideways to the nearest spot within 0.8 m where nothing stands
## above its height, and `stand_off` further; or, if there is none, lifted
## onto the top of what covers it.
static func _step_out(p: Vector3, ground: Callable, stand_off: float) -> Vector3:
	for ring in range(1, 17):
		var r := ring * 0.05
		for s in 12:
			var a := TAU * s / 12.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var q := p + dir * r
			var g: float = ground.call(q.x, q.z)
			if not is_nan(g) and g <= p.y + 0.02:
				return p + dir * (r + stand_off)
	var top: float = ground.call(p.x, p.z)
	return Vector3(p.x, top, p.z)


## p set `gap` off the nearest face that stands above it, within 0.8 m;
## p itself if there is none.
static func _hug(p: Vector3, ground: Callable, gap: float) -> Vector3:
	var best_r := INF
	var best_dir := Vector3.ZERO
	for s in 24:
		var a := TAU * s / 24.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		# the first distance along dir where something stands above p
		var lo := 0.0
		var hi := -1.0
		for ring in range(1, 17):
			var r := ring * 0.05
			if r >= best_r:
				break
			var g: float = ground.call(p.x + dir.x * r, p.z + dir.z * r)
			if not is_nan(g) and g > p.y + 0.03:
				hi = r
				break
			lo = r
		if hi < 0.0:
			continue
		for _halving in 6:
			var m := (lo + hi) * 0.5
			var g: float = ground.call(p.x + dir.x * m, p.z + dir.z * m)
			if not is_nan(g) and g > p.y + 0.03:
				hi = m
			else:
				lo = m
		if lo < best_r:
			best_r = lo
			best_dir = dir
	if best_dir == Vector3.ZERO:
		return p
	return p + best_dir * (best_r - gap)


## p, or the nearest point outside the ground, the ruins and the stones for
## a root of radius r lying on or against them: lifted onto the top, or
## moved out from the face, whichever is the shorter way.
static func _outside(p: Vector3, r: float, ground: Callable) -> Vector3:
	var g: float = ground.call(p.x, p.z)
	if is_nan(g):
		return p
	var floor_y := g + r * 0.3
	if p.y >= floor_y - 0.01:
		return p
	var lift := floor_y - p.y
	# out sideways: the nearest spot where nothing stands above p
	for ring in range(1, 13):
		var d := ring * 0.04
		if d + r > lift:
			break
		for s in 12:
			var a := TAU * s / 12.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var q := p + dir * d
			var gq: float = ground.call(q.x, q.z)
			if not is_nan(gq) and gq + r * 0.3 <= p.y:
				return p + dir * (d + r)
	return Vector3(p.x, floor_y, p.z)


## Where a root comes up a face and over the top of a wall or stone, the
## points from a little way down the face, across the top and (if it goes
## on down) a little way down the far face are replaced by one smooth arch:
## a cubic curve leaving the face along it and landing the same way. The
## arch is raised until it clears the stone everywhere, so the root rolls
## over the crest instead of folding round its edges.
static func _arch_over_tops(pts: Array[Vector3], rad: Array[float], on_solid: Array[bool], on_face: Array[bool], ground: Callable) -> void:
	var n := pts.size()
	if n < 6:
		return
	# found from the shape itself: a stretch where the root runs steeply up
	# and then levels off is a climb onto a top, whether the root counted
	# itself as climbing or walked up a crumbled wall's steps
	var slope: Array[float] = []
	for i in n:
		slope.append((pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized().y)
	var back := 3
	var k := back
	while k < n - 2:
		var top_of_climb: bool = on_solid[k] and slope[k] > 0.5 and slope[k + 1] <= 0.5
		if not top_of_climb or pts[k].y - pts[maxi(0, k - 8)].y < 0.25:
			k += 1
			continue
		# across the top, to where it runs steeply down again, or a little way on
		var end := k + 1
		while end < n - 1 and slope[end] > -0.5 and end - k < 16:
			end += 1
		var down_far: bool = slope[end] <= -0.5
		var a := k - back
		var b := mini(n - 2, end + back) if down_far else mini(n - 2, k + 4)
		var all_solid := true
		for i in range(a, b + 1):
			all_solid = all_solid and on_solid[i]
		if b - a < 4 or not all_solid:
			k += 1
			continue
		var p0 := pts[a]
		var p3 := pts[b]
		var t0 := (pts[a] - pts[a - 1]).normalized()
		var t3 := (pts[b + 1] - pts[b]).normalized()
		var reach := p0.distance_to(p3) * 0.4 + 0.05
		var curve: Array[Vector3] = []
		var clear := false
		for attempt in 5:
			curve = []
			clear = true
			for i in range(a, b + 1):
				var t := float(i - a) / float(b - a)
				var p := _bezier(p0, p0 + t0 * reach, p3 - t3 * reach, p3, t)
				curve.append(p)
				# a few centimetres' grace: the height raster is coarse at a face
				if _outside(p, rad[i], ground).distance_to(p) > 0.06:
					clear = false
			if clear:
				break
			reach *= 1.25
		var off := 0.0
		for i in range(a, b + 1):
			off = maxf(off, curve[i - a].distance_to(pts[i]))
		# only a gentle arch: if it would have to stand far off the root's own
		# course to clear the stone, the root keeps its course
		if clear and off < (0.25 if down_far else 0.12):
			for i in range(a, b + 1):
				pts[i] = _outside(curve[i - a], rad[i], ground)
		k = b + 1


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Note a new node's family: its parent has one more child.
static func _kin(kidc: PackedInt32Array, first_kid: PackedInt32Array, gen: PackedInt32Array, parent: PackedInt32Array,
		from: int, generation: int) -> void:
	kidc.append(0)
	first_kid.append(-1)
	gen.append(generation)
	if from >= 0:
		if kidc[from] == 0:
			first_kid[from] = kidc.size() - 1
		kidc[from] += 1


## No other fork within `gap` of node ni, up the root or down its course.
static func _gap_clear(ni: int, parent: PackedInt32Array, first_kid: PackedInt32Array, kidc: PackedInt32Array, gap: float, step: float) -> bool:
	var reach := 0.0
	var k := parent[ni]
	while k >= 0 and reach < gap:
		if kidc[k] > 1:
			return false
		reach += step
		k = parent[k]
	reach = 0.0
	k = first_kid[ni]
	while k >= 0 and reach < gap:
		if kidc[k] > 1:
			return false
		reach += step
		k = first_kid[k]
	return true


## dir turned so it leaves `heading` at exactly `angle`, on the side it
## already leans to.
static func _at_angle(heading: Vector3, dir: Vector3, angle: float, rng: RandomNumberGenerator) -> Vector3:
	var side := dir - heading * dir.dot(heading)
	if side.length() < 0.001:
		var any := Vector3(rng.randfn(), rng.randfn(), rng.randfn()) if rng else Vector3.UP
		side = heading.cross(any)
		if side.length() < 0.001:
			side = heading.cross(Vector3.RIGHT)
	side = side.normalized()
	return (heading * cos(angle) + side * sin(angle)).normalized()


## dir, bent back toward `heading` if it turns away by more than `limit`.
static func _within(heading: Vector3, dir: Vector3, limit: float) -> Vector3:
	var angle := heading.angle_to(dir)
	if angle <= limit:
		return dir
	return _at_angle(heading, dir, limit, null)


static func _cell(p: Vector3, size: float) -> Vector3i:
	return Vector3i(floori(p.x / size), floori(p.y / size), floori(p.z / size))


static func _add(pos: PackedVector3Array, parent: PackedInt32Array, along: PackedFloat32Array, lies: PackedByteArray,
		grid: Dictionary, cell: float, p: Vector3, from: int, dist: float, lie: bool) -> void:
	pos.append(p)
	parent.append(from)
	along.append(dist)
	lies.append(1 if lie else 0)
	var key := _cell(p, cell)
	if not grid.has(key):
		grid[key] = []
	grid[key].append(pos.size() - 1)


static func _near(pos: PackedVector3Array, grid: Dictionary, cell: float, p: Vector3, r: float) -> bool:
	var key := _cell(p, cell)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := key + Vector3i(dx, dy, dz)
				if grid.has(k):
					for ni in grid[k]:
						if pos[ni].distance_to(p) < r:
							return true
	return false


## A smooth tube along a chain of nodes, snaking a little if the style
## curls, its end rounded off.
static func _tube(m: Dictionary, chain: PackedInt32Array, pos: PackedVector3Array, radius: PackedFloat32Array,
		along: PackedFloat32Array, lies: PackedByteArray, climbs: PackedByteArray, longest: float, curl: float, phase: float, branch: bool, ground: Callable) -> void:
	var pts: Array[Vector3] = []
	var rad: Array[float] = []
	var dist: Array[float] = []
	var free: Array[float] = []
	var on_solid: Array[bool] = []
	var on_face: Array[bool] = []
	for k in chain:
		on_solid.append(lies[k] == 1)
		on_face.append(climbs[k] == 1)
		pts.append(pos[k])
		rad.append(radius[k])
		dist.append(along[k])
		free.append(0.0 if lies[k] == 1 else 1.0)
	# a branch starts at the centre of its parent with the parent's girth:
	# swell it there and taper it over a few rings, a fillet that grows out
	# of the parent instead of a crease where a thin tube pokes through
	if branch and rad.size() > 2:
		var own := rad[1]
		var host := rad[0]
		rad[0] = lerpf(own, host, 0.85)
		rad[1] = lerpf(own, host, 0.45)
		if rad.size() > 3:
			rad[2] = lerpf(rad[2], host, 0.15)
	# twice as many points, halfway between the nodes, so bends over a
	# wall's top and round its foot come out round rather than folded
	if pts.size() > 2:
		var p2: Array[Vector3] = [pts[0]]
		var r2: Array[float] = [rad[0]]
		var d2: Array[float] = [dist[0]]
		var f2: Array[float] = [free[0]]
		var s2: Array[bool] = [on_solid[0]]
		var c2: Array[bool] = [on_face[0]]
		for k in range(1, pts.size()):
			p2.append((pts[k - 1] + pts[k]) * 0.5)
			r2.append((rad[k - 1] + rad[k]) * 0.5)
			d2.append((dist[k - 1] + dist[k]) * 0.5)
			f2.append(maxf(free[k - 1], free[k]))
			s2.append(on_solid[k - 1] and on_solid[k])
			c2.append(on_face[k - 1] and on_face[k])
			p2.append(pts[k])
			r2.append(rad[k])
			d2.append(dist[k])
			f2.append(free[k])
			s2.append(on_solid[k])
			c2.append(on_face[k])
		pts = p2
		rad = r2
		dist = d2
		free = f2
		on_solid = s2
		on_face = c2
	# the girth eases from one node to the next, so a root narrowing as it
	# takes to a wall does not step down at the wall's foot
	for _easing in 2:
		var eased := rad.duplicate()
		for k in range(1, rad.size() - 1):
			eased[k] = rad[k - 1] * 0.25 + rad[k] * 0.5 + rad[k + 1] * 0.25
		rad = eased
	# smoothing, the ends held: rounder bends for the stylized look. At a
	# wall's foot the curve cuts through the air of the corner, a soft bend;
	# where it would cut into stone (over a wall's top, round a stone's
	# shoulder) the point is put back outside it after every pass
	for _smoothing in 5:
		var smooth := pts.duplicate()
		for k in range(1, pts.size() - 1):
			smooth[k] = pts[k - 1] * 0.25 + pts[k] * 0.5 + pts[k + 1] * 0.25
		pts = smooth
		for k in pts.size():
			# up a face the root is drawn back against it; only its first and
			# last steps on the face are left to round the bend at the foot
			var mid_face: bool = on_face[k] and k > 1 and k < pts.size() - 2 and on_face[k - 1] and on_face[k + 1] and (on_face[k - 2] or on_face[k + 2])
			if mid_face:
				pts[k] = _hug(pts[k], ground, rad[k] + 0.015)
			if on_solid[k] or (k > 0 and k < pts.size() - 1 and on_solid[k - 1] and on_solid[k + 1]):
				pts[k] = _outside(pts[k], rad[k], ground)
	_arch_over_tops(pts, rad, on_solid, on_face, ground)
	var count := pts.size()
	var sides := 8 if rad[0] > 0.07 else 6
	var base: int = m.v.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var u := t0.cross(Vector3.RIGHT if absf(t0.x) < 0.9 else Vector3.FORWARD).normalized()
	var v_len := 0.0
	for k in count:
		var t := (pts[mini(k + 1, count - 1)] - pts[maxi(k - 1, 0)]).normalized()
		u = (u - t * u.dot(t)).normalized()
		var w := t.cross(u)
		if k > 0:
			v_len += pts[k].distance_to(pts[k - 1])
		# a slow snake sideways, more on thin roots
		var snake := u * sin(v_len * 2.2 + phase) * curl * 0.12 * (1.0 - smoothstep(0.05, 0.25, rad[k]))
		# the last rings close to a rounded tip
		var r := rad[k]
		if k == count - 1:
			r *= 0.15
		elif k == count - 2:
			r *= 0.7
		var sway := clampf(dist[k] / longest, 0.0, 1.0)
		for s in sides + 1:
			var a := TAU * s / sides
			var nrm := u * cos(a) + w * sin(a)
			m.v.append(pts[k] + snake + nrm * r)
			m.n.append(nrm)
			# the bark wraps once round every root
			m.uv.append(Vector2(float(s) / sides, v_len * 0.9))
			m.c.append(Color(sway, free[k], 0.0, 1.0))
	for k in count - 1:
		for s in sides:
			var i0 := base + k * (sides + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + sides + 1
			var i3 := i2 + 1
			m.i.append_array([i0, i2, i1, i1, i2, i3])
