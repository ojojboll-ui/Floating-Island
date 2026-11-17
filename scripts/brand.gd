extends RefCounted
## Skyholme's name as a picture: the wordmark and the emblem.
##
## Both are drawn here as SVG and turned into textures at whatever size is
## asked for, so they are sharp on any screen and nothing has to be
## imported. The wordmark is lettering of our own (no typeface): one round
## pen stroke per letter, and for the o a sun with a little island and its
## tree cut out of it: the sky and the holme of the name. tools/brand_export.gd writes them out as files for the
## shop pages and the program icon.

const NAME := "Skyholme"

# the lettering sits on these lines (SVG units, y down)
const CAP := 40.0
const XH := 104.0
const BASE := 200.0
const PEN := 24.0
const WIDTH := 892.0
const MARGIN := 34.0

## Each letter: how far along the line it starts, and its strokes.
const LETTERS := [
	[8.0, "M 84,74 C 78,42 30,30 14,64 C -6,108 92,110 86,164 C 80,206 22,210 2,172"],   # S
	[130.0, "M 0,40 L 0,200 M 60,104 L 2,160 M 24,140 L 66,200"],                              # k
	[228.0, "M 0,104 L 40,196 M 80,104 C 62,152 46,204 30,234 C 22,250 10,260 -6,258"],        # y
	[344.0, "M 0,40 L 0,200 M 0,150 C 0,96 72,92 72,150 L 72,200"],                            # h
	[454.0, "M 50,102 C 116,102 116,202 50,202 C -16,202 -16,102 50,102 Z"],                   # o
	[592.0, "M 0,40 L 0,200"],                                                                # l
	[634.0, "M 0,104 L 0,200 M 0,148 C 0,96 62,94 62,148 L 62,200 M 62,148 C 62,96 124,94 124,148 L 124,200"],   # m
	[796.0, "M 4,152 L 96,152 C 98,92 4,86 4,152 C 4,216 74,212 92,182"],                      # e
]

## The o as a sun with the island cut out of it, in the o's own frame: the
## disc, then (one outline, so it can be a hole) the island's top, its tree
## and the rock hanging under it.
const SUN := "M 50,92 C 127,92 127,208 50,208 C -27,208 -27,92 50,92 Z"
const HOLME := "M 9,157 C 22,149 36,149 46,149 L 46,139 A 19.5 19.5 0 1 1 54,139 L 54,149 C 64,149 78,149 91,157 L 85,168 L 73,172 L 67,189 L 58,181 L 50,202 L 42,183 L 34,191 L 27,172 L 15,168 Z"


## The wordmark as SVG, in one colour. Without `holme` the o is a plain
## ring (the island is too fine to read below about 200 pixels wide).
static func wordmark_svg(color := Color(1.0, 0.975, 0.93), holme := true) -> String:
	var hex := "#" + color.to_html(false)
	var w := WIDTH + MARGIN * 2.0
	var h := 262.0 + MARGIN * 2.0 - 10.0
	var out := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\">\n" % [w, h, w, h]
	out += "<g fill=\"none\" stroke=\"%s\" stroke-width=\"%d\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-opacity=\"%.3f\">\n" % [hex, PEN, color.a]
	for k in LETTERS.size():
		if k == 4 and holme:
			continue
		var l: Array = LETTERS[k]
		out += "<path transform=\"translate(%.1f %.1f)\" d=\"%s\"/>\n" % [float(l[0]) + MARGIN, MARGIN - 20.0, l[1]]
	out += "</g>\n"
	if holme:
		out += "<path transform=\"translate(%.1f %.1f)\" fill=\"%s\" fill-opacity=\"%.3f\" fill-rule=\"evenodd\" d=\"%s %s\"/>\n" % [float(LETTERS[4][0]) + MARGIN, MARGIN - 20.0, hex, color.a, SUN, HOLME]
	out += "</svg>\n"
	return out


## The emblem: the island with its tree in a patch of sky, for the program
## icon and wherever the name does not fit. `plate` draws the rounded
## square of sky behind it.
static func emblem_svg(plate := true) -> String:
	var out := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\">\n"
	out += "<defs>\n"
	out += "<linearGradient id=\"sky\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#5f96cf\"/><stop offset=\"1\" stop-color=\"#a9d2ee\"/></linearGradient>\n"
	out += "<linearGradient id=\"rock\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#8a6a4c\"/><stop offset=\"1\" stop-color=\"#5a4334\"/></linearGradient>\n"
	out += "<linearGradient id=\"leaf\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#8fc45a\"/><stop offset=\"1\" stop-color=\"#4f8f3c\"/></linearGradient>\n"
	out += "</defs>\n"
	if plate:
		out += "<rect x=\"8\" y=\"8\" width=\"240\" height=\"240\" rx=\"54\" fill=\"url(#sky)\"/>\n"
		# clouds
		out += "<g fill=\"#ffffff\" fill-opacity=\"0.92\">\n"
		out += "<path d=\"M 34,96 C 30,82 46,74 56,82 C 60,68 84,70 84,86 C 96,86 96,102 84,102 L 42,102 C 36,102 34,100 34,96 Z\"/>\n"
		out += "<path d=\"M 176,70 C 174,60 186,54 193,60 C 197,50 214,52 214,64 C 224,64 224,76 214,76 L 183,76 C 178,76 176,74 176,70 Z\"/>\n"
		out += "<path d=\"M 166,214 C 163,203 176,196 184,203 C 189,191 208,194 208,207 C 219,207 219,221 208,221 L 174,221 C 168,221 166,218 166,214 Z\" fill-opacity=\"0.8\"/>\n"
		out += "</g>\n"
	# the rock under the island, in facets
	out += "<path d=\"M 58,150 L 198,150 L 180,176 L 166,180 L 152,214 L 140,196 L 128,236 L 114,200 L 100,206 L 90,178 L 74,174 Z\" fill=\"url(#rock)\"/>\n"
	out += "<path d=\"M 128,236 L 114,200 L 122,160 L 140,196 Z\" fill=\"#000000\" fill-opacity=\"0.14\"/>\n"
	out += "<path d=\"M 152,214 L 140,196 L 160,160 L 166,180 Z\" fill=\"#ffffff\" fill-opacity=\"0.08\"/>\n"
	out += "<path d=\"M 100,206 L 90,178 L 104,160 L 114,200 Z\" fill=\"#ffffff\" fill-opacity=\"0.06\"/>\n"
	# soil, then the grass on top
	out += "<path d=\"M 52,146 C 52,132 204,132 204,146 C 204,158 196,162 188,160 C 180,166 170,160 162,164 C 152,170 142,162 132,166 C 120,170 112,162 102,166 C 92,170 84,160 74,162 C 62,164 52,158 52,146 Z\" fill=\"#6b4a33\"/>\n"
	out += "<path d=\"M 50,142 C 50,124 206,124 206,142 C 206,154 196,156 188,154 C 180,160 170,154 162,158 C 152,164 142,156 132,160 C 120,164 112,156 102,160 C 92,164 84,154 74,156 C 62,158 50,154 50,142 Z\" fill=\"#7fb851\"/>\n"
	out += "<path d=\"M 62,138 C 80,128 176,128 194,138 C 170,134 86,134 62,138 Z\" fill=\"#a6d86c\"/>\n"
	# the tree: trunk and three rounds of crown
	out += "<path d=\"M 121,140 C 124,122 122,108 118,96 L 136,96 C 133,110 133,124 137,140 Z\" fill=\"#6e4a30\"/>\n"
	out += "<circle cx=\"128\" cy=\"66\" r=\"36\" fill=\"url(#leaf)\"/>\n"
	out += "<circle cx=\"100\" cy=\"86\" r=\"24\" fill=\"#5a9a42\"/>\n"
	out += "<circle cx=\"156\" cy=\"86\" r=\"25\" fill=\"#559440\"/>\n"
	out += "<circle cx=\"128\" cy=\"62\" r=\"30\" fill=\"#7fba50\"/>\n"
	out += "<circle cx=\"118\" cy=\"52\" r=\"14\" fill=\"#a6d86c\" fill-opacity=\"0.8\"/>\n"
	out += "</svg>\n"
	return out


## An SVG as a texture, `width` pixels wide.
static func texture(svg: String, width: int) -> ImageTexture:
	return ImageTexture.create_from_image(image(svg, width))


static func image(svg: String, width: int) -> Image:
	var img := Image.new()
	var native := svg.get_slice("width=\"", 1).get_slice("\"", 0).to_float()
	img.load_svg_from_string(svg, float(width) / maxf(native, 1.0))
	return img
