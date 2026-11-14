class_name UiKit
extends RefCounted
## Shared look for all menus: colours, the theme, and small helpers that build
## labels and buttons so every screen looks and sounds the same.

const TEXT := Color("ece7d5")
const DIM := Color("a39f8c")
const GOLD := Color("ffc531")
const RED := Color("d9382c")
const GREEN := Color("9bd15a")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22

	t.set_stylebox("normal", "Button", _box(Color("262b20"), Color("4a5440"), 2))
	t.set_stylebox("hover", "Button", _box(Color("3a4530"), GREEN, 2))
	t.set_stylebox("pressed", "Button", _box(Color("8f241c"), Color("ff6a5a"), 2))
	t.set_stylebox("disabled", "Button", _box(Color("1a1c17"), Color("2a2d26"), 2))
	var focus := _box(Color(0, 0, 0, 0), GOLD, 3)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("6a6a60"))
	t.set_font_size("font_size", "Button", 24)

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.06, 0.07, 0.05, 0.95), Color("3f4634"), 2, 12, 26))

	# Sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color("14160f")
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GREEN
	fill.set_corner_radius_all(6)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	return t


static func _box(bg: Color, border: Color, border_width: int, radius: int = 8, margin: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


static func small_panel_style() -> StyleBoxFlat:
	return _box(Color(0.11, 0.13, 0.09, 0.9), Color("343a2b"), 2, 8, 16)


static func label(text: String, font_size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Big outlined heading.
static func heading(text: String, font_size: int, color: Color = TEXT) -> Label:
	var l := label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.03))
	l.add_theme_constant_override("outline_size", maxi(int(font_size / 6.0), 4))
	return l


## A menu button that clicks, and highlights the same way for mouse and gamepad.
static func button(text: String, on_pressed: Callable, min_width: float = 340.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.pressed.connect(func() -> void:
		Sfx.play("ui_click", -4.0, 0.0)
		on_pressed.call())
	b.focus_entered.connect(func() -> void: Sfx.play("ui_move", -12.0, 0.0))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and not b.has_focus():
			b.grab_focus())
	return b


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## A full-screen container that centres one child.
static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c
