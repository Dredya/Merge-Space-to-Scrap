extends RefCounted
## Interface for rewarded-advertising providers.
##
## Platform SDKs are integrated by subclassing this file and swapping the
## provider in `monetization_service.gd`. Nothing in the game requires ads.

## Whether the provider has the credentials/SDK it needs.
func is_configured() -> bool:
	return false


## True for development stand-ins, so the UI can label them honestly.
func is_mock() -> bool:
	return false


func provider_name() -> String:
	return "Not configured"


## Shows a rewarded ad and returns true when the reward should be granted.
## Implementations are coroutines (they await their SDK callback).
func show_rewarded(_host: Node) -> bool:
	push_warning("No rewarded ad provider configured; reward not granted.")
	return false
