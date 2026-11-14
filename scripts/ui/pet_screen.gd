class_name PetScreen
extends Control
## The Pet screen: every pet in the game, from common to legendary. Pets open
## at character level Config.PET_UNLOCK_LEVEL, when the first one joins by
## itself; the others must be earned (a level or a cleared map) and bought
## with coins. One pet comes along at a time.
##
## A pet adds to the character's damage - at most what its rarity allows -
## and how much of that you get depends on BOND, the pet's branch of the
## Skills page. The numbers are in Config (PETS section).

const CARD_SIZE := Vector2(232, 372)

var main: Main
var _cards: Array[Button] = []
var _pictures: Array[TextureRect] = []
var _status: Array[Label] = []
var _detail: Array[Label] = []
var _selected := 0
var _coins: Label
var _intro: Label
var _bond: Label
var _action: Button
var _home: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiKit.heading("PETS", 46))
	var counter := UiKit.coin_counter(26)
	_coins = counter[1]
	(counter[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(counter[0])
	col.add_child(head)
	_intro = UiKit.heading("", 17, UiKit.DIM)
	col.add_child(_intro)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in Config.PET_ORDER.size():
		row.add_child(_make_card(i))

	_bond = UiKit.heading("", 15, Config.PASSIVES["bond"]["color"])
	col.add_child(_bond)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	buttons.add_child(UiKit.button("BACK", func() -> void: main.close_screen(), 200.0))
	_action = UiKit.button("", _on_action, 420.0)
	buttons.add_child(_action)
	_home = UiKit.button("LEAVE PET AT HOME", _on_home, 300.0)
	_home.add_theme_font_size_override("font_size", 19)
	buttons.add_child(_home)


func _make_card(index: int) -> Button:
	var id: String = Config.PET_ORDER[index]
	var def: Dictionary = Config.PETS[id]
	var rarity: Dictionary = Config.PET_RARITIES[String(def["rarity"])]
	var color: Color = rarity["color"]
	var card := UiKit.button("", func() -> void: _select(index), CARD_SIZE.x)
	card.custom_minimum_size = CARD_SIZE
	_cards.append(card)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	box.add_child(UiKit.heading(String(rarity["name"]), 15, color))
	var picture := TextureRect.new()
	picture.texture = Art.t("pet_" + id)
	picture.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 96)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	_pictures.append(picture)
	box.add_child(UiKit.heading(String(def["name"]), 24, color))
	box.add_child(UiKit.heading(String(def["title"]), 13, UiKit.DIM))
	box.add_child(UiKit.heading("Adds up to +%d%% damage" % int(round(float(rarity["damage"]) * 100.0)), 16, UiKit.GREEN))
	box.add_child(UiKit.heading("Bite strength x%s" % String.num(float(rarity["bite"]), 1), 13, UiKit.TEXT))
	var note := UiKit.heading(String(def["note"]), 13, UiKit.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 36)
	box.add_child(note)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(filler)
	var status := UiKit.heading("", 17, UiKit.TEXT)
	box.add_child(status)
	_status.append(status)
	var detail := UiKit.heading("", 12, UiKit.DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 34)
	box.add_child(detail)
	_detail.append(detail)
	return card


func _select(index: int) -> void:
	_selected = index
	_refresh()


## The big button: take the selected pet along, or buy it.
func _on_action() -> void:
	var id: String = Config.PET_ORDER[_selected]
	match SaveData.pet_status(id):
		"owned":
			SaveData.choose_pet(id)
			Sfx.play("pet_call")
		"ready":
			if SaveData.buy_pet(id):
				Sfx.play("ui_buy")
				Sfx.play("pet_call")
		_:
			Sfx.play("ui_deny")
	_refresh()


func _on_home() -> void:
	SaveData.choose_pet("")
	_refresh()
	_action.grab_focus()


func _refresh() -> void:
	_coins.text = "%d" % SaveData.coins
	var open := SaveData.pets_unlocked()
	var bond := SaveData.passive_rank("bond")
	if open:
		_intro.text = "One pet comes along at a time. It bites zombies that come close and adds to your damage."
	else:
		_intro.text = "A pet joins you at character level %d.   You are level %d." % [Config.PET_UNLOCK_LEVEL, SaveData.level]
	_bond.text = "PET BOND %d: a pet gives %d%% of its damage bonus (all of it at %d). Raise PET BOND on the SKILLS page - it also teaches your pet tricks." % [
			bond, int(round(Config.pet_bond_share(bond) * 100.0)), Config.PET_BOND_FULL]

	for i in _cards.size():
		var id: String = Config.PET_ORDER[i]
		var def: Dictionary = Config.PETS[id]
		var color: Color = Config.PET_RARITIES[String(def["rarity"])]["color"]
		var status := SaveData.pet_status(id)
		var card := _cards[i]
		for state: String in ["normal", "hover"]:
			if i == _selected:
				card.add_theme_stylebox_override(state, UiKit.card_style(color, state == "hover"))
			else:
				card.remove_theme_stylebox_override(state)
		# A pet you do not have yet is only a dark shape.
		_pictures[i].modulate = Color(1, 1, 1) if status == "owned" else (Color(0.5, 0.5, 0.5) if status != "locked" else Color(0.08, 0.08, 0.08))
		var gives := "Now gives you +%s%% damage" % String.num(Config.pet_damage_bonus(id, bond) * 100.0, 1)
		match status:
			"owned":
				if SaveData.pet_active == id:
					_status[i].text = "COMING ALONG"
					_status[i].add_theme_color_override("font_color", UiKit.GOLD)
				else:
					_status[i].text = "YOURS"
					_status[i].add_theme_color_override("font_color", UiKit.GREEN)
				_detail[i].text = gives
			"ready", "poor":
				_status[i].text = "%d coins" % int(def["price"])
				_status[i].add_theme_color_override("font_color", UiKit.GOLD if status == "ready" else UiKit.RED)
				_detail[i].text = "Would give you +%s%% damage" % String.num(Config.pet_damage_bonus(id, bond) * 100.0, 1)
			_:
				_status[i].text = "LOCKED"
				_status[i].add_theme_color_override("font_color", UiKit.RED)
				var price := int(def["price"])
				_detail[i].text = "%s%s" % [Config.deed_text(def["needs"]), "" if price <= 0 else ", then %d coins" % price]

	var chosen: String = Config.PET_ORDER[_selected]
	var chosen_name := String(Config.PETS[chosen]["name"])
	match SaveData.pet_status(chosen):
		"owned":
			_action.text = "%s IS COMING ALONG" % chosen_name if SaveData.pet_active == chosen else "TAKE %s ALONG" % chosen_name
			_action.disabled = SaveData.pet_active == chosen
		"ready":
			_action.text = "BUY %s  -  %d coins" % [chosen_name, int(Config.PETS[chosen]["price"])]
			_action.disabled = false
		"poor":
			_action.text = "NOT ENOUGH COINS FOR %s" % chosen_name
			_action.disabled = true
		_:
			_action.text = "%s IS LOCKED" % chosen_name
			_action.disabled = true
	_home.disabled = SaveData.pet_active == ""
	_home.text = "NO PET IS COMING ALONG" if SaveData.pet_active == "" and open and not SaveData.pets_owned.is_empty() else "LEAVE PET AT HOME"


## Called by Main every time this screen is shown.
func opened() -> void:
	if SaveData.pets_unlocked():
		SaveData.pet_seen = true
	var active := Config.PET_ORDER.find(SaveData.pet_active)
	_selected = maxi(active, 0)
	_refresh()
	if _action.disabled:
		_cards[_selected].grab_focus()
	else:
		_action.grab_focus()
