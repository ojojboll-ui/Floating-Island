extends Node
## The finish on the picture, the Effekter tab's settings.
##
## Part of it is Godot's own: glow, the volumetric fog that turns sunlight
## into shafts through the trees and ruins, ambient occlusion and the
## contrast and brightness adjustments. Light shafts from the sun are
## shafts.gdshader, a full-screen quad in the 3D view that can read the depth
## buffer. The rest is post.gdshader, a screen pass under the panel: white
## balance, split toning, vignette, grain, colour fringes and sharpening.
##
## It runs after the weather each frame, because the weather sets the fog
## and the glow it builds on.

var glow := 0.4
var glow_bloom := 0.05
var glow_threshold := 1.0
var rays := 0.0
var ray_length := 0.6
var volume := 0.0              # volumetric light: how thick the air is
var volume_glow := 1.0         # how brightly the sun lights it
var occlusion := 1.0
var contrast := 1.04
var brightness := 1.0
var temperature := 0.0
var tint := 0.0
var shadow_tint := Color.WHITE
var highlight_tint := Color.WHITE
var vignette := 0.25
var grain := 0.0
var aberration := 0.0
var sharpen := 0.0

const SETTINGS := ["glow", "glow_bloom", "glow_threshold", "rays", "ray_length", "volume", "volume_glow",
	"occlusion", "contrast", "brightness", "temperature", "tint", "shadow_tint", "highlight_tint",
	"vignette", "grain", "aberration", "sharpen"]

var material: ShaderMaterial
var weather
var rig
var _layer: CanvasLayer
var _shafts: MeshInstance3D
var _shafts_mat: ShaderMaterial
var _haze: FogVolume
var _haze_mat: FogMaterial


func setup(weather_node, rig_node) -> void:
	weather = weather_node
	rig = rig_node
	process_priority = 10
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/post.gdshader")
	_layer = make_layer(material)
	add_child(_layer)
	_shafts_mat = ShaderMaterial.new()
	_shafts_mat.shader = load("res://shaders/shafts.gdshader")
	_shafts_mat.render_priority = 100
	_shafts = MeshInstance3D.new()
	_shafts.mesh = QuadMesh.new()
	_shafts.material_override = _shafts_mat
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shafts.extra_cull_margin = 16384.0
	_shafts.position = Vector3(0.0, 0.0, -1.0)
	rig.camera.add_child(_shafts)
	# the haze for the volumetric light: a box of air round the island only,
	# so the air between the camera and the island stays clear
	_haze_mat = FogMaterial.new()
	_haze_mat.edge_fade = 0.6
	_haze_mat.height_falloff = 0.0
	_haze = FogVolume.new()
	_haze.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	_haze.material = _haze_mat
	add_child(_haze)
	apply()


## A full-screen pass on its own layer, under the panel. The still export
## puts one in its own viewport too.
static func make_layer(mat: ShaderMaterial) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	layer.add_child(rect)
	return layer


func _process(_delta: float) -> void:
	apply()


func apply() -> void:
	var env: Environment = weather.env
	env.glow_intensity = glow
	env.glow_bloom = glow_bloom
	env.glow_hdr_threshold = glow_threshold
	env.ssao_intensity = 2.5 * occlusion
	env.ssao_enabled = occlusion > 0.01
	env.adjustment_contrast = contrast
	env.adjustment_brightness = brightness

	# volumetric light: a thin haze all through the air, lit by the sun and
	# shadowed by everything on the island, so shafts fall between them
	_haze.visible = volume > 0.01
	if volume > 0.01:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_anisotropy = 0.25
		env.volumetric_fog_sky_affect = 0.0
		var r: float = rig.island_radius
		_haze.position = Vector3(rig.island_center.x, 2.0, rig.island_center.z)
		_haze.size = Vector3(r * 3.0, 26.0, r * 3.0)
		_haze_mat.density = volume * 0.045
		var reach: float = rig.camera.global_position.distance_to(rig.island_center) + r * 1.6
		env.volumetric_fog_length = maxf(90.0, reach)
	weather.sun.light_volumetric_fog_energy = volume_glow
	weather.moon.light_volumetric_fog_energy = volume_glow

	_aim(_shafts_mat, rig.camera, get_viewport().get_visible_rect().size)
	# only drawn while the sun is in or near the picture
	_shafts.visible = rays > 0.01 and float(_shafts_mat.get_shader_parameter("sun_on")) > 0.001
	_shafts_mat.set_shader_parameter("rays", rays)
	_shafts_mat.set_shader_parameter("ray_length", ray_length)
	var size := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	material.set_shader_parameter("temperature", temperature)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("shadow_tint", shadow_tint)
	material.set_shader_parameter("highlight_tint", highlight_tint)
	material.set_shader_parameter("vignette", vignette)
	material.set_shader_parameter("grain", grain)
	material.set_shader_parameter("aberration", aberration)
	material.set_shader_parameter("sharpen", sharpen)


## Where the sun stands on the screen of `cam`, and how much it shines in.
func _aim(mat: ShaderMaterial, cam: Camera3D, size: Vector2) -> void:
	var sun: DirectionalLight3D = weather.sun
	var toward: Vector3 = sun.global_basis.z
	var facing := toward.dot(-cam.global_basis.z)
	var on := 0.0
	var uv := Vector2(0.5, -1.0)
	if facing > 0.02 and sun.visible:
		uv = cam.unproject_position(cam.global_position + toward * 1000.0) / size
		# fade as the sun leaves the frame, and with its strength
		var outside := Vector2(maxf(0.0, absf(uv.x - 0.5) - 0.5), maxf(0.0, absf(uv.y - 0.5) - 0.5)).length()
		on = smoothstep(0.02, 0.4, facing) * exp(-outside * 1.6) * clampf(sun.light_energy, 0.0, 1.0)
	mat.set_shader_parameter("sun_uv", uv)
	mat.set_shader_parameter("sun_on", on)
	mat.set_shader_parameter("sun_color", sun.light_color)
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## A copy of the screen pass for a viewport of another size, for the still
## export. The shafts are in the world, so the export sees them anyway.
func material_for(size: Vector2) -> ShaderMaterial:
	var mat := material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	return mat


func state() -> Dictionary:
	var out := {}
	for key in SETTINGS:
		var v = get(key)
		out[key] = [v.r, v.g, v.b] if v is Color else v
	return out


func set_state(s: Dictionary) -> void:
	for key in SETTINGS:
		if s.has(key):
			var v = s[key]
			set(key, Color(v[0], v[1], v[2]) if v is Array else v)
	apply()


func reset() -> void:
	var fresh = get_script().new()
	for key in SETTINGS:
		set(key, fresh.get(key))
	fresh.free()
	apply()
