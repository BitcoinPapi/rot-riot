class_name Hud
extends Control
## The in-game overlay: health, rage, weapon timer, score, coins, wave info,
## boss bar, crosshair and big announcements. Everything is drawn in _draw
## from the Game's state, so there is nothing to keep in sync.

var game: Game

var _font: Font
var _time := 0.0
var _hp_trail := 1.0            # the pale bar that catches up after damage
var _hurt := 0.0                # red flash when hit
var _announce := ""
var _announce_sub := ""
var _announce_color := Color.WHITE
var _announce_t := 0.0
var _announce_len := 1.0
var _score_shown := 0.0
var _score_pop := 0.0
var _coins_seen := 0
var _coin_pop := 0.0
var _crosshair_kick := 0.0
var _hint_t := 7.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func announce(title: String, subtitle: String, color: Color, duration: float = 2.4) -> void:
	_announce = title
	_announce_sub = subtitle
	_announce_color = color
	_announce_t = duration
	_announce_len = duration


func hurt() -> void:
	_hurt = 1.0


func fired(kick: float) -> void:
	_crosshair_kick = minf(_crosshair_kick + kick, 16.0)


func tick(real_dt: float) -> void:
	_time += real_dt
	var p := game.player
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
	if _hp_trail > frac:
		_hp_trail = maxf(_hp_trail - real_dt * 0.45, frac)
	else:
		_hp_trail = frac
	_hurt = maxf(_hurt - real_dt * 2.2, 0.0)
	_announce_t = maxf(_announce_t - real_dt, 0.0)
	_hint_t = maxf(_hint_t - real_dt, 0.0)
	_crosshair_kick = lerpf(_crosshair_kick, 0.0, minf(real_dt * 12.0, 1.0))
	if absf(_score_shown - game.score) > 0.5:
		_score_shown = lerpf(_score_shown, float(game.score), minf(real_dt * 10.0, 1.0))
		_score_pop = 1.0
	_score_pop = maxf(_score_pop - real_dt * 4.0, 0.0)
	if game.coins_run != _coins_seen:
		_coins_seen = game.coins_run
		_coin_pop = 1.0
	_coin_pop = maxf(_coin_pop - real_dt * 5.0, 0.0)
	queue_redraw()


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _draw() -> void:
	if game == null:
		return
	var p := game.player
	var w := size.x
	var h := size.y

	_draw_vignettes(p)
	_draw_crate_arrows()
	_draw_health_and_rage(p)
	_draw_weapon(p, h)
	_draw_xp(w, h)
	_draw_score(w)
	_draw_wave(w)
	_draw_announcement(w, h)
	_draw_hint(w, h)
	if p.alive:
		_draw_crosshair(p)


func _draw_vignettes(p: Player) -> void:
	var vignette: Texture2D = Art.t("vignette")
	var full := Rect2(Vector2.ZERO, size)
	# Always-on dark corners for mood.
	draw_texture_rect(vignette, full, false, Color(0, 0, 0, 0.55))
	var frac := p.hp / p.max_hp
	if game.rage_active:
		draw_texture_rect(vignette, full, false, Color(1.0, 0.35, 0.05, 0.4 + 0.15 * sin(_time * 14.0)))
	if frac < 0.3 and p.alive:
		draw_texture_rect(vignette, full, false, Color(0.9, 0.0, 0.0, 0.3 + 0.25 * sin(_time * 7.0)))
	if _hurt > 0.0:
		draw_texture_rect(vignette, full, false, Color(1.0, 0.05, 0.05, _hurt * 0.85))
		draw_rect(full, Color(1.0, 0.0, 0.0, _hurt * 0.12))


func _draw_health_and_rage(p: Player) -> void:
	var x := 26.0
	var y := 24.0
	var bar_w := 290.0
	var bar_h := 24.0
	var frac := clampf(p.hp / p.max_hp, 0.0, 1.0)

	# Health
	draw_rect(Rect2(x - 4, y - 4, bar_w + 8, bar_h + 8), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(x, y, bar_w * _hp_trail, bar_h), Color(1.0, 0.9, 0.7))
	var hp_color := Color(0.85, 0.13, 0.1).lerp(Color(0.35, 0.85, 0.3), frac)
	draw_rect(Rect2(x, y, bar_w * frac, bar_h), hp_color)
	draw_rect(Rect2(x, y, bar_w * frac, bar_h * 0.35), Color(1, 1, 1, 0.16))
	_text(Vector2(x + 8, y + 18), "HP", 16, Color.WHITE)
	_text(Vector2(x + bar_w - 8, y + 18), "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)], 16, Color.WHITE, 2)

	# Rage
	var ry := y + bar_h + 12.0
	var rh := 14.0
	var rfrac := clampf(game.rage / Config.RAGE_MAX, 0.0, 1.0)
	var is_ready := game.rage_ready()
	draw_rect(Rect2(x - 4, ry - 4, bar_w + 8, rh + 8), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(x, ry, bar_w, rh), Color(0.16, 0.08, 0.03))
	var rcolor := Color(0.95, 0.45, 0.1)
	if game.rage_active:
		rcolor = Color(1.0, 0.25, 0.1).lerp(Color(1.0, 0.9, 0.3), 0.5 + 0.5 * sin(_time * 22.0))
	elif is_ready:
		rcolor = Color(1.0, 0.55, 0.1).lerp(Color(1.0, 1.0, 0.6), 0.5 + 0.5 * sin(_time * 10.0))
	draw_rect(Rect2(x, ry, bar_w * rfrac, rh), rcolor)
	if game.rage_active:
		_text(Vector2(x, ry + rh + 22), "RAGE!", 20, Color(1.0, 0.4, 0.15))
	elif is_ready:
		var key := "LB" if GameInput.using_gamepad() else "SPACE"
		var blink := 0.6 + 0.4 * sin(_time * 10.0)
		_text(Vector2(x, ry + rh + 22), "RAGE READY - PRESS %s" % key, 20, Color(1.0, 0.75, 0.25, blink))
	else:
		_text(Vector2(x, ry + rh + 20), "RAGE", 14, Color(0.9, 0.6, 0.35, 0.8))


func _draw_weapon(p: Player, h: float) -> void:
	var w: Dictionary = p.weapon
	var color: Color = w["color"]
	var px := 20.0
	var pw := 372.0
	var ph := 96.0
	var py := h - 18.0 - ph
	draw_rect(Rect2(px, py, pw, ph), Color(0, 0, 0, 0.55))

	# The weapon's picture (two of them when dual wielding).
	var icon: Texture2D = Art.t("icon_" + p.weapon_id)
	var icon_rect := Rect2(px + 8.0, py + 8.0, 132.0, 48.0)
	if p.dual:
		draw_texture_rect(icon, Rect2(icon_rect.position + Vector2(10, 12), icon_rect.size), false, Color(0.55, 0.55, 0.6))
		draw_texture_rect(icon, Rect2(icon_rect.position + Vector2(-2, -4), icon_rect.size), false)
	else:
		draw_texture_rect(icon, icon_rect, false)

	# Its own level and how close it is to the next one.
	var wlevel := SaveData.weapon_level(p.weapon_id)
	var wfrac := clampf(float(SaveData.weapon_xp(p.weapon_id)) / float(SaveData.weapon_xp_needed(p.weapon_id)), 0.0, 1.0)
	_text(Vector2(px + 10.0, py + ph - 10.0), "LV %d" % wlevel, 14, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(px + 56.0, py + ph - 19.0, 84.0, 5.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(px + 56.0, py + ph - 19.0, 84.0 * wfrac, 5.0), Color(color.r, color.g, color.b, 0.9))

	var tx := px + 152.0
	_text(Vector2(tx, py + 26.0), p.weapon_label(), 20, color)

	# Ammo, or the reload in progress.
	if p.mag_size <= 0:
		_text(Vector2(tx, py + 54.0), "MELEE", 18, Color(1, 1, 1, 0.6))
	elif p.reloading:
		var blink := 0.6 + 0.4 * sin(_time * 14.0)
		_text(Vector2(tx, py + 52.0), "RELOADING", 18, Color(1.0, 0.85, 0.35, blink))
		draw_rect(Rect2(tx + 112.0, py + 40.0, 96.0, 8.0), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(tx + 112.0, py + 40.0, 96.0 * p.reload_progress, 8.0), Color(1.0, 0.85, 0.35))
	else:
		var low := float(p.ammo) <= float(p.mag_size) * Config.LOW_AMMO_FRACTION
		var ammo_color := Color(1.0, 0.3, 0.25) if low else Color.WHITE
		var ammo_text := "%d" % p.ammo
		_text(Vector2(tx, py + 56.0), ammo_text, 26, ammo_color)
		var aw := _font.get_string_size(ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(Vector2(tx + aw + 6.0, py + 56.0), "/ %d" % p.mag_size, 16, Color(1, 1, 1, 0.55))
		# A reminder that you can reload early (it pulses when the magazine is low).
		if p.ammo < p.mag_size:
			var key := "X" if GameInput.using_gamepad() else "R"
			var aw2 := _font.get_string_size("/ %d" % p.mag_size, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var hint_alpha := (0.6 + 0.4 * sin(_time * 10.0)) if low else 0.45
			_text(Vector2(tx + aw + aw2 + 18.0, py + 56.0), "%s = reload" % key, 14,
					Color(1.0, 0.85, 0.35, hint_alpha))

	# How long a crate weapon has left.
	var duration: float = p.weapon_time_max
	if duration > 0.0:
		var frac := clampf(p.weapon_time / duration, 0.0, 1.0)
		var show_bar := frac > 0.22 or fmod(_time, 0.3) < 0.18
		draw_rect(Rect2(tx, py + 70.0, 170.0, 8.0), Color(0.1, 0.1, 0.1))
		if show_bar:
			draw_rect(Rect2(tx, py + 70.0, 170.0 * frac, 8.0), color)
		_text(Vector2(px + pw - 10.0, py + 80.0), "%.0fs" % ceilf(p.weapon_time), 15, Color(1, 1, 1, 0.8), 2)


## Character level and XP: a thin bar along the bottom edge of the screen.
func _draw_xp(w: float, h: float) -> void:
	var capped := SaveData.at_level_cap()
	var frac := 1.0 if capped else clampf(float(SaveData.xp) / float(SaveData.xp_needed()), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	draw_rect(Rect2(0, h - 7, w, 7), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(0, h - 6, w * frac, 5), Color(0.35, 0.75, 1.0))
	draw_rect(Rect2(0, h - 6, w * frac, 2), Color(1, 1, 1, 0.25))
	_text(Vector2(w * 0.5, h - 14), "LEVEL %d%s" % [SaveData.level, "  (MAX)" if capped else ""], 16, Color(0.75, 0.9, 1.0), 1)
	if SaveData.skill_points > 0:
		_text(Vector2(w * 0.5, h - 34), "%d skill point%s to spend after this run" % [
				SaveData.skill_points, "" if SaveData.skill_points == 1 else "s"], 13, Color(1.0, 0.85, 0.3, 0.55 + 0.35 * pulse), 1)


func _draw_score(w: float) -> void:
	var x := w - 26.0
	_text(Vector2(x, 50), "%d" % int(round(_score_shown)), 36 + int(_score_pop * 6.0), Color.WHITE, 2)
	_text(Vector2(x, 70), "SCORE", 13, Color(1, 1, 1, 0.6), 2)
	# Coins
	var coin: Texture2D = Art.t("coin")
	var coin_text := "%d" % game.coins_run
	var cs := 24.0 + _coin_pop * 8.0
	var tw := _font.get_string_size(coin_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_text(Vector2(x, 108), coin_text, 24, Color(1.0, 0.82, 0.3), 2)
	draw_texture_rect(coin, Rect2(Vector2(x - tw - 10 - cs, 100 - cs * 0.5), Vector2(cs, cs)), false)
	# Combo
	if game.combo > 1:
		var mult := Config.combo_multiplier(game.combo)
		var cf := clampf(game.combo_timer / Config.COMBO_WINDOW, 0.0, 1.0)
		var ccol := Color(1.0, 0.9, 0.4).lerp(Color(1.0, 0.35, 0.15), clampf((mult - 1.0) / 2.0, 0.0, 1.0))
		_text(Vector2(x, 144), "%d KILL COMBO  x%.1f" % [game.combo, mult], 18, ccol, 2)
		draw_rect(Rect2(x - 150, 152, 150, 4), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x - 150 * cf, 152, 150 * cf, 4), ccol)


func _draw_wave(w: float) -> void:
	var d := game.director
	var cx := w * 0.5
	if d.wave <= 0:
		_text(Vector2(cx, 40), "GET READY", 24, Color(1, 1, 1, 0.9), 1)
		return
	var map_color: Color = game.map["color"]
	_text(Vector2(cx, 15), "MAP %d  -  %s" % [game.map_index + 1, String(game.map["name"])], 12,
			Color(map_color.r, map_color.g, map_color.b, 0.85), 1, 4)
	_text(Vector2(cx, 40), "WAVE %d / %d" % [d.wave, Config.WAVES_PER_MAP], 26, Color.WHITE, 1)
	if d.finished:
		_text(Vector2(cx, 62), "map cleared", 15, Color(1.0, 0.85, 0.3, 0.95), 1)
	elif d.in_wave:
		_text(Vector2(cx, 62), "%d left" % d.remaining(), 15, Color(1, 1, 1, 0.7), 1)
	else:
		_text(Vector2(cx, 62), "next wave in %d" % int(ceil(d.intermission)), 15, Color(0.7, 1.0, 0.6, 0.9), 1)
	if d.boss_alive():
		var boss := d.boss
		var bw := minf(520.0, w * 0.5)
		var bx := cx - bw * 0.5
		var by := 78.0
		var frac := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		draw_rect(Rect2(bx - 4, by - 4, bw + 8, 22), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bx, by, bw, 14), Color(0.2, 0.04, 0.04))
		draw_rect(Rect2(bx, by, bw * frac, 14), Color(0.85, 0.12, 0.1))
		draw_rect(Rect2(bx, by, bw * frac, 5), Color(1, 1, 1, 0.18))
		var boss_name: String = Config.ENEMIES[Config.BOSS]["name"]
		_text(Vector2(cx, by + 36), boss_name, 16, Color(1.0, 0.5, 0.4), 1)


func _draw_announcement(w: float, h: float) -> void:
	if _announce_t <= 0.0:
		return
	var age := _announce_len - _announce_t
	var alpha := clampf(age / 0.15, 0.0, 1.0) * clampf(_announce_t / 0.5, 0.0, 1.0)
	var pop := 1.0 + maxf(0.2 - age, 0.0) * 1.5
	var color := _announce_color
	color.a = alpha
	_text(Vector2(w * 0.5, h * 0.3), _announce, int(64.0 * pop), color, 1, 12)
	if _announce_sub != "":
		_text(Vector2(w * 0.5, h * 0.3 + 40), _announce_sub, 24, Color(1, 1, 1, alpha), 1)


func _draw_hint(w: float, h: float) -> void:
	if _hint_t <= 0.0 or game.director.wave > 1:
		return
	var alpha := clampf(_hint_t / 1.0, 0.0, 1.0) * 0.9
	var hint := "WASD move   -   MOUSE aim   -   LEFT CLICK shoot   -   R reload   -   SPACE rage   -   ESC pause"
	if GameInput.using_gamepad():
		hint = "LEFT STICK move   -   RIGHT STICK aim   -   RT shoot   -   X reload   -   LB rage   -   START pause"
	_text(Vector2(w * 0.5, h - 104), hint, 17, Color(1, 1, 1, alpha), 1)


func _draw_crosshair(p: Player) -> void:
	var at: Vector2
	if GameInput.using_gamepad() or GameInput.virtual_active:
		at = _to_screen(p.pos + p.aim * 150.0)
	else:
		at = get_viewport().get_mouse_position()
	var gap := 6.0 + _crosshair_kick
	var length := 9.0
	var color: Color = p.weapon["color"]
	color = color.lerp(Color.WHITE, 0.6)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(at + dir * (gap - 1.0), at + dir * (gap + length + 1.0), Color(0, 0, 0, 0.7), 5.0)
		draw_line(at + dir * gap, at + dir * (gap + length), color, 2.5)
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), color)

	# Around the crosshair, where the eyes already are: a ring that fills
	# while reloading, otherwise the shots left (red when nearly empty).
	if p.mag_size > 0:
		if p.reloading:
			var radius := 24.0
			draw_arc(at, radius, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 5.0)
			draw_arc(at, radius, -PI * 0.5, -PI * 0.5 + TAU * p.reload_progress, 40, Color(1.0, 0.85, 0.35), 3.0)
		else:
			var low := float(p.ammo) <= float(p.mag_size) * Config.LOW_AMMO_FRACTION
			var key := "X" if GameInput.using_gamepad() else "R"
			_text(at + Vector2(0.0, 36.0), ("%d   [%s]" % [p.ammo, key]) if low else "%d" % p.ammo, 16 if low else 13,
					Color(1.0, 0.3, 0.25, 0.95) if low else Color(1, 1, 1, 0.6), 1, 4)


## Arrows at the screen edge pointing to weapon crates that are out of view.
func _draw_crate_arrows() -> void:
	var view := Rect2(Vector2(46.0, 128.0), size - Vector2(92.0, 228.0))
	for crate: Pickups.Crate in game.pickups.crates:
		var sp := _to_screen(crate.pos)
		if view.has_point(sp):
			continue
		var color: Color = Config.WEAPONS[crate.weapon]["color"]
		var clamped := Vector2(clampf(sp.x, view.position.x, view.end.x), clampf(sp.y, view.position.y, view.end.y))
		var dir := (sp - clamped).normalized()
		var side := Vector2(-dir.y, dir.x)
		var pulse := 1.0 + 0.15 * sin(_time * 8.0)
		var tip := clamped + dir * 18.0 * pulse
		draw_colored_polygon(PackedVector2Array([tip, clamped + side * 12.0, clamped - side * 12.0]), color)
		var crate_tex: Texture2D = Art.t("crate")
		draw_texture_rect(crate_tex, Rect2(clamped - dir * 22.0 - Vector2(13, 13), Vector2(26, 26)), false)


func _to_screen(world: Vector2) -> Vector2:
	return game.get_viewport().get_canvas_transform() * world


## Draw outlined text. align: 0 = left, 1 = centre, 2 = right. `at` is the baseline.
func _text(at: Vector2, message: String, font_size: int, color: Color, align: int = 0, outline: int = 6) -> void:
	var pos := at
	if align != 0:
		var width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		pos.x -= width * (0.5 if align == 1 else 1.0)
	draw_string_outline(_font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, color.a * 0.85))
	draw_string(_font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
