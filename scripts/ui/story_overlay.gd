class_name StoryOverlay
extends Control

## 剧情播放器。galgame 那种：左下角站一个小人，底下一条对话框，一句一句往下走。
##
## 为什么要单独一层而不是塞进结算卡片：剧情是「这一局欠下的」，结算才是「这一局的结果」。
## 两者可能同时发生（比如第二次钓上豆包那一竿正好也集齐了三条鱼），
## 先播剧情、再摆结果，顺序反了就漏掉一整段。
##
## 可回溯：一步步走过来的，随时能按「◀」退回上一句 —— 手快点快了不至于错过。
## 可跳过：右上角一个「跳过」，跳的是整段，不是这一句。

signal finished

const DIM := Color(0.055, 0.129, 0.169, 0.55)
const BOX_H := 176.0
const FACE_H := 520.0

var _pages: Array = []
var _index: int = 0
var _story: Dictionary = {}
## 正序还是回看。回看时这一页的配音不重放。
var _forward: bool = true

var _bg: TextureRect = null
var _face: TextureRect = null
var _name_label: Label = null
var _text_label: Label = null
var _counter: Label = null
var _back_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## story 是一段剧情（story.json 里的一项）。播完 emit finished。
func play(story: Dictionary) -> void:
	_clear()
	_story = story
	_pages = story.get("pages", []) as Array
	if _pages.is_empty():
		finished.emit()
		return
	_index = 0
	visible = true
	_build()
	_render()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# 底图（梗图）。没有就用湖面背景透出来
	var bg_path := String(_story.get("bg", ""))
	if not bg_path.is_empty():
		_bg = UIKit.picture_fit(bg_path, get_viewport_rect().size)
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.modulate = Color(1, 1, 1, 0.92)
		add_child(_bg)

	# 左下角立绘
	var face_path := String(_story.get("portrait", ""))
	if not face_path.is_empty():
		_face = UIKit.picture_fit(face_path, Vector2(FACE_H * 0.62, FACE_H))
		_face.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_face.offset_left = 28
		_face.offset_bottom = -BOX_H + 24
		_face.offset_top = _face.offset_bottom - FACE_H
		_face.offset_right = _face.offset_left + FACE_H * 0.62
		add_child(_face)

	# 对话框
	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -BOX_H - 24
	wrap.offset_bottom = -24
	wrap.offset_left = 24
	wrap.offset_right = -24
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 22)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	_name_label = UIKit.label("", Palette.F_H3, Palette.ACCENT_DEEP)
	col.add_child(_name_label)

	_text_label = UIKit.wrap_label("", Palette.F_BODY, Palette.INK)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_text_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)

	_counter = UIKit.label("", Palette.F_SMALL, Palette.INK_FAINT)
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_counter)

	var next_hint := UIKit.label("点击继续 ▸", Palette.F_SMALL, Palette.INK_SOFT)
	bottom.add_child(next_hint)

	# 右上角：回看 / 跳过
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -260
	top.offset_top = 18
	top.offset_right = -20
	top.offset_bottom = 64
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 10)
	add_child(top)

	_back_btn = UIKit.button("◀ 回看", false, true)
	_back_btn.pressed.connect(_on_back)
	top.add_child(_back_btn)

	var skip := UIKit.button("跳过 ▶▶", false, true)
	skip.pressed.connect(_on_skip)
	top.add_child(skip)


func _render() -> void:
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[_index] as Dictionary
	var who := String(page.get("who", ""))
	_name_label.text = who
	_name_label.visible = not who.is_empty()
	_text_label.text = String(page.get("text", ""))
	_counter.text = "%d / %d" % [_index + 1, _pages.size()]
	if _back_btn != null:
		_back_btn.disabled = _index <= 0
	# 这一页配了音就放。回看时不重放 —— 退回上一句是为了读字，不是为了再听一遍。
	if _forward and not page.get("voice", "").is_empty():
		Audio.play_voice(String(page["voice"]))
	_forward = true


func _advance() -> void:
	if _index + 1 >= _pages.size():
		_finish()
		return
	_index += 1
	_render()


func _on_back() -> void:
	if _index <= 0:
		return
	_index -= 1
	_forward = false
	_render()


func _on_skip() -> void:
	_finish()


func _finish() -> void:
	_clear()
	visible = false
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 跳过按钮和回看按钮自己会吃掉点击，走到这里的都是「继续」
	var go := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		go = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		go = (event as InputEventScreenTouch).pressed
	elif event is InputEventKey:
		var k := event as InputEventKey
		go = k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER)
	if go:
		get_viewport().set_input_as_handled()
		_advance()


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_pages = []
	_bg = null
	_face = null
	_name_label = null
	_text_label = null
	_counter = null
	_back_btn = null
	_story = {}
