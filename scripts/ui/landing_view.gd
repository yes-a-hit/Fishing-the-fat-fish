class_name LandingView
extends Control

## 上鱼飞扑动画。
##
## 体力磨空后，鱼从浮标所在的水面位置「飞」出来，带旋转和缩放扑向屏幕中央，
## 落地后报一句台词，然后淡出回到抛竿。
##
## 刻意做得短（约 2.4 秒）且不能跳过 —— 它是这一轮唯一的正反馈，
## 值得让玩家看完；但又不能长到打断节奏。
##
## 这里只播动画，判定「是否上鱼」已经在 FishingSession 里做完了。

const FISH_SIZE := 460.0
const FLIGHT_SECONDS := 0.55
const HOLD_SECONDS := 1.5

signal finished

var _dim: ColorRect = null
var _fish: TextureRect = null
var _line: Label = null
var _playing: bool = false
var _elapsed: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.035, 0.098, 0.129, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_fish = TextureRect.new()
	_fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fish.size = Vector2(FISH_SIZE, FISH_SIZE)
	_fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fish)

	_line = UIKit.label("", Palette.F_H2, Palette.ON_DARK)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_line.add_theme_constant_override("shadow_offset_x", 0)
	_line.add_theme_constant_override("shadow_offset_y", 3)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _elapsed >= FLIGHT_SECONDS + HOLD_SECONDS:
		_finish()


## 播一次。from_pos 是浮标在屏幕上的位置，鱼从那里飞出来。
func play(fish: FishSpec, from_pos: Vector2) -> void:
	if fish == null:
		_finish()
		return

	_playing = true
	_elapsed = 0.0
	visible = true

	_fish.texture = UIKit.load_texture(fish.portrait)
	var tint := fish.tint
	_fish.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	_fish.pivot_offset = _fish.size * 0.5
	_fish.position = from_pos - _fish.size * 0.5
	_fish.scale = Vector2(0.12, 0.12)
	_fish.rotation = -0.42

	_dim.color = Color(0.035, 0.098, 0.129, 0.0)

	var target := Vector2(size.x * 0.5, size.y * 0.44) - _fish.size * 0.5

	_line.text = fish.tagline
	_line.modulate.a = 0.0
	_line.position = Vector2(0, size.y * 0.44 + FISH_SIZE * 0.30)
	_line.size = Vector2(size.x, 40)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.52, 0.30)
	tw.tween_property(_fish, "modulate:a", 1.0, 0.16)
	tw.tween_property(_fish, "position", target, FLIGHT_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fish, "scale", Vector2.ONE, FLIGHT_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fish, "rotation", 0.0, FLIGHT_SECONDS) \
		.set_trans(Tween.TRANS_SINE)

	tw.chain().tween_property(_line, "modulate:a", 1.0, 0.25)


func _finish() -> void:
	if not _playing:
		return
	_playing = false

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.0, 0.26)
	tw.tween_property(_fish, "modulate:a", 0.0, 0.22)
	tw.tween_property(_line, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(_on_fade_done)


func _on_fade_done() -> void:
	visible = false
	_fish.texture = null
	finished.emit()
