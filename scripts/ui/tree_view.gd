class_name TreeView
extends Control
## A web of upgrade nodes that can be dragged around and zoomed. It only
## shows nodes and reports clicks; what the nodes mean (skill tree, weapon
## tree) is decided by the screen that owns it.
##
## Mouse: drag to move, wheel to zoom, hover to inspect, click to pick.
## Trackpad: two-finger scroll moves, pinch zooms.
## Keyboard / gamepad: arrows or stick jump to the nearest node that way,
## Enter / A picks it.
##
## Each node is a Dictionary:
##   id, pos (Vector2), radius, shape ("circle", "diamond" or "hex"),
##   color, color2 (second colour for hybrids, or the same), icon (Art sprite
##   name or ""), links (ids it is joined to)

signal node_selected(id: String)     # the highlighted node changed
signal node_activated(id: String)    # it was clicked / accepted

# How a node is drawn.
const OWNED := 0      # bright and filled
const READY := 1      # can be bought now: glows
const POOR := 2       # reachable but too expensive: outlined in its colour
const LOCKED := 3     # needs a level or a deed: grey with a padlock
const FAR := 4        # not connected yet: dark

const MIN_ZOOM := 0.26
const MAX_ZOOM := 1.6

var zoom := 0.62
var selected := ""
## Circles around the middle that mark where a requirement starts:
## [{"radius": float, "text": String, "open": bool}]
var guides: Array = []
var hint := "Drag to move   -   scroll to zoom   -   click a glowing node to learn it"
var hint_gamepad := "Stick: next node   -   A: learn   -   Y: other buttons   -   B: back"

var _nodes := {}               # id -> node
var _order: Array = []
var _links: Array = []         # [id, id] once per pair
var _states := {}              # id -> OWNED..FAR
var _badges := {}              # id -> small text under the node
var _cam := Vector2.ZERO       # tree position at the middle of the view
var _cam_target := Vector2.ZERO
var _extent := 600.0
var _dragging := false
var _drag_moved := 0.0
var _press_node := ""
var _time := 0.0
var _nav_wait := 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	mouse_entered.connect(func() -> void:
		if not has_focus():
			grab_focus())


## Give the view its nodes (see the top of this file).
func set_tree(node_list: Array) -> void:
	_nodes = {}
	_order = []
	_links = []
	_extent = 200.0
	for n: Dictionary in node_list:
		var id := String(n["id"])
		_nodes[id] = n
		_order.append(id)
		_extent = maxf(_extent, (n["pos"] as Vector2).length() + 80.0)
	for id: String in _order:
		for other: String in _nodes[id]["links"]:
			if id < other and _nodes.has(other):
				_links.append([id, other])
	if not _nodes.has(selected):
		selected = ""
	queue_redraw()


## How each node looks right now, and the small text under some of them.
func set_states(states: Dictionary, badges: Dictionary = {}) -> void:
	_states = states
	_badges = badges
	queue_redraw()


func select(id: String, centre: bool = false) -> void:
	if not _nodes.has(id):
		return
	var changed := id != selected
	selected = id
	if centre:
		_cam_target = _nodes[id]["pos"]
	if changed:
		node_selected.emit(id)
	queue_redraw()


## Jump the view to a point of the tree at a zoom level.
func look_at_point(point: Vector2, new_zoom: float) -> void:
	zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	_cam = point
	_cam_target = point
	queue_redraw()


func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


## Zoom out until the whole tree fits.
func fit() -> void:
	var smallest := minf(size.x, size.y)
	if smallest > 10.0:
		look_at_point(Vector2.ZERO, smallest * 0.5 / _extent)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_nav_wait = maxf(_nav_wait - delta, 0.0)
	if not _dragging:
		_cam = _cam.lerp(_cam_target, 1.0 - exp(-12.0 * delta))
	queue_redraw()


# ----------------------------------------------------------------------------
#  Input
# ----------------------------------------------------------------------------
func _to_tree(screen: Vector2) -> Vector2:
	return _cam + (screen - size * 0.5) / zoom


func _node_at(screen: Vector2) -> String:
	var at := _to_tree(screen)
	var slack := 7.0 / zoom
	var best := ""
	var best_d := INF
	for id: String in _order:
		var n: Dictionary = _nodes[id]
		var d := (n["pos"] as Vector2).distance_to(at)
		if d <= float(n["radius"]) + slack and d < best_d:
			best = id
			best_d = d
	return best


func _move_cam(by: Vector2) -> void:
	_cam = (_cam + by).limit_length(_extent)
	_cam_target = _cam


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _to_tree(screen)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_move_cam(before - _to_tree(screen))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.12)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_dragging = true
					_drag_moved = 0.0
					_press_node = _node_at(mb.position) if mb.button_index == MOUSE_BUTTON_LEFT else ""
				else:
					_dragging = false
					if mb.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 6.0 and _press_node != "" \
							and _node_at(mb.position) == _press_node:
						select(_press_node)
						node_activated.emit(_press_node)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_drag_moved += mm.relative.length()
			_move_cam(-mm.relative / zoom)
		else:
			var id := _node_at(mm.position)
			if id != "" and id != selected:
				select(id)
	elif event is InputEventPanGesture:
		_move_cam((event as InputEventPanGesture).delta * 24.0 / zoom)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		if selected != "":
			node_activated.emit(selected)
		accept_event()
	else:
		for pair: Array in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
			if event.is_action_pressed(String(pair[0]), true):
				# A stick sends a stream of events: take one step at a time.
				# If there is no node that way, let the focus move on to the
				# buttons beside the tree.
				if _nav_wait > 0.0 and event is InputEventJoypadMotion:
					accept_event()
				elif _step(pair[1]):
					_nav_wait = 0.18
					accept_event()
				return


## Highlight the nearest node in a direction. Returns false if there is none.
func _step(dir: Vector2) -> bool:
	var from: Vector2 = _nodes[selected]["pos"] if _nodes.has(selected) else _cam
	var best := ""
	var best_score := INF
	for id: String in _order:
		if id == selected:
			continue
		var v: Vector2 = (_nodes[id]["pos"] as Vector2) - from
		var d := v.length()
		if d < 1.0:
			continue
		var along := v.dot(dir) / d
		if along < 0.45:
			continue
		var score := d / (along * along * along)
		if score < best_score:
			best = id
			best_score = score
	if best == "":
		return false
	select(best, true)
	return true


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.028, 0.97))
	draw_set_transform(size * 0.5 - _cam * zoom, 0.0, Vector2(zoom, zoom))
	var view := Rect2(_to_tree(Vector2.ZERO), size / zoom).grow(70.0)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)

	# Requirement circles.
	for g: Dictionary in guides:
		var radius := float(g["radius"])
		var open := bool(g["open"])
		var ring_color := Color(0.45, 0.6, 0.35, 0.22) if open else Color(0.85, 0.3, 0.25, 0.4)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 120, ring_color, 2.0 / zoom, true)
		var text_size := int(clampf(15.0 / zoom, 13.0, 40.0))
		for corner: float in [-PI * 0.375, PI * 0.625]:
			var at := Vector2.from_angle(corner) * (radius + 6.0)
			draw_string(font, at + Vector2(-100.0, text_size * 0.4), String(g["text"]), HORIZONTAL_ALIGNMENT_CENTER, 200.0,
					text_size, Color(0.6, 0.75, 0.5, 0.55) if open else Color(1.0, 0.45, 0.4, 0.85))

	# Links.
	for link: Array in _links:
		var a: Dictionary = _nodes[link[0]]
		var b: Dictionary = _nodes[link[1]]
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		if not view.has_point(pa) and not view.has_point(pb):
			continue
		var sa := int(_states.get(link[0], FAR))
		var sb := int(_states.get(link[1], FAR))
		if sa == OWNED and sb == OWNED:
			var c: Color = (a["color"] as Color).lerp(b["color"], 0.5)
			draw_line(pa, pb, Color(c.r, c.g, c.b, 0.3), 9.0)
			draw_line(pa, pb, c.lightened(0.25), 4.0)
		elif sa == OWNED or sb == OWNED:
			var other: Dictionary = b if sa == OWNED else a
			var other_state := sb if sa == OWNED else sa
			var c: Color = other["color"]
			if other_state == READY:
				draw_line(pa, pb, Color(c.r, c.g, c.b, 0.45 + 0.35 * pulse), 3.5)
			else:
				draw_line(pa, pb, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.6), 2.5)
		else:
			draw_line(pa, pb, Color(0.36, 0.38, 0.32, 0.7), 2.0)

	# Nodes.
	var glow := Art.t("glow")
	for id: String in _order:
		var n: Dictionary = _nodes[id]
		var pos: Vector2 = n["pos"]
		if not view.has_point(pos):
			continue
		var r := float(n["radius"])
		var state := int(_states.get(id, FAR))
		var color: Color = n["color"]
		var color2: Color = n.get("color2", color)
		var shape := String(n["shape"])
		var fill_tex := Art.t("node_fill" if shape == "circle" else "node_" + shape)
		var ring_tex := Art.t("node_ring" if shape == "circle" else "node_%s_ring" % shape)
		var body := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0)
		var fill := Color(0.11, 0.12, 0.1)
		var ring := Color(0.3, 0.32, 0.28)
		var icon_color := Color(0.42, 0.44, 0.4)
		match state:
			OWNED:
				draw_texture_rect(glow, body.grow(r * 1.1), false, Color(color.r, color.g, color.b, 0.5))
				fill = color
				ring = color2.lightened(0.45)
				icon_color = Color(0.06, 0.05, 0.05, 0.85)
			READY:
				draw_texture_rect(glow, body.grow(r * (1.0 + 0.5 * pulse)), false, Color(color.r, color.g, color.b, 0.35 + 0.4 * pulse))
				fill = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3)
				ring = color2.lightened(0.2 + 0.3 * pulse)
				icon_color = color.lightened(0.3)
			POOR:
				fill = Color(color.r * 0.2, color.g * 0.2, color.b * 0.2)
				ring = Color(color2.r * 0.75, color2.g * 0.75, color2.b * 0.75)
				icon_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8)
			LOCKED:
				fill = Color(0.1, 0.09, 0.09)
				ring = Color(0.42, 0.26, 0.24)
				icon_color = Color(0.6, 0.38, 0.35)
			_:
				fill = Color(color.r * 0.14 + 0.05, color.g * 0.14 + 0.05, color.b * 0.14 + 0.05)
				ring = Color(color2.r * 0.42 + 0.12, color2.g * 0.42 + 0.12, color2.b * 0.42 + 0.12)
				icon_color = Color(color.r * 0.5 + 0.1, color.g * 0.5 + 0.1, color.b * 0.5 + 0.1)
		draw_texture_rect(fill_tex, body, false, fill)
		draw_texture_rect(ring_tex, body, false, ring)
		# Symbols only once they are big enough to read.
		var icon := String(n.get("icon", ""))
		if state == LOCKED and r >= 15.0:
			icon = "ui_lock"
		if icon != "" and r * zoom >= 6.0:
			var s := r * (1.05 if shape == "circle" else 0.9)
			draw_texture_rect(Art.t(icon), Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), false, icon_color)
		var badge := String(_badges.get(id, ""))
		if badge != "" and zoom >= 0.4:
			draw_string(font, pos + Vector2(-60.0, r + 15.0), badge, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(1, 1, 1, 0.9))

	# The highlighted node.
	if _nodes.has(selected):
		var n: Dictionary = _nodes[selected]
		var r := float(n["radius"]) + 9.0 + 2.5 * pulse
		draw_texture_rect(Art.t("ring"), Rect2((n["pos"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1, 1, 1, 0.95) if has_focus() else Color(1, 1, 1, 0.55))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var help := hint_gamepad if GameInput.using_gamepad() else hint
	if help != "":
		draw_string(font, Vector2(14.0, size.y - 12.0), help, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.45))
	# Frame; gold when the tree has the keyboard / gamepad focus.
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), UiKit.GOLD if has_focus() else Color("3f4634"), false, 2.0)
