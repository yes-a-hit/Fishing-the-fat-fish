class_name FishingSession
extends RefCounted

## 一局钓鱼的全部规则 —— 纯逻辑，不碰 Node、不读文件、不碰输入。
##
## 一次完整的循环：
##   AIMING（按住蓄力条瞄准） → 松手 → WAITING（饵在水里等咬钩）
##   → FIGHTING（圆环搏斗，看准时机点一下）
##   → LANDING（上鱼飞扑动画，仅成功时走）
##   → RESOLVING（断线/空竿的场景内提示，仅失败时走）
##   → 回到 AIMING 或 ENDED
##
## 所有阶段转移都只经过 _set_phase()，不要在别处直接赋值 phase。
## UI 只做两件事：读 phase 决定显示什么，连信号更新画面。
## 规则判断一律写在这里，测试才能脱离界面跑。

enum Phase { AIMING, WAITING, FIGHTING, LANDING, RESOLVING, ENDED }

## resolved() 的三种结果
const RESULT_CAUGHT := "caught"        ## 上鱼
const RESULT_ESCAPED := "escaped"      ## 断线跑鱼
const RESULT_EMPTY := "empty"          ## 空竿，没鱼咬钩

signal phase_changed(phase: int)
signal bait_changed(left: int, total: int)
signal charge_changed(value: float)
signal cast_made(point: float, fish_id: String)
signal bite_started(fish: FishSpec, fight: FightSession)
signal landing_started(fish: FishSpec)
signal resolved(kind: String, fish: FishSpec)
signal doubao_started(refund: int)
signal finished(ending: String, summary: Dictionary)

var phase: int = Phase.ENDED
var bait_max: int = 5
var bait_left: int = 5
var charge: float = 0.0
var cast_point: float = 0.0
var fight: FightSession = null
var pending_fish: FishSpec = null
var last_result: String = ""

var rng: RandomNumberGenerator = null

var _fish: Array = []
var _targets: Array = []      ## 收集目标，不含 is_claude 的陷阱
var _tune: GameTuning = null
var _zones: Array = []
var _caught: Array = []       ## 钓到过的鱼 id（去重），只用于「集齐」判定
var _landed: int = 0          ## 本局上鱼总次数。可以重复钓同一条，所以不等于 _caught.size()
var _charging: bool = false
var _wait_left: float = 0.0
var _resolve_left: float = 0.0
var _landing_left: float = 0.0
var _empty_reason: String = ""
var _ending: String = ""
var _pending_claude_fake: bool = false   ## 这次抛向陷阱带，钓上来的会不会是假的
var _totals: Dictionary = {"rounds": 0, "perfect": 0, "miss": 0}


func _init(fish_list: Array, tuning: GameTuning, rng_source: RandomNumberGenerator = null) -> void:
	_fish = fish_list.duplicate()
	_tune = tuning
	# 收集目标与特殊鱼分开存：claude 与豆包都参与分带，但不参与「集齐」判定
	_targets = []
	for f in _fish:
		if not f.is_claude and not f.is_doubao:
			_targets.append(f)
	# 距离带在这里一次性解析：加鱼不用改配置，见 GameTuning.resolved_zones()
	_zones = tuning.resolved_zones(_fish)
	rng = rng_source if rng_source != null else RandomNumberGenerator.new()
	if rng_source == null:
		rng.randomize()
	bait_max = tuning.bait_count
	bait_left = tuning.bait_count
	phase = Phase.ENDED


## 开一局。调用后进入 AIMING。
func start() -> void:
	bait_max = _tune.bait_count
	bait_left = bait_max
	_caught.clear()
	_landed = 0
	_totals = {"rounds": 0, "perfect": 0, "miss": 0}
	pending_fish = null
	fight = null
	charge = 0.0
	_charging = false
	_landing_left = 0.0
	_empty_reason = ""
	last_result = ""
	_ending = ""
	bait_changed.emit(bait_left, bait_max)
	_set_phase(Phase.AIMING)


func is_charging() -> bool:
	return _charging


func caught_ids() -> Array:
	return _caught.duplicate()


func fish_list() -> Array:
	return _fish.duplicate()


## 收集目标（不含陷阱）。HUD、结算、集齐判定都用这个。
func targets() -> Array:
	return _targets.duplicate()


func fish_total() -> int:
	return _targets.size()


## 本局是否已经把陷阱钓上来了。
func claude_caught() -> bool:
	for id in _caught:
		for f in _fish:
			if f.id == id and f.is_claude:
				return true
	return false


## 当前生效的距离带，UI 画抛竿条时直接用。
func zones() -> Array:
	return _zones.duplicate(true)


## 某条鱼对应的距离带。
func zone_of(fish_id: String) -> Dictionary:
	return GameTuning.zone_of(_zones, fish_id)


func ending() -> String:
	return _ending


## 某条鱼是否已经钓到。
func is_caught(fish_id: String) -> bool:
	return _caught.has(fish_id)


# ---------- 输入入口 ----------

## 按下主键。AIMING 开始蓄力，RESOLVING 跳过等待，FIGHTING 走圆环判定。
## 三种状态共用同一个「点一下」，手机上不需要额外的虚拟按键。
func press() -> void:
	match phase:
		Phase.AIMING:
			_charging = true
		Phase.FIGHTING:
			qte_strike()
		Phase.RESOLVING:
			# 防误触：提示至少露脸 0.35 秒才允许点击跳过
			if _resolve_left <= _tune.resolve_hold - 0.35:
				_advance_after_round()


## 搏斗期点了一下。返回 "round" / "good" / "miss"，非搏斗期或冷却中返回 ""。
func qte_strike() -> String:
	if phase != Phase.FIGHTING or fight == null:
		return ""
	return fight.strike()


## 上鱼动画播完，由 UI 调用。逻辑层也留了超时兜底，不会卡死。
func landing_done() -> void:
	if phase != Phase.LANDING:
		return
	_advance_after_round()


## 松开主键。只在蓄力中有效，把当前蓄力值作为抛竿力气。
func release() -> void:
	if phase != Phase.AIMING or not _charging:
		return
	_charging = false
	_cast()


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	match phase:
		Phase.AIMING:
			_tick_aiming(delta)
		Phase.WAITING:
			_tick_waiting(delta)
		Phase.FIGHTING:
			if fight != null:
				fight.tick(delta)
		Phase.LANDING:
			_tick_landing(delta)
		Phase.RESOLVING:
			_tick_resolving(delta)


# ---------- 各阶段推进 ----------

func _tick_aiming(delta: float) -> void:
	if not _charging:
		return
	var speed := 1.0 / maxf(_tune.charge_full_seconds, 0.05)
	# 循环滚动：走到远洋（100）之后从近岸（0）重新进来，一直转下去。
	# 滚完一圈不等于结束、不扣饵、更不判负 —— 玩家想等多久就等多久，
	# 直到看见想要的区域再松手。这是「循环」不是「来回折返」，
	# 方向永远一致，玩家才好预判下一圈什么时候到。
	charge = fmod(charge + speed * delta, 1.0)
	if charge < 0.0:
		charge += 1.0
	charge_changed.emit(charge)


func _cast() -> void:
	if bait_left <= 0:
		return

	bait_left -= 1
	bait_changed.emit(bait_left, bait_max)

	cast_point = clampf(
		charge * 100.0 + rng.randf_range(-_tune.cast_jitter, _tune.cast_jitter),
		0.0, 100.0
	)
	charge = 0.0
	charge_changed.emit(0.0)

	# 距离带是重叠的：覆盖该点且**没被隔离**的鱼全部进池子，按 weight 抽一条。
	# 注意不过滤已钓到的鱼 —— 同一条可以反复上，只是不再计入收集。
	var pool := GameTuning.candidates_at(_zones, cast_point)

	if pool.is_empty():
		pending_fish = null
		# 一条鱼都不覆盖该点 = 空竿。当前只有陷阱带与前一条鱼之间的隔离区会走到这里。
		_empty_reason = RESULT_EMPTY
		_wait_left = _tune.empty_wait
	else:
		pending_fish = _find_fish(_weighted_pick(pool))
		_empty_reason = ""
		_wait_left = rng.randf_range(_tune.bite_delay_min, _tune.bite_delay_max)
		# 远洋尽头那条到底是陷阱还是套着头套的鲸鱼娘，抛下去的那一刻就定了。
		# 她一样会挣扎、一样要打满，玩家在钓上来之前没有分辨的办法。
		_pending_claude_fake = false
		if pending_fish != null and pending_fish.is_claude:
			_pending_claude_fake = rng.randf() < _tune.fake_claude_chance

	cast_made.emit(cast_point, pending_fish.id if pending_fish != null else "")

	_set_phase(Phase.WAITING)


## 从候选池里按 weight 加权抽一条鱼 id。池子必须非空。
func _weighted_pick(pool: Array) -> String:
	var total := 0.0
	for c in pool:
		total += float(c["weight"])
	if total <= 0.0:
		return String(pool[0]["fish"])
	var roll := rng.randf() * total
	for c in pool:
		roll -= float(c["weight"])
		if roll <= 0.0:
			return String(c["fish"])
	return String(pool[pool.size() - 1]["fish"])


func _tick_waiting(delta: float) -> void:
	_wait_left -= delta
	if _wait_left > 0.0:
		return
	if pending_fish == null:
		_resolve(_empty_reason if _empty_reason != "" else RESULT_EMPTY)
	elif pending_fish.is_doubao and rng.randf() < _tune.doubao_escape_chance:
		# 豆包咬一口就跑。它 damage_ratio = 1.0，一轮就上鱼，
		# 张力永远没机会爆表 —— 不在咬钩这一下掷骰，脱钩画面就是死代码。
		_resolve(RESULT_ESCAPED)
	else:
		_start_fight()


func _start_fight() -> void:
	fight = FightSession.new(pending_fish, _tune, rng)
	fight.finished.connect(_on_fight_finished)
	_set_phase(Phase.FIGHTING)
	bite_started.emit(pending_fish, fight)
	fight.start()


func _on_fight_finished(success: bool, _reason: String) -> void:
	_accumulate(fight)

	if not success:
		_resolve(RESULT_ESCAPED)
		return

	if pending_fish != null and pending_fish.is_doubao:
		# 豆包既不算上鱼次数也不进收集：它只是一碗饭的返场。
		# 抛出去的那碗还回来，再额外补一碗，但总量封在开局碗数上。
		var before := bait_left
		bait_left = mini(bait_left + _tune.doubao_refund, bait_max)
		if bait_left != before:
			bait_changed.emit(bait_left, bait_max)
		doubao_started.emit(bait_left - before)
	elif pending_fish != null:
		_landed += 1
		if not _caught.has(pending_fish.id):
			_caught.append(pending_fish.id)

	# 上鱼不走结果卡，交给 LANDING 播飞扑动画；动画结束由 UI 调 landing_done()
	last_result = RESULT_CAUGHT
	_landing_left = _tune.landing_timeout
	_set_phase(Phase.LANDING)
	landing_started.emit(pending_fish)


func _accumulate(f: FightSession) -> void:
	if f == null:
		return
	for key in ["rounds", "perfect", "miss"]:
		_totals[key] = int(_totals.get(key, 0)) + int(f.stats.get(key, 0))


func _resolve(kind: String) -> void:
	last_result = kind
	_resolve_left = _tune.resolve_hold
	_set_phase(Phase.RESOLVING)
	resolved.emit(kind, pending_fish)


func _tick_landing(delta: float) -> void:
	# 兜底：万一 UI 没接上（比如无窗口测试），动画时间一到也自动往下走
	_landing_left -= delta
	if _landing_left <= 0.0:
		landing_done()


func _tick_resolving(delta: float) -> void:
	_resolve_left -= delta
	if _resolve_left <= 0.0:
		_advance_after_round()


## 一次抛竿彻底结束后的去向：踩到陷阱 / 集齐 / 吃饱 / 没吃饱 / 继续钓。
func _advance_after_round() -> void:
	if phase != Phase.RESOLVING and phase != Phase.LANDING:
		return

	# 陷阱优先级最高：钓上 claude 这一局就到此为止，不算赢也不算没饵
	if claude_caught():
		# 掀开头套发现是自己人 —— 她也照样把这一局终结掉了，只是结算画面完全不一样
		_finish("claude_fake" if _pending_claude_fake else "claude")
		return

	# 集齐三种 = 齐鱼之福，这是唯一的「通关」
	if _caught_target_count() >= _targets.size() and not _targets.is_empty():
		_finish("feast")
		return

	# 没集齐就得把饵用完才结算：钓够三条算吃饱，不够算没吃饱
	if bait_left <= 0:
		_finish("full" if _landed >= _tune.full_catch_threshold else "hungry")
		return

	pending_fish = null
	fight = null
	_empty_reason = ""
	_set_phase(Phase.AIMING)


## 已钓到的收集目标数，陷阱不计。
func _caught_target_count() -> int:
	var n := 0
	for f in _targets:
		if _caught.has(f.id):
			n += 1
	return n


func _finish(kind: String) -> void:
	if phase == Phase.ENDED:
		return
	_ending = kind
	_set_phase(Phase.ENDED)
	finished.emit(kind, summary())


func summary() -> Dictionary:
	return {
		"bait_total": bait_max,
		"bait_left": bait_left,
		"bait_used": bait_max - bait_left,
		"caught": _caught.duplicate(),
		"caught_count": _caught_target_count(),
		"landed": _landed,
		"fish_total": _targets.size(),
		"claude_caught": claude_caught(),
		"claude_fake": _pending_claude_fake,
		"rounds": int(_totals.get("rounds", 0)),
		"perfect": int(_totals.get("perfect", 0)),
		"good": maxi(int(_totals.get("rounds", 0)) - int(_totals.get("miss", 0)), 0),
		"miss": int(_totals.get("miss", 0)),
	}


# ---------- 工具 ----------

func _find_fish(fish_id: String) -> FishSpec:
	for f in _fish:
		if f.id == fish_id:
			return f
	return null


func _set_phase(next: int) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)
