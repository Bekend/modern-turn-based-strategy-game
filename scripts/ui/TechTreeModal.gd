class_name TechTreeModal
extends Control

## Grand Strategy Node-Based Technology Tree and Research Archive.
## Visualizes technology dependencies across Ancient, Classical, and Medieval Eras
## with drawn dependency lines, rich status cards, and interactive research commands.

signal tech_chosen(tech_id: String)
signal closed()

@onready var close_btn: Button = $Panel/HeaderBox/CloseButton
@onready var faction_science_label: Label = $Panel/HeaderBox/FactionScienceLabel
@onready var line_canvas: Control = find_child("LineCanvas", true, false)
@onready var card_container: Control = find_child("CardContainer", true, false)

# Inspector Panel Elements
@onready var glyph_label: Label = $Panel/InfoPanel/Margin/HBox/LeftBox/TitleBox/GlyphLabel
@onready var info_title: Label = $Panel/InfoPanel/Margin/HBox/LeftBox/TitleBox/TechTitle
@onready var status_badge: Label = $Panel/InfoPanel/Margin/HBox/LeftBox/StatusBadge
@onready var cost_label: Label = $Panel/InfoPanel/Margin/HBox/LeftBox/CostLabel
@onready var progress_bar: ProgressBar = $Panel/InfoPanel/Margin/HBox/LeftBox/ProgressBar
@onready var progress_text: Label = $Panel/InfoPanel/Margin/HBox/LeftBox/ProgressText

@onready var info_desc: Label = $Panel/InfoPanel/Margin/HBox/CenterBox/TechDesc
@onready var unlocks_flow: HFlowContainer = $Panel/InfoPanel/Margin/HBox/CenterBox/UnlocksFlow

@onready var research_btn: Button = $Panel/InfoPanel/Margin/HBox/RightBox/ResearchButton
@onready var prereq_label: Label = $Panel/InfoPanel/Margin/HBox/RightBox/PrereqLabel

# Era Banners
@onready var ancient_banner: PanelContainer = find_child("AncientEraBanner", true, false)
@onready var classical_banner: PanelContainer = find_child("ClassicalEraBanner", true, false)
@onready var medieval_banner: PanelContainer = find_child("MedievalEraBanner", true, false)
@onready var renaissance_banner: PanelContainer = find_child("RenaissanceEraBanner", true, false)

var tech_manager: TechTreeManager
var faction_id: int = GameEnums.FactionId.SOLARIS_DOMINION
var selected_tech_id: String = ""

const CARD_W: float = 172.0
const CARD_H: float = 96.0
const COL_DX: float = 188.0
const ROW_DY: float = 118.0
const OFFSET_X: float = 8.0
const OFFSET_Y: float = 10.0

const TECH_GLYPHS = {
	"agriculture": "🌾",
	"mining": "⛏",
	"archery": "🏹",
	"bronze_working": "🛡",
	"writing": "📜",
	"iron_working": "⚔",
	"horse_riding": "🐎",
	"sailing": "⛵",
	"shipbuilding": "🚢",
	"mathematics": "📐",
	"currency": "🪙",
	"construction": "🧱",
	"machinery": "⚙",
	"chivalry": "🛡",
	"feudalism": "👑",
	"gunpowder": "💥",
	"siege_tactics": "💣",
	"military_science": "⚔",
	"square_rigging": "⛵",
	"diplomatic_service": "🕊️"
}

func _ready() -> void:
	close_btn.pressed.connect(func():
		hide()
		closed.emit()
	)
	research_btn.pressed.connect(_on_research_pressed)
	line_canvas.draw.connect(_on_draw_lines)
	_style_era_banners()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			hide()
			closed.emit()
			get_viewport().set_input_as_handled()

func _style_era_banners() -> void:
	var sb_ancient = StyleBoxFlat.new()
	sb_ancient.bg_color = Color(0.45, 0.22, 0.05, 0.85)
	sb_ancient.border_color = Color(0.85, 0.55, 0.15, 0.9)
	sb_ancient.set_border_width_all(1)
	sb_ancient.set_corner_radius_all(3)
	if ancient_banner:
		ancient_banner.add_theme_stylebox_override("panel", sb_ancient)

	var sb_classical = StyleBoxFlat.new()
	sb_classical.bg_color = Color(0.08, 0.22, 0.48, 0.85)
	sb_classical.border_color = Color(0.25, 0.55, 0.95, 0.9)
	sb_classical.set_border_width_all(1)
	sb_classical.set_corner_radius_all(3)
	if classical_banner:
		classical_banner.add_theme_stylebox_override("panel", sb_classical)

	var sb_medieval = StyleBoxFlat.new()
	sb_medieval.bg_color = Color(0.28, 0.12, 0.48, 0.85)
	sb_medieval.border_color = Color(0.65, 0.35, 0.95, 0.9)
	sb_medieval.set_border_width_all(1)
	sb_medieval.set_corner_radius_all(3)
	if medieval_banner:
		medieval_banner.add_theme_stylebox_override("panel", sb_medieval)

	var sb_renaissance = StyleBoxFlat.new()
	sb_renaissance.bg_color = Color(0.48, 0.12, 0.18, 0.85)
	sb_renaissance.border_color = Color(0.95, 0.35, 0.45, 0.9)
	sb_renaissance.set_border_width_all(1)
	sb_renaissance.set_corner_radius_all(3)
	if renaissance_banner:
		renaissance_banner.add_theme_stylebox_override("panel", sb_renaissance)

func open(p_manager: TechTreeManager, p_faction_id: int) -> void:
	tech_manager = p_manager
	faction_id = p_faction_id
	show()
	_refresh_tree_view()

func _refresh_tree_view() -> void:
	for child in card_container.get_children():
		child.queue_free()

	if not tech_manager:
		return

	var researched = tech_manager.get_researched_techs(faction_id)
	var state = tech_manager.faction_tech_state.get(faction_id, {})
	var current_tech = state.get("current_tech_id", "")
	var accumulated = state.get("accumulated_science", 0)

	faction_science_label.text = "Solaris Dominion | Researched: %d / %d Techs" % [researched.size(), tech_manager.all_techs.size()]

	# Calculate max column to dynamically expand tree canvas and scroll bounds
	var max_col = 0
	for tid in tech_manager.all_techs.keys():
		var tech_obj: TechNode = tech_manager.all_techs[tid]
		if tech_obj.tree_column > max_col:
			max_col = tech_obj.tree_column

	var needed_width = maxf(1780.0, OFFSET_X + (max_col + 1) * COL_DX + 60.0)
	var tree_content = find_child("TreeContent", true, false)
	if tree_content:
		tree_content.custom_minimum_size = Vector2(needed_width, 360)
	var era_bar = find_child("EraBar", true, false)
	if era_bar:
		era_bar.offset_right = needed_width - 10.0
	var tree_canvas = find_child("TreeCanvas", true, false)
	if tree_canvas:
		tree_canvas.offset_right = needed_width - 10.0

	# Place all cards at exact graph coordinates
	for tid in tech_manager.all_techs.keys():
		var tech: TechNode = tech_manager.all_techs[tid]
		var card = _create_tech_card(tech, researched, current_tech, accumulated)
		var px = OFFSET_X + tech.tree_column * COL_DX
		var py = OFFSET_Y + tech.tree_row * ROW_DY
		card.position = Vector2(px, py)
		card.size = Vector2(CARD_W, CARD_H)
		card_container.add_child(card)

	# Ensure a valid selection
	if selected_tech_id == "" or not tech_manager.all_techs.has(selected_tech_id):
		if current_tech != "":
			selected_tech_id = current_tech
		else:
			selected_tech_id = "mining"

	if tech_manager.all_techs.has(selected_tech_id):
		_select_tech(tech_manager.all_techs[selected_tech_id])

	line_canvas.queue_redraw()

func _create_tech_card(tech: TechNode, researched: Array, current_tech: String, accumulated: int) -> Control:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.clip_contents = true

	var tid = tech.tech_id
	var is_mastered = researched.has(tid)
	var is_current = (tid == current_tech)
	var can_research = tech_manager.can_research_tech(faction_id, tid)
	var is_selected = (tid == selected_tech_id)

	# Card StyleBox
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(6)

	var glyph = TECH_GLYPHS.get(tid, "🔬")
	var status_tag = ""

	if is_mastered:
		sb.bg_color = Color(0.04, 0.20, 0.12, 0.92)
		sb.border_color = Color(0.15, 0.85, 0.45, 0.95)
		sb.set_border_width_all(2 if not is_selected else 3)
		status_tag = "✓ MASTERED"
	elif is_current:
		sb.bg_color = Color(0.08, 0.22, 0.38, 0.95)
		sb.border_color = Color(0.20, 0.75, 1.0, 1.0)
		sb.set_border_width_all(2 if not is_selected else 3)
		status_tag = "🔬 ACTIVE (%d/%d)" % [accumulated, tech.science_cost]
	elif can_research:
		sb.bg_color = Color(0.12, 0.16, 0.24, 0.92)
		sb.border_color = Color(0.95, 0.72, 0.15, 0.90)
		sb.set_border_width_all(2 if not is_selected else 3)
		status_tag = "READY (%d🔬)" % tech.science_cost
	else:
		sb.bg_color = Color(0.07, 0.09, 0.14, 0.85)
		sb.border_color = Color(0.25, 0.30, 0.40, 0.60)
		sb.set_border_width_all(1 if not is_selected else 3)
		status_tag = "🔒 LOCKED"

	if is_selected:
		sb.border_color = Color(1.0, 0.85, 0.2, 1.0) # Golden selection glow
		sb.shadow_size = 3
		sb.shadow_color = Color(1.0, 0.85, 0.2, 0.4)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

	# Content layout inside card
	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)

	# Row 1: Glyph & Name
	var r1 = HBoxContainer.new()
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r1.add_theme_constant_override("separation", 4)
	var g_lbl = Label.new()
	g_lbl.text = glyph
	g_lbl.add_theme_font_size_override("font_size", 13)
	r1.add_child(g_lbl)

	var name_lbl = Label.new()
	name_lbl.text = tech.title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.clip_text = false
	r1.add_child(name_lbl)
	vbox.add_child(r1)

	# Row 2: Status & Cost
	var status_lbl = Label.new()
	status_lbl.text = status_tag
	status_lbl.add_theme_font_size_override("font_size", 10)
	if is_mastered:
		status_lbl.modulate = Color(0.3, 1.0, 0.5)
	elif is_current:
		status_lbl.modulate = Color(0.3, 0.85, 1.0)
	elif can_research:
		status_lbl.modulate = Color(1.0, 0.85, 0.3)
	else:
		status_lbl.modulate = Color(0.6, 0.65, 0.7)
	vbox.add_child(status_lbl)

	# Row 3: Progress Bar or Unlock Preview
	if is_current:
		var pbar = ProgressBar.new()
		pbar.show_percentage = false
		pbar.custom_minimum_size = Vector2(0, 8)
		pbar.max_value = float(maxi(1, tech.science_cost))
		pbar.value = float(accumulated)
		var p_sb = StyleBoxFlat.new()
		p_sb.bg_color = Color(0.2, 0.75, 1.0)
		p_sb.set_corner_radius_all(3)
		pbar.add_theme_stylebox_override("fill", p_sb)
		vbox.add_child(pbar)
	else:
		var preview = _get_micro_unlock_summary(tech)
		if preview != "":
			var prev_lbl = Label.new()
			prev_lbl.text = preview
			prev_lbl.add_theme_font_size_override("font_size", 9)
			prev_lbl.modulate = Color(0.75, 0.8, 0.85)
			prev_lbl.clip_text = true
			vbox.add_child(prev_lbl)

	margin.add_child(vbox)
	btn.add_child(margin)

	btn.pressed.connect(func():
		_select_tech(tech)
		_refresh_tree_view()
	)

	return btn

func _get_micro_unlock_summary(tech: TechNode) -> String:
	var items: Array[String] = []
	for u in tech.unlocked_units:
		items.append("+" + u.capitalize())
	for imp in tech.unlocked_improvements:
		items.append("+" + imp.capitalize())
	if tech.reveals_strategic_resource != "":
		items.append("+" + tech.reveals_strategic_resource.capitalize())
	if tech.tech_id == "shipbuilding":
		items.append("+Embark")
	if tech.tech_id == "diplomatic_service":
		items.append("+1 Spy Cap")
	if items.is_empty():
		return ""
	return ", ".join(items)

func _select_tech(tech: TechNode) -> void:
	selected_tech_id = tech.tech_id
	var era_str = tech.era if "era" in tech else "Ancient"
	var glyph = TECH_GLYPHS.get(tech.tech_id, "🔬")

	glyph_label.text = glyph
	info_title.text = "%s [%s Era]" % [tech.title.to_upper(), era_str.to_upper()]
	info_desc.text = tech.description

	var researched = tech_manager.is_tech_researched(faction_id, selected_tech_id)
	var can_research = tech_manager.can_research_tech(faction_id, selected_tech_id)
	var state = tech_manager.faction_tech_state.get(faction_id, {})
	var current_tech = state.get("current_tech_id", "")
	var accumulated = state.get("accumulated_science", 0)

	# Research Progress & Status Badge
	if researched:
		status_badge.text = "STATUS: [✓ TECHNOLOGY MASTERED]"
		status_badge.modulate = Color(0.25, 0.95, 0.45)
		cost_label.text = "Science Cost: %d 🔬 (Completed)" % tech.science_cost
		progress_bar.value = 100.0
		progress_text.text = "All knowledge mastered and perks active across your empire."
		research_btn.disabled = true
		research_btn.text = "TECHNOLOGY MASTERED ✓"
		prereq_label.text = "Research Completed ✓"
		prereq_label.modulate = Color(0.3, 0.9, 0.4)
	elif selected_tech_id == current_tech:
		status_badge.text = "STATUS: [🔬 CURRENT RESEARCH PROJECT]"
		status_badge.modulate = Color(0.25, 0.80, 1.0)
		var turns_left = maxi(1, ceili(float(tech.science_cost - accumulated) / 5.0))
		cost_label.text = "Science Cost: %d 🔬  •  Estimated: %d Turn(s) Left" % [tech.science_cost, turns_left]
		progress_bar.max_value = float(maxi(1, tech.science_cost))
		progress_bar.value = float(accumulated)
		progress_text.text = "Progress: %d / %d 🔬 (%d%% Completed)" % [
			accumulated, tech.science_cost, int(float(accumulated) / float(maxi(1, tech.science_cost)) * 100.0)
		]
		research_btn.disabled = true
		research_btn.text = "CURRENTLY ACTIVE 🔬"
		prereq_label.text = "Active in Research Labs"
		prereq_label.modulate = Color(0.4, 0.8, 1.0)
	elif can_research:
		status_badge.text = "STATUS: [AVAILABLE TO RESEARCH]"
		status_badge.modulate = Color(1.0, 0.85, 0.25)
		var turns_left = maxi(1, ceili(float(tech.science_cost) / 5.0))
		cost_label.text = "Science Cost: %d 🔬  •  Estimated: ~%d Turn(s)" % [tech.science_cost, turns_left]
		progress_bar.max_value = float(maxi(1, tech.science_cost))
		progress_bar.value = 0.0
		progress_text.text = "Ready to start! Tap 'COMMENCE RESEARCH' to begin."
		research_btn.disabled = false
		research_btn.text = "COMMENCE RESEARCH 🔬"
		prereq_label.text = "Prerequisites Mastered ✓"
		prereq_label.modulate = Color(0.3, 0.9, 0.4)
	else:
		status_badge.text = "STATUS: [🔒 LOCKED - PREREQUISITES REQUIRED]"
		status_badge.modulate = Color(0.8, 0.4, 0.4)
		cost_label.text = "Science Cost: %d 🔬  •  Requires Unlocked Prerequisites" % tech.science_cost
		progress_bar.value = 0.0
		progress_text.text = "Research locked until prerequisite technologies are completed."
		research_btn.disabled = true
		research_btn.text = "LOCKED 🔒"

		var missing: Array[String] = []
		for req_id in tech.prerequisites:
			if not tech_manager.is_tech_researched(faction_id, req_id):
				var r_name = req_id.capitalize()
				var r_obj = tech_manager.all_techs.get(req_id, null)
				if r_obj: r_name = r_obj.title
				missing.append(r_name)
		prereq_label.text = "Requires: %s" % ", ".join(missing)
		prereq_label.modulate = Color(0.9, 0.4, 0.4)

	# Categorized Unlocks
	for child in unlocks_flow.get_children():
		child.queue_free()

	# 1. Military Units (Crimson / Red)
	for u in tech.unlocked_units:
		var u_badge = _create_chip("🏹 UNIT: " + u.capitalize(), Color(0.85, 0.25, 0.25))
		unlocks_flow.add_child(u_badge)

	# 2. Buildings & Structures (Amber / Orange)
	for imp in tech.unlocked_improvements:
		var imp_name = imp.replace("_", " ").capitalize()
		var imp_badge = _create_chip("🏛 STRUCTURE: " + imp_name, Color(0.95, 0.65, 0.15))
		unlocks_flow.add_child(imp_badge)

	# 3. Strategic Resources (Teal / Cyan)
	if tech.reveals_strategic_resource != "":
		var res_badge = _create_chip("💎 RESOURCE: " + tech.reveals_strategic_resource.capitalize(), Color(0.15, 0.85, 0.85))
		unlocks_flow.add_child(res_badge)

	# 4. Empire Perks (Purple)
	if tech.highland_move_cost_reduction > 0:
		var perk_badge = _create_chip("⚡ PERK: Highland Move Cost -1", Color(0.75, 0.45, 0.95))
		unlocks_flow.add_child(perk_badge)
	if tech.melee_attack_bonus_percent > 0:
		var perk_badge2 = _create_chip("⚔ PERK: +%d%% Melee Attack" % tech.melee_attack_bonus_percent, Color(0.95, 0.35, 0.55))
		unlocks_flow.add_child(perk_badge2)
	if tech.tech_id == "shipbuilding":
		var perk_badge_embark = _create_chip("⚓ PERK: Land Units Water Embarkation", Color(0.2, 0.7, 1.0))
		unlocks_flow.add_child(perk_badge_embark)
	if tech.tech_id == "diplomatic_service":
		var perk_badge_spy = _create_chip("🕵️ PERK: +1 Spy Capacity & Foreign Missions", Color(0.3, 0.75, 1.0))
		unlocks_flow.add_child(perk_badge_spy)

	if unlocks_flow.get_child_count() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "Foundational scientific knowledge for future eras."
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.modulate = Color(0.65, 0.7, 0.75)
		unlocks_flow.add_child(empty_lbl)

func _create_chip(text: String, color: Color) -> PanelContainer:
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.85)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	pc.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 2)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = color
	margin.add_child(lbl)
	pc.add_child(margin)
	return pc

func _on_draw_lines() -> void:
	if not tech_manager:
		return

	var researched = tech_manager.get_researched_techs(faction_id)
	var current_tech = tech_manager.faction_tech_state.get(faction_id, {}).get("current_tech_id", "")

	for tid in tech_manager.all_techs.keys():
		var child_tech: TechNode = tech_manager.all_techs[tid]
		var c_x = OFFSET_X + child_tech.tree_column * COL_DX
		var c_y = OFFSET_Y + child_tech.tree_row * ROW_DY + CARD_H * 0.5
		var end_pt = Vector2(c_x, c_y)

		for parent_id in child_tech.prerequisites:
			var parent_tech = tech_manager.all_techs.get(parent_id, null)
			if not parent_tech:
				continue

			var p_x = OFFSET_X + parent_tech.tree_column * COL_DX + CARD_W
			var p_y = OFFSET_Y + parent_tech.tree_row * ROW_DY + CARD_H * 0.5
			var start_pt = Vector2(p_x, p_y)

			# Determine line color
			var is_parent_researched = researched.has(parent_id)
			var is_child_researched = researched.has(tid)
			var is_child_active = (tid == current_tech)
			var can_child = tech_manager.can_research_tech(faction_id, tid)

			var line_color: Color
			var line_width: float = 2.0

			if is_parent_researched and is_child_researched:
				line_color = Color(0.20, 0.85, 0.45, 0.85) # Researched emerald
				line_width = 2.5
			elif is_child_active:
				line_color = Color(0.25, 0.80, 1.0, 0.9) # Active cyan
				line_width = 2.5
			elif is_parent_researched and can_child:
				line_color = Color(0.95, 0.75, 0.2, 0.7) # Available amber
				line_width = 2.0
			else:
				line_color = Color(0.30, 0.35, 0.45, 0.35) # Dim slate
				line_width = 1.5

			# Draw orthogonal elbow connection
			var mid_x = (start_pt.x + end_pt.x) * 0.5
			var points = PackedVector2Array([
				start_pt,
				Vector2(mid_x, start_pt.y),
				Vector2(mid_x, end_pt.y),
				end_pt
			])
			line_canvas.draw_polyline(points, line_color, line_width, true)

			# Draw socket circle at target
			line_canvas.draw_circle(end_pt, 3.0, line_color)

func _on_research_pressed() -> void:
	if selected_tech_id != "" and tech_manager.can_research_tech(faction_id, selected_tech_id):
		tech_manager.set_current_research(faction_id, selected_tech_id)
		tech_chosen.emit(selected_tech_id)
		_refresh_tree_view()
