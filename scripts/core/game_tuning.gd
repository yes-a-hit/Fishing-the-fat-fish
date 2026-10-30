class_name GameTuning
extends RefCounted

## 一局的全局规则数值，来自 data/tuning.json。
##
## 设计原则：JSON 少写一个 key 不能让游戏崩。每个字段都有默认值，
## 缺失时用默认值 + 一条 warning，而不是抛异常。
## 想调手感，只改 data/tuning.json，不用碰代码。
##
## 距离带是**可重叠**的：抛到某一点，所有覆盖该点的鱼都是候选，
## 按 weight 加权随机抽一条。这样「抛偏一点」不会直接空竿，
## 而是钓到隔壁那条 —— 容错靠重叠，难度靠收窄。

## 兜底距离带。tuning.json 完全读不到时用。
const DEFAULT_ZONES: Array = [
	{"id": "z_small", "fish": "small", "from": 0.0, "to": 50.0, "weight": 3},
	{"id": "z_mid", "fish": "mid", "from": 30.0, "to": 80.0, "weight": 2},
	{"id": "z_big", "fish": "big", "from": 60.0, "to": 100.0, "weight": 2},
]

## 自动分带时相邻两带的重叠宽度（百分比）。故意留重叠 ——
## 无缝无重叠的话，两个区域的分界线上永远只会命中前一条鱼。
const AUTO_OVERLAP := 8.0

const DIFFICULTY_KEYS := ["easy", "normal", "hard"]

## 重叠区里，贴到带边缘的候选还剩多少权重。0.2 = 边缘只有中心的五分之一。
## 有这个下限而不是 0，是为了「重叠」真的有意义 —— 否则重叠区就变成硬边界了。
const BIAS_FLOOR := 0.2

var bait_count: int = 5                 ## 白饭碗数，也就是总抛竿次数
var full_catch_threshold: int = 3       ## 上鱼总次数达到这个值就判「吃饱饱」；重复钓也算次数
var fake_claude_chance: float = 0.5     ## 远洋尽头那条 trap 有这么大比例是套头套的鲸鱼娘，不是真陷阱
var doubao_refund: int = 2              ## 钓上豆包返还几碗饭（含抛出去的那碗）。总量封在 bait_count。
var doubao_escape_chance: float = 0.35  ## 豆包咬一口就跑的概率。它 damage_ratio = 1.0，
                                        ## 一轮就上鱼，张力永远没机会爆表 —— 不在这里掷骰，
                                        ## 脱钩画面就是死代码。
## 雪中送炭：饵快见底又还没集齐时，豆包更愿意冒头
var doubao_mercy_bait: int = 2          ## 剩这么多饵以内开始加成
var doubao_mercy_gain: float = 2.0      ## 加成倍数

## 豆包不是靠距离带权重抽的，而是一条正态曲线压在抛竿条上。
## 峰值在近岸偏中段，往两侧衰减 —— 玩家能感觉到「中间比较热闹」，
## 但没法靠记某个刻度刷它。
var doubao_peak_center: float = 28.0    ## 峰值落在 0~100 的哪个位置
var doubao_peak_chance: float = 0.40    ## 峰值处的概率，按难度覆盖
var doubao_peak_sigma: float = 18.0     ## 标准差，越小越尖
## 动态难度：钓上来的鱼越多，AI 越上劲 —— 游标转得更快，黄标摆得更凶
var dda_speed_gain: float = 0.45        ## 集齐时游标速度额外 +45%
var dda_sway_gain: float = 1.6          ## 集齐时摆动幅度额外 +160%
var dda_from_difficulty: bool = true    ## 简单难度不启用，普通以上才上劲
var charge_full_seconds: float = 1.6    ## 蓄力条转完一圈（0→100）需要几秒；走完从 0 继续，不结束
var cast_jitter: float = 1.5            ## 落点随机误差 ±
## 水面上的模糊鱼影：落点压在影子里，那条鱼已经累了，打起来轻一些。
## 影子每局随机生成，玩家只能看见一团模糊的黑影 —— 看见影子就知道这一竿值得赌。
var shadow_count: int = 2               ## 每局生成几个影子；0 = 关掉这个机制
var shadow_width: float = 13.0          ## 影子在距离条上占多宽（0~100 的刻度）
var shadow_weaken: float = 0.62         ## 落进影子时，鱼的体力乘这个系数
var bite_delay_min: float = 0.8         ## 抛竿后最短等待
var bite_delay_max: float = 1.7         ## 抛竿后最长等待
var empty_wait: float = 1.1             ## 空竿时的干等时长
var resolve_hold: float = 2.2           ## 失败提示停留时长（可点击跳过）
var landing_timeout: float = 3.2        ## 上鱼动画的兜底时长；UI 正常会提前调 landing_done()
var zones: Array = []                   ## 可重叠距离带；空数组 = 自动分带
var zones_explicit: bool = false        ## tuning.json 里是否显式写了 zones
var fight: Dictionary = {}              ## 原样交给 FightSession，见 tuning.json
var difficulty: String = "normal"       ## 当前难度 key
var difficulties: Dictionary = {}       ## 原样的 difficulties 段，menu 场景拿它列选项


static func from_dict(src: Dictionary) -> GameTuning:
	var t := GameTuning.new()
	t.bait_count = maxi(int(src.get("bait_count", t.bait_count)), 1)
	t.full_catch_threshold = maxi(int(src.get("full_catch_threshold", t.full_catch_threshold)), 1)
	t.fake_claude_chance = clampf(float(src.get("fake_claude_chance", t.fake_claude_chance)), 0.0, 1.0)
	t.doubao_refund = maxi(int(src.get("doubao_refund", t.doubao_refund)), 1)
	t.doubao_escape_chance = clampf(float(src.get("doubao_escape_chance", t.doubao_escape_chance)), 0.0, 1.0)
	t.doubao_mercy_bait = maxi(int(src.get("doubao_mercy_bait", t.doubao_mercy_bait)), 0)
	t.doubao_mercy_gain = maxf(float(src.get("doubao_mercy_gain", t.doubao_mercy_gain)), 1.0)
	t.doubao_peak_center = clampf(float(src.get("doubao_peak_center", t.doubao_peak_center)), 0.0, 100.0)
	t.doubao_peak_chance = clampf(float(src.get("doubao_peak_chance", t.doubao_peak_chance)), 0.0, 1.0)
	t.doubao_peak_sigma = maxf(float(src.get("doubao_peak_sigma", t.doubao_peak_sigma)), 1.0)
	t.dda_speed_gain = maxf(float(src.get("dda_speed_gain", t.dda_speed_gain)), 0.0)
	t.dda_sway_gain = maxf(float(src.get("dda_sway_gain", t.dda_sway_gain)), 0.0)
	t.dda_from_difficulty = bool(src.get("dda_from_difficulty", t.dda_from_difficulty))
	t.charge_full_seconds = maxf(float(src.get("charge_full_seconds", t.charge_full_seconds)), 0.1)
	t.cast_jitter = maxf(float(src.get("cast_jitter", t.cast_jitter)), 0.0)
	t.shadow_count = clampi(int(src.get("shadow_count", t.shadow_count)), 0, 6)
	t.shadow_width = clampf(float(src.get("shadow_width", t.shadow_width)), 3.0, 40.0)
	t.shadow_weaken = clampf(float(src.get("shadow_weaken", t.shadow_weaken)), 0.2, 1.0)
	t.bite_delay_min = maxf(float(src.get("bite_delay_min", t.bite_delay_min)), 0.05)
	t.bite_delay_max = maxf(float(src.get("bite_delay_max", t.bite_delay_max)), t.bite_delay_min)
	t.empty_wait = maxf(float(src.get("empty_wait", t.empty_wait)), 0.05)
	t.resolve_hold = maxf(float(src.get("resolve_hold", t.resolve_hold)), 0.2)
	t.landing_timeout = maxf(float(src.get("landing_timeout", t.landing_timeout)), 0.5)

	var raw_zones: Variant = src.get("zones", null)
	if raw_zones is Array and not (raw_zones as Array).is_empty():
		t.zones = _sanitize_zones(raw_zones as Array)
		t.zones_explicit = not t.zones.is_empty()

	var raw_fight: Variant = src.get("fight", null)
	t.fight = (raw_fight as Dictionary).duplicate(true) if raw_fight is Dictionary else {}

	var raw_diff: Variant = src.get("difficulties", null)
	t.difficulties = (raw_diff as Dictionary).duplicate(true) if raw_diff is Dictionary else {}
	return t


## 套用一档难度。只覆盖它显式写了的键，其余继承顶层。
## 未知 key 不会崩 —— 落回 normal。
func apply_difficulty(name: String) -> void:
	var key := name if difficulties.has(name) else "normal"
	if not difficulties.has(key):
		difficulty = "normal"
		return
	var d: Dictionary = difficulties[key] as Dictionary

	bait_count = maxi(int(d.get("bait_count", bait_count)), 1)
	full_catch_threshold = maxi(int(d.get("full_catch_threshold", full_catch_threshold)), 1)
	fake_claude_chance = clampf(float(d.get("fake_claude_chance", fake_claude_chance)), 0.0, 1.0)
	doubao_refund = maxi(int(d.get("doubao_refund", doubao_refund)), 1)
	doubao_escape_chance = clampf(float(d.get("doubao_escape_chance", doubao_escape_chance)), 0.0, 1.0)
	# 简单难度整档关掉动态难度，普通以上才上劲
	if d.has("dda_from_difficulty"):
		dda_from_difficulty = bool(d["dda_from_difficulty"])
	if d.has("doubao_mercy_gain"):
		doubao_mercy_gain = maxf(float(d["doubao_mercy_gain"]), 1.0)
	# 豆包峰值：简单 30% / 普通 40% / 困难 50%。越难越常撞见，因为越难越缺饭。
	doubao_peak_chance = clampf(float(d.get("doubao_peak_chance", doubao_peak_chance)), 0.0, 1.0)
	charge_full_seconds = maxf(float(d.get("charge_full_seconds", charge_full_seconds)), 0.1)
	cast_jitter = maxf(float(d.get("cast_jitter", cast_jitter)), 0.0)

	var dz: Variant = d.get("zones", null)
	if dz is Array and not (dz as Array).is_empty():
		zones = _sanitize_zones(dz as Array)
		zones_explicit = not zones.is_empty()

	# 简单难度关掉鱼影，故事模式不该考验手气
	if d.has("shadow_count"):
		shadow_count = clampi(int(d["shadow_count"]), 0, 6)
	if d.has("shadow_weaken"):
		shadow_weaken = clampf(float(d["shadow_weaken"]), 0.2, 1.0)

	var df: Variant = d.get("fight", null)
	if df is Dictionary:
		for k in (df as Dictionary).keys():
			fight[k] = (df as Dictionary)[k]

	difficulty = key


## menu 场景列难度按钮用。返回 [{key,label,blurb}]，顺序按 DIFFICULTY_KEYS。
func difficulty_options() -> Array:
	var out: Array = []
	for key in DIFFICULTY_KEYS:
		if not difficulties.has(key):
			continue
		var d: Dictionary = difficulties[key] as Dictionary
		out.append({
			"key": key,
			"label": String(d.get("label", key)),
			"blurb": String(d.get("blurb", "")),
		})
	return out


static func _sanitize_zones(raw: Array) -> Array:
	var out: Array = []
	for i in raw.size():
		var z: Variant = raw[i]
		if not (z is Dictionary):
			push_warning("[tuning] zones[%d] 不是对象，已跳过" % i)
			continue
		var from := clampf(float(z.get("from", 0.0)), 0.0, 100.0)
		var to := clampf(float(z.get("to", 0.0)), 0.0, 100.0)
		if to <= from:
			push_warning("[tuning] zones[%d] 的 to <= from，已跳过" % i)
			continue
		out.append({
			"id": String(z.get("id", "zone_%d" % i)),
			"fish": String(z.get("fish", "")),
			"from": from,
			"to": to,
			"weight": maxf(float(z.get("weight", 1.0)), 0.0),
		})
	if out.is_empty():
		push_warning("[tuning] zones 全部无效，回退到内置带")
		return DEFAULT_ZONES.duplicate(true)
	return out


## 按当前鱼列表解析出真正生效的距离带。
##
## 扩展接口的核心：**加一条鱼不需要配 zones**。
##   - 写了完整 zones → 完全按写的走
##   - 没写 / 没覆盖全部鱼 → 按体力自动分带
func resolved_zones(fish_list: Array) -> Array:
	if zones_explicit and _covers_all(zones, fish_list):
		return zones
	if zones_explicit:
		push_warning("[tuning] zones 没有覆盖全部鱼，改用自动分带")
	return auto_zones(fish_list)


## 自动分带：体力最低的在近岸，最高的在远洋。相邻带留 AUTO_OVERLAP 的重叠。
func auto_zones(fish_list: Array) -> Array:
	# 豆包不进自动分带：它是一份偶遇的救济，不该按体力排序占掉最前面的一整条带。
	# 想让它出现就在 tuning.json 的 zones 里显式给它一条窄带。
	var ordered: Array = []
	for f in fish_list:
		if not f.is_doubao:
			ordered.append(f)
	ordered.sort_custom(func(a, b): return a.stamina < b.stamina)

	var n := ordered.size()
	if n <= 0:
		return []
	if n == 1:
		return [{
			"id": "z_0", "fish": ordered[0].id,
			"from": 0.0, "to": 100.0, "weight": 1.0,
		}]

	# 每带推进 step，带本身宽 band，band > step 的那部分就是与下一带的重叠。
	var step := 100.0 / float(n)
	var half := AUTO_OVERLAP * 0.5
	var out: Array = []
	for i in n:
		var center := step * (float(i) + 0.5)
		out.append({
			"id": "z_%d" % i,
			"fish": ordered[i].id,
			"from": clampf(center - step * 0.5 - half, 0.0, 100.0),
			"to": clampf(center + step * 0.5 + half, 0.0, 100.0),
			"weight": 1.0,
		})
	# 两端收口到 0 / 100，保证全覆盖
	out[0]["from"] = 0.0
	out[n - 1]["to"] = 100.0
	return out


static func _covers_all(zone_list: Array, fish_list: Array) -> bool:
	for f in fish_list:
		var found := false
		for z in zone_list:
			if String(z["fish"]) == f.id:
				found = true
				break
		if not found:
			return false
	return true


## 落点（0~100）上所有候选鱼。返回 [{fish, weight, bias, score}]，按 zones 顺序。
##
## bias 是「这条带在自己的地盘里有多核心」：落点越靠近带中心越接近 1，
## 贴到带边缘就掉到 BIAS_FLOOR。重叠区里靠中心的那条鱼明显更容易被抽中 ——
## 不然远洋末端抛一竿还可能抽到小肥鱼，手感像在抽奖。
static func candidates_at(zone_list: Array, point: float) -> Array:
	var out: Array = []
	var p := clampf(point, 0.0, 100.0)
	for z in zone_list:
		var lo := float(z["from"])
		var hi := float(z["to"])
		if p < lo or p > hi:
			continue
		var w := maxf(float(z.get("weight", 1.0)), 0.0)
		var bias := 1.0
		var span := hi - lo
		if span > 0.001:
			var mid := (lo + hi) * 0.5
			var ratio := clampf(absf(p - mid) / (span * 0.5), 0.0, 1.0)
			bias = lerpf(1.0, BIAS_FLOOR, ratio)
		out.append({
			"fish": String(z["fish"]),
			"weight": w,
			"bias": bias,
			"score": w * bias,
		})
	# 正好 100 时，只覆盖到 100 的带已经在上面命中了；这里不做兜底，
	# 因为要求配置全覆盖，真漏了就是要暴露出来。
	return out


## 按 weight × bias 加权随机抽一条。point 上没有候选时返回 ""。
static func pick_fish_at(zone_list: Array, point: float, rng: RandomNumberGenerator) -> String:
	var cands := candidates_at(zone_list, point)
	var total := 0.0
	for c in cands:
		total += float(c["score"])
	if total <= 0.0:
		return "" if cands.is_empty() else String(cands[0]["fish"])
	var roll := rng.randf() * total
	for c in cands:
		roll -= float(c["score"])
		if roll <= 0.0:
			return String(c["fish"])
	return String(cands[cands.size() - 1]["fish"])


## 兼容旧调用：返回该点上第一条鱼的 id。新代码用 pick_fish_at()。
static func fish_id_in(zone_list: Array, point: float) -> String:
	var cands := candidates_at(zone_list, point)
	return "" if cands.is_empty() else String(cands[0]["fish"])


## 某条鱼的主带（第一条），找不到返回 {}。
static func zone_of(zone_list: Array, fish_id: String) -> Dictionary:
	for z in zone_list:
		if String(z["fish"]) == fish_id:
			return z
	return {}


## 落点对应的水域描述。纯位置语言，不点名任何鱼 ——
## 抛竿条只靠这块牌子给「大概在哪」，剩下的留给玩家自己猜。
static func water_label(point: float) -> String:
	var p := clampf(point, 0.0, 100.0)
	if p < 33.0:
		return "近岸水域"
	if p < 66.0:
		return "中段水域"
	return "远洋水域"


## 战斗配置的浅取值，带默认值。FightSession 用同一套 key。
func fight_value(key: String, fallback: Variant) -> Variant:
	return fight.get(key, fallback)


## 动态难度倍率。越接近集齐，返的倍率越大；简单难度整档关掉。
func dda_scale(caught: int, total: int) -> Dictionary:
	if not dda_from_difficulty or total <= 0:
		return {"speed": 1.0, "sway": 1.0}
	var progress := clampf(float(caught) / float(total), 0.0, 1.0)
	return {
		"speed": 1.0 + progress * dda_speed_gain,
		"sway": 1.0 + progress * dda_sway_gain,
	}


## 豆包的出现倍率。剩下的饵越少、离集齐越远，它越愿意冒头。
## 已经集齐就直接归零 —— 那时候玩家要的是结局，不是救济。
func doubao_weight_scale(bait_left: int, caught: int, total: int) -> float:
	if total > 0 and caught >= total:
		return 0.0
	if bait_left > doubao_mercy_bait:
		return 1.0
	return maxf(doubao_mercy_gain, 1.0)


## 落在 point 上撞见豆包的概率。正态分布，峰值 doubao_peak_chance 在
## doubao_peak_center，往两侧按 doubao_peak_sigma 衰减。
## 返回的是「裸概率」，还没乘饥荒加成 —— 那一层由调用方自己决定。
func doubao_chance_at(point: float) -> float:
	if doubao_peak_chance <= 0.0:
		return 0.0
	var d := point - doubao_peak_center
	return doubao_peak_chance * exp(-(d * d) / (2.0 * doubao_peak_sigma * doubao_peak_sigma))

