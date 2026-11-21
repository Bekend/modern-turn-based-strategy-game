class_name DiplomacyManager
extends RefCounted

## Manages diplomatic relations, war/peace states, opinions, and economic trade deals between factions.

signal relation_changed(fac_a: int, fac_b: int, new_status: int)
signal trade_deal_signed(fac_a: int, fac_b: int, deal_type: String)
signal faction_met(fac_a: int, fac_b: int)

enum RelationStatus {
	PEACE = 0,
	WAR = 1
}

# relations[a][b] = { "status": int, "opinion": int, "open_borders": bool, "trade_turns": int }
var relations: Dictionary = {}

# Tracks which factions have discovered/met each other: met_factions[a][b] = true
var met_factions: Dictionary = {}

# Active resource export agreements: Array of { "seller": int, "buyer": int, "res_type": String, "turns_left": int }
var active_export_deals: Array[Dictionary] = []

func initialize(factions: Array[int]) -> void:
	relations.clear()
	met_factions.clear()
	active_export_deals.clear()
	for a in factions:
		relations[a] = {}
		met_factions[a] = {}
		for b in factions:
			if a == b:
				continue
			var status = RelationStatus.PEACE
			var opinion = 0
			# Barbarians are permanently at war with everyone
			if a == GameEnums.FactionId.BARBARIANS or b == GameEnums.FactionId.BARBARIANS:
				status = RelationStatus.WAR
				opinion = -100
			relations[a][b] = {
				"status": status,
				"opinion": opinion,
				"open_borders": false,
				"trade_turns": 0
			}

func has_met_faction(fac_a: int, fac_b: int) -> bool:
	if fac_a == fac_b:
		return true
	if met_factions.has(fac_a) and met_factions[fac_a].has(fac_b):
		return met_factions[fac_a][fac_b]
	return false

func meet_factions(fac_a: int, fac_b: int) -> bool:
	if fac_a == fac_b:
		return false
	if has_met_faction(fac_a, fac_b):
		return false
	if not met_factions.has(fac_a): met_factions[fac_a] = {}
	if not met_factions.has(fac_b): met_factions[fac_b] = {}
	met_factions[fac_a][fac_b] = true
	met_factions[fac_b][fac_a] = true
	faction_met.emit(fac_a, fac_b)
	return true

func get_relation(fac_a: int, fac_b: int) -> Dictionary:
	if relations.has(fac_a) and relations[fac_a].has(fac_b):
		return relations[fac_a][fac_b]
	return {"status": RelationStatus.PEACE, "opinion": 0, "open_borders": false, "trade_turns": 0}

func is_at_war(fac_a: int, fac_b: int) -> bool:
	return get_relation(fac_a, fac_b)["status"] == RelationStatus.WAR

func declare_war(fac_a: int, fac_b: int) -> void:
	if fac_a == fac_b:
		return
	_ensure_entry(fac_a, fac_b)
	relations[fac_a][fac_b]["status"] = RelationStatus.WAR
	relations[fac_b][fac_a]["status"] = RelationStatus.WAR
	relations[fac_a][fac_b]["opinion"] -= 40
	relations[fac_b][fac_a]["opinion"] -= 40

	# Break any active export deals between these belligerents
	var to_remove: Array[Dictionary] = []
	for deal in active_export_deals:
		if (deal["seller"] == fac_a and deal["buyer"] == fac_b) or (deal["seller"] == fac_b and deal["buyer"] == fac_a):
			to_remove.append(deal)
	for d in to_remove:
		active_export_deals.erase(d)

	relation_changed.emit(fac_a, fac_b, RelationStatus.WAR)

func make_peace(fac_a: int, fac_b: int) -> void:
	if fac_a == fac_b:
		return
	_ensure_entry(fac_a, fac_b)
	relations[fac_a][fac_b]["status"] = RelationStatus.PEACE
	relations[fac_b][fac_a]["status"] = RelationStatus.PEACE
	relations[fac_a][fac_b]["opinion"] += 15
	relations[fac_b][fac_a]["opinion"] += 15
	relation_changed.emit(fac_a, fac_b, RelationStatus.PEACE)

func start_trade_agreement(fac_a: int, fac_b: int, turns: int = 10) -> void:
	_ensure_entry(fac_a, fac_b)
	relations[fac_a][fac_b]["trade_turns"] = turns
	relations[fac_b][fac_a]["trade_turns"] = turns
	relations[fac_a][fac_b]["opinion"] += 20
	relations[fac_b][fac_a]["opinion"] += 20
	trade_deal_signed.emit(fac_a, fac_b, "trade_agreement")

func start_resource_export(seller: int, buyer: int, res_type: String, duration: int = 10) -> bool:
	if has_active_export(seller, buyer, res_type):
		return false
	active_export_deals.append({
		"seller": seller,
		"buyer": buyer,
		"res_type": res_type,
		"turns_left": duration
	})
	_ensure_entry(seller, buyer)
	relations[seller][buyer]["opinion"] += 10
	relations[buyer][seller]["opinion"] += 10
	trade_deal_signed.emit(seller, buyer, "export_" + res_type)
	return true

func has_active_export(seller: int, buyer: int, res_type: String) -> bool:
	for deal in active_export_deals:
		if deal["seller"] == seller and deal["buyer"] == buyer and deal["res_type"] == res_type:
			return true
	return false

func get_active_export(seller: int, buyer: int, res_type: String) -> Dictionary:
	for deal in active_export_deals:
		if deal["seller"] == seller and deal["buyer"] == buyer and deal["res_type"] == res_type:
			return deal
	return {}

func get_locked_resource_count(faction_id: int, res_type: String) -> int:
	var count = 0
	for deal in active_export_deals:
		if deal["seller"] == faction_id and deal["res_type"] == res_type:
			count += 1
	return count

func process_turn_deals(game_state: GameState) -> void:
	for a in relations.keys():
		for b in relations[a].keys():
			if a < b: # Process pair once
				var deal = relations[a][b]
				if deal["trade_turns"] > 0:
					deal["trade_turns"] -= 1
					relations[b][a]["trade_turns"] = deal["trade_turns"]
					game_state.faction_gold[a] = game_state.faction_gold.get(a, 0) + 2
					game_state.faction_gold[b] = game_state.faction_gold.get(b, 0) + 2

	# Process active export deals
	var expired_deals: Array[Dictionary] = []
	for deal in active_export_deals:
		deal["turns_left"] -= 1
		if deal["turns_left"] <= 0:
			expired_deals.append(deal)
	for exp_deal in expired_deals:
		active_export_deals.erase(exp_deal)

func _ensure_entry(a: int, b: int) -> void:
	if not relations.has(a): relations[a] = {}
	if not relations.has(b): relations[b] = {}
	if not relations[a].has(b):
		relations[a][b] = {"status": RelationStatus.PEACE, "opinion": 0, "open_borders": false, "trade_turns": 0}
	if not relations[b].has(a):
		relations[b][a] = {"status": RelationStatus.PEACE, "opinion": 0, "open_borders": false, "trade_turns": 0}
