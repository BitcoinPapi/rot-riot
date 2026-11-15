class_name Pond
extends Node2D
## The pond in the middle of the map, as you see it: wet earth round the edge,
## shallow water, a deep middle, reeds and stones on the shore, lily pads,
## fish under the surface, rings and glints on the water.
##
## It lies over the ground and its blood, and under everything that walks: a
## body or a shell case that ends up in the pond is simply gone under water.
## Where the pond IS, and that nobody can walk into it, is the map's business
## (Arena: pond_edge, out_of_water, along_shore). All numbers: Config, THE POND.

var game: Game
var _arena: Arena
var _time := 0.0
var _shore := PackedVector2Array()      # the wet earth round the water
var _rim := PackedVector2Array()        # the water's edge
var _water := PackedVector2Array()
var _deep := PackedVector2Array()
var _edge_line := PackedVector2Array()  # the water's edge again, closed, for the bright line along it
var _reeds: Array = []                  # [where, turned, size]
var _stones: Array = []                 # [where, turned, size]
var _lilies: Array = []                 # [where, turned, size, has a flower, how far through its bobbing]
var _fish: Array = []                   # [middle of its loop, how wide, how tall, where on the loop, which way round, size]
var _rings: Array = []                  # [where, how far through its life 0..1]
var _glints: Array = []                 # [where, length, how far through its twinkle]


func setup(owner_game: Game) -> void:
	game = owner_game
	_arena = game.arena
	var steps := 72
	_shore = _arena.pond_outline(steps, Config.POND_SHORE_WIDTH)
	_rim = _arena.pond_outline(steps)
	_water = _arena.pond_outline(steps, 0.0, 0.84)
	_deep = _arena.pond_outline(steps, 0.0, 0.58)
	_edge_line = _rim.duplicate()
	_edge_line.append(_rim[0])
	# What grows and lies where: the same for everybody who plays this run (it follows
	# from the pond's own shape, which the host sends).
	var rng := RandomNumberGenerator.new()
	var data := _arena.pond_data()
	rng.seed = int(float(data[4]) * 100000.0) + int(float(data[5]) * 1000.0) + 17
	for i in Config.POND_REEDS:
		var angle := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(Config.POND_REEDS)
		_reeds.append([_arena.pond_point(angle, rng.randf_range(-10.0, 9.0)), rng.randf() * TAU, rng.randf_range(0.8, 1.3)])
	for i in Config.POND_STONES:
		var angle := rng.randf() * TAU
		_stones.append([_arena.pond_point(angle, rng.randf_range(-6.0, 12.0)), rng.randf() * TAU, rng.randf_range(0.7, 1.4)])
	for i in Config.POND_LILIES:
		var angle := rng.randf() * TAU
		var out := rng.randf_range(0.5, 0.86)
		_lilies.append([_arena.pond_at + Vector2.from_angle(angle) * (_arena.pond_edge(angle) * out), rng.randf() * TAU,
				rng.randf_range(0.8, 1.35), rng.randf() < 0.4, rng.randf()])
	for i in Config.POND_FISH:
		_fish.append([_arena.pond_at + Vector2(rng.randf_range(-0.25, 0.25) * _arena.pond_half.x, rng.randf_range(-0.2, 0.2) * _arena.pond_half.y),
				_arena.pond_half.x * rng.randf_range(0.28, 0.5), _arena.pond_half.y * rng.randf_range(0.25, 0.45),
				rng.randf(), 1.0 if rng.randf() < 0.5 else -1.0, rng.randf_range(0.8, 1.3)])
	for i in Config.POND_RIPPLES:
		_rings.append([_spot_on_water(), float(i) / float(Config.POND_RIPPLES)])
	for i in Config.POND_GLINTS:
		_glints.append([_spot_on_water(), randf_range(5.0, 12.0), randf()])


## Somewhere on the water, not too near the shore.
func _spot_on_water() -> Vector2:
	var angle := randf() * TAU
	return _arena.pond_at + Vector2.from_angle(angle) * (_arena.pond_edge(angle) * sqrt(randf()) * 0.8)


func _process(delta: float) -> void:
	_time += delta
	for ring: Array in _rings:
		ring[1] = float(ring[1]) + delta / Config.POND_RIPPLE_TIME
		if float(ring[1]) >= 1.0:
			ring[0] = _spot_on_water()
			ring[1] = 0.0
	for glint: Array in _glints:
		glint[2] = float(glint[2]) + delta * 0.45
		if float(glint[2]) >= 1.0:
			glint[0] = _spot_on_water()
			glint[2] = 0.0
	for fish: Array in _fish:
		fish[3] = float(fish[3]) + delta * Config.POND_FISH_SPEED * float(fish[4]) / float(fish[5])
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(_shore, Config.POND_SHORE_COLOR)
	draw_colored_polygon(_rim, Config.POND_RIM_COLOR)
	draw_colored_polygon(_water, Config.POND_WATER_COLOR)
	draw_colored_polygon(_deep, Config.POND_DEEP_COLOR)
	draw_polyline(_edge_line, Config.POND_EDGE_COLOR, 2.0, true)

	# Fish: dark shapes going round under the surface, tails wagging.
	for fish: Array in _fish:
		var at := TAU * float(fish[3])
		var spot: Vector2 = (fish[0] as Vector2) + Vector2(cos(at) * float(fish[1]), sin(at) * float(fish[2]))
		var heading := Vector2(-sin(at) * float(fish[1]), cos(at) * float(fish[2])) * float(fish[4])
		var size := float(fish[5])
		draw_set_transform(spot, heading.angle() + sin(_time * 7.0 + float(fish[5]) * 9.0) * 0.18, Vector2(size, size))
		Art.draw(self, "pond_fish", Vector2.ZERO)

	# Rings spreading and glints twinkling (left out with FEWER EFFECTS).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not bool(SaveData.get_setting("fewer_effects")):
		var shine: Color = Config.POND_SHINE_COLOR
		for ring: Array in _rings:
			var age := float(ring[1])
			var fade := sin(age * PI)
			draw_arc(ring[0], 3.0 + age * Config.POND_RIPPLE_SIZE, 0.0, TAU, 28, Color(shine.r, shine.g, shine.b, shine.a * fade), 1.4, true)
			if age > 0.25:
				draw_arc(ring[0], 3.0 + (age - 0.25) * Config.POND_RIPPLE_SIZE, 0.0, TAU, 24, Color(shine.r, shine.g, shine.b, shine.a * fade * 0.6), 1.1, true)
		for glint: Array in _glints:
			var twinkle := sin(float(glint[2]) * PI)
			var from: Vector2 = glint[0]
			draw_line(from, from + Vector2(float(glint[1]), 0.0), Color(shine.r, shine.g, shine.b, shine.a * twinkle), 1.3, true)

	# Lily pads rocking gently, some with a flower.
	for pad: Array in _lilies:
		var rock := sin(_time * 0.9 + float(pad[4]) * TAU)
		var size := float(pad[2])
		draw_set_transform((pad[0] as Vector2) + Vector2(rock * 1.2, 0.0), float(pad[1]) + rock * 0.06, Vector2(size, size))
		Art.draw(self, "pond_lily", Vector2.ZERO)
		if bool(pad[3]):
			Art.draw(self, "pond_flower", Vector2(2.0, -1.0))

	# The shore: wet stones, and reeds swaying in the wind.
	for stone: Array in _stones:
		var size := float(stone[2])
		draw_set_transform(stone[0], float(stone[1]), Vector2(size, size))
		Art.draw(self, "pond_stone", Vector2.ZERO)
	for reed: Array in _reeds:
		var size := float(reed[2])
		var at: Vector2 = reed[0]
		draw_set_transform(at, float(reed[1]) + sin(_time * 1.3 + at.x * 0.02) * 0.07, Vector2(size, size))
		Art.draw(self, "pond_reeds", Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
