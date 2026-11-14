class_name MenuBackground
extends Control
## The picture behind the main menu: dark ground, old blood, and a ring of
## zombies closing in. Drawn once from the same placeholder sprites as the game.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var w := size.x
	var h := size.y
	var center := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color("3a352a"))

	var glow: Texture2D = Art.t("glow")
	var tints := [Color(0.16, 0.15, 0.11, 0.4), Color(0.2, 0.26, 0.14, 0.35), Color(0.3, 0.27, 0.2, 0.3)]
	for i in 60:
		var p := Vector2(rng.randf() * w, rng.randf() * h)
		var s := rng.randf_range(200.0, 520.0)
		draw_texture_rect(glow, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, tints[rng.randi() % tints.size()])

	# Old blood.
	for i in 26:
		var p := Vector2(rng.randf() * w, rng.randf() * h)
		var s := rng.randf_range(50.0, 150.0)
		var color := Config.BLOOD_COLOR_DARK.lerp(Config.BLOOD_COLOR, rng.randf())
		color.a = rng.randf_range(0.5, 0.85)
		draw_set_transform(p, rng.randf() * TAU, Vector2.ONE)
		Art.draw(self, "splat_%d" % (rng.randi() % 3), Vector2.ZERO, s / 72.0, color)

	# A horde closing in from every side, all facing the middle.
	for i in 46:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(0.62, 1.05)
		var p := center + Vector2(cos(angle) * w * 0.5, sin(angle) * h * 0.5) * dist
		var roll := rng.randf()
		var sprite := "shambler_%d" % (rng.randi() % Art.SHAMBLER_VARIANTS)
		if roll > 0.9:
			sprite = "brute_%d" % (rng.randi() % Art.BRUTE_VARIANTS)
		elif roll > 0.7:
			sprite = "runner_%d" % (rng.randi() % Art.RUNNER_VARIANTS)
		draw_set_transform(p, (center - p).angle() + rng.randf_range(-0.3, 0.3), Vector2.ONE)
		Art.draw(self, sprite, Vector2.ZERO, 1.7)
	draw_set_transform(Vector2(w * 0.88, h * 0.5), PI, Vector2.ONE)
	Art.draw(self, "boss_0", Vector2.ZERO, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Darken the middle so the menu reads clearly, then the corners for mood.
	draw_texture_rect(glow, Rect2(center - Vector2(w, h) * 0.75, Vector2(w, h) * 1.5), false, Color(0.02, 0.03, 0.02, 0.92))
	draw_texture_rect(Art.t("vignette"), Rect2(Vector2.ZERO, size), false, Color(0, 0, 0, 0.85))
