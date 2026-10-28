class_name CastBar
extends Control

## 抛竿距离指示 —— **只属于抛竿阶段**。
##
## 刻意只有一条槽和一块牌子：**不画任何分区**。
## 玩家能看到牌子上的水域描述（近岸 / 中段 / 远洋）和游标位置，
## 但看不到「这截归谁」—— 距离带之间是重叠的，同一点可能钓到不同的鱼，
## 画色块等于直接把答案印在界面上。
##
## 牌子随游标水平滑动，像立在岸边的一块路牌。
## 牌子显示的是**瞄准点**，不是最终落点 —— cast_jitter 会让实际落点偏一点。

const TRACK_HEIGHT := 12.0
const SIGN_W := 108.0
const SIGN_H := 30.0
const SIGN_TOP := 4.0
const TOP_PAD := SIGN_TOP + SIGN_H + 14.0
const STEM := 8.0

var _point: float = 0.0
var _font: Font = null
var _shadows: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, TOP_PAD + TRACK_HEIGHT + STEM)
	_font = ThemeDB.fallback_font


## 前两个参数保留是为了不改调用方 —— 分区已经不再画出来了。
## shadows 是 [[{center, width}]] 形式的鱼影，画成几团压暗的模糊块。
func configure(_zones: Array, _caught: Array, _fish_names: Dictionary = {},
		shadows: Array = []) -> void:
	_shadows = shadows.duplicate()
	queue_redraw()


func set_charge(value: float) -> void:
	_point = clampf(value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	if w <= 4.0:
		return

	# 轨道：一条干净的空槽，没有任何分区色块
	var track := Rect2(0, TOP_PAD, w, TRACK_HEIGHT)
	draw_style_box(_box(Palette.ZONE_GAP, int(TRACK_HEIGHT * 0.5), Color(0, 0, 0, 0), 0), track)
	_draw_shadows(w)

	var cx := w * _point
	# 两端各留一点，免得牌子贴边时被裁掉
	var half := SIGN_W * 0.5
	var sx := clampf(cx, half, maxf(w - half, half))

	# 牌子：投影 → 边框 → 牌面 → 文字
	var sign_rect := Rect2(sx - half + 1.5, SIGN_TOP + 2.0, SIGN_W, SIGN_H)
	draw_style_box(_box(Palette.SHADOW, Palette.RADIUS_SM, Color(0, 0, 0, 0), 0), sign_rect)

	var board := Rect2(sx - half, SIGN_TOP, SIGN_W, SIGN_H)
	draw_style_box(_box(Palette.CARD, Palette.RADIUS_SM, Palette.CARD_EDGE, 2), board)

	# 牌子到轨道的小杆
	var stem_top := SIGN_TOP + SIGN_H
	draw_line(Vector2(sx, stem_top), Vector2(cx, TOP_PAD), Palette.CARD_EDGE, 2.0, true)

	if _font != null:
		var caption := GameTuning.water_label(_point * 100.0)
		var text_y := SIGN_TOP + SIGN_H * 0.5 + Palette.F_SMALL * 0.36
		draw_string(
			_font, Vector2(board.position.x, text_y), caption,
			HORIZONTAL_ALIGNMENT_CENTER, SIGN_W, Palette.F_SMALL, Palette.INK
		)

	# 游标：一条竖线加一个小三角，指示当前瞄准点
	var top := TOP_PAD - 7.0
	var bottom := TOP_PAD + TRACK_HEIGHT + 4.0
	draw_line(Vector2(cx, top), Vector2(cx, bottom), Palette.INK, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, top - 1.0),
		Vector2(cx - 6.0, top - 9.0),
		Vector2(cx + 6.0, top - 9.0),
	]), Palette.INK)


## 水面上那几团模糊的鱼影。三层同心、越里越暗，边缘就软下去了 ——
## 看起来像水下的东西，而不是一条画上去的色块。
func _draw_shadows(w: float) -> void:
	for s in _shadows:
		var center := float(s["center"])
		var full := float(s["width"])
		var cx := w * center / 100.0
		var half := w * full / 100.0 * 0.5
		if half <= 1.0:
			continue
		var layers := [
			[1.00, 0.10],
			[0.74, 0.13],
			[0.46, 0.17],
		]
		for layer in layers:
			var lw: float = half * float(layer[0])
			var alpha: float = float(layer[1])
			var rect := Rect2(cx - lw, TOP_PAD - 1.0, lw * 2.0, TRACK_HEIGHT + 2.0)
			draw_style_box(
				_box(Color(Palette.INK, alpha), int((TRACK_HEIGHT + 2.0) * 0.5), Color(0, 0, 0, 0), 0),
				rect
			)


func _box(fill: Color, radius: int, edge: Color, edge_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	if edge_width > 0:
		sb.border_color = edge
		sb.set_border_width_all(edge_width)
	return sb
