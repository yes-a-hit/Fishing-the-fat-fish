extends SceneTree

## 视觉快照工具（开发用，不参与游戏）。
##
## 运行（**不要加 --headless**，headless 没有渲染缓冲）：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程> --script res://tests/screenshot.gd
##
## 会把六个关键状态存到 <工程>/.screenshots/：
##   01_aiming.png   开局抛竿
##   02_charging.png 蓄力中
##   03_fight.png    搏斗（圆环判定 + 浮标挣扎）
##   04_landing.png  上鱼飞扑
##   05_ending.png   结算
##   06_opening.png  开场剧情（第一次进游戏播的那段）
##
## 用途：改完 UI 后快速确认布局没崩，不用手动点一遍。

const OUT_DIR := "res://.screenshots"

var _game: Node = null
var _t := 0.0
var _step := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# 截图不碰玩家真实进度；开场剧情在这一层手动播，不靠 boot 自动排
	Gallery.override_path = "user://gallery_shot.json"
	Gallery.clear()
	Gallery.queue_story("opening")
	Gallery.pop_story()
	_game = _spawn()


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
				# 直接播上鱼动画，不用真的把体力打完。
				# 用中肥鱼：她是唯一换了 Q 版汉服立绘的一条，这张图要能看出新旧差别。
				var mid = _game._fish[0]
				for f in _game._fish:
					if (f as FishSpec).id == "mid":
						mid = f
				_game._landing.play(mid, Vector2(320, 428))
				_step = 4
		4:
			if _t > 2.9:
				_shot("04_landing")
				# 计分层单独拍一张：_shot 抓的是上一帧的纹理，
				# 同一帧里先 bump 再拍是拍不到的，必须隔一帧。
				_game._score_layer.bump(130, 4, 1.45, 1860)
				_step = 45
		45:
			if _t > 2.95:
				_shot("11_score")
				# 用一份完整的假数据直接渲染结算页，验证真实布局下的高度
				var fake := {
					"bait_total": 5, "bait_left": 2, "bait_used": 3,
					"caught": ["small", "mid", "big"], "caught_count": 3, "landed": 3,
					"fish_total": 3, "claude_caught": false,
					"rounds": 16, "perfect": 9, "miss": 3, "good": 7,
					"score": 1840, "best_combo": 6, "best_score": 2210, "new_record": false,
				}
				_game._ending.show_ending("feast", _game._endings.get("feast", {}), fake, _game._fish)
				_step = 5
		5:
			if _t > 3.5:
				_shot("05_ending")
				# 换一局干净的，专门拍开场剧情（结算层跟着旧实例一起销毁）
				_game.queue_free()
				_game = _spawn()
				# 走 _begin_story 而不是 _story.play：这样 HUD 和暂停键会一起收起来，
				# 拍出来的就是玩家真正看到的那一版全屏叙事。
				_game._begin_story(_game._stories.get("opening", {}), func() -> void: pass)
				_step = 6
		6:
			if _t > 4.2:
				# 停在第 4 条（中肥鱼的台词）。每页都要先补完打字再翻，
				# 少补一次就差一页 —— 用 while 跟着 _index 走，不数点击次数。
				var ov = _game._story
				ov._stop_typing()
				while ov._index < 3:
					ov._punch()
					ov._stop_typing()
				_step = 7
		7:
			if _t > 4.6:
				_shot("06_opening")
				# 换一局，专门拍齐鱼之福第二天的整页 CG（页级 bg + hide_face）
				_game.queue_free()
				_game = _spawn()
				_game._begin_story(_game._stories.get("ending_feast", {}), func() -> void: pass)
				_step = 8
		8:
			if _t > 5.2:
				var ov2 = _game._story
				ov2._stop_typing()
				while ov2._index < ov2._pages.size() - 1:
					ov2._punch()
					ov2._stop_typing()
				_step = 9
		9:
			if _t > 5.6:
				_shot("07_feast_after")
				# 再换一局，拍开场那三张 CG：中肥鱼下水 / 造小肥鱼 / 递竿后自己下水
				_game.queue_free()
				_game = _spawn()
				_game._begin_story(_game._stories.get("opening", {}), func() -> void: pass)
				_step = 10
		10:
			if _t > 6.2:
				_advance_to(5)      # 中肥鱼捂着胸口：这条台词开始挂 denial 那张 CG
				_step = 105
		105:
			if _t > 6.3:
				_shot("12_opening_denial")
				_advance_to(12)     # 大肥鱼比心
				_step = 106
		106:
			if _t > 6.4:
				_shot("13_opening_heart")
				_advance_to(16)     # 河边：放下空玻璃杯、撒饵
				_step = 107
		107:
			if _t > 6.5:
				_shot("14_opening_bank")
				_advance_to(26)
				_step = 11
		11:
			if _t > 6.5:
				_shot("08_opening_dive")
				_advance_to(33)
				_step = 12
		12:
			if _t > 6.9:
				_shot("09_opening_summon")
				_advance_to(41)
				_step = 13
		13:
			if _t > 7.3:
				_shot("10_opening_rod")
				quit()
	return false


# 把剧情翻到第 target 页（0 起）。每页先补完打字，翻页才生效。
func _advance_to(target: int) -> void:
	var ov = _game._story
	ov._stop_typing()
	while ov._index < target and ov._index < ov._pages.size() - 1:
		ov._punch()
		ov._stop_typing()


func _spawn() -> Node:
	var packed := load("res://main.tscn") as PackedScene
	var node := packed.instantiate()
	get_root().add_child(node)
	return node


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png")
	var err := img.save_png(path)
	print("[shot] %s -> %s (%s)" % [name, path, "ok" if err == OK else "err %d" % err])
