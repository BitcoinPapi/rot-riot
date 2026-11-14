extends Node
## ============================================================================
##  PLACEHOLDER ART
##
##  Every sprite in the game is built here at startup from simple shapes
##  (circles, rectangles, a few polygons) written as tiny SVG drawings.
##  Nothing is copied from any other game.
##
##  REPLACING A SPRITE WITH REAL ART LATER:
##  Put a PNG named like the sprite in  res://assets/sprites/  - for example
##  assets/sprites/shambler_0.png - and it is used instead of the shapes.
##  Draw it facing RIGHT, at 2x the size listed in _build() (so a 56x56 sprite
##  becomes a 112x112 PNG). White "hit flash" versions are generated for you.
## ============================================================================

const PX := 2.0   # sprites are rasterised at 2x and drawn at half size, so they stay sharp in fullscreen

var tex: Dictionary = {}     # name -> Texture2D
var sizes: Dictionary = {}   # name -> Vector2 (size in game pixels)
var _images: Dictionary = {} # name -> Image (kept only while building)

const SHAMBLER_VARIANTS := 4
const RUNNER_VARIANTS := 2
const BRUTE_VARIANTS := 2

const ENEMY_SPRITE := ["shambler", "runner", "brute", "boss"]   # indexed by enemy kind (see Config)
const ENEMY_VARIANTS := [SHAMBLER_VARIANTS, RUNNER_VARIANTS, BRUTE_VARIANTS, 1]


func _ready() -> void:
	_build()
	_images.clear()


## Texture by name.
func t(sprite: String) -> Texture2D:
	return tex[sprite]


## Size of a sprite in game pixels.
func size_of(sprite: String) -> Vector2:
	return sizes[sprite]


func enemy_tex(kind: int, variant: int) -> Texture2D:
	return tex["%s_%d" % [ENEMY_SPRITE[kind], variant]]


func enemy_flash_tex(kind: int) -> Texture2D:
	return tex["%s_0_flash" % ENEMY_SPRITE[kind]]


## Draw a sprite centred on `pos` in the canvas item `ci`.
func draw(ci: CanvasItem, sprite: String, pos: Vector2, scale: float = 1.0, color: Color = Color.WHITE) -> void:
	var s: Vector2 = sizes[sprite] * scale
	ci.draw_texture_rect(tex[sprite], Rect2(pos - s * 0.5, s), false, color)


# ----------------------------------------------------------------------------
#  Building
# ----------------------------------------------------------------------------
func _build() -> void:
	# --- zombies (all drawn facing right) ---
	var shirts := ["#5b6f8c", "#8a5550", "#7d7a55", "#5a6d62"]
	var skins := ["#8fb56a", "#86a95f", "#9bbd74", "#7fa262"]
	for i in SHAMBLER_VARIANTS:
		_svg("shambler_%d" % i, 56, 56, SVG_SHAMBLER.format({
			"line": "#1a2114", "skin": skins[i], "shirt": shirts[i], "blood": "#7a1f1f",
			"hair": "#34422a", "eye": "#ff3b30"}))
	_flash("shambler_0")

	var runner_shirts := ["#6b4a3a", "#4f4a6b"]
	for i in RUNNER_VARIANTS:
		_svg("runner_%d" % i, 48, 48, SVG_RUNNER.format({
			"line": "#231a0c", "skin": "#e0b040", "shirt": runner_shirts[i],
			"hair": "#7a3b1c", "eye": "#ffffff"}))
	_flash("runner_0")

	var brute_shirts := ["#4a3d5c", "#5c3d46"]
	for i in BRUTE_VARIANTS:
		_svg("brute_%d" % i, 92, 92, SVG_BRUTE.format({
			"line": "#17111f", "skin": "#8d6fa8", "skin2": "#73578c", "shirt": brute_shirts[i],
			"bone": "#d9d2bd", "hair": "#3b2a4d", "eye": "#ffe14a"}))
	_flash("brute_0")

	_svg("boss_0", 176, 176, SVG_BOSS.format({
		"line": "#1c0a0a", "skin": "#8e2f2f", "skin2": "#6e2222", "skin3": "#a53c36",
		"bone": "#e6dcc0", "eye": "#ffd23f"}))
	_flash("boss_0")

	# --- player and weapons ---
	_svg("player", 56, 56, SVG_PLAYER)
	_flash("player")
	_svg("gun_pistol", 24, 12, SVG_GUN_PISTOL, false)
	_svg("gun_shotgun", 42, 14, SVG_GUN_SHOTGUN, false)
	_svg("gun_machinegun", 46, 18, SVG_GUN_MACHINEGUN, false)
	_svg("gun_launcher", 44, 20, SVG_GUN_LAUNCHER, false)
	_svg("gun_sledge", 54, 28, SVG_GUN_SLEDGE, false)
	_svg("gun_smg", 36, 16, SVG_GUN_SMG, false)
	_svg("gun_rifle", 58, 14, SVG_GUN_RIFLE, false)
	_svg("gun_flamethrower", 48, 22, SVG_GUN_FLAMETHROWER, false)
	_svg("gun_chainsaw", 54, 22, SVG_GUN_CHAINSAW, false)
	_svg("grenade", 16, 16, SVG_GRENADE)

	# --- pickups ---
	_svg("coin", 18, 18, SVG_COIN)
	_svg("crate", 38, 38, SVG_CRATE)
	_svg("medkit", 28, 28, SVG_MEDKIT)

	# --- scenery ---
	_svg("rock", 120, 120, SVG_ROCK)
	_svg("stump", 120, 120, SVG_STUMP)
	_svg("canopy", 220, 220, SVG_CANOPY)

	# --- effects (white, tinted when drawn) ---
	_svg("splat_0", 72, 72, SVG_SPLAT_0)
	_svg("splat_1", 72, 72, SVG_SPLAT_1)
	_svg("splat_2", 72, 72, SVG_SPLAT_2)
	_svg("flash", 64, 64, SVG_MUZZLE_FLASH)
	_svg("dot", 32, 32, "<circle r=\"15\" fill=\"#ffffff\"/>")
	_svg("glow", 64, 64, SVG_GLOW)
	_svg("ring", 128, 128, "<circle r=\"58\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"5\"/>")

	# Soft screen-edge vignette used by the HUD (tinted red when hurt).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	var vignette := GradientTexture2D.new()
	vignette.gradient = gradient
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.0, 1.0)
	vignette.width = 256
	vignette.height = 256
	tex["vignette"] = vignette
	sizes["vignette"] = Vector2(256, 256)


## Rasterise an SVG drawing into a texture. `centered` puts (0,0) in the middle
## of the sprite; otherwise (0,0) is the middle of the LEFT edge (used for guns,
## so they rotate around the grip).
func _svg(sprite: String, w: int, h: int, body: String, centered: bool = true) -> void:
	var override_path := "res://assets/sprites/%s.png" % sprite
	if ResourceLoader.exists(override_path):
		var custom: Texture2D = load(override_path)
		tex[sprite] = custom
		sizes[sprite] = Vector2(custom.get_size()) / PX
		_images[sprite] = custom.get_image()
		return
	var view_x := -w * 0.5 if centered else 0.0
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"%s %s %d %d\">%s</svg>" % [
		w, h, str(view_x), str(-h * 0.5), w, h, body]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, PX)
	if err != OK or img.is_empty():
		push_error("Art: could not build sprite '%s'" % sprite)
		img = Image.create(int(w * PX), int(h * PX), false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	tex[sprite] = ImageTexture.create_from_image(img)
	sizes[sprite] = Vector2(w, h)
	_images[sprite] = img


## Make a pure white copy of a sprite, used for the hit flash.
func _flash(sprite: String) -> void:
	var src: Image = _images.get(sprite)
	if src == null:
		return
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var i := 0
	var n := data.size()
	while i < n:
		data[i] = 255
		data[i + 1] = 255
		data[i + 2] = 255
		i += 4
	var white := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	tex[sprite + "_flash"] = ImageTexture.create_from_image(white)
	sizes[sprite + "_flash"] = sizes[sprite]


# ----------------------------------------------------------------------------
#  The drawings. {tokens} are colours filled in by _build().
# ----------------------------------------------------------------------------
const SVG_SHAMBLER := """
<circle cx="0" cy="0" r="20" fill="#000000" fill-opacity="0.22"/>
<path d="M0,-11 L17,-8" stroke="{line}" stroke-width="9" stroke-linecap="round" fill="none"/>
<path d="M0,11 L15,9" stroke="{line}" stroke-width="9" stroke-linecap="round" fill="none"/>
<path d="M0,-11 L17,-8" stroke="{skin}" stroke-width="5.6" stroke-linecap="round" fill="none"/>
<path d="M0,11 L15,9" stroke="{skin}" stroke-width="5.6" stroke-linecap="round" fill="none"/>
<ellipse cx="-2" cy="0" rx="10.8" ry="14.8" fill="{line}"/>
<ellipse cx="-2" cy="0" rx="9.2" ry="13.2" fill="{shirt}"/>
<path d="M-9,-8 L-3,-5 L-8,2 Z" fill="{blood}"/>
<circle cx="3" cy="0" r="8.8" fill="{line}"/>
<circle cx="3" cy="0" r="7.3" fill="{skin}"/>
<path d="M-3,-4.5 Q-6.5,0 -3,4.5 Q0.5,0 -3,-4.5 Z" fill="{hair}"/>
<circle cx="7.4" cy="-3" r="1.8" fill="{eye}"/>
<circle cx="7.4" cy="3" r="1.8" fill="{eye}"/>
"""

const SVG_RUNNER := """
<circle cx="0" cy="0" r="16" fill="#000000" fill-opacity="0.22"/>
<path d="M-2,-8 L-14,-12" stroke="{line}" stroke-width="7.4" stroke-linecap="round" fill="none"/>
<path d="M-2,8 L-14,12" stroke="{line}" stroke-width="7.4" stroke-linecap="round" fill="none"/>
<path d="M-2,-8 L-14,-12" stroke="{skin}" stroke-width="4.2" stroke-linecap="round" fill="none"/>
<path d="M-2,8 L-14,12" stroke="{skin}" stroke-width="4.2" stroke-linecap="round" fill="none"/>
<ellipse cx="-1" cy="0" rx="9.4" ry="11.4" fill="{line}"/>
<ellipse cx="-1" cy="0" rx="7.9" ry="9.9" fill="{shirt}"/>
<path d="M-1,-8.6 L14,0 L-1,8.6 Z" fill="{line}" stroke="{line}" stroke-width="1.5" stroke-linejoin="round"/>
<path d="M0.6,-6.2 L11.2,0 L0.6,6.2 Z" fill="{skin}"/>
<circle cx="5" cy="-2.5" r="1.5" fill="{eye}"/>
<circle cx="5" cy="2.5" r="1.5" fill="{eye}"/>
<path d="M-4.5,-5 L-9,-2.4 L-5,0 L-9,2.4 L-4.5,5 Z" fill="{hair}"/>
"""

const SVG_BRUTE := """
<circle cx="0" cy="0" r="35" fill="#000000" fill-opacity="0.24"/>
<path d="M0,-22 L25,-18" stroke="{line}" stroke-width="17" stroke-linecap="round" fill="none"/>
<path d="M0,22 L25,18" stroke="{line}" stroke-width="17" stroke-linecap="round" fill="none"/>
<path d="M0,-22 L25,-18" stroke="{skin}" stroke-width="13" stroke-linecap="round" fill="none"/>
<path d="M0,22 L25,18" stroke="{skin}" stroke-width="13" stroke-linecap="round" fill="none"/>
<circle cx="27" cy="-18" r="8" fill="{skin2}" stroke="{line}" stroke-width="1.6"/>
<circle cx="27" cy="18" r="8" fill="{skin2}" stroke="{line}" stroke-width="1.6"/>
<ellipse cx="-4" cy="0" rx="20.5" ry="27.5" fill="{line}"/>
<ellipse cx="-4" cy="0" rx="18.6" ry="25.6" fill="{shirt}"/>
<path d="M-16,-17 L6,17" stroke="{line}" stroke-width="3.2" stroke-linecap="round"/>
<path d="M-12,-6 L-6,-10 M-8,1 L-2,-3 M-4,8 L2,4" stroke="{bone}" stroke-width="1.8" stroke-linecap="round"/>
<circle cx="5" cy="0" r="12" fill="{line}"/>
<circle cx="5" cy="0" r="10.3" fill="{skin}"/>
<circle cx="11.6" cy="-4.2" r="2.4" fill="{eye}"/>
<circle cx="11.6" cy="4.2" r="2.4" fill="{eye}"/>
<path d="M-1,-7 Q-6,0 -1,7" stroke="{hair}" stroke-width="3" fill="none" stroke-linecap="round"/>
"""

const SVG_BOSS := """
<circle cx="0" cy="0" r="66" fill="#000000" fill-opacity="0.26"/>
<path d="M-40,-26 L-68,-36 L-46,-8 Z" fill="{bone}" stroke="{line}" stroke-width="2.4" stroke-linejoin="round"/>
<path d="M-46,-9 L-76,0 L-46,9 Z" fill="{bone}" stroke="{line}" stroke-width="2.4" stroke-linejoin="round"/>
<path d="M-40,26 L-68,36 L-46,8 Z" fill="{bone}" stroke="{line}" stroke-width="2.4" stroke-linejoin="round"/>
<path d="M4,-44 L46,-36" stroke="{line}" stroke-width="29" stroke-linecap="round" fill="none"/>
<path d="M4,44 L46,36" stroke="{line}" stroke-width="29" stroke-linecap="round" fill="none"/>
<path d="M4,-44 L46,-36" stroke="{skin}" stroke-width="24" stroke-linecap="round" fill="none"/>
<path d="M4,44 L46,36" stroke="{skin}" stroke-width="24" stroke-linecap="round" fill="none"/>
<path d="M60,-44 L73,-42 L61,-37 Z M62,-36 L75,-33 L61,-30 Z" fill="{bone}"/>
<path d="M60,44 L73,42 L61,37 Z M62,36 L75,33 L61,30 Z" fill="{bone}"/>
<circle cx="50" cy="-36" r="14" fill="{skin2}" stroke="{line}" stroke-width="2.4"/>
<circle cx="50" cy="36" r="14" fill="{skin2}" stroke="{line}" stroke-width="2.4"/>
<ellipse cx="-8" cy="0" rx="42" ry="54" fill="{line}"/>
<ellipse cx="-8" cy="0" rx="39.4" ry="51.4" fill="{skin}"/>
<ellipse cx="-20" cy="-16" rx="13" ry="18" fill="{skin2}"/>
<ellipse cx="-22" cy="22" rx="10" ry="12" fill="{skin2}"/>
<path d="M-34,6 L-2,36" stroke="{line}" stroke-width="3.6" stroke-linecap="round"/>
<path d="M-28,4 L-22,16 M-20,11 L-14,23 M-12,18 L-6,30" stroke="{bone}" stroke-width="2.6" stroke-linecap="round"/>
<circle cx="14" cy="0" r="24" fill="{line}"/>
<circle cx="14" cy="0" r="21.6" fill="{skin3}"/>
<path d="M30,-11 L38,-7.5 L31,-4.5 L38,-1.5 L31,1.5 L38,4.5 L31,7.5 L38,11 L28,13 L28,-13 Z" fill="{bone}" stroke="{line}" stroke-width="1.6" stroke-linejoin="round"/>
<circle cx="23" cy="-10" r="4.8" fill="{line}"/>
<circle cx="23" cy="10" r="4.8" fill="{line}"/>
<circle cx="23.6" cy="-10" r="3.3" fill="{eye}"/>
<circle cx="23.6" cy="10" r="3.3" fill="{eye}"/>
<path d="M2,-14 Q-6,0 2,14" stroke="{line}" stroke-width="3.4" fill="none" stroke-linecap="round"/>
"""

const SVG_PLAYER := """
<circle cx="0" cy="0" r="20" fill="#000000" fill-opacity="0.24"/>
<path d="M0,-10.5 L13,-4" stroke="#1c1712" stroke-width="9" stroke-linecap="round" fill="none"/>
<path d="M0,10.5 L13,4" stroke="#1c1712" stroke-width="9" stroke-linecap="round" fill="none"/>
<path d="M0,-10.5 L13,-4" stroke="#e8862e" stroke-width="5.6" stroke-linecap="round" fill="none"/>
<path d="M0,10.5 L13,4" stroke="#e8862e" stroke-width="5.6" stroke-linecap="round" fill="none"/>
<circle cx="14" cy="-3.6" r="3.5" fill="#f0c7a0" stroke="#1c1712" stroke-width="1.2"/>
<circle cx="14" cy="3.6" r="3.5" fill="#f0c7a0" stroke="#1c1712" stroke-width="1.2"/>
<ellipse cx="-2" cy="0" rx="10.4" ry="14.6" fill="#1c1712"/>
<ellipse cx="-2" cy="0" rx="8.8" ry="13" fill="#e8862e"/>
<rect x="-12.5" y="-7.5" width="7.5" height="15" rx="2.5" fill="#6b5236" stroke="#1c1712" stroke-width="1.4"/>
<circle cx="2.5" cy="0" r="8.6" fill="#1c1712"/>
<circle cx="2.5" cy="0" r="7.1" fill="#2f6aa8"/>
<path d="M6.5,-6 Q14.5,0 6.5,6 Q8.6,0 6.5,-6 Z" fill="#1f4c7c" stroke="#1c1712" stroke-width="1.2" stroke-linejoin="round"/>
<circle cx="1.5" cy="0" r="1.8" fill="#5c9bdc"/>
"""

const SVG_GUN_PISTOL := """
<rect x="3" y="-3.2" width="18" height="6.4" rx="1.6" fill="#16181c"/>
<rect x="6" y="-2.2" width="14" height="2.4" rx="1" fill="#9aa3ad"/>
"""

const SVG_GUN_SHOTGUN := """
<rect x="1" y="-3.6" width="14" height="7.2" rx="2" fill="#16181c"/>
<rect x="2" y="-2.6" width="12" height="5.2" rx="1.6" fill="#8a5a2c"/>
<rect x="13" y="-4.2" width="27" height="8.4" rx="1.6" fill="#16181c"/>
<rect x="14.5" y="-3" width="24.5" height="2.5" rx="1" fill="#b4bcc6"/>
<rect x="14.5" y="0.5" width="24.5" height="2.5" rx="1" fill="#8e97a2"/>
<rect x="20" y="-4.6" width="8" height="9.2" rx="1.4" fill="#6b4420" stroke="#16181c" stroke-width="1"/>
"""

const SVG_GUN_MACHINEGUN := """
<rect x="0" y="-3.4" width="12" height="6.8" rx="1.6" fill="#16181c"/>
<rect x="10" y="-4.6" width="22" height="9.2" rx="1.8" fill="#16181c"/>
<rect x="12" y="-3.2" width="18" height="3" rx="1" fill="#5d6670"/>
<rect x="30" y="-2.6" width="14" height="5.2" rx="1.2" fill="#16181c"/>
<rect x="32" y="-1.4" width="11" height="2.2" rx="1" fill="#99a2ad"/>
<rect x="15" y="3" width="8" height="5.6" rx="1.2" fill="#3c434b" stroke="#16181c" stroke-width="1"/>
"""

const SVG_GUN_LAUNCHER := """
<rect x="1" y="-5.6" width="38" height="11.2" rx="3" fill="#16181c"/>
<rect x="2.5" y="-4.2" width="35" height="8.4" rx="2.2" fill="#5f7d3a"/>
<rect x="34" y="-7.4" width="9" height="14.8" rx="2.4" fill="#16181c"/>
<rect x="35.4" y="-6" width="6.2" height="12" rx="1.6" fill="#3f5626"/>
<rect x="10" y="-4.2" width="5" height="8.4" fill="#e9c94a"/>
"""

const SVG_GUN_SLEDGE := """
<rect x="0" y="-2.8" width="42" height="5.6" rx="2" fill="#16181c"/>
<rect x="1.2" y="-1.6" width="40" height="3.2" rx="1.4" fill="#9a6a38"/>
<rect x="36" y="-12.5" width="15" height="25" rx="3" fill="#16181c"/>
<rect x="37.6" y="-11" width="11.8" height="22" rx="2" fill="#a9b2bd"/>
<rect x="37.6" y="-11" width="11.8" height="5.5" rx="2" fill="#d5dbe2"/>
"""

const SVG_GUN_SMG := """
<rect x="0" y="-2.6" width="9" height="5.2" rx="1.4" fill="#16181c"/>
<rect x="7" y="-4.4" width="19" height="8.8" rx="1.8" fill="#16181c"/>
<rect x="9" y="-3" width="15" height="2.6" rx="1" fill="#4f6b73"/>
<rect x="25" y="-2.2" width="10" height="4.4" rx="1.2" fill="#16181c"/>
<rect x="27" y="-1.1" width="7" height="1.8" rx="0.8" fill="#99a2ad"/>
<rect x="13" y="3" width="6" height="5" rx="1.2" fill="#3c434b" stroke="#16181c" stroke-width="1"/>
"""

const SVG_GUN_RIFLE := """
<rect x="0" y="-3.4" width="16" height="6.8" rx="2" fill="#16181c"/>
<rect x="1" y="-2.4" width="14" height="4.8" rx="1.5" fill="#7a5230"/>
<rect x="14" y="-3.2" width="20" height="6.4" rx="1.4" fill="#16181c"/>
<rect x="16" y="-2" width="16" height="2.2" rx="1" fill="#5d6670"/>
<rect x="32" y="-1.9" width="25" height="3.8" rx="1.2" fill="#16181c"/>
<rect x="34" y="-0.9" width="22" height="1.6" rx="0.8" fill="#aab2bc"/>
<rect x="18" y="-6.2" width="12" height="3.4" rx="1.4" fill="#2a2f36" stroke="#16181c" stroke-width="0.8"/>
"""

const SVG_GUN_FLAMETHROWER := """
<rect x="0" y="-8.5" width="14" height="17" rx="5" fill="#16181c"/>
<rect x="1.4" y="-7" width="11.2" height="14" rx="4" fill="#b23a2a"/>
<rect x="3" y="-5.5" width="3" height="11" rx="1.5" fill="#d9644f"/>
<rect x="12" y="-3.6" width="24" height="7.2" rx="2" fill="#16181c"/>
<rect x="14" y="-2.4" width="20" height="2.4" rx="1" fill="#6d747d"/>
<rect x="34" y="-2.6" width="12" height="5.2" rx="1.4" fill="#16181c"/>
<rect x="36" y="-1.4" width="9" height="2.8" rx="1" fill="#e9a23a"/>
<circle cx="46" cy="0" r="1.8" fill="#ffd36b"/>
"""

const SVG_GUN_CHAINSAW := """
<rect x="4" y="-10" width="10" height="4.4" rx="2" fill="#16181c"/>
<rect x="0" y="-7" width="18" height="14" rx="3" fill="#16181c"/>
<rect x="1.4" y="-5.6" width="15.2" height="11.2" rx="2.2" fill="#e8731f"/>
<rect x="4" y="-3" width="6" height="6" rx="1.5" fill="#b3540f"/>
<rect x="16" y="-4.6" width="37" height="9.2" rx="4.6" fill="#16181c"/>
<rect x="18" y="-2.8" width="33" height="5.6" rx="2.8" fill="#aab2bc"/>
<path d="M20,-4.6 L22,-6.2 L24,-4.6 M27,-4.6 L29,-6.2 L31,-4.6 M34,-4.6 L36,-6.2 L38,-4.6 M41,-4.6 L43,-6.2 L45,-4.6 M20,4.6 L22,6.2 L24,4.6 M27,4.6 L29,6.2 L31,4.6 M34,4.6 L36,6.2 L38,4.6 M41,4.6 L43,6.2 L45,4.6" stroke="#16181c" stroke-width="1.6" fill="none"/>
"""

const SVG_GRENADE := """
<circle r="6.8" fill="#16181c"/>
<circle r="5.2" fill="#59752f"/>
<circle cx="-1.6" cy="-1.6" r="1.7" fill="#b8d67a"/>
"""

const SVG_COIN := """
<circle r="8.2" fill="#6b4700"/>
<circle r="6.8" fill="#ffc531"/>
<circle r="4.3" fill="#ffe27a"/>
<circle cx="-1.8" cy="-2" r="1.4" fill="#fff6cf"/>
"""

const SVG_CRATE := """
<rect x="-18" y="-18" width="36" height="36" rx="5" fill="#000000" fill-opacity="0.25"/>
<rect x="-15.5" y="-15.5" width="31" height="31" rx="3.4" fill="#2b1d0f"/>
<rect x="-13.6" y="-13.6" width="27.2" height="27.2" rx="2.2" fill="#b07c42"/>
<path d="M-13.6,-4.6 L13.6,-4.6 M-13.6,4.6 L13.6,4.6" stroke="#7d5427" stroke-width="1.6"/>
<path d="M-12.6,-12.6 L12.6,12.6 M12.6,-12.6 L-12.6,12.6" stroke="#8c6030" stroke-width="2.6"/>
<rect x="-13.6" y="-13.6" width="27.2" height="27.2" rx="2.2" fill="none" stroke="#d8a868" stroke-width="1.4"/>
"""

const SVG_MEDKIT := """
<rect x="-13" y="-13" width="26" height="26" rx="6" fill="#000000" fill-opacity="0.25"/>
<rect x="-11" y="-11" width="22" height="22" rx="4.4" fill="#1d1d1d"/>
<rect x="-9.4" y="-9.4" width="18.8" height="18.8" rx="3.4" fill="#f4f1ea"/>
<rect x="-2.6" y="-7" width="5.2" height="14" rx="1" fill="#e0342b"/>
<rect x="-7" y="-2.6" width="14" height="5.2" rx="1" fill="#e0342b"/>
"""

const SVG_ROCK := """
<circle r="57" fill="#000000" fill-opacity="0.25"/>
<path d="M-46,-14 L-30,-42 L4,-50 L38,-34 L50,-4 L42,30 L12,48 L-24,44 L-48,18 Z" fill="#24262a"/>
<path d="M-42,-13 L-28,-38 L4,-46 L35,-31 L46,-4 L38,27 L11,44 L-22,40 L-44,16 Z" fill="#646a72"/>
<path d="M-28,-38 L4,-46 L35,-31 L10,-18 L-16,-22 Z" fill="#868d96"/>
<path d="M-42,-13 L-28,-38 L-16,-22 L-22,6 Z" fill="#747b84"/>
<path d="M10,-18 L35,-31 L46,-4 L24,10 Z" fill="#6c727a"/>
<path d="M-22,6 L24,10 L38,27 L11,44 L-22,40 L-44,16 Z" fill="#555a61"/>
<path d="M-10,14 L6,18 M18,24 L26,22" stroke="#3a3d42" stroke-width="2" stroke-linecap="round"/>
"""

const SVG_STUMP := """
<circle r="57" fill="#000000" fill-opacity="0.25"/>
<circle r="49" fill="#241a10"/>
<circle r="45.5" fill="#6e4d2b"/>
<circle r="38" fill="#a67c4e"/>
<circle r="38" fill="none" stroke="#8a6238" stroke-width="2"/>
<circle r="28" fill="none" stroke="#8a6238" stroke-width="2"/>
<circle r="18" fill="none" stroke="#8a6238" stroke-width="2"/>
<circle r="8" fill="none" stroke="#8a6238" stroke-width="2"/>
<path d="M0,0 L30,-22 M-6,4 L-34,14" stroke="#5c4023" stroke-width="2.4" stroke-linecap="round"/>
"""

const SVG_CANOPY := """
<circle cx="0" cy="0" r="92" fill="#0a1408"/>
<circle cx="-48" cy="-40" r="52" fill="#0a1408"/>
<circle cx="50" cy="-44" r="50" fill="#0a1408"/>
<circle cx="56" cy="40" r="52" fill="#0a1408"/>
<circle cx="-50" cy="46" r="50" fill="#0a1408"/>
<circle cx="-10" cy="-8" r="80" fill="#101f0d"/>
<circle cx="-44" cy="-36" r="40" fill="#101f0d"/>
<circle cx="44" cy="-40" r="38" fill="#101f0d"/>
<circle cx="48" cy="36" r="40" fill="#101f0d"/>
<circle cx="-44" cy="40" r="38" fill="#101f0d"/>
<circle cx="-22" cy="-24" r="46" fill="#152b15"/>
<circle cx="30" cy="-30" r="24" fill="#152b15"/>
<circle cx="34" cy="26" r="26" fill="#152b15"/>
<circle cx="-36" cy="30" r="22" fill="#152b15"/>
<circle cx="-30" cy="-32" r="22" fill="#1b371b"/>
<circle cx="24" cy="-34" r="10" fill="#1b371b"/>
"""

const SVG_SPLAT_0 := """<g fill="#ffffff">
<circle cx="0" cy="0" r="17"/><circle cx="13" cy="-7" r="11"/><circle cx="-12" cy="9" r="12"/>
<circle cx="5" cy="15" r="9"/><circle cx="-10" cy="-13" r="9"/><circle cx="27" cy="-14" r="4"/>
<circle cx="-26" cy="18" r="3.4"/><circle cx="18" cy="26" r="3"/><circle cx="-22" cy="-24" r="2.6"/>
<circle cx="31" cy="6" r="2.2"/></g>"""

const SVG_SPLAT_1 := """<g fill="#ffffff">
<ellipse cx="0" cy="0" rx="24" ry="11"/><circle cx="-18" cy="3" r="10"/><circle cx="16" cy="-4" r="9"/>
<ellipse cx="28" cy="-6" rx="6" ry="3.4"/><circle cx="-30" cy="8" r="3.4"/><circle cx="8" cy="14" r="5"/>
<circle cx="-6" cy="-14" r="4.4"/><circle cx="33" cy="4" r="2"/></g>"""

const SVG_SPLAT_2 := """<g fill="#ffffff">
<circle cx="0" cy="0" r="12"/><circle cx="14" cy="10" r="7"/><circle cx="-13" cy="-9" r="8"/>
<circle cx="-16" cy="12" r="5"/><circle cx="15" cy="-14" r="5.4"/><circle cx="26" cy="0" r="3"/>
<circle cx="-27" cy="-2" r="3.2"/><circle cx="2" cy="25" r="3.4"/><circle cx="-4" cy="-26" r="2.8"/>
<circle cx="24" cy="22" r="2"/><circle cx="-24" cy="-22" r="2.2"/></g>"""

const SVG_MUZZLE_FLASH := """
<path d="M31,0 L8,4 L16,15 L4,8 L0,22 L-4,8 L-13,12 L-8,4 L-18,0 L-8,-4 L-13,-12 L-4,-8 L0,-22 L4,-8 L16,-15 L8,-4 Z" fill="#ffffff"/>
<circle r="9" fill="#ffffff"/>
"""

const SVG_GLOW := """
<defs><radialGradient id="g" cx="0" cy="0" r="32" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#ffffff" stop-opacity="1"/>
<stop offset="0.35" stop-color="#ffffff" stop-opacity="0.5"/>
<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</radialGradient></defs>
<circle r="32" fill="url(#g)"/>
"""
