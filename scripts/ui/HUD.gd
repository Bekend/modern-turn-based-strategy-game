class_name HUD
extends CanvasLayer

## 8-bit retro HUD controller displaying turn status, faction legend,
## entity inspection cards, D-Pad movement controls, and victory modals.

signal end_turn_requested()
signal tech_tree_opened()
signal found_city_requested(unit_id: int)
signal build_improvement_requested(unit_id: int, improvement_type: GameEnums.ImprovementType)
signal change_production_requested(city_id: int, item_id: String)
signal cycle_unit_requested()
signal cycle_city_requested()
signal save_requested()
signal save_and_exit_requested()
signal unit_upgrade_requested(unit_id: int)
signal declare_war_requested(target_faction_id: int)
signal peace_proposed(target_faction_id: int)
signal trade_deal_requested(target_faction_id: int)
signal resource_trade_requested(target_faction_id: int, res_type: String)
signal purchase_unit_requested(city_id: int, unit_id: String)
signal unit_pillage_requested(unit_id: int)
signal unit_heal_requested(unit_id: int)
signal unit_skip_requested(unit_id: int)
signal unit_fortify_requested(unit_id: int)
signal build_border_wall_requested(unit_id: int)
signal build_temporary_camp_requested(unit_id: int)
signal garrison_unit_requested(unit_id: int)
signal start_district_placement_requested(city: CityData, district_id: String)
signal cancel_district_placement_requested()
signal select_garrisoned_unit_requested(unit_id: int)
signal unit_automate_requested(unit_id: int, automated: bool)
signal select_city_requested(city: CityData)

var is_queue_mode: bool = false
var queue_mode_btn: Button = null
var queue_list_container: VBoxContainer = null

@onready var turn_label: Label = $TopBar/TurnLabel
@onready var menu_btn: Button = $TopBar/MenuButton
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var diplomacy_btn: Button = $TopBar/DiplomacyButton
@onready var espionage_btn: Button = $TopBar/EspionageButton
@onready var phase_label: Label = $TopBar/PhaseLabel
@onready var cycle_unit_btn: Button = $TopBar/CycleUnitButton
@onready var cycle_city_btn: Button = $TopBar/CycleCityButton
@onready var tech_btn: Button = $TopBar/TechButton
@onready var end_turn_btn: Button = $TopBar/EndTurnButton
@onready var feedback_label: Label = $FeedbackBanner/FeedbackLabel
@onready var diplomacy_modal: DiplomacyModal = $DiplomacyModal

# Pause Modal
@onready var pause_modal: Panel = $PauseModal
@onready var resume_btn: Button = $PauseModal/VBox/ResumeBtn
@onready var save_btn: Button = $PauseModal/VBox/SaveBtn
@onready var save_exit_btn: Button = $PauseModal/VBox/SaveExitBtn

# Faction Legend Badges
@onready var legend_container: HBoxContainer = $FactionLegendBar/LegendContainer
@onready var player_badge: Label = $FactionLegendBar/LegendContainer/PlayerFactionBadge
@onready var rival1_badge: Label = $FactionLegendBar/LegendContainer/Rival1Badge
@onready var rival2_badge: Label = $FactionLegendBar/LegendContainer/Rival2Badge
@onready var barb_badge: Label = $FactionLegendBar/LegendContainer/BarbarianBadge

# Bottom Card
@onready var bottom_panel: Panel = $BottomCard
@onready var card_title: Label = $BottomCard/InfoBox/TitleLabel
@onready var card_stats: Label = $BottomCard/InfoBox/StatsLabel
@onready var hp_box: HBoxContainer = $BottomCard/InfoBox/HPBox
@onready var hp_bar: ProgressBar = $BottomCard/InfoBox/HPBox/HPBar
@onready var hp_text: Label = $BottomCard/InfoBox/HPBox/HPText
@onready var card_movement: Label = $BottomCard/InfoBox/MovementLabel
@onready var card_hint: Label = $BottomCard/InfoBox/HintLabel
@onready var action_button_box: HBoxContainer = $BottomCard/ActionScroll/ActionButtons

# Left-Side Production Menu
@onready var prod_menu: Panel = $ProductionMenu
@onready var prod_title: Label = $ProductionMenu/Margin/VBox/HeaderBox/TitleLabel
@onready var prod_close_btn: Button = $ProductionMenu/Margin/VBox/HeaderBox/CloseButton
@onready var prod_yield_label: Label = $ProductionMenu/Margin/VBox/YieldLabel
@onready var prod_status_label: Label = $ProductionMenu/Margin/VBox/CurrentProjectCard/CardVBox/ProjectStatusLabel
@onready var prod_progress_bar: ProgressBar = $ProductionMenu/Margin/VBox/CurrentProjectCard/CardVBox/ProjectProgressBar
@onready var prod_turns_label: Label = $ProductionMenu/Margin/VBox/CurrentProjectCard/CardVBox/ProjectTurnsLabel
@onready var prod_options_container: VBoxContainer = $ProductionMenu/Margin/VBox/ScrollList/OptionsContainer

# Victory Overlay
@onready var victory_panel: Panel = $VictoryModal
@onready var victory_title: Label = $VictoryModal/Title
@onready var victory_desc: Label = $VictoryModal/Description
@onready var restart_btn: Button = $VictoryModal/RestartButton
@onready var main_menu_btn: Button = $VictoryModal/MainMenuButton

var game_state: GameState
var turn_manager: TurnManager
var active_unit_id: int = -1
var active_city_id: int = -1

var placement_banner: Panel = null
var placement_label: Label = null
var placement_cancel_btn: Button = null

func _ensure_placement_banner() -> void:
	if placement_banner != null:
		return
	placement_banner = Panel.new()
	placement_banner.custom_minimum_size = Vector2(400, 48)
	placement_banner.anchor_left = 0.5
	placement_banner.anchor_right = 0.5
	placement_banner.anchor_top = 0.0
	placement_banner.anchor_bottom = 0.0
	placement_banner.offset_left = -200
	placement_banner.offset_right = 200
	placement_banner.offset_top = 54
	placement_banner.offset_bottom = 102
	placement_banner.visible = false

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	style.border_color = Color(0.0, 0.85, 1.0, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	placement_banner.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 12
	hbox.offset_right = -12
	hbox.offset_top = 4
	hbox.offset_bottom = -4
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	placement_banner.add_child(hbox)

	placement_label = Label.new()
	placement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_label.text = "📍 SELECT LOCATION"
	placement_label.add_theme_font_size_override("font_size", 12)
	placement_label.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	hbox.add_child(placement_label)

	placement_cancel_btn = Button.new()
	placement_cancel_btn.text = "✕ CANCEL"
	placement_cancel_btn.custom_minimum_size = Vector2(85, 32)
	placement_cancel_btn.pressed.connect(func():
		hide_district_placement_banner()
		cancel_district_placement_requested.emit()
	)
	hbox.add_child(placement_cancel_btn)

	add_child(placement_banner)

func show_district_placement_banner(district_id: String, city_name: String) -> void:
	_ensure_placement_banner()
	var d_name = district_id.capitalize()
	if district_id == "encampment": d_name = "Military Encampment"
	elif district_id == "science_camp": d_name = "Science Campus"
	elif district_id == "neighborhood": d_name = "Neighborhood"
	elif district_id == "harbor": d_name = "Harbor"

	placement_label.text = "📍 SELECT TILE FOR %s (%s)\n[Tap highlighted tile on map]" % [d_name.to_upper(), city_name]
	placement_banner.show()

func hide_district_placement_banner() -> void:
	if placement_banner:
		placement_banner.hide()

func setup(p_game_state: GameState, p_turn_manager: TurnManager) -> void:
	game_state = p_game_state
	turn_manager = p_turn_manager

	end_turn_btn.pressed.connect(func():
		# Civ 6 Priority 1: prompt player if any city is idle without orders
		var idle_city: CityData = null
		if game_state:
			for c in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
				if c.current_production_id == "":
					if not c.production_queue.is_empty():
						c.current_production_id = c.production_queue.pop_front()
					else:
						idle_city = c
						break
		if idle_city != null:
			select_city_requested.emit(idle_city)
			show_feedback("⚠️ %s requires production orders!" % idle_city.city_name, true)
			return

		# Civ 6 Priority 2: prompt player if active units have unspent moves
		var unmoved = game_state.get_unmoved_units(GameEnums.FactionId.SOLARIS_DOMINION) if game_state else []
		if not unmoved.is_empty():
			show_feedback("⚔ Selecting next unit awaiting orders (%d left)..." % unmoved.size(), false)
			cycle_unit_requested.emit()
			return

		end_turn_requested.emit()
	)
	cycle_unit_btn.pressed.connect(func(): cycle_unit_requested.emit())
	cycle_city_btn.pressed.connect(func(): cycle_city_requested.emit())
	tech_btn.pressed.connect(func(): tech_tree_opened.emit())
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	main_menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	# Pause Modal connections
	menu_btn.pressed.connect(toggle_pause_menu)
	resume_btn.pressed.connect(hide_pause_menu)
	save_btn.pressed.connect(func(): save_requested.emit())
	save_exit_btn.pressed.connect(func(): save_and_exit_requested.emit())

	# Left-side Production Menu
	prod_close_btn.pressed.connect(hide_production_menu)

	# Diplomacy & Espionage connections
	if diplomacy_btn:
		diplomacy_btn.pressed.connect(func():
			if diplomacy_modal and diplomacy_modal.visible and diplomacy_modal.current_tab == "civ":
				diplomacy_modal.hide()
			else:
				show_diplomacy_menu("civ")
		)
	if espionage_btn:
		espionage_btn.pressed.connect(func():
			if diplomacy_modal and diplomacy_modal.visible and diplomacy_modal.current_tab == "espionage":
				diplomacy_modal.hide()
			else:
				show_diplomacy_menu("espionage")
		)
	if diplomacy_modal:
		diplomacy_modal.war_declared.connect(func(fac): declare_war_requested.emit(fac))
		diplomacy_modal.peace_proposed.connect(func(fac): peace_proposed.emit(fac))
		diplomacy_modal.trade_deal_requested.connect(func(fac): trade_deal_requested.emit(fac))
		diplomacy_modal.resource_trade_requested.connect(func(fac, res): resource_trade_requested.emit(fac, res))

	victory_panel.hide()
	bottom_panel.hide()
	prod_menu.hide()
	pause_modal.hide()
	if diplomacy_modal:
		diplomacy_modal.hide()

	update_top_bar()
	update_faction_legend()

func show_diplomacy_menu(tab_name: String = "civ") -> void:
	if not diplomacy_modal:
		return
	diplomacy_modal.setup(game_state, game_state.diplomacy_manager)
	diplomacy_modal.open_tab(tab_name)
	diplomacy_modal.show()

func toggle_diplomacy_menu() -> void:
	show_diplomacy_menu("civ")

func hide_diplomacy_menu() -> void:
	if diplomacy_modal:
		diplomacy_modal.hide()

func update_top_bar() -> void:
	turn_label.text = "TURN: %d" % turn_manager.current_turn

	if gold_label and game_state:
		var gold = game_state.faction_gold.get(GameEnums.FactionId.SOLARIS_DOMINION, 0)
		var total_gold_income = 0
		for p_city in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
			var city_y = game_state.calculate_city_yields(p_city)
			total_gold_income += city_y.get("gold", 0)
		var total_upkeep = 0
		for u in game_state.get_faction_units(GameEnums.FactionId.SOLARIS_DOMINION):
			total_upkeep += game_state.UNIT_MAINTENANCE_COSTS.get(u.data.id, 0)
		var net_gold_rate = total_gold_income - total_upkeep
		var strat = game_state.get_faction_strategic_resources(GameEnums.FactionId.SOLARIS_DOMINION)
		var res_str = ""
		if strat.get("iron", 0) > 0: res_str += " ⛏%d" % strat["iron"]
		if strat.get("horses", 0) > 0: res_str += " 🐴%d" % strat["horses"]
		if strat.get("niter", 0) > 0: res_str += " 🧂%d" % strat["niter"]
		gold_label.text = "🪙 %d (%+d/t)%s" % [gold, net_gold_rate, res_str]

	# Civ 6 mandatory production orders: check if any player city is idle
	var has_idle_city = false
	if game_state:
		for p_city in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
			if p_city.current_production_id == "":
				if not p_city.production_queue.is_empty():
					p_city.current_production_id = p_city.production_queue.pop_front()
				else:
					has_idle_city = true
					break

	var unmoved_count = 0
	if game_state:
		unmoved_count = game_state.get_unmoved_units(GameEnums.FactionId.SOLARIS_DOMINION).size()

	match turn_manager.current_phase:
		GameEnums.TurnPhase.PLAYER_TURN:
			phase_label.text = "YOUR TURN"
			phase_label.modulate = Color("3498db")
			end_turn_btn.disabled = false
			if has_idle_city:
				end_turn_btn.text = "CHOOSE PRODUCTION ⚙"
				end_turn_btn.modulate = Color("f39c12")
			elif unmoved_count > 0:
				end_turn_btn.text = "MOVE UNIT ⚔ (%d)" % unmoved_count
				end_turn_btn.modulate = Color("00e5ff")
			else:
				end_turn_btn.text = "END TURN ▶"
				end_turn_btn.modulate = Color("2ecc71")
		GameEnums.TurnPhase.AI_FACTIONS_TURN:
			phase_label.text = "RIVAL AI TURN..."
			phase_label.modulate = Color("e74c3c")
			end_turn_btn.disabled = true
		GameEnums.TurnPhase.BARBARIAN_TURN:
			phase_label.text = "BARBARIAN RAIDERS..."
			phase_label.modulate = Color("8e44ad")
			end_turn_btn.disabled = true
		GameEnums.TurnPhase.TURN_RESOLUTION:
			phase_label.text = "PROCESSING HARVEST..."
			phase_label.modulate = Color("f1c40f")
			end_turn_btn.disabled = true

	var total_sci_rate = 0
	if game_state:
		for p_city in game_state.get_faction_cities(GameEnums.FactionId.SOLARIS_DOMINION):
			var city_y = game_state.calculate_city_yields(p_city)
			total_sci_rate += city_y.get("science", 0)

	var tech_state = game_state.tech_manager.faction_tech_state.get(GameEnums.FactionId.SOLARIS_DOMINION, {})
	var curr_tid = tech_state.get("current_tech_id", "None")
	var science = tech_state.get("accumulated_science", 0)
	var curr_tech = game_state.tech_manager.all_techs.get(curr_tid, null)
	var cost = curr_tech.science_cost if curr_tech else 0
	if curr_tid == "None":
		tech_btn.text = "TECH: [CHOOSE RESEARCH] (+%d🔬/t)" % total_sci_rate
	else:
		tech_btn.text = "TECH: %s (%d/%d 🔬 +%d/t)" % [curr_tid.capitalize(), science, cost, total_sci_rate]

	update_faction_legend()

const FACTION_ICONS = {
	GameEnums.FactionId.SOLARIS_DOMINION: "🔵",
	GameEnums.FactionId.IRONFANG_EMPIRE: "🔴",
	GameEnums.FactionId.VERDANT_KINGDOM: "🟢",
	GameEnums.FactionId.OBSIDIAN_CONCLAVE: "🟣",
	GameEnums.FactionId.CELESTIAL_SHOGUNATE: "🟡",
	GameEnums.FactionId.FROSTVEIN_CLAN: "⚪",
	GameEnums.FactionId.GOLDEN_EMIRATE: "🟠",
	GameEnums.FactionId.BARBARIANS: "💀",
}

func update_faction_legend() -> void:
	if not game_state or not legend_container:
		return

	# Rebuild legend items dynamically
	for child in legend_container.get_children():
		child.queue_free()

	for f_id in game_state.factions:
		if f_id == GameEnums.FactionId.BARBARIANS:
			continue
		var fname = game_state.get_faction_name(f_id)
		var fcolor = game_state.get_faction_color(f_id)
		var icon = FACTION_ICONS.get(f_id, "🏳️")
		var u_cnt = game_state.get_faction_units(f_id).size()
		var c_cnt = game_state.get_faction_cities(f_id).size()

		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", fcolor)

		if f_id == GameEnums.FactionId.SOLARIS_DOMINION:
			lbl.text = "%s %s (YOU): %d U, %d C" % [icon, fname, u_cnt, c_cnt]
		else:
			var status = "Defeated" if (u_cnt == 0 and c_cnt == 0) else "%d U, %d C" % [u_cnt, c_cnt]
			lbl.text = "%s %s: %s" % [icon, fname, status]
		legend_container.add_child(lbl)

	# Barbarians
	var barb_units = game_state.get_faction_units(GameEnums.FactionId.BARBARIANS).size()
	var barb_lbl = Label.new()
	barb_lbl.add_theme_font_size_override("font_size", 11)
	barb_lbl.add_theme_color_override("font_color", Color(0.85, 0.35, 0.35))
	barb_lbl.text = "💀 Barbarians: %d Raiders" % barb_units
	legend_container.add_child(barb_lbl)

func show_feedback(text: String, is_warning: bool) -> void:
	feedback_label.text = text
	feedback_label.modulate = Color(1.0, 0.4, 0.4) if is_warning else Color(0.4, 1.0, 0.5)

	var tween = create_tween()
	tween.tween_property(feedback_label, "modulate:a", 1.0, 0.1)
	tween.tween_interval(3.5)
	tween.tween_property(feedback_label, "modulate:a", 0.0, 0.5)

func show_unit_card(unit: GameState.UnitInstance) -> void:
	active_unit_id = unit.instance_id
	active_city_id = -1
	hide_production_menu()
	bottom_panel.show()
	hp_box.show()

	var is_player = unit.faction_id == GameEnums.FactionId.SOLARIS_DOMINION
	var tag = "[YOU - SOLARIS DOMINION]" if is_player else "[HOSTILE / RIVAL]"
	card_title.text = "%s %s (ID #%d)" % [tag, unit.data.unit_name.to_upper(), unit.instance_id]
	card_title.modulate = Color("3895d3") if is_player else Color("e74c3c")

	# Unit HP Bar & Text
	var hp_pct = clampf(float(unit.current_health) / float(maxi(1, unit.data.max_health)) * 100.0, 0.0, 100.0)
	hp_bar.value = hp_pct
	hp_text.text = "%d / %d HP" % [unit.current_health, unit.data.max_health]
	if hp_pct > 50.0:
		hp_text.modulate = Color("2ecc71")
	elif hp_pct > 25.0:
		hp_text.modulate = Color("f1c40f")
	else:
		hp_text.modulate = Color("e74c3c")

	# Stats, Builder Charges & Upkeep
	var upkeep = game_state.UNIT_MAINTENANCE_COSTS.get(unit.data.id, 0)
	var upkeep_str = "Upkeep: Free" if upkeep == 0 else "Upkeep: -%d 🪙/t" % upkeep

	var embarked_str = "  |  [EMBARKED - CANNOT ATTACK ⚓]" if unit.is_embarked else ""
	if unit.data.can_build_improvements:
		card_stats.text = "Combat Strength: %d  |  BUILD CHARGES: [ %d / 3 ]  |  %s%s" % [
			unit.data.combat_strength, unit.build_charges, upkeep_str, embarked_str
		]
	else:
		card_stats.text = "Combat Strength: %d%s  |  %s%s" % [
			unit.data.combat_strength,
			("  |  Ranged: %d (Range %d)" % [unit.data.ranged_strength, unit.data.attack_range]) if unit.data.is_ranged() else "",
			upkeep_str,
			embarked_str
		]

	# Movement Points display with clear rules
	if unit.remaining_mp > 0:
		card_movement.text = "MOVEMENT POINTS: [ %d / %d MP ]  (Plains = 1 MP | Hills = 2 MP)" % [
			unit.remaining_mp, unit.data.max_movement_points
		]
		card_movement.modulate = Color(0.0, 0.95, 1.0)
		if unit.data.can_build_improvements and unit.build_charges <= 0:
			card_hint.text = "⚠️ Builder has exhausted all 3 build charges."
			card_hint.modulate = Color(1.0, 0.4, 0.4)
		else:
			card_hint.text = "Tap highlighted cyan tile on map to move (or use Arrow keys / WASD)."
			card_hint.modulate = Color(0.7, 0.7, 0.75)
	else:
		card_movement.text = "MOVEMENT POINTS: [ 0 / %d MP - Turn Moves Exhausted ]" % unit.data.max_movement_points
		card_movement.modulate = Color(0.8, 0.4, 0.4)
	if unit.is_fortified:
		var garrison_city = game_state.get_city_at(unit.grid_pos) if game_state else null
		if garrison_city and garrison_city.garrison_unit_id == unit.instance_id:
			card_hint.text = "🛡️ Garrisoned in %s (+10 City Defense active). Fortified until moved or awakened." % garrison_city.city_name
			card_hint.modulate = Color(0.2, 0.9, 1.0)
		else:
			card_hint.text = "🛡 Unit is Fortified (+25% Defense). Sleeps until moved, attacked, or awakened."
			card_hint.modulate = Color(0.3, 0.8, 1.0)

	_clear_action_buttons()

	if is_player:
		if unit.is_automated:
			var stop_auto_btn = Button.new()
			stop_auto_btn.text = "🛑 STOP AUTO"
			stop_auto_btn.add_theme_color_override("font_color", Color("ff7675"))
			stop_auto_btn.pressed.connect(func():
				unit_automate_requested.emit(unit.instance_id, false)
				show_unit_card(unit)
			)
			action_button_box.add_child(stop_auto_btn)
		else:
			var auto_btn = Button.new()
			auto_btn.text = "🤖 AUTOMATE"
			auto_btn.add_theme_color_override("font_color", Color("74b9ff"))
			auto_btn.pressed.connect(func():
				unit_automate_requested.emit(unit.instance_id, true)
				show_unit_card(unit)
			)
			action_button_box.add_child(auto_btn)

		if unit.is_fortified or unit.is_resting_heal:
			var wake_btn = Button.new()
			wake_btn.text = "WAKE UP ⏰"
			wake_btn.add_theme_color_override("font_color", Color("00e5ff"))
			wake_btn.pressed.connect(func():
				unit.is_fortified = false
				unit.fortify_turns = 0
				unit.is_resting_heal = false
				unit.is_garrisoned = false
				unit.is_automated = false
				var old_city = game_state.get_city_at(unit.grid_pos) if game_state else null
				if old_city and old_city.garrison_unit_id == unit.instance_id:
					old_city.garrison_unit_id = -1
				show_unit_card(unit)
				update_top_bar()
			)
			action_button_box.add_child(wake_btn)

		# Tactical Actions: Skip, Fortify, Garrison, Heal, Pillage
		if unit.remaining_mp > 0:
			var skip_btn = Button.new()
			skip_btn.text = "SKIP TURN ⏳"
			skip_btn.pressed.connect(func(): unit_skip_requested.emit(unit.instance_id))
			action_button_box.add_child(skip_btn)

		if not unit.data.is_civilian() and unit.remaining_mp > 0 and not unit.is_fortified:
			var fort_btn = Button.new()
			fort_btn.text = "FORTIFY 🛡 (+25% Def)"
			fort_btn.pressed.connect(func(): unit_fortify_requested.emit(unit.instance_id))
			action_button_box.add_child(fort_btn)

		# City Garrison Action
		if not unit.data.is_civilian() and unit.remaining_mp > 0:
			var target_city = turn_manager.get_garrisonable_city_for_unit(unit.instance_id) if turn_manager else null
			if target_city != null and target_city.garrison_unit_id != unit.instance_id:
				var garrison_btn = Button.new()
				garrison_btn.text = "🛡️ GARRISON %s (+10 Def)" % target_city.city_name.to_upper()
				garrison_btn.add_theme_color_override("font_color", Color("ffd700"))
				garrison_btn.pressed.connect(func(): garrison_unit_requested.emit(unit.instance_id))
				action_button_box.add_child(garrison_btn)

		if unit.current_health < unit.data.max_health and unit.remaining_mp > 0:
			var heal_btn = Button.new()
			heal_btn.text = "HEAL 🩹"
			heal_btn.add_theme_color_override("font_color", Color("2ecc71"))
			heal_btn.pressed.connect(func(): unit_heal_requested.emit(unit.instance_id))
			action_button_box.add_child(heal_btn)

		if unit.remaining_mp > 0:
			var cur_tile = game_state.grid_model.get_tile(unit.grid_pos)
			if cur_tile and cur_tile.improvement_data != null and cur_tile.owner_faction_id != unit.faction_id:
				var pil_btn = Button.new()
				pil_btn.text = "PILLAGE 💥 (+30🪙 & Heal)"
				pil_btn.add_theme_color_override("font_color", Color("f39c12"))
				pil_btn.pressed.connect(func(): unit_pillage_requested.emit(unit.instance_id))
				action_button_box.add_child(pil_btn)

		# Settler: Found City
		if unit.data.can_found_city:
			var found_btn = Button.new()
			found_btn.custom_minimum_size = Vector2(150, 36)

			var too_close = false
			for c in game_state.cities.values():
				var dx = absi(c.grid_pos.x - unit.grid_pos.x)
				var dy = absi(c.grid_pos.y - unit.grid_pos.y)
				if dx <= 2 and dy <= 2:
					too_close = true
					break

			var current_tile = game_state.grid_model.get_tile(unit.grid_pos)
			var impassable = (current_tile == null or not current_tile.biome_data.is_passable)
			var foreign_land = (current_tile != null and current_tile.owner_faction_id != -1 and current_tile.owner_faction_id != unit.faction_id)

			if too_close:
				found_btn.text = "TOO CLOSE TO CITY 🔒"
				found_btn.disabled = true
				card_hint.text = "❌ Cannot settle: Must be at least 2 tiles away from any city (Red zones)."
				card_hint.modulate = Color(1.0, 0.45, 0.45)
			elif impassable or foreign_land:
				found_btn.text = "CANNOT SETTLE 🔒"
				found_btn.disabled = true
				card_hint.text = "❌ Cannot settle on this terrain or foreign territory."
				card_hint.modulate = Color(1.0, 0.45, 0.45)
			else:
				found_btn.text = "FOUND CITY 🏛"
				found_btn.pressed.connect(func(): found_city_requested.emit(unit.instance_id))
				card_hint.text = "✅ Settleable land! Tap 'FOUND CITY' to establish a new city here."
				card_hint.modulate = Color(0.4, 0.95, 0.5)

			action_button_box.add_child(found_btn)

		# Unit Upgrade Action
		if unit.data.upgrade_unit_id != "":
			var target_proto: UnitData = load("res://resources/units/%s.tres" % unit.data.upgrade_unit_id)
			if target_proto:
				var up_cost = unit.data.upgrade_cost
				var player_gold = game_state.faction_gold.get(unit.faction_id, 0)
				var has_tech = (target_proto.tech_prerequisite == "" or game_state.tech_manager.is_tech_researched(unit.faction_id, target_proto.tech_prerequisite))
				var strat_res = game_state.get_faction_strategic_resources(unit.faction_id)
				var has_res = (target_proto.strategic_prerequisite == "" or strat_res.get(target_proto.strategic_prerequisite, 0) >= 1)
				var can_afford = (player_gold >= up_cost)
				var can_upgrade = has_tech and has_res and can_afford and unit.remaining_mp > 0

				var up_btn = Button.new()
				var lock_reason = ""
				if not has_tech:
					var t_name = target_proto.tech_prerequisite.capitalize()
					var t_obj = game_state.tech_manager.all_techs.get(target_proto.tech_prerequisite, null)
					if t_obj: t_name = t_obj.title
					lock_reason = " [Needs %s]" % t_name
				elif not has_res:
					lock_reason = " [Needs %s]" % target_proto.strategic_prerequisite.capitalize()
				elif not can_afford:
					lock_reason = " [Needs %d 🪙]" % up_cost

				up_btn.text = "UPGRADE TO %s (%d🪙)%s" % [target_proto.unit_name.to_upper(), up_cost, lock_reason]
				up_btn.disabled = not can_upgrade
				up_btn.add_theme_color_override("font_color", Color.GOLD if can_upgrade else Color.LIGHT_GRAY)
				up_btn.pressed.connect(func(): unit_upgrade_requested.emit(unit.instance_id))
				action_button_box.add_child(up_btn)

		# Military Engineer: Border Walls & Fortified Camps
		if (unit.data.can_build_military_structures or unit.data.id == "military_engineer") and unit.remaining_mp > 0 and unit.build_charges > 0:
			var tile = game_state.grid_model.get_tile(unit.grid_pos)
			if tile:
				var is_friendly = (tile.owner_faction_id == unit.faction_id)
				var is_city = tile.is_city or (game_state.get_city_at(unit.grid_pos) != null if game_state else false)
				var can_border_wall = is_friendly and not tile.has_border_wall and not is_city and (tile.improvement_data == null or tile.improvement_data.improvement_type != GameEnums.ImprovementType.MILITARY_ENCAMPMENT)
				if can_border_wall:
					var wall_btn = Button.new()
					wall_btn.text = "+ BORDER WALL 🧱"
					wall_btn.pressed.connect(func(): build_border_wall_requested.emit(unit.instance_id))
					action_button_box.add_child(wall_btn)

				var can_camp = not is_city and tile.improvement_data == null and tile.biome_data.is_passable and (tile.owner_faction_id == unit.faction_id or tile.owner_faction_id == -1)
				if can_camp:
					var camp_btn = Button.new()
					camp_btn.text = "+ FORTIFIED CAMP ⛺"
					camp_btn.pressed.connect(func(): build_temporary_camp_requested.emit(unit.instance_id))
					action_button_box.add_child(camp_btn)

		# Builder: Rural Improvements (Farms, Pastures, Mines)
		if unit.data.can_build_improvements and unit.remaining_mp > 0 and unit.build_charges > 0:
			var tile = game_state.grid_model.get_tile(unit.grid_pos)
			if tile and tile.improvement_data == null:
				var is_inside_borders = (tile.owner_faction_id == unit.faction_id)
				if not is_inside_borders:
					card_hint.text = "⚠️ Tile is outside city borders! Commit your city to EXPAND BORDER to build here."
					card_hint.modulate = Color(1.0, 0.75, 0.2)
				else:
					card_hint.text = "Inside city territory (%d charges left). Tap an action to construct improvement." % unit.build_charges
					card_hint.modulate = Color(0.3, 1.0, 0.5)

				var is_plains = (tile.biome_data.biome_type == GameEnums.BiomeType.PLAINS)
				var is_rice = (tile.resource_data and tile.resource_data.id == "rice")
				var is_horses = (tile.resource_data and tile.resource_data.id == "horses")
				var is_iron = (tile.resource_data and tile.resource_data.id == "iron")
				var is_gold = (tile.resource_data and tile.resource_data.id == "gold_ore")
				var is_gems = (tile.resource_data and tile.resource_data.id == "gems")
				var is_bare_grass = (is_plains and tile.resource_data == null)

				# 1. Farm on Rice (Requires Agriculture, yields +5 food with rice bonus)
				if is_rice:
					var farm_btn = Button.new()
					var has_agri = game_state.tech_manager.is_tech_researched(unit.faction_id, "agriculture")
					var farm_label = "+ FARM 🌾 [Rice (+5 Food)]"
					if not has_agri: farm_label += " [Needs Agriculture]"
					farm_btn.text = farm_label
					farm_btn.disabled = not is_inside_borders or not has_agri
					farm_btn.pressed.connect(func(): build_improvement_requested.emit(unit.instance_id, GameEnums.ImprovementType.FARM))
					action_button_box.add_child(farm_btn)

				# 2. Basic Farm on empty grass/plains (No tech required, yields +1 food)
				elif is_bare_grass:
					var farm_btn = Button.new()
					farm_btn.text = "+ BASIC FARM 🌾 (+1 Food)"
					farm_btn.disabled = not is_inside_borders
					farm_btn.pressed.connect(func(): build_improvement_requested.emit(unit.instance_id, GameEnums.ImprovementType.FARM))
					action_button_box.add_child(farm_btn)

				# 3. Pasture on Horses (Requires Horse Riding)
				if is_horses:
					var pas_btn = Button.new()
					var has_hr = game_state.tech_manager.is_tech_researched(unit.faction_id, "horse_riding")
					var pas_label = "+ PASTURE 🐎 [Horses (+1🌾, +2⚙)]"
					if not has_hr: pas_label += " [Needs Horse Riding]"
					pas_btn.text = pas_label
					pas_btn.disabled = not is_inside_borders or not has_hr
					pas_btn.pressed.connect(func(): build_improvement_requested.emit(unit.instance_id, GameEnums.ImprovementType.PASTURE))
					action_button_box.add_child(pas_btn)

				# 4. Mine on Hills, Iron, Gold Ore, Gems, or Niter
				var is_hills = (tile.biome_data.biome_type == GameEnums.BiomeType.HILLS)
				var is_niter = (tile.resource_data and tile.resource_data.id == "niter")
				if is_hills or is_iron or is_gold or is_gems or is_niter:
					var mine_btn = Button.new()
					var has_mining = game_state.tech_manager.is_tech_researched(unit.faction_id, "mining")
					var res_tech_ok = true
					var req_tech_name = ""
					if is_iron:
						res_tech_ok = game_state.tech_manager.is_tech_researched(unit.faction_id, "iron_working")
						req_tech_name = "Iron Working"
					elif is_gold:
						res_tech_ok = game_state.tech_manager.is_tech_researched(unit.faction_id, "currency")
						req_tech_name = "Currency"
					elif is_gems:
						res_tech_ok = game_state.tech_manager.is_tech_researched(unit.faction_id, "construction")
						req_tech_name = "Construction"
					elif is_niter:
						res_tech_ok = game_state.tech_manager.is_tech_researched(unit.faction_id, "gunpowder")
						req_tech_name = "Gunpowder"

					var can_mine = has_mining and res_tech_ok
					var mine_label = "+ MINE ⛏"
					if is_niter:
						mine_label = "+ NITER MINE 🧂 [Niter (+1⚙, +1🔬)]"
					if not has_mining: mine_label += " [Needs Mining]"
					elif not res_tech_ok: mine_label += " [Needs %s]" % req_tech_name
					mine_btn.text = mine_label
					mine_btn.disabled = not is_inside_borders or not can_mine
					mine_btn.pressed.connect(func(): build_improvement_requested.emit(unit.instance_id, GameEnums.ImprovementType.MINE))
					action_button_box.add_child(mine_btn)

	# Deselect button
	var desel_btn = Button.new()
	desel_btn.text = "DESELECT"
	desel_btn.pressed.connect(hide_bottom_card)
	action_button_box.add_child(desel_btn)

func show_city_card(city: CityData) -> void:
	active_city_id = city.city_id
	active_unit_id = -1
	bottom_panel.show()
	hp_box.show()

	var is_player = city.faction_id == GameEnums.FactionId.SOLARIS_DOMINION
	var tag = "[YOU - SOLARIS DOMINION]" if is_player else "[HOSTILE / RIVAL CITY]"
	var yields = game_state.calculate_city_yields(city)
	var consumption = maxi(1, int(city.population * 1.5))
	var surplus = yields["food"] - consumption
	var housing_cap = game_state.calculate_city_housing(city)
	city.housing = housing_cap
	var housing_status = "[100% Growth]"
	if city.population >= housing_cap:
		housing_status = "[CAPPED ⛔ 0% Growth]"
	elif city.population >= housing_cap - 1:
		housing_status = "[SLOW ⚠️ 50% Growth]"

	card_title.text = "%s %s (Pop %d | Working %d Tiles | Territory: %d)" % [
		tag, city.city_name.to_upper(), city.population, yields["worked_count"], city.territory_tiles.size()
	]
	card_title.modulate = Color("3895d3") if is_player else Color("e74c3c")

	# City Health & Fortification
	var hp_pct = clampf(float(city.health) / float(maxi(1, city.max_health)) * 100.0, 0.0, 100.0)
	hp_bar.value = hp_pct
	hp_text.text = "%d / %d HP  |  Fort: %d / %d" % [city.health, city.max_health, city.fortification, city.max_fortification]
	hp_text.modulate = Color("3498db")

	card_stats.text = "Prod: +%d ⚙  |  Food: +%d (%+d)  |  Housing: %d/%d 🏠 %s  |  Sci: +%d 🔬" % [
		yields["production"], yields["food"], surplus, city.population, housing_cap, housing_status,
		yields.get("science", 1)
	]

	# Cost lookup and progress estimation
	var unit_costs = {
		"scout": 25,
		"builder": 30,
		"settler": 50,
		"slinger": 30,
		"archer": 50,
		"spearman": 45,
		"swordsman": 65,
		"horseman": 55,
		"catapult": 65,
		"crossbowman": 75,
		"knight": 85,
		"military_engineer": 45,
		"barbarian_raider": 35,
		"barbarian_horseman": 45,
		"galley": 40,
		"quadrireme": 50,
		"galleass": 70,
		"musketman": 100,
		"bombard": 110,
		"cuirassier": 120,
		"frigate": 115,
		"spy": 75,
		"walls": 40,
		"market": 50,
		"aqueduct": 55,
		"castle": 75,
		"encampment": 45,
		"science_camp": 45,
		"neighborhood": 55,
		"harbor": 50,
		"expand_border": 25,
		"harvest_project": 30,
		"commercial_project": 30,
		"festival_project": 40
	}

	if city.current_production_id == "":
		card_movement.text = "PROJECT: [IDLE - CHOOSE PRODUCTION]"
		card_movement.modulate = Color(1.0, 0.75, 0.2)
		card_hint.text = "Production is idle! Select a unit or project from the left menu."
		card_hint.modulate = Color(1.0, 0.85, 0.3)
	elif city.current_production_id == "expand_border":
		var target_cost = 25
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "PROJECT: EXPAND BORDER [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.95, 0.85, 0.2)
		card_hint.text = "City is expanding borders! Tap 'PRODUCE ⚙' to change project."
		card_hint.modulate = Color(0.7, 0.7, 0.75)
	elif city.current_production_id == "walls":
		var target_cost = 40
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: CITY WALLS [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.4, 0.8, 1.0)
		card_hint.text = "Walls provide +50 Fortification and unlock ranged bombardment defense!"
		card_hint.modulate = Color(0.7, 0.85, 1.0)
	elif city.current_production_id == "market":
		var target_cost = 50
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: MARKET [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(1.0, 0.85, 0.2)
		card_hint.text = "Market generates +4 🪙 Gold every turn for your treasury!"
		card_hint.modulate = Color(1.0, 0.9, 0.5)
	elif city.current_production_id == "aqueduct":
		var target_cost = 55
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: AQUEDUCT [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.3, 0.8, 1.0)
		card_hint.text = "Aqueduct grants +3 🌾 Food every turn to accelerate city growth!"
		card_hint.modulate = Color(0.5, 0.9, 1.0)
	elif city.current_production_id == "castle":
		var target_cost = 75
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: CASTLE [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.9, 0.7, 0.9)
		card_hint.text = "Castle grants +50 Fortification and strengthens defensive bombardment!"
		card_hint.modulate = Color(0.9, 0.7, 1.0)
	elif city.current_production_id == "encampment":
		var target_cost = 45
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: MILITARY ENCAMPMENT [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.9, 0.4, 0.4)
		card_hint.text = "Encampment generates +1 ⚙ Production, discounts unit resources, and unlocks Military Engineers!"
		card_hint.modulate = Color(1.0, 0.6, 0.6)
	elif city.current_production_id == "science_camp":
		var target_cost = 45
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: SCIENCE CAMPUS [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.3, 0.8, 1.0)
		card_hint.text = "Science Campus generates +3 🔬 Science per turn to accelerate research!"
		card_hint.modulate = Color(0.5, 0.9, 1.0)
	elif city.current_production_id == "neighborhood":
		var target_cost = 55
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: NEIGHBORHOOD [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.4, 0.9, 0.5)
		card_hint.text = "Neighborhood provides +4 Housing and +1 Food to support massive city growth!"
		card_hint.modulate = Color(0.6, 1.0, 0.7)
	elif city.current_production_id == "harbor":
		var target_cost = 50
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "CONSTRUCTING: HARBOR DISTRICT [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.2, 0.7, 1.0)
		card_hint.text = "Harbor enables naval units and grants +2 🪙 Gold, +1 ⚙ Production, and +1 🌾 Food!"
		card_hint.modulate = Color(0.4, 0.85, 1.0)
	elif city.current_production_id == "harvest_project":
		var target_cost = 30
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "PROJECT: HARVEST FESTIVAL [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.3, 0.9, 0.4)
		card_hint.text = "Harvest Festival will grant +30 🌾 Food upon completion to accelerate city growth!"
		card_hint.modulate = Color(0.5, 1.0, 0.6)
	elif city.current_production_id == "commercial_project":
		var target_cost = 30
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "PROJECT: COMMERCIAL INVESTMENT [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(1.0, 0.85, 0.2)
		card_hint.text = "Commercial Investment will deposit +40 🪙 Gold into treasury upon completion!"
		card_hint.modulate = Color(1.0, 0.9, 0.4)
	elif city.current_production_id == "festival_project":
		var target_cost = 40
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		card_movement.text = "PROJECT: GRAND FESTIVAL [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.9, 0.6, 1.0)
		card_hint.text = "Grand Festival will grant +20 🌾 Food and +25 🪙 Gold upon completion!"
		card_hint.modulate = Color(0.9, 0.7, 1.0)
	else:
		var target_cost = unit_costs.get(city.current_production_id, 30)
		var remaining_prod = maxi(0, target_cost - city.production_stored)
		var est_turns = maxi(1, ceili(float(remaining_prod) / float(maxi(1, yields["production"]))))
		var proj_name = city.current_production_id.to_upper()
		if turn_manager.unit_prototypes.has(city.current_production_id):
			proj_name = turn_manager.unit_prototypes[city.current_production_id].unit_name.to_upper()
		card_movement.text = "TRAINING: %s [ %d / %d ⚙ ] (%d Turns to Completion)" % [
			proj_name, city.production_stored, target_cost, est_turns
		]
		card_movement.modulate = Color(0.2, 0.9, 1.0)
		card_hint.text = "Tap 'PRODUCE ⚙' to select a different unit or project from the left menu."
		card_hint.modulate = Color(0.7, 0.7, 0.75)

	if not city.production_queue.is_empty():
		card_hint.text += "  •  [Queue: %d item(s)]" % city.production_queue.size()

	# If city has walls, show defensive bombardment info
	if city.has_walls and is_player:
		if not city.has_bombarded_this_turn:
			card_hint.text = "🧱 City Walls ACTIVE: Tap an enemy within 2 tiles to fire defensive bombardment!"
			card_hint.modulate = Color(0.3, 1.0, 0.6)
		else:
			card_hint.text = "🧱 City Walls: Defensive bombardment fired this turn."
			card_hint.modulate = Color(0.65, 0.65, 0.7)

	_clear_action_buttons()

	if is_player:
		# Garrisoned unit select button
		if city.garrison_unit_id != -1 and game_state and game_state.units.has(city.garrison_unit_id):
			var g_unit = game_state.units[city.garrison_unit_id]
			var garrison_btn = Button.new()
			garrison_btn.text = "🗡️ GARRISON: %s" % g_unit.data.unit_name
			garrison_btn.custom_minimum_size = Vector2(130, 36)
			garrison_btn.modulate = Color(1.0, 0.85, 0.3)
			garrison_btn.pressed.connect(func():
				select_garrisoned_unit_requested.emit(city.garrison_unit_id)
			)
			action_button_box.add_child(garrison_btn)

		# Open Production Menu Button
		var prod_btn = Button.new()
		prod_btn.text = "PRODUCE ⚙"
		prod_btn.custom_minimum_size = Vector2(120, 36)
		prod_btn.pressed.connect(func():
			if prod_menu.visible:
				hide_production_menu()
			else:
				show_production_menu(city)
		)
		action_button_box.add_child(prod_btn)

		# Open left production menu
		show_production_menu(city)

	var desel_btn = Button.new()
	desel_btn.custom_minimum_size = Vector2(80, 36)
	desel_btn.text = "✕ CLOSE"
	desel_btn.pressed.connect(hide_bottom_card)
	action_button_box.add_child(desel_btn)

func show_production_menu(city: CityData) -> void:
	if not city or city.faction_id != GameEnums.FactionId.SOLARIS_DOMINION:
		hide_production_menu()
		return

	prod_menu.show()
	prod_title.text = "🏛 %s" % city.city_name.to_upper()

	var yields = game_state.calculate_city_yields(city)
	var consumption = maxi(1, int(city.population * 1.5))
	var surplus = yields["food"] - consumption
	var housing_cap = game_state.calculate_city_housing(city)
	city.housing = housing_cap
	var housing_status = "[100% Growth]"
	if city.population >= housing_cap:
		housing_status = "[CAPPED ⛔ 0% Growth]"
	elif city.population >= housing_cap - 1:
		housing_status = "[SLOW ⚠️ 50% Growth]"

	prod_yield_label.text = "Yield: +%d ⚙  •  Food: +%d (%+d)  •  Housing: %d/%d 🏠 %s  •  Sci: +%d 🔬\nGrowth: %d/%d to Pop %d" % [
		yields["production"], yields["food"], surplus, city.population, housing_cap, housing_status,
		yields.get("science", 1),
		city.food_stored, city.food_needed, city.population + 1
	]

	var unit_costs = {
		"scout": 25,
		"builder": 30,
		"settler": 50,
		"slinger": 30,
		"archer": 50,
		"spearman": 45,
		"swordsman": 65,
		"horseman": 55,
		"catapult": 65,
		"crossbowman": 75,
		"knight": 85,
		"military_engineer": 45,
		"barbarian_raider": 35,
		"barbarian_horseman": 45,
		"galley": 40,
		"quadrireme": 50,
		"galleass": 70,
		"musketman": 100,
		"bombard": 110,
		"cuirassier": 120,
		"frigate": 115,
		"spy": 75,
		"walls": 40,
		"market": 50,
		"aqueduct": 55,
		"castle": 75,
		"encampment": 45,
		"science_camp": 45,
		"neighborhood": 55,
		"harbor": 50,
		"expand_border": 25,
		"harvest_project": 30,
		"commercial_project": 30,
		"festival_project": 40
	}

	var curr_id = city.current_production_id
	if curr_id == "":
		prod_status_label.text = "CURRENT: [IDLE - SELECT PROJECT]"
		prod_status_label.modulate = Color(1.0, 0.75, 0.2)
		prod_progress_bar.value = 0.0
		prod_turns_label.text = "Awaiting orders! Choose from options below."
		prod_turns_label.modulate = Color(1.0, 0.85, 0.3)
	else:
		prod_status_label.modulate = Color.WHITE
		prod_turns_label.modulate = Color(0.7, 0.85, 1.0)
		var curr_cost = unit_costs.get(curr_id, 30)
		var stored = city.production_stored
		var pct = clampf(float(stored) / float(maxi(1, curr_cost)) * 100.0, 0.0, 100.0)
		prod_progress_bar.value = pct

		var rem_prod = maxi(0, curr_cost - stored)
		var turns_left = ceili(float(rem_prod) / float(maxi(1, yields["production"])))

		var curr_display_name = curr_id.capitalize()
		if curr_id == "expand_border":
			curr_display_name = "Expand Border 🏰"
		elif curr_id == "walls":
			curr_display_name = "City Walls 🧱"
		elif curr_id == "market":
			curr_display_name = "Market 💰"
		elif curr_id == "aqueduct":
			curr_display_name = "Aqueduct 💧"
		elif curr_id == "castle":
			curr_display_name = "Castle 🏰"
		elif curr_id == "encampment":
			curr_display_name = "Military Encampment ⚔"
		elif curr_id == "science_camp":
			curr_display_name = "Science Campus 🔬"
		elif curr_id == "neighborhood":
			curr_display_name = "Neighborhood 🏘"
		elif curr_id == "harbor":
			curr_display_name = "Harbor District ⚓"
		elif curr_id == "harvest_project":
			curr_display_name = "Harvest Festival 🌾 (+30 Food)"
		elif curr_id == "commercial_project":
			curr_display_name = "Commercial Investment 🪙 (+40 Gold)"
		elif curr_id == "festival_project":
			curr_display_name = "Grand Festival 🎉 (+20 Food & +25 Gold)"
		elif curr_id == "spy":
			curr_display_name = "Spy (Covert Agent) 🕵️"
		elif turn_manager.unit_prototypes.has(curr_id):
			curr_display_name = turn_manager.unit_prototypes[curr_id].unit_name

		prod_status_label.text = "CURRENT: " + curr_display_name
		prod_turns_label.text = "%d / %d ⚙  •  %d Turn(s) Left" % [stored, curr_cost, turns_left]

	# Queue Mode Toggle in HeaderBox
	var header_box = prod_title.get_parent()
	if queue_mode_btn == null or not is_instance_valid(queue_mode_btn):
		queue_mode_btn = Button.new()
		queue_mode_btn.custom_minimum_size = Vector2(75, 24)
		queue_mode_btn.add_theme_font_size_override("font_size", 10)
		header_box.add_child(queue_mode_btn)
		header_box.move_child(queue_mode_btn, 1)
		queue_mode_btn.pressed.connect(func():
			is_queue_mode = not is_queue_mode
			show_production_menu(city)
		)
	queue_mode_btn.text = "📋 QUEUE: ON" if is_queue_mode else "📋 QUEUE: OFF"
	queue_mode_btn.modulate = Color("f1c40f") if is_queue_mode else Color(0.75, 0.75, 0.75)

	# Production Queue List Section in CardVBox
	var card_vbox = prod_status_label.get_parent()
	if queue_list_container == null or not is_instance_valid(queue_list_container):
		queue_list_container = VBoxContainer.new()
		queue_list_container.name = "QueueListContainer"
		card_vbox.add_child(queue_list_container)

	for q_child in queue_list_container.get_children():
		queue_list_container.remove_child(q_child)
		q_child.queue_free()

	if city.production_queue.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Queue: [Empty - tap '+Q' to queue orders]"
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.modulate = Color(0.65, 0.65, 0.7, 0.7)
		queue_list_container.add_child(empty_lbl)
	else:
		var q_header_box = HBoxContainer.new()
		var q_title = Label.new()
		q_title.text = "PROD QUEUE (%d):" % city.production_queue.size()
		q_title.add_theme_font_size_override("font_size", 11)
		q_title.modulate = Color("ffe082")
		q_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q_header_box.add_child(q_title)

		var clear_btn = Button.new()
		clear_btn.text = "Clear"
		clear_btn.custom_minimum_size = Vector2(40, 20)
		clear_btn.add_theme_font_size_override("font_size", 9)
		clear_btn.pressed.connect(func():
			city.clear_production_queue()
			show_production_menu.call_deferred(city)
			show_city_card.call_deferred(city)
		)
		q_header_box.add_child(clear_btn)
		queue_list_container.add_child(q_header_box)

		for idx in range(city.production_queue.size()):
			var q_id = city.production_queue[idx]
			var q_cost = unit_costs.get(q_id, 30)
			var q_turns = ceili(float(q_cost) / float(maxi(1, yields["production"])))
			var q_name = q_id.capitalize()
			if q_id == "expand_border": q_name = "Expand Border 🏰"
			elif q_id == "walls": q_name = "City Walls 🧱"
			elif q_id == "harvest_project": q_name = "Harvest (+30🌾)"
			elif q_id == "commercial_project": q_name = "Commercial (+40🪙)"
			elif q_id == "festival_project": q_name = "Festival (+20🌾 +25🪙)"
			elif turn_manager.unit_prototypes.has(q_id):
				q_name = turn_manager.unit_prototypes[q_id].unit_name

			var q_row = HBoxContainer.new()
			var q_item_lbl = Label.new()
			q_item_lbl.text = "%d. %s (%dt)" % [idx + 1, q_name, q_turns]
			q_item_lbl.add_theme_font_size_override("font_size", 10)
			q_item_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			q_row.add_child(q_item_lbl)

			var q_del_btn = Button.new()
			q_del_btn.text = "✕"
			q_del_btn.custom_minimum_size = Vector2(24, 20)
			q_del_btn.add_theme_font_size_override("font_size", 10)
			q_del_btn.modulate = Color("e74c3c")
			var item_idx = idx
			q_del_btn.pressed.connect(func():
				city.remove_from_queue_at(item_idx)
				show_production_menu.call_deferred(city)
				show_city_card.call_deferred(city)
			)
			q_row.add_child(q_del_btn)
			queue_list_container.add_child(q_row)

	# Clean options list safely without emitting errors
	for child in prod_options_container.get_children():
		prod_options_container.remove_child(child)
		child.queue_free()

	var strat_res = game_state.get_available_strategic_resources(city.faction_id)

	var options = [
		{"id": "scout", "name": "Scout", "icon": "⚡", "cost": 25},
		{"id": "builder", "name": "Builder (3 charges)", "icon": "🔨", "cost": 30},
		{"id": "settler", "name": "Settler", "icon": "🏛", "cost": 50},
		{"id": "slinger", "name": "Slinger (Ranged)", "icon": "🏹", "cost": 30},
		{"id": "archer", "name": "Archer (Rng 2)", "icon": "🏹", "cost": 50, "tech": "archer"},
		{"id": "spearman", "name": "Spearman (Anti-Cav)", "icon": "🔱", "cost": 45, "tech": "spearman"},
		{"id": "swordsman", "name": "Swordsman", "icon": "⚔", "cost": 65, "tech": "swordsman", "res": "iron"},
		{"id": "horseman", "name": "Horseman", "icon": "🐴", "cost": 55, "tech": "horseman", "res": "horses"},
		{"id": "military_engineer", "name": "Military Engineer (2 chg)", "icon": "👷", "cost": 45, "tech": "bronze_working", "req_encampment": true},
		{"id": "catapult", "name": "Catapult (Siege)", "icon": "☄", "cost": 65, "tech": "catapult", "res": "iron"},
		{"id": "crossbowman", "name": "Crossbowman (Rng 2)", "icon": "🎯", "cost": 75, "tech": "crossbowman", "res": "iron"},
		{"id": "knight", "name": "Knight (Heavy Cav)", "icon": "🛡", "cost": 85, "tech": "knight", "res": "horses"},
		{"id": "galley", "name": "Galley (Naval Melee)", "icon": "⛵", "cost": 40, "tech": "galley", "req_harbor": true},
		{"id": "quadrireme", "name": "Quadrireme (Rng 1)", "icon": "🛶", "cost": 50, "tech": "quadrireme", "req_harbor": true},
		{"id": "galleass", "name": "Galleass (Rng 2)", "icon": "🚢", "cost": 70, "tech": "galleass", "req_harbor": true},
		{"id": "musketman", "name": "Musketman (Melee Str 55)", "icon": "💂", "cost": 100, "tech": "gunpowder", "res": "niter"},
		{"id": "bombard", "name": "Bombard (Siege Rng 2)", "icon": "💣", "cost": 110, "tech": "siege_tactics", "res": "niter"},
		{"id": "cuirassier", "name": "Cuirassier (Heavy Cav Str 64)", "icon": "🏇", "cost": 120, "tech": "military_science", "res": "niter"},
		{"id": "frigate", "name": "Frigate (Naval Rng 2 Str 55)", "icon": "⛵", "cost": 115, "tech": "square_rigging", "res": "niter", "req_harbor": true},
		{"id": "spy", "name": "Spy (Covert Agent)", "icon": "🕵️", "cost": 75, "tech": "espionage", "is_spy": true},
		{"id": "barbarian_raider", "name": "Raider", "icon": "💀", "cost": 35},
		{"id": "barbarian_horseman", "name": "Barb Horseman", "icon": "🐴", "cost": 45, "res": "horses"},
		{"id": "walls", "name": "City Walls", "icon": "🧱", "cost": 40},
		{"id": "encampment", "name": "Military Encampment (+1⚙)", "icon": "⚔", "cost": 45, "tech_imp": "encampment"},
		{"id": "science_camp", "name": "Science Campus (+3🔬)", "icon": "🔬", "cost": 45, "tech_imp": "science_camp"},
		{"id": "market", "name": "Market (+4🪙)", "icon": "💰", "cost": 50, "tech_imp": "market"},
		{"id": "aqueduct", "name": "Aqueduct (+3🌾)", "icon": "💧", "cost": 55, "tech_imp": "aqueduct"},
		{"id": "neighborhood", "name": "Neighborhood (+4🏠)", "icon": "🏘", "cost": 55, "tech_imp": "neighborhood"},
		{"id": "castle", "name": "Castle (+50Fort)", "icon": "🏰", "cost": 75, "tech_imp": "castle"},
		{"id": "harbor", "name": "Harbor (+2🪙 +1⚙ +1🌾)", "icon": "⚓", "cost": 50, "tech_imp": "harbor"},
		{"id": "harvest_project", "name": "Harvest Festival (+30🌾)", "icon": "🌾", "cost": 30},
		{"id": "commercial_project", "name": "Commercial Invest (+40🪙)", "icon": "🪙", "cost": 30},
		{"id": "festival_project", "name": "Grand Festival (+20🌾 +25🪙)", "icon": "🎉", "cost": 40},
		{"id": "expand_border", "name": "Expand Border", "icon": "🏰", "cost": 25}
	]

	for item in options:
		var opt_id: String = item["id"]
		# Do not display already constructed unique city structures
		if opt_id == "walls" and city.has_walls:
			continue
		if opt_id == "market" and city.has_market:
			continue
		if opt_id == "aqueduct" and city.has_aqueduct:
			continue
		if opt_id == "castle" and city.has_castle:
			continue
		if opt_id == "encampment" and city.has_encampment:
			continue
		if opt_id == "science_camp" and city.has_science_camp:
			continue
		if opt_id == "neighborhood" and city.has_neighborhood:
			continue
		if opt_id == "harbor" and city.has_harbor:
			continue

		var cost: int = item["cost"]
		var est_turns: int = ceili(float(cost) / float(maxi(1, yields["production"])))

		# Check tech unlock for units
		if item.has("tech"):
			var tech_unit: String = item["tech"]
			if not game_state.tech_manager.is_tech_researched(city.faction_id, tech_unit) and not game_state.tech_manager.is_unit_unlocked(city.faction_id, tech_unit):
				continue

		# Check tech unlock for improvements/buildings
		if item.has("tech_imp"):
			var tech_imp: String = item["tech_imp"]
			if not game_state.tech_manager.is_improvement_unlocked(city.faction_id, tech_imp):
				continue

		# Check strategic resource requirement with Encampment discount (1 with Encampment, 2 without)
		var is_locked: bool = false
		var lock_msg: String = ""
		var req_amount = game_state.get_required_resource_amount_for_city(city)
		if item.has("res"):
			var req_res: String = item["res"]
			var count: int = strat_res.get(req_res, 0)
			if count < req_amount:
				is_locked = true
				lock_msg = " [🔒 Needs %d %s: %d/%d]" % [req_amount, req_res.capitalize(), count, req_amount]

		# Check building/district prerequisite (e.g. Military Engineer requires Encampment)
		if item.get("req_encampment", false) and not city.has_encampment:
			is_locked = true
			if lock_msg == "":
				lock_msg = " [🔒 Needs Encampment]"
			else:
				lock_msg += " [Needs Encampment]"

		# Check Harbor prerequisite for naval units
		if item.get("req_harbor", false) and not city.has_harbor:
			is_locked = true
			if lock_msg == "":
				lock_msg = " [🔒 Needs Harbor]"
			else:
				lock_msg += " [Needs Harbor]"

		# Check Spy capacity limit
		if item.get("is_spy", false):
			var esp_mgr = game_state.espionage_manager
			var can_spy = esp_mgr.can_produce_spy(city.faction_id) if esp_mgr else false
			if not can_spy:
				is_locked = true
				var cap = esp_mgr.get_spy_capacity(city.faction_id) if esp_mgr else 0
				var count = esp_mgr.get_spies(city.faction_id).size() if esp_mgr else 0
				if cap == 0:
					lock_msg = " [🔒 Needs Espionage Tech]"
				else:
					lock_msg = " [🔒 Capacity Limit (%d/%d)]" % [count, cap]

		var is_district_or_proj = opt_id in [
			"walls", "market", "aqueduct", "castle", "expand_border",
			"encampment", "science_camp", "neighborhood", "harbor",
			"harvest_project", "commercial_project", "festival_project"
		]
		var is_unit = not is_district_or_proj
		var is_district = opt_id in ["encampment", "science_camp", "neighborhood", "harbor", "market", "aqueduct", "castle"]

		# Check population requirement: city must remain at least pop 1
		var pop_cost = game_state.UNIT_POPULATION_COSTS.get(opt_id, 0)
		if is_unit and pop_cost > 0 and city.population <= pop_cost:
			is_locked = true
			if lock_msg == "":
				lock_msg = " [🔒 Needs Pop %d]" % [pop_cost + 1]
			else:
				lock_msg += " [Needs Pop %d]" % [pop_cost + 1]

		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 32)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 11)

		var is_active = (opt_id == city.current_production_id)
		var prefix = "✓ " if is_active else ""
		var pop_tag = " (-%d Pop)" % pop_cost if (is_unit and pop_cost > 0) else ""
		btn.text = "%s%s %s%s (%d⚙ • %dt)%s" % [prefix, item["icon"], item["name"], pop_tag, cost, est_turns, lock_msg]

		if is_locked:
			btn.disabled = true
			btn.modulate = Color(0.75, 0.45, 0.45)
		else:
			btn.pressed.connect(func():
				if is_district:
					hide_production_menu()
					start_district_placement_requested.emit(city, opt_id)
				else:
					if is_queue_mode and city.current_production_id != "":
						city.queue_production(opt_id)
						show_feedback("Added %s to %s queue (#%d)." % [item["name"], city.city_name, city.production_queue.size()], false)
					else:
						city.current_production_id = opt_id
						change_production_requested.emit(city.city_id, opt_id)
						if opt_id == "expand_border":
							show_feedback("Now committing %s to EXPAND BORDER." % city.city_name, false)
						elif opt_id == "walls":
							show_feedback("Now constructing City Walls in %s." % city.city_name, false)
						elif opt_id == "harvest_project":
							show_feedback("Now holding Harvest Festival in %s." % city.city_name, false)
						elif opt_id == "commercial_project":
							show_feedback("Now investing in Commercial Projects in %s." % city.city_name, false)
						elif opt_id == "festival_project":
							show_feedback("Now celebrating Grand Festival in %s." % city.city_name, false)
						else:
							show_feedback("Now training %s in %s." % [item["name"], city.city_name], false)
					show_production_menu.call_deferred(city)
					show_city_card.call_deferred(city)
			)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(btn)

		# Add +Q button for all non-districts
		if not is_district:
			var q_btn = Button.new()
			q_btn.text = "+Q"
			q_btn.custom_minimum_size = Vector2(30, 32)
			q_btn.add_theme_font_size_override("font_size", 10)
			q_btn.tooltip_text = "Add to production queue"
			q_btn.modulate = Color("85c1e9")
			if is_locked:
				q_btn.disabled = true
				q_btn.modulate = Color(0.6, 0.6, 0.6, 0.5)
			else:
				q_btn.pressed.connect(func():
					city.queue_production(opt_id)
					show_feedback("Added %s to %s queue (#%d)." % [item["name"], city.city_name, city.production_queue.size()], false)
					show_production_menu.call_deferred(city)
					show_city_card.call_deferred(city)
				)
			row.add_child(q_btn)

		if is_unit:
			var gold_cost = cost * 2
			var player_gold = game_state.faction_gold.get(city.faction_id, 0)
			var buy_btn = Button.new()
			buy_btn.text = "BUY 🪙%d" % gold_cost
			buy_btn.custom_minimum_size = Vector2(72, 32)
			buy_btn.clip_text = true
			buy_btn.add_theme_font_size_override("font_size", 10)
			if is_locked or player_gold < gold_cost:
				buy_btn.disabled = true
				buy_btn.modulate = Color(0.65, 0.65, 0.65, 0.6)
			else:
				buy_btn.modulate = Color("ffe082")
				buy_btn.pressed.connect(func():
					purchase_unit_requested.emit(city.city_id, opt_id)
				)
			row.add_child(buy_btn)

		prod_options_container.add_child(row)

func hide_production_menu() -> void:
	prod_menu.hide()

func show_tile_card(coords: Vector2i, tile_state: GridModel.TileState) -> void:
	if not tile_state:
		return
	active_unit_id = -1
	active_city_id = -1
	hide_production_menu()
	hp_box.hide()
	bottom_panel.show()

	var res_name = tile_state.resource_data.display_name if tile_state.resource_data else "None"
	var imp_name = tile_state.improvement_data.improvement_name if tile_state.improvement_data else "None"
	var sci_yield = tile_state.biome_data.yield_science + tile_state.natural_science

	var gold_yield = 0
	if tile_state.improvement_data != null:
		gold_yield += 1 # Base improvement gold
		if tile_state.resource_data != null:
			var req_tech = tile_state.resource_data.required_tech
			if req_tech == "" or game_state.tech_manager.is_tech_researched(GameEnums.FactionId.SOLARIS_DOMINION, req_tech):
				match tile_state.resource_data.id:
					"rice": gold_yield += 2
					"horses": gold_yield += 2
					"iron": gold_yield += 3
					"gold_ore": gold_yield += 4
					"gems": gold_yield += 5
					"niter": gold_yield += 3
		if "gold_bonus" in tile_state.improvement_data:
			gold_yield += tile_state.improvement_data.gold_bonus
	elif tile_state.resource_data != null and "gold_bonus" in tile_state.resource_data:
		gold_yield += tile_state.resource_data.gold_bonus

	card_title.text = "Tile (%d, %d): %s" % [coords.x, coords.y, tile_state.biome_data.biome_name]
	if tile_state.science_tag != "":
		card_title.text += " [%s]" % tile_state.science_tag
	card_title.modulate = Color("80d8ff") if tile_state.natural_science > 0 else Color.WHITE

	card_stats.text = "Move Cost: %d MP | Defense Bonus: +%d%% | Passable: %s" % [
		tile_state.biome_data.move_cost,
		tile_state.biome_data.defense_bonus_percent,
		"YES" if tile_state.biome_data.is_passable else "NO (Impassable)"
	]

	card_movement.text = "Yields: 🌾 %d Food | ⚙ %d Prod | 🔬 %d Sci | 🪙 %d Gold | %s | %s" % [
		tile_state.biome_data.yield_food,
		tile_state.biome_data.yield_production,
		sci_yield,
		gold_yield,
		res_name,
		imp_name
	]
	card_movement.modulate = Color("69f0ae")

	if tile_state.natural_science > 0:
		card_hint.text = "🔬 %s: Grants +%d Science to cities working this tile!" % [
			tile_state.science_tag, tile_state.natural_science
		]
		card_hint.modulate = Color("40c4ff")
	else:
		card_hint.text = "Move Settlers here to found cities, or send Builders to construct farms/mines."
		card_hint.modulate = Color(0.7, 0.7, 0.75)

	_clear_action_buttons()

func update_fortification_card(coords: Vector2i, imp: ImprovementData, attackable_tiles: Array[Vector2i]) -> void:
	bottom_panel.show()
	hp_box.show()
	hide_production_menu()
	active_unit_id = -1
	active_city_id = -1

	var is_encampment = (imp.improvement_type == GameEnums.ImprovementType.MILITARY_ENCAMPMENT)
	var fort_name = "MILITARY ENCAMPMENT" if is_encampment else "FORTIFIED OUTPOST CAMP"
	card_title.text = "🛡 %s (%d, %d)" % [fort_name, coords.x, coords.y]
	card_title.modulate = Color("3895d3")

	var m_hp = maxi(1, imp.max_health)
	hp_bar.max_value = m_hp
	hp_bar.value = imp.health
	var fort_str = " | Wall Fort: %d/%d" % [imp.fortification, imp.max_fortification] if (imp.has_walls and imp.max_fortification > 0) else " | No Walls"
	hp_text.text = "%d/%d HP%s" % [imp.health, m_hp, fort_str]

	var can_fire = not imp.has_bombarded_this_turn and (imp.has_walls or not is_encampment)
	var fire_status = "READY TO FIRE" if can_fire else ("ALREADY FIRED" if imp.has_bombarded_this_turn else "NEEDS WALLS")

	card_stats.text = "Health: %d/%d | Fortification: %d/%d | Strike Range: %d" % [
		imp.health, imp.max_health, imp.fortification, imp.max_fortification, imp.bombard_range
	]

	card_movement.text = "Bombard Strength: %d | Status: %s | Targets in Range: %d" % [
		imp.bombard_strength, fire_status, attackable_tiles.size()
	]
	card_movement.modulate = Color("2ecc71") if can_fire else Color("e74c3c")

	if can_fire and attackable_tiles.size() > 0:
		card_hint.text = "🏹 Tap a highlighted hostile unit within %d tiles to fire defensive bombardment!" % imp.bombard_range
		card_hint.modulate = Color("f1c40f")
	elif can_fire:
		card_hint.text = "Defensive bombardment ready. Waiting for hostile units within %d tiles." % imp.bombard_range
		card_hint.modulate = Color("80d8ff")
	elif is_encampment and not imp.has_walls:
		card_hint.text = "Construct City Walls in parent city to enable Encampment ranged bombardment and wall shield!"
		card_hint.modulate = Color(0.7, 0.7, 0.75)
	else:
		card_hint.text = "Defenses have already fired this turn. Resets on next turn."
		card_hint.modulate = Color(0.7, 0.7, 0.75)

	_clear_action_buttons()

func hide_bottom_card() -> void:
	bottom_panel.hide()
	hp_box.hide()
	hide_production_menu()
	active_unit_id = -1
	active_city_id = -1

func _clear_action_buttons() -> void:
	for child in action_button_box.get_children():
		child.queue_free()

func toggle_pause_menu() -> void:
	pause_modal.visible = not pause_modal.visible

func hide_pause_menu() -> void:
	pause_modal.hide()

func show_victory_screen(winning_faction_id: int) -> void:
	pause_modal.hide()
	victory_panel.show()
	if winning_faction_id == GameEnums.FactionId.SOLARIS_DOMINION:
		victory_title.text = "DOMINATION VICTORY!"
		victory_title.modulate = Color("2ecc71")
		victory_desc.text = "All rival civilizations and barbarian hordes have been eliminated.\nThe Solaris Dominion reigns absolute over the realm!"
	else:
		victory_title.text = "CIVILIZATION DEFEATED"
		victory_title.modulate = Color("e74c3c")
		victory_desc.text = "Your cities have fallen and your armies have perished.\nYour civilization is lost to history."
