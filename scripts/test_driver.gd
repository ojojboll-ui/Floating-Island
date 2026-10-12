extends RefCounted
## Scripted sessions for snapshots. They go through the real input path:
## mouse events are injected at screen positions, so button clicks reach the
## panel and drags reach the brush exactly as a user's would.

const Brush := preload("res://scripts/brush.gd")
const Catalog := preload("res://scripts/prop_catalog.gd")


static func run(main: Node, name: String) -> void:
	await _frames(main, 20)
	match name:
		"sculpt":
			await _sculpt(main)
		"undo":
			await _sculpt(main)
			for k in 3:
				main.brush.undo()
				await _frames(main, 2)
		"water":
			main.view.profile = false
			await _click(main, main.ui.buttons["Vatten"])
			await _drag(main, [Vector3(2.2, 0.5, -0.6), Vector3(3.0, 0.5, -1.4), Vector3(2.4, 0.5, -1.6), Vector3(2.2, 0.5, -0.6)], 90)
			await _drag(main, [Vector3(3.2, 0.5, -1.2), Vector3(5.0, 0.4, -1.6), Vector3(7.2, 0.2, -1.9)], 70)
		"dry":
			await run(main, "water")
			await _click(main, main.ui.buttons["Torka"])
			await _drag(main, [Vector3(2.0, 0.3, -0.5), Vector3(3.0, 0.3, -1.5), Vector3(2.4, 0.3, -1.7), Vector3(2.0, 0.3, -0.6)], 120)
		"stones":
			await _click(main, main.ui.buttons["Höj"])
			await _drag(main, [Vector3(-3.5, 0.5, 2.5), Vector3(-3.3, 0.5, 2.7)], 120)
			await _click(main, main.ui.buttons["Stenar"])
			await _drag(main, [Vector3(1.0, 0.5, 2.0), Vector3(-1.0, 0.5, 4.0), Vector3(-2.5, 0.5, 4.5)], 60)
		"plants":
			await run(main, "water")
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Lövträd"])
			await _tap(main, Vector3(-5.2, 0.4, -0.6))
			await _tap(main, Vector3(0.8, 0.4, -4.6))
			await _click(main, main.ui.buttons["Gran"])
			await _tap(main, Vector3(-4.0, 0.4, -4.2))
			await _click(main, main.ui.buttons["Buske"])
			await _tap(main, Vector3(1.4, 0.4, 2.6))
			await _tap(main, Vector3(-1.2, 0.6, -2.4))
			await _click(main, main.ui.buttons["Blommor"])
			await _drag(main, [Vector3(-1.0, 0.4, 2.0), Vector3(-2.8, 0.4, 3.6)], 70)
			await _click(main, main.ui.buttons["Vass"])
			await _drag(main, [Vector3(1.2, 0.3, -0.2), Vector3(1.7, 0.3, 0.5), Vector3(3.2, 0.3, 0.3)], 60)
			await _click(main, main.ui.buttons["Näckros"])
			await _drag(main, [Vector3(2.3, 0.2, -0.9), Vector3(2.9, 0.2, -1.4)], 50)
			await _frames(main, 10)
		"trees":
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			for pair in [["Lövträd", Vector3(-5.2, 0.4, -2.2)], ["Gran", Vector3(-2.2, 0.4, 3.9)], ["Höstträd", Vector3(2.2, 0.6, -4.6)], ["Torrträd", Vector3(4.2, 0.4, -2.6)],
					["Buske", Vector3(0.6, 0.4, 2.4)], ["Blombuske", Vector3(-0.6, 0.4, 3.2)], ["Ormbunke", Vector3(-3.4, 0.4, 0.2)], ["Högt gräs", Vector3(-1.4, 0.4, 1.4)],
					["Svamp", Vector3(-3.0, 0.5, -1.0)], ["Klöver", Vector3(1.8, 0.4, 1.0)], ["Stenblock", Vector3(2.6, 0.4, -0.8)], ["Trampstenar", Vector3(1.4, 0.4, 4.4)]]:
				await _click(main, main.ui.buttons[pair[0]])
				await _tap(main, pair[1])
			await _click(main, main.ui.buttons["Blommor"])
			await _drag(main, [Vector3(-3.0, 0.4, 2.0), Vector3(-4.0, 0.4, 3.0)], 50)
			await _frames(main, 10)
		"remove":
			await run(main, "trees")
			print("  props after placing: ", main.props.records.size())
			await _click(main, main.ui.buttons["Ta bort"])
			await _drag(main, [Vector3(-5.0, 0.4, -2.0), Vector3(-1.0, 0.6, -2.0)], 30)
			print("  after erasing: ", main.props.records.size())
			main.brush.undo()
			await _frames(main, 3)
			print("  after undo: ", main.props.records.size())
			main.brush.redo()
			await _frames(main, 3)
			print("  after redo: ", main.props.records.size())
		"paint":
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			main.brush.radius = 2.5
			await _click(main, main.ui.buttons["Gran"])
			await _drag(main, [Vector3(-5.0, 0.4, 1.0), Vector3(-3.0, 0.4, 4.5)], 40)
			await _click(main, main.ui.buttons["Högt gräs"])
			await _drag(main, [Vector3(0.0, 0.4, 1.5), Vector3(2.0, 0.4, 3.5)], 40)
			await _click(main, main.ui.buttons["Buske"])
			await _drag(main, [Vector3(3.0, 0.4, -2.0), Vector3(4.5, 0.4, -3.5)], 30)
			print("  painted props: ", main.props.records.size())
		"ruins", "ruins_new", "ruins_old", "ruins_cut":
			main.view.profile = false
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			var t0 := Time.get_ticks_usec()
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(1.0, 0.5, -1.2), Vector3(2.6, 0.5, -2.2), Vector3(4.2, 0.5, -1.6), Vector3(5.0, 0.4, 0.0)], 50)
			await _click(main, main.ui.buttons["Pelare"])
			await _tap(main, Vector3(0.8, 0.5, -4.2))
			await _click(main, main.ui.buttons["Valv"])
			await _drag(main, [Vector3(1.9, 0.5, -4.6), Vector3(4.3, 0.5, -3.7)], 30)
			await _click(main, main.ui.buttons["Trappa"])
			await _drag(main, [Vector3(3.6, 0.4, 0.6), Vector3(4.9, 0.4, 1.5)], 30)
			print("  ruins: ", main.ruins.records.size(), " pieces in ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
			if name == "ruins_cut":
				await _click(main, main.ui.buttons["Riv"])
				await _drag(main, [Vector3(2.6, 0.5, -2.2), Vector3(2.7, 0.5, -2.2)], 6)
				print("  after cutting the wall: ", main.ruins.records.size(), " pieces")
				main.brush.undo()
				await _frames(main, 3)
				print("  after undo: ", main.ruins.records.size(), " pieces")
				main.brush.redo()
				await _frames(main, 3)
			if name == "ruins_new":
				main.ruins.set_age(0.0)
			elif name == "ruins_old":
				var a0 := Time.get_ticks_usec()
				main.ruins.set_age(0.85)
				print("  set_age rebuilt all in ", (Time.get_ticks_usec() - a0) / 1000.0, " ms")
		"storey":
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			# a wall with an arch drawn along it
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(0.5, 0.5, -2.0), Vector3(3.0, 0.5, -2.6), Vector3(5.0, 0.5, -2.0)], 40)
			await _click(main, main.ui.buttons["Valv"])
			await _drag(main, [Vector3(2.0, 0.5, -2.45), Vector3(3.6, 0.5, -2.5)], 20)
			# stairs up from the lawn, then a floor from their top step
			await _click(main, main.ui.buttons["Trappa"])
			await _drag(main, [Vector3(-1.0, 0.5, 1.6), Vector3(1.4, 0.5, 1.6)], 20)
			var top: float = main.ruins.RuinBuilder.stairs_top(main.ruins.ground, Vector2(-1.0, 1.6), Vector2(1.4, 1.6))
			await _click(main, main.ui.buttons["Golv"])
			main.brush.radius = 1.2
			await _drag(main, [Vector3(1.25, top, 1.6), Vector3(2.4, top, 2.2), Vector3(2.6, top, 3.2)], 40)
			# and a wall standing on that floor
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(2.0, top, 3.4), Vector3(3.3, top, 2.6)], 20)
			var kinds := []
			for r in main.ruins.records:
				kinds.append(r.kind + ("(in wall)" if r.has("wall") else "") + ("(raised %.2f)" % r.level if r.kind == "floor" and r.raised else ""))
			print("  pieces: ", kinds)
			if main.args_age >= 0.0:
				main.ruins.set_age(main.args_age)
		"storey2":
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(0.5, 0.5, -2.0), Vector3(3.0, 0.5, -2.6), Vector3(5.0, 0.5, -2.0)], 40)
			await _click(main, main.ui.buttons["Valv"])
			await _drag(main, [Vector3(2.0, 0.5, -2.45), Vector3(3.6, 0.5, -2.5)], 20)
			await _click(main, main.ui.buttons["Trappa"])
			await _drag(main, [Vector3(-1.0, 0.5, 1.6), Vector3(1.4, 0.5, 1.6)], 20)
			await _click(main, main.ui.buttons["Pelare"])
			await _tap(main, Vector3(3.4, 0.5, 2.4))
			main.ruins.set_age(0.8)
			await _frames(main, 3)
			# click the stair halfway up its flight, and the broken pillar's shaft
			await _click(main, main.ui.buttons["Övervåning"])
			main.brush.radius = 1.0
			var g: float = main.data.sample_height(0.2, 1.6)
			await _drag(main, [Vector3(0.2, g + 0.6, 1.6), Vector3(1.2, g + 0.9, 2.4)], 30)
			var gp: float = main.data.sample_height(3.4, 2.4)
			await _drag(main, [Vector3(3.4, gp + 0.6, 2.4), Vector3(3.0, gp + 0.6, 1.8)], 30)
			var kinds := []
			for r in main.ruins.records:
				kinds.append(r.kind + ("(raised %.2f, %d cells)" % [r.level, r.cells.size()] if r.kind == "floor" else ""))
			print("  pieces: ", kinds)
			print("  stair top %.2f" % main.ruins._top(main.ruins.records[2]), "  pillar top %.2f" % main.ruins._top(main.ruins.records[3]))
			if main.args_age >= 0.0:
				main.ruins.set_age(main.args_age)
		"openings":
			# build from the default view, so every click lands on the island;
			# the view asked for is put back afterwards
			var view := [main.rig.goal_yaw, main.rig.goal_pitch, main.rig.goal_distance, main.rig.goal_target]
			main.rig.goal_yaw = deg_to_rad(20.0)
			main.rig.goal_pitch = deg_to_rad(50.0)
			main.rig.goal_distance = 30.0
			main.rig.goal_target = Vector3(1.5, 0.5, 0.0)
			main.rig.settle()
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			main.brush.ruin_height = 3.4
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(-1.5, 0.5, -2.2), Vector3(2.5, 0.5, -2.8), Vector3(5.5, 0.5, -2.2)], 40)
			await _click(main, main.ui.buttons["Valv"])
			await _drag(main, [Vector3(2.4, 0.5, -2.75), Vector3(3.8, 0.5, -2.68)], 20)
			var gw: float = main.data.sample_height(-0.4, -2.4)
			await _click(main, main.ui.buttons["Dörr"])
			await _tap(main, Vector3(-0.4, gw + 1.0, -2.4))
			await _click(main, main.ui.buttons["Fönster"])
			var gw2: float = main.data.sample_height(4.75, -2.42)
			await _tap(main, Vector3(4.75, gw2 + 1.6, -2.42))
			await _click(main, main.ui.buttons["Fönster"])
			var gw3: float = main.data.sample_height(1.0, -2.6)
			await _tap(main, Vector3(1.0, gw3 + 1.8, -2.6))
			main.brush.ruin_height = 2.0
			await _click(main, main.ui.buttons["Trappa"])
			await _drag(main, [Vector3(-1.4, 0.5, 1.4), Vector3(1.0, 0.5, 1.4)], 20)
			await _click(main, main.ui.buttons["Övervåning"])
			main.brush.radius = 0.9
			var gs: float = main.data.sample_height(0.6, 1.4)
			await _drag(main, [Vector3(0.8, gs + 1.0, 1.4), Vector3(1.8, gs + 1.0, 1.8), Vector3(2.2, gs + 1.0, 2.6)], 30)
			var kinds := []
			for r in main.ruins.records:
				kinds.append(r.kind + ("(%d holes)" % r.get("holes", []).size() if r.kind == "wall" else "") + ("(in wall)" if r.has("wall") else ""))
			print("  pieces: ", kinds)
			if main.args_age >= 0.0:
				main.ruins.set_age(main.args_age)
			main.rig.goal_yaw = view[0]
			main.rig.goal_pitch = view[1]
			main.rig.goal_distance = view[2]
			main.rig.goal_target = view[3]
			main.rig.settle()
		"holes":
			main.rig.goal_yaw = deg_to_rad(20.0)
			main.rig.goal_pitch = deg_to_rad(50.0)
			main.rig.goal_distance = 30.0
			main.rig.goal_target = Vector3(1.5, 0.5, 0.0)
			var view := [deg_to_rad(float(main.args_yaw)), deg_to_rad(8.0), float(main.args_dist), main.args_target]
			main.rig.settle()
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			main.brush.ruin_height = 3.2
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [Vector3(-1.5, 0.5, -2.2), Vector3(2.5, 0.5, -2.8), Vector3(5.5, 0.5, -2.2)], 40)
			main.brush.ruin_height = 2.0
			await _click(main, main.ui.buttons["Valv"])
			await _drag(main, [Vector3(2.4, 0.5, -2.75), Vector3(3.8, 0.5, -2.68)], 20)
			await _click(main, main.ui.buttons["Dörr"])
			await _tap(main, Vector3(-0.4, main.data.sample_height(-0.4, -2.4) + 1.0, -2.4))
			main.brush.ruin_height = 1.2
			await _click(main, main.ui.buttons["Fönster"])
			await _tap(main, Vector3(1.45, main.data.sample_height(1.45, -2.65) + 1.8, -2.65))
			await _tap(main, Vector3(4.75, main.data.sample_height(4.75, -2.42) + 1.6, -2.42))
			var kinds := []
			for r in main.ruins.records:
				kinds.append(r.kind + ("(%d holes)" % r.get("holes", []).size() if r.kind == "wall" else ""))
			print("  pieces: ", kinds)
			if main.args_age >= 0.0:
				main.ruins.set_age(main.args_age)
			main.rig.goal_yaw = view[0]
			main.rig.goal_pitch = view[1]
			main.rig.goal_distance = view[2]
			main.rig.goal_target = view[3]
			main.rig.settle()
		"age_undo":
			await run(main, "holes")
			var slider: HSlider
			for s in main.ui.find_children("*", "HSlider", true, false):
				if s.get_meta("unit", "") == "%" and s.get_parent().get_child(0).text == "Ålder":
					slider = s
			slider.drag_started.emit()
			slider.value = 0.9
			slider.drag_ended.emit(true)
			await _frames(main, 3)
			print("  age after dial: ", main.ruins.age, " shown ", slider.value)
			main.brush.undo()
			await _frames(main, 3)
			print("  age after undo: ", main.ruins.age, " shown ", slider.value)
			main.brush.redo()
			await _frames(main, 3)
			print("  age after redo: ", main.ruins.age, " shown ", slider.value)
		"weather":
			await run(main, "plants")
			main.weather.settle()
			main.ui.tabs.current_tab = 4
			await _frames(main, 3)
		"light":
			main.weather.hour = 17.8
			main.weather.tint_clouds = Color(1.0, 0.72, 0.85)
			main.weather.tint_top = Color(0.85, 0.75, 1.0)
			main.weather.sun_strength = 1.4
			main.weather.clouds = 0.8
			main.rebuild_ui()
			await _frames(main, 2)
			main.ui.tabs.current_tab = 5
			await _frames(main, 3)
		"camera":
			main.rig.spin_speed = 8.0
			main.rig.bob = 2.0
			main.rig.spin_shape[2] = 1.0
			main.rig.spin_shape[6] = 0.6
			main.rig.bob_period = 8.0
			main.rig.focal_mm = 110.0
			main.rig.aperture = 0.8
			main.rebuild_ui()
			await _frames(main, 2)
			main.ui.tabs.current_tab = 6
			await _frames(main, 40)
		"files":
			await run(main, "storey2")
			main.weather.snow = 0.6
			main.weather.settle()
			var path := OS.get_user_data_dir().path_join("test.island")
			var t0 := Time.get_ticks_msec()
			print("  save: ", error_string(main.IslandFile.save(main, path)), " in ", Time.get_ticks_msec() - t0, " ms, ", FileAccess.get_file_as_bytes(path).size() / 1024, " kB")
			var before := [main.props.records.size(), main.ruins.records.size(), main.data.height[8000]]
			# wreck the island, then open it again
			main.data.generate_default(99)
			main.props.restore([])
			main.ruins.restore([[], 0.0])
			main.weather.snow = 0.0
			t0 = Time.get_ticks_msec()
			print("  open: ", error_string(main.IslandFile.open(main, path)), " in ", Time.get_ticks_msec() - t0, " ms")
			var after := [main.props.records.size(), main.ruins.records.size(), main.data.height[8000]]
			print("  before ", before, " after ", after, " snow ", main.weather.snow)
			var still: String = await main.IslandFile.still(main, Vector2i(1920, 1080))
			print("  still: ", still, " ", Image.load_from_file(still).get_size())
		"export":
			main.ui.tabs.current_tab = 6
			await _frames(main, 3)
			var out: String = main.IslandFile.film(main, 2.0, Vector2i(1280, 720), true)
			print("  film: ", out)
		"ff_live":
			main.weather.hour = 23.0
			main.weather.fireflies = 0.05
			await _frames(main, 300)
			main.weather.fireflies = 1.0
			await _frames(main, 300)
		"bigisland":
			for k in 10:
				var a := k * 0.55 - 1.2
				main.data.edit_land(Vector2(cos(a), sin(a)) * 10.0 + Vector2(-2.0, 2.0), 4.5, true)
			main.view.rebuild(main.data.full_rect(), main.data.full_rect())
			main.view.flush()
			main.data.dirty = Rect2i()
			main.data.dirty_shape = Rect2i()
			main._on_ground_changed(main.data.full_rect())
			print("  island centre ", main.rig.island_center, " radius ", main.rig.island_radius)
			await _frames(main, 90)
		"loopmath":
			var r = main.rig
			r.spin_speed = 8.0
			r.spin_vary = 0.5
			r.spin_period = 13.0
			r.spin_shape[2] = 1.0
			r.bob = 1.5
			r.bob_period = 7.0
			var live: Dictionary = r.state()
			var loop: float = r.fit_loop(12.0)
			# integrate the spin over the loop the way _process does
			var turned := 0.0
			var dt := 1.0 / 30.0
			for k in int(round(loop * 30.0)):
				turned += r.spin_now() * dt
				r.spin_phase = fmod(r.spin_phase + dt / r.spin_period, 1.0)
			print("  loop %.2f s, spin period %.2f, bob period %.2f, turned %.2f deg" % [loop, r.spin_period, r.bob_period, turned])
			r.set_state(live)
			var path := OS.get_user_data_dir().path_join("test2.island")
			main.IslandFile.save(main, path)
			r.spin_shape[2] = 0.0
			main.IslandFile.open(main, path)
			print("  shape after open ", main.rig.spin_shape[2], " speed ", main.rig.spin_speed, " clockwise ", main.rig.spin_clockwise)
		"post":
			# fold and unfold the panel by its buttons, then a round trip of the effects through a file
			await _click(main, main.ui.buttons["Göm"])
			await _frames(main, 30)
			print("  folded: ", main.ui.collapsed, " handle ", main.ui.buttons["Visa"].visible, " shift ", main.rig.frame_shift)
			await _click(main, main.ui.buttons["Visa"])
			await _frames(main, 30)
			print("  unfolded: ", not main.ui.collapsed, " shift %.3f" % main.rig.frame_shift)
			var p = main.post
			p.rays = 0.8
			p.volume = 0.4
			p.temperature = 0.5
			p.shadow_tint = Color(0.6, 0.7, 1.0)
			var path := OS.get_user_data_dir().path_join("test3.island")
			main.IslandFile.save(main, path)
			p.reset()
			main.IslandFile.open(main, path)
			print("  after open rays ", p.rays, " volume ", p.volume, " temperature ", p.temperature, " shadow ", p.shadow_tint)
			main.rebuild_ui()
			await _frames(main, 2)
			main.ui.tabs.current_tab = 7
			await _frames(main, 3)
			var still: String = await main.IslandFile.still(main, Vector2i(1280, 720))
			print("  still: ", still)
		"underside", "underside_side", "underside_before":
			# from below: wear the hanging tip away, then draw roots near the coast
			var M = preload("res://scripts/island_mesher.gd")
			var d = main.data
			main.rig.goal_pitch = deg_to_rad(-38.0)
			main.rig.goal_yaw = deg_to_rad(40.0)
			main.rig.settle()
			await _frames(main, 5)
			if name == "underside_before":
				return
			var under := func(x: float, z: float) -> Vector3: return Vector3(x, M.underside(d, x, z), z)
			await _click(main, main.ui.buttons["Sudda under"])
			main.brush.strength = 1.0
			main.brush.radius = 2.6
			var t0 := Time.get_ticks_msec()
			for pass_i in 3:
				await _drag(main, [under.call(-2.0, -1.0), under.call(1.5, 1.0), under.call(-1.0, 1.5), under.call(1.0, -1.5)], 70)
			print("  carve took ", Time.get_ticks_msec() - t0, " ms, deepest underside now %.2f" % M.underside(d, 0.0, 0.0))
			await _click(main, main.ui.buttons["Rötter"])
			main.brush.strength = 0.55
			main.brush.radius = 1.4
			t0 = Time.get_ticks_msec()
			await _drag(main, [under.call(4.0, 3.5), under.call(2.0, 4.8)], 30)
			await _drag(main, [under.call(-3.5, 3.0), under.call(-4.5, 0.5)], 30)
			await _drag(main, [under.call(5.5, 0.5), under.call(5.0, -1.5)], 30)
			print("  roots took ", Time.get_ticks_msec() - t0, " ms, records ", main.roots.records.size(), " anchors ", main.roots.records.map(func(r): return r.anchors.size()))
			var saved: Array = main.roots.snapshot()
			main.roots.restore([])
			var tb := Time.get_ticks_usec()
			main.roots.restore(saved)
			print("  regrowing all %d records: %.1f ms" % [saved.size(), (Time.get_ticks_usec() - tb) / 1000.0])
			if name == "underside_side":
				main.rig.goal_pitch = deg_to_rad(6.0)
				main.rig.settle()
				await _frames(main, 5)
		"roots_ground", "roots_bold", "roots_tangle":
			# roots round the old tree's foot, and some by the coast that tip over
			var d = main.data
			if name == "roots_bold":
				for kv in [["thickness", 2.2], ["length", 4.5], ["bark", 0.8], ["fork_angle", 55.0], ["fork_gap", 0.9], ["max_kids", 2], ["fork_depth", 3]]:
					main.roots.style[kv[0]] = kv[1]
			elif name == "roots_tangle":
				for kv in [["thickness", 1.4], ["length", 4.5], ["branching", 0.8], ["fork_angle", 25.0], ["fork_gap", 0.2], ["max_kids", 3], ["fork_depth", 8]]:
					main.roots.style[kv[0]] = kv[1]
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			await _click(main, main.ui.buttons["Rötter"])
			main.brush.radius = 1.0
			var t0 := Time.get_ticks_msec()
			await _drag(main, [on.call(-2.0, -1.5), on.call(-2.9, -1.4), on.call(-2.5, -2.3)], 25)
			await _drag(main, [on.call(4.6, 3.6), on.call(5.4, 2.4)], 20)
			print("  ground roots took ", Time.get_ticks_msec() - t0, " ms, records ", main.roots.records.size(), " starts ", main.roots.records.map(func(r): return r.anchors.map(func(a): return a[3])))
			if name == "roots_bold":
				var cleared := func() -> int: return Array(main.data.root_mask).filter(func(v): return v > 0.5).size()
				print("  grass cleared on %d grid points" % cleared.call())
				main.brush.undo()
				main.brush.undo()
				print("  after undoing both strokes: %d" % cleared.call())
				main.brush.redo()
				main.brush.redo()
				print("  after redo: %d" % cleared.call())
			if name == "roots_ground":
				var tb := Time.get_ticks_usec()
				main.roots.set_style("thickness", 2.0)
				print("  restyling the last roots: %.1f ms" % ((Time.get_ticks_usec() - tb) / 1000.0))
		"roots_ruins", "roots_climb":
			# ruins first, then roots drawn beside the wall and the pillar
			await run(main, "ruins")
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 0
			await _frames(main, 3)
			var tr := Time.get_ticks_usec()
			main.roots._take_raster()
			print("  raster of the ruins: %.1f ms, wall top at (2.6, -2.2): %.2f" % [(Time.get_ticks_usec() - tr) / 1000.0, main.roots.ruin_top(2.6, -2.2)])
			main.roots.style.thickness = 1.5
			main.roots.style.length = 4.0
			main.roots.style.curl = 0.6
			await _click(main, main.ui.buttons["Rötter"])
			main.brush.radius = 1.0
			if name == "roots_climb":
				main.roots.style.length = 3.0
				await _drag(main, [on.call(1.4, -0.95), on.call(2.3, -1.45)], 20)
			else:
				await _drag(main, [on.call(2.3, -0.6), on.call(3.4, -0.4)], 20)
				await _drag(main, [on.call(0.2, -3.2), on.call(0.4, -3.6)], 10)
			print("  roots: ", main.roots.records.size())
			for seed in main.roots._nodes:
				var bb: AABB = main.roots._nodes[seed].mesh.get_aabb()
				print("  roots reach from %s to %s, anchors %s" % [bb.position, bb.end, main.roots.records[0].anchors])
			if name == "roots_climb":
				for size in [0.5, 2.0]:
					var t0 := Time.get_ticks_usec()
					main.roots.set_style("size", size)
					var bs: AABB = main.roots._nodes.values()[0].mesh.get_aabb()
					print("  size %.1f: spans %.1f x %.1f m, %.0f ms" % [size, bs.size.x, bs.size.z, (Time.get_ticks_usec() - t0) / 1000.0])
				main.roots.set_style("size", 1.0)
		"roots_sizes":
			# three root systems, small, medium and large, then the panel folded away
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			await _click(main, main.ui.buttons["Rötter"])
			main.brush.radius = 0.8
			main.roots.style.thickness = 1.4
			for spec in [[2.0, [-2.2, -1.6], [-2.6, -1.9]], [1.0, [3.6, -0.6], [3.9, -0.9]], [0.5, [1.2, 3.0], [1.35, 2.85]], [0.5, [-2.6, 2.4], [-2.75, 2.25]]]:
				main.roots.style.size = spec[0]
				await _drag(main, [on.call(spec[1][0], spec[1][1]), on.call(spec[2][0], spec[2][1])], 12)
			print("  sizes drawn: ", main.roots.records.map(func(r): return r.style.size))
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"roots_stones", "roots_climb0", "roots_climb1":
			# ruins, the island's boulders and a paved patch, with roots of four
			# sizes drawn beside them
			await run(main, "ruins")
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 0
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Plattor"])
			main.brush.radius = 1.3
			main.brush.strength = 1.0
			await _drag(main, [on.call(2.4, 1.0), on.call(3.6, 1.6)], 25)
			await _click(main, main.ui.buttons["Rötter"])
			main.brush.radius = 0.8
			main.roots.style.thickness = 1.3
			if name != "roots_stones":
				main.roots.style.climb = 0.0 if name == "roots_climb0" else 1.0
			for spec in [[1.6, [1.3, -0.9], [1.7, -1.05]], [1.0, [4.2, 2.7], [4.4, 2.5]], [0.8, [2.8, 1.2], [3.1, 1.3]], [0.5, [-0.3, -2.8], [-0.45, -2.95]], [0.6, [0.3, -3.8], [0.4, -3.65]], [1.2, [2.4, -1.65], [2.8, -1.8]]]:
				main.roots.style.size = spec[0]
				await _drag(main, [on.call(spec[1][0], spec[1][1]), on.call(spec[2][0], spec[2][1])], 12)
			await _frames(main, 10)
			print("  sizes drawn: ", main.roots.records.map(func(r): return r.style.size), " stones rev ", main.props.revision)
			# which root nodes end up inside a ruin or stone, and what were they doing
			var r0 = main.roots
			for rec in r0.records:
				var g: Dictionary = r0.RootBuilder.grow(r0._resolve(rec.anchors), r0._style_of(rec), rec.seed, r0.inside, r0.ground, r0.bare_ground)
				var bad := []
				var ns: PackedVector3Array = g.nodes
				for k in ns.size():
					var p := ns[k]
					var top: float = r0.ruin_top(p.x, p.z)
					var terrain: float = d.sample_height(p.x, p.z)
					if top > terrain + 0.2 and p.y < top - 0.05:
						bad.append("%d y%.2f top%.2f lie%d climb%d r%.2f" % [k, p.y, top, g.lies[k], g.climbs[k], g.radius[k]])
				var up := 0
				for p in ns:
					if r0.ruin_top(p.x, p.z) > d.sample_height(p.x, p.z) + 0.3 and p.y > d.sample_height(p.x, p.z) + 0.3:
						up += 1
				var climbing := 0
				for c in g.climbs:
					climbing += c
				print("  on walls and stones: %d of %d nodes, climbing %d" % [up, ns.size(), climbing])
				print("  size %.1f: %d nodes, %d inside: %s" % [rec.style.size, ns.size(), bad.size(), bad.slice(0, 6)])
				var deep := 0
				var vs: PackedVector3Array = g.v
				for v in vs:
					var top: float = r0.ruin_top(v.x, v.z)
					if top > d.sample_height(v.x, v.z) + 0.2 and v.y < top - 0.05:
						# the real depth: the shortest way out, up or sideways
						var depth: float = top - v.y
						for ring in range(1, 9):
							var out := false
							for s in 16:
								var q := v + Vector3(cos(TAU * s / 16.0), 0.0, sin(TAU * s / 16.0)) * ring * 0.025
								if r0.ruin_top(q.x, q.z) < v.y:
									out = true
							if out:
								depth = minf(depth, ring * 0.025)
								break
						if depth > 0.12:
							deep += 1
				print("    surface points more than 12 cm into stone: %d of %d" % [deep, vs.size()])
				var gaps := []
				for k in ns.size():
					if g.climbs[k] == 1:
						var off: Vector3 = r0.RootBuilder._hug(ns[k], r0.ground, 0.0) - ns[k]
						gaps.append(snappedf(off.length() - g.radius[k], 0.01))
				if not gaps.is_empty():
					print("    climbing nodes, gap between root surface and face: ", gaps.slice(0, 10))
			for rec in main.roots.records:
				print("  starts ", rec.anchors.map(func(a): return "(%.2f %.2f %.2f on %s)" % [a[0], a[1], a[2], a[3]]), " resolved y ", main.roots._resolve(rec.anchors).map(func(r): return snappedf(r[0].y, 0.01)), " terrain ", rec.anchors.map(func(a): return snappedf(d.sample_height(a[0], a[2]), 0.01)))
			for seed in main.roots._nodes:
				var bb: AABB = main.roots._nodes[seed].mesh.get_aabb()
				print("  reaches up to %.2f m" % bb.end.y)
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"boulders":
			# boulders, pebbles gathered round them, and stepping stones along the path
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stenblock"])
			for at in [[-1.2, 1.6], [0.6, 2.2], [-3.4, -0.6]]:
				await _tap(main, on.call(at[0], at[1]))
			await _click(main, main.ui.buttons["Småsten"])
			main.brush.radius = 1.8
			main.brush.density = 0.8
			main.brush.clumping = 0.85
			print("  boulders before pebbles: ", main.props.records.filter(func(r): return r.kind == "stenblock").size())
			var t0 := Time.get_ticks_msec()
			await _drag(main, [on.call(-1.4, 1.2), on.call(0.4, 2.4), on.call(-0.6, 1.6)], 60)
			print("  pebbles: ", main.props.records.filter(func(r): return r.kind == "smasten").size(), " in ", Time.get_ticks_msec() - t0, " ms")
			await _click(main, main.ui.buttons["Trampstenar"])
			main.brush.radius = 0.6
			main.brush.density = 0.8
			main.brush.clumping = 0.0
			await _drag(main, [on.call(2.6, 5.0), on.call(2.4, 2.4), on.call(1.2, 0.2)], 50)
			print("  stepping stones: ", main.props.records.filter(func(r): return r.kind == "trampsten").size())
			print("  boulders left: ", main.props.records.filter(func(r): return r.kind == "stenblock").size())
			for r in main.props.records.filter(func(r): return r.kind == "trampsten"):
				var bb: AABB = main.props._nodes[r.id].mesh.get_aabb()
				print("    slab mesh %s, size %.2f" % [bb.size, r.size])
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"stone_gallery":
			# one boulder per setting, in a row
			var d = main.data
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4
			var looks := [
				{"angular": 0.0, "flat": 0.2, "long": 0.1, "moss": 0.1, "texture": 0.2},
				{"angular": 0.5, "flat": 0.25, "long": 0.2, "moss": 0.5, "texture": 0.5},
				{"angular": 1.0, "flat": 0.2, "long": 0.3, "moss": 0.3, "texture": 0.8},
				{"angular": 0.6, "flat": 0.85, "long": 0.4, "moss": 0.6, "texture": 0.6},
				{"angular": 0.7, "flat": 0.0, "long": 1.0, "moss": 0.9, "texture": 1.0},
			]
			for k in looks.size():
				main.props.begin_stroke()
				for key in looks[k]:
					main.props.style_for("stenblock")[key] = looks[k][key]
				var x := -4.0 + k * 2.0
				main.props.add("stenblock", x, 1.0, rng, 1.4)
			await _frames(main, 5)
		"tree_gallery":
			# the five tree kinds in a row, the island's own tree taken away
			main.props.remove_near(-2.4, -1.8, 1.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var t0 := Time.get_ticks_msec()
			var x := -5.6
			for kind in ["lovtrad", "gran", "krokigt", "torrtrad", "sagotrad"]:
				main.props.add(kind, x, -1.0, rng)
				x += 2.8
			print("  five trees built in ", Time.get_ticks_msec() - t0, " ms")
			await _frames(main, 5)
		"spruce":
			main.props.remove_near(-2.4, -1.8, 1.0)
			var TB = preload("res://scripts/tree_builder.gd")
			var st: Dictionary = main.props.style_for("gran")
			var n: Node3D = TB.build(st, 6.2, 7)
			for c in n.get_children():
				var mi := c as MeshInstance3D
				print("  ", mi.mesh.get_class(), " aabb ", mi.mesh.get_aabb(), " verts ", mi.mesh.surface_get_array_len(0))
			n.free()
			var rng := RandomNumberGenerator.new()
			main.props.add("gran", 0.0, -1.0, rng, 6.2, 7)
			await _frames(main, 5)
		"tree_dials":
			# paint a broadleaf, then drag its dials: the tree just painted follows
			main.props.remove_near(-2.4, -1.8, 1.0)
			var d = main.data
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Lövträd"])
			await _tap(main, Vector3(-1.0, d.sample_height(-1.0, -1.0), -1.0))
			var box: Control = main.ui._kind_dials["lovtrad"]
			print("  tree dials shown: ", box.visible, ", ", box.find_children("*", "HSlider", true, false).size(), " sliders")
			var t0 := Time.get_ticks_usec()
			for kv in [["size", 8.0], ["crown", 1.0], ["angle", 70.0], ["branch_len", 0.8], ["leaf_color", [0.42, 0.62, 0.2]], ["leaves", 0.9], ["fruit", 0.8]]:
				main.props.set_style("lovtrad", kv[0], kv[1])
			print("  restyled six times in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"plant_gallery":
			# every small kind in a row, a few of each
			main.props.remove_near(-2.4, -1.8, 1.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var t0 := Time.get_ticks_msec()
			var kinds := ["buske", "blombuske", "ormbunke", "hogtgras", "blommor", "klover", "svamp"]
			for k in kinds.size():
				var x := -4.2 + k * 1.4
				for n in 3:
					main.props.add(kinds[k], x + rng.randf_range(-0.3, 0.3), 0.4 + n * 0.55, rng)
			print("  21 plants built in ", Time.get_ticks_msec() - t0, " ms")
			await _frames(main, 5)
		"plant_dials":
			# paint each small kind through the panel, then turn its dials
			main.props.remove_near(-2.4, -1.8, 1.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			var plan := [
				["Blommor", 0.0, 1.0, [["petals", 12.0], ["cup", 0.0], ["bloom", 2.2], ["color_b", [0.98, 0.95, 0.9]]]],
				["Svamp", 1.4, 1.0, [["count", 6.0], ["cap_shape", 0.9], ["color_b", [0.6, 0.38, 0.22]], ["spots", 0.0]]],
				["Ormbunke", -1.4, 1.0, [["fronds", 14.0], ["arch", 0.9]]],
				["Högt gräs", 0.0, 2.2, [["lawn", 0.0], ["color_a", [0.75, 0.62, 0.35]], ["heads", 1.0], ["blades", 40.0]]],
			]
			var t0 := Time.get_ticks_usec()
			for p in plan:
				await _click(main, main.ui.buttons[p[0]])
				await _tap(main, on.call(p[1], p[2]))
				for kv in p[3]:
					main.props.set_style(main.brush.place_kind, kv[0], kv[1])
			print("  painted and restyled four kinds in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"together":
			# a broadleaf beside a boulder, two of a kind planted on each other, a
			# spruce beside a wall
			main.props.remove_near(-2.4, -1.8, 1.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Mur"])
			await _drag(main, [on.call(2.4, -2.6), on.call(4.6, -1.6)], 30)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stenblock"])
			main.props.set_style("stenblock", "size", 1.8)
			await _tap(main, on.call(-3.0, 0.6))
			print("  stones: ", main.props.records.filter(func(r): return r.kind == "stenblock").map(func(r): return "(%.1f,%.1f) %.2f" % [r.x, r.z, r.size]))
			print("  can place by stone: ", main.props.can_place("lovtrad", -1.9, 0.4, 1.0, true), " by wall: ", main.props.can_place("gran", 3.1, -1.0, 1.0, true), " occ ", d.sample_occupied(-1.9, 0.4), " sdf ", d.sample_sdf(-1.9, 0.4))
			await _click(main, main.ui.buttons["Lövträd"])
			await _tap(main, on.call(-1.6, 0.5))
			var placed := []
			await _tap(main, on.call(0.2, -1.6))
			await _tap(main, on.call(0.9, -1.4))
			await _click(main, main.ui.buttons["Gran"])
			await _tap(main, on.call(3.5, -0.9))
			print("  trees: ", main.props.records.filter(func(r): return r.kind in main.props.WOODY).map(func(r): return "%s(%.1f,%.1f)" % [r.kind, r.x, r.z]))
			await _frames(main, 10)
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"stone_after":
			# a tree first, then a big boulder right beside it: the tree regrows round it
			main.props.remove_near(-2.4, -1.8, 1.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			var tree: Dictionary = main.props.add("lovtrad", 0.0, -1.0, rng, 5.5, 4)
			await _frames(main, 5)
			var before: Node = main.props._nodes[tree.id]
			var trunk_before: AABB = (before.get_child(0) as MeshInstance3D).mesh.get_aabb()
			main.props.style_for("stenblock").size = 2.0
			main.props.add("stenblock", 1.25, -1.0, rng, 2.0)
			await _frames(main, 5)
			var after: Node = main.props._nodes[tree.id]
			var trunk_after: AABB = (after.get_child(0) as MeshInstance3D).mesh.get_aabb()
			print("  tree rebuilt: ", before != after, ", trunk centre x %.2f -> %.2f" % [trunk_before.get_center().x, trunk_after.get_center().x])
			await _frames(main, 10)
		"kit_pines":
			# the Quaternius pines beside our own, for reference
			main.props.remove_near(-2.4, -1.8, 1.0)
			var Cat = preload("res://scripts/prop_catalog.gd")
			var x := -4.5
			for model in ["Pine_1", "Pine_3", "Pine_5"]:
				var entry: Dictionary = Cat._model(model, 0.2, Color(1, 1, 1, 0), false)
				var mi := MeshInstance3D.new()
				mi.mesh = entry.mesh
				mi.scale = Vector3.ONE * 6.0 / float(entry.height)
				main.add_child(mi)
				mi.position = Vector3(x, main.data.sample_height(x, -1.0), -1.0)
				x += 2.6
			var rng := RandomNumberGenerator.new()
			main.props.add("gran", 3.4, -1.0, rng, 6.0, 3)
			await _frames(main, 5)
		"stack_ghost":
			# three boulders clicked onto each other, then a spruce's ghost under the pointer
			main.props.remove_near(-2.4, -1.8, 1.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stenblock"])
			main.props.set_style("stenblock", "size", 1.6)
			for at in [[0.6, 1.2], [1.3, 1.4], [0.95, 1.25]]:
				await _tap(main, on.call(at[0], at[1]))
				await _frames(main, 3)
			print("  stones: ", main.props.records.filter(func(r): return r.kind == "stenblock" and r.x > 0.0 and r.x < 2.0).map(func(r): return "(%.1f,%.1f) lift %.2f" % [r.x, r.z, r.lift]))
			await _click(main, main.ui.buttons["Gran"])
			_mouse_move(main.rig.camera.unproject_position(on.call(-1.6, -0.6)))
			await _frames(main, 20)
			print("  ghost shown: ", main.brush._ghost != null and main.brush._ghost.visible)
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"showcase":
			# everything new on one island: ruins, a pond, generated trees and
			# plants, stacked stones and roots
			await run(main, "ruins")
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 0
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Vatten"])
			main.brush.radius = 1.3
			await _drag(main, [on.call(-3.8, 2.0), on.call(-3.0, 2.6), on.call(-2.4, 2.2)], 70)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 21
			p.begin_stroke()
			p.style_for("lovtrad").fruit = 0.3
			for at in [[1.4, 4.4], [-0.3, 1.9], [0.4, 2.2]]:
				p.add("lovtrad", at[0], at[1], rng)
			p.add("krokigt", 5.6, 3.2, rng)
			for at in [[-4.9, -0.6], [-0.9, -4.8]]:
				p.add("gran", at[0], at[1], rng)
			p.style_for("stenblock").size = 1.5
			for at in [[2.7, 2.9], [3.3, 3.1], [3.0, 2.95]]:
				p.add("stenblock", at[0], at[1], rng)
			for k in 14:
				var a := rng.randf() * TAU
				p.add("smasten", 3.0 + cos(a) * rng.randf_range(1.0, 1.7), 3.0 + sin(a) * rng.randf_range(1.0, 1.7), rng)
			for at in [[-1.9, 3.7], [-4.7, 3.2]]:
				p.add("buske", at[0], at[1], rng)
			p.add("blombuske", -1.2, 4.6, rng)
			for at in [[-3.7, -3.0], [-1.4, -3.4], [-3.3, -0.6]]:
				p.add("ormbunke", at[0], at[1], rng)
			for at in [[-1.9, -0.8], [-2.9, -1.0]]:
				p.add("svamp", at[0], at[1], rng)
			for k in 10:
				p.add("blommor", rng.randf_range(-0.5, 2.5), rng.randf_range(0.0, 1.6), rng)
			for k in 6:
				p.add("hogtgras", rng.randf_range(-4.8, -2.0), rng.randf_range(1.0, 3.4), rng)
			for k in 5:
				p.add("klover", rng.randf_range(0.5, 3.0), rng.randf_range(-0.3, 1.0), rng)
			# roots from the old tree's foot, crawling out over the ground
			var r = main.roots
			var anchors := []
			for a in [0.4, 2.1, 3.6, 5.0]:
				anchors.append(r.anchor_at(on.call(-2.4 + cos(a) * 0.5, -1.8 + sin(a) * 0.5)))
			r.add(anchors, 77)
			for rec in p.records:
				if rec.kind in p.WOODY:
					var m: Array = p.merge_with(rec)
					print("  %s at (%.1f,%.1f) lean %s" % [rec.kind, rec.x, rec.z, (m[0] as Vector3).snapped(Vector3.ONE * 0.01)])
			main.weather.hour = 16.8
			main.weather.clouds = 0.5
			main.ui.set_collapsed(true)
			await _frames(main, 40)
		"fairy_top":
			var TB = preload("res://scripts/tree_builder.gd")
			var st: Dictionary = main.props.style_for("sagotrad")
			var n: Node3D = TB.build(st, 6.0, 4)
			for c in n.get_children():
				print("  part aabb ", (c as MeshInstance3D).mesh.get_aabb())
			n.free()
			await _frames(main, 5)
		"item_gallery", "item_dusk":
			# every small thing in rows, a pot hung over the fire
			main.props.remove_near(-2.4, -1.8, 1.0)
			main.props.remove_near(0.0, 0.0, 9.0)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			var t0 := Time.get_ticks_msec()
			var rows := [["eldstad", "fackla", "ljus", "lykta", "huggkubbe", "yxa", "vedtrave", "stockhog"],
				["talt", "ryggsack", "koffert", "filt", "spade", "hacka"],
				["flaskor", "bocker", "svampkorg", "tunna", "skylt", "stock", "stubbe"]]
			for r in rows.size():
				var kinds: Array = rows[r]
				for i in kinds.size():
					var x := -4.2 + i * 8.4 / maxf(kinds.size() - 1, 1)
					var z := -2.4 + r * 2.6
					p.add(kinds[i], x, z, rng, -1.0, -1, 0.35)
			p.add("gryta", -4.1, -2.3, rng, -1.0, -1, 0.0)
			print("  %d things in %d ms" % [p.records.size(), Time.get_ticks_msec() - t0])
			if name == "item_dusk":
				main.weather.hour = 19.6
				main.weather.settle()
			await _frames(main, 10)
		"tool_close":
			main.props.remove_near(0.0, 0.0, 9.0)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			p.add("huggkubbe", 0.0, 0.0, rng, -1.0, 1, 0.0)
			p.add("yxa", 1.0, 0.3, rng, -1.0, 1, 0.4)
			p.add("spade", -0.9, 0.2, rng, -1.0, 1, 0.0)
			p.add("hacka", 1.0, -0.6, rng, -1.0, 1, 0.3)
			await _frames(main, 10)
		"tool_studio":
			# the tools alone, standing up in the air in front of the camera
			main.props.remove_near(0.0, 0.0, 9.0)
			var IB = preload("res://scripts/item_builder.gd")
			var cam: Camera3D = main.rig.camera
			var x := -0.9
			for spec in [["spade", "spade", 0.0], ["pick", "hacka", PI * 0.5], ["axe", "yxa", PI * 0.5], ["block", "huggkubbe", 0.0]]:
				var st: Dictionary = main.props.style_for(spec[1])
				var n: Node3D = IB.build(spec[0], st, 3)
				main.add_child(n)
				var fwd := -cam.global_basis.z
				n.global_position = cam.global_position + fwd * 3.2 + cam.global_basis.x * x + Vector3(0, -0.6, 0)
				n.rotation = Vector3(float(spec[2]) if spec[0] != "spade" and spec[0] != "block" else 0.0, cam.global_rotation.y, 0)
				x += 0.65
			await _frames(main, 10)
		"wood_row":
			main.props.remove_near(0.0, 0.0, 9.0)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			p.add("stubbe", -2.2, 0.0, rng, 1.6, 2, 0.3)
			p.add("stock", 0.6, -0.4, rng, 1.0, 2, 0.15)
			p.add("huggkubbe", 2.8, 0.3, rng, 1.0, 1, 0.0)
			p.add("vedtrave", -1.2, -2.2, rng, 1.0, 1, 0.0)
			p.add("stockhog", 1.6, -2.2, rng, 1.0, 1, 0.0)
			await _frames(main, 10)
		"wood_stump", "wood_log", "wood_block", "wood_pile", "wood_logs", "wood_stumptop":
			# one wood thing alone in front of the camera, everything sharp
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.aperture = 0.0
			main.weather.hour = 15.0
			var IB = preload("res://scripts/item_builder.gd")
			var kind: String = {"wood_stumptop": "stubbe", "wood_stump": "stubbe", "wood_log": "stock", "wood_block": "huggkubbe", "wood_pile": "vedtrave", "wood_logs": "stockhog"}[name]
			var gen: String = {"wood_stumptop": "stump", "wood_stump": "stump", "wood_log": "log", "wood_block": "block", "wood_pile": "woodpile", "wood_logs": "logpile"}[name]
			var dist: float = {"wood_stumptop": 1.4, "wood_stump": 2.6, "wood_log": 3.4, "wood_block": 2.0, "wood_pile": 2.6, "wood_logs": 2.0}[name]
			var n: Node3D = IB.build(gen, main.props.style_for(kind), 4)
			main.add_child(n)
			var cam: Camera3D = main.rig.camera
			var fwd := -cam.global_basis.z
			var at := cam.global_position + fwd * dist
			n.global_position = at - Vector3(0, 0.35 if name != "wood_stumptop" else 0.75, 0)
			n.rotation.y = cam.global_rotation.y + 0.5
			await _frames(main, 10)
		"studio":
			# things in a row in front of the camera, everything sharp: --kinds=a,b,c
			# (catalog kinds), --gap= metres between them, --turn= degrees
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.aperture = 0.0
			main.weather.hour = 15.0
			var kinds: Array = ["tunna"]
			var gap := 0.7
			var spin := 0.5
			var dist := 2.4
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--kinds="):
					kinds = a.substr(8).split(",")
				elif a.begins_with("--gap="):
					gap = float(a.substr(6))
				elif a.begins_with("--turn="):
					spin = deg_to_rad(float(a.substr(7)))
				elif a.begins_with("--near="):
					dist = float(a.substr(7))
				elif a.begins_with("--set="):
					var kv: PackedStringArray = a.substr(6).split(":")
					for kind in kinds:
						main.props.style_for(kind)[kv[0]] = float(kv[1])
			var cam: Camera3D = main.rig.camera
			var fwd := -cam.global_basis.z
			var x := -gap * (kinds.size() - 1) * 0.5
			for kind in kinds:
				var rec := {"id": -1, "kind": kind, "x": 0.0, "z": 0.0, "rot": 0.0, "variant": 4, "hue": 0.5, "jit": 0.0}
				rec.style = main.props.style_for(kind).duplicate(true)
				rec.size = float(rec.style.size)
				var n: Node3D = Catalog.build(rec)
				main.add_child(n)
				n.global_position = cam.global_position + fwd * dist + cam.global_basis.x * x - Vector3(0, 0.45, 0)
				n.rotation.y = cam.global_rotation.y + spin
				x += gap
			await _frames(main, 10)
		"tool_lean":
			# tools set down by things lean on them; out in the open they lie flat
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.aperture = 0.0
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 4
			p.add("stubbe", 0.0, 0.0, rng, -1.0, 2, 0.3)
			p.add("tunna", 2.0, 0.2, rng, -1.0, 1, 0.0)
			p.add("koffert", -2.0, 0.6, rng, -1.0, 1, 0.4)
			p.add("lovtrad", 1.0, -2.6, rng)
			await _frames(main, 3)
			# [kind, foot x, z, what it leans toward x, z]
			var spots := [["spade", 0.75, 0.55, 0.0, 0.0], ["hacka", 2.0, 1.0, 2.0, 0.2], ["yxa", -2.0, 1.25, -2.0, 0.6],
				["spade", 1.0, -1.9, 1.0, -2.6], ["yxa", -1.0, -1.2, -1.0, -2.2], ["hacka", 3.0, -1.4, 3.0, -2.6], ["spade", -2.8, -1.0, -2.8, -2.4]]
			for s in spots:
				var rot := atan2(-(float(s[3]) - float(s[1])), -(float(s[4]) - float(s[2])))
				p.add(s[0], s[1], s[2], rng, -1.0, 1, rot)
			await _frames(main, 5)
			for r in p.records:
				if r.kind in p.TOOLS:
					var n: Node3D = p._nodes[r.id]
					var up: Vector3 = n.global_basis.y.normalized()
					print("  %s at (%.1f,%.1f): %.0f degrees up" % [r.kind, r.x, r.z, rad_to_deg(asin(clampf(up.y, -1.0, 1.0)))])
			main.ui.set_collapsed(true)
			await _frames(main, 20)
		"ghost_match":
			# the ghost shows what a click puts down: a spade leaning on a stump,
			# a tree bending away from a boulder, turned with Q and E
			main.props.remove_near(0.0, 0.0, 9.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			p.add("stubbe", 0.0, 0.0, rng, -1.0, 2, 0.3)
			p.style_for("stenblock").size = 1.6
			p.add("stenblock", 2.0, 0.0, rng, -1.0, 3, 0.0)
			main.ui.tabs.current_tab = 3
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Spade"])
			var cam_yaw: float = main.rig.camera.global_rotation.y
			# the spade's foot in front of the stump, as seen from the camera
			var foot: Vector3 = on.call(-sin(cam_yaw) * 0.6, -cos(cam_yaw) * 0.6)
			foot = on.call(-foot.x, -foot.z)
			main.brush.turn = 0.0
			_mouse_move(main.rig.camera.unproject_position(foot))
			await _frames(main, 6)
			var g: Node3D = main.brush._ghost
			print("  spade ghost %.0f degrees up" % rad_to_deg(asin(g.global_basis.y.normalized().y)))
			await _tap(main, foot)
			await _frames(main, 3)
			for r in p.records:
				if r.kind == "spade":
					print("  spade placed %.0f degrees up" % rad_to_deg(asin((p._nodes[r.id] as Node3D).global_basis.y.normalized().y)))
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Lövträd"])
			for turn in [0.0, 90.0]:
				main.brush.turn = turn
				var at: Vector3 = on.call(1.1, 0.4 + turn / 180.0)
				_mouse_move(main.rig.camera.unproject_position(at))
				await _frames(main, 8)
				var gt: Node3D = main.brush._ghost
				var gbox: AABB = gt.global_transform * (gt.get_child(0) as MeshInstance3D).mesh.get_aabb()
				await _tap(main, at)
				await _frames(main, 3)
				var last: Dictionary = p.records[p.records.size() - 1]
				var tn: Node3D = p._nodes[last.id]
				var tbox: AABB = tn.global_transform * (tn.get_child(0) as MeshInstance3D).mesh.get_aabb()
				print("  tree turned %d: ghost crown centre %s, placed %s" % [turn, (gbox.get_center() - at).snapped(Vector3.ONE * 0.01), (tbox.get_center() - at).snapped(Vector3.ONE * 0.01)])
			main.ui.set_collapsed(true)
			await _frames(main, 20)
		"camp":
			# a little camp of the restyled things, tools leaning where they were put
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.aperture = 0.0
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 12
			var lean := func(kind: String, x: float, z: float, tx: float, tz: float) -> void:
				p.add(kind, x, z, rng, -1.0, 1, atan2(-(tx - x), -(tz - z)))
			p.add("talt", -2.6, -1.6, rng, -1.0, 1, 0.5)
			p.add("eldstad", 0.0, 0.0, rng, -1.0, 1, 0.0)
			p.add("gryta", 0.0, 0.0, rng, -1.0, 1, 0.0)
			p.add("tunna", 1.7, -1.2, rng, -1.0, 1, 0.0)
			lean.call("hacka", 1.75, -0.45, 1.7, -1.2)
			p.add("huggkubbe", 2.4, 0.9, rng, -1.0, 1, 0.3)
			p.add("stubbe", -1.6, 1.4, rng, -1.0, 2, 0.5)
			lean.call("spade", -1.0, 1.75, -1.6, 1.4)
			p.add("koffert", -0.3, -1.9, rng, -1.0, 1, 0.2)
			lean.call("yxa", 0.3, -1.25, -0.2, -1.8)
			p.add("stockhog", 3.2, -2.2, rng, -1.0, 1, 0.4)
			p.add("skylt", 0.9, 2.4, rng, -1.0, 1, 2.6)
			p.add("svampkorg", -0.9, 0.6, rng, -1.0, 1, 0.3)
			p.add("bocker", 0.9, -0.6, rng, -1.0, 1, 0.8)
			p.add("flaskor", 1.25, -0.9, rng, -1.0, 1, 0.0)
			p.add("lykta", -1.9, -0.2, rng, -1.0, 1, 0.0)
			p.style_for("stenblock").size = 1.3
			p.add("stenblock", -3.6, 1.0, rng, -1.0, 7, 0.0)
			p.add("stenblock", -3.0, 1.6, rng, -1.0, 9, 0.0)
			for k in 10:
				var a := rng.randf() * TAU
				p.add("smasten", -3.3 + cos(a) * rng.randf_range(0.9, 1.6), 1.3 + sin(a) * rng.randf_range(0.9, 1.6), rng)
			p.add("ryggsack", -1.4, -0.6, rng, -1.0, 1, 0.9)
			main.weather.hour = 16.5
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"berg":
			# a hill raised, then Berg painted over it with the brush: an outcrop of
			# boulder stones that sits on the slope, and how smooth the stroke ran
			main.props.remove_near(0.0, 0.0, 9.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			for k in 14:
				d.edit_height(Vector2(1.2, 1.2), 1.4, 0.12)
			main.view.rebuild(d.dirty, d.dirty_shape)
			d.dirty = Rect2i()
			d.dirty_shape = Rect2i()
			main.view.flush()
			main.props.follow_ground()
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Berg"])
			main.brush.radius = 1.6
			await _drag(main, [on.call(-0.6, 0.4), on.call(1.2, 1.4), on.call(2.6, 1.0)], 60)
			await _frames(main, 10)
			var layers := 1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--layers="):
					layers = int(a.substr(9))
			for l in layers - 1:
				await _drag(main, [on.call(-0.3, 0.6), on.call(1.2, 1.2), on.call(2.2, 1.0)], 50)
				await _frames(main, 10)
			var top_lift := 0.0
			for rr in main.props.records:
				if rr.kind == "berg":
					top_lift = maxf(top_lift, float(rr.get("lift", 0.0)))
			print("  highest rock layer lifted %.2f m" % top_lift)
			print("  rock stones: %d" % main.props.records.filter(func(r): return r.kind == "berg").size())
			main.ui.set_collapsed(true)
			await _frames(main, 20)
		"rock_time":
			# how long a stone's shape takes to build, and the roots' raster after it
			var RB = preload("res://scripts/rock_builder.gd")
			for kind in ["berg", "stenblock", "smasten"]:
				var st: Dictionary = main.props.style_for(kind)
				var t0 := Time.get_ticks_usec()
				for v in 3:
					RB.mesh(st, 500 + v, int(Catalog.KINDS[kind].detail))
				print("  %s: %.0f ms a shape" % [kind, (Time.get_ticks_usec() - t0) / 3000.0])
			var rng := RandomNumberGenerator.new()
			for v in [3, 3, 7]:
				var ta := Time.get_ticks_usec()
				main.props.add("berg", 1.0 + v * 0.3, 1.0, rng, -1.0, v)
				var tb := Time.get_ticks_usec()
				await _frames(main, 1)
				print("  add berg variant %d: %.0f ms, next frame %.0f ms" % [v, (tb - ta) / 1000.0, (Time.get_ticks_usec() - tb) / 1000.0])
			main.props.add("berg", 1.0, 1.0, rng)
			var t1 := Time.get_ticks_usec()
			main.roots.ensure_raster()
			print("  raster after a stone: %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
		"stones_under":
			# boulders clicked onto the cliff and the underside from below, then a
			# brush of pebbles strewn under the island
			main.props.remove_near(0.0, 0.0, 9.0)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stenblock"])
			var vp: Vector2 = main.get_viewport().get_visible_rect().size
			for at in [Vector2(0.58, 0.5), Vector2(0.64, 0.62), Vector2(0.55, 0.68)]:
				var hit: Dictionary = main.brush.pick(vp * at)
				print("  pick %s: side %s" % [at, hit.get("side", false)])
				if not hit.is_empty():
					await _tap(main, hit.pos)
					await _frames(main, 3)
			await _click(main, main.ui.buttons["Småsten"])
			main.brush.radius = 1.4
			var a: Dictionary = main.brush.pick(vp * Vector2(0.5, 0.72))
			var b: Dictionary = main.brush.pick(vp * Vector2(0.62, 0.75))
			if not a.is_empty() and not b.is_empty():
				await _drag(main, [a.pos, b.pos], 40)
			print("  on the body: %d" % main.props.records.filter(func(r): return r.get("side", false)).size())
			main.ui.set_collapsed(true)
			await _frames(main, 20)
		"roots_close":
			# a tree with no moss, roots drawn round its foot, seen close: what
			# colours the roots
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.aperture = 0.0
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			p.style_for("lovtrad").moss = 0.0
			var root_moss := 0.0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--treemoss="):
					p.style_for("lovtrad").moss = float(a.substr(11))
				elif a.begins_with("--rootmoss="):
					root_moss = float(a.substr(11))
			p.add("lovtrad", 0.0, 0.0, rng)
			var r = main.roots
			r.style["moss"] = root_moss
			if "--userroots" in OS.get_cmdline_user_args():
				for kv in [["size", 0.39], ["length", 1.0], ["spread", 2.1], ["thickness", 3.0], ["fork_gap", 1.5], ["fork_angle", 24.0], ["bark", 0.0]]:
					r.style[kv[0]] = kv[1]
			var anchors := []
			for a in [0.3, 1.9, 3.4, 4.8]:
				anchors.append(r.anchor_at(on.call(cos(a) * 0.3, sin(a) * 0.3)))
			r.add(anchors, 77)
			if "--erase" in OS.get_cmdline_user_args():
				await _frames(main, 5)
				var t0 := Time.get_ticks_msec()
				r.remove_near(on.call(0.9, 0.3), 0.35)
				print("  rubbed out in %d ms, cuts: %s" % [Time.get_ticks_msec() - t0, r.records.map(func(x): return x.get("cuts", []).size())])
			main.weather.hour = 14.0
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"cam_reset":
			# the camera moved away, then the reset button brings it back
			var r = main.rig
			r.goal_yaw = deg_to_rad(200.0)
			r.goal_pitch = deg_to_rad(-10.0)
			r.goal_distance = 20.0
			r.goal_target = Vector3(4.0, 0.0, -3.0)
			main.ui.tabs.current_tab = 6
			await _frames(main, 60)
			await _click(main, main.ui.buttons["Återställ kameran"])
			await _frames(main, 120)
			print("  after reset: yaw %.0f pitch %.0f zoom %.0f target %s" % [rad_to_deg(r.yaw), rad_to_deg(r.pitch), r.distance, r.target.snapped(Vector3.ONE * 0.1)])
		"cam_preset":
			# a camera preset chosen in the dropdown: --preset=n
			var n := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--preset="):
					n = int(a.substr(9))
			main.ui.tabs.current_tab = 6
			await _frames(main, 3)
			var menu: OptionButton = main.ui.buttons["Kameravy"]
			menu.select(n)
			menu.item_selected.emit(n)
			await _frames(main, 150)
			print("  %s: focal %.0f, sliders follow: %s" % [menu.get_item_text(n), main.rig.focal_mm, is_equal_approx(main.ui._cam_sliders.focal.value, main.rig.focal_mm)])
		"big_island":
			# a wide island drawn with the land brush in small circles: its
			# underside should hang deep in proportion
			var d = main.data
			for gx in range(-11, 12, 2):
				for gz in range(-7, 8, 2):
					d.edit_land(Vector2(gx, gz), 2.2, true)
			var t0 := Time.get_ticks_usec()
			d.refresh_inland()
			print("  inland measured in %.1f ms, deepest %.1f m inland" % [(Time.get_ticks_usec() - t0) / 1000.0, Array(d.inland).max()])
			main.view.rebuild(d.dirty, d.dirty_shape)
			d.dirty = Rect2i()
			d.dirty_shape = Rect2i()
			main.view.flush()
			main.props.follow_ground()
			main.ui.set_collapsed(true)
			await _frames(main, 60)
		"cliff_trees":
			# trees at the rim and down the cliff, leaning out more the lower
			# they grow; looked at from the side
			main.props.remove_near(0.0, 0.0, 12.0)
			var d = main.data
			var p = main.props
			var rng := RandomNumberGenerator.new()
			rng.seed = 8
			var a0 := deg_to_rad(200.0)
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--dir="):
					a0 = deg_to_rad(float(arg.substr(6)))
			for k in 3:
				var a := a0 + (k - 1) * 0.35
				var dir := Vector2(cos(a), sin(a))
				var q := Vector2.ZERO
				while d.sample_sdf(q.x, q.y) > 0.25:
					q += dir * 0.05
				var depth: float = [0.0, 0.45, 1.0][k]
				if depth == 0.0:
					var rec: Dictionary = p.add("lovtrad", q.x, q.y, rng)
					print("  rim tree lean %s" % rec.get("cliff_lean", Vector3.ZERO))
					continue
				# down the cliff: march in from outside at that depth until the body
				var y: float = d.sample_height(q.x, q.y) - depth
				var s := Vector3(q.x, y, q.y) + Vector3(dir.x, 0, dir.y) * 2.0
				var hit := Vector3.INF
				for step in 80:
					var t := s - Vector3(dir.x, 0, dir.y) * step * 0.05
					if main.roots.inside(t):
						hit = t
						break
				if hit != Vector3.INF:
					var rec: Dictionary = p.place_side("lovtrad", hit, main.brush._body_normal(hit), rng)
					print("  cliff tree %.1f m down, lean %s" % [depth, (rec.cliff_lean as Vector3).snapped(Vector3.ONE * 0.01)])
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"tree_depth":
			# pointing ever lower down the cliff with a tree chosen: it never
			# goes deeper than the most a tree may hang
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Lövträd"])
			var vp: Vector2 = main.get_viewport().get_visible_rect().size
			var worst := 0.0
			var sides := 0
			for k in 30:
				var hit: Dictionary = main.brush.pick(vp * Vector2(0.62, 0.4 + k * 0.015))
				if hit.get("side", false):
					sides += 1
					var p: Vector3 = hit.pos
					worst = maxf(worst, main.data.sample_height(p.x, p.z) - p.y)
			print("  %d picks on the cliff, deepest %.2f m under the top" % [sides, worst])
		"water_rock":
			# Berg painted, then a pond dug in the middle of it; stones clicked into
			# the water; a tree at the water's edge
			main.props.remove_near(0.0, 0.0, 9.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Berg"])
			main.brush.radius = 2.2
			await _drag(main, [on.call(0.0, 0.5), on.call(2.5, 1.0)], 50)
			var rocks_before: int = main.props.records.filter(func(r): return r.kind == "berg").size()
			main.ui.tabs.current_tab = 0
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Vatten"])
			main.brush.radius = 1.0
			await _drag(main, [on.call(1.0, 0.7), on.call(1.6, 0.9)], 40)
			await _frames(main, 10)
			print("  rock stones %d before the pond, %d after; water at (1.3,0.8): %.2f" % [rocks_before, main.props.records.filter(func(r): return r.kind == "berg").size(), d.sample_water(1.3, 0.8)])
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stenblock"])
			await _tap(main, on.call(1.3, 0.8))
			print("  boulder in the water: %s" % main.props.records.any(func(r): return r.kind == "stenblock"))
			await _click(main, main.ui.buttons["Lövträd"])
			# at the pond's edge, out from its middle
			var q := Vector2(1.3, 0.8)
			while d.sample_water(q.x, q.y) > 0.15:
				q += Vector2(-0.6, -0.8) * 0.05
			await _tap(main, on.call(q.x, q.y))
			for r in main.props.records:
				if r.kind == "lovtrad":
					print("  tree at the water: lean %s" % (r.get("cliff_lean", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01))
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"storey_holes":
			# the ruins, then the ghost of a door hovering over a wall, and a door
			# and a window clicked into the walls under a storey
			await run(main, "openings")
			main.rig.goal_yaw = deg_to_rad(float(main.args_yaw))
			main.rig.goal_pitch = deg_to_rad(14.0)
			main.rig.goal_distance = 22.0
			main.rig.goal_target = Vector3(1.5, 0.5, 1.5)
			main.rig.settle()
			await _frames(main, 5)
			var storey: Dictionary = {}
			for r in main.ruins.records:
				if r.kind == "floor" and r.raised:
					storey = r
			var walls: Array = main.ruins._floor_walls(storey)
			walls.sort_custom(func(a, b): return a[0].distance_to(a[1]) > b[0].distance_to(b[1]))
			print("  storey walls: %d, longest %.1f m" % [walls.size(), walls[0][0].distance_to(walls[0][1])])
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			for spec in [["Dörr", 0, 0.5, 0.8], ["Fönster", 1 if walls.size() > 1 else 0, 0.5, 1.4]]:
				await _click(main, main.ui.buttons[spec[0]])
				var w: PackedVector2Array = walls[spec[1]]
				var mid: Vector2 = w[0].lerp(w[1], spec[2])
				var foot: float = main.ruins._hole_foot(storey, mid)
				_mouse_move(main.rig.camera.unproject_position(Vector3(mid.x, foot + spec[3], mid.y)))
				await _frames(main, 4)
				var g: MeshInstance3D = main.brush._hole_ghost
				print("  %s ghost shown: %s" % [spec[0], g != null and g.visible])
				await _tap(main, Vector3(mid.x, foot + spec[3], mid.y))
				await _frames(main, 3)
			print("  holes in the storey: %d" % storey.get("holes", []).size())
			# the ghost left showing on another of the storey's walls
			await _click(main, main.ui.buttons["Dörr"])
			var w2: PackedVector2Array = walls[2 if walls.size() > 2 else 0]
			var m2: Vector2 = w2[0].lerp(w2[1], 0.5)
			_mouse_move(main.rig.camera.unproject_position(Vector3(m2.x, main.ruins._hole_foot(storey, m2) + 0.8, m2.y)))
			await _frames(main, 10)
		"square_storey":
			# a storey painted with the square brush along a straight Shift-free
			# stroke on a pillar, a door clicked into one of its walls, and the
			# ghost of a window over another
			main.props.remove_near(0.0, 0.0, 9.0)
			main.rig.goal_yaw = deg_to_rad(float(main.args_yaw))
			main.rig.goal_pitch = deg_to_rad(16.0)
			main.rig.goal_distance = 24.0
			main.rig.goal_target = Vector3(1.0, 1.0, 1.0)
			main.rig.settle()
			main.ui.tabs.current_tab = 2
			await _frames(main, 3)
			var d = main.data
			main.brush.ruin_height = 2.4
			await _click(main, main.ui.buttons["Pelare"])
			var gp: float = d.sample_height(0.0, 1.0)
			await _tap(main, Vector3(0.0, gp, 1.0))
			main.ui.buttons["Fyrkantig pensel"].button_pressed = true
			await _click(main, main.ui.buttons["Övervåning"])
			main.brush.radius = 1.0
			await _drag(main, [Vector3(0.0, gp + 0.6, 1.0), Vector3(1.0, gp + 2.3, 1.0), Vector3(2.2, gp + 2.3, 1.0)], 30)
			await _frames(main, 5)
			var storey: Dictionary = {}
			for r in main.ruins.records:
				if r.kind == "floor" and r.raised:
					storey = r
			if storey.is_empty():
				print("  no storey")
				return
			var walls: Array = main.ruins._floor_walls(storey)
			print("  storey walls: %s" % [walls.map(func(w): return "%.1f m" % w[0].distance_to(w[1]))])
			walls.sort_custom(func(a, b): return a[0].distance_to(a[1]) > b[0].distance_to(b[1]))
			var cam: Vector3 = main.rig.camera.global_position
			# the long walls facing the camera
			var c2 := Vector2(cam.x, cam.z)
			var long: Array = walls.filter(func(w): return w[0].distance_to(w[1]) >= 1.9 and ((w[0] + w[1]) * 0.5).distance_to(Vector2(1.1, 1.0)) < 2.2)
			long.sort_custom(func(a, b): return c2.distance_to((a[0] + a[1]) * 0.5) < c2.distance_to((b[0] + b[1]) * 0.5))
			var w0: PackedVector2Array = long[0] if not long.is_empty() else walls[0]
			var m0: Vector2 = w0[0].lerp(w0[1], 0.35)
			await _click(main, main.ui.buttons["Dörr"])
			await _tap(main, Vector3(m0.x, main.ruins._hole_foot(storey, m0) + 0.8, m0.y))
			await _frames(main, 5)
			print("  holes in the storey: %d" % storey.get("holes", []).size())
			await _click(main, main.ui.buttons["Fönster"])
			var m1: Vector2 = w0[0].lerp(w0[1], 0.8)
			_mouse_move(main.rig.camera.unproject_position(Vector3(m1.x, main.ruins._hole_foot(storey, m1) + 1.2, m1.y)))
			await _frames(main, 10)
			print("  window ghost shown: %s at %s, screen %s, wall %.1f m" % [main.brush._hole_ghost.visible, main.brush._hole_ghost.global_position.snapped(Vector3.ONE * 0.01), main.rig.camera.unproject_position(main.brush._hole_ghost.global_position).round(), w0[0].distance_to(w0[1])])
			await RenderingServer.frame_post_draw
			main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://shots/sq_ghost.png"))
		"paint_over":
			# flowers painted over a bush and stones: they are taken away, flowers
			# stay where they were; then the ghost of a boulder over a tree
			main.props.remove_near(0.0, 0.0, 9.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			var p = main.props
			var rng := RandomNumberGenerator.new()
			p.add("buske", 0.0, 1.0, rng)
			p.add("stenblock", 1.2, 1.4, rng)
			p.add("lovtrad", -2.0, -1.0, rng)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			print("  before: ", p.records.map(func(r): return r.kind))
			# a click puts a boulder over the bush; a brush of ferns runs past the stone
			await _click(main, main.ui.buttons["Stenblock"])
			await _tap(main, on.call(0.0, 1.0))
			await _click(main, main.ui.buttons["Ormbunke"])
			main.brush.radius = 1.0
			await _drag(main, [on.call(1.2, 0.6), on.call(1.8, 1.9)], 40)
			var kinds := {}
			for r in p.records:
				kinds[r.kind] = kinds.get(r.kind, 0) + 1
			print("  after painting flowers over: ", kinds)
			await _click(main, main.ui.buttons["Stenblock"])
			_mouse_move(main.rig.camera.unproject_position(on.call(-2.0, -1.0)))
			await _frames(main, 10)
			print("  ghost over the tree says: ", ["fits", "replaces", "impossible"][p.place_check("stenblock", -2.0, -1.0, 1.0, true)])
		"close_click":
			# logs clicked down close round a stump, turned with Q and E
			main.props.remove_near(0.0, 0.0, 9.0)
			var d = main.data
			var on := func(x: float, z: float) -> Vector3: return Vector3(x, d.sample_height(x, z), z)
			main.ui.tabs.current_tab = 1
			await _frames(main, 3)
			await _click(main, main.ui.buttons["Stubbe"])
			await _tap(main, on.call(0.0, 0.0))
			await _click(main, main.ui.buttons["Stock"])
			var spots := [[0.75, 0.0, 0.0], [-0.2, 0.8, 60.0], [-0.6, -0.7, 120.0]]
			for sp in spots:
				main.brush.turn = sp[2]
				await _tap(main, on.call(sp[0], sp[1]))
			var cam_yaw := rad_to_deg(main.rig.camera.global_rotation.y)
			print("  placed: ", main.props.records.map(func(r): return "%s rot %.0f" % [r.kind, fposmod(rad_to_deg(r.rot) - cam_yaw, 360.0)]))
			main.ui.set_collapsed(true)
			await _frames(main, 30)
		"hover":
			await _click(main, main.ui.buttons["Mossa"])
			_mouse_move(main.rig.camera.unproject_position(Vector3(1.5, 0.6, 1.5)))
			await _frames(main, 5)
		_:
			push_error("unknown test " + name)
	# park the pointer in the sky so the brush ring stays out of the picture
	if name != "hover" and name != "stack_ghost" and name != "paint_over":
		_mouse_move(Vector2(8, 8))
		await _frames(main, 2)


static func _sculpt(main: Node) -> void:
	main.view.profile = true
	var t0 := Time.get_ticks_usec()
	# draw a peninsula out into the air
	await _click(main, main.ui.buttons["Rita land"])
	await _drag(main, [Vector3(5.5, 0, -4.5), Vector3(8.0, 0, -6.5), Vector3(10.0, 0, -6.0)], 50)
	# raise a hill on it
	await _click(main, main.ui.buttons["Höj"])
	await _drag(main, [Vector3(8.2, 0.2, -6.2), Vector3(8.6, 0.2, -6.0)], 90)
	# a sandy cove and a stone patch
	await _click(main, main.ui.buttons["Sand"])
	await _drag(main, [Vector3(0.5, 0.5, 4.0), Vector3(-2.0, 0.5, 5.0)], 50)
	await _click(main, main.ui.buttons["Plattor"])
	await _drag(main, [Vector3(2.0, 0.8, -3.0), Vector3(3.5, 0.8, -2.5)], 40)
	# bite a notch out of the far coast
	await _click(main, main.ui.buttons["Sudda land"])
	await _drag(main, [Vector3(-6.5, 0, -2.0), Vector3(-5.2, 0, -3.5)], 30)
	print("test strokes took ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")


## A single click on the island at a world point.
static func _tap(main: Node, at: Vector3) -> void:
	await _drag(main, [at, at], 2)


static func _frames(main: Node, n: int) -> void:
	for k in n:
		await main.get_tree().process_frame


static func _click(main: Node, control: Control) -> void:
	var at := control.get_global_rect().get_center()
	_mouse_move(at)
	await _frames(main, 2)
	_mouse_button(at, true)
	_mouse_button(at, false)
	await _frames(main, 2)


## Press at the first point, move through the rest over `frames` frames,
## release. Points are world positions projected to the screen.
static func _drag(main: Node, points: Array, frames: int) -> void:
	var cam: Camera3D = main.rig.camera
	var screen: Array[Vector2] = []
	for p in points:
		screen.append(cam.unproject_position(p))
	_mouse_move(screen[0])
	await _frames(main, 2)
	_mouse_button(screen[0], true)
	var worst := 0.0
	for f in frames:
		var t := float(f) / maxf(frames - 1, 1) * (screen.size() - 1)
		var seg := mini(int(t), screen.size() - 2)
		var at := screen[seg].lerp(screen[seg + 1], t - seg)
		_mouse_move(at)
		var before := Time.get_ticks_usec()
		await main.get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - before) / 1000.0)
	_mouse_button(screen[-1], false)
	await _frames(main, 3)
	print("  stroke worst frame ", worst, " ms")


static func _mouse_move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


static func _mouse_button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
