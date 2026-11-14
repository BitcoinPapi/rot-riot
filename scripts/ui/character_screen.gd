class_name CharacterScreen
extends Control
## The character's skill tree. Skill points (one per level, more for coins)
## are spent on nodes of a big web: eight branches, one per passive stat,
## joined by arcs, with sealed nodes, keystones and endless nodes further
## out. The tree itself is described in scripts/game/skill_tree.gd, its
## numbers are in Config (SKILL TREE), what is learned lives in SaveData.

const PANEL_WIDTH := 348.0
const START_ZOOM := 0.62

var main: Main
var _tree: TreeView
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _points: Label
var _coins: Label
var _notice: Label
var _name: Label
var _kind: Label
var _effect: Label
var _detail: Label
var _need: Label
var _learn: Button
var _stats := {}           # passive id -> Label
var _buy: Button
var _reset: Button
var _back: Button
var _reset_armed := false
var _shown := ""           # node id in the info card


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- the tree, with zoom buttons in its corner ---
	_tree = TreeView.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.node_selected.connect(_show_node)
	_tree.node_activated.connect(_on_node_activated)
	row.add_child(_tree)
	_tree.add_zoom_buttons()
	_notice = UiKit.label("", 15, UiKit.GOLD)
	_notice.position = Vector2(66, 14)
	_tree.add_child(_notice)

	# --- side panel ---
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.label("SKILL TREE", 24, UiKit.TEXT))
	_level = UiKit.label("LEVEL 1", 22, UiKit.GOLD)
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_level)
	col.add_child(head)
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 12)
	col.add_child(_xp_bar)
	_xp_text = UiKit.label("", 12, UiKit.DIM)
	col.add_child(_xp_text)
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 10)
	_points = UiKit.label("", 21, UiKit.GOLD)
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet.add_child(_points)
	var counter := UiKit.coin_counter(20)
	_coins = counter[1]
	wallet.add_child(counter[0])
	col.add_child(wallet)

	# The node under the cursor.
	# (Inside a scroll box so that a long description can never push the
	# buttons below it off the screen.)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	col.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 178)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info)
	_name = UiKit.label("", 21, UiKit.TEXT)
	info.add_child(_name)
	_kind = UiKit.label("", 12, UiKit.DIM)
	info.add_child(_kind)
	_effect = _wrapped(15, UiKit.GREEN)
	info.add_child(_effect)
	_need = _wrapped(13, Color(1.0, 0.55, 0.45))
	info.add_child(_need)
	_detail = _wrapped(13, UiKit.DIM)
	info.add_child(_detail)
	_learn = UiKit.button("LEARN", func() -> void: _on_node_activated(_shown), PANEL_WIDTH - 40.0)
	_learn.custom_minimum_size.y = 46
	col.add_child(_learn)

	# What the tree adds up to.
	for id: String in Config.PASSIVE_ORDER:
		var line := UiKit.label("", 13, Config.PASSIVES[id]["color"])
		col.add_child(line)
		_stats[id] = line

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 6)
	_buy = UiKit.button("", _on_buy, (PANEL_WIDTH - 46.0) * 0.5)
	_buy.custom_minimum_size.y = 46
	_buy.add_theme_font_size_override("font_size", 16)
	shop.add_child(_buy)
	_reset = UiKit.button("", _on_reset, (PANEL_WIDTH - 46.0) * 0.5)
	_reset.custom_minimum_size.y = 46
	_reset.add_theme_font_size_override("font_size", 16)
	shop.add_child(_reset)
	col.add_child(shop)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), PANEL_WIDTH - 40.0)
	_back.custom_minimum_size.y = 46
	col.add_child(_back)

	_tree.set_tree(_view_nodes())
	var guides: Array = []
	var rings: Array = Config.TREE_RINGS
	for ring in range(1, rings.size()):
		guides.append({"radius": Config.TREE_START_RADIUS + Config.TREE_STEP * (float(ring * Config.TREE_SPINE_PER_RING) - 0.5),
				"text": "LEVEL %d" % int(rings[ring]["level"]), "open": false, "level": int(rings[ring]["level"])})
	_tree.guides = guides


static func _wrapped(font_size: int, color: Color) -> Label:
	var l := UiKit.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 76.0, 0)
	return l


## Turn the skill tree's nodes into what the TreeView draws.
static func _view_nodes() -> Array:
	var sizes := {"start": 27.0, "small": 11.0, "arc": 11.0, "notable": 18.0, "sealed": 17.0, "keystone": 28.0, "mastery": 21.0}
	var out: Array = []
	for id: String in SkillTree.order():
		var n: Dictionary = SkillTree.nodes()[id]
		var kind := String(n["kind"])
		var stat := String(n["stat"])
		var color := Color(0.93, 0.9, 0.82) if stat == "" else (Config.PASSIVES[stat]["color"] as Color)
		var color2 := color if String(n["stat2"]) == "" else (Config.PASSIVES[String(n["stat2"])]["color"] as Color)
		var icon := ""
		var shape := "circle"
		match kind:
			"start":
				icon = "ui_person"
			"notable":
				icon = "stat_" + stat
			"sealed":
				icon = "stat_" + stat
				shape = "hex"
			"keystone":
				icon = "ui_star"
				shape = "diamond"
			"mastery":
				icon = "ui_infinity"
		out.append({"id": id, "pos": n["pos"], "radius": sizes[kind], "shape": shape, "color": color, "color2": color2,
				"icon": icon, "links": n["links"]})
	return out


# ----------------------------------------------------------------------------
#  Actions
# ----------------------------------------------------------------------------
func _on_node_activated(id: String) -> void:
	if id == "" or not SkillTree.has(id):
		return
	if SaveData.learn_node(id):
		Sfx.play("ui_buy")
		var kind := String(SkillTree.nodes()[id]["kind"])
		if kind == "keystone" or kind == "sealed":
			Sfx.play("level_up", -6.0)
	elif id != "start" and SaveData.node_status(id) != SkillTree.OWNED:
		Sfx.play("ui_deny")
	_refresh()


func _on_buy() -> void:
	if SaveData.buy_skill_point():
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _buy.disabled:
		_tree.grab_focus()


## Resetting costs coins, so it asks once before doing it.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	if SaveData.respec():
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _reset.disabled:
		_tree.grab_focus()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
func _refresh() -> void:
	_level.text = "LEVEL %d" % SaveData.level
	if SaveData.at_level_cap():
		_xp_bar.set_fraction(1.0)
		_xp_text.text = "Maximum level reached"
	else:
		_xp_bar.set_fraction(float(SaveData.xp) / float(SaveData.xp_needed()))
		_xp_text.text = "%d / %d XP to level %d  (the highest is %d)" % [
				SaveData.xp, SaveData.xp_needed(), SaveData.level + 1, Config.LEVEL_CAP]
	_points.text = "SKILL POINTS: %d" % SaveData.skill_points
	_coins.text = "%d" % SaveData.coins
	_notice.text = "The skill tree has changed: %d skill points were handed back to you. Spend them here." % SaveData.points_returned \
			if SaveData.points_returned > 0 else ""

	# How every node looks.
	var states := {}
	var badges := {}
	for id: String in SkillTree.order():
		var n: Dictionary = SkillTree.nodes()[id]
		var count := SaveData.node_count(id)
		if count > 0:
			states[id] = TreeView.OWNED
			if bool(n["repeat"]):
				badges[id] = "x%d" % count
		elif SaveData.level < int(n["level"]) or not SaveData.deed_done(n["deed"]):
			states[id] = TreeView.LOCKED
		elif not SaveData.node_touches_learned(id):
			states[id] = TreeView.FAR
		elif SaveData.skill_points < SaveData.node_cost(id):
			states[id] = TreeView.POOR
		else:
			states[id] = TreeView.READY
	_tree.set_states(states, badges)
	for g: Dictionary in _tree.guides:
		g["open"] = SaveData.level >= int(g["level"])

	for id: String in Config.PASSIVE_ORDER:
		var line: Label = _stats[id]
		var rank := SaveData.passive_rank(id)
		line.text = "%s %d   %s%s" % [String(Config.PASSIVES[id]["name"]), rank,
				PlayerStats.describe_passive(id, SaveData.passive_value(id)),
				"   + %s" % String(Config.KEYSTONES[id]["name"]) if SaveData.has_keystone(id) else ""]
		line.modulate = Color(1, 1, 1, 1.0 if rank > 0 else 0.5)

	var price := SaveData.skill_point_price()
	_buy.text = "BUY POINT  %d" % price
	_buy.disabled = SaveData.coins < price
	var respec := SaveData.respec_price()
	_reset.text = ("SURE?  %d" if _reset_armed else "RESET  %d") % respec
	_reset.disabled = SaveData.spent_points() <= 0 or SaveData.coins < respec
	_show_node(_shown if _shown != "" else "start")


## Fill the info card for a node.
func _show_node(id: String) -> void:
	if not SkillTree.has(id):
		return
	_shown = id
	var n: Dictionary = SkillTree.nodes()[id]
	var kind := String(n["kind"])
	var stat := String(n["stat"])
	var count := SaveData.node_count(id)
	var cost := SaveData.node_cost(id)
	var status := SaveData.node_status(id)
	_name.text = String(n["name"]).to_upper()
	_name.add_theme_color_override("font_color", UiKit.TEXT if stat == "" else (Config.PASSIVES[stat]["color"] as Color))
	var kinds := {"start": "Where every survivor begins", "small": "Small node", "arc": "Link between two branches",
			"notable": "Big node", "sealed": "Sealed node", "keystone": "KEYSTONE  -  a special power",
			"mastery": "Endless node  -  can be learned again and again"}
	_kind.text = kinds[kind]

	# What it gives, and what the stat becomes.
	var effects: Array[String] = []
	var details: Array[String] = []
	var ranks: Dictionary = n["ranks"]
	for passive: String in ranks.keys():
		var add := int(ranks[passive])
		var def: Dictionary = Config.PASSIVES[passive]
		var rank := SaveData.passive_rank(passive)
		effects.append("+%d %s" % [add, String(def["name"])])
		if count > 0 and not bool(n["repeat"]):
			details.append("%s. You have %s." % [String(def["desc"]), PlayerStats.describe_passive(passive, SaveData.passive_value(passive))])
		else:
			details.append("%s: %s, then %s." % [String(def["desc"]), PlayerStats.describe_passive(passive, Config.stat_value(def, rank)),
					PlayerStats.describe_passive(passive, Config.stat_value(def, rank + add))])
	if String(n.get("note", "")) != "":
		effects.append(String(n["note"]))
	if kind == "keystone":
		effects.append(SkillTree.keystone_text(stat))
	elif kind == "start":
		effects.append("Learn a node that touches one you already have.")
		details.append("Each branch is one stat; arcs join the branches. Further out you need a higher level, and sealed nodes ask for a deed.")
	_effect.text = "\n".join(effects)
	_detail.text = "\n".join(details)
	_detail.visible = not details.is_empty()

	# What stands in the way.
	var needs: Array[String] = []
	if status != SkillTree.OWNED and id != "start":
		if SaveData.level < int(n["level"]):
			needs.append("Needs level %d (you are level %d)" % [int(n["level"]), SaveData.level])
		var deed: Dictionary = n["deed"]
		if not SaveData.deed_done(deed):
			needs.append("Sealed: %s (so far %d)" % [Config.deed_text(deed).to_lower(), SaveData.deed_progress(deed)])
		if count == 0 and not SaveData.node_touches_learned(id):
			needs.append("Not connected: learn a node next to it")
	_need.text = "\n".join(needs)
	_need.visible = not needs.is_empty()

	var points_word := "point" if cost == 1 else "points"
	match status:
		SkillTree.OWNED:
			_learn.text = "LEARNED"
		SkillTree.READY:
			_learn.text = "LEARN   (%d %s)" % [cost, points_word]
		SkillTree.POOR:
			_learn.text = "NEEDS %d %s" % [cost, points_word.to_upper()]
		_:
			_learn.text = "LOCKED   (%d %s)" % [cost, points_word]
	if id == "start":
		_learn.text = "YOU START HERE"
	_learn.disabled = status != SkillTree.READY or id == "start"


func opened() -> void:
	_reset_armed = false
	_refresh()
	_tree.grab_focus()
	if _tree.selected == "":
		_tree.look_at_point(Vector2.ZERO, START_ZOOM)
		_tree.select("start")
