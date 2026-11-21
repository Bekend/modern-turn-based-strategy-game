class_name CombatEngine
extends RefCounted

## Deterministic Combat Engine computing military engagements, terrain modifiers,
## ranged bombardment, and city fortification sieges.

const BASE_DAMAGE: float = 30.0
const STRENGTH_EXPONENT: float = 1.25

## Result container for combat calculation
class CombatResult:
	var attacker_damage_dealt: int = 0
	var defender_damage_dealt: int = 0
	var defender_died: bool = false
	var attacker_died: bool = false
	var city_captured: bool = false
	var remaining_attacker_hp: int = 0
	var remaining_defender_hp: int = 0
	var fort_damage: int = 0
	var city_hp_damage: int = 0

## Resolves deterministic melee combat between two field units
static func resolve_unit_melee(
	attacker_strength: int,
	attacker_hp: int,
	defender_strength: int,
	defender_hp: int,
	defender_terrain_bonus_percent: int,
	attacker_faction_bonus_percent: int = 0
) -> CombatResult:
	var result = CombatResult.new()

	# Health scaling: Damaged units have slightly reduced combat effectiveness
	var att_hp_ratio = float(attacker_hp) / 100.0
	var def_hp_ratio = float(defender_hp) / 100.0

	var eff_att_strength = float(attacker_strength) * (0.6 + 0.4 * att_hp_ratio) * (1.0 + float(attacker_faction_bonus_percent) / 100.0)
	var eff_def_strength = float(defender_strength) * (0.6 + 0.4 * def_hp_ratio) * (1.0 + float(defender_terrain_bonus_percent) / 100.0)

	eff_att_strength = maxf(1.0, eff_att_strength)
	eff_def_strength = maxf(1.0, eff_def_strength)

	var ratio = eff_att_strength / eff_def_strength

	# Attacker deals damage to defender
	var raw_att_dmg = BASE_DAMAGE * pow(ratio, STRENGTH_EXPONENT)
	var att_dmg = int(clampf(roundf(raw_att_dmg), 5.0, 100.0))

	# Defender deals retaliation damage to attacker
	var raw_def_dmg = BASE_DAMAGE * pow(1.0 / ratio, STRENGTH_EXPONENT)
	var def_dmg = int(clampf(roundf(raw_def_dmg), 5.0, 100.0))

	result.attacker_damage_dealt = att_dmg
	result.defender_damage_dealt = def_dmg

	result.remaining_defender_hp = maxi(0, defender_hp - att_dmg)
	result.remaining_attacker_hp = maxi(0, attacker_hp - def_dmg)

	result.defender_died = result.remaining_defender_hp <= 0
	result.attacker_died = result.remaining_attacker_hp <= 0

	return result

## Resolves ranged attack (no retaliation against the shooter)
static func resolve_ranged_attack(
	attacker_ranged_strength: int,
	attacker_hp: int,
	defender_strength: int,
	defender_hp: int,
	defender_terrain_bonus_percent: int
) -> CombatResult:
	var result = CombatResult.new()

	var att_hp_ratio = float(attacker_hp) / 100.0
	var def_hp_ratio = float(defender_hp) / 100.0

	var eff_att = float(attacker_ranged_strength) * (0.6 + 0.4 * att_hp_ratio)
	var eff_def = float(defender_strength) * (0.6 + 0.4 * def_hp_ratio) * (1.0 + float(defender_terrain_bonus_percent) / 100.0)

	eff_att = maxf(1.0, eff_att)
	eff_def = maxf(1.0, eff_def)

	var ratio = eff_att / eff_def
	var raw_dmg = BASE_DAMAGE * 0.85 * pow(ratio, STRENGTH_EXPONENT)
	var damage = int(clampf(roundf(raw_dmg), 4.0, 100.0))

	result.attacker_damage_dealt = damage
	result.defender_damage_dealt = 0 # No retaliation for ranged!
	result.remaining_attacker_hp = attacker_hp
	result.remaining_defender_hp = maxi(0, defender_hp - damage)
	result.defender_died = result.remaining_defender_hp <= 0
	result.attacker_died = false

	return result

## Resolves unit attacking a city (Siege combat with Fortification absorption)
static func resolve_city_siege(
	attacker_strength: int,
	attacker_hp: int,
	city_data: CityData,
	is_ranged: bool = false
) -> CombatResult:
	var result = CombatResult.new()

	var city_defense = maxf(1.0, float(city_data.get_effective_defense_strength()))
	var att_hp_ratio = float(attacker_hp) / 100.0

	var eff_att = float(attacker_strength) * (0.6 + 0.4 * att_hp_ratio)
	var ratio = clampf(eff_att / city_defense, 0.05, 20.0)

	var raw_dmg = BASE_DAMAGE * (0.7 if is_ranged else 1.0) * pow(ratio, STRENGTH_EXPONENT)
	var total_damage = int(clampf(roundf(raw_dmg), 6.0, 100.0))

	result.attacker_damage_dealt = total_damage

	# Retaliation from city garrison if melee
	if not is_ranged:
		var raw_retaliation = BASE_DAMAGE * 0.75 * pow(1.0 / ratio, STRENGTH_EXPONENT)
		var retal_dmg = int(clampf(roundf(raw_retaliation), 5.0, 80.0))
		result.defender_damage_dealt = retal_dmg
		result.remaining_attacker_hp = maxi(0, attacker_hp - retal_dmg)
		result.attacker_died = result.remaining_attacker_hp <= 0
	else:
		result.defender_damage_dealt = 0
		result.remaining_attacker_hp = attacker_hp
		result.attacker_died = false

	# Apply damage to city: Fortification absorbs first!
	var dmg_packet = city_data.take_damage(total_damage)
	result.fort_damage = dmg_packet["absorbed_by_fort"]
	result.city_hp_damage = dmg_packet["absorbed_by_hp"]
	result.city_captured = dmg_packet["is_conquered"]
	result.remaining_defender_hp = city_data.health

	return result
