class_name Arena
extends Node2D
## The battlefield: one big clearing in the woods, larger than the screen.
## Knows the playable rectangle, the obstacles (rocks and stumps), the pond in
## the middle, and draws the ring of trees around the edge.
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

# The pond in the middle (Config: THE POND). Its shore is an oval with an uneven edge.
static var ponds := true       # (the tests can switch every pond off)
var pond := false              # this map has one
var pond_at := Vector2.ZERO    # its middle
var pond_half := Vector2.ZERO  # half its width and height
var pond_box := Vector2.ZERO   # ...with the uneven edge: nothing of it is further from its middle than this
var _pond_a := 0.0             # how its shore is uneven (two waves round it start at these angles)
var _pond_b := 0.0
var start := Vector2.ZERO      # where the player starts: the middle of the map, or the pond's southern shore
var shore_turn := 0.0          # which way round the pond the last walker asked about went (1 / -1; 0 = it was not at the shore)

var canopy: DrawLayer          # tree tops, drawn above everything in the world
var tree_tint := Color(1, 1, 1)   # the map's colour for the tree tops
var _trees: Array = []         # [pos, scale, rotation, tint]


## `layout_seed` decides where the rocks are (0 = different every time).
## In co-op the host makes the map and sends the joiners the finished list of
## rocks (`given_rocks`, see rocks()): a Mac and a PC do not always round
## numbers the same way, so each working the rocks out for itself could end
## up with two different maps.
## `with_pond` = this map has a pond; a joiner gets the host's as `given_pond` (see pond_data()).
func _init(size: Vector2 = Config.ARENA_SIZE, layout_seed: int = 0, given_rocks: Variant = null,
		with_pond: bool = false, given_pond: Variant = null) -> void:
	rect = Rect2(Vector2.ZERO, size)
	start = rect.get_center()
	if given_rocks is Array:
		_set_pond(given_pond if given_pond is Array else [])
		_set_obstacles(given_rocks)
	else:
		if with_pond and ponds:
			_set_pond([start.x, start.y, Config.POND_SIZE.x * 0.5, Config.POND_SIZE.y * 0.5, randf() * TAU, randf() * TAU])
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
	var wanted := int(round(rect.get_area() / 1000000.0 * Config.OBSTACLES_PER_MILLION))
	var tries := 0
	while obs_pos.size() < wanted and tries < wanted * 80:
		tries += 1
		var radius := rng.randf_range(Config.OBSTACLE_RADIUS_MIN, Config.OBSTACLE_RADIUS_MAX)
		var pos := Vector2(
			rng.randf_range(rect.position.x + 190.0, rect.end.x - 190.0),
			rng.randf_range(rect.position.y + 190.0, rect.end.y - 190.0))
		if pos.distance_to(start) < Config.OBSTACLE_START_CLEAR or in_water(pos, radius + Config.POND_KEEP_CLEAR):
			continue   # keep the player's starting spot open, and the way round the pond
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


## (co-op) Every rock as plain numbers, for the host to send to the joiners:
## [[x, y, radius, 1 if it is a stump, rotation], ...]
func rocks() -> Array:
	var list: Array = []
	for i in obs_pos.size():
		list.append([obs_pos[i].x, obs_pos[i].y, obs_radius[i], 1 if _obs_sprite[i] == "stump" else 0, _obs_rot[i]])
	return list


## (co-op) Put the rocks exactly where the host's list says.
func _set_obstacles(list: Array) -> void:
	for entry: Variant in list:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 5:
			continue
		var rock: Array = entry
		var at := Vector2(float(rock[0]), float(rock[1]))
		if not rect.has_point(at):
			continue
		obs_pos.append(at)
		obs_radius.append(clampf(float(rock[2]), 10.0, 200.0))
		_obs_sprite.append("stump" if int(rock[3]) == 1 else "rock")
		_obs_rot.append(float(rock[4]))


# ----------------------------------------------------------------------------
#  The pond
# ----------------------------------------------------------------------------
## (co-op) The pond as plain numbers, for the host to send to the joiners:
## [x, y, half its width, half its height, the two angles of its uneven edge] - or [] for none.
func pond_data() -> Array:
	return [pond_at.x, pond_at.y, pond_half.x, pond_half.y, _pond_a, _pond_b] if pond else []


func _set_pond(data: Array) -> void:
	if data.size() < 6:
		return
	var at := Vector2(float(data[0]), float(data[1]))
	var half := Vector2(clampf(float(data[2]), 40.0, rect.size.x * 0.4), clampf(float(data[3]), 40.0, rect.size.y * 0.4))
	if not rect.grow(-half.x).has_point(at):
		return
	pond = true
	pond_at = at
	pond_half = half
	pond_box = half * (1.0 + Config.POND_WOBBLE)
	_pond_a = float(data[4])
	_pond_b = float(data[5])
	start = Vector2(at.x, minf(at.y + pond_box.y + Config.POND_START_GAP, rect.end.y - 60.0))


## How far the shore is from the pond's middle in the direction `angle`.
func pond_edge(angle: float) -> float:
	var co := cos(angle) * pond_half.y
	var si := sin(angle) * pond_half.x
	var oval := pond_half.x * pond_half.y / sqrt(co * co + si * si)
	return oval * (1.0 + Config.POND_WOBBLE * (0.6 * sin(3.0 * angle + _pond_a) + 0.4 * sin(5.0 * angle + _pond_b)))


## The point of the shore in the direction `angle` from the pond's middle (`grow` px further out).
func pond_point(angle: float, grow: float = 0.0) -> Vector2:
	return pond_at + Vector2.from_angle(angle) * (pond_edge(angle) + grow)


## The shore as a ring of points (for drawing it; `grow` px outside the water's edge, `shrink` = toward the middle).
func pond_outline(steps: int, grow: float = 0.0, shrink: float = 1.0) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		ring.append(pond_at + Vector2.from_angle(angle) * (pond_edge(angle) * shrink + grow))
	return ring


## Is this spot in the water (or closer to it than `margin`)?
func in_water(pos: Vector2, margin: float = 0.0) -> bool:
	if not pond:
		return false
	var d := pos - pond_at
	if absf(d.x) > pond_box.x + margin or absf(d.y) > pond_box.y + margin:
		return false
	return d.length() < pond_edge(d.angle()) + margin


## Push a circle out of the pond, straight away from its middle.
func out_of_water(pos: Vector2, radius: float) -> Vector2:
	if not pond:
		return pos
	var d := pos - pond_at
	if absf(d.x) > pond_box.x + radius or absf(d.y) > pond_box.y + radius:
		return pos
	var dist := d.length()
	if dist < 0.01:
		d = Vector2.DOWN
		dist = 1.0
	var edge := pond_edge(d.angle()) + radius
	return pos if dist >= edge else pond_at + d * (edge / dist)


## A walker whose step from `from` to `to` would take it into the pond walks along the
## shore instead, round to `toward` (where it wants to get: the player). Which way round:
## the shorter one - or, when both are about as long, `side` (1 / -1) - and then it KEEPS
## to that way (`keep`: 1 / -1, or 0 if it has only just reached the shore) unless the
## other has become clearly shorter. The way it took is left in `shore_turn` for the
## caller to remember (0 = it was not at the shore).
## Without this a zombie pressing against the shore would hardly move - and one that
## chose anew at every dent of the shore would walk to and fro.
func along_shore(from: Vector2, to: Vector2, radius: float, toward: Vector2, keep: float, side: float) -> Vector2:
	shore_turn = 0.0
	if not pond:
		return to
	var d := to - pond_at
	if absf(d.x) > pond_box.x + radius or absf(d.y) > pond_box.y + radius:
		return to
	var dist := d.length()
	var angle := d.angle()
	if dist >= pond_edge(angle) + radius:
		return to
	var length := (to - from).length()
	if length < 0.001 or dist < 0.01:
		return out_of_water(to, radius)
	# How far round the pond it is to there: -PI..PI, + = the way the angle rises.
	var round_to := angle_difference(angle, (toward - pond_at).angle())
	var way := keep
	if keep == 0.0:
		way = signf(round_to) if absf(round_to) < PI - 0.35 and round_to != 0.0 else side
	elif signf(round_to) == -keep and absf(round_to) < 2.0:
		way = -keep
	shore_turn = way
	var shore := (pond_point(angle + 0.03) - pond_point(angle - 0.03)).normalized()
	return out_of_water(from + shore * (length * way), radius)


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
## Push a circle out of every obstacle and out of the pond, and keep it inside the arena.
func resolve(pos: Vector2, radius: float) -> Vector2:
	for i: int in _near(pos):
		pos = push_out_of(i, pos, radius)
	return clamp_inside(out_of_water(pos, radius), radius)


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
	if not rect.grow(-radius).has_point(pos) or in_water(pos, radius):
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
	return start


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
		if inner.has_point(p) and not in_water(p, Config.POND_SPAWN_CLEAR):
			return p
		a = randf() * TAU
	# Cornered: come from the direction of the middle of the map.
	var toward := rect.get_center() - center
	var dir := toward.normalized() if toward.length_squared() > 1.0 else Vector2.RIGHT
	return clamp_inside(out_of_water(center + dir * min_dist, Config.POND_SPAWN_CLEAR), edge)
