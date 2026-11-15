class_name MapScreen
extends Control
## The Play screen: a map of Haiti with the five gang zones on it (the owner's
## idea: "the game map could be Haiti's map and we go fight in a zone occupied
## by gangs to take back the territory").
##
## A zone is one of Config.MAPS. Red pin = a gang holds it, green pin with a
## flag = taken back (all its waves cleared), grey = locked until the zone
## before it is taken back. Click a pin to choose the zone; the panel on the
## right shows its gang, leader and numbers. Under the map: the wave to start
## from (each boss beaten opens a later one) and START.
##
## The rules are the old ones - only the look changed.

const MAP_SIZE := Vector2(560, 400)
const PANEL_WIDTH := 330.0

# The piece of the world the map shows, in degrees, and how it is laid flat.
const LON_WEST := -74.62
const LAT_NORTH := 20.15
const LAT_SPAN := 2.3
const LON_SQUEEZE := 0.945      # this far from the equator a degree east-west is shorter than one north-south

# Haiti's coast and border as (degrees east, degrees north): from where the
# border meets the north coast, west along it, around both peninsulas and back
# up the border. Drawn by hand and much simplified - a map for a game, not for
# finding your way.
const COAST: Array[Vector2] = [
	Vector2(-71.757, 19.71), Vector2(-71.85, 19.67), Vector2(-72.02, 19.73), Vector2(-72.20, 19.78),
	Vector2(-72.42, 19.81), Vector2(-72.62, 19.88), Vector2(-72.83, 19.95), Vector2(-73.05, 19.92),
	Vector2(-73.30, 19.90), Vector2(-73.42, 19.82), Vector2(-73.47, 19.70), Vector2(-73.38, 19.62),
	Vector2(-73.20, 19.60), Vector2(-73.02, 19.58), Vector2(-72.85, 19.48), Vector2(-72.72, 19.44),
	Vector2(-72.76, 19.32), Vector2(-72.80, 19.22), Vector2(-72.72, 19.12), Vector2(-72.68, 18.98),
	Vector2(-72.52, 18.80), Vector2(-72.40, 18.70), Vector2(-72.34, 18.58), Vector2(-72.42, 18.53),
	Vector2(-72.63, 18.52), Vector2(-72.78, 18.43), Vector2(-72.88, 18.43), Vector2(-73.08, 18.45),
	Vector2(-73.30, 18.50), Vector2(-73.55, 18.55), Vector2(-73.78, 18.60), Vector2(-74.00, 18.63),
	Vector2(-74.12, 18.65), Vector2(-74.30, 18.66), Vector2(-74.45, 18.62), Vector2(-74.48, 18.45),
	Vector2(-74.42, 18.33), Vector2(-74.22, 18.30), Vector2(-74.02, 18.22), Vector2(-73.90, 18.07),
	Vector2(-73.75, 18.19), Vector2(-73.55, 18.22), Vector2(-73.38, 18.27), Vector2(-73.15, 18.22),
	Vector2(-72.90, 18.18), Vector2(-72.53, 18.23), Vector2(-72.30, 18.23), Vector2(-72.05, 18.20),
	Vector2(-71.90, 18.12), Vector2(-71.77, 18.04), Vector2(-71.74, 18.20), Vector2(-71.72, 18.32),
	Vector2(-71.78, 18.40), Vector2(-71.84, 18.52), Vector2(-71.84, 18.62), Vector2(-71.72, 18.70),
	Vector2(-71.72, 18.85), Vector2(-71.63, 18.95), Vector2(-71.62, 19.05), Vector2(-71.68, 19.20),
	Vector2(-71.75, 19.35), Vector2(-71.70, 19.50),
]
# The islands, the big lake, and the land east of the border (not part of
# the game: it is only there so the country does not float in the sea).
const ISLANDS: Array = [
	[Vector2(-73.30, 18.93), Vector2(-73.18, 18.97), Vector2(-73.00, 18.95), Vector2(-72.85, 18.86),
		Vector2(-72.78, 18.74), Vector2(-72.86, 18.70), Vector2(-73.05, 18.76), Vector2(-73.22, 18.84)],
	[Vector2(-72.95, 20.05), Vector2(-72.80, 20.09), Vector2(-72.62, 20.04), Vector2(-72.66, 20.00), Vector2(-72.85, 19.99)],
	[Vector2(-73.72, 18.10), Vector2(-73.62, 18.11), Vector2(-73.60, 18.06), Vector2(-73.70, 18.05)],
]
const LAKE: Array[Vector2] = [
	Vector2(-72.10, 18.63), Vector2(-72.00, 18.66), Vector2(-71.92, 18.60), Vector2(-71.96, 18.55), Vector2(-72.06, 18.56),
]
const NEIGHBOUR: Array[Vector2] = [
	Vector2(-71.77, 18.04), Vector2(-71.74, 18.20), Vector2(-71.72, 18.32), Vector2(-71.78, 18.40),
	Vector2(-71.84, 18.52), Vector2(-71.84, 18.62), Vector2(-71.72, 18.70), Vector2(-71.72, 18.85),
	Vector2(-71.63, 18.95), Vector2(-71.62, 19.05), Vector2(-71.68, 19.20), Vector2(-71.75, 19.35),
	Vector2(-71.70, 19.50), Vector2(-71.757, 19.71), Vector2(-71.66, 19.86), Vector2(-71.45, 19.88),
	Vector2(-71.00, 19.90), Vector2(-71.00, 17.70), Vector2(-71.42, 17.62), Vector2(-71.60, 17.80),
]

const SEA := Color(0.06, 0.12, 0.14)
const LAND := Color(0.29, 0.33, 0.21)
const LAND_EDGE := Color(0.62, 0.66, 0.46, 0.9)
const NEIGHBOUR_LAND := Color(0.17, 0.2, 0.16)
const HELD := Color(0.86, 0.2, 0.15)        # a gang holds the zone
const FREE := Color(0.45, 0.8, 0.36)        # taken back
const SHUT := Color(0.36, 0.37, 0.34)       # locked
const PIN_RADIUS := 13.0


## The picture: sea, land, pins. The pins' buttons lie on top of it (they are
## invisible; they only take the clicks and the gamepad's highlight).
class HaitiMap extends Control:
	var screen: MapScreen
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), MapScreen.SEA)
		_land(MapScreen.NEIGHBOUR, MapScreen.NEIGHBOUR_LAND, Color(0, 0, 0, 0))
		_land(MapScreen.COAST, MapScreen.LAND, MapScreen.LAND_EDGE)
		for island: Array in MapScreen.ISLANDS:
			_land(island, MapScreen.LAND, MapScreen.LAND_EDGE)
		_land(MapScreen.LAKE, MapScreen.SEA, Color(0, 0, 0, 0))

		_write(Vector2(14, 26), "HAITI", 18, Color(1, 1, 1, 0.55))
		_write(Vector2(size.x - 14, 24), "TAKEN BACK:  %d of %d" % [screen.zones_free(), Config.MAPS.size()], 14,
				MapScreen.FREE if screen.zones_free() > 0 else Color(1, 1, 1, 0.55), 2)
		for i in Config.MAPS.size():
			_pin(i)

		# What the pointer (or the gamepad's highlight) is on.
		draw_rect(Rect2(0, size.y - 28, size.x, 28), Color(0, 0, 0, 0.55))
		_write(Vector2(size.x * 0.5, size.y - 9), screen.caption(), 13, Color(1, 1, 1, 0.9), 1, 3)
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color("3f4634"), false, 2.0)

	func _land(shape: Array, fill: Color, edge: Color) -> void:
		var points := PackedVector2Array()
		for corner: Vector2 in shape:
			points.append(MapScreen.project(corner))
		draw_colored_polygon(points, fill)
		if edge.a > 0.0:
			points.append(points[0])
			draw_polyline(points, edge, 1.5, true)

	func _pin(index: int) -> void:
		var def: Dictionary = Config.MAPS[index]
		var at := MapScreen.project(def["at"])
		var state := screen.zone_state(index)
		var fill: Color = MapScreen.FREE if state == "free" else (MapScreen.HELD if state == "held" else MapScreen.SHUT)
		var radius := MapScreen.PIN_RADIUS
		# The zone you chose wears a gold ring that breathes; the one under the pointer a white one.
		if index == screen.selected():
			var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
			draw_arc(at, radius + 6.0 + breath * 2.0, 0.0, TAU, 40, Color(1.0, 0.78, 0.2, 0.95), 3.0, true)
		elif index == screen.pointed():
			draw_arc(at, radius + 6.0, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 2.0, true)
		draw_circle(at + Vector2(1.5, 2.5), radius + 1.5, Color(0, 0, 0, 0.55))
		draw_circle(at, radius + 1.5, Color(0.05, 0.05, 0.04))
		draw_circle(at, radius, fill)
		draw_circle(at - Vector2(0, 3), radius - 4.0, Color(1, 1, 1, 0.12))
		_write(at + Vector2(0, 6), "%d" % (index + 1), 16, Color.WHITE if state != "locked" else Color(1, 1, 1, 0.5), 1, 4)
		if state == "free":
			# A small flag planted in the zone: blue over red.
			var foot := at + Vector2(radius - 3.0, -radius + 3.0)
			draw_line(foot, foot + Vector2(0, -20), Color(0.9, 0.9, 0.85), 2.0)
			draw_rect(Rect2(foot + Vector2(1, -20), Vector2(15, 5.5)), Color(0.12, 0.25, 0.75))
			draw_rect(Rect2(foot + Vector2(1, -14.5), Vector2(15, 5.5)), Color(0.82, 0.12, 0.16))

		var side := int(def.get("label_side", 1))
		var x := at.x + (radius + 9.0) * side
		var align := 0 if side > 0 else 2
		var name_color: Color = def["color"] if state != "locked" else Color(1, 1, 1, 0.45)
		_write(Vector2(x, at.y + 1), String(def["name"]), 13, name_color, align, 4)
		var note := "LOCKED"
		var note_color := Color(1, 1, 1, 0.4)
		if state == "free":
			note = "TAKEN BACK"
			note_color = MapScreen.FREE
		elif state == "held":
			var best := SaveData.map_best_wave(index)
			note = "held by %s" % String(def["gang"])
			if best > 0:
				note += "  -  wave %d / %d" % [best, Config.WAVES_PER_MAP]
			note_color = Color(1.0, 0.5, 0.42)
		_write(Vector2(x, at.y + 15), note, 11, note_color, align, 3)

	## Outlined text. align: 0 = left, 1 = centre, 2 = right. `at` is the baseline.
	func _write(at: Vector2, message: String, font_size: int, color: Color, align: int = 0, outline: int = 5) -> void:
		var pos := at
		if align != 0:
			var width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			pos.x -= width * (0.5 if align == 1 else 1.0)
		draw_string_outline(_font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, color.a * 0.85))
		draw_string(_font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


var main: Main
var _map: HaitiMap
var _pins: Array[Button] = []
var _selected := 0
var _pointed := -1               # the pin under the pointer / the gamepad's highlight (-1 = none)
var _start := 1
var _start_label: Label
var _prev: Button
var _next: Button
var _go: Button
var _back: Button
var _hint: Label
# The panel beside the map: everything about the chosen zone.
var _zone: Label
var _name: Label
var _holder: Label
var _leader: Label
var _story: Label
var _values: Array[Label] = []
var _status: Label
var _bar: UiKit.Bar
var _detail: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	col.add_child(UiKit.heading("TAKE BACK THE COUNTRY", 42))
	col.add_child(UiKit.heading("Five gangs hold the country. Clear all %d waves of a zone to take it back - that opens the next one." % Config.WAVES_PER_MAP,
			16, UiKit.DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_map = HaitiMap.new()
	_map.screen = self
	_map.custom_minimum_size = MAP_SIZE
	_map.clip_contents = true
	row.add_child(_map)
	for i in Config.MAPS.size():
		_map.add_child(_make_pin(i))
	row.add_child(_make_panel())

	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 12)
	pick.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(pick)
	pick.add_child(UiKit.label("START FROM", 22, UiKit.DIM))
	_prev = UiKit.button("<", func() -> void: _step(-1), 56.0)
	pick.add_child(_prev)
	_start_label = UiKit.heading("WAVE 1", 30, UiKit.GOLD)
	_start_label.custom_minimum_size = Vector2(170, 0)
	_start_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick.add_child(_start_label)
	_next = UiKit.button(">", func() -> void: _step(1), 56.0)
	pick.add_child(_next)
	_hint = UiKit.heading("", 15, UiKit.DIM)
	col.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), 220.0)
	buttons.add_child(_back)
	_go = UiKit.button("START", func() -> void: main.start_run(_selected, _start), 400.0)
	buttons.add_child(_go)

	# Keys and gamepad: left / right walk through the zones in their order,
	# down leaves the map for the buttons under it.
	for i in _pins.size():
		var pin := _pins[i]
		pin.focus_neighbor_left = pin.get_path_to(_pins[maxi(i - 1, 0)])
		pin.focus_neighbor_right = pin.get_path_to(_pins[mini(i + 1, _pins.size() - 1)])
		pin.focus_neighbor_top = pin.get_path_to(pin)
		pin.focus_neighbor_bottom = pin.get_path_to(_go)


## Where a spot of the world (degrees east, degrees north) lies on the picture.
static func project(lonlat: Vector2) -> Vector2:
	var per_degree := MAP_SIZE.y / LAT_SPAN
	return Vector2((lonlat.x - LON_WEST) * LON_SQUEEZE * per_degree, (LAT_NORTH - lonlat.y) * per_degree)


## A zone's pin: an invisible button over the drawn pin and its name.
func _make_pin(index: int) -> Button:
	var def: Dictionary = Config.MAPS[index]
	var at := project(def["at"])
	var side := int(def.get("label_side", 1))
	var name_width := ThemeDB.fallback_font.get_string_size(String(def["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var reach := PIN_RADIUS + 12.0 + name_width
	var pin := Button.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		pin.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pin.position = Vector2(at.x - (PIN_RADIUS + 6.0 if side > 0 else reach), at.y - PIN_RADIUS - 6.0)
	pin.custom_minimum_size = Vector2(reach + PIN_RADIUS + 6.0, PIN_RADIUS * 2.0 + 16.0)
	pin.size = pin.custom_minimum_size
	pin.pressed.connect(func() -> void: _select(index))
	pin.focus_entered.connect(func() -> void:
		Sfx.play("ui_move", -12.0, 0.0)
		_pointed = index)
	pin.focus_exited.connect(func() -> void:
		if _pointed == index:
			_pointed = -1)
	pin.mouse_entered.connect(func() -> void:
		if not pin.has_focus():
			pin.grab_focus())
	_pins.append(pin)
	return pin


func _make_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, MAP_SIZE.y)
	panel.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_zone = UiKit.heading("", 14, UiKit.DIM)
	box.add_child(_zone)
	_name = UiKit.heading("", 26)
	box.add_child(_name)
	_holder = UiKit.heading("", 16)
	box.add_child(_holder)
	_leader = UiKit.heading("", 14, UiKit.DIM)
	box.add_child(_leader)
	box.add_child(UiKit.spacer(2))
	_story = UiKit.label("", 14, UiKit.DIM)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 62)
	box.add_child(_story)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for title: String in ["Zombie health", "Zombie damage", "Zombie speed", "XP", "Coins"]:
		grid.add_child(UiKit.label(title, 15, UiKit.DIM))
		var value := UiKit.label("", 16)
		grid.add_child(value)
		_values.append(value)
	box.add_child(grid)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	_status = UiKit.heading("", 16)
	box.add_child(_status)
	_bar = UiKit.Bar.new()
	_bar.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 10)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_bar)
	_detail = UiKit.heading("", 13, UiKit.DIM)
	box.add_child(_detail)
	return panel


static func _times(value: float) -> String:
	return "x%d" % int(value) if is_equal_approx(value, round(value)) else "x%s" % String.num(value, 2)


## "free" (taken back), "held" (a gang holds it, you may fight there) or "locked".
func zone_state(index: int) -> String:
	if not SaveData.map_unlocked(index):
		return "locked"
	return "free" if SaveData.map_cleared(index) else "held"


## How many zones have been taken back.
func zones_free() -> int:
	var count := 0
	for i in Config.MAPS.size():
		if SaveData.map_cleared(i):
			count += 1
	return count


func selected() -> int:
	return _selected


func pointed() -> int:
	return _pointed


## The line along the bottom of the map: what the pointer is on.
func caption() -> String:
	if _pointed < 0:
		return "Click a zone on the map to choose where to fight."
	var def: Dictionary = Config.MAPS[_pointed]
	var head := "ZONE %d  -  %s  -  " % [_pointed + 1, String(def["name"])]
	match zone_state(_pointed):
		"locked":
			return head + "LOCKED: take back %s first" % String(Config.MAPS[_pointed - 1]["name"])
		"free":
			return head + "taken back from %s" % String(def["gang"])
	return head + "held by %s, led by %s" % [String(def["gang"]), String(def["boss"])]


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_map.queue_redraw()         # (the chosen zone's ring breathes)


## Called by Main every time this screen is shown.
func opened() -> void:
	_selected = SaveData.selected_map
	_start = SaveData.selected_start
	_pointed = -1
	_refresh()
	_go.grab_focus()


func _select(index: int) -> void:
	if not SaveData.map_unlocked(index):
		Sfx.play("ui_deny", -4.0, 0.0)
		return
	Sfx.play("ui_click", -4.0, 0.0)
	if index != _selected:
		_selected = index
		_start = SaveData.selected_start if index == SaveData.selected_map else 1
	_refresh()


func _step(direction: int) -> void:
	var waves := SaveData.map_checkpoints(_selected)
	var at := maxi(waves.find(_start), 0)
	_start = waves[clampi(at + direction, 0, waves.size() - 1)]
	_refresh()


func _refresh() -> void:
	var def: Dictionary = Config.MAPS[_selected]
	var color: Color = def["color"]
	var best := SaveData.map_best_wave(_selected)
	var free := SaveData.map_cleared(_selected)
	_zone.text = "ZONE %d of %d" % [_selected + 1, Config.MAPS.size()]
	_name.text = String(def["name"])
	_name.add_theme_color_override("font_color", color)
	_holder.text = "TAKEN BACK" if free else "HELD BY %s" % String(def["gang"])
	_holder.add_theme_color_override("font_color", FREE if free else Color(1.0, 0.5, 0.42))
	_leader.text = ("Their leader %s is beaten" if free else "Gang leader:  %s") % String(def["boss"])
	_story.text = String(def["story"])
	var numbers := [float(def["hp"]), float(def["damage"]), float(def["speed"]), float(def["xp"]), float(def["coins"])]
	for i in _values.size():
		_values[i].text = _times(numbers[i])
		var plain := is_equal_approx(numbers[i], 1.0)
		_values[i].add_theme_color_override("font_color", UiKit.TEXT if plain else (Color(1.0, 0.55, 0.45) if i < 3 else UiKit.GREEN))
	_bar.fill = color
	_bar.set_fraction(float(best) / float(Config.WAVES_PER_MAP))
	if free:
		_status.text = "ALL %d WAVES BEATEN" % Config.WAVES_PER_MAP
		_status.add_theme_color_override("font_color", UiKit.GOLD)
		_detail.text = "You can fight here again for coins and XP."
	else:
		_status.text = "BEST: WAVE %d / %d" % [best, Config.WAVES_PER_MAP] if best > 0 else "NOT TAKEN BACK YET"
		_status.add_theme_color_override("font_color", UiKit.TEXT)
		_detail.text = "%d waves to go" % (Config.WAVES_PER_MAP - best)

	var waves := SaveData.map_checkpoints(_selected)
	if not waves.has(_start):
		_start = 1
	var at := waves.find(_start)
	_start_label.text = "WAVE %d" % _start
	_prev.disabled = at <= 0
	_next.disabled = at >= waves.size() - 1
	if waves.size() <= 1:
		_hint.text = "Beat the boss on wave %d to unlock a later starting wave." % Config.CHECKPOINT_EVERY
	else:
		_hint.text = "Every boss you beat unlocks the next starting wave (you have reached wave %d)." % waves[waves.size() - 1]
	_go.text = "START   -   %s" % String(def["name"])
	# Up from the buttons leads back onto the map, to the chosen zone.
	for button: Button in [_prev, _next, _back, _go]:
		button.focus_neighbor_top = button.get_path_to(_pins[_selected])
	_map.queue_redraw()
