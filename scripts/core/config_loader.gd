class_name ConfigLoader
extends RefCounted

## 所有 data/*.json 的唯一入口。
##
## 规则：
##   1. 读不到文件 → push_error + 返回空，不崩。
##   2. 字段缺失 → 由各模型自己的 from_dict 回填默认值。
##   3. 结构错误（顶层不是对象、fish 不是数组）→ 报错 + 用内置兜底数据。
##
## 除了这个文件和测试，别的地方不应该出现 FileAccess / JSON。

const PATH_FISH := "res://data/fish.json"
const PATH_TUNING := "res://data/tuning.json"
const PATH_ENDINGS := "res://data/endings.json"
const PATH_STORY := "res://data/story.json"

## 连 fish.json 都读不到时的兜底，保证游戏还能跑起来。
const FALLBACK_FISH := [
	{"id": "small", "name": "小肥鱼", "stamina": 100.0, "damage_ratio": 0.25,
	 "tension_rate": 0.85},
	{"id": "mid", "name": "中肥鱼", "stamina": 140.0, "damage_ratio": 0.20,
	 "tension_rate": 1.0},
	{"id": "big", "name": "大肥鱼", "stamina": 190.0, "damage_ratio": 0.20,
	 "tension_rate": 1.0},
]


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[config] 文件不存在: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[config] 无法打开: " + path)
		return {}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[config] JSON 解析失败 %s 第 %d 行: %s" % [
			path, json.get_error_line(), json.get_error_message()
		])
		return {}
	if not (json.data is Dictionary):
		push_error("[config] 顶层必须是对象: " + path)
		return {}
	return json.data as Dictionary


## 读 fish.json，返回 Array[FishSpec]。保证至少有一条鱼。
static func load_fish(path: String = PATH_FISH) -> Array:
	var data := read_json(path)
	var raw: Variant = data.get("fish", null)
	var out: Array = []

	if raw is Array and not (raw as Array).is_empty():
		for i in (raw as Array).size():
			var item: Variant = (raw as Array)[i]
			if not (item is Dictionary):
				push_warning("[config] fish[%d] 不是对象，已跳过" % i)
				continue
			out.append(FishSpec.from_dict(item as Dictionary, "fish_%d" % i))
	else:
		push_error("[config] fish.json 缺少 fish 数组，使用内置兜底数据")
		for item in FALLBACK_FISH:
			out.append(FishSpec.from_dict(item, "fallback"))

	if out.is_empty():
		push_error("[config] 没有任何可用鱼数据，使用内置兜底数据")
		for item in FALLBACK_FISH:
			out.append(FishSpec.from_dict(item, "fallback"))

	# 鱼名走翻译表。规格里的 tagline / blurb 也一并处理。
	for spec in out:
		var s: FishSpec = spec
		s.display_name = TranslationServer.translate(s.display_name)
		s.tagline = TranslationServer.translate(s.tagline)
		s.blurb = TranslationServer.translate(s.blurb)
	return out


static func load_tuning(path: String = PATH_TUNING) -> GameTuning:
	return GameTuning.from_dict(read_json(path))


## 数据层的文案（鱼名、结局标题）也走翻译表。
## 用 TranslationServer.translate() 而不是 tr()，因为这是 static 函数。
## 语种在读完就固化了 —— 切语言后回菜单再进游戏会重新加载，够用。
static func _loc(v: Variant) -> Variant:
	if v is String:
		return TranslationServer.translate(v as String)
	if v is Array:
		var arr: Array = []
		for item in (v as Array):
			arr.append(_loc(item))
		return arr
	return v


static func load_endings(path: String = PATH_ENDINGS) -> Dictionary:
	var data := read_json(path)
	if data.is_empty():
		push_error("[config] endings.json 为空，结算页将没有文案")
		return data
	# 只翻展示字段，不碰 reward / pages 里的资源路径
	for key in data.keys():
		var entry: Variant = data[key]
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		for field in ["title", "subtitle", "lines", "caption"]:
			if d.has(field):
				d[field] = _loc(d[field])
		if d.has("pages") and d["pages"] is Array:
			for page in (d["pages"] as Array):
				if page is Dictionary:
					var pg: Dictionary = page
					for pf in ["caption", "text", "who"]:
						if pg.has(pf):
							pg[pf] = _loc(pg[pf])
	return data


## 一次性把配置读齐。game_root 只调这个。
static func load_all() -> Dictionary:
	return {
		"fish": load_fish(),
		"tuning": load_tuning(),
		"endings": load_endings(),
		"story": read_json(PATH_STORY),
	}
