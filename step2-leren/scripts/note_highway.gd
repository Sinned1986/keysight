class_name NoteHighway
extends Node3D
## Vallende noten (zoals Synthesia), als kind van het PianoKeyboard.
##
## De noten vallen in een verticaal vlak op de achterrand van de toetsen.
## De onderkant van een balk raakt de toets precies op het moment dat je
## hem moet aanslaan; de lengte van de balk is de duur van de noot.
## Idee en kleuren per hand naar piARno (MIT), code nieuw geschreven.

const FALL_SPEED := 0.22      # meter per seconde liedtijd
const MAX_HEIGHT := 0.45      # hoe hoog de baan is (lookahead = MAX_HEIGHT / FALL_SPEED)
const BAR_DEPTH := 0.006
const HINT_LEAD := 1.0        # seconden vooraf dat de toets begint op te lichten

const COLOR_RIGHT := Color(0.74, 0.40, 1.0)   # rechterhand violet (zoals de artwork)
const COLOR_LEFT := Color(0.22, 0.86, 1.0)    # linkerhand cyaan
const COLOR_HIT := Color(0.25, 0.95, 0.35)
const COLOR_MISS := Color(0.45, 0.45, 0.45)

enum { PENDING, HIT, MISSED, OTHER_HAND }

var keyboard: PianoKeyboard
var notes: Array[Dictionary] = []
var practice_hand := -1   # -1 beide, 0 links, 1 rechts

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _plane_z := 0.0
var _base_y := 0.0
var _max_instances := 900
var _guides: MultiMeshInstance3D


func _init(kb: PianoKeyboard) -> void:
	keyboard = kb


func _ready() -> void:
	_plane_z = -PianoKeyboard.WHITE_LENGTH + 0.004
	_base_y = PianoKeyboard.WHITE_HEIGHT + PianoKeyboard.BLACK_HEIGHT
	# Gloeiende, afgeronde tegels + lichtbundels (shaders/note.gdshader).
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/note.gdshader")
	mat.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = _max_instances
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.custom_aabb = AABB(Vector3(-1, -0.1, -0.5), Vector3(2, 1.2, 1))
	add_child(_mmi)
	_build_guides()


## Dunne verticale lijnen bij elke C en F, zodat je de baan kunt volgen.
func _build_guides() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.035)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	var xs: Array[float] = []
	for n in range(PianoKeyboard.LOWEST_NOTE, PianoKeyboard.HIGHEST_NOTE + 1):
		if n % 12 == 0 or n % 12 == 5:
			# naad links van C en F
			xs.append(PianoKeyboard.key_center_x(n) - PianoKeyboard.WHITE_WIDTH / 2.0 - keyboard.total_width / 2.0)
	mm.instance_count = xs.size()
	for i in xs.size():
		var t := Transform3D(Basis.from_scale(Vector3(0.002, MAX_HEIGHT, 0.0005)),
			Vector3(xs[i], _base_y + MAX_HEIGHT / 2.0, _plane_z - 0.004))
		mm.set_instance_transform(i, t)
	_guides = MultiMeshInstance3D.new()
	_guides.multimesh = mm
	add_child(_guides)


func set_notes(n: Array[Dictionary]) -> void:
	notes = n


static func hand_color(hand: int, black: bool) -> Color:
	var c := COLOR_RIGHT if hand == 1 else COLOR_LEFT
	if black:
		c = c.darkened(0.25)
	return c


## Tekent alle noten rond liedtijd `t` en geeft de toets-hints terug:
## { noot: [kleur, sterkte] }.
func update_view(t: float, cursor: int) -> Dictionary:
	var hints := {}
	var lookahead := MAX_HEIGHT / FALL_SPEED
	var count := 0
	var beams: Array = []
	var tiles: Array = []
	var bursts: Array = []
	var i := cursor
	while i < notes.size():
		var n: Dictionary = notes[i]
		var start: float = n["start"]
		if start > t + lookahead:
			break
		i += 1
		var end: float = n["end"]
		if end < t:
			continue
		var pitch: int = n["pitch"]
		var black := PianoKeyboard.is_black(pitch)
		var state: int = n["state"]
		var col := hand_color(n["hand"], black)
		var alpha := 0.85
		if state == OTHER_HAND:
			alpha = 0.22
		elif state == HIT:
			col = col.lerp(COLOR_HIT, 0.55)
		elif state == MISSED:
			col = COLOR_MISS
			alpha = 0.5
		# Hint op de toets: oplichten in de seconde voor de aanslag.
		if state != OTHER_HAND:
			var s := 0.0
			if start > t:
				s = 1.0 - (start - t) / HINT_LEAD
			elif state == PENDING:
				s = 1.0
			if s > 0.0 and (not hints.has(pitch) or hints[pitch][1] < s):
				hints[pitch] = [hand_color(n["hand"], false), s]
		var bottom := maxf(0.0, (start - t) * FALL_SPEED)
		var top := minf(MAX_HEIGHT, (end - t) * FALL_SPEED)
		if top <= bottom:
			continue
		var w := PianoKeyboard.key_width(pitch) - 0.003
		var x := keyboard.local_x(pitch)
		var z := _plane_z + (0.002 if black else 0.0)
		var h := top - bottom
		var y0 := _base_y
		# Lichtbundel: van de toets omhoog, voor noten die er bijna zijn of klinken.
		if state != OTHER_HAND and start - t < 1.2:
			var s_beam := clampf(1.0 - (start - t) / 1.2, 0.0, 1.0)
			beams.append([x, y0, z - 0.002, w * 1.6, MAX_HEIGHT, col, 1.0, s_beam])
		tiles.append([x, y0 + bottom, z, w, h, col, alpha])
		# Gloed waar de balk de toets raakt.
		if start <= t and state != OTHER_HAND:
			var since := t - start
			var puff := 1.0 + 0.8 * maxf(0.0, 1.0 - since / 0.18)
			bursts.append([x, y0 + 0.004, z + 0.004, w * 3.2 * puff, 0.030 * puff, col.lightened(0.3), 1.0, 0.9])
	for item in beams + tiles + bursts:
		if count >= _max_instances:
			break
		_put(count, item)
		count += 1
	_mm.visible_instance_count = count
	return hints


## item = [x, onderkant_y, z, breedte, hoogte, kleur, alpha, (sterkte)]
## modus 0 = tegel (onderkant op y), 1 = bundel, 2 = gloed (midden op y).
func _put(idx: int, item: Array) -> void:
	var mode := 0.0
	var strength := 1.0
	if item.size() > 7:
		strength = item[7]
		mode = 1.0 if item[4] >= MAX_HEIGHT - 0.001 else 2.0
	var w: float = item[3]
	var h: float = item[4]
	var m := 0.014 * 2.0
	var cy: float = item[1] + h / 2.0 if mode < 1.5 else item[1]
	var tr := Transform3D(Basis.from_scale(Vector3(w + m, h + m, 1.0)), Vector3(item[0], cy, item[2]))
	_mm.set_instance_transform(idx, tr)
	var c: Color = item[5]
	_mm.set_instance_color(idx, Color(c.r, c.g, c.b, item[6]))
	_mm.set_instance_custom_data(idx, Color(w, h, mode, strength))


func clear() -> void:
	_mm.visible_instance_count = 0
