class_name Stun
extends RefCounted
## Finds out how this computer looks from the internet.
##
## A home router gives everything that leaves the house one shared internet
## address, and a door number (port) of its choosing. A game cannot see that
## from the inside, so it asks an "address finder" - a public server that
## answers "your message came from address A, door P". (The standard is called
## STUN, RFC 5389; this is the one question of it that we need.)
##
## The question must leave through the SAME door the game will use afterwards,
## so the order is: start(port) -> poll() until `done` -> stop() -> only then
## open the game's own connection on `local_port`.
##
## Two finders are asked. If they see two different doors, the router gives
## every conversation a new one ("strict"), and friends will probably not get
## through to this computer.

const MAGIC := 0x2112A442               # fixed number every STUN message carries

var done := false
var address := ""                       # our internet address ("" = nobody answered)
var port := 0                           # ...and the door the router gave us
var strict := false                     # two finders saw two different doors
var local_port := 0                     # the door on this computer the question left through
var finder_ip := ""                     # a finder that answered (the host keeps its router's door open through it)
var finder_port := 0

var _udp: PacketPeerUDP
var _servers: Array = []                # each: {"host", "port", "ip", "query" (-1 = none), "answer": [ip, port] or []}
var _id: PackedByteArray
var _time := 0.0
var _resend := 0.0
var _first_answer := -1.0


## Begin asking. `bind_port` 0 = any free door. False if that door is taken.
func start(bind_port: int, servers: Array) -> bool:
	_udp = PacketPeerUDP.new()
	if _udp.bind(bind_port, "0.0.0.0") != OK:
		_udp = null
		done = true
		return false
	local_port = _udp.get_local_port()
	_id = Crypto.new().generate_random_bytes(12)
	for entry: Variant in servers:
		var text := String(entry)
		var server := {"host": text.get_slice(":", 0), "port": int(text.get_slice(":", 1)) if text.contains(":") else 3478,
				"ip": "", "query": -1, "answer": []}
		if String(server["host"]).is_valid_ip_address():
			server["ip"] = server["host"]
		else:
			# (looking a name up can take seconds: let it run in the background)
			server["query"] = IP.resolve_hostname_queue_item(String(server["host"]), IP.TYPE_IPV4)
		_servers.append(server)
	if _servers.is_empty():
		_finish()
	return true


## Call every frame until `done`.
func poll(delta: float) -> void:
	if done or _udp == null:
		return
	_time += delta
	_resend -= delta
	var ask := _resend <= 0.0
	if ask:
		_resend = Config.NET_STUN_RESEND
	for server: Dictionary in _servers:
		if String(server["ip"]) == "" and int(server["query"]) >= 0:
			var state := IP.get_resolve_item_status(int(server["query"]))
			if state == IP.RESOLVER_STATUS_DONE:
				server["ip"] = IP.get_resolve_item_address(int(server["query"]))
			if state != IP.RESOLVER_STATUS_WAITING:
				IP.erase_resolve_item(int(server["query"]))
				server["query"] = -1
		if ask and String(server["ip"]) != "" and (server["answer"] as Array).is_empty():
			_udp.set_dest_address(String(server["ip"]), int(server["port"]))
			_udp.put_packet(request(_id))
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var seen := parse(packet, _id)
		if seen.is_empty():
			continue
		for server: Dictionary in _servers:
			if String(server["ip"]) == from_ip and int(server["port"]) == from_port and (server["answer"] as Array).is_empty():
				server["answer"] = seen
				if _first_answer < 0.0:
					_first_answer = _time
	# Enough? Two answers; or one answer and the second finder stays silent;
	# or nobody answers at all.
	var answers := 0
	for server: Dictionary in _servers:
		if not (server["answer"] as Array).is_empty():
			answers += 1
	if answers >= mini(2, _servers.size()) or (answers >= 1 and _time - _first_answer > 1.0) or _time >= Config.NET_STUN_TIMEOUT:
		_finish()


## Let go of the door, so the game's own connection can use it.
func stop() -> void:
	for server: Dictionary in _servers:
		if int(server["query"]) >= 0:
			IP.erase_resolve_item(int(server["query"]))
			server["query"] = -1
	if _udp != null:
		_udp.close()
	_udp = null
	done = true


func _finish() -> void:
	done = true
	for server: Dictionary in _servers:
		var seen: Array = server["answer"]
		if seen.is_empty():
			continue
		if address == "":
			address = String(seen[0])
			port = int(seen[1])
			finder_ip = String(server["ip"])
			finder_port = int(server["port"])
		elif String(seen[0]) != address or int(seen[1]) != port:
			strict = true


## The question: "what address did this come from?" (20 bytes)
static func request(id: PackedByteArray) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(8)
	packet.encode_u16(0, 0x0100)          # (message type 0x0001 "binding request"; network byte order = bytes swapped)
	packet.encode_u16(2, 0)               # no extra fields
	packet[4] = 0x21
	packet[5] = 0x12
	packet[6] = 0xA4
	packet[7] = 0x42
	packet.append_array(id)
	return packet


## The answer: [address, port], or [] if `packet` is not an answer to question `id`.
static func parse(packet: PackedByteArray, id: PackedByteArray) -> Array:
	if packet.size() < 20 or id.size() != 12:
		return []
	if packet[0] != 0x01 or packet[1] != 0x01:      # "binding success"
		return []
	if _u32(packet, 4) != MAGIC or packet.slice(8, 20) != id:
		return []
	var end := mini(20 + _u16(packet, 2), packet.size())
	var at := 20
	var plain: Array = []
	while at + 4 <= end:
		var kind := _u16(packet, at)
		var length := _u16(packet, at + 2)
		var value := at + 4
		if value + length > end:
			break
		if length >= 8 and packet[value + 1] == 0x01:       # (0x01 = an IPv4 address)
			if kind == 0x0020:
				# XOR-MAPPED-ADDRESS: scrambled with the magic number, so that
				# routers which rewrite addresses inside packets leave it alone.
				var door := _u16(packet, value + 2) ^ (MAGIC >> 16)
				var number := _u32(packet, value + 4) ^ MAGIC
				return [_dotted(number), door]
			elif kind == 0x0001:
				# MAPPED-ADDRESS: the plain form old servers send.
				plain = [_dotted(_u32(packet, value + 4)), _u16(packet, value + 2)]
		at = value + ((length + 3) & ~3)                    # (fields are padded to 4 bytes)
	return plain


static func _u16(packet: PackedByteArray, at: int) -> int:
	return (packet[at] << 8) | packet[at + 1]


static func _u32(packet: PackedByteArray, at: int) -> int:
	return (packet[at] << 24) | (packet[at + 1] << 16) | (packet[at + 2] << 8) | packet[at + 3]


static func _dotted(number: int) -> String:
	return "%d.%d.%d.%d" % [(number >> 24) & 255, (number >> 16) & 255, (number >> 8) & 255, number & 255]
