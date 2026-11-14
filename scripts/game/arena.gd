class_name Arena
extends Node2D
## The battlefield: a clearing in the woods. Knows the playable rectangle,
## the obstacles (rocks and stumps) and draws the ring of trees that hides
## zombies until they walk in.

var rect: Rect2
var obs_pos := PackedVector2Array()
var obs_radius := PackedFloat32Array()
var _obs_sprite := PackedStringArray()
var _obs_rot := PackedFloat32Array()

var canopy: DrawLayer          # tree tops, drawn above everything in the world
var tree_tint := Color(1, 1, 1)   # the map's colour for the tree tops
var _trees: Array = []         # [pos, scale, rotation, tint]


func _init() -> void:
	rect = Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	_generate_obstacles()
	_generate_trees()
	canopy = DrawLayer.new()
	canopy.painter = _paint_canopy


func _generate_obstacles() -> void:
	var center := rect.get_center()
	var tries := 0
	while obs_pos.size() < Config.OBSTACLE_COUNT and tries < 600:
		tries += 1
		var radius := randf_range(Config.OBSTACLE_RADIUS_MIN, Config.OBSTACLE_RADIUS_MAX)
		var pos := Vector2(
			randf_range(rect.position.x + 190.0, rect.end.x - 190.0),
			randf_range(rect.position.y + 190.0, rect.end.y - 190.0))
		if pos.distance_to(center) < 300.0:
			continue   # keep the player's starting spot open
		var ok := true
		for i in obs_pos.size():
			# Spaced well apart so hordes can always flow around them.
			if pos.distance_to(obs_pos[i]) < radius + obs_radius[i] + 240.0:
				ok = false
				break
		if not ok:
			continue
		obs_pos.append(pos)
		obs_radius.append(radius)
		_obs_sprite.append("rock" if randf() < 0.65 else "stump")
		_obs_rot.append(randf() * TAU)


func _generate_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var tints := [Color(1, 1, 1), Color(0.86, 0.92, 0.86), Color(1.0, 1.0, 0.9), Color(0.8, 0.86, 0.8)]
	# Two rows of tree tops around the clearing. The inner row just touches
	# the edge; the outer row covers the area where zombies spawn.
	for row in 2:
		var dist := 100.0 + row * 150.0
		var spacing := 118.0
		var w := rect.size.x
		var h := rect.size.y
		var x := -dist - 60.0
		while x <= w + dist + 60.0:
			_add_tree(rng, Vector2(x, -dist), row, tints)
			_add_tree(rng, Vector2(x, h + dist), row, tints)
			x += spacing
		var y := -dist + spacing
		while y <= h + dist - spacing:
			_add_tree(rng, Vector2(-dist, y), row, tints)
			_add_tree(rng, Vector2(w + dist, y), row, tints)
			y += spacing


func _add_tree(rng: RandomNumberGenerator, pos: Vector2, row: int, tints: Array) -> void:
	var jitter := 14.0 if row == 0 else 40.0
	var p := pos + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter) * (0.4 if row == 0 else 1.0))
	var s := rng.randf_range(0.92, 1.06) if row == 0 else rng.randf_range(1.1, 1.5)
	_trees.append([p, s, rng.randf() * TAU, tints[rng.randi() % tints.size()]])


func _draw() -> void:
	for i in obs_pos.size():
		var s := obs_radius[i] / 47.0
		draw_set_transform(obs_pos[i], _obs_rot[i], Vector2(s, s))
		Art.draw(self, _obs_sprite[i], Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_canopy(ci: CanvasItem) -> void:
	for tree: Array in _trees:
		var s: float = tree[1]
		ci.draw_set_transform(tree[0], tree[2], Vector2(s, s))
		Art.draw(ci, "canopy", Vector2.ZERO, 1.0, (tree[3] as Color) * tree_tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------
#  Collision helpers (plain maths - no physics engine needed)
# ----------------------------------------------------------------------------
## Push a circle out of every obstacle and keep it inside the arena.
func resolve(pos: Vector2, radius: float) -> Vector2:
	for i in obs_pos.size():
		pos = push_out_of(i, pos, radius)
	return clamp_inside(pos, radius)


## Push a circle out of one obstacle.
func push_out_of(index: int, pos: Vector2, radius: float) -> Vector2:
	var center := obs_pos[index]
	var diff := pos - center
	var min_dist := radius + obs_radius[index]
	var d2 := diff.length_squared()
	if d2 < min_dist * min_dist:
		if d2 < 0.0001:
			diff = Vector2.RIGHT
			d2 = 1.0
		return center + diff * (min_dist / sqrt(d2))
	return pos


func clamp_inside(pos: Vector2, radius: float) -> Vector2:
	pos.x = clampf(pos.x, rect.position.x + radius, rect.end.x - radius)
	pos.y = clampf(pos.y, rect.position.y + radius, rect.end.y - radius)
	return pos


## Where does the segment from->to first touch an obstacle?
## Returns 0..1 along the segment, or 2.0 if it touches nothing.
func segment_hit(from: Vector2, to: Vector2) -> float:
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 0.0001:
		return 2.0
	var best := 2.0
	for i in obs_pos.size():
		var c := obs_pos[i]
		var r := obs_radius[i] - 5.0
		var t := clampf((c - from).dot(seg) / len2, 0.0, 1.0)
		var d2 := (from + seg * t).distance_squared_to(c)
		if d2 <= r * r:
			var enter := maxf(t - sqrt(r * r - d2) / sqrt(len2), 0.0)
			if enter < best:
				best = enter
	return best


## True if a circle at `pos` overlaps no obstacle (used to place pickups).
func is_free(pos: Vector2, radius: float) -> bool:
	if not rect.grow(-radius).has_point(pos):
		return false
	for i in obs_pos.size():
		if pos.distance_to(obs_pos[i]) < radius + obs_radius[i]:
			return false
	return true


## A random free spot inside the arena, `margin` px away from the edge.
func random_free_point(radius: float, margin: float = 80.0) -> Vector2:
	for _i in 30:
		var p := Vector2(
			randf_range(rect.position.x + margin, rect.end.x - margin),
			randf_range(rect.position.y + margin, rect.end.y - margin))
		if is_free(p, radius):
			return p
	return rect.get_center()


## A random point outside the clearing, hidden under the trees, where zombies appear.
func random_spawn_point() -> Vector2:
	var d := randf_range(Config.SPAWN_DIST_MIN, Config.SPAWN_DIST_MAX)
	var w := rect.size.x
	var h := rect.size.y
	var t := randf() * 2.0 * (w + h)
	if t < w:
		return Vector2(t, -d)
	t -= w
	if t < h:
		return Vector2(w + d, t)
	t -= h
	if t < w:
		return Vector2(t, h + d)
	return Vector2(-d, t - w)
