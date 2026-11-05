class_name StoryOverlay
extends Control

## 剧情播放器。视觉小说那种：底图铺满、左下角站个小人、底下一条对话框，一句一句往下走。
##
## 为什么单独一层而不是塞进结算卡片：剧情是「这一局欠下的」，结算才是「这一局的结果」。
## 两者可能同时发生（比如第二次钓上豆包那一竿正好也集齐了三条鱼），
## 先播剧情、再摆结果，顺序反了就漏掉一整段。
##
## 可回溯：一步步走过来的，随时能按「◀」退回上一句 —— 手快点快了不至于错过。
## 可跳过：右上角一个「跳过」，跳的是整段，不是这一句。
##
## 操作：点画面任意处继续；打字打到一半点时先把这句显示完整，再点才翻页。
## 键盘空格 / 回车等价于点一下。

signal finished
## 这一页要放一句语音。上层（game_root）接走，交给 Audio 去播。
signal voice_requested(key: String)

const DIM := Color(0.055, 0.129, 0.169, 0.42)
const BOX_H := 190.0
const FACE_H := 560.0
## 每个字停多少秒。0 表示不做打字机，直接整句显示。
const TYPE_SPEED := 0.028

## 旁白没有说话人，立绘整体压暗一点，让镜头感降下来
const DIM_NARRATOR := Color(0.70, 0.72, 0.78, 1.0)
const DIM_SPEAKING := Color(1, 1, 1, 1)

## 玩家的说话人名字。自己说话时不该把鱼的脸打亮 —— 说话的不是她。
const USER_SPEAKER := "你"

var _pages: Array = []
var _index: int = 0
var _story: Dictionary = {}
## 正序还是回看。回看时这一页的配音不重放。
var _forward: bool = true

var _bg: TextureRect = null
var _bg_path: String = ""
var _face: TextureRect = null
var _face_path: String = ""
var _name_label: Label = null
var _text_label: Label = null
var _counter: Label = null
var _arrow: Label = null
var _back_btn: Button = null
var _skip_btn: Button = null

## 打字机：_reveal 是当前已经显示到第几个字，_typing 是还在打
var _reveal: float = 0.0
var _typing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)


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
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		return
	_reveal += delta / maxf(TYPE_SPEED, 0.001)
	if _reveal >= float(_full_length()):
		_reveal = float(_full_length())
		_stop_typing()
	else:
		_text_label.visible_characters = int(_reveal)


func _full_length() -> int:
	return _text_label.text.length() if _text_label != null else 0


func _stop_typing() -> void:
	_typing = false
	if _text_label != null:
		_text_label.visible_characters = -1
	if _arrow != null:
		_arrow.visible = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# 底图（梗图）。没有就用湖面背景透出来
	var bg_path := String(_story.get("bg", ""))
	if not bg_path.is_empty():
		_bg = _make_bg(bg_path)
		add_child(_bg)
		_bg_path = bg_path

	# 左下角立绘
	var face_path := String(_story.get("portrait", ""))
	if not face_path.is_empty():
		_face = _make_face(face_path)
		add_child(_face)
		_face_path = face_path

	# 对话框
	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -BOX_H - 26
	wrap.offset_bottom = -26
	wrap.offset_left = 26
	wrap.offset_right = -26
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 24)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	_name_label = UIKit.label("", Palette.F_H3, Palette.ACCENT_DEEP)
	col.add_child(_name_label)

	_text_label = UIKit.wrap_label("", Palette.F_BODY, Palette.INK)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 手动控制可见字数，逐字显示靠这个
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	col.add_child(_text_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)

	_counter = UIKit.label("", Palette.F_SMALL, Palette.INK_FAINT)
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_counter)

	_arrow = UIKit.label("▼", Palette.F_SMALL, Palette.INK_SOFT)
	_arrow.visible = false
	bottom.add_child(_arrow)

	# 右上角：回看 / 跳过
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -280
	top.offset_top = 18
	top.offset_right = -20
	top.offset_bottom = 64
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 10)
	add_child(top)

	_back_btn = UIKit.button("◀ 回看", false, true)
	_back_btn.pressed.connect(_on_back)
	top.add_child(_back_btn)

	_skip_btn = UIKit.button("跳过 ▶▶", false, true)
	_skip_btn.pressed.connect(_on_skip)
	top.add_child(_skip_btn)


func _make_bg(path: String) -> TextureRect:
	var t := UIKit.picture_fit(path, get_viewport_rect().size)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.modulate = Color(1, 1, 1, 0.90)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _make_face(path: String) -> TextureRect:
	var f := UIKit.picture_fit(path, Vector2(FACE_H * 0.62, FACE_H))
	f.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	f.offset_left = 30
	f.offset_bottom = -BOX_H + 20
	f.offset_top = f.offset_bottom - FACE_H
	f.offset_right = f.offset_left + FACE_H * 0.62
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _render() -> void:
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[_index] as Dictionary

	var who := String(page.get("who", ""))

	# 这一页可以单独覆盖立绘与背景，没写就查整段的 faces 表（谁说话画谁），
	# 再没有就沿用上一页 —— 一段里三个人轮流说话时只写一张脸会张冠李戴。
	# 整段没配 bg 时，页级 bg 要能把底图建出来：齐鱼之福第二天那张 CG
	# 就只挂在后半段的句子上，不能不整段铺。
	var want_bg := String(page.get("bg", ""))
	# "bg": "-" 表示这一页把整页 CG 撤掉，回到只用立绘的普通演出
	if want_bg == "-" and _bg != null:
		_bg.queue_free()
		_bg = null
		_bg_path = ""
	elif not want_bg.is_empty() and want_bg != "-" and want_bg != _bg_path:
		if _bg == null:
			_bg = _make_bg(want_bg)
			# 整页 CG 要整张看到：装进 16:9 画框后只缩不裁，上下留一点暗边也比把手裁掉强
			_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			add_child(_bg)
			move_child(_bg, 1 if get_child_count() > 1 else 0)
			_bg_path = want_bg
		else:
			_swap_bg(want_bg)
	var want_face := String(page.get("portrait", ""))
	if want_face.is_empty() and not who.is_empty():
		want_face = String((_story.get("faces", {}) as Dictionary).get(who, ""))
	if not want_face.is_empty() and want_face != _face_path:
		_swap_face(want_face)
	# 整页 CG 的句子上把立绘收起来，不然一张小脸压在 CG 上很怪
	if _face != null:
		_face.visible = not bool(page.get("hide_face", false))

	_name_label.text = who
	_name_label.visible = not who.is_empty()
	# 旁白和玩家自己的台词都把立绘压暗，只有鱼说话时亮着 —— 一眼能看出这句是谁在说
	var speaking := not who.is_empty() and who != USER_SPEAKER
	if _face != null:
		_face.modulate = DIM_SPEAKING if speaking else DIM_NARRATOR

	_text_label.text = String(page.get("text", ""))
	_counter.text = "%d / %d" % [_index + 1, _pages.size()]
	if _back_btn != null:
		_back_btn.disabled = _index <= 0

	_start_typing()

	# 这一页配了音就请求播放。回看时不重放 —— 退回上一句是为了读字，不是为了再听一遍。
	# 只发信号、不直接叫 Audio：这一层不该认识音频单例（`--script` 自测里
	# 没有 autoload，硬引用会让整个脚本编译失败）。
	if _forward and not page.get("voice", "").is_empty():
		voice_requested.emit(String(page["voice"]))
	_forward = true


func _start_typing() -> void:
	if TYPE_SPEED <= 0.0:
		_stop_typing()
		return
	_reveal = 0.0
	_typing = true
	_text_label.visible_characters = 0
	if _arrow != null:
		_arrow.visible = false


func _swap_bg(path: String) -> void:
	if _bg == null:
		return
	var tex := UIKit.load_texture(path)
	if tex == null:
		return
	_bg.texture = tex
	_bg_path = path
	_bg.modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.tween_property(_bg, "modulate", Color(1, 1, 1, 0.90), 0.22)


func _swap_face(path: String) -> void:
	if _face == null:
		return
	var tex := UIKit.load_texture(path)
	if tex == null:
		return
	_face.texture = tex
	_face_path = path


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
	# 回看是为了读字，直接给整句
	_stop_typing()


func _on_skip() -> void:
	_finish()


func _finish() -> void:
	_clear()
	visible = false
	set_process(false)
	finished.emit()


## 点一下：打字中就先补齐，打完了才翻页。
func _punch() -> void:
	if _typing:
		_stop_typing()
	else:
		_advance()


## 用 _gui_input 而不是 _unhandled_input：这一层 mouse_filter 是 STOP，
## 鼠标事件在 GUI 阶段就被它自己吃掉了，压根到不了 unhandled_input。
##
## 但对话框本身是一堆 Label，Label 会先把落在自己身上的点击吃掉，
## 结果就是「点字没反应、只能按 Enter」。所以点击统一在 _input 里收，
## 只把右上角两个按钮的范围让出去 —— 手机上也没有别的输入方式了。
func _input(event: InputEvent) -> void:
	# 键盘走 _input：这一层不抢焦点，Key 事件到不了 _gui_input。
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER):
			get_viewport().set_input_as_handled()
			_punch()
		return

	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
		pos = st.position
	if not pressed:
		return

	# 右上角的「回看 / 跳过」自己接点击，别在这一层抢掉
	for b in [_back_btn, _skip_btn]:
		if b != null and b.visible and b.get_global_rect().has_point(pos):
			return

	get_viewport().set_input_as_handled()
	_punch()


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_pages = []
	_bg = null
	_bg_path = ""
	_face = null
	_face_path = ""
	_name_label = null
	_text_label = null
	_counter = null
	_arrow = null
	_back_btn = null
	_story = {}
	_typing = false
	_reveal = 0.0
