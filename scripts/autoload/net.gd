extends Node
## ============================================================================
##  ONLINE CO-OP: finding and connecting the players, and carrying messages
##  between their computers. Up to Config.COOP_MAX_PLAYERS play together.
##
##  One player HOSTS: their computer opens a door (Config.NET_PORT) and runs
##  the zombies. The others JOIN by typing the host's code (its internet
##  address). Every player has a number, their "slot": the host is 0, the
##  joiners are 1 and 2. Joiners only ever talk to the host; what one joiner
##  needs to know about the other, the host passes on.
##
##  Getting through the host's router: most home routers let a program ask
##  for a door to be opened ("UPnP"). host() tries that in the background; if
##  the router refuses, players in the same house can still join with the
##  local code, and for players elsewhere the host has to forward the port in
##  the router by hand.
##
##  What is sent during a run is decided by scripts/game/coop.gd; this file
##  only delivers it:
##     send_events(to, list)        things that must arrive (kills, pickups...)
##     send_state(to, who, array)   where player `who` is right now
##     send_snapshot(to, bytes)     (host) where every zombie is right now
## ============================================================================

signal changed                          ## something the co-op screen shows has changed
signal run_started(settings: Dictionary)   ## (joiner) the host has started a run
signal mate_left(slot: int)             ## a player is gone (left, or the connection broke); -1 = the host, and with it everybody

enum Role { NONE, HOST, CLIENT }

var role: int = Role.NONE
var slot := 0                           # my number in this game: 0 = the host, 1 and 2 = the joiners
var mates: Dictionary = {}              # slot -> what we know about that other player: name, level, worn gear, pet
var joined := false                     # (joiner) the host has let us in
var host_busy := false                  # (joiner) the host was in the middle of a run when we joined
var status := ""                        # one plain line for the co-op screen
var code := ""                          # (host) what a friend anywhere types to join
var lan_code := ""                      # (host) ...and what a friend in the same house types
var door := 0                           # (host) 0 = not asked yet, 1 = asking the router, 2 = open, 3 = the router said no
var use_upnp := true                    # (tests switch this off)
var coop: Coop                          # the co-op part of the run being played (null between runs)

var _peer: ENetMultiplayerPeer
var _peers: Dictionary = {}             # (host) slot -> that joiner's connection number
var _connect_left := 0.0
var _upnp: UPNP
var _upnp_thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if role == Role.CLIENT and not joined and _connect_left > 0.0:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_fail("Nobody answered at %s. Check the code, and that your friend's game says it is waiting." % code)


func _exit_tree() -> void:
	leave()


# ----------------------------------------------------------------------------
#  Hosting and joining
# ----------------------------------------------------------------------------
## Open a game on this computer for friends to join. False if it could not.
func host() -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(Config.NET_PORT, Config.COOP_MAX_PLAYERS - 1) != OK:
		_peer = null
		status = "Could not open a game on this computer. Is another copy of the game already hosting?"
		changed.emit()
		return false
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	slot = 0
	lan_code = _lan_address()
	code = ""
	status = "Waiting for your friends to join..."
	door = 0
	if use_upnp:
		door = 1
		_upnp_thread = Thread.new()
		_upnp_thread.start(_open_door)
	changed.emit()
	return true


## Join the game hosted at `address` (the host's code).
func join(address: String) -> bool:
	leave()
	address = address.strip_edges()
	if address == "":
		status = "Type the code your friend's game shows."
		changed.emit()
		return false
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(address, Config.NET_PORT) != OK:
		_peer = null
		status = "\"%s\" is not a code this game understands. It looks like 84.25.133.7" % address
		changed.emit()
		return false
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	code = address
	_connect_left = Config.NET_CONNECT_TIMEOUT
	slot = 1
	status = "Looking for the game at %s ..." % address
	changed.emit()
	return true


## Stop hosting / leave the game we joined.
func leave() -> void:
	if role == Role.NONE:
		return
	if _peer != null:
		if role == Role.HOST:
			for other: int in _peers.keys():
				_bye.rpc_id(int(_peers[other]))
		elif joined:
			_bye.rpc_id(1)
		_peer.poll()                      # (push the goodbye out before the door closes)
	_close()
	status = ""
	changed.emit()


func _close() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null and door == 2:
		_upnp.delete_port_mapping(Config.NET_PORT, "UDP")
	_upnp = null
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	slot = 0
	joined = false
	host_busy = false
	mates = {}
	_peers = {}
	code = ""
	lan_code = ""
	door = 0
	_connect_left = 0.0


func _fail(reason: String) -> void:
	_close()
	status = reason
	changed.emit()


## True while at least one other player is in the game with us.
func playing_together() -> bool:
	return role != Role.NONE and not mates.is_empty()


func is_host() -> bool:
	return role == Role.HOST


## The others' names in one piece: "T", "T and SAM".
func mate_names() -> String:
	var names: Array[String] = []
	for other: int in mates.keys():
		names.append(String(mates[other].get("name", "FRIEND")))
	return " and ".join(names) if not names.is_empty() else "your friends"


func name_of(player: int) -> String:
	if player == slot:
		return String(SaveData.get_setting("player_name"))
	return String(mates[player].get("name", "FRIEND")) if mates.has(player) else "FRIEND"


## What the other players need to know about me.
func my_info() -> Dictionary:
	return {"v": Config.GAME_VERSION, "name": String(SaveData.get_setting("player_name")), "level": SaveData.level,
			"worn": SaveData.gear_worn.duplicate(), "pet": SaveData.pet_active}


# ----------------------------------------------------------------------------
#  The door in the router (runs in the background: asking can take seconds)
# ----------------------------------------------------------------------------
func _open_door() -> void:
	var router := UPNP.new()
	var address := ""
	if router.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
			and router.get_gateway() != null and router.get_gateway().is_valid_gateway():
		if router.add_port_mapping(Config.NET_PORT, Config.NET_PORT, "Rot Riot", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			address = router.query_external_address()
	_door_answer.call_deferred(router, address)


func _door_answer(router: UPNP, address: String) -> void:
	if role != Role.HOST:
		return
	_upnp = router
	if address != "":
		door = 2
		code = address
	else:
		door = 3
	changed.emit()


## This computer's address inside the house.
func _lan_address() -> String:
	for address: String in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var second := int(address.get_slice(".", 1))
			if second >= 16 and second <= 31:
				return address
	return ""


# ----------------------------------------------------------------------------
#  Connection events
# ----------------------------------------------------------------------------
func _on_connected_to_server() -> void:
	_connect_left = 0.0
	status = "Found the game. Saying hello..."
	_hello.rpc_id(1, my_info())
	changed.emit()


func _on_connection_failed() -> void:
	_fail("Could not reach a game at %s. Check the code, and that your friend's game says it is waiting." % code)


func _on_server_disconnected() -> void:
	var who := name_of(0)
	_close()
	status = "%s has closed the game." % who
	mate_left.emit(-1)
	changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST:
		return
	for other: int in _peers.keys():
		if int(_peers[other]) == id:
			var who := name_of(other)
			_peers.erase(other)
			mates.erase(other)
			status = "%s has left." % who
			_send_roster()
			mate_left.emit(other)
			changed.emit()
			return


# ----------------------------------------------------------------------------
#  Saying hello
# ----------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _hello(info: Dictionary) -> void:
	if role != Role.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peers.values().has(id):
		return
	if _peers.size() >= Config.COOP_MAX_PLAYERS - 1:
		_refuse.rpc_id(id, "That game is full (%d players)." % Config.COOP_MAX_PLAYERS)
		return
	if String(info.get("v", "")) != Config.GAME_VERSION:
		_refuse.rpc_id(id, "You have different versions of the game: the host has v%s, you have v%s. Everybody needs the newest one." % [
				Config.GAME_VERSION, String(info.get("v", "?"))])
		return
	var free := 1
	while _peers.has(free):
		free += 1
	_peers[free] = id
	mates[free] = _clean_info(info)
	status = "%s has joined." % name_of(free)
	_welcome.rpc_id(id, free, coop != null and is_instance_valid(coop))
	_send_roster()
	changed.emit()


## (host) Tell every joiner who is in the game.
func _send_roster() -> void:
	var everyone := {0: my_info()}
	for other: int in mates.keys():
		everyone[other] = mates[other]
	for other: int in _peers.keys():
		_roster.rpc_id(int(_peers[other]), everyone)


@rpc("any_peer", "call_remote", "reliable")
func _welcome(my_slot: int, busy: bool) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	slot = clampi(my_slot, 1, Config.COOP_MAX_PLAYERS - 1)
	joined = true
	host_busy = busy
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _roster(everyone: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	var before := mates.keys()
	mates = {}
	for key: Variant in everyone.keys():
		var other := int(key)
		if other != slot and other >= 0 and other < Config.COOP_MAX_PLAYERS and typeof(everyone[key]) == TYPE_DICTIONARY:
			mates[other] = _clean_info(everyone[key])
	status = "You are in %s's game%s. The host chooses the map and starts." % [name_of(0),
			"" if mates.size() <= 1 else " with " + " and ".join(_names_without_host())]
	# Somebody who was here is not any more.
	for other: int in before:
		if not mates.has(other):
			mate_left.emit(other)
	changed.emit()


func _names_without_host() -> Array[String]:
	var names: Array[String] = []
	for other: int in mates.keys():
		if other != 0:
			names.append(name_of(other))
	return names


@rpc("any_peer", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	_fail(reason)


@rpc("any_peer", "call_remote", "reliable")
func _bye() -> void:
	var id := multiplayer.get_remote_sender_id()
	if role == Role.CLIENT and id == 1:
		_on_server_disconnected()
	elif role == Role.HOST:
		_on_peer_disconnected(id)


## Never trust what comes down the wire: keep only what we understand.
func _clean_info(info: Dictionary) -> Dictionary:
	var clean := {"name": "FRIEND", "level": 1, "worn": {}, "pet": ""}
	var shown := String(info.get("name", "")).strip_edges().substr(0, Config.COOP_NAME_MAX)
	if shown != "":
		clean["name"] = shown.to_upper()
	clean["level"] = clampi(int(info.get("level", 1)), 1, Config.LEVEL_CAP)
	var worn: Variant = info.get("worn", {})
	if typeof(worn) == TYPE_DICTIONARY:
		for gear_slot: Variant in (worn as Dictionary).keys():
			var key := String((worn as Dictionary)[gear_slot])
			if Config.GEAR_SLOTS.has(String(gear_slot)) and Config.GEAR_ITEMS.has(Config.gear_item_of(key)):
				(clean["worn"] as Dictionary)[String(gear_slot)] = key
	var pet := String(info.get("pet", ""))
	if Config.PETS.has(pet):
		clean["pet"] = pet
	return clean


# ----------------------------------------------------------------------------
#  Starting a run (the host decides)
# ----------------------------------------------------------------------------
## (host) Tell the other players that a run is starting, with everything all
## computers must agree on: the map, the wave, where the rocks and chests are,
## and who is in it.
func announce_run(settings: Dictionary) -> void:
	if role != Role.HOST:
		return
	for other: int in _peers.keys():
		_start.rpc_id(int(_peers[other]), settings)


@rpc("any_peer", "call_remote", "reliable")
func _start(settings: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	host_busy = false
	run_started.emit(settings)


# ----------------------------------------------------------------------------
#  During a run. `to` is the slot of the player the message is for (a joiner
#  can only send to 0, the host).
# ----------------------------------------------------------------------------
func _peer_of(to: int) -> int:
	if role == Role.HOST:
		return int(_peers.get(to, 0))
	return 1 if role == Role.CLIENT and joined and to == 0 else 0


## (host) Which player a message came from (-1 = nobody we know).
func _slot_of_sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	if role == Role.CLIENT:
		return 0 if id == 1 else -1
	for other: int in _peers.keys():
		if int(_peers[other]) == id:
			return other
	return -1


func send_events(to: int, list: Array) -> void:
	var id := _peer_of(to)
	if id != 0:
		_events.rpc_id(id, list)


func send_state(to: int, who: int, state: Array) -> void:
	var id := _peer_of(to)
	if id != 0:
		_state.rpc_id(id, who, state)


func send_snapshot(to: int, bytes: PackedByteArray) -> void:
	var id := _peer_of(to)
	if id != 0:
		_snapshot.rpc_id(id, bytes)


@rpc("any_peer", "call_remote", "reliable")
func _events(list: Array) -> void:
	var from := _slot_of_sender()
	if from >= 0 and coop != null and is_instance_valid(coop):
		coop.receive_events(list, from)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _state(who: int, state: Array) -> void:
	var from := _slot_of_sender()
	if from < 0 or coop == null or not is_instance_valid(coop):
		return
	# A joiner can only speak for itself; the host passes the others' on.
	coop.receive_state(from if role == Role.HOST else who, state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	if role == Role.CLIENT and _slot_of_sender() == 0 and coop != null and is_instance_valid(coop):
		coop.receive_snapshot(bytes)
