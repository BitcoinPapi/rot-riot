class_name ArmoryScreen
extends Control
## The Armory: every weapon has its own level (from kills made with it) and
## its own upgrade tree. A weapon's points (one per weapon level) are spent on
## its tree: a branch per upgrade, arcs between them, three perks that change
## how the weapon works, and endless nodes at the tips. The trees are
## described in scripts/game/weapon_tree.gd, their numbers are in Config
## (WEAPON TREES), what is learned lives in SaveData.

const LIST_WIDTH := 236.0
const PANEL_WIDTH := 336.0
const START_ZOOM := 0.56

var main: Main
var _selected := ""
var _weapon_buttons := {}     # weapon id -> Button
var _tree: TreeView
var _notice: Label
var _icon: TextureRect
var _name: Label
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _points: Label
var _crate: Label
var _node_name: Label
var _node_kind: Label
var _effect: Label
var _need: Label
var _detail: Label
var _learn: Button
var _totals: Label
var _reset: Button
var _back: Button
var _reset_armed := false
var _shown := "start"         # node id in the info card


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- left: the weapons ---
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	row.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list_panel.add_child(list)
	list.add_child(UiKit.heading("ARMORY", 30))
	var blurb := UiKit.heading("Kills level a weapon up. Every level is a point for its tree.", 12, UiKit.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(LIST_WIDTH - 50.0, 0)
	list.add_child(blurb)
	for id: String in Config.WEAPON_ORDER:
		var b := UiKit.button("", func() -> void: _on_weapon_pressed(id), LIST_WIDTH - 50.0)
		b.custom_minimum_size = Vector2(LIST_WIDTH - 50.0, 42)
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Keyboard / gamepad: moving onto a weapon shows its tree. (With the
		# mouse you click, so that crossing the list does not flip trees.)
		b.focus_entered.connect(func() -> void:
			if not b.is_hovered():
				_select(id))
		list.add_child(b)
		_weapon_buttons[id] = b
	var list_filler := Control.new()
	list_filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(list_filler)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), LIST_WIDTH - 50.0)
	_back.custom_minimum_size.y = 46
	list.add_child(_back)

	# --- middle: the selected weapon's tree ---
	_tree = TreeView.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.zoom = START_ZOOM
	_tree.node_selected.connect(_show_node)
	_tree.node_activated.connect(_on_node_activated)
	row.add_child(_tree)
	_tree.add_zoom_buttons()
	_notice = UiKit.label("", 14, UiKit.GOLD)
	_notice.position = Vector2(66, 14)
	_tree.add_child(_notice)

	# --- right: the weapon and the node under the cursor ---
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(176, 64)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(_icon)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_name = UiKit.label("", 23)
	head.add_child(_name)
	_level = UiKit.label("", 20, UiKit.GOLD)
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_level)
	col.add_child(head)
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 12)
	col.add_child(_xp_bar)
	_xp_text = UiKit.label("", 12, UiKit.DIM)
	col.add_child(_xp_text)
	_points = UiKit.label("", 20, UiKit.GOLD)
	col.add_child(_points)
	_crate = _wrapped(12, UiKit.DIM)
	col.add_child(_crate)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	col.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info)
	_node_name = UiKit.label("", 20, UiKit.TEXT)
	info.add_child(_node_name)
	_node_kind = UiKit.label("", 12, UiKit.DIM)
	info.add_child(_node_kind)
	_effect = _wrapped(15, UiKit.GREEN)
	info.add_child(_effect)
	_need = _wrapped(13, Color(1.0, 0.55, 0.45))
	info.add_child(_need)
	_detail = _wrapped(13, UiKit.DIM)
	info.add_child(_detail)
	_learn = UiKit.button("LEARN", func() -> void: _on_node_activated(_shown), PANEL_WIDTH - 40.0)
	_learn.custom_minimum_size.y = 44
	col.add_child(_learn)

	_totals = UiKit.label("", 13, UiKit.TEXT)
	col.add_child(_totals)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	_reset = UiKit.button("", _on_reset, PANEL_WIDTH - 40.0)
	_reset.custom_minimum_size.y = 42
	_reset.add_theme_font_size_override("font_size", 16)
	col.add_child(_reset)


static func _wrapped(font_size: int, color: Color) -> Label:
	var l := UiKit.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 76.0, 0)
	return l


## Turn a weapon's tree into what the TreeView draws.
static func _view_nodes(weapon_id: String) -> Array:
	var sizes := {"start": 31.0, "small": 11.0, "arc": 11.0, "notable": 18.0, "perk": 23.0, "mastery": 20.0}
	var weapon_color: Color = Config.WEAPONS[weapon_id]["color"]
	var out: Array = []
	for id: String in WeaponTree.order(weapon_id):
		var n: Dictionary = WeaponTree.nodes(weapon_id)[id]
		var kind := String(n["kind"])
		var track := String(n["track"])
		var color := weapon_color if track == "" else (Config.WEAPON_TRACKS[track]["color"] as Color)
		var icon := ""
		var shape := "circle"
		match kind:
			"start":
				icon = "gun_" + weapon_id
			"notable":
				icon = "track_" + track
			"perk":
				icon = "ui_perk"
				shape = "hex"
				color = UiKit.GOLD
			"mastery":
				icon = "ui_infinity"
		out.append({"id": id, "pos": n["pos"], "radius": sizes[kind], "shape": shape, "color": color, "color2": color,
				"icon": icon, "links": n["links"]})
	return out


# ----------------------------------------------------------------------------
#  Actions
# ----------------------------------------------------------------------------
func _on_weapon_pressed(id: String) -> void:
	_select(id)
	_tree.grab_focus()


func _select(id: String) -> void:
	if id != _selected:
		_selected = id
		_reset_armed = false
		_shown = "start"
		_tree.set_tree(_view_nodes(id))
		var guides: Array = []
		var tiers: Array = Config.WEAPON_TREE_TIERS
		for tier in range(1, tiers.size()):
			guides.append({"radius": Config.WEAPON_TREE_START_RADIUS + Config.WEAPON_TREE_STEP * (float(tier * Config.WEAPON_TREE_PER_TIER) - 0.5),
					"text": "WEAPON LEVEL %d" % int(tiers[tier]["level"]), "open": false, "level": int(tiers[tier]["level"])})
		guides.append({"radius": Config.WEAPON_TREE_START_RADIUS + Config.WEAPON_TREE_STEP * (float(tiers.size() * Config.WEAPON_TREE_PER_TIER) - 0.35),
				"text": "WEAPON LEVEL %d" % Config.WEAPON_TREE_ENDLESS_LEVEL, "open": false, "level": Config.WEAPON_TREE_ENDLESS_LEVEL})
		_tree.guides = guides
		_tree.look_at_point(Vector2.ZERO, START_ZOOM)
		_tree.select("start")
	_refresh()


func _on_node_activated(id: String) -> void:
	if id == "" or not WeaponTree.has(_selected, id):
		return
	if SaveData.learn_weapon_node(_selected, id):
		Sfx.play("ui_buy")
		if String(WeaponTree.nodes(_selected)[id]["kind"]) == "perk":
			Sfx.play("weapon_level", -4.0)
	elif id != "start" and SaveData.weapon_node_status(_selected, id) != SkillTree.OWNED:
		Sfx.play("ui_deny")
	_refresh()


## Resetting costs coins, so it asks once before doing it.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	if SaveData.respec_weapon(_selected):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _reset.disabled:
		_tree.grab_focus()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
## Share of crates that hold this weapon, counting rarity and SPAWN RATE upgrades.
func _crate_share(id: String) -> float:
	var total := 0.0
	var mine := 0.0
	for other: String in Config.CRATE_WEAPONS:
		var weight: float = Config.crate_weight(other) * (1.0 + SaveData.weapon_value(other, "spawn"))
		total += weight
		if other == id:
			mine = weight
	return mine / total if total > 0.0 else 0.0


func _refresh() -> void:
	for id: String in Config.WEAPON_ORDER:
		var b: Button = _weapon_buttons[id]
		var waiting := SaveData.weapon_points(id)
		b.text = "%s  LV %d%s" % [String(Config.WEAPONS[id]["name"]), SaveData.weapon_level(id), "   (%d)" % waiting if waiting > 0 else ""]
		if id == _selected:
			b.add_theme_stylebox_override("normal", UiKit.card_style(Config.WEAPONS[id]["color"]))
		else:
			b.remove_theme_stylebox_override("normal")
	_notice.text = "Weapon upgrades are trees now: %d weapon points were handed back. Spend them here." % SaveData.weapon_points_returned \
			if SaveData.weapon_points_returned > 0 else ""

	var w: Dictionary = Config.WEAPONS[_selected]
	var weapon_level := SaveData.weapon_level(_selected)
	var points_now := SaveData.weapon_points(_selected)
	_icon.texture = Art.t("icon_" + _selected)
	_name.text = String(w["name"])
	_name.add_theme_color_override("font_color", w["color"])
	_level.text = "LEVEL %d" % weapon_level
	_xp_bar.fill = w["color"]
	_xp_bar.set_fraction(float(SaveData.weapon_xp(_selected)) / float(SaveData.weapon_xp_needed(_selected)))
	_xp_text.text = "%d / %d XP to level %d" % [SaveData.weapon_xp(_selected), SaveData.weapon_xp_needed(_selected), weapon_level + 1]
	_points.text = "WEAPON POINTS: %d" % points_now
	var rarity: Dictionary = Config.CRATE_RARITIES[String(w["rarity"])]
	if _selected == Config.STARTER_WEAPON:
		_crate.text = "Always with you. A pistol crate (%d%% of crates) gives a second one." % int(round(_crate_share(_selected) * 100.0))
		_crate.add_theme_color_override("font_color", UiKit.DIM)
	else:
		_crate.text = "%s  -  in %d%% of crates%s" % [String(rarity["name"]), int(round(_crate_share(_selected) * 100.0)),
				"  -  can be dual wielded" if bool(w["dual"]) else ""]
		_crate.add_theme_color_override("font_color", rarity["color"])

	# How every node looks.
	var states := {}
	var badges := {}
	for id: String in WeaponTree.order(_selected):
		var n: Dictionary = WeaponTree.nodes(_selected)[id]
		var count := SaveData.weapon_node_count(_selected, id)
		if count > 0:
			states[id] = TreeView.OWNED
			if bool(n["repeat"]):
				badges[id] = "x%d" % count
		elif weapon_level < int(n["level"]):
			states[id] = TreeView.LOCKED
		elif not SaveData.weapon_node_touches_learned(_selected, id):
			states[id] = TreeView.FAR
		elif points_now < SaveData.weapon_node_cost(_selected, id):
			states[id] = TreeView.POOR
		else:
			states[id] = TreeView.READY
	_tree.set_states(states, badges)
	for g: Dictionary in _tree.guides:
		g["open"] = weapon_level >= int(g["level"])

	# What the tree adds up to.
	var lines: Array[String] = []
	for track: String in Config.weapon_tracks(_selected):
		lines.append("%s %d   %s" % [String(Config.WEAPON_TRACKS[track]["name"]), SaveData.weapon_rank(_selected, track),
				PlayerStats.describe_track(track, SaveData.weapon_value(_selected, track))])
	var perks: Array = Config.WEAPON_PERKS[_selected]
	for i in perks.size():
		if SaveData.weapon_has_perk(_selected, i):
			lines.append("PERK: %s" % String(perks[i]["name"]))
	_totals.text = "\n".join(lines)

	var price := SaveData.weapon_respec_price(_selected)
	_reset.text = ("SURE?  %d coins" if _reset_armed else "RESET THIS TREE  %d") % price
	_reset.disabled = SaveData.weapon_spent(_selected) <= 0 or SaveData.coins < price
	_show_node(_shown)


## Fill the info card for a node of the selected weapon's tree.
func _show_node(id: String) -> void:
	if _selected == "" or not WeaponTree.has(_selected, id):
		return
	_shown = id
	var n: Dictionary = WeaponTree.nodes(_selected)[id]
	var kind := String(n["kind"])
	var track := String(n["track"])
	var count := SaveData.weapon_node_count(_selected, id)
	var cost := SaveData.weapon_node_cost(_selected, id)
	var status := SaveData.weapon_node_status(_selected, id)
	var weapon_level := SaveData.weapon_level(_selected)
	_node_name.text = String(n["name"])
	var title_color: Color = Config.WEAPONS[_selected]["color"]
	if kind == "perk":
		title_color = UiKit.GOLD
	elif track != "":
		title_color = Config.WEAPON_TRACKS[track]["color"]
	_node_name.add_theme_color_override("font_color", title_color)
	var kinds := {"start": "Its tree starts here", "small": "Small node", "arc": "Link between two branches",
			"notable": "Big node", "perk": "PERK  -  changes how the weapon works",
			"mastery": "Endless node  -  can be learned again and again"}
	_node_kind.text = kinds[kind]

	var effects: Array[String] = []
	var details: Array[String] = []
	var ranks: Dictionary = n["ranks"]
	for key: String in ranks.keys():
		var add := int(ranks[key])
		var def: Dictionary = Config.WEAPON_TRACKS[key]
		var rank := SaveData.weapon_rank(_selected, key)
		effects.append("+%d %s" % [add, String(def["name"])])
		if count > 0 and not bool(n["repeat"]):
			details.append("%s. This weapon has %s." % [String(def["desc"]), PlayerStats.describe_track(key, SaveData.weapon_value(_selected, key))])
		else:
			details.append("%s: %s, then %s." % [String(def["desc"]), PlayerStats.describe_track(key, Config.stat_value(def, rank)),
					PlayerStats.describe_track(key, Config.stat_value(def, rank + add))])
	if kind == "perk":
		effects.append(String(WeaponTree.perk(_selected, int(n["perk"]))["desc"]))
	elif kind == "start":
		effects.append("Learn a node that touches one this weapon already has.")
		details.append("Each branch is one upgrade. The gold hexagons are perks. Rings further out need a higher weapon level.")
	_effect.text = "\n".join(effects)
	_detail.text = "\n".join(details)
	_detail.visible = not details.is_empty()

	var needs: Array[String] = []
	if status != SkillTree.OWNED and id != "start":
		if weapon_level < int(n["level"]):
			needs.append("Needs weapon level %d (it is level %d)" % [int(n["level"]), weapon_level])
		if count == 0 and not SaveData.weapon_node_touches_learned(_selected, id):
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
		_learn.text = "KILL WITH IT TO LEVEL IT"
	_learn.disabled = status != SkillTree.READY or id == "start"


func opened() -> void:
	# Open on a weapon that has points to spend, if there is one.
	var start := _selected if _selected != "" else Config.STARTER_WEAPON
	for id: String in Config.WEAPON_ORDER:
		if SaveData.weapon_points(id) > 0:
			start = id
			break
	_reset_armed = false
	_select(start)
	_tree.grab_focus()
