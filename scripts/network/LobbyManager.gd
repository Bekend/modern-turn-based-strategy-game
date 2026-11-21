class_name LobbyManager
extends Node

## Manages local WiFi (LAN) lobby discovery via UDP beacons
## and connection staging via ENetMultiplayerPeer.

signal lobbies_updated(lobbies: Array)
signal lobby_joined(lobby_data: Dictionary)
signal lobby_join_failed(reason: String)
signal player_list_updated(players: Array)
signal game_start_received(config: Dictionary)

const BROADCAST_PORT: int = 24567
const DEFAULT_GAME_PORT: int = 24568
const BEACON_INTERVAL: float = 1.0
const LOBBY_TIMEOUT: float = 3.5

# UDP Discovery
var _udp_peer: PacketPeerUDP
var _beacon_timer: float = 0.0
var _cleanup_timer: float = 0.0
var _is_discovering: bool = false

# Current State
var is_hosting: bool = false
var is_in_lobby: bool = false
var current_lobby_info: Dictionary = {}
var discovered_lobbies: Dictionary = {} # ip -> { 'info': Dictionary, 'last_seen': float }
var connected_players: Array = [] # Array of player dicts

# Multiplayer Peer
var _enet_peer: ENetMultiplayerPeer

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if is_hosting:
		_beacon_timer += delta
		if _beacon_timer >= BEACON_INTERVAL:
			_beacon_timer = 0.0
			_broadcast_beacon()

	if _is_discovering:
		_poll_incoming_beacons()
		_cleanup_timer += delta
		if _cleanup_timer >= 1.0:
			_cleanup_timer = 0.0
			_prune_stale_lobbies()

# -------------------------------------------------------------
# DISCOVERY (CLIENT & LISTENER)
# -------------------------------------------------------------

func start_discovery() -> void:
	discovered_lobbies.clear()
	_is_discovering = true
	if not _udp_peer:
		_udp_peer = PacketPeerUDP.new()
		_udp_peer.bind(BROADCAST_PORT)
	lobbies_updated.emit([])

func stop_discovery() -> void:
	_is_discovering = false
	if _udp_peer and not is_hosting:
		_udp_peer.close()
		_udp_peer = null

func _poll_incoming_beacons() -> void:
	if not _udp_peer or not _udp_peer.is_bound():
		return

	while _udp_peer.get_available_packet_count() > 0:
		var packet = _udp_peer.get_packet()
		var sender_ip = _udp_peer.get_packet_ip()
		var text = packet.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary and parsed.get('type', '') == 'retro4x_beacon':
			parsed['ip'] = sender_ip
			var now = Time.get_ticks_msec() / 1000.0
			discovered_lobbies[sender_ip] = {
				'info': parsed,
				'last_seen': now
			}
			_emit_discovered_list()

func _prune_stale_lobbies() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var changed = false
	var keys_to_remove: Array = []
	for ip in discovered_lobbies.keys():
		if now - discovered_lobbies[ip]['last_seen'] > LOBBY_TIMEOUT:
			keys_to_remove.append(ip)
			changed = true

	for ip in keys_to_remove:
		discovered_lobbies.erase(ip)

	if changed:
		_emit_discovered_list()

func _emit_discovered_list() -> void:
	var list: Array = []
	for item in discovered_lobbies.values():
		list.append(item['info'])
	lobbies_updated.emit(list)

# -------------------------------------------------------------
# HOSTING A LOBBY
# -------------------------------------------------------------

func create_lobby(lobby_name: String, password: String, player_limit: int, ai_count: int, map_size_index: int) -> bool:
	leave_lobby()

	_enet_peer = ENetMultiplayerPeer.new()
	var err = _enet_peer.create_server(DEFAULT_GAME_PORT, player_limit)
	if err != OK:
		push_error('Failed to start ENet server on port %d: %d' % [DEFAULT_GAME_PORT, err])
		return false

	multiplayer.multiplayer_peer = _enet_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_hosting = true
	is_in_lobby = true

	var cfg = Engine.get_main_loop().root.get_node_or_null('/root/GameConfig')
	var map_label = cfg.MAP_SIZES[map_size_index][2] if cfg else 'Standard'

	current_lobby_info = {
		'name': lobby_name,
		'password': password,
		'has_password': password != '',
		'player_limit': player_limit,
		'ai_count': ai_count,
		'map_size_index': map_size_index,
		'map_label': map_label,
		'port': DEFAULT_GAME_PORT
	}

	# Host is Player 1 (Solaris Dominion)
	connected_players = [{
		'peer_id': 1,
		'name': 'Host (You)',
		'faction_id': 0,
		'is_ready': true
	}]

	# Setup UDP broadcast socket
	if not _udp_peer:
		_udp_peer = PacketPeerUDP.new()
	_udp_peer.set_broadcast_enabled(true)
	_udp_peer.set_dest_address('255.255.255.255', BROADCAST_PORT)

	player_list_updated.emit(connected_players)
	lobby_joined.emit(current_lobby_info)
	return true

func _broadcast_beacon() -> void:
	if not _udp_peer:
		return
	var beacon = {
		'type': 'retro4x_beacon',
		'name': current_lobby_info.get('name', 'LAN Lobby'),
		'has_password': current_lobby_info.get('has_password', false),
		'player_count': connected_players.size(),
		'player_limit': current_lobby_info.get('player_limit', 4),
		'ai_count': current_lobby_info.get('ai_count', 2),
		'map_size_index': current_lobby_info.get('map_size_index', 1),
		'map_label': current_lobby_info.get('map_label', 'Standard'),
		'port': DEFAULT_GAME_PORT
	}
	var msg = JSON.stringify(beacon).to_utf8_buffer()
	_udp_peer.put_packet(msg)

# -------------------------------------------------------------
# JOINING A LOBBY
# -------------------------------------------------------------

func join_lobby(ip: String, password: String = '') -> void:
	join_direct(ip, DEFAULT_GAME_PORT, password)

func join_direct(ip: String, port: int, password: String = '') -> void:
	leave_lobby()

	_enet_peer = ENetMultiplayerPeer.new()
	var err = _enet_peer.create_client(ip, port)
	if err != OK:
		lobby_join_failed.emit('Could not connect to host at %s:%d' % [ip, port])
		return

	multiplayer.multiplayer_peer = _enet_peer
	multiplayer.connected_to_server.connect(func():
		_send_join_request.rpc_id(1, password)
	)
	multiplayer.connection_failed.connect(func():
		lobby_join_failed.emit('Connection failed.')
		leave_lobby()
	)
	multiplayer.server_disconnected.connect(func():
		lobby_join_failed.emit('Host closed the lobby.')
		leave_lobby()
	)

	is_hosting = false
	is_in_lobby = true

# -------------------------------------------------------------
# RPC HANDLERS
# -------------------------------------------------------------

@rpc('any_peer', 'call_remote', 'reliable')
func _send_join_request(password_attempt: String) -> void:
	if not is_hosting:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if current_lobby_info.get('has_password', false):
		if password_attempt != current_lobby_info.get('password', ''):
			_receive_join_response.rpc_id(sender_id, false, 'Incorrect password', {})
			return

	if connected_players.size() >= current_lobby_info.get('player_limit', 4):
		_receive_join_response.rpc_id(sender_id, false, 'Lobby is full', {})
		return

	var assigned_faction = connected_players.size()
	var new_player = {
		'peer_id': sender_id,
		'name': 'Player %d' % (connected_players.size() + 1),
		'faction_id': assigned_faction,
		'is_ready': true
	}
	connected_players.append(new_player)

	_receive_join_response.rpc_id(sender_id, true, '', current_lobby_info)
	_sync_player_list.rpc(connected_players)
	player_list_updated.emit(connected_players)

@rpc('authority', 'call_remote', 'reliable')
func _receive_join_response(success: bool, error_reason: String, lobby_info: Dictionary) -> void:
	if success:
		current_lobby_info = lobby_info
		lobby_joined.emit(lobby_info)
	else:
		lobby_join_failed.emit(error_reason)
		leave_lobby()

@rpc('authority', 'call_remote', 'reliable')
func _sync_player_list(players: Array) -> void:
	connected_players = players
	player_list_updated.emit(connected_players)

@rpc('authority', 'call_remote', 'reliable')
func _receive_game_start(config: Dictionary) -> void:
	var cfg = Engine.get_main_loop().root.get_node_or_null('/root/GameConfig')
	if cfg:
		cfg.is_multiplayer = true
		cfg.is_host = false
		cfg.map_size_index = int(config.get('map_size_index', 1))
		cfg.ai_count = int(config.get('ai_count', 0))
		cfg.multiplayer_seed = int(config.get('seed', 1337))
		for p in connected_players:
			if p['peer_id'] == multiplayer.get_unique_id():
				cfg.local_player_faction_id = p['faction_id']
	game_start_received.emit(config)

func start_game() -> void:
	if not is_hosting:
		return
	var match_seed = int(Time.get_unix_time_from_system()) % 100000
	var config = {
		'map_size_index': current_lobby_info.get('map_size_index', 1),
		'ai_count': current_lobby_info.get('ai_count', 2),
		'seed': match_seed
	}

	var cfg = Engine.get_main_loop().root.get_node_or_null('/root/GameConfig')
	if cfg:
		cfg.is_multiplayer = true
		cfg.is_host = true
		cfg.map_size_index = config['map_size_index']
		cfg.ai_count = config['ai_count']
		cfg.multiplayer_seed = match_seed
		cfg.local_player_faction_id = 0

	_receive_game_start.rpc(config)
	game_start_received.emit(config)

# -------------------------------------------------------------
# CLEANUP
# -------------------------------------------------------------

func leave_lobby() -> void:
	if _enet_peer:
		_enet_peer.close()
		_enet_peer = null
	if multiplayer:
		multiplayer.multiplayer_peer = null

	is_hosting = false
	is_in_lobby = false
	current_lobby_info.clear()
	connected_players.clear()

	if _udp_peer:
		_udp_peer.close()
		_udp_peer = null

func _exit_tree() -> void:
	stop_discovery()
	leave_lobby()
	if _udp_peer:
		_udp_peer.close()
		_udp_peer = null

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if is_hosting:
		var idx = -1
		for i in range(connected_players.size()):
			if connected_players[i]['peer_id'] == id:
				idx = i
				break
		if idx != -1:
			connected_players.remove_at(idx)
			_sync_player_list.rpc(connected_players)
			player_list_updated.emit(connected_players)
