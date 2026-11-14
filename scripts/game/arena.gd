class_name Arena
extends Node2D
## The battlefield: one big clearing in the woods, much larger than the
## screen. Knows the playable rectangle, the obstacles (rocks and stumps) and
## draws the ring of trees around the edge.
##
## There are dozens of obstacles, so they are sorted into coarse squares
## ("buckets"): a bullet or a walker only checks the few rocks near it.

const BUCKET := 256.0          # size of one square of the obstacle lookup
const BUCKET_REACH := 70.0     # a rock is listed in every square this close to it (bigger than any walker)

var rect: Rect2
var obs_pos := PackedVector2Array()
var obs_radius := PackedFloat32Array()
var _obs_sprite := PackedStringArray()
var _obs_rot := PackedFloat32Array()
var _buckets: Array = []       # per square: PackedInt32Array of the obstacles near it
var _bw := 1
var _bh := 1

var canopy: DrawLayer          # tree tops, drawn above everything in the world
var tree_tint := Color(1, 1, 1)   # the map's colour for the tree tops
var _trees: Array = []         # [pos, scale, rotation, tint]


## `layout_seed` decides where the rocks are (0 = different every time). In
## co-op both computers build the map from the same number.
func _init(size: Vector2 = Config.ARENA_SIZE, layout_seed: int = 0) -> void:
	rect = Rect2(Vector2.ZERO, size)
	_generate_obstacles(layout_seed)
	_build_buckets()
	_generate_trees()
	canopy = DrawLayer.new()
	canopy.painter = _paint_canopy


func _generate_obstacles(layout_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	if layout_seed != 0:
		rng.seed = layout_seed
	else:
		rng.randomize()
	var center := rect.get_center()
	var wanted := int(round(rect.get_area() / 1000000.0 * Config.OBSTACLES_PER_MILLION))
	var tries := 0
	while obs_pos.size() < wanted and tries < wanted * 80:
		tries += 1
		var radius := rng.randf_range(Config.OBSTACLE_RADIUS_MIN, Config.OBSTACLE_RADIUS_MAX)
		var pos := Vector2(
			rng.randf_range(rect.position.x + 190.0, rect.end.x - 190.0),
			rng.randf_range(rect.position.y + 190.0, rect.end.y - 190.0))
		if pos.distance_to(center) < Config.OBSTACLE_START_CLEAR:
			continue   # keep the player's starting spot open
		var ok := true
		for i in obs_pos.size():
			# Spaced well apart so hordes can always flow around them.
			if pos.distance_to(obs_pos[i]) < radius + obs_radius[i] + Config.OBSTACLE_SPACING:
				ok = false
				break
		if not ok:
			continue
		obs_pos.append(pos)
		obs_radius.append(radius)
		_obs_sprite.append("rock" if rng.randf() < 0.65 else "stump")
		_obs_rot.append(rng.randf() * TAU)


## Sort the obstacles into squares, so nobody has to check all of them.
func _build_buckets() -> void:
	_bw = maxi(int(ceil(rect.size.x / BUCKET)), 1)
	_bh = maxi(int(ceil(rect.size.y / BUCKET)), 1)
	_buckets.resize(_bw * _bh)
	for i in _buckets.size():
		_buckets[i] = PackedInt32Array()
	for i in obs_pos.size():
		var c := obs_pos[i] - rect.position
		var reach := obs_radius[i] + BUCKET_REACH
		var x0 := clampi(int((c.x - reach) / BUCKET), 0, _bw - 1)
		var x1 := clampi(int((c.x + reach) / BUCKET), 0, _bw - 1)
		var y0 := clampi(int((c.y - reach) / BUCKET), 0, _bh - 1)
		var y1 := clampi(int((c.y + reach) / BUCKET), 0, _bh - 1)
		for by in range(y0, y1 + 1):
			for bx in range(x0, x1 + 1):
				var list: PackedInt32Array = _buckets[by * _bw + bx]
				list.append(i)
				_buckets[by * _bw + bx] = list


## The obstacles near a point.
func _near(pos: Vector2) -> PackedInt32Array:
	var bx := clampi(int((pos.x - rect.position.x) / BUCKET), 0, _bw - 1)
	var by := clampi(int((pos.y - rect.position.y) / BUCKET), 0, _bh - 1)
	return _buckets[by * _bw + bx]


func _generate_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var tints := [Color(1, 1, 1), Color(0.86, 0.92, 0.86), Color(1.0, 1.0, 0.9), Color(0.8, 0.86, 0.8)]
	# Two rows of tree tops around the clearing: the inner row just touches
	# the edge, the outer row fills the view beyond it.
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
	for i: int in _near(pos):
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
	# Only the squares the segment passes through (a bullet moves a few pixels
	# per frame, so that is nearly always one square).
	var x0 := clampi(int((minf(from.x, to.x) - rect.position.x) / BUCKET), 0, _bw - 1)
	var x1 := clampi(int((maxf(from.x, to.x) - rect.position.x) / BUCKET), 0, _bw - 1)
	var y0 := clampi(int((minf(from.y, to.y) - rect.position.y) / BUCKET), 0, _bh - 1)
	var y1 := clampi(int((maxf(from.y, to.y) - rect.position.y) / BUCKET), 0, _bh - 1)
	var best := 2.0
	var inv_len := 1.0 / sqrt(len2)
	for by in range(y0, y1 + 1):
		for bx in range(x0, x1 + 1):
			for i: int in _buckets[by * _bw + bx]:
				var c := obs_pos[i]
				var r := obs_radius[i] - 5.0
				var t := clampf((c - from).dot(seg) / len2, 0.0, 1.0)
				var d2 := (from + seg * t).distance_squared_to(c)
				if d2 <= r * r:
					var enter := maxf(t - sqrt(r * r - d2) * inv_len, 0.0)
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


## A free spot between `min_dist` and `max_dist` from `center` (for things
## that should land near the player, wherever on the map that is).
func random_free_point_near(center: Vector2, min_dist: float, max_dist: float, radius: float, margin: float = 80.0) -> Vector2:
	var inner := rect.grow(-margin)
	for _i in 40:
		var p := center + Vector2.from_angle(randf() * TAU) * randf_range(min_dist, max_dist)
		if inner.has_point(p) and is_free(p, radius):
			return p
	# Cornered: take a spot toward the middle of the map.
	var toward := rect.get_center() - center
	var dir := toward.normalized() if toward.length_squared() > 1.0 else Vector2.RIGHT
	return resolve(clamp_inside(center + dir * min_dist, margin), radius)


## Where a pack of zombies comes out of the ground: between `min_dist` and
## `max_dist` from `center` (the player), in the direction `angle` if the map
## has room there, otherwise in any direction that does.
func spawn_point_around(center: Vector2, min_dist: float, max_dist: float, angle: float, edge: float = 40.0) -> Vector2:
	var inner := rect.grow(-edge)
	var a := angle
	for _i in 18:
		var p := center + Vector2.from_angle(a) * randf_range(min_dist, max_dist)
		if inner.has_point(p):
			return p
		a = randf() * TAU
	# Cornered: come from the direction of the middle of the map.
	var toward := rect.get_center() - center
	var dir := toward.normalized() if toward.length_squared() > 1.0 else Vector2.RIGHT
	return clamp_inside(center + dir * min_dist, edge)
