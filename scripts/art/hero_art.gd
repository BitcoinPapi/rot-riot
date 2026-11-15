class_name HeroArt
extends RefCounted
## JanJan, drawn from shapes after the owner's paintings of him: a camouflage
## backpack, a torn sand-coloured shirt, a red scarf, bare arms, fingerless
## gloves, the flag on his left shoulder.
##
## He is not one picture but a PUPPET: body, head, two arms (upper arm and
## forearm), legs and boots are separate pieces, so that the game can bend his
## arms to whatever gun he holds and move his feet when he walks (HeroRig puts
## the pieces together). Every piece is redrawn from the gear he wears - each
## piece of gear has a "look" in Config.GEAR_ITEMS.
##
## Everything here returns SVG drawings as text; Art turns them into pictures.
## Sizes are game pixels. From above he faces RIGHT (+x), +y is his right side.


# ----------------------------------------------------------------------------
#  Small helpers for writing SVG
# ----------------------------------------------------------------------------
static func _f(v: float) -> String:
	return String.num(v, 2)


static func _path(d: String, fill: String, stroke: String = "", width: float = 0.0, more: String = "") -> String:
	var line := "" if stroke == "" else " stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\" stroke-linecap=\"round\"" % [stroke, _f(width)]
	return "<path d=\"%s\" fill=\"%s\"%s %s/>" % [d, fill, line, more]


static func _circle(x: float, y: float, r: float, fill: String, stroke: String = "", width: float = 0.0, more: String = "") -> String:
	var line := "" if stroke == "" else " stroke=\"%s\" stroke-width=\"%s\"" % [stroke, _f(width)]
	return "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"%s %s/>" % [_f(x), _f(y), _f(r), fill, line, more]


static func _oval(x: float, y: float, rx: float, ry: float, fill: String, stroke: String = "", width: float = 0.0, more: String = "") -> String:
	var line := "" if stroke == "" else " stroke=\"%s\" stroke-width=\"%s\"" % [stroke, _f(width)]
	return "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" fill=\"%s\"%s %s/>" % [_f(x), _f(y), _f(rx), _f(ry), fill, line, more]


static func _box(x: float, y: float, w: float, h: float, corner: float, fill: String, stroke: String = "", width: float = 0.0, more: String = "") -> String:
	var line := "" if stroke == "" else " stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\"" % [stroke, _f(width)]
	return "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\" fill=\"%s\"%s %s/>" % [_f(x), _f(y), _f(w), _f(h), _f(corner), fill, line, more]


static func _line(x1: float, y1: float, x2: float, y2: float, color: String, width: float, more: String = "") -> String:
	return "<path d=\"M%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\" %s/>" % [
			_f(x1), _f(y1), _f(x2), _f(y2), color, _f(width), more]


## A shape filled with something that must not spill over its edge (camouflage
## blotches, shading, hair curls), with an ink outline on top.
static func _filled(id: String, d: String, base: String, inside: String, ink: String, width: float) -> String:
	return "<clipPath id=\"%s\"><path d=\"%s\"/></clipPath><path d=\"%s\" fill=\"%s\"/><g clip-path=\"url(#%s)\">%s</g>%s" % [
			id, d, d, base, id, inside, _path(d, "none", ink, width) if width > 0.0 else ""]


## Camouflage: uneven blotches scattered over a box (always the same ones for the same number).
static func _blots(number: int, box: Rect2, count: int, colors: Array, size: float, strength: float = 1.0) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = number
	var out := ""
	for i in count:
		var x := rng.randf_range(box.position.x, box.end.x)
		var y := rng.randf_range(box.position.y, box.end.y)
		out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" fill=\"%s\" fill-opacity=\"%s\" transform=\"rotate(%s %s %s)\"/>" % [
				_f(x), _f(y), _f(size * rng.randf_range(0.7, 1.5)), _f(size * rng.randf_range(0.35, 0.75)),
				String(colors[i % colors.size()]), _f(strength), _f(rng.randf_range(0.0, 180.0)), _f(x), _f(y)]
	return out


## Light from the upper left, shade at the lower right: makes a flat shape look round.
static func _round(box: Rect2, strength: float = 1.0) -> String:
	var c := box.get_center()
	return _oval(c.x - box.size.x * 0.22, c.y - box.size.y * 0.24, box.size.x * 0.42, box.size.y * 0.36, "#ffffff", "", 0.0, "fill-opacity=\"%s\"" % _f(0.13 * strength)) \
			+ _oval(c.x + box.size.x * 0.3, c.y + box.size.y * 0.34, box.size.x * 0.5, box.size.y * 0.4, "#000000", "", 0.0, "fill-opacity=\"%s\"" % _f(0.2 * strength))


## A colour made darker (amount 0..1) or lighter (negative amount).
static func _shade(color: String, amount: float) -> String:
	var c := Color(color)
	c = c.darkened(amount) if amount >= 0.0 else c.lightened(-amount)
	return "#" + c.to_html(false)


static func _style(look: Dictionary) -> String:
	return String(look.get("style", ""))


## The flag patch on his shoulder: blue over red, a white panel in the middle.
static func _flag(h: Dictionary, x: float, y: float, w: float, tall: float, turn: float) -> String:
	var ink := String(h["ink"])
	var out := "<g transform=\"translate(%s %s) rotate(%s)\">" % [_f(x), _f(y), _f(turn)]
	out += _box(-w * 0.5, -tall * 0.5, w, tall, tall * 0.08, String(h["flag_red"]), ink, maxf(tall * 0.14, 0.5))
	out += _box(-w * 0.5, -tall * 0.5, w, tall * 0.5, tall * 0.08, String(h["flag_blue"]))
	out += _box(-w * 0.17, -tall * 0.24, w * 0.34, tall * 0.48, 0.0, String(h["flag_white"]))
	out += _box(-w * 0.5, -tall * 0.5, w, tall, tall * 0.08, "none", ink, maxf(tall * 0.14, 0.5))
	return out + "</g>"


# ----------------------------------------------------------------------------
#  Seen from above: the pieces of the puppet
#
#  Where each piece's own (0, 0) is:  body = the middle between his shoulders;
#  head = its middle;  upper arm = the shoulder joint, the arm lies along +x;
#  forearm = the elbow, the fist is at Config.HERO_ARM_FORE;  leg = the ankle,
#  the leg lies along -x toward the hip;  boot = the ankle, toes toward +x.
# ----------------------------------------------------------------------------
## The soft shadow under him.
static func top_shadow() -> String:
	return _oval(-3.0, 0.0, 23.0, 19.0, "#000000", "", 0.0, "fill-opacity=\"0.2\"") + _oval(-3.0, 0.0, 17.0, 14.0, "#000000", "", 0.0, "fill-opacity=\"0.12\"")


## Shoulders, backpack, scarf and the pouches on his belt.
static func top_body(h: Dictionary, chest: Dictionary, belt: Dictionary, hurt: bool) -> String:
	var ink := String(h["ink"])
	var style := _style(chest)
	var out := ""

	# The pouches on his belt, peeking out at the hips beside the pack.
	var pouch := String(h["web"]) if belt.is_empty() else String(belt["color"])
	var flap := String(h["web_dark"]) if belt.is_empty() else String(belt["trim"])
	for side: float in [-1.0, 1.0]:
		var y := 10.4 if side > 0.0 else -16.0
		out += _box(-11.0, y, 8.6, 5.6, 1.5, pouch, ink, 1.0)
		out += _line(-10.2, y + (1.9 if side > 0.0 else 3.7), -3.2, y + (1.9 if side > 0.0 else 3.7), flap, 0.9)
		if belt.is_empty():
			# (his own belt: two spare magazines stick out of each pouch)
			for k in 2:
				out += _box(-9.6 + 3.5 * k, y + (3.3 if side > 0.0 else 0.5), 2.3, 1.8, 0.4, String(h["mag"]), ink, 0.5)
		else:
			out += _circle(-6.7, y + 2.8, 0.8, flap)

	# Shoulders and chest: the torn shirt, or the jacket he wears over it.
	var cloth := String(chest["color"]) if style == "jacket" else String(h["shirt"])
	var torso := "M-7,-11.6 Q-9.6,0 -7,11.6 Q0.5,14.6 6.4,10.8 Q10.6,0 6.4,-10.8 Q0.5,-14.6 -7,-11.6 Z"
	out += _filled("hb", torso, cloth, _round(Rect2(-9.0, -14.0, 19.0, 28.0)) + _oval(-8.0, 0.0, 4.5, 14.0, "#000000", "", 0.0, "fill-opacity=\"0.16\""), ink, 1.2)
	if style == "vest" or style == "armor":
		# A vest shows from above as its two broad shoulder pieces.
		for side: float in [-1.0, 1.0]:
			var yoke := "M-6.6,%s L6.4,%s Q8.2,%s 6.6,%s L-6.2,%s Z" % [_f(side * 3.6), _f(side * 3.9), _f(side * 7.4), _f(side * 10.6), _f(side * 11.0)]
			out += _path(yoke, String(chest["color"]), ink, 1.0)
			out += _line(-5.4, side * 9.6, 5.6, side * 9.3, String(chest["trim"]), 0.9)
		if style == "armor":
			out += _path("M-7.4,-6.5 Q-10.4,0 -7.4,6.5", "none", ink, 4.0) + _path("M-7.4,-6.5 Q-10.4,0 -7.4,6.5", "none", String(chest["trim"]), 2.4)
		else:
			out += _box(-1.6, -9.2, 3.2, 2.4, 0.4, String(chest["trim"]), ink, 0.5)
	if style == "jacket":
		out += _path("M4.6,-9.6 Q11.2,0 4.6,9.6", "none", String(chest["trim"]), 1.6)

	# The backpack: a bedroll strapped behind it, a pocket on each side, two straps over the top.
	var camo := String(h["camo"])
	var spots := [String(h["camo_dark"]), String(h["camo_light"]), String(h["camo_deep"])]
	var roll := "M-25.6,-6 Q-25.6,-8.6 -23,-8.6 L-21,-8.6 L-21,8.6 L-23,8.6 Q-25.6,8.6 -25.6,6 Z"
	out += _filled("hr", roll, _shade(camo, 0.22), _blots(7, Rect2(-26.0, -9.0, 6.0, 18.0), 7, spots, 1.5, 0.8), ink, 1.0)
	for side: float in [-1.0, 1.0]:
		out += _line(-23.2, side * 4.6, -21.0, side * 4.6, String(h["web"]), 1.3)
		var pocket := "M-18.4,%s L-9.4,%s L-9.4,%s Q-13.9,%s -18.4,%s Z" % [_f(side * 9.6), _f(side * 9.6), _f(side * 13.0), _f(side * 14.6), _f(side * 13.0)]
		out += _filled("hp%d" % int(side + 1.0), pocket, camo, _blots(11 + int(side), Rect2(-19.0, minf(side * 9.0, side * 15.0), 10.0, 6.0), 5, spots, 1.4, 0.85), ink, 1.0)
	var pack := "M-18,-10.8 L-9.5,-10.8 Q-5.4,-10.8 -5.4,-6.6 L-5.4,6.6 Q-5.4,10.8 -9.5,10.8 L-18,10.8 Q-22.2,10.8 -22.2,6.6 L-22.2,-6.6 Q-22.2,-10.8 -18,-10.8 Z"
	out += _filled("hk", pack, camo, _blots(3, Rect2(-22.5, -11.0, 17.5, 22.0), 24, spots, 1.9, 0.9) + _round(Rect2(-22.5, -11.0, 17.5, 22.0), 1.2), ink, 1.2)
	out += _path("M-9.6,-9.8 Q-7.6,0 -9.6,9.8", "none", String(h["camo_deep"]), 0.8, "stroke-opacity=\"0.75\"")
	for side: float in [-1.0, 1.0]:
		# (a strap from the bedroll over the pack and on over his shoulder)
		out += _line(-21.6, side * 4.6, 7.0, side * 7.2, ink, 3.5)
		out += _line(-21.6, side * 4.6, 7.0, side * 7.2, String(h["web"]), 2.3)
		out += _line(-21.0, side * 4.1, 6.6, side * 6.7, _shade(String(h["web"]), -0.25), 0.5, "stroke-opacity=\"0.7\"")
		out += _box(-15.4, side * 5.1 - 1.9, 3.0, 3.8, 0.5, String(h["buckle"]), ink, 0.6)
		out += _box(1.2, side * 6.8 - 1.7, 2.6, 3.4, 0.5, String(h["buckle"]), ink, 0.6)

	if style == "bandolier":
		# A belt of cartridges slung across his back and over his right shoulder.
		out += _line(-8.6, -10.0, 7.6, 8.8, ink, 4.6) + _line(-8.6, -10.0, 7.6, 8.8, String(chest["color"]), 3.3)
		for k in 6:
			out += _circle(-6.6 + 2.6 * k, -7.7 + 3.0 * k, 0.85, String(chest["trim"]), ink, 0.35)

	# The red scarf round his neck, knotted at the back (most of it is under his head).
	var red := String(h["scarf"])
	var tail := String(h["scarf_dark"])
	out += _path("M-6.4,-3.4 L-13.6,-7.4 L-11.2,-3.6 L-14.8,-2.2 L-7.2,0.2 Z", red, ink, 0.9)
	out += _line(-8.2, -3.0, -12.2, -5.4, tail, 0.6)
	out += _oval(0.9, 0.0, 9.6, 10.0, red, ink, 1.1)
	out += _path("M-7.6,-4.4 Q-9.6,0 -7.6,4.4 M-5.2,-7.4 Q-2.4,-9.2 1.4,-9.4 M-5.2,7.4 Q-2.4,9.2 1.4,9.4", "none", tail, 0.8)
	out += _circle(-7.6, -2.2, 1.9, red, ink, 0.8)

	if hurt:
		out += BODY_WOUNDS
	return out


## Blood and a field dressing on his body when he is badly hurt.
const BODY_WOUNDS := """
<ellipse cx="-14.6" cy="-5.4" rx="3.6" ry="2.3" fill="#7a1010" fill-opacity="0.9" transform="rotate(-24 -14.6 -5.4)"/>
<ellipse cx="-12" cy="-3.6" rx="1.6" ry="1.1" fill="#5a0c0c"/>
<ellipse cx="-16" cy="5.6" rx="3.2" ry="2" fill="#7a1010" fill-opacity="0.85" transform="rotate(18 -16 5.6)"/>
<path d="M-18,7 Q-20.4,9 -19.6,11.4" stroke="#7a1010" stroke-width="1.3" fill="none" stroke-linecap="round"/>
<path d="M-4.8,10.2 L2.6,13.2" stroke="#15130f" stroke-width="4.6" stroke-linecap="round"/>
<path d="M-4.8,10.2 L2.6,13.2" stroke="#ece6d2" stroke-width="3.1" stroke-linecap="round"/>
<path d="M-2.4,11.2 L0.4,12.3" stroke="#c2392b" stroke-width="1.5" stroke-linecap="round"/>
<circle cx="-8" cy="-12.6" r="1.4" fill="#7a1010"/><circle cx="-21" cy="-1" r="1.1" fill="#7a1010"/><circle cx="3.4" cy="-13" r="1.2" fill="#7a1010"/><circle cx="-9.6" cy="8.6" r="0.9" fill="#7a1010"/>
"""


## His head from above: short black hair, a sliver of brow and nose at the front - or whatever he wears on it.
static func top_head(h: Dictionary, helmet: Dictionary, hurt: bool) -> String:
	var ink := String(h["ink"])
	var skin := String(h["skin"])
	var out := ""
	for side: float in [-1.0, 1.0]:
		out += _oval(0.4, side * 6.7, 1.7, 1.2, skin, ink, 0.8)
	out += _circle(0.0, 0.0, 6.9, skin, ink, 1.2)
	out += _path("M5.6,-1.2 Q8.6,0 5.6,1.2 Z", String(h["skin_dark"]), ink, 0.7)      # the tip of his nose
	# Hair: tight black curls.
	var hair := "M3.9,-5.7 A6.9,6.9 0 1 0 3.9,5.7 Q5.5,0 3.9,-5.7 Z"
	var curls := ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for row in 11:
		for col in 10:
			curls += _circle(-7.0 + col * 1.3 + (0.65 if row % 2 == 1 else 0.0) + rng.randf_range(-0.2, 0.2), -6.6 + row * 1.3 + rng.randf_range(-0.2, 0.2),
					0.42, String(h["hair_light"]))
	out += _filled("hh", hair, String(h["hair"]), curls + _round(Rect2(-7.0, -7.0, 12.0, 14.0), 0.8), ink, 0.0)
	out += _path("M3.9,-5.7 Q5.5,0 3.9,5.7", "none", ink, 0.7)

	var color := String(helmet.get("color", "#000000"))
	var trim := String(helmet.get("trim", "#000000"))
	match _style(helmet):
		"hardhat":
			# A hard hat: a brim all round, longer at the front, and three ridges over the top.
			out += _oval(1.0, 0.0, 9.2, 8.5, _shade(color, 0.18), ink, 1.1)
			out += _filled("ht", "M-7.2,0 A7.2,7.2 0 1 0 7.2,0 A7.2,7.2 0 1 0 -7.2,0 Z", color, _round(Rect2(-7.2, -7.2, 14.4, 14.4), 1.5), ink, 1.0)
			out += _line(-6.0, 0.0, 6.4, 0.0, trim, 1.7)
			for side: float in [-1.0, 1.0]:
				out += _path("M-4.6,%s Q0,%s 5.2,%s" % [_f(side * 3.3), _f(side * 3.9), _f(side * 3.3)], "none", trim, 0.9)
		"cap":
			# A field cap: the peak sticks out ahead.
			out += _path("M4.6,-5.6 Q13.4,0 4.6,5.6 Q7,0 4.6,-5.6 Z", _shade(color, 0.2), ink, 1.0)
			out += _filled("ht", "M-7.1,0 A7.1,7.1 0 1 0 7.1,0 A7.1,7.1 0 1 0 -7.1,0 Z", color,
					_blots(21, Rect2(-7.0, -7.0, 14.0, 14.0), 9, [trim], 1.7, 0.85) + _round(Rect2(-7.1, -7.1, 14.2, 14.2), 1.2), ink, 1.0)
			out += _circle(0.0, 0.0, 1.0, trim, ink, 0.4)
		"mask":
			# A gas mask: straps over his hair, the snout and its two filters at the front.
			out += _path("M5,-2.6 Q-2,-4.2 -6.4,-2.2 M5,2.6 Q-2,4.2 -6.4,2.2 M-1.6,-6.6 L-1.6,6.6", "none", trim, 1.2)
			for side: float in [-1.0, 1.0]:
				out += _circle(6.6, side * 5.3, 2.7, _shade(color, 0.25), ink, 0.9) + _circle(6.6, side * 5.3, 1.2, trim)
			out += _box(4.0, -3.5, 6.0, 7.0, 2.2, color, ink, 1.0)
			out += _box(7.6, -1.4, 2.0, 2.8, 0.6, trim)
		"helmet":
			# A combat helmet in a camouflage cover, with its band and the mount at the front.
			out += _filled("ht", "M-8,0 A8,7.8 0 1 0 8,0 A8,7.8 0 1 0 -8,0 Z", color,
					_blots(31, Rect2(-8.0, -8.0, 16.0, 16.0), 12, [trim, _shade(color, -0.2)], 1.9, 0.85) + _round(Rect2(-8.0, -7.8, 16.0, 15.6), 1.4), ink, 1.1)
			out += _oval(0.0, 0.0, 5.6, 5.4, "none", _shade(trim, 0.2), 0.8, "stroke-opacity=\"0.8\"")
			out += _box(5.9, -1.3, 2.3, 2.6, 0.5, "#2a2c2e", ink, 0.5)
			out += _flag(h, -1.0, 6.1, 3.0, 1.9, 0.0)
	if hurt:
		if helmet.is_empty() or _style(helmet) == "mask":
			# A bandage round his head, blood coming through.
			out += _path("M-3.6,-6.2 Q-1,0 -3.6,6.2", "none", ink, 3.4) + _path("M-3.6,-6.2 Q-1,0 -3.6,6.2", "none", "#ece6d2", 2.2)
			out += _circle(-2.6, 2.6, 1.2, "#c2392b")
		else:
			out += _path("M-4,-5 L1,-2.4 L-2.6,1.6", "none", "#7a1010", 1.5) + _circle(2.6, 4.2, 1.1, "#7a1010")
	return out


## A limb from (0, 0) to (reach, 0) with some muscle on it: `thick` at its thickest (a third
## of the way along), `thin` at its far end. Ink outline, a light and a dark side.
static func _limb(id: String, reach: float, thick: float, thin: float, color: String, ink: String) -> String:
	var d := "M0,%s Q%s,%s %s,%s Q%s,%s %s,0 Q%s,%s %s,%s Q%s,%s 0,%s Q%s,0 0,%s Z" % [
			_f(-thick * 0.92), _f(reach * 0.34), _f(-thick * 1.12), _f(reach), _f(-thin), _f(reach + thin * 1.25), _f(-thin * 0.9), _f(reach + thin * 1.25),
			_f(reach + thin * 1.25), _f(thin * 0.9), _f(reach), _f(thin), _f(reach * 0.34), _f(thick * 1.12), _f(thick * 0.92), _f(-thick * 1.25), _f(-thick * 0.92)]
	var inside := _oval(reach * 0.4, -thick * 0.45, reach * 0.42, thick * 0.34, _shade(color, -0.25), "", 0.0, "fill-opacity=\"0.75\"") \
			+ _oval(reach * 0.5, thick * 0.75, reach * 0.55, thick * 0.4, _shade(color, 0.35), "", 0.0, "fill-opacity=\"0.6\"")
	return _filled(id, d, color, inside, ink, 1.1)


## An upper arm: the shoulder joint is at (0, 0), the elbow at (Config.HERO_ARM_UPPER, 0).
## `flag` = this is his left arm, which carries the flag patch.
static func top_arm_upper(h: Dictionary, chest: Dictionary, flag: bool) -> String:
	var ink := String(h["ink"])
	var style := _style(chest)
	var reach: float = Config.HERO_ARM_UPPER
	var sleeved := style == "jacket"
	var out := ""
	out += _limb("ha", reach, 4.5 if sleeved else 4.2, 3.7 if sleeved else 3.3, String(chest["color"]) if sleeved else String(h["skin"]), ink)
	if sleeved:
		out += _line(6.8, -3.4, 6.8, 3.4, String(chest["trim"]), 0.8)
		out += _circle(0.0, 0.0, 5.0, String(chest["color"]), ink, 1.0) + _path("M-2.6,-3 Q-3.6,0 -2.6,3", "none", String(chest["trim"]), 0.8)
	else:
		out += _line(8.4, -1.6, 10.8, 0.6, String(h["skin_dark"]), 0.9)      # an old scar
		# The torn-off sleeve of his shirt over the shoulder.
		var sleeve := "M-4.9,0 Q-4.9,-5.1 0,-5.1 L3.6,-5.1 L5.3,-3.7 L4,-2.2 L5.7,-0.8 L4.2,0.6 L5.7,2 L4,3.5 L5.1,5.1 L0,5.1 Q-4.9,5.1 -4.9,0 Z"
		out += _path(sleeve, String(h["shirt"]), ink, 1.0)
		out += _path("M-2.6,-3 Q-3.6,0 -2.6,3", "none", String(h["shirt_dark"]), 0.8)
	if style == "armor":
		out += _circle(0.2, 0.0, 5.6, String(chest["color"]), ink, 1.1) + _circle(0.2, 0.0, 3.3, "none", String(chest["trim"]), 0.9)
	elif flag:
		out += _flag(h, 0.4, 0.0, 5.0, 3.6, 90.0)
	return out


## A forearm with its hand: the elbow is at (0, 0), the fist at (Config.HERO_ARM_FORE, 0).
static func top_arm_fore(h: Dictionary, chest: Dictionary, gloves: Dictionary) -> String:
	var ink := String(h["ink"])
	var reach: float = Config.HERO_ARM_FORE
	var sleeved := _style(chest) == "jacket"
	var wrist := reach - 4.0
	var out := ""
	out += _limb("hf", wrist, 4.1 if sleeved else 3.8, 3.2 if sleeved else 2.8, String(chest["color"]) if sleeved else String(h["skin"]), ink)
	# The hand: a fist round the grip. His own gloves leave the fingers bare.
	var glove := String(h["glove"]) if gloves.is_empty() else String(gloves["color"])
	var pad := String(h["glove_pad"]) if gloves.is_empty() else String(gloves["trim"])
	var bare := gloves.is_empty() or _style(gloves) == "wraps" or _style(gloves) == "fingerless"
	out += _circle(reach + 0.2, 0.0, 3.9, String(h["skin"]) if bare else glove, ink, 1.0)
	if bare:
		out += _path("M%s,-2.2 Q%s,0 %s,2.2" % [_f(reach + 1.6), _f(reach + 2.9), _f(reach + 1.6)], "none", String(h["skin_dark"]), 0.6)
	var mitt := "M%s,-3.5 L%s,-3.9 Q%s,0 %s,3.9 L%s,3.5 Z" % [_f(wrist - 1.4), _f(reach + 0.2), _f(reach + 1.9), _f(reach + 0.2), _f(wrist - 1.4)]
	out += _path(mitt, glove, ink, 0.9)
	if _style(gloves) == "wraps":
		for k in 4:
			out += _line(wrist - 0.8 + 1.5 * k, -3.2, wrist + 1.5 * k, 3.2, pad, 0.7)
	else:
		out += _box(reach - 2.6, -1.9, 2.8, 3.8, 0.9, pad, ink, 0.5)
		out += _line(wrist - 1.0, -3.2, wrist - 1.0, 3.2, _shade(glove, 0.4), 1.0)
	return out


## A leg from above: the ankle is at (0, 0), the leg lies back along -x toward the hip.
static func top_leg(h: Dictionary, pants: Dictionary) -> String:
	var ink := String(h["ink"])
	var d := "M-12,-3.7 L-1,-3.7 Q1.6,-3.7 1.6,0 Q1.6,3.7 -1,3.7 L-12,3.7 Z"
	if pants.is_empty():
		var spots := [String(h["camo_dark"]), String(h["camo_light"]), String(h["camo_deep"])]
		return _filled("hl", d, String(h["camo"]), _blots(41, Rect2(-12.0, -4.0, 14.0, 8.0), 9, spots, 1.5, 0.9) + _round(Rect2(-12.0, -3.7, 13.6, 7.4)), ink, 1.0)
	var out := _filled("hl", d, String(pants["color"]), _round(Rect2(-12.0, -3.7, 13.6, 7.4)), ink, 1.0)
	match _style(pants):
		"track":
			out += _line(-11.0, -2.3, 0.6, -2.3, String(pants["trim"]), 0.9)      # a stripe down the side
		"camo":
			out = _filled("hl", d, String(pants["color"]), _blots(43, Rect2(-12.0, -4.0, 14.0, 8.0), 9, [String(pants["trim"]), _shade(String(pants["color"]), -0.2)], 1.5, 0.9), ink, 1.0)
		_:
			out += _box(-6.4, -2.6, 4.2, 5.2, 1.2, String(pants["trim"]), ink, 0.5)      # a pocket or a pad over the knee
	return out


## A boot from above: the ankle is at (0, 0), the toes point to +x.
static func top_boot(h: Dictionary, boots: Dictionary) -> String:
	var ink := String(h["ink"])
	var style := _style(boots)
	var color := String(h["boots"]) if boots.is_empty() else String(boots["color"])
	var trim := String(h["sole"]) if boots.is_empty() else String(boots["trim"])
	var shape := "M-3.6,-2.6 Q-3.6,-3.4 -2.4,-3.4 L4.2,-3.2 Q8,-2.6 8,0 Q8,2.6 4.2,3.2 L-2.4,3.4 Q-3.6,3.4 -3.6,2.6 Z"
	var out := ""
	if style == "sandals":
		# Rope sandals: his bare foot on a sole, two straps over it.
		out += _path(shape, color, ink, 1.0)
		out += _path("M-2.6,-2.3 L4,-2.2 Q6.6,-1.8 6.6,0 Q6.6,1.8 4,2.2 L-2.6,2.3 Z", String(h["skin"]), "", 0.0)
		out += _line(1.0, -2.8, 3.4, 2.8, trim, 1.1) + _line(4.6, -2.4, 2.0, 2.8, trim, 1.1)
		return out
	out += _path(shape, _shade(color, 0.35) if style != "shoes" else trim, ink, 1.0)      # the sole, showing round the edge
	out += _path("M-2.8,-2.5 L4,-2.3 Q6.9,-1.9 6.9,0 Q6.9,1.9 4,2.3 L-2.8,2.5 Z", color, "", 0.0)
	out += _oval(4.6, 0.0, 2.0, 1.7, _shade(color, -0.18) if style != "shoes" else color, "", 0.0, "fill-opacity=\"0.8\"")
	if style == "shoes":
		for side: float in [-1.0, 1.0]:
			out += _line(0.6, side * 2.2, 2.6, side * 1.0, trim, 0.7) + _line(2.2, side * 2.2, 4.2, side * 1.0, trim, 0.7)
	else:
		if not boots.is_empty():
			out += _path("M5,-2 Q7.2,0 5,2", "none", trim, 1.0)      # a toe cap
	for k in 3:
		out += _line(0.2 + 1.4 * k, -1.2, 0.2 + 1.4 * k, 1.2, String(h["lace"]) if boots.is_empty() else _shade(color, 0.5), 0.6)
	return out


# ----------------------------------------------------------------------------
#  Seen from the front, standing - for the menus. 260 x 400, (0, 0) in the
#  middle of the picture; he looks at you, so his RIGHT hand is on the LEFT.
#  He carries his guns the way the owner's painting shows him: a pistol in
#  his right hand, his rifle in his left, both pointing at the ground.
#  `worn` = slot -> the "look" of the piece worn there ({} = nothing).
# ----------------------------------------------------------------------------
## The outline of a limb from `a` to `b`, `wa` thick (half its width) at `a` and `wb` at `b`, round at both ends.
static func _limb2(a: Vector2, b: Vector2, wa: float, wb: float) -> String:
	var n := (b - a).normalized().orthogonal() * -1.0
	var a1 := a + n * wa
	var a2 := a - n * wa
	var b1 := b + n * wb
	var b2 := b - n * wb
	return "M%s,%s L%s,%s A%s,%s 0 0 0 %s,%s L%s,%s A%s,%s 0 0 0 %s,%s Z" % [_f(a1.x), _f(a1.y), _f(b1.x), _f(b1.y), _f(wb), _f(wb), _f(b2.x), _f(b2.y),
			_f(a2.x), _f(a2.y), _f(wa), _f(wa), _f(a1.x), _f(a1.y)]


## A soft light side and dark side for a shape that stands upright (light from the upper left).
static func _upright(box: Rect2, strength: float = 1.0) -> String:
	return _box(box.position.x, box.position.y, box.size.x * 0.3, box.size.y, 0.0, "#ffffff", "", 0.0, "fill-opacity=\"%s\"" % _f(0.1 * strength)) \
			+ _box(box.position.x + box.size.x * 0.66, box.position.y, box.size.x * 0.34, box.size.y, 0.0, "#000000", "", 0.0, "fill-opacity=\"%s\"" % _f(0.2 * strength))


static func front(h: Dictionary, worn: Dictionary) -> String:
	var ink := String(h["ink"])
	var skin := String(h["skin"])
	var helmet: Dictionary = worn.get("helmet", {})
	var chest: Dictionary = worn.get("chest", {})
	var gloves: Dictionary = worn.get("gloves", {})
	var belt: Dictionary = worn.get("belt", {})
	var pants: Dictionary = worn.get("pants", {})
	var boots: Dictionary = worn.get("boots", {})
	var amulet: Dictionary = worn.get("amulet", {})
	var chest_style := _style(chest)
	var sleeved := chest_style == "jacket"
	var camo := String(h["camo"])
	var spots := [String(h["camo_dark"]), String(h["camo_light"]), String(h["camo_deep"])]
	var web := String(h["web"])
	var out := _oval(0.0, 188.0, 96.0, 10.0, "#000000", "", 0.0, "fill-opacity=\"0.35\"")

	# --- behind him: the top of his backpack with the bedroll, and the machete over his left shoulder ---
	out += "<g transform=\"translate(47 -116) rotate(20)\">"
	out += _box(-4.5, -50.0, 9.0, 46.0, 3.0, "#6b4226", ink, 2.0) + _line(-4.5, -38.0, 4.5, -38.0, ink, 1.2) + _line(-4.5, -26.0, 4.5, -26.0, ink, 1.2)
	out += _box(-8.0, -6.0, 16.0, 7.0, 2.0, "#3a3d42", ink, 1.8) + "</g>"
	var pack := "M-46,-92 L-42,-124 Q-40,-134 -30,-134 L30,-134 Q40,-134 42,-124 L46,-92 Z"
	out += _filled("fk", pack, camo, _blots(61, Rect2(-46.0, -134.0, 92.0, 42.0), 22, spots, 6.0, 0.9) + _upright(Rect2(-46.0, -134.0, 92.0, 42.0)), ink, 2.2)
	var roll := "M-34,-150 L34,-150 Q42,-150 42,-142 Q42,-134 34,-134 L-34,-134 Q-42,-134 -42,-142 Q-42,-150 -34,-150 Z"
	out += _filled("fr", roll, _shade(camo, 0.2), _blots(63, Rect2(-42.0, -150.0, 84.0, 16.0), 12, spots, 5.0, 0.8), ink, 2.2)
	for side: float in [-1.0, 1.0]:
		out += _box(side * 20.0 - 3.5, -151.0, 7.0, 18.0, 1.0, web, ink, 1.4)

	# --- legs ---
	var leg_color := camo if pants.is_empty() else String(pants["color"])
	var leg_trim := String(h["camo_dark"]) if pants.is_empty() else String(pants["trim"])
	var pants_style := _style(pants)
	for side: float in [-1.0, 1.0]:
		var leg := "M%s,30 Q%s,70 %s,104 L%s,160 L%s,160 L%s,104 L%s,54 L%s,30 Z" % [_f(side * 43.0), _f(side * 48.0), _f(side * 44.0), _f(side * 39.0), _f(side * 9.0), _f(side * 5.0), _f(side * 1.5), _f(side * 1.5)]
		var box := Rect2(minf(side * 47.0, side * 1.5), 30.0, 46.0, 130.0)
		var inside := _upright(box)
		if pants.is_empty() or pants_style == "camo":
			inside = _blots(71 + int(side), box, 26, spots if pants.is_empty() else [leg_trim, _shade(leg_color, -0.2)], 6.0, 0.9) + inside
		out += _filled("fl%d" % int(side + 1.0), leg, leg_color, inside, ink, 2.2)
		out += _path("M%s,98 Q%s,106 %s,101" % [_f(side * 41.0), _f(side * 25.0), _f(side * 9.0)], "none", _shade(leg_color, 0.35), 1.6)      # the knee
		match pants_style:
			"track":
				out += _path("M%s,40 Q%s,74 %s,104 L%s,156" % [_f(side * 41.5), _f(side * 45.0), _f(side * 41.5), _f(side * 36.5)], "none", leg_trim, 3.2)
			"padded":
				out += _box(minf(side * 42.0, side * 9.0), 92.0, 33.0, 26.0, 8.0, leg_trim, ink, 1.6)
				out += _box(minf(side * 39.0, side * 11.0), 124.0, 28.0, 30.0, 5.0, leg_trim, ink, 1.6)
			"camo":
				pass
			_:
				# A big pocket on the outside of each thigh.
				out += _box(minf(side * 46.0, side * 26.0), 58.0, 20.0, 30.0, 3.0, _shade(leg_color, 0.14), ink, 1.6)
				out += _line(side * 45.0, 66.0, side * 27.0, 66.0, ink, 1.2)
	if pants.is_empty():
		# His own trousers are torn at the right knee.
		out += _oval(-27.0, 110.0, 9.0, 6.0, skin, ink, 1.4) + _line(-32.0, 109.0, -23.0, 111.5, String(h["skin_dark"]), 1.2)
	# The holster strapped to his right thigh (empty: the pistol is in his hand).
	out += _line(-45.0, 76.0, -4.0, 78.0, ink, 6.0) + _line(-45.0, 76.0, -4.0, 78.0, String(h["web_dark"]), 3.6)
	out += _box(-54.0, 56.0, 18.0, 42.0, 4.0, String(h["web_dark"]), ink, 2.0) + _line(-52.0, 67.0, -38.0, 67.0, ink, 1.2)

	# --- boots ---
	var boot_color := String(h["boots"]) if boots.is_empty() else String(boots["color"])
	var boot_trim := String(h["sole"]) if boots.is_empty() else String(boots["trim"])
	var boot_style := _style(boots)
	for side: float in [-1.0, 1.0]:
		var top := 150.0 if boot_style != "shoes" and boot_style != "sandals" else 166.0
		var shoe := "M%s,%s L%s,%s L%s,176 Q%s,187 %s,187 L%s,187 Q%s,187 %s,176 Z" % [_f(side * 41.0), _f(top), _f(side * 7.0), _f(top), _f(side * 4.0),
				_f(side * 4.0), _f(side * 14.0), _f(side * 46.0), _f(side * 54.0), _f(side * 51.0)]
		if boot_style == "sandals":
			# Rope sandals: his bare feet, a sole, two straps.
			out += _path(shoe, skin, ink, 2.2)
			out += _line(side * 5.0, 185.0, side * 53.0, 185.0, ink, 6.0) + _line(side * 6.0, 185.0, side * 52.0, 185.0, boot_color, 3.6)
			out += _line(side * 7.0, 172.0, side * 50.0, 176.0, boot_trim, 3.4) + _line(side * 22.0, 166.0, side * 32.0, 184.0, boot_trim, 3.4)
			continue
		out += _filled("fb%d" % int(side + 1.0), shoe, boot_color, _upright(Rect2(minf(side * 54.0, side * 4.0), top, 50.0, 187.0 - top)), ink, 2.2)
		out += _line(side * 5.0, 184.5, side * 53.0, 184.5, ink, 6.4) + _line(side * 6.5, 184.5, side * 51.5, 184.5, boot_trim if boot_style != "shoes" else "#f2efe6", 3.4)
		if boot_style == "shoes":
			out += _box(minf(side * 40.0, side * 8.0), 157.0, 32.0, 10.0, 2.0, "#e9e4d6", ink, 1.4)      # socks
			for k in 3:
				out += _line(side * (14.0 + 8.0 * k), 170.0, side * (21.0 + 8.0 * k), 182.0, boot_trim, 2.8)
		else:
			for k in 4:
				out += _line(side * 17.0, top + 6.0 + 6.0 * k, side * 32.0, top + 6.0 + 6.0 * k, String(h["lace"]) if boots.is_empty() else _shade(boot_color, 0.5), 1.8)
			if not boots.is_empty():
				out += _path("M%s,173 Q%s,166 %s,177" % [_f(side * 9.0), _f(side * 30.0), _f(side * 50.0)], "none", boot_trim, 2.4)      # a toe cap

	# --- arms, hands and guns (his right arm is on the left of the picture) ---
	var limb := String(chest["color"]) if sleeved else skin
	var glove := String(h["glove"]) if gloves.is_empty() else String(gloves["color"])
	var pad := String(h["glove_pad"]) if gloves.is_empty() else String(gloves["trim"])
	var bare := gloves.is_empty() or _style(gloves) == "wraps" or _style(gloves) == "fingerless"
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector2(side * 55.0, -88.0)
		var elbow := Vector2(side * 68.0, -27.0)
		var wrist := Vector2(side * 73.0, 22.0)
		var fist := Vector2(side * 74.0, 40.0)
		# The gun first: his fist closes over its grip.
		if side < 0.0:
			out += "<g transform=\"translate(-74 40) rotate(5) scale(1.25)\">" + FRONT_PISTOL + "</g>"
		else:
			out += "<g transform=\"translate(74 40) rotate(-9) scale(1.3)\">" + FRONT_RIFLE + "</g>"
		var upper := _limb2(shoulder, elbow, 15.0 if sleeved else 14.0, 11.5)
		var fore := _limb2(elbow, wrist, 11.8, 8.6 if not sleeved else 10.0)
		for part: Array in [["fu", upper, Rect2(minf(shoulder.x, elbow.x) - 15.0, -104.0, 44.0, 92.0)], ["fo", fore, Rect2(minf(elbow.x, wrist.x) - 12.0, -40.0, 30.0, 74.0)]]:
			out += _filled("%s%d" % [String(part[0]), int(side + 1.0)], String(part[1]), limb, _upright(part[2], 1.3), ink, 2.2)
		if sleeved:
			out += _line(wrist.x - 10.0, wrist.y - 4.0, wrist.x + 10.0, wrist.y - 4.0, String(chest["trim"]), 3.0)
		else:
			out += _line(side * 64.0, -58.0, side * 70.0, -46.0, String(h["skin_dark"]), 1.8)      # old scars
			out += _line(side * 68.0, -6.0, side * 74.0, 4.0, String(h["skin_dark"]), 1.6)
		# The hand: a fist, in his fingerless gloves or whatever he wears on his hands.
		out += _oval(fist.x, fist.y + 2.0, 12.0, 13.0, skin if bare else glove, ink, 2.2)
		var mitt := "M%s,%s L%s,%s L%s,%s Q%s,%s %s,%s Z" % [_f(wrist.x - 10.5), _f(wrist.y - 3.0), _f(wrist.x + 10.5), _f(wrist.y - 3.0),
				_f(fist.x + 12.5), _f(fist.y + 3.0), _f(fist.x), _f(fist.y + 9.0), _f(fist.x - 12.5), _f(fist.y + 3.0)]
		out += _path(mitt, glove, ink, 2.0)
		if _style(gloves) == "wraps":
			for k in 4:
				out += _line(wrist.x - 10.0, wrist.y + 5.0 * k, wrist.x + 10.5, wrist.y + 2.0 + 5.0 * k, pad, 1.5)
		else:
			out += _box(fist.x - 6.5, wrist.y + 6.0, 13.0, 9.0, 3.0, pad, ink, 1.2)
			out += _line(wrist.x - 10.0, wrist.y + 2.0, wrist.x + 10.0, wrist.y + 2.0, _shade(glove, 0.4), 2.2)
		if bare:
			for k in 3:
				out += _line(fist.x - 6.0 + 6.0 * k, fist.y + 9.0, fist.x - 6.0 + 6.0 * k, fist.y + 13.0, String(h["skin_dark"]), 1.2)
		var ring: Dictionary = worn.get("ring1" if side < 0.0 else "ring2", {})
		if not ring.is_empty():
			out += _box(fist.x + side * 2.0 - 4.0, fist.y + 8.0, 8.0, 4.6, 1.6, String(ring["color"]), ink, 1.2)
		# Over the shoulder: the torn sleeve of his shirt, a jacket's seam, or a shoulder plate.
		if sleeved:
			out += _path("M%s,-100 Q%s,-80 %s,-70" % [_f(side * 44.0), _f(side * 52.0), _f(side * 70.0)], "none", String(chest["trim"]), 2.0)
		elif chest_style == "armor":
			var plate := "M%s,-104 Q%s,-108 %s,-92 L%s,-66 Q%s,-58 %s,-66 Z" % [_f(side * 42.0), _f(side * 66.0), _f(side * 73.0), _f(side * 72.0), _f(side * 56.0), _f(side * 42.0)]
			out += _path(plate, String(chest["color"]), ink, 2.2) + _path("M%s,-74 Q%s,-68 %s,-74" % [_f(side * 46.0), _f(side * 58.0), _f(side * 70.0)], "none", String(chest["trim"]), 2.0)
		else:
			var cap := "M%s,-104 Q%s,-108 %s,-92 L%s,-70 L%s,-76 L%s,-66 L%s,-74 L%s,-64 L%s,-72 L%s,-66 Z" % [_f(side * 40.0), _f(side * 64.0), _f(side * 72.0), _f(side * 73.0),
					_f(side * 67.0), _f(side * 62.0), _f(side * 56.0), _f(side * 51.0), _f(side * 46.0), _f(side * 40.0)]
			out += _filled("fc%d" % int(side + 1.0), cap, String(h["shirt"]), _upright(Rect2(minf(side * 73.0, side * 40.0), -108.0, 33.0, 44.0)), ink, 2.2)
			if side > 0.0:
				out += _flag(h, 58.0, -86.0, 19.0, 13.0, 8.0)

	# --- body ---
	var torso := "M-50,-94 Q-52,-103 -40,-105 L-15,-110 L15,-110 L40,-105 Q52,-103 50,-94 L43,-20 L39,26 L-39,26 L-43,-20 Z"
	var cloth := String(chest["color"]) if sleeved else String(h["shirt"])
	out += _filled("ft", torso, cloth, _upright(Rect2(-52.0, -110.0, 104.0, 136.0)) + _oval(0.0, 20.0, 44.0, 14.0, "#000000", "", 0.0, "fill-opacity=\"0.12\""), ink, 2.2)
	match chest_style:
		"jacket":
			# A leather jacket: zip, two lapels, a pocket on each side.
			out += _line(0.0, -84.0, 0.0, 24.0, ink, 2.0)
			for side: float in [-1.0, 1.0]:
				out += _path("M%s,-108 L%s,-78 L%s,-88 Z" % [_f(side * 15.0), _f(side * 3.0), _f(side * 26.0)], String(chest["trim"]), ink, 1.8)
				out += _line(side * 14.0, -6.0, side * 34.0, -2.0, String(chest["trim"]), 2.4)
				out += _path("M%s,-100 Q%s,-40 %s,22" % [_f(side * 44.0), _f(side * 40.0), _f(side * 36.0)], "none", String(chest["trim"]), 1.6)
		"vest", "armor":
			# A vest over the shirt: one broad panel from collar to belt.
			var panel := "M-36,-106 L-17,-110 Q0,-98 17,-110 L36,-106 L41,-58 L37,20 L-37,20 L-41,-58 Z"
			out += _filled("fv", panel, String(chest["color"]), _upright(Rect2(-41.0, -110.0, 82.0, 130.0)), ink, 2.2)
			if chest_style == "armor":
				out += _box(-27.0, -78.0, 54.0, 50.0, 6.0, _shade(String(chest["color"]), -0.12), String(chest["trim"]), 2.2)
				for k in 3:
					out += _line(-22.0, -66.0 + 12.0 * k, 22.0, -66.0 + 12.0 * k, String(chest["trim"]), 1.6)
				for k: float in [-1.0, 0.0, 1.0]:
					out += _box(k * 23.0 - 9.5, -20.0, 19.0, 34.0, 2.5, String(chest["trim"]), ink, 1.6) + _line(k * 23.0 - 9.5, -8.0, k * 23.0 + 9.5, -8.0, ink, 1.2)
			else:
				# (patched: squares sewn on, big stitches)
				out += _box(-30.0, -66.0, 22.0, 20.0, 2.0, String(chest["trim"]), ink, 1.4) + _box(8.0, -30.0, 24.0, 22.0, 2.0, String(chest["trim"]), ink, 1.4)
				out += _path("M0,-96 L0,18", "none", ink, 1.6, "stroke-dasharray=\"5 4\"") + _path("M-38,-8 L38,-8", "none", _shade(String(chest["color"]), 0.3), 1.6)
		_:
			# His own kit: webbing over the shoulders, a chest rig with three magazines, the radio.
			for side: float in [-1.0, 1.0]:
				out += _line(side * 27.0, -108.0, side * 23.0, -62.0, ink, 14.0) + _line(side * 27.0, -108.0, side * 23.0, -62.0, web, 10.0)
				out += _box(side * 25.0 - 6.5, -92.0, 13.0, 9.0, 1.5, String(h["buckle"]), ink, 1.4)
			if chest_style != "bandolier":
				var rig := "M-35,-70 Q0,-77 35,-70 L33,-26 L-33,-26 Z"
				out += _filled("fg", rig, _shade(web, 0.12), _upright(Rect2(-35.0, -77.0, 70.0, 51.0)), ink, 2.0)
				for k in 3:
					out += _line(-30.0, -60.0 + 10.0 * k, 30.0, -60.0 + 10.0 * k, String(h["web_dark"]), 1.4)
				for k: float in [-1.0, 0.0, 1.0]:
					out += _box(k * 23.0 - 6.5, -36.0, 13.0, 12.0, 1.5, String(h["mag"]), ink, 1.6)
					out += _box(k * 23.0 - 10.0, -28.0, 20.0, 40.0, 2.5, web, ink, 2.0)
					out += _line(k * 23.0 - 10.0, -14.0, k * 23.0 + 10.0, -14.0, ink, 1.3) + _line(k * 23.0 - 10.0, 0.0, k * 23.0 + 10.0, 0.0, String(h["web_dark"]), 1.3)
				out += _line(28.0, -72.0, 31.0, -112.0, ink, 2.6)
				out += _box(15.0, -76.0, 17.0, 30.0, 2.5, "#2f3236", ink, 2.0) + _box(18.0, -70.0, 11.0, 8.0, 1.0, "#565b62") + _circle(19.5, -52.0, 1.6, "#8f959c")
	if chest_style == "bandolier":
		out += _line(-40.0, -100.0, 36.0, 18.0, ink, 17.0) + _line(-40.0, -100.0, 36.0, 18.0, String(chest["color"]), 13.0)
		for k in 9:
			out += "<g transform=\"translate(%s %s) rotate(-33)\">%s</g>" % [_f(-36.0 + 8.4 * k), _f(-93.0 + 13.0 * k), _box(-2.2, -5.5, 4.4, 11.0, 1.6, String(chest["trim"]), ink, 0.9)]

	# --- belt ---
	var belt_color := web if belt.is_empty() else String(belt["color"])
	var buckle := String(h["buckle"]) if belt.is_empty() else String(belt["trim"])
	var belt_style := _style(belt)
	if belt_style == "machete":
		# A machete in its sheath hangs from the belt on his right hip.
		out += "<g transform=\"translate(-33 36) rotate(12)\">" + _box(-5.0, -16.0, 10.0, 16.0, 3.0, "#2b2622", ink, 1.6) + _box(-6.5, 0.0, 13.0, 62.0, 3.0, belt_color, ink, 2.0) \
				+ _line(-6.5, 12.0, 6.5, 12.0, buckle, 2.0) + "</g>"
	for side: float in [-1.0, 1.0]:
		if belt_style == "money" and side > 0.0:
			continue
		out += _box(minf(side * 41.0, side * 22.0), 30.0, 19.0, 26.0, 3.0, belt_color if not belt.is_empty() else web, ink, 2.0)
		out += _line(minf(side * 41.0, side * 22.0), 40.0, maxf(side * 41.0, side * 22.0), 40.0, ink, 1.3)
	out += _box(-41.0, 19.0, 82.0, 18.0, 3.0, belt_color, ink, 2.2)
	out += _line(-38.0, 23.0, 38.0, 23.0, _shade(belt_color, -0.25), 1.4, "stroke-opacity=\"0.7\"")
	match belt_style:
		"champion":
			out += _oval(0.0, 28.0, 21.0, 15.0, buckle, ink, 2.2) + _oval(0.0, 28.0, 13.0, 9.0, "none", _shade(buckle, 0.3), 1.8) + _circle(0.0, 28.0, 4.0, belt_color, ink, 1.2)
		"ammo":
			for k in 7:
				out += _box(-36.0 + 10.6 * k, 21.0, 7.0, 14.0, 1.5, _shade(belt_color, -0.15), ink, 1.2) + _circle(-32.5 + 10.6 * k, 25.0, 1.6, buckle)
		"money":
			out += _box(8.0, 24.0, 32.0, 24.0, 5.0, belt_color, ink, 2.0) + _line(11.0, 31.0, 37.0, 31.0, buckle, 2.2) + _circle(13.0, 31.0, 2.4, buckle, ink, 0.8)
			out += _box(-10.0, 20.0, 20.0, 16.0, 2.0, buckle, ink, 1.6)
		_:
			out += _box(-10.0, 20.0, 20.0, 16.0, 2.0, buckle, ink, 1.6) + _box(-5.0, 24.0, 10.0, 8.0, 1.0, "none", ink, 1.2)

	# --- neck, scarf ---
	out += _box(-12.0, -126.0, 24.0, 22.0, 4.0, String(h["skin_dark"]), ink, 2.0)
	var red := String(h["scarf"])
	var fold := String(h["scarf_dark"])
	out += _path("M-21,-106 L-34,-92 L-27,-90 L-31,-80 L-18,-96 Z", red, ink, 1.8)      # the knot's tails, on his right
	var drape := "M-27,-112 Q0,-102 27,-112 L16,-92 L9,-86 L7,-76 L2,-70 L0,-60 L-3,-70 L-8,-76 L-10,-86 L-17,-92 Z"
	out += _filled("fs", drape, red, _oval(10.0, -84.0, 9.0, 22.0, "#000000", "", 0.0, "fill-opacity=\"0.18\""), ink, 2.0)
	out += _path("M-8,-100 L-2,-74 M8,-101 L4,-80", "none", fold, 1.6)
	var neck_wrap := "M-27,-112 Q-28,-126 -17,-128 Q0,-120 17,-128 Q28,-126 27,-112 Q0,-101 -27,-112 Z"
	out += _filled("fw", neck_wrap, red, _oval(12.0, -112.0, 14.0, 10.0, "#000000", "", 0.0, "fill-opacity=\"0.18\""), ink, 2.0)
	out += _path("M-18,-121 Q0,-113 18,-121", "none", fold, 1.6)

	# --- the amulet on his chest ---
	if not amulet.is_empty():
		var a_color := String(amulet["color"])
		var a_trim := String(amulet["trim"])
		if _style(amulet) == "chain":
			out += _path("M-23,-108 Q0,-40 23,-108", "none", ink, 7.4) + _path("M-23,-108 Q0,-40 23,-108", "none", a_color, 4.6)
			out += _path("M-23,-108 Q0,-40 23,-108", "none", _shade(a_color, 0.45), 1.6, "stroke-dasharray=\"2 5\"")
			out += _box(-7.0, -78.0, 14.0, 14.0, 2.0, a_color, ink, 1.6) + _box(-4.0, -75.0, 8.0, 8.0, 1.0, a_trim, ink, 1.0)
		else:
			out += _path("M-21,-108 L0,-58 L21,-108", "none", String(h["metal"]), 1.6)
			match _style(amulet):
				"tags":
					out += _box(-9.0, -60.0, 11.0, 17.0, 3.0, a_color, ink, 1.6) + _box(-1.0, -56.0, 11.0, 17.0, 3.0, a_color, ink, 1.6) + _line(2.0, -50.0, 7.0, -50.0, a_trim, 1.2) + _line(2.0, -46.0, 7.0, -46.0, a_trim, 1.2)
				"medal":
					out += _box(-7.0, -62.0, 7.0, 14.0, 0.0, String(h["flag_blue"]), ink, 1.2) + _box(0.0, -62.0, 7.0, 14.0, 0.0, String(h["flag_red"]), ink, 1.2)
					out += _circle(0.0, -40.0, 10.0, a_color, ink, 1.8) + _circle(0.0, -40.0, 5.5, "none", a_trim, 1.4)
				_:
					out += _box(-4.0, -62.0, 8.0, 6.0, 1.5, a_trim, ink, 1.2)
					out += _path("M-6,-56 L6,-56 Q5,-42 0,-32 Q-5,-42 -6,-56 Z", a_color, ink, 1.6)

	# --- head ---
	for side: float in [-1.0, 1.0]:
		out += _oval(side * 25.0, -145.0, 5.0, 8.0, skin, ink, 2.0) + _oval(side * 25.5, -145.0, 2.0, 4.5, String(h["skin_dark"]))
	var face := "M-24,-150 Q-25,-176 0,-177 Q25,-176 24,-150 Q24,-129 12,-120 Q0,-113 -12,-120 Q-24,-129 -24,-150 Z"
	out += _filled("fa", face, skin, _oval(-9.0, -150.0, 12.0, 16.0, String(h["skin_light"]), "", 0.0, "fill-opacity=\"0.45\"")
			+ _oval(14.0, -134.0, 14.0, 22.0, String(h["skin_dark"]), "", 0.0, "fill-opacity=\"0.5\"") + _oval(0.0, -116.0, 16.0, 6.0, String(h["skin_dark"]), "", 0.0, "fill-opacity=\"0.45\""), ink, 2.2)
	var hair := "M-25,-149 Q-28,-181 0,-182 Q28,-181 25,-149 Q23,-162 13,-163 Q0,-165 -13,-163 Q-23,-162 -25,-149 Z"
	var curls := ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for row in 9:
		for col in 15:
			curls += _circle(-27.0 + col * 3.8 + (1.9 if row % 2 == 1 else 0.0) + rng.randf_range(-0.5, 0.5), -181.0 + row * 3.8 + rng.randf_range(-0.5, 0.5), 1.25, String(h["hair_light"]))
	out += _filled("fh", hair, String(h["hair"]), curls, ink, 2.0)
	for side: float in [-1.0, 1.0]:
		out += _oval(side * 10.5, -143.0, 5.0, 2.9, "#efe9dc", ink, 1.0) + _circle(side * 10.2, -143.0, 2.4, "#2a1a10")
		out += _path("M%s,-151 L%s,-148" % [_f(side * 17.5), _f(side * 5.0)], "none", String(h["hair"]), 3.6)
		out += _path("M%s,-146 Q%s,-147.5 %s,-145" % [_f(side * 16.0), _f(side * 10.0), _f(side * 5.0)], "none", ink, 1.4)
	out += _path("M-2,-142 Q-4.5,-133 -6.5,-130 Q0,-126 6.5,-130", "none", String(h["skin_dark"]), 2.0)
	out += _line(-8.0, -121.5, 8.0, -121.5, "#3f2218", 2.4) + _line(-4.0, -117.5, 4.0, -117.5, String(h["skin_dark"]), 1.6)
	out += _line(14.5, -157.0, 10.0, -139.0, "#b9805c", 1.6)      # the scar through his left eyebrow

	var hat := String(helmet.get("color", "#000000"))
	var hat_trim := String(helmet.get("trim", "#000000"))
	match _style(helmet):
		"hardhat":
			var dome := "M-30,-153 Q-32,-187 0,-188 Q32,-187 30,-153 Z"
			out += _filled("fy", dome, hat, _upright(Rect2(-32.0, -188.0, 64.0, 35.0), 1.4), ink, 2.2)
			out += _box(-4.5, -188.0, 9.0, 34.0, 2.0, hat_trim, ink, 1.4)
			for side: float in [-1.0, 1.0]:
				out += _path("M%s,-184 Q%s,-170 %s,-154" % [_f(side * 13.0), _f(side * 19.0), _f(side * 20.0)], "none", hat_trim, 2.6)
			out += _box(-37.0, -157.0, 74.0, 10.0, 4.5, _shade(hat, 0.12), ink, 2.2)
		"cap":
			var crown := "M-27,-152 Q-29,-182 0,-183 Q29,-182 27,-152 Z"
			out += _filled("fy", crown, hat, _blots(81, Rect2(-28.0, -183.0, 56.0, 32.0), 12, [hat_trim], 5.0, 0.85) + _upright(Rect2(-29.0, -183.0, 58.0, 31.0)), ink, 2.2)
			out += _path("M-29,-154 Q0,-161 31,-154 L37,-144 Q2,-152 -31,-146 Z", _shade(hat, 0.22), ink, 2.0)
		"mask":
			# A gas mask: big round eye pieces, the snout, a filter on each side, straps over his hair.
			out += _path("M-22,-150 Q-12,-170 0,-172 Q12,-170 22,-150", "none", hat_trim, 3.4)
			out += _path("M-23,-138 Q0,-152 23,-138 L18,-114 Q0,-104 -18,-114 Z", hat, ink, 2.2)
			for side: float in [-1.0, 1.0]:
				out += _circle(side * 10.5, -144.0, 8.4, hat_trim, ink, 1.8) + _circle(side * 10.5, -144.0, 5.8, "#1b2226") + _path("M%s,-147 L%s,-143" % [_f(side * 10.5 - 3.0), _f(side * 10.5 - 0.5)], "none", "#7f93a0", 1.4)
				out += _circle(side * 23.0, -117.0, 9.5, _shade(hat, 0.2), ink, 2.0) + _circle(side * 23.0, -117.0, 5.0, hat_trim, ink, 1.0)
			out += _box(-7.0, -126.0, 14.0, 12.0, 4.0, _shade(hat, 0.25), ink, 1.6)
		"helmet":
			var shell := "M-30,-146 Q-33,-185 0,-186 Q33,-185 30,-146 L27,-151 Q0,-158 -27,-151 Z"
			out += _filled("fy", shell, hat, _blots(83, Rect2(-32.0, -186.0, 64.0, 40.0), 16, [hat_trim, _shade(hat, -0.2)], 5.6, 0.85) + _upright(Rect2(-33.0, -186.0, 66.0, 40.0), 1.3), ink, 2.2)
			out += _path("M-29,-160 Q0,-167 29,-160", "none", _shade(hat_trim, 0.2), 2.4)
			for side: float in [-1.0, 1.0]:
				out += _path("M%s,-149 L%s,-124 L%s,-117" % [_f(side * 26.0), _f(side * 21.0), _f(side * 9.0)], "none", "#2a2c2e", 2.6)
			out += _box(-5.0, -180.0, 10.0, 8.0, 1.5, "#2a2c2e", ink, 1.2)
			out += _flag(h, 17.0, -172.0, 13.0, 9.0, 6.0)
	return out


## The guns in his hands in the menu picture. Each is drawn hanging straight down from his
## fist at (0, 0); the picture turns them a little outward. Plain, made-up guns.
const FRONT_PISTOL := """
<rect x="-6.5" y="-2" width="13" height="50" rx="2.5" fill="#3a3f46" stroke="#15130f" stroke-width="2"/>
<rect x="-6.5" y="-2" width="4.6" height="50" rx="2" fill="#6d7580" fill-opacity="0.8"/>
<rect x="-3" y="44" width="6" height="8" rx="1.5" fill="#23262a" stroke="#15130f" stroke-width="1.4"/>
<path d="M-6.5,8 L6.5,8 M-6.5,13 L6.5,13 M-6.5,18 L6.5,18" stroke="#15130f" stroke-width="1.1"/>
<path d="M6.5,2 Q15,4 13,14 L6.5,14" fill="none" stroke="#15130f" stroke-width="2.2"/>
"""

const FRONT_RIFLE := """
<path d="M-8,-76 L8,-76 L7,-24 L-6.5,-24 Z" fill="#8c5c2f" stroke="#15130f" stroke-width="2.2" stroke-linejoin="round"/>
<path d="M-5,-72 L-4.5,-28" stroke="#c48d54" stroke-width="2.4" stroke-opacity="0.7" stroke-linecap="round"/>
<rect x="-9" y="-80" width="18" height="6" rx="2" fill="#23262a" stroke="#15130f" stroke-width="1.6"/>
<path d="M7.5,9 L17,8 Q22,18 21,30 L12.5,31 Q13.5,22 7.5,21 Z" fill="#3a3f46" stroke="#15130f" stroke-width="2" stroke-linejoin="round"/>
<path d="M12,12 Q16.5,20 16.5,29" stroke="#15130f" stroke-width="1" stroke-opacity="0.8" fill="none"/>
<rect x="-7.5" y="-24" width="15" height="52" rx="2" fill="#3a3f46" stroke="#15130f" stroke-width="2.2"/>
<rect x="-7.5" y="-24" width="5" height="52" rx="2" fill="#6d7580" fill-opacity="0.75"/>
<rect x="2" y="-14" width="4" height="12" rx="1" fill="#15130f"/>
<rect x="-7" y="28" width="14" height="36" rx="2.5" fill="#8c5c2f" stroke="#15130f" stroke-width="2.2"/>
<path d="M-7,38 L7,38 M-7,46 L7,46 M-7,54 L7,54" stroke="#5c3a1c" stroke-width="1.6"/>
<rect x="-3" y="64" width="6" height="52" rx="1.5" fill="#4a5058" stroke="#15130f" stroke-width="2"/>
<rect x="-6.5" y="96" width="5" height="9" rx="1" fill="#23262a" stroke="#15130f" stroke-width="1.4"/>
<rect x="-4.5" y="112" width="9" height="11" rx="1.5" fill="#23262a" stroke="#15130f" stroke-width="1.8"/>
"""
