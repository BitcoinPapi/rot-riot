class_name ShopScreen
extends Control
## Upgrade shop between runs. Prices and effects come from Config.UPGRADES,
## purchases are saved straight away by SaveData.

## Small row of boxes showing how many levels are bought.
class Pips extends Control:
	var level := 0
	var max_level := 5

	func _init() -> void:
		custom_minimum_size = Vector2(150, 24)

	func _draw() -> void:
		for i in max_level:
			var r := Rect2(i * 28.0, 2.0, 22.0, 20.0)
			draw_rect(r, Color(0, 0, 0, 0.6))
			if i < level:
				draw_rect(r.grow(-2.0), UiKit.GREEN)
			else:
				draw_rect(r.grow(-2.0), Color(0.2, 0.22, 0.17))

var main: Main
var _coins: Label
var _back: Button
var _rows := {}     # upgrade id -> {pips, bonus, buy}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(UiKit.heading("UPGRADES", 54))
	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 10)
	var coin_icon := TextureRect.new()
	coin_icon.texture = Art.t("coin")
	coin_icon.custom_minimum_size = Vector2(30, 30)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_row.add_child(coin_icon)
	_coins = UiKit.label("0", 30, UiKit.GOLD)
	coin_row.add_child(_coins)
	col.add_child(coin_row)
	col.add_child(UiKit.heading("Coins come from kills and cleared waves. Upgrades are permanent.", 16, UiKit.DIM))
	col.add_child(UiKit.spacer(4))

	for id: String in Config.UPGRADE_ORDER:
		col.add_child(_build_row(id))

	col.add_child(UiKit.spacer(6))
	_back = UiKit.button("BACK", func() -> void: main.close_screen())
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_back)


func _build_row(id: String) -> Control:
	var cfg: Dictionary = Config.UPGRADES[id]
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row_panel.add_child(row)

	var names := VBoxContainer.new()
	names.custom_minimum_size = Vector2(330, 0)
	names.add_child(UiKit.label(String(cfg["name"]), 26, UiKit.TEXT))
	names.add_child(UiKit.label(String(cfg["desc"]), 16, UiKit.DIM))
	row.add_child(names)

	var pips := Pips.new()
	pips.max_level = Config.upgrade_max_level(id)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)

	var bonus := UiKit.label("", 22, UiKit.GREEN)
	bonus.custom_minimum_size = Vector2(110, 0)
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bonus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bonus)

	var buy := UiKit.button("", func() -> void: _buy(id), 210.0)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buy)

	_rows[id] = {"pips": pips, "bonus": bonus, "buy": buy}
	return row_panel


func _buy(id: String) -> void:
	if SaveData.buy_upgrade(id):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	var buy: Button = _rows[id]["buy"]
	if buy.disabled:
		_back.grab_focus()


func _refresh() -> void:
	_coins.text = "%d" % SaveData.coins
	for id: String in Config.UPGRADE_ORDER:
		var level := SaveData.upgrade_level(id)
		var cost := Config.upgrade_cost(id, level)
		var row: Dictionary = _rows[id]
		var pips: Pips = row["pips"]
		pips.level = level
		pips.queue_redraw()
		var bonus: Label = row["bonus"]
		var total := SaveData.upgrade_bonus(id)
		if id == "max_health":
			bonus.text = "+%d HP" % int(total)
		else:
			bonus.text = "+%d%%" % int(round(total * 100.0))
		var buy: Button = row["buy"]
		if cost < 0:
			buy.text = "MAXED"
			buy.disabled = true
		else:
			buy.text = "BUY   %d" % cost
			buy.disabled = SaveData.coins < cost


func opened() -> void:
	_refresh()
	for id: String in Config.UPGRADE_ORDER:
		var buy: Button = _rows[id]["buy"]
		if not buy.disabled:
			buy.grab_focus()
			return
	_back.grab_focus()
