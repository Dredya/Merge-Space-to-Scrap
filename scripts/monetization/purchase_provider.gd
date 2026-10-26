extends RefCounted
## Interface for optional non-essential purchases (cosmetic skins, etc.).
##
## Deliberately unconfigured: this build has no store integration, so it reports
## that purchases are unavailable instead of faking a transaction.

func is_configured() -> bool:
	return false


func provider_name() -> String:
	return "Store not configured"


## Returns {ok: bool, message: String, entitlement: String}.
## A configured implementation must verify a real receipt before returning
## ok = true.
func purchase(_product_id: String, _host: Node) -> Dictionary:
	return {
		"ok": false,
		"message": "In-app purchases are not available in this build.",
		"entitlement": "",
	}
