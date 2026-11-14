class_name GearScreen
extends Control
## The Gear screen. In the middle the survivor's nine slots are laid out
## like a body; around them every piece of gear in the game has a row of
## five nodes, one per tier. Pieces you own are lit, pieces you have never
## found are locked, and a node glows when two pieces of the tier below are
## in the bag and can be forged into it.
##
## The pieces, tiers and forging odds are in Config (GEAR section), the layout
## comes from scripts/game/gear_tree.gd, what the player owns is in SaveData.

const PANEL_WIDTH := 348.0
const START_ZOOM := 0.56
const EMPTY_COLOR := Color(0.72, 0.72, 0.68)

var main: Main
var _tree: TreeView
var _view := {}               # node id -> the Dictionary the TreeView draws
var _count: Label
var _name: Label
var _kind: Label
var _effect: Label
var _need: Label
var _detail: Label
var _banner: Label
var _wear: Button
var _forge: Button
var _totals: Label
var _back: Button
var _shown := ""              # node id in the info card
var _armed := ""              # node id whose risky forging is waiting for a second press


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_tree = TreeView.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.zoom = START_ZOOM
	_tree.hint = "Drag to move   -   scroll to zoom   -   click a piece to wear it, a glowing node to forge it"
	_tree.hint_gamepad = "Stick: next node   -   A: wear / forge   -   Y: other buttons   -   B: back"
	_tree.node_selected.connect(_on_node_selected)
	_tree.node_activated.connect(_on_node_activated)
	row.add_child(_tree)
	_tree.add_zoom_buttons()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_child(UiKit.label("GEAR", 26, UiKit.TEXT))
	_count = UiKit.label("", 15, UiKit.DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	col.add_child(head)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	col.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info)
	_name = UiKit.label("", 21, UiKit.TEXT)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(PANEL_WIDTH - 76.0, 0)
	info.add_child(_name)
	_kind = UiKit.label("", 12, UiKit.DIM)
	info.add_child(_kind)
	_effect = _wrapped(16, UiKit.GREEN)
	info.add_child(_effect)
	_detail = _wrapped(13, UiKit.DIM)
	info.add_child(_detail)
	_need = _wrapped(13, Color(1.0, 0.6, 0.45))
	info.add_child(_need)

	_banner = _wrapped(16, UiKit.GOLD)
	_banner.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner)
	_wear = UiKit.button("", _on_wear_pressed, PANEL_WIDTH - 40.0)
	_wear.custom_minimum_size.y = 44
	_wear.add_theme_font_size_override("font_size", 19)
	col.add_child(_wear)
	_forge = UiKit.button("", _on_forge_pressed, PANEL_WIDTH - 40.0)
	_forge.custom_minimum_size.y = 44
	_forge.add_theme_font_size_override("font_size", 19)
	col.add_child(_forge)

	col.add_child(UiKit.label("WHAT YOUR GEAR GIVES", 13, UiKit.DIM))
	_totals = _wrapped(14, UiKit.TEXT)
	col.add_child(_totals)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), PANEL_WIDTH - 40.0)
	_back.custom_minimum_size.y = 46
	col.add_child(_back)

	# The web. Node colours and states are filled in by _refresh().
	var list: Array = []
	for id: String in GearTree.order():
		var n: Dictionary = GearTree.nodes()[id]
		var radius := 24.0
		var color := EMPTY_COLOR
		match String(n["kind"]):
			"type":
				radius = 13.0
			"item":
				radius = 14.0 + float(n["tier"])
				color = Config.gear_tier_def(int(n["tier"]))["color"]
		var view := {"id": id, "pos": n["pos"], "radius": radius, "shape": "hex" if String(n["kind"]) == "slot" else "circle",
				"color": color, "color2": color, "icon": "gear_" + String(n["type"]), "links": n["links"]}
		_view[id] = view
		list.append(view)
	_tree.set_tree(list)
	# A labelled ring per tier, in the tier's colour, with its forging odds.
	var guides: Array = []
	for tier in range(1, Config.GEAR_TIERS.size() + 1):
		var def := Config.gear_tier_def(tier)
		var text := String(def["name"])
		if tier > 1:
			text += "  -  forge %d%%" % int(round(float(def["chance"]) * 100.0))
		guides.append({"radius": GearTree.tier_radius(tier), "text": text, "open": true, "color": def["color"]})
	_tree.guides = guides


static func _wrapped(font_size: int, color: Color) -> Label:
	var l := UiKit.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 76.0, 0)
	return l


# ----------------------------------------------------------------------------
#  What can be done with a node
# ----------------------------------------------------------------------------
## The piece a forging started from this node would make: [item, tier], or []
## if nothing can be forged here. On a piece you hold two of, that is the next
## tier; on a glowing node it is the node itself.
func _forge_target(id: String) -> Array:
	var n: Dictionary = GearTree.nodes()[id]
	if String(n["kind"]) != "item":
		return []
	var item := String(n["item"])
	var tier := int(n["tier"])
	if SaveData.can_forge(item, tier + 1):
		return [item, tier + 1]
	if SaveData.can_forge(item, tier):
		return [item, tier]
	return []


func _on_node_selected(id: String) -> void:
	_armed = ""
	_show_node(id)


## Click / A on a node: take off a worn slot, wear a piece from the bag, or
## forge a glowing node.
func _on_node_activated(id: String) -> void:
	if not GearTree.nodes().has(id):
		return
	var n: Dictionary = GearTree.nodes()[id]
	match String(n["kind"]):
		"slot":
			_on_wear_pressed()
		"item":
			var key := Config.gear_key(String(n["item"]), int(n["tier"]))
			if SaveData.gear_count(key) > 0:
				_on_wear_pressed()
			elif not _forge_target(id).is_empty():
				_on_forge_pressed()
			else:
				Sfx.play("ui_deny")
		_:
			pass


func _on_wear_pressed() -> void:
	if not GearTree.nodes().has(_shown):
		return
	var n: Dictionary = GearTree.nodes()[_shown]
	_armed = ""
	_banner.text = ""
	var done := false
	if String(n["kind"]) == "slot":
		done = SaveData.take_off_gear(String(n["slot"]))
	elif String(n["kind"]) == "item":
		var key := Config.gear_key(String(n["item"]), int(n["tier"]))
		if SaveData.gear_count(key) > 0:
			done = SaveData.wear_gear(key)
			if done:
				_tree.burst(GearTree.slot_id(SaveData.gear_worn_slot(key)), Config.gear_tier_def(int(n["tier"]))["color"])
		elif SaveData.gear_worn_slot(key) != "":
			done = SaveData.take_off_gear(SaveData.gear_worn_slot(key))
	Sfx.play("mag_in" if done else "ui_deny")
	_refresh()


func _on_forge_pressed() -> void:
	var target := _forge_target(_shown)
	if target.is_empty():
		Sfx.play("ui_deny")
		return
	var item := String(target[0])
	var tier := int(target[1])
	var def := Config.gear_tier_def(tier)
	# Anything that can fail asks once before it is done.
	if float(def["chance"]) < 1.0 and _armed != _shown:
		_armed = _shown
		_banner.text = ""
		Sfx.play("ui_click", -4.0, 0.0)
		_refresh()
		return
	_armed = ""
	var source_id := GearTree.item_id(item, tier - 1)
	var made_id := GearTree.item_id(item, tier)
	var made_name := Config.gear_name(Config.gear_key(item, tier))
	match SaveData.forge_gear(item, tier):
		"success":
			_banner.text = "FORGED:  %s" % made_name
			_banner.add_theme_color_override("font_color", def["color"])
			_tree.burst(made_id, def["color"])
			_tree.select(made_id, true)
			Sfx.play("forge_ok")
		"fail":
			_banner.text = "THE FORGING FAILED  -  one piece was lost"
			_banner.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			_tree.burst(source_id, Color(1.0, 0.35, 0.25))
			Sfx.play("forge_fail")
		"broke":
			_banner.text = "DESTROYED  -  both pieces are gone"
			_banner.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
			_tree.burst(source_id, Color(1.0, 0.2, 0.15))
			_tree.burst(made_id, Color(1.0, 0.2, 0.15))
			Sfx.play("forge_break")
		_:
			Sfx.play("ui_deny")
	_refresh()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
func _refresh() -> void:
	var states := {}
	var badges := {}
	var owned_types := {}
	var pieces := 0
	for key: String in SaveData.gear_bag.keys():
		pieces += SaveData.gear_count(key)
		owned_types[String(Config.GEAR_ITEMS[Config.gear_item_of(key)]["type"])] = true
	for slot: String in Config.GEAR_SLOTS:
		if SaveData.gear_in_slot(slot) != "":
			pieces += 1
			owned_types[String(Config.GEAR_SLOT_TYPE[slot])] = true

	for id: String in GearTree.order():
		var n: Dictionary = GearTree.nodes()[id]
		var view: Dictionary = _view[id]
		match String(n["kind"]):
			"slot":
				var worn := SaveData.gear_in_slot(String(n["slot"]))
				var color: Color = EMPTY_COLOR if worn == "" else (Config.gear_tier_def(Config.gear_tier_of(worn))["color"] as Color)
				view["color"] = color
				view["color2"] = color
				states[id] = TreeView.OWNED if worn != "" else TreeView.POOR
				badges[id] = String(Config.GEAR_SLOT_NAMES[n["slot"]]) if worn == "" \
						else String(Config.GEAR_ITEMS[Config.gear_item_of(worn)]["name"])
			"type":
				states[id] = TreeView.OWNED if owned_types.has(String(n["type"])) else TreeView.FAR
			"item":
				var item := String(n["item"])
				var tier := int(n["tier"])
				var key := Config.gear_key(item, tier)
				var in_bag := SaveData.gear_count(key)
				var worn_here := SaveData.gear_worn_slot(key) != ""
				if in_bag > 0 or worn_here:
					states[id] = TreeView.OWNED
					if worn_here:
						badges[id] = "EQUIPPED" if in_bag == 0 else "EQUIPPED +%d" % in_bag
					elif in_bag > 1:
						badges[id] = "x%d" % in_bag
				elif SaveData.can_forge(item, tier):
					states[id] = TreeView.READY
				elif SaveData.gear_seen.has(key):
					states[id] = TreeView.POOR
				elif tier == 1:
					states[id] = TreeView.LOCKED
				else:
					states[id] = TreeView.FAR
	_tree.set_states(states, badges)
	_count.text = "%d piece%s" % [pieces, "" if pieces == 1 else "s"]

	var lines: Array[String] = []
	for passive: String in Config.PASSIVE_ORDER:
		var ranks := SaveData.gear_rank(passive)
		if ranks > 0:
			var def: Dictionary = Config.PASSIVES[passive]
			var without := Config.stat_value(def, SaveData.passive_rank(passive) - ranks)
			lines.append("+%d %s   (%s -> %s)" % [ranks, String(def["name"]), PlayerStats.describe_passive(passive, without).get_slice(" ", 0),
					PlayerStats.describe_passive(passive, SaveData.passive_value(passive))])
	_totals.text = "Nothing yet. Wear a piece to see it here." if lines.is_empty() else "\n".join(lines)
	_show_node(_shown if _shown != "" else GearTree.slot_id("chest"))


## Fill the info card and the two buttons for a node.
func _show_node(id: String) -> void:
	if not GearTree.nodes().has(id):
		return
	_shown = id
	var n: Dictionary = GearTree.nodes()[id]
	var kind := String(n["kind"])
	var type_name := String(Config.GEAR_TYPE_NAMES[n["type"]])
	var effects: Array[String] = []
	var details: Array[String] = []
	var needs: Array[String] = []
	_name.add_theme_color_override("font_color", UiKit.TEXT)
	_wear.disabled = true
	_wear.text = "WEAR"

	if kind == "slot":
		var slot := String(n["slot"])
		var worn := SaveData.gear_in_slot(slot)
		_name.text = String(Config.GEAR_SLOT_NAMES[slot])
		_kind.text = "One of the nine things you wear"
		if worn == "":
			effects.append("Nothing worn here.")
			details.append("Click a %s you own (in the web around the body) to wear it." % type_name.to_lower())
		else:
			_name.text = Config.gear_name(worn)
			_name.add_theme_color_override("font_color", Config.gear_tier_def(Config.gear_tier_of(worn))["color"])
			_kind.text = "Worn as your %s" % String(Config.GEAR_SLOT_NAMES[slot]).to_lower()
			effects.append_array(_stat_lines(Config.gear_item_of(worn), Config.gear_tier_of(worn)))
			_wear.disabled = false
			_wear.text = "TAKE OFF"
	elif kind == "type":
		var found := 0
		var total := 0
		for item: String in Config.GEAR_ORDER:
			if String(Config.GEAR_ITEMS[item]["type"]) == String(n["type"]):
				total += 1
				if SaveData.gear_seen.has(Config.gear_key(item, 1)):
					found += 1
		_name.text = "%sS" % type_name if not type_name.ends_with("S") else type_name
		_kind.text = "A kind of gear"
		effects.append("%d of %d found" % [found, total])
		details.append("Each row is one piece, from COMMON on the inside to LEGENDARY on the outside.")
	else:
		var item := String(n["item"])
		var tier := int(n["tier"])
		var key := Config.gear_key(item, tier)
		var def := Config.gear_tier_def(tier)
		var in_bag := SaveData.gear_count(key)
		var worn_slot := SaveData.gear_worn_slot(key)
		var known := SaveData.gear_seen.has(Config.gear_key(item, 1)) or SaveData.gear_seen.has(key)
		_name.text = Config.gear_name(key)
		_name.add_theme_color_override("font_color", def["color"])
		_kind.text = "%s  -  tier %d of %d" % [type_name, tier, Config.GEAR_TIERS.size()]
		effects.append_array(_stat_lines(item, tier))
		if worn_slot != "":
			details.append("You are wearing it%s." % ("" if in_bag == 0 else ", and have %d more in the bag" % in_bag))
		elif in_bag > 0:
			details.append("In your bag: %d." % in_bag)
		elif known:
			details.append("You have none right now.")
		else:
			details.append("Not found yet.")
		details.append("%s." % Config.gear_source_text(item))
		if tier > 1:
			var chance := int(round(float(def["chance"]) * 100.0))
			var text := "Forged from two %s: %d%% chance." % [Config.gear_name(Config.gear_key(item, tier - 1)), chance]
			if chance < 100:
				text += " If it fails, one of the two is lost"
				if float(def["break"]) > 0.0:
					text += " - and there is a %d%% chance the other is destroyed too" % int(round(float(def["break"]) * 100.0))
				text += "."
			needs.append(text)
		if in_bag > 0:
			_wear.disabled = false
			var slot := SaveData.gear_slot_for(key)
			var replaced := SaveData.gear_in_slot(slot)
			_wear.text = "WEAR IT" if replaced == "" else "WEAR IT  (swap)"
		elif worn_slot != "":
			_wear.disabled = false
			_wear.text = "TAKE OFF"
		else:
			_wear.text = "YOU HAVE NONE"

	_effect.text = "\n".join(effects)
	_detail.text = "\n".join(details)
	_detail.visible = not details.is_empty()
	_need.text = "\n".join(needs)
	_need.visible = not needs.is_empty()

	var target := _forge_target(id)
	if target.is_empty():
		_forge.disabled = true
		_forge.text = "FORGE  (needs 2 the same)"
	else:
		var tdef := Config.gear_tier_def(int(target[1]))
		var chance := int(round(float(tdef["chance"]) * 100.0))
		_forge.disabled = false
		_forge.text = "SURE?  %d%%  -  PRESS AGAIN" % chance if _armed == id \
				else "FORGE 2 INTO %s  (%d%%)" % [String(tdef["name"]), chance]


## "+4 DEFENSE  (take less damage from every hit)" for each stat of a piece.
static func _stat_lines(item: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	var stats := Config.gear_stats(item, tier)
	for passive: String in stats.keys():
		out.append("+%d %s  (%s)" % [int(stats[passive]), String(Config.PASSIVES[passive]["name"]),
				String(Config.PASSIVES[passive]["desc"]).to_lower()])
	return out


func opened() -> void:
	_armed = ""
	_banner.text = ""
	SaveData.gear_new = 0
	_refresh()
	_tree.grab_focus()
	if _tree.selected == "":
		_tree.look_at_point(Vector2.ZERO, START_ZOOM)
		_tree.select(GearTree.slot_id("chest"))
