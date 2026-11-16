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

const HERO_PX := 3.0   # ...and the hero's pieces at 3x: he is on screen all the time, often enlarged

var tex: Dictionary = {}     # name -> Texture2D
var sizes: Dictionary = {}   # name -> Vector2 (size in game pixels)
var origins: Dictionary = {} # name -> Vector2: where the drawing's own (0, 0) is inside the picture (the hero's pieces)
var _images: Dictionary = {} # name -> Image (kept only while building)

const SHAMBLER_VARIANTS := 4
const RUNNER_VARIANTS := 2
const BRUTE_VARIANTS := 2

const GOBBER_VARIANTS := 2
const CHUCKER_VARIANTS := 2
const GASBAG_VARIANTS := 2
const LUNGER_VARIANTS := 2
const FIGHTER_VARIANTS := 1
const BOSS_VARIANTS := 5        # one look per map: boss_0 is the first map's gang leader, boss_1 the second's...

# Indexed by enemy kind (see Config).
const ENEMY_SPRITE := ["shambler", "runner", "brute", "boss", "gobber", "chucker", "gasbag", "lunger", "fighter"]
const ENEMY_VARIANTS := [SHAMBLER_VARIANTS, RUNNER_VARIANTS, BRUTE_VARIANTS, BOSS_VARIANTS,
	GOBBER_VARIANTS, CHUCKER_VARIANTS, GASBAG_VARIANTS, LUNGER_VARIANTS, FIGHTER_VARIANTS]


## The movements a character can have as picture strips (see _load_anims).
const ANIM_NAMES := ["walk", "idle", "attack", "hit", "death"]
const NO_ANIMS := {}

## sprite -> {"walk": [frames], "walk_hurt": [frames], "idle": ...}: only for sprites that
## have strips. A frame is a Texture2D like any other picture.
var anims: Dictionary = {}


## A piece of gear's own picture, for the pieces that have one: item id -> Texture2D
## (assets/sprites/gear_item_<id>.png, and the small gear_drop_<id>.png for the lid of
## a gear case; made by tools/make_gear_pictures.py from the owner's pictures).
var _gear_pictures: Dictionary = {}
var _gear_drops: Dictionary = {}


func _ready() -> void:
	_build()
	_build_anims()
	for item: String in Config.GEAR_ITEMS.keys():
		var big := "res://assets/sprites/gear_item_%s.png" % item
		var small := "res://assets/sprites/gear_drop_%s.png" % item
		if ResourceLoader.exists(big):
			_gear_pictures[item] = load(big)
			_gear_drops[item] = load(small) if ResourceLoader.exists(small) else _gear_pictures[item]
	_images.clear()
	# The hero is redrawn whenever he puts something on or takes it off.
	SaveData.gear_changed.connect(refresh_hero)


## Texture by name.
func t(sprite: String) -> Texture2D:
	return tex[sprite]


## Size of a sprite in game pixels.
func size_of(sprite: String) -> Vector2:
	return sizes[sprite]


func enemy_tex(kind: int, variant: int) -> Texture2D:
	return tex["%s_%d" % [ENEMY_SPRITE[kind], variant]]


## The badly-hurt look of a zombie (same outline, with wounds drawn over it).
func enemy_hurt_tex(kind: int, variant: int) -> Texture2D:
	return tex["%s_%d_hurt" % [ENEMY_SPRITE[kind], variant]]


## The all-white picture shown for a moment when it is hit. Looks of a kind that share
## one outline share one; the bosses, who do not, have one each.
func enemy_flash_tex(kind: int, variant: int = 0) -> Texture2D:
	var own := "%s_%d_flash" % [ENEMY_SPRITE[kind], variant]
	return tex[own] if tex.has(own) else tex["%s_0_flash" % ENEMY_SPRITE[kind]]


## A piece of gear's own picture, or null if it has none yet (it then shows the symbol
## of its kind, "gear_<type>"). `small` = the little one for a gear case on the ground.
func gear_picture(item: String, small: bool = false) -> Texture2D:
	return (_gear_drops if small else _gear_pictures).get(item)


## Where a drawing's own (0, 0) is inside its picture, in game pixels from the picture's
## top left corner (the hero's pieces: a joint, the middle of his head...).
func origin_of(sprite: String) -> Vector2:
	return origins[sprite]


## The animations of a sprite ({} = it is one still picture).
func anim_of(sprite: String) -> Dictionary:
	return anims.get(sprite, NO_ANIMS)


func enemy_anim(kind: int, variant: int) -> Dictionary:
	return anims.get("%s_%d" % [ENEMY_SPRITE[kind], variant], NO_ANIMS)


## The frame to show of one movement (a list of frames): `at` says how far through it,
## 0..1. A movement that goes round and round (walking) may be given any number.
func frame_at(frames: Array, at: float) -> Texture2D:
	var count := frames.size()
	return frames[clampi(int(fposmod(at, 1.0) * count), 0, count - 1)]


## Draw a sprite centred on `pos` in the canvas item `ci`.
func draw(ci: CanvasItem, sprite: String, pos: Vector2, scale: float = 1.0, color: Color = Color.WHITE) -> void:
	var s: Vector2 = sizes[sprite] * scale
	ci.draw_texture_rect(tex[sprite], Rect2(pos - s * 0.5, s), false, color)


# ----------------------------------------------------------------------------
#  Animations
#
#  A strip is a PNG with the frames of one movement side by side, each frame a
#  square as tall as the strip:  assets/sprites/<sprite>_walk.png  (and _idle,
#  _attack, _hit, _death), plus <sprite>_walk_hurt.png ... for the wounded
#  look. tools/make_sprite.py cuts them out of the sheets the owner sends.
#  A character without strips stays one still picture.
# ----------------------------------------------------------------------------
func _build_anims() -> void:
	for kind in ENEMY_SPRITE.size():
		var first := "%s_0" % ENEMY_SPRITE[kind]
		for variant in ENEMY_VARIANTS[kind]:
			var sprite := "%s_%d" % [ENEMY_SPRITE[kind], variant]
			_load_anims(sprite)
			# (A look without a picture of its own moves like the first look, whose picture it uses.)
			if not anims.has(sprite) and anims.has(first) and not ResourceLoader.exists("res://assets/sprites/%s.png" % sprite):
				anims[sprite] = anims[first]


func _load_anims(sprite: String) -> void:
	var found := {}
	for anim: String in ANIM_NAMES:
		var path := "res://assets/sprites/%s_%s.png" % [sprite, anim]
		if not ResourceLoader.exists(path):
			continue
		found[anim] = _frames(load(path))
		var hurt_path := "res://assets/sprites/%s_%s_hurt.png" % [sprite, anim]
		found[anim + "_hurt"] = _frames(load(hurt_path)) if ResourceLoader.exists(hurt_path) else found[anim]
	if not found.is_empty():
		anims[sprite] = found


func _frames(strip: Texture2D) -> Array:
	var side := strip.get_height()
	var list: Array = []
	for i in maxi(int(strip.get_width() / float(side)), 1):
		var frame := AtlasTexture.new()
		frame.atlas = strip
		frame.region = Rect2(i * side, 0, side, side)
		list.append(frame)
	return list


# ----------------------------------------------------------------------------
#  Building
# ----------------------------------------------------------------------------
func _build() -> void:
	# --- zombies (all drawn facing right) ---
	var shirts := ["#5b6f8c", "#8a5550", "#7d7a55", "#5a6d62"]
	var skins := ["#8fb56a", "#86a95f", "#9bbd74", "#7fa262"]
	for i in SHAMBLER_VARIANTS:
		var shambler := SVG_SHAMBLER.format({
			"line": "#1a2114", "skin": skins[i], "shirt": shirts[i], "blood": "#7a1f1f",
			"hair": "#34422a", "eye": "#ff3b30"})
		_svg("shambler_%d" % i, 56, 56, shambler)
		_svg("shambler_%d_hurt" % i, 56, 56, shambler + WOUNDS_SHAMBLER)
	_flash("shambler_0")

	var runner_shirts := ["#6b4a3a", "#4f4a6b"]
	for i in RUNNER_VARIANTS:
		var runner := SVG_RUNNER.format({
			"line": "#231a0c", "skin": "#e0b040", "shirt": runner_shirts[i],
			"hair": "#7a3b1c", "eye": "#ffffff"})
		_svg("runner_%d" % i, 48, 48, runner)
		_svg("runner_%d_hurt" % i, 48, 48, runner + WOUNDS_RUNNER)
	_flash("runner_0")

	var brute_shirts := ["#4a3d5c", "#5c3d46"]
	for i in BRUTE_VARIANTS:
		var brute := SVG_BRUTE.format({
			"line": "#17111f", "skin": "#8d6fa8", "skin2": "#73578c", "shirt": brute_shirts[i],
			"bone": "#d9d2bd", "hair": "#3b2a4d", "eye": "#ffe14a"})
		_svg("brute_%d" % i, 92, 92, brute)
		_svg("brute_%d_hurt" % i, 92, 92, brute + WOUNDS_BRUTE)
	_flash("brute_0")

	var boss := SVG_BOSS.format({
		"line": "#1c0a0a", "skin": "#8e2f2f", "skin2": "#6e2222", "skin3": "#a53c36",
		"bone": "#e6dcc0", "eye": "#ffd23f"})
	for i in BOSS_VARIANTS:
		_svg("boss_%d" % i, 176, 176, boss)
		_svg("boss_%d_hurt" % i, 176, 176, boss + WOUNDS_BOSS)
		_flash("boss_%d" % i)

	# The Gobber: sickly yellow, cheeks full of spit.
	var gobber_shirts := ["#5a4a6b", "#6b5a3a"]
	for i in GOBBER_VARIANTS:
		var gobber := SVG_GOBBER.format({
			"line": "#1d2110", "skin": "#b9c552", "sac": "#dff06e", "shirt": gobber_shirts[i],
			"hair": "#4a4f22", "eye": "#fbffd0", "mouth": "#2a3310"})
		_svg("gobber_%d" % i, 56, 56, gobber)
		_svg("gobber_%d_hurt" % i, 56, 56, gobber + WOUNDS_GOBBER)
	_flash("gobber_0")

	# The Chucker: a dusty hulk with a lump of rubble in its fist.
	var chucker_shirts := ["#4d5a3f", "#5a4a3a"]
	for i in CHUCKER_VARIANTS:
		var chucker := SVG_CHUCKER.format({
			"line": "#1c1a16", "skin": "#a39883", "skin2": "#857a67", "shirt": chucker_shirts[i],
			"rock": "#8d929b", "rock2": "#6f747d", "eye": "#ffb84a"})
		_svg("chucker_%d" % i, 84, 84, chucker)
		_svg("chucker_%d_hurt" % i, 84, 84, chucker + WOUNDS_CHUCKER)
	_flash("chucker_0")
	_svg("rubble", 30, 30, SVG_RUBBLE)

	# The Gasbag: stretched tight and about to go.
	var gasbag_bellies := ["#c9d47a", "#d4c97a"]
	for i in GASBAG_VARIANTS:
		var gasbag := SVG_GASBAG.format({
			"line": "#22240f", "belly": gasbag_bellies[i], "belly2": "#e6ee9f", "vein": "#7d8a35",
			"skin": "#a9b85f", "boil": "#f2e36b", "eye": "#ff7a3b"})
		_svg("gasbag_%d" % i, 76, 76, gasbag)
		_svg("gasbag_%d_hurt" % i, 76, 76, gasbag + WOUNDS_GASBAG)
	_flash("gasbag_0")

	# The Lunger: thin, cold-skinned, all claws.
	var lunger_skins := ["#5f7f8f", "#6a7590"]
	for i in LUNGER_VARIANTS:
		var lunger := SVG_LUNGER.format({
			"line": "#0f171c", "skin": lunger_skins[i], "skin2": "#465f6c", "bone": "#e6dcc0", "eye": "#ff4a3b"})
		_svg("lunger_%d" % i, 56, 56, lunger)
		_svg("lunger_%d_hurt" % i, 56, 56, lunger + WOUNDS_LUNGER)
	_flash("lunger_0")

	# The Gang Fighter has a painted picture (assets/sprites/fighter_0.png). Without it:
	# a Shambler's shape with a red headcloth and a blade.
	var fighter := SVG_SHAMBLER.format({
		"line": "#1c1410", "skin": "#7f8f5c", "shirt": "#cfc4ad", "blood": "#7a1f1f",
		"hair": "#b3322b", "eye": "#ffe14a"}) + SVG_FIGHTER_BLADE
	_svg("fighter_0", 56, 56, fighter)
	_svg("fighter_0_hurt", 56, 56, fighter + WOUNDS_SHAMBLER)
	_flash("fighter_0")

	# --- player and weapons ---
	_svg_at("hero_shadow", Vector2(56, 44), Vector2(29, 22), HeroArt.top_shadow(), PX)
	refresh_hero()
	_svg("gun_pistol", 24, 12, SVG_GUN_PISTOL, false)
	_svg("gun_shotgun", 42, 14, SVG_GUN_SHOTGUN, false)
	_svg("gun_machinegun", 46, 18, SVG_GUN_MACHINEGUN, false)
	_svg("gun_launcher", 44, 20, SVG_GUN_LAUNCHER, false)
	_svg("gun_smg", 36, 16, SVG_GUN_SMG, false)
	_svg("gun_rifle", 58, 14, SVG_GUN_RIFLE, false)
	_svg("gun_flamethrower", 48, 22, SVG_GUN_FLAMETHROWER, false)
	_svg("gun_chainsaw", 54, 22, SVG_GUN_CHAINSAW, false)
	_svg("grenade", 16, 16, SVG_GRENADE)
	# Pets (52x32, facing right), drawn from the colours in Config.PETS.
	for pet_id: String in Config.PET_ORDER:
		_svg("pet_" + pet_id, 52, 32, _pet_svg(Config.PETS[pet_id]["look"]))

	# --- detailed weapon pictures (side view) for the HUD and the Armory ---
	# 220x80 each. To replace one with real art: assets/sprites/icon_<weapon>.png at 440x160.
	_svg("icon_pistol", 220, 80, ICON_DEFS + ICON_PISTOL, false)
	_svg("icon_smg", 220, 80, ICON_DEFS + ICON_SMG, false)
	_svg("icon_shotgun", 220, 80, ICON_DEFS + ICON_SHOTGUN, false)
	_svg("icon_machinegun", 220, 80, ICON_DEFS + ICON_MACHINEGUN, false)
	_svg("icon_rifle", 220, 80, ICON_DEFS + ICON_RIFLE, false)
	_svg("icon_launcher", 220, 80, ICON_DEFS + ICON_LAUNCHER, false)
	_svg("icon_flamethrower", 220, 80, ICON_DEFS + ICON_FLAMETHROWER, false)
	_svg("icon_chainsaw", 220, 80, ICON_DEFS + ICON_CHAINSAW, false)

	# --- pickups ---
	_svg("coin", 18, 18, SVG_COIN)
	_svg("crate", 38, 38, SVG_CRATE)
	_flash("crate")
	_svg("medkit", 28, 28, SVG_MEDKIT)
	_svg("gear_crate", 38, 38, SVG_GEAR_CRATE)
	_svg("gear_crate_band", 38, 38, SVG_GEAR_CRATE_BAND)
	_svg("chest", 60, 60, SVG_CHEST)
	_svg("chest_open", 60, 60, SVG_CHEST_OPEN)

	# --- scenery ---
	_svg("rock", 120, 120, SVG_ROCK)
	_svg("stump", 120, 120, SVG_STUMP)
	_svg("canopy", 220, 220, SVG_CANOPY)
	# The pond's reeds, lily pads, stones and fish, and the details painted on the ground.
	_svg("pond_reeds", 32, 32, SceneryArt.reeds())
	_svg("pond_lily", 22, 22, SceneryArt.lily())
	_svg("pond_flower", 12, 12, SceneryArt.lily_flower())
	_svg("pond_stone", 18, 16, SceneryArt.stone())
	_svg("pond_fish", 22, 12, SceneryArt.fish())
	for i in 3:
		_svg("detail_grass_%d" % i, 24, 24, SceneryArt.grass(40 + i))
	_svg("detail_fern", 30, 30, SceneryArt.fern())
	_svg("detail_leaves", 28, 24, SceneryArt.leaves())
	_svg("detail_stones", 28, 22, SceneryArt.stones())
	_svg("detail_flowers_red", 22, 22, SceneryArt.flowers(61, "#c8322b", "#f3d27a"))
	_svg("detail_flowers_yellow", 22, 22, SceneryArt.flowers(62, "#e2b83a", "#8a5a1a"))
	_svg("detail_twig", 40, 16, SceneryArt.twig())
	_svg("detail_mushrooms", 18, 16, SceneryArt.mushrooms())
	_svg("detail_bones", 28, 20, SceneryArt.bones())
	_svg("detail_puddle", 44, 30, SceneryArt.puddle())
	# Scenery: bushes, heaps of rubble, the tires that burn.
	_svg("decor_bush_0", 80, 68, SceneryArt.bush(101, 36.0, 30.0, ""))
	_svg("decor_bush_1", 64, 58, SceneryArt.bush(102, 28.0, 25.0, "#c8322b"))
	_svg("decor_bush_2", 96, 66, SceneryArt.bush(103, 44.0, 29.0, ""))
	_svg("decor_rubble_0", 96, 72, SceneryArt.rubble(201))
	_svg("decor_rubble_1", 96, 72, SceneryArt.rubble(202))
	_svg("decor_tire", 40, 40, SceneryArt.tire())
	_svg("decor_tires", 60, 52, SceneryArt.tires())

	# --- effects (white, tinted when drawn) ---
	_svg("splat_0", 72, 72, SVG_SPLAT_0)
	_svg("splat_1", 72, 72, SVG_SPLAT_1)
	_svg("splat_2", 72, 72, SVG_SPLAT_2)
	_svg("flash", 64, 64, SVG_MUZZLE_FLASH)
	_svg("dot", 32, 32, "<circle r=\"15\" fill=\"#ffffff\"/>")
	_svg("glow", 64, 64, SVG_GLOW)
	_svg("ring", 128, 128, "<circle r=\"58\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"5\"/>")

	# --- upgrade trees: node shapes and small symbols (white, tinted when drawn) ---
	_svg("node_fill", 64, 64, "<circle r=\"29\" fill=\"#ffffff\"/>")
	_svg("node_ring", 64, 64, "<circle r=\"27\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"6\"/>")
	_svg("node_diamond", 64, 64, "<path d=\"M0 -30 L30 0 L0 30 L-30 0Z\" fill=\"#ffffff\"/>")
	_svg("node_diamond_ring", 64, 64, "<path d=\"M0 -27 L27 0 L0 27 L-27 0Z\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"6\" stroke-linejoin=\"round\"/>")
	_svg("node_hex", 64, 64, "<path d=\"M-15 -26 L15 -26 L30 0 L15 26 L-15 26 L-30 0Z\" fill=\"#ffffff\"/>")
	_svg("node_hex_ring", 64, 64, "<path d=\"M-13.5 -23.5 L13.5 -23.5 L27 0 L13.5 23.5 L-13.5 23.5 L-27 0Z\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"6\" stroke-linejoin=\"round\"/>")
	for symbol: String in SYMBOLS.keys():
		_svg(symbol, 40, 40, SYMBOLS[symbol])

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


## A four-legged pet seen from above, built from a "look" (see Config.PETS):
## colours, the kind of tail and ears, how stocky it is, and whether embers
## glow along its back.
func _pet_svg(look: Dictionary) -> String:
	var dark := "#1c1712"
	var body := String(look["body"])
	var head := String(look["head"])
	var patch := String(look["patch"])
	var ear := String(look["ear"])
	var collar := String(look["collar"])
	var eye := String(look["eye"])
	var ry := 7.4 * float(look["girth"])
	var out := "<ellipse cx=\"0\" cy=\"0\" rx=\"22\" ry=\"%s\" fill=\"#000000\" fill-opacity=\"0.22\"/>" % str(ry + 4.0)
	# Tail.
	var tails := {"curl": ["M-13,0 Q-20,-2 -21,-8", 4.6], "long": ["M-13,0 Q-22,4 -25,-4", 3.2],
			"stub": ["M-13,0 L-17,-1.5", 4.6], "bushy": ["M-13,0 Q-21,-1 -25,-6", 6.4]}
	var tail: Array = tails[String(look["tail"])]
	out += "<path d=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\" fill=\"none\"/>" % [tail[0], dark, str(float(tail[1]) + 2.4)]
	out += "<path d=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\" fill=\"none\"/>" % [tail[0], body, str(tail[1])]
	# Legs, then the body over them.
	for x: float in [-8.0, 6.5]:
		for side: float in [-1.0, 1.0]:
			out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"3.5\" ry=\"2.9\" fill=\"%s\"/>" % [str(x), str(side * (ry - 0.4)), dark]
			out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"2.3\" ry=\"1.8\" fill=\"%s\"/>" % [str(x), str(side * (ry - 0.4)), body]
	out += "<ellipse cx=\"-2\" cy=\"0\" rx=\"12.6\" ry=\"%s\" fill=\"%s\"/>" % [str(ry + 1.4), dark]
	out += "<ellipse cx=\"-2\" cy=\"0\" rx=\"11.2\" ry=\"%s\" fill=\"%s\"/>" % [str(ry), body]
	if patch != "":
		out += "<ellipse cx=\"-6\" cy=\"-1.4\" rx=\"4.2\" ry=\"%s\" fill=\"%s\"/>" % [str(ry * 0.42), patch]
	if bool(look["ember"]):
		out += "<path d=\"M-10,-3 L-7,2.5 M-4,-4 L-1.5,3 M2,-3.5 L3.5,2.5\" stroke=\"#ff7a1a\" stroke-width=\"1.7\" stroke-linecap=\"round\" fill=\"none\"/>"
		out += "<path d=\"M-10,-3 L-7,2.5 M-4,-4 L-1.5,3 M2,-3.5 L3.5,2.5\" stroke=\"#ffd27a\" stroke-width=\"0.6\" stroke-linecap=\"round\" fill=\"none\"/>"
	if collar != "":
		out += "<rect x=\"5.2\" y=\"%s\" width=\"3\" height=\"%s\" rx=\"1.2\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.8\"/>" % [
				str(-(ry - 0.8)), str(2.0 * (ry - 0.8)), collar, dark]
	# Head, ears, snout, eyes.
	out += "<circle cx=\"11\" cy=\"0\" r=\"6.9\" fill=\"%s\"/><circle cx=\"11\" cy=\"0\" r=\"5.6\" fill=\"%s\"/>" % [dark, head]
	for side: float in [-1.0, 1.0]:
		if String(look["ears"]) == "point":
			out += "<path d=\"M8.6,%s L7,%s L13,%s Z\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1\" stroke-linejoin=\"round\"/>" % [
					str(side * 3.8), str(side * 11.4), str(side * 5.8), ear, dark]
		else:
			out += "<path d=\"M8,%s L4.6,%s L11.6,%s Z\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1\" stroke-linejoin=\"round\"/>" % [
					str(side * 4.4), str(side * 9.6), str(side * 6.8), ear, dark]
	out += "<ellipse cx=\"16.6\" cy=\"0\" rx=\"3.7\" ry=\"3\" fill=\"%s\"/>" % dark
	out += "<ellipse cx=\"16.4\" cy=\"0\" rx=\"2.6\" ry=\"2\" fill=\"%s\"/>" % (patch if patch != "" else head)
	out += "<circle cx=\"18.8\" cy=\"0\" r=\"1.25\" fill=\"%s\"/>" % dark
	for side: float in [-1.0, 1.0]:
		out += "<circle cx=\"13.6\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [str(side * 2.5), "1.4" if bool(look["ember"]) else "1.0", eye]
	return out


# ----------------------------------------------------------------------------
#  The hero. He is a puppet drawn by HeroArt from Config.HERO_LOOK plus
#  whatever gear he is wearing (each piece's "look" in Config.GEAR_ITEMS):
#  seen from above he is a handful of pieces that HeroRig puts together in the
#  game ("player_body", "player_head", "player_arm_l", "player_arm_r",
#  "player_fore", "player_leg", "player_boot", with wounded and hit-flash
#  versions); in the menus he is one picture from the front ("hero_front").
# ----------------------------------------------------------------------------
## Redraw the hero from the gear worn right now.
func refresh_hero() -> void:
	var worn: Dictionary = SaveData.gear_worn
	_build_hero("player", worn)
	build_front(worn, "hero_front")


## The hero from the front (the menus' picture) in the gear `worn`, as the picture `sprite`.
func build_front(worn: Dictionary, sprite: String) -> void:
	var looks := {}
	for slot: String in Config.GEAR_SLOTS:
		looks[slot] = _worn_look(worn, slot)
	_svg_at(sprite, Vector2(260, 400), Vector2(130, 200), HeroArt.front(Config.HERO_LOOK, looks), HERO_PX)
	_images.erase(sprite)


## Another co-op player seen from above, wearing their own gear. `sprite` is
## the name their pieces get: "mate1" makes "mate1_body", "mate1_head"...
func build_mate(worn: Dictionary, sprite: String) -> void:
	_build_hero(sprite, worn)


## What the hero's pieces look like for the gear in `worn`:
## piece -> [the drawing, its size, where its own (0, 0) is inside it].
func hero_pieces(worn: Dictionary) -> Dictionary:
	var h: Dictionary = Config.HERO_LOOK
	var helmet := _worn_look(worn, "helmet")
	var chest := _worn_look(worn, "chest")
	var gloves := _worn_look(worn, "gloves")
	var belt := _worn_look(worn, "belt")
	var pants := _worn_look(worn, "pants")
	var boots := _worn_look(worn, "boots")
	return {
		"body": [HeroArt.top_body(h, chest, belt, false), Vector2(40, 42), Vector2(27, 21)],
		"body_hurt": [HeroArt.top_body(h, chest, belt, true), Vector2(40, 42), Vector2(27, 21)],
		"head": [HeroArt.top_head(h, helmet, false), Vector2(26, 22), Vector2(11, 11)],
		"head_hurt": [HeroArt.top_head(h, helmet, true), Vector2(26, 22), Vector2(11, 11)],
		"arm_l": [HeroArt.top_arm_upper(h, chest, true), Vector2(28, 14), Vector2(7, 7)],
		"arm_r": [HeroArt.top_arm_upper(h, chest, false), Vector2(28, 14), Vector2(7, 7)],
		"fore": [HeroArt.top_arm_fore(h, chest, gloves), Vector2(28, 12), Vector2(6, 6)],
		"leg": [HeroArt.top_leg(h, pants), Vector2(16, 10), Vector2(13, 5)],
		"boot": [HeroArt.top_boot(h, boots), Vector2(14, 10), Vector2(5, 5)],
	}


func _build_hero(prefix: String, worn: Dictionary) -> void:
	var pieces := hero_pieces(worn)
	for piece: String in pieces:
		var made: Array = pieces[piece]
		var sprite := "%s_%s" % [prefix, piece]
		_svg_at(sprite, made[1], made[2], made[0], HERO_PX)
		if not piece.ends_with("_hurt"):
			_flash(sprite)
			origins[sprite + "_flash"] = made[2]
		_images.erase(sprite)


## The "look" of the piece worn in a slot ({} = nothing there).
func _worn_look(worn: Dictionary, slot: String) -> Dictionary:
	var key := String(worn.get(slot, ""))
	if key == "":
		return {}
	var item := Config.gear_item_of(key)
	if not Config.GEAR_ITEMS.has(item):
		return {}
	return Config.GEAR_ITEMS[item]["look"]


## Rasterise an SVG drawing into a texture. `centered` puts (0,0) in the middle
## of the sprite; otherwise (0,0) is the middle of the LEFT edge (used for guns,
## so they rotate around the grip).
## The painted picture for a sprite, if there is one: assets/sprites/<sprite>.png. A kind
## with several looks (shambler_0 .. shambler_3) and only ONE painted picture uses that
## one for all of them: "brute_1" takes brute_0.png, "brute_1_hurt" takes brute_0_hurt.png.
func _painted(sprite: String) -> String:
	var path := "res://assets/sprites/%s.png" % sprite
	if ResourceLoader.exists(path):
		return path
	var tail := "_hurt" if sprite.ends_with("_hurt") else ""
	var core := sprite.trim_suffix("_hurt")
	var cut := core.rfind("_")
	if cut > 0 and core.substr(cut + 1).is_valid_int() and core.substr(cut + 1) != "0":
		path = "res://assets/sprites/%s_0%s.png" % [core.substr(0, cut), tail]
		if ResourceLoader.exists(path):
			return path
	return ""


func _svg(sprite: String, w: int, h: int, body: String, centered: bool = true) -> void:
	var override_path := _painted(sprite)
	if override_path != "":
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


## The same for a drawing whose own (0, 0) is somewhere inside it: `origin` says where,
## in game pixels from the picture's top left corner. `px` = how sharp it is made.
func _svg_at(sprite: String, size: Vector2, origin: Vector2, body: String, px: float) -> void:
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"%s %s %d %d\">%s</svg>" % [
		int(size.x), int(size.y), str(-origin.x), str(-origin.y), int(size.x), int(size.y), body]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, px)
	if err != OK or img.is_empty():
		push_error("Art: could not build sprite '%s'" % sprite)
		img = Image.create(int(size.x * px), int(size.y * px), false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	tex[sprite] = ImageTexture.create_from_image(img)
	sizes[sprite] = size
	origins[sprite] = origin
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
const SVG_FIGHTER_BLADE := """
<path d="M15,9 L28,5" stroke="#1c1410" stroke-width="5" stroke-linecap="round" fill="none"/>
<path d="M16,9 L27,5.5" stroke="#b9bcc0" stroke-width="2.6" stroke-linecap="round" fill="none"/>
"""

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

const SVG_GOBBER := """
<circle cx="0" cy="0" r="19" fill="#000000" fill-opacity="0.22"/>
<path d="M-2,-10 L-13,-15" stroke="{line}" stroke-width="8.4" stroke-linecap="round" fill="none"/>
<path d="M-2,10 L-13,15" stroke="{line}" stroke-width="8.4" stroke-linecap="round" fill="none"/>
<path d="M-2,-10 L-13,-15" stroke="{skin}" stroke-width="5" stroke-linecap="round" fill="none"/>
<path d="M-2,10 L-13,15" stroke="{skin}" stroke-width="5" stroke-linecap="round" fill="none"/>
<ellipse cx="-3" cy="0" rx="10.4" ry="13.4" fill="{line}"/>
<ellipse cx="-3" cy="0" rx="8.9" ry="11.9" fill="{shirt}"/>
<path d="M-9,4 L-4,7 L-8,11 Z" fill="{sac}" fill-opacity="0.7"/>
<circle cx="5" cy="0" r="8.6" fill="{line}"/>
<circle cx="5" cy="0" r="7.1" fill="{skin}"/>
<circle cx="8.6" cy="-6.6" r="4.8" fill="{line}"/>
<circle cx="8.6" cy="6.6" r="4.8" fill="{line}"/>
<circle cx="8.6" cy="-6.6" r="3.6" fill="{sac}"/>
<circle cx="8.6" cy="6.6" r="3.6" fill="{sac}"/>
<circle cx="7.6" cy="-7.6" r="1.1" fill="#ffffff" fill-opacity="0.8"/>
<circle cx="7.6" cy="5.6" r="1.1" fill="#ffffff" fill-opacity="0.8"/>
<ellipse cx="11.4" cy="0" rx="2.9" ry="3.7" fill="{line}"/>
<ellipse cx="11.2" cy="0" rx="1.9" ry="2.7" fill="{mouth}"/>
<circle cx="14.4" cy="1.8" r="1.5" fill="{sac}" stroke="{line}" stroke-width="0.6"/>
<circle cx="6.4" cy="-2.6" r="1.5" fill="{eye}"/>
<circle cx="6.4" cy="2.6" r="1.5" fill="{eye}"/>
<path d="M-1.5,-4 Q-4.6,0 -1.5,4 Q1,0 -1.5,-4 Z" fill="{hair}"/>
"""

const SVG_CHUCKER := """
<circle cx="0" cy="0" r="30" fill="#000000" fill-opacity="0.24"/>
<circle cx="-17" cy="-8" r="6.4" fill="{rock2}" stroke="{line}" stroke-width="1.5"/>
<circle cx="-19" cy="5" r="7.4" fill="{rock}" stroke="{line}" stroke-width="1.5"/>
<circle cx="-13" cy="13" r="5.2" fill="{rock2}" stroke="{line}" stroke-width="1.5"/>
<path d="M0,-17 L15,-20" stroke="{line}" stroke-width="13" stroke-linecap="round" fill="none"/>
<path d="M0,-17 L15,-20" stroke="{skin}" stroke-width="9.4" stroke-linecap="round" fill="none"/>
<circle cx="18" cy="-20.5" r="6" fill="{skin2}" stroke="{line}" stroke-width="1.5"/>
<path d="M0,17 L19,16" stroke="{line}" stroke-width="16" stroke-linecap="round" fill="none"/>
<path d="M0,17 L19,16" stroke="{skin}" stroke-width="12.2" stroke-linecap="round" fill="none"/>
<path d="M21,6 L30,7 L35,14 L32,23 L23,25 L18,18 Z" fill="{rock}" stroke="{line}" stroke-width="1.8" stroke-linejoin="round"/>
<path d="M21,6 L27,14 L35,14 M27,14 L23,25" stroke="{rock2}" stroke-width="1.4" fill="none"/>
<ellipse cx="-3" cy="0" rx="16.6" ry="21.6" fill="{line}"/>
<ellipse cx="-3" cy="0" rx="14.9" ry="19.9" fill="{shirt}"/>
<path d="M-12,-15 L2,-10 M-12,15 L2,10" stroke="{line}" stroke-width="3" stroke-linecap="round"/>
<path d="M-15,-2 L-9,3 M-13,6 L-8,9" stroke="{skin2}" stroke-width="2" stroke-linecap="round"/>
<circle cx="5" cy="0" r="10.2" fill="{line}"/>
<circle cx="5" cy="0" r="8.6" fill="{skin}"/>
<path d="M8.4,-7 L12.6,-2.4 M8.4,7 L12.6,2.4" stroke="{line}" stroke-width="1.8" stroke-linecap="round"/>
<circle cx="10.6" cy="-3.4" r="1.9" fill="{eye}"/>
<circle cx="10.6" cy="3.4" r="1.9" fill="{eye}"/>
<path d="M0,-6 Q-4,0 0,6" stroke="{skin2}" stroke-width="2.6" fill="none" stroke-linecap="round"/>
"""

# The lump a Chucker throws (also left lying where it lands).
const SVG_RUBBLE := """
<path d="M-9,-6 L-1,-12 L9,-8 L12,2 L6,11 L-5,12 L-12,4 Z" fill="#8d929b" stroke="#1c1a16" stroke-width="2" stroke-linejoin="round"/>
<path d="M-9,-6 L0,-1 L9,-8 M0,-1 L-5,12 M0,-1 L12,2" stroke="#6f747d" stroke-width="1.5" fill="none"/>
<path d="M-6,-6 L-1,-9 L4,-7" stroke="#b9bec6" stroke-width="1.4" fill="none" stroke-linecap="round"/>
"""

const SVG_GASBAG := """
<circle cx="0" cy="0" r="28" fill="#000000" fill-opacity="0.24"/>
<path d="M4,-17 L14,-21" stroke="{line}" stroke-width="8.6" stroke-linecap="round" fill="none"/>
<path d="M4,17 L14,21" stroke="{line}" stroke-width="8.6" stroke-linecap="round" fill="none"/>
<path d="M4,-17 L14,-21" stroke="{skin}" stroke-width="5.2" stroke-linecap="round" fill="none"/>
<path d="M4,17 L14,21" stroke="{skin}" stroke-width="5.2" stroke-linecap="round" fill="none"/>
<circle cx="-3" cy="0" r="21" fill="{line}"/>
<circle cx="-3" cy="0" r="19.3" fill="{belly}"/>
<ellipse cx="-9" cy="-7" rx="8" ry="6" fill="{belly2}" fill-opacity="0.75"/>
<path d="M-20,2 Q-12,6 -8,0 Q-4,-6 4,-8 M-14,14 Q-8,8 -2,12 Q4,14 10,8 M-6,-18 Q-2,-12 6,-14" stroke="{vein}" stroke-width="1.5" fill="none" stroke-linecap="round"/>
<circle cx="-12" cy="9" r="3.2" fill="{boil}" stroke="{line}" stroke-width="0.9"/>
<circle cx="2" cy="-12" r="2.6" fill="{boil}" stroke="{line}" stroke-width="0.9"/>
<circle cx="-1" cy="5" r="2.1" fill="{boil}" stroke="{line}" stroke-width="0.9"/>
<circle cx="-16" cy="-6" r="1.9" fill="{boil}" stroke="{line}" stroke-width="0.9"/>
<circle cx="8" cy="9" r="1.8" fill="{boil}" stroke="{line}" stroke-width="0.9"/>
<circle cx="15" cy="0" r="7.4" fill="{line}"/>
<circle cx="15" cy="0" r="6" fill="{skin}"/>
<circle cx="18.2" cy="-2.3" r="1.3" fill="{eye}"/>
<circle cx="18.2" cy="2.3" r="1.3" fill="{eye}"/>
"""

const SVG_LUNGER := """
<circle cx="0" cy="0" r="17" fill="#000000" fill-opacity="0.22"/>
<path d="M-5,-5 L-16,-11" stroke="{line}" stroke-width="6.6" stroke-linecap="round" fill="none"/>
<path d="M-5,5 L-16,11" stroke="{line}" stroke-width="6.6" stroke-linecap="round" fill="none"/>
<path d="M-5,-5 L-16,-11" stroke="{skin2}" stroke-width="3.6" stroke-linecap="round" fill="none"/>
<path d="M-5,5 L-16,11" stroke="{skin2}" stroke-width="3.6" stroke-linecap="round" fill="none"/>
<path d="M0,-8 L15,-11.5" stroke="{line}" stroke-width="6.8" stroke-linecap="round" fill="none"/>
<path d="M0,8 L15,11.5" stroke="{line}" stroke-width="6.8" stroke-linecap="round" fill="none"/>
<path d="M0,-8 L15,-11.5" stroke="{skin}" stroke-width="3.8" stroke-linecap="round" fill="none"/>
<path d="M0,8 L15,11.5" stroke="{skin}" stroke-width="3.8" stroke-linecap="round" fill="none"/>
<path d="M16,-14.4 L23,-13.4 L16.6,-11.2 L22.6,-9.6 L16,-8.6 Z" fill="{bone}" stroke="{line}" stroke-width="0.8" stroke-linejoin="round"/>
<path d="M16,14.4 L23,13.4 L16.6,11.2 L22.6,9.6 L16,8.6 Z" fill="{bone}" stroke="{line}" stroke-width="0.8" stroke-linejoin="round"/>
<ellipse cx="-3" cy="0" rx="10" ry="8.8" fill="{line}"/>
<ellipse cx="-3" cy="0" rx="8.5" ry="7.3" fill="{skin}"/>
<path d="M-9,0 L3,0" stroke="{skin2}" stroke-width="2.4" stroke-linecap="round"/>
<circle cx="-7" cy="0" r="1.2" fill="{bone}"/><circle cx="-3.4" cy="0" r="1.2" fill="{bone}"/><circle cx="0.2" cy="0" r="1.2" fill="{bone}"/>
<ellipse cx="7" cy="0" rx="7" ry="5.8" fill="{line}"/>
<ellipse cx="7" cy="0" rx="5.6" ry="4.4" fill="{skin}"/>
<path d="M10.6,-2.6 L13.4,-1.6 L10.8,-0.6 L13.4,0.6 L10.6,1.6 L13.2,2.6" stroke="{bone}" stroke-width="1" fill="none" stroke-linejoin="round"/>
<circle cx="8.4" cy="-2.3" r="1.4" fill="{eye}"/>
<circle cx="8.4" cy="2.3" r="1.4" fill="{eye}"/>
"""

# Wounds drawn on top of a zombie once it is badly hurt: open gashes, bare
# ribs, a lost eye, bloody hands. (To replace with real art: <name>_hurt.png.)
const WOUNDS_SHAMBLER := """
<path d="M-10,-3 L-4,2 L-7,9 L-12,5 Z" fill="#4a0a0a"/>
<path d="M-9,1 L-6,4 M-8.5,5 L-5.5,7" stroke="#e8dcc0" stroke-width="1.5" stroke-linecap="round"/>
<path d="M-3,-11 L1,-9 L-2,-6 Z" fill="#7a1010"/>
<circle cx="2" cy="4.2" r="3.4" fill="#7a1010"/>
<circle cx="7.4" cy="3" r="2.3" fill="#1a0505"/>
<path d="M7.4,3 L10,6.4" stroke="#7a1010" stroke-width="1.4" stroke-linecap="round"/>
<circle cx="16.5" cy="-8" r="3.6" fill="#7a1010"/>
<path d="M9,10 L15,9" stroke="#7a1010" stroke-width="3" stroke-linecap="round"/>
<circle cx="-13" cy="-9" r="1.4" fill="#7a1010"/><circle cx="-6" cy="14" r="1.2" fill="#7a1010"/>
"""

const WOUNDS_RUNNER := """
<path d="M-6,-4 L-1,0 L-5,6 L-8,2 Z" fill="#4a0a0a"/>
<path d="M-5.4,0.6 L-3.2,2.8" stroke="#e8dcc0" stroke-width="1.3" stroke-linecap="round"/>
<path d="M3,-3.4 L8,-1 L4,2 Z" fill="#7a1010"/>
<circle cx="5" cy="2.5" r="2" fill="#1a0505"/>
<path d="M-8,10 L-14,12" stroke="#7a1010" stroke-width="3.6" stroke-linecap="round"/>
<circle cx="-2" cy="-8" r="1.8" fill="#7a1010"/><circle cx="9.4" cy="1.4" r="1.2" fill="#7a1010"/>
"""

const WOUNDS_BRUTE := """
<path d="M-18,-8 L-6,-2 L-12,12 L-20,6 Z" fill="#3a0606"/>
<path d="M-16,-2 L-9,2 M-15,4 L-10,7 M-14,9 L-11,11" stroke="#e8dcc0" stroke-width="2" stroke-linecap="round"/>
<path d="M-2,14 L8,18 L2,24 L-6,20 Z" fill="#7a1010"/>
<path d="M0,-8 L8,-10 L6,-3 L1,-2 Z" fill="#7a1010"/>
<circle cx="11.6" cy="-4.2" r="3.1" fill="#1a0505"/>
<path d="M11.6,-4.2 L15,1" stroke="#7a1010" stroke-width="1.8" stroke-linecap="round"/>
<circle cx="27" cy="18" r="6.2" fill="#7a1010"/>
<path d="M10,-20 L22,-18" stroke="#7a1010" stroke-width="5" stroke-linecap="round"/>
<circle cx="-22" cy="-16" r="2.4" fill="#7a1010"/><circle cx="-10" cy="-22" r="1.8" fill="#7a1010"/><circle cx="-16" cy="20" r="2" fill="#7a1010"/>
"""

const WOUNDS_GOBBER := """
<path d="M-10,-4 L-4,0 L-7,8 L-12,4 Z" fill="#4a0a0a"/>
<path d="M-9,0 L-6,3 M-8.5,4 L-6,6" stroke="#e8dcc0" stroke-width="1.4" stroke-linecap="round"/>
<circle cx="8.6" cy="6.6" r="3.8" fill="#4d5a12"/>
<path d="M8.6,6.6 L12,11 M7,9 L6,13" stroke="#8ea520" stroke-width="1.6" stroke-linecap="round"/>
<circle cx="6.4" cy="-2.6" r="2" fill="#1a0505"/>
<path d="M0,-6 L4,-8 L3,-3 Z" fill="#7a1010"/>
<path d="M-8,13 L-13,15" stroke="#7a1010" stroke-width="3.6" stroke-linecap="round"/>
<circle cx="-12" cy="-8" r="1.4" fill="#7a1010"/><circle cx="-4" cy="13" r="1.2" fill="#7a1010"/>
"""

const WOUNDS_CHUCKER := """
<path d="M-15,-8 L-5,-3 L-10,10 L-17,5 Z" fill="#3a0606"/>
<path d="M-13,-3 L-8,0 M-13,3 L-8,6" stroke="#e8dcc0" stroke-width="1.9" stroke-linecap="round"/>
<path d="M0,-7 L7,-9 L6,-3 L1,-2 Z" fill="#7a1010"/>
<circle cx="10.6" cy="3.4" r="2.6" fill="#1a0505"/>
<path d="M10.6,3.4 L13.6,8" stroke="#7a1010" stroke-width="1.7" stroke-linecap="round"/>
<path d="M6,-19 L14,-20" stroke="#7a1010" stroke-width="5" stroke-linecap="round"/>
<path d="M-2,13 L7,16 L2,21 L-5,18 Z" fill="#7a1010"/>
<circle cx="-18" cy="-14" r="2.2" fill="#7a1010"/><circle cx="-8" cy="-19" r="1.7" fill="#7a1010"/><circle cx="-13" cy="18" r="1.9" fill="#7a1010"/>
"""

const WOUNDS_GASBAG := """
<path d="M-14,-10 L-6,-6 L-9,3 L-17,-1 Z" fill="#4a0a0a"/>
<path d="M-4,8 L4,11 L0,17 L-7,14 Z" fill="#4a0a0a"/>
<path d="M-12,-5 L-8,-2 M-2,11 L1,14" stroke="#b5c431" stroke-width="1.6" stroke-linecap="round"/>
<circle cx="-18" cy="-4" r="3.4" fill="#d9ec5a" fill-opacity="0.55"/>
<circle cx="-20" cy="-9" r="2.2" fill="#d9ec5a" fill-opacity="0.4"/>
<circle cx="2" cy="19" r="3" fill="#d9ec5a" fill-opacity="0.55"/>
<circle cx="18.2" cy="2.3" r="1.9" fill="#1a0505"/>
<path d="M6,-14 L12,-12 L9,-8 Z" fill="#7a1010"/>
<circle cx="-10" cy="16" r="1.6" fill="#7a1010"/><circle cx="6" cy="-18" r="1.4" fill="#7a1010"/>
"""

const WOUNDS_LUNGER := """
<path d="M-8,-3 L-2,0 L-5,6 L-9,3 Z" fill="#4a0a0a"/>
<path d="M-7,1 L-4.4,3" stroke="#e8dcc0" stroke-width="1.3" stroke-linecap="round"/>
<path d="M3,-3 L8,-4 L6,0 Z" fill="#7a1010"/>
<circle cx="8.4" cy="2.3" r="1.9" fill="#1a0505"/>
<path d="M8,-10 L14,-11.4" stroke="#7a1010" stroke-width="3.4" stroke-linecap="round"/>
<path d="M-10,8 L-16,11" stroke="#7a1010" stroke-width="3.2" stroke-linecap="round"/>
<circle cx="-11" cy="-7" r="1.3" fill="#7a1010"/><circle cx="1" cy="7" r="1.1" fill="#7a1010"/>
"""

const WOUNDS_BOSS := """
<path d="M-40,-10 L-18,-2 L-26,26 L-44,14 Z" fill="#3a0606"/>
<path d="M-36,-2 L-24,4 M-35,6 L-24,11 M-33,14 L-26,18" stroke="#e8dcc0" stroke-width="3" stroke-linecap="round"/>
<path d="M-10,-40 L8,-34 L-2,-22 L-14,-28 Z" fill="#3a0606"/>
<path d="M-6,22 L14,30 L4,42 L-10,36 Z" fill="#5a0c0c"/>
<path d="M4,-18 L20,-22 L18,-8 L8,-6 Z" fill="#5a0c0c"/>
<circle cx="23.6" cy="-10" r="5.2" fill="#1a0505"/>
<path d="M23.6,-10 L30,0" stroke="#5a0c0c" stroke-width="3" stroke-linecap="round"/>
<path d="M-50,-8 L-78,0 L-50,8 Z" fill="#1c0a0a"/>
<path d="M-48,-5 L-56,-1 L-48,4 Z" fill="#e6dcc0"/>
<circle cx="50" cy="36" r="10.5" fill="#5a0c0c"/>
<path d="M20,-40 L40,-37" stroke="#5a0c0c" stroke-width="8" stroke-linecap="round"/>
<circle cx="-30" cy="-32" r="3" fill="#5a0c0c"/><circle cx="-20" cy="40" r="3.4" fill="#5a0c0c"/><circle cx="0" cy="-48" r="2.6" fill="#5a0c0c"/>
"""

const SVG_GUN_PISTOL := """
<rect x="3" y="-3.5" width="18.6" height="7" rx="1.8" fill="#0c0e11"/>
<rect x="4" y="-2.6" width="16.6" height="5.2" rx="1.2" fill="#6d7580"/>
<rect x="4" y="-2.6" width="16.6" height="1.9" rx="0.9" fill="#b4bdc7"/>
<rect x="11" y="-1.2" width="5" height="2.6" rx="0.6" fill="#191c20"/>
<rect x="11.6" y="-0.8" width="3.8" height="0.9" rx="0.4" fill="#f3d27a"/>
<path d="M5.6,-2.4 L5.6,2.4 M7.1,-2.4 L7.1,2.4 M8.6,-2.4 L8.6,2.4" stroke="#3a4048" stroke-width="0.7"/>
<rect x="19" y="-0.7" width="1.6" height="1.4" rx="0.4" fill="#ff5a3c"/>
<rect x="3.4" y="-1.1" width="1.5" height="2.2" rx="0.4" fill="#191c20"/>
"""

const SVG_GUN_SHOTGUN := """
<rect x="1" y="-3.8" width="14" height="7.6" rx="2" fill="#0c0e11"/>
<rect x="2" y="-2.8" width="12" height="5.6" rx="1.6" fill="#8c5c2f"/>
<path d="M3,-1.2 L13,-1.6 M3,0.8 L13,0.4" stroke="#5c3a1c" stroke-width="0.7"/>
<rect x="2" y="-2.8" width="12" height="1.6" rx="0.8" fill="#c48d54"/>
<rect x="13" y="-4.4" width="27.6" height="8.8" rx="1.7" fill="#0c0e11"/>
<rect x="14.4" y="-3.2" width="25" height="2.7" rx="1" fill="#b4bdc7"/>
<rect x="14.4" y="0.5" width="25" height="2.7" rx="1" fill="#6d7580"/>
<rect x="14.4" y="-3.2" width="25" height="0.9" rx="0.4" fill="#e3e9ef"/>
<rect x="20" y="-4.9" width="8.4" height="9.8" rx="1.6" fill="#0c0e11"/>
<rect x="20.9" y="-4" width="6.6" height="8" rx="1" fill="#8c5c2f"/>
<path d="M22.6,-4 L22.6,4 M24.2,-4 L24.2,4 M25.8,-4 L25.8,4" stroke="#5c3a1c" stroke-width="0.8"/>
<circle cx="38.6" cy="-1.8" r="0.9" fill="#f3d27a"/>
<rect x="15.5" y="-0.6" width="3.4" height="1.2" rx="0.4" fill="#c9422f"/>
"""

const SVG_GUN_MACHINEGUN := """
<rect x="0" y="-3.6" width="12" height="7.2" rx="1.7" fill="#0c0e11"/>
<rect x="1" y="-2.6" width="10" height="5.2" rx="1.2" fill="#30353c"/>
<rect x="10" y="-4.8" width="22.4" height="9.6" rx="1.9" fill="#0c0e11"/>
<rect x="11" y="-3.8" width="20.4" height="7.6" rx="1.3" fill="#3f454d"/>
<rect x="13" y="-3.2" width="15" height="3" rx="1" fill="#8d96a1"/>
<rect x="13" y="-3.2" width="15" height="1" rx="0.5" fill="#c9d0d8"/>
<rect x="30" y="-2.8" width="14.6" height="5.6" rx="1.3" fill="#0c0e11"/>
<rect x="31" y="-1.8" width="12.6" height="3.6" rx="0.9" fill="#8d96a1"/>
<circle cx="33.5" cy="0" r="0.8" fill="#191c20"/><circle cx="36.3" cy="0" r="0.8" fill="#191c20"/><circle cx="39.1" cy="0" r="0.8" fill="#191c20"/><circle cx="41.9" cy="0" r="0.8" fill="#191c20"/>
<rect x="14.4" y="2.8" width="9.2" height="6" rx="1.3" fill="#0c0e11"/>
<rect x="15.3" y="3.7" width="7.4" height="4.2" rx="0.8" fill="#5a7436"/>
<path d="M16,-4.6 L16,-6.2 L20,-6.2 L20,-4.6" stroke="#0c0e11" stroke-width="1.2" fill="none"/>
<rect x="24" y="1.6" width="1.4" height="2.2" fill="#f3d27a"/><rect x="26" y="1.6" width="1.4" height="2.2" fill="#f3d27a"/>
"""

const SVG_GUN_LAUNCHER := """
<rect x="0" y="-3.4" width="9" height="6.8" rx="1.8" fill="#0c0e11"/>
<rect x="1" y="-2.4" width="7" height="4.8" rx="1.3" fill="#8c5c2f"/>
<rect x="7" y="-5.8" width="32" height="11.6" rx="3" fill="#0c0e11"/>
<rect x="8.2" y="-4.5" width="29.6" height="9" rx="2.2" fill="#5a7436"/>
<rect x="8.2" y="-4.5" width="29.6" height="2.8" rx="1.4" fill="#8aa65a"/>
<rect x="14" y="-4.5" width="2.2" height="9" fill="#3a4d22"/><rect x="29" y="-4.5" width="2.2" height="9" fill="#3a4d22"/>
<rect x="20" y="-4.5" width="5" height="9" fill="#e9c94a"/>
<path d="M20,-4.5 L22.5,-4.5 L20,0 Z M22.5,4.5 L25,4.5 L25,0 Z" fill="#191c20" fill-opacity="0.7"/>
<rect x="34" y="-7.6" width="9.4" height="15.2" rx="2.6" fill="#0c0e11"/>
<rect x="35.3" y="-6.2" width="6.8" height="12.4" rx="1.8" fill="#3a4d22"/>
<ellipse cx="40.6" cy="0" rx="1.3" ry="4.4" fill="#0c0e11"/>
<rect x="17" y="-7" width="2" height="2.8" fill="#30353c"/>
"""

# ----------------------------------------------------------------------------
#  Detailed weapon pictures. Shared metal / wood / paint gradients first, then
#  one drawing per weapon (all facing right, origin at the middle of the left edge).
# ----------------------------------------------------------------------------
const ICON_DEFS := """
<defs>
<linearGradient id="mt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b4bdc7"/><stop offset="0.5" stop-color="#6d7580"/><stop offset="1" stop-color="#3a4048"/></linearGradient>
<linearGradient id="dk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a616b"/><stop offset="0.5" stop-color="#30353c"/><stop offset="1" stop-color="#191c20"/></linearGradient>
<linearGradient id="wd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c48d54"/><stop offset="0.6" stop-color="#8c5c2f"/><stop offset="1" stop-color="#5c3a1c"/></linearGradient>
<linearGradient id="ol" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8aa65a"/><stop offset="0.6" stop-color="#5a7436"/><stop offset="1" stop-color="#3a4d22"/></linearGradient>
<linearGradient id="rd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e86a50"/><stop offset="0.55" stop-color="#b53520"/><stop offset="1" stop-color="#6e1a10"/></linearGradient>
<linearGradient id="og" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffa64d"/><stop offset="0.6" stop-color="#e06a14"/><stop offset="1" stop-color="#9c4409"/></linearGradient>
<linearGradient id="br" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3d27a"/><stop offset="1" stop-color="#a87c26"/></linearGradient>
</defs>
"""

const ICON_PISTOL := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M56,-4 L176,-4 L176,5 L128,7 L122,15 L96,15 L90,7 L86,7 L76,38 L48,38 L58,7 Z" fill="url(#dk)"/>
<path d="M52,-23 L170,-23 L177,-16 L177,-4 L52,-4 Z" fill="url(#mt)"/>
<rect x="175" y="-18" width="9" height="9" rx="2" fill="#191c20"/>
<path d="M52,-19 L43,-23 L43,-10 L52,-8 Z" fill="#30353c"/>
<path d="M62,11 L84,11 L75,34 L53,34 Z" fill="url(#wd)" stroke-width="1.6"/>
<path d="M97,7 Q99,23 112,23 Q124,23 124,9" fill="none" stroke-width="3"/>
</g>
<path d="M62,-20 L62,-7 M68,-20 L68,-7 M74,-20 L74,-7 M80,-20 L80,-7 M86,-20 L86,-7" stroke="#2b3037" stroke-width="2"/>
<rect x="112" y="-21" width="27" height="8" rx="2" fill="#15171a"/>
<rect x="114" y="-20" width="23" height="2.4" rx="1" fill="#f3d27a" fill-opacity="0.8"/>
<path d="M108,8 Q106,15 110,18" fill="none" stroke="#b4bdc7" stroke-width="2.6" stroke-linecap="round"/>
<path d="M61,16 L80,16 M59,21 L78,21 M57,26 L76,26 M55,31 L74,31" stroke="#4a2e16" stroke-width="1.5"/>
<rect x="54" y="-27" width="9" height="5" rx="1" fill="#191c20"/><rect x="164" y="-26" width="5" height="4" rx="1" fill="#191c20"/>
<circle cx="166.5" cy="-26" r="1.2" fill="#ff5a3c"/>
<path d="M96,-18 L166,-18" stroke="#e3e9ef" stroke-width="1.4" stroke-opacity="0.75" stroke-linecap="round"/>
<circle cx="100" cy="1" r="2" fill="#191c20"/><circle cx="150" cy="1" r="2" fill="#191c20"/>
<path d="M132,-1 L170,-1" stroke="#191c20" stroke-width="1.4"/>
"""

const ICON_SMG := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M60,-11 L26,-11 L26,8 L42,8" fill="none" stroke-width="4.5"/>
<path d="M104,2 L123,2 L128,38 L111,38 Z" fill="url(#mt)"/>
<path d="M70,2 L91,2 L84,31 L63,31 Z" fill="url(#dk)"/>
<path d="M137,2 L151,2 L149,25 L139,25 Z" fill="url(#dk)"/>
<rect x="150" y="-14" width="36" height="10" rx="2.5" fill="url(#mt)"/>
<rect x="184" y="-12" width="12" height="6" rx="1.5" fill="#191c20"/>
<path d="M58,-19 L152,-19 L152,2 L58,2 Z" fill="url(#dk)"/>
</g>
<path d="M66,-23 L72,-23 L72,-19 L66,-19 Z M78,-23 L84,-23 L84,-19 L78,-19 Z M90,-23 L96,-23 L96,-19 L90,-19 Z M102,-23 L108,-23 L108,-19 L102,-19 Z M114,-23 L120,-23 L120,-19 L114,-19 Z M126,-23 L132,-23 L132,-19 L126,-19 Z M138,-23 L144,-23 L144,-19 L138,-19 Z" fill="#30353c" stroke="#0c0e11" stroke-width="1.2"/>
<rect x="96" y="-15" width="26" height="7" rx="1.5" fill="#101215"/>
<rect x="98" y="-14" width="22" height="2.2" rx="1" fill="#f3d27a" fill-opacity="0.8"/>
<path d="M92,3 Q93,16 103,16" fill="none" stroke="#0c0e11" stroke-width="2.6"/>
<path d="M97,4 Q96,9 99,12" fill="none" stroke="#b4bdc7" stroke-width="2.2" stroke-linecap="round"/>
<path d="M110,9 L125,9 M111,16 L126,16 M112,23 L127,23 M113,30 L128,30" stroke="#3a4048" stroke-width="1.5"/>
<path d="M68,8 L86,8 M67,13 L85,13 M66,18 L84,18 M65,23 L83,23" stroke="#191c20" stroke-width="1.4"/>
<path d="M156,-11 L182,-11" stroke="#e3e9ef" stroke-width="1.3" stroke-opacity="0.8" stroke-linecap="round"/>
<circle cx="130" cy="-9" r="3" fill="#6d7580" stroke="#0c0e11" stroke-width="1.2"/>
<path d="M62,-6 L148,-6" stroke="#191c20" stroke-width="1.2"/>
<circle cx="66" cy="-13" r="1.8" fill="#191c20"/><circle cx="146" cy="-13" r="1.8" fill="#191c20"/>
"""

const ICON_SHOTGUN := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M6,-5 L50,-13 L62,-13 L62,7 L50,9 L14,23 L6,21 Z" fill="url(#wd)"/>
<rect x="104" y="-3" width="90" height="8.5" rx="2.5" fill="url(#dk)"/>
<rect x="104" y="-14" width="110" height="9" rx="2.5" fill="url(#mt)"/>
<path d="M60,-15 L106,-15 L106,9 L60,9 Z" fill="url(#dk)"/>
<rect x="124" y="-6" width="46" height="15" rx="4" fill="url(#wd)"/>
<path d="M66,9 Q68,24 80,24 Q90,24 90,10" fill="none" stroke-width="3"/>
<rect x="188" y="-16" width="6" height="23" rx="1.5" fill="#30353c" stroke-width="1.6"/>
</g>
<path d="M131,-4 L131,7 M137,-4 L137,7 M143,-4 L143,7 M149,-4 L149,7 M155,-4 L155,7 M161,-4 L161,7" stroke="#5c3a1c" stroke-width="1.8"/>
<rect x="72" y="-12" width="22" height="7" rx="1.5" fill="#101215"/>
<rect x="74" y="-11" width="12" height="5" rx="1.5" fill="#c9422f"/>
<rect x="86" y="-11" width="5" height="5" rx="1" fill="#f3d27a"/>
<path d="M78,10 Q77,16 80,19" fill="none" stroke="#b4bdc7" stroke-width="2.4" stroke-linecap="round"/>
<path d="M12,2 Q30,-4 52,-6 M12,10 Q32,2 54,0 M14,17 Q32,10 50,4" stroke="#5c3a1c" stroke-width="1.3" fill="none" stroke-opacity="0.8"/>
<path d="M6,-5 L6,21" stroke="#191c20" stroke-width="4" stroke-linecap="round"/>
<circle cx="209" cy="-16" r="2.2" fill="#f3d27a" stroke="#0c0e11" stroke-width="1"/>
<path d="M110,-11 L206,-11" stroke="#e3e9ef" stroke-width="1.4" stroke-opacity="0.8" stroke-linecap="round"/>
<circle cx="66" cy="-9" r="1.8" fill="#191c20"/><circle cx="100" cy="3" r="1.8" fill="#191c20"/>
"""

const ICON_MACHINEGUN := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M170,-2 L158,30 M170,-2 L186,30" fill="none" stroke-width="4"/>
<path d="M6,-10 L40,-13 L40,9 L22,11 L6,7 Z" fill="url(#dk)"/>
<path d="M46,7 L65,7 L58,31 L39,31 Z" fill="url(#dk)"/>
<rect x="74" y="5" width="36" height="28" rx="3.5" fill="url(#ol)"/>
<rect x="180" y="-9" width="30" height="7" rx="2" fill="url(#dk)"/>
<rect x="206" y="-12" width="11" height="13" rx="2.5" fill="#30353c"/>
<rect x="120" y="-12" width="62" height="12" rx="3" fill="url(#mt)"/>
<path d="M40,-17 L122,-17 L122,7 L40,7 Z" fill="url(#dk)"/>
<rect x="58" y="-22" width="52" height="7" rx="2" fill="url(#mt)"/>
<path d="M94,-22 Q108,-37 124,-22" fill="none" stroke-width="4.5"/>
</g>
<circle cx="130" cy="-6" r="2.3" fill="#191c20"/><circle cx="140" cy="-6" r="2.3" fill="#191c20"/><circle cx="150" cy="-6" r="2.3" fill="#191c20"/><circle cx="160" cy="-6" r="2.3" fill="#191c20"/><circle cx="170" cy="-6" r="2.3" fill="#191c20"/>
<rect x="62" y="1" width="4" height="7" rx="1" fill="url(#br)" stroke="#0c0e11" stroke-width="0.8"/><rect x="67" y="1" width="4" height="7" rx="1" fill="url(#br)" stroke="#0c0e11" stroke-width="0.8"/><rect x="72" y="1" width="4" height="7" rx="1" fill="url(#br)" stroke="#0c0e11" stroke-width="0.8"/><rect x="77" y="1" width="4" height="7" rx="1" fill="url(#br)" stroke="#0c0e11" stroke-width="0.8"/><rect x="82" y="1" width="4" height="7" rx="1" fill="url(#br)" stroke="#0c0e11" stroke-width="0.8"/>
<path d="M74,13 L110,13" stroke="#3a4d22" stroke-width="2"/>
<rect x="88" y="10" width="8" height="6" rx="1.5" fill="#b4bdc7" stroke="#0c0e11" stroke-width="1"/>
<path d="M80,20 L104,20 M80,25 L104,25" stroke="#3a4d22" stroke-width="1.4"/>
<path d="M66,8 Q67,20 76,21" fill="none" stroke="#0c0e11" stroke-width="2.4"/>
<path d="M45,13 L61,13 M44,18 L60,18 M43,23 L59,23" stroke="#191c20" stroke-width="1.4"/>
<path d="M6,-10 L6,7" stroke="#191c20" stroke-width="4" stroke-linecap="round"/>
<path d="M62,-19 L106,-19" stroke="#e3e9ef" stroke-width="1.3" stroke-opacity="0.8" stroke-linecap="round"/>
<path d="M124,-9 L178,-9" stroke="#e3e9ef" stroke-width="1.2" stroke-opacity="0.6" stroke-linecap="round"/>
<rect x="46" y="-12" width="10" height="6" rx="1" fill="#101215"/>
<circle cx="116" cy="-11" r="2" fill="#191c20"/><circle cx="46" cy="2" r="2" fill="#191c20"/>
"""

const ICON_RIFLE := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<rect x="106" y="-12" width="108" height="6.5" rx="2" fill="url(#mt)"/>
<path d="M4,-3 L46,-11 L152,-8 L152,2 L72,5 L62,11 L46,9 L12,21 L4,19 Z" fill="url(#wd)"/>
<rect x="62" y="-13" width="46" height="8" rx="2" fill="url(#dk)"/>
<path d="M68,5 Q70,20 82,20 Q92,20 92,7" fill="none" stroke-width="3"/>
<rect x="76" y="-18" width="6" height="7" rx="1" fill="#30353c" stroke-width="1.4"/><rect x="106" y="-18" width="6" height="7" rx="1" fill="#30353c" stroke-width="1.4"/>
<rect x="58" y="-27" width="72" height="10" rx="5" fill="url(#dk)"/>
<rect x="50" y="-29" width="14" height="14" rx="4" fill="url(#dk)"/>
<rect x="122" y="-30" width="16" height="16" rx="4.5" fill="url(#dk)"/>
<path d="M92,-9 L101,3" fill="none" stroke-width="4"/>
<circle cx="102" cy="4" r="4" fill="url(#mt)"/>
</g>
<ellipse cx="136" cy="-22" rx="2.2" ry="5.4" fill="#7fd0ff" fill-opacity="0.85"/>
<ellipse cx="52" cy="-22" rx="1.8" ry="4.6" fill="#0c0e11"/>
<rect x="90" y="-31" width="7" height="5" rx="1.5" fill="#6d7580" stroke="#0c0e11" stroke-width="1.2"/>
<path d="M80,6 Q79,12 82,15" fill="none" stroke="#b4bdc7" stroke-width="2.4" stroke-linecap="round"/>
<path d="M10,4 Q30,-3 54,-6 M10,12 Q34,3 60,0 M12,18 Q30,11 48,6 M66,-1 L148,-4 M110,-1 L150,-1" stroke="#5c3a1c" stroke-width="1.3" fill="none" stroke-opacity="0.8"/>
<path d="M4,-3 L4,19" stroke="#191c20" stroke-width="4" stroke-linecap="round"/>
<path d="M204,-12 L207,-18 L210,-12 Z" fill="#191c20"/>
<path d="M112,-10 L206,-10" stroke="#e3e9ef" stroke-width="1.3" stroke-opacity="0.8" stroke-linecap="round"/>
<path d="M62,-24 L126,-24" stroke="#8d96a1" stroke-width="1.2" stroke-opacity="0.7" stroke-linecap="round"/>
"""

const ICON_LAUNCHER := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M6,-6 L40,-11 L54,-11 L54,9 L40,11 L12,19 L6,17 Z" fill="url(#wd)"/>
<path d="M58,9 L77,9 L70,32 L51,32 Z" fill="url(#dk)"/>
<path d="M122,9 L138,9 L136,29 L124,29 Z" fill="url(#dk)"/>
<rect x="88" y="-19" width="112" height="28" rx="5" fill="url(#ol)"/>
<rect x="194" y="-22" width="15" height="34" rx="5" fill="#3a4d22"/>
<rect x="50" y="-15" width="42" height="24" rx="4" fill="url(#dk)"/>
<rect x="120" y="-34" width="6" height="16" rx="1.5" fill="#30353c" stroke-width="1.6"/>
</g>
<rect x="108" y="-19" width="7" height="28" fill="#3a4d22"/><rect x="170" y="-19" width="7" height="28" fill="#3a4d22"/>
<rect x="140" y="-19" width="12" height="28" fill="#e9c94a"/>
<path d="M140,-19 L146,-19 L140,-9 Z M146,-19 L152,-19 L152,-15 L142,2 L140,2 L140,-4 Z M152,-6 L152,5 L146,9 L143,9 Z" fill="#191c20" fill-opacity="0.75"/>
<path d="M118,-30 L128,-30 M118,-25 L128,-25" stroke="#b4bdc7" stroke-width="1.4"/>
<circle cx="88" cy="6" r="3.4" fill="#6d7580" stroke="#0c0e11" stroke-width="1.4"/>
<path d="M78,10 Q80,22 90,22 Q98,22 98,11" fill="none" stroke="#0c0e11" stroke-width="2.6"/>
<path d="M88,11 Q87,16 90,18" fill="none" stroke="#b4bdc7" stroke-width="2.2" stroke-linecap="round"/>
<path d="M94,-14 L190,-14" stroke="#e8f0c8" stroke-width="1.6" stroke-opacity="0.6" stroke-linecap="round"/>
<ellipse cx="204" cy="-5" rx="2.6" ry="11" fill="#0c0e11"/>
<path d="M12,1 Q28,-4 50,-6 M12,9 Q30,3 50,1" stroke="#5c3a1c" stroke-width="1.3" fill="none" stroke-opacity="0.8"/>
<path d="M56,15 L73,15 M55,20 L72,20 M54,25 L71,25" stroke="#191c20" stroke-width="1.4"/>
<circle cx="58" cy="-8" r="2" fill="#191c20"/><circle cx="84" cy="-8" r="2" fill="#191c20"/>
"""

const ICON_FLAMETHROWER := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M48,10 Q66,30 86,8" fill="none" stroke-width="5.5"/>
<rect x="6" y="-28" width="42" height="21" rx="10" fill="url(#rd)"/>
<rect x="6" y="-3" width="42" height="21" rx="10" fill="url(#rd)"/>
<rect x="20" y="-30" width="6" height="50" rx="2" fill="#30353c"/>
<path d="M84,5 L103,5 L96,30 L77,30 Z" fill="url(#dk)"/>
<path d="M119,5 L133,5 L131,24 L121,24 Z" fill="url(#dk)"/>
<rect x="136" y="-9" width="56" height="10" rx="2.5" fill="url(#mt)"/>
<rect x="146" y="-14" width="36" height="5" rx="1.5" fill="url(#dk)"/>
<rect x="186" y="3" width="15" height="5" rx="1.5" fill="url(#mt)" stroke-width="1.6"/>
<path d="M190,-13 L205,-15 L205,5 L190,3 Z" fill="url(#dk)"/>
<rect x="70" y="-11" width="68" height="16" rx="3.5" fill="url(#dk)"/>
<circle cx="34" cy="-31" r="4.5" fill="url(#mt)"/>
</g>
<path d="M206,-7 Q218,-13 215,-5 Q222,-2 213,3 Q208,1 206,-2 Z" fill="#ff9a2e"/>
<path d="M207,-5 Q213,-8 212,-3 Q214,-1 210,1 Q207,0 207,-3 Z" fill="#fff0a8"/>
<circle cx="104" cy="-12" r="6" fill="#ece6d2" stroke="#0c0e11" stroke-width="1.6"/>
<path d="M104,-12 L108,-15" stroke="#c9422f" stroke-width="1.6" stroke-linecap="round"/>
<circle cx="152" cy="-11.5" r="1.3" fill="#0c0e11"/><circle cx="159" cy="-11.5" r="1.3" fill="#0c0e11"/><circle cx="166" cy="-11.5" r="1.3" fill="#0c0e11"/><circle cx="173" cy="-11.5" r="1.3" fill="#0c0e11"/>
<path d="M12,-22 L42,-22 M12,3 L42,3" stroke="#ffb09c" stroke-width="2" stroke-opacity="0.7" stroke-linecap="round"/>
<path d="M30,-17 L40,-17 L35,-10 Z M30,8 L40,8 L35,15 Z" fill="#f3d27a" stroke="#0c0e11" stroke-width="1"/>
<path d="M104,6 Q105,17 114,18" fill="none" stroke="#0c0e11" stroke-width="2.4"/>
<path d="M82,11 L99,11 M81,16 L98,16 M80,21 L97,21" stroke="#191c20" stroke-width="1.4"/>
<path d="M140,-6 L188,-6" stroke="#e3e9ef" stroke-width="1.3" stroke-opacity="0.8" stroke-linecap="round"/>
<path d="M76,-6 L96,-6 M116,-6 L134,-6" stroke="#8d96a1" stroke-width="1.2" stroke-opacity="0.6" stroke-linecap="round"/>
"""

const ICON_CHAINSAW := """
<g stroke="#0c0e11" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
<path d="M96,-11 L196,-11 Q213,-11 213,0 Q213,11 196,11 L96,11 Z" fill="url(#mt)"/>
<path d="M20,-9 L4,-9 L4,15 L20,15" fill="none" stroke-width="5.5"/>
<path d="M30,-19 Q30,-36 56,-36 L84,-36 Q98,-36 98,-21" fill="none" stroke-width="5.5"/>
<path d="M18,-19 L92,-19 L100,-8 L100,17 L18,17 Z" fill="url(#og)"/>
<circle cx="42" cy="2" r="10" fill="url(#dk)"/>
</g>
<path d="M102,-11 L105,-16.5 L108,-11 Z M112,-11 L115,-16.5 L118,-11 Z M122,-11 L125,-16.5 L128,-11 Z M132,-11 L135,-16.5 L138,-11 Z M142,-11 L145,-16.5 L148,-11 Z M152,-11 L155,-16.5 L158,-11 Z M162,-11 L165,-16.5 L168,-11 Z M172,-11 L175,-16.5 L178,-11 Z M182,-11 L185,-16.5 L188,-11 Z M192,-11 L195,-16.5 L198,-11 Z" fill="#191c20" stroke="#0c0e11" stroke-width="1"/>
<path d="M102,11 L105,16.5 L108,11 Z M112,11 L115,16.5 L118,11 Z M122,11 L125,16.5 L128,11 Z M132,11 L135,16.5 L138,11 Z M142,11 L145,16.5 L148,11 Z M152,11 L155,16.5 L158,11 Z M162,11 L165,16.5 L168,11 Z M172,11 L175,16.5 L178,11 Z M182,11 L185,16.5 L188,11 Z M192,11 L195,16.5 L198,11 Z" fill="#191c20" stroke="#0c0e11" stroke-width="1"/>
<path d="M206,-9 L212,-12 L211,-4 Z M210,3 L217,3 L211,9 Z" fill="#191c20" stroke="#0c0e11" stroke-width="1"/>
<path d="M106,0 L198,0" stroke="#3a4048" stroke-width="2.2" stroke-linecap="round"/>
<path d="M104,-6 L200,-6" stroke="#e3e9ef" stroke-width="1.4" stroke-opacity="0.8" stroke-linecap="round"/>
<circle cx="106" cy="-4" r="2.6" fill="#30353c" stroke="#0c0e11" stroke-width="1"/><circle cx="106" cy="5" r="2.6" fill="#30353c" stroke="#0c0e11" stroke-width="1"/>
<path d="M178,-2 Q196,-10 210,-2 Q212,6 200,9 Q186,8 178,-2 Z" fill="#7a1010" fill-opacity="0.9"/>
<circle cx="170" cy="5" r="2" fill="#7a1010"/><circle cx="160" cy="-5" r="1.5" fill="#7a1010"/>
<circle cx="42" cy="2" r="4" fill="#6d7580" stroke="#0c0e11" stroke-width="1.2"/>
<path d="M62,-13 L62,-3 M68,-13 L68,-3 M74,-13 L74,-3 M80,-13 L80,-3 M86,-13 L86,-3" stroke="#9c4409" stroke-width="2" stroke-linecap="round"/>
<path d="M24,-14 L54,-14" stroke="#ffd9a8" stroke-width="2" stroke-opacity="0.8" stroke-linecap="round"/>
<rect x="60" y="4" width="30" height="9" rx="2" fill="#191c20"/>
<path d="M64,8.5 L86,8.5" stroke="#ffa64d" stroke-width="1.6"/>
<path d="M8,-2 L8,8" stroke="#6d7580" stroke-width="2.4" stroke-linecap="round"/>
"""

const SVG_GUN_SMG := """
<rect x="0" y="-2.8" width="9" height="5.6" rx="1.4" fill="#0c0e11"/>
<rect x="1" y="-1.8" width="7" height="3.6" rx="1" fill="#30353c"/>
<rect x="7" y="-4.6" width="19.4" height="9.2" rx="1.9" fill="#0c0e11"/>
<rect x="8" y="-3.6" width="17.4" height="7.2" rx="1.3" fill="#3f454d"/>
<rect x="8" y="-3.6" width="17.4" height="2.2" rx="1" fill="#6d7580"/>
<path d="M10,-1 L10,1 M13,-1 L13,1 M16,-1 L16,1 M19,-1 L19,1 M22,-1 L22,1" stroke="#191c20" stroke-width="1.2"/>
<rect x="25" y="-2.4" width="10.4" height="4.8" rx="1.3" fill="#0c0e11"/>
<rect x="26" y="-1.4" width="8.6" height="2.8" rx="0.9" fill="#8d96a1"/>
<rect x="26" y="-1.4" width="8.6" height="1" rx="0.5" fill="#c9d0d8"/>
<rect x="12.6" y="3" width="6.8" height="5.4" rx="1.2" fill="#0c0e11"/>
<rect x="13.5" y="3.8" width="5" height="3.8" rx="0.8" fill="#565d67"/>
<rect x="20" y="-5.4" width="3" height="1.8" rx="0.5" fill="#8d96a1"/>
"""

const SVG_GUN_RIFLE := """
<rect x="0" y="-3.6" width="17" height="7.2" rx="2" fill="#0c0e11"/>
<rect x="1" y="-2.6" width="15" height="5.2" rx="1.5" fill="#8c5c2f"/>
<rect x="1" y="-2.6" width="15" height="1.6" rx="0.8" fill="#c48d54"/>
<rect x="14" y="-3.4" width="20.4" height="6.8" rx="1.5" fill="#0c0e11"/>
<rect x="15" y="-2.4" width="18.4" height="4.8" rx="1" fill="#8c5c2f"/>
<rect x="32" y="-2.1" width="25.4" height="4.2" rx="1.2" fill="#0c0e11"/>
<rect x="33" y="-1.1" width="23.6" height="2.2" rx="0.8" fill="#8d96a1"/>
<rect x="33" y="-1.1" width="23.6" height="0.8" rx="0.4" fill="#d5dbe2"/>
<rect x="15" y="-1.9" width="18" height="3.8" rx="1.9" fill="#0c0e11"/>
<rect x="16" y="-1.2" width="16" height="2.4" rx="1.2" fill="#30353c"/>
<rect x="13.4" y="-2.5" width="4.4" height="5" rx="1.4" fill="#0c0e11"/>
<rect x="30.4" y="-2.7" width="4.8" height="5.4" rx="1.5" fill="#0c0e11"/>
<ellipse cx="33.6" cy="0" rx="0.9" ry="1.7" fill="#7fd0ff"/>
<rect x="24" y="2.6" width="5" height="1.8" rx="0.8" fill="#8d96a1"/>
"""

const SVG_GUN_FLAMETHROWER := """
<rect x="0" y="-9" width="14.4" height="8.6" rx="4" fill="#0c0e11"/>
<rect x="0" y="0.4" width="14.4" height="8.6" rx="4" fill="#0c0e11"/>
<rect x="1.2" y="-7.8" width="12" height="6.2" rx="3" fill="#b53520"/>
<rect x="1.2" y="1.6" width="12" height="6.2" rx="3" fill="#b53520"/>
<rect x="2.4" y="-7.2" width="9" height="1.6" rx="0.8" fill="#e86a50"/><rect x="2.4" y="2.2" width="9" height="1.6" rx="0.8" fill="#e86a50"/>
<rect x="6" y="-9.4" width="2.4" height="18.8" rx="1" fill="#30353c"/>
<rect x="12" y="-3.8" width="24.4" height="7.6" rx="2" fill="#0c0e11"/>
<rect x="13.2" y="-2.6" width="22" height="5.2" rx="1.3" fill="#3f454d"/>
<rect x="13.2" y="-2.6" width="22" height="1.7" rx="0.8" fill="#6d7580"/>
<circle cx="19" cy="0" r="1.9" fill="#ece6d2" stroke="#0c0e11" stroke-width="0.7"/>
<rect x="34" y="-2.8" width="12.4" height="5.6" rx="1.5" fill="#0c0e11"/>
<rect x="35.2" y="-1.6" width="10" height="3.2" rx="1" fill="#e9a23a"/>
<circle cx="24.5" cy="0" r="0.7" fill="#0c0e11"/><circle cx="27.5" cy="0" r="0.7" fill="#0c0e11"/><circle cx="30.5" cy="0" r="0.7" fill="#0c0e11"/>
<circle cx="46.2" cy="0" r="1.7" fill="#ffd36b"/>
"""

const SVG_GUN_CHAINSAW := """
<rect x="4" y="-10.2" width="10" height="4.8" rx="2.2" fill="#0c0e11"/>
<rect x="0" y="-7.2" width="18.4" height="14.4" rx="3.2" fill="#0c0e11"/>
<rect x="1.3" y="-5.9" width="15.8" height="11.8" rx="2.3" fill="#e06a14"/>
<rect x="1.3" y="-5.9" width="15.8" height="3.6" rx="1.8" fill="#ffa64d"/>
<circle cx="7" cy="1" r="3" fill="#30353c" stroke="#0c0e11" stroke-width="0.8"/>
<path d="M11.5,-1.5 L11.5,3.5 M13.3,-1.5 L13.3,3.5 M15.1,-1.5 L15.1,3.5" stroke="#9c4409" stroke-width="0.9"/>
<rect x="16" y="-4.8" width="37.4" height="9.6" rx="4.8" fill="#0c0e11"/>
<rect x="17.8" y="-3" width="33.8" height="6" rx="3" fill="#8d96a1"/>
<rect x="17.8" y="-3" width="33.8" height="1.8" rx="0.9" fill="#d5dbe2"/>
<path d="M20,-4.8 L22,-6.6 L24,-4.8 M27,-4.8 L29,-6.6 L31,-4.8 M34,-4.8 L36,-6.6 L38,-4.8 M41,-4.8 L43,-6.6 L45,-4.8 M20,4.8 L22,6.6 L24,4.8 M27,4.8 L29,6.6 L31,4.8 M34,4.8 L36,6.6 L38,4.8 M41,4.8 L43,6.6 L45,4.8" stroke="#0c0e11" stroke-width="1.6" fill="none"/>
<path d="M19,0 L49,0" stroke="#3a4048" stroke-width="0.9"/>
<path d="M42,-2 Q48,-4 51,-1 Q51,3 46,3 Q43,2 42,-2 Z" fill="#7a1010"/>
"""

const SVG_GRENADE := """
<circle r="6.8" fill="#16181c"/>
<circle r="5.2" fill="#59752f"/>
<circle cx="-1.6" cy="-1.6" r="1.7" fill="#b8d67a"/>
"""

# Small white symbols for the upgrade trees (40x40, drawn tinted).
const SYMBOLS := {
	"stat_vitality": "<path d=\"M0 15 C-21 1 -16 -15 -7 -15 C-3 -15 0 -12 0 -9 C0 -12 3 -15 7 -15 C16 -15 21 1 0 15Z\" fill=\"#fff\"/>",
	"stat_strength": "<path d=\"M0 -18 L4.5 -11 L4.5 4 L-4.5 4 L-4.5 -11Z\" fill=\"#fff\"/><rect x=\"-10\" y=\"4\" width=\"20\" height=\"4\" rx=\"1.5\" fill=\"#fff\"/><rect x=\"-2.2\" y=\"8\" width=\"4.4\" height=\"7\" fill=\"#fff\"/><circle cy=\"16.5\" r=\"2.8\" fill=\"#fff\"/>",
	"stat_dexterity": "<path d=\"M5 -18 L-10 2 L-1.5 2 L-6 18 L11 -4 L2 -4Z\" fill=\"#fff\"/>",
	"stat_agility": "<path d=\"M-15 -12 L-4 0 L-15 12 L-8.5 12 L2.5 0 L-8.5 -12Z\" fill=\"#fff\"/><path d=\"M-2 -12 L9 0 L-2 12 L4.5 12 L15.5 0 L4.5 -12Z\" fill=\"#fff\"/>",
	"stat_defense": "<path d=\"M0 -17 L14 -12 L14 0 C14 9 7 14.5 0 18 C-7 14.5 -14 9 -14 0 L-14 -12Z\" fill=\"#fff\"/>",
	"stat_evasion": "<path d=\"M-12 16 L-12 -3 C-12 -21 12 -21 12 -3 L12 16 L7 11 L2.5 16 L-2.5 11 L-7 16Z\" fill=\"#fff\"/><circle cx=\"-4.5\" cy=\"-4\" r=\"2.6\" fill=\"#000\" fill-opacity=\"0.75\"/><circle cx=\"4.5\" cy=\"-4\" r=\"2.6\" fill=\"#000\" fill-opacity=\"0.75\"/>",
	"stat_critical": "<circle r=\"10.5\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.2\"/><path d=\"M0 -18 V-7 M0 7 V18 M-18 0 H-7 M7 0 H18\" stroke=\"#fff\" stroke-width=\"3.2\" stroke-linecap=\"round\"/><circle r=\"2.4\" fill=\"#fff\"/>",
	"stat_luck": "<circle cx=\"-6\" cy=\"-7\" r=\"6.6\" fill=\"#fff\"/><circle cx=\"6\" cy=\"-7\" r=\"6.6\" fill=\"#fff\"/><circle cx=\"-6\" cy=\"4\" r=\"6.6\" fill=\"#fff\"/><circle cx=\"6\" cy=\"4\" r=\"6.6\" fill=\"#fff\"/><path d=\"M0 2 C1 9 3 14 7 17\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\"/>",
	"stat_bond": "<ellipse cx=\"0\" cy=\"7\" rx=\"9.5\" ry=\"8\" fill=\"#fff\"/><circle cx=\"-12\" cy=\"-3\" r=\"4.3\" fill=\"#fff\"/><circle cx=\"-4.6\" cy=\"-11\" r=\"4.6\" fill=\"#fff\"/><circle cx=\"4.6\" cy=\"-11\" r=\"4.6\" fill=\"#fff\"/><circle cx=\"12\" cy=\"-3\" r=\"4.3\" fill=\"#fff\"/>",
	"family_grit": "<path d=\"M0 -18 L15 -12 L15 1 C15 10 7 15.5 0 19 C-7 15.5 -15 10 -15 1 L-15 -12Z\" fill=\"#fff\"/><path d=\"M-7 -4 L0 3 L7 -4 L7 2 L0 9 L-7 2Z\" fill=\"#000\" fill-opacity=\"0.6\"/>",
	"family_fury": "<path d=\"M0 -19 C3 -11 12 -7 12 4 C12 12 6 18 0 18 C-6 18 -12 12 -12 4 C-12 -1 -9 -5 -6 -8 C-6 -3 -3 0 -1 0 C-3 -6 -2 -13 0 -19Z\" fill=\"#fff\"/><path d=\"M0 16 C-4 16 -6 12 -6 9 C-6 5 -2 3 0 -1 C2 3 6 5 6 9 C6 12 4 16 0 16Z\" fill=\"#000\" fill-opacity=\"0.55\"/>",
	"family_instinct": "<path d=\"M-18 0 C-10 -12 10 -12 18 0 C10 12 -10 12 -18 0Z\" fill=\"#fff\"/><circle r=\"6.5\" fill=\"#000\" fill-opacity=\"0.65\"/><circle r=\"2.6\" fill=\"#fff\"/>",
	"ui_star": "<path d=\"M0 -18 L5.3 -5.6 L18.5 -5.6 L7.8 2.6 L11.4 15.5 L0 7.8 L-11.4 15.5 L-7.8 2.6 L-18.5 -5.6 L-5.3 -5.6Z\" fill=\"#fff\"/>",
	"ui_infinity": "<path d=\"M0 0 C-4 -9 -16 -9 -16 0 C-16 9 -4 9 0 0 C4 -9 16 -9 16 0 C16 9 4 9 0 0Z\" fill=\"none\" stroke=\"#fff\" stroke-width=\"4\"/>",
	"ui_lock": "<rect x=\"-11\" y=\"-3\" width=\"22\" height=\"18\" rx=\"3\" fill=\"#fff\"/><path d=\"M-7 -3 V-8 C-7 -18 7 -18 7 -8 V-3\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.6\"/><circle cy=\"5\" r=\"2.6\" fill=\"#000\" fill-opacity=\"0.7\"/>",
	"ui_person": "<circle cy=\"-8\" r=\"7.5\" fill=\"#fff\"/><path d=\"M-14 17 C-14 2 14 2 14 17Z\" fill=\"#fff\"/>",
	"perk_mags": "<path d=\"M-6 -17 L10 -17 L5 17 L-11 17Z\" fill=\"#fff\"/><path d=\"M-5.5 -9 H7.5 M-6.7 -1 H6.3 M-7.9 7 H5.1\" stroke=\"#000\" stroke-opacity=\"0.5\" stroke-width=\"2.6\"/>",
	"perk_pierce": "<circle cx=\"-5\" r=\"9.5\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.2\"/><path d=\"M-19 0 H11\" stroke=\"#fff\" stroke-width=\"3.6\" stroke-linecap=\"round\"/><path d=\"M8 -7.5 L19 0 L8 7.5Z\" fill=\"#fff\"/>",
	"perk_medic": "<path d=\"M-5.5 -16 H5.5 V-5.5 H16 V5.5 H5.5 V16 H-5.5 V5.5 H-16 V-5.5 H-5.5Z\" fill=\"#fff\"/>",
	"perk_leech": "<path d=\"M0 -18 C8 -6 13 0 13 7 C13 14 7 18 0 18 C-7 18 -13 14 -13 7 C-13 0 -8 -6 0 -18Z\" fill=\"#fff\"/><path d=\"M-2 0 H2 V4 H6 V8 H2 V12 H-2 V8 H-6 V4 H-2Z\" fill=\"#000\" fill-opacity=\"0.55\"/>",
	"track_power": "<path d=\"M0 -18 L4 -6 L16 -10 L8 0 L16 10 L4 6 L0 18 L-4 6 L-16 10 L-8 0 L-16 -10 L-4 -6Z\" fill=\"#fff\"/>",
	"track_speed": "<path d=\"M5 -18 L-10 2 L-1.5 2 L-6 18 L11 -4 L2 -4Z\" fill=\"#fff\"/>",
	"track_stability": "<circle r=\"10.5\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.2\"/><path d=\"M0 -18 V-7 M0 7 V18 M-18 0 H-7 M7 0 H18\" stroke=\"#fff\" stroke-width=\"3.2\" stroke-linecap=\"round\"/><circle r=\"2.4\" fill=\"#fff\"/>",
	"track_reload": "<path d=\"M12 -6 A13.5 13.5 0 1 0 13.5 3\" fill=\"none\" stroke=\"#fff\" stroke-width=\"4\" stroke-linecap=\"round\"/><path d=\"M5 -9 L16 -3 L15 -16Z\" fill=\"#fff\"/>",
	"track_spawn": "<rect x=\"-14\" y=\"-12\" width=\"28\" height=\"24\" rx=\"2.5\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.4\"/><path d=\"M-14 -12 L14 12 M14 -12 L-14 12\" stroke=\"#fff\" stroke-width=\"3\"/>",
	"track_duration": "<path d=\"M-10 -17 H10 M-10 17 H10\" stroke=\"#fff\" stroke-width=\"3.4\" stroke-linecap=\"round\"/><path d=\"M-8 -15 C-8 -5 0 -3 0 0 C0 -3 8 -5 8 -15Z M-8 15 C-8 5 0 3 0 0 C0 3 8 5 8 15Z\" fill=\"#fff\"/>",
	"gear_helmet": "<path d=\"M-15 5 C-15 -19 15 -19 15 5 L18 5 L18 11 L-18 11 L-18 5Z\" fill=\"#fff\"/><rect x=\"-9\" y=\"-2\" width=\"18\" height=\"4\" rx=\"1.5\" fill=\"#000\" fill-opacity=\"0.6\"/>",
	"gear_amulet": "<path d=\"M-13 -17 L0 3 L13 -17\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><path d=\"M0 1 L7 9 L0 18 L-7 9Z\" fill=\"#fff\"/>",
	"gear_ring": "<circle cy=\"4\" r=\"10\" fill=\"none\" stroke=\"#fff\" stroke-width=\"5\"/><path d=\"M0 -18 L6.5 -11 L0 -4 L-6.5 -11Z\" fill=\"#fff\"/>",
	"gear_belt": "<rect x=\"-18\" y=\"-5\" width=\"36\" height=\"10\" rx=\"2\" fill=\"#fff\"/><rect x=\"-7.5\" y=\"-10\" width=\"15\" height=\"20\" rx=\"2.5\" fill=\"#fff\"/><rect x=\"-3.5\" y=\"-5.5\" width=\"7\" height=\"11\" rx=\"1\" fill=\"#000\" fill-opacity=\"0.65\"/>",
	"gear_boots": "<path d=\"M-9 -17 L3 -17 L3 1 L14 5 C18 6.5 18 15 14 15 L-9 15Z\" fill=\"#fff\"/><rect x=\"-9\" y=\"9.5\" width=\"25\" height=\"2.6\" fill=\"#000\" fill-opacity=\"0.5\"/>",
	"gear_pants": "<path d=\"M-12 -17 L12 -17 L14.5 17 L4.5 17 L0 -3 L-4.5 17 L-14.5 17Z\" fill=\"#fff\"/><rect x=\"-12\" y=\"-17\" width=\"24\" height=\"3.4\" fill=\"#000\" fill-opacity=\"0.45\"/>",
	"gear_gloves": "<path d=\"M-8 17 L-8 0 L-13 -6 C-15.5 -9 -11.5 -12.5 -9 -9.5 L-5 -5 L-5 -13 C-5 -17 0 -17 0 -13 L0 -15 C0 -19 5 -19 5 -15 L5 -12 C5 -16 10 -16 10 -12 L10 6 C10 12 8 14 8 17Z\" fill=\"#fff\"/>",
	"gear_chest": "<path d=\"M-15 -13 L-6 -17 C-3 -11 3 -11 6 -17 L15 -13 L12.5 -1 L12.5 17 L-12.5 17 L-12.5 -1Z\" fill=\"#fff\"/><path d=\"M0 -11 V17\" stroke=\"#000\" stroke-opacity=\"0.5\" stroke-width=\"2\"/>",
	"ui_perk": "<path d=\"M0 -18 L15.6 -9 L15.6 9 L0 18 L-15.6 9 L-15.6 -9Z\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3.4\" stroke-linejoin=\"round\"/><path d=\"M0 -9 L2.7 -2.9 L9.3 -2.9 L3.9 1.3 L5.7 7.8 L0 3.9 L-5.7 7.8 L-3.9 1.3 L-9.3 -2.9 L-2.7 -2.9Z\" fill=\"#fff\"/>",
}

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

# A piece of gear on the ground: an olive metal case with riveted corner
# plates, seen from above (a weapon crate is wood; this one is steel).
const SVG_GEAR_CRATE := """
<rect x="-18" y="-18" width="36" height="36" rx="5" fill="#000000" fill-opacity="0.25"/>
<rect x="-15.5" y="-15.5" width="31" height="31" rx="4" fill="#10140c"/>
<rect x="-13.6" y="-13.6" width="27.2" height="27.2" rx="2.8" fill="#4b5839"/>
<rect x="-13.6" y="-13.6" width="27.2" height="8.6" rx="2.8" fill="#5a6943"/>
<path d="M-13.6,5 L13.6,5" stroke="#3a452c" stroke-width="1.4"/>
<path d="M-13.6,-13.6 h7.4 v7.4 h-7.4 Z M6.2,-13.6 h7.4 v7.4 h-7.4 Z M-13.6,6.2 h7.4 v7.4 h-7.4 Z M6.2,6.2 h7.4 v7.4 h-7.4 Z" fill="#2b3222"/>
<circle cx="-9.9" cy="-9.9" r="1.15" fill="#a3ae8a"/><circle cx="9.9" cy="-9.9" r="1.15" fill="#a3ae8a"/>
<circle cx="-9.9" cy="9.9" r="1.15" fill="#77815f"/><circle cx="9.9" cy="9.9" r="1.15" fill="#77815f"/>
<rect x="-13.6" y="-13.6" width="27.2" height="27.2" rx="2.8" fill="none" stroke="#8a986b" stroke-width="1.2"/>
"""

# The strap and latches across that case: white, so it can be drawn in the
# colour of the piece's tier.
const SVG_GEAR_CRATE_BAND := """
<rect x="-15.5" y="-3.4" width="31" height="6.8" fill="#ffffff"/>
<rect x="-15.5" y="-3.4" width="31" height="1.6" fill="#ffffff" fill-opacity="0.55"/>
<rect x="-17" y="-5.2" width="4.6" height="10.4" rx="1.2" fill="#ffffff"/>
<rect x="12.4" y="-5.2" width="4.6" height="10.4" rx="1.2" fill="#ffffff"/>
<path d="M-15.5,3.4 L15.5,3.4" stroke="#000000" stroke-opacity="0.35" stroke-width="1"/>
"""

# A treasure chest seen from above: dark wood, brass bands and a lock.
const SVG_CHEST := """
<rect x="-26" y="-17" width="52" height="38" rx="7" fill="#000000" fill-opacity="0.3"/>
<rect x="-24" y="-18" width="48" height="36" rx="5" fill="#231407"/>
<rect x="-22" y="-16" width="44" height="32" rx="3.5" fill="#8a5527"/>
<rect x="-22" y="-16" width="44" height="9" rx="3.5" fill="#a56a33"/>
<path d="M-22,-6.5 L22,-6.5 M-22,4 L22,4" stroke="#603a17" stroke-width="1.6"/>
<rect x="-15.5" y="-16" width="6" height="32" fill="#d9ae42" stroke="#6e4f10" stroke-width="1"/>
<rect x="9.5" y="-16" width="6" height="32" fill="#d9ae42" stroke="#6e4f10" stroke-width="1"/>
<circle cx="-12.5" cy="-11" r="1.3" fill="#fff0b0"/><circle cx="-12.5" cy="10.5" r="1.3" fill="#8a6414"/>
<circle cx="12.5" cy="-11" r="1.3" fill="#fff0b0"/><circle cx="12.5" cy="10.5" r="1.3" fill="#8a6414"/>
<rect x="-5.5" y="0.5" width="11" height="12" rx="2.4" fill="#f0c74c" stroke="#6e4f10" stroke-width="1.2"/>
<circle cx="0" cy="5" r="1.9" fill="#3a2607"/><rect x="-0.9" y="5" width="1.8" height="4.6" fill="#3a2607"/>
<rect x="-22" y="-16" width="44" height="32" rx="3.5" fill="none" stroke="#c98d47" stroke-width="1.2" stroke-opacity="0.7"/>
"""

# The same chest with its lid thrown back: empty inside.
const SVG_CHEST_OPEN := """
<rect x="-26" y="-23" width="52" height="46" rx="7" fill="#000000" fill-opacity="0.3"/>
<rect x="-24" y="-26" width="48" height="13" rx="4" fill="#231407"/>
<rect x="-22" y="-24" width="44" height="9" rx="2.5" fill="#6e4420"/>
<rect x="-15.5" y="-24" width="6" height="9" fill="#b08a30" stroke="#6e4f10" stroke-width="1"/>
<rect x="9.5" y="-24" width="6" height="9" fill="#b08a30" stroke="#6e4f10" stroke-width="1"/>
<rect x="-24" y="-14" width="48" height="36" rx="5" fill="#231407"/>
<rect x="-22" y="-12" width="44" height="32" rx="3.5" fill="#8a5527"/>
<rect x="-18" y="-8" width="36" height="24" rx="2.5" fill="#150b04"/>
<rect x="-18" y="-8" width="36" height="6" rx="2.5" fill="#000000" fill-opacity="0.45"/>
<rect x="-22" y="-12" width="4" height="32" fill="#d9ae42" fill-opacity="0.0"/>
<path d="M-15.5,-12 L-9.5,-12 L-9.5,-8 L-15.5,-8 Z M9.5,-12 L15.5,-12 L15.5,-8 L9.5,-8 Z M-15.5,16 L-9.5,16 L-9.5,20 L-15.5,20 Z M9.5,16 L15.5,16 L15.5,20 L9.5,20 Z" fill="#d9ae42" stroke="#6e4f10" stroke-width="0.8"/>
<rect x="-22" y="-12" width="44" height="32" rx="3.5" fill="none" stroke="#c98d47" stroke-width="1.2" stroke-opacity="0.7"/>
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
