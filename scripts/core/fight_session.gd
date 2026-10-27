class_name FightSession
extends RefCounted

## 一条鱼的搏斗过程 —— 纯逻辑，不碰 Node、不读文件、不碰输入。
##
## 搏斗期只有一种操作：**看准时机点一下**（空格 / 鼠标左键 / 触摸屏）。
## 屏幕上是一个圆环，游标从顶部顺时针转，转到顶部那段弧里点下去就算命中。
##
## 为什么回到单键圆环：
##   方向序列在键盘上很爽，但搬到手机上就没法按了 —— 要么加虚拟摇杆
##   （屏幕上多出一坨东西），要么改成滑动（和抛竿手势冲突）。
##   单键点击是唯一在手机上「零学习成本、不占屏幕、不误触」的方案。
##   判定弧还刻意放宽到六成圆周，手机上手指出点偏差也不至于直接失手。
##
## 两条资源线：
##   体力（stamina）—— 进度条，每命中一次削一截，削空就上鱼。
##   张力（tension）—— 倒计时，一直涨；命中降一点，失手猛涨。
## 张力涨满 = 断线，鱼跑。

signal cursor_changed(pos: float)
signal stamina_changed(ratio: float)
signal tension_changed(ratio: float)
signal strike_result(kind: String)   ## "perfect" / "good" / "miss" / "round"
signal input_lock_changed(locked: bool)
signal finished(success: bool, reason: String)   ## reason: landed / line_broke

var spec: FishSpec = null
var rng: RandomNumberGenerator = null

var stamina_max: float = 100.0
var stamina: float = 100.0
var tension: float = 0.0
var tension_max: float = 100.0
var round_index: int = 0
var active: bool = false

## 游标位置，归一化 0~1，顶部为 0，顺时针走。
var cursor: float = 0.0

var stats: Dictionary = {"rounds": 0, "perfect": 0, "miss": 0}

var _tune: GameTuning = null
var _input_lock: float = 0.0   ## 击打冷却剩余时间，秒
var _hit_half: float = 0.33
var _perfect_half: float = 0.15
var _speed_base: float = 0.45
var _speed_accel: float = 0.5
var _sway_amp: float = 0.0     ## 命中区左右摆动的幅度，0 = 不摆
var _sway_period: float = 2.2  ## 摆动一个来回要几秒
var _elapsed: float = 0.0      ## 搏斗累计时间，摆动相位靠它推


func _init(fish: FishSpec, tuning: GameTuning, rng_source: RandomNumberGenerator = null) -> void:
	spec = fish
	_tune = tuning
	rng = rng_source if rng_source != null else RandomNumberGenerator.new()
	if rng_source == null:
		rng.randomize()

	stamina_max = maxf(fish.stamina, 1.0)
	stamina = stamina_max
	tension_max = maxf(float(tuning.fight_value("tension_max", 100.0)), 1.0)
	tension = 0.0

	_hit_half = clampf(float(tuning.fight_value("hit_half", 0.33)), 0.02, 0.49)
	_perfect_half = clampf(float(tuning.fight_value("perfect_half", 0.15)), 0.01, _hit_half)
	_speed_base = maxf(float(tuning.fight_value("cursor_speed", 0.45)), 0.02)
	_speed_accel = maxf(float(tuning.fight_value("cursor_accel", 0.5)), 0.0)
	# 爆冲：困难难度起，黄标会左右摆。振幅按圈宽算，0.12 大约是两个标位。
	_sway_amp = clampf(float(tuning.fight_value("hit_sway", 0.0)), 0.0, 0.35)
	_sway_period = maxf(float(tuning.fight_value("sway_period", 2.2)), 0.4)


func start() -> void:
	active = true
	stamina_changed.emit(stamina_ratio())
	tension_changed.emit(tension_ratio())
	# 随机起点：不然每一场都从顶部起手，玩家数好节拍就能闭眼满分
	cursor = rng.randf()
	cursor_changed.emit(cursor)


func stamina_ratio() -> float:
	return clampf(stamina / stamina_max, 0.0, 1.0)


func tension_ratio() -> float:
	return clampf(tension / tension_max, 0.0, 1.0)


## 这一条鱼还要命中几次。体力条的比例决定，UI 用它画小格。
func rounds_needed() -> int:
	return maxi(spec.rounds_needed(), 1)


func rounds_done() -> int:
	return round_index


func current_hit_half() -> float:
	return _hit_half


func current_perfect_half() -> float:
	return _perfect_half


## 当前游标速度（圈/秒）。体力越低转得越快，最后一段最紧。
func current_speed() -> float:
	return _speed_base * (1.0 + (1.0 - stamina_ratio()) * _speed_accel)


func input_locked() -> bool:
	return _input_lock > 0.0


func lock_remaining() -> float:
	return _input_lock


## 玩家点了一下。返回判定结果，方便 UI 直接反馈。
## 冷却窗口内不判定 —— 连续乱点不该刷出连击，也不该白吃一次失手。
func strike() -> String:
	if not active or _input_lock > 0.0:
		return ""

	# 环形距离：到命中区中心的最近距离（中心会随爆冲左右摆）
	var d := absf(cursor - hit_center())
	d = minf(d, 1.0 - d)

	if d <= _perfect_half:
		stats.perfect += 1
		_complete_round(true)
		return "round"
	if d <= _hit_half:
		_complete_round(false)
		return "good"

	stats.miss += 1
	_add_tension(float(_tune.fight_value("miss_tension", 14.0)))
	_lock()
	strike_result.emit("miss")
	return "miss"


## 命中区中心。平常固定在顶部（0），困难难度下鱼会爆冲，整块黄标左右摆。
## 用 fposmod 保证返回值始终在 0~1，UI 画弧和这里判定用的是同一个数。
func hit_center() -> float:
	if _sway_amp <= 0.0:
		return 0.0
	return fposmod(sin(_elapsed * TAU / maxf(_sway_period, 0.1)) * _sway_amp, 1.0)


## 距离下一次爆冲换向还有多久，给 UI 做预兆用。零振幅时恒为 0。
func sway_phase() -> float:
	if _sway_amp <= 0.0:
		return 0.0
	return 0.5 + 0.5 * sin(_elapsed * TAU / maxf(_sway_period, 0.1))


func tick(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	if _input_lock > 0.0:
		_input_lock = maxf(_input_lock - delta, 0.0)
		if _input_lock <= 0.0:
			input_lock_changed.emit(false)

	_elapsed += delta
	cursor = fposmod(cursor + current_speed() * delta, 1.0)
	cursor_changed.emit(cursor)
	_tick_tension(delta)


# ---------- 内部 ----------

func _lock() -> void:
	_input_lock = maxf(float(_tune.fight_value("strike_lock", 0.30)), 0.0)
	if _input_lock > 0.0:
		input_lock_changed.emit(true)


func _complete_round(perfect: bool) -> void:
	round_index += 1
	stats.rounds += 1
	_relieve(float(_tune.fight_value("round_relief", 6.0)))
	if perfect:
		_relieve(float(_tune.fight_value("perfect_relief", 3.0)))
	_lock()
	strike_result.emit("round")
	_damage(spec.damage_ratio)


func _damage(ratio: float) -> void:
	if not active:
		return
	stamina = maxf(stamina - stamina_max * ratio, 0.0)
	stamina_changed.emit(stamina_ratio())
	if stamina <= 0.0:
		_finish(true, "landed")


func _relieve(amount: float) -> void:
	if not active:
		return
	tension = maxf(tension - amount, 0.0)
	tension_changed.emit(tension_ratio())


func _add_tension(amount: float) -> void:
	if not active:
		return
	tension = minf(tension + amount, tension_max)
	tension_changed.emit(tension_ratio())
	if tension >= tension_max:
		_finish(false, "line_broke")


func _tick_tension(delta: float) -> void:
	if not active:
		return
	var rate := float(_tune.fight_value("tension_passive_rate", 7.0)) * spec.tension_rate
	# 体力越低鱼越暴躁，最后一段最紧
	var rage := 1.0 + (1.0 - stamina_ratio()) * float(_tune.fight_value("rage_tension_bonus", 0.6))
	_add_tension(rate * rage * delta)


func _finish(success: bool, reason: String) -> void:
	if not active:
		return
	active = false
	finished.emit(success, reason)
