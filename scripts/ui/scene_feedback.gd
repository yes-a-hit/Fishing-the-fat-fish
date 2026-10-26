class_name SceneFeedback
extends Control

## 场景内的一次性文字提示，用来替代原来的「结果卡面板」。
##
## 空竿、断线、这条钓过了 —— 这些只需要一句话，不值得占一整个面板。
## 文字直接浮在湖面上，淡入、停一下、淡出，不打断画面。

const HOLD_DEFAULT := 1.6

var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = UIKit.label("", Palette.F_TITLE, Palette.ON_DARK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.09, 0.65))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)

	resized.connect(_layout)


func _layout() -> void:
	_label.position = Vector2(0, size.y * 0.30)
	_label.size = Vector2(size.x, 56)


## 弹一句话。同一时间只显示一条，新的会打断旧的。
func show_text(text: String, color: Color = Palette.ON_DARK, hold: float = HOLD_DEFAULT) -> void:
	_layout()
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_label.modulate.a = 0.0

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, 0.14)
	_tween.tween_interval(hold)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.38)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 0.0
