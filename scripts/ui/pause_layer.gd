class_name PauseLayer
extends Control

## 暂停遮罩：一层压暗 + 一张三按钮卡片。
##
## 这段原本现搓在 game_root._pause_game() 里，混在七百行的根节点中间，也和
## 项目「一个 overlay 一个脚本」的惯例不一致。现在它只负责长相和发信号，
## 「冻不冻场景树、要不要重开」由 game_root 决定。
##
## 信号：
##   resumed        点了「继续」
##   restarted      点了「重新开始」
##   quit_requested 点了「返回菜单」

signal resumed
signal restarted
signal quit_requested


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 摆上这一层的时候场景树已经冻住了，遮罩自己必须照常跑，否则按钮按不动。
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.12, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 26)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	col.add_child(UIKit.title(tr("已 暂 停"), Palette.F_H2))
	col.add_child(UIKit.divider())

	var resume := UIKit.button(tr("继 续"), true, true)
	resume.pressed.connect(func(): resumed.emit())
	col.add_child(resume)

	var restart := UIKit.button(tr("重 新 开 始"), false, true)
	restart.pressed.connect(func(): restarted.emit())
	col.add_child(restart)

	var menu := UIKit.button(tr("返 回 菜 单"), false, true)
	menu.pressed.connect(func(): quit_requested.emit())
	col.add_child(menu)
