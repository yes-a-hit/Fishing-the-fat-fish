class_name CastPanel
extends PanelContainer

## 抛竿面板。**蓄力滚动条只出现在这里，搏斗阶段绝不复用。**
##
## 玩法：按住 → 游标从 0 往 100 循环走；松手 → 当前值就是抛竿力气。
##
## 界面刻意只有一条槽 + 一块牌子（见 CastBar）：**不画分区、不点名鱼**。
## 距离带之间是重叠的，同一点可能钓到不同的鱼，
## 任何能看出「这截归谁」的提示都等于直接给答案。

var _bar: CastBar = null
var _aim_label: Label = null
var _shadows: Array = []


## 两个参数都保留是为了不改调用方 —— 分区已经不再参与显示。
func setup(_fish_list: Array, _zones: Array) -> void:
	var sb := UIKit.flat(Color(1, 1, 1, 0.94), Palette.RADIUS, Palette.CARD_EDGE, 1)
	sb.set_content_margin_all(18)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 5)
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)

	var t := UIKit.label(tr("抛　竿"), Palette.F_H3, Palette.INK)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)

	_aim_label = UIKit.label(tr("按住蓄力"), Palette.F_BODY, Palette.INK_FAINT)
	_aim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_aim_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_aim_label)

	_bar = CastBar.new()
	_bar.configure([], [], {}, _shadows)
	col.add_child(_bar)

	var tip := UIKit.label(tr("按住蓄力，牌子会一直往前走。松手才抛 —— 转多少圈都不算输，看准了再放。"),
		Palette.F_SMALL, Palette.INK_FAINT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tip)


func set_charge(value: float) -> void:
	_bar.set_charge(value)
	# 只报状态，不报是哪条鱼 —— 牌子上的水域描述已经够了
	if value > 0.02:
		_aim_label.text = tr("松手抛竿")
		_aim_label.add_theme_color_override("font_color", Palette.INK)
	else:
		_aim_label.text = tr("按住蓄力")
		_aim_label.add_theme_color_override("font_color", Palette.INK_FAINT)


func refresh_caught(_caught: Array) -> void:
	_bar.configure([], [], {}, _shadows)


## 每局开始时调用一次：把这一局的鱼影交给距离条去画。
func set_shadows(list: Array) -> void:
	_shadows = list.duplicate()
	_bar.configure([], [], {}, _shadows)


## 阶段切换时把游标归零，避免上一局的残影。
func reset() -> void:
	_bar.set_charge(0.0)
	_aim_label.text = tr("按住蓄力")
	_aim_label.add_theme_color_override("font_color", Palette.INK_FAINT)
