extends SceneTree

## 输入链路探针（开发用，不参与游戏）。
##
## 模拟一整条输入链，确认玩家真的能玩：
##   左键按下 → 蓄力 → 松开抛竿 → 等待 → 进入搏斗 → 点击 QTE
##
## 运行（不要加 --headless，GUI 事件需要真实 viewport）：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程> --script res://tests/input_probe.gd

var _game: Node = null
var _t := 0.0
var _step := 0
var _hits := 0


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_game = packed.instantiate()
	get_root().add_child(_game)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t > 0.4:
				_click(true)
				print("[probe] 左键按下 @ 湖面")
				_step = 1
		1:
			if _t > 0.9:
				print("[probe] 蓄力中：charging=%s charge=%.3f phase=%d" % [
					_game._session.is_charging(), _game._session.charge, _game._session.phase
				])
				_click(false)
				print("[probe] 左键松开 → 抛竿")
				_step = 2
		2:
			if _t > 1.1:
				print("[probe] 抛竿后：bait=%d phase=%d（1=WAITING）" % [
					_game._session.bait_left, _game._session.phase
				])
				_step = 3
		3:
			if _t > 3.2:
				print("[probe] 等待结束：phase=%d（2=FIGHTING 才对）" % _game._session.phase)
				_step = 4
		4:
			if _t > 3.4:
				_click(true)
				_click(false)
				print("[probe] 搏斗中点击一次")
				_step = 5
		5:
			if _t > 3.7:
				var f = _game._session.fight
				if f != null:
					_hits = int(f.stats.perfect) + int(f.stats.good) + int(f.stats.miss)
					print("[probe] QTE 统计：perfect=%d good=%d miss=%d 体力=%.0f%%" % [
						int(f.stats.perfect), int(f.stats.good), int(f.stats.miss),
						f.stamina_ratio() * 100.0
					])
				print("[probe] 结论：%s" % ("输入链路通畅" if _hits > 0 else "QTE 点击没生效"))
				quit()
	return false


func _click(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = Vector2(640, 300)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
