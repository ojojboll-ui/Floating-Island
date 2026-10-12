extends Node3D
## Sky, light and weather round the island.
##
## The hour sets the sun and the moon; their heights pick the sky's colours
## from a few key moments (night, blue hour, sunrise, day). The moon has its
## phase and lights the island at night by how full it is. Clouds, fog,
## rain, snow, wind-blown leaves and fireflies each have their own amount.
##
## Rain and snow fall through the whole scene and stop on the island where
## they hit it (a height field camera looks down at it); past the edge they
## fall on into the sky. The island's own surfaces read three shader globals:
## snow_cover and wetness, which build up and fade over time, and
## wind_strength.

const IslandData := preload("res://scripts/island_data.gd")

# what the panel sets
var hour := 14.0
var moon_phase := 0.5
var clouds := 0.45
var fog := 0.0
var rain := 0.0
var snow := 0.0
var wind := 0.35
var fireflies := 0.6
var time_flows := false

# the Ljus tab: tints laid over the hour's colours (white leaves them be),
# and multipliers on the light
var tint_top := Color.WHITE
var tint_horizon := Color.WHITE
var tint_bottom := Color.WHITE
var tint_clouds := Color.WHITE
var tint_sun := Color.WHITE
var tint_fog := Color.WHITE
var sun_strength := 1.0
var ambient := 1.0
var exposure := 1.0
var saturation := 1.0

const SETTINGS := ["hour", "moon_phase", "clouds", "fog", "rain", "snow", "wind", "fireflies", "time_flows",
	"tint_top", "tint_horizon", "tint_bottom", "tint_clouds", "tint_sun", "tint_fog",
	"sun_strength", "ambient", "exposure", "saturation"]

const DAY_SECONDS := 240.0       # one turn of the clock when time flows
const MOON_DAYS := 8.0           # days from full moon to full moon

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var night := 0.0                 # 0 day .. 1 deep night, for anyone who asks

var _cloud_mat: ShaderMaterial
var _cloud_holder: Node3D
var _clouds: Array[Node3D] = []
var _fog_volume: FogVolume
var _fog_mat: ShaderMaterial
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _snow: GPUParticles3D
var _leaves: GPUParticles3D
var _flies: GPUParticles3D
var _fly_mat: StandardMaterial3D
var _collision: GPUParticlesCollisionHeightField3D
var _wet := 0.0
var _snow_cover := 0.0
var _data
var _props
var hold_clouds := false   # a looping film keeps them where they are
var island_rig   # the camera rig, which knows the island's size
var _leaf_count := -1
var _has_leaf_sources := false
var _ruins
var _splash_key := ""


func setup(island_data, prop_layer, ruin_layer) -> void:
	_data = island_data
	_props = prop_layer
	_ruins = ruin_layer
	_build_environment()
	_build_lights()
	_build_clouds()
	_build_fog()
	_build_collision()
	_build_rain()
	_build_snow()
	_build_leaves()
	_build_fireflies()
	refresh_ground()
	apply()


## Jump the slow things (wet ground, lying snow) straight to where they are
## heading, for snapshots and first frames.
func settle() -> void:
	_wet = rain
	_snow_cover = snow
	apply()


func _process(delta: float) -> void:
	if time_flows:
		hour = fmod(hour + delta * 24.0 / DAY_SECONDS, 24.0)
		moon_phase = fmod(moon_phase + delta / (DAY_SECONDS * MOON_DAYS), 1.0)
	# the ground wets quickly and dries slowly; snow settles and melts slowly
	_wet = move_toward(_wet, rain, delta * (0.25 if rain > _wet else 0.04))
	_snow_cover = move_toward(_snow_cover, snow, delta * (0.08 if snow > _snow_cover else 0.03))
	if not hold_clouds:
		_cloud_holder.rotate_y(delta * (0.004 + wind * 0.02))
	# the clouds keep their distance round an island however big it grows
	if island_rig:
		var s: float = island_rig._fit_radius / island_rig.BASE_RADIUS
		_cloud_holder.scale = Vector3.ONE * s
		_cloud_holder.position = island_rig._fit_center
	# trees come and go; let the leaves follow
	if _props and _props.records.size() != _leaf_count:
		_refresh_leaves()
	# and splashes follow what has been built
	if rain > 0.01:
		var key := "%d|%d" % [_props.records.size(), _ruins.records.size()]
		if key != _splash_key:
			_refresh_splashes()
	apply()


# --- the hour ----------------------------------------------------------------

## Sun height in degrees over the day: up at 6, highest at noon, down at 18.
func sun_elevation() -> float:
	return 62.0 * sin((hour - 6.0) / 24.0 * TAU)


## Colours of the sky at a few sun heights, blended between.
const KEYS := [
	# elevation, top, horizon, bottom, sun colour, sun energy, ambient
	[-18.0, Color("0b1330"), Color("1f2d55"), Color("0e1838"), Color(0.5, 0.6, 0.9), 0.0, 0.32],
	[-6.0, Color("2a356b"), Color("c98a8e"), Color("3e4683"), Color(1.0, 0.55, 0.4), 0.0, 0.42],
	[3.0, Color("6a86c4"), Color("ffb889"), Color("8a8dc6"), Color(1.0, 0.62, 0.38), 1.2, 0.55],
	[14.0, Color("6a97d2"), Color("f2dfca"), Color("86a8d8"), Color(1.0, 0.82, 0.62), 2.3, 0.68],
	[30.0, Color("6b9ad6"), Color("e2eaf0"), Color("78a8e6"), Color(1.0, 0.92, 0.8), 2.8, 0.75],
]


func _palette(e: float) -> Array:
	if e <= KEYS[0][0]:
		return KEYS[0]
	for k in KEYS.size() - 1:
		var a: Array = KEYS[k]
		var b: Array = KEYS[k + 1]
		if e <= b[0]:
			var t := smoothstep(a[0], b[0], e)
			var out := [e]
			for i in range(1, a.size()):
				if a[i] is Color:
					out.append((a[i] as Color).lerp(b[i], t))
				else:
					out.append(lerpf(a[i], b[i], t))
			return out
	return KEYS[KEYS.size() - 1]


## Push the hour, the moon and the weather into lights, sky, fog and
## particles. Cheap enough to run every frame.
func apply() -> void:
	var e := sun_elevation()
	var pal := _palette(e)
	var overcast := clampf(maxf(rain, snow * 0.8) + maxf(clouds - 0.75, 0.0) * 0.8, 0.0, 1.0)
	night = 1.0 - smoothstep(-14.0, 2.0, e)

	# sun: comes round from the east, its light dimmed by overcast
	var azimuth := 125.0 + (hour - 12.0) * 15.0
	sun.rotation_degrees = Vector3(-maxf(e, -30.0), azimuth, 0.0)
	var sun_col: Color = (pal[4] as Color) * tint_sun
	sun.light_color = sun_col
	sun.light_energy = float(pal[5]) * (1.0 - overcast * 0.65) * sun_strength
	sun.visible = sun.light_energy > 0.02
	sun.shadow_opacity = 1.0 - overcast * 0.6

	# moon: across the sky from the sun, as bright as it is full
	var full := 0.5 - 0.5 * cos(moon_phase * TAU)
	# low over the far side of the sky, where a diorama camera can see it
	moon.rotation_degrees = Vector3(-clampf(-e * 0.35 + 6.0, -30.0, 26.0), azimuth + 180.0 + 25.0, 0.0)
	moon.light_energy = 0.55 * full * night * (1.0 - overcast * 0.7)
	moon.visible = moon.light_energy > 0.02

	sky_mat.set_shader_parameter("top_color", (pal[1] as Color) * tint_top)
	sky_mat.set_shader_parameter("horizon_color", (pal[2] as Color) * tint_horizon)
	sky_mat.set_shader_parameter("light_horizon", (pal[2] as Color).lerp(Color("f6e4cc"), smoothstep(14.0, 30.0, e)) * tint_horizon)
	sky_mat.set_shader_parameter("bottom_color", (pal[3] as Color) * tint_bottom)
	sky_mat.set_shader_parameter("sun_color", sun_col)
	sky_mat.set_shader_parameter("sun_dir", sun.global_basis.z)
	sky_mat.set_shader_parameter("moon_dir", moon.global_basis.z)
	sky_mat.set_shader_parameter("moon_phase", moon_phase)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("overcast", overcast)
	sky_mat.set_shader_parameter("high_clouds", clouds * 0.7)

	env.ambient_light_energy = (float(pal[6]) * (1.0 + overcast * 0.2) + full * night * 0.12) * ambient
	env.tonemap_exposure = lerpf(1.0, 1.45, night) * exposure
	# the haze keeps the warm cream of the old day horizon, even though the sky
	# band itself has turned a cooler blue-white
	var haze: Color = (pal[2] as Color).lerp(Color("f6e4cc"), smoothstep(14.0, 30.0, e))
	env.fog_light_color = haze.lerp(Color(0.72, 0.75, 0.8), overcast * 0.6) * tint_horizon * tint_fog
	env.fog_density = 0.0008 + fog * 0.004 + overcast * 0.0015
	env.adjustment_saturation = lerpf(1.2, 0.95, maxf(night * 0.6, overcast * 0.5)) * saturation

	# cloud puffs: as many as the cover asks for, tinted for the hour
	var showing := int(round(clouds * _clouds.size()))
	for k in _clouds.size():
		_clouds[k].visible = k < showing
	var lit: Color = Color(0.95, 0.95, 0.96).lerp(pal[4], 0.35 * (1.0 - night))
	lit = lit.lerp(Color(0.32, 0.36, 0.5), night * 0.85).lerp(Color(0.62, 0.64, 0.68), overcast * 0.7)
	var shade: Color = (pal[3] as Color).lerp(Color(0.7, 0.76, 0.88), 0.5).lerp(Color(0.42, 0.45, 0.52), overcast * 0.8)
	_cloud_mat.set_shader_parameter("lit_color", lit * tint_clouds)
	_cloud_mat.set_shader_parameter("shade_color", shade * tint_clouds.lerp(Color.WHITE, 0.3))
	_cloud_mat.set_shader_parameter("glow", Color(0.05, 0.055, 0.07).lerp(Color(0.04, 0.05, 0.09), night))

	# mist lying low over the island, coloured by the light
	_fog_volume.visible = fog > 0.01
	env.volumetric_fog_enabled = fog > 0.01
	# heavy, winding and lying low; at night it glows faintly white of its own
	# accord, where it would only scatter the little moonlight and go black
	_fog_mat.set_shader_parameter("density", fog * 1.1)
	_fog_mat.set_shader_parameter("thickness", lerpf(0.5, 1.4, fog))
	_fog_mat.set_shader_parameter("drift", 0.4 + wind * 1.6)
	var mist_col: Color = (pal[2] as Color).lerp(Color(0.92, 0.94, 0.97), 0.8) * tint_fog
	_fog_mat.set_shader_parameter("albedo", mist_col)
	_fog_mat.set_shader_parameter("glow_color", Color(0.72, 0.8, 0.95).lerp(mist_col, 0.3))
	_fog_mat.set_shader_parameter("glow", 0.02 + night * 0.22)

	# falling things
	_rain.emitting = rain > 0.01
	_rain.amount_ratio = rain
	_splash.emitting = rain > 0.01
	_splash.amount_ratio = rain
	_snow.emitting = snow > 0.01
	_snow.amount_ratio = snow
	var drift := Vector3(1.0, 0.0, 0.45) * wind
	(_rain.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, -14.0, 0.0) + drift * 8.0
	(_snow.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, -0.9, 0.0) + drift * 1.5
	var leaf_pm := _leaves.process_material as ParticleProcessMaterial
	leaf_pm.gravity = Vector3(0.0, -0.55, 0.0) + drift * 2.2
	_leaves.amount_ratio = clampf((wind - 0.15) * 1.4, 0.0, 1.0) * (1.0 - snow)
	_leaves.emitting = _leaves.amount_ratio > 0.01 and _has_leaf_sources
	# always there when asked for, so the dial answers at once; few and faint
	# by day, bright at dusk and night
	var dark := smoothstep(0.2, 0.8, night)
	_flies.amount_ratio = fireflies * lerpf(0.35, 1.0, dark) * (1.0 - rain) * (1.0 - snow)
	_fly_mat.albedo_color = Color(2.0, 1.7, 0.6) * lerpf(0.45, 1.0, dark)
	_flies.emitting = _flies.amount_ratio > 0.01

	RenderingServer.global_shader_parameter_set("wetness", _wet)
	RenderingServer.global_shader_parameter_set("snow_cover", _snow_cover)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("rain_amount", rain)


# --- building ------------------------------------------------------------------

func state() -> Dictionary:
	var out := {}
	for key in SETTINGS:
		var v = get(key)
		out[key] = [v.r, v.g, v.b] if v is Color else v
	return out


func set_state(s: Dictionary) -> void:
	for key in SETTINGS:
		if not s.has(key):
			continue
		var v = s[key]
		set(key, Color(v[0], v[1], v[2]) if v is Array else v)
	settle()


func _build_environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.ssao_power = 1.5
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 1.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.light_angular_distance = 0.4
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_angular_distance = 0.6
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _build_clouds() -> void:
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://shaders/cloud.gdshader")
	_cloud_holder = Node3D.new()
	add_child(_cloud_holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	# the first six are the ones the island always had; more fill in the gaps
	var spots := [[0.4, 15.0, -6.5], [1.5, 17.0, 1.5], [2.7, 14.5, -3.0], [3.6, 18.0, 3.0], [4.6, 15.5, -8.0], [5.6, 16.0, -1.0],
		[0.9, 21.0, 4.0], [2.1, 20.0, -9.5], [3.1, 22.0, 6.0], [4.1, 19.5, -4.5], [5.1, 21.5, 2.5], [6.0, 19.0, -10.0],
		[0.1, 24.0, -2.0], [3.4, 13.0, -11.0], [1.8, 12.5, 6.5], [5.0, 23.0, 7.0]]
	for s in spots:
		var cloud := Node3D.new()
		cloud.position = Vector3(cos(s[0]) * s[1], s[2], sin(s[0]) * s[1])
		cloud.rotation.y = rng.randf() * TAU
		# big puffs in the middle, small ones toward the ends, all resting
		# on a flat-ish base
		var length := rng.randf_range(3.0, 5.5)
		var puffs := rng.randi_range(9, 15)
		for p in puffs:
			var along := rng.randf_range(-1.0, 1.0)
			var r := lerpf(1.6, 0.6, absf(along)) * rng.randf_range(0.75, 1.15)
			var sphere := SphereMesh.new()
			sphere.radius = r
			sphere.height = r * 2.0
			var puff := MeshInstance3D.new()
			puff.mesh = sphere
			puff.material_override = _cloud_mat
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = Vector3(along * length, r * 0.55 + rng.randf_range(-0.1, 0.4), rng.randf_range(-0.9, 0.9))
			puff.scale = Vector3(1.0, 0.85, 1.0)
			cloud.add_child(puff)
		_cloud_holder.add_child(cloud)
		_clouds.append(cloud)


## The mist (mist.gdshader): a box over the whole island, from well under
## its rim, where the mist spills over, to above its hills.
## The terrain texture, so the mist knows where the ground lies.
func set_terrain(tex: Texture2D) -> void:
	_fog_mat.set_shader_parameter("terrain", tex)


func _build_fog() -> void:
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://shaders/mist.gdshader")
	_fog_volume = FogVolume.new()
	_fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_fog_volume.size = Vector3(40.0, 9.0, 40.0)
	_fog_volume.position = Vector3(0.0, -1.0, 0.0)
	_fog_volume.material = _fog_mat
	add_child(_fog_volume)


## Rain and snow stop where they meet the island. The height field is
## re-taken from above whenever the ground changes.
func _build_collision() -> void:
	_collision = GPUParticlesCollisionHeightField3D.new()
	_collision.size = Vector3(IslandData.SIZE + 4.0, 34.0, IslandData.SIZE + 4.0)
	_collision.position = Vector3(0.0, 4.0, 0.0)
	_collision.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collision)


## The ground changed: let rain see the new shape and fireflies the new
## lawns.
func refresh_ground() -> void:
	_collision.position.y = 4.0 if _collision.position.y != 4.0 else 4.0001
	_refresh_fireflies()
	_splash_key = ""


static func _disc_texture(n: int, hard: float) -> ImageTexture:
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - r, 0.0, 1.0), hard)))
	return ImageTexture.create_from_image(img)


func _particles(amount: int, lifetime: float, mesh: Mesh, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.draw_pass_1 = mesh
	p.process_material = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 70, 60))
	p.collision_base_size = 0.02
	p.emitting = false
	add_child(p)
	return p


func _build_rain() -> void:
	var streak := QuadMesh.new()
	streak.size = Vector2(0.035, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.55)
	mat.albedo_texture = _streak_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	streak.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(17.0, 0.5, 17.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain = _particles(9000, 2.6, streak, pm)
	_rain.position = Vector3(0.0, 16.0, 0.0)

	# Splashes: a little crown of droplets jumping up and falling back. Rain
	# falls evenly, so rather than catching each drop they rise from points
	# spread over whatever is uppermost: ground, water, wall tops, steps,
	# floors and boulders (see _refresh_splashes).
	var ring := QuadMesh.new()
	ring.size = Vector2(0.06, 0.06)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _disc_texture(32, 1.5)
	smat.albedo_color = Color(0.92, 0.95, 1.0, 0.85)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	ring.material = smat
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 38.0
	spm.initial_velocity_min = 0.9
	spm.initial_velocity_max = 1.7
	spm.gravity = Vector3(0, -9.0, 0)
	spm.scale_min = 0.6
	spm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	spm.color_ramp = fade_tex
	_splash = _particles(2600, 0.35, ring, spm)
	_splash.preprocess = 0.0


func _build_snow() -> void:
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _disc_texture(32, 1.2)
	mat.albedo_color = Color(1, 1, 1, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.27, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(17.0, 0.5, 17.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow = _particles(7000, 18.0, flake, pm)
	_snow.position = Vector3(0.0, 13.0, 0.0)


func _build_leaves() -> void:
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.albedo_texture = _leaf_texture()
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	leaf.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.direction = Vector3(1, 0.3, 0.45)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.3
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	# summer greens with the odd yellow and rust leaf
	var hues := Gradient.new()
	hues.set_color(0, Color(0.32, 0.5, 0.16))
	hues.set_color(1, Color(0.78, 0.42, 0.16))
	hues.add_point(0.55, Color(0.45, 0.6, 0.2))
	hues.add_point(0.8, Color(0.86, 0.72, 0.25))
	var hue_tex := GradientTexture1D.new()
	hue_tex.gradient = hues
	pm.color_initial_ramp = hue_tex
	_leaves = _particles(160, 7.0, leaf, pm)
	_leaves.preprocess = 0.0


## A raindrop's streak: feathered at the sides, a thin fading tail at the
## top swelling toward the drop at the bottom, and soft at both ends.
static func _streak_texture() -> ImageTexture:
	var w := 16
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := (y + 0.5) / h          # 0 at the top of the quad, 1 at the bottom
		var width := lerpf(0.15, 0.8, pow(t, 1.6))
		var ends := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.9, 1.0, t))
		for x in w:
			var u := ((x + 0.5) / w * 2.0 - 1.0) / width
			var a := exp(-u * u * 2.5) * ends * lerpf(0.35, 1.0, t)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _leaf_texture() -> ImageTexture:
	var n := 48
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			# a pointed oval with a paler midrib
			var w := (1.0 - v * v) * 0.5
			var inside := absf(u) < w
			var rib := 1.0 - smoothstep(0.0, 0.06, absf(u)) * 0.25
			img.set_pixel(x, y, Color(rib, rib, rib, 1.0 if inside else 0.0))
	return ImageTexture.create_from_image(img)


func _build_fireflies() -> void:
	var dot := QuadMesh.new()
	dot.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _disc_texture(32, 2.2)
	mat.albedo_color = Color(2.0, 1.7, 0.6)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.material = mat
	_fly_mat = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.1
	pm.damping_max = 0.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	# glow, dim, glow again and fade: the slow blink of a firefly
	var blink := Gradient.new()
	blink.set_color(0, Color(1, 1, 1, 0))
	blink.set_color(1, Color(1, 1, 1, 0))
	blink.add_point(0.15, Color(1, 1, 1, 1))
	blink.add_point(0.35, Color(1, 1, 1, 0.1))
	blink.add_point(0.55, Color(1, 1, 1, 1))
	blink.add_point(0.75, Color(1, 1, 1, 0.15))
	blink.add_point(0.88, Color(1, 1, 1, 0.9))
	var blink_tex := GradientTexture1D.new()
	blink_tex.gradient = blink
	pm.color_ramp = blink_tex
	_flies = _particles(420, 4.5, dot, pm)


## Splash points over the uppermost surface everywhere on the island.
func _refresh_splashes() -> void:
	_splash_key = "%d|%d" % [_props.records.size(), _ruins.records.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var pts := PackedVector3Array()
	for n in 6000:
		var x := rng.randf_range(-IslandData.SIZE * 0.5, IslandData.SIZE * 0.5)
		var z := rng.randf_range(-IslandData.SIZE * 0.5, IslandData.SIZE * 0.5)
		if _data.sample_sdf(x, z) < 0.05:
			continue
		pts.append(Vector3(x, top_height(x, z) + 0.02, z))
		if pts.size() >= 3000:
			break
	_set_points(_splash, pts)


## The height rain lands on at (x, z): the ground or the water, or the top
## of a ruin or a boulder standing there.
func top_height(x: float, z: float) -> float:
	var h: float = _data.sample_height(x, z)
	if _data.sample_water(x, z) > 0.4:
		h = maxf(h, _data.sample_wlevel(x, z))
	if _ruins:
		h = maxf(h, _ruins.top_at(Vector2(x, z)))
	for r in _props.records:
		if r.kind == "stenblock" and Vector2(x, z).distance_to(Vector2(r.x, r.z)) < float(r.size) * 0.55:
			h = maxf(h, _data.sample_height(r.x, r.z) + float(r.size) * 0.75)
	return h


## Fireflies rise from the lawns and the reeds, a little above the ground.
func _refresh_fireflies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var pts := PackedVector3Array()
	for n in 2000:
		var x := rng.randf_range(-IslandData.SIZE * 0.5, IslandData.SIZE * 0.5)
		var z := rng.randf_range(-IslandData.SIZE * 0.5, IslandData.SIZE * 0.5)
		if _data.sample_sdf(x, z) < 0.6:
			continue
		var y: float = _data.sample_height(x, z)
		if _data.sample_water(x, z) > 0.5:
			y = maxf(y, _data.sample_wlevel(x, z))
		pts.append(Vector3(x, y + rng.randf_range(0.25, 1.4), z))
		if pts.size() >= 400:
			break
	_set_points(_flies, pts)


## Leaves blow from the crowns of trees and bushes.
func _refresh_leaves() -> void:
	_leaf_count = _props.records.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pts := PackedVector3Array()
	var crowned := ["lovtrad", "krokigt", "sagotrad", "buske", "blombuske"]
	for r in _props.records:
		if not r.kind in crowned:
			continue
		var size: float = r.size
		var ground: float = _data.sample_height(r.x, r.z)
		for k in 24:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * size * 0.3
			pts.append(Vector3(r.x + cos(a) * d, ground + size * rng.randf_range(0.45, 0.85), r.z + sin(a) * d))
	_has_leaf_sources = not pts.is_empty()
	_set_points(_leaves, pts)


static func _set_points(p: GPUParticles3D, pts: PackedVector3Array) -> void:
	if pts.is_empty():
		pts.append(Vector3(0.0, -100.0, 0.0))
	var img := Image.create_empty(pts.size(), 1, false, Image.FORMAT_RGBF)
	for k in pts.size():
		img.set_pixel(k, 0, Color(pts[k].x, pts[k].y, pts[k].z))
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = pts.size()
