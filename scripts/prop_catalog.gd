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
const PlantGen := preload("res://scripts/plant_gen.gd")
const ItemBuilder := preload("res://scripts/item_builder.gd")
const RockBuilder := preload("res://scripts/rock_builder.gd")
const PlantBuilder := preload("res://scripts/plant_builder.gd")

const MODELS := "res://assets/quaternius/"

const KINDS := {
	"lovtrad": {"label": "Lövträd", "builder": "tree", "dials": "tree", "variants": 1000,
		"style": {"size": 5.5, "variation": 0.15, "trunk": 0.3, "bend": 0.3, "branches": 5, "levels": 3, "branch_len": 0.6,
			"angle": 45.0, "crown": 0.5, "branch_start": 0.35, "leaves": 0.75, "leaf_size": 1.0,
			"leaf_color": [0.46, 0.66, 0.2], "bark_color": [0.4, 0.29, 0.21], "fruit": 0.0, "fruit_size": 1.0, "fruit_color": [0.82, 0.14, 0.1]},
		"spacing": 2.6, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.45, 0.3), 1.9], "occupied": 0.55, "sink": 0.0},
	"gran": {"label": "Gran", "builder": "tree", "dials": "conifer", "variants": 1000,
		"style": {"size": 6.2, "variation": 0.15, "trunk": 0.2, "bend": 0.55, "branches": 10, "levels": 1, "branch_len": 0.8,
			"angle": 40.0, "crown": 0.0, "branch_start": 0.3, "leaves": 0.15, "leaf_size": 1.0, "conifer": true,
			"leaf_color": [0.2, 0.38, 0.13], "bark_color": [0.36, 0.24, 0.17], "fruit": 0.0, "fruit_size": 1.0, "fruit_color": [0.82, 0.14, 0.1]},
		"spacing": 2.4, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.3, 0.45), 1.7], "occupied": 0.5, "sink": 0.0},
	"krokigt": {"label": "Höstträd", "builder": "tree", "dials": "tree", "variants": 1000,
		"style": {"size": 6.5, "variation": 0.15, "trunk": 0.32, "bend": 0.75, "branches": 4, "levels": 3, "branch_len": 0.65,
			"angle": 50.0, "crown": 0.6, "branch_start": 0.4, "leaves": 0.65, "leaf_size": 1.1,
			"leaf_color": [0.85, 0.24, 0.12], "bark_color": [0.3, 0.24, 0.22], "fruit": 0.0, "fruit_size": 1.0, "fruit_color": [0.82, 0.14, 0.1]},
		"spacing": 4.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.3), 2.4], "occupied": 0.8, "sink": 0.0},
	"torrtrad": {"label": "Torrträd", "builder": "tree", "dials": "tree", "variants": 1000,
		"style": {"size": 4.8, "variation": 0.15, "trunk": 0.28, "bend": 0.65, "branches": 5, "levels": 3, "branch_len": 0.6,
			"angle": 40.0, "crown": 0.5, "branch_start": 0.3, "leaves": 0.0, "leaf_size": 1.0,
			"leaf_color": [0.5, 0.45, 0.25], "bark_color": [0.47, 0.42, 0.37], "fruit": 0.0, "fruit_size": 1.0, "fruit_color": [0.82, 0.14, 0.1]},
		"spacing": 3.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.2, 0.55), 1.5], "occupied": 0.45, "sink": 0.0},
	"sagotrad": {"label": "Sagoträd", "builder": "tree", "dials": "tree", "variants": 1000,
		"style": {"size": 6.0, "variation": 0.1, "trunk": 0.42, "bend": 0.4, "branches": 3, "levels": 3, "branch_len": 0.72,
			"angle": 52.0, "crown": 0.8, "branch_start": 0.48, "leaves": 0.85, "leaf_size": 1.3,
			"leaf_color": [0.46, 0.66, 0.2], "bark_color": [0.42, 0.3, 0.22], "fruit": 0.0, "fruit_size": 1.0, "fruit_color": [0.82, 0.14, 0.1]},
		"spacing": 3.0, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.35), 2.0], "occupied": 0.7, "sink": 0.0},
	"buske": {"label": "Buske", "builder": "tree", "dials": "bush", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.2, "trunk": 0.12, "bend": 0.45, "branches": 6, "levels": 2, "branch_len": 0.9,
			"angle": 55.0, "crown": 0.5, "branch_start": 0.0, "leaves": 0.9, "leaf_size": 0.55,
			"leaf_color": [0.36, 0.56, 0.17], "bark_color": [0.35, 0.26, 0.19], "fruit": 0.0, "fruit_size": 0.45, "fruit_color": [0.75, 0.12, 0.2]},
		"spacing": 1.1, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.35, 0.15), 0.9], "occupied": 0.55, "sink": 0.05},
	"blombuske": {"label": "Blombuske", "builder": "tree", "dials": "bush", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.2, "trunk": 0.12, "bend": 0.45, "branches": 6, "levels": 2, "branch_len": 0.9,
			"angle": 55.0, "crown": 0.5, "branch_start": 0.0, "leaves": 0.85, "leaf_size": 0.5, "blossom": true,
			"leaf_color": [0.32, 0.52, 0.18], "bark_color": [0.35, 0.26, 0.19], "fruit": 0.8, "fruit_size": 1.0, "fruit_color": [0.72, 0.5, 0.88]},
		"spacing": 1.1, "layer": "big", "where": "land",
		"mark": [Color(0, 0, 0.35, 0.15), 0.9], "occupied": 0.55, "sink": 0.05},
	"ormbunke": {"label": "Ormbunke", "builder": "plant", "gen": "fern", "dials": "fern", "variants": 1000,
		"style": {"size": 0.6, "variation": 0.25, "fronds": 8, "arch": 0.55, "width": 0.65,
			"color_a": [0.3, 0.55, 0.16], "color_b": [0.3, 0.55, 0.16], "color_c": [0.3, 0.55, 0.16]},
		"spacing": 0.6, "layer": "small", "where": "land",
		"mark": [Color(0, 0, 0.4, 0.1), 0.6], "occupied": 0.25, "sink": 0.0},
	"hogtgras": {"label": "Högt gräs", "builder": "plant", "gen": "grass", "dials": "grass", "variants": 1000,
		"style": {"size": 0.7, "variation": 0.25, "blades": 22, "bend": 0.35, "width": 1.0, "spread": 0.5, "heads": 0.3, "lawn": 1.0,
			"color_a": [0.45, 0.62, 0.2], "color_b": [0.45, 0.62, 0.2], "color_c": [0.78, 0.7, 0.45]},
		"spacing": 0.35, "layer": "small", "where": "land", "occupied": 0.0, "sink": 0.0},
	"blommor": {"label": "Blommor", "builder": "plant", "gen": "flower", "dials": "flower", "variants": 1000,
		"style": {"size": 0.45, "variation": 0.25, "stems": 4, "petals": 6, "bloom": 1.6, "cup": 0.3,
			"color_a": [0.32, 0.55, 0.18], "color_b": [0.72, 0.5, 0.9], "color_c": [0.98, 0.82, 0.3]},
		"spacing": 0.35, "layer": "small", "where": "land", "occupied": 0.0, "sink": 0.0},
	"klover": {"label": "Klöver", "builder": "plant", "gen": "clover", "dials": "clover", "variants": 1000,
		"style": {"size": 0.8, "variation": 0.2, "count": 18, "heads": 0.25,
			"color_a": [0.3, 0.55, 0.2], "color_b": [0.95, 0.93, 0.88], "color_c": [0.95, 0.93, 0.88]},
		"spacing": 0.3, "layer": "small", "where": "land", "occupied": 0.0, "sink": 0.0},
	"svamp": {"label": "Svamp", "builder": "plant", "gen": "mushroom", "dials": "mushroom", "variants": 1000,
		"style": {"size": 0.2, "variation": 0.3, "count": 3, "cap_width": 1.0, "cap_shape": 0.4, "spots": 0.55,
			"color_a": [0.93, 0.88, 0.78], "color_b": [0.78, 0.16, 0.1], "color_c": [0.98, 0.96, 0.9]},
		"spacing": 0.25, "layer": "small", "where": "land",
		"mark": [Color(0, 0, 0.5, 0.2), 0.35], "occupied": 0.0, "sink": 0.0},
	"stenblock": {"label": "Stenblock", "builder": "rock", "variants": 1000, "detail": 4,
		"style": {"size": 1.4, "variation": 0.3, "angular": 0.5, "flat": 0.25, "long": 0.2, "moss": 0.5, "texture": 0.5, "tint": [0.5, 0.51, 0.53]},
		"spacing": 1.6, "layer": "big", "where": "land", "occupied": 0.75, "sink": 0.15, "sway": 0.0},
	"smasten": {"label": "Småsten", "builder": "rock", "variants": 10, "detail": 2,
		"style": {"size": 0.16, "variation": 0.45, "angular": 0.35, "flat": 0.45, "long": 0.3, "moss": 0.25, "texture": 0.3, "tint": [0.54, 0.52, 0.5]},
		"spacing": 0.3, "layer": "small", "where": "land", "occupied": 0.1, "sink": 0.3, "sway": 0.0},
	"trampsten": {"label": "Trampstenar", "builder": "rock", "variants": 10, "detail": 2,
		"style": {"size": 0.6, "variation": 0.2, "angular": 0.55, "flat": 0.85, "long": 0.25, "moss": 0.3, "texture": 0.4, "tint": [0.57, 0.55, 0.52]},
		"spacing": 0.75, "layer": "small", "where": "any", "occupied": 0.4, "sink": 0.45, "sway": 0.0},
	"stock": {"label": "Stock", "builder": "item", "gen": "log", "dials": "deadwood", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.2, "thick": 1.0, "moss": 0.6, "fungi": 0.4, "color_a": [0.36, 0.3, 0.25], "color_b": [0.82, 0.62, 0.36]},
		"spacing": 1.4, "layer": "big", "where": "land", "mark": [Color(0, 0, 0.45, 0.25), 1.2], "occupied": 0.5, "sink": 0.12},
	"stubbe": {"label": "Stubbe", "builder": "item", "gen": "stump", "dials": "deadwood", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.2, "thick": 1.0, "moss": 0.4, "fungi": 0.4, "color_a": [0.38, 0.29, 0.22], "color_b": [0.85, 0.66, 0.4]},
		"spacing": 1.0, "layer": "big", "where": "land", "mark": [Color(0, 0, 0.4, 0.25), 0.9], "occupied": 0.45, "sink": 0.0},
	"eldstad": {"label": "Eldstad", "builder": "item", "gen": "firepit", "dials": "light", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "glow": 1.0, "color_a": [0.4, 0.4, 0.4], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 1.2, "layer": "small", "where": "land", "mark": [Color(0, 0, 0, 0.8), 0.7], "occupied": 0.75, "sink": 0.0},
	"fackla": {"label": "Fackla", "builder": "item", "gen": "torch", "dials": "light", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "glow": 1.0, "color_a": [0.45, 0.32, 0.2], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.4, "layer": "small", "where": "any", "occupied": 0.08, "sink": 0.0},
	"ljus": {"label": "Stearinljus", "builder": "item", "gen": "candles", "dials": "light", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "glow": 1.0, "color_a": [0.95, 0.9, 0.78], "color_b": [0.55, 0.45, 0.35]},
		"spacing": 0.3, "layer": "small", "where": "any", "occupied": 0.1, "sink": 0.0},
	"lykta": {"label": "Lykta", "builder": "item", "gen": "lantern", "dials": "light", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "glow": 1.0, "color_a": [0.18, 0.18, 0.2], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.3, "layer": "small", "where": "any", "occupied": 0.1, "sink": 0.0},
	"talt": {"label": "Tält", "builder": "item", "gen": "tent", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.05, "color_a": [0.78, 0.66, 0.42], "color_b": [0.42, 0.3, 0.2]},
		"spacing": 2.6, "layer": "big", "where": "land", "occupied": 1.0, "sink": 0.0},
	"ryggsack": {"label": "Ryggsäck", "builder": "item", "gen": "backpack", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.05, "color_a": [0.4, 0.5, 0.3], "color_b": [0.7, 0.3, 0.25]},
		"spacing": 0.5, "layer": "small", "where": "any", "occupied": 0.15, "sink": 0.0},
	"koffert": {"label": "Koffert", "builder": "item", "gen": "chest", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.05, "color_a": [0.5, 0.33, 0.2], "color_b": [0.25, 0.25, 0.27]},
		"spacing": 0.8, "layer": "small", "where": "any", "occupied": 0.35, "sink": 0.0},
	"gryta": {"label": "Gryta", "builder": "item", "gen": "pot", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.05, "color_a": [0.62, 0.38, 0.2], "color_b": [0.42, 0.3, 0.2]},
		"spacing": 0.4, "layer": "small", "where": "any", "occupied": 0.1, "sink": 0.0},
	"filt": {"label": "Picknickfilt", "builder": "item", "gen": "blanket", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.05, "color_a": [0.78, 0.22, 0.2], "color_b": [0.75, 0.7, 0.6]},
		"spacing": 1.4, "layer": "small", "where": "land", "occupied": 1.05, "sink": 0.0},
	"spade": {"label": "Spade", "builder": "item", "gen": "spade", "dials": "item", "variants": 1000,
		"style": {"size": 1.25, "variation": 0.05, "color_a": [0.55, 0.4, 0.25], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.4, "layer": "small", "where": "land", "occupied": 0.05, "sink": 0.0},
	"hacka": {"label": "Hacka", "builder": "item", "gen": "pick", "dials": "item", "variants": 1000,
		"style": {"size": 1.25, "variation": 0.05, "color_a": [0.55, 0.4, 0.25], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.5, "layer": "small", "where": "any", "occupied": 0.05, "sink": 0.0},
	"yxa": {"label": "Yxa", "builder": "item", "gen": "axe", "dials": "item", "variants": 1000,
		"style": {"size": 1.25, "variation": 0.05, "color_a": [0.72, 0.5, 0.3], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.4, "layer": "small", "where": "any", "occupied": 0.3, "sink": 0.0},
	"huggkubbe": {"label": "Huggkubbe", "builder": "item", "gen": "block", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.86, 0.66, 0.42], "color_b": [0.42, 0.36, 0.3]},
		"spacing": 0.9, "layer": "small", "where": "land", "mark": [Color(0, 0, 0, 0.6), 1.0], "occupied": 0.8, "sink": 0.0},
	"flaskor": {"label": "Flaskor", "builder": "item", "gen": "bottles", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.3, 0.55, 0.32], "color_b": [0.55, 0.32, 0.15]},
		"spacing": 0.3, "layer": "small", "where": "any", "occupied": 0.05, "sink": 0.0},
	"bocker": {"label": "Böcker", "builder": "item", "gen": "books", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.55, 0.2, 0.18], "color_b": [0.25, 0.4, 0.3]},
		"spacing": 0.3, "layer": "small", "where": "any", "occupied": 0.05, "sink": 0.0},
	"svampkorg": {"label": "Svampkorg", "builder": "item", "gen": "basket", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.7, 0.52, 0.3], "color_b": [0.75, 0.45, 0.2]},
		"spacing": 0.35, "layer": "small", "where": "any", "occupied": 0.08, "sink": 0.0},
	"tunna": {"label": "Tunna", "builder": "item", "gen": "barrel", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.52, 0.36, 0.22], "color_b": [0.25, 0.25, 0.27]},
		"spacing": 0.65, "layer": "small", "where": "any", "occupied": 0.3, "sink": 0.0},
	"vedtrave": {"label": "Vedtrave", "builder": "item", "gen": "woodpile", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.86, 0.66, 0.42], "color_b": [0.42, 0.36, 0.3]},
		"spacing": 0.8, "layer": "small", "where": "land", "mark": [Color(0, 0, 0, 0.45), 0.9], "occupied": 0.7, "sink": 0.0},
	"stockhog": {"label": "Rund vedtrave", "builder": "item", "gen": "logpile", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.86, 0.66, 0.42], "color_b": [0.42, 0.33, 0.25]},
		"spacing": 0.9, "layer": "small", "where": "land", "mark": [Color(0, 0, 0, 0.4), 0.8], "occupied": 0.6, "sink": 0.0},
	"skylt": {"label": "Skylt", "builder": "item", "gen": "sign", "dials": "item", "variants": 1000,
		"style": {"size": 1.0, "variation": 0.1, "color_a": [0.6, 0.45, 0.28], "color_b": [0.4, 0.4, 0.4]},
		"spacing": 0.5, "layer": "small", "where": "land", "occupied": 0.05, "sink": 0.0},
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
const TREE_DIALS := [
	["Höjd", "size", 1.5, 12.0, "m", "Hur högt trädet är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket träden skiljer sig i höjd"],
	["Stam", "trunk", 0.08, 0.8, "m", "Stammens tjocklek vid roten"],
	["Krokighet", "bend", 0.0, 1.0, "%", "Raka stammar och grenar, eller vridna och knotiga"],
	["Grenar", "branches", 2.0, 18.0, "count", "Hur många huvudgrenar som går ut från stammen"],
	["Förgrening", "levels", 1.0, 4.0, "count", "Hur många led grenarna delar sig i"],
	["Grenlängd", "branch_len", 0.2, 1.0, "%", "Hur långa grenarna är"],
	["Grenvinkel", "angle", 15.0, 95.0, "deg", "Vinkeln grenarna växer ut i från stammen"],
	["Kronform", "crown", 0.0, 1.0, "%", "Spetsig som en gran, rund, eller bred som ett paraply"],
	["Stambas", "branch_start", 0.05, 0.75, "%", "Hur högt upp de första grenarna sitter"],
	["Lövmängd", "leaves", 0.0, 1.0, "%", "Hur tät kronan är; noll ger ett kalt träd"],
	["Lövstorlek", "leaf_size", 0.3, 2.0, "x", "Hur stora lövklungorna är"],
	["Frukt", "fruit", 0.0, 1.0, "%", "Äpplen, bär eller blom i kronan"],
	["Fruktstorlek", "fruit_size", 0.3, 2.5, "x", "Hur stora frukterna är"],
]
const CONIFER_DIALS := [
	["Höjd", "size", 1.5, 14.0, "m", "Hur hög granen är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket granarna skiljer sig i höjd"],
	["Stam", "trunk", 0.06, 0.6, "m", "Stammens tjocklek"],
	["Våningar", "branches", 2.0, 14.0, "count", "Hur många grenvåningar granen har"],
	["Bredd", "branch_len", 0.3, 1.6, "x", "Hur breda våningarna är"],
	["Hängning", "angle", 0.0, 60.0, "deg", "Hur mycket grenarna hänger"],
	["Kronform", "crown", 0.0, 1.0, "%", "Spetsig kon, eller rundare topp"],
	["Stambas", "branch_start", 0.0, 0.6, "%", "Hur högt upp de nedersta grenarna sitter"],
	["Fransighet", "bend", 0.0, 1.0, "%", "Släta kanter, eller fransiga och taggiga"],
	["Krokighet", "leaves", 0.0, 1.0, "%", "Rak eller lite krokig stam"],
]


const BUSH_DIALS := [
	["Höjd", "size", 0.3, 3.0, "m", "Hur hög busken är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket buskarna skiljer sig i höjd"],
	["Krokighet", "bend", 0.0, 1.0, "%", "Raka eller knotiga grenar"],
	["Grenar", "branches", 2.0, 12.0, "count", "Hur många grenar som växer upp ur roten"],
	["Förgrening", "levels", 1.0, 3.0, "count", "Hur många led grenarna delar sig i"],
	["Grenvinkel", "angle", 15.0, 90.0, "deg", "Upprätt eller utbredd"],
	["Lövmängd", "leaves", 0.0, 1.0, "%", "Hur tät busken är"],
	["Lövstorlek", "leaf_size", 0.2, 1.5, "x", "Hur stora lövklungorna är"],
	["Blom/bär", "fruit", 0.0, 1.0, "%", "Blommor eller bär på busken"],
	["Storlek", "fruit_size", 0.3, 2.5, "x", "Hur stora blommorna eller bären är"],
]
const FERN_DIALS := [
	["Storlek", "size", 0.15, 2.0, "m", "Hur hög ormbunken är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
	["Blad", "fronds", 3.0, 16.0, "count", "Hur många blad som växer ur mitten"],
	["Böjning", "arch", 0.0, 1.0, "%", "Hur mycket bladen böjer sig ner"],
	["Bredd", "width", 0.15, 1.0, "%", "Hur breda bladen är"],
]
const FLOWER_DIALS := [
	["Höjd", "size", 0.1, 1.2, "m", "Hur höga blommorna är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i höjd"],
	["Stjälkar", "stems", 1.0, 9.0, "count", "Hur många blommor i varje tuva"],
	["Kronblad", "petals", 3.0, 14.0, "count", "Hur många kronblad varje blomma har"],
	["Blomstorlek", "bloom", 0.4, 2.5, "x", "Hur stora blommorna är"],
	["Kupning", "cup", 0.0, 1.0, "%", "Platta som en prästkrage, eller kupade som en tulpan"],
]
const CLOVER_DIALS := [
	["Storlek", "size", 0.15, 1.5, "m", "Hur stor varje klövertuva är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket tuvorna skiljer sig"],
	["Täthet", "count", 4.0, 40.0, "count", "Hur många blad i en tuva"],
	["Blommor", "heads", 0.0, 1.0, "%", "Hur många blomhuvuden"],
]
const MUSHROOM_DIALS := [
	["Höjd", "size", 0.05, 0.8, "m", "Hur höga svamparna är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
	["Antal", "count", 1.0, 7.0, "count", "Hur många svampar i varje klunga"],
	["Hattbredd", "cap_width", 0.4, 2.0, "x", "Hur breda hattarna är"],
	["Hattform", "cap_shape", 0.0, 1.0, "%", "Platt, välvd eller klockformad hatt"],
	["Prickar", "spots", 0.0, 1.0, "%", "Vita prickar på hatten, som en flugsvamp"],
]
const GRASS_DIALS := [
	["Höjd", "size", 0.15, 1.5, "m", "Hur högt gräset är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket tuvorna skiljer sig i höjd"],
	["Strån", "blades", 4.0, 50.0, "count", "Hur många strån i varje tuva"],
	["Böjning", "bend", 0.0, 1.0, "%", "Raka strån, eller böjda som i vind"],
	["Bredd", "width", 0.3, 3.0, "x", "Hur breda stråna är"],
	["Spridning", "spread", 0.0, 1.0, "%", "Tät tuva, eller utspridd"],
	["Vippor", "heads", 0.0, 1.0, "%", "Fröställningar ovanför stråna"],
	["Gräsfärg", "lawn", 0.0, 1.0, "%", "Hur mycket gräset tar efter gräsmattan; noll ger den egna färgen"],
]
const ITEM_DIALS := [
	["Storlek", "size", 0.3, 3.0, "x", "Hur stor saken är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
]
const LIGHT_DIALS := [
	["Storlek", "size", 0.3, 3.0, "x", "Hur stor saken är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
	["Ljusstyrka", "glow", 0.0, 3.0, "x", "Hur starkt det lyser"],
]
const DEADWOOD_DIALS := [
	["Storlek", "size", 0.3, 3.0, "x", "Hur stor den är"],
	["Variation", "variation", 0.0, 1.0, "%", "Hur mycket de skiljer sig i storlek"],
	["Tjocklek", "thick", 0.4, 2.5, "x", "Hur grov den är"],
	["Mossa", "moss", 0.0, 1.0, "%", "Hur mossig den är"],
	["Svampar", "fungi", 0.0, 1.0, "%", "Tickor som växer på den"],
]
## The tab of small things: groups and the kinds in them.
const ITEMS := [
	["Ljus och eld", ["eldstad", "fackla", "ljus", "lykta"]],
	["Läger", ["talt", "ryggsack", "koffert", "gryta", "filt"]],
	["Ved och verktyg", ["huggkubbe", "yxa", "vedtrave", "stockhog", "spade", "hacka"]],
	["Smått", ["flaskor", "bocker", "svampkorg", "tunna", "skylt"]],
]
## The colours a kind's dials can set: label and style key.
const DIAL_COLORS := {
	"stone": [["Färg", "tint"]],
	"item": [["Färg", "color_a"], ["Färg 2", "color_b"]],
	"light": [["Färg", "color_a"]],
	"deadwood": [["Bark", "color_a"], ["Svamp", "color_b"]],
	"tree": [["Löv", "leaf_color"], ["Bark", "bark_color"], ["Frukt", "fruit_color"]],
	"bush": [["Löv", "leaf_color"], ["Blom/bär", "fruit_color"]],
	"conifer": [["Barr", "leaf_color"], ["Bark", "bark_color"]],
	"fern": [["Färg", "color_a"]],
	"flower": [["Blad", "color_a"], ["Kronblad", "color_b"], ["Mitt", "color_c"]],
	"clover": [["Blad", "color_a"], ["Blomma", "color_b"]],
	"mushroom": [["Hatt", "color_b"], ["Fot", "color_a"], ["Prickar", "color_c"]],
	"grass": [["Strå", "color_a"], ["Vippa", "color_c"]],
}
const DIALS := {"stone": STONE_DIALS, "tree": TREE_DIALS, "conifer": CONIFER_DIALS, "bush": BUSH_DIALS, "fern": FERN_DIALS,
	"flower": FLOWER_DIALS, "item": ITEM_DIALS, "light": LIGHT_DIALS, "deadwood": DEADWOOD_DIALS, "clover": CLOVER_DIALS, "mushroom": MUSHROOM_DIALS, "grass": GRASS_DIALS}


const TREES := ["lovtrad", "gran", "krokigt", "torrtrad", "sagotrad"]
static var _rock_mat: ShaderMaterial
static var _plant_mat: ShaderMaterial
## The prop layer, which knows what stands round a tree (see TreeBuilder env).
static var context: Object


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
		"item":
			var st := RockBuilder.style_of(k.style, rec.get("style"))
			node = ItemBuilder.build(k.gen, st, int(rec.variant), {"over_fire": rec.get("over_fire", false)})
			node.scale = Vector3.ONE * size
			node.set_meta("tall", float(node.get_meta("tall", 0.3)) * size)
			node.rotation.y = rec.rot
			return node
		"plant":
			var st := RockBuilder.style_of(k.style, rec.get("style"))
			var mi := MeshInstance3D.new()
			mi.mesh = PlantGen.mesh(k.gen, st, int(rec.variant))
			mi.scale = Vector3.ONE * size
			if _plant_mat == null:
				_plant_mat = ShaderMaterial.new()
				_plant_mat.shader = load("res://shaders/plant.gdshader")
			mi.material_override = _plant_mat
			# thin double-sided petals and caps shadow themselves in speckles; only
			# the taller leafy kinds cast shadows
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k.gen in ["fern", "grass"] and size > 0.3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for key in ["color_a", "color_b", "color_c"]:
				var col: Array = st[key]
				mi.set_instance_shader_parameter(key, Vector3(col[0], col[1], col[2]))
			mi.set_instance_shader_parameter("spots", float(st.get("spots", 0.0)))
			mi.set_instance_shader_parameter("lawn", float(st.get("lawn", 0.0)))
			var hue: float = rec.hue
			mi.set_instance_shader_parameter("tint", Vector3(1.0 + (hue - 0.5) * 0.12, 1.0 + (hue - 0.5) * 0.06, 1.0 - (hue - 0.5) * 0.1))
			mi.set_meta("tall", mi.mesh.get_aabb().size.y * size)
			mi.rotation.y = rec.rot
			mi.set_meta("shaded", mi)
			return mi
		"tree":
			var st := RockBuilder.style_of(k.style, rec.get("style"))
			var lc: Array = st.leaf_color
			var hue: float = rec.hue
			# each tree a touch lighter or darker than its neighbours
			st.leaf_color = [lc[0] * (0.92 + 0.16 * hue), lc[1] * (0.94 + 0.12 * hue), lc[2]]
			node = TreeBuilder.build(st, size, int(rec.variant), _env(rec))
			node.set_meta("tall", size)
			node.rotation.y = rec.rot
			node.set_meta("shaded", node.get_child(0))
			return node
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


## What a tree needs to know about where it stands, in its own frame.
static func _env(rec: Dictionary) -> Dictionary:
	if context == null:
		return {}
	var ctx = context
	var base_y: float = ctx.ground_at(rec.x, rec.z)
	var rot := Basis(Vector3.UP, float(rec.rot))
	var inv := rot.inverse()
	var origin := Vector3(rec.x, base_y, rec.z)
	var merge: Array = ctx.merge_with(rec)
	return {
		"top": func(q: Vector3) -> float:
			var w := origin + rot * q
			return float(ctx.obstacle_top(w.x, w.z)) - base_y,
		"lean": inv * (merge[0] as Vector3),
		"base": inv * (merge[1] as Vector3),
	}


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
