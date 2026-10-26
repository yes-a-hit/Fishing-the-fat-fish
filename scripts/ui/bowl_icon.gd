class_name BowlIcon
extends Control

## 一只白饭碗的小图标，纯 _draw() 画。
## 不用 emoji 是因为默认字体不一定带彩色 emoji，跨平台会变豆腐块。
##
## 构图（控件 20×22）：上半是露出碗口的米饭，下半是梯形碗身。
## 描边故意用深墨蓝而不是浅灰 —— HUD 底色本身接近白，白碗配白底会糊成一片。

const W := 20.0
const H := 22.0

var _filled: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_filled(on: bool) -> void:
	if _filled == on:
		return
	_filled = on
	queue_redraw()


func _draw() -> void:
	var rim_y := H * 0.44
	var bottom := H * 0.96

	# 米饭：先画，碗身会盖住下半截
	if _filled:
		var rice_c := Vector2(W * 0.50, rim_y - H * 0.06)
		var rice_r := W * 0.32
		draw_circle(rice_c, rice_r, Color(1, 1, 1, 1))
		draw_arc(rice_c, rice_r, PI, TAU, 18, Palette.INK_SOFT, 1.3, true)

	# 碗身：上宽下窄的梯形
	var body := PackedVector2Array([
		Vector2(W * 0.06, rim_y),
		Vector2(W * 0.94, rim_y),
		Vector2(W * 0.76, bottom),
		Vector2(W * 0.24, bottom),
	])
	var fill := Color(1, 1, 1, 1) if _filled else Color(1, 1, 1, 0.45)
	draw_colored_polygon(body, fill)
	draw_polyline(PackedVector2Array([
		Vector2(W * 0.06, rim_y),
		Vector2(W * 0.94, rim_y),
		Vector2(W * 0.76, bottom),
		Vector2(W * 0.24, bottom),
		Vector2(W * 0.06, rim_y),
	]), Palette.INK_SOFT, 1.4, true)

	# 碗沿：比碗身描边更重，让「一只碗」的轮廓一眼可辨
	draw_line(Vector2(W * 0.02, rim_y), Vector2(W * 0.98, rim_y), Palette.INK, 1.8, true)

	if _filled:
		# 碗身左侧的高光
		draw_line(Vector2(W * 0.19, rim_y + H * 0.12), Vector2(W * 0.27, rim_y + H * 0.24),
			Color(0.55, 0.65, 0.70, 0.55), 1.2, true)
