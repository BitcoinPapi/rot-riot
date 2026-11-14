class_name MapScreen
extends Control
## The Play screen: choose a map and the wave to start from.
##
## Every map has Config.WAVES_PER_MAP waves. Clearing the last one unlocks the
## next map. Each boss beaten on a map opens a later starting wave there, so a
## long map can be finished over several sessions.

const CARD_SIZE := Vector2(232, 322)

var main: Main
var _cards: Array[Button] = []
var _status: Array[Label] = []
var _detail: Array[Label] = []
var _bars: Array[UiKit.Bar] = []
var _selected := 0
var _start := 1
var _start_label: Label
var _prev: Button
var _next: Button
var _go: Button
var _hint: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	col.add_child(UiKit.heading("CHOOSE YOUR MAP", 46))
	col.add_child(UiKit.heading("Every map has %d waves. Clear the last one to unlock the next map." % Config.WAVES_PER_MAP,
			17, UiKit.DIM))
	col.add_child(UiKit.spacer(4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in Config.MAPS.size():
		row.add_child(_make_card(i))

	col.add_child(UiKit.spacer(6))
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
	buttons.add_child(UiKit.button("BACK", func() -> void: main.close_screen(), 220.0))
	_go = UiKit.button("START", func() -> void: main.start_run(_selected, _start), 340.0)
	buttons.add_child(_go)


func _make_card(index: int) -> Button:
	var def: Dictionary = Config.MAPS[index]
	var color: Color = def["color"]
	var card := UiKit.button("", func() -> void: _select(index), CARD_SIZE.x)
	card.custom_minimum_size = CARD_SIZE
	_cards.append(card)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	box.add_child(UiKit.heading("MAP %d" % (index + 1), 14, UiKit.DIM))
	box.add_child(UiKit.heading(String(def["name"]), 23, color))
	var story := UiKit.label(String(def["story"]), 13, UiKit.DIM)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 54)
	box.add_child(story)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line: Array in [
			["Zombie health", _times(float(def["hp"]))], ["Zombie damage", _times(float(def["damage"]))],
			["Zombie speed", _times(float(def["speed"]))], ["XP", _times(float(def["xp"]))],
			["Coins", _times(float(def["coins"]))]]:
		grid.add_child(UiKit.label(String(line[0]), 14, UiKit.DIM))
		var hard := index > 0 and String(line[0]).begins_with("Zombie")
		var good := index > 0 and not String(line[0]).begins_with("Zombie")
		grid.add_child(UiKit.label(String(line[1]), 15, Color(1.0, 0.55, 0.45) if hard else (UiKit.GREEN if good else UiKit.TEXT)))
	box.add_child(grid)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(filler)

	var status := UiKit.heading("", 16, UiKit.TEXT)
	box.add_child(status)
	_status.append(status)
	var bar := UiKit.Bar.new()
	bar.custom_minimum_size = Vector2(CARD_SIZE.x - 40, 10)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.fill = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	_bars.append(bar)
	var detail := UiKit.heading("", 12, UiKit.DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 32)
	box.add_child(detail)
	_detail.append(detail)
	return card


static func _times(value: float) -> String:
	return "x%d" % int(value) if is_equal_approx(value, round(value)) else "x%s" % String.num(value, 2)


## Called by Main every time this screen is shown.
func opened() -> void:
	_selected = SaveData.selected_map
	_start = SaveData.selected_start
	_refresh()
	_go.grab_focus()


func _select(index: int) -> void:
	if not SaveData.map_unlocked(index):
		return
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
	for i in _cards.size():
		var card := _cards[i]
		var def: Dictionary = Config.MAPS[i]
		var color: Color = def["color"]
		var open := SaveData.map_unlocked(i)
		var best := SaveData.map_best_wave(i)
		card.disabled = not open
		card.modulate = Color(1, 1, 1, 1) if open else Color(0.55, 0.55, 0.55, 0.8)
		for state: String in ["normal", "hover", "disabled"]:
			if i == _selected:
				card.add_theme_stylebox_override(state, UiKit.card_style(color, state == "hover"))
			else:
				card.remove_theme_stylebox_override(state)
		_bars[i].set_fraction(float(best) / float(Config.WAVES_PER_MAP))
		_bars[i].visible = open
		if not open:
			_status[i].text = "LOCKED"
			_status[i].add_theme_color_override("font_color", UiKit.RED)
			_detail[i].text = "Clear wave %d of %s" % [Config.WAVES_PER_MAP, String(Config.MAPS[i - 1]["name"])]
		elif SaveData.map_cleared(i):
			_status[i].text = "CLEARED"
			_status[i].add_theme_color_override("font_color", UiKit.GOLD)
			_detail[i].text = "All %d waves beaten" % Config.WAVES_PER_MAP
		else:
			_status[i].text = "BEST: WAVE %d / %d" % [best, Config.WAVES_PER_MAP] if best > 0 else "NOT CLEARED YET"
			_status[i].add_theme_color_override("font_color", UiKit.TEXT)
			_detail[i].text = "%d waves to go" % (Config.WAVES_PER_MAP - best)

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
	_go.text = "START   -   %s" % String(Config.MAPS[_selected]["name"])
