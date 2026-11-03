class_name LakeBackdrop
extends Control

## 菜单/图鉴/设置/关于四页共用的湖面背景。
##
## 之前这四十行绘制代码在四个 ui/*.gd 里各抄了一份，改一次配色要改四处，
## 改漏一处就是「设置页的天比菜单页暗一点」这种没人报的 bug。
## 现在只有这一个文件知道天有多蓝、山在哪、水线多粗。
##
## 用法：`add_child(LakeBackdrop.new())`，先加它再加卡片，天然在最底层。
## 自己不拦鼠标 —— 页面根的点击要能一路落到 _unhandled_input。

const HORIZON := 0.62   ## 地平线在屏幕高度的比例


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	var horizon := h * HORIZON

	# 天：上下两个色，靠顶点色渐变。水面同理。
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon), Vector2(0, horizon)]),
		PackedColorArray([Palette.SKY_TOP, Palette.SKY_TOP, Palette.SKY_LOW, Palette.SKY_LOW])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Palette.WATER_DEEP, Palette.WATER_DEEP, Palette.WATER_SHALLOW, Palette.WATER_SHALLOW])
	)

	# 两层山：远的亮、近的暗，纯多边形，不用贴图。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.1, horizon),
		Vector2(w * 0.18, horizon - h * 0.11),
		Vector2(w * 0.44, horizon - h * 0.04),
		Vector2(w * 0.62, horizon - h * 0.13),
		Vector2(w * 1.1, horizon),
	]), Palette.HILL_FAR)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.1, horizon),
		Vector2(w * 0.30, horizon - h * 0.06),
		Vector2(w * 0.55, horizon - h * 0.02),
		Vector2(w * 0.78, horizon - h * 0.08),
		Vector2(w * 1.1, horizon),
	]), Palette.HILL_NEAR)

	draw_rect(Rect2(0, horizon - 1.0, w, 2.0), Palette.WATER_LINE)
