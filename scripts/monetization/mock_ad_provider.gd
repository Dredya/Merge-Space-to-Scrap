extends "res://scripts/monetization/ad_provider.gd"
## Development-only rewarded-ad stand-in.
##
## It never contacts a network and never reports a real ad view: it simply waits
## a moment so the UI flow can be exercised. The interface flags it as mock so
## screens can label it "simulated".

const SIMULATED_SECONDS := 1.0


func is_configured() -> bool:
	return true


func is_mock() -> bool:
	return true


func provider_name() -> String:
	return "Simulated ads (development)"


func show_rewarded(host: Node) -> bool:
	if host == null or not host.is_inside_tree():
		return false
	await host.get_tree().create_timer(SIMULATED_SECONDS).timeout
	return true
