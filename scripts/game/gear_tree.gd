class_name GearTree
extends RefCounted
## The layout of the Gear screen, built from Config (GEAR section): the nine
## slots in the middle laid out like a body, and around them one sector per
## kind of piece (helmets, amulets, rings, ...). Every piece has a row of five
## nodes, one per tier, running outwards.
##
## This file only says where things are. What the player owns is in SaveData.
## A node is a Dictionary:
##   id     "slot.<slot>", "type.<kind>" or "<piece>.<tier>"
##   pos    position (the body is around 0,0)
##   kind   "slot" (something is worn here), "type" (where a sector starts)
##          or "item" (one piece at one tier)
##   slot / type / item / tier   what it stands for
##   links  ids of the nodes it is joined to

static var _nodes: Dictionary = {}
static var _order: Array[String] = []


static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build()
	return _nodes


static func order() -> Array[String]:
	if _nodes.is_empty():
		_build()
	return _order


static func slot_id(slot: String) -> String:
	return "slot.%s" % slot


static func item_id(item: String, tier: int) -> String:
	return "%s.%d" % [item, tier]


## The node of a piece given as "item:tier" (Config.gear_key).
static func key_id(key: String) -> String:
	return item_id(Config.gear_item_of(key), Config.gear_tier_of(key))


## Distance of a tier's nodes from the middle.
static func tier_radius(tier: int) -> float:
	return Config.GEAR_TREE_START_RADIUS + Config.GEAR_TREE_STEP * float(tier - 1)


static func _add(id: String, pos: Vector2, kind: String) -> Dictionary:
	var n := {"id": id, "pos": pos, "kind": kind, "slot": "", "type": "", "item": "", "tier": 0, "links": []}
	_nodes[id] = n
	_order.append(id)
	return n


static func _link(a: String, b: String) -> void:
	(_nodes[a]["links"] as Array).append(b)
	(_nodes[b]["links"] as Array).append(a)


static func _build() -> void:
	_nodes = {}
	_order = []

	# The body.
	for slot: String in Config.GEAR_SLOTS:
		var n := _add(slot_id(slot), Config.GEAR_SLOT_POS[slot], "slot")
		n["slot"] = slot
		n["type"] = Config.GEAR_SLOT_TYPE[slot]
	for pair: Array in [["helmet", "chest"], ["chest", "amulet"], ["chest", "gloves"], ["chest", "belt"], ["belt", "pants"],
			["pants", "boots"], ["chest", "ring1"], ["ring1", "ring2"]]:
		_link(slot_id(pair[0]), slot_id(pair[1]))

	# One sector per kind of piece, clockwise from the top.
	var kinds: Array = Config.GEAR_TYPE_ORDER
	var slice := TAU / float(kinds.size())
	var fan := deg_to_rad(Config.GEAR_TREE_FAN_DEG)
	for k in kinds.size():
		var type := String(kinds[k])
		var angle := -PI * 0.5 + slice * float(k)
		var hub_id := "type.%s" % type
		var hub := _add(hub_id, Vector2.from_angle(angle) * Config.GEAR_TREE_HUB_RADIUS, "type")
		hub["type"] = type
		for slot: String in Config.GEAR_SLOTS:
			if String(Config.GEAR_SLOT_TYPE[slot]) == type:
				_link(slot_id(slot), hub_id)

		var pieces: Array[String] = []
		for item: String in Config.GEAR_ORDER:
			if String(Config.GEAR_ITEMS[item]["type"]) == type:
				pieces.append(item)
		for p in pieces.size():
			var item := pieces[p]
			var out := Vector2.from_angle(angle + fan * (float(p) - float(pieces.size() - 1) * 0.5))
			var last := hub_id
			for tier in range(1, Config.GEAR_TIERS.size() + 1):
				var id := item_id(item, tier)
				var n := _add(id, out * tier_radius(tier), "item")
				n["type"] = type
				n["item"] = item
				n["tier"] = tier
				_link(last, id)
				last = id
