class_name Coop
extends Node
## The co-op part of a run: what the two computers tell each other.
##
## WHO DECIDES WHAT
##   * Each computer runs its OWN player for real: moving, shooting, health,
##     reloading. So your own character always reacts instantly.
##   * The HOST's computer runs the world: zombies, waves, pickups, gold.
##   * The joiner's computer shows the host's world: its zombies are copies
##     that glide to where the host says they are. When the joiner's bullets
##     hit a copy, the hit is sent to the host, who applies it for real.
##   * The other players are shown as figures (scripts/game/mate.gd). A
##     joiner hears about the other joiner through the host.
##
## WHAT IS SENT (see scripts/autoload/net.gd for how)
##   * my player's position etc., Config.NET_PLAYER_RATE times a second
##   * (host) a "snapshot" of every zombie and the run's numbers,
##     Config.NET_SNAPSHOT_RATE times a second
##   * events that must not get lost: the list of E_ / C_ codes below
##
## Everything here is about a run in progress; connecting is net.gd's job.

# Events from the host.
const E_KILL := 1          # [id, x, y, dir x, dir y, kind, variant, flags, xp, the killer's slot, weapon number, hit stop]
const E_HURT := 2          # [amount, from x, from y]   a zombie hit you
const E_WAVE_START := 3    # [wave, boss wave]
const E_WAVE_CLEAR := 4    # [wave, coin bonus]
const E_BOSS := 5          # []
const E_CRATE_ADD := 6     # [id, x, y, weapon number]
const E_CRATE_HP := 7      # [id, health]
const E_CRATE_GONE := 8    # [id, why (0 time ran out, 1 picked up, 2 destroyed), the slot of whoever took it or -1]
const E_MEDKIT_ADD := 9    # [id, x, y]
const E_MEDKIT_GONE := 10  # [id, the slot of whoever used it or -1]
const E_LOOT_ADD := 11     # [id, x, y, gear key]
const E_LOOT_GONE := 12    # [id, picked up]
const E_COINS := 13        # [x, y, how many]
const E_CHEST := 14        # [chest number, gear key]
const E_SPIT := 15         # [x, y, dir x, dir y, damage]
const E_LOB := 16          # [from x, from y, to x, to y, damage]
const E_BURST := 17        # [x, y]   a Gasbag went off
const E_OVER := 18         # [the run's shared numbers]   the run has ended
# Events either way.
const E_PAUSE := 19        # [paused]
const E_REVIVE := 20       # [slot]   that player has been picked up
const E_FIRE := 21         # [slot, weapon number, x, y, angle, both hands]
const E_LEFT := 22         # [slot]   that player has left this run
# Events from the joiner.
const C_HITS := 30         # [[id, amount, dir x, dir y, knockback, stagger, crit, weapon number, hit stop], ...]
const C_IGNITE := 31       # [id, seconds, damage per second, weapon number]
const C_KNOCK := 32        # [x, y, radius, force, stagger]   a shove without damage
const C_CRATE_HIT := 33    # [id, amount, dir x, dir y]

# How long each message must be at least (anything shorter is thrown away).
const SIZES := {E_KILL: 13, E_HURT: 4, E_WAVE_START: 3, E_WAVE_CLEAR: 3, E_BOSS: 1, E_CRATE_ADD: 5, E_CRATE_HP: 3,
	E_CRATE_GONE: 4, E_MEDKIT_ADD: 4, E_MEDKIT_GONE: 3, E_LOOT_ADD: 5, E_LOOT_GONE: 3, E_COINS: 4, E_CHEST: 3, E_SPIT: 6,
	E_LOB: 6, E_BURST: 3, E_OVER: 2, E_PAUSE: 2, E_REVIVE: 2, E_FIRE: 7, E_LEFT: 2, C_HITS: 2, C_IGNITE: 5, C_KNOCK: 6,
	C_CRATE_HIT: 5}

var game: Game
var is_host := true
var my_slot := 0                    # my number among the players (0 = the host)
var mates: Dictionary = {}          # slot -> Mate: the other players in this run (one leaves: it is taken out)
var shared: Dictionary = {}         # (joiner) the run's final numbers, as the host counted them
var revive_slot := -1               # the fallen player I am picking up (-1 = nobody)...
var revive_progress := 0.0          # ...and how far along I am, 0..1
var helped := 0.0                   # 0..1: how far somebody is with picking ME up

var _out: Dictionary = {}           # slot -> events waiting to be sent to that player
var _hits: Array = []               # (joiner) hits on zombies waiting to be sent
var _state_t := 0.0
var _snap_t := 0.0
var _snap_no := 0                   # the number of the snapshot being sent / received
var _snap_got := 0                  # (joiner) how many pieces of that snapshot have arrived
var _boss_id := 0


func setup(owner_game: Game, hosting: bool) -> void:
	game = owner_game
	is_host = hosting
	my_slot = Net.slot
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.coop = self
	Net.mate_left.connect(_on_mate_left)


func _exit_tree() -> void:
	if Net.coop == self:
		Net.coop = null


## Put the other players' figures into the world. `slots` = who is in this run.
func add_mates(slots: Array) -> void:
	var middle := game.arena.rect.get_center()
	for entry: Variant in slots:
		var other := int(entry)
		if other == my_slot or other < 0 or other >= Config.COOP_MAX_PLAYERS or not Net.mates.has(other):
			continue
		var mate := Mate.new()
		mate.setup(game, other, Net.mates[other], middle + Config.COOP_START_SPOTS[other])
		game.add_child(mate)
		game.move_child(mate, game.player.get_index())
		mates[other] = mate


## The other players who are on their feet.
func mates_up() -> Array[Mate]:
	var up: Array[Mate] = []
	for other: int in mates.keys():
		var mate: Mate = mates[other]
		if mate.has_state and not mate.down:
			up.append(mate)
	return up


## True if somebody else is still standing.
func someone_up() -> bool:
	return not mates_up().is_empty()


## The names of the other players in this run: "T", "T and SAM".
func names() -> String:
	var list: Array[String] = []
	for other: int in mates.keys():
		list.append((mates[other] as Mate).shown_name)
	return " and ".join(list) if not list.is_empty() else "nobody"


# ----------------------------------------------------------------------------
#  Every frame (called by Game with real time, pauses and hit stops included)
# ----------------------------------------------------------------------------
func tick(real_dt: float, sim_dt: float) -> void:
	if not mates.is_empty():
		helped = 0.0
		for other: int in mates.keys():
			var mate: Mate = mates[other]
			mate.tick(real_dt)
			if mate.reviving_slot == my_slot:
				helped = maxf(helped, mate.reviving)
		_state_t -= real_dt
		if _state_t <= 0.0:
			_state_t = 1.0 / Config.NET_PLAYER_RATE
			var mine := _my_state()
			if is_host:
				for other: int in mates.keys():
					Net.send_state(other, my_slot, mine)
			else:
				Net.send_state(0, my_slot, mine)
		if is_host:
			_snap_t -= real_dt
			if _snap_t <= 0.0:
				_snap_t = 1.0 / Config.NET_SNAPSHOT_RATE
				_send_snapshot()
		_tick_revive(sim_dt)
		# (host) Everybody on the ground: the run is over.
		if is_host and game.state == Game.State.PLAYING and game.player.down and not someone_up():
			var everyone_reported := true
			for other: int in mates.keys():
				if not (mates[other] as Mate).has_state:
					everyone_reported = false
			if everyone_reported:
				game.wipe()
	flush()


## Send everything that is waiting.
func flush() -> void:
	if not _hits.is_empty():
		send([C_HITS, _hits])
		_hits = []
	for to: int in _out.keys():
		var list: Array = _out[to]
		if not list.is_empty():
			Net.send_events(to, list)
	_out = {}


## Queue an event for everybody else in the run (a joiner's go to the host).
func send(event: Array) -> void:
	if is_host:
		for other: int in mates.keys():
			send_to(other, event)
	elif not mates.is_empty():
		send_to(0, event)


## Queue an event for one player.
func send_to(to: int, event: Array) -> void:
	if not _out.has(to):
		_out[to] = []
	(_out[to] as Array).append(event)


## Send one event right now (used while the game is paused, when tick() does not run).
func send_now(event: Array) -> void:
	if is_host:
		for other: int in mates.keys():
			Net.send_events(other, [event])
	elif not mates.is_empty():
		Net.send_events(0, [event])


func _my_state() -> Array:
	var p := game.player
	var flags := 0
	if p.dual:
		flags |= 1
	if p.reloading:
		flags |= 2
	if p.down:
		flags |= 4
	if p.wounded:
		flags |= 8
	if p.invuln > 0.0:
		flags |= 64
	if game.perks_owed > 0:
		flags |= 16                       # choosing a perk: the host holds the next wave
	var pet_at := game.pet.pos if game.pet != null else p.pos
	return [p.pos.x, p.pos.y, p.aim.angle(), Config.WEAPON_ORDER.find(p.weapon_id), flags,
			clampf(p.hp / p.max_hp, 0.0, 1.0), pet_at.x, pet_at.y, revive_slot, revive_progress]


## Where player `who` is. (The host also passes it on to the other joiner.)
func receive_state(who: int, state: Array) -> void:
	if not mates.has(who):
		return
	(mates[who] as Mate).apply_state(state)
	if is_host:
		for other: int in mates.keys():
			if other != who:
				Net.send_state(other, who, state)


## Standing beside a fallen player picks them up (one at a time: the nearest).
func _tick_revive(dt: float) -> void:
	var p := game.player
	var target := -1
	var nearest: float = Config.COOP_REVIVE_RADIUS
	if p.alive:
		for other: int in mates.keys():
			var mate: Mate = mates[other]
			if mate.down:
				var gap := p.pos.distance_to(mate.pos)
				if gap < nearest:
					nearest = gap
					target = other
	if target != revive_slot:
		revive_slot = target
		revive_progress = 0.0
	if target < 0:
		return
	revive_progress += dt / Config.COOP_REVIVE_TIME
	if revive_progress >= 1.0:
		revive_progress = 0.0
		var mate: Mate = mates[target]
		if is_host:
			send_to(target, [E_REVIVE, target])
		else:
			send_to(0, [E_REVIVE, target])       # (the host passes it on)
		game.fx.ring(mate.pos, 12.0, 160.0, 0.45, Color(0.5, 1.0, 0.55, 0.9))


# ----------------------------------------------------------------------------
#  The snapshot: the run's numbers and every zombie, in as few bytes as possible
# ----------------------------------------------------------------------------
## Sent in pieces small enough to travel as one packet each (bigger ones get
## lost more easily). Every piece carries the snapshot's number, so the
## joiner knows when it has seen a whole one.
const PIECE_ZOMBIES := 120

func _send_snapshot() -> void:
	var d := game.director
	var enemies := game.enemies
	var living: Array[Enemy] = []
	for e: Enemy in enemies.active:
		if e.alive:
			living.append(e)
	var pieces := maxi(int(ceil(float(living.size()) / float(PIECE_ZOMBIES))), 1)
	_snap_no = (_snap_no + 1) % 65536
	for piece in pieces:
		var buf := StreamPeerBuffer.new()
		buf.put_u16(_snap_no)
		buf.put_u8(piece)
		buf.put_u8(pieces)
		if piece == 0:
			# The run's numbers ride along with the first piece.
			var flags := 0
			if d.in_wave:
				flags |= 1
			if d.finished:
				flags |= 2
			buf.put_u8(clampi(d.wave, 0, 255))
			buf.put_u8(flags)
			buf.put_u16(clampi(d.remaining() - enemies.alive_count, 0, 65535))
			buf.put_u16(clampi(int(d.intermission * 10.0), 0, 65535))
			buf.put_u32(game.score)
			buf.put_u16(clampi(game.combo, 0, 65535))
			buf.put_u8(clampi(int(game.combo_timer * 50.0), 0, 255))
			buf.put_u32(game.coins_run)
			buf.put_u32(game.kills)
			buf.put_u16(d.boss.net_id if d.boss_alive() else 0)
		var from := piece * PIECE_ZOMBIES
		var to := mini(from + PIECE_ZOMBIES, living.size())
		buf.put_u16(to - from)
		for i in range(from, to):
			var e := living[i]
			var bits := 0
			if e.net_hit:
				bits |= 1
				e.net_hit = false
			if e.wounded:
				bits |= 2
			if e.burn_t > 0.0:
				bits |= 4
			if e.spawn_t > 0.0:
				bits |= 8
			bits |= (e.state & 3) << 4
			buf.put_u16(e.net_id)
			buf.put_u8(e.kind | (e.variant << 4))
			buf.put_16(clampi(int(round(e.pos.x)), -32768, 32767))
			buf.put_16(clampi(int(round(e.pos.y)), -32768, 32767))
			buf.put_u8(int(fposmod(e.face, TAU) / TAU * 256.0) & 255)
			buf.put_u8(bits)
			buf.put_u8(clampi(int(ceil(clampf(e.hp / e.max_hp, 0.0, 1.0) * 255.0)), 0, 255))
		for other: int in mates.keys():
			Net.send_snapshot(other, buf.data_array)


func receive_snapshot(bytes: PackedByteArray) -> void:
	if is_host or bytes.size() < 6 or game.state == Game.State.OVER:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var number := buf.get_u16()
	var piece := buf.get_u8()
	var pieces := buf.get_u8()
	if number != _snap_no:
		_snap_no = number
		_snap_got = 0
	_snap_got += 1
	var d := game.director
	if piece == 0:
		if bytes.size() < 28:
			return
		d.wave = buf.get_u8()
		var flags := buf.get_u8()
		d.in_wave = flags & 1 != 0
		d.finished = flags & 2 != 0
		d.to_spawn = buf.get_u16()
		d.intermission = float(buf.get_u16()) / 10.0
		var score := int(buf.get_u32())
		var combo := buf.get_u16()
		var combo_timer := float(buf.get_u8()) / 50.0
		var coins := int(buf.get_u32())
		var kills := int(buf.get_u32())
		_boss_id = buf.get_u16()
		if shared.is_empty():      # (once the run has ended, its final numbers stand)
			game.score = score
			game.combo = combo
			game.combo_timer = combo_timer
			game.coins_run = coins
			game.kills = kills
	var count := buf.get_u16()
	if buf.get_size() - buf.get_position() < count * 10:
		return
	game.enemies.apply_snapshot(buf, count, number)
	# A whole snapshot has arrived: whatever it did not mention is gone.
	if _snap_got >= pieces:
		game.enemies.drop_unseen(number)
	d.boss = game.enemies.by_id(_boss_id) if _boss_id != 0 else null


# ----------------------------------------------------------------------------
#  Sending (called from the game's own code)
# ----------------------------------------------------------------------------
## (host) A zombie hit another player.
func hurt_mate(mate: Mate, amount: float, from: Vector2) -> void:
	mate.show_hurt()
	send_to(mate.slot, [E_HURT, amount, from.x, from.y])


## (host) A zombie died. `killer` = the slot of the player who killed it.
func send_kill(e: Enemy, dir: Vector2, kill_hitstop: float, source: String, killer: int) -> void:
	var flags := (1 if e.wounded else 0) | (2 if e.burn_t > 0.0 else 0)
	send([E_KILL, e.net_id, e.pos.x, e.pos.y, dir.x, dir.y, e.kind, e.variant, flags, e.xp, killer,
			Config.WEAPON_ORDER.find(source), kill_hitstop])


## (joiner) My shot hit a zombie: the host applies it.
func send_hit(e: Enemy, amount: float, dir: Vector2, knockback: float, stagger: float, crit: bool, source: String, kill_hitstop: float) -> void:
	_hits.append([e.net_id, amount, dir.x, dir.y, knockback, stagger, crit, Config.WEAPON_ORDER.find(source), kill_hitstop])


func send_ignite(e: Enemy, seconds: float, dps: float, source: String) -> void:
	send([C_IGNITE, e.net_id, seconds, dps, Config.WEAPON_ORDER.find(source)])


func send_knock(center: Vector2, radius: float, force: float, stagger: float) -> void:
	send([C_KNOCK, center.x, center.y, radius, force, stagger])


func send_crate_hit(id: int, amount: float, dir: Vector2) -> void:
	send([C_CRATE_HIT, id, amount, dir.x, dir.y])


## I fired: let the other computers show it.
func send_fire(weapon_id: String, from: Vector2, dir: Vector2, both_hands: bool) -> void:
	send([E_FIRE, my_slot, Config.WEAPON_ORDER.find(weapon_id), from.x, from.y, dir.angle(), both_hands])


## (host) The run is over: these are the numbers every player gets.
func send_over(victory: bool) -> void:
	shared = _shared_stats(victory)
	send([E_OVER, shared])
	flush()


func _shared_stats(victory: bool) -> Dictionary:
	return {"score": game.score, "wave": game.director.wave, "kills": game.kills, "coins": game.coins_run,
			"time": game.time_alive, "cleared": game.director.cleared, "victory": victory}


# ----------------------------------------------------------------------------
#  Receiving. `from` is the slot of the player who sent it (for a joiner that
#  is always 0, the host).
# ----------------------------------------------------------------------------
func receive_events(list: Array, from: int) -> void:
	for event: Variant in list:
		if typeof(event) == TYPE_ARRAY and not (event as Array).is_empty():
			_handle(event, from)


func _weapon(index: Variant) -> String:
	var i := int(index)
	return Config.WEAPON_ORDER[i] if i >= 0 and i < Config.WEAPON_ORDER.size() else ""


## (host) Pass an event from one joiner on to the other.
func _pass_on(event: Array, from: int) -> void:
	if not is_host:
		return
	for other: int in mates.keys():
		if other != from:
			if get_tree().paused:
				Net.send_events(other, [event])
			else:
				send_to(other, event)


func _handle(ev: Array, from: int) -> void:
	var code := int(ev[0])
	if not SIZES.has(code) or ev.size() < int(SIZES[code]):
		return
	if is_host and not mates.has(from):
		return       # (somebody who is not in this run)
	# --- either way ---
	match code:
		E_PAUSE:
			game.main_paused_by_mate(bool(ev[1]))
			_pass_on(ev, from)
			return
		E_REVIVE:
			var target := int(ev[1])
			if target == my_slot:
				game.revive_local()
			elif is_host and mates.has(target):
				send_to(target, ev)
			return
		E_FIRE:
			var who := from if is_host else int(ev[1])
			if mates.has(who):
				(mates[who] as Mate).show_fire(int(ev[2]), Vector2(float(ev[3]), float(ev[4])), float(ev[5]), bool(ev[6]))
				_pass_on([E_FIRE, who, ev[2], ev[3], ev[4], ev[5], ev[6]], from)
			return
		E_LEFT:
			_remove(from if is_host else int(ev[1]))
			return
	if is_host:
		_handle_from_joiner(code, ev, from)
	else:
		_handle_from_host(code, ev)


func _handle_from_joiner(code: int, ev: Array, from: int) -> void:
	var enemies := game.enemies
	match code:
		C_HITS:
			if typeof(ev[1]) != TYPE_ARRAY:
				return
			for hit: Variant in (ev[1] as Array):
				if typeof(hit) != TYPE_ARRAY or (hit as Array).size() < 9:
					continue
				var h: Array = hit
				enemies.apply_mate_hit(from, int(h[0]), float(h[1]), Vector2(float(h[2]), float(h[3])), float(h[4]), float(h[5]),
						bool(h[6]), _weapon(h[7]), float(h[8]))
		C_IGNITE:
			enemies.apply_mate_ignite(from, int(ev[1]), float(ev[2]), float(ev[3]), _weapon(ev[4]))
		C_KNOCK:
			enemies.shockwave(Vector2(float(ev[1]), float(ev[2])), float(ev[3]), float(ev[4]), 0.0, float(ev[5]))
		C_CRATE_HIT:
			var crate := game.pickups.crate_by_id(int(ev[1]))
			if crate != null:
				game.pickups.damage_crate(crate, float(ev[2]), Vector2(float(ev[3]), float(ev[4])))


func _handle_from_host(code: int, ev: Array) -> void:
	var pickups := game.pickups
	match code:
		E_KILL:
			game.on_remote_kill(int(ev[1]), Vector2(float(ev[2]), float(ev[3])), Vector2(float(ev[4]), float(ev[5])),
					int(ev[6]), int(ev[7]), int(ev[8]), int(ev[9]), int(ev[10]) == my_slot, _weapon(ev[11]), float(ev[12]))
		E_HURT:
			game.damage_player(float(ev[1]), Vector2(float(ev[2]), float(ev[3])))
		E_WAVE_START:
			game.remote_wave_started(int(ev[1]), bool(ev[2]))
		E_WAVE_CLEAR:
			game.remote_wave_cleared(int(ev[1]), int(ev[2]))
		E_BOSS:
			game.remote_boss_spawned()
		E_CRATE_ADD:
			pickups.net_add_crate(int(ev[1]), Vector2(float(ev[2]), float(ev[3])), _weapon(ev[4]))
		E_CRATE_HP:
			pickups.net_crate_hp(int(ev[1]), float(ev[2]))
		E_CRATE_GONE:
			pickups.net_crate_gone(int(ev[1]), int(ev[2]), int(ev[3]) == my_slot)
		E_MEDKIT_ADD:
			pickups.net_add_medkit(int(ev[1]), Vector2(float(ev[2]), float(ev[3])))
		E_MEDKIT_GONE:
			pickups.net_medkit_gone(int(ev[1]), int(ev[2]) == my_slot)
		E_LOOT_ADD:
			pickups.net_add_loot(int(ev[1]), Vector2(float(ev[2]), float(ev[3])), String(ev[4]))
		E_LOOT_GONE:
			pickups.net_loot_gone(int(ev[1]), bool(ev[2]))
		E_COINS:
			pickups.spawn_coins(Vector2(float(ev[1]), float(ev[2])), int(ev[3]))
		E_CHEST:
			pickups.net_chest_opened(int(ev[1]), String(ev[2]))
		E_SPIT:
			game.enemy_shots.spit(Vector2(float(ev[1]), float(ev[2])), Vector2(float(ev[3]), float(ev[4])),
					Config.ENEMIES[Config.GOBBER], float(ev[5]))
		E_LOB:
			game.enemy_shots.lob(Vector2(float(ev[1]), float(ev[2])), Vector2(float(ev[3]), float(ev[4])),
					Config.ENEMIES[Config.CHUCKER], float(ev[5]))
		E_BURST:
			game.enemies.burst_fx(Vector2(float(ev[1]), float(ev[2])))
		E_OVER:
			if typeof(ev[1]) == TYPE_DICTIONARY:
				shared = ev[1]
				game.finish_from_host(shared)


## A player has gone from the game altogether (they closed it, or the
## connection broke). -1 = the host, and with the host the whole world.
func _on_mate_left(who: int) -> void:
	_remove(0 if who < 0 else who)


## Take a player out of this run (they left it, or are gone altogether).
func _remove(who: int) -> void:
	if not mates.has(who):
		return
	var mate: Mate = mates[who]
	var shown := mate.shown_name
	mate.queue_free()
	mates.erase(who)
	_out.erase(who)
	if revive_slot == who:
		revive_slot = -1
		revive_progress = 0.0
	if is_host:
		# Tell whoever is left.
		for other: int in mates.keys():
			Net.send_events(other, [[E_LEFT, who]])
	game.mate_left(shown, who == 0)
