class_name CoopScreen
extends Control
## PLAY WITH FRIENDS: up to three players, each on their own computer.
##
## One of you presses HOST A GAME and tells the others the code that appears.
## They type it in and press JOIN. If a home router stands in the way, the
## joiner's screen shows a REPLY CODE: the host types that in and presses
## LET IN, and they are connected. Then the host chooses the map and starts;
## everybody's game starts the same run. The connection stays between runs,
## so after a run you are back here, ready for the next one.
##
## Everything about the connection itself is in scripts/autoload/net.gd.

var main: Main
var _name: LineEdit
var _code: LineEdit
var _host: Button
var _join: Button
var _big: Label                 # the code to pass on, large: the host's game code or a joiner's reply code
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

	_big = UiKit.heading("", 44, UiKit.GOLD)
	col.add_child(_big)

	_status = UiKit.heading("", 20, UiKit.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(760, 118)
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


## The button beside the code box: JOIN, or - while hosting - LET IN.
func _on_join() -> void:
	if _join.disabled:
		return
	var typed := _code.text
	if Net.role != Net.Role.HOST:
		Sfx.play("ui_buy")
		Net.join(typed)
		return
	var kind := int(Net.read_code(typed)["kind"])
	if kind != Net.CODE_GAME and kind != Net.CODE_ADDRESS:
		if Net.let_in(typed):
			Sfx.play("ui_buy")
			_code.text = ""
	elif typed.strip_edges().to_upper() == Net.code:
		Net.status = "That is your own code. Tell it to your friends: they type it in on their screen."
		_refresh()
	elif not Net.mates.is_empty():
		Net.status = "You have friends in your game. Press STOP HOSTING first if you want to join another game."
		_refresh()
	else:
		# A friend's game code typed while hosting: join their game instead.
		Sfx.play("ui_buy")
		Net.join(typed)


func _on_copy() -> void:
	DisplayServer.clipboard_set(_big.text)
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
	# While hosting the code box takes a friend's reply code (or, to give up
	# hosting and join a friend instead, their game code).
	_code.editable = idle or hosting
	_code.placeholder_text = "a friend's reply code" if hosting else "your friend's code"
	_join.disabled = not (idle or hosting)
	_join.text = "LET IN" if hosting else "JOIN"
	_name.editable = idle
	_leave.visible = not idle
	_leave.text = "STOP HOSTING" if hosting else "LEAVE"
	_start.visible = hosting
	_start.disabled = Net.mates.is_empty()
	var shown := Net.code if hosting else (Net.reply_code if not idle and not Net.joined else "")
	if shown != _big.text:
		_copy.text = "COPY CODE"
	_big.text = shown
	_big.visible = shown != ""
	_copy.visible = shown != ""
	_status.add_theme_color_override("font_color", UiKit.TEXT)

	if idle:
		_status.text = Net.status if Net.status != "" else \
				"One of you hosts and tells the others the code that appears here.\nThey type it in above and press JOIN."
		if Net.status != "":
			_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	elif hosting:
		var lines: Array[String] = []
		if not Net.mates.is_empty():
			var here: Array[String] = []
			for other: int in Net.mates.keys():
				here.append("%s (level %d)" % [Net.name_of(other), int(Net.mates[other].get("level", 1))])
			lines.append("IN YOUR GAME:  %s" % ",  ".join(here))
			if Net.mates.size() >= Config.COOP_MAX_PLAYERS - 1:
				lines.append("The game is full. Choose a map and start: everybody's game begins together.")
			else:
				lines.append("Choose a map and start, or wait: one more friend can still join with your code.")
			_status.add_theme_color_override("font_color", UiKit.GREEN)
		elif Net.finding or (Net.code == "" and Net.door == 1):
			lines.append("Finding out your code...")
		elif Net.code != "":
			lines.append("Tell this code to your friends. They type it in on this screen and press JOIN.")
			lines.append("If a friend sends you a REPLY CODE, type it in above and press LET IN.")
			if Net.strict:
				lines.append("(Your internet connection is the strict kind: if nobody gets in, let a friend host.)")
		else:
			lines.append("Could not find out your internet address. Is the internet working?")
		if Net.mates.is_empty() and Net.lan_code != "" and not Net.finding:
			lines.append("Somebody in the SAME HOUSE can type  %s  instead." % Net.lan_code)
		if Net.status != "" and not Net.finding and (Net.code == "" or not Net.status.begins_with("Waiting")):
			lines.append(Net.status)
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
	_big.text = ""
	_refresh()
	if Net.role == Net.Role.HOST and not Net.mates.is_empty():
		_start.grab_focus()
	elif Net.role == Net.Role.NONE:
		_host.grab_focus()
	else:
		_back.grab_focus()
