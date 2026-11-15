class_name Mate
extends Node2D
## Another player in a co-op run, as shown on this computer. Their own
## computer runs the real character (moving, shooting, health); here it is a
## figure that glides to wherever they say they are, holds the weapon they
## hold, and shows their shots. Zombies on the host chase it like a player.

var game: Game
var slot := 1                       # their number among the players (0 = the host)
var color := Color(0.45, 0.75, 1.0) # the colour of everything that points at them
var shown_name := "FRIEND"
var pos := Vector2.ZERO             # where the figure is drawn (glides toward net_pos)
var net_pos := Vector2.ZERO         # where their last message says they are
var aim := Vector2.RIGHT
var radius: float = Config.PLAYER_RADIUS
var weapon_id: String = Config.STARTER_WEAPON
var dual := false
var reloading := false
var down := false                   # fallen: waiting to be picked up
var wounded := false
var blinking := false               # just hit: safe for a moment
var choosing := false               # busy choosing a perk (the next wave waits for them)
var fewer := false                  # has FEWER EFFECTS switched on (the host keeps fewer zombies alive)
var hp_frac := 1.0
var pet_id := ""
var pet_pos := Vector2.ZERO
var has_state := false              # a first message has arrived
var reviving_slot := -1             # the fallen player they are picking up (-1 = nobody)...
var reviving := 0.0                 # ...and how far along they are, 0..1

var _font: Font
var _time := 0.0
var _gun_kick := 0.0
var _saw_t := 0.0               # their chainsaw ran this short while ago...
var _saw_phase := 0.0           # ...and is this far along its back-and-forth
var _walk := 0.0
var _anim_t := 0.0
var _anim_hit := 0.0
var _moving := false
var _swing := 0.0
var _swing_side := 1.0
var _flash := 0.0
var _down_t := 0.0
var _sprite := "mate1"


func setup(owner_game: Game, their_slot: int, info: Dictionary, at: Vector2) -> void:
	game = owner_game
	slot = their_slot
	color = Config.COOP_COLORS[slot % Config.COOP_COLORS.size()]
	shown_name = String(info.get("name", "FRIEND"))
	pet_id = String(info.get("pet", ""))
	_sprite = "mate%d" % slot
	Art.build_mate(info.get("worn", {}), _sprite)
	pos = at
	net_pos = at
	pet_pos = at + Vector2(-44.0, 30.0)
	position = at
	_font = ThemeDB.fallback_font


## A message from their computer: where they are and what they hold.
## [x, y, aim angle, weapon number, flags, health 0..1, pet x, pet y, who they are picking up, how far 0..1]
func apply_state(s: Array) -> void:
	if s.size() < 10:
		return
	reviving_slot = int(s[8])
	reviving = clampf(float(s[9]), 0.0, 1.0)
	net_pos = game.arena.clamp_inside(Vector2(float(s[0]), float(s[1])), radius)
	aim = Vector2.from_angle(float(s[2]))
	var index := clampi(int(s[3]), 0, Config.WEAPON_ORDER.size() - 1)
	weapon_id = Config.WEAPON_ORDER[index]
	var flags := int(s[4])
	dual = flags & 1 != 0
	reloading = flags & 2 != 0
	var was_down := down
	down = flags & 4 != 0
	wounded = flags & 8 != 0
	blinking = flags & 64 != 0
	choosing = flags & 16 != 0
	fewer = flags & 32 != 0
	hp_frac = clampf(float(s[5]), 0.0, 1.0)
	pet_pos = Vector2(float(s[6]), float(s[7]))
	if not has_state or pos.distance_to(net_pos) > 400.0:
		pos = net_pos
	has_state = true
	if down and not was_down:
		_down_t = 0.0
		game.fx.blood_burst(pos, 24, 1.4)
		game.decals.blood_splat(pos, 70.0)
		game.hud.announce("%s IS DOWN" % shown_name, "stand beside them to pick them up", Color(1.0, 0.35, 0.3), 3.0)
		Sfx.play("player_die", -4.0)
	elif was_down and not down:
		game.fx.ring(pos, 12.0, 150.0, 0.45, color)
		game.fx.text(pos + Vector2(0, -44), "%s IS BACK UP" % shown_name, color, 20, 1.6)
		Sfx.play("medkit")


func tick(real_dt: float) -> void:
	_time += real_dt
	var before := pos
	pos = pos.lerp(net_pos, 1.0 - exp(-22.0 * real_dt))
	_moving = pos.distance_to(before) > 0.4
	if _moving:
		_walk += real_dt * 14.0
		_anim_t += pos.distance_to(before) / Config.ANIM_HERO_WALK_CYCLE
	else:
		_anim_t += real_dt / Config.ANIM_IDLE_TIME
	_anim_hit = maxf(_anim_hit - real_dt, 0.0)
	position = pos
	_gun_kick = lerpf(_gun_kick, 0.0, minf(real_dt * 22.0, 1.0))
	_swing = maxf(_swing - real_dt / 0.16, 0.0)
	_flash = maxf(_flash - real_dt, 0.0)
	# Their chainsaw swings from side to side while it runs (how exactly, only their own
	# computer knows: here it just goes back and forth).
	_saw_t = maxf(_saw_t - real_dt, 0.0)
	if _saw_t > 0.0:
		_saw_phase += real_dt * 9.0
	else:
		_saw_phase = move_toward(_saw_phase, round(_saw_phase / PI) * PI, real_dt * 9.0)
	if down:
		_down_t += real_dt
	queue_redraw()


## They fired: show it here (the flash, the casing, the sound and bullets that
## look right but hurt nothing - their own computer decides what they hit).
func show_fire(index: int, from: Vector2, angle: float, both_hands: bool) -> void:
	var id: String = Config.WEAPON_ORDER[clampi(index, 0, Config.WEAPON_ORDER.size() - 1)]
	var w: Dictionary = Config.WEAPONS[id]
	var dir := Vector2.from_angle(angle)
	_gun_kick = float(w["recoil_gun"])
	if String(w["kind"]) == "melee":
		if bool(w.get("sweep", false)):
			_saw_t = 0.3
		if bool(w["swing"]):
			_swing = 1.0
			_swing_side = -_swing_side
			game.fx.swing_arc(from, dir, float(w["arc_deg"]), float(w["range"]), _swing_side)
	else:
		var spread := deg_to_rad(float(w["spread_deg"])) * (Config.DUAL_SPREAD_MULT if both_hands else 1.0)
		var muzzle := from + dir * float(w["muzzle_dist"])
		for k in int(w["pellets"]):
			game.projectiles.spawn(from + dir * (radius + 2.0), dir.rotated(randf_range(-0.5, 0.5) * spread), w, id, 0.0, 0.0, false, true)
		if String(w["kind"]) == "flame":
			game.fx.light(muzzle, 110.0, 0.07, Color(1.0, 0.6, 0.2, 0.45))
		else:
			game.fx.muzzle_flash(muzzle, dir, float(w["flash_size"]), w["tracer_color"])
		if String(w["casing"]) != "":
			game.fx.casing(from + dir * 12.0, dir, String(w["casing"]))
	Sfx.play(String(w["sound"]), -7.0)


## The frame of their movement to show now (null = the one still picture).
func _body_frame() -> Texture2D:
	# (Every player is shown as the painted hero, in the pose for what they hold.)
	var anims := Art.anim_of("player" + Art.hero_pose(dual))
	if anims.is_empty():
		return null
	var tail := "_hurt" if wounded else ""
	if _anim_hit > 0.0 and anims.has("hit"):
		return Art.frame_at(anims["hit" + tail], clampf(1.0 - _anim_hit / Config.ANIM_HIT_TIME, 0.0, 0.999))
	if _moving and anims.has("walk"):
		return Art.frame_at(anims["walk" + tail], _anim_t)
	if anims.has("idle"):
		return Art.frame_at(anims["idle" + tail], _anim_t)
	return null


## They were hit (shown as a quick white flash).
func show_hurt() -> void:
	_flash = 0.12
	_anim_hit = Config.ANIM_HIT_TIME


func _draw() -> void:
	if not has_state:
		return
	var blue := color
	# Their pet trots along.
	if pet_id != "" and not down:
		var pet_size := float(Config.PETS[pet_id]["size"])
		draw_set_transform(pet_pos - pos, (pos - pet_pos).angle(), Vector2(pet_size, pet_size))
		Art.draw(self, "pet_" + pet_id, Vector2.ZERO, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if down:
		# Fallen: lying still, with a ring that calls for help - and fills up
		# while you stand beside them.
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var reach: float = Config.COOP_REVIVE_RADIUS
		draw_arc(Vector2.ZERO, reach, 0.0, TAU, 48, Color(1.0, 0.3, 0.25, 0.35 + 0.35 * pulse), 3.0)
		var progress := game.coop.revive_progress if game.coop != null and game.coop.revive_slot == slot else 0.0
		if progress > 0.0:
			draw_arc(Vector2.ZERO, reach, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(0.5, 1.0, 0.55), 6.0)
		draw_set_transform(Vector2.ZERO, aim.angle() + 1.3, Vector2(1.0, 0.86))
		Art.draw(self, _sprite + "_hurt", Vector2.ZERO, 1.0, Color(0.6, 0.5, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_label("%s IS DOWN" % shown_name, Vector2(0.0, -34.0), Color(1.0, 0.4, 0.35), 15)
		return

	# A soft blue ring on the ground, so it is always clear which one is your partner.
	draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 28, Color(blue.r, blue.g, blue.b, 0.55), 2.0)
	var alpha := 0.45 if blinking and fmod(_time, 0.12) < 0.06 else 1.0
	var facing := aim.angle()
	var w: Dictionary = Config.WEAPONS[weapon_id]
	var sweeping := String(w["kind"]) == "melee" and bool(w.get("sweep", false))
	var saw_turn := sin(_saw_phase) * deg_to_rad(float(w.get("arc_deg", 0.0))) * 0.5 if sweeping else 0.0
	var body_turn := facing + (saw_turn if Art.hero_painted() else 0.0)       # (the painted hero turns with his saw)
	var moving := _body_frame() if _flash <= 0.0 else null
	if moving != null:
		# A frame of the hero's movement (walking, standing, flinching).
		var frame_size := Vector2(moving.get_size()) / Art.PX
		draw_set_transform(Vector2.ZERO, body_turn, Vector2.ONE)
		draw_texture_rect(moving, Rect2(-frame_size * 0.5, frame_size), false, Color(1, 1, 1, alpha))
	else:
		var bob := 1.0 + sin(_walk) * 0.035
		draw_set_transform(Vector2.ZERO, body_turn, Vector2(1.0, bob))
		var body := _sprite + Art.hero_pose(dual) + ("_flash" if _flash > 0.0 else ("_hurt" if wounded else ""))
		Art.draw(self, body, Vector2.ZERO, 1.0, Color(1, 1, 1, alpha))

	# The weapon in their hands (at the spots where the hero's hands are).
	var spots := Art.hero_guns(dual, w)
	var gun: Texture2D = Art.t("gun_" + weapon_id)
	var gun_size := Art.size_of("gun_" + weapon_id)
	var tint := Color(1, 1, 1, alpha)
	var tilt := 0.5 if reloading else 0.0
	if String(w["kind"]) == "melee" and bool(w["swing"]):
		var rest := -0.9 * _swing_side
		var sweep := lerpf(1.4, -1.4, 1.0 - _swing) * _swing_side
		draw_set_transform(Vector2.ZERO, facing + (sweep if _swing > 0.0 else rest), Vector2.ONE)
		draw_texture_rect(gun, Rect2(Vector2(8.0, -gun_size.y * 0.5), gun_size), false, tint)
	elif dual:
		for i in 2:
			var fist: Vector2 = spots[i]
			var at := Vector2(fist.x - _gun_kick, fist.y).rotated(facing)
			draw_set_transform(at, facing + tilt * (-1.0 if i == 0 else 1.0), Vector2.ONE)
			draw_texture_rect(gun, Rect2(Vector2(0.0, -gun_size.y * 0.5), gun_size), false, tint)
	elif sweeping:
		var saw: Vector2 = spots[0]
		draw_set_transform(Vector2.ZERO, facing + saw_turn, Vector2.ONE)
		draw_texture_rect(gun, Rect2(Vector2(saw.x - _gun_kick, saw.y - gun_size.y * 0.5), gun_size), false, tint)
	else:
		var held: Vector2 = spots[0]
		draw_set_transform(Vector2(held.x - _gun_kick, held.y).rotated(facing), facing + tilt, Vector2.ONE)
		draw_texture_rect(gun, Rect2(Vector2(0.0, -gun_size.y * 0.5), gun_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_label(shown_name + ("  (choosing a perk)" if choosing else ""), Vector2(0.0, -30.0), blue, 13)


func _label(text: String, at: Vector2, tint: Color, font_size: int) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var from := at - Vector2(width * 0.5, 0.0)
	draw_string_outline(_font, from, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, 0.85))
	draw_string(_font, from, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
