extends RefCounted

# Message, English, German, Dutch.
const MESSAGES := {
	"SYNTH_AUDIO": ["Audio", "Audio", "Audio"],
	"SYNTH_ENABLED": ["Internal synthesizer", "Interner Synthesizer", "Interne synthesizer"],
	"SYNTH_LIVE": ["Live MIDI", "Live-MIDI", "Live-MIDI"],
	"SYNTH_REFERENCE": ["Lesson reference", "Referenznoten", "Voorbeeldnoten"],
	"SYNTH_DEMO": ["Demo playback", "Demo-Wiedergabe", "Demo afspelen"],
	"SYNTH_REVERB": ["Reverb", "Hall", "Galm"],
	"SYNTH_CHORUS": ["Chorus", "Chorus", "Chorus"],
	"SYNTH_GAIN": ["Master volume", "Gesamtlautstärke", "Hoofdvolume"],
	"SYNTH_VOICES": ["Polyphony", "Polyphonie", "Polyfonie"],
	"SYNTH_FILE": ["SoundFont", "SoundFont", "SoundFont"],
	"SYNTH_SCAN": ["Rescan", "Neu suchen", "Opnieuw zoeken"],
	"SYNTH_NO_FILES": ["No SF2 found in the SoundFont folders", "Keine SF2-Datei in den SoundFont-Ordnern", "Geen SF2 in de SoundFont-mappen"],
	"SYNTH_NO_FILE": ["No SoundFont selected", "Kein SoundFont ausgewählt", "Geen SoundFont geselecteerd"],
	"SYNTH_OFF": ["Synthesizer off", "Synthesizer aus", "Synthesizer uit"],
	"SYNTH_SELECT": ["Select a SoundFont to play", "SoundFont zum Spielen auswählen", "Kies een SoundFont om te spelen"],
	"SYNTH_READY": ["Loaded: %s", "Geladen: %s", "Geladen: %s"],
	"SYNTH_LOADING": ["Loading SoundFont…", "SoundFont wird geladen…", "SoundFont wordt geladen…"],
	"SYNTH_MISSING": ["SoundFont file is missing", "SoundFont-Datei fehlt", "SoundFont-bestand ontbreekt"],
	"SYNTH_INVALID": ["SoundFont could not be read as SF2", "SoundFont konnte nicht als SF2 gelesen werden", "SoundFont kon niet als SF2 worden gelezen"],
	"SYNTH_NO_BACKEND": ["Native synthesizer library unavailable", "Native Synthesizer-Bibliothek fehlt", "Native synthesizerbibliotheek ontbreekt"],
	"SYNTH_SAVE_FAILED": ["Could not save audio settings", "Audio-Einstellungen konnten nicht gespeichert werden", "Audio-instellingen konden niet worden opgeslagen"],
	"SYNTH_PANIC": ["Silence all", "Alle Töne stoppen", "Alle klanken stoppen"],
	"SYNTH_TEST": ["Test tone", "Testton", "Testtoon"],
	"SYNTH_BACK": ["Back", "Zurück", "Terug"],
	"SYNTH_PREVIOUS": ["Previous SoundFont", "Vorheriger SoundFont", "Vorige SoundFont"],
	"SYNTH_NEXT": ["Next SoundFont", "Nächster SoundFont", "Volgende SoundFont"],
}


static func install() -> void:
	var locales := ["en", "de", "nl"]
	for index in locales.size():
		var translation := Translation.new()
		translation.locale = locales[index]
		for key in MESSAGES:
			translation.add_message(key, MESSAGES[key][index])
		TranslationServer.add_translation(translation)
