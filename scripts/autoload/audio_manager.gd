extends Node
## Procedural audio service.
##
## Every sound is synthesised at startup, so the project has no binary audio
## assets and cannot break because a wave file is missing. Mute is respected by
## skipping playback entirely.

const SAMPLE_RATE := 22050
const SFX_VOICES := 8

var sfx_volume: float = 0.8
var music_volume: float = 0.55
var haptics_enabled: bool = true

var _voices: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _sounds: Dictionary = {}
var _music_stream: AudioStreamWAV
var _next_voice: int = 0


func _ready() -> void:
	for _i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "Master"
		add_child(voice)
		_voices.append(voice)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -80.0
	add_child(_music_player)

	_sounds = {
		"merge": _tone(520.0, 1040.0, 0.20, 3, 0.6, 3.0),
		"collect": _tone(700.0, 880.0, 0.10, 0, 0.5, 4.0),
		"buy": _tone(620.0, 930.0, 0.16, 3, 0.5, 3.5),
		"error": _tone(220.0, 150.0, 0.18, 1, 0.35, 2.5),
		"depart": _tone(180.0, 680.0, 0.55, 3, 0.5, 1.4),
		"arrive": _tone(990.0, 660.0, 0.28, 3, 0.5, 2.2),
		"order": _tone(760.0, 1140.0, 0.18, 3, 0.5, 3.2),
		"tap": _tone(460.0, 460.0, 0.04, 0, 0.3, 6.0),
	}

	# GameState loads before this autoload, so pull its saved mix on startup.
	var state := get_node_or_null("/root/GameState")
	if state != null:
		apply_settings(
			float(state.settings.get("music", 0.55)),
			float(state.settings.get("sfx", 0.8)),
			bool(state.settings.get("haptics", true))
		)


func _exit_tree() -> void:
	# Release playback streams so a forced quit cannot report leaked instances.
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for voice in _voices:
		voice.stop()
		voice.stream = null
	_sounds.clear()
	_music_stream = null


func apply_settings(music: float, sfx: float, haptics: bool) -> void:
	music_volume = clampf(music, 0.0, 1.0)
	sfx_volume = clampf(sfx, 0.0, 1.0)
	haptics_enabled = haptics

	if _music_player == null:
		return

	if music_volume <= 0.01:
		_music_player.stop()
	else:
		_music_player.volume_db = _linear_to_db(music_volume * 0.45)
		if not _music_player.playing:
			play_music()


func play(sound_name: String) -> void:
	if sfx_volume <= 0.01 or _is_headless():
		return
	var stream: AudioStream = _sounds.get(sound_name, null)
	if stream == null or _voices.is_empty():
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = _linear_to_db(sfx_volume)
	voice.play()


func play_with_haptic(sound_name: String, milliseconds: int = 24) -> void:
	play(sound_name)
	haptic(milliseconds)


func haptic(milliseconds: int = 24) -> void:
	if not haptics_enabled:
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


func play_music() -> void:
	if music_volume <= 0.01 or _music_player == null or _is_headless():
		return
	if _music_stream == null:
		_music_stream = _build_music_loop()
	_music_player.stream = _music_stream
	_music_player.volume_db = _linear_to_db(music_volume * 0.45)
	_music_player.play()


# --- Synthesis --------------------------------------------------------------
func _tone(start_freq: float, end_freq: float, duration: float, waveform: int, gain: float, decay: float) -> AudioStreamWAV:
	var sample_count: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0

	for index in sample_count:
		var time: float = float(index) / float(SAMPLE_RATE)
		var progress: float = time / duration
		var frequency: float = lerpf(start_freq, end_freq, progress)
		phase += TAU * frequency / float(SAMPLE_RATE)

		var value: float = 0.0
		match waveform:
			1:
				value = 1.0 if sin(phase) >= 0.0 else -1.0
			2:
				value = 2.0 * absf(2.0 * (phase / TAU - floor(phase / TAU + 0.5))) - 1.0
			3:
				value = sin(phase) + 0.35 * sin(phase * 2.0) + 0.18 * sin(phase * 3.0)
			_:
				value = sin(phase)

		var envelope: float = exp(-decay * progress) * minf(1.0, progress * 40.0)
		var sample: int = int(clampf(value * envelope * gain, -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _build_music_loop() -> AudioStreamWAV:
	var duration: float = 8.0
	var sample_count: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var chord_a: Array[float] = [110.0, 164.81, 220.0, 329.63]
	var chord_b: Array[float] = [98.0, 146.83, 196.0, 293.66]

	for index in sample_count:
		var time: float = float(index) / float(SAMPLE_RATE)
		var blend: float = smoothstep(0.0, 1.0, fmod(time, 4.0) / 4.0)
		var value: float = 0.0
		for frequency in chord_a:
			value += sin(TAU * frequency * time) * (1.0 - blend)
		for frequency in chord_b:
			value += sin(TAU * frequency * time) * blend
		value /= float(chord_a.size())

		var tremolo: float = 0.85 + 0.15 * sin(TAU * 0.125 * time)
		var sample: int = int(clampf(value * tremolo * 0.22, -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _linear_to_db(value: float) -> float:
	if value <= 0.001:
		return -80.0
	return linear_to_db(clampf(value, 0.001, 1.0))
