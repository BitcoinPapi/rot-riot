class_name SkillScreen
extends Control
## The Skills screen: the skill tree. Skill points (one per character level,
## more for coins) buy levels of its nodes. The tree has three families -
## VITALITY, STRENGTH and INSTINCT - each in its own colour, so it is always clear
## where the points have gone. The tree itself is described in
## scripts/game/skill_tree.gd, its numbers are in Config (SKILL TREE), what
## has been bought lives in SaveData.

const PANEL_WIDTH := 348.0

var main: Main
var _tree: SkillTreeView
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
var _families := {}        # family id -> {"points": Label, "bar": UiKit.Bar}
var _buy: Button
var _reset: Button
var _back: Button
var _reset_armed := false
var _shown := "start"      # node id in the info card


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- the tree ---
	_tree = SkillTreeView.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hint = "Click a node to add a level   -   drag to move   -   scroll to zoom"
	_tree.hint_gamepad = "Stick: next node   -   A: add a level   -   Y: other buttons   -   B: back"
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
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.label("SKILLS", 26, UiKit.TEXT))
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
	_points = UiKit.label("", 22, UiKit.GOLD)
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet.add_child(_points)
	var counter := UiKit.coin_counter(20)
	_coins = counter[1]
	wallet.add_child(counter[0])
	col.add_child(wallet)

	# The node under the cursor. (In a scroll box, so that a long description
	# can never push the buttons below it off the screen.)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	col.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 218)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info)
	_name = UiKit.label("", 21, UiKit.TEXT)
	info.add_child(_name)
	_kind = UiKit.label("", 13, UiKit.DIM)
	info.add_child(_kind)
	_effect = _wrapped(15, UiKit.GREEN)
	info.add_child(_effect)
	_need = _wrapped(13, Color(1.0, 0.55, 0.45))
	info.add_child(_need)
	_detail = _wrapped(13, UiKit.DIM)
	info.add_child(_detail)
	_learn = UiKit.button("LEARN", func() -> void: _on_node_activated(_shown), PANEL_WIDTH - 40.0)
	_learn.custom_minimum_size.y = 46
	_learn.add_theme_font_size_override("font_size", 21)
	col.add_child(_learn)

	# Where the points have gone.
	col.add_child(UiKit.spacer(2))
	col.add_child(UiKit.label("WHERE YOUR POINTS ARE", 13, UiKit.DIM))
	for family: String in Config.TREE_FAMILY_ORDER:
		var def: Dictionary = Config.TREE_FAMILIES[family]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = Art.t("family_" + family)
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = def["color"]
		line.add_child(icon)
		var title := UiKit.label(String(def["name"]), 16, def["color"])
		title.custom_minimum_size = Vector2(86, 0)
		line.add_child(title)
		var bar := UiKit.Bar.new()
		bar.custom_minimum_size = Vector2(120, 10)
		bar.fill = def["color"]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		var spent := UiKit.label("0", 15, UiKit.TEXT)
		spent.custom_minimum_size = Vector2(34, 0)
		spent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(spent)
		col.add_child(line)
		_families[family] = {"points": spent, "bar": bar}

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


static func _wrapped(font_size: int, color: Color) -> Label:
	var l := UiKit.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 76.0, 0)
	return l


## Turn the skill tree's nodes into what the view draws.
static func _view_nodes() -> Array:
	var sizes := {"start": 31.0, "root": 27.0, "node": 23.0, "sealed": 17.0, "keystone": 26.0, "cap": 36.0}
	var out: Array = []
	for id: String in SkillTree.order():
		var n: Dictionary = SkillTree.nodes()[id]
		var kind := String(n["kind"])
		var family := String(n["family"])
		var color := Color(0.93, 0.9, 0.82) if family == "" else (Config.TREE_FAMILIES[family]["color"] as Color)
		var icon := ""
		var shape := "circle"
		match kind:
			"start":
				icon = "ui_person"
			"root", "cap":
				icon = "family_" + family
			"node":
				icon = "stat_" + String(n["stat"])
			"sealed":
				icon = "stat_" + String(n["stat"])
				shape = "hex"
			"keystone":
				icon = "ui_star"
				shape = "diamond"
		out.append({"id": id, "pos": n["pos"], "radius": sizes[kind], "shape": shape, "color": color, "color2": color,
				"icon": icon, "links": n["requires"], "parents": n["requires"], "kind": kind})
	return out


# ----------------------------------------------------------------------------
#  Actions
# ----------------------------------------------------------------------------
func _on_node_activated(id: String) -> void:
	if id == "" or not SkillTree.has(id):
		return
	if SaveData.learn_node(id):
		Sfx.play("ui_buy")
		var n: Dictionary = SkillTree.nodes()[id]
		_tree.burst(id, Config.TREE_FAMILIES[String(n["family"])]["color"])
		if String(n["kind"]) == "keystone" or String(n["kind"]) == "sealed":
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
	_notice.text = "The skill tree is new: %d skill points were handed back to you. Spend them here." % SaveData.points_returned \
			if SaveData.points_returned > 0 else ""

	# How every node looks, and how many of its levels are bought.
	var states := {}
	var levels := {}
	for id: String in SkillTree.order():
		var n: Dictionary = SkillTree.nodes()[id]
		levels[id] = Vector2i(SaveData.node_count(id), int(n["max"]))
		if id == "start":
			states[id] = TreeView.OWNED
			continue
		match SaveData.node_status(id):
			SkillTree.OWNED:
				states[id] = TreeView.OWNED
			SkillTree.READY:
				states[id] = TreeView.READY
			SkillTree.POOR:
				states[id] = TreeView.POOR
			SkillTree.FAR:
				states[id] = TreeView.FAR
			_:
				states[id] = TreeView.LOCKED
	_tree.set_states(states)

	# What has gone into each family.
	var total := 0
	for family: String in Config.TREE_FAMILY_ORDER:
		total += SaveData.family_points(family)
	var info: Array = []
	for family: String in Config.TREE_FAMILY_ORDER:
		var def: Dictionary = Config.TREE_FAMILIES[family]
		var spent := SaveData.family_points(family)
		var cap: Dictionary = SkillTree.nodes()["%s.cap" % family]
		var out := Vector2.from_angle(deg_to_rad(float(def["angle_deg"])))
		info.append({"name": def["name"], "desc": def["desc"], "color": def["color"], "points": spent,
				"label": (cap["pos"] as Vector2) + (Vector2(signf(out.x) * 30.0, 82.0) if out.y > 0.0 else Vector2(0.0, -100.0)),
				"haze": out * (Config.TREE_ROOT_DIST + Config.TREE_STEP * 2.0)})
		var row: Dictionary = _families[family]
		(row["points"] as Label).text = "%d" % spent
		(row["bar"] as UiKit.Bar).set_fraction(float(spent) / float(total) if total > 0 else 0.0)
	_tree.set_levels(levels, info)

	var price := SaveData.skill_point_price()
	_buy.text = "BUY POINT  %d" % price
	_buy.disabled = SaveData.coins < price
	var respec := SaveData.respec_price()
	_reset.text = ("SURE?  %d" if _reset_armed else "RESET  %d") % respec
	_reset.disabled = SaveData.spent_points() <= 0 or SaveData.coins < respec
	_show_node(_shown)


## Fill the info card for a node.
func _show_node(id: String) -> void:
	if not SkillTree.has(id):
		return
	_shown = id
	var n: Dictionary = SkillTree.nodes()[id]
	var kind := String(n["kind"])
	var family := String(n["family"])
	var count := SaveData.node_count(id)
	var most := int(n["max"])
	var cost := SaveData.node_cost(id)
	var status := SaveData.node_status(id)
	_name.text = String(n["name"]).to_upper()
	_name.add_theme_color_override("font_color", UiKit.TEXT if family == "" else (Config.TREE_FAMILIES[family]["color"] as Color))
	if id == "start":
		_kind.text = "Every family grows out of here"
	elif most <= 0:
		_kind.text = "%s  -  endless  -  level %d" % [String(Config.TREE_FAMILIES[family]["name"]), count]
	elif most == 1:
		_kind.text = "%s  -  %s" % [String(Config.TREE_FAMILIES[family]["name"]),
				"KEYSTONE: a special power" if kind == "keystone" else "sealed node"]
	else:
		_kind.text = "%s  -  level %d of %d" % [String(Config.TREE_FAMILIES[family]["name"]), count, most]

	# What a level gives, and what the stat becomes.
	var effects: Array[String] = []
	var details: Array[String] = []
	var ranks: Dictionary = n["ranks"]
	var per_level := " per level" if most != 1 else ""
	for passive: String in ranks.keys():
		var add := int(ranks[passive])
		var def: Dictionary = Config.PASSIVES[passive]
		var rank := SaveData.passive_rank(passive)
		effects.append("+%d %s%s" % [add, String(def["name"]), per_level])
		if status == SkillTree.OWNED:
			details.append("%s: %s." % [String(def["desc"]), PlayerStats.describe_passive(passive, SaveData.passive_value(passive))])
		else:
			details.append("%s: %s, then %s." % [String(def["desc"]), PlayerStats.describe_passive(passive, Config.stat_value(def, rank)),
					PlayerStats.describe_passive(passive, Config.stat_value(def, rank + add))])
	if String(n.get("note", "")) != "":
		effects.append(String(n["note"]))
	if kind == "keystone":
		effects.append(SkillTree.keystone_text(String(n["stat"])))
	elif id == "start":
		effects.append("Three families: VITALITY keeps you alive, STRENGTH kills faster, INSTINCT is speed, luck and your pet.")
		details.append("Start a family with its first node. Put %d levels into a node and the next one along its branch opens." % Config.TREE_NEED_LEVELS)
	_effect.text = "\n".join(effects)
	_detail.text = "\n".join(details)
	_detail.visible = not details.is_empty()

	# What stands in the way.
	var needs: Array[String] = []
	if status != SkillTree.OWNED and id != "start":
		if not SaveData.node_requirement_met(id):
			var names: Array[String] = []
			for other: String in n["requires"]:
				names.append(String(SkillTree.nodes()[other]["name"]).to_upper())
			var need_count := int(n["requires_count"])
			if kind == "cap":
				needs.append("Needs one keystone of this family")
			elif need_count <= 1:
				needs.append("Needs %s first" % " or ".join(names))
			else:
				needs.append("Needs %d levels in %s" % [need_count, " or ".join(names)])
		if SaveData.level < int(n["level"]):
			needs.append("Needs character level %d (you are level %d)" % [int(n["level"]), SaveData.level])
		var deed: Dictionary = n["deed"]
		if not SaveData.deed_done(deed):
			needs.append("Sealed: %s (so far %d)" % [Config.deed_text(deed).to_lower(), SaveData.deed_progress(deed)])
	_need.text = "\n".join(needs)
	_need.visible = not needs.is_empty()

	var points_word := "point" if cost == 1 else "points"
	match status:
		SkillTree.OWNED:
			_learn.text = "LEARNED" if most == 1 else "ALL %d LEVELS BOUGHT" % most
		SkillTree.READY:
			_learn.text = ("LEARN   (%d %s)" if most == 1 else "ADD A LEVEL   (%d %s)") % [cost, points_word]
		SkillTree.POOR:
			_learn.text = "NEEDS %d %s" % [cost, points_word.to_upper()]
		_:
			_learn.text = "LOCKED   (%d %s)" % [cost, points_word]
	if id == "start":
		_learn.text = "PICK A FAMILY"
	_learn.disabled = status != SkillTree.READY or id == "start"


func opened() -> void:
	_reset_armed = false
	_refresh()
	_tree.grab_focus()
	if _tree.selected == "":
		_tree.select("start")
	# Show the whole tree (once the screen has been laid out).
	await get_tree().process_frame
	await get_tree().process_frame
	_tree.fit()
