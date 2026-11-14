class_name SkillTreeView
extends TreeView
## Draws the skill tree: three colour families growing out of the middle.
## Every node shows its levels as a row of small dots, the lines you have
## invested in are lit in the family's colour, and each family's name carries
## the number of skill points put into it - so it is always clear where the
## points went.
##
## Moving around, pointing and clicking come from TreeView. Each node given
## to set_tree() also has: "kind" (see skill_tree.gd), "parents" (ids of the
## nodes it grows from).

## Levels bought and levels available for every node: id -> Vector2i(bought, of); of = 0 means endless.
var levels := {}
## One entry per family: {"name", "desc", "color", "points", "label" (where its name goes), "haze" (its middle)}.
var families: Array = []


func set_levels(node_levels: Dictionary, family_info: Array) -> void:
	levels = node_levels
	families = family_info
	queue_redraw()


## Show the whole tree.
func fit() -> void:
	if size.x < 10.0 or size.y < 10.0 or _order.is_empty():
		return
	var box := Rect2(Vector2.ZERO, Vector2.ZERO)
	for id: String in _order:
		box = box.expand(_nodes[id]["pos"])
	for f: Dictionary in families:
		box = box.expand(f["label"])
	# (Room at the top for a notice and at the bottom for the last label and the hint.)
	box = box.grow(70.0).grow_individual(0.0, 46.0, 0.0, 46.0)
	look_at_point(box.get_center(), minf(size.x / box.size.x, size.y / box.size.y))


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.026, 0.03, 0.03, 0.98))
	draw_set_transform(size * 0.5 - _cam * zoom, 0.0, Vector2(zoom, zoom))
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var glow := Art.t("glow")

	# A soft haze of the family's colour behind each family (stronger once
	# points are in it), and two quiet rings around the middle.
	for f: Dictionary in families:
		var c: Color = f["color"]
		var haze := 620.0
		var strength := 0.06 + 0.12 * clampf(float(f["points"]) / 40.0, 0.0, 1.0)
		draw_texture_rect(glow, Rect2((f["haze"] as Vector2) - Vector2(haze, haze) * 0.5, Vector2(haze, haze)), false, Color(c.r, c.g, c.b, strength))
	for radius: float in [Config.TREE_ROOT_DIST, Config.TREE_ROOT_DIST + Config.TREE_STEP * 3.0]:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(1, 1, 1, 0.045), 1.5 / zoom, true)

	# Lines: lit where points have been spent.
	for id: String in _order:
		var n: Dictionary = _nodes[id]
		var to: Vector2 = n["pos"]
		var c: Color = n["color"]
		var bought := int((levels.get(id, Vector2i.ZERO) as Vector2i).x)
		var state := int(_states.get(id, FAR))
		for parent: String in n["parents"]:
			if not _nodes.has(parent):
				continue
			var from: Vector2 = _nodes[parent]["pos"]
			var parent_bought := int((levels.get(parent, Vector2i(1, 1)) as Vector2i).x)
			if bought > 0 and parent_bought > 0:
				draw_line(from, to, Color(c.r, c.g, c.b, 0.28), 11.0)
				draw_line(from, to, c.lightened(0.2), 4.5)
			elif state == READY and parent_bought > 0:
				draw_line(from, to, Color(c.r, c.g, c.b, 0.4 + 0.4 * pulse), 3.5)
			elif state == POOR and parent_bought > 0:
				draw_line(from, to, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.7), 3.0)
			else:
				draw_line(from, to, Color(0.34, 0.36, 0.34, 0.6), 2.0)

	# Nodes.
	for id: String in _order:
		var n: Dictionary = _nodes[id]
		var pos: Vector2 = n["pos"]
		var r := float(n["radius"])
		var state := int(_states.get(id, FAR))
		var color: Color = n["color"]
		var shape := String(n["shape"])
		var level: Vector2i = levels.get(id, Vector2i(0, 1))
		var body := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0)
		var fill := Color(0.1, 0.11, 0.1)
		var ring := Color(0.32, 0.34, 0.32)
		var icon_color := Color(0.46, 0.48, 0.46)
		var partly := level.x > 0 and state != OWNED
		if state == OWNED:
			draw_texture_rect(glow, body.grow(r * 1.15), false, Color(color.r, color.g, color.b, 0.55))
			fill = color
			ring = color.lightened(0.5)
			icon_color = Color(0.05, 0.05, 0.05, 0.88)
		elif partly:
			draw_texture_rect(glow, body.grow(r * 0.9), false, Color(color.r, color.g, color.b, 0.3))
			fill = Color(color.r * 0.34, color.g * 0.34, color.b * 0.34)
			ring = color.lightened(0.15 + (0.25 * pulse if state == READY else 0.0))
			icon_color = color.lightened(0.45)
		elif state == READY:
			draw_texture_rect(glow, body.grow(r * (0.9 + 0.5 * pulse)), false, Color(color.r, color.g, color.b, 0.3 + 0.35 * pulse))
			fill = Color(color.r * 0.22, color.g * 0.22, color.b * 0.22)
			ring = color.lightened(0.1 + 0.3 * pulse)
			icon_color = color.lightened(0.3)
		elif state == POOR:
			fill = Color(color.r * 0.16, color.g * 0.16, color.b * 0.16)
			ring = Color(color.r * 0.7, color.g * 0.7, color.b * 0.7)
			icon_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8)
		elif state == LOCKED:
			fill = Color(0.09, 0.09, 0.09)
			ring = Color(color.r * 0.3 + 0.12, color.g * 0.3 + 0.12, color.b * 0.3 + 0.12)
			icon_color = Color(0.5, 0.5, 0.5)
		else:
			fill = Color(color.r * 0.1 + 0.05, color.g * 0.1 + 0.05, color.b * 0.1 + 0.05)
			ring = Color(color.r * 0.36 + 0.1, color.g * 0.36 + 0.1, color.b * 0.36 + 0.1)
			icon_color = Color(color.r * 0.5 + 0.1, color.g * 0.5 + 0.1, color.b * 0.5 + 0.1)
		draw_texture_rect(Art.t("node_fill" if shape == "circle" else "node_" + shape), body, false, fill)
		draw_texture_rect(Art.t("node_ring" if shape == "circle" else "node_%s_ring" % shape), body, false, ring)
		if String(n["kind"]) == "cap":
			# The family emblem wears a second ring.
			draw_texture_rect(Art.t("node_ring"), body.grow(7.0), false, Color(ring.r, ring.g, ring.b, 0.55))
		var icon := "ui_lock" if state == LOCKED else String(n["icon"])
		if icon != "":
			var s := r * (1.05 if shape == "circle" else 0.9)
			draw_texture_rect(Art.t(icon), Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), false, icon_color)
		# Levels: a row of dots under the node (a number for the endless one).
		if level.y > 1:
			var spacing := 9.5
			var start := pos + Vector2(-spacing * float(level.y - 1) * 0.5, r + 10.0)
			for i in level.y:
				var dot := start + Vector2(spacing * float(i), 0.0)
				draw_circle(dot, 3.6, Color(0, 0, 0, 0.75))
				draw_circle(dot, 2.6, color.lightened(0.25) if i < level.x else Color(0.3, 0.32, 0.3))
		elif level.y == 0 and level.x > 0:
			draw_string(font, pos + Vector2(-60.0, r + 24.0), "x%d" % level.x, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 17, Color(1, 1, 1, 0.92))

	# Family names, with what has been put into each.
	for f: Dictionary in families:
		var c: Color = f["color"]
		var at: Vector2 = f["label"]
		var points := int(f["points"])
		draw_string(font, at + Vector2(-200.0, 0.0), String(f["name"]), HORIZONTAL_ALIGNMENT_CENTER, 400.0, 34, c)
		draw_string(font, at + Vector2(-200.0, 22.0), String(f["desc"]), HORIZONTAL_ALIGNMENT_CENTER, 400.0, 15, Color(1, 1, 1, 0.5))
		draw_string(font, at + Vector2(-200.0, 46.0), "%d point%s invested" % [points, "" if points == 1 else "s"], HORIZONTAL_ALIGNMENT_CENTER,
				400.0, 17, Color(1, 1, 1, 0.9) if points > 0 else Color(1, 1, 1, 0.4))

	# The highlighted node.
	if _nodes.has(selected):
		var n: Dictionary = _nodes[selected]
		var r := float(n["radius"]) + 9.0 + 2.5 * pulse
		draw_texture_rect(Art.t("ring"), Rect2((n["pos"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1, 1, 1, 0.95) if has_focus() else Color(1, 1, 1, 0.55))

	for b: Array in _bursts:
		var age := float(b[2]) / 0.7
		var burst_color: Color = b[1]
		var br := 20.0 + 150.0 * (1.0 - (1.0 - age) * (1.0 - age))
		draw_texture_rect(Art.t("ring"), Rect2((b[0] as Vector2) - Vector2(br, br), Vector2(br, br) * 2.0), false,
				Color(burst_color.r, burst_color.g, burst_color.b, 1.0 - age))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var help := hint_gamepad if GameInput.using_gamepad() else hint
	if help != "":
		draw_string(font, Vector2(14.0, size.y - 12.0), help, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.45))
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), UiKit.GOLD if has_focus() else Color("3f4634"), false, 2.0)
