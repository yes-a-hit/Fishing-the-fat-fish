extends SceneTree

## 视觉快照工具（开发用，不参与游戏）。
##
## 运行（**不要加 --headless**，headless 没有渲染缓冲）：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程> --script res://tests/screenshot.gd
##
## 会把五个关键状态存到 <工程>/.screenshots/：
##   01_aiming.png   开局抛竿
##   02_charging.png 蓄力中
##   03_fight.png    搏斗（圆环判定 + 浮标挣扎）
##   04_landing.png  上鱼飞扑
##   05_ending.png   结算
##
## 用途：改完 UI 后快速确认布局没崩，不用手动点一遍。

const OUT_DIR := "res://.screenshots"

var _game: Node = null
var _t := 0.0
var _step := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := load("res://main.tscn") as PackedScene
	_game = packed.instantiate()
	get_root().add_child(_game)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t > 0.5:
				_shot("01_aiming")
				_step = 1
		1:
			if _t > 0.8:
				_game._session.press()
				_game._session.tick(0.62)   # 蓄力到一半左右
				_step = 2
		2:
			if _t > 1.1:
				_shot("02_charging")
				_game._session.charge = 0.15
				_game._session.release()
				_game._session.tick(3.0)    # 越过等待，进入搏斗
				# 先命中一次，让圆环展示「已削掉一截体力」的状态
				var f = _game._session.fight
				if f != null:
					f.cursor = 0.0
					_game._session.qte_strike()
				_step = 3
		3:
			if _t > 1.8:
				_shot("03_fight")
				# 直接播上鱼动画，不用真的把体力打完
				_game._landing.play(_game._fish[2], Vector2(320, 428))
				_step = 4
		4:
			if _t > 2.9:
				_shot("04_landing")
				# 用一份完整的假数据直接渲染结算页，验证真实布局下的高度
				var fake := {
					"bait_total": 5, "bait_left": 2, "bait_used": 3,
					"caught": ["small", "mid", "big"], "caught_count": 3, "landed": 3,
					"fish_total": 3, "claude_caught": false,
					"rounds": 16, "perfect": 9, "miss": 3, "good": 16,
				}
				_game._ending.show_ending("feast", _game._endings.get("feast", {}), fake, _game._fish)
				_step = 5
		5:
			if _t > 3.5:
				_shot("05_ending")
				quit()
	return false


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png")
	var err := img.save_png(path)
	print("[shot] %s -> %s (%s)" % [name, path, "ok" if err == OK else "err %d" % err])
