extends Control

## 关于页。授权、出处、以及三个链接。
##
## 为什么要有这一页：这是个 CC BY-NC-SA 的免费小游戏，角色形象全部来自
## 别人（ZipZipPipe）和社区梗图。把出处摆在自己家门口，是这条协议要求的最起码的事。
## 链接存在 data/about.json 里，改地址不用动代码。

const MENU_SCENE := "res://menu.tscn"
const DATA_PATH := "res://data/about.json"

var _data: Dictionary = {}
var _preview: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_data = _read_json(DATA_PATH)
	_build_background()
	_build_page()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[about] 解析失败：" + path)
		return {}
	var raw: Variant = json.data
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _sections() -> Array:
	var out: Array = []
	for s in _data.get("sections", []):
		if typeof(s) == TYPE_DICTIONARY:
			out.append(s)
	return out


func _links() -> Array:
	var out: Array = []
	for l in _data.get("links", []):
		if typeof(l) == TYPE_DICTIONARY:
			out.append(l)
	return out


func _easter() -> Array:
	var out: Array = []
	for e in _data.get("easter_eggs", []):
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out


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


# ---------- 页面 ----------

func _build_page() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var card := UIKit.card(Color(1, 1, 1, 0.95), Palette.RADIUS, 26)
	margin.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)

	var title := UIKit.title("关 于", Palette.F_H2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)

	head.add_child(UIKit.label(String(_data.get("license_short", "")), Palette.F_BODY, Palette.ACCENT_DEEP))

	col.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var intro := UIKit.wrap_label(String(_data.get("intro", "")), Palette.F_BODY, Palette.INK_SOFT)
	body.add_child(intro)

	for s in _sections():
		body.add_child(_build_section(s))

	var links := _links()
	if not links.is_empty():
		body.add_child(UIKit.divider())
		body.add_child(UIKit.label("去 处", Palette.F_SMALL, Palette.INK_FAINT))
		for l in links:
			body.add_child(_build_link_row(l))

	# 彩蛋摆在最下面：先看完正事，再掉进私货里。
	var eggs := _easter()
	if not eggs.is_empty():
		body.add_child(UIKit.divider())
		body.add_child(_build_easter_section(eggs))

	col.add_child(UIKit.divider())

	var back := UIKit.button("返 回", false)
	back.add_theme_font_size_override("font_size", Palette.F_BODY)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	col.add_child(back)


func _build_section(s: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var head := UIKit.label("· " + String(s.get("title", "")), Palette.F_SMALL, Palette.INK)
	box.add_child(head)

	var text := UIKit.wrap_label(String(s.get("body", "")), Palette.F_SMALL, Palette.INK_SOFT)
	box.add_child(text)
	return box


## 一行链接：左边标题 + 右边 URL，整行可点，点了开系统浏览器。
func _build_link_row(l: Dictionary) -> Control:
	var url := String(l.get("url", ""))
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 44)
	row.add_theme_stylebox_override("normal", _link_box(Palette.CARD_SOFT))
	row.add_theme_stylebox_override("hover", _link_box(Palette.CARD_EDGE))
	row.add_theme_stylebox_override("pressed", _link_box(Palette.CARD_EDGE.darkened(0.12)))
	if url != "":
		row.pressed.connect(_open_url.bind(url))
		row.tooltip_text = url
	else:
		row.disabled = true

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(line)

	var name_label := UIKit.label(String(l.get("label", "")), Palette.F_BODY, Palette.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)

	var url_label := UIKit.label(_pretty_url(url), Palette.F_SMALL, Palette.ACCENT_DEEP)
	url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	url_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(url_label)

	return row


## 长链接砍成「域名/末段」，一行放得下。
func _pretty_url(url: String) -> String:
	if url == "":
		return "—"
	var s := url.replace("https://", "").replace("http://", "")
	if s.length() <= 46:
		return s
	var tail := s.substr(s.length() - 30, 30)
	return s.substr(0, 12) + "…" + tail


# ---------- 彩蛋 ----------

## 两列网格。图都是 16:9，按 420 宽算出来高约 236，放大只到预览层。
func _build_easter_section(eggs: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	box.add_child(UIKit.label("彩 蛋", Palette.F_SMALL, Palette.INK_FAINT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in eggs:
		grid.add_child(_build_easter_cell(e))
	box.add_child(grid)
	return box


func _build_easter_cell(e: Dictionary) -> Control:
	var img := String(e.get("image", ""))
	var has_art := img != "" and ResourceLoader.exists(img)

	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_NONE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("normal", _link_box(Palette.CARD_SOFT))
	cell.add_theme_stylebox_override("hover", _link_box(Palette.CARD_EDGE))
	cell.add_theme_stylebox_override("pressed", _link_box(Palette.CARD_EDGE.darkened(0.12)))
	if has_art:
		cell.pressed.connect(_open_preview.bind(img, String(e.get("caption", ""))))
		cell.tooltip_text = "点一下放大"
	else:
		cell.disabled = true

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	if has_art:
		var pic := UIKit.picture_fit(img, Vector2(420, 236))
		pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(pic)

	var cap := UIKit.label(String(e.get("caption", "")), Palette.F_SMALL, Palette.INK_SOFT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return cell


func _open_preview(image: String, caption: String) -> void:
	_close_preview()

	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_preview = layer

	var dim := ColorRect.new()
	dim.color = Color(0.055, 0.129, 0.169, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var closer := Button.new()
	closer.focus_mode = Control.FOCUS_NONE
	closer.flat = true
	closer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	closer.pressed.connect(_close_preview)
	layer.add_child(closer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 20)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	# 按视口收一道，别让图把卡片顶出屏幕
	var max_w := clampf(get_viewport_rect().size.x * 0.72, 480.0, 960.0)
	col.add_child(UIKit.picture_fit(image, Vector2(max_w, max_w * 0.60)))

	if caption != "":
		var cap := UIKit.label(caption, Palette.F_BODY, Palette.INK_SOFT)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cap)

	var close := UIKit.button("关 闭", false)
	close.add_theme_font_size_override("font_size", Palette.F_BODY)
	close.pressed.connect(_close_preview)
	col.add_child(close)


func _close_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


func _link_box(bg: Color) -> StyleBoxFlat:
	var sb := UIKit.flat(bg, Palette.RADIUS_SM + 2)
	sb.set_content_margin_all(2)
	return sb


func _open_url(url: String) -> void:
	var err := OS.shell_open(url)
	if err != OK:
		push_warning("[about] 打不开链接：%s (err %d)" % [url, err])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_SCENE)
		get_viewport().set_input_as_handled()
