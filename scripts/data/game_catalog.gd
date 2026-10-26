extends RefCounted
## Central, data-driven configuration for Scrap to Space.
##
## Everything tunable lives here: merge chains, generator upgrades, board
## expansions, ship components, destinations, tutorial steps and economy
## constants. Gameplay scripts read this data through the static helpers at the
## bottom of the file, so new items / chains / destinations can be added without
## touching merge logic.

const SAVE_VERSION := 1

# --- Economy / board tuning -------------------------------------------------
const STARTING_CREDITS := 100
const BOARD_COLUMNS := 5
const BOARD_START_ROWS := 6
const MAX_GENERATOR_LEVEL := 12
const PART_MAX_LEVEL := 5
const ORDER_SLOTS := 3
const OFFLINE_CAP_SECONDS := 7200.0  # 2 hours of offline production
const PRODUCTION_BOOST_SECONDS := 300.0
const PRODUCTION_BOOST_MULTIPLIER := 2.0
const MAX_BOARD_ROWS := 8

# Rarity colours by tier (index 0 == tier 1).
const RARITY_COLORS := [
	Color("#8f9dbd"),
	Color("#5fd97a"),
	Color("#4aa8ff"),
	Color("#b06bff"),
	Color("#ffc94a"),
	Color("#ff7a9c"),
	Color("#43e8ff"),
	Color("#ffffff"),
]

# --- Merge chains -----------------------------------------------------------
# Each family defines an ordered chain of tiers. Two identical items of the same
# family and tier merge into the next tier of that chain.
const FAMILY_DEFS := {
	"circuit": {
		"label": "Electronics",
		"short": "CIRCUIT",
		"base_value": 5.0,
		"value_growth": 2.3,
		"shape": "chip",
		"tiers": [
			["broken_circuit", "Broken Circuit"],
			["repaired_circuit", "Repaired Circuit"],
			["electronic_module", "Electronic Module"],
			["processing_unit", "Processing Unit"],
			["advanced_processor", "Advanced Processor"],
			["navigation_computer", "Navigation Computer"],
			["quantum_core", "Quantum Core"],
			["warp_drive", "Warp Drive Component"],
		],
	},
	"alloy": {
		"label": "Mechanic",
		"short": "ALLOY",
		"base_value": 7.0,
		"value_growth": 2.1,
		"shape": "plate",
		"tiers": [
			["rusted_plate", "Rusted Plate"],
			["scrap_alloy", "Scrap Alloy"],
			["reinforced_panel", "Reinforced Panel"],
			["hardened_hull", "Hardened Hull Plate"],
			["titanium_composite", "Titanium Composite"],
		],
	},
	"quantum": {
		"label": "Quantum",
		"short": "QUANTUM",
		"base_value": 12.0,
		"value_growth": 2.2,
		"shape": "crystal",
		"tiers": [
			["flickering_shard", "Flickering Shard"],
			["neon_cell", "Neon Cell"],
			["photon_relay", "Photon Relay"],
			["prism_matrix", "Prism Matrix"],
			["singularity_lens", "Singularity Lens"],
		],
	},
}

# --- Production upgrades ----------------------------------------------------
# level 0 means "not built yet"; the first purchase installs the machine.
const GENERATOR_DEFS := [
	{
		"id": "collector",
		"name": "Manual Scrap Collector",
		"short": "Collector",
		"item": "broken_circuit",
		"base_cost": 50,
		"cost_growth": 1.6,
		"base_interval": 12.0,
		"interval_scale": 0.9,
		"capacity_base": 6,
		"capacity_per_level": 4,
		"requires": {},
		"blurb": "Hand-cranked bin that feeds broken circuits onto your board.",
	},
	{
		"id": "sorter",
		"name": "Automated Sorting Machine",
		"short": "Sorter",
		"item": "rusted_plate",
		"base_cost": 320,
		"cost_growth": 1.65,
		"base_interval": 18.0,
		"interval_scale": 0.91,
		"capacity_base": 5,
		"capacity_per_level": 3,
		"requires": {"collector": 3},
		"blurb": "Sorts hull plates out of the junkyard rubble.",
	},
	{
		"id": "arm",
		"name": "Robotic Salvage Arm",
		"short": "Salvage Arm",
		"item": "flickering_shard",
		"base_cost": 1200,
		"cost_growth": 1.7,
		"base_interval": 26.0,
		"interval_scale": 0.92,
		"capacity_base": 4,
		"capacity_per_level": 3,
		"requires": {"sorter": 3},
		"blurb": "Reaches into the wreck field for unstable quantum shards.",
	},
]

# Extra rows purchasable for the merge board, in order.
const BOARD_EXPANSIONS := [
	{"cost": 400, "rows": 7},
	{"cost": 1500, "rows": 8},
]

# --- Spaceship --------------------------------------------------------------
const SHIP_PART_DEFS := [
	{
		"id": "hull",
		"name": "Hull",
		"color": Color("#7fa8ff"),
		"blurb": "Thick plating that survives rough landings.",
		"upgrades": [
			{"credits": 150, "items": {}, "effect": "Ship frame stabilised"},
			{"credits": 500, "items": {"rusted_plate": 2}, "effect": "+1 cargo pod"},
			{"credits": 1600, "items": {"scrap_alloy": 2}, "effect": "+2 cargo pods"},
			{"credits": 4500, "items": {"reinforced_panel": 1}, "effect": "+3 cargo pods"},
		],
	},
	{
		"id": "engine",
		"name": "Engine",
		"color": Color("#ff9a5a"),
		"blurb": "Speed matters when the scrap field is drifting away.",
		"upgrades": [
			{"credits": 220, "items": {"repaired_circuit": 1}, "effect": "Unlocks basic travel"},
			{"credits": 650, "items": {"electronic_module": 1}, "effect": "-4% travel time per level"},
			{"credits": 2000, "items": {"processing_unit": 1}, "effect": "-8% travel time per level"},
			{"credits": 6000, "items": {"advanced_processor": 1}, "effect": "Rustfall class engine"},
		],
	},
	{
		"id": "power_core",
		"name": "Power Core",
		"color": Color("#43e8ff"),
		"blurb": "Powers navigation arrays and quantum tooling.",
		"upgrades": [
			{"credits": 300, "items": {"electronic_module": 1}, "effect": "+5% expedition credits"},
			{"credits": 900, "items": {"processing_unit": 1}, "effect": "+10% expedition credits"},
			{"credits": 2600, "items": {"advanced_processor": 1}, "effect": "+15% expedition credits"},
			{"credits": 7000, "items": {"quantum_core": 1}, "effect": "+20% expedition credits"},
		],
	},
	{
		"id": "navigation",
		"name": "Navigation System",
		"color": Color("#b06bff"),
		"blurb": "Plotting a jump through the wreck belt is not optional.",
		"upgrades": [
			{"credits": 260, "items": {"repaired_circuit": 2}, "effect": "+5% rare salvage chance"},
			{"credits": 800, "items": {"processing_unit": 1}, "effect": "+10% rare salvage chance"},
			{"credits": 2400, "items": {"navigation_computer": 1}, "effect": "Neon Moon coordinates"},
			{"credits": 6800, "items": {"quantum_core": 1}, "effect": "+20% rare salvage chance"},
		],
	},
	{
		"id": "cargo",
		"name": "Cargo Module",
		"color": Color("#57e389"),
		"blurb": "Every expedition brings back more with a bigger hold.",
		"upgrades": [
			{"credits": 180, "items": {"rusted_plate": 1}, "effect": "+1 salvaged item"},
			{"credits": 550, "items": {"scrap_alloy": 2}, "effect": "+2 salvaged items"},
			{"credits": 1700, "items": {"reinforced_panel": 1}, "effect": "+3 salvaged items"},
			{"credits": 5000, "items": {"titanium_composite": 1}, "effect": "+4 salvaged items"},
		],
	},
]

# --- Destinations -----------------------------------------------------------
const PLANET_DEFS := [
	{
		"id": "junkyard",
		"name": "Orbital Junkyard",
		"family": "circuit",
		"duration": 30.0,
		"credits_min": 45,
		"credits_max": 95,
		"items_min": 1,
		"items_max": 3,
		"rare_chance": 0.10,
		"requirements": {"engine": 1},
		"blurb": "The drifting scrapyard you woke up in. Common circuits, low risk.",
		"accent": Color("#61d0ff"),
	},
	{
		"id": "rustfall",
		"name": "Rustfall",
		"family": "alloy",
		"duration": 90.0,
		"credits_min": 220,
		"credits_max": 380,
		"items_min": 2,
		"items_max": 4,
		"rare_chance": 0.18,
		"requirements": {"engine": 2, "hull": 2},
		"blurb": "A shattered industrial world. Heavy plating and rare alloys.",
		"accent": Color("#ff9a5a"),
	},
	{
		"id": "neon_moon",
		"name": "Neon Moon",
		"family": "quantum",
		"duration": 180.0,
		"credits_min": 850,
		"credits_max": 1400,
		"items_min": 2,
		"items_max": 5,
		"rare_chance": 0.25,
		"requirements": {"navigation": 3, "power_core": 3},
		"blurb": "A technological ruin humming with quantum salvage.",
		"accent": Color("#b06bff"),
	},
]

const STARTER_PLANET := "junkyard"

# --- Tutorial ---------------------------------------------------------------
const TUTORIAL_STEPS := [
	{"id": "collect", "text": "Tap COLLECT to pull scrap out of your machines."},
	{"id": "merge", "text": "Drag one item onto an identical item to merge them."},
	{"id": "sell", "text": "Tap an item, then SELL it for credits."},
	{"id": "upgrade", "text": "Open UPGRADES and make your collector faster."},
	{"id": "part", "text": "Open SHIP and build a component."},
	{"id": "travel", "text": "Launch your first expedition from TRAVEL."},
]

# --- Static data access -----------------------------------------------------
static var _items: Dictionary = {}


static func _ensure_items() -> void:
	if not _items.is_empty():
		return
	for family_id in FAMILY_DEFS:
		var family: Dictionary = FAMILY_DEFS[family_id]
		var tiers: Array = family["tiers"]
		var tier_count: int = tiers.size()
		for index in tier_count:
			var entry: Array = tiers[index]
			var tier: int = index + 1
			var item_id: String = entry[0]
			var sell_value: int = int(round(float(family["base_value"]) * pow(float(family["value_growth"]), tier - 1)))
			_items[item_id] = {
				"id": item_id,
				"name": entry[1],
				"tier": tier,
				"max_tier": tier_count,
				"family": family_id,
				"family_label": family["label"],
				"shape": family["shape"],
				"color": rarity_color(tier),
				"sell_value": maxi(sell_value, 1),
				"next_id": (str(tiers[index + 1][0]) if index + 1 < tier_count else ""),
			}


static func items() -> Dictionary:
	_ensure_items()
	return _items


static func item(item_id: String) -> Dictionary:
	_ensure_items()
	return _items.get(item_id, {})


static func has_item(item_id: String) -> bool:
	_ensure_items()
	return _items.has(item_id)


static func next_tier_id(item_id: String) -> String:
	var definition: Dictionary = item(item_id)
	return str(definition.get("next_id", ""))


static func sell_value(item_id: String) -> int:
	return int(item(item_id).get("sell_value", 0))


static func item_tier(item_id: String) -> int:
	return int(item(item_id).get("tier", 0))


static func item_family(item_id: String) -> String:
	return str(item(item_id).get("family", ""))


static func family_def(family_id: String) -> Dictionary:
	return FAMILY_DEFS.get(family_id, {})


static func tier_ids(family_id: String) -> Array:
	var family: Dictionary = family_def(family_id)
	if family.is_empty():
		return []
	var result: Array = []
	for entry in family["tiers"]:
		result.append(str(entry[0]))
	return result


static func rarity_color(tier: int) -> Color:
	var index: int = clampi(tier - 1, 0, RARITY_COLORS.size() - 1)
	return RARITY_COLORS[index]


static func generator_def(generator_id: String) -> Dictionary:
	for definition in GENERATOR_DEFS:
		if str(definition["id"]) == generator_id:
			return definition
	return {}


static func ship_part_def(part_id: String) -> Dictionary:
	for definition in SHIP_PART_DEFS:
		if str(definition["id"]) == part_id:
			return definition
	return {}


static func planet(planet_id: String) -> Dictionary:
	for definition in PLANET_DEFS:
		if str(definition["id"]) == planet_id:
			return definition
	return {}
