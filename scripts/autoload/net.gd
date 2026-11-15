extends Node
## ============================================================================
##  ONLINE CO-OP: finding and connecting the players, and carrying messages
##  between their computers. Up to Config.COOP_MAX_PLAYERS play together.
##
##  One player HOSTS: their computer runs the zombies. The others JOIN by
##  typing the host's game code. Every player has a number, their "slot": the
##  host is 0, the joiners are 1 and 2. Joiners only ever talk to the host;
##  what one joiner needs to know about the other, the host passes on.
##
##  GETTING THROUGH HOME ROUTERS. A router lets nothing in from the internet
##  unless somebody inside spoke to that exact place first. So nobody can
##  simply "connect to the host". What the game does instead (the usual way
##  for games; it is called hole punching):
##    1. The host's game asks an address finder (scripts/net/stun.gd) how it
##       looks from the internet: an address and a door number. That, packed
##       into 12 letters, is the GAME CODE (make_code / read_code).
##    2. A joiner's game does the same for itself, then starts knocking at the
##       host's address. That alone gets through if the host's router is an
##       easy one (or its door was opened, see 4).
##    3. Otherwise the joiner's screen shows a REPLY CODE (the joiner's own
##       address). The joiner sends it to the host, the host types it in and
##       presses LET IN (let_in): now the host's game knocks at the joiner's
##       router too. Both routers have seen their own side speak first, so
##       both let the other side's knocking through, and the two are connected.
##    4. As before, the host's game also asks its router to open the door by
##       itself (UPnP). Most routers refuse, but where it works step 3 is
##       never needed.
##  A plain address still works as a code (192.168.0.12, or a name:port): for
##  players in the same house, a forwarded port, or a VPN.
##  What cannot work: a router that gives every conversation a new door
##  ("strict", `strict`), which some mobile and campus networks do. The screen
##  says so and suggests letting another player host.
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
## What a typed code turned out to be (read_code).
enum { CODE_BAD, CODE_GAME, CODE_REPLY, CODE_ADDRESS }

## The 32 signs a code is written with: no I, L, O or U (they look like 1, 1, 0 and V).
const CODE_SIGNS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

var role: int = Role.NONE
var slot := 0                           # my number in this game: 0 = the host, 1 and 2 = the joiners
var mates: Dictionary = {}              # slot -> what we know about that other player: name, level, worn gear, pet
var joined := false                     # (joiner) the host has let us in
var host_busy := false                  # (joiner) the host was in the middle of a run when we joined
var status := ""                        # one plain line for the co-op screen
var code := ""                          # (host) the game code friends type; (joiner) the code we are joining
var lan_code := ""                      # (host) what a friend in the same house can type instead
var reply_code := ""                    # (joiner) not in yet: the code to send back to the host
var finding := false                    # still asking how we look from the internet (no code to show yet)
var strict := false                     # our router gives every conversation a new door: friends may not get through
var door := 0                           # (host) the router's own door: 0 = not asked, 1 = asking, 2 = open, 3 = it said no
var online := true                      # ask the address finders (tests on one computer switch this off)
var use_upnp := true                    # ask the router to open its door (tests switch this off)
var stun_servers: Array = Config.NET_STUN_SERVERS   # (tests point this at their own)
var coop: Coop                          # the co-op part of the run being played (null between runs)

var _peer: ENetMultiplayerPeer
var _peers: Dictionary = {}             # (host) slot -> that joiner's connection number
var _connect_left := 0.0                # (joiner, plain address) seconds before giving up
var _upnp: UPNP
var _upnp_thread: Thread
var _stun: Stun                         # the question "how do I look from the internet?" while it is being asked
var _public_ip := ""                    # ...and the answer
var _public_port := 0
var _finder_ip := ""                    # (host) the finder that answered: small packets to it keep our door open
var _finder_port := 0
var _keep_left := 0.0
var _keep_id: PackedByteArray
var _punch: Dictionary = {}             # (host) "address:port" of a joiner's router -> seconds of knocking left
var _punch_left := 0.0
var _target_ip := ""                    # (joiner) where the host is
var _target_port := 0
var _local_port := 0                    # (joiner) the door on this computer all attempts leave through
var _join_left := 0.0                   # (joiner, game code) seconds of attempts left
var _round_left := 0.0                  # ...and of this attempt
var _rounds := 0
var _swapping := false                  # one attempt is being replaced by the next (not a lost connection)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_keep_id = Crypto.new().generate_random_bytes(12)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _stun != null:
		_stun.poll(delta)
		if _stun.done:
			_address_found()
	elif role == Role.HOST and _peer != null:
		_tick_host(delta)
	elif role == Role.CLIENT and _peer != null and not joined:
		_tick_joining(delta)


func _exit_tree() -> void:
	leave()


# ----------------------------------------------------------------------------
#  Game codes: an internet address and a door number as 12 signs, e.g.
#  K7QM-X2PD-9AB4. Two of the twelve signs are a check, so a typing mistake
#  is noticed at once instead of after a long wait. A reply code looks the same
#  but is marked as one, so the two cannot be mixed up.
# ----------------------------------------------------------------------------
func make_code(ip: String, port: int, kind: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4 or port < 1 or port > 65535:
		return ""
	var bytes: Array[int] = []
	for part: String in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return ""
		bytes.append(int(part))
	bytes.append(port >> 8)
	bytes.append(port & 255)
	var number := 0
	for b: int in bytes:
		number = (number << 8) | b
	number = (number << 8) | _code_check(bytes, kind)
	number = (number << 4) | (1 if kind == CODE_REPLY else 0)      # 60 bits = 12 signs of 5 bits
	var text := ""
	for i in 12:
		text = CODE_SIGNS[number & 31] + text
		number >>= 5
	return "%s-%s-%s" % [text.substr(0, 4), text.substr(4, 4), text.substr(8, 4)]


## What somebody typed -> {"kind": CODE_..., "ip", "port", "typo": true if it
## looks like a code with a mistake in it}.
func read_code(typed: String) -> Dictionary:
	var result := {"kind": CODE_BAD, "ip": "", "port": 0, "typo": false}
	var text := typed.strip_edges()
	if text == "":
		return result
	if text.contains(".") or text.contains(":") or text.to_lower() == "localhost":
		# A plain address, perhaps with a door number: 192.168.0.12 or 84.25.133.7:24565
		var where := text.to_lower()
		var door_number: int = Config.NET_PORT
		if where.count(":") == 1:
			door_number = int(where.get_slice(":", 1))
			where = where.get_slice(":", 0)
		if where == "" or where.contains(" ") or door_number < 1 or door_number > 65535:
			return result
		result["kind"] = CODE_ADDRESS
		result["ip"] = where
		result["port"] = door_number
		return result
	var number := 0
	var signs := 0
	for letter: String in text.to_upper():
		if letter == "-" or letter == " ":
			continue
		if letter == "O":
			letter = "0"
		elif letter == "I" or letter == "L":
			letter = "1"
		var value := CODE_SIGNS.find(letter)
		signs += 1
		if value < 0 or signs > 12:
			return result
		number = (number << 5) | value
	if signs != 12:
		result["typo"] = signs >= 8
		return result
	var mark := number & 15
	var check := (number >> 4) & 255
	var bytes: Array[int] = []
	for i in 6:
		bytes.append((number >> (52 - i * 8)) & 255)
	var kind := CODE_REPLY if mark == 1 else CODE_GAME
	var port := (bytes[4] << 8) | bytes[5]
	if mark > 1 or check != _code_check(bytes, kind) or port == 0:
		result["typo"] = true
		return result
	result["kind"] = kind
	result["ip"] = "%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]]
	result["port"] = port
	return result


func _code_check(bytes: Array[int], kind: int) -> int:
	var check := 0xA7 if kind == CODE_REPLY else 0x3C
	for b: int in bytes:
		check = ((check ^ b) * 167 + 13) & 255
	return check


# ----------------------------------------------------------------------------
#  Hosting
# ----------------------------------------------------------------------------
## Open a game on this computer for friends to join. False if it could not.
func host() -> bool:
	leave()
	role = Role.HOST
	slot = 0
	lan_code = _lan_address()
	status = "Waiting for your friends to join..."
	if online:
		# First ask how we look from the internet - through the very door the
		# game will use, so the question has to come before the game opens it.
		_stun = Stun.new()
		if _stun.start(Config.NET_PORT, stun_servers):
			finding = true
			changed.emit()
			return true
		_stun = null
		return _cannot_host()
	return _open_game()


func _open_game() -> bool:
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(Config.NET_PORT, Config.NET_MAX_CONNECTIONS) != OK:
		_peer = null
		return _cannot_host()
	multiplayer.multiplayer_peer = _peer
	if online and use_upnp:
		door = 1
		_upnp_thread = Thread.new()
		_upnp_thread.start(_open_door)
	changed.emit()
	return true


func _cannot_host() -> bool:
	_fail("Could not open a game on this computer. Is another copy of the game already hosting?")
	return false


## (host) A friend who cannot get in has sent their reply code: knock on their
## router from our side, so that ours lets their knocking through.
func let_in(typed: String) -> bool:
	if role != Role.HOST or _peer == null:
		return false
	var read := read_code(typed)
	if int(read["kind"]) != CODE_REPLY:
		status = "That is not a reply code. A friend who cannot get in sees one on their screen (12 letters and numbers)."
		if int(read["kind"]) == CODE_GAME:
			status = "That is a game code (maybe your own). The code to type here is the REPLY code on your friend's screen."
		elif bool(read["typo"]):
			status = "That reply code has a typing mistake in it. Check it against your friend's screen."
		changed.emit()
		return false
	_punch["%s:%d" % [read["ip"], read["port"]]] = Config.NET_PUNCH_TIME
	_punch_left = 0.0
	status = "Letting your friend in... they should appear here within a few seconds."
	changed.emit()
	return true


func _tick_host(delta: float) -> void:
	var enet := _peer.host
	if enet == null:
		return
	# A router closes a door nothing has gone through for a while: keep ours in use.
	if _finder_ip != "":
		_keep_left -= delta
		if _keep_left <= 0.0:
			_keep_left = Config.NET_KEEPALIVE
			enet.socket_send(_finder_ip, _finder_port, Stun.request(_keep_id))
	# Knock on the routers of the friends we are letting in. (One byte: their
	# game throws it away, it only has to pass through OUR router on its way out.)
	if _punch.is_empty():
		return
	_punch_left -= delta
	var knock := _punch_left <= 0.0
	if knock:
		_punch_left = Config.NET_PUNCH_INTERVAL
	for target: String in _punch.keys():
		_punch[target] = float(_punch[target]) - delta
		if float(_punch[target]) <= 0.0:
			_punch.erase(target)
		elif knock:
			enet.socket_send(target.get_slice(":", 0), int(target.get_slice(":", 1)), PackedByteArray([0]))


# ----------------------------------------------------------------------------
#  Joining
# ----------------------------------------------------------------------------
## Join the game with this code (or at this plain address).
func join(typed: String) -> bool:
	leave()
	var read := read_code(typed)
	var kind := int(read["kind"])
	if kind == CODE_BAD or kind == CODE_REPLY:
		if typed.strip_edges() == "":
			status = "Type the code your friend's game shows."
		elif kind == CODE_REPLY:
			status = "That is a REPLY code. It goes to the player who is hosting: they type it in and press LET IN."
		elif bool(read["typo"]):
			status = "That code has a typing mistake in it. Check it against your friend's screen."
		else:
			status = "\"%s\" is not a code this game understands. A code looks like K7QM-X2PD-9AB4" % typed.strip_edges()
		changed.emit()
		return false
	_target_ip = String(read["ip"])
	_target_port = int(read["port"])
	role = Role.CLIENT
	slot = 1
	code = typed.strip_edges().to_upper() if kind == CODE_GAME else typed.strip_edges()
	status = "Looking for the game..."
	if kind == CODE_ADDRESS:
		# A plain address (same house, a forwarded port): straight there.
		_peer = ENetMultiplayerPeer.new()
		if _peer.create_client(_target_ip, _target_port) != OK:
			_peer = null
			_fail("\"%s\" is not an address this game can reach." % code)
			return false
		multiplayer.multiplayer_peer = _peer
		_connect_left = Config.NET_CONNECT_TIMEOUT
		changed.emit()
		return true
	_join_left = Config.NET_JOIN_TIME
	if online:
		_stun = Stun.new()
		if _stun.start(0, stun_servers):
			finding = true
			changed.emit()
			return true
		_stun = null
	changed.emit()
	return _begin_round()


## One attempt: knock at the host's address from our door. (The connection
## itself knocks at 0, 0.5 and 1.5 seconds and then ever more slowly, so a
## fresh attempt every few seconds keeps the knocking brisk.)
func _begin_round() -> bool:
	_swapping = true
	if _peer != null:
		_peer.close()
	_peer = ENetMultiplayerPeer.new()
	var result := _peer.create_client(_target_ip, _target_port, 0, 0, 0, _local_port)
	if result != OK and _local_port != 0:
		_local_port = 0                   # (our door is taken? then any door - the reply code will not help any more)
		_public_ip = ""
		_peer = ENetMultiplayerPeer.new()
		result = _peer.create_client(_target_ip, _target_port)
	if result != OK:
		_peer = null
		_swapping = false
		_fail("Could not start looking for the game (%s)." % code)
		return false
	multiplayer.multiplayer_peer = _peer
	_swapping = false
	_round_left = Config.NET_JOIN_ROUND
	_rounds += 1
	return true


func _tick_joining(delta: float) -> void:
	if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return                            # (through: saying hello)
	if _connect_left > 0.0:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_fail("Nobody answered at %s. Check it, and that your friend's game says it is waiting." % code)
		return
	if _join_left <= 0.0:
		return
	_join_left -= delta
	_round_left -= delta
	if _join_left <= 0.0:
		_fail(_no_way_through())
	elif _round_left <= 0.0:
		if _rounds == 1 and _public_ip != "" and _public_ip != _target_ip:
			# Not through at the first knock: the host's router wants to hear
			# from the host first. Our address goes back to the host.
			reply_code = make_code(_public_ip, _public_port, CODE_REPLY)
			status = "ALMOST THERE.  Send this reply code to your host.  They type it in on this screen and press LET IN."
		_begin_round()
		changed.emit()


func _no_way_through() -> String:
	if _public_ip != "" and _public_ip == _target_ip:
		return "You and the host seem to be in the same house. Type the same-house code their screen shows instead (it looks like 192.168.0.12)."
	if _public_ip == "":
		return "Could not reach that game, and could not find out this computer's own internet address. Is the internet working?"
	var text := "Could not get through to that game. Check that your friend's game still shows that code and that they typed in your reply code."
	if strict:
		text += " Your internet connection is the strict kind that is hard to reach."
	return text + " If it keeps failing, let somebody else be the host."


## The address finder has answered (or stayed silent).
func _address_found() -> void:
	var found := _stun
	_stun = null
	found.stop()                          # (lets go of the door: the game's own connection takes it now)
	finding = false
	_public_ip = found.address
	_public_port = found.port
	strict = found.strict
	if role == Role.HOST:
		if _public_ip != "":
			code = make_code(_public_ip, _public_port, CODE_GAME)
			_finder_ip = found.finder_ip
			_finder_port = found.finder_port
			_keep_left = Config.NET_KEEPALIVE
		_open_game()
	elif role == Role.CLIENT:
		_local_port = found.local_port
		if _public_ip == "" or _public_ip == _target_ip:
			_join_left = minf(_join_left, Config.NET_JOIN_ROUND * 4.0)   # (no reply code to wait for)
		_begin_round()
		changed.emit()


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
	if _stun != null:
		_stun.stop()
		_stun = null
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null and door == 2:
		_upnp.delete_port_mapping(Config.NET_PORT, "UDP")
	_upnp = null
	_swapping = true
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_swapping = false
	role = Role.NONE
	slot = 0
	joined = false
	host_busy = false
	mates = {}
	_peers = {}
	code = ""
	lan_code = ""
	reply_code = ""
	finding = false
	strict = false
	door = 0
	_connect_left = 0.0
	_public_ip = ""
	_public_port = 0
	_finder_ip = ""
	_punch = {}
	_target_ip = ""
	_local_port = 0
	_join_left = 0.0
	_rounds = 0


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
#  The door in the router (runs in the background: asking can take seconds).
#  Where a router agrees, friends get in at the first knock.
# ----------------------------------------------------------------------------
func _open_door() -> void:
	var router := UPNP.new()
	var address := ""
	if router.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
			and router.get_gateway() != null and router.get_gateway().is_valid_gateway():
		if router.add_port_mapping(Config.NET_PORT, Config.NET_PORT, "Haitian Gang Wars", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			address = router.query_external_address()
	_door_answer.call_deferred(router, address)


func _door_answer(router: UPNP, address: String) -> void:
	if role != Role.HOST:
		return
	_upnp = router
	if address != "":
		door = 2
		if code == "":
			# (the address finders stayed silent: the router's word will do)
			code = make_code(address, Config.NET_PORT, CODE_GAME)
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
	_join_left = 0.0
	reply_code = ""
	status = "Found the game. Saying hello..."
	_hello.rpc_id(1, my_info())
	changed.emit()


func _on_connection_failed() -> void:
	if _swapping or role != Role.CLIENT or _join_left > 0.0:
		return                            # (one attempt with a game code ending: the next one follows)
	_fail("Could not reach a game at %s. Check it, and that your friend's game says it is waiting." % code)


func _on_server_disconnected() -> void:
	if _swapping or role != Role.CLIENT:
		return
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
