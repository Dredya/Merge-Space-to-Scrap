extends RefCounted
## Pure merge rules. No state, no nodes: safe to unit test.

const Catalog = preload("res://scripts/data/game_catalog.gd")


static func can_merge(first_id: String, second_id: String) -> bool:
	return merge_target(first_id, second_id) != ""


static func merge_target(first_id: String, second_id: String) -> String:
	if first_id == "" or first_id != second_id:
		return ""
	return Catalog.next_tier_id(first_id)


static func failure_reason(first_id: String, second_id: String) -> String:
	if first_id == "" or second_id == "":
		return "That slot is empty."
	if first_id != second_id:
		return "Only identical items merge."
	if Catalog.next_tier_id(first_id) == "":
		return "This component is already the highest tier."
	return ""
