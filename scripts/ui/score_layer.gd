class_name ScoreLayer
extends Control

## 分数行 + 命中瞬间的飘字。
##
## 为什么单独一层：
##   HUD 管状态（白饭、鱼名、上鱼提示），这一层管爽感（分数、连击）。
##   剧情播放、暂停、结算都该把它收掉，但不该去动 HUD 的其它部分，
##   所以「收起来」这件事由 game_root 单独调。
##
## 连击的爽感靠三件事堆起来：数字变大、字放大、颜色变烫。
## 分数与飘字各一个 Label —— 早先给连击单开一个 Label 是对齐问题，
## 后来发现同一帧里新建 Label 的文本常常赶不上这一帧的重绘，干脆合成一行。

const SCORE_COLOR := Color(0.10, 0.20, 0.32)
const GAIN_COLOR := Color(0.86, 0.44, 0.06)
const HOT_COLOR := Color(0.76, 0.24, 0.10)
const LANDING_COLOR := Color(0.10, 0.48, 0.34)

## 连击到几下开始发烫。6 下是「停不下来」。
const FIRE_FROM := 6

var _score_label: Label = null
var _gain_label: Label = null
## 最近一次的分数。断连时要把分数行退回「不带连击」的样子，得记住它。
var _last_score: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_score_label = _make_label(Palette.F_H2, SCORE_COLOR)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_score_label)

	_gain_label = _make_label(Palette.F_TITLE, GAIN_COLOR)
	_gain_label.modulate.a = 0.0
	add_child(_gain_label)

	resized.connect(_layout)
	_layout()
	reset()


func _make_label(font_size: int, color: Color) -> Label:
	var l := UIKit.label("", font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 湖面是浅色、剧情底图是深色，两头上都可能压字 —— 用白描边，
	# 比投影稳：投影在浅色天空上会把字糊掉。
	l.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.92))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _layout() -> void:
	# 拿视口尺寸而不是 size：加进树的那一帧 size 还是 0，
	# 用 size 算出来的位置会跑到屏幕外（第一版就是这么消失的）。
	var vs := get_viewport_rect().size

	# 分数钉在左上第二行 —— 白饭条下面那一条空着，右上角被「上鱼！」占着
	_score_label.size = Vector2(320, 40)
	_score_label.position = Vector2(28, 58)

	# 飘字落在圆环正上方：玩家眼睛本来就在那儿
	_gain_label.size = Vector2(520, 48)
	_gain_label.position = Vector2((vs.x - 520) * 0.5, vs.y * 0.30)
	_gain_label.pivot_offset = Vector2(260, 24)


func reset() -> void:
	_score_label.text = "%s 0" % tr("得分")
	_gain_label.text = ""
	_gain_label.modulate.a = 0.0


## 分数行同时挂当前连击：连击是「此刻的状态」，飘字是「这一下的收益」。
## 早先把连击单独放一个 Label，那一层总是晚一帧才重绘；并进这一行之后就没这问题了。
func set_score(value: int, combo: int = 0) -> void:
	_last_score = maxi(value, 0)
	var text := "%s %d" % [tr("得分"), _last_score]
	if combo >= 2:
		text += "   x%d" % combo
	_score_label.text = text


## 一次命中的反馈。连击从 2 起才挂出来 —— 第一下就喊 x1 很傻。
func bump(gain: int, combo: int, _mult: float, total: int) -> void:
	set_score(total, combo)
	_gain_label.text = "+%d" % maxi(gain, 1)
	_gain_label.add_theme_color_override("font_color", _combo_color(combo))

	# 连击越长，字跳得越高；到 6 下最凶
	var peak := clampf(1.10 + float(maxi(combo - 2, 0)) * 0.05, 1.10, 1.40)
	_pop(peak, 0.55)


## 上鱼：比普通命中更重的一下。
func landing(gain: int, total: int) -> void:
	set_score(total, 0)
	_gain_label.text = "+%d" % maxi(gain, 1)
	_gain_label.add_theme_color_override("font_color", LANDING_COLOR)
	_pop(1.42, 0.8)


## 掉连击：把飘字淡掉，分数行退回不带连击的样子。
func break_combo() -> void:
	set_score(int(_last_score), 0)
	var t := create_tween()
	t.tween_property(_gain_label, "modulate:a", 0.0, 0.22)


func _combo_color(combo: int) -> Color:
	return HOT_COLOR if combo >= FIRE_FROM else GAIN_COLOR


func _pop(peak: float, hold: float) -> void:
	_gain_label.scale = Vector2.ONE
	_gain_label.modulate.a = 1.0
	var t := create_tween()
	var grow := t.tween_property(_gain_label, "scale", Vector2(peak, peak), 0.12)
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_gain_label, "modulate:a", 0.0, hold).set_delay(0.26)
