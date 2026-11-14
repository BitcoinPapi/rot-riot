class_name SkillTree
extends RefCounted
## The skill tree, built once from the numbers in Config (SKILL TREE section).
## Three families grow out of the middle. Each family has a first node, three
## branches (one per stat) of three nodes with a sealed node and a keystone,
## and an endless emblem node at the far end. Every node has several levels.
##
## This file only describes the tree - where each node is, what a level of it
## gives, what it costs and what it needs. Which levels the player has bought
## is stored in SaveData; what the ranks DO is in player_stats.gd.
##
## A node is a Dictionary:
##   id       unique name, e.g. "strength.2" (never change these: saves use them)
##   pos      position in tree space (the middle is at 0,0)
##   kind     "start" (the middle), "root" (a family's first node), "node" (along a
##            stat's branch), "sealed" (needs a deed), "keystone" (a special power)
##            or "cap" (the family's endless emblem)
##   family   which family it belongs to ("" for the middle)
##   stat     the passive it belongs to ("" for start / root / cap)
##   ranks    {passive id: ranks ONE LEVEL of this node gives}
##   max      how many levels it has (0 = endless)
##   cost     skill points per level (for the endless node: the first level, see cost())
##   level    character level needed
##   deed     {} or the deed that unseals it (Config.deed_text)
##   requires ids of the nodes it grows from; ONE of them must have at least
##            `requires_count` levels
##   name     what the info panel calls it
##   note     (optional) an extra line for the info panel, e.g. the pet trick it teaches

# What SaveData.node_status() answers.
const OWNED := 0      # every level bought
const READY := 1      # a level can be bought right now
const POOR := 2       # everything is in order, but not enough skill points
const LEVEL := 3      # character level too low
const SEALED := 4     # its deed is not done yet
const FAR := 5        # the node before it does not have enough levels yet

static var _nodes: Dictionary = {}
static var _order: Array[String] = []


## Every node, by id.
static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build()
	return _nodes


## Node ids in the order they were built (a node always comes after the ones it grows from).
static func order() -> Array[String]:
	if _nodes.is_empty():
		_build()
	return _order


static func has(id: String) -> bool:
	return nodes().has(id)


## Skill points for the next level of a node of which `owned` levels are bought.
static func cost(id: String, owned: int = 0) -> int:
	var n: Dictionary = nodes()[id]
	if int(n["max"]) <= 0:
		return int(n["cost"]) + int(float(owned) / float(Config.TREE_CAP_COST_STEP))
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


## The node whose first level teaches pet trick number `index` (Config.PET_TRICKS):
## BOND's three nodes in order, then BOND's sealed node.
static func trick_node(index: int) -> String:
	return "bond.%d" % (index + 1) if index < Config.TREE_BRANCH.size() else "bond.seal"


## The family a stat belongs to.
static func family_of(stat: String) -> String:
	for family: String in Config.TREE_FAMILY_ORDER:
		if (Config.TREE_FAMILIES[family]["stats"] as Array).has(stat):
			return family
	return ""


# ----------------------------------------------------------------------------
#  Building
# ----------------------------------------------------------------------------
static func _add(id: String, pos: Vector2, kind: String, family: String, stat: String, ranks: Dictionary, levels: int,
		node_cost: int, level: int, requires: Array, requires_count: int, node_name: String) -> Dictionary:
	var n := {"id": id, "pos": pos, "kind": kind, "family": family, "stat": stat, "ranks": ranks, "max": levels, "cost": node_cost,
			"level": level, "deed": {}, "requires": requires, "requires_count": requires_count, "name": node_name}
	_nodes[id] = n
	_order.append(id)
	return n


static func _build() -> void:
	_nodes = {}
	_order = []
	_add("start", Vector2.ZERO, "start", "", "", {}, 1, 0, 1, [], 0, Config.HERO_NAME)

	var fan := deg_to_rad(Config.TREE_FAN_DEG)
	var branch: Array = Config.TREE_BRANCH
	for family: String in Config.TREE_FAMILY_ORDER:
		var fdef: Dictionary = Config.TREE_FAMILIES[family]
		var stats: Array = fdef["stats"]
		var axis := deg_to_rad(float(fdef["angle_deg"]))
		var out := Vector2.from_angle(axis)
		var across := out.orthogonal()

		# The family's first node: every level raises all three of its stats.
		var root_id := "%s.root" % family
		var root_pos := out * Config.TREE_ROOT_DIST
		var all_three := {}
		for stat: String in stats:
			all_three[stat] = 1
		_add(root_id, root_pos, "root", family, "", all_three, Config.TREE_ROOT_LEVELS, Config.TREE_ROOT_COST, 1,
				["start"], 1, "%s BASICS" % String(fdef["name"]))

		var keystones: Array = []
		var middle_key := Vector2.ZERO
		for b in stats.size():
			var stat := String(stats[b])
			var def: Dictionary = Config.PASSIVES[stat]
			var floor_level := int(def.get("min_level", 1))       # (the pet's branch opens later)
			var lean := float(b) - float(stats.size() - 1) * 0.5      # -1, 0, +1
			var dir := Vector2.from_angle(axis + fan * lean)
			var last := root_id
			var last_need := 1
			for k in branch.size():
				var id := "%s.%d" % [stat, k + 1]
				var node := _add(id, root_pos + dir * (Config.TREE_STEP * float(k + 1)), "node", family, stat, {stat: 1},
						Config.TREE_NODE_LEVELS, int(branch[k]["cost"]), maxi(int(branch[k]["level"]), floor_level),
						[last], last_need, String((def["nodes"] as Array)[k]))
				if stat == "bond":
					node["note"] = "TRICK (first level): %s" % String(Config.PET_TRICKS[k]["desc"])
				last = id
				last_need = Config.TREE_NEED_LEVELS

			# A sealed node beside the second node: on the outside of the fan
			# (for the middle branch: to one side).
			var second: Dictionary = _nodes["%s.2" % stat]
			var beside := dir.orthogonal()
			var outside := -lean if lean != 0.0 else 1.0      # (`across` points to the side of the first branch)
			if beside.dot(across) * outside < 0.0:
				beside = -beside
			var sealed := _add("%s.seal" % stat, (second["pos"] as Vector2) + beside * Config.TREE_SEAL_OFFSET, "sealed", family, stat,
					{stat: Config.TREE_SEALED_RANKS}, 1, Config.TREE_SEALED_COST, int(second["level"]), ["%s.2" % stat], 1,
					String(def.get("sealed_name", "%s SECRET" % String(def["name"]))))
			sealed["deed"] = Config.TREE_SEAL_DEEDS[stat]
			if stat == "bond":
				sealed["note"] = "TRICK: %s" % String(Config.PET_TRICKS[branch.size()]["desc"])

			# The keystone at the end of the branch.
			var third: Dictionary = _nodes[last]
			var key := _add("%s.key" % stat, (third["pos"] as Vector2) + dir * Config.TREE_KEY_DIST, "keystone", family, stat, {}, 1,
					Config.TREE_KEYSTONE_COST, int(third["level"]), [last], Config.TREE_NODE_LEVELS, String(Config.KEYSTONES[stat]["name"]))
			key["deed"] = Config.KEYSTONES[stat]["deed"]
			keystones.append("%s.key" % stat)
			if lean == 0.0:
				middle_key = key["pos"]

		# The emblem: the family's endless node, beyond the middle keystone.
		_add("%s.cap" % family, middle_key + out * Config.TREE_CAP_DIST, "cap", family, "", all_three, 0, Config.TREE_CAP_COST,
				Config.TREE_CAP_LEVEL, keystones, 1, "%s MASTERY" % String(fdef["name"]))
