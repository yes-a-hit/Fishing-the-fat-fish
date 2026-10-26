class_name UIKit
extends RefCounted

## 控件工厂。所有面板都通过这里造控件，样式才不会各写一套。
##
## 约定：
##   - 面板里不出现 new StyleBoxFlat()，要样式就调这里。
##   - 字号一律用 Palette.F_*，颜色一律用 Palette.*。

static func flat(bg: Color, radius: int = Palette.RADIUS_SM, edge: Color = Color(0, 0, 0, 0), edge_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if edge_width > 0:
		sb.set_border_width_all(edge_width)
		sb.border_color = edge
	return sb


## 标准白卡片：圆角、细边、内边距。
static func card(bg: Color = Palette.CARD, radius: int = Palette.RADIUS, padding: int = Palette.PAD) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := flat(bg, radius, Palette.CARD_EDGE, 1)
	sb.set_content_margin_all(padding)
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	pc.add_theme_stylebox_override("panel", sb)
	return pc


static func label(text: String, size: int = Palette.F_BODY, color: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = Palette.F_TITLE, color: Color = Palette.INK) -> Label:
	var l := label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func wrap_label(text: String, size: int = Palette.F_BODY, color: Color = Palette.INK_SOFT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## 主按钮（金色） / 次按钮（浅底）。
static func button(text: String, primary: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", Palette.F_H3)

	var base := Palette.ACCENT if primary else Palette.CARD_SOFT
	var hover := Palette.ACCENT_DEEP if primary else Palette.CARD_EDGE
	var fg := Palette.ON_DARK if primary else Palette.INK

	b.add_theme_stylebox_override("normal", _btn_style(base, fg))
	b.add_theme_stylebox_override("hover", _btn_style(hover, fg))
	b.add_theme_stylebox_override("pressed", _btn_style(hover.darkened(0.12), fg))
	b.add_theme_stylebox_override("disabled", _btn_style(Palette.ZONE_GAP, Palette.INK_FAINT))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Palette.INK_FAINT)
	return b


static func _btn_style(bg: Color, _fg: Color) -> StyleBoxFlat:
	var sb := flat(bg, Palette.RADIUS_SM + 2)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	return sb


## 进度条：一条圆角底 + 一条彩色填充。
static func progress(fill: Color, height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)

	var bg := flat(Palette.CARD_SOFT, height / 2)
	bg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)

	var fg := flat(fill, height / 2)
	fg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


## 竖直留白。
static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 一条横向细分割线。
static func divider(color: Color = Palette.CARD_EDGE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 贴一张图，等比居中，缺图时给灰色占位。
static func picture(path: String, min_size: Vector2, tint: Color = Color.WHITE) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = min_size
	tr.texture = load_texture(path)
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 按图片真实宽高比算一个能完整塞进 max_size 的框。
##
## `picture()` 用的是固定 custom_minimum_size —— 框的比例和图片不一致时，
## STRETCH_KEEP_ASPECT_CENTERED 会先把图缩到刚好盖住框再居中，超出的部分直接裁掉。
## 竖版图放进横版框会切掉上下，横版图放进竖版框会切掉左右。
## 这个版本让框跟着图走，一张都不裁。
static func picture_fit(path: String, max_size: Vector2, tint: Color = Color.WHITE) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = load_texture(path)

	var size := max_size
	var tex := tr.texture
	if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
		var ar := float(tex.get_width()) / float(tex.get_height())
		var w := max_size.x
		var h := w / ar
		if h > max_size.y:
			h = max_size.y
			w = h * ar
		size = Vector2(maxf(w, 1.0), maxf(h, 1.0))
	tr.custom_minimum_size = size
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 加载贴图，失败时返回 8x8 灰块，绝不让 UI 因为缺图崩掉。
static func load_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if path != "":
		push_warning("[ui] 贴图缺失: " + path)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Palette.ZONE_GAP)
	return ImageTexture.create_from_image(img)
