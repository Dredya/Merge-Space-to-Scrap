extends "res://scripts/monetization/ad_provider.gd"
## Real (AdMob) rewarded-ad provider skeleton.
##
## This file is the integration point for the Google Mobile Ads SDK. The SDK
## itself must be shipped through a Godot 4 Android plugin (Gradle build). Until
## that plugin is installed and configured, `is_configured()` returns false so
## the game keeps using its honest "unavailable" state instead of pretending.

const ADMOB_APP_ID := "ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"
const REWARDED_AD_UNIT_ID := "ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ"

var _plugin: Object = null


func _init() -> void:
	# Try to grab the native plugin if it was registered under this name.
	if Engine.has_singleton("GodotAdMob"):
		_plugin = Engine.get_singleton("GodotAdMob")


func is_configured() -> bool:
	return _plugin != null and ADMOB_APP_ID.find("X") == -1


func is_mock() -> bool:
	return false


func provider_name() -> String:
	return "AdMob (real)"


func show_rewarded(_host: Node) -> bool:
	if not is_configured():
		push_warning("AdMob plugin or ad unit IDs are not configured; reward not granted.")
		return false
	# Plugin-specific call goes here, e.g.:
	#   _plugin.load_rewarded(REWARDED_AD_UNIT_ID)
	#   await _plugin.rewarded_closed
	#   return _plugin.last_rewarded
	push_warning("AdMob show_rewarded not yet wired to the native plugin.")
	return false