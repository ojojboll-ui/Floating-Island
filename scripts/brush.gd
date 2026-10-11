extends Node3D
## The brush. Left drag applies the current tool where the mouse points;
## Shift turns raise into lower, draw-land into erase-land, water into dry,
## and placing into taking away. Each stroke is one undo step, covering both
## the ground and what stands on it.
##
## Placing works like painting: a click puts down one, holding or dragging
## fills the brush, as densely as Styrka asks.
##
## Picking marches the camera ray through the height field instead of using
## physics, so it always matches the terrain as it is right now. The two
## underside tools (wearing it away, and roots) march through the whole body
## instead, so they can be used from below.

signal changed(rect: Rect2i)
signal tool_changed

enum Tool { RAISE, LOWER, SMOOTH, FLATTEN, LAND_ADD, LAND_REMOVE, PAINT, WATER, DRY, PLACE, REMOVE,
		WALL, PILLAR, ARCH, STAIRS, DEMOLISH, FLOOR, STOREY, DOOR, WINDOW, CARVE, ROOTS }

## Tools that move the ground, so ruins standing on it are rebuilt to follow.
const SHAPING := [Tool.RAISE, Tool.LOWER, Tool.SMOOTH, Tool.FLATTEN, Tool.LAND_ADD, Tool.LAND_REMOVE, Tool.WATER, Tool.DRY, Tool.CARVE]

const IslandData := preload("res://scripts/island_data.gd")
const IslandMesher := preload("res://scripts/island_mesher.gd")
const Catalog := preload("res://scripts/prop_catalog.gd")
const REBUILD_INTERVAL := 0.05
## the reversed underside tools, while Shift is held
const UNCARVE := 100
const UNROOT := 101
const UNDO_LIMIT := 40

var tool: int = Tool.RAISE
var paint_target := Color(0, 0, 0, 0)
var paint_rocks := 0.0
var place_kind := ""
var ruin_height := 2.0
var radius := 1.6
var strength := 0.5
## Painting things out: how close they stand, and whether evenly or in clumps.
var density := 0.5
var clumping := 0.3

var data
var view
var props
var ruins
var roots
var camera: Camera3D

var _stroking := false
var _flatten_h := 0.0
var _water_level := 0.0
var _stroke_ground := PackedFloat32Array()   # heights before this stroke
var _since_rebuild := 0.0
var _undo: Array = []
var _redo: Array = []
var _decal: Decal
var _ring: MeshInstance3D
var _hit := {}
var _mouse := Vector2(-1, -1)
var _stroke_time := 0.0
var _scatter := 0.0
var _rng := RandomNumberGenerator.new()
var _draw := PackedVector2Array()   # a wall being drawn
var _from := Vector2.ZERO             # where an arch or stair starts
var _to := Vector2.ZERO
var _since_preview := 0.0
var _ruin_seed := 0                  # so the preview is the piece you get
var _floor := {}                       # the floor record being painted
var _root_anchors: Array = []         # where the roots being drawn start
# the ghost: what a click will put down, see-through under the pointer
var _ghost: Node3D
var _ghost_key := ""
var _ghost_variant := 0
var _ghost_rot := 0.0
var _ghost_jit := 0.0
var _ghost_mat: ShaderMaterial
var _ghost_leaf_mat: ShaderMaterial


func setup(island_data, island_view, prop_layer, ruin_layer, cam: Camera3D) -> void:
	data = island_data
	view = island_view
	props = prop_layer
	ruins = ruin_layer
	_rng.seed = 5
	camera = cam
	_decal = Decal.new()
	_decal.texture_albedo = _ring_texture()
	_decal.modulate = Color(1.0, 0.98, 0.92)
	_decal.albedo_mix = 1.0
	_decal.cull_mask = 1
	# only on ground facing up, not smeared down the cliffs
	_decal.normal_fade = 0.6
	add_child(_decal)
	_ring = MeshInstance3D.new()
	_ring.mesh = _circle_mesh()
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.97, 0.88, 0.8)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.no_depth_test = true
	_ring.material_override = ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func set_tool(t: int, paint: Color = Color(0, 0, 0, 0), rocks: float = 0.0, kind := "") -> void:
	tool = t
	place_kind = kind
	_reroll_ghost()
	paint_target = paint
	paint_rocks = rocks
	tool_changed.emit()


func _is_land_tool() -> bool:
	return tool == Tool.LAND_ADD or tool == Tool.LAND_REMOVE


func _input(event: InputEvent) -> void:
	# track the pointer from events, also while it is over the panel
	if event is InputEventMouse:
		_mouse = event.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z:
			if key.shift_pressed:
				redo()
			else:
				undo()
		elif key.ctrl_pressed and key.keycode == KEY_Y:
			redo()
		elif key.keycode == KEY_BRACKETLEFT:
			radius = maxf(0.4, radius / 1.15)
			tool_changed.emit()
		elif key.keycode == KEY_BRACKETRIGHT:
			radius = minf(6.0, radius * 1.15)
			tool_changed.emit()


func _begin_stroke(screen: Vector2) -> void:
	var hit := pick(screen)
	if hit.is_empty() or (not hit.land and not _is_land_tool()):
		return
	_undo.append(_state())
	_stroke_ground = data.height.duplicate()
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_stroking = true
	_stroke_time = 0.0
	_scatter = 0.0
	var p: Vector3 = hit.pos
	props.begin_stroke()
	if tool == Tool.PLACE and not Input.is_key_pressed(KEY_SHIFT):
		if not props.place_over(place_kind, p.x, p.z, _rng, 1.0, true, false, _ghost_variant, _ghost_rot, _ghost_jit).is_empty():
			_reroll_ghost()
	# ruins: a pillar goes down at once; walls, arches and stairs are drawn.
	# Started on a storey, they stand on that storey.
	_ruin_seed = _rng.randi()
	ruins.build_base = hit.get("level", NAN)
	var at: Vector2 = ruins.snap_point(Vector2(p.x, p.z))
	match tool:
		Tool.PILLAR:
			ruins.add_pillar(at, ruin_height, _ruin_seed)
		Tool.WALL:
			_draw = PackedVector2Array([at])
		Tool.ARCH, Tool.STAIRS:
			_from = at
			_to = at
		Tool.FLOOR:
			# paving on the ground, or more of the storey it is started on
			_floor = ruins.begin_floor(hit.get("level", NAN), _ruin_seed)
			ruins.paint_floor(_floor, Vector2(p.x, p.z), radius)
			ruins.refresh(_floor)
		Tool.DOOR, Tool.WINDOW:
			_open_hole(screen)
		Tool.ROOTS:
			_root_anchors = []
			if not Input.is_key_pressed(KEY_SHIFT):
				_root_anchors.append(roots.anchor_at(p))
		Tool.STOREY:
			# a new storey Höjd above where it is started: the ground, or the
			# storey clicked on. Pillars under it grow up to carry it.
			var level: float = (hit.level if hit.has("level") else data.sample_height(p.x, p.z)) + ruin_height
			ruins.build_base = NAN
			_floor = ruins.begin_floor(level, _ruin_seed)
			ruins.paint_floor(_floor, _on_plane(level), radius)
			ruins.refresh(_floor)
	_since_preview = 1.0
	_flatten_h = data.sample_base_height(p.x, p.z)
	# start in a pond and you extend it at its own level; start on dry
	# ground and the new water sits just below that ground
	if data.sample_water(p.x, p.z) > 0.3:
		_water_level = data.sample_wlevel(p.x, p.z)
	else:
		_water_level = data.sample_height(p.x, p.z) - IslandData.WATERLINE


func _end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	match tool:
		Tool.WALL:
			if _draw.size() >= 1:
				_draw[_draw.size() - 1] = ruins.snap_point(_draw[_draw.size() - 1])
			ruins.add_wall(_draw, ruin_height, _ruin_seed)
		Tool.ARCH:
			ruins.add_arch(_from, ruins.snap_point(_to), ruin_height, _ruin_seed)
		Tool.STAIRS:
			ruins.add_stairs(_from, _to, ruin_height, _ruin_seed)
		Tool.FLOOR, Tool.STOREY:
			if not _floor.is_empty():
				ruins.finish_floor(_floor)
			_floor = {}
		Tool.ROOTS:
			roots.add(_root_anchors, _ruin_seed)
			_root_anchors = []
	ruins.clear_preview()
	_draw = PackedVector2Array()
	_flush()


## Forget all undo steps (a new island was opened).
func clear_history() -> void:
	_undo.clear()
	_redo.clear()


## Remember the present as an undo step, for changes made outside a stroke
## (the age dial).
func push_undo() -> void:
	_undo.append(_state())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_state())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_state())
	_restore(_redo.pop_back())


func _state() -> Array:
	return [data.snapshot(), props.snapshot(), ruins.snapshot(), roots.snapshot()]


func _restore(state: Array) -> void:
	data.restore(state[0])
	props.restore(state[1])
	ruins.restore(state[2])
	roots.restore(state[3])
	_flush()
	props.follow_ground()


func _process(delta: float) -> void:
	_hit = pick(_mouse) if _mouse.x >= 0.0 else {}
	_update_cursor()
	if _stroking and not _hit.is_empty():
		_stroke_time += delta
		_apply(_hit, delta)
	_since_rebuild += delta
	if data.dirty.has_area() and _since_rebuild >= REBUILD_INTERVAL:
		_flush()


func _flush() -> void:
	if not data.dirty.has_area():
		return
	var r: Rect2i = data.dirty
	var shape: Rect2i = data.dirty_shape
	data.dirty = Rect2i()
	data.dirty_shape = Rect2i()
	view.rebuild(r, shape)
	_since_rebuild = 0.0
	if tool in SHAPING:
		ruins.follow_ground(r)
	changed.emit(r)


## Show what is being drawn, a few times a second; walls are not cheap.
func _preview(dt: float, kind: String) -> void:
	_since_preview += dt
	if _since_preview < 0.1:
		return
	_since_preview = 0.0
	ruins.preview(kind, _from, _to, _draw, ruin_height, _ruin_seed)


func _apply(hit: Dictionary, dt: float) -> void:
	var p: Vector3 = hit.pos
	var c := Vector2(p.x, p.z)
	var inverse := Input.is_key_pressed(KEY_SHIFT)
	var t: int = tool
	if inverse:
		match t:
			Tool.RAISE: t = Tool.LOWER
			Tool.LOWER: t = Tool.RAISE
			Tool.LAND_ADD: t = Tool.LAND_REMOVE
			Tool.LAND_REMOVE: t = Tool.LAND_ADD
			Tool.WATER: t = Tool.DRY
			Tool.DRY: t = Tool.WATER
			Tool.PLACE: t = Tool.REMOVE
			Tool.CARVE: t = UNCARVE
			Tool.ROOTS: t = UNROOT
	if not hit.land and not (t == Tool.LAND_ADD or t == Tool.LAND_REMOVE):
		return
	var rate := lerpf(0.15, 1.0, strength)
	match t:
		Tool.RAISE:
			data.edit_height(c, radius, 2.0 * rate * dt)
		Tool.LOWER:
			data.edit_height(c, radius, -2.0 * rate * dt)
		Tool.SMOOTH:
			data.edit_smooth(c, radius, 8.0 * rate * dt)
		Tool.FLATTEN:
			data.edit_flatten(c, radius, _flatten_h, 8.0 * rate * dt)
		Tool.LAND_ADD:
			data.edit_land(c, radius, true)
		Tool.LAND_REMOVE:
			data.edit_land(c, radius, false)
		Tool.PAINT:
			data.paint(c, radius, paint_target, paint_rocks, 6.0 * rate * dt)
		Tool.WATER:
			# the level follows the ground down as the brush moves downhill, so
			# a stroke becomes a stream; it never climbs back up. The rim roll
			# is left out, so water runs level all the way to the edge.
			if data.sample_water(c.x, c.y) < 0.3 and data.sample_sdf(c.x, c.y) > 0.0:
				_water_level = minf(_water_level, data.sample_base_height_in(_stroke_ground, c.x, c.y) - IslandData.WATERLINE)
			data.edit_water(c, radius, _water_level, 4.0 * rate * dt, true)
		Tool.DRY:
			data.edit_water(c, radius, _water_level, 4.0 * rate * dt, false)
		Tool.PLACE:
			# paint: once the brush is held or moving, fill it with as many as
			# fit. Täthet sets how close they may stand, Klungor whether they
			# spread evenly or gather in groups (pebbles round a boulder's foot).
			if _stroke_time > 0.12:
				var spread := lerpf(2.6, 0.8, density)
				for attempt in 14:
					var q := _scatter_point(c)
					# paints over what is there, but not over its own kind
					props.place_over(place_kind, q.x, q.y, _rng, spread, false, true)
		Tool.WALL:
			if _draw.is_empty() or _draw[_draw.size() - 1].distance_to(c) > 0.25:
				_draw.append(c)
			_preview(dt, "wall")
		Tool.ARCH, Tool.STAIRS:
			_to = c
			_preview(dt, "arch" if t == Tool.ARCH else "stairs")
		Tool.FLOOR, Tool.STOREY:
			if not _floor.is_empty():
				var at := c
				if _floor.raised:
					# paint across the storey's own plane, not the ground below it
					at = _on_plane(float(_floor.level))
				ruins.paint_floor(_floor, at, radius)
				_since_preview += dt
				if _since_preview >= 0.1:
					_since_preview = 0.0
					ruins.refresh(_floor)
		Tool.DOOR, Tool.WINDOW:
			# drag along a wall to open more of them, as space allows
			_since_preview += dt
			if _since_preview >= 0.05:
				_since_preview = 0.0
				_open_hole(_mouse)
		Tool.CARVE, UNCARVE:
			# wear the underside away from below; Shift builds it back
			var cap := func(k: int) -> float: return IslandMesher.hang_at(data, k)
			data.edit_carve(c, radius, (3.0 if t == Tool.CARVE else -3.0) * rate * dt, cap)
		Tool.ROOTS:
			# a new root wherever the brush has moved on far enough
			var last: Array = _root_anchors.back() if not _root_anchors.is_empty() else []
			if last.is_empty() or Vector3(last[0], last[1], last[2]).distance_to(p) > maxf(0.5, radius * 0.6):
				_root_anchors.append(roots.anchor_at(p))
				_since_preview = 1.0
			_since_preview += dt
			if _since_preview >= 0.25:
				_since_preview = 0.0
				roots.preview(_root_anchors, _ruin_seed)
		UNROOT:
			roots.remove_near(p, radius)
		Tool.DEMOLISH:
			ruins.remove_near(c, radius)
		Tool.REMOVE:
			# Shift with a kind chosen takes away only that kind; the eraser
			# takes everything
			props.remove_near(c.x, c.y, radius, place_kind if tool == Tool.PLACE else "")


func _is_under_tool() -> bool:
	return tool == Tool.CARVE or tool == Tool.ROOTS


## A spot in the brush for the next thing painted. With Klungor up, most
## land beside something already there: one of this stroke's own, or, for
## pebbles, a boulder's foot.
func _scatter_point(c: Vector2) -> Vector2:
	if _rng.randf() < clumping:
		var near: Array = props.stroke_records(place_kind)
		if place_kind == "smasten":
			near.append_array(props.records_near("stenblock", c, radius + 1.0))
		if not near.is_empty():
			var r: Dictionary = near[_rng.randi() % near.size()]
			var reach := float(r.size) * 0.8 + 0.15
			if r.kind == "stenblock":
				reach = float(r.size) * 0.5 + 0.1
			var a := _rng.randf() * TAU
			var q := Vector2(r.x, r.z) + Vector2(cos(a), sin(a)) * reach * _rng.randf_range(1.0, 1.8)
			if q.distance_to(c) <= radius * 1.3:
				return q
	var a := _rng.randf() * TAU
	return c + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * radius


## Where the mouse ray meets the island top. Off the island, it answers with
## the point at rim height, so land can be drawn out into the air.
func pick(screen: Vector2) -> Dictionary:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if _is_under_tool():
		return _pick_body(o, d)
	var hit := _pick_ground(o, d)
	# the top of a stair, pillar, wall or raised floor, if the ray meets one
	# before the ground; {level} then says how high it is
	var top: Dictionary = ruins.pick_support(o, d) if ruins else {}
	if not top.is_empty():
		var t_ground: float = INF if hit.is_empty() or not hit.land else o.distance_to(hit.pos)
		if top.t < t_ground:
			return {"pos": top.pos, "land": true, "level": top.level}
	return hit


func _pick_ground(o: Vector3, d: Vector3) -> Dictionary:
	if absf(d.y) < 0.0001:
		return {}
	var top := IslandData.MAX_HEIGHT + 0.5
	var bottom := IslandData.MIN_HEIGHT - 0.5
	var ta := (top - o.y) / d.y
	var tb := (bottom - o.y) / d.y
	var t := maxf(minf(ta, tb), 0.0)
	var t_end := maxf(ta, tb)
	var step := 0.08
	var prev := t
	while t < t_end:
		var p := o + d * t
		if _below_surface(p):
			var a := prev
			var b := t
			for k in 10:
				var m := (a + b) * 0.5
				if _below_surface(o + d * m):
					b = m
				else:
					a = m
			return {"pos": o + d * b, "land": true}
		prev = t
		t += step
	var tp := (0.0 - o.y) / d.y
	if tp > 0.0:
		var q := o + d * tp
		if data.in_bounds(q.x, q.z):
			return {"pos": q, "land": false}
	return {}


## Open a door or window in the wall under the mouse, if there is one.
func _open_hole(screen: Vector2) -> void:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	var g := _pick_ground(o, d)
	var reach: float = o.distance_to(g.pos) + 0.5 if not g.is_empty() else 200.0
	var piece: Dictionary = ruins.pick_piece(o, d, reach)
	if not piece.is_empty() and piece.record.kind == "wall":
		ruins.add_hole(piece.record, piece.pos, "door" if tool == Tool.DOOR else "window", ruin_height)


## Where the mouse ray crosses the level y.
func _on_plane(y: float) -> Vector2:
	var o := camera.project_ray_origin(_mouse)
	var d := camera.project_ray_normal(_mouse)
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	var q := o + d * ((y - o.y) / d.y)
	return Vector2(q.x, q.z)


## Where the mouse ray first enters the island's body, from above, the side
## or below. {under} says whether that is on the underside.
func _pick_body(o: Vector3, d: Vector3) -> Dictionary:
	var top := IslandData.MAX_HEIGHT + 0.5
	var bottom := -IslandMesher.SKIRT_DEPTH - IslandMesher.BODY_DEPTH - 4.0
	if absf(d.y) < 0.0001:
		return {}
	var ta := (top - o.y) / d.y
	var tb := (bottom - o.y) / d.y
	var t := maxf(minf(ta, tb), 0.0)
	var t_end := minf(maxf(ta, tb), t + 250.0)
	var step := 0.1
	var prev := t
	while t < t_end:
		if roots.inside(o + d * t):
			var a := prev
			var b := t
			for k in 10:
				var m := (a + b) * 0.5
				if roots.inside(o + d * m):
					b = m
				else:
					a = m
			var p := o + d * b
			var under := p.y - IslandMesher.underside(data, p.x, p.z) < 0.35
			return {"pos": p, "land": true, "under": under}
		prev = t
		t += step
	return {}


func _below_surface(p: Vector3) -> bool:
	if not data.in_bounds(p.x, p.z):
		return false
	return data.sample_sdf(p.x, p.z) > 0.0 and p.y <= data.sample_height(p.x, p.z)


func _update_cursor() -> void:
	var over_ui := get_viewport().gui_get_hovered_control() != null
	_update_ghost(over_ui)
	if _hit.is_empty() or over_ui:
		_decal.visible = false
		_ring.visible = false
		return
	var p: Vector3 = _hit.pos
	_decal.visible = true
	_decal.position = p
	# on the underside the ring is cast upward
	_decal.rotation = Vector3(PI, 0.0, 0.0) if _hit.get("under", false) else Vector3.ZERO
	_decal.size = Vector3(radius * 2.0, 4.0, radius * 2.0)
	# the flat ring shows the brush over open air, where there is nothing
	# for the decal to land on
	_ring.visible = _is_land_tool()
	_ring.position = Vector3(p.x, 0.0 if not _hit.land else p.y, p.z)
	_ring.scale = Vector3(radius, 1.0, radius)


func _reroll_ghost() -> void:
	_ghost_variant = _rng.randi() % maxi(1, Catalog.variants(place_kind)) if place_kind != "" else 0
	_ghost_rot = _rng.randf() * TAU
	_ghost_jit = _rng.randf_range(-1.0, 1.0)
	_ghost_key = ""


## The ghost of what a click puts down, where it would stand: the same
## shape, size and turn the click will give it. Green where it may go, red
## where it may not.
func _update_ghost(over_ui: bool) -> void:
	var show: bool = tool == Tool.PLACE and place_kind != "" and not over_ui and not _hit.is_empty() \
		and _hit.land and not Input.is_key_pressed(KEY_SHIFT)
	if not show:
		if _ghost:
			_ghost.visible = false
		return
	var p: Vector3 = _hit.pos
	var k: Dictionary = Catalog.KINDS[place_kind]
	var st = props.style_for(place_kind) if k.has("style") else null
	# a pot by a fire shows hanging over it
	var fire = props.fire_near(p.x, p.z) if place_kind == "gryta" else null
	if fire != null:
		p = Vector3(fire.x, p.y, fire.z)
	var woody: bool = place_kind in props.WOODY
	var key := "%s|%s|%d|%.2f|%.2f|%s" % [place_kind, str(st), _ghost_variant, _ghost_rot, _ghost_jit, fire != null]
	if woody:
		# a tree's shape depends on what stands round it
		key += "|%.1f,%.1f" % [snappedf(p.x, 0.5), snappedf(p.z, 0.5)]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost:
			_ghost.queue_free()
		var rec := {"id": -1, "kind": place_kind, "x": p.x, "z": p.z, "rot": _ghost_rot, "variant": _ghost_variant,
			"hue": 0.5, "jit": _ghost_jit, "over_fire": fire != null}
		if st != null:
			rec.style = (st as Dictionary).duplicate(true)
			rec.size = maxf(0.02, float(st.size) * (1.0 + float(st.variation) * 0.6 * _ghost_jit))
		else:
			rec.size = (float(k.height[0]) + float(k.height[1])) * 0.5
		_ghost = Catalog.build(rec)
		_dress_ghost(_ghost)
		add_child(_ghost)
	_ghost.visible = true
	var lift: float = 0.0 if fire != null else props.lift_for(place_kind, p.x, p.z)
	var tall: float = _ghost.get_meta("tall", 1.0)
	_ghost.global_position = Vector3(p.x, data.sample_height(p.x, p.z) - float(k.sink) * tall + lift, p.z)
	# green: it fits; red: it will take away what is in its way; grey: it
	# cannot go there at all
	var check: int = props.place_check(place_kind, p.x, p.z, 1.0, true)
	var tint: Color = [Color(0.8, 1.0, 0.78), Color(1.0, 0.42, 0.38), Color(0.55, 0.55, 0.58)][check]
	_ghost_mat.set_shader_parameter("tint", tint)
	_ghost_leaf_mat.set_shader_parameter("tint", tint)


func _dress_ghost(node: Node) -> void:
	if _ghost_mat == null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = load("res://shaders/ghost.gdshader")
		_ghost_leaf_mat = ShaderMaterial.new()
		_ghost_leaf_mat.shader = _ghost_mat.shader
		_ghost_leaf_mat.set_shader_parameter("leaf_cut", true)
	# no light or flame in a ghost
	for l in node.find_children("*", "Light3D", true, false):
		l.queue_free()
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mat = (m as MeshInstance3D).material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).shader.resource_path.ends_with("flame.gdshader"):
			m.queue_free()
	var all: Array = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		all.append(node)
	for gi in all:
		var g := gi as GeometryInstance3D
		var leafy := false
		if g.material_override is ShaderMaterial:
			var sh: Shader = (g.material_override as ShaderMaterial).shader
			leafy = sh != null and sh.resource_path.ends_with("leaves.gdshader")
		g.material_override = _ghost_leaf_mat if leafy else _ghost_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _ring_texture() -> ImageTexture:
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var line := 1.0 - smoothstep(0.0, 0.035, absf(r - 0.94))
			var fill := 0.12 * (1.0 - smoothstep(0.85, 0.95, r))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(line + fill, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _circle_mesh() -> ImmediateMesh:
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in 65:
		var a := TAU * k / 64.0
		m.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)))
	m.surface_end()
	return m
