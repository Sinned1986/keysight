class_name ScoreModel
extends RefCounted
## Zet de noten van een MIDI-bestand om naar eenvoudige notatie: maten,
## notenbalken (rechterhand = solsleutel, linkerhand = fa-sleutel),
## nootwaarden op een 16e-raster, toonsoort en voortekens.
## Leest alleen; verandert niets aan het lied of de les.
##
## Benadering: MIDI bevat geen echte notatie. Noten worden gekwantiseerd op
## zestienden, noten over de maatstreep worden afgekapt (geen overbindingen),
## en rusten worden eenvoudig opgevuld.

const STD_VALUES := [16, 12, 8, 6, 4, 3, 2, 1]   # in zestienden (12/6/3 = gepunteerd)

# Krumhansl-Kessler toonsoortprofielen.
const MAJOR := [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
const MINOR := [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
# Grondtoon (toonklasse) van een majeurtoonsoort -> aantal kruizen (+) of mollen (-).
const PC_TO_FIFTHS := {0: 0, 7: 1, 2: 2, 9: 3, 4: 4, 11: 5, 6: 6, 1: -5, 8: -4, 3: -3, 10: -2, 5: -1}
const SHARP_ORDER := [3, 0, 4, 1, 5, 2, 6]   # F C G D A E B (letters 0=C..6=B)
const FLAT_ORDER := [6, 2, 5, 1, 4, 0, 3]    # B E A D G C F
const LETTER_PC := [0, 2, 4, 5, 7, 9, 11]

var tpq := 480
var grid := 120               # ticks per zestiende
var num := 4
var den := 4
var bar_len := 16             # zestienden per maat
var fifths := 0
var minor := false
var key_from_file := false
var bars: Array = []          # [{staves: [treble_events, bass_events]}]
var bars_per_page := 4


func build(song: MidiSong, notes: Array) -> void:
	bars.clear()
	if song == null or notes.is_empty():
		return
	tpq = maxi(song.ticks_per_quarter(), 1)
	grid = maxi(tpq / 4, 1)
	num = maxi(song.time_sig.x, 1)
	den = maxi(song.time_sig.y, 1)
	bar_len = maxi(int(num * 16 / den), 1)
	if song.key_sig != -99:
		fifths = clampi(song.key_sig, -7, 7)
		minor = song.key_minor
		key_from_file = true
	else:
		var k := estimate_key(notes)
		fifths = k[0]
		minor = k[1]
		key_from_file = false
	_layout(notes)


## Schat de toonsoort met Krumhansl-profielen. Geeft [fifths, mineur].
static func estimate_key(notes: Array) -> Array:
	var hist := []
	hist.resize(12)
	hist.fill(0.0)
	for n in notes:
		hist[int(n["pitch"]) % 12] += maxf(0.05, float(n["end"]) - float(n["start"]))
	var best := -INF
	var best_key := [0, false]
	for tonic in 12:
		for m in [false, true]:
			var prof: Array = MINOR if m else MAJOR
			var r := _corr(hist, prof, tonic)
			if r > best:
				best = r
				var major_pc := (tonic + 3) % 12 if m else tonic
				best_key = [PC_TO_FIFTHS[major_pc], m]
	return best_key


static func _corr(hist: Array, prof: Array, tonic: int) -> float:
	var mh := 0.0
	var mp := 0.0
	for i in 12:
		mh += hist[i]
		mp += prof[i]
	mh /= 12.0
	mp /= 12.0
	var num_ := 0.0
	var dh := 0.0
	var dp := 0.0
	for i in 12:
		var h: float = hist[(i + tonic) % 12] - mh
		var p: float = prof[i] - mp
		num_ += h * p
		dh += h * h
		dp += p * p
	if dh <= 0.0 or dp <= 0.0:
		return -1.0
	return num_ / sqrt(dh * dp)


## Voorteken van een letter in de toonsoort: -1 mol, 0, +1 kruis.
static func key_alter(letter: int, key_fifths: int) -> int:
	if key_fifths > 0 and SHARP_ORDER.find(letter) < key_fifths:
		return 1
	if key_fifths < 0 and FLAT_ORDER.find(letter) < -key_fifths:
		return -1
	return 0


## Spelling van een toonhoogte: {letter, alter, step} met step = octaaf*7+letter.
static func spell(pitch: int, key_fifths: int) -> Dictionary:
	var pc := pitch % 12
	var letter := LETTER_PC.find(pc)
	var alter := 0
	if letter < 0:
		if key_fifths >= 0:
			letter = LETTER_PC.find(pc - 1)
			alter = 1
		else:
			letter = LETTER_PC.find((pc + 1) % 12)
			alter = -1
	var octave := floori((pitch - alter) / 12.0) - 1
	return {"letter": letter, "alter": alter, "step": octave * 7 + letter}


## Notenbalkpositie: 0 = onderste lijn, elke stap = halve tussenruimte.
static func staff_pos(step: int, treble: bool) -> int:
	return step - (30 if treble else 18)   # E4 resp. G2 op de onderste lijn


## Splitst een duur (zestienden) in de grootste standaardwaarde die past.
static func note_value(dur16: int) -> int:
	for v in STD_VALUES:
		if v <= dur16:
			return v
	return 1


func _layout(notes: Array) -> void:
	var max_bar := 0
	var per_staff := [{}, {}]   # staf -> {start16: [note_idx...]}
	for i in notes.size():
		var n: Dictionary = notes[i]
		if not n.has("start_tick"):
			continue
		var s16 := roundi(float(n["start_tick"]) / grid)
		# MIDI-noten worden vaak iets korter gespeeld dan genoteerd (legato-gat):
		# een kleine marge naar boven afronden.
		var len16 := (float(n["end_tick"]) - float(n["start_tick"])) / grid
		var e16 := s16 + maxi(1, roundi(len16 + 0.35))
		var st := 0 if n["hand"] == 1 else 1
		if not per_staff[st].has(s16):
			per_staff[st][s16] = []
		per_staff[st][s16].append([i, e16 - s16])
		max_bar = maxi(max_bar, int(s16 / bar_len))
	for b in max_bar + 1:
		bars.append({"staves": [[], []]})
	var max_events := 0
	var min_dur := 16
	for st in 2:
		var starts: Array = per_staff[st].keys()
		starts.sort()
		for k in starts.size():
			var s16: int = starts[k]
			var bi := int(s16 / bar_len)
			var pos := s16 - bi * bar_len
			var group: Array = per_staff[st][s16]
			var dur := 9999
			for g in group:
				dur = mini(dur, g[1])
			if k + 1 < starts.size():
				dur = mini(dur, starts[k + 1] - s16)
			dur = clampi(dur, 1, bar_len - pos)
			var heads: Array = []
			for g in group:
				var p: int = notes[g[0]]["pitch"]
				var sp := spell(p, fifths)
				heads.append({"pitch": p, "note": g[0], "letter": sp["letter"], "alter": sp["alter"],
					"pos": staff_pos(sp["step"], st == 0), "acc": null})
			heads.sort_custom(func(a, c): return a["pos"] < c["pos"])
			bars[bi]["staves"][st].append({"pos": pos, "dur": note_value(dur), "rest": false, "heads": heads})
			min_dur = mini(min_dur, note_value(dur))
	# Voortekens per maat en rusten opvullen.
	for bar in bars:
		for st in 2:
			var evs: Array = bar["staves"][st]
			evs.sort_custom(func(a, c): return a["pos"] < c["pos"])
			_accidentals(evs)
			bar["staves"][st] = _fill_rests(evs)
			max_events = maxi(max_events, evs.size())
	# Maten per pagina volgens de dichtheid: zestienden hebben meer ruimte nodig.
	var px_per16 := 22.0 if min_dur >= 4 else (28.0 if min_dur >= 2 else 40.0)
	bars_per_page = clampi(floori(1560.0 / (bar_len * px_per16 + 70.0)), 1, 4)


func _accidentals(evs: Array) -> void:
	var current := {}   # (stap) -> alter in deze maat
	for e in evs:
		for h in e["heads"]:
			var step: int = h["pos"]
			var key_alt := key_alter(h["letter"], fifths)
			var cur: int = current.get(step, key_alt)
			if h["alter"] != cur:
				h["acc"] = h["alter"]
				current[step] = h["alter"]


func _fill_rests(evs: Array) -> Array:
	var out: Array = []
	if evs.is_empty():
		out.append({"pos": 0, "dur": bar_len, "rest": true, "whole_bar": true, "heads": []})
		return out
	var cursor := 0
	for e in evs:
		if e["pos"] > cursor:
			out.append_array(_rests(cursor, e["pos"] - cursor))
		out.append(e)
		cursor = maxi(cursor, e["pos"] + e["dur"])
	if cursor < bar_len:
		out.append_array(_rests(cursor, bar_len - cursor))
	return out


## Rusten per tel (eenvoudig): vul aan tot de volgende tel, dan hele tellen.
func _rests(pos: int, length: int) -> Array:
	var out: Array = []
	var beat := maxi(int(16 / den), 1)
	while length > 0:
		var v := 1
		for cand in [16, 8, 4, 2, 1]:
			if cand <= length and pos % cand == 0 and (cand <= beat or pos % beat == 0):
				v = cand
				break
		if v > bar_len:
			v = bar_len
		out.append({"pos": pos, "dur": v, "rest": true, "heads": []})
		pos += v
		length -= v
	return out


func page_count() -> int:
	return maxi(1, ceili(float(bars.size()) / bars_per_page))


## Positie in zestienden voor een tick.
func pos16(tick: float) -> float:
	return tick / grid
