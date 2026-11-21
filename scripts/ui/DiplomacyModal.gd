class_name DiplomacyModal
extends Panel

signal war_declared(target_faction_id: int)
signal peace_proposed(target_faction_id: int)
signal trade_deal_requested(target_faction_id: int)
signal resource_trade_requested(target_faction_id: int, res_type: String)

@onready var title_label: Label = $Margin/VBox/HeaderBar/TitleLabel
@onready var close_btn: Button = $Margin/VBox/HeaderBar/CloseBtn
@onready var civ_tab_btn: Button = $Margin/VBox/TabBar/CivTabBtn
@onready var espionage_tab_btn: Button = $Margin/VBox/TabBar/EspionageTabBtn

# Civ View Nodes
@onready var civ_view: VBoxContainer = $Margin/VBox/CivView
@onready var civ_buttons_container: HBoxContainer = $Margin/VBox/CivView/CivSelectorScroll/CivButtonsContainer
@onready var leader_label: Label = $Margin/VBox/CivView/CivDetailsVBox/CivHeaderBox/LeaderLabel
@onready var status_badge: Label = $Margin/VBox/CivView/CivDetailsVBox/CivHeaderBox/StatusBadge
@onready var opinion_label: Label = $Margin/VBox/CivView/CivDetailsVBox/CivHeaderBox/OpinionLabel
@onready var cities_count_label: Label = $Margin/VBox/CivView/CivDetailsVBox/IntelPanel/IntelHBox/CitiesCountLabel
@onready var units_count_label: Label = $Margin/VBox/CivView/CivDetailsVBox/IntelPanel/IntelHBox/UnitsCountLabel
@onready var trade_status_label: Label = $Margin/VBox/CivView/CivDetailsVBox/IntelPanel/IntelHBox/TradeStatusLabel
@onready var speech_label: Label = $Margin/VBox/CivView/CivDetailsVBox/SpeechBox/SpeechLabel

@onready var war_btn: Button = $Margin/VBox/CivView/CivDetailsVBox/CivActions/WarBtn
@onready var peace_btn: Button = $Margin/VBox/CivView/CivDetailsVBox/CivActions/PeaceBtn
@onready var trade_btn: Button = $Margin/VBox/CivView/CivDetailsVBox/CivActions/TradeBtn
@onready var sell_res_btn: Button = $Margin/VBox/CivView/CivDetailsVBox/CivActions/SellResBtn

# Espionage View Nodes
@onready var espionage_view: VBoxContainer = $Margin/VBox/EspionageView
@onready var spy_capacity_label: Label = $Margin/VBox/EspionageView/EspionageHeaderBox/SpyCapacityLabel
@onready var spy_tech_hint_label: Label = $Margin/VBox/EspionageView/EspionageHeaderBox/SpyTechHintLabel
@onready var agents_container: VBoxContainer = $Margin/VBox/EspionageView/EspionageContentHBox/AgentsPane/AgentsScroll/AgentsContainer
@onready var selected_agent_info_label: Label = $Margin/VBox/EspionageView/EspionageContentHBox/OperationsPane/OpsScroll/OpsVBox/SelectedAgentInfoLabel
@onready var missions_container: VBoxContainer = $Margin/VBox/EspionageView/EspionageContentHBox/OperationsPane/OpsScroll/OpsVBox/MissionsContainer
@onready var relocate_container: VBoxContainer = $Margin/VBox/EspionageView/EspionageContentHBox/OperationsPane/OpsScroll/OpsVBox/RelocateContainer

var game_state: GameState
var diplomacy_mgr: DiplomacyManager
var current_target_faction: int = -1
var player_faction: int = GameEnums.FactionId.SOLARIS_DOMINION
var current_tab: String = "civ"
var selected_agent: RefCounted = null

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(func(): hide())
	if civ_tab_btn:
		civ_tab_btn.pressed.connect(func(): open_tab("civ"))
	if espionage_tab_btn:
		espionage_tab_btn.pressed.connect(func(): open_tab("espionage"))

	if war_btn:
		war_btn.pressed.connect(_on_war_pressed)
	if peace_btn:
		peace_btn.pressed.connect(_on_peace_pressed)
	if trade_btn:
		trade_btn.pressed.connect(_on_trade_pressed)
	if sell_res_btn:
		sell_res_btn.pressed.connect(_on_sell_res_pressed)

func setup(p_game_state: GameState, p_diplomacy: DiplomacyManager) -> void:
	game_state = p_game_state
	diplomacy_mgr = p_diplomacy
	_init_target_faction()
	open_tab("civ")

func _init_target_faction() -> void:
	if not game_state:
		return
	for fid in game_state.factions:
		if fid != player_faction and fid != GameEnums.FactionId.BARBARIANS:
			if diplomacy_mgr and diplomacy_mgr.has_met_faction(player_faction, fid):
				current_target_faction = fid
				return
	for fid in game_state.factions:
		if fid != player_faction and fid != GameEnums.FactionId.BARBARIANS:
			current_target_faction = fid
			return

func open_tab(tab_name: String) -> void:
	current_tab = tab_name
	if current_tab == "civ":
		civ_view.show()
		espionage_view.hide()
		civ_tab_btn.add_theme_color_override("font_color", Color("00e5ff"))
		espionage_tab_btn.add_theme_color_override("font_color", Color("a0a0a0"))
		_refresh_civ_tab()
	else:
		civ_view.hide()
		espionage_view.show()
		espionage_tab_btn.add_theme_color_override("font_color", Color("00e5ff"))
		civ_tab_btn.add_theme_color_override("font_color", Color("a0a0a0"))
		_refresh_espionage_tab()

func refresh() -> void:
	if current_tab == "civ":
		_refresh_civ_tab()
	else:
		_refresh_espionage_tab()

# =============================================================
# WORLD CIVILIZATIONS TAB
# =============================================================

func _refresh_civ_tab() -> void:
	if not game_state or not diplomacy_mgr:
		return

	# Rebuild civ buttons
	for child in civ_buttons_container.get_children():
		child.queue_free()

	var rival_factions: Array[int] = []
	for fid in game_state.factions:
		if fid != player_faction and fid != GameEnums.FactionId.BARBARIANS:
			rival_factions.append(fid)

	if current_target_faction == -1 and not rival_factions.is_empty():
		current_target_faction = rival_factions[0]

	for fid in rival_factions:
		var fac_name = game_state.faction_names.get(fid, "Empire")
		var fac_color = game_state.faction_colors.get(fid, Color.WHITE)
		var is_met = diplomacy_mgr.has_met_faction(player_faction, fid)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(140, 32)
		if is_met:
			var rel = diplomacy_mgr.get_relation(player_faction, fid)
			var status_str = "🕊" if rel["status"] != DiplomacyManager.RelationStatus.WAR else "⚔"
			btn.text = "%s %s" % [status_str, fac_name]
			btn.add_theme_color_override("font_color", fac_color)
		else:
			btn.text = "🔭 Undiscovered"
			btn.add_theme_color_override("font_color", Color("7f8c8d"))

		if fid == current_target_faction:
			btn.modulate = Color(1.2, 1.2, 1.2, 1.0)
		else:
			btn.modulate = Color(0.85, 0.85, 0.85, 1.0)

		btn.pressed.connect(func():
			current_target_faction = fid
			_refresh_civ_tab()
		)
		civ_buttons_container.add_child(btn)

	# Render details of current target faction
	var target_fid = current_target_faction
	var is_met = diplomacy_mgr.has_met_faction(player_faction, target_fid)
	var fac_name = game_state.faction_names.get(target_fid, "Empire")
	var fac_color = game_state.faction_colors.get(target_fid, Color.WHITE)

	if not is_met:
		leader_label.text = "Emissary: Undiscovered Civilization"
		leader_label.modulate = Color("95a5a6")
		status_badge.text = "🔭 UNDISCOVERED"
		status_badge.add_theme_color_override("font_color", Color("95a5a6"))
		opinion_label.text = "  |  Opinion: Unknown"
		cities_count_label.text = "🏛 Known Cities: ???"
		units_count_label.text = "⚔ Military Units: ???"
		trade_status_label.text = "🤝 Trade: Unavailable"
		speech_label.text = "Our scouts have not established contact with the emissaries of this realm. Explore across the fog of war or encounter their borders to open diplomacy!"

		war_btn.visible = false
		peace_btn.visible = false
		trade_btn.visible = false
		sell_res_btn.visible = false
		return

	# Met civilization details
	war_btn.visible = true
	peace_btn.visible = true
	trade_btn.visible = true
	sell_res_btn.visible = true

	var rel = diplomacy_mgr.get_relation(player_faction, target_fid)
	var is_war = (rel["status"] == DiplomacyManager.RelationStatus.WAR)
	var opinion = rel["opinion"]

	leader_label.text = "Leader Emissary: %s" % fac_name
	leader_label.modulate = fac_color

	if is_war:
		status_badge.text = "⚔ AT WAR"
		status_badge.add_theme_color_override("font_color", Color("e74c3c"))
		war_btn.disabled = true
		peace_btn.disabled = false
	else:
		status_badge.text = "🕊 AT PEACE"
		status_badge.add_theme_color_override("font_color", Color("2ecc71"))
		war_btn.disabled = false
		peace_btn.disabled = true

	var op_str = "Neutral"
	if opinion > 15: op_str = "Friendly"
	elif opinion < -15: op_str = "Hostile"
	opinion_label.text = "  |  Opinion: %s (%+d)" % [op_str, opinion]

	# World Intel Counts (moved from top legend)
	var known_cities = 0
	for c in game_state.get_faction_cities(target_fid):
		var is_disc = c.is_discovered_by(player_faction) if c.has_method("is_discovered_by") else c.discovered_by_faction.get(player_faction, false)
		if is_disc:
			known_cities += 1
	var known_units = 0
	var has_surv = game_state.espionage_manager.has_active_surveillance(player_faction, target_fid) if game_state.espionage_manager else false
	for u in game_state.get_faction_units(target_fid):
		var tile = game_state.grid_model.get_tile(u.grid_pos)
		if has_surv or (tile and tile.revealed_by_faction.get(player_faction, false)):
			known_units += 1

	var surv_note = " (🛰 Satellite Surveillance Active!)" if has_surv else ""
	cities_count_label.text = "🏛 Known Cities: %d" % known_cities
	units_count_label.text = "⚔ Military Units: %d%s" % [known_units, surv_note]

	# Trade deal status
	if rel["trade_turns"] > 0:
		trade_status_label.text = "🤝 Trade Deal: %d turns remaining (+2 🪙/turn)" % rel["trade_turns"]
		trade_btn.disabled = true
	else:
		trade_status_label.text = "🤝 Trade: No active trade treaty"
		trade_btn.disabled = is_war

	# Dynamic retro speech
	if is_war:
		speech_label.text = "Our warriors shall crush your forces and tear down your banners! No concessions!"
	else:
		if opinion > 15:
			speech_label.text = "Solaris Dominion has proven a steadfast friend. Let our commerce and mutual respect endure!"
		elif opinion < -15:
			speech_label.text = "Your expansion encroaches upon our ancestral domains. Tensions rise by the day."
		else:
			speech_label.text = "Greetings, travelers of Solaris Dominion. The realm is tranquil. What terms or agreements bring you to our court?"

	# Strategic resource sale button
	var total_res = game_state.get_faction_strategic_resources(player_faction)
	var avail_res = game_state.get_available_strategic_resources(player_faction)
	var res_type = ""
	if total_res.get("niter", 0) > 0: res_type = "niter"
	elif total_res.get("iron", 0) > 0: res_type = "iron"
	elif total_res.get("horses", 0) > 0: res_type = "horses"

	if res_type == "":
		sell_res_btn.text = "NO EXPORT RES 🔒"
		sell_res_btn.disabled = true
	elif is_war:
		sell_res_btn.text = "SELL RES (+40🪙) 🔒"
		sell_res_btn.disabled = true
	else:
		var has_deal = diplomacy_mgr.has_export_deal(player_faction, target_fid, res_type)
		var free_count = avail_res.get(res_type, 0)
		if has_deal:
			var deal_turns = diplomacy_mgr.get_export_deal_turns_remaining(player_faction, target_fid, res_type)
			sell_res_btn.text = "ACTIVE EXPORT (%d T) 🔒" % deal_turns
			sell_res_btn.disabled = true
		elif free_count < 1:
			sell_res_btn.text = "%s COMMITTED 🔒" % res_type.to_upper()
			sell_res_btn.disabled = true
		else:
			sell_res_btn.text = "SELL %s (+40🪙)" % res_type.to_upper()
			sell_res_btn.disabled = false

func _on_war_pressed() -> void:
	if current_target_faction != -1:
		war_declared.emit(current_target_faction)
		_refresh_civ_tab()

func _on_peace_pressed() -> void:
	if current_target_faction != -1:
		peace_proposed.emit(current_target_faction)
		_refresh_civ_tab()

func _on_trade_pressed() -> void:
	if current_target_faction != -1:
		trade_deal_requested.emit(current_target_faction)
		_refresh_civ_tab()

func _on_sell_res_pressed() -> void:
	if current_target_faction != -1:
		var total_res = game_state.get_faction_strategic_resources(player_faction)
		var res_type = "horses"
		if total_res.get("niter", 0) > 0: res_type = "niter"
		elif total_res.get("iron", 0) > 0: res_type = "iron"
		resource_trade_requested.emit(current_target_faction, res_type)
		_refresh_civ_tab()

# =============================================================
# ESPIONAGE BUREAU TAB
# =============================================================

func _refresh_espionage_tab() -> void:
	if not game_state or not game_state.espionage_manager:
		return

	var esp_mgr = game_state.espionage_manager
	var capacity = esp_mgr.get_spy_capacity(player_faction)
	var active_spies = esp_mgr.get_spies(player_faction)

	spy_capacity_label.text = "🕵️ Covert Agents: %d / %d (Capacity: %d)" % [
		active_spies.size(), capacity, capacity
	]

	if capacity == 0:
		spy_tech_hint_label.text = "Research 'Espionage' (Medieval Era) to recruit your first Spy!"
	elif capacity == 1:
		spy_tech_hint_label.text = "Research 'Diplomatic Service' (Renaissance Era) to unlock 2nd Spy capacity!"
	else:
		spy_tech_hint_label.text = "Maximum Espionage capacity unlocked (2 Agents). Off-map covert operations active."

	# Rebuild agents list
	for child in agents_container.get_children():
		child.queue_free()

	if active_spies.is_empty():
		var empty_lbl = Label.new()
		if capacity == 0:
			empty_lbl.text = "No spies unlocked yet.\nResearch 'Espionage' tech in the Tech Tree to train Spies."
		else:
			empty_lbl.text = "No active agents.\nTrain a Spy in any of your cities from City Production (Cost: 75 ⚙)!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color("95a5a6"))
		agents_container.add_child(empty_lbl)
		selected_agent = null
		_refresh_operations_pane()
		return

	if selected_agent == null or not active_spies.has(selected_agent):
		selected_agent = active_spies[0]

	for agent in active_spies:
		var card = PanelContainer.new()
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)

		var name_lbl = Label.new()
		name_lbl.text = agent.name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color("00e5ff"))
		vbox.add_child(name_lbl)

		var loc_str = "Home Territory"
		if agent.current_city_id != -1:
			var c = game_state.cities.get(agent.current_city_id, null)
			if c:
				var c_fac_name = game_state.faction_names.get(c.faction_id, "Empire")
				loc_str = "%s (%s)" % [c.city_name, c_fac_name]
		elif agent.target_faction_id != -1:
			loc_str = "%s Territory" % game_state.faction_names.get(agent.target_faction_id, "Empire")

		var loc_lbl = Label.new()
		loc_lbl.text = "📍 %s" % loc_str
		loc_lbl.add_theme_font_size_override("font_size", 10)
		loc_lbl.add_theme_color_override("font_color", Color("bdc3c7"))
		vbox.add_child(loc_lbl)

		var status_str = "💤 Idle"
		var status_color = Color("f1c40f")
		match agent.state:
			"traveling":
				status_str = "✈ Traveling (⏳ %d turns)" % agent.turns_remaining
				status_color = Color("3498db")
			"established":
				status_str = "👁 Established (Ready)"
				status_color = Color("2ecc71")
			"operating":
				status_str = "🎯 %s (⏳ %d turns)" % [agent.current_mission.capitalize().replace("_", " "), agent.turns_remaining]
				status_color = Color("e67e22")

		var st_lbl = Label.new()
		st_lbl.text = status_str
		st_lbl.add_theme_font_size_override("font_size", 10)
		st_lbl.add_theme_color_override("font_color", status_color)
		vbox.add_child(st_lbl)

		var select_btn = Button.new()
		select_btn.text = "SELECT AGENT"
		select_btn.add_theme_font_size_override("font_size", 10)
		if agent == selected_agent:
			select_btn.modulate = Color(1.3, 1.3, 1.3, 1.0)
			select_btn.text = "▶ SELECTED"
		select_btn.pressed.connect(func():
			selected_agent = agent
			_refresh_espionage_tab()
		)
		vbox.add_child(select_btn)

		card.add_child(vbox)
		agents_container.add_child(card)

	_refresh_operations_pane()

func _refresh_operations_pane() -> void:
	for c in missions_container.get_children():
		c.queue_free()
	for c in relocate_container.get_children():
		c.queue_free()

	if selected_agent == null:
		selected_agent_info_label.text = "No agent selected. Select an agent on the left to assign covert orders."
		return

	var agent = selected_agent
	var esp_mgr = game_state.espionage_manager

	var target_fac_name = "Unknown"
	if agent.target_faction_id != -1:
		target_fac_name = game_state.faction_names.get(agent.target_faction_id, "Empire")

	var target_city_name = "None"
	if agent.current_city_id != -1:
		var c = game_state.cities.get(agent.current_city_id, null)
		if c: target_city_name = c.city_name

	selected_agent_info_label.text = "%s | Target: %s (%s) | Status: %s" % [
		agent.name, target_fac_name, target_city_name, agent.state.to_upper()
	]

	# 1. State: Traveling
	if agent.state == "traveling":
		var info = Label.new()
		info.text = "✈ Agent is currently en route to establish an intelligence network in %s.\nArrival and establishment in %d turn(s)." % [
			target_fac_name, agent.turns_remaining
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color("3498db"))
		missions_container.add_child(info)
		return

	# 2. State: Operating
	if agent.state == "operating":
		var info = Label.new()
		info.text = "🎯 Covert operation [%s] in progress against %s!\nOperation will resolve in %d turn(s)." % [
			agent.current_mission.capitalize().replace("_", " "), target_fac_name, agent.turns_remaining
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color("e67e22"))
		missions_container.add_child(info)
		return

	# 3. State: Idle (Deploy to foreign realm)
	if agent.state == "idle":
		var prompt = Label.new()
		prompt.text = "DEPLOYMENT ORDERS:\nChoose a discovered foreign empire to infiltrate (takes 2 turns to travel and establish network):"
		prompt.add_theme_font_size_override("font_size", 11)
		prompt.add_theme_color_override("font_color", Color("f1c40f"))
		missions_container.add_child(prompt)

		var met_civs: Array[int] = []
		for fid in game_state.factions:
			if fid != player_faction and fid != GameEnums.FactionId.BARBARIANS:
				if diplomacy_mgr and diplomacy_mgr.has_met_faction(player_faction, fid):
					met_civs.append(fid)

		if met_civs.is_empty():
			var no_civ = Label.new()
			no_civ.text = "No foreign civilizations met yet. Send military or scout units to explore before dispatching spies!"
			no_civ.add_theme_font_size_override("font_size", 11)
			no_civ.add_theme_color_override("font_color", Color("e74c3c"))
			missions_container.add_child(no_civ)
		else:
			for fid in met_civs:
				var fname = game_state.faction_names.get(fid, "Empire")
				var dep_btn = Button.new()
				dep_btn.text = "✈ INFILTRATE %s" % fname.to_upper()
				dep_btn.custom_minimum_size = Vector2(0, 32)
				dep_btn.pressed.connect(func():
					esp_mgr.travel_to_faction(agent, fid)
					_refresh_espionage_tab()
				)
				missions_container.add_child(dep_btn)
		return

	# 4. State: Established (Display 4 Operations and Relocation)
	if agent.state == "established":
		var mission_prompt = Label.new()
		mission_prompt.text = "CHOOSE COVERT OPERATION (Infiltrated: %s):" % target_fac_name
		mission_prompt.add_theme_font_size_override("font_size", 12)
		mission_prompt.add_theme_color_override("font_color", Color("2ecc71"))
		missions_container.add_child(mission_prompt)

		# Operation 1: Find Enemy Cities
		_add_mission_card(
			"FIND ENEMY CITIES",
			"Scout uncharted settlements of %s to locate their hidden cities." % target_fac_name,
			"✅ 95% Success  |  ❌ 5% Failure (Safe)  |  ⏳ 3 Turns",
			true, "",
			func():
				esp_mgr.start_mission(agent, "find_cities")
				_refresh_espionage_tab()
		)

		# Operation 2: Military Surveillance
		_add_mission_card(
			"MILITARY SURVEILLANCE",
			"Tap communication channels to reveal all %s unit positions and moves for 5 turns." % target_fac_name,
			"✅ 95% Success (5 Turns Vision)  |  ❌ 5% Failure (Safe)  |  ⏳ 3 Turns",
			true, "",
			func():
				esp_mgr.start_mission(agent, "locate_units")
				_refresh_espionage_tab()
		)

		# Operation 3: Pillage Encampment
		var has_enc = (esp_mgr._find_target_encampment(agent.target_faction_id) != Vector2i(-1, -1))
		var enc_lock_reason = "" if has_enc else " [Locked: Target has no Military Encampment]"
		_add_mission_card(
			"PILLAGE ENCAMPMENT",
			"Sabotage and destroy foreign military encampment district." + enc_lock_reason,
			"✅ 60% Success  |  💀 15% Killed  |  ⚠️ 25% Escaped  |  ⏳ 3 Turns",
			has_enc, enc_lock_reason,
			func():
				esp_mgr.start_mission(agent, "pillage_encampment")
				_refresh_espionage_tab()
		)

		# Operation 4: Incite Rebellion
		_add_mission_card(
			"INCITE REBELLION",
			"Arm dissidents around target encampment to spawn 1 melee & 2 ranged barbarian rebels." + enc_lock_reason,
			"✅ 40% Success  |  💀 25% Killed  |  ⚠️ 35% Escaped  |  ⏳ 3 Turns",
			has_enc, enc_lock_reason,
			func():
				esp_mgr.start_mission(agent, "incite_rebellion")
				_refresh_espionage_tab()
		)

		# Relocate Section
		var sep = HSeparator.new()
		relocate_container.add_child(sep)

		var rel_lbl = Label.new()
		rel_lbl.text = "RELOCATE AGENT TO ANOTHER EMPIRE:"
		rel_lbl.add_theme_font_size_override("font_size", 11)
		rel_lbl.add_theme_color_override("font_color", Color("3498db"))
		relocate_container.add_child(rel_lbl)

		var rel_hbox = HBoxContainer.new()
		rel_hbox.add_theme_constant_override("separation", 8)
		for fid in game_state.factions:
			if fid != player_faction and fid != GameEnums.FactionId.BARBARIANS and fid != agent.target_faction_id:
				if diplomacy_mgr and diplomacy_mgr.has_met_faction(player_faction, fid):
					var fname = game_state.faction_names.get(fid, "Empire")
					var r_btn = Button.new()
					r_btn.text = "✈ To %s" % fname
					r_btn.add_theme_font_size_override("font_size", 10)
					r_btn.pressed.connect(func():
						esp_mgr.travel_to_faction(agent, fid)
						_refresh_espionage_tab()
					)
					rel_hbox.add_child(r_btn)
		relocate_container.add_child(rel_hbox)

func _add_mission_card(m_title: String, desc: String, odds_str: String, is_enabled: bool, lock_reason: String, on_execute: Callable) -> void:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var title_lbl = Label.new()
	title_lbl.text = "🎯 " + m_title
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color("00e5ff") if is_enabled else Color("7f8c8d"))
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color("bdc3c7"))
	vbox.add_child(desc_lbl)

	var odds_lbl = Label.new()
	odds_lbl.text = odds_str
	odds_lbl.add_theme_font_size_override("font_size", 10)
	odds_lbl.add_theme_color_override("font_color", Color("ffd700") if is_enabled else Color("7f8c8d"))
	vbox.add_child(odds_lbl)

	var exec_btn = Button.new()
	exec_btn.text = "EXECUTE MISSION (3 Turns)" if is_enabled else ("LOCKED" + lock_reason)
	exec_btn.disabled = not is_enabled
	exec_btn.custom_minimum_size = Vector2(0, 28)
	exec_btn.add_theme_font_size_override("font_size", 10)
	exec_btn.pressed.connect(on_execute)
	vbox.add_child(exec_btn)

	panel.add_child(vbox)
	missions_container.add_child(panel)
