extends Control

## 主菜单 + 设置。整个游戏唯一的入口。
##
## 菜单和设置合成一页：这个游戏需要玩家配置的只有难度，
## 再拆一个「设置」子页面点进去选一次难度是纯多余的操作。
##
## 难度写进 user://settings.json，game_root 启动时读回来套到 GameTuning 上。
## 选完点「开始钓鱼」→ change_scene_to_file("res://main.tscn")。

const GAME_SCENE := "res://main.tscn"
const GALLERY_SCENE := "res://gallery.tscn"
const ABOUT_SCENE := "res://about.tscn"

var _settings: GameSettings = null
var _tuning: GameTuning = null
var _options: Array = []
var _buttons: Dictionary = {}
var _blurb: Label = null
var _audio_rows: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_settings = GameSettings.load_settings()
	_tuning = ConfigLoader.load_tuning()
	_options = _tuning.difficulty_options()

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

	# 远山：两层压扁的椭圆，纯装饰
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

	# 水面高光
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

	var logo := UIKit.picture_fit("res://assets/logo.png", Vector2(300, 100))
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)

	col.add_child(UIKit.title("钓肥鱼", Palette.F_TITLE))
	var sub := UIKit.label("有限的饵，喂饱这几条鱼", Palette.F_BODY, Palette.INK_FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(UIKit.spacer(4))
	col.add_child(UIKit.divider())

	var cap := UIKit.label("难度", Palette.F_SMALL, Palette.INK_SOFT)
	col.add_child(cap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for opt in _options:
		var b := UIKit.button(String(opt["label"]), false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", Palette.F_BODY)
		b.pressed.connect(_on_pick.bind(String(opt["key"])))
		row.add_child(b)
		_buttons[String(opt["key"])] = b

	_blurb = UIKit.wrap_label("", Palette.F_SMALL, Palette.INK_SOFT)
	_blurb.custom_minimum_size = Vector2(0, 36)
	col.add_child(_blurb)

	_build_audio_section(col)

	col.add_child(UIKit.divider())

	var start := UIKit.button("开 始 钓 鱼", true)
	start.pressed.connect(_on_start)
	col.add_child(start)

	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 8)
	col.add_child(footer_row)

	var gallery := UIKit.button("图 鉴", false)
	gallery.add_theme_font_size_override("font_size", Palette.F_BODY)
	gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery.pressed.connect(_on_gallery)
	footer_row.add_child(gallery)

	var about := UIKit.button("关 于", false)
	about.add_theme_font_size_override("font_size", Palette.F_BODY)
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about.pressed.connect(_on_about)
	footer_row.add_child(about)

	var quit := UIKit.button("退 出", false)
	quit.add_theme_font_size_override("font_size", Palette.F_BODY)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	footer_row.add_child(quit)

	_refresh_selection()
	_wire_audio_rows()


# ---------- 声音 ----------

func _build_audio_section(col: VBoxContainer) -> void:
	col.add_child(UIKit.spacer(2))
	col.add_child(UIKit.divider())
	col.add_child(UIKit.label("声音", Palette.F_SMALL, Palette.INK_SOFT))
	_audio_rows["bgm"] = _build_audio_row(col, "背景音乐", _settings.bgm_on, _settings.bgm_volume)
	_audio_rows["voice"] = _build_audio_row(col, "语音", _settings.voice_on, _settings.voice_volume)


## 一行 = 名字 + 开关 + 滑块 + 百分比。返回这三个控件，方便之后回灌状态。
func _build_audio_row(col: VBoxContainer, caption: String, on: bool, vol: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var name_label := UIKit.label(caption, Palette.F_SMALL, Palette.INK)
	name_label.custom_minimum_size = Vector2(70, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = on
	toggle.custom_minimum_size = Vector2(52, 0)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.add_theme_font_size_override("font_size", Palette.F_SMALL)
	toggle.text = "开" if on else "关"
	row.add_child(toggle)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = vol
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var pct := UIKit.label("%d%%" % roundi(vol * 100.0), Palette.F_SMALL, Palette.INK_SOFT)
	pct.custom_minimum_size = Vector2(42, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)

	return {"toggle": toggle, "slider": slider, "pct": pct, "name": caption}


## 两个通道接同一套回调，靠 channel 反查是哪一路。
func _wire_audio_rows() -> void:
	for channel in _audio_rows.keys():
		var ui: Dictionary = _audio_rows[channel]
		var toggle: Button = ui["toggle"]
		var slider: HSlider = ui["slider"]
		toggle.toggled.connect(_on_audio_toggle.bind(String(channel)))
		slider.value_changed.connect(_on_audio_slider.bind(String(channel)))
		_style_toggle(toggle)


func _on_audio_toggle(pressed: bool, channel: String) -> void:
	if channel == "bgm":
		_settings.bgm_on = pressed
	else:
		_settings.voice_on = pressed
	var ui: Dictionary = _audio_rows[channel]
	var toggle: Button = ui["toggle"]
	toggle.text = "开" if pressed else "关"
	_style_toggle(toggle)
	_settings.save()
	Audio.apply_settings(_settings)


func _on_audio_slider(value: float, channel: String) -> void:
	if channel == "bgm":
		_settings.bgm_volume = value
	else:
		_settings.voice_volume = value
	var ui: Dictionary = _audio_rows[channel]
	var pct: Label = ui["pct"]
	pct.text = "%d%%" % roundi(value * 100.0)
	_settings.save()
	Audio.apply_settings(_settings)


func _style_toggle(toggle: Button) -> void:
	var on := toggle.button_pressed
	var base := Palette.ACCENT if on else Palette.CARD_SOFT
	var hover := Palette.ACCENT_DEEP if on else Palette.CARD_EDGE
	var fg := Palette.ON_DARK if on else Palette.INK_SOFT
	toggle.add_theme_stylebox_override("normal", _btn_box(base))
	toggle.add_theme_stylebox_override("hover", _btn_box(hover))
	toggle.add_theme_stylebox_override("pressed", _btn_box(hover.darkened(0.12)))
	toggle.add_theme_color_override("font_color", fg)
	toggle.add_theme_color_override("font_hover_color", fg)
	toggle.add_theme_color_override("font_pressed_color", fg)


# ---------- 交互 ----------

func _on_pick(key: String) -> void:
	_settings.difficulty = key
	_settings.save()
	_refresh_selection()


func _refresh_selection() -> void:
	for key in _buttons.keys():
		var b: Button = _buttons[key]
		var active: bool = String(key) == _settings.difficulty
		var base := Palette.ACCENT if active else Palette.CARD_SOFT
		var hover := Palette.ACCENT_DEEP if active else Palette.CARD_EDGE
		var fg := Palette.ON_DARK if active else Palette.INK
		b.add_theme_stylebox_override("normal", _btn_box(base))
		b.add_theme_stylebox_override("hover", _btn_box(hover))
		b.add_theme_stylebox_override("pressed", _btn_box(hover.darkened(0.12)))
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", fg)
		b.add_theme_color_override("font_pressed_color", fg)

	if _blurb != null:
		_blurb.text = _blurb_of(_settings.difficulty)


func _blurb_of(key: String) -> String:
	for opt in _options:
		if String(opt["key"]) == key:
			return String(opt["blurb"])
	return ""


func _btn_box(bg: Color) -> StyleBoxFlat:
	var sb := UIKit.flat(bg, Palette.RADIUS_SM + 2)
	sb.set_content_margin_all(10)
	return sb


func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_gallery() -> void:
	get_tree().change_scene_to_file(GALLERY_SCENE)


func _on_about() -> void:
	get_tree().change_scene_to_file(ABOUT_SCENE)
