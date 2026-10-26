extends RefCounted
## Pure expedition math: duration, reward modifiers and seeded reward rolls.

const Catalog = preload("res://scripts/data/game_catalog.gd")


static func expedition_duration(planet: Dictionary, parts: Dictionary) -> float:
	if planet.is_empty():
		return 0.0
	var engine: int = int(parts.get("engine", 1))
	var multiplier: float = clampf(1.0 - 0.04 * float(maxi(engine - 1, 0)), 0.6, 1.0)
	return maxf(5.0, float(planet.get("duration", 30.0)) * multiplier)


static func credits_multiplier(parts: Dictionary) -> float:
	return 1.0 + 0.05 * float(maxi(int(parts.get("power_core", 1)) - 1, 0))


static func rare_chance(planet: Dictionary, parts: Dictionary) -> float:
	if planet.is_empty():
		return 0.0
	var base: float = float(planet.get("rare_chance", 0.0))
	var bonus: float = 0.05 * float(maxi(int(parts.get("navigation", 1)) - 1, 0))
	return clampf(base + bonus, 0.0, 0.9)


static func max_items(planet: Dictionary, parts: Dictionary) -> int:
	if planet.is_empty():
		return 0
	var cargo_bonus: int = maxi(int(parts.get("cargo", 1)) - 1, 0)
	var hull_bonus: int = maxi(int(parts.get("hull", 1)) - 1, 0)
	return int(planet.get("items_max", 1)) + cargo_bonus + hull_bonus


## Deterministic loot roll: the same planet/parts/seed always yields the same
## rewards, which makes expeditions testable and prevents save-scumming.
static func roll_rewards(planet: Dictionary, parts: Dictionary, seed_value: int) -> Dictionary:
	if planet.is_empty():
		return {"credits": 0, "items": {}, "rare": false, "count": 0}

	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value)

	var credits: int = rng.randi_range(int(planet.get("credits_min", 0)), int(planet.get("credits_max", 0)))
	credits = int(round(float(credits) * credits_multiplier(parts)))

	var tier_ids: Array = Catalog.tier_ids(str(planet.get("family", "")))
	if tier_ids.is_empty():
		return {"credits": credits, "items": {}, "rare": false, "count": 0}

	var item_count: int = rng.randi_range(int(planet.get("items_min", 1)), maxi(max_items(planet, parts), int(planet.get("items_min", 1))))
	var chance: float = rare_chance(planet, parts)
	var rewards: Dictionary = {}
	var rare_found: bool = false

	for _i in item_count:
		var is_rare: bool = rng.randf() < chance
		var tier: int
		if is_rare:
			tier = rng.randi_range(3, tier_ids.size())
			rare_found = true
		else:
			tier = rng.randi_range(1, 2)
		tier = clampi(tier, 1, tier_ids.size())
		var item_id: String = str(tier_ids[tier - 1])
		rewards[item_id] = int(rewards.get(item_id, 0)) + 1

	return {
		"credits": credits,
		"items": rewards,
		"rare": rare_found,
		"count": item_count,
	}


## Requirements for a destination: {ok, missing: [{part, required, current}]}
static func requirements_status(planet: Dictionary, parts: Dictionary) -> Dictionary:
	if planet.is_empty():
		return {"ok": false, "missing": [{"part": "destination", "required": 1, "current": 0}]}
	var requirements: Dictionary = planet.get("requirements", {})
	var missing: Array = []
	for part_id in requirements:
		var required: int = int(requirements[part_id])
		var current: int = int(parts.get(part_id, 0))
		if current < required:
			var definition: Dictionary = Catalog.ship_part_def(str(part_id))
			missing.append({
				"part": part_id,
				"name": str(definition.get("name", part_id)),
				"required": required,
				"current": current,
			})
	return {"ok": missing.is_empty(), "missing": missing}
