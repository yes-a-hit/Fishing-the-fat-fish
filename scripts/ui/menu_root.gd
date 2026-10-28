extends Control

## 主菜单。整个游戏唯一的入口。
##
## 这一页只做一件事：开始。难度和音量都收进 settings.tscn 了 ——
## 首屏摆一排难度按钮和两个滑块，玩家每次进来都得先看一遍噪音。
##
## 难度写进 user://settings.json，game_root 启动时读回来套到 GameTuning 上。

const GAME_SCENE := "res://main.tscn"
const GALLERY_SCENE := "res://gallery.tscn"
const ABOUT_SCENE := "res://about.tscn"
const SETTINGS_SCENE := "res://settings.tscn"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_card()


# ---------- 背景 ----------

func _build_background() -> void:
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_background.bind(bg))
	add_child(bg)


func _draw_background(canvas: Control) -> void:
	var w := canvas.size.x
	var h := canvas.size.y
	if w <= 1.0 or h <= 1.0:
		return
	var horizon := h * 0.62

	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon), Vector2(0, horizon)]),
		PackedColorArray([Palette.SKY_TOP, Palette.SKY_TOP, Palette.SKY_LOW, Palette.SKY_LOW])
	)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Palette.WATER_DEEP, Palette.WATER_DEEP, Palette.WATER_SHALLOW, Palette.WATER_SHALLOW])
	)

	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.1, horizon),
		Vector2(w * 0.18, horizon - h * 0.11),
		Vector2(w * 0.44, horizon - h * 0.04),
		Vector2(w * 0.62, horizon - h * 0.13),
		Vector2(w * 1.1, horizon),
	]), Palette.HILL_FAR)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.1, horizon),
		Vector2(w * 0.30, horizon - h * 0.06),
		Vector2(w * 0.55, horizon - h * 0.02),
		Vector2(w * 0.78, horizon - h * 0.08),
		Vector2(w * 1.1, horizon),
	]), Palette.HILL_NEAR)

	canvas.draw_rect(Rect2(0, horizon - 1.0, w, 2.0), Palette.WATER_LINE)


# ---------- 卡片 ----------

func _build_card() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := UIKit.card(Color(1, 1, 1, 0.95), Palette.RADIUS, 30)
	card.custom_minimum_size = Vector2(430, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)

	var logo := UIKit.picture_fit("res://assets/logo.webp", Vector2(300, 100))
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)

	col.add_child(UIKit.title("钓肥鱼", Palette.F_TITLE))
	var sub := UIKit.label("有限的饵，喂饱这几条鱼", Palette.F_BODY, Palette.INK_FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(UIKit.spacer(6))
	col.add_child(UIKit.divider())
	col.add_child(UIKit.spacer(6))

	var start := UIKit.button("开 始 钓 鱼", true)
	start.pressed.connect(_on_start)
	col.add_child(start)

	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 6)
	col.add_child(footer_row)

	for spec in [
		{"text": "图 鉴", "cb": _on_gallery},
		{"text": "设 置", "cb": _on_settings},
		{"text": "关 于", "cb": _on_about},
		{"text": "退 出", "cb": func(): get_tree().quit()},
	]:
		var b := UIKit.button(String(spec["text"]), false, true)
		b.add_theme_font_size_override("font_size", Palette.F_SMALL)
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec["cb"])
		footer_row.add_child(b)


# ---------- 交互 ----------

func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_gallery() -> void:
	get_tree().change_scene_to_file(GALLERY_SCENE)


func _on_settings() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_about() -> void:
	get_tree().change_scene_to_file(ABOUT_SCENE)
