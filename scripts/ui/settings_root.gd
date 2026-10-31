extends Control

## 设置页：难度 + 声音。
##
## 主菜单只放「开始」，需要调的东西全收进这里 —— 一张卡上同时摆难度按钮和
## 两个音量滑块，玩家进来一次就能改完，不用来回跳。
##
## 每改一项立刻写盘（GameSettings.save）并同时推给 Audio，
## 所以从这里退出去打一局，改动已经生效了，没有「保存」按钮。

const MENU_SCENE := "res://menu.tscn"

var _settings: GameSettings = null
var _tuning: GameTuning = null
var _options: Array = []
var _buttons: Dictionary = {}
var _blurb: Label = null
var _audio_rows: Dictionary = {}
var _lang_buttons: Dictionary = {}
var _reset_btn: Button = null
var _reset_hint: Label = null
var _reset_armed: bool = false
var _reset_timer: SceneTreeTimer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_settings = GameSettings.load_settings()
	_tuning = ConfigLoader.load_tuning()
	_options = _tuning.difficulty_options()

	_build_background()
	_build_card()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


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

	col.add_child(UIKit.title(tr("设 置"), Palette.F_TITLE))

	col.add_child(UIKit.spacer(2))
	col.add_child(UIKit.label(tr("难度"), Palette.F_SMALL, Palette.INK_SOFT))

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

	col.add_child(UIKit.spacer(2))
	col.add_child(UIKit.divider())
	col.add_child(UIKit.label(tr("语言"), Palette.F_SMALL, Palette.INK_FAINT))

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	col.add_child(lang_row)
	for code in GameSettings.LANGUAGES:
		var lb := UIKit.button(_lang_label(code), false)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.add_theme_font_size_override("font_size", Palette.F_BODY)
		lb.pressed.connect(_on_language.bind(String(code)))
		lang_row.add_child(lb)
		_lang_buttons[String(code)] = lb

	col.add_child(UIKit.spacer(2))
	col.add_child(UIKit.divider())
	col.add_child(UIKit.label(tr("声音"), Palette.F_SMALL, Palette.INK_SOFT))
	_audio_rows["bgm"] = _build_audio_row(col, tr("背景音乐"), _settings.bgm_on, _settings.bgm_volume)
	_audio_rows["voice"] = _build_audio_row(col, tr("语音"), _settings.voice_on, _settings.voice_volume)

	col.add_child(UIKit.divider())
	col.add_child(UIKit.label(tr("回到开头"), Palette.F_SMALL, Palette.INK_SOFT))

	_reset_btn = UIKit.button(tr("从头再来一次"), false)
	_reset_btn.pressed.connect(_on_reset_progress)
	col.add_child(_reset_btn)

	_reset_hint = UIKit.wrap_label(
		tr("图鉴、封号次数、「齐人之福」都会回到最初的样子。难度和音量不动。"),
		Palette.F_SMALL, Palette.INK_FAINT)
	_reset_hint.custom_minimum_size = Vector2(0, 34)
	col.add_child(_reset_hint)

	col.add_child(UIKit.divider())

	var back := UIKit.button(tr("返 回"), true)
	back.pressed.connect(_back)
	col.add_child(back)

	_refresh_selection()
	_wire_audio_rows()


## 一行 = 名字 + 开关 + 滑块 + 百分比。
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
	toggle.text = tr("开") if on else tr("关")
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
	toggle.text = tr("开") if pressed else tr("关")
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

	for code in _lang_buttons.keys():
		var lb: Button = _lang_buttons[code]
		var on: bool = String(code) == _settings.language
		var base2 := Palette.ACCENT if on else Palette.CARD_SOFT
		var hover2 := Palette.ACCENT_DEEP if on else Palette.CARD_EDGE
		var fg2 := Palette.ON_DARK if on else Palette.INK
		lb.add_theme_stylebox_override("normal", _btn_box(base2))
		lb.add_theme_stylebox_override("hover", _btn_box(hover2))
		lb.add_theme_stylebox_override("pressed", _btn_box(hover2.darkened(0.12)))
		lb.add_theme_color_override("font_color", fg2)
		lb.add_theme_color_override("font_hover_color", fg2)
		lb.add_theme_color_override("font_pressed_color", fg2)

	if _blurb != null:
		_blurb.text = _blurb_of(_settings.difficulty)


## 语言按钮上写的话要一直显示中文名 —— 英文界面下 "Chinese" 也认不出是哪个。
## 换语言后整页文案跟着变，但按钮标识本身保持原样。
func _lang_label(code: String) -> String:
	match code:
		"zh_CN": return "简体中文"
		"en": return "English"
	return code


func _on_language(code: String) -> void:
	if _settings.language == code:
		return
	_settings.language = code
	_settings.save()
	_settings.apply_language()
	_rebuild_page()


## 切语言后整页重画。tr() 只在构建时求值，不重建的话文字还是旧语种。
func _rebuild_page() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_audio_rows.clear()
	_lang_buttons.clear()
	_blurb = null
	_reset_btn = null
	_reset_hint = null
	_reset_armed = false
	_options = _tuning.difficulty_options()
	_build_background()
	_build_card()


func _blurb_of(key: String) -> String:
	for opt in _options:
		if String(opt["key"]) == key:
			return String(opt["blurb"])
	return ""


func _btn_box(bg: Color) -> StyleBoxFlat:
	var sb := UIKit.flat(bg, Palette.RADIUS_SM + 2)
	sb.set_content_margin_all(10)
	return sb


## 两段式确认：第一下把按钮改成问句，四秒内再点一下才动手。
## 话说得轻一点 —— 清档不是惩罚，是想把这段路再走一遍。
func _on_reset_progress() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = tr("确定要从头再来吗？")
		_reset_hint.text = tr("一定是主人想陪我们再走一遍 —— 再点一次就开始。")
		_reset_hint.add_theme_color_override("font_color", Palette.ACCENT_DEEP)
		_disarm_later()
		return

	_reset_armed = false
	_reset_btn.text = tr("从头再来一次")
	_reset_hint.text = tr("好啦，那就从第一碗白饭重新开始。我们还在。")
	_reset_hint.add_theme_color_override("font_color", Palette.GOOD)
	Gallery.clear()
	# clear() 删的是整个文件，图鉴与 claude_stage 一起归零


func _disarm_later() -> void:
	var timer := get_tree().create_timer(4.0)
	_reset_timer = timer
	await timer.timeout
	# 四秒内没点第二下就撤销，按钮恢复原样
	if _reset_armed:
		_reset_armed = false
		_reset_btn.text = tr("从头再来一次")
		_reset_hint.text = tr("图鉴、封号次数、「齐人之福」都会回到最初的样子。难度和音量不动。")
		_reset_hint.add_theme_color_override("font_color", Palette.INK_FAINT)


func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
