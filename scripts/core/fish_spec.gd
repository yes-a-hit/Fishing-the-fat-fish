class_name FishSpec
extends RefCounted

## 一条鱼的「静态数据」，全部来自 data/fish.json。
##
## 这里只描述这条鱼是什么：体力、削伤比例、立绘、台词。
## 运行时状态（当前体力、张力、游标位置）一律放在 FightSession 里，
## 不要把两者混在同一个对象上 —— 那是屎山的起点。
##
## 新增一条鱼 = 在 fish.json 的 fish 数组里加一项。距离带会自动重排，
## 不用改任何代码。

var id: String = ""
var display_name: String = "鱼"
var portrait: String = ""
var tint: Color = Color(1, 1, 1)
var stamina: float = 100.0          ## 体力上限，磨空即上鱼
var damage_ratio: float = 0.2       ## 每命中一次削掉的体力比例
var tension_rate: float = 1.0       ## 张力自然上涨乘数
var tagline: String = ""            ## 上鱼瞬间的一句台词
var blurb: String = ""              ## 图鉴/结算里的一句介绍
var is_claude: bool = false         ## 陷阱：不计入收集目标，钓上立刻终止本局
var is_doubao: bool = false         ## 救济：钓上返还白饭，不计收集、不算上鱼次数


static func from_dict(src: Dictionary, fallback_id: String = "fish") -> FishSpec:
	var spec := FishSpec.new()
	spec.id = String(src.get("id", fallback_id))
	spec.display_name = String(src.get("name", spec.id))
	spec.portrait = String(src.get("portrait", ""))
	spec.tint = Color(String(src.get("tint", "#ffffff")))
	spec.stamina = maxf(float(src.get("stamina", 100.0)), 1.0)
	spec.damage_ratio = clampf(float(src.get("damage_ratio", 0.2)), 0.02, 1.0)
	spec.tension_rate = maxf(float(src.get("tension_rate", 1.0)), 0.1)
	spec.tagline = String(src.get("tagline", ""))
	spec.blurb = String(src.get("blurb", ""))
	spec.is_claude = bool(src.get("claude", false))
	spec.is_doubao = bool(src.get("doubao", false))
	return spec


## 打空体力需要命中几次。只用于文档、自测和调参参考。
func rounds_needed() -> int:
	return int(ceil(1.0 / damage_ratio))


func has_portrait() -> bool:
	return portrait != "" and ResourceLoader.exists(portrait)
