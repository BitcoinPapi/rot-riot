class_name WeaponTree
extends RefCounted
## Every weapon's own upgrade tree, built from the numbers in Config (WEAPON
## TREES section): the weapon in the middle, one branch per upgrade track the
## weapon has, arcs of nodes between the branches, three perks, and an endless
## node at the tip of each branch.
##
## Which nodes a weapon has learned is stored in SaveData; what the ranks DO is
## in player_stats.gd. Nodes look like the skill tree's (see skill_tree.gd):
##   id, pos, kind ("start", "small", "notable", "arc", "perk", "mastery"),
##   track (which upgrade; "" for the middle and for perks), ranks {track: n},
##   cost, level (WEAPON level needed), repeat, links, name, perk (index or -1)

static var _trees: Dictionary = {}     # weapon id -> {"nodes": {id: node}, "order": [ids]}


static func _tree(weapon_id: String) -> Dictionary:
	if not _trees.has(weapon_id):
		_trees[weapon_id] = _build(weapon_id)
	return _trees[weapon_id]


## Every node of a weapon's tree, by id.
static func nodes(weapon_id: String) -> Dictionary:
	return _tree(weapon_id)["nodes"]


static func order(weapon_id: String) -> Array:
	return _tree(weapon_id)["order"]


static func has(weapon_id: String, id: String) -> bool:
	return nodes(weapon_id).has(id)


## Weapon points for the next purchase of a node of which `owned` are learned.
static func cost(weapon_id: String, id: String, owned: int = 0) -> int:
	var n: Dictionary = nodes(weapon_id)[id]
	if bool(n["repeat"]):
		return int(n["cost"]) + int(float(owned) / float(Config.WEAPON_TREE_ENDLESS_COST_STEP))
	return int(n["cost"])


static func perk(weapon_id: String, index: int) -> Dictionary:
	return (Config.WEAPON_PERKS[weapon_id] as Array)[index]


# ----------------------------------------------------------------------------
#  Building
# ----------------------------------------------------------------------------
static func _build(weapon_id: String) -> Dictionary:
	var all := {}
	var ids: Array = []
	var w: Dictionary = Config.WEAPONS[weapon_id]
	var tracks: Array = Config.weapon_tracks(weapon_id)
	var tiers: Array = Config.WEAPON_TREE_TIERS
	var per_tier: int = Config.WEAPON_TREE_PER_TIER
	var slice := TAU / float(tracks.size())

	var add := func(id: String, pos: Vector2, kind: String, track: String, ranks: Dictionary, node_cost: int,
			level: int, node_name: String) -> Dictionary:
		var n := {"id": id, "pos": pos, "kind": kind, "track": track, "ranks": ranks, "cost": node_cost, "level": level,
				"repeat": false, "links": [], "name": node_name, "perk": -1}
		all[id] = n
		ids.append(id)
		return n
	var link := func(a: String, b: String) -> void:
		(all[a]["links"] as Array).append(b)
		(all[b]["links"] as Array).append(a)

	add.call("start", Vector2.ZERO, "start", "", {}, 0, 1, String(w["name"]))

	# Branches.
	for b in tracks.size():
		var track := String(tracks[b])
		var def: Dictionary = Config.WEAPON_TRACKS[track]
		var out := Vector2.from_angle(-PI * 0.5 + slice * float(b))
		var last := "start"
		for tier in tiers.size():
			var t: Dictionary = tiers[tier]
			for step in per_tier:
				var k := tier * per_tier + step
				var id := "%s.%d" % [track, k]
				var pos := out * (Config.WEAPON_TREE_START_RADIUS + Config.WEAPON_TREE_STEP * float(k))
				if step == per_tier - 1:
					add.call(id, pos, "notable", track, {track: Config.WEAPON_TREE_BIG_RANKS},
							int(t["cost"]) * Config.WEAPON_TREE_BIG_COST_MULT, int(t["level"]), String(def["name"]))
				else:
					add.call(id, pos, "small", track, {track: Config.WEAPON_TREE_SMALL_RANKS}, int(t["cost"]), int(t["level"]),
							String(def["name"]))
				link.call(last, id)
				last = id
		var tip := out * (Config.WEAPON_TREE_START_RADIUS + Config.WEAPON_TREE_STEP * (float(tiers.size() * per_tier) + 0.3))
		var endless: Dictionary = add.call("%s.endless" % track, tip, "mastery", track, {track: Config.WEAPON_TREE_SMALL_RANKS},
				Config.WEAPON_TREE_ENDLESS_COST, Config.WEAPON_TREE_ENDLESS_LEVEL, "ENDLESS %s" % String(def["name"]))
		endless["repeat"] = true
		link.call(last, "%s.endless" % track)

	# Arcs between neighbouring branches at the end of every tier. One gap per
	# tier carries that tier's perk in its middle.
	for tier in tiers.size():
		var t: Dictionary = tiers[tier]
		var k := tier * per_tier + per_tier - 1
		var arc_radius: float = Config.WEAPON_TREE_START_RADIUS + Config.WEAPON_TREE_STEP * float(k)
		var perk_gap := (tier * 2) % tracks.size()
		for b in tracks.size():
			var track_a := String(tracks[b])
			var track_b := String(tracks[(b + 1) % tracks.size()])
			var count := int(t["arc"])
			# Where along the arc (0..1) its nodes sit; -1 marks the perk.
			var spots: Array = []
			for m in count:
				spots.append(float(m + 1) / float(count + 1))
			var perk_spot := -1
			if b == perk_gap and tier < (Config.WEAPON_PERKS[weapon_id] as Array).size():
				if count % 2 == 1:
					perk_spot = int(count / 2.0)
				else:
					perk_spot = int(count / 2.0)
					spots.insert(perk_spot, 0.5)
					# Keep the neighbours clear of the perk.
					for m in spots.size():
						if m != perk_spot:
							spots[m] = float(m + 1) / float(spots.size() + 1)
			if spots.is_empty():
				continue
			var last := "%s.%d" % [track_a, k]
			var angle := -PI * 0.5 + slice * float(b)
			for m in spots.size():
				var at: float = spots[m]
				var pos := Vector2.from_angle(angle + slice * at) * (arc_radius + 14.0 * sin(PI * at))
				var id := "%s-%s.a%d.%d" % [track_a, track_b, tier, m]
				if m == perk_spot:
					id = "perk.%d" % tier
					var p: Dictionary = perk(weapon_id, tier)
					var node: Dictionary = add.call(id, pos, "perk", "", {}, int(Config.WEAPON_PERK_COST[tier]), int(t["level"]),
							String(p["name"]))
					node["perk"] = tier
				else:
					var track := track_a if at <= 0.5 else track_b
					add.call(id, pos, "arc", track, {track: Config.WEAPON_TREE_SMALL_RANKS}, int(t["cost"]), int(t["level"]),
							String(Config.WEAPON_TRACKS[track]["name"]))
				link.call(last, id)
				last = id
			link.call(last, "%s.%d" % [track_b, k])

	return {"nodes": all, "order": ids}
