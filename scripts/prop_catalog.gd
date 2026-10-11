extends RefCounted
## Everything that can be placed on the island, and how to build it.
##
## Most kinds come from the Quaternius Stylized Nature MegaKit (CC0), loaded
## from glTF at runtime so the project needs no editor import. Their
## materials are swapped for our own shaders, so kit plants sway in the same
## wind and kit rocks gather the same moss as everything else. Reeds, lilies
## and the fairy-tale tree are built in code.
##
## Stones are generated (rock_builder.gd), each kind with a style that the
## panel's dials change: see STONE_DIALS.
##
## Per kind:
##   height     world height range in meters
##   spacing    how close two of its own layer may stand
##   layer      big things block small ones underneath; small ones only mind
##              their own spacing
##   where      land, shore (wet edges) or water (floating)
##   mark       [splat colour, radius]: the ground it leaves around itself
##   occupied   radius where grass gives way
##   sink       how far into the ground, as a share of its height

const TreeBuilder := preload("res://scripts/tree_builder.gd")
const RockBuilder := preload("res://scripts/rock_builder.gd")
const PlantBuilder := preload("res://scripts/plant_builder.gd")

const MODELS := "res://assets/quaternius/"

const KINDS := {
	"lovtrad": {"label": "Lövträd", "models": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"],
		"height": [4.6, 6.4], "spacing": 2.6, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.45, 0.3), 1.9], "occupied": 0.55, "sink": 0.0, "sway": 0.35},
	"gran": {"label": "Gran", "models": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"height": [5.0, 7.2], "spacing": 2.4, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.3, 0.45), 1.7], "occupied": 0.5, "sink": 0.0, "sway": 0.2},
	"krokigt": {"label": "Höstträd", "models": ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"],
		"height": [6.5, 8.0], "spacing": 4.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.3), 2.4], "occupied": 0.8, "sink": 0.0, "sway": 0.25},
	"torrtrad": {"label": "Torrträd", "models": ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"],
		"height": [4.0, 5.5], "spacing": 3.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.2, 0.55), 1.5], "occupied": 0.45, "sink": 0.0, "sway": 0.0},
	"sagotrad": {"label": "Sagoträd", "builder": "tree", "height": [5.5, 6.5], "spacing": 3.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.35), 2.0], "occupied": 0.7, "sink": 0.0},
	"buske": {"label": "Buske", "models": ["Bush_Common"], "recolor": Color(0.36, 0.56, 0.17), "height": [0.9, 1.3], "spacing": 1.1, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.35, 0.15), 0.9], "occupied": 0.55, "sink": 0.05, "sway": 0.4},
	"blombuske": {"label": "Blombuske", "models": ["Bush_Common_Flowers"], "height": [0.9, 1.3], "spacing": 1.1, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.35, 0.15), 0.9], "occupied": 0.55, "sink": 0.05, "sway": 0.4},
	"ormbunke": {"label": "Ormbunke", "models": ["Fern_1", "Plant_1", "Plant_1_Big"], "height": [0.4, 0.75], "spacing": 0.6, "layer": "small", "where": "land",
		"mark": [Color(0, 0, 0.4, 0.1), 0.6], "occupied": 0.25, "sink": 0.0, "sway": 0.6},
	"hogtgras": {"label": "Högt gräs", "lawn": true, "models": ["Grass_Wispy_Short", "Grass_Wispy_Tall", "Grass_Common_Tall"], "height": [0.35, 0.6], "spacing": 0.35, "layer": "small", "where": "land",
		"occupied": 0.0, "sink": 0.0, "sway": 1.0},
	"blommor": {"label": "Blommor", "models": ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"], "height": [0.3, 0.55], "spacing": 0.35, "layer": "small", "where": "land",
		"occupied": 0.0, "sink": 0.0, "sway": 0.9},
	"klover": {"label": "Klöver", "models": ["Clover_1", "Clover_2"], "height": [0.16, 0.26], "spacing": 0.3, "layer": "small", "where": "land",
		"occupied": 0.0, "sink": 0.0, "sway": 0.5},
	"svamp": {"label": "Svamp", "models": ["Mushroom_Common", "Mushroom_Laetiporus"], "height": [0.12, 0.24], "spacing": 0.25, "layer": "small", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.2), 0.35], "occupied": 0.0, "sink": 0.0, "sway": 0.0},
	"stenblock": {"label": "Stenblock", "builder": "rock", "variants": 1000, "detail": 4,
		"style": {"size": 1.4, "variation": 0.3, "angular": 0.5, "flat": 0.25, "long": 0.2, "moss": 0.5, "texture": 0.5, "tint": [0.47, 0.48, 0.5]},
		"spacing": 1.6, "layer": "big", "where": "land",
		"mark": [Color(0.08, 0, 0.6, 0.2), 1.7], "occupied": 0.9, "sink": 0.15, "sway": 0.0},
	"smasten": {"label": "Småsten", "builder": "rock", "variants": 10, "detail": 2,
		"style": {"size": 0.16, "variation": 0.45, "angular": 0.35, "flat": 0.45, "long": 0.3, "moss": 0.25, "texture": 0.3, "tint": [0.52, 0.51, 0.5]},
		"spacing": 0.3, "layer": "small", "where": "land", "occupied": 0.1, "sink": 0.3, "sway": 0.0},
	"trampsten": {"label": "Trampstenar", "builder": "rock", "variants": 10, "detail": 2,
		"style": {"size": 0.6, "variation": 0.2, "angular": 0.55, "flat": 0.85, "long": 0.25, "moss": 0.3, "texture": 0.4, "tint": [0.55, 0.54, 0.52]},
		"spacing": 0.75, "layer": "small", "where": "any", "occupied": 0.4, "sink": 0.45, "sway": 0.0},
	"vass": {"label": "Vass", "builder": "reeds", "height": [0.8, 1.2], "spacing": 0.4, "layer": "small", "where": "shore",
		"mark": [Color(0, 0, 0.2, 0.5), 0.5], "occupied": 0.2, "sink": 0.0},
	"nackros": {"label": "Näckros", "builder": "lily", "height": [0.22, 0.34], "spacing": 0.4, "layer": "water", "where": "water",
		"occupied": 0.0, "sink": 0.0},
}

## The dials for a generated kind: label, style key, low, high, unit, tip.
const STONE_DIALS := [
	["Storlek", "size", 0.05, 3.0, "m", "Hur stora stenarna är, tvärs över"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
	["Kantighet", "angular", 0.0, 1.0, "%", "Nötta och runda, eller huggna med skarpa kanter"],
	["Platthet", "flat", 0.0, 1.0, "%", "Lika höga som breda, eller flata hällar"],
	["Avlånghet", "long", 0.0, 1.0, "%", "Runda, eller dubbelt så långa som breda"],
	["Mossa", "moss", 0.0, 1.0, "%", "Hur mycket mossa; mer nära vatten och under träd"],
	["Textur", "texture", 0.0, 1.0, "%", "Sprickor och skikt i stenen"],
]
const TREES := ["lovtrad", "gran", "krokigt", "torrtrad", "sagotrad"]
static var _rock_mat: ShaderMaterial


static var _models := {}      # model name -> {mesh, height}
static var _materials := {}   # "name|sway" -> Material
static var _procedural := {}  # "kind|variant" -> Mesh


static func variants(kind: String) -> int:
	var k: Dictionary = KINDS[kind]
	if k.has("variants"):
		return k.variants
	if k.has("models"):
		return k.models.size()
	return 6


## A node for one placed record, positioned at the origin; the layer moves it.
static func build(rec: Dictionary) -> Node3D:
	var k: Dictionary = KINDS[rec.kind]
	var size: float = rec.size
	var builder: String = k.get("builder", "model")
	var node: Node3D
	var shaded: GeometryInstance3D
	var model_height := 1.0
	match builder:
		"rock":
			var st := RockBuilder.style_of(k.style, rec.get("style"))
			var mi := MeshInstance3D.new()
			mi.mesh = RockBuilder.mesh(st, int(rec.variant), int(k.get("detail", 3)))
			mi.scale = Vector3.ONE * size
			if _rock_mat == null:
				_rock_mat = ShaderMaterial.new()
				_rock_mat.shader = load("res://shaders/rock.gdshader")
			mi.material_override = _rock_mat
			var t: Array = st.tint
			var hue: float = rec.hue
			mi.set_instance_shader_parameter("stone", Vector3(t[0], t[1], t[2]) * (0.9 + 0.2 * hue))
			mi.set_instance_shader_parameter("moss_amount", st.moss)
			mi.set_instance_shader_parameter("texture_amount", st.texture)
			mi.set_meta("tall", mi.mesh.get_aabb().size.y * size)
			mi.rotation.y = rec.rot
			mi.set_meta("shaded", mi)
			return mi
		"tree":
			node = TreeBuilder.build(Vector3.ZERO, int(rec.variant) + 100)
			node.scale = Vector3.ONE * size / 6.0
			shaded = node.get_child(0)
		"reeds", "lily":
			var key := "%s|%d" % [rec.kind, rec.variant]
			if not _procedural.has(key):
				var mat := ShaderMaterial.new()
				if builder == "reeds":
					_procedural[key] = PlantBuilder.reeds(int(rec.variant) * 31 + 7)
					mat.shader = load("res://shaders/reeds.gdshader")
				else:
					_procedural[key] = PlantBuilder.lily(int(rec.variant) * 17 + 3, int(rec.variant) % 3 == 0)
					mat.shader = load("res://shaders/lily.gdshader")
				(_procedural[key] as ArrayMesh).surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = _procedural[key]
			mi.scale = Vector3.ONE * size
			node = mi
			shaded = mi
		_:
			var entry := _model(k.models[int(rec.variant) % k.models.size()], k.get("sway", 0.5), k.get("recolor", Color(1, 1, 1, 0)), k.get("lawn", false))
			var mi := MeshInstance3D.new()
			mi.mesh = entry.mesh
			model_height = entry.height
			mi.scale = Vector3.ONE * size / model_height
			node = mi
			shaded = mi
	node.rotation.y = rec.rot
	node.set_meta("shaded", shaded)
	var hue: float = rec.hue
	shaded.set_instance_shader_parameter("tint", Vector3(1.0 + (hue - 0.5) * 0.18, 1.0 + (hue - 0.5) * 0.05, 1.0 - (hue - 0.5) * 0.15))
	shaded.set_instance_shader_parameter("height", model_height)
	return node


## Load a kit model once, with its materials swapped for ours.
static func _model(name: String, sway: float, recolor: Color, lawn: bool) -> Dictionary:
	if _models.has(name):
		return _models[name]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(MODELS + name + ".gltf"), state)
	if err != OK:
		push_error("could not load model " + name)
		return {"mesh": BoxMesh.new(), "height": 1.0}
	var root := doc.generate_scene(state)
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mi.mesh
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, _material(mesh.surface_get_material(s) as BaseMaterial3D, sway, recolor, lawn))
	var box := mesh.get_aabb()
	root.free()
	var entry := {"mesh": mesh, "height": box.end.y}
	_models[name] = entry
	return entry


static func _material(src: BaseMaterial3D, sway: float, recolor: Color, lawn: bool) -> Material:
	var name := src.resource_name if src else ""
	var key := "%s|%.2f|%s|%s" % [name, sway, recolor, lawn]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	if name.begins_with("Bark"):
		mat.shader = load("res://shaders/bark_tex.gdshader")
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		if src.normal_texture:
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("has_normal", true)
	elif name.contains("Rock"):
		mat.shader = load("res://shaders/rock.gdshader")
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("use_tex", true)
	else:
		mat.shader = load("res://shaders/foliage.gdshader")
		mat.set_shader_parameter("albedo_tex", src.albedo_texture if src else null)
		mat.set_shader_parameter("sway", sway)
		mat.set_shader_parameter("lawn_colour", lawn)
		if recolor.a > 0.0 and name.begins_with("Leaves"):
			mat.set_shader_parameter("recolor", Vector4(recolor.r, recolor.g, recolor.b, 1.0))
		mat.set_shader_parameter("backlight", 0.2 if name.begins_with("Mushroom") else 0.5)
	_materials[key] = mat
	return mat
