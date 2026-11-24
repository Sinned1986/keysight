extends Node

signal changed

const SETTINGS := "user://audio.cfg"
const DEFAULTS := {
	"enabled": false, "soundfont": "", "gain": 0.5, "polyphony": 128,
	"live": true, "reference": false, "demo": false, "reverb": false, "chorus": false,
}
const LIVE := 0
const REFERENCE := 16
const DEMO := 32
const TEST := 48
const CHANNEL_COUNT := 49

var options := DEFAULTS.duplicate()
var status := &"SYNTH_OFF"
var loaded_path := ""
var _settings_path := SETTINGS
var _saved := DEFAULTS.duplicate()
var _player: AudioStreamPlayer
var _bus := -1
var _worker: Thread
var _requested := {}
var _generation := 0
var _test_generation := 0


static func load_options(path: String) -> Dictionary:
	var result := DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key in DEFAULTS:
			var value: Variant = config.get_value("audio", key, DEFAULTS[key])
			if typeof(value) == typeof(DEFAULTS[key]):
				result[key] = value
	result.gain = clampf(result.gain, 0.0, 1.0)
	result.polyphony = clampi(result.polyphony, 1, 256)
	return result


static func save_options(path: String, values: Dictionary) -> Error:
	var config := ConfigFile.new()
	for key in DEFAULTS:
		config.set_value("audio", key, values[key])
	return config.save(path)


static func with_arguments(values: Dictionary, args: PackedStringArray) -> Dictionary:
	var result := values.duplicate()
	var i := 0
	while i < args.size():
		var flag := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match flag:
			"--synth", "--no-synth":
				result.enabled = flag == "--synth"
			"--soundfont":
				if not value.is_empty() and not value.begins_with("--"):
					result.soundfont = value
					i += 1
			"--gain":
				if value.is_valid_float() and is_finite(value.to_float()):
					result.gain = clampf(value.to_float(), 0.0, 1.0)
					i += 1
			"--polyphony":
				if value.is_valid_int():
					result.polyphony = clampi(value.to_int(), 1, 256)
					i += 1
		i += 1
	return result


static func soundfonts() -> PackedStringArray:
	var paths := PackedStringArray()
	var dirs := ["user://soundfonts"]
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		for sub in ["soundfonts", "keysight/soundfonts", ".local/share/KeySight/soundfonts"]:
			dirs.append(home.path_join(sub))
	for dir: String in dirs:
		for file in DirAccess.get_files_at(dir):
			var path := ProjectSettings.globalize_path(dir.path_join(file))
			if file.get_extension().to_lower() == "sf2" and not paths.has(path):
				paths.append(path)
	paths.sort()
	return paths


static func absolute_path(path: String) -> String:
	if path.begins_with("~/"):
		return OS.get_environment("HOME").path_join(path.substr(2))
	if path.is_absolute_path():
		return ProjectSettings.globalize_path(path)
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + path)
	return OS.get_executable_path().get_base_dir().path_join(path)


func initialize(args: PackedStringArray, settings_path := SETTINGS) -> void:
	_settings_path = settings_path
	_saved = load_options(_settings_path)
	options = with_arguments(_saved, args)
	DirAccess.make_dir_recursive_absolute("user://soundfonts")
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, &"KeySightSynth")
	var reverb := AudioEffectReverb.new()
	reverb.wet = 0.18
	AudioServer.add_bus_effect(_bus, reverb)
	var chorus := AudioEffectChorus.new()
	chorus.wet = 0.20
	AudioServer.add_bus_effect(_bus, chorus)
	_player = AudioStreamPlayer.new()
	_player.bus = &"KeySightSynth"
	add_child(_player)
	_apply_mix()
	_reload()


func configure(key: String, value: Variant) -> void:
	if options[key] == value:
		return
	options[key] = value
	_saved[key] = value
	var error := save_options(_settings_path, _saved)
	if error != OK:
		push_warning(tr(&"SYNTH_SAVE_FAILED"))
	match key:
		"enabled", "soundfont", "polyphony":
			_reload()
		"live":
			_silence_source(LIVE)
		"reference":
			_silence_source(REFERENCE)
		"demo":
			_silence_source(DEMO)
		_:
			_apply_mix()
	changed.emit()


func retry_soundfont() -> void:
	if status == &"SYNTH_MISSING" or status == &"SYNTH_INVALID":
		_reload()
		changed.emit()


func _apply_mix() -> void:
	if _player.stream:
		_player.stream.set_gain(options.gain)
	AudioServer.set_bus_effect_enabled(_bus, 0, options.reverb)
	AudioServer.set_bus_effect_enabled(_bus, 1, options.chorus)


func _reload() -> void:
	_generation += 1
	_requested = {}
	panic()
	_player.stop()
	_player.stream = null
	loaded_path = ""
	if not options.enabled:
		status = &"SYNTH_OFF"
	elif not ClassDB.class_exists(&"KeySightSynthStream"):
		status = &"SYNTH_NO_BACKEND"
	elif options.soundfont.is_empty():
		status = &"SYNTH_SELECT"
	else:
		status = &"SYNTH_LOADING"
		_requested = {
			"generation": _generation, "path": absolute_path(options.soundfont),
			"voices": options.polyphony, "rate": roundi(AudioServer.get_mix_rate()),
		}
		_start_load()


func _start_load() -> void:
	if _worker or _requested.is_empty():
		return
	_worker = Thread.new()
	var request := _requested
	_requested = {}
	var stream := ClassDB.instantiate(&"KeySightSynthStream") as AudioStream
	if _worker.start(_load_file.bind(stream, request)) != OK:
		_worker = null
		status = &"SYNTH_INVALID"


static func _load_file(stream: AudioStream, request: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(request.path):
		request.status = &"SYNTH_MISSING"
	elif request.path.get_extension().to_lower() != "sf2" or not stream.load_soundfont(
			request.path, request.rate, request.voices):
		request.status = &"SYNTH_INVALID"
	else:
		request.stream = stream
		request.status = &"SYNTH_READY"
	return request


func _process(_delta: float) -> void:
	if not _worker or _worker.is_alive():
		return
	var result: Dictionary = _worker.wait_to_finish()
	_worker = null
	if result.generation == _generation:
		status = result.status
		if result.has("stream"):
			loaded_path = result.path
			_player.stream = result.stream
			_apply_mix()
			# Dummy never emits audio. Leave sample testing to the native playback selftest.
			if AudioServer.get_driver_name() != "Dummy":
				_player.play()
		changed.emit()
	_start_load()


func midi_event(event: InputEventMIDI) -> void:
	if not options.live or not _player.stream or event.channel < 0 or event.channel > 15:
		return
	match event.message:
		MIDI_MESSAGE_NOTE_ON, MIDI_MESSAGE_NOTE_OFF, MIDI_MESSAGE_PITCH_BEND:
			_player.stream.midi(event.message, event.channel, event.pitch, event.velocity)
		MIDI_MESSAGE_CONTROL_CHANGE:
			_player.stream.midi(event.message, event.channel, event.controller_number, event.controller_value)
		MIDI_MESSAGE_PROGRAM_CHANGE:
			_player.stream.midi(event.message, event.channel, event.instrument, 0)
		MIDI_MESSAGE_SYSTEM_RESET:
			panic()


func playback_note(source: int, channel: int, pitch: int, velocity: int) -> void:
	var key := "demo" if source == DEMO else "reference"
	if _player.stream and options[key]:
		_player.stream.midi(MIDI_MESSAGE_NOTE_ON, source + clampi(channel, 0, 15), pitch, velocity)


func _silence_source(source: int) -> void:
	if _player.stream:
		_player.stream.silence(source, source + 16)


func stop_reference() -> void:
	_silence_source(REFERENCE)


func panic() -> void:
	_test_generation += 1
	if _player and _player.stream:
		_player.stream.silence(0, CHANNEL_COUNT)
	if _bus >= 0 and _player.stream:
		# Recreate the effect instances to clear any reverb or chorus tail.
		for i in [1, 0]:
			if not AudioServer.is_bus_effect_enabled(_bus, i):
				continue
			var effect := AudioServer.get_bus_effect(_bus, i)
			AudioServer.remove_bus_effect(_bus, i)
			AudioServer.add_bus_effect(_bus, effect, i)
		_apply_mix()


func test_tone() -> void:
	if not _player.stream:
		return
	_test_generation += 1
	var generation := _test_generation
	_player.stream.silence(TEST, CHANNEL_COUNT)
	_player.stream.midi(MIDI_MESSAGE_NOTE_ON, TEST, 60, 96)
	await get_tree().create_timer(0.45).timeout
	if _player.stream and generation == _test_generation:
		_player.stream.midi(MIDI_MESSAGE_NOTE_OFF, TEST, 60, 0)


func shutdown() -> void:
	_generation += 1
	_requested = {}
	if _player and _player.stream:
		_player.stream.silence(0, CHANNEL_COUNT)
		_player.stop()
		_player.stream = null


func _exit_tree() -> void:
	shutdown()
	if _worker:
		_worker.wait_to_finish()
		_worker = null
	if _bus >= 0:
		AudioServer.remove_bus(_bus)
