class_name PerkChoice
extends Control
## The perk choice. Every few waves three cards appear over the game and the
## player takes one: with the mouse, with left / right and Enter, or with a
## gamepad. A perk lasts until the run ends.
##
## What the perks are and all their numbers: Config.RUN_PERKS.
## When a choice is due and what choosing does: scripts/game/game.gd
## (perks_owed, perk_offer, choose_perk).

var game: Game

var _sub: Label
var _timer: Label
var _cards: Array[Button] = []
var _parts: Array[Dictionary] = []     # per card: {"icon", "name", "level", "text", "have"}
var _lock := 0.0                       # seconds the cards still ignore clicks (nothing is chosen by accident)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.make_theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(UiKit.centered(col))
	col.add_child(UiKit.heading("CHOOSE A PERK", 52, UiKit.GOLD))
	_sub = UiKit.heading("", 20, UiKit.TEXT)
	col.add_child(_sub)
	col.add_child(UiKit.spacer(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in Config.PERK_CHOICES:
		row.add_child(_build_card(i))
	col.add_child(UiKit.spacer(4))
	_timer = UiKit.heading("", 18, UiKit.DIM)
	col.add_child(_timer)


func _build_card(index: int) -> Button:
	var card := UiKit.button("", func() -> void: _on_card(index), 300.0)
	card.custom_minimum_size = Vector2(300.0, 330.0)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18.0
	box.offset_right = -18.0
	box.offset_top = 22.0
	box.offset_bottom = -16.0
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(88.0, 88.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var perk_name := UiKit.heading("", 25)
	var level := UiKit.heading("", 15, UiKit.DIM)
	var text := UiKit.heading("", 21)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var have := UiKit.heading("", 15, UiKit.DIM)
	for part: Label in [perk_name, level, text, have]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(part)
	_cards.append(card)
	_parts.append({"icon": icon, "name": perk_name, "level": level, "text": text, "have": have})
	return card


## Put `offer` (perk ids) on the table. `owned`: the perks taken so far
## (id -> how many times); `left`: choices still to make, this one included.
func show_offer(offer: Array[String], owned: Dictionary, left: int) -> void:
	for i in _cards.size():
		_cards[i].visible = i < offer.size()
		if i >= offer.size():
			continue
		var id := offer[i]
		var perk: Dictionary = Config.RUN_PERKS[id]
		var level := int(owned.get(id, 0))
		var part: Dictionary = _parts[i]
		(part["icon"] as TextureRect).texture = Art.t(String(perk["icon"]))
		(part["icon"] as TextureRect).modulate = perk["color"]
		(part["name"] as Label).text = String(perk["name"])
		(part["name"] as Label).add_theme_color_override("font_color", perk["color"])
		(part["level"] as Label).text = "NEW" if level == 0 else "LEVEL %s  >  %s" % [Config.roman(level), Config.roman(level + 1)]
		(part["text"] as Label).text = Config.run_perk_text(id, level + 1)
		(part["have"] as Label).text = "" if level == 0 else "(now: %s)" % Config.run_perk_text(id, level)
	_sub.text = "It stays with you until this run ends."
	if left > 1:
		_sub.text += "   %d more to choose after this one." % (left - 1)
	_lock = Config.PERK_CLICK_LOCK
	visible = true
	_cards[mini(1, offer.size() - 1)].grab_focus()


func hide_offer() -> void:
	visible = false
	for card: Button in _cards:
		card.release_focus()


func _process(delta: float) -> void:
	if not visible:
		return
	_lock = maxf(_lock - delta, 0.0)
	# Together, the others are waiting: after a while a perk is taken for you.
	if game != null and game.together():
		_timer.text = "Your friends are waiting: a perk is chosen for you in %d s" % int(ceil(game.perk_time_left))
	else:
		_timer.text = "Take your time - the zombies wait."


func _on_card(index: int) -> void:
	if _lock > 0.0 or game == null:
		return
	game.choose_perk(index)
