extends Node
## Versioned, atomic save/load service.
##
## Gameplay code never touches the filesystem: it hands a dictionary to
## `write_save()` and asks for one back with `load_save()`. Failed or outdated
## saves are moved aside (never deleted) so a broken file cannot wipe progress.

const SAVE_VERSION := 2
const MAIN_SAVE_PATH := "user://scrap_to_space_save.json"

var save_path: String = MAIN_SAVE_PATH
var autosave_enabled: bool = true
var last_error: String = ""
var last_save_unix: float = 0.0


func _ready() -> void:
	# Tests run with `-- --test-mode` so they never touch the player's save.
	if "--test-mode" in OS.get_cmdline_user_args():
		save_path = "user://scrap_to_space_test_save.json"
		autosave_enabled = false


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func backup_path() -> String:
	return save_path + ".bak"


func load_save() -> Dictionary:
	last_error = ""
	if not has_save():
		return {}

	var text: String = FileAccess.get_file_as_string(save_path)
	if text.strip_edges() == "":
		_quarantine("empty_file")
		return {}

	# JSON.new().parse() reports the error without dumping engine noise to the
	# console, which matters when a player's file is damaged.
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		_quarantine("invalid_json")
		return {}

	var data: Dictionary = parser.data
	var version: int = int(data.get("version", 0))
	if version <= 0:
		_quarantine("missing_version")
		return {}
	if version > SAVE_VERSION:
		_quarantine("newer_version_%d" % version)
		return {}
	if not (data.get("board", []) is Array) or not (data.get("parts", {}) is Dictionary):
		_quarantine("malformed_fields")
		return {}

	return data


func write_save(data: Dictionary) -> bool:
	last_error = ""
	var payload: Dictionary = data.duplicate(true)
	payload["version"] = SAVE_VERSION
	payload["saved_at"] = Time.get_unix_time_from_system()

	var text: String = JSON.stringify(payload)
	var temp_path: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open save file for writing (%d)." % FileAccess.get_open_error()
		return false
	file.store_string(text)
	file.close()

	_backup_current()

	var target_abs: String = ProjectSettings.globalize_path(save_path)
	var temp_abs: String = ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(target_abs)

	var rename_error: int = DirAccess.rename_absolute(temp_abs, target_abs)
	if rename_error != OK:
		# Fall back to a direct write so the player never loses a session.
		var fallback: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		if fallback == null:
			last_error = "Could not finalise save file (%d)." % FileAccess.get_open_error()
			return false
		fallback.store_string(text)
		fallback.close()
		DirAccess.remove_absolute(temp_abs)

	last_save_unix = Time.get_unix_time_from_system()
	return true


func delete_save() -> void:
	for path in [save_path, save_path + ".tmp", backup_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _backup_current() -> void:
	if not FileAccess.file_exists(save_path):
		return
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(save_path),
		ProjectSettings.globalize_path(backup_path())
	)


## Moves an unreadable save aside so the player keeps the file but can start a
## fresh run instead of hitting the same error forever.
func _quarantine(reason: String) -> void:
	var stamp: int = int(Time.get_unix_time_from_system())
	# Microseconds keep two failures in the same second from overwriting each other.
	var target: String = "%s.corrupt-%d-%d.json" % [save_path, stamp, Time.get_ticks_usec()]
	if FileAccess.file_exists(save_path):
		var error: int = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(target)
		)
		if error != OK:
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(save_path),
				ProjectSettings.globalize_path(target)
			)
	last_error = "Save could not be read (%s). A copy was kept at %s." % [reason, target]
