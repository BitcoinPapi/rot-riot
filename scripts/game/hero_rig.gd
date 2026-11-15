class_name HeroRig
extends RefCounted
## Puts JanJan together from his pieces (drawn by Art from HeroArt, in whatever
## gear he wears): where his body, head, arms, legs, boots and gun go for what
## he is doing right now. His arms are bent so that his hands end up ON the
## gun; his feet step the way he walks; reloading sends his left hand to his
## belt and back. Used for the player, for the other players in co-op and for
## looking at him in the dev gallery. All numbers: Config, THE HERO'S BODY.
##
## Everything is worked out in HIS OWN space: (0, 0) between his shoulders,
## +x where he aims, +y to his right. The caller says where that is on screen.


## What he is doing. One of these is kept by whoever draws him and filled in every frame.
class Pose:
	var look := "player"          # whose pieces: "player", or "mate1" / "mate2" for the others in co-op
	var weapon_id := "pistol"
	var weapon: Dictionary = {}   # the gun's entry in Config.WEAPONS (with its perks)
	var dual := false             # a gun in each hand
	var kick := 0.0               # px the gun is kicked back right now
	var kick_side := 0.0          # two guns: which one kicks (-1 his left, 1 his right, 0 both)
	var reload := -1.0            # how far his left hand is through its trip to the belt and back, 0..1 (-1 = not reloading)
	var shells := false           # ...the trip is one of many (shells going in one by one)
	var tip := 0.0                # how far the gun is tipped over for the reload, 0..1
	var move := Vector2.ZERO      # the way he walks as seen from himself, length 0..1 (0 = standing)
	var step := 0.0               # how far through his steps (goes round and round, 1 = a left and a right step)
	var breath := 0.0             # how far through a breath while he stands (goes round and round)
	var flinch := 0.0             # 1 = hit this moment ... 0
	var flash := false            # shown all white for a moment (just hit)
	var hurt := false             # badly hurt: bloodied, bandaged
	var saw := 0.0                # a swinging chainsaw: where it is beside his aim, radians
	var shudder := 0.0            # a running saw shakes in his hands: px to the side right now
	var fall := 0.0               # 0 = on his feet ... 1 = lying on the ground
	var tint := Color.WHITE


## Where the rear end of his gun(s) sits: one spot, or two (in his left hand, in his
## right hand) when he holds two.
static func gun_spots(two_guns: bool, weapon: Dictionary) -> Array:
	if not two_guns:
		return [weapon.get("butt", Config.HERO_BUTT)]
	var back: float = weapon.get("hold", Config.HERO_HOLD)
	var spots: Array = []
	for hand: Vector2 in Config.HERO_TWIN_HANDS:
		spots.append(Vector2(hand.x - back, hand.y))
	return spots


## The same in game pixels as he is drawn (Config.HERO_SCALE): where the gun really is on
## the screen - for the muzzle flash, the shell cases, where a shot starts.
static func gun_spots_drawn(two_guns: bool, weapon: Dictionary) -> Array:
	var spots := gun_spots(two_guns, weapon)
	for i in spots.size():
		spots[i] = (spots[i] as Vector2) * Config.HERO_SCALE
	return spots


## The pieces to draw, in order: [[sprite name, where and how turned (Transform2D)], ...].
## A gun's picture starts at the middle of its rear end; every other piece says where its
## own (0, 0) is (Art.origin_of).
static func parts(p: Pose) -> Array:
	var ops: Array = []
	var w := p.weapon
	var up := 1.0 - p.fall                       # 1 = on his feet
	var pace := clampf(p.move.length(), 0.0, 1.0) * up
	var way := p.move.normalized() if pace > 0.0 else Vector2.RIGHT
	var swing := sin(TAU * p.step)
	var saw := p.saw * up

	# His shoulders: they turn a little with every step and with the saw, a hit or a
	# kicking gun pushes them back, and falling turns him over.
	var turn := swing * Config.HERO_SWAY * pace + saw * Config.HERO_SAW_BODY + p.fall * Config.HERO_FALL_TURN
	var swell := 1.0 + sin(TAU * p.breath) * Config.HERO_BREATH * (1.0 - pace) * up
	var dip := absf(swing) * Config.HERO_BOB * pace
	var body := Transform2D(turn, Vector2(swell, swell), 0.0, Vector2(dip - Config.HERO_FLINCH * p.flinch * up - p.kick * Config.HERO_KICK_BODY * up, 0.0))

	ops.append(["hero_shadow", Transform2D.IDENTITY])

	# Feet first (they are under everything): each swings ahead and back along the way he walks.
	var boot_turn := Config.HERO_BOOT_TURN * way.y * clampf(way.x * 3.0, -1.0, 1.0) * pace
	for side: float in [-1.0, 1.0]:
		var stand := Vector2(Config.HERO_FOOT.x, Config.HERO_FOOT.y * side) + way * (swing * side * Config.HERO_STEP * pace)
		var lying: Vector2 = body * Vector2(Config.HERO_FALL_FEET.x, Config.HERO_FALL_FEET.y * side)
		var foot := stand.lerp(lying, p.fall)
		var hip: Vector2 = body * Vector2(Config.HERO_HIP.x, Config.HERO_HIP.y * side)
		var leg := foot - hip
		var leg_turn := leg.angle() if leg.length_squared() > 0.25 else 0.0
		ops.append([p.look + "_boot", Transform2D(lerp_angle(boot_turn, leg_turn, p.fall), foot)])
		ops.append([p.look + "_leg", Transform2D(leg_turn, foot)])

	ops.append([p.look + "_body" + ("_hurt" if p.hurt else ""), body])

	# The gun(s) where his hands hold them - and from that, where his hands must be.
	var guns: Array = []                          # [Transform2D] the middle of each gun's rear end
	var right_hand: Vector2
	var left_hand: Vector2
	var hold: float = w.get("hold", Config.HERO_HOLD)
	var shells := String(w.get("reload_kind", "")) == "shell"
	var tilt := p.tip * (Config.HERO_SHELL_TILT if shells else Config.HERO_RELOAD_TILT)
	var pull := p.tip * (Config.HERO_SHELL_PULL if shells else Config.HERO_RELOAD_PULL)
	var spots := gun_spots(p.dual, w)
	var swung := Transform2D(saw, Vector2.ZERO)   # (a swinging saw goes round the middle of him)
	if p.dual:
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			var kick := p.kick if (p.kick_side == 0.0 or p.kick_side == side) else 0.0
			var rear: Vector2 = spots[i]
			# (the gun turns round the hand that grips it)
			guns.append(Transform2D(0.0, Vector2(rear.x + hold - kick - pull, rear.y)) * Transform2D(-tilt * side, Vector2(-hold, 0.0)))
		left_hand = guns[0] * Vector2(hold, 0.0)
		right_hand = guns[1] * Vector2(hold, 0.0)
	else:
		var rear: Vector2 = spots[0]
		var gun: Transform2D = swung * Transform2D(0.0, Vector2(rear.x + hold - p.kick - pull, rear.y + p.shudder)) * Transform2D(-tilt, Vector2(-hold, 0.0))
		guns.append(gun)
		right_hand = gun * Vector2(hold, Config.HERO_GRIP_SIDE)
		var fore := Vector2(float(w["fore"]), float(w.get("fore_side", Config.HERO_FORE_SIDE))) if w.has("fore") else Vector2(hold + 1.6, -Config.HERO_GRIP_SIDE - 0.8)
		left_hand = gun * fore
		if p.reload >= 0.0:
			# His left hand lets go: to the magazine, to the pouch on his hip, back to the
			# gun with a fresh one - and (once the last is in) back to its place.
			var well: Vector2 = gun * Vector2(float(w.get("mag_at", hold + 4.0)), 2.2)
			var pouch: Vector2 = body * Config.HERO_POUCH
			var r := p.reload
			if p.shells:
				left_hand = well.lerp(pouch, 0.5 - 0.5 * cos(TAU * r))
			else:
				left_hand = left_hand.lerp(well, smoothstep(0.0, 0.1, r))
				left_hand = left_hand.lerp(pouch, smoothstep(0.12, 0.32, r))
				left_hand = left_hand.lerp(well, smoothstep(0.36, Config.RELOAD_MAG_IN_AT, r))
				left_hand = left_hand.lerp(gun * fore, smoothstep(Config.RELOAD_RACK_AT - 0.14, Config.RELOAD_RACK_AT, r))

	# Falling: his hands leave the gun and his arms end up stretched out on the ground.
	if p.fall > 0.0:
		var out: Vector2 = Config.HERO_FALL_ARMS
		right_hand = right_hand.lerp(body * out, p.fall)
		left_hand = left_hand.lerp(body * Vector2(out.x, -out.y), p.fall)

	# Arms: bent at the elbow so that each fist lands on its spot, elbows pointing outward.
	# His upper arms go under the gun, his forearms and fists over it: his hands are ON it.
	var forearms: Array = []
	for side: float in [-1.0, 1.0]:
		var shoulder: Vector2 = body * Vector2(Config.HERO_SHOULDER.x, Config.HERO_SHOULDER.y * side)
		var arm := _bend(shoulder, right_hand if side > 0.0 else left_hand, side)
		ops.append([p.look + ("_arm_r" if side > 0.0 else "_arm_l"), Transform2D(arm[0], shoulder)])
		forearms.append([p.look + "_fore", Transform2D(arm[2], arm[1])])

	# The gun (a dropped gun slides away and stays where it fell).
	var drop := smoothstep(0.0, 0.45, p.fall)
	for i in guns.size():
		var held: Transform2D = guns[i]
		if drop > 0.0:
			var side := 1.0 if (i == 1 or guns.size() == 1) else -1.0
			var lies := Transform2D(Config.HERO_FALL_GUN_TURN * side, Vector2(Config.HERO_FALL_GUN.x, Config.HERO_FALL_GUN.y * side))
			held = held.interpolate_with(lies, drop)
		ops.append(["gun_" + p.weapon_id, held])
	ops.append_array(forearms)

	ops.append([p.look + "_head" + ("_hurt" if p.hurt else ""), body * Transform2D(-swing * Config.HERO_SWAY * pace * 0.6, Config.HERO_HEAD)])
	return ops


## One arm from `shoulder` to `fist`: [the upper arm's angle, where the elbow is, the
## forearm's angle]. `side` (1 = his right arm, -1 = his left) says which way the elbow points.
static func _bend(shoulder: Vector2, fist: Vector2, side: float) -> Array:
	var a: float = Config.HERO_ARM_UPPER
	var b: float = Config.HERO_ARM_FORE
	var reach := fist - shoulder
	var d := clampf(reach.length(), absf(a - b) + 0.1, a + b - 0.01)
	var toward := reach.angle() if reach.length_squared() > 0.0001 else 0.0
	var open := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var upper := toward + open * side
	var elbow := shoulder + Vector2.from_angle(upper) * a
	var fore := (shoulder + Vector2.from_angle(toward) * d - elbow).angle()
	return [upper, elbow, fore]


## Draw him. `base` = where his own space is on the canvas item `ci` (IDENTITY for a node
## that already sits at his spot and is turned the way he aims).
static func draw(ci: CanvasItem, base: Transform2D, p: Pose) -> void:
	base = base * Transform2D(0.0, Vector2(Config.HERO_SCALE, Config.HERO_SCALE), 0.0, Vector2.ZERO)
	for op: Array in parts(p):
		var sprite := String(op[0])
		var shown := sprite
		if sprite.begins_with("gun_"):
			var gun_size: Vector2 = Art.size_of(sprite)
			ci.draw_set_transform_matrix(base * (op[1] as Transform2D))
			ci.draw_texture_rect(Art.t(sprite), Rect2(Vector2(0.0, -gun_size.y * 0.5), gun_size), false, p.tint)
			continue
		if sprite == "hero_shadow":
			if p.flash:
				continue
		elif p.flash:
			shown = sprite.trim_suffix("_hurt") + "_flash"
		ci.draw_set_transform_matrix(base * (op[1] as Transform2D))
		ci.draw_texture_rect(Art.t(shown), Rect2(-Art.origin_of(sprite), Art.size_of(sprite)), false, p.tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
