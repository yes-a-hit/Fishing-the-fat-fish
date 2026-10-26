class_name HudView
extends PanelContainer

## 顶部状态栏：白饭余量 / 已钓进度 / 阶段提示。
##
## 鱼的数量是动态的 —— 加一条鱼，这里自动多一个 chip，不用改代码。

var _bowl_row: HBoxContainer = null
var _bait_label: Label = null
var _chips_row: HBoxContainer = null
var _hint_label: Label = null
var _chips: Dictionary = {}     # fish_id -> Label
var _names: Dictionary = {}     # fish_id -> String


func setup(fish_list: Array) -> void:
	var sb := UIKit.flat(Color(1, 1, 1, 0.82), Palette.RADIUS, Palette.CARD_EDGE, 1)
	sb.set_content_margin_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(row)

	# ---- 左：白饭 ----
	var bait_box := HBoxContainer.new()
	bait_box.add_theme_constant_override("separation", 5)
	bait_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bait_box)

	_bowl_row = HBoxContainer.new()
	_bowl_row.add_theme_constant_override("separation", 2)
	_bowl_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bait_box.add_child(_bowl_row)

	_bait_label = UIKit.label("", Palette.F_H3, Palette.INK)
	_bait_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bait_box.add_child(_bait_label)

	row.add_child(_vline())

	# ---- 中：已钓进度 ----
	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 12)
	_chips_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chips_row)

	for f in fish_list:
		var chip := UIKit.label(f.display_name, Palette.F_BODY, Palette.INK_FAINT)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chips_row.add_child(chip)
		_chips[f.id] = chip
		_names[f.id] = f.display_name

	row.add_child(_vline())

	# ---- 右：阶段提示 ----
	_hint_label = UIKit.label("", Palette.F_BODY, Palette.INK_SOFT)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.custom_minimum_size = Vector2(280, 0)
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint_label)


## 重建白饭图标（数量变了才需要调）。
func refresh_bait(left: int, total: int) -> void:
	_bait_label.text = "白饭 %d / %d" % [left, total]

	if _bowl_row.get_child_count() != total:
		for c in _bowl_row.get_children():
			c.queue_free()
		for i in total:
			var icon := BowlIcon.new()
			_bowl_row.add_child(icon)

	for i in _bowl_row.get_child_count():
		var icon := _bowl_row.get_child(i) as BowlIcon
		if icon != null:
			icon.set_filled(i < left)


func refresh_caught(caught: Array) -> void:
	for fish_id in _chips.keys():
		var chip: Label = _chips[fish_id]
		var got := caught.has(fish_id)
		chip.text = ("✓ " if got else "") + String(_names.get(fish_id, fish_id))
		chip.add_theme_color_override("font_color", Palette.GOOD if got else Palette.INK_FAINT)


func set_hint(text: String) -> void:
	_hint_label.text = text


func _vline() -> ColorRect:
	var r := ColorRect.new()
	r.color = Palette.CARD_EDGE
	r.custom_minimum_size = Vector2(1, 26)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r
