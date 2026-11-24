extends Node

const Synth := preload("res://audio/synth_manager.gd")
const FIXTURE := "res://tests/sine.sf2"
var failures := 0


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
	print("  %s  %s" % ["OK" if condition else "FAIL", description])


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	print("=== SYNTH SELFTEST ===")
	var native := ClassDB.class_exists(&"KeySightSynthStream")
	check(native, "native backend registered")
	if not native:
		get_tree().quit(1)
		return
	var sandbox := "user://synth-selftest-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(sandbox)
	var font := sandbox.path_join("sine.sf2")
	var bad_font := sandbox.path_join("invalid.sf2")
	var broken_font := sandbox.path_join("broken.sf2")
	var config := sandbox.path_join("audio.cfg")
	var fixture := FileAccess.get_file_as_bytes(FIXTURE)
	FileAccess.open(font, FileAccess.WRITE).store_buffer(fixture)
	FileAccess.open(bad_font, FileAccess.WRITE).store_string("invalid")
	# Break the terminal preset's bag index while preserving the RIFF structure.
	var broken := fixture.duplicate()
	var phdr := fixture.hex_encode().find("70686472") >> 1
	broken.encode_u16(phdr + 8 + 38 + 24, 65535)
	FileAccess.open(broken_font, FileAccess.WRITE).store_buffer(broken)
	var stream: AudioStream = ClassDB.instantiate(&"KeySightSynthStream")
	var path := ProjectSettings.globalize_path(font)
	check(stream.load_soundfont(path, 48000, 32), "valid SF2")
	check(not stream.load_soundfont(ProjectSettings.globalize_path(bad_font), 48000, 32), "invalid SF2")
	check(not stream.load_soundfont(ProjectSettings.globalize_path(broken_font), 48000, 32), "damaged preset table")
	var playback := stream.instantiate_playback()
	playback.start()
	stream.midi(MIDI_MESSAGE_NOTE_ON, 15, 108, 96)
	var peak := 0.0
	for sample in playback.mix_audio(1.0, 512):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check(is_finite(peak) and peak > 0.001, "Godot playback mixes non-silent samples on channel 16")
	playback.stop()
	stream.midi(MIDI_MESSAGE_NOTE_OFF, 15, 108, 0)
	stream.render_peak(48000)
	check(stream.active_voices() == 0, "note off")
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 64, 127)
	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 21, 90)
	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 21, 0)
	check(stream.render_peak(48000) > 0.001 and stream.active_voices() == 1, "CC64 sustains velocity-zero note off")
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 64, 0)
	stream.render_peak(48000)
	check(stream.active_voices() == 0, "CC64 pedal up releases sustained note")
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 64, 127)
	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 21, 90)
	stream.midi(MIDI_MESSAGE_NOTE_OFF, 0, 21, 0)
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 121, 0)
	stream.render_peak(48000)
	check(stream.active_voices() == 0, "CC121 releases sustain")
	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 67, 90)
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 123, 0)
	stream.render_peak(48000)
	check(stream.active_voices() == 0, "CC123 releases notes")
	for note in range(40, 80):
		stream.midi(MIDI_MESSAGE_NOTE_ON, 0, note, 90)
	check(stream.active_voices() == 32, "polyphony capped at 32 voices")
	stream.midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 120, 0)
	stream.render_peak(4096)
	check(stream.active_voices() == 0 and stream.render_peak(512) == 0.0, "CC120 silences channel")

	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 60, 20)
	var quiet: float = stream.render_peak(2048)
	stream.silence(0, 16)
	stream.render_peak(4096)
	stream.midi(MIDI_MESSAGE_NOTE_ON, 0, 60, 115)
	var loud: float = stream.render_peak(2048)
	check(quiet > 0.0 and loud > quiet * 2.0, "velocity affects PCM amplitude")

	var launch_args := OS.get_cmdline_args()
	launch_args.append_array(OS.get_cmdline_user_args())
	var supplied := Synth.with_arguments(Synth.DEFAULTS, launch_args)
	if not supplied.soundfont.is_empty():
		var external: AudioStream = ClassDB.instantiate(&"KeySightSynthStream")
		var loaded: bool = external.load_soundfont(Synth.absolute_path(supplied.soundfont), 48000, 128)
		check(loaded, "external SoundFont loads")
		if loaded:
			external.midi(MIDI_MESSAGE_NOTE_ON, 0, 60, 96)
			check(external.render_peak(4096) > 0.001, "external SoundFont renders middle C")
			for note in range(21, 109):
				external.midi(MIDI_MESSAGE_NOTE_ON, note % 16, note, 90)
			var voices: int = external.active_voices()
			var start := Time.get_ticks_usec()
			external.render_peak(48000)
			print("  INFO  48000 frames from %d initial voices rendered in %.2f ms (offline)" %
				[voices, (Time.get_ticks_usec() - start) / 1000.0])

	var defaults := Synth.load_options(config)
	check(not defaults.enabled and defaults.live and not defaults.demo and not defaults.reference, "first-start defaults")
	defaults.gain = 0.25
	check(Synth.save_options(config, defaults) == OK and Synth.load_options(config) == defaults, "settings round trip")
	var args := PackedStringArray(["--no-synth", "--synth", "--soundfont", font, "--gain", "0.75", "--polyphony", "64"])
	var opts := Synth.with_arguments(defaults, args)
	check(opts.enabled and opts.soundfont == font and opts.gain == 0.75 and opts.polyphony == 64 and not defaults.enabled, "startup CLI overrides are temporary")

	var manager := Synth.new()
	add_child(manager)
	# Inject only the storage path so the selftest never changes user settings.
	manager.initialize(args, config)
	await wait_for_load(manager)
	check(manager.status == &"SYNTH_READY" and manager.loaded_path == path, "asynchronous load and enable")
	manager.configure("enabled", false)
	check(manager.status == &"SYNTH_OFF" and manager.loaded_path.is_empty(), "disable")
	manager.configure("soundfont", sandbox.path_join("missing.sf2"))
	manager.configure("enabled", true)
	await wait_for_load(manager)
	check(manager.status == &"SYNTH_MISSING", "missing SF2 status")
	manager.configure("soundfont", bad_font)
	await wait_for_load(manager)
	check(manager.status == &"SYNTH_INVALID", "invalid SF2 status")
	manager.configure("soundfont", font)
	await wait_for_load(manager)
	check(manager.status == &"SYNTH_READY", "switch back to valid SF2")
	manager.panic()
	manager.configure("enabled", false)
	manager.free()
	# Allow the audio server to retire stopped playback before shutdown.
	await get_tree().create_timer(0.1).timeout
	for file in [font, bad_font, broken_font, config, sandbox]:
		DirAccess.remove_absolute(file)
	print("=== SYNTH SELFTEST %s ===" % ("OK" if failures == 0 else "FAILED"))
	get_tree().quit(int(failures > 0))


func wait_for_load(manager: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while manager.status == &"SYNTH_LOADING" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
