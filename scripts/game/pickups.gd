class_name Pickups
extends Node2D
## Things lying on the ground that the player walks over:
##   coins    - dropped by kills, fly to the player when close, spent in the shop
##   crates   - appear on a timer, give a weapon for a limited time
##   medkits  - rare drops that heal
##   loot     - a piece of gear, dropped rarely (always by bosses); kept forever
##   chests   - a few treasure chests hidden on the map each run; opening one
##              gives a piece of gear and coins
## Coins are plain data in arrays (there can be hundreds); all of it is drawn
## by this one node.

class Crate:
	var id := 0                         # (co-op) the number both computers know it by
	var pos := Vector2.ZERO
	var weapon := ""
	var life := 0.0
	var age := 0.0
	var hp: float = Config.CRATE_HP     # bullets and blasts wear it down (see damage_crate)
	var flash := 0.0                    # white flash after a hit

class Medkit:
	var id := 0
	var pos := Vector2.ZERO
	var life := 0.0
	var age := 0.0

class Loot:
	var id := 0
	var pos := Vector2.ZERO
	var key := ""              # which piece and tier (Config.gear_key)
	var life := 0.0
	var age := 0.0

class Chest:
	var pos := Vector2.ZERO
	var found := false         # the fog over it has cleared: from then on it is marked on the minimap
	var opened := false
	var age := 0.0             # seconds since it was opened

var game: Game
# Co-op: on the joiner's computer everything here is only shown - the host
# decides what appears, who picked it up and when it is gone (the net_...
# functions at the end are the host's messages arriving).
var remote := false
var _next_id := 1
var chests: Array[Chest] = []
var crates: Array[Crate] = []
var medkits: Array[Medkit] = []
var loot: Array[Loot] = []
var crate_t := 2.0               # how far along the last tested path a crate was hit (see crate_on_segment)
var coin_count := 0

var _coin_pos := PackedVector2Array()
var _coin_vel := PackedVector2Array()
var _coin_life := PackedFloat32Array()
var _crate_timer: float = Config.CRATE_FIRST_DELAY
var _time := 0.0
var _coin_streak := 0
var _coin_streak_t := 0.0

var _coin_tex: Texture2D
var _crate_tex: Texture2D
var _crate_flash_tex: Texture2D
var _medkit_tex: Texture2D
var _chest_tex: Texture2D
var _chest_open_tex: Texture2D
var _glow: Texture2D
var _gear_crate_tex: Texture2D
var _gear_band_tex: Texture2D
var _font: Font


func _ready() -> void:
	_gear_crate_tex = Art.t("gear_crate")
	_gear_band_tex = Art.t("gear_crate_band")
	_font = ThemeDB.fallback_font
	_coin_tex = Art.t("coin")
	_crate_tex = Art.t("crate")
	_crate_flash_tex = Art.t("crate_flash")
	_medkit_tex = Art.t("medkit")
	_chest_tex = Art.t("chest")
	_chest_open_tex = Art.t("chest_open")
	_glow = Art.t("glow")
	var cap: int = Config.MAX_COINS_ON_FIELD
	_coin_pos.resize(cap)
	_coin_vel.resize(cap)
	_coin_life.resize(cap)


# ----------------------------------------------------------------------------
#  Spawning
# ----------------------------------------------------------------------------
func drop_from_enemy(e: Enemy) -> void:
	var c: Dictionary = Config.ENEMIES[e.kind]
	if randf() < float(c["coin_chance"]) * (1.0 + game.player.stats.coin_luck):
		spawn_coins(e.pos, randi_range(int(c["coins_min"]), int(c["coins_max"])))
	if randf() < float(c["medkit_chance"]) and medkits.size() < Config.MEDKIT_MAX_ON_FIELD:
		spawn_medkit(e.pos)
	_roll_gear(e)


## Gear is rare: a small chance per zombie (better on later maps and with
## LUCK). A boss always leaves a ring or an amulet, and sometimes more.
func _roll_gear(e: Enemy) -> void:
	if e.kind == Config.BOSS:
		spawn_gear(e.pos + Vector2(-34.0, 26.0), _pick_gear("bosses"))
		if randf() < Config.GEAR_BOSS_EXTRA_CHANCE:
			spawn_gear(e.pos + Vector2(34.0, 26.0), _pick_gear("brutes"))
		return
	var chance: float = float(Config.GEAR_DROP_CHANCE[e.kind]) * float(game.map["gear"]) \
			* (1.0 + game.player.stats.coin_luck * Config.GEAR_LUCK_FACTOR)
	if loot.size() < Config.GEAR_MAX_ON_FIELD and randf() < chance:
		spawn_gear(e.pos, _pick_gear("brutes" if e.kind == Config.BRUTE else String(e.cfg.get("gear_pool", "zombies"))))


## Hide this run's treasure chests on the map: away from the starting spot
## and spread out (each one goes to the best of a few random spots: the one
## furthest from the chests already placed).
func place_chests() -> void:
	chests.clear()
	var arena := game.arena
	var start := game.player.pos
	for n in Config.CHEST_COUNT:
		var best := Vector2.ZERO
		var best_gap := -1.0
		for _try in Config.CHEST_PLACE_TRIES:
			var p := arena.random_free_point(44.0, Config.CHEST_EDGE_MARGIN)
			if p.distance_to(start) < Config.CHEST_MIN_DIST_FROM_START:
				continue
			var gap := 1000000.0
			for other: Chest in chests:
				gap = minf(gap, other.pos.distance_to(p))
			if gap > best_gap:
				best_gap = gap
				best = p
		if best_gap < 0.0:
			continue      # (a map too small to hide anything on)
		var chest := Chest.new()
		chest.pos = best
		chests.append(chest)


## (co-op) Where this run's chests are, to tell the joiner...
func chest_positions() -> Array:
	var list: Array = []
	for chest: Chest in chests:
		list.append([chest.pos.x, chest.pos.y])
	return list


## ...and the joiner putting them in the same places.
func set_chests(list: Variant) -> void:
	chests.clear()
	if typeof(list) != TYPE_ARRAY:
		return
	for spot: Variant in (list as Array):
		if typeof(spot) == TYPE_ARRAY and (spot as Array).size() >= 2:
			var chest := Chest.new()
			chest.pos = game.arena.clamp_inside(Vector2(float((spot as Array)[0]), float((spot as Array)[1])), 40.0)
			chests.append(chest)


## What a treasure chest holds: any piece that zombies or brutes drop on this
## map (rings and amulets stay with the bosses) - usually COMMON, sometimes better.
func roll_chest_gear() -> String:
	var weights: Array = Config.CHEST_TIER_WEIGHTS
	var roll := randf()
	var tier := weights.size()
	for i in weights.size():
		roll -= float(weights[i])
		if roll < 0.0:
			tier = i + 1
			break
	if randf() < float(game.map["gear_up"]):
		tier += 1
	# The deeper into the run the chest is opened, the better.
	if randf() < minf(float(game.director.wave) * Config.CHEST_TIER_UP_PER_WAVE, Config.CHEST_TIER_UP_MAX):
		tier += 1
	return _pick_gear("brutes", mini(tier, Config.GEAR_TIERS.size()))


## Choose a piece for a drop. `source`: "zombies" = pieces any zombie drops,
## "brutes" = those plus the brute pieces, "bosses" = boss-only pieces.
## `tier` 0 = the usual for a drop (COMMON, or one better on later maps).
func _pick_gear(source: String, tier: int = 0) -> String:
	var options: Array[String] = []
	for item: String in Config.GEAR_ORDER:
		var def: Dictionary = Config.GEAR_ITEMS[item]
		if int(def["map"]) > game.map_index + 1:
			continue
		var from := String(def["from"])
		if from == source or (source == "brutes" and from == "zombies"):
			options.append(item)
	if tier <= 0:
		tier = 2 if randf() < float(game.map["gear_up"]) else 1
	return Config.gear_key(options[randi() % options.size()], tier)


func spawn_gear(at: Vector2, key: String) -> void:
	var l := Loot.new()
	l.pos = game.arena.resolve(game.arena.clamp_inside(at, 30.0), 16.0)
	l.key = key
	l.life = Config.GEAR_LIFETIME
	l.id = _new_id()
	loot.append(l)
	if game.coop != null:
		game.coop.send([Coop.E_LOOT_ADD, l.id, l.pos.x, l.pos.y, key])
	_show_new_loot(l)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _show_new_loot(l: Loot) -> void:
	var key := l.key
	game.fog.reveal(l.pos, Config.FOG_DROP_MULT)      # its light burns a hole in the fog
	var color: Color = Config.gear_tier_def(Config.gear_tier_of(key))["color"]
	game.fx.ring(l.pos, 8.0, 110.0, 0.5, Color(color.r, color.g, color.b, 0.9))
	game.fx.light(l.pos, 260.0, 0.4, Color(color.r, color.g, color.b, 0.6))
	Sfx.play("gear_drop")


func spawn_coins(at: Vector2, count: int) -> void:
	if game.coop != null and not remote:
		game.coop.send([Coop.E_COINS, at.x, at.y, count])
	for k in count:
		if coin_count >= _coin_pos.size():
			# Field is full: hand the coin over directly so nothing is lost.
			game.collect_coin(at, false)
			continue
		var i := coin_count
		coin_count += 1
		_coin_pos[i] = at
		_coin_vel[i] = Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * Config.COIN_SCATTER_SPEED
		_coin_life[i] = Config.COIN_LIFETIME


func spawn_crate(at: Vector2, weapon: String = "") -> void:
	var c := Crate.new()
	c.pos = game.arena.resolve(at, 20.0)
	c.weapon = weapon if weapon != "" else _pick_crate_weapon()
	c.life = Config.CRATE_LIFETIME
	c.id = _new_id()
	crates.append(c)
	if game.coop != null:
		game.coop.send([Coop.E_CRATE_ADD, c.id, c.pos.x, c.pos.y, Config.WEAPON_ORDER.find(c.weapon)])
	game.fog.reveal(c.pos, Config.FOG_DROP_MULT)
	game.fx.dust(c.pos, 8)
	Sfx.play("crate_spawn")


# ----------------------------------------------------------------------------
#  Crates can be shot to pieces
# ----------------------------------------------------------------------------
## The first crate a shot flying from `a` to `b` runs into (null = none).
## `crate_t` is then how far along that path (0..1) it is hit. Crates in
## `ignore` (already burnt by this puff of fire) are skipped.
func crate_on_segment(a: Vector2, b: Vector2, shot_radius: float, ignore: Array) -> Crate:
	crate_t = 2.0
	if Config.CRATE_HP <= 0.0:
		return null
	var best: Crate = null
	var d := b - a
	var len2 := d.length_squared()
	var reach: float = Config.CRATE_HIT_RADIUS + shot_radius
	for c: Crate in crates:
		if c.hp <= 0.0 or ignore.has(c):
			continue
		var f := a - c.pos
		var t := 0.0
		if f.length_squared() > reach * reach:
			# Where the path first enters the circle around the crate.
			if len2 <= 0.0001:
				continue
			var half_b := f.dot(d)
			var disc := half_b * half_b - len2 * (f.length_squared() - reach * reach)
			if disc < 0.0:
				continue
			t = (-half_b - sqrt(disc)) / len2
			if t < 0.0 or t > 1.0:
				continue
		if t < crate_t:
			crate_t = t
			best = c
	return best


## Wear a crate down. At zero it bursts and the weapon inside is lost.
func damage_crate(c: Crate, amount: float, dir: Vector2) -> void:
	if Config.CRATE_HP <= 0.0 or c.hp <= 0.0 or amount <= 0.0:
		return
	if remote:
		# (joiner) Show the hit; the host's computer counts it.
		c.flash = Config.CRATE_FLASH_TIME
		game.fx.dust(c.pos - dir * 14.0, 2)
		Sfx.play("crate_hit", 0.0, 0.15)
		game.coop.send_crate_hit(c.id, amount, dir)
		return
	c.hp -= amount
	c.flash = Config.CRATE_FLASH_TIME
	game.fx.dust(c.pos - dir * 14.0, 2)
	if c.hp > 0.0:
		Sfx.play("crate_hit", 0.0, 0.15)
		if game.coop != null:
			game.coop.send([Coop.E_CRATE_HP, c.id, c.hp])
		return
	c.life = 0.0                      # (tick() takes it off the field)
	_show_crate_broken(c, dir)


func _show_crate_broken(c: Crate, dir: Vector2) -> void:
	game.fx.dust(c.pos, 16)
	game.fx.sparks(c.pos, dir, 6)
	game.fx.text(c.pos + Vector2(0, -34), "%s CRATE DESTROYED" % String(Config.WEAPONS[c.weapon]["name"]), Color(1.0, 0.45, 0.35), 17, 1.3)
	game.shake(Config.CRATE_BREAK_SHAKE)
	Sfx.play("crate_break")


## An explosion at `at`: crates inside take the blast, less toward the edge.
func blast_crates(at: Vector2, radius: float, amount: float, edge: float) -> void:
	for c: Crate in crates:
		var away := c.pos - at
		var d := away.length()
		if d < radius + Config.CRATE_HIT_RADIUS:
			damage_crate(c, amount * Config.CRATE_BLAST_MULT * lerpf(1.0, edge, clampf(d / radius, 0.0, 1.0)),
					away / d if d > 0.01 else Vector2.RIGHT)


func spawn_medkit(at: Vector2) -> void:
	var m := Medkit.new()
	m.pos = game.arena.resolve(at, 14.0)
	m.life = Config.MEDKIT_LIFETIME
	m.id = _new_id()
	medkits.append(m)
	if game.coop != null:
		game.coop.send([Coop.E_MEDKIT_ADD, m.id, m.pos.x, m.pos.y])


func _pick_crate_weapon() -> String:
	# Any crate weapon that is not already lying on the field. The weapon the
	# player holds is allowed: a second one means dual wielding.
	var options: Array = []
	for id: String in Config.CRATE_WEAPONS:
		var taken := false
		for c: Crate in crates:
			if c.weapon == id:
				taken = true
		if not taken:
			options.append(id)
	if options.is_empty():
		options = Config.CRATE_WEAPONS.duplicate()
	# Weighted pick: each weapon's rarity tier sets its weight (Config.CRATE_RARITIES)
	# and its own SPAWN RATE upgrade raises its share.
	var weights: Array = []
	var total := 0.0
	for id: String in options:
		var weight: float = Config.crate_weight(id) * (1.0 + SaveData.weapon_value(id, "spawn"))
		weights.append(weight)
		total += weight
	var roll := randf() * total
	for i in options.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


## Crates land near the player, wherever on the map that is - on ground that
## is already uncovered if there is any in reach.
func _random_crate_spot() -> Vector2:
	var spot := Vector2.ZERO
	for _i in 10:
		spot = game.arena.random_free_point_near(game.player.pos, Config.CRATE_MIN_DIST_FROM_PLAYER,
				Config.CRATE_MAX_DIST_FROM_PLAYER, 26.0, 110.0)
		if game.fog.is_clear(spot):
			break
	return spot


# ----------------------------------------------------------------------------
#  Update
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	_time += dt
	var player := game.player
	var ppos := player.pos
	var can_collect := player.alive
	# Co-op: the other players pick things up too.
	var ups: Array[Mate] = game.coop.mates_up() if game.coop != null else ([] as Array[Mate])
	var me: int = game.coop.my_slot if game.coop != null else 0

	# --- coins (on the joiner's computer they are only for show: the count is the host's) ---
	_coin_streak_t -= dt
	if _coin_streak_t <= 0.0:
		_coin_streak = 0
	var magnet: float = Config.COIN_MAGNET_RADIUS * player.stats.magnet_mult
	var magnet2 := magnet * magnet
	var mate_magnet2: float = Config.COIN_MAGNET_RADIUS * Config.COIN_MAGNET_RADIUS
	var pick2: float = Config.COIN_PICKUP_RADIUS * Config.COIN_PICKUP_RADIUS
	var magnet_speed: float = Config.COIN_MAGNET_SPEED
	var keep := maxf(1.0 - 5.0 * dt, 0.0)
	# A pet that knows FETCH picks up what it runs past.
	var pet := game.pet
	var pet_fetches := can_collect and pet != null and pet.fetches()
	var pet_pos := pet.pos if pet != null else Vector2.ZERO
	var pet_pick2: float = Config.PET_FETCH_RADIUS * Config.PET_FETCH_RADIUS
	var i := 0
	while i < coin_count:
		var p := _coin_pos[i]
		var life := _coin_life[i] - dt
		var gone := life <= 0.0
		if not gone:
			var v := _coin_vel[i]
			p += v * dt
			_coin_vel[i] = v * keep
			# It flies to whichever player is nearer.
			var to := ppos - p
			var d2 := to.length_squared() if can_collect else 1.0e12
			var pull2 := magnet2
			var mine := true
			for other: Mate in ups:
				var to_mate := other.pos - p
				var m2 := to_mate.length_squared()
				if m2 < d2:
					to = to_mate
					d2 = m2
					pull2 = mate_magnet2
					mine = false
			if d2 < pick2 or (pet_fetches and p.distance_squared_to(pet_pos) < pet_pick2):
				gone = true
				game.collect_coin(p, mine)
			elif d2 < pull2:
				p += to * (magnet_speed * dt / sqrt(d2))
			_coin_pos[i] = p
			_coin_life[i] = life
		if gone:
			coin_count -= 1
			if i < coin_count:
				_coin_pos[i] = _coin_pos[coin_count]
				_coin_vel[i] = _coin_vel[coin_count]
				_coin_life[i] = _coin_life[coin_count]
		else:
			i += 1

	# --- crates ---
	if game.state == Game.State.PLAYING and not remote:
		_crate_timer -= dt
		if _crate_timer <= 0.0:
			_crate_timer = randf_range(Config.CRATE_INTERVAL_MIN, Config.CRATE_INTERVAL_MAX) / (1.0 + game.player.stats.crate_rate)
			if crates.size() < Config.CRATE_MAX_ON_FIELD:
				spawn_crate(_random_crate_spot())
	i = 0
	while i < crates.size():
		var c := crates[i]
		c.life -= dt
		c.age += dt
		c.flash = maxf(c.flash - dt, 0.0)
		if remote:
			i += 1
			continue
		var who := _toucher(c.pos, Config.CRATE_PICKUP_RADIUS) if c.hp > 0.0 else -1
		if who == me:
			game.collect_crate(c)
		if who >= 0 or c.life <= 0.0:
			if game.coop != null:
				game.coop.send([Coop.E_CRATE_GONE, c.id, 1 if who >= 0 else (2 if c.hp <= 0.0 else 0), who])
				if who >= 0 and who != me:
					game.fx.ring(c.pos, 16.0, 110.0, 0.35, Config.COOP_COLORS[who % Config.COOP_COLORS.size()])
			crates[i] = crates[crates.size() - 1]
			crates.pop_back()
		else:
			i += 1

	# --- medkits ---
	i = 0
	while i < medkits.size():
		var m := medkits[i]
		m.life -= dt
		m.age += dt
		if remote:
			i += 1
			continue
		var healed := _toucher(m.pos, Config.MEDKIT_PICKUP_RADIUS)
		if healed == me and player.hp >= player.max_hp:
			healed = -1       # (nobody picks one up at full health)
		elif healed >= 0 and healed != me and (game.coop.mates[healed] as Mate).hp_frac >= 0.999:
			healed = -1
		if healed == me:
			game.collect_medkit(m.pos)
		if healed >= 0 or m.life <= 0.0:
			if game.coop != null:
				game.coop.send([Coop.E_MEDKIT_GONE, m.id, healed])
			medkits[i] = medkits[medkits.size() - 1]
			medkits.pop_back()
		else:
			i += 1

	# --- treasure chests ---
	for chest: Chest in chests:
		if chest.opened:
			chest.age += dt
			continue
		if not chest.found and game.fog.is_clear(chest.pos):
			chest.found = true
			game.fx.text(chest.pos + Vector2(0, -46), "TREASURE CHEST", Color(1.0, 0.85, 0.3), 18, 1.8)
			Sfx.play_pitched("gear_drop", 0.8, -5.0)
		if not remote and _toucher(chest.pos, Config.CHEST_OPEN_RADIUS) >= 0:
			game.open_chest(chest)

	# --- gear (together, a piece that either player picks up goes to both) ---
	i = 0
	while i < loot.size():
		var l := loot[i]
		l.life -= dt
		l.age += dt
		if remote:
			i += 1
			continue
		var grabbed := _toucher(l.pos, Config.GEAR_PICKUP_RADIUS) >= 0 \
				or (pet_fetches and l.pos.distance_to(pet_pos) < Config.PET_FETCH_RADIUS + pet.radius)
		if grabbed:
			game.collect_gear(l)
		if grabbed or l.life <= 0.0:
			if game.coop != null:
				game.coop.send([Coop.E_LOOT_GONE, l.id, grabbed])
			loot[i] = loot[loot.size() - 1]
			loot.pop_back()
		else:
			i += 1

	queue_redraw()


## Who is standing on something: the slot of that player (alone, the player
## here is 0), or -1 if nobody is.
func _toucher(at: Vector2, reach: float) -> int:
	var player := game.player
	if player.alive and at.distance_to(player.pos) < reach + player.radius:
		return game.coop.my_slot if game.coop != null else 0
	if game.coop != null:
		for other: Mate in game.coop.mates_up():
			if at.distance_to(other.pos) < reach + other.radius:
				return other.slot
	return -1


# ----------------------------------------------------------------------------
#  Co-op: the host's messages arriving on the joiner's computer
# ----------------------------------------------------------------------------
func crate_by_id(id: int) -> Crate:
	for c: Crate in crates:
		if c.id == id:
			return c
	return null


func net_add_crate(id: int, at: Vector2, weapon: String) -> void:
	if not Config.WEAPONS.has(weapon):
		return
	var c := Crate.new()
	c.id = id
	c.pos = at
	c.weapon = weapon
	c.life = Config.CRATE_LIFETIME
	crates.append(c)
	game.fog.reveal(c.pos, Config.FOG_DROP_MULT)
	game.fx.dust(c.pos, 8)
	Sfx.play("crate_spawn")


func net_crate_hp(id: int, hp: float) -> void:
	var c := crate_by_id(id)
	if c != null:
		c.hp = hp
		c.flash = Config.CRATE_FLASH_TIME


## why: 0 = its time ran out, 1 = picked up, 2 = shot to pieces.
func net_crate_gone(id: int, why: int, by_me: bool) -> void:
	var c := crate_by_id(id)
	if c == null:
		return
	crates.erase(c)
	if by_me:
		game.collect_crate(c)
	elif why == 1:
		game.fx.ring(c.pos, 16.0, 110.0, 0.35, Color(1, 1, 1, 0.8))
	elif why == 2:
		_show_crate_broken(c, Vector2.RIGHT)


func net_add_medkit(id: int, at: Vector2) -> void:
	var m := Medkit.new()
	m.id = id
	m.pos = at
	m.life = Config.MEDKIT_LIFETIME
	medkits.append(m)


func net_medkit_gone(id: int, by_me: bool) -> void:
	for m: Medkit in medkits:
		if m.id == id:
			medkits.erase(m)
			if by_me:
				game.collect_medkit(m.pos)
			return


func net_add_loot(id: int, at: Vector2, key: String) -> void:
	if not Config.GEAR_ITEMS.has(Config.gear_item_of(key)):
		return
	var l := Loot.new()
	l.id = id
	l.pos = at
	l.key = key
	l.life = Config.GEAR_LIFETIME
	loot.append(l)
	_show_new_loot(l)


func net_loot_gone(id: int, picked_up: bool) -> void:
	for l: Loot in loot:
		if l.id == id:
			loot.erase(l)
			if picked_up:
				game.collect_gear(l)      # all loot is shared: I get the piece too
			return


func net_chest_opened(index: int, key: String) -> void:
	if index < 0 or index >= chests.size() or chests[index].opened or not Config.GEAR_ITEMS.has(Config.gear_item_of(key)):
		return
	game.open_chest(chests[index], key)


## Each coin grabbed in quick succession plays a slightly higher note.
func next_coin_pitch() -> float:
	_coin_streak = mini(_coin_streak + 1, 14)
	_coin_streak_t = 0.6
	return 1.0 + 0.045 * float(_coin_streak)


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _draw() -> void:
	# Treasure chests: a closed one glints gold; an opened one stays where it is.
	var chest_size := Vector2(Config.CHEST_SIZE, Config.CHEST_SIZE)
	for chest: Chest in chests:
		if chest.opened:
			var fade := clampf(1.0 - chest.age / 1.5, 0.0, 1.0)
			if fade > 0.0:
				var burst := Vector2(220.0, 220.0) * (0.6 + 0.4 * fade)
				draw_texture_rect(_glow, Rect2(chest.pos - burst * 0.5, burst), false, Color(1.0, 0.85, 0.35, 0.7 * fade))
			var pop := chest_size * (1.0 + 0.25 * fade)
			draw_texture_rect(_chest_open_tex, Rect2(chest.pos - pop * 0.5, pop), false, Color(0.72, 0.7, 0.68).lerp(Color.WHITE, fade))
			continue
		var breathe := chest_size * (1.0 + 0.03 * sin(_time * 3.0))
		draw_texture_rect(_chest_tex, Rect2(chest.pos - breathe * 0.5, breathe), false)
		# Two glints wander over the brass.
		for k in 2:
			var t := _time * 1.3 + float(k) * 1.7
			var glint := chest.pos + Vector2(cos(t * 1.3) * 22.0, sin(t) * 12.0 - 4.0)
			var gs := 10.0 * maxf(sin(t * 2.4), 0.0)
			draw_texture_rect(_glow, Rect2(glint - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(1, 1, 0.85, 0.95))
		# Its name underneath, like a crate's.
		var chest_label_at := chest.pos + Vector2(-90.0, chest_size.y * 0.5 + 6.0)
		draw_string_outline(_font, chest_label_at, "TREASURE", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, 6, Color(0, 0, 0, 0.9))
		draw_string(_font, chest_label_at, "TREASURE", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color(1.0, 0.82, 0.3))

	# Coins: a little pulse, and they blink before they vanish.
	var blink_on := fmod(_time, 0.2) < 0.12
	for i in coin_count:
		var life := _coin_life[i]
		if life < 3.0 and not blink_on:
			continue
		var s := 18.0 * (1.0 + 0.12 * sin(_time * 7.0 + float(i)))
		draw_texture_rect(_coin_tex, Rect2(_coin_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false)

	for m: Medkit in medkits:
		if m.life < 4.0 and not blink_on:
			continue
		var s := 28.0 * (1.0 + 0.08 * sin(_time * 5.0)) * minf(m.age * 5.0, 1.0)
		draw_texture_rect(_glow, Rect2(m.pos - Vector2(60, 60) * 0.5, Vector2(60, 60)), false, Color(1.0, 0.3, 0.3, 0.35))
		draw_texture_rect(_medkit_tex, Rect2(m.pos - Vector2(s, s) * 0.5, Vector2(s, s)), false)

	# Gear: a metal case with a big picture of the piece on its lid and the
	# piece's name underneath in the colour of its tier - the same idea as a
	# weapon crate (no rings, no beams of light: the owner does not like them).
	for l: Loot in loot:
		if l.life < 6.0 and not blink_on:
			continue
		var tier := Config.gear_tier_of(l.key)
		var color: Color = Config.gear_tier_def(tier)["color"]
		# Drops in with a bounce, then bobs gently.
		var drop := 1.0 + maxf(0.3 - l.age, 0.0) * 2.5
		var s: float = Config.GEAR_CRATE_SIZE * drop * (1.0 + 0.04 * sin(_time * 4.0 + l.pos.x * 0.05))
		var box := Rect2(l.pos - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_texture_rect(_gear_crate_tex, box, false)
		draw_texture_rect(_gear_band_tex, box, false, color)
		# The piece itself, large, on the lid.
		# (Its own picture as it was painted, if it has one; otherwise the symbol of its
		# kind in the tier's colour.)
		var gear_item := Config.gear_item_of(l.key)
		var painted: Texture2D = Art.gear_picture(gear_item, true)
		var icon: Texture2D = painted if painted != null else Art.t("gear_" + String(Config.GEAR_ITEMS[gear_item]["type"]))
		var isize := Vector2.ONE * (Config.GEAR_CRATE_PICTURE_SIZE if painted != null else Config.GEAR_CRATE_ICON_SIZE) * drop
		var icon_at := l.pos + Vector2(0.0, -2.0 - 2.0 * sin(_time * 3.0 + l.pos.y * 0.05))
		draw_texture_rect(icon, Rect2(icon_at - isize * 0.5 + Vector2(2.0, 3.0), isize), false, Color(0, 0, 0, 0.6))
		draw_texture_rect(icon, Rect2(icon_at - isize * 0.5, isize), false, Color.WHITE if painted != null else color.lightened(0.55))
		# A better tier twinkles more: one glint per tier wanders over the case.
		for k in tier:
			var t := _time * 1.5 + float(k) * 1.9 + l.pos.x * 0.013
			var glint := l.pos + Vector2(cos(t * 1.3 + float(k)) * s * 0.44, sin(t) * s * 0.38)
			var gs := 9.0 * maxf(sin(t * 2.4), 0.0)
			draw_texture_rect(_glow, Rect2(glint - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(1.0, 1.0, 0.92, 0.95))
		# Its name underneath, in the tier's colour: the tier small, the piece below it
		# (two lines: "LEGENDARY FIELD HAND'S LEG GUARDS" does not fit on one).
		var tier_at := l.pos + Vector2(-160.0, s * 0.5 + 13.0)
		var tier_word := String(Config.gear_tier_def(tier)["name"])
		draw_string_outline(_font, tier_at, tier_word, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, 5, Color(0, 0, 0, 0.9))
		draw_string(_font, tier_at, tier_word, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, color.lightened(0.05))
		var gear_label := String(Config.GEAR_ITEMS[Config.gear_item_of(l.key)]["name"]).to_upper()
		var gear_label_at := tier_at + Vector2(0.0, 15.0)
		draw_string_outline(_font, gear_label_at, gear_label, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 14, 6, Color(0, 0, 0, 0.9))
		draw_string(_font, gear_label_at, gear_label, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 14, color.lightened(0.15))

	# Weapon crates: a wooden box with a big picture of the weapon inside and
	# its name underneath, in the colour of its rarity.
	for c: Crate in crates:
		if c.life < 5.0 and not blink_on:
			continue
		var w: Dictionary = Config.WEAPONS[c.weapon]
		var rarity_color: Color = Config.CRATE_RARITIES[String(w["rarity"])]["color"]
		# Drops in with a bounce, then bobs gently.
		var drop := 1.0 + maxf(0.3 - c.age, 0.0) * 2.5
		var s: float = Config.CRATE_SIZE * drop * (1.0 + 0.04 * sin(_time * 4.0))
		var box := Rect2(c.pos - Vector2(s, s) * 0.5, Vector2(s, s))
		var worn := clampf(c.hp / Config.CRATE_HP, 0.0, 1.0) if Config.CRATE_HP > 0.0 else 1.0
		draw_texture_rect(_crate_flash_tex if c.flash > 0.0 else _crate_tex, box, false,
				Color(1, 1, 1).lerp(Color(0.62, 0.55, 0.5), 1.0 - worn))
		# A shot-up crate shows its cracks.
		if worn < 0.67:
			draw_line(c.pos + Vector2(-s * 0.38, -s * 0.3), c.pos + Vector2(-s * 0.05, -s * 0.05), Color(0.08, 0.05, 0.03, 0.85), 2.5)
			draw_line(c.pos + Vector2(-s * 0.05, -s * 0.05), c.pos + Vector2(-s * 0.18, s * 0.22), Color(0.08, 0.05, 0.03, 0.85), 2.5)
		if worn < 0.34:
			draw_line(c.pos + Vector2(s * 0.4, -s * 0.2), c.pos + Vector2(s * 0.1, s * 0.08), Color(0.08, 0.05, 0.03, 0.85), 2.5)
			draw_line(c.pos + Vector2(s * 0.1, s * 0.08), c.pos + Vector2(s * 0.3, s * 0.4), Color(0.08, 0.05, 0.03, 0.85), 2.5)
		# The weapon inside, large, straight across the lid.
		var icon: Texture2D = Art.t("icon_" + c.weapon)
		var icon_size := Art.size_of("icon_" + c.weapon)
		var isize := Vector2(Config.CRATE_ICON_WIDTH, Config.CRATE_ICON_WIDTH * icon_size.y / icon_size.x) * drop
		var icon_at := c.pos + Vector2(0.0, -2.0 - 2.0 * sin(_time * 3.0))
		draw_texture_rect(icon, Rect2(icon_at - isize * 0.5 + Vector2(2.0, 3.0), isize), false, Color(0, 0, 0, 0.55))
		draw_texture_rect(icon, Rect2(icon_at - isize * 0.5, isize), false)
		var label := String(w["name"])
		var label_at := c.pos + Vector2(-90.0, s * 0.5 + 17.0)
		draw_string_outline(_font, label_at, label, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, 6, Color(0, 0, 0, 0.9))
		draw_string(_font, label_at, label, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, rarity_color)
		# How much more it can take, once it has been hit.
		if worn < 1.0:
			var bar := Rect2(c.pos + Vector2(-22.0, s * 0.5 + 22.0), Vector2(44.0, 4.0))
			draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * worn, bar.size.y)), Color(0.9, 0.3, 0.2).lerp(Color(0.95, 0.8, 0.4), worn))
		# "x2": picking this one up would put one in each hand.
		if game.player.alive and game.player.would_dual(c.weapon):
			var at := c.pos + Vector2(s * 0.5 - 4.0, -s * 0.5 + 4.0)
			draw_string_outline(_font, at, "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 6, Color(0, 0, 0, 0.9))
			draw_string(_font, at, "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, 0.9, 0.35))
