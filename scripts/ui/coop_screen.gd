class_name CoopScreen
extends Control
## PLAY WITH FRIENDS: up to three players, each on their own computer.
##
## One of you presses HOST A GAME and tells the others the code that appears.
## They type it in and press JOIN. Then the host chooses the map and starts;
## everybody's game starts the same run. The connection stays between runs,
## so after a run you are back here, ready for the next one.
##
## Everything about the connection itself is in scripts/autoload/net.gd.

var main: Main
var _name: LineEdit
var _code: LineEdit
var _host: Button
var _join: Button
var _status: Label
var _start: Button
var _copy: Button
var _leave: Button
var _back: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(UiKit.heading("PLAY WITH FRIENDS", 46))
	var rules := UiKit.heading("Up to %d players, each on their own computer.  ALL GOLD IS SHARED: every coin any of you " % Config.COOP_MAX_PLAYERS
			+ "picks up counts for everybody.  The more of you there are, the tougher the zombies and the more of them.  "
			+ "If one of you falls, another can pick them up.", 16, UiKit.DIM)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(760, 0)
	col.add_child(rules)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_child(UiKit.label("YOUR NAME", 20, UiKit.DIM))
	_name = _field("", 240.0, Config.COOP_NAME_MAX)
	_name.text_changed.connect(_on_name_changed)
	name_row.add_child(_name)
	col.add_child(name_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_host = UiKit.button("HOST A GAME", _on_host, 250.0)
	row.add_child(_host)
	row.add_child(UiKit.label("or", 18, UiKit.DIM))
	_code = _field("your friend's code", 250.0, 64)
	_code.text_submitted.connect(func(_text: String) -> void: _on_join())
	row.add_child(_code)
	_join = UiKit.button("JOIN", _on_join, 150.0)
	row.add_child(_join)
	col.add_child(row)

	_status = UiKit.heading("", 20, UiKit.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(760, 132)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_status)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	_start = UiKit.button("CHOOSE A MAP AND START", func() -> void: main.open_screen("maps"), 420.0)
	row2.add_child(_start)
	_copy = UiKit.button("COPY CODE", _on_copy, 200.0)
	row2.add_child(_copy)
	col.add_child(row2)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	_leave = UiKit.button("STOP", _on_leave, 250.0)
	row3.add_child(_leave)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), 250.0)
	row3.add_child(_back)
	col.add_child(row3)
	for small: Button in [_copy, _leave, _back]:
		small.add_theme_font_size_override("font_size", 19)

	Net.changed.connect(_refresh)


func _field(hint: String, width: float, max_length: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = hint
	field.max_length = max_length
	field.custom_minimum_size = Vector2(width, 46)
	field.add_theme_font_size_override("font_size", 22)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.select_all_on_focus = true
	return field


func _on_name_changed(text: String) -> void:
	var cleaned := text.strip_edges().to_upper()
	if cleaned != "":
		SaveData.settings["player_name"] = cleaned
		SaveData.save_game()


func _on_host() -> void:
	Sfx.play("ui_buy")
	Net.host()


func _on_join() -> void:
	if _join.disabled:
		return
	Sfx.play("ui_buy")
	Net.join(_code.text)


func _on_copy() -> void:
	DisplayServer.clipboard_set(Net.code if Net.code != "" else Net.lan_code)
	_copy.text = "COPIED"


func _on_leave() -> void:
	Net.leave()
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var idle := Net.role == Net.Role.NONE
	var hosting := Net.role == Net.Role.HOST
	_host.disabled = not idle
	_join.disabled = not idle
	_code.editable = idle
	_name.editable = idle
	_leave.visible = not idle
	_leave.text = "STOP HOSTING" if hosting else "LEAVE"
	_start.visible = hosting
	_start.disabled = Net.mates.is_empty()
	_copy.visible = hosting and (Net.code != "" or Net.lan_code != "")
	if _copy.text == "COPIED" and not _copy.visible:
		_copy.text = "COPY CODE"
	_status.add_theme_color_override("font_color", UiKit.TEXT)

	if idle:
		_status.text = Net.status if Net.status != "" else \
				"One of you hosts and tells the others the code that appears here.\nThey type it in above and press JOIN."
		if Net.status != "":
			_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	elif hosting and not Net.mates.is_empty():
		var here: Array[String] = []
		for other: int in Net.mates.keys():
			here.append("%s (level %d)" % [Net.name_of(other), int(Net.mates[other].get("level", 1))])
		var room := Config.COOP_MAX_PLAYERS - 1 - Net.mates.size()
		_status.text = "IN YOUR GAME:  %s\n%s\nChoose a map and start: everybody's game begins together." % [",  ".join(here),
				("One more friend can still join with the code  %s" % (Net.code if Net.code != "" else Net.lan_code)) if room > 0
				else "The game is full."]
		_status.add_theme_color_override("font_color", UiKit.GREEN)
	elif hosting:
		var lines: Array[String] = []
		match Net.door:
			1:
				lines.append("Asking your router to let your friends in...")
			2:
				lines.append("YOUR CODE:   %s" % Net.code)
				lines.append("Tell it to your friends. They type it in on this screen and press JOIN.")
			3:
				lines.append("Your router did not open the way in by itself.")
				lines.append("For a friend somewhere else, the router must pass UDP port %d on to this computer "
						% Config.NET_PORT + "(\"port forwarding\"). Then they join with your internet address.")
		if Net.lan_code != "" and Net.door != 2:
			lines.append("A friend IN THE SAME HOUSE can join with:   %s" % Net.lan_code)
		lines.append("Waiting for your friends to join...")
		_status.text = "\n".join(lines)
	else:
		_status.text = Net.status
		if Net.joined:
			if Net.host_busy:
				_status.text += "\nThey are in the middle of a run right now: you will be in the next one."
			_status.add_theme_color_override("font_color", UiKit.GREEN)


## Called by Main every time this screen is shown.
func opened() -> void:
	_name.text = String(SaveData.get_setting("player_name"))
	_copy.text = "COPY CODE"
	_refresh()
	if Net.role == Net.Role.HOST and not Net.mates.is_empty():
		_start.grab_focus()
	elif Net.role == Net.Role.NONE:
		_host.grab_focus()
	else:
		_back.grab_focus()
