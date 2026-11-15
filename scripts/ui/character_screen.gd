class_name CharacterScreen
extends Control
## The character sheet. The hero stands in the middle wearing his gear, with
## his nine slots on either side and his numbers underneath. On the right is
## the inventory: every piece in the bag. Pointing at a piece or a slot
## describes it in the strip along the bottom; clicking a piece in the bag
## wears it, clicking a slot takes it off.
##
## FORGE (in the inventory) opens the forge: choose a piece you have two of
## and try to turn the pair into one of the next quality.
##
## The pieces, qualities and forging odds are in Config (GEAR section); what
## the player owns is in SaveData; how the hero looks comes from Art.

const SLOT_SIZE := 74.0
const TILE_SIZE := 66.0
const LEFT_SLOTS := ["helmet", "chest", "gloves", "pants", "boots"]
const RIGHT_SLOTS := ["amulet", "ring1", "ring2", "belt"]

var main: Main
var _title: Label
var _coins: Label
var _hero: TextureRect
var _slot_boxes := {}          # slot -> the box its tile sits in
var _stats := {}               # stat name -> value Label
var _bag_box: VBoxContainer
var _bag_count: Label
var _bag_grid: GridContainer
var _bag_empty: Label
var _forge_open_button: Button
var _forge_box: VBoxContainer
var _forge_grid: GridContainer
var _forge_none: Label
var _forge_row: HBoxContainer
var _forge_chance: Label
var _forge_risk: Label
var _forge_button: Button
var _banner: Label
var _strip_icon: Control
var _strip_name: Label
var _strip_line: Label
var _strip_stats: Label
var _strip_hint: Label
var _forging := false          # the forge is open instead of the inventory
var _forge_item := ""          # the piece chosen at the forge...
var _forge_tier := 0           # ...and the tier it would become
var _armed := false            # a risky forging is waiting for a second press
var _focus_on := ""            # what to highlight after the tiles are rebuilt: "slot:<slot>" or a piece


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	page.add_theme_constant_override("separation", 8)
	add_child(page)

	# --- top: back, who this is, coins ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	page.add_child(top)
	var back := UiKit.button("BACK", func() -> void: main.close_screen(), 150.0)
	back.custom_minimum_size.y = 44
	top.add_child(back)
	_title = UiKit.heading("", 30)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var counter := UiKit.coin_counter(26)
	_coins = counter[1]
	(counter[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(counter[0])

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(middle)

	# --- left: the hero between his slots ---
	var doll_panel := PanelContainer.new()
	middle.add_child(doll_panel)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 12)
	doll_panel.add_child(doll)
	doll.add_child(_slot_column(LEFT_SLOTS))
	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 4)
	doll.add_child(centre)
	_hero = TextureRect.new()
	_hero.custom_minimum_size = Vector2(230, 300)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_hero)
	centre.add_child(UiKit.heading("STATS", 13, UiKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for stat: String in ["HEALTH", "DAMAGE", "FIRE RATE", "SPEED", "ARMOR", "DODGE", "CRITICAL", "COINS", "PET"]:
		grid.add_child(UiKit.label(stat, 12, UiKit.DIM))
		var value := UiKit.label("", 13, UiKit.TEXT)
		value.custom_minimum_size = Vector2(46, 0)
		grid.add_child(value)
		_stats[stat] = value
	centre.add_child(grid)
	doll.add_child(_slot_column(RIGHT_SLOTS))

	# --- right: the inventory, or the forge ---
	var bag_panel := PanelContainer.new()
	bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(bag_panel)
	var holder := VBoxContainer.new()
	bag_panel.add_child(holder)

	_bag_box = VBoxContainer.new()
	_bag_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_box.add_theme_constant_override("separation", 8)
	holder.add_child(_bag_box)
	var bag_head := HBoxContainer.new()
	bag_head.add_theme_constant_override("separation", 14)
	_bag_box.add_child(bag_head)
	bag_head.add_child(UiKit.label("INVENTORY", 24, UiKit.TEXT))
	_bag_count = UiKit.label("", 14, UiKit.DIM)
	_bag_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(_bag_count)
	_forge_open_button = UiKit.button("FORGE", _open_forge, 230.0)
	_forge_open_button.custom_minimum_size.y = 44
	_forge_open_button.add_theme_font_size_override("font_size", 20)
	bag_head.add_child(_forge_open_button)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_box.add_child(bag_scroll)
	var bag_inner := VBoxContainer.new()
	bag_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(bag_inner)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 8
	_bag_grid.add_theme_constant_override("h_separation", 8)
	_bag_grid.add_theme_constant_override("v_separation", 8)
	bag_inner.add_child(_bag_grid)
	_bag_empty = UiKit.label("Your bag is empty.\n\nNow and then a zombie drops something to wear: look for a pillar of light.\nRings and amulets only drop from bosses.", 16, UiKit.DIM)
	_bag_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bag_inner.add_child(_bag_empty)

	_forge_box = VBoxContainer.new()
	_forge_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_forge_box.add_theme_constant_override("separation", 8)
	_forge_box.visible = false
	holder.add_child(_forge_box)
	var forge_head := HBoxContainer.new()
	forge_head.add_theme_constant_override("separation", 14)
	_forge_box.add_child(forge_head)
	var forge_title := UiKit.label("FORGE", 24, UiKit.GOLD)
	forge_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_head.add_child(forge_title)
	var to_bag := UiKit.button("BACK TO INVENTORY", _close_forge, 260.0)
	to_bag.custom_minimum_size.y = 44
	to_bag.add_theme_font_size_override("font_size", 18)
	forge_head.add_child(to_bag)
	var blurb := UiKit.label("Two identical pieces of the same quality can be forged into one piece of the next quality. Choose a pair:", 14, UiKit.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_box.add_child(blurb)
	var forge_scroll := ScrollContainer.new()
	forge_scroll.custom_minimum_size = Vector2(0, 150)
	forge_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_forge_box.add_child(forge_scroll)
	var forge_inner := VBoxContainer.new()
	forge_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_scroll.add_child(forge_inner)
	_forge_grid = GridContainer.new()
	_forge_grid.columns = 8
	_forge_grid.add_theme_constant_override("h_separation", 8)
	_forge_grid.add_theme_constant_override("v_separation", 8)
	forge_inner.add_child(_forge_grid)
	_forge_none = UiKit.label("Nothing to forge yet: you need two identical pieces of the same quality in your bag.", 15, UiKit.DIM)
	_forge_none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forge_inner.add_child(_forge_none)
	# The anvil: piece + piece = the piece it may become.
	_forge_row = HBoxContainer.new()
	_forge_row.add_theme_constant_override("separation", 14)
	_forge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_forge_row.custom_minimum_size = Vector2(0, SLOT_SIZE + 8.0)
	_forge_box.add_child(_forge_row)
	_forge_chance = UiKit.heading("", 22, UiKit.TEXT)
	_forge_box.add_child(_forge_chance)
	_forge_risk = UiKit.heading("", 14, Color(1.0, 0.6, 0.45))
	_forge_risk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_box.add_child(_forge_risk)
	_forge_button = UiKit.button("FORGE", _on_forge_pressed, 420.0)
	_forge_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_forge_box.add_child(_forge_button)
	_banner = UiKit.heading("", 20, UiKit.GOLD)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_box.add_child(_banner)

	# --- bottom: what is under the pointer ---
	var strip := PanelContainer.new()
	strip.custom_minimum_size = Vector2(0, 104)
	page.add_child(strip)
	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 18)
	strip.add_child(strip_row)
	_strip_icon = CenterContainer.new()
	_strip_icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_strip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_strip_icon)
	var strip_text := VBoxContainer.new()
	strip_text.add_theme_constant_override("separation", 0)
	strip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(strip_text)
	_strip_name = UiKit.label("", 24, UiKit.TEXT)
	strip_text.add_child(_strip_name)
	_strip_stats = UiKit.label("", 16, UiKit.GREEN)
	strip_text.add_child(_strip_stats)
	_strip_line = UiKit.label("", 13, UiKit.DIM)
	_strip_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strip_text.add_child(_strip_line)
	_strip_hint = UiKit.label("", 17, UiKit.GOLD)
	_strip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_strip_hint.custom_minimum_size = Vector2(190, 0)
	_strip_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_strip_hint)


## A column of slots, each with its name underneath.
func _slot_column(slots: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot: String in slots:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var box := CenterContainer.new()
		box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		cell.add_child(box)
		cell.add_child(UiKit.heading(String(Config.GEAR_SLOT_NAMES[slot]), 11, UiKit.DIM))
		col.add_child(cell)
		_slot_boxes[slot] = box
	return col


## A square tile for a piece of gear (or an empty slot): framed in the colour
## of its quality, with its picture in the piece's own colour and, in the
## corner, how many there are.
func _make_tile(key: String, empty_type: String, count: int, tile_size: float, on_press: Callable, on_point: Callable) -> Button:
	var tile := UiKit.button("", on_press, tile_size)
	tile.custom_minimum_size = Vector2(tile_size, tile_size)
	var frame := Color(0.3, 0.32, 0.28)
	var tint := Color(0.42, 0.44, 0.4)
	var type := empty_type
	if key != "":
		var item := Config.gear_item_of(key)
		type = String(Config.GEAR_ITEMS[item]["type"])
		frame = Config.gear_tier_def(Config.gear_tier_of(key))["color"]
		tint = Color(String(Config.GEAR_ITEMS[item]["look"]["color"])).lightened(0.25)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := UiKit.card_style(frame, state == "hover")
		box.bg_color = Color(0.07, 0.08, 0.07) if key == "" else Color(frame.r * 0.16 + 0.03, frame.g * 0.16 + 0.03, frame.b * 0.16 + 0.03)
		box.set_content_margin_all(0.0)
		tile.add_theme_stylebox_override(state, box)
	var icon := TextureRect.new()
	icon.texture = Art.t("gear_" + type)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(tile_size * 0.16))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(icon)
	if count > 1:
		var badge := UiKit.label("x%d" % count, 14, Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		badge.add_theme_constant_override("outline_size", 5)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 4)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
	tile.focus_entered.connect(on_point)
	return tile


static func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


# ----------------------------------------------------------------------------
#  Wearing and taking off
# ----------------------------------------------------------------------------
func _on_bag_pressed(key: String) -> void:
	if SaveData.wear_gear(key):
		Sfx.play("mag_in")
		_focus_on = "slot:" + SaveData.gear_worn_slot(key)
	else:
		Sfx.play("ui_deny")
	_refresh()


func _on_slot_pressed(slot: String) -> void:
	var key := SaveData.gear_in_slot(slot)
	if key != "" and SaveData.take_off_gear(slot):
		Sfx.play("mag_out")
		_focus_on = key
	_refresh()


# ----------------------------------------------------------------------------
#  The forge
# ----------------------------------------------------------------------------
func _open_forge() -> void:
	_forging = true
	_armed = false
	_banner.text = ""
	if not SaveData.can_forge(_forge_item, _forge_tier):
		_forge_item = ""
	_refresh()


func _close_forge() -> void:
	_forging = false
	_armed = false
	_refresh()
	_forge_open_button.grab_focus()


## Put a pair on the anvil: `key` is the piece you have two of.
func _choose_forge(key: String) -> void:
	_forge_item = Config.gear_item_of(key)
	_forge_tier = Config.gear_tier_of(key) + 1
	_armed = false
	_banner.text = ""
	_focus_on = key
	_refresh()


func _on_forge_pressed() -> void:
	if not SaveData.can_forge(_forge_item, _forge_tier):
		Sfx.play("ui_deny")
		return
	var def := Config.gear_tier_def(_forge_tier)
	# Anything that can fail asks once before it is done.
	if float(def["chance"]) < 1.0 and not _armed:
		_armed = true
		Sfx.play("ui_click", -4.0, 0.0)
		_refresh()
		return
	_armed = false
	var made := Config.gear_key(_forge_item, _forge_tier)
	match SaveData.forge_gear(_forge_item, _forge_tier):
		"success":
			_banner.text = "FORGED:  %s" % Config.gear_name(made)
			_banner.add_theme_color_override("font_color", def["color"])
			Sfx.play("forge_ok")
		"fail":
			_banner.text = "THE FORGING FAILED  -  one piece was lost"
			_banner.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			Sfx.play("forge_fail")
		"broke":
			_banner.text = "DESTROYED  -  both pieces are gone"
			_banner.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
			Sfx.play("forge_break")
		_:
			Sfx.play("ui_deny")
	_focus_on = made
	_refresh()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
func _refresh() -> void:
	_title.text = "%s \"%s\"   -   LEVEL %d" % [Config.HERO_FULL_NAME, Config.HERO_NAME, SaveData.level]
	_coins.text = "%d" % SaveData.coins
	_hero.texture = Art.t("hero_front")
	var focus: Button = null

	# His slots.
	for slot: String in Config.GEAR_SLOTS:
		var box: Control = _slot_boxes[slot]
		_clear(box)
		var key := SaveData.gear_in_slot(slot)
		var tile := _make_tile(key, String(Config.GEAR_SLOT_TYPE[slot]), 1, SLOT_SIZE,
				func() -> void: _on_slot_pressed(slot), func() -> void: _describe_slot(slot))
		box.add_child(tile)
		if _focus_on == "slot:" + slot:
			focus = tile

	# His numbers.
	var stats := PlayerStats.current()
	(_stats["HEALTH"] as Label).text = "%d" % int(stats.max_hp)
	(_stats["DAMAGE"] as Label).text = "+%d%%" % int(round((stats.damage_mult - 1.0) * 100.0))
	(_stats["FIRE RATE"] as Label).text = "+%d%%" % int(round((stats.fire_rate_mult - 1.0) * 100.0))
	(_stats["SPEED"] as Label).text = "+%d%%" % int(round((stats.speed_mult - 1.0) * 100.0))
	(_stats["ARMOR"] as Label).text = "%d%%" % int(round((1.0 - stats.damage_taken_mult) * 100.0))
	(_stats["DODGE"] as Label).text = "%d%%" % int(round(stats.evasion * 100.0))
	(_stats["CRITICAL"] as Label).text = "%d%%" % int(round(stats.crit_chance * 100.0))
	(_stats["COINS"] as Label).text = "+%d%%" % int(round(stats.coin_luck * 100.0))
	(_stats["PET"] as Label).text = "+%s%%" % String.num(stats.pet_damage * 100.0, 1) if stats.pet != "" else "-"

	# The bag, in the order of the catalogue, best quality first.
	_bag_box.visible = not _forging
	_forge_box.visible = _forging
	_clear(_bag_grid)
	_clear(_forge_grid)
	var pieces := 0
	var pairs := 0
	for item: String in Config.GEAR_ORDER:
		for tier in range(Config.GEAR_TIERS.size(), 0, -1):
			var key := Config.gear_key(item, tier)
			var count := SaveData.gear_count(key)
			if count <= 0:
				continue
			pieces += count
			var tile := _make_tile(key, "", count, TILE_SIZE, func() -> void: _on_bag_pressed(key), func() -> void: _describe_piece(key, "bag"))
			_bag_grid.add_child(tile)
			if _focus_on == key and not _forging:
				focus = tile
			if count >= 2 and tier < Config.GEAR_TIERS.size():
				pairs += 1
				var pair := _make_tile(key, "", count, TILE_SIZE, func() -> void: _choose_forge(key), func() -> void: _describe_piece(key, "forge"))
				_forge_grid.add_child(pair)
				if _forging and (_focus_on == key or focus == null):
					focus = pair
	_bag_empty.visible = pieces == 0
	_bag_count.text = "%d piece%s" % [pieces, "" if pieces == 1 else "s"]
	_forge_open_button.text = "FORGE" if pairs == 0 else "FORGE  (%d ready)" % pairs
	_forge_none.visible = pairs == 0

	# The anvil.
	_clear(_forge_row)
	var can_forge := SaveData.can_forge(_forge_item, _forge_tier)
	_forge_row.visible = can_forge
	_forge_chance.visible = can_forge
	_forge_risk.visible = can_forge
	_forge_button.visible = can_forge
	if can_forge:
		var def := Config.gear_tier_def(_forge_tier)
		var source := Config.gear_key(_forge_item, _forge_tier - 1)
		var made := Config.gear_key(_forge_item, _forge_tier)
		var chance := int(round(float(def["chance"]) * 100.0))
		for part: Array in [[source, ""], ["", "+"], [source, ""], ["", "="], [made, ""]]:
			if String(part[1]) != "":
				var mark := UiKit.heading(String(part[1]), 34, UiKit.DIM)
				mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_forge_row.add_child(mark)
			else:
				var shown := _make_tile(String(part[0]), "", 1, SLOT_SIZE, func() -> void: pass, func() -> void: pass)
				shown.focus_mode = Control.FOCUS_NONE
				shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_forge_row.add_child(shown)
		_forge_chance.text = "%s   -   %d%% chance" % [Config.gear_name(made), chance]
		_forge_chance.add_theme_color_override("font_color", def["color"])
		if chance >= 100:
			_forge_risk.text = "This always works."
		else:
			_forge_risk.text = "If it fails, one of the two pieces is lost%s." % (
					"" if float(def["break"]) <= 0.0 else " - and there is a %d%% chance the other is destroyed as well" % int(round(float(def["break"]) * 100.0)))
		_forge_button.text = "SURE?   %d%%   -   PRESS AGAIN" % chance if _armed else "FORGE   (%d%%)" % chance
	_banner.visible = _banner.text != ""

	if focus != null:
		focus.grab_focus()
	elif _forging and _forge_button.visible:
		_forge_button.grab_focus()
	else:
		_forge_open_button.grab_focus()
		_describe_nothing()
	_focus_on = ""


func _set_strip(key: String, empty_type: String) -> void:
	_clear(_strip_icon)
	var tile := _make_tile(key, empty_type, 1, SLOT_SIZE, func() -> void: pass, func() -> void: pass)
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_icon.add_child(tile)


func _describe_nothing() -> void:
	_set_strip("", "chest")
	_strip_name.text = "%s'S GEAR" % Config.HERO_NAME
	_strip_name.add_theme_color_override("font_color", UiKit.TEXT)
	_strip_stats.text = "Point at a piece to read about it."
	_strip_line.text = "Click a piece in the inventory to wear it. Click a slot to take it off. FORGE turns two identical pieces into a better one."
	_strip_hint.text = ""


## Where a piece was pointed at: "bag", "forge" or "" (just shown).
func _describe_piece(key: String, where: String) -> void:
	var item := Config.gear_item_of(key)
	var tier := Config.gear_tier_of(key)
	var def := Config.gear_tier_def(tier)
	_set_strip(key, "")
	_strip_name.text = Config.gear_name(key)
	_strip_name.add_theme_color_override("font_color", def["color"])
	var lines: Array[String] = []
	var stats := Config.gear_stats(item, tier)
	for passive: String in stats.keys():
		lines.append("+%d %s  (%s)" % [int(stats[passive]), String(Config.PASSIVES[passive]["name"]),
				String(Config.PASSIVES[passive]["desc"]).to_lower()])
	_strip_stats.text = "      ".join(lines)
	var count := SaveData.gear_count(key)
	_strip_line.text = "%s  -  quality %d of %d  -  %s  -  %s" % [String(Config.GEAR_TYPE_NAMES[Config.GEAR_ITEMS[item]["type"]]), tier,
			Config.GEAR_TIERS.size(), "in your bag: %d" % count if count > 0 else "none in your bag", Config.gear_source_text(item)]
	match where:
		"bag":
			var slot := SaveData.gear_slot_for(key)
			_strip_hint.text = "Click to wear" if SaveData.gear_in_slot(slot) == "" else "Click to swap"
		"forge":
			_strip_hint.text = "Click to put the pair\non the anvil"
		_:
			_strip_hint.text = ""


func _describe_slot(slot: String) -> void:
	var key := SaveData.gear_in_slot(slot)
	if key != "":
		_describe_piece(key, "")
		_strip_hint.text = "Click to take off"
		return
	_set_strip("", String(Config.GEAR_SLOT_TYPE[slot]))
	_strip_name.text = String(Config.GEAR_SLOT_NAMES[slot])
	_strip_name.add_theme_color_override("font_color", UiKit.TEXT)
	_strip_stats.text = "Nothing worn here."
	_strip_line.text = "Click a %s in your inventory to wear it." % String(Config.GEAR_TYPE_NAMES[Config.GEAR_SLOT_TYPE[slot]]).to_lower()
	_strip_hint.text = ""


## Called by Main every time this screen is shown.
func opened() -> void:
	SaveData.gear_new = 0
	_forging = false
	_armed = false
	_banner.text = ""
	_refresh()
