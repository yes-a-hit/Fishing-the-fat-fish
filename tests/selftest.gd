extends SceneTree

## 无窗口逻辑自测。运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/selftest.gd
##
## 覆盖四类：
##   1. 配置与自动分带（含「加一条鱼」的扩展性验证）
##   2. 抛竿落点、空竿、重复上鱼
##   3. 搏斗：完美窗口宽度、上鱼、断线、连击
##   4. 结局判定与场景装配
##
## 用 _process 驱动而不是 _initialize：_initialize 阶段 root 还没进主循环，
## 场景 add_child 后的 _ready 时序不可靠。

var _ran := false
var _fail := 0
var _pass := 0


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	# 沙盒跑完清干净，把图鉴指回真实存档
	Gallery.clear()
	Gallery.override_path = ""
	print("\n[selftest] pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
	return true


func _run_all() -> void:
	# 整套测试跑下来会调 play_voice()，而它会往图鉴里记一笔。
	# 全局把图鉴重定向到临时文件，玩家的真实进度一个字节都不许碰。
	Gallery.override_path = "user://gallery_sandbox.json"
	Gallery.clear()

	_case_config()
	_case_auto_zones()
	_case_extension_add_fish()
	_case_ring()
	_case_strike_lock()
	_case_charge_loops()
	_case_cast_and_bait()
	_case_empty_cast()
	_case_catch_all()
	_case_full()
	_case_hungry()
	_case_repeat_catch()
	_case_claude_trap()
	_case_claude_fake()
	_case_doubao()
	_case_doubao_escape()
	_case_gallery()
	_case_gallery_pages()
	_case_voice_rewards()
	_case_about()
	_case_line_break()
	_case_scene_boot()
	_case_pause()
	_case_mouse_policy()
	_case_ending_overlay()
	_case_settings_roundtrip()
	_case_audio_settings()
	_case_audio_director()
	_case_menu_boot()
	_case_difficulty_affects_game()


func _check(label: String, actual, expected) -> void:
	if str(actual) == str(expected):
		_pass += 1
		print("  ok   %s = %s" % [label, actual])
	else:
		_fail += 1
		print("  FAIL %s = %s (want %s)" % [label, actual, expected])


func _ok(label: String, condition: bool) -> void:
	_check(label, condition, true)


# ---------- 构造工具 ----------

## 造一份可控的 tuning：jitter 归零，方便断言落点。
func _test_tuning() -> GameTuning:
	var t := ConfigLoader.load_tuning()
	t.cast_jitter = 0.0
	return t


func _new_session() -> FishingSession:
	var fish := ConfigLoader.load_fish()
	var s := FishingSession.new(fish, _test_tuning(), _seeded_rng())
	s.start()
	return s


func _seeded_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 20261026
	return r


## 把蓄力直接设到目标百分比再松手（跳过按住时长，测试专用）。
func _cast_at(session: FishingSession, point: float) -> void:
	session.press()
	session.charge = clampf(point / 100.0, 0.0, 1.0)
	session.release()


## 走完一次完整上鱼：抛竿 → 等咬钩 → 按对每一轮序列 → 跳过飞扑动画。
##
## 距离带是重叠的，直接抛到某条带的坐标不能保证抽中它。
## 所以这里临时把 session 的带换成「只有这一条鱼」的窄带，钓完再换回来 ——
## 测试要验的是「钓到 X 之后会发生什么」，不是「能不能抽中 X」。
func _catch(session: FishingSession, fish_id: String) -> void:
	if session.zone_of(fish_id).is_empty():
		return
	var saved: Array = session._zones
	session._zones = [{"id": "pin_%s" % fish_id, "fish": fish_id, "from": 0.0, "to": 100.0, "weight": 1.0}]
	_cast_at(session, 50.0)
	session.tick(3.0)   # 越过等待，进入 FIGHTING
	_win_fight(session)
	session._zones = saved


## 找一段只含小鱼、不掺任何别的鱼（含豆包）的落点。
## 分带可能是显式的也可能是自动算出来的，所以从 session 的实际带里反推，不写死坐标。
func _small_point(session: FishingSession) -> float:
	for p in range(0, 100):
		var c := GameTuning.candidates_at(session._zones, float(p))
		if c.size() == 1 and String(c[0]["fish"]) == "small":
			return float(p)
	return 50.0


## 把当前这场搏斗打赢。圆环是看时机，测试里直接把游标摆到顶部再点。
func _win_fight(session: FishingSession) -> void:
	var guard := 0
	while session.phase == FishingSession.Phase.FIGHTING and guard < 400:
		var f := session.fight
		if f == null:
			break
		# 每次点完有冷却，得先耗掉才点得进去
		if f.input_locked():
			session.tick(0.1)
			guard += 1
			continue
		f.cursor = 0.0
		session.qte_strike()
		guard += 1

	# 上鱼后进入 LANDING，测试里直接跳过动画
	if session.phase == FishingSession.Phase.LANDING:
		session.landing_done()


# ---------- 用例 ----------

func _case_config() -> void:
	print("[case] 配置加载")
	var fish := ConfigLoader.load_fish()
	# 4 条正式/特殊鱼 + 豆包 = 5；豆包和陷阱都不算收集目标
	_check("鱼的总数（含陷阱与豆包）", fish.size(), 5)
	_ok("每条鱼都有 id", fish.all(func(f): return f.id != ""))
	_ok("每条鱼体力 > 0", fish.all(func(f): return f.stamina > 0.0))
	_ok("每条鱼有立绘路径", fish.all(func(f): return f.portrait != ""))

	# 陷阱只该有一条，且必须与大鱼同色，否则抛竿条上会露馅
	var traps := fish.filter(func(f): return f.is_claude)
	_check("陷阱数量", traps.size(), 1)
	_check("陷阱 id", traps[0].id if traps.size() > 0 else "", "claude")
	_ok("陷阱与大鱼同色", Palette.zone_color("claude") == Palette.zone_color("big"))
	_ok("陷阱有立绘文件", traps.size() > 0 and traps[0].has_portrait())

	# 豆包也是救济，同样不进收集目标；顺带确认它被正确标记
	var beans := fish.filter(func(f): return f.is_doubao)
	_check("豆包数量", beans.size(), 1)
	_check("豆包 id", beans[0].id if beans.size() > 0 else "", "doubao")
	_ok("豆包有立绘文件", beans.size() > 0 and beans[0].has_portrait())
	_check("豆包返还碗数", ConfigLoader.load_tuning().doubao_refund, 2)

	var targets := fish.filter(func(f): return not f.is_claude and not f.is_doubao)
	_check("收集目标数", targets.size(), 3)

	var t := ConfigLoader.load_tuning()
	_check("饵数量", t.bait_count, 4)
	_check("吃饱线（上鱼总次数）", t.full_catch_threshold, 3)
	# zones 现在挂在难度下面，顶层不写 —— 顶层写了就没人能靠切难度改分带
	_ok("顶层不写 zones（分带归难度管）", t.zones_explicit == false)
	_ok("difficulties 存在", not t.difficulties.is_empty())
	for key in GameTuning.DIFFICULTY_KEYS:
		_ok("难度 %s 存在" % key, t.difficulties.has(key))
	var opts := t.difficulty_options()
	_check("难度选项数量", opts.size(), 3)
	_ok("每个难度都有中文名", opts.all(func(o): return String(o["label"]) != ""))
	_ok("每个难度都有说明", opts.all(func(o): return String(o["blurb"]) != ""))

	var endings := ConfigLoader.load_endings()
	for key in ["feast", "full", "hungry", "claude"]:
		_ok("结局 %s 存在" % key, endings.has(key))
	# 通关结局只留一个，perfet/win 已被「齐鱼之福」取代
	_ok("旧通关结局已移除", not endings.has("perfect") and not endings.has("win"))
	# 单图结局看 image，多图结局看 pages —— claude_fake 走的是 pages 那条路
	_ok("每个结局都有图", endings.keys().all(func(k):
		if k.begins_with("_"):
			return true
		var d: Dictionary = endings[k]
		if String(d.get("image", "")) != "":
			return true
		return not d.get("pages", []).is_empty()
	))


## 普通鱼之间必须无缝。陷阱带刻意隔离在最后，那段空档是设计，所以跳过她，
## 并且只要求在普通鱼自己的覆盖跨度内没有洞 —— 跨度本身必须从 0 起。
func _has_no_gap(zone_list: Array, skip_fish: String = "") -> bool:
	var relevant: Array = []
	for z in zone_list:
		if skip_fish != "" and String(z["fish"]) == skip_fish:
			continue
		relevant.append(z)
	if relevant.is_empty():
		return false

	var lo := 1e9
	var hi := -1e9
	for z in relevant:
		lo = minf(lo, float(z["from"]))
		hi = maxf(hi, float(z["to"]))
	if lo > 0.001:
		return false

	var p := lo
	while p <= hi:
		var hit := false
		for z in relevant:
			if p >= float(z["from"]) and p <= float(z["to"]):
				hit = true
				break
		if not hit:
			return false
		p += 0.5
	return true


## 陷阱带必须与所有普通鱼隔离，玩家才得刻意抛到最远才可能撞上她。
func _trap_isolated(zone_list: Array) -> bool:
	var trap: Dictionary = {}
	var others: Array = []
	for z in zone_list:
		if String(z["fish"]) == "claude":
			trap = z
		else:
			others.append(z)
	if trap.is_empty():
		return false
	var tf := float(trap["from"])
	for z in others:
		if tf <= float(z["to"]):
			return false
	return true


func _case_auto_zones() -> void:
	print("[case] 自动分带")
	var fish := ConfigLoader.load_fish()
	var t := ConfigLoader.load_tuning()
	var zones := t.resolved_zones(fish)

	# auto_zones 只按体力给「要收集的鱼 + 陷阱」分带；豆包只有在显式 zones 里才会出现
	_check("分带数量 = 鱼的数量（不含豆包）", zones.size(), fish.size() - 1)
	_ok("自动分带里没有豆包", zones.all(func(z): return String(z["fish"]) != "doubao"))
	_ok("第一带从 0 开始", float(zones[0]["from"]) == 0.0)
	_ok("最后一带到 100 结束", float(zones[zones.size() - 1]["to"]) == 100.0)

	# 明确要求：不要 gap。整条 0~100 必须被覆盖，任何落点都有鱼。
	_ok("0~100 无空档（每 0.5 采样）", _has_no_gap(zones))

	# 相邻带必须重叠，否则分界线上永远只有前一条鱼能命中
	var overlapped := 0
	for i in range(1, zones.size()):
		if float(zones[i]["from"]) < float(zones[i - 1]["to"]):
			overlapped += 1
	_check("相邻带全部重叠", overlapped, zones.size() - 1)

	# 近 → 远 按体力升序
	_ok("最近的是体力最低的鱼", String(zones[0]["fish"]) == "small")
	_ok("最远的是体力最高的鱼", String(zones[zones.size() - 1]["fish"]) == "claude")

	# 重叠区里真的会抽到不同的鱼 —— 这是「区域重叠」的核心
	var overlap_point := (float(zones[1]["from"]) + float(zones[0]["to"])) * 0.5
	var cands := GameTuning.candidates_at(zones, overlap_point)
	_ok("重叠点有多个候选（≥ 2）", cands.size() >= 2)

	var seen: Dictionary = {}
	var rng := _seeded_rng()
	for i in 300:
		seen[GameTuning.pick_fish_at(zones, overlap_point, rng)] = true
	_ok("重叠点能抽到不止一种鱼", seen.size() >= 2)

	# 三档难度都要能解析出无空档的带（陷阱带刻意隔离，验普通鱼）
	for key in GameTuning.DIFFICULTY_KEYS:
		var dt := ConfigLoader.load_tuning()
		dt.apply_difficulty(key)
		var dz := dt.resolved_zones(fish)
		_ok("难度 %s 的普通鱼无空档" % key, _has_no_gap(dz, "claude"))
		_ok("难度 %s 的带数量正确" % key, dz.size() == fish.size())
		_ok("难度 %s 的陷阱带隔离在最远" % key, _trap_isolated(dz))
		_check("难度 %s 生效" % key, dt.difficulty, key)


func _case_extension_add_fish() -> void:
	print("[case] 扩展性：加一条鱼")
	var fish := ConfigLoader.load_fish()
	var t := ConfigLoader.load_tuning()

	var extra := FishSpec.from_dict({
		"id": "huge", "name": "超大肥鱼", "stamina": 300.0,
		"damage_ratio": 0.12, "tension_rate": 1.3,
	})
	var bigger := fish.duplicate()
	bigger.append(extra)

	var zones := t.resolved_zones(bigger)
	# 豆包不进自动分带，所以 6 条鱼只分 5 条带
	_check("6 条鱼 → 5 个带（豆包不占带）", zones.size(), bigger.size() - 1)
	_check("体力最高的排在最后", String(zones[4]["fish"]), "claude")
	_check("新加的鱼排在倒数第二", String(zones[3]["fish"]), "huge")
	_ok("新带仍然覆盖到 100", float(zones[4]["to"]) == 100.0)
	_ok("加鱼后依旧无空档", _has_no_gap(zones))

	# 能正常开局，不用改任何代码
	var s := FishingSession.new(bigger, t, _seeded_rng())
	s.start()
	_check("6 鱼局可以开局（收集目标 4 条）", s.fish_total(), 4)
	_check("6 鱼局饵数不变", s.bait_left, 4)
	_ok("陷阱与豆包都不计入收集目标", s.fish_total() == bigger.size() - 2)


func _case_ring() -> void:
	print("[case] 单键圆环（不是方向序列）")
	var fish := ConfigLoader.load_fish()
	var t := _test_tuning()
	for f in fish:
		var fight := FightSession.new(f, t, _seeded_rng())
		fight.start()
		print("       %s：约 %d 次命中上鱼，游标 %.2f 圈/秒" % [
			f.id, f.rounds_needed(), fight.current_speed()
		])
		_ok("%s 游标起点在 0~1" % f.id, fight.cursor >= 0.0 and fight.cursor < 1.0)
		_ok("%s 命中半宽够宽（>= 0.2）" % f.id, fight.current_hit_half() >= 0.2)
		_ok("%s 完美区不超过命中区" % f.id,
			fight.current_perfect_half() <= fight.current_hit_half())
		var hi := 10 if f.is_claude else 8
		if f.is_doubao:
			# 豆包是一份救济，一次命中就该捞上来，不该有难度
			_check("%s 一次命中上鱼" % f.id, f.rounds_needed(), 1)
		else:
			_ok("%s 上鱼次数在 3~%d 之间" % [f.id, hi],
				f.rounds_needed() >= 3 and f.rounds_needed() <= hi)

	# 游标随时间前进，绕满一圈回零
	var probe := FightSession.new(fish[0], t, _seeded_rng())
	probe.start()
	probe.cursor = 0.0
	var speed := probe.current_speed()
	probe.tick(0.1)
	_check("游标前进量 = 速度 × 时间", snappedf(probe.cursor, 0.001), snappedf(speed * 0.1, 0.001))
	probe.cursor = 0.98
	probe.tick(0.5)
	_ok("游标绕回 0~1", probe.cursor >= 0.0 and probe.cursor < 1.0)

	# 顶部命中 → 一轮 → 体力下降
	var hit := FightSession.new(fish[0], t, _seeded_rng())
	hit.start()
	var before := hit.stamina
	hit.cursor = 0.0
	_check("顶部点击返回 round", hit.strike(), "round")
	_ok("命中后体力下降", hit.stamina < before)
	_check("轮次 +1", hit.round_index, 1)
	_check("完美计数 +1", int(hit.stats["perfect"]), 1)
	_ok("命中后进入冷却", hit.input_locked())

	# 圆环另一端（底部）必然失手
	var miss := FightSession.new(fish[0], t, _seeded_rng())
	miss.start()
	var tension_before := miss.tension
	miss.cursor = 0.5
	_check("底部点击返回 miss", miss.strike(), "miss")
	_check("失手不算轮次", miss.round_index, 0)
	_ok("失手张力上涨", miss.tension > tension_before)
	_check("失手计数 +1", int(miss.stats["miss"]), 1)

	# 命中区边缘（但没进完美区）算 good，不给完美奖励
	var edge := FightSession.new(fish[0], t, _seeded_rng())
	edge.start()
	edge.cursor = (edge.current_hit_half() + edge.current_perfect_half()) * 0.5
	_check("命中区边缘算 good", edge.strike(), "good")
	_check("边缘不给完美", int(edge.stats["perfect"]), 0)

	# 体力越低游标越快
	var late := FightSession.new(fish[0], t, _seeded_rng())
	late.start()
	var slow := late.current_speed()
	late.stamina = late.stamina_max * 0.1
	_ok("体力见底后游标更快", late.current_speed() > slow)


## 击打冷却：点完一下之后的一小段时间里按下去不算数。
func _case_strike_lock() -> void:
	print("[case] 击打冷却")
	var fish := ConfigLoader.load_fish()
	var t := _test_tuning()
	var lock := float(t.fight_value("strike_lock", 0.3))
	_ok("tuning 里写了 strike_lock（0.3 左右）", absf(lock - 0.3) < 0.001)

	var f := FightSession.new(fish[0], t, _seeded_rng())
	f.start()
	f.cursor = 0.0
	f.strike()
	_ok("点完进入冷却", f.input_locked())
	_check("冷却时长 = 配置值", snappedf(f.lock_remaining(), 0.01), snappedf(lock, 0.01))

	# 冷却里再点：返回空，不涨张力，不算轮次
	var tension0 := f.tension
	var rounds0 := f.round_index
	f.cursor = 0.5
	_check("冷却中点击返回空", f.strike(), "")
	_check("冷却中不算轮次", f.round_index, rounds0)
	_check("冷却中不吃失手", snappedf(f.tension, 0.01), snappedf(tension0, 0.01))

	f.tick(lock - 0.05)
	_ok("差一点还没解冻", f.input_locked())
	f.tick(0.1)
	_ok("过了冷却解冻", not f.input_locked())
	f.cursor = 0.0
	_check("解冻后点击生效", f.strike(), "round")


func _case_charge_loops() -> void:
	print("[case] 蓄力无限循环（滚完不会输）")
	var s := _new_session()
	s.press()

	var wraps := 0
	var prev := 0.0
	var in_range := true
	# 5 秒 ≈ 4.3 圈，足够验证「滚完一圈会继续」而不是结束
	for i in 500:
		s.tick(0.01)
		if s.charge < 0.0 or s.charge > 1.0:
			in_range = false
		if s.charge < prev:
			wraps += 1
		prev = s.charge

	_ok("蓄力值始终在 0~1", in_range)
	_ok("至少绕回 3 次", wraps >= 3)
	_check("仍在瞄准阶段", s.phase, FishingSession.Phase.AIMING)
	_check("一碗饵都没扣", s.bait_left, 4)
	_check("一次都没抛出去", s.cast_point, 0.0)

	# 只有松手才真的抛
	s.release()
	_check("松手才扣饵", s.bait_left, 3)
	_check("松手后进入等待", s.phase, FishingSession.Phase.WAITING)


func _case_cast_and_bait() -> void:
	print("[case] 抛竿与扣饵")
	var s := _new_session()
	_check("初始阶段 AIMING", s.phase, FishingSession.Phase.AIMING)
	_check("初始饵", s.bait_left, 4)

	_cast_at(s, _small_point(s))   # 只落在小鱼带上，避开豆包带与重叠区
	_check("抛竿后扣一碗", s.bait_left, 3)
	_check("抛竿后进入 WAITING", s.phase, FishingSession.Phase.WAITING)

	s.tick(3.0)
	_check("等待结束进入搏斗", s.phase, FishingSession.Phase.FIGHTING)
	_ok("搏斗对象存在", s.fight != null)
	_check("钓到的是小鱼", s.pending_fish.id, "small")


func _case_empty_cast() -> void:
	print("[case] 空竿（手工造一个带洞的配置）")
	# 正常配置已经要求无空档，所以只能手工做一份有洞的来验空竿分支还活着
	var fish := ConfigLoader.load_fish()
	var t := ConfigLoader.load_tuning()
	t.zones = [
		{"id": "a", "fish": "small", "from": 0.0, "to": 30.0, "weight": 1.0},
		{"id": "b", "fish": "mid", "from": 30.0, "to": 42.0, "weight": 1.0},
		{"id": "c", "fish": "big", "from": 58.0, "to": 78.0, "weight": 1.0},
		{"id": "d", "fish": "claude", "from": 78.0, "to": 100.0, "weight": 1.0},
		# 豆包也得给一条带，否则 _covers_all 失败会回退到自动分带，洞就没了
		{"id": "e", "fish": "doubao", "from": 0.0, "to": 12.0, "weight": 0.2},
	]
	t.zones_explicit = true

	var s := FishingSession.new(fish, t, _seeded_rng())
	s.start()
	_cast_at(s, 50.0)   # 42~58 是那个洞
	s.tick(3.0)
	_check("空竿进入结果卡", s.phase, FishingSession.Phase.RESOLVING)
	_check("结果是空竿", s.last_result, FishingSession.RESULT_EMPTY)
	_ok("没有上鱼", s.caught_ids().is_empty())

	s.tick(3.0)
	_check("结果卡后回到 AIMING", s.phase, FishingSession.Phase.AIMING)


func _case_catch_all() -> void:
	print("[case] 三种集齐 → feast")
	var s := _new_session()
	_catch(s, "small")
	_check("钓到小鱼", s.caught_ids().has("small"), true)
	_check("钓到小鱼后剩余饵", s.bait_left, 3)

	_catch(s, "mid")
	_catch(s, "big")
	_check("三条集齐", s.caught_ids().size(), 3)
	# 集齐当场就是齐鱼之福，不必把剩下的饵烧完
	_ok("集齐就直接结算，不用烧完剩下的饵", s.phase == FishingSession.Phase.ENDED)
	_check("集齐的结局就是齐鱼之福", s.ending(), "feast")

	var sum := s.summary()
	_check("统计上鱼数", sum["caught_count"], 3)
	_check("统计上鱼次数", sum["landed"], 3)
	_ok("完成轮数 > 0", int(sum["rounds"]) > 0)
	_ok("按键数 > 0", int(sum["perfect"]) > 0)


func _case_full() -> void:
	print("[case] 钓够三条但没集齐 → full")
	# 全场只留小鱼一个带，每抛必中小鱼；上限三条就能验证「次数够但种类不够」
	var s := _new_session()
	s._zones = [{"id": "pin_small", "fish": "small", "from": 0.0, "to": 100.0, "weight": 1.0}]
	s.start()
	for i in 4:
		_cast_at(s, 50.0)
		s.tick(3.0)
		if s.phase == FishingSession.Phase.FIGHTING:
			_win_fight(s)
		s.tick(3.0)
	_check("饵用完", s.bait_left, 0)
	_check("上鱼次数 4", s.summary()["landed"], 4)
	_check("种类只有 1", s.caught_ids().size(), 1)
	_check("结局 full", s.ending(), "full")


func _case_hungry() -> void:
	print("[case] 饵用完不足三条 → hungry")
	# 把三档都塞进同一段窄带，再让搏斗全输，保证一次都没上鱼
	var fish := ConfigLoader.load_fish()
	var t := _test_tuning()
	t.bait_count = 3

	var s := FishingSession.new(fish, t, _seeded_rng())
	s.start()
	for i in 3:
		_cast_at(s, 50.0)
		s.tick(3.0)
		if s.phase == FishingSession.Phase.FIGHTING:
			# 一直点空档，直到张力爆掉
			var guard := 0
			while s.phase == FishingSession.Phase.FIGHTING and guard < 400:
				var f := s.fight
				if f == null:
					break
				if not f.input_locked():
					f.cursor = 0.5
					s.qte_strike()
				s.tick(0.1)
				guard += 1
		s.tick(3.0)
	_check("一条都没上", s.summary()["landed"], 0)
	_check("结局 hungry", s.ending(), "hungry")
	_check("阶段 ENDED", s.phase, FishingSession.Phase.ENDED)


func _case_repeat_catch() -> void:
	print("[case] 同一条可以反复上鱼")
	var s := _new_session()
	s.start()
	var before := s.bait_left
	_catch(s, "small")
	_check("第一次上鱼次数 1", s.summary()["landed"], 1)
	_check("会消耗饵", s.bait_left, before - 1)

	# 再钓同一条：照常进入搏斗、照常上鱼、照常扣饵，只是不重复计入收集
	_catch(s, "small")
	_check("第二次上鱼次数 2", s.summary()["landed"], 2)
	_check("收集种类仍是 1", s.caught_ids().size(), 1)
	_ok("没被当成重复拦下来", s.ending() != "full")


## 陷阱的核心契约：钓上她这一局立刻结束，且她不算「钓到的鱼」。
func _case_claude_trap() -> void:
	print("[case] 陷阱鱼：钓上即终止")
	var s := _new_session()
	# 这一段专测真陷阱，把假概率压到 0，免得被 rng 抽成 claude_fake
	s._tune.fake_claude_chance = 0.0
	_check("开局收集目标 = 3", s.fish_total(), 3)
	_ok("开局没钓到陷阱", s.claude_caught() == false)

	var zone := s.zone_of("claude")
	_ok("陷阱带存在", not zone.is_empty())
	if zone.is_empty():
		return

	var mid := (float(zone["from"]) + float(zone["to"])) * 0.5
	_cast_at(s, mid)
	s.tick(3.0)
	_check("陷阱也能咬钩", s.phase, FishingSession.Phase.FIGHTING)
	_check("咬钩的是陷阱", s.pending_fish.id, "claude")

	var guard := 0
	while s.phase == FishingSession.Phase.FIGHTING and guard < 600:
		var f := s.fight
		if f == null:
			break
		if f.input_locked():
			s.tick(0.1)
			guard += 1
			continue
		f.cursor = 0.0
		s.qte_strike()
		guard += 1

	_check("上鱼后进入 LANDING", s.phase, FishingSession.Phase.LANDING)
	_ok("已记录钓到陷阱", s.claude_caught())
	s.landing_done()

	_check("结局 claude", s.ending(), "claude")
	_check("阶段 ENDED", s.phase, FishingSession.Phase.ENDED)
	_ok("还有饵（不是没饵才结束的）", s.bait_left > 0)

	var sum := s.summary()
	_check("陷阱不计入收集进度", sum["caught_count"], 0)
	_ok("统计标记了陷阱", bool(sum["claude_caught"]))
	# 再 tick 也不该把局推进回 AIMING
	s.tick(5.0)
	_check("结束后不会自己重开", s.phase, FishingSession.Phase.ENDED)


## 假陷阱：同样终止，但结局走 claude_fake，且 summary 里带标记。
func _case_claude_fake() -> void:
	print("[case] 假陷阱：走 claude_fake 结局")
	# 概率两端都要能抽到
	var easy := GameTuning.from_dict({"difficulties": {
		"easy": {"fake_claude_chance": 0.85},
		"normal": {"fake_claude_chance": 0.75},
		"hard": {"fake_claude_chance": 0.6},
	}})
	easy.apply_difficulty("easy")
	_check("easy 假陷阱概率", easy.fake_claude_chance, 0.85)
	easy.apply_difficulty("hard")
	_check("hard 假陷阱概率", easy.fake_claude_chance, 0.6)
	_ok("真陷阱概率被压低（hard 仍 ≤ 0.4）", 1.0 - easy.fake_claude_chance <= 0.4)

	var s := _new_session()
	s._tune.fake_claude_chance = 1.0  # 保证是假的
	var zone := s.zone_of("claude")
	_ok("陷阱带存在", not zone.is_empty())
	if zone.is_empty():
		return
	_cast_at(s, (float(zone["from"]) + float(zone["to"])) * 0.5)
	s.tick(3.0)
	_check("咬钩的是陷阱", s.pending_fish.id, "claude")

	var guard := 0
	while s.phase == FishingSession.Phase.FIGHTING and guard < 600:
		var f := s.fight
		if f == null:
			break
		if f.input_locked():
			s.tick(0.1)
			guard += 1
			continue
		f.cursor = 0.0
		s.qte_strike()
		guard += 1

	s.landing_done()
	_check("结局 claude_fake", s.ending(), "claude_fake")
	_ok("summary 标记了假陷阱", bool(s.summary().get("claude_fake", false)))


## 豆包：近岸捞上来返还两碗饭，不算上鱼、不进收集、不触发结局。
func _case_doubao() -> void:
	print("[case] 豆包：返还两碗白饭")
	var fish := ConfigLoader.load_fish()
	var t := _test_tuning()
	_check("返还碗数配置", t.doubao_refund, 2)
	# 这个用例只测返还，把脱钩概率关掉，否则三分之一的机会它咬一口就跑
	t.doubao_escape_chance = 0.0

	var s := FishingSession.new(fish, t, _seeded_rng())
	s.start()
	_check("开局饵数", s.bait_left, 4)

	# 把带收窄到只剩豆包，保证抽中的一定是它
	s._zones = [{"id": "pin_doubao", "fish": "doubao", "from": 0.0, "to": 100.0, "weight": 1.0}]
	var refunds: Array = []
	s.doubao_started.connect(func(n): refunds.append(n))

	_cast_at(s, 50.0)
	_check("抛竿扣一碗", s.bait_left, 3)
	s.tick(3.0)
	_ok("咬钩的是豆包", s.pending_fish != null and s.pending_fish.id == "doubao")
	_win_fight(s)
	_check("上鱼后返还到 4（3 + 2 撞上限）", s.bait_left, 4)
	_ok("触发了返还信号", refunds.size() == 1)
	if refunds.size() == 1:
		_check("上限截断后只返还 1 碗", int(refunds[0]), 1)

	_check("豆包不算上鱼次数", s.summary()["landed"], 0)
	_check("豆包不进收集目标", s.caught_ids().size(), 0)
	_ok("豆包不会触发结局", s.ending() == "")

	# 饵不满时，返还应当真的补两碗
	s.bait_left = 1
	s._zones = [{"id": "pin_doubao", "fish": "doubao", "from": 0.0, "to": 100.0, "weight": 1.0}]
	refunds.clear()
	_cast_at(s, 50.0)
	_check("再抛扣到 0", s.bait_left, 0)
	s.tick(3.0)
	_win_fight(s)
	_check("返还后 2 碗", s.bait_left, 2)
	_ok("这次也发了返还信号", refunds.size() == 1)
	if refunds.size() == 1:
		_check("这次返还的就是 2 碗", int(refunds[0]), 2)


## 豆包咬一口就跑：脱钩概率必须真的掷出来，否则那张梗图是死代码。
func _case_doubao_escape() -> void:
	print("[case] 豆包脱钩")
	var fish := ConfigLoader.load_fish()
	var t := _test_tuning()
	_check("默认脱钩概率", t.doubao_escape_chance, 0.35)

	# 概率拉到 1，保证每次都跑
	t.doubao_escape_chance = 1.0
	var s := FishingSession.new(fish, t, _seeded_rng())
	s.start()
	s._zones = [{"id": "pin_doubao", "fish": "doubao", "from": 0.0, "to": 100.0, "weight": 1.0}]
	var refunds: Array = []
	s.doubao_started.connect(func(n): refunds.append(n))

	_cast_at(s, 50.0)
	_check("抛竿扣一碗", s.bait_left, 3)
	s.tick(3.0)

	_ok("咬钩的是豆包", s.pending_fish != null and s.pending_fish.id == "doubao")
	_ok("没有进入搏斗", s.fight == null)
	_check("判定为断线", s.last_result, FishingSession.RESULT_ESCAPED)
	_check("白饭不退，仍是 3", s.bait_left, 3)
	_check("没有返还信号", refunds.size(), 0)
	_check("不算上鱼次数", s.summary()["landed"], 0)
	_check("不进收集", s.caught_ids().size(), 0)
	_ok("不触发结局", s.ending() == "")

	# 概率归零时必须进入搏斗，证明这个开关真的在起作用
	t.doubao_escape_chance = 0.0
	var s2 := FishingSession.new(fish, t, _seeded_rng())
	s2.start()
	s2._zones = [{"id": "pin_doubao", "fish": "doubao", "from": 0.0, "to": 100.0, "weight": 1.0}]
	_cast_at(s2, 50.0)
	s2.tick(3.0)
	_ok("概率归零后进入搏斗", s2.fight != null)


## 图鉴：解锁是幂等的，坏文件不崩，清理能清空。
func _case_gallery() -> void:
	print("[case] 结局图鉴")
	# 图鉴封面：claude_fake 必须用掀头套那张，不是竖中指那张（那会剧透）
	var gr: Node = (load("res://scripts/ui/gallery_root.gd") as GDScript).new()
	gr._endings = ConfigLoader.load_endings()
	var cover: String = gr._thumb_of("claude_fake")
	_ok("claude_fake 封面是掀头套那张", cover.ends_with("claude_fake_2.webp"))
	_ok("通关结局封面用被窝合照", gr._thumb_of("feast").ends_with("ending_feast.webp"))
	gr.free()

	# override_path 已经在 _run_all 开头指向沙盒，这里一律不传 path ——
	# 传了也没用（_resolve 优先 override），反而让「坏文件」那条测错了对象
	Gallery.clear()
	_ok("初始为空", Gallery.load_unlocked().is_empty())

	_ok("第一次解锁返回 true", Gallery.unlock("feast"))
	_ok("重复解锁返回 false", not Gallery.unlock("feast"))
	_check("解锁数 = 1", Gallery.load_unlocked().size(), 1)

	Gallery.unlock("hungry")
	_check("解锁数 = 2", Gallery.load_unlocked().size(), 2)
	_ok("feast 仍在", Gallery.is_unlocked("feast"))
	_ok("claude 还没解锁", not Gallery.is_unlocked("claude"))
	_check("进度文案", Gallery.progress_text(5), "2 / 5")

	# 坏文件：写一段非法 JSON，读回来应当是空的而不是崩
	var path := Gallery.override_path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("{ not json at all")
		f.close()
	_ok("坏 JSON 当空处理", Gallery.load_unlocked().is_empty())

	Gallery.clear()
	_ok("清理后为空", Gallery.load_unlocked().is_empty())


## 图鉴三页：结局 / 脱钩 / 声音。顺带验 play_voice 会解锁、override_path 能隔离。
func _case_gallery_pages() -> void:
	print("[case] 图鉴三页")
	var gr: Node = (load("res://scripts/ui/gallery_root.gd") as GDScript).new()
	# _endings 只在 _ready 里拉，测试里得手动喂
	gr._endings = ConfigLoader.load_endings()

	# 页数与每页条目数
	_check("三页", gr.TABS.size(), 3)
	_check("结局页 8 条", gr._total_of("ending"), 8)
	_check("脱钩页 4 条", gr._total_of("escape"), 4)
	_check("声音页 14 条", gr._total_of("voice"), 14)

	# 每条脱钩条目都要有图、有 key、有唯一 key
	var keys: Array = []
	for it in gr.ESCAPE_ITEMS:
		var k := String(it["key"])
		_ok("脱钩 %s 有图" % k, String(it["image"]) != "")
		_ok("脱钩 %s 图存在" % k, ResourceLoader.exists(String(it["image"])))
		_ok("脱钩 %s key 不重复" % k, not keys.has(k))
		keys.append(k)

	# 每条语音条目都要有对应 mp3，且 Audio 认得出
	# --script 模式下 autoload 不在这里的作用域，得从 root 上摸
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = tree.root.get_node_or_null("Audio") if tree != null else null
	_ok("Audio 单例在树上", audio != null)
	for it in gr.VOICE_ITEMS:
		var k := String(it["key"])
		_ok("语音 %s 文件存在" % k, ResourceLoader.exists("res://assets/voice/" + k + ".ogg"))
		if audio != null:
			_ok("语音 %s Audio 能加载" % k, bool(audio.call("has_voice", k)))
	gr.free()

	# play_voice 会写图鉴。_run_all 已经把 override_path 指向沙盒，
	# 这里先清空验一遍干净起点，再确认播放真的落了账。
	Gallery.clear()
	_ok("沙盒起点为空", Gallery.load_unlocked().is_empty())
	if audio != null:
		audio.call("play_voice", "catch")
	_ok("播过就解锁 voice_catch", Gallery.is_unlocked("voice_catch"))
	_check("声音页解锁 1 条", Gallery.count_of("voice_"), 1)
	_check("总数也是 1", Gallery.count_of(""), 1)
	Gallery.clear()
	_ok("沙盒指向临时文件", Gallery.override_path != Gallery.PATH)


## 语音收集奖励：某个人的语音听全了，她的专属结局就进图鉴。
## 这两条结局不在任何游戏流程里触发，纯粹是「把她听完了」的回报。
func _case_voice_rewards() -> void:
	print("[case] 语音收集奖励结局")
	Gallery.clear()

	_ok("豆包结局初始锁着", not Gallery.is_unlocked("doubao_good"))
	_check("豆包还差 3 条", Gallery.missing_voice_for("doubao_good").size(), 3)
	_ok("普通结局没有收集条件", Gallery.missing_voice_for("feast").is_empty())

	# 豆包：一条一条听，前两条不该解锁
	Gallery.unlock("voice_bite_doubao")
	_check("听了 1 条还差 2", Gallery.missing_voice_for("doubao_good").size(), 2)
	_ok("听了 1 条仍锁着", not Gallery.is_unlocked("doubao_good"))
	_ok("check_rewards 此时不给东西", Gallery.check_rewards().is_empty())

	Gallery.unlock("voice_doubao_catch")
	_ok("听了 2 条仍锁着", not Gallery.is_unlocked("doubao_good"))
	Gallery.unlock("voice_doubao_escape")

	var fresh := Gallery.check_rewards()
	_ok("三条齐了会返回新解锁", fresh.has("doubao_good"))
	_ok("豆包结局已解锁", Gallery.is_unlocked("doubao_good"))
	_ok("豆包缺项清零", Gallery.missing_voice_for("doubao_good").is_empty())
	_ok("重复检查不再返回", Gallery.check_rewards().is_empty())

	# claude_good 改走剧情三段线，不再挂在语音收集上
	_ok("claude_good 不在语音奖励表里", not Gallery.VOICE_REWARDS.has("claude_good"))
	_ok("claude_good 没有收集条件", Gallery.missing_voice_for("claude_good").is_empty())

	# 两个奖励结局必须在 endings.json 里真有条目、真有图，否则图鉴上是个空壳
	var endings := ConfigLoader.load_endings()
	for k in Gallery.VOICE_REWARDS.keys():
		var key := String(k)
		_ok("%s 在 endings.json 里有条目" % key, endings.has(key))
		var d: Variant = endings.get(key, {})
		if typeof(d) == TYPE_DICTIONARY:
			var img := String((d as Dictionary).get("image", ""))
			_ok("%s 有图且文件存在" % key, img != "" and ResourceLoader.exists(img))
		else:
			_ok("%s 有图且文件存在" % key, false)

	Gallery.clear()


## 关于页：协议、出处、两条外链。
func _case_about() -> void:
	print("[case] 关于页")
	_ok("about.tscn 存在", ResourceLoader.exists("res://about.tscn"))
	_ok("about.json 存在", ResourceLoader.exists("res://data/about.json"))

	var ab: Node = (load("res://scripts/ui/about_root.gd") as GDScript).new()
	var data: Dictionary = ab._read_json("res://data/about.json")
	_ok("json 能解析", not data.is_empty())
	_ok("协议短名非空", String(data.get("license_short", "")) != "")
	_ok("有正文字段", String(data.get("intro", "")) != "")

	var secs: Array = data.get("sections", [])
	_ok("至少四节出处", secs.size() >= 4)
	for s in secs:
		_ok("小节「%s」有标题" % String(s.get("title", "")), String(s.get("title", "")) != "")
		_ok("小节「%s」有正文" % String(s.get("title", "")), String(s.get("body", "")) != "")

	var links: Array = data.get("links", [])
	_ok("至少两条外链", links.size() >= 2)
	var seen: Array = []
	for l in links:
		var url := String(l.get("url", ""))
		_ok("链接「%s」以 http 开头" % String(l.get("label", "")), url.begins_with("http"))
		_ok("链接「%s」不重复" % String(l.get("label", "")), not seen.has(url))
		seen.append(url)
	_ok("含 B 站主页", seen.has("https://space.bilibili.com/zh-Hans/4168597"))

	# 长链接会被截断，不能截成空串
	_ok("短链接原样显示", String(ab._pretty_url("https://a.cn/x")) == "a.cn/x")
	var long: String = ab._pretty_url("https://space.bilibili.com/zh-Hans/4168597")
	_ok("长链接非空", long != "" and long != "—")
	_ok("空链接显示占位", String(ab._pretty_url("")) == "—")

	# 彩蛋：四条图都要在，否则关于页会开出空框
	var eggs: Array = data.get("easter_eggs", [])
	_check("彩蛋四条", eggs.size(), 4)
	for e in eggs:
		var img := String(e.get("image", ""))
		_ok("彩蛋图「%s」存在" % img.get_file(), img != "" and ResourceLoader.exists(img))
		_ok("彩蛋「%s」有配字" % img.get_file(), String(e.get("caption", "")) != "")
	ab.free()


func _case_line_break() -> void:
	print("[case] 失手断线")
	var s := _new_session()
	_cast_at(s, _small_point(s))
	s.tick(3.0)
	var f := s.fight
	_ok("进入搏斗", f != null)
	if f == null:
		return

	var guard := 0
	while f.active and guard < 60:
		# 每次都点空档：不算轮次，张力一路涨到断线
		f.cursor = 0.5
		f.strike()
		f.tick(0.05)
		guard += 1

	_check("张力拉满", int(f.tension_ratio() * 100.0), 100)
	_ok("已结束", f.active == false)
	_check("结果是断线", s.last_result, FishingSession.RESULT_ESCAPED)
	_check("没钓到鱼", s.caught_ids().size(), 0)


func _case_scene_boot() -> void:
	print("[case] 场景装配")
	var g = _spawn_game()
	if g == null:
		return

	_ok("主控有 session", g._session != null)
	_check("HUD 只列收集目标", g._targets.size(), 3)
	_check("配置里含陷阱与豆包", g._fish.size(), 5)
	_ok("湖面已建", g._lake != null)
	_ok("抛竿面板已建", g._cast_panel != null)
	_ok("搏斗 QTE 已建", g._qte != null)
	_ok("上鱼动画已建", g._landing != null)
	_ok("场景提示已建", g._feedback != null)
	_ok("结算层已建", g._ending != null)
	_check("开局阶段", g._session.phase, FishingSession.Phase.AIMING)
	g.free()


## 暂停：ESC 和右上角那颗按钮走同一条路，暂停中 session 不许推进。
func _case_pause() -> void:
	print("[case] 暂停")
	var g = _spawn_game()
	if g == null:
		return

	_ok("开局没在暂停", g._paused_layer == null and not get_root().get_tree().paused)
	_ok("右上角有暂停键", _collect_button_text(g).has("Ⅱ"))

	# 记一个会变的量：暂停期间它必须一动不动
	g._session.charge = 0.37
	g._pause_game()
	_ok("暂停后遮罩在", g._paused_layer != null)
	_ok("暂停后场景树冻结", get_root().get_tree().paused)

	var before: float = g._session.charge
	g._process(0.5)
	g._process(0.5)
	_check("暂停中 session 不推进", g._session.charge, before)

	g._resume_game()
	_ok("继续后遮罩没了", g._paused_layer == null)
	_ok("继续后场景树解冻", not get_root().get_tree().paused)

	# 再暂停一次，走「重新开始」那条路，必须解冻并且换一局新的
	g._pause_game()
	var old: FishingSession = g._session
	g._restart_from_pause()
	_ok("重新开始后遮罩没了", g._paused_layer == null)
	_ok("重新开始后场景树解冻", not get_root().get_tree().paused)
	_ok("重新开始后是新的 session", g._session != null and g._session != old)
	_check("重新开始后回到起手", g._session.phase, FishingSession.Phase.AIMING)

	g.free()
	get_root().get_tree().paused = false


## 收集一棵节点树下所有 Button 的文字，用来验按钮有没有真的被摆出来。
func _collect_button_text(root: Node) -> Array:
	var out: Array = []
	for b in root.find_children("*", "Button", true, false):
		out.append(String((b as Button).text))
	return out


func _case_mouse_policy() -> void:
	print("[case] 鼠标不拦截（点击必须能落到 _unhandled_input）")
	var g = _spawn_game()
	if g == null:
		return
	# 任何非按钮的 Control 只要 mouse_filter = STOP，就会把点击吃掉，
	# 玩家点画面将毫无反应。这条用例守住那个坑。
	var blocking := _find_blocking_control(g)
	_check("没有非按钮 Control 拦截鼠标", blocking, "")
	g.free()


## 实例化主场景并挂到树上，_ready 会同步跑完。
func _spawn_game():
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail += 1
		print("  FAIL 无法加载 main.tscn")
		return null
	var g = packed.instantiate()
	get_root().add_child(g)
	return g


## 结算层不能因为某个结局缺字段就崩 —— 四种结局全摆一遍。
func _case_ending_overlay() -> void:
	print("[case] 结算层：四种结局都能摆出来")
	var fish := ConfigLoader.load_fish()
	var endings := ConfigLoader.load_endings()
	var targets := fish.filter(func(f): return not f.is_claude and not f.is_doubao)

	var overlay := EndingOverlay.new()
	get_root().add_child(overlay)

	var sample := _sample_summary()
	for key in ["feast", "full", "hungry", "claude"]:
		_ok("结局 %s 有配置" % key, endings.has(key))
		overlay.show_ending(key, endings.get(key, {}), sample, targets)
		_ok("结局 %s 装配出了内容" % key,
			overlay._box != null and overlay._box.get_child_count() > 0)

	# 陷阱结局里，三条鱼应当全是未钓到
	overlay.show_ending("claude", endings.get("claude", {}), sample, targets)
	_ok("陷阱结局仍列出三条目标", targets.size() == 3)

	# 卡片必须可滚动，否则 1280×800 下内容会把底部按钮顶出屏幕
	_ok("结算卡片套了滚动容器", overlay._scroll != null)
	if overlay._scroll != null:
		_ok("滚动容器允许纵向滚动",
			overlay._scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	_ok("按钮条在滚动区外", overlay._footer != null)
	if overlay._scroll != null and overlay._footer != null:
		# 手机上 ScrollContainer 拖不动，按钮只要还在滚动区里就等于消失
		_ok("按钮条不是滚动区的后代", not overlay._scroll.is_ancestor_of(overlay._footer))
		_ok("按钮条不参与滚动", overlay._footer.get_parent() != overlay._scroll)

	# 多图结局翻到最后一页，三个按钮必须都在
	overlay.show_ending("claude_fake", endings.get("claude_fake", {}), sample, targets)
	_check("多图结局有 3 页", overlay._pages.size(), 3)
	overlay._next_page()
	overlay._next_page()
	_check("翻到最后一页", overlay._page_index, 2)
	var labels := _collect_button_text(overlay)
	_ok("最后一页有「再来一局」", labels.has("再来一局"))
	_ok("最后一页有「返回菜单」", labels.has("返回菜单"))
	_ok("最后一页有「退出」", labels.has("退出"))

	overlay.free()

	# 结算翻页的图框必须跟图片同比例，否则 STRETCH_KEEP_ASPECT_CENTERED 会切边
	for asset in ["res://assets/claude_fake_1.webp", "res://assets/claude_fake_2.webp", "res://assets/claude_fake_3.webp"]:
		var pic := UIKit.picture_fit(asset, Vector2(420, 420))
		var tex := pic.texture
		if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
			_ok("%s 能加载" % asset.get_file(), false)
			pic.free()
			continue
		var ms := pic.custom_minimum_size
		var ar_tex := float(tex.get_width()) / float(tex.get_height())
		var ar_frame := ms.x / ms.y
		_ok("%s 框与图同比例（不裁边）" % asset.get_file(), absf(ar_frame - ar_tex) < 0.01)
		_ok("%s 框不超出 420" % asset.get_file(), ms.x <= 420.5 and ms.y <= 420.5)
		pic.free()


func _sample_summary() -> Dictionary:
	return {
		"bait_total": 5, "bait_left": 2, "bait_used": 3,
		"caught": ["small"], "caught_count": 1, "landed": 2, "fish_total": 3,
		"claude_caught": false,
		"rounds": 12, "perfect": 7, "good": 12, "miss": 4,
	}


## 设置读写：正常、坏 JSON、未知难度三条路。
func _case_settings_roundtrip() -> void:
	print("[case] 设置读写")
	var scratch := "user://selftest_settings.json"

	var s := GameSettings.new()
	s.difficulty = "hard"
	s.save(scratch)
	_check("难度能读回", GameSettings.load_settings(scratch).difficulty, "hard")

	# 写坏了不该崩，应该静默回落
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	_check("坏文件回落默认", GameSettings.load_settings(scratch).difficulty, GameSettings.DEFAULT_DIFFICULTY)

	# 不认识的难度同样回落，而不是原样塞进 tuning
	f = FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string('{"difficulty":"nightmare"}')
	f.close()
	_check("未知难度回落默认", GameSettings.load_settings(scratch).difficulty, GameSettings.DEFAULT_DIFFICULTY)

	# 文件不存在也不该崩
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	_check("文件不存在回落默认", GameSettings.load_settings(scratch).difficulty, GameSettings.DEFAULT_DIFFICULTY)


## 声音偏好：四个字段能存能读，坏值被夹住。
func _case_audio_settings() -> void:
	print("[case] 声音偏好")
	var scratch := "user://selftest_audio.json"

	var s := GameSettings.new()
	s.bgm_on = false
	s.bgm_volume = 0.3
	s.voice_on = true
	s.voice_volume = 0.7
	s.save(scratch)

	var back := GameSettings.load_settings(scratch)
	_ok("BGM 开关能读回", back.bgm_on == false)
	_ok("BGM 音量能读回", absf(back.bgm_volume - 0.3) < 0.001)
	_ok("语音开关能读回", back.voice_on == true)
	_ok("语音音量能读回", absf(back.voice_volume - 0.7) < 0.001)

	# 越界音量要被夹回 0~1，不能拿着 3.0 去算 dB
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string('{"bgm_volume": 3.0, "voice_volume": -2.0}')
	f.close()
	var bad := GameSettings.load_settings(scratch)
	_ok("音量上界被夹住", bad.bgm_volume <= 1.0)
	_ok("音量下界被夹住", bad.voice_volume >= 0.0)

	# 缺字段走默认值，不是 0
	f = FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string('{"difficulty":"easy"}')
	f.close()
	var bare := GameSettings.load_settings(scratch)
	_ok("缺声音字段时 BGM 默认开", bare.bgm_on == true)
	_ok("缺声音字段时语音默认开", bare.voice_on == true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## 音频总管：单例在、12 条台词都在盘上、BGM 资源能加载。
func _case_audio_director() -> void:
	print("[case] 音频总管")
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = null
	if tree != null and tree.root != null:
		audio = tree.root.get_node_or_null("Audio")
	_ok("Audio 单例已注册为 autoload", audio != null)
	if audio == null:
		return

	var keys := [
		"bite_small", "bite_mid", "bite_big", "bite_claude", "bite_doubao",
		"catch", "escape", "feast", "full", "hungry", "claude", "claude_fake",
		"doubao_catch", "doubao_escape",
	]
	var missing: Array = []
	for k in keys:
		if not bool(audio.call("has_voice", k)):
			missing.append(k)
	_check("14 条台词全部可加载", missing.size(), 0)
	if not missing.is_empty():
		print("     缺: ", missing)

	_ok("豆包脱钩梗图存在", ResourceLoader.exists("res://assets/doubao_escape.webp"))
	_ok("豆包上钩梗图存在", ResourceLoader.exists("res://assets/doubao_kick.webp"))

	_ok("BGM 资源存在", ResourceLoader.exists("res://assets/bgm/lake_loop.ogg"))
	var bgm := load("res://assets/bgm/lake_loop.ogg") as AudioStream
	_ok("BGM 能解析成 AudioStream", bgm != null)
	_ok("BGM 是 ogg 且开了循环", bgm is AudioStreamOggVorbis and (bgm as AudioStreamOggVorbis).loop)

	# 灌一份语音关掉的设置，play_voice 应该直接拒绝
	var quiet := GameSettings.new()
	quiet.voice_on = false
	audio.call("apply_settings", quiet)
	_ok("语音关掉后不播", bool(audio.call("play_voice", "catch")) == false)
	audio.call("apply_settings", GameSettings.new())



## 主菜单只负责开始 + 四个入口，难度和音量搬去 settings.tscn 了。
func _case_menu_boot() -> void:
	print("[case] 菜单装配")
	var packed := load("res://menu.tscn") as PackedScene
	_ok("menu.tscn 能加载", packed != null)
	if packed == null:
		return

	var original := GameSettings.load_settings().difficulty

	var m = packed.instantiate()
	get_root().add_child(m)

	var labels := _collect_button_text(m)
	_ok("菜单有「开始钓鱼」", labels.has("开 始 钓 鱼"))
	_ok("菜单有「设置」入口", labels.has("设 置"))
	_ok("菜单不再摆难度按钮", not labels.has("轻松") and not labels.has("普通") and not labels.has("困难"))
	_ok("菜单不再摆音量滑块", _count_type(m, "HSlider") == 0)

	m.free()

	# 设置页：难度三按钮 + 两个滑块 + 落盘
	var sp := load("res://settings.tscn") as PackedScene
	_ok("settings.tscn 能加载", sp != null)
	if sp == null:
		return
	var s = sp.instantiate()
	get_root().add_child(s)

	_check("设置页难度按钮数", s._buttons.size(), 3)
	_ok("当前难度有对应按钮", s._buttons.has(s._settings.difficulty))
	_ok("设置页有说明文字", s._blurb != null and s._blurb.text != "")
	_check("设置页有两个音量滑块", _count_type(s, "HSlider"), 2)

	s._on_pick("hard")
	_check("切换难度生效", s._settings.difficulty, "hard")
	_check("难度已落盘", GameSettings.load_settings().difficulty, "hard")

	var restore := GameSettings.new()
	restore.difficulty = original
	restore.save()
	s.free()


## 递归数某类节点有几个，用来确认菜单里确实没有滑块了。
func _count_type(root: Node, cls: String) -> int:
	var n := 0
	if root.is_class(cls):
		n += 1
	for c in root.get_children():
		n += _count_type(c, cls)
	return n


## 难度必须真的改到数值上，不能只是换个标签。
func _case_difficulty_affects_game() -> void:
	print("[case] 难度影响数值")
	var base := ConfigLoader.load_tuning()
	var base_bait := base.bait_count
	var base_jitter := base.cast_jitter
	var base_miss := float(base.fight_value("miss_tension", 0.0))

	var easy := ConfigLoader.load_tuning()
	easy.apply_difficulty("easy")
	var hard := ConfigLoader.load_tuning()
	hard.apply_difficulty("hard")

	_ok("轻松饵更多", easy.bait_count > hard.bait_count)
	_ok("轻松手感更宽容（jitter 更大）", easy.cast_jitter > hard.cast_jitter)
	_ok("困难按错更疼", float(hard.fight_value("miss_tension", 0.0)) > float(easy.fight_value("miss_tension", 0.0)))

	# 黄标宽度与游标转速必须随难度走 —— 这是环上唯一能读出难度的地方
	var easy_hit := float(easy.fight_value("hit_half", 0.0))
	var hard_hit := float(hard.fight_value("hit_half", 0.0))
	var easy_spd := float(easy.fight_value("cursor_speed", 0.0))
	var hard_spd := float(hard.fight_value("cursor_speed", 0.0))
	var base_hit := float(base.fight_value("hit_half", 0.0))
	_ok("轻松黄标更宽", easy_hit > base_hit)
	_ok("困难黄标更窄", hard_hit < base_hit)
	_ok("轻松游标更慢", easy_spd < hard_spd)
	_ok("困难游标更快", hard_spd > easy_spd)
	# 收得再狠也不能让手机上按不中：hit_half 下限 0.14（约 100°）
	_ok("困难黄标仍 ≥ 100°", hard_hit >= 0.14)
	# 三档之间必须真的不一样，不能有哪一档漏配
	var seen: Array = []
	for key in GameTuning.DIFFICULTY_KEYS:
		var t := ConfigLoader.load_tuning()
		t.apply_difficulty(String(key))
		var sig := "%.3f/%.3f" % [float(t.fight_value("hit_half", 0.0)), float(t.fight_value("cursor_speed", 0.0))]
		_ok("难度 %s 的 黄标/转速 = %s 不重复" % [key, sig], not seen.has(sig))
		seen.append(sig)

	_check("顶层值不被难度污染（重新读一遍还是原值）", ConfigLoader.load_tuning().bait_count, base_bait)
	_ok("顶层 jitter 未被污染", absf(ConfigLoader.load_tuning().cast_jitter - base_jitter) < 0.001)
	_ok("顶层 miss_tension 未被污染", absf(float(ConfigLoader.load_tuning().fight_value("miss_tension", 0.0)) - base_miss) < 0.001)
	_ok("顶层 黄标/转速 未被污染",
		absf(float(ConfigLoader.load_tuning().fight_value("hit_half", 0.0)) - base_hit) < 0.001)

	# 未知难度不能崩，要静默落回 normal
	var weird := ConfigLoader.load_tuning()
	weird.apply_difficulty("nightmare")
	_check("未知难度落回 normal", weird.difficulty, "normal")


func _find_blocking_control(node: Node) -> String:
	for child in node.get_children():
		if child is BaseButton:
			continue
		if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			return String(child.name)
		var found := _find_blocking_control(child)
		if found != "":
			return found
	return ""
