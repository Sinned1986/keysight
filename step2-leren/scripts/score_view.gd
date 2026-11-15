class_name ScoreView
extends Control
## Tekent één notenbalksysteem (een "pagina" van een paar maten) met de
## Bravura-muziekfont (SMuFL). De pagina wordt alleen opnieuw getekend als
## hij verandert; de cursor is een apart, licht element.

const SP := 24.0                    # tussenruimte notenbalk in pixels (12 mm)
const FONT_SIZE := 96               # SMuFL: 1 em = 4 tussenruimtes
const TREBLE_BOTTOM := 250.0        # y van de onderste lijn (solsleutel)
const BASS_BOTTOM := 470.0          # y van de onderste lijn (fa-sleutel)
const LEFT := 40.0
const RIGHT := 40.0

const INK := Color(0.93, 0.95, 0.98)
const DIM := Color(0.93, 0.95, 0.98, 0.55)
const OK := Color("3ddc97")
const BAD := Color("ff5a5a")
const BG := Color(0.07, 0.08, 0.11, 0.86)

# SMuFL-codepunten
const G_CLEF := 0xE050
const F_CLEF := 0xE062
const HEAD_WHOLE := 0xE0A2
const HEAD_HALF := 0xE0A3
const HEAD_BLACK := 0xE0A4
const SHARP := 0xE262
const FLAT := 0xE260
const NATURAL := 0xE261
const DOT := 0xE1E7
const FLAG8_UP := 0xE240
const FLAG8_DOWN := 0xE241
const FLAG16_UP := 0xE242
const FLAG16_DOWN := 0xE243
const REST := {16: 0xE4E3, 8: 0xE4E4, 4: 0xE4E5, 2: 0xE4E6, 1: 0xE4E7}
const TIME_DIGIT0 := 0xE080
const BRACE := 0xE000

# Kruizen/mollen van de voortekening, als notenbalkpositie in de solsleutel.
const SHARP_POS := [8, 5, 9, 6, 3, 7, 4]
const FLAT_POS := [4, 7, 3, 6, 2, 5, 1]

var model: ScoreModel
var notes: Array = []
var hand_colors := [Color(0.74, 0.40, 1.0), Color(0.22, 0.86, 1.0)]   # rechts, links
var page := -1
var cursor16 := 0.0
var _music: Font
var _text: Font
var _cursor: ColorRect
var _bar_x: Array = []           # x-begin van elke maat op de pagina
var _bar_w := 0.0
var _redraw_timer := 0.0


func _init() -> void:
	_music = load("res://fonts/Bravura.otf")
	_text = load("res://fonts/AtkinsonHyperlegible-Bold.ttf")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor = ColorRect.new()
	_cursor.color = Color(0.24, 0.86, 0.59, 0.28)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)


func set_song(m: ScoreModel, note_list: Array) -> void:
	model = m
	notes = note_list
	page = -1
	set_cursor(0.0)


## Cursor in zestienden sinds het begin. Wisselt van pagina als dat nodig is.
func set_cursor(pos: float) -> void:
	cursor16 = pos
	if model == null or model.bars.is_empty():
		_cursor.visible = false
		return
	var bar := clampi(floori(pos / model.bar_len), 0, model.bars.size() - 1)
	var p := int(bar / model.bars_per_page)
	if p != page:
		page = p
		_compute_layout()
		queue_redraw()
	var local_bar := bar - page * model.bars_per_page
	var in_bar := clampf(pos - bar * model.bar_len, 0.0, model.bar_len)
	var x := _x_for(local_bar, in_bar)
	_cursor.visible = pos >= 0.0
	_cursor.position = Vector2(x - 10.0, TREBLE_BOTTOM - 4.0 * SP - 2.5 * SP)
	_cursor.size = Vector2(20.0, (BASS_BOTTOM - TREBLE_BOTTOM) + 4.0 * SP + 5.0 * SP)


func _process(delta: float) -> void:
	# Kleuren van gespeelde noten bijwerken, 4x per seconde is genoeg.
	_redraw_timer -= delta
	if _redraw_timer <= 0.0 and is_visible_in_tree():
		_redraw_timer = 0.25
		queue_redraw()


func _header_width() -> float:
	var w := 2.6 * SP + 1.0 * SP   # sleutel
	w += absi(model.fifths) * 1.1 * SP
	if page == 0:
		w += 2.0 * SP              # maatsoort
	return w + SP


func _compute_layout() -> void:
	_bar_x.clear()
	var x0 := LEFT + _header_width()
	_bar_w = (size.x - RIGHT - x0) / model.bars_per_page
	for i in model.bars_per_page:
		_bar_x.append(x0 + i * _bar_w)


func _x_for(local_bar: int, in_bar16: float) -> float:
	if _bar_x.is_empty():
		return 0.0
	var pad := 1.4 * SP
	return _bar_x[clampi(local_bar, 0, _bar_x.size() - 1)] + pad + in_bar16 / model.bar_len * (_bar_w - 2.0 * pad)


func _y(pos: int, treble: bool) -> float:
	return (TREBLE_BOTTOM if treble else BASS_BOTTOM) - pos * SP / 2.0


func _glyph(code: int, pos: Vector2, color := INK, scale := 1.0) -> void:
	draw_string(_music, pos, String.chr(code), HORIZONTAL_ALIGNMENT_LEFT, -1, int(FONT_SIZE * scale), color)


func _draw() -> void:
	draw_style_box(_panel_box(), Rect2(Vector2.ZERO, size))
	if model == null or model.bars.is_empty():
		return
	var top := TREBLE_BOTTOM - 4.0 * SP
	var bottom := BASS_BOTTOM
	# Notenbalken
	for treble in [true, false]:
		for l in 5:
			var y := _y(l * 2, treble)
			draw_line(Vector2(LEFT, y), Vector2(size.x - RIGHT, y), DIM, 2.0, true)
	# Systeemlijn en accolade
	draw_line(Vector2(LEFT, top), Vector2(LEFT, bottom), INK, 3.0, true)
	var brace_scale := (bottom - top) / (4.0 * SP)
	_glyph(BRACE, Vector2(LEFT - 0.9 * SP * brace_scale * 0.35, bottom), INK, brace_scale)
	# Sleutels, voortekening, maatsoort
	var x := LEFT + 0.6 * SP
	_glyph(G_CLEF, Vector2(x, _y(2, true)))
	_glyph(F_CLEF, Vector2(x, _y(6, false)))
	x += 3.0 * SP
	for i in absi(model.fifths):
		var code := SHARP if model.fifths > 0 else FLAT
		var tp: int = (SHARP_POS if model.fifths > 0 else FLAT_POS)[i]
		_glyph(code, Vector2(x, _y(tp, true)))
		_glyph(code, Vector2(x, _y(tp - 2, false)))
		x += 1.1 * SP
	if page == 0:
		for treble in [true, false]:
			_digits(model.num, Vector2(x + 0.2 * SP, _y(6, treble)))
			_digits(model.den, Vector2(x + 0.2 * SP, _y(2, treble)))
	# Maten van deze pagina
	var first := page * model.bars_per_page
	for lb in model.bars_per_page:
		var bi := first + lb
		var bx: float = _bar_x[lb] + _bar_w
		draw_line(Vector2(bx, top), Vector2(bx, bottom), INK if bi < model.bars.size() else DIM, 2.0, true)
		if bi >= model.bars.size():
			continue
		# maatnummer
		draw_string(_text, Vector2(_bar_x[lb] + 4.0, top - 1.6 * SP), str(bi + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, DIM)
		for st in 2:
			for e in model.bars[bi]["staves"][st]:
				_draw_event(e, lb, st == 0)


func _digits(n: int, pos: Vector2) -> void:
	var s := str(n)
	var x := pos.x
	for ch in s:
		_glyph(TIME_DIGIT0 + int(ch), Vector2(x, pos.y))
		x += 1.6 * SP


func _draw_event(e: Dictionary, local_bar: int, treble: bool) -> void:
	var x := _x_for(local_bar, e["pos"])
	var dur: int = e["dur"]
	if e["rest"]:
		var rd := 16 if e.get("whole_bar", false) else dur
		var base := rd
		for v in [16, 8, 4, 2, 1]:
			if v <= rd:
				base = v
				break
		var rpos := 6 if base == 16 else 4
		var rx := x
		if e.get("whole_bar", false):
			rx = _bar_x[local_bar] + _bar_w / 2.0 - 0.6 * SP
		_glyph(REST[base], Vector2(rx, _y(rpos, treble)), DIM)
		return
	var heads: Array = e["heads"]
	# Ruimte maken voor voortekens: noot iets naar rechts.
	for h in heads:
		if h["acc"] != null:
			x += 0.6 * SP
			break
	var base_val := dur
	var dotted := false
	if dur in [12, 6, 3]:
		base_val = dur * 2 / 3
		dotted = true
	var head := HEAD_BLACK
	if base_val >= 16:
		head = HEAD_WHOLE
	elif base_val >= 8:
		head = HEAD_HALF
	var head_w := 1.18 * SP if head != HEAD_WHOLE else 1.7 * SP
	# Steelrichting: omhoog als de noten gemiddeld onder de middelste lijn liggen.
	var avg := 0.0
	for h in heads:
		avg += h["pos"]
	avg /= heads.size()
	var up := avg < 4.0
	var lo: int = heads[0]["pos"]
	var hi: int = heads[-1]["pos"]
	for h in heads:
		var pos: int = h["pos"]
		var col := _head_color(h)
		var hx := x
		# Hulplijnen
		if pos <= -2:
			var lp := -2
			while lp >= pos:
				var ly := _y(lp, treble)
				draw_line(Vector2(hx - 0.4 * SP, ly), Vector2(hx + head_w + 0.4 * SP, ly), DIM, 2.0, true)
				lp -= 2
		if pos >= 10:
			var lp := 10
			while lp <= pos:
				var ly := _y(lp, treble)
				draw_line(Vector2(hx - 0.4 * SP, ly), Vector2(hx + head_w + 0.4 * SP, ly), DIM, 2.0, true)
				lp += 2
		if h["acc"] != null:
			var acc_code := NATURAL
			if h["acc"] == 1:
				acc_code = SHARP
			elif h["acc"] == -1:
				acc_code = FLAT
			_glyph(acc_code, Vector2(hx - 1.05 * SP, _y(pos, treble)), col)
		_glyph(head, Vector2(hx, _y(pos, treble)), col)
		if dotted:
			var dpos := pos if pos % 2 != 0 else pos + 1
			_glyph(DOT, Vector2(hx + head_w + 0.35 * SP, _y(dpos, treble)), col)
	if head == HEAD_WHOLE:
		return
	# Steel en vlag
	var stem_x := x + head_w - 1.0 if up else x + 1.0
	var y_lo := _y(lo, treble)
	var y_hi := _y(hi, treble)
	var stem_len := 3.5 * SP
	var y0 := y_lo if up else y_hi
	var y1 := (y_hi - stem_len) if up else (y_lo + stem_len)
	draw_line(Vector2(stem_x, y0), Vector2(stem_x, y1), INK, 2.4, true)
	if base_val == 2 or base_val == 1:
		var flag := (FLAG8_UP if up else FLAG8_DOWN) if base_val == 2 else (FLAG16_UP if up else FLAG16_DOWN)
		_glyph(flag, Vector2(stem_x - (1.0 if up else 1.0), y1))


func _head_color(h: Dictionary) -> Color:
	var idx: int = h["note"]
	if idx < 0 or idx >= notes.size():
		return INK
	var n: Dictionary = notes[idx]
	var state: int = n.get("state", NoteHighway.PENDING)
	if state == NoteHighway.HIT:
		return OK
	if state == NoteHighway.MISSED:
		return BAD
	if state == NoteHighway.OTHER_HAND:
		return DIM
	# Nog te spelen: noten onder de cursor in de handkleur.
	if model and absf(float(n["start_tick"]) / model.grid - cursor16) < 1.0:
		return hand_colors[0] if n["hand"] == 1 else hand_colors[1]
	return INK


func _panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.set_corner_radius_all(24)
	s.anti_aliasing = true
	return s
