extends CanvasLayer

## Main menu scene controller with Local Multiplayer (WiFi LAN),
## Audio Settings persistence, Online Multiplayer placeholder, and up to 6 AI opponents.

@onready var map_size_label: Label  = $Panel/VBox/MapSection/MapSizeLabel
@onready var map_slider: HSlider    = $Panel/VBox/MapSection/MapSlider
@onready var ai_count_label: Label  = $Panel/VBox/AISection/AICountLabel
@onready var ai_less_btn: Button    = $Panel/VBox/AISection/AILessBtn
@onready var ai_more_btn: Button    = $Panel/VBox/AISection/AIMoreBtn
@onready var continue_btn: Button   = $Panel/VBox/Buttons/ContinueBtn
@onready var new_game_btn: Button   = $Panel/VBox/Buttons/NewGameBtn
@onready var local_mp_btn: Button   = $Panel/VBox/Buttons/LocalMultiplayerBtn
@onready var online_mp_btn: Button  = $Panel/VBox/Buttons/OnlineMultiplayerBtn
@onready var settings_btn: Button   = $Panel/VBox/Buttons/SettingsBtn

# Settings Modal
@onready var settings_modal: PanelContainer = $SettingsModal
@onready var sfx_toggle_btn: Button          = $SettingsModal/VBox/SFXBtn
@onready var music_toggle_btn: Button        = $SettingsModal/VBox/MusicBtn
@onready var settings_close_btn: Button      = $SettingsModal/VBox/CloseBtn

# Online Modal
@onready var online_modal: PanelContainer    = $OnlineModal
@onready var online_close_btn: Button        = $OnlineModal/VBox/CloseBtn

# Multiplayer Modal
@onready var mp_modal: PanelContainer        = $MultiplayerModal
@onready var mp_close_btn: Button            = $MultiplayerModal/VBox/Header/CloseBtn
@onready var tab_browse_btn: Button          = $MultiplayerModal/VBox/Tabs/BrowseTabBtn
@onready var tab_host_btn: Button            = $MultiplayerModal/VBox/Tabs/HostTabBtn
@onready var browse_view: VBoxContainer      = $MultiplayerModal/VBox/Views/BrowseView
@onready var host_view: VBoxContainer        = $MultiplayerModal/VBox/Views/HostView
@onready var room_view: VBoxContainer        = $MultiplayerModal/VBox/Views/RoomView
@onready var lobby_list_container: VBoxContainer = $MultiplayerModal/VBox/Views/BrowseView/Scroll/LobbyList
@onready var refresh_btn: Button             = $MultiplayerModal/VBox/Views/BrowseView/RefreshBtn
@onready var direct_ip_input: LineEdit       = $MultiplayerModal/VBox/Views/BrowseView/DirectBox/IPInput
@onready var direct_port_input: LineEdit     = $MultiplayerModal/VBox/Views/BrowseView/DirectBox/PortInput
@onready var direct_pass_input: LineEdit     = $MultiplayerModal/VBox/Views/BrowseView/DirectBox/PassInput
@onready var direct_connect_btn: Button      = $MultiplayerModal/VBox/Views/BrowseView/DirectBox/ConnectBtn
@onready var host_name_input: LineEdit       = $MultiplayerModal/VBox/Views/HostView/NameBox/NameInput
@onready var host_pass_input: LineEdit       = $MultiplayerModal/VBox/Views/HostView/PassBox/PassInput
@onready var host_p_less: Button             = $MultiplayerModal/VBox/Views/HostView/PlayerLimitBox/LessBtn
@onready var host_p_more: Button             = $MultiplayerModal/VBox/Views/HostView/PlayerLimitBox/MoreBtn
@onready var host_p_label: Label             = $MultiplayerModal/VBox/Views/HostView/PlayerLimitBox/CountLabel
@onready var host_ai_less: Button            = $MultiplayerModal/VBox/Views/HostView/AIBOX/LessBtn
@onready var host_ai_more: Button            = $MultiplayerModal/VBox/Views/HostView/AIBOX/MoreBtn
@onready var host_ai_label: Label            = $MultiplayerModal/VBox/Views/HostView/AIBOX/CountLabel
@onready var host_map_slider: HSlider        = $MultiplayerModal/VBox/Views/HostView/MapBox/MapSlider
@onready var host_map_label: Label           = $MultiplayerModal/VBox/Views/HostView/MapBox/MapLabel
@onready var host_create_btn: Button         = $MultiplayerModal/VBox/Views/HostView/CreateBtn
@onready var room_title_label: Label         = $MultiplayerModal/VBox/Views/RoomView/RoomTitleLabel
@onready var room_details_label: Label       = $MultiplayerModal/VBox/Views/RoomView/RoomDetailsLabel
@onready var player_list_container: VBoxContainer = $MultiplayerModal/VBox/Views/RoomView/PlayerScroll/PlayerList
@onready var room_start_btn: Button          = $MultiplayerModal/VBox/Views/RoomView/RoomActions/StartBtn
@onready var room_leave_btn: Button          = $MultiplayerModal/VBox/Views/RoomView/RoomActions/LeaveBtn
@onready var room_status_label: Label        = $MultiplayerModal/VBox/Views/RoomView/StatusLabel

const GAME_SCENE := "res://scenes/Main.tscn"
const LobbyManagerClass = preload("res://scripts/network/LobbyManager.gd")

var _cfg: Node
var _audio: AudioManager
var lobby_manager: Node

var _host_player_limit: int = 4
var _host_ai_count: int = 2
var _host_map_size_index: int = 1

func _ready() -> void:
	_cfg = get_node_or_null("/root/GameConfig")
	_audio = get_node_or_null("/root/GlobalAudio") as AudioManager

	# Create Lobby Manager instance
	lobby_manager = LobbyManagerClass.new()
	add_child(lobby_manager)
	lobby_manager.lobbies_updated.connect(_on_lobbies_updated)
	lobby_manager.lobby_joined.connect(_on_lobby_joined)
	lobby_manager.lobby_join_failed.connect(_on_lobby_join_failed)
	lobby_manager.player_list_updated.connect(_on_player_list_updated)
	lobby_manager.game_start_received.connect(_on_game_start_received)

	# Wire main menu buttons
	new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	local_mp_btn.pressed.connect(_on_local_mp_pressed)
	online_mp_btn.pressed.connect(_on_online_mp_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)

	map_slider.value_changed.connect(_on_map_slider_value_changed)
	ai_less_btn.pressed.connect(_on_ai_less_pressed)
	ai_more_btn.pressed.connect(_on_ai_more_pressed)

	# Wire Settings modal
	sfx_toggle_btn.pressed.connect(_on_sfx_toggle_pressed)
	music_toggle_btn.pressed.connect(_on_music_toggle_pressed)
	settings_close_btn.pressed.connect(func():
		settings_modal.hide()
		if _audio: _audio.play_ui_click()
	)

	# Wire Online modal
	online_close_btn.pressed.connect(func():
		online_modal.hide()
		if _audio: _audio.play_ui_click()
	)

	# Wire Multiplayer modal
	mp_close_btn.pressed.connect(_on_mp_close_pressed)
	tab_browse_btn.pressed.connect(func(): _switch_mp_view("browse"))
	tab_host_btn.pressed.connect(func(): _switch_mp_view("host"))
	refresh_btn.pressed.connect(func(): lobby_manager.start_discovery())
	direct_connect_btn.pressed.connect(_on_direct_connect_pressed)

	host_p_less.pressed.connect(func():
		_host_player_limit = max(2, _host_player_limit - 1)
		_refresh_host_inputs()
	)
	host_p_more.pressed.connect(func():
		_host_player_limit = min(7, _host_player_limit + 1)
		_refresh_host_inputs()
	)
	host_ai_less.pressed.connect(func():
		_host_ai_count = max(0, _host_ai_count - 1)
		_refresh_host_inputs()
	)
	host_ai_more.pressed.connect(func():
		_host_ai_count = min(6, _host_ai_count + 1)
		_refresh_host_inputs()
	)
	host_map_slider.value_changed.connect(func(v):
		_host_map_size_index = int(v)
		_refresh_host_inputs()
	)
	host_create_btn.pressed.connect(_on_host_create_pressed)
	room_start_btn.pressed.connect(_on_room_start_pressed)
	room_leave_btn.pressed.connect(_on_room_leave_pressed)

	# Initialize single-player controls
	map_slider.min_value = 0
	map_slider.max_value = _cfg.MAP_SIZES.size() - 1
	map_slider.step     = 1
	map_slider.value    = _cfg.map_size_index

	host_map_slider.min_value = 0
	host_map_slider.max_value = _cfg.MAP_SIZES.size() - 1
	host_map_slider.step     = 1
	host_map_slider.value    = _host_map_size_index

	_refresh_map_label()
	_refresh_ai_label()
	_refresh_host_inputs()
	_update_settings_ui()

	# Check saved game
	continue_btn.disabled = not SaveManager.save_exists()

	# Hide modals
	settings_modal.hide()
	online_modal.hide()
	mp_modal.hide()

# ---------------------------------------------------------------------------
# Single-player & Basic Navigation
# ---------------------------------------------------------------------------

func _on_new_game_pressed() -> void:
	if _audio: _audio.play_ui_click()
	_cfg.is_continue = false
	_cfg.is_multiplayer = false
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_continue_pressed() -> void:
	if _audio: _audio.play_ui_click()
	_cfg.is_continue = true
	_cfg.is_multiplayer = false
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_map_slider_value_changed(value: float) -> void:
	_cfg.map_size_index = int(value)
	_refresh_map_label()

func _on_ai_less_pressed() -> void:
	if _audio: _audio.play_ui_click()
	_cfg.ai_count = max(1, _cfg.ai_count - 1)
	_refresh_ai_label()

func _on_ai_more_pressed() -> void:
	if _audio: _audio.play_ui_click()
	_cfg.ai_count = min(6, _cfg.ai_count + 1)
	_refresh_ai_label()

func _refresh_map_label() -> void:
	var lbl: String = _cfg.MAP_SIZES[_cfg.map_size_index][2]
	var w: int      = _cfg.MAP_SIZES[_cfg.map_size_index][0]
	var h: int      = _cfg.MAP_SIZES[_cfg.map_size_index][1]
	map_size_label.text = "%s  (%d x %d)" % [lbl, w, h]

func _refresh_ai_label() -> void:
	ai_count_label.text  = str(_cfg.ai_count)
	ai_less_btn.disabled = (_cfg.ai_count <= 1)
	ai_more_btn.disabled = (_cfg.ai_count >= 6)

# ---------------------------------------------------------------------------
# Settings Handlers
# ---------------------------------------------------------------------------

func _on_settings_pressed() -> void:
	if _audio: _audio.play_ui_click()
	_update_settings_ui()
	settings_modal.show()

func _update_settings_ui() -> void:
	sfx_toggle_btn.text = "SFX: %s" % ("ON 🔊" if _cfg.sfx_enabled else "OFF 🔇")
	music_toggle_btn.text = "MUSIC: %s" % ("ON 🎵" if _cfg.music_enabled else "OFF 🔇")

func _on_sfx_toggle_pressed() -> void:
	var new_val = not _cfg.sfx_enabled
	if _audio:
		_audio.set_sfx_enabled(new_val)
	else:
		_cfg.sfx_enabled = new_val
		_cfg.save_settings()
	if _audio and new_val:
		_audio.play_ui_click()
	_update_settings_ui()

func _on_music_toggle_pressed() -> void:
	if _audio: _audio.play_ui_click()
	var new_val = not _cfg.music_enabled
	if _audio:
		_audio.set_music_enabled(new_val)
	else:
		_cfg.music_enabled = new_val
		_cfg.save_settings()
	_update_settings_ui()

# ---------------------------------------------------------------------------
# Online Handlers
# ---------------------------------------------------------------------------

func _on_online_mp_pressed() -> void:
	if _audio: _audio.play_ui_click()
	online_modal.show()

# ---------------------------------------------------------------------------
# Local WiFi Multiplayer Handlers
# ---------------------------------------------------------------------------

func _on_local_mp_pressed() -> void:
	if _audio: _audio.play_ui_click()
	mp_modal.show()
	_switch_mp_view("browse")
	lobby_manager.start_discovery()

func _on_mp_close_pressed() -> void:
	if _audio: _audio.play_ui_click()
	lobby_manager.leave_lobby()
	lobby_manager.stop_discovery()
	mp_modal.hide()

func _switch_mp_view(view_name: String) -> void:
	if _audio: _audio.play_ui_click()
	browse_view.visible = (view_name == "browse")
	host_view.visible   = (view_name == "host")
	room_view.visible   = (view_name == "room")

	if view_name == "browse":
		tab_browse_btn.disabled = true
		tab_host_btn.disabled = false
		lobby_manager.start_discovery()
	elif view_name == "host":
		tab_browse_btn.disabled = false
		tab_host_btn.disabled = true
		lobby_manager.stop_discovery()
	else:
		tab_browse_btn.disabled = true
		tab_host_btn.disabled = true

func _refresh_host_inputs() -> void:
	host_p_label.text = str(_host_player_limit)
	host_p_less.disabled = (_host_player_limit <= 2)
	host_p_more.disabled = (_host_player_limit >= 7)

	host_ai_label.text = str(_host_ai_count)
	host_ai_less.disabled = (_host_ai_count <= 0)
	host_ai_more.disabled = (_host_ai_count >= 6)

	var lbl: String = _cfg.MAP_SIZES[_host_map_size_index][2]
	var w: int      = _cfg.MAP_SIZES[_host_map_size_index][0]
	var h: int      = _cfg.MAP_SIZES[_host_map_size_index][1]
	host_map_label.text = "%s (%d x %d)" % [lbl, w, h]

func _on_host_create_pressed() -> void:
	if _audio: _audio.play_ui_click()
	var lname = host_name_input.text.strip_edges()
	if lname.is_empty():
		lname = "Commander's Game"
	var lpass = host_pass_input.text.strip_edges()
	var ok = lobby_manager.create_lobby(lname, lpass, _host_player_limit, _host_ai_count, _host_map_size_index)
	if ok:
		_switch_mp_view("room")

func _on_direct_connect_pressed() -> void:
	if _audio: _audio.play_ui_click()
	var ip = direct_ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port = int(direct_port_input.text.strip_edges())
	if port <= 0:
		port = 24568
	var passw = direct_pass_input.text.strip_edges()
	lobby_manager.join_direct(ip, port, passw)

func _on_lobbies_updated(lobbies: Array) -> void:
	for c in lobby_list_container.get_children():
		c.queue_free()

	if lobbies.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Scanning WiFi network for active lobbies..."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lobby_list_container.add_child(empty_lbl)
		return

	for l_info in lobbies:
		var card = PanelContainer.new()
		var hbox = HBoxContainer.new()
		hbox.theme_override_constants.separation = 12
		card.add_child(hbox)

		var name_lbl = Label.new()
		name_lbl.text = "%s%s" % ["🔒 " if l_info.get("has_password", false) else "", l_info.get("name", "Game")]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_lbl)

		var stats_lbl = Label.new()
		stats_lbl.text = "Players: %d/%d | AI: %d | Map: %s" % [
			l_info.get("player_count", 1),
			l_info.get("player_limit", 4),
			l_info.get("ai_count", 2),
			l_info.get("map_label", "Standard")
		]
		hbox.add_child(stats_lbl)

		var join_btn = Button.new()
		join_btn.text = "JOIN"
		var ip = l_info.get("ip", "127.0.0.1")
		var has_pw = l_info.get("has_password", false)
		join_btn.pressed.connect(func():
			if _audio: _audio.play_ui_click()
			if has_pw:
				direct_ip_input.text = ip
				direct_pass_input.grab_focus()
			else:
				lobby_manager.join_lobby(ip, "")
		)
		hbox.add_child(join_btn)
		lobby_list_container.add_child(card)

func _on_lobby_joined(info: Dictionary) -> void:
	_switch_mp_view("room")
	room_title_label.text = "ROOM: %s" % info.get("name", "LAN Empire")
	room_details_label.text = "Map: %s | AI: %d | Limit: %d Players" % [
		info.get("map_label", "Standard"),
		info.get("ai_count", 2),
		info.get("player_limit", 4)
	]
	room_start_btn.visible = lobby_manager.is_hosting
	room_status_label.text = "You are the Host! Press Start Match when ready." if lobby_manager.is_hosting else "Connected! Waiting for host to start..."

func _on_lobby_join_failed(reason: String) -> void:
	_switch_mp_view("browse")
	room_status_label.text = "Connection failed: %s" % reason

func _on_player_list_updated(players: Array) -> void:
	for c in player_list_container.get_children():
		c.queue_free()

	var faction_names = [
		"Solaris Dominion (Blue)",
		"Ironfang Empire (Red)",
		"Verdant Kingdom (Green)",
		"Obsidian Conclave (Purple)",
		"Celestial Shogunate (Gold)",
		"Frostvein Clan (Teal)",
		"Golden Emirate (Orange)"
	]

	for p in players:
		var p_lbl = Label.new()
		var fid = int(p.get("faction_id", 0))
		var fac_name = faction_names[fid] if (fid >= 0 and fid < faction_names.size()) else "Empire"
		p_lbl.text = "👑 %s — Assigned: %s" % [p.get("name", "Player"), fac_name]
		player_list_container.add_child(p_lbl)

	var ai_count = lobby_manager.current_lobby_info.get("ai_count", 0)
	for a in range(ai_count):
		var a_fid = players.size() + a
		var a_name = faction_names[a_fid] if (a_fid >= 0 and a_fid < faction_names.size()) else "AI Empire"
		var ai_lbl = Label.new()
		ai_lbl.text = "🤖 AI Opponent %d — Assigned: %s" % [a + 1, a_name]
		ai_lbl.modulate = Color(0.8, 0.8, 0.8, 0.85)
		player_list_container.add_child(ai_lbl)

func _on_room_start_pressed() -> void:
	if _audio: _audio.play_ui_click()
	lobby_manager.start_game()

func _on_room_leave_pressed() -> void:
	if _audio: _audio.play_ui_click()
	lobby_manager.leave_lobby()
	_switch_mp_view("browse")

func _on_game_start_received(_config: Dictionary) -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
