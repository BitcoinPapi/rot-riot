class_name Hud
extends Control
## The in-game overlay: health, weapon timer, score, coins, wave info,
## boss bar, minimap, crosshair and big announcements. Everything is drawn in
## _draw from the Game's state, so there is nothing to keep in sync.

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
var _tips: Array = []           # one-time explanations waiting their turn: [title, text, colour, seconds]
var _tip_t := 0.0               # how long the first of them has left
var _fps_log: Array[float] = [] # F3 counter: the frame rate, noted once a second, for "lowest"
var _fps_t := 0.0


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


## A one-time explanation (a new kind of zombie...). It gets a line of its
## own near the bottom of the screen, so the wave banners cannot push it away;
## several are shown one after the other.
func show_tip(title: String, text: String, color: Color, duration: float) -> void:
	_tips.append([title, text, color, duration])
	if _tips.size() == 1:
		_tip_t = duration


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
	_fps_t += real_dt
	if _fps_t >= 1.0:
		_fps_t = 0.0
		_fps_log.append(Engine.get_frames_per_second())
		while _fps_log.size() > int(Config.STATS_LOW_WINDOW):
			_fps_log.pop_front()
	if not _tips.is_empty():
		_tip_t -= real_dt
		if _tip_t <= 0.0:
			_tips.pop_front()
			if not _tips.is_empty():
				_tip_t = float((_tips[0] as Array)[3])
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
	_draw_health(p)
	_draw_weapon(p, h)
	_draw_perks(h)
	_draw_xp(w, h)
	_draw_score(w)
	_draw_wave(w)
	_draw_minimap(w, h)
	_draw_announcement(w, h)
	if not game.choosing():
		_draw_hint(w, h)
	_draw_tip(w, h)
	if GameInput.stats_shown:
		_text(Vector2(14.0, h * 0.5), stats_line(), 15, Color(0.75, 1.0, 0.7, 0.95))
	if p.alive and not game.choosing():
		_draw_crosshair(p)


func _draw_vignettes(p: Player) -> void:
	var vignette: Texture2D = Art.t("vignette")
	var full := Rect2(Vector2.ZERO, size)
	# Always-on dark corners for mood.
	draw_texture_rect(vignette, full, false, Color(0, 0, 0, 0.55))
	var frac := p.hp / p.max_hp
	if frac < 0.3 and p.alive:
		draw_texture_rect(vignette, full, false, Color(0.9, 0.0, 0.0, 0.3 + 0.25 * sin(_time * 7.0)))
	if _hurt > 0.0:
		draw_texture_rect(vignette, full, false, Color(1.0, 0.05, 0.05, _hurt * 0.85))
		draw_rect(full, Color(1.0, 0.0, 0.0, _hurt * 0.12))


func _draw_health(p: Player) -> void:
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

	# The pet at your side and what it adds.
	if game.pet != null:
		var pet_def: Dictionary = Config.PETS[game.pet.id]
		var pet_color: Color = Config.PET_RARITIES[String(pet_def["rarity"])]["color"]
		_text(Vector2(x, y + bar_h + 24.0), "%s   +%s%% damage" % [String(pet_def["name"]), String.num(p.stats.pet_damage * 100.0, 1)], 13,
				Color(pet_color.r, pet_color.g, pet_color.b, 0.9), 0, 4)

	# Co-op: the other players' names and health.
	if game.coop != null:
		var my := y + bar_h + (40.0 if game.pet != null else 24.0)
		var mw := 190.0
		for other: int in game.coop.mates.keys():
			var mate: Mate = game.coop.mates[other]
			_text(Vector2(x, my + 10.0), mate.shown_name, 14, mate.color, 0, 4)
			var name_w := maxf(_font.get_string_size(mate.shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0, 64.0)
			draw_rect(Rect2(x + name_w - 2.0, my - 2.0, mw + 4.0, 14.0), Color(0, 0, 0, 0.65))
			if mate.down:
				var blink := 0.55 + 0.45 * sin(_time * 8.0)
				_text(Vector2(x + name_w + 4.0, my + 10.0), "DOWN - GO AND PICK THEM UP", 12, Color(1.0, 0.4, 0.35, blink), 0, 4)
			else:
				draw_rect(Rect2(x + name_w, my, mw, 10.0), Color(0.08, 0.12, 0.18))
				draw_rect(Rect2(x + name_w, my, mw * mate.hp_frac, 10.0), mate.color.darkened(0.15) if mate.hp_frac > 0.3 else Color(0.9, 0.3, 0.25))
			my += 20.0

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
## The perks chosen this run: a row of small symbols above the weapon panel,
## with a number on those taken more than once.
func _draw_perks(h: float) -> void:
	if game.perks.is_empty():
		return
	var x := 22.0
	var y := h - 18.0 - 96.0 - 38.0
	for id: String in Config.RUN_PERK_ORDER:
		var level := int(game.perks.get(id, 0))
		if level <= 0:
			continue
		var perk: Dictionary = Config.RUN_PERKS[id]
		var color: Color = perk["color"]
		draw_rect(Rect2(x - 2.0, y - 2.0, 32.0, 32.0), Color(0, 0, 0, 0.6))
		draw_texture_rect(Art.t(String(perk["icon"])), Rect2(x + 2.0, y + 2.0, 24.0, 24.0), false, color)
		if level > 1:
			_text(Vector2(x + 29.0, y + 29.0), str(level), 13, Color.WHITE, 2, 4)
		x += 36.0


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
	_text(Vector2(cx, 15), "ZONE %d  -  %s" % [game.map_index + 1, String(game.map["name"])], 12,
			Color(map_color.r, map_color.g, map_color.b, 0.85), 1, 4)
	_text(Vector2(cx, 40), "WAVE %d / %d" % [d.wave, Config.WAVES_PER_MAP], 26, Color.WHITE, 1)
	if d.finished:
		_text(Vector2(cx, 62), "zone taken back", 15, Color(1.0, 0.85, 0.3, 0.95), 1)
	elif d.in_wave:
		_text(Vector2(cx, 62), "%d left" % d.remaining(), 15, Color(1, 1, 1, 0.7), 1)
	elif game.perks_pending():
		# (The next wave waits while somebody chooses a perk.)
		var busy := game.perk_waiting_for()
		var who := "you choose" if game.perks_owed > 0 else " and ".join(busy) + (" chooses" if busy.size() == 1 else " choose")
		_text(Vector2(cx, 62), "the next wave waits while %s a perk" % who, 15, Color(1.0, 0.85, 0.3, 0.95), 1)
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
		_text(Vector2(cx, by + 36), Config.boss_name(game.map_index), 16, Color(1.0, 0.5, 0.4), 1)


## The whole map in the corner: where you have been (the rest is fog), where
## you are and what is on the field.
func _draw_minimap(w: float, h: float) -> void:
	var arena := game.arena.rect
	var mw: float = Config.MINIMAP_WIDTH
	var mh := mw * arena.size.y / arena.size.x
	var box := Rect2(Vector2(w - Config.MINIMAP_MARGIN.x - mw, h - Config.MINIMAP_MARGIN.y - mh), Vector2(mw, mh))
	var k := mw / arena.size.x                     # world pixels -> minimap pixels
	var from := box.position - arena.position * k
	draw_rect(box.grow(4.0), Color(0, 0, 0, 0.7))
	draw_rect(box, Config.MINIMAP_GROUND)
	if game.arena.pond:
		# The pond (under the fog, like everything not seen yet).
		var water := game.arena.pond_outline(28)
		for i in water.size():
			water[i] = from + water[i] * k
		draw_colored_polygon(water, Config.MINIMAP_POND)

	# Zombies: small red dots (the fog is drawn over them).
	var red := Color(0.95, 0.2, 0.15, 0.9)
	for e: Enemy in game.enemies.active:
		if e.alive and not e.is_big:
			draw_rect(Rect2(from + e.pos * k - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), red)

	draw_texture_rect_region(game.fog.texture, box, game.fog.map_region(), Config.MINIMAP_FOG)

	# What matters is drawn over the fog: chests you have seen, weapon
	# crates, gear, the boss, you.
	var chests_open := 0
	for chest: Pickups.Chest in game.pickups.chests:
		if chest.opened:
			chests_open += 1
			_map_mark(from + chest.pos * k, 2.0, Color(0.5, 0.42, 0.3))
		elif chest.found:
			_map_mark(from + chest.pos * k, 3.5 + 1.0 * sin(_time * 5.0), Color(1.0, 0.82, 0.3))
	for crate: Pickups.Crate in game.pickups.crates:
		var crate_color: Color = Config.CRATE_RARITIES[String(Config.WEAPONS[crate.weapon]["rarity"])]["color"]
		_map_mark(from + crate.pos * k, 3.0, crate_color)
	for piece: Pickups.Loot in game.pickups.loot:
		_map_mark(from + piece.pos * k, 3.0, Config.gear_tier_def(Config.gear_tier_of(piece.key))["color"])
	for boss: Enemy in game.enemies.bigs:
		if boss.alive:
			var pulse := 4.0 + 1.5 * sin(_time * 8.0)
			_map_mark(from + boss.pos * k, pulse, Color(1.0, 0.15, 0.1))
	# Co-op: the other players (each in their colour; red and blinking when down).
	if game.coop != null:
		for other: int in game.coop.mates.keys():
			var mate: Mate = game.coop.mates[other]
			if not mate.has_state:
				continue
			var mate_at := from + mate.pos * k
			if mate.down:
				_map_mark(mate_at, 3.5 + 1.2 * sin(_time * 9.0), Color(1.0, 0.3, 0.25))
			else:
				var facing := mate.aim
				var across := Vector2(-facing.y, facing.x)
				draw_colored_polygon(PackedVector2Array([mate_at + facing * 7.0, mate_at - facing * 4.0 + across * 4.5,
						mate_at - facing * 4.0 - across * 4.5]), Color(0, 0, 0, 0.9))
				draw_colored_polygon(PackedVector2Array([mate_at + facing * 5.5, mate_at - facing * 3.0 + across * 3.2,
						mate_at - facing * 3.0 - across * 3.2]), mate.color)
	# What the screen shows, and the player in the middle of it.
	var view := game.cam.view_rect()
	var seen := Rect2(from + view.position * k, view.size * k).intersection(box)
	draw_rect(seen, Color(1, 1, 1, 0.3), false, 1.0)
	var at := from + game.player.pos * k
	var aim := game.player.aim
	var side := Vector2(-aim.y, aim.x)
	draw_colored_polygon(PackedVector2Array([at + aim * 7.0, at - aim * 4.0 + side * 4.5, at - aim * 4.0 - side * 4.5]), Color(0, 0, 0, 0.9))
	draw_colored_polygon(PackedVector2Array([at + aim * 5.5, at - aim * 3.0 + side * 3.2, at - aim * 3.0 - side * 3.2]), Color.WHITE)
	draw_rect(box, Color(1, 1, 1, 0.22), false, 1.0)

	# Above the map: treasure chests opened, and how much of the map you have seen.
	var label_y := box.position.y - 10.0
	_text(Vector2(box.end.x, label_y), "%d%% explored" % int(floor(game.fog.explored * 100.0)), 13, Color(1, 1, 1, 0.6), 2, 4)
	var chest_total := game.pickups.chests.size()
	if chest_total > 0:
		draw_texture_rect(Art.t("chest"), Rect2(box.position.x - 3.0, label_y - 19.0, 26.0, 26.0), false)
		_text(Vector2(box.position.x + 27.0, label_y), "%d / %d" % [chests_open, chest_total], 15,
				Color(1.0, 0.85, 0.35) if chests_open < chest_total else Color(0.6, 1.0, 0.5), 0, 4)


## A small square mark on the minimap, with a dark edge so it shows on anything.
func _map_mark(at: Vector2, half: float, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(half + 1.0, half + 1.0), Vector2(half + 1.0, half + 1.0) * 2.0), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), color)


func _draw_announcement(w: float, h: float) -> void:
	# Co-op: lying on the ground, waiting for your partner.
	if game.player.down and game.coop != null and game.state == Game.State.PLAYING:
		var helping := game.coop.helped
		_text(Vector2(w * 0.5, h * 0.62), "YOU ARE DOWN", 38, Color(1.0, 0.35, 0.3, 0.75 + 0.25 * sin(_time * 5.0)), 1, 10)
		_text(Vector2(w * 0.5, h * 0.62 + 30.0),
				("You are being picked up...  %d%%" % int(helping * 100.0)) if helping > 0.0 else
				("%s can pick you up by standing beside you  -  or clear the wave" % game.coop.names()), 18, Color(1, 1, 1, 0.9), 1)
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


func _draw_tip(w: float, h: float) -> void:
	if _tips.is_empty():
		return
	var entry: Array = _tips[0]
	var total := float(entry[3])
	var alpha := clampf((total - _tip_t) / 0.2, 0.0, 1.0) * clampf(_tip_t / 0.5, 0.0, 1.0)
	var color: Color = entry[2]
	var title := "NEW:  %s" % String(entry[0])
	var text := String(entry[1])
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var title_w := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var bw := maxf(text_w, title_w) + 48.0
	var box := Rect2(w * 0.5 - bw * 0.5, h - 206.0, bw, 70.0)
	draw_rect(box, Color(0, 0, 0, 0.62 * alpha))
	draw_rect(Rect2(box.position, Vector2(5.0, box.size.y)), Color(color.r, color.g, color.b, alpha))
	draw_rect(Rect2(box.end.x - 5.0, box.position.y, 5.0, box.size.y), Color(color.r, color.g, color.b, alpha))
	_text(Vector2(w * 0.5, box.position.y + 29.0), title, 24, Color(color.r, color.g, color.b, alpha), 1)
	_text(Vector2(w * 0.5, box.position.y + 56.0), text, 19, Color(1, 1, 1, alpha), 1, 4)


func _draw_hint(w: float, h: float) -> void:
	if _hint_t <= 0.0 or game.director.wave > 1:
		return
	var alpha := clampf(_hint_t / 1.0, 0.0, 1.0) * 0.9
	var hint := "WASD move   -   MOUSE aim   -   LEFT CLICK shoot   -   R reload   -   ESC pause"
	if GameInput.using_gamepad():
		hint = "LEFT STICK move   -   RIGHT STICK aim   -   RT shoot   -   X reload   -   START pause"
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


## Arrows at the screen edge pointing to weapon crates, dropped gear and
## treasure chests you have seen but not opened, when they are out of view.
func _draw_crate_arrows() -> void:
	# Co-op: where the other players are (red when one is down and needs you).
	if game.coop != null:
		for other: int in game.coop.mates.keys():
			var mate: Mate = game.coop.mates[other]
			if mate.has_state:
				_edge_arrow(mate.pos, Color(1.0, 0.35, 0.3) if mate.down else mate.color, Art.t("mate%d_head" % other), Color.WHITE)
	for chest: Pickups.Chest in game.pickups.chests:
		if chest.found and not chest.opened:
			_edge_arrow(chest.pos, Color(1.0, 0.82, 0.3), Art.t("chest"), Color.WHITE)
	for crate: Pickups.Crate in game.pickups.crates:
		_edge_arrow(crate.pos, Config.CRATE_RARITIES[String(Config.WEAPONS[crate.weapon]["rarity"])]["color"],
				Art.t("icon_" + crate.weapon), Color.WHITE)
	for piece: Pickups.Loot in game.pickups.loot:
		var color: Color = Config.gear_tier_def(Config.gear_tier_of(piece.key))["color"]
		_edge_arrow(piece.pos, color, Art.t("gear_" + String(Config.GEAR_ITEMS[Config.gear_item_of(piece.key)]["type"])),
				color.lightened(0.4))


func _edge_arrow(world: Vector2, color: Color, icon: Texture2D, icon_color: Color) -> void:
	# Only for things that really are off the screen; the arrow itself is kept
	# clear of the bars at the top and bottom.
	var view := Rect2(Vector2(46.0, 128.0), size - Vector2(92.0, 228.0))
	var sp := _to_screen(world)
	if Rect2(Vector2.ZERO, size).grow(-12.0).has_point(sp):
		return
	var clamped := Vector2(clampf(sp.x, view.position.x, view.end.x), clampf(sp.y, view.position.y, view.end.y))
	var dir := (sp - clamped).normalized()
	var side := Vector2(-dir.y, dir.x)
	var pulse := 1.0 + 0.15 * sin(_time * 8.0)
	var tip := clamped + dir * 18.0 * pulse
	draw_colored_polygon(PackedVector2Array([tip, clamped + side * 12.0, clamped - side * 12.0]), color)
	# (Weapon pictures are wide: keep their shape.)
	var shape := icon.get_size()
	var icon_size := Vector2(26, 26) if is_equal_approx(shape.x, shape.y) else Vector2(64.0, 64.0 * shape.y / shape.x)
	draw_texture_rect(icon, Rect2(clamped - dir * (14.0 + icon_size.x * 0.5) - icon_size * 0.5, icon_size), false, icon_color)


## The F3 counter: how smoothly the game runs on this computer, and how much
## is going on. Made for telling us numbers ("FPS 31, lowest 22, 240 zombies").
func stats_line() -> String:
	var fps := Engine.get_frames_per_second()
	var lowest := fps
	for noted: float in _fps_log:
		lowest = minf(lowest, noted)
	return "FPS %d   lowest %d   zombies %d / %d   effects %d%s" % [int(round(fps)), int(round(lowest)),
			game.enemies.alive_count, game.max_alive(), game.fx.flying(),
			"   FEWER EFFECTS on" if bool(SaveData.get_setting("fewer_effects")) else ""]


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
