class_name SkillTree
extends RefCounted
## The character's skill tree: a web of nodes built once from the numbers in
## Config (SKILL TREE section). This file only describes the tree - where each
## node is, what it gives, what it costs and what it needs. Which nodes the
## player has is stored in SaveData; what the ranks DO is in player_stats.gd.
##
## A node is a Dictionary:
##   id      unique name, e.g. "strength.4" (never change these: saves use them)
##   pos     position in tree space (the survivor is at 0,0)
##   kind    "start", "small", "notable" (big node), "sealed" (needs a deed),
##           "arc" (links two branches), "keystone" (special power), "mastery" (endless)
##   stat    the passive it belongs to ("" for the start); stat2 = second stat of a hybrid
##   ranks   {passive id: ranks it gives}
##   cost    skill points (for endless nodes: the first rank, see cost())
##   level   character level needed
##   deed    {} or the deed that unseals it (Config.deed_text)
##   repeat  true = can be learned again and again
##   links   ids of the nodes it touches
##   name    what the info panel calls it
##   note    (optional) an extra line for the info panel, e.g. the pet trick a node teaches

# What SaveData.node_status() answers.
const OWNED := 0      # learned
const READY := 1      # can be learned right now
const POOR := 2       # everything is in order, but not enough skill points
const LEVEL := 3      # character level too low
const SEALED := 4     # its deed is not done yet
const FAR := 5        # does not touch a learned node

static var _nodes: Dictionary = {}
static var _order: Array[String] = []


## Every node, by id.
static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build()
	return _nodes


## Node ids in the order they were built (stable, used for drawing and tests).
static func order() -> Array[String]:
	if _nodes.is_empty():
		_build()
	return _order


static func has(id: String) -> bool:
	return nodes().has(id)


## Skill points for the next purchase of a node of which `owned` are learned.
static func cost(id: String, owned: int = 0) -> int:
	var n: Dictionary = nodes()[id]
	if bool(n["repeat"]):
		return int(n["cost"]) + int(float(owned) / float(Config.TREE_MASTERY_COST_STEP))
	return int(n["cost"])


## The keystone's description with its numbers filled in.
static func keystone_text(stat: String) -> String:
	var k: Dictionary = Config.KEYSTONES[stat]
	var value := float(k["value"])
	var text := String(k["desc"])
	match stat:
		"vitality", "strength":
			return text % int(round(value * 100.0))
		"dexterity":
			return text % [int(round(value * 100.0)), int(k["combo"])]
		"agility":
			return text % [int(round(value * 100.0)), int(round(float(k["time"])))]
		"luck":
			return text % [int(round(value)), int(round(float(k["crates"]) * 100.0))]
	return text % int(round(value))


## The big node of the BOND branch that teaches pet trick number `index`.
static func trick_node(index: int) -> String:
	return "bond.%d" % (index * Config.TREE_SPINE_PER_RING + Config.TREE_SPINE_PER_RING - 1)


## How far the tree reaches from the middle (for fitting it on screen).
static func radius() -> float:
	var far := 0.0
	for id: String in order():
		far = maxf(far, (nodes()[id]["pos"] as Vector2).length())
	return far


# ----------------------------------------------------------------------------
#  Building
# ----------------------------------------------------------------------------
static func _add(id: String, pos: Vector2, kind: String, stat: String, ranks: Dictionary, node_cost: int,
		level: int, node_name: String) -> Dictionary:
	var n := {"id": id, "pos": pos, "kind": kind, "stat": stat, "stat2": "", "ranks": ranks, "cost": node_cost,
			"level": level, "deed": {}, "repeat": false, "links": [], "name": node_name}
	_nodes[id] = n
	_order.append(id)
	return n


static func _link(a: String, b: String) -> void:
	(_nodes[a]["links"] as Array).append(b)
	(_nodes[b]["links"] as Array).append(a)


static func _build() -> void:
	_nodes = {}
	_order = []
	var stats: Array = Config.PASSIVE_ORDER
	var branches := stats.size()
	var rings: Array = Config.TREE_RINGS
	var per_ring: int = Config.TREE_SPINE_PER_RING
	var slice := TAU / float(branches)

	_add("start", Vector2.ZERO, "start", "", {}, 0, 1, "SURVIVOR")

	for b in branches:
		var stat := String(stats[b])
		var def: Dictionary = Config.PASSIVES[stat]
		var angle := -PI * 0.5 + slice * float(b)
		var out := Vector2.from_angle(angle)
		var side := out.orthogonal()
		var last := "start"
		var floor_level := int(def.get("min_level", 1))     # (the pet's branch opens later)

		for ring in rings.size():
			var r: Dictionary = rings[ring]
			var ring_cost := int(r["cost"])
			var ring_level := maxi(int(r["level"]), floor_level)
			for step in per_ring:
				var k := ring * per_ring + step
				var id := "%s.%d" % [stat, k]
				var pos := out * (Config.TREE_START_RADIUS + Config.TREE_STEP * float(k))
				if step == per_ring - 1:
					var big := _add(id, pos, "notable", stat, {stat: Config.TREE_NOTABLE_RANKS},
							ring_cost * Config.TREE_NOTABLE_COST_MULT, ring_level, String((def["notables"] as Array)[ring]))
					if stat == "bond" and ring < Config.PET_TRICKS.size():
						big["note"] = "TRICK: %s" % String(Config.PET_TRICKS[ring]["desc"])
				else:
					_add(id, pos, "small", stat, {stat: Config.TREE_SMALL_RANKS}, ring_cost, ring_level, String(def["name"]))
				_link(last, id)
				last = id

			# Side twig off the middle of this ring (alternating sides so the web stays even).
			var twig_from := "%s.%d" % [stat, ring * per_ring + mini(1, per_ring - 1)]
			var twig_dir := (side * (1.0 if ring % 2 == 0 else -1.0) - out * 0.25).normalized()
			var twig_len := int(r["twig"])
			var twig_last := twig_from
			for t in twig_len:
				var tid := "%s.t%d.%d" % [stat, ring, t]
				var tpos: Vector2 = (_nodes[twig_from]["pos"] as Vector2) + twig_dir * (Config.TREE_TWIG_STEP * float(t + 1))
				var deeds: Array = Config.TREE_SEAL_DEEDS[ring]
				if t == twig_len - 1 and twig_len > 1 and not deeds.is_empty():
					var sealed := _add(tid, tpos, "sealed", stat, {stat: Config.TREE_SEALED_RANKS},
							ring_cost * Config.TREE_NOTABLE_COST_MULT, ring_level, "%s SECRET" % String(def["name"]))
					sealed["deed"] = deeds[b % deeds.size()]
				else:
					_add(tid, tpos, "small", stat, {stat: Config.TREE_SMALL_RANKS}, ring_cost, ring_level, String(def["name"]))
				_link(twig_last, tid)
				twig_last = tid

		# The tip: a keystone and an endless node beyond the last big node.
		var tip_radius: float = (_nodes[last]["pos"] as Vector2).length() + Config.TREE_TIP_DISTANCE
		var spread := deg_to_rad(Config.TREE_TIP_SPREAD_DEG)
		var top_level := maxi(int(rings[rings.size() - 1]["level"]), floor_level)
		var key: Dictionary = Config.KEYSTONES[stat]
		var keystone := _add("%s.key" % stat, Vector2.from_angle(angle - spread) * tip_radius, "keystone", stat, {},
				Config.TREE_KEYSTONE_COST, top_level, String(key["name"]))
		keystone["deed"] = key["deed"]
		_link(last, "%s.key" % stat)
		var mastery := _add("%s.mastery" % stat, Vector2.from_angle(angle + spread) * tip_radius, "mastery", stat,
				{stat: Config.TREE_MASTERY_RANKS}, Config.TREE_MASTERY_COST, top_level, "ENDLESS %s" % String(def["name"]))
		mastery["repeat"] = true
		_link(last, "%s.mastery" % stat)

	# Arcs: a chain of nodes from each ring's big node to the same ring's big
	# node on the next branch. The half nearer a branch gives that branch's
	# stat; a node exactly in the middle gives both.
	for b in branches:
		var stat_a := String(stats[b])
		var stat_b := String(stats[(b + 1) % branches])
		var angle := -PI * 0.5 + slice * float(b)
		for ring in rings.size():
			var r: Dictionary = rings[ring]
			var count := int(r["arc"])
			var k := ring * per_ring + per_ring - 1
			var arc_radius: float = Config.TREE_START_RADIUS + Config.TREE_STEP * float(k)
			var last := "%s.%d" % [stat_a, k]
			for m in count:
				var t := float(m + 1) / float(count + 1)
				var pos := Vector2.from_angle(angle + slice * t) * (arc_radius + (8.0 + 5.0 * float(ring)) * sin(PI * t))
				var id := "%s-%s.a%d.%d" % [stat_a, stat_b, ring, m]
				var middle := absf(t - 0.5) < 0.01
				var owner := stat_a if t < 0.5 else stat_b
				var ranks := {owner: Config.TREE_SMALL_RANKS}
				var arc_cost := int(r["cost"])
				var arc_name := String(Config.PASSIVES[owner]["name"])
				if middle:
					ranks = {stat_a: Config.TREE_SMALL_RANKS, stat_b: Config.TREE_SMALL_RANKS}
					arc_cost += 1
					arc_name = "%s + %s" % [String(Config.PASSIVES[stat_a]["name"]), String(Config.PASSIVES[stat_b]["name"])]
				var arc_level := int(r["level"])
				for giver: String in ranks.keys():
					arc_level = maxi(arc_level, int(Config.PASSIVES[giver].get("min_level", 1)))
				var node := _add(id, pos, "arc", stat_a if middle else owner, ranks, arc_cost, arc_level, arc_name)
				if middle:
					node["stat2"] = stat_b
				_link(last, id)
				last = id
			_link(last, "%s.%d" % [stat_b, k])
