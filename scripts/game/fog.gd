class_name Fog
extends Node2D
## Fog of war. The map starts hidden under mist; wherever the player has been
## it clears, and stays clear for the rest of the run.
##
## How: the map is divided into squares (Config.FOG_CELL). Each remembers how
## thick the fog over it still is. Those numbers live in one tiny picture -
## one pixel per square - which is stretched over the whole map (stretching
## smooths it, so the edge of the fog is soft). The same picture is drawn
## small by the HUD as the minimap's fog.

const SHADER := """
shader_type canvas_item;
uniform sampler2D mist : repeat_enable, filter_linear;
uniform vec4 dark : source_color;
uniform vec4 pale : source_color;
uniform vec2 tiles = vec2(8.0, 6.0);
uniform float opacity = 0.97;

void fragment() {
	float thick = texture(TEXTURE, UV).a;
	vec2 p = UV * tiles;
	float a = texture(mist, p + vec2(TIME * 0.011, TIME * 0.006)).r;
	float b = texture(mist, p * 0.47 - vec2(TIME * 0.007, -TIME * 0.004)).r;
	float wisp = a * 0.6 + b * 0.4;
	// The mist curls a little way into the cleared ground at the edge.
	float edge = 1.0 - abs(thick * 2.0 - 1.0);
	float cover = clamp(thick + (wisp - 0.5) * 0.5 * edge, 0.0, 1.0);
	COLOR = vec4(mix(dark.rgb, pale.rgb, wisp * wisp * 0.9), cover * opacity);
}
"""

static var _mist: ImageTexture     # the drifting wisps (made once, shared by every run)

var rect := Rect2()                # the part of the world the fog picture covers
var texture: ImageTexture          # white, with the fog's thickness in alpha (the minimap draws it too)
var explored := 0.0                # 0..1: how much of the playable map has been uncovered

var _arena := Rect2()
var _cols := 1
var _rows := 1
var _image: Image
var _thick := PackedByteArray()    # 255 = full fog, 0 = clear
var _last: Array[Vector2] = []     # where each player (by slot) last cleared from
var _map_cells := 0                # squares inside the playable map
var _clear_cells := 0


func setup(arena_rect: Rect2) -> void:
	_arena = arena_rect
	var cell: float = Config.FOG_CELL
	var covered := arena_rect.grow(Config.ARENA_OUTER_MARGIN + cell)
	_cols = int(ceil(covered.size.x / cell))
	_rows = int(ceil(covered.size.y / cell))
	rect = Rect2(covered.position, Vector2(_cols, _rows) * cell)
	_thick.resize(_cols * _rows)
	_thick.fill(255)
	_image = Image.create(_cols, _rows, false, Image.FORMAT_RGBA8)
	_image.fill(Color(1, 1, 1, 1))
	texture = ImageTexture.create_from_image(_image)
	for iy in _rows:
		for ix in _cols:
			if _arena.has_point(_cell_center(ix, iy)):
				_map_cells += 1

	z_index = 60                    # above the tree tops: the fog hides everything in the world
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _mist == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 3
		_mist = ImageTexture.create_from_image(noise.get_seamless_image(256, 256))
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("mist", _mist)
	mat.set_shader_parameter("dark", Config.FOG_COLOR)
	mat.set_shader_parameter("pale", Config.FOG_LIGHT)
	mat.set_shader_parameter("tiles", rect.size / 700.0)
	mat.set_shader_parameter("opacity", Config.FOG_OPACITY)
	material = mat


func _cell_center(ix: int, iy: int) -> Vector2:
	return rect.position + (Vector2(ix, iy) + Vector2(0.5, 0.5)) * Config.FOG_CELL


## Clear the fog around `center` (a player). `size_mult` widens it; `who` is
## that player's slot (alone, the player is 0).
func reveal(center: Vector2, size_mult: float = 1.0, who: int = 0) -> void:
	var cell: float = Config.FOG_CELL
	while _last.size() <= who:
		_last.append(Vector2(INF, INF))
	# Only worth doing again once that player has moved a little.
	if size_mult == 1.0:
		if center.distance_squared_to(_last[who]) < cell * cell * 0.16:
			return
		_last[who] = center
	var inner: float = Config.FOG_CLEAR_RADIUS * size_mult
	var outer: float = Config.FOG_EDGE_RADIUS * size_mult
	var x0 := clampi(int((center.x - outer - rect.position.x) / cell), 0, _cols - 1)
	var x1 := clampi(int((center.x + outer - rect.position.x) / cell), 0, _cols - 1)
	var y0 := clampi(int((center.y - outer - rect.position.y) / cell), 0, _rows - 1)
	var y1 := clampi(int((center.y + outer - rect.position.y) / cell), 0, _rows - 1)
	var changed := false
	for iy in range(y0, y1 + 1):
		var py := rect.position.y + (float(iy) + 0.5) * cell
		for ix in range(x0, x1 + 1):
			var px := rect.position.x + (float(ix) + 0.5) * cell
			var d := sqrt((px - center.x) * (px - center.x) + (py - center.y) * (py - center.y))
			if d >= outer:
				continue
			var now := 0 if d <= inner else int(255.0 * smoothstep(inner, outer, d))
			var index := iy * _cols + ix
			var before := _thick[index]
			if now >= before:
				continue
			_thick[index] = now
			_image.set_pixel(ix, iy, Color(1, 1, 1, float(now) / 255.0))
			changed = true
			if before >= 128 and now < 128 and _arena.has_point(Vector2(px, py)):
				_clear_cells += 1
	if changed:
		texture.update(_image)
		explored = float(_clear_cells) / float(maxi(_map_cells, 1))


## Clear the whole map (for tests and screenshots).
func reveal_all() -> void:
	_thick.fill(0)
	_image.fill(Color(1, 1, 1, 0))
	texture.update(_image)
	_clear_cells = _map_cells
	explored = 1.0


## Has the fog over this spot cleared?
func is_clear(pos: Vector2) -> bool:
	var ix := clampi(int((pos.x - rect.position.x) / Config.FOG_CELL), 0, _cols - 1)
	var iy := clampi(int((pos.y - rect.position.y) / Config.FOG_CELL), 0, _rows - 1)
	return _thick[iy * _cols + ix] < 128


## The part of the fog picture that lies over the playable map, in the
## picture's own pixels (the minimap draws just that part).
func map_region() -> Rect2:
	return Rect2((_arena.position - rect.position) / Config.FOG_CELL, _arena.size / Config.FOG_CELL)


func _draw() -> void:
	draw_texture_rect(texture, rect, false)
