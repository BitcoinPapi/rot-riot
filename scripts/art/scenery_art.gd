class_name SceneryArt
extends RefCounted
## Small drawings for the map: what grows and lies round the pond (reeds, lily
## pads, wet stones, fish under the water) and the details painted on the
## ground (grass, ferns, flowers, fallen leaves, stones, twigs, mushrooms, old
## bones, puddles). Everything returns an SVG drawing as text, with (0, 0) in
## the middle; Art turns them into pictures. Sizes are game pixels.
##
## Each drawing is scattered by its own fixed number, so it looks the same on
## every computer and every time.

const INK := "#1b1d17"


static func _f(v: float) -> String:
	return String.num(v, 2)


static func _rng(number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = number
	return rng


## One blade of grass or reed from (0, 0) outward, bent a little: a dark stroke with a lighter one on it.
static func _blade(turn: float, length: float, bend: float, width: float, dark: String, light: String) -> String:
	var d := "M0,0 Q%s,%s %s,%s" % [_f(length * 0.55), _f(bend), _f(length), _f(bend * 0.4)]
	return "<g transform=\"rotate(%s)\"><path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\"/><path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\"/></g>" % [
			_f(turn), d, dark, _f(width + 1.1), d, light, _f(width)]


## A tuft seen from above: blades leaning out from the middle.
static func tuft(number: int, blades: int, length: float, width: float, dark: String, lights: Array) -> String:
	var rng := _rng(number)
	var out := "<circle cx=\"0\" cy=\"0\" r=\"%s\" fill=\"#000000\" fill-opacity=\"0.22\"/>" % _f(length * 0.5)
	for i in blades:
		out += _blade(360.0 * float(i) / float(blades) + rng.randf_range(-16.0, 16.0), length * rng.randf_range(0.6, 1.0), rng.randf_range(-2.4, 2.4),
				width, dark, String(lights[i % lights.size()]))
	return out


## Reeds at the pond's edge: a tuft of long blades with a few brown heads.
static func reeds() -> String:
	var rng := _rng(301)
	var out := tuft(300, 11, 13.0, 1.5, "#27381c", ["#5f7f38", "#7a9a4a", "#4f6d30"])
	for i in 4:
		var turn := rng.randf() * 360.0
		out += "<g transform=\"rotate(%s)\"><ellipse cx=\"%s\" cy=\"0\" rx=\"2.7\" ry=\"1.25\" fill=\"#5b3a20\" stroke=\"%s\" stroke-width=\"0.5\"/></g>" % [_f(turn), _f(rng.randf_range(6.0, 11.0)), INK]
	return out


static func lily() -> String:
	return "<path d=\"M0,0 L8.7,-2.5 A9,9 0 1 0 8.7,2.5 Z\" fill=\"#4a7a37\" stroke=\"#1c3519\" stroke-width=\"1\" stroke-linejoin=\"round\"/>" \
			+ "<path d=\"M0,0 L-7,-4 M0,0 L-8.2,1.8 M0,0 L-2.2,-8 M0,0 L-1.4,8 M0,0 L5,6.6 M0,0 L4.4,-7\" stroke=\"#33602a\" stroke-width=\"0.7\" fill=\"none\"/>" \
			+ "<ellipse cx=\"-3\" cy=\"-3\" rx=\"4\" ry=\"2.4\" fill=\"#8fb86a\" fill-opacity=\"0.35\"/>"


static func lily_flower() -> String:
	var out := ""
	for i in 7:
		out += "<ellipse cx=\"2.6\" cy=\"0\" rx=\"2.9\" ry=\"1.35\" fill=\"#f4e6ee\" stroke=\"#b98aa2\" stroke-width=\"0.4\" transform=\"rotate(%s)\"/>" % _f(360.0 * float(i) / 7.0)
	return out + "<circle cx=\"0\" cy=\"0\" r=\"1.5\" fill=\"#e9c247\"/>"


static func stone() -> String:
	return "<ellipse cx=\"0.8\" cy=\"1.4\" rx=\"7\" ry=\"5.4\" fill=\"#000000\" fill-opacity=\"0.3\"/>" \
			+ "<path d=\"M-6,1 Q-6.2,-4.4 -1,-5 Q5,-5.2 6.4,-0.6 Q6.6,4 1,4.8 Q-5,5 -6,1 Z\" fill=\"#6c726c\" stroke=\"%s\" stroke-width=\"1.1\" stroke-linejoin=\"round\"/>" % INK \
			+ "<path d=\"M-3.6,-2.4 Q-0.6,-4 2.8,-2.8\" stroke=\"#aeb5ad\" stroke-width=\"1.1\" fill=\"none\" stroke-linecap=\"round\"/>" \
			+ "<path d=\"M1,2.6 Q3.6,2.6 4.8,0.6\" stroke=\"#444a45\" stroke-width=\"0.9\" fill=\"none\" stroke-linecap=\"round\"/>"


## A fish seen through the water: only a dark shape.
static func fish() -> String:
	return "<path d=\"M9,0 Q4,-3.4 -3,-2 L-9,-4.2 L-7,0 L-9,4.2 L-3,2 Q4,3.4 9,0 Z\" fill=\"#0c1a1a\" fill-opacity=\"0.5\"/>"


# ----------------------------------------------------------------------------
#  Details on the ground
# ----------------------------------------------------------------------------
static func grass(number: int) -> String:
	return tuft(number, 8 + number % 3, 9.5, 1.2, "#27321a", ["#55692f", "#65803a", "#48592a"])


static func fern() -> String:
	var rng := _rng(77)
	var out := "<circle cx=\"0\" cy=\"0\" r=\"8\" fill=\"#000000\" fill-opacity=\"0.2\"/>"
	for i in 6:
		var reach := rng.randf_range(9.0, 13.0)
		out += "<g transform=\"rotate(%s)\"><path d=\"M0,0 Q%s,-3.4 %s,0 Q%s,3.4 0,0 Z\" fill=\"#3f6330\" stroke=\"#1f3319\" stroke-width=\"0.7\" stroke-linejoin=\"round\"/><path d=\"M1,0 L%s,0\" stroke=\"#6c8f4a\" stroke-width=\"0.6\"/></g>" % [
				_f(60.0 * i + rng.randf_range(-10.0, 10.0)), _f(reach * 0.5), _f(reach), _f(reach * 0.5), _f(reach - 1.5)]
	return out


static func leaves() -> String:
	var rng := _rng(91)
	var colors := ["#8a5a26", "#a8702c", "#6b4a22", "#b98a3a", "#7a3f1e"]
	var out := ""
	for i in 7:
		out += "<g transform=\"translate(%s %s) rotate(%s)\"><path d=\"M-3.6,0 Q0,-2.6 3.6,0 Q0,2.6 -3.6,0 Z\" fill=\"%s\" stroke=\"#2a1c10\" stroke-width=\"0.5\"/><path d=\"M-3,0 L3,0\" stroke=\"#2a1c10\" stroke-width=\"0.4\"/></g>" % [
				_f(rng.randf_range(-9.0, 9.0)), _f(rng.randf_range(-7.0, 7.0)), _f(rng.randf() * 360.0), String(colors[i % colors.size()])]
	return out


static func stones() -> String:
	var rng := _rng(55)
	var out := ""
	for i in 4:
		var x := rng.randf_range(-7.5, 7.5)
		var y := rng.randf_range(-5.0, 5.0)
		var r := rng.randf_range(2.2, 4.4)
		var grey := rng.randf_range(0.36, 0.52)
		out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" fill=\"#000000\" fill-opacity=\"0.32\"/>" % [_f(x + 0.8), _f(y + 1.1), _f(r), _f(r * 0.8)]
		out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" fill=\"#%s\" stroke=\"%s\" stroke-width=\"0.7\"/>" % [_f(x), _f(y), _f(r), _f(r * 0.78), Color(grey, grey, grey * 0.95).to_html(false), INK]
		out += "<path d=\"M%s,%s l%s,-0.5\" stroke=\"#b4b8b0\" stroke-width=\"0.7\" stroke-linecap=\"round\"/>" % [_f(x - r * 0.5), _f(y - r * 0.3), _f(r * 0.7)]
	return out


## A few small flowers with their leaves (`petal` = their colour).
static func flowers(number: int, petal: String, heart: String) -> String:
	var rng := _rng(number)
	var out := ""
	for i in 5:
		out += "<g transform=\"rotate(%s)\"><path d=\"M0,0 Q4,-1.8 8,0 Q4,1.8 0,0 Z\" fill=\"#44642f\" stroke=\"#22361a\" stroke-width=\"0.5\"/></g>" % _f(72.0 * i + rng.randf_range(-14.0, 14.0))
	for i in 4:
		var x := rng.randf_range(-6.0, 6.0)
		var y := rng.randf_range(-6.0, 6.0)
		out += "<g transform=\"translate(%s %s)\">" % [_f(x), _f(y)]
		for k in 5:
			out += "<circle cx=\"%s\" cy=\"%s\" r=\"1.25\" fill=\"%s\"/>" % [_f(cos(TAU * k / 5.0) * 1.7), _f(sin(TAU * k / 5.0) * 1.7), petal]
		out += "<circle cx=\"0\" cy=\"0\" r=\"0.9\" fill=\"%s\"/></g>" % heart
	return out


static func twig() -> String:
	return "<path d=\"M-17,2 Q-6,-2.4 4,0.4 Q11,2 17,-1.6\" fill=\"none\" stroke=\"#1f150c\" stroke-width=\"3.4\" stroke-linecap=\"round\"/>" \
			+ "<path d=\"M-17,2 Q-6,-2.4 4,0.4 Q11,2 17,-1.6\" fill=\"none\" stroke=\"#6b4a2a\" stroke-width=\"2\" stroke-linecap=\"round\"/>" \
			+ "<path d=\"M-4,-0.8 L-8,-5.4 M6,0.9 L10,5.6\" fill=\"none\" stroke=\"#1f150c\" stroke-width=\"2.4\" stroke-linecap=\"round\"/>" \
			+ "<path d=\"M-4,-0.8 L-8,-5.4 M6,0.9 L10,5.6\" fill=\"none\" stroke=\"#6b4a2a\" stroke-width=\"1.2\" stroke-linecap=\"round\"/>"


static func mushrooms() -> String:
	var out := ""
	for cap: Array in [[-3.4, 1.0, 3.4, "#b9824a"], [3.0, -1.6, 2.7, "#a86a3c"], [1.6, 3.6, 2.0, "#c79a5e"]]:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#000000\" fill-opacity=\"0.3\"/>" % [_f(float(cap[0]) + 0.6), _f(float(cap[1]) + 0.9), _f(float(cap[2]))]
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.6\"/>" % [_f(float(cap[0])), _f(float(cap[1])), _f(float(cap[2])), String(cap[3]), INK]
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#ecd9b0\" fill-opacity=\"0.8\"/>" % [_f(float(cap[0]) - 0.8), _f(float(cap[1]) - 0.8), _f(float(cap[2]) * 0.28)]
	return out


## Old bones, half sunk into the earth.
static func bones() -> String:
	var out := ""
	for bone: Array in [[-3.0, -2.0, 24.0, 9.0], [3.0, 3.0, -38.0, 7.0]]:
		var half := float(bone[3]) * 0.5
		out += "<g transform=\"translate(%s %s) rotate(%s)\">" % [_f(float(bone[0])), _f(float(bone[1])), _f(float(bone[2]))]
		out += "<path d=\"M%s,0 L%s,0\" stroke=\"%s\" stroke-width=\"3.2\" stroke-linecap=\"round\"/>" % [_f(-half), _f(half), INK]
		out += "<path d=\"M%s,0 L%s,0\" stroke=\"#d9cfb4\" stroke-width=\"1.8\" stroke-linecap=\"round\"/>" % [_f(-half), _f(half)]
		for end: float in [-half, half]:
			out += "<circle cx=\"%s\" cy=\"-1\" r=\"1.5\" fill=\"#d9cfb4\" stroke=\"%s\" stroke-width=\"0.6\"/><circle cx=\"%s\" cy=\"1\" r=\"1.5\" fill=\"#d9cfb4\" stroke=\"%s\" stroke-width=\"0.6\"/>" % [_f(end), INK, _f(end), INK]
		out += "</g>"
	return out


## A puddle of muddy water with a glint on it.
static func puddle() -> String:
	return "<path d=\"M-17,1 Q-18,-8 -7,-9.6 Q3,-12 12,-7.4 Q19,-3 16.4,4.6 Q13,11 2,10.4 Q-12,11.4 -17,1 Z\" fill=\"#231c14\" fill-opacity=\"0.6\"/>" \
			+ "<path d=\"M-13,0.6 Q-13.6,-6 -5,-7 Q3,-8.6 10,-5 Q14.6,-2 12.6,3.4 Q10,7.6 1.6,7.4 Q-9.6,8 -13,0.6 Z\" fill=\"#3a4a44\" fill-opacity=\"0.8\"/>" \
			+ "<path d=\"M-7,-3.4 Q-2,-5.4 4,-4.4\" stroke=\"#a9c0b6\" stroke-width=\"1.1\" fill=\"none\" stroke-linecap=\"round\" stroke-opacity=\"0.7\"/>"


# ----------------------------------------------------------------------------
#  Scenery: bushes, heaps of rubble, tires (the ones that burn)
# ----------------------------------------------------------------------------
## A bush seen from above: clumps of leaves, darker underneath, lighter on top.
## `flower` = the colour of its blossoms ("" = none).
static func bush(number: int, half_w: float, half_h: float, flower: String) -> String:
	var rng := _rng(number)
	var out := "<ellipse cx=\"3\" cy=\"4\" rx=\"%s\" ry=\"%s\" fill=\"#000000\" fill-opacity=\"0.3\"/>" % [_f(half_w * 0.96), _f(half_h * 0.96)]
	var clumps: Array = []
	for i in 17:
		var turn := rng.randf() * TAU
		var out_by := sqrt(rng.randf())
		clumps.append(Vector3(cos(turn) * out_by * (half_w - 12.0), sin(turn) * out_by * (half_h - 12.0), rng.randf_range(8.0, 12.0)))
	for c: Vector3 in clumps:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#14230e\"/>" % [_f(c.x), _f(c.y), _f(c.z + 1.5)]
	for c: Vector3 in clumps:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#2f4f1d\"/>" % [_f(c.x), _f(c.y), _f(c.z)]
	for c: Vector3 in clumps:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#44702a\" fill-opacity=\"0.9\"/>" % [_f(c.x - c.z * 0.24), _f(c.y - c.z * 0.26), _f(c.z * 0.64)]
	for c: Vector3 in clumps:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#63933a\" fill-opacity=\"0.8\"/>" % [_f(c.x - c.z * 0.4), _f(c.y - c.z * 0.42), _f(c.z * 0.3)]
		out += "<path d=\"M%s,%s q%s,%s %s,0\" fill=\"none\" stroke=\"#14230e\" stroke-width=\"0.8\" stroke-opacity=\"0.6\" stroke-linecap=\"round\"/>" % [
				_f(c.x - 1.0), _f(c.y + c.z * 0.4), _f(c.z * 0.35), _f(c.z * 0.3), _f(c.z * 0.7)]
	if flower != "":
		for i in 6:
			var c: Vector3 = clumps[i * 2]
			out += "<circle cx=\"%s\" cy=\"%s\" r=\"2.3\" fill=\"%s\" stroke=\"#3a0f0c\" stroke-width=\"0.5\"/><circle cx=\"%s\" cy=\"%s\" r=\"0.8\" fill=\"#f3d27a\"/>" % [
					_f(c.x + 2.0), _f(c.y - 1.0), flower, _f(c.x + 2.0), _f(c.y - 1.0)]
	return out


## A heap of rubble: broken concrete, a few bricks, a plank, a bent iron bar, dust round it.
static func rubble(number: int) -> String:
	var rng := _rng(number)
	var out := "<ellipse cx=\"0\" cy=\"0\" rx=\"44\" ry=\"32\" fill=\"#6b6455\" fill-opacity=\"0.3\"/><ellipse cx=\"0\" cy=\"1\" rx=\"32\" ry=\"22\" fill=\"#3a352c\" fill-opacity=\"0.35\"/>"
	out += "<g transform=\"rotate(%s)\"><rect x=\"-27\" y=\"-3\" width=\"48\" height=\"6\" rx=\"1\" fill=\"#6b4a2a\" stroke=\"%s\" stroke-width=\"1\"/><path d=\"M-22,0 L16,0\" stroke=\"#8a6238\" stroke-width=\"1\"/></g>" % [
			_f(rng.randf_range(-40.0, 40.0)), INK]
	for i in 10:
		var cx := rng.randf_range(-28.0, 28.0)
		var cy := rng.randf_range(-18.0, 18.0)
		var r := rng.randf_range(5.0, 10.5)
		var corners := rng.randi_range(4, 6)
		var first := rng.randf() * TAU
		var d := ""
		var top := ""
		for k in corners:
			var turn := first + TAU * float(k) / float(corners) + rng.randf_range(-0.3, 0.3)
			var reach := r * rng.randf_range(0.7, 1.0)
			d += "%s%s,%s " % ["M" if k == 0 else "L", _f(cx + cos(turn) * reach), _f(cy + sin(turn) * reach)]
			top += "%s%s,%s " % ["M" if k == 0 else "L", _f(cx - 1.0 + cos(turn) * reach * 0.55), _f(cy - 1.2 + sin(turn) * reach * 0.55)]
		var grey := rng.randf_range(0.4, 0.58)
		out += "<path d=\"%sZ\" fill=\"#000000\" fill-opacity=\"0.3\" transform=\"translate(1.4 2)\"/>" % d
		out += "<path d=\"%sZ\" fill=\"#%s\" stroke=\"%s\" stroke-width=\"0.9\" stroke-linejoin=\"round\"/>" % [d, Color(grey, grey, grey * 0.96).to_html(false), INK]
		out += "<path d=\"%sZ\" fill=\"#%s\" fill-opacity=\"0.8\"/>" % [top, Color(grey + 0.14, grey + 0.14, grey + 0.12).to_html(false)]
	for i in 5:
		out += "<g transform=\"translate(%s %s) rotate(%s)\"><rect x=\"-4.4\" y=\"-2.4\" width=\"8.8\" height=\"4.8\" rx=\"0.6\" fill=\"#9a4a34\" stroke=\"%s\" stroke-width=\"0.8\"/><path d=\"M-3,-0.8 L3,-0.8\" stroke=\"#c06a4c\" stroke-width=\"0.8\"/></g>" % [
				_f(rng.randf_range(-30.0, 30.0)), _f(rng.randf_range(-20.0, 20.0)), _f(rng.randf() * 180.0), INK]
	out += "<path d=\"M-20,12 Q-4,2 8,10 Q16,15 24,6\" fill=\"none\" stroke=\"%s\" stroke-width=\"2.6\" stroke-linecap=\"round\"/><path d=\"M-20,12 Q-4,2 8,10 Q16,15 24,6\" fill=\"none\" stroke=\"#5a4a3c\" stroke-width=\"1.2\" stroke-linecap=\"round\"/>" % INK
	return out


## One tire lying on the ground, charred, a few cinders glowing on it.
static func _one_tire(x: float, y: float, cinders: int, number: int) -> String:
	var rng := _rng(number)
	var out := "<ellipse cx=\"%s\" cy=\"%s\" rx=\"16.5\" ry=\"16.5\" fill=\"#000000\" fill-opacity=\"0.32\"/>" % [_f(x + 1.6), _f(y + 2.2)]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"15\" fill=\"#1c1c1b\" stroke=\"#0b0b0a\" stroke-width=\"1.4\"/>" % [_f(x), _f(y)]
	for k in 18:
		var turn := TAU * float(k) / 18.0
		out += "<path d=\"M%s,%s L%s,%s\" stroke=\"#3b3b38\" stroke-width=\"1.4\" stroke-linecap=\"round\"/>" % [
				_f(x + cos(turn) * 11.4), _f(y + sin(turn) * 11.4), _f(x + cos(turn + 0.16) * 14.2), _f(y + sin(turn + 0.16) * 14.2)]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"8.4\" fill=\"#2a241e\" stroke=\"#0b0b0a\" stroke-width=\"1.1\"/>" % [_f(x), _f(y)]
	out += "<path d=\"M%s,%s A12.6,12.6 0 0 1 %s,%s\" fill=\"none\" stroke=\"#5a5a55\" stroke-width=\"1.1\" stroke-linecap=\"round\" stroke-opacity=\"0.8\"/>" % [
			_f(x - 11.0), _f(y - 6.0), _f(x - 2.0), _f(y - 12.4)]
	for k in cinders:
		var turn := rng.randf() * TAU
		var reach := rng.randf_range(9.5, 13.5)
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#ff8a2a\" fill-opacity=\"0.9\"/>" % [_f(x + cos(turn) * reach), _f(y + sin(turn) * reach), _f(rng.randf_range(0.7, 1.4))]
	return out


static func tire() -> String:
	return _one_tire(0.0, 0.0, 7, 5)


## Two tires, one half on the other.
static func tires() -> String:
	return _one_tire(-9.0, 5.0, 5, 6) + _one_tire(9.0, -5.0, 7, 7)
