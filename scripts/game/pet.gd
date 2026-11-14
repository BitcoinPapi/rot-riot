class_name Pet
extends Node2D
## The survivor's pet. It trots at your heel, darts out to bite zombies that
## come close to you and comes back. Which pet it is, how hard it bites and
## which tricks it knows all arrive through the player's stats
## (scripts/game/player_stats.gd); the numbers are in Config (PETS section).
## Zombies ignore it, so it has no health.

var game: Game
var id := ""
var pos := Vector2.ZERO
var radius: float = Config.PET_RADIUS
var target: Enemy = null            # the zombie it is after

var _def: Dictionary = {}
var _loot: Pickups.Loot = null      # the piece of gear it is fetching
var _facing := Vector2.RIGHT
var _bite_cd := 0.0
var _bites := 0
var _think := 0.0
var _guard_cd := 0.0
var _lunge := 0.0                   # bite animation, 1 -> 0
var _walk := 0.0
var _time := 0.0
var _arrive := 0.0                  # pops in when it joins
var _sprite := ""
var _size := 1.0


func setup(owner_game: Game, pet_id: String, at: Vector2) -> void:
	game = owner_game
	id = pet_id
	_def = Config.PETS[pet_id]
	_sprite = "pet_" + pet_id
	_size = float(_def["size"])
	radius = Config.PET_RADIUS * _size
	pos = at
	position = at
	_arrive = 1.0


## True if this pet picks things up (the FETCH trick).
func fetches() -> bool:
	return game.player.stats.pet_fetch


# ----------------------------------------------------------------------------
#  Per-frame update (called by Game)
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	_time += dt
	_bite_cd = maxf(_bite_cd - dt, 0.0)
	_guard_cd = maxf(_guard_cd - dt, 0.0)
	_lunge = maxf(_lunge - dt * 5.0, 0.0)
	_arrive = maxf(_arrive - dt * 2.5, 0.0)
	var player := game.player
	if not player.alive:
		queue_redraw()
		return

	# Decide what to do a few times a second: fetch gear first (it is rare),
	# otherwise go for the zombie nearest to the owner.
	if target != null and (not target.alive or target.pos.distance_to(player.pos) > Config.PET_LEASH):
		target = null
	_think -= dt
	if _think <= 0.0:
		_think = 0.15
		_loot = null
		if fetches() and not game.is_client:      # (on the joiner's computer the host decides who picks gear up)
			for piece: Pickups.Loot in game.pickups.loot:
				if _loot == null or piece.pos.distance_squared_to(pos) < _loot.pos.distance_squared_to(pos):
					_loot = piece
		if target == null and _loot == null:
			target = game.enemies.nearest(player.pos, Config.PET_GUARD_RANGE)

	# Run: to the gear, to the zombie, or back to heel.
	var goal: Vector2
	var reach := 0.0
	var chasing := target != null and _loot == null
	if _loot != null:
		goal = _loot.pos
	elif chasing:
		goal = target.pos
		reach = radius + target.radius + 2.0
	else:
		goal = player.pos - player.aim * Config.PET_HEEL_BEHIND + player.aim.orthogonal() * Config.PET_HEEL_SIDE
	var to := goal - pos
	var dist := to.length()
	if dist > reach + 1.0:
		var step := minf(float(_def["speed"]) * dt, dist - reach)
		if not chasing and _loot == null:
			step = minf(step, dist * 9.0 * dt)       # ease in beside the owner instead of jittering
		pos += to / dist * step
		_walk += step * 0.11
		if dist > 6.0:
			_facing = to / dist
	pos = game.arena.resolve(pos, radius)

	if chasing and dist <= reach + 8.0 and _bite_cd <= 0.0:
		_bite(target)

	position = pos
	rotation = _facing.angle()
	queue_redraw()


func _bite(e: Enemy) -> void:
	var stats := game.player.stats
	var speed := stats.pet_attack_speed
	if game.player.wounded:
		speed *= stats.pet_feral_speed      # FERAL keystone
	_bite_cd = Config.PET_BITE_INTERVAL * float(_def["bite_interval"]) / speed
	_bites += 1
	_lunge = 1.0
	var dir := (e.pos - pos).normalized()
	if dir == Vector2.ZERO:
		dir = _facing
	var dmg := stats.pet_bite
	var knock: float = Config.PET_BITE_KNOCKBACK * float(_def["knockback"])
	# MAUL trick: every few bites is a big one.
	if stats.pet_maul and _bites % Config.PET_MAUL_EVERY == 0:
		dmg *= Config.PET_MAUL_DAMAGE_MULT
		knock = Config.PET_MAUL_KNOCKBACK * float(_def["knockback"])
		game.fx.blood_spray(e.pos, dir, 10, 1.5)
		game.shake(Config.KILL_SHAKE)
	e.pet_marked = true
	game.fx.blood_spray(e.pos, dir, 4, 1.0)
	if bool(_def["ignite"]):
		game.enemies.ignite(e, Config.PET_IGNITE_TIME, dmg * Config.PET_IGNITE_DPS_MULT, "pet")
	game.enemies.damage(e, dmg, dir, knock, Config.PET_BITE_STAGGER, 0.0, "pet")
	Sfx.play("pet_bite", -3.0)


## GUARDIAN trick: the owner was just hit.
func on_owner_hurt() -> void:
	if not game.player.stats.pet_guard or _guard_cd > 0.0:
		return
	_guard_cd = Config.PET_GUARD_COOLDOWN
	game.enemies.shockwave(game.player.pos, Config.PET_GUARD_RADIUS, 0.0, 0.0, Config.PET_GUARD_STAGGER)
	game.fx.ring(pos, 10.0, Config.PET_GUARD_RADIUS, 0.4, Color(1.0, 0.9, 0.6, 0.8))
	game.fx.text(pos + Vector2(0, -30), "!", Color(1.0, 0.9, 0.5), 30, 0.7)
	Sfx.play("pet_call")


# ----------------------------------------------------------------------------
#  Drawing (the node is rotated to face where it runs, so +X is "forward")
# ----------------------------------------------------------------------------
func _draw() -> void:
	var grow := 1.0 - _arrive * _arrive
	var s := _size * grow * (1.0 + 0.04 * sin(_walk))
	var lunge := Vector2(_lunge * 7.0, 0.0)
	if game.player.wounded and game.player.stats.pet_feral_speed > 1.0:
		Art.draw(self, "glow", Vector2.ZERO, 1.5 * _size, Color(1.0, 0.3, 0.1, 0.45))
	draw_set_transform(lunge, 0.0, Vector2(s * (1.0 + 0.12 * _lunge), s))
	Art.draw(self, _sprite, Vector2.ZERO, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
