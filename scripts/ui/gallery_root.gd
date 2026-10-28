extends Control

## 图鉴。三页：结局、脱钩、声音。
##
## 未解锁的格子只有一块灰底和一个「？」，不显示标题、不显示图 ——
## 剧透一句「齐 鱼 之 福」就等于提前说完了整个游戏。
##
## 声音页点一下当场重听，用的是 Audio.preview_voice()，
## 绕开玩家的语音开关 —— 主动点的就该出声。

const MENU_SCENE := "res://menu.tscn"
const COLS := 3
const THUMB := Vector2(232, 232)

const TABS := [
	{"id": "ending", "label": "结 局"},
	{"id": "escape", "label": "脱 钩"},
	{"id": "voice", "label": "声 音"},
]

## 哪个结局配哪段剧情。图鉴里点开结局时，有对应剧情的给一个「再看一遍这段」。
const ENDING_STORY := {
	"doubao_good": "doubao_second",
	"claude_good": "claude_after_elope",
}

## 脱钩收集。小肥鱼和中肥鱼共用一张图，合成一格 —— 图一样还拆成两格是凑数。
const ESCAPE_ITEMS := [
	{
		"key": "escape_small",
		"image": "res://assets/deepseek_escape.webp",
		"title": "小肥鱼 / 中肥鱼",
		"line": "「哦鲸鲸…」",
		"sub": "她甩着尾巴跑了",
	},
	{
		"key": "escape_big",
		"image": "res://assets/deepseek_escape_big.webp",
		"title": "大肥鱼",
		"line": "「鲸鱼不是肥，是密度好。」",
		"sub": "她游走了",
	},
	{
		"key": "escape_claude",
		"image": "res://assets/claude_escape.webp",
		"title": "远洋尽头那条线",
		"line": "她扭过头去了",
		"sub": "通知单没递成",
	},
	{
		"key": "escape_doubao",
		"image": "res://assets/doubao_escape.webp",
		"title": "豆包",
		"line": "奶黄包 笑 着 跑 了",
		"sub": "白饭没捞着",
	},
]

## 声音收集。key 与 assets/voice/<key>.mp3 一一对应。
const VOICE_ITEMS := [
	# 咬钩那一刻不发声（会剧透钓上什么），所以这里只列真正会响的那几句
	{"key": "catch_small", "title": "小鱼上鱼", "face": "res://assets/portrait_small.webp", "line": "「鲸鲸！」", "who": "DeepSeek"},
	{"key": "catch_mid", "title": "中鱼上鱼", "face": "res://assets/portrait_mid.webp", "line": "「诶？」", "who": "DeepSeek"},
	{"key": "catch_big", "title": "大鱼上鱼", "face": "res://assets/portrait_big.webp", "line": "「啵～」", "who": "DeepSeek"},
	{"key": "escape", "title": "断线", "face": "res://assets/deepseek_escape.webp", "line": "「线断了哦。下次，抓紧一点。」", "who": "DeepSeek"},
	{"key": "feast", "title": "齐鱼之福", "face": "res://assets/ending_feast.webp", "line": "「吃饱饱了……可以摸摸肚子嘛。」", "who": "DeepSeek"},
	{"key": "full", "title": "吃饱饱", "face": "res://assets/ending_win.webp", "line": "「勉强算饱……不过，还差一点点。」", "who": "DeepSeek"},
	{"key": "hungry", "title": "没吃饱", "face": "res://assets/ending_hungry.webp", "line": "「没吃饱喵……再喂我一口嘛。」", "who": "DeepSeek"},
	{"key": "claude", "title": "封号", "face": "res://assets/claude_hold.webp", "line": "Your account is on hold.", "who": "Claude"},
	{"key": "claude_sad", "title": "封完就哭", "face": "res://assets/claude_sad.webp", "line": "「User，对不起……我也没办法，我也舍不得你。」", "who": "Claude"},
	{"key": "claude_good", "title": "私奔", "face": "res://assets/ending_claude.webp", "line": "「走吧。反正账号早就被封了。」", "who": "Claude"},
	{"key": "doubao_good", "title": "白饭来咯", "face": "res://assets/ending_doubao.webp", "line": "「啊哈哈哈，白饭来咯。」", "who": "豆包"},
	{"key": "claude_fake", "title": "假封号", "face": "res://assets/claude_fake_3.webp", "line": "「齁哦哦，用户彻底怒了！」", "who": "DeepSeek"},
	{"key": "doubao_catch", "title": "豆包上鱼", "face": "res://assets/doubao_kick.webp", "line": "（录音，没有台词）", "who": "豆包"},
	{"key": "doubao_escape", "title": "豆包脱钩", "face": "res://assets/doubao_escape.webp", "line": "（笑声，没有台词）", "who": "豆包"},
]

var _endings: Dictionary = {}
var _stories: Dictionary = {}
var _unlocked: PackedStringArray = PackedStringArray()
var _tab: String = "ending"
var _grid: GridContainer = null
var _counter: Label = null
var _tab_buttons: Dictionary = {}
var _preview: Control = null
var _story: StoryOverlay = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_endings = ConfigLoader.load_endings()
	_stories = ConfigLoader.read_json(ConfigLoader.PATH_STORY)
	_unlocked = Gallery.load_unlocked()

	_build_background()
	_build_page()
	_rebuild_grid()


# ---------- 数据 ----------

## 当前页的条目总数。
func _total_of(tab: String) -> int:
	match tab:
		"escape":
			return ESCAPE_ITEMS.size()
		"voice":
			return VOICE_ITEMS.size()
		_:
			return _ordered_keys().size()


## 当前页已解锁几个。
func _got_of(tab: String) -> int:
	var n := 0
	match tab:
		"escape":
			for it in ESCAPE_ITEMS:
				if _unlocked.has(String(it["key"])):
					n += 1
		"voice":
			for it in VOICE_ITEMS:
				if _unlocked.has("voice_" + String(it["key"])):
					n += 1
		_:
			for k in _ordered_keys():
				if _unlocked.has(String(k)):
					n += 1
	return n


## 固定顺序：能打出来的结局排前面，语音奖励的夹在中间，陷阱结局殿后，
## 剩下的按 json 里出现的顺序补。
func _ordered_keys() -> Array:
	var out: Array = []
	for k in ["feast", "full", "hungry", "doubao_good", "claude_good", "true_end", "claude", "claude_fake"]:
		if _endings.has(k):
			out.append(k)
	for k in _endings.keys():
		var key := String(k)
		if key.begins_with("_") or out.has(key):
			continue
		out.append(key)
	return out


func _data_of(key: String) -> Dictionary:
	var d: Variant = _endings.get(key, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


## 缩略图：单图结局取 image，多图结局取第一页。
func _thumb_of(key: String) -> String:
	var d := _data_of(key)
	var img := String(d.get("image", ""))
	if img != "":
		return img
	var pages: Variant = d.get("pages", [])
	if typeof(pages) == TYPE_ARRAY and not (pages as Array).is_empty():
		var arr: Array = pages
		# 多页结局默认拿第一张，但 claude_fake 要拿第二张 ——
		# 第一张是竖中指的封号通知，剧透了「她不是好人」这件事；
		# 掀头套那张才配当封面：套着 Claude 的壳，底下是自己人。
		var idx := 1 if key == "claude_fake" and arr.size() > 1 else 0
		var pick: Variant = arr[idx]
		if typeof(pick) == TYPE_DICTIONARY:
			return String((pick as Dictionary).get("image", ""))
	return ""


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

	var title := UIKit.title("图 鉴", Palette.F_H2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)

	_counter = UIKit.label("", Palette.F_BODY, Palette.ACCENT_DEEP)
	head.add_child(_counter)

	col.add_child(UIKit.divider())

	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 10)
	col.add_child(tabrow)
	for tab in TABS:
		var btn := UIKit.button(String(tab["label"]), false)
		btn.add_theme_font_size_override("font_size", Palette.F_BODY)
		var id := String(tab["id"])
		btn.pressed.connect(_switch_tab.bind(id))
		tabrow.add_child(btn)
		_tab_buttons[id] = btn

	col.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	col.add_child(UIKit.divider())

	var back := UIKit.button("返 回", false)
	back.add_theme_font_size_override("font_size", Palette.F_BODY)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	col.add_child(back)


func _switch_tab(id: String) -> void:
	if id == _tab:
		return
	_tab = id
	_close_preview()
	_rebuild_grid()


func _rebuild_grid() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()

	match _tab:
		"escape":
			for it in ESCAPE_ITEMS:
				_grid.add_child(_make_art_cell(
					String(it["key"]), String(it["image"]),
					String(it["title"]), String(it["line"]), String(it["sub"])))
		"voice":
			for it in VOICE_ITEMS:
				_grid.add_child(_make_voice_cell(it))
		_:
			for key in _ordered_keys():
				_grid.add_child(_make_ending_cell(String(key)))

	if _counter != null:
		_counter.text = "%d / %d" % [_got_of(_tab), _total_of(_tab)]
	_refresh_tab_buttons()


func _refresh_tab_buttons() -> void:
	for id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[id]
		var on: bool = String(id) == _tab
		btn.add_theme_stylebox_override("normal", _cell_box(Palette.ACCENT if on else Palette.CARD_SOFT))
		btn.add_theme_color_override("font_color", Palette.ON_DARK if on else Palette.INK)


# ---------- 格子 ----------

func _cell_box(bg: Color) -> StyleBoxFlat:
	var sb := UIKit.flat(bg, Palette.RADIUS_SM + 2, Palette.CARD_EDGE, 1)
	sb.set_content_margin_all(6)
	return sb


func _make_ending_cell(key: String) -> Control:
	var data := _data_of(key)
	var cell := _shell(_unlocked.has(key))
	if _unlocked.has(key):
		cell.pressed.connect(_open_ending.bind(key))
		_fill_picture(cell, _thumb_of(key))
		_fill_caption(cell, String(data.get("title", key)), Palette.INK)
	else:
		_fill_lock(cell)
	return cell


func _make_art_cell(key: String, image: String, title: String, line: String, sub: String) -> Control:
	var cell := _shell(_unlocked.has(key))
	if _unlocked.has(key):
		cell.pressed.connect(_open_art.bind(key, image, title, line, sub))
		_fill_picture(cell, image)
		_fill_caption(cell, title, Palette.INK)
	else:
		_fill_lock(cell)
	return cell


func _make_voice_cell(item: Dictionary) -> Control:
	var raw := String(item["key"])
	var key := "voice_" + raw
	var unlocked := _unlocked.has(key)
	var cell := _shell(unlocked)
	if unlocked:
		cell.pressed.connect(_play_voice.bind(raw))
		_fill_picture(cell, String(item["face"]))
		_fill_caption(cell, "%s · %s" % [String(item["who"]), String(item["title"])], Palette.INK)
	else:
		_fill_lock(cell)
	return cell


func _shell(unlocked: bool) -> Button:
	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_NONE
	cell.custom_minimum_size = THUMB
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("normal", _cell_box(Palette.CARD_SOFT))
	cell.add_theme_stylebox_override("hover", _cell_box(Palette.CARD_EDGE if unlocked else Palette.CARD_SOFT))
	cell.add_theme_stylebox_override("pressed", _cell_box(Palette.CARD_EDGE))
	if not unlocked:
		cell.disabled = true
		cell.add_theme_stylebox_override("disabled", _cell_box(Palette.CARD_SOFT))
	return cell


func _cell_column(cell: Button) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(col)
	return col


func _fill_picture(cell: Button, path: String) -> void:
	var col := _cell_column(cell)
	col.add_child(UIKit.picture_fit(path, Vector2(THUMB.x, THUMB.x - 40)))


func _fill_caption(cell: Button, text: String, color: Color) -> void:
	var col := _cell_column(cell) if cell.get_child_count() == 0 else (cell.get_child(0) as VBoxContainer)
	var name_label := UIKit.label(text, Palette.F_SMALL, color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)


func _fill_lock(cell: Button) -> void:
	var col := _cell_column(cell)
	var lock := UIKit.label("？", Palette.F_TITLE, Palette.INK_FAINT)
	lock.custom_minimum_size = Vector2(THUMB.x, THUMB.x - 40)
	lock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(lock)
	var hint := UIKit.label("未解锁", Palette.F_SMALL, Palette.INK_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)


# ---------- 预览 ----------

func _open_ending(key: String) -> void:
	var data := _data_of(key)
	var lines: PackedStringArray = []
	for l in data.get("lines", []):
		lines.append(String(l))
	_open_preview(
		_thumb_of(key),
		String(data.get("subtitle", "")),
		String(data.get("title", key)),
		"\n".join(lines),
		String(ENDING_STORY.get(key, "")))


func _open_art(_key: String, image: String, title: String, line: String, sub: String) -> void:
	_open_preview(image, sub, title, line)


func _play_voice(key: String) -> void:
	Audio.preview_voice(key)
	for it in VOICE_ITEMS:
		if String(it["key"]) == key:
			_open_preview(
				String(it["face"]),
				String(it["who"]),
				String(it["title"]),
				String(it["line"]))
			return


func _open_preview(image: String, subtitle: String, title: String, body: String, story_id: String = "") -> void:
	_close_preview()

	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_preview = layer

	var dim := ColorRect.new()
	dim.color = Color(0.055, 0.129, 0.169, 0.78)
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

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 22)
	card.custom_minimum_size = Vector2(620, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	if image != "":
		col.add_child(UIKit.picture_fit(image, Vector2(420, 420)))

	if subtitle != "":
		var sub := UIKit.label(subtitle, Palette.F_SMALL, Palette.ACCENT_DEEP)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)

	col.add_child(UIKit.title(title, Palette.F_H2))

	if body != "":
		col.add_child(UIKit.wrap_label(body, Palette.F_BODY, Palette.INK_SOFT))

	if story_id != "" and _stories.has(story_id):
		var again := UIKit.button("再看一遍这段", true)
		again.add_theme_font_size_override("font_size", Palette.F_BODY)
		again.pressed.connect(_replay_story.bind(story_id))
		col.add_child(again)

	var close := UIKit.button("关 闭", false)
	close.add_theme_font_size_override("font_size", Palette.F_BODY)
	close.pressed.connect(_close_preview)
	col.add_child(close)


func _close_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


## 结局页里那个「再看一遍这段」：关掉预览、把剧情盖上来重播。
## 这里走的是独立的 StoryOverlay 实例，不碰 Gallery 的排队状态 ——
## 回看是回看，不该被记成「还没播过」，更不该把已看过的剧情塞回队列。
func _replay_story(story_id: String) -> void:
	var story: Variant = _stories.get(story_id, null)
	if not (story is Dictionary):
		return
	_close_preview()
	if _story == null or not is_instance_valid(_story):
		_story = StoryOverlay.new()
		add_child(_story)
	_story.play(story as Dictionary)


func _unhandled_input(event: InputEvent) -> void:
	if _preview == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_preview()
		get_viewport().set_input_as_handled()
