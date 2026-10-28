class_name EndingOverlay
extends Control

## 结算画面。全屏遮罩 + 居中卡片。
##
## 数据全部来自 data/endings.json 和 FishingSession.summary()，
## 这里不判断输赢，只负责把结果摆好看。

signal restart_requested
signal menu_requested

var _box: VBoxContainer = null
var _scroll: ScrollContainer = null
var _footer: HBoxContainer = null

## 多图结局（claude_fake 那三段 meme）用这两组状态翻页。
## 只有 pages 非空时才走翻页路径，单图结局完全不受影响。
var _pages: Array = []
var _page_index: int = 0
var _page_box: VBoxContainer = null
var _page_data: Dictionary = {}
var _page_summary: Dictionary = {}
var _page_fish: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_ending(ending_key: String, data: Dictionary, summary: Dictionary, fish_list: Array) -> void:
	_clear()
	visible = true

	var dim := ColorRect.new()
	dim.color = Color(0.055, 0.129, 0.169, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	# 整页竖排：上面是可滚动的内容，下面是固定在屏幕内的按钮条。
	#
	# 早先是把按钮放进 ScrollContainer 一起滚的 —— 桌面端靠滚轮还行，
	# 手机上 ScrollContainer 一拖不动，三个按钮就永远够不着，游戏卡死在这儿。
	# 按钮条移出滚动区，无论如何都在视野里。
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	# 宽屏别把卡片拉成一条，窄屏铺满
	page.custom_minimum_size = Vector2(minf(get_viewport_rect().size.x - 32.0, 660.0), 0)
	page.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(page)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = false
	page.add_child(_scroll)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 24)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(card)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	card.add_child(_box)

	# 副标题（PERFECT / CLEAR / OUT OF RICE）
	var subtitle := UIKit.label(String(data.get("subtitle", "")), Palette.F_SMALL, Palette.ACCENT_DEEP)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(subtitle)

	# 主标题
	var title := UIKit.title(String(data.get("title", "结算")), Palette.F_TITLE, Palette.INK)
	_box.add_child(title)

	_box.add_child(UIKit.spacer(2))

	# 正文
	var lines: PackedStringArray = []
	for l in data.get("lines", []):
		lines.append(String(l))
	if not lines.is_empty():
		var body := UIKit.wrap_label("\n".join(lines), Palette.F_BODY, Palette.INK_SOFT)
		_box.add_child(body)

	_box.add_child(UIKit.spacer(4))
	_box.add_child(UIKit.divider())
	_box.add_child(UIKit.spacer(4))

	# 多图结局：图和台词随页替换，统计和按钮放完再出现
	_pages = data.get("pages", [])
	_page_index = 0
	_page_data = data
	_page_summary = summary
	_page_fish = fish_list

	_page_box = VBoxContainer.new()
	_page_box.add_theme_constant_override("separation", 6)
	_box.add_child(_page_box)

	# 按钮条永远在滚动区外面
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_footer)

	if not _pages.is_empty():
		_show_page()
		return

	_box.add_child(_stats_block(summary, fish_list))
	_add_buttons()


## 画当前这一页：图 + 一句台词。
func _show_page() -> void:
	for child in _page_box.get_children():
		child.queue_free()

	var page: Dictionary = _pages[_page_index]
	# 图统一按可用高度再收一道，翻到最后一页时统计和三个按钮才有地方站
	var max_h := clampf(get_viewport_rect().size.y * 0.36, 220.0, 380.0)
	var img := UIKit.picture_fit(String(page.get("image", "")), Vector2(400, max_h))
	_page_box.add_child(img)

	var caption := UIKit.wrap_label(String(page.get("caption", "")), Palette.F_BODY, Palette.INK)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_box.add_child(caption)

	var dots := UIKit.label("%d / %d" % [_page_index + 1, _pages.size()], Palette.F_SMALL, Palette.INK_FAINT)
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_box.add_child(dots)

	# 把上一页留下的按钮和统计清掉
	for child in _box.get_children():
		if child.has_meta("tail"):
			child.queue_free()

	var tail := VBoxContainer.new()
	tail.set_meta("tail", true)
	tail.add_theme_constant_override("separation", 8)
	_box.add_child(tail)

	if _page_index < _pages.size() - 1:
		var next := UIKit.button("……")
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next.pressed.connect(_next_page)
		_footer.add_child(next)
		return

	tail.add_child(UIKit.spacer(4))
	tail.add_child(UIKit.divider())
	tail.add_child(UIKit.spacer(4))
	tail.add_child(_stats_block(_page_summary, _page_fish))
	_add_buttons()


func _next_page() -> void:
	if _page_index >= _pages.size() - 1:
		return
	_page_index += 1
	_show_page()
	# 翻到新页回到顶部，最后一页有统计和按钮，别让人先看到半截
	_reset_scroll()

## 翻页/换局都把滚动条拉回顶端，否则会停在上一次的位置。
func _reset_scroll() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = 0
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


func _add_buttons(parent: Control = null) -> void:
	# 按钮条默认落在 _footer —— 它在 ScrollContainer 外面，
	# 内容再长也顶不掉，手机上一定点得到。
	if _footer == null:
		_footer = HBoxContainer.new()
		_footer.add_theme_constant_override("separation", 10)
		_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(_footer)

	var btns := _footer if parent == null else HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if btns != _footer:
		parent.add_child(btns)

	var again := UIKit.button("再来一局", true, true)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func(): restart_requested.emit())
	btns.add_child(again)

	var menu := UIKit.button("返回菜单", false, true)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): menu_requested.emit())
	btns.add_child(menu)

	var quit := UIKit.button("退出", false, true)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	btns.add_child(quit)


func hide_overlay() -> void:
	visible = false
	_clear()


func _stats_block(summary: Dictionary, fish_list: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 26)
	line1.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(line1)

	line1.add_child(_stat("用饵", "%d / %d" % [
		int(summary.get("bait_used", 0)), int(summary.get("bait_total", 0))
	]))
	line1.add_child(_stat("上鱼", "%d / %d" % [
		int(summary.get("caught_count", 0)), int(summary.get("fish_total", 0))
	]))
	line1.add_child(_stat("轮次", str(int(summary.get("rounds", 0)))))

	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 26)
	line2.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(line2)

	line2.add_child(_stat("命中", str(int(summary.get("good", 0))), Palette.GOOD))
	line2.add_child(_stat("完美", str(int(summary.get("perfect", 0))), Palette.ACCENT_DEEP))
	line2.add_child(_stat("失手", str(int(summary.get("miss", 0))), Palette.BAD))

	# 每条鱼的收集状态 —— 鱼多鱼少都能摆
	var caught: Array = summary.get("caught", [])
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 14)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(chips)

	for f in fish_list:
		var got := caught.has(f.id)
		var chip := UIKit.label(
			("✓ " if got else "✗ ") + f.display_name,
			Palette.F_SMALL,
			Palette.GOOD if got else Palette.INK_FAINT
		)
		chips.add_child(chip)

	return col


func _stat(caption: String, value: String, value_color: Color = Palette.INK) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)

	var v := UIKit.label(value, Palette.F_H3, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)

	var c := UIKit.label(caption, Palette.F_SMALL, Palette.INK_FAINT)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(c)
	return col


func _clear() -> void:
	_pages = []
	_page_index = 0
	_page_box = null
	_scroll = null
	_footer = null
	for child in get_children():
		child.queue_free()
