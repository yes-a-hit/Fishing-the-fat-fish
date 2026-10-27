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
var _session: FishingSession = null

var _lake: LakeView = null
var _hud: HudView = null
var _cast_panel: CastPanel = null
var _qte: QteOverlay = null
var _feedback: SceneFeedback = null
var _landing: LandingView = null
var _ending: EndingOverlay = null
var _doubao_card: Control = null
var _doubao_tween: Tween = null
var _doubao_pic: TextureRect = null
var _doubao_tip: Label = null
var _doubao_gain: Label = null

## 暂停遮罩。非 null 就代表正暂停着 —— 输入、tick、QTE 全靠这一个判据让路。
var _paused_layer: Control = null


func _ready() -> void:
	# 根节点自己不能拦鼠标，否则点击在 GUI 层就被吃掉，
	# 永远落不到下面的 _unhandled_input 上。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cfg := ConfigLoader.load_all()
	_fish = cfg["fish"]
	_tuning = cfg["tuning"]
	_endings = cfg["endings"]

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


func _process(delta: float) -> void:
	# 暂停时整局冻住：session 不推进，QTE 不转，动画不停但不影响判定。
	if _paused_layer != null:
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

	# 5. 上鱼飞扑动画
	_landing = LandingView.new()
	add_child(_landing)
	_landing.finished.connect(_on_landing_finished)

	# 6. 结算层（最顶）
	_ending = EndingOverlay.new()
	add_child(_ending)
	_ending.restart_requested.connect(_start_session)
	_ending.menu_requested.connect(_back_to_menu)

	# 7. 豆包图卡：钓上豆包时飘出来的一小块，2 秒后自己退
	_doubao_card = _build_doubao_card()
	add_child(_doubao_card)

	# 8. 右上角暂停键。手机没有 ESC，只能靠这一颗；PC 上它和 ESC 等价。
	_build_pause_button()


## 右上角那颗「暂停」。锚在右上角，永远压在 HUD 之上、结算层之下。
func _build_pause_button() -> void:
	var layer := MarginContainer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_theme_constant_override("margin_right", 18)
	layer.add_theme_constant_override("margin_top", 14)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(row)

	var btn := Button.new()
	btn.text = "Ⅱ"
	btn.tooltip_text = "暂停（Esc）"
	btn.custom_minimum_size = Vector2(44, 40)
	btn.add_theme_font_size_override("font_size", Palette.F_H3)
	btn.focus_mode = Control.FOCUS_NONE
	_paint_ghost_button(btn)
	btn.pressed.connect(_toggle_pause)
	row.add_child(btn)


## 半透明胶囊按钮，压在湖面上不抢戏。
func _paint_ghost_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(1, 1, 1, 0.16)
		if state == "hover":
			bg = Color(1, 1, 1, 0.28)
		elif state == "pressed":
			bg = Color(1, 1, 1, 0.10)
		var sb := UIKit.flat(bg, btn.custom_minimum_size.y * 0.5)
		sb.set_content_margin_all(6)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Palette.ON_DARK)
	btn.add_theme_color_override("font_hover_color", Palette.ON_DARK)
	btn.add_theme_color_override("font_pressed_color", Palette.ON_DARK)


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

	var tip := UIKit.label("哪来的奶黄包！", Palette.F_BODY, Palette.INK)
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
	_session.phase_changed.connect(_on_phase_changed)
	_session.bait_changed.connect(_on_bait_changed)
	_session.charge_changed.connect(_on_charge_changed)
	_session.cast_made.connect(_on_cast_made)
	_session.bite_started.connect(_on_bite_started)
	_session.landing_started.connect(_on_landing_started)
	_session.resolved.connect(_on_resolved)
	_session.doubao_started.connect(_on_doubao)
	_session.claude_spared.connect(_on_claude_spared)
	_session.finished.connect(_on_finished)

	_ending.hide_overlay()
	_qte.unbind()
	_qte.visible = false
	_feedback.clear()
	_lake.set_fight_intensity(0.0)
	_lake.set_fish_shadow(false)
	_lake.set_bobber(0.0, false)
	_lake.set_bite(false)
	_cast_panel.reset()
	_cast_panel.refresh_caught([])
	_hud.refresh_bait(_session.bait_left, _session.bait_max)
	_hud.refresh_caught([])

	_session.start()


func _disconnect_session() -> void:
	if _session == null:
		return
	var s := _session
	_session = null
	if s.phase_changed.is_connected(_on_phase_changed):
		s.phase_changed.disconnect(_on_phase_changed)
	if s.bait_changed.is_connected(_on_bait_changed):
		s.bait_changed.disconnect(_on_bait_changed)
	if s.charge_changed.is_connected(_on_charge_changed):
		s.charge_changed.disconnect(_on_charge_changed)
	if s.cast_made.is_connected(_on_cast_made):
		s.cast_made.disconnect(_on_cast_made)
	if s.bite_started.is_connected(_on_bite_started):
		s.bite_started.disconnect(_on_bite_started)
	if s.landing_started.is_connected(_on_landing_started):
		s.landing_started.disconnect(_on_landing_started)
	if s.resolved.is_connected(_on_resolved):
		s.resolved.disconnect(_on_resolved)
	if s.doubao_started.is_connected(_on_doubao):
		s.doubao_started.disconnect(_on_doubao)
	if s.claude_spared.is_connected(_on_claude_spared):
		s.claude_spared.disconnect(_on_claude_spared)
	if s.finished.is_connected(_on_finished):
		s.finished.disconnect(_on_finished)


# ---------- 阶段切换 ----------

func _on_phase_changed(phase: int) -> void:
	_cast_panel.visible = phase == FishingSession.Phase.AIMING

	match phase:
		FishingSession.Phase.AIMING:
			_hud.set_hint("按住蓄力，松手抛竿")
			_qte.visible = false
			_lake.set_bobber(0.0, false)
			_lake.set_bite(false)
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
			_cast_panel.reset()
		FishingSession.Phase.WAITING:
			_hud.set_hint("饵在水里，等鱼咬钩…")
			_qte.visible = false
		FishingSession.Phase.FIGHTING:
			_hud.set_hint("圆环转到顶部时点一下")
			_qte.visible = true
			_lake.set_bite(false)
			_lake.set_fight_intensity(1.0)
			_lake.set_fish_shadow(true)
		FishingSession.Phase.LANDING:
			_hud.set_hint("上鱼！")
			_qte.visible = false
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
		FishingSession.Phase.RESOLVING:
			_hud.set_hint("收竿")
			_qte.visible = false
			_lake.set_fight_intensity(0.0)
			_lake.set_fish_shadow(false)
		FishingSession.Phase.ENDED:
			_hud.set_hint("本局结束")
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
	_lake.set_bite(true)
	# 咬钩不开口：鱼在水下咬着钩，这时候说话就露馅了。声音留到真的捞上来那一下。


func _on_landing_started(fish: FishSpec) -> void:
	_hud.refresh_caught(_session.caught_ids())
	_cast_panel.refresh_caught(_session.caught_ids())
	_landing.play(fish, _lake.bobber_screen_pos())
	# 捞上来的瞬间才出声，每条鱼说自己的那句；豆包用主人录的那条
	if fish.is_doubao:
		Audio.play_voice("doubao_catch")
	elif Audio.has_voice("bite_" + fish.id):
		Audio.play_voice("bite_" + fish.id)
	else:
		Audio.play_voice("catch")


func _on_landing_finished() -> void:
	if _session != null:
		_session.landing_done()


func _on_resolved(kind: String, fish: FishSpec) -> void:
	_lake.set_bite(false)
	_hud.refresh_caught(_session.caught_ids())
	_cast_panel.refresh_caught(_session.caught_ids())

	match kind:
		FishingSession.RESULT_ESCAPED:
			_show_escape(fish)
		_:
			_feedback.show_text("空　竿", Palette.INK_SOFT)


## 豆包上钩。饭已经由 session 加回去了，这里只负责把那张梗图飘出来。
func _on_doubao(refund: int) -> void:
	_hud.refresh_bait(_session.bait_left, _session.bait_max)
	var gain_text := "+%d 碗白饭" % refund if refund > 0 else "碗已经满了"
	var gain_color := Palette.GOOD if refund > 0 else Palette.INK_FAINT
	_flash_card("res://assets/doubao_kick.webp", "哪来的奶黄包！", gain_text, gain_color)


## 私奔之后再钓上她。不封号，不结算，只是浮上来打个照面。
func _on_claude_spared() -> void:
	_feedback.show_text("她 看 了 你 一 眼", Palette.ACCENT_DEEP)
	Audio.play_voice("claude")


## 脱钩弹脸。每条鱼一张，没有对应图才掉回纯文字。
##
## 卡片的版式只有一个，图和字都换 —— 上是鱼在嘲笑你，不是系统在宣布你失败。
## 所以颜色给 WARN 不给 BAD：断了线是喜剧，被拉爆张力才是真失败。
func _show_escape(fish: FishSpec) -> void:
	var art := _escape_art_of(fish)
	if art.is_empty():
		_feedback.show_text("线　断　了", Palette.BAD)
		Audio.play_voice("escape")
		return
	Gallery.unlock(String(art["gallery"]))
	_flash_card(art["image"], art["tip"], art["gain"], art["color"])
	Audio.play_voice(art["voice"])


## 图、字、音按鱼分。缺图返回空字典，调用方退回纯文字。
func _escape_art_of(fish: FishSpec) -> Dictionary:
	if fish == null:
		return {}
	if fish.is_doubao:
		return {
			"image": "res://assets/doubao_escape.webp",
			"tip": "奶黄包 笑 着 跑 了",
			"gain": "白饭没捞着",
			"color": Palette.WARN,
			"voice": "doubao_escape",
			"gallery": "escape_doubao",
		}
	if fish.is_claude:
		return {
			"image": "res://assets/claude_escape.webp",
			"tip": "她 扭 过 头 去 了",
			"gain": "通知单没递成",
			"color": Palette.WARN,
			"voice": "escape",
			"gallery": "escape_claude",
		}
	if fish.id == "big":
		return {
			"image": "res://assets/deepseek_escape_big.webp",
			"tip": "鲸鱼不是肥，是密度好",
			"gain": "她 游 走 了",
			"color": Palette.WARN,
			"voice": "escape",
			"gallery": "escape_big",
		}
	if fish.id == "small" or fish.id == "mid":
		return {
			"image": "res://assets/deepseek_escape.webp",
			"tip": "哦 鲸 鲸 …",
			"gain": "她 甩 尾 巴 跑 了",
			"color": Palette.WARN,
			"voice": "escape",
			"gallery": "escape_small",
		}
	return {}


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
		print("[gallery] 新解锁结局: " + ending)
	var data: Dictionary = _endings.get(ending, {})
	Audio.play_voice(ending)
	_ending.show_ending(ending, data, summary, _targets)


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
	# 真暂停整棵场景树：_process 停、Tween 停、动画停，退出时不会留下半个状态。
	get_tree().paused = true

	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 遮罩自己必须在暂停中照常跑，否则它的按钮按不动。
	layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.12, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var card := UIKit.card(Palette.CARD, Palette.RADIUS, 26)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	col.add_child(UIKit.title("已 暂 停", Palette.F_H2))
	col.add_child(UIKit.divider())

	var resume := UIKit.button("继 续", true)
	resume.pressed.connect(_resume_game)
	col.add_child(resume)

	var restart := UIKit.button("重 新 开 始", false)
	restart.pressed.connect(_restart_from_pause)
	col.add_child(restart)

	var menu := UIKit.button("返 回 菜 单", false)
	menu.pressed.connect(_back_to_menu)
	col.add_child(menu)

	_paused_layer = layer


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

