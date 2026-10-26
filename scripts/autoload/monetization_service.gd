extends Node
## Optional monetization facade.
##
## The game is fully playable with this service missing or disabled. Ads are
## provided by a swappable provider; the shipped default is an explicitly
## simulated provider for development. No purchase flow is presented because no
## store integration is configured.

signal ad_state_changed(busy: bool)

const MockAdProvider = preload("res://scripts/monetization/mock_ad_provider.gd")
const PurchaseProvider = preload("res://scripts/monetization/purchase_provider.gd")

var enabled: bool = true

var _ad_provider: RefCounted
var _purchase_provider: RefCounted
var _busy: bool = false


func _ready() -> void:
	_ad_provider = MockAdProvider.new()
	_purchase_provider = PurchaseProvider.new()

	# To integrate a real SDK later:
	#   1. Implement a class extending res://scripts/monetization/ad_provider.gd
	#      that initialises the SDK and maps its reward callback to a bool.
	#   2. Replace the line below.
	#   3. Ship the SDK's Android plugin and manifest permissions.
	# _ad_provider = MyRealAdProvider.new()


func ads_available() -> bool:
	return enabled and _ad_provider != null and _ad_provider.is_configured()


func ads_are_mock() -> bool:
	return _ad_provider != null and _ad_provider.is_mock()


func ads_label() -> String:
	if not ads_available():
		return "Rewarded ads unavailable"
	return str(_ad_provider.provider_name())


func is_busy() -> bool:
	return _busy


func purchases_available() -> bool:
	return _purchase_provider != null and _purchase_provider.is_configured()


## Requests a rewarded ad for `context`. Returns true only when the provider
## confirmed the view should be rewarded.
func watch_rewarded_ad(_context: String) -> bool:
	if not ads_available() or _busy:
		return false
	_busy = true
	ad_state_changed.emit(true)
	var granted: bool = await _ad_provider.show_rewarded(self)
	_busy = false
	ad_state_changed.emit(false)
	return granted
