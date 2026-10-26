extends RefCounted
## Pure economy formulas: generator rates, prices, board expansion, ship costs.

const Catalog = preload("res://scripts/data/game_catalog.gd")


static func generator_interval(definition: Dictionary, level: int) -> float:
	if definition.is_empty() or level <= 0:
		return 0.0
	var scale: float = float(definition.get("interval_scale", 0.9))
	return maxf(2.0, float(definition.get("base_interval", 10.0)) * pow(scale, level - 1))


static func generator_rate_per_minute(definition: Dictionary, level: int, multiplier: float = 1.0) -> float:
	var interval: float = generator_interval(definition, level)
	if interval <= 0.0:
		return 0.0
	return 60.0 / interval * multiplier


static func generator_capacity(definition: Dictionary, level: int) -> int:
	if definition.is_empty() or level <= 0:
		return 0
	return int(definition.get("capacity_base", 4)) + int(definition.get("capacity_per_level", 2)) * (level - 1)


## Cost of the purchase that takes `level` to `level + 1`. Level 0 means the
## machine has not been built yet, so this is also the install price.
static func generator_upgrade_cost(definition: Dictionary, level: int) -> int:
	if definition.is_empty():
		return 0
	var base: float = float(definition.get("base_cost", 50))
	var growth: float = float(definition.get("cost_growth", 1.6))
	# Installing (level 0) and the first upgrade both cost the base price, then
	# every further level grows by `cost_growth`.
	return int(round(base * pow(growth, maxi(level - 1, 0))))


static func generator_requirements_met(definition: Dictionary, levels: Dictionary) -> bool:
	var requires: Dictionary = definition.get("requires", {})
	for generator_id in requires:
		if int(levels.get(generator_id, 0)) < int(requires[generator_id]):
			return false
	return true


static func generator_requirement_text(definition: Dictionary) -> String:
	var requires: Dictionary = definition.get("requires", {})
	var parts: Array[String] = []
	for generator_id in requires:
		var required_def: Dictionary = Catalog.generator_def(str(generator_id))
		var required_level: int = int(requires[generator_id])
		parts.append("%s Lv %d" % [str(required_def.get("short", generator_id)), required_level])
	return ", ".join(parts)


static func expansion_cost(index: int) -> int:
	if index < 0 or index >= Catalog.BOARD_EXPANSIONS.size():
		return 0
	return int(Catalog.BOARD_EXPANSIONS[index]["cost"])


static func expansion_rows(index: int) -> int:
	if index < 0 or index >= Catalog.BOARD_EXPANSIONS.size():
		return Catalog.BOARD_START_ROWS
	return int(Catalog.BOARD_EXPANSIONS[index]["rows"])


## Returns {credits, items, effect} for the next level of a ship part, or an
## empty dictionary when the component is already maxed.
static func part_upgrade_cost(definition: Dictionary, level: int) -> Dictionary:
	if definition.is_empty() or level < 1 or level >= int(definition.get("max_level", Catalog.PART_MAX_LEVEL)):
		return {}
	var upgrades: Array = definition.get("upgrades", [])
	var index: int = level - 1
	if index < 0 or index >= upgrades.size():
		return {}
	var entry: Dictionary = upgrades[index]
	return {
		"credits": int(entry.get("credits", 0)),
		"items": (entry.get("items", {}) as Dictionary).duplicate(),
		"effect": str(entry.get("effect", "")),
	}


## Human readable summary of what a component currently provides.
static func part_current_effect(definition: Dictionary, level: int) -> String:
	if definition.is_empty():
		return ""
	if level <= 1:
		return "Basic installed unit"
	var upgrades: Array = definition.get("upgrades", [])
	var index: int = level - 2
	if index < 0 or index >= upgrades.size():
		return "Basic installed unit"
	return str(upgrades[index].get("effect", ""))
