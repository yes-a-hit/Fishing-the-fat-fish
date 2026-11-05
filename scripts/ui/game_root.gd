extends Control

## 主控：装配界面、接输入、把 FishingSession 的信号翻译成画面变化。
##
## 这里**不放任何规则判断**。判断在 FishingSession / FightSession 里，
## 这个文件只做三件事：
##   1. 读配置、建视图
##   2. 把按键转给 session
##   3. 按 session 的阶段切换显示
##
## 界面刻意做得「不像界面」：搏斗没有面板，QTE 直接浮在湖面上，
## 上鱼是鱼从水里扑出来的动画。只有抛竿和结算用卡片。
##
## 想加一条鱼：只改 data/fish.json。想改手感：只改 data/tuning.json。
## 想改表现：改对应的 ui/*.gd，别在这里塞逻辑。

var _fish: Array = []
var _targets: Array = []      ## 收集目标，不含 is_claude 的陷阱
var _tuning: GameTuning = null
var _endings: Dictionary = {}
var _stories: Dictionary = {}
var _escapes: Array = []      ## 脱钩演出表，见 data/escapes.json
var _session: FishingSession = null

var _lake: LakeView = null
var _hud: HudView = null
var _cast_panel: CastPanel = null
var _qte: QteOverlay = null
var _feedback: SceneFeedback = null
var _landing: LandingView = null
var _ending: EndingOverlay = null
var _story: StoryOverlay = null
var _doubao_card: Control = null
var _doubao_tween: Tween = null
var _doubao_pic: TextureRect = null
var _doubao_tip: Label = null
var _doubao_gain: Label = null

## 这一局的分。纯逻辑在 ScoreBoard，这里只负责接信号和往结算页塞数字。
var _score := ScoreBoard.new()
var _score_layer: ScoreLayer = null
## 当前搏斗。命中判定从它身上听，鱼一换就换对象。
var _fight: FightSession = null

## 暂停遮罩。非 null 就代表正暂停着 —— 输入、tick、QTE 全靠这一个判据让路。
var _paused_layer: Control = null

## 剧情播放中。和暂停分开是因为暂停有菜单和按钮，剧情只是把这一局冻住。
var _story_playing: bool = false

## 右上角暂停键所在的整行。剧情播放时连同 HUD 一起收起来。
var _pause_row: Control = null

## 会话信号 → 处理函数。加一条信号只补这里一行。
## 早先 connect 与 disconnect 各抄十行名字：删信号时漏掉一半，旧会话就会
## 继续往同一个界面上推事件 —— 表现为「重开一局后数量跳两格」。
const SESSION_HOOKS := [
	["phase_changed", "_on_phase_changed"],
	["bait_changed", "_on_bait_changed"],
	["charge_changed", "_on_charge_changed"],
	["cast_made", "_on_cast_made"],
	["bite_started", "_on_bite_started"],
	["landing_started", "_on_landing_started"],
	["resolved", "_on_resolved"],
	["doubao_started", "_on_doubao"],
	["claude_spared", "_on_claude_spared"],
	["finished", "_on_finished"],
]

## 开场剧情。只在没播过时排队 —— 判定交给 Gallery.queue_story 自己：
## 它同时看「已播」列表和待播队列，播过一次的不会再排进来。
const OPENING_STORY := "opening"


func _ready() -> void:
	# 根节点自己不能拦鼠标，否则点击在 GUI 层就被吃掉，
	# 永远落不到下面的 _unhandled_input 上。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cfg := ConfigLoader.load_all()
	_fish = cfg["fish"]
	_tuning = cfg["tuning"]
	_endings = cfg["endings"]
	_stories = cfg.get("story", {})
	_escapes = ConfigLoader.load_escapes()

	# 难度只改数值，不改结构：先套难度再解析距离带，顺序不能反
	var settings := GameSettings.load_settings()
	_tuning.apply_difficulty(settings.difficulty)
	Audio.apply_settings(settings)

	# HUD 与结算只列收集目标，陷阱与豆包都不出现
	_targets = []
	for f in _fish:
		if not f.is_claude and not f.is_doubao:
			_targets.append(f)

	_build_ui()
	_apply_mouse_policy(self)
	_start_session()
	# 开场：第一次进游戏才排。queue_story 自己会跳过「已经播过」和「已经在队里」，
	# 所以这里不用再判一次，也就没有第二处真相源。
	Gallery.queue_story(OPENING_STORY)
	# 上一局欠下的剧情在这时候补播。放在开局之后而不是之前，
	# 是因为要等 UI 全部建好、session 也起来，播完才轮得到玩家操作。
	_play_pending_story_on_boot()


## 开局补播。队列空就什么都不做 —— 多数对局根本没剧情。
## 播的时候整局冻住，不然玩家一边看字一边蓄力条在背后转。
func _play_pending_story_on_boot() -> void:
	if Gallery.pending_stories().is_empty():
		return
	_story_playing = true
	_play_story_queue(func(): _story_playing = false)


func _process(delta: float) -> void:
	# 暂停时整局冻住：session 不推进，QTE 不转，动画不停但不影响判定。
	if _paused_layer != null:
		return
	# 剧情播放中同理，看字的时候不该被蓄力条偷走时间。
	if _story_playing:
		return
	if _session != null:
		_session.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	# ESC 在任何阶段都能暂停，包括结算页 —— 结算页正是最想跑路的时候。
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		accept_event()
		return

	if _paused_layer != null:
		return
	# 剧情层自己会吃掉点击（它在子节点里先收到事件），走到这里说明是漏网的
	if _story_playing:
		return
	if _session == null or _session.phase == FishingSession.Phase.ENDED:
		return
	if _session.phase == FishingSession.Phase.LANDING:
		return

	# 三种状态共用同一个「点一下」：蓄力起手、圆环判定、跳过结算提示。
	# 手机上没有键盘，触摸也必须走通这条路。
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
				_session.press()
				accept_event()
		elif key.pressed == false:
			if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
				_session.release()
				accept_event()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_session.press()
			else:
				_session.release()
			accept_event()
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_session.press()
		else:
			_session.release()
		accept_event()
		return

	if event.is_action_pressed("ui_accept"):
		_session.press()
		accept_event()
	elif event.is_action_released("ui_accept"):
		_session.release()
		accept_event()


# ---------- 装配 ----------

func _build_ui() -> void:
	# 1. 湖面
	_lake = LakeView.new()
	add_child(_lake)

	# 2. 顶部 HUD + 底部抛竿面板
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	_hud = HudView.new()
	_hud.setup(_targets)
	_hud.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(_hud)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_cast_panel = CastPanel.new()
	_cast_panel.setup(_fish, _tuning.resolved_zones(_fish))
	_cast_panel.custom_minimum_size = Vector2(860, 0)
	_cast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_cast_panel)

	# 3. 搏斗 QTE：直接浮在湖面上，没有面板
	_qte = QteOverlay.new()
	_qte.visible = false
	add_child(_qte)

	# 4. 场景内一次性文字（空竿 / 断线）
	_feedback = SceneFeedback.new()
	add_child(_feedback)

	# 4b. 分数与连击。压在「上鱼飞扑」上面加：上鱼那一刻 +240 要跟画面一起出现，
	# 藏在下层就被演出挡掉了（结算层仍在它之上，不会挡按钮）。
	_score_layer = ScoreLayer.new()
	# 5. 上鱼飞扑动画
	_landing = LandingView.new()
	add_child(_landing)
	_landing.finished.connect(_on_landing_finished)
	add_child(_score_layer)

	# 6. 结算层（最顶）
	_ending = EndingOverlay.new()
	_story = StoryOverlay.new()
	add_child(_ending)
	add_child(_story)
	_ending.restart_requested.connect(_start_session)
	_ending.menu_requested.connect(_back_to_menu)

	# 7. 豆包图卡：钓上豆包时飘出来的一小块，2 秒后自己退
	_doubao_card = _build_doubao_card()
	add_child(_doubao_card)

	# 8. 右上角暂停键。手机没有 ESC，只能靠这一颗；PC 上它和 ESC 等价。
	_build_pause_button()


## 右上角那颗「暂停」。锚在右上角，永远压在 HUD 之上、结算层之下。
##
## 上一版做成了 84×44 的白底汉字胶囊，太大太抢戏 —— 玩家在钓鱼，不是在看菜单。
## 真正要的是「一眼能找到」而不是「占满视野」，所以缩回 44×44 的圆，
## 靠实白底 + 描边保证醒目度，靠图标保证不占地。图标用 ASCII 的 || 画，
## 不走字体子集（子集里没有 ⏸ 这类符号会变成方块）。
func _build_pause_button() -> void:
	# 不套 MarginContainer：它会把里面唯一的孩子纵向拉满整屏，
	# 按钮因此变成一根贴右边缘、从上贯到下的白条。
	# 直接用 HBox + 右上角偏移 + 顶端对齐，按钮永远只有 44×44。
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.offset_top = 16
	row.offset_bottom = 60
	row.offset_right = -18
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var btn := Button.new()
	btn.tooltip_text = tr("暂停（Esc）")
	btn.custom_minimum_size = Vector2(44, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	_paint_pause_button(btn)

	var glyph := _PauseGlyph.new()
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(glyph)

	btn.pressed.connect(_toggle_pause)
	row.add_child(btn)
	_pause_row = row


## 两条圆角竖杠。用画的不用字体 —— 字体子集里没有 ⏸，
## 而 || 这个 ASCII 组合在比例字体里又细又偏，画出来才和设计稿一致。
class _PauseGlyph extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var bar_w := 4.0
		var bar_h := 13.0
		var gap := 4.5
		for x in [c.x - gap * 0.5 - bar_w, c.x + gap * 0.5]:
			draw_rect(Rect2(x, c.y - bar_h * 0.5, bar_w, bar_h), Palette.INK)


## 小圆按钮：实白底 + 一圈强调色边，压在任何画面上都看得见。
func _paint_pause_button(btn: Button) -> void:
	var states := {
		"normal": Color(1, 1, 1, 0.92),
		"hover": Color(1, 1, 1, 1.0),
		"pressed": Color(0.86, 0.90, 0.94, 0.96),
	}
	var r: float = btn.custom_minimum_size.y * 0.5
	for state in states.keys():
		var sb := UIKit.flat(states[state], r)
		sb.set_content_margin_all(0)
		sb.set_border_width_all(2)
		sb.border_color = Palette.ACCENT
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Palette.INK)
	btn.add_theme_color_override("font_hover_color", Palette.INK)
	btn.add_theme_color_override("font_pressed_color", Palette.INK)


## 豆包图卡。整块浮在屏幕右侧偏上，不拦鼠标，不吃输入。
func _build_doubao_card() -> Control:
	var holder := MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_right", 34)
	holder.add_theme_constant_override("margin_top", 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var align := HBoxContainer.new()
	align.alignment = BoxContainer.ALIGNMENT_END
	align.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(align)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 14)
	card.custom_minimum_size = Vector2(268, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	align.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var pic := UIKit.picture("res://assets/doubao_kick.webp", Vector2(240, 172))
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	_doubao_pic = pic

	var tip := UIKit.label(tr("哪来的奶黄包！"), Palette.F_BODY, Palette.INK)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tip)
	_doubao_tip = tip

	var gain := UIKit.label("", Palette.F_SMALL, Palette.GOOD)
	gain.name = "Gain"
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gain)
	_doubao_gain = gain

	holder.visible = false
	return holder


## 除了按钮，所有 Control 都不拦鼠标。
##
## 原因：Godot 的鼠标事件会先走 GUI 链，任何 mouse_filter = STOP 的 Control
## 都会把它标记为已处理，_unhandled_input 就永远收不到。
## 结果是「点湖面毫无反应」—— 这是踩过的坑。
## 按钮保留 STOP（否则点不动），其余全部 IGNORE，点击就一路落到 _unhandled_input。
func _apply_mouse_policy(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			# 按钮自己保持可点，但它的子节点要放行，别挡住按钮的点击区
			_apply_mouse_policy(child)
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_mouse_policy(child)


# ---------- 一局的生命周期 ----------

func _start_session() -> void:
	if _session != null:
		_disconnect_session()

	_session = FishingSession.new(_fish, _tuning)
	for hook in SESSION_HOOKS:
		_session.connect(StringName(hook[0]), Callable(self, String(hook[1])))

	_ending.hide_overlay()
	_qte.unbind()
	_qte.visible = false
	_feedback.clear()
	_score.reset()
	if _score_layer != null:
		_score_layer.reset()
	_fight = null
	_lake.set_fight_intensity(0.0)
	_lake.set_fish_shadow(false)
	_lake.set_bobber(0.0, false)
	_lake.set_bite(false)
	_cast_panel.reset()
	_cast_panel.refresh_caught([])
	_hud.refresh_bait(_session.bait_left, _session.bait_max)
	_hud.refresh_caught([])

	_session.start()
	# 新的一局，水面上的影子重新撒；交给距离条去画
	_cast_panel.set_shadows(_session.shadows())


func _disconnect_session() -> void:
	if _session == null:
		return
	var s := _session
	_session = null
	for hook in SESSION_HOOKS:
		var sig := StringName(hook[0])
		var cb := Callable(self, String(hook[1]))
		if s.is_connected(sig, cb):
			s.disconnect(sig, cb)


# ---------- 阶段切换 ----------

func _on_phase_changed(phase: int) -> void:
	_cast_panel.visible = phase == FishingSession.Phase.AIMING

	match phase:
		FishingSession.Phase.AIMING:
			_hud.set_hint(tr("按住蓄力，松手抛竿"))
			_qte.visible = false
			_lake.set_bobber(0.0, false)
			_lake.set_bite(false)
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
			_cast_panel.reset()
		FishingSession.Phase.WAITING:
			_hud.set_hint(tr("饵在水里，等鱼咬钩…"))
			_qte.visible = false
		FishingSession.Phase.FIGHTING:
			_hud.set_hint(tr("圆环转到顶部时点一下"))
			_qte.visible = true
			_lake.set_bite(false)
			_lake.set_fight_intensity(1.0)
			_lake.set_fish_shadow(true)
		FishingSession.Phase.LANDING:
			_hud.set_hint(tr("上鱼！"))
			_qte.visible = false
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
		FishingSession.Phase.RESOLVING:
			_hud.set_hint(tr("收竿"))
			_qte.visible = false
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
		FishingSession.Phase.ENDED:
			_hud.set_hint(tr("本局结束"))
			_qte.visible = false
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)


func _on_bait_changed(left: int, total: int) -> void:
	_hud.refresh_bait(left, total)


func _on_charge_changed(value: float) -> void:
	_cast_panel.set_charge(value)


func _on_cast_made(point: float, _fish_id: String) -> void:
	_lake.set_bobber(point, true)
	_cast_panel.visible = false
	# 刻意不报「抽到了谁」—— 咬钩才知道，抛之前一切皆有可能


func _on_bite_started(fish: FishSpec, fight: FightSession) -> void:
	_qte.bind(fight)
	_fight = fight
	if not fight.strike_result.is_connected(_on_strike_result):
		fight.strike_result.connect(_on_strike_result)
	_lake.set_bite(true)
	# 咬钩这一刻不开口。水底下有东西咬钩，但它是什么得等真捞上来才知道 ——
	# 一出声就等于提前报菜名，惊喜全没了。声音一律留到 landing 那一下。


func _on_landing_started(fish: FishSpec) -> void:
	_hud.refresh_caught(_session.caught_ids())
	_cast_panel.refresh_caught(_session.caught_ids())
	_landing.play(fish, _lake.bobber_screen_pos())
	# 上鱼也算进分里。放在 landing 这一刻而不是 resolved：
	# 鱼真的被拎出水面了，玩家看到的 +240 和动画是同一拍。
	if _score_layer != null:
		_score_layer.landing(_score.landed(fish.id), _score.score)
	# 上鱼那句和咬钩那句是两回事：咬钩时鱼还在水里说话（bite_*），
	# 被捞出水面的瞬间说的是另一句（catch_*）。豆包用主人录的那条。
	if fish.is_doubao:
		Audio.play_voice("doubao_catch")
	elif Audio.has_voice("catch_" + fish.id):
		Audio.play_voice("catch_" + fish.id)
	else:
		Audio.play_voice("catch_mid")


func _on_landing_finished() -> void:
	if _session != null:
		_session.landing_done()


## 一次判定。kind: "round"(完美) / "good" / "miss"，来自 FightSession。
func _on_strike_result(kind: String) -> void:
	var r := _score.hit(kind)
	if _score_layer == null:
		return
	if kind == "miss":
		_score_layer.break_combo()
	else:
		_score_layer.bump(int(r["gain"]), int(r["combo"]), float(r["mult"]), _score.score)


func _on_resolved(kind: String, fish: FishSpec) -> void:
	_lake.set_bite(false)
	_hud.refresh_caught(_session.caught_ids())
	_cast_panel.refresh_caught(_session.caught_ids())

	match kind:
		FishingSession.RESULT_ESCAPED:
			_show_escape(fish)
		_:
			_feedback.show_text(tr("空　竿"), Palette.INK_SOFT)


## 豆包上钩。饭已经由 session 加回去了，这里只负责把那张梗图飘出来。
func _on_doubao(refund: int) -> void:
	_hud.refresh_bait(_session.bait_left, _session.bait_max)
	var gain_text := tr("+%d 碗白饭") % refund if refund > 0 else tr("碗已经满了")
	var gain_color := Palette.GOOD if refund > 0 else Palette.INK_FAINT
	_flash_card("res://assets/doubao_kick.webp", tr("哪来的奶黄包！"), gain_text, gain_color)


## 私奔之后再钓上她。不封号，不结算，只是浮上来打个照面。
func _on_claude_spared() -> void:
	_feedback.show_text(tr("她 看 了 你 一 眼"), Palette.ACCENT_DEEP)
	Audio.play_voice("claude")


## 脱钩弹脸。每条鱼一张，没有对应图才掉回纯文字。
##
## 卡片的版式只有一个，图和字都换 —— 上是鱼在嘲笑你，不是系统在宣布你失败。
## 所以颜色给 WARN 不给 BAD：断了线是喜剧，被拉爆张力才是真失败。
func _show_escape(fish: FishSpec) -> void:
	var art := _escape_art_of(fish)
	if art.is_empty():
		_feedback.show_text(tr("线　断　了"), Palette.BAD)
		Audio.play_voice("escape")
		return
	Gallery.unlock(String(art["gallery"]))
	_flash_card(art["image"], art["tip"], art["gain"], art["color"])
	var voice := String(art["voice"])
	if not voice.is_empty():
		Audio.play_voice(voice)


## 图、字、音全部来自 data/escapes.json。这里只把字段名对到卡片要的名字，
## 不再判断「她是不是鲸鱼 / 是不是豆包」—— 加一条鱼只改数据。
func _escape_art_of(fish: FishSpec) -> Dictionary:
	if fish == null:
		return {}
	var art := ConfigLoader.escape_for(_escapes, fish.id)
	if art.is_empty():
		return {}
	return {
		"image": String(art.get("image", "")),
		"tip": String(art.get("line", "")),
		"gain": String(art.get("sub", "")),
		"color": Palette.WARN,
		"voice": String(art.get("voice", "")),
		"gallery": String(art.get("key", "")),
	}


func _flash_card(image_path: String, tip_text: String, gain_text: String, gain_color: Color) -> void:
	if _doubao_card == null:
		return
	if _doubao_pic != null and ResourceLoader.exists(image_path):
		_doubao_pic.texture = load(image_path)
	if _doubao_tip != null:
		_doubao_tip.text = tip_text
	if _doubao_gain != null:
		_doubao_gain.text = gain_text
		_doubao_gain.modulate = gain_color
	_doubao_card.visible = true
	_doubao_card.modulate = Color(1, 1, 1, 0)
	if _doubao_tween != null and _doubao_tween.is_valid():
		_doubao_tween.kill()
	_doubao_tween = create_tween()
	_doubao_tween.tween_property(_doubao_card, "modulate", Color(1, 1, 1, 1), 0.18)
	_doubao_tween.tween_interval(1.7)
	_doubao_tween.tween_property(_doubao_card, "modulate", Color(1, 1, 1, 0), 0.35)
	_doubao_tween.tween_callback(func(): _doubao_card.visible = false)


func _on_finished(ending: String, summary: Dictionary) -> void:
	_qte.unbind()
	_qte.visible = false
	_lake.set_bite(false)
	_lake.set_fight_intensity(0.0)
	_lake.set_fish_shadow(false)
	# 记一笔图鉴。新解锁时顺手打条日志，方便确认落盘成功。
	if Gallery.unlock(ending):
		print(tr("[gallery] 新解锁结局: ") + ending)
	var data: Dictionary = _endings.get(ending, {})
	Audio.play_voice(ending)
	# 分数在这里定死：尾款、难度系数、历史最高一次算完，
	# 结算页只是把 summary 里的数字画出来。
	var final := _score.finalize(summary, _tuning.difficulty)
	summary["score"] = final["score"]
	summary["score_bonus"] = final["bonus"]
	summary["best_combo"] = final["best_combo"]
	summary["best_score"] = final["best_score"]
	summary["new_record"] = final["new_record"]
	# 这一局欠下的剧情先播完，再播这个结局自己的那段，最后才摆结算。
	# 顺序反了的话，第二次钓上豆包那一竿恰好也是集齐三条鱼的那一竿，
	# 结算卡片一盖上来，「白饭来咯」就永远看不到了。
	_story_playing = true
	_play_story_queue(func():
		# 每个结局都配了一段对话，播完才轮到结算页
		_play_one_story("ending_" + ending, func():
			_story_playing = false
			_ending.show_ending(ending, data, summary, _targets)
		)
	)


## 把队列里的剧情一段段播完，最后调 done。
## 队列空就直接 done —— 多数对局根本没剧情。
func _play_story_queue(done: Callable) -> void:
	var id := Gallery.pop_story()
	if id.is_empty():
		done.call()
		return
	var story: Dictionary = _stories.get(id, {})
	if story.is_empty() or (story.get("pages", []) as Array).is_empty():
		_play_story_queue(done)
		return
	_begin_story(story, _play_story_queue.bind(done))


## 播指定的一段剧情，播完调 done。找不到就直接 done。
## 结局剧情走这里，不进队列 —— 它每局都要放，不是「欠下的」。
func _play_one_story(id: String, done: Callable) -> void:
	var story: Dictionary = _stories.get(id, {})
	if story.is_empty() or (story.get("pages", []) as Array).is_empty():
		done.call()
		return
	_begin_story(story, done)


## 剧情期间收起对局界面。开场那段是全屏叙事，
## 顶上的白饭计数、三条鱼的名字、右上角暂停圆压在字上面，一眼就出戏。
## 收起来以后玩家看到的只有背景、立绘和台词；播完立刻还原，不给状态留缝。
func _begin_story(story: Dictionary, done: Callable) -> void:
	_set_play_chrome(false)
	_story.finished.connect(
		func() -> void:
			_set_play_chrome(true)
			done.call(),
		CONNECT_ONE_SHOT
	)
	_story.play(story)


func _set_play_chrome(on: bool) -> void:
	if _hud != null:
		_hud.visible = on
	if _pause_row != null:
		_pause_row.visible = on
	# 分数也跟着收：全屏剧情里顶着一个「1240」很出戏
	if _score_layer != null:
		_score_layer.visible = on


func _back_to_menu() -> void:
	_resume_tree()
	_disconnect_session()
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------- 暂停 ----------

## ESC 和右上角那颗按钮走同一条路：按一下暂停，再按一下继续。
func _toggle_pause() -> void:
	if _paused_layer != null:
		_resume_game()
	else:
		_pause_game()


func _pause_game() -> void:
	if _paused_layer != null:
		return
	var layer := PauseLayer.new()
	layer.resumed.connect(_resume_game)
	layer.restarted.connect(_restart_from_pause)
	layer.quit_requested.connect(_back_to_menu)
	add_child(layer)
	_paused_layer = layer
	# 真暂停整棵场景树：_process 停、Tween 停、动画停，退出时不会留下半个状态。
	# 遮罩自己 PROCESS_MODE_WHEN_PAUSED，所以它还活着。
	get_tree().paused = true


func _resume_game() -> void:
	if _paused_layer == null:
		return
	_paused_layer.queue_free()
	_paused_layer = null
	get_tree().paused = false


func _resume_tree() -> void:
	# 任何离开这一局的路径都必须先把树解开，否则换场景后新场景也是冻的。
	get_tree().paused = false


func _restart_from_pause() -> void:
	var layer := _paused_layer
	_paused_layer = null
	get_tree().paused = false
	if layer != null:
		layer.queue_free()
	_start_session()

