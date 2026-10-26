class_name Gallery
extends RefCounted

## 收集图鉴：记录玩家解锁过哪些内容。
##
## 存 user://gallery.json，结构就一个数组：
##   { "_note": "...", "unlocked": ["feast", "hungry", "escape_big", "voice_catch"] }
##
## key 用前缀分页：
##   结局   feast / full / hungry / claude / claude_fake
##   脱钩   escape_small / escape_big / escape_claude / escape_doubao
##   声音   voice_<assets/voice/<key>.mp3 的文件名，不含扩展名>
##
## 为什么单独存一个文件而不是塞进 settings.json：
##   设置是「玩家偏好」，图鉴是「游戏进度」，一个是改坏了要能回落默认值、
##   一个是丢了就没了。混在一起会让 settings 的容错逻辑把进度也一起清掉。
##
## 所有函数都是 static，因为这东西没有生命周期 —— 每次要用就读一遍文件。

const PATH := "user://gallery.json"
const KEY_UNLOCKED := "unlocked"

## 语音收集奖励：把某人的语音听全了，就解锁一个只属于她的结局。
## 这些结局不在正常流程里触发 —— 它们是「你把她听完了」这件事本身的回报，
## 所以挂在 Gallery 而不是 FishingSession 上。
const VOICE_REWARDS := {
	"doubao_good": ["bite_doubao", "doubao_catch", "doubao_escape"],
	"claude_good": ["bite_claude", "claude"],
}

## 测试用：非空时所有读写都走这里，不碰玩家的真实存档。
## 自测要跑 play_voice()，而 play_voice() 会解锁 —— 不隔离就把玩家进度写脏了。
static var override_path: String = ""


static func _resolve(path: String) -> String:
	if override_path != "":
		return override_path
	return path if path != "" else PATH


## 读已解锁的 key 列表。文件缺失、坏掉、字段类型不对，一律当空。
static func load_unlocked(path: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var list: Variant = (raw as Dictionary).get(KEY_UNLOCKED, [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for item in (list as Array):
		var key := String(item)
		if key != "" and not out.has(key):
			out.append(key)
	return out


static func is_unlocked(key: String, path: String = "") -> bool:
	return load_unlocked(path).has(key)


## 记一笔。返回 true 表示这次是新解锁。
static func unlock(key: String, path: String = "") -> bool:
	if key == "":
		return false
	var resolved := _resolve(path)
	var unlocked := load_unlocked(path)
	if unlocked.has(key):
		return false
	unlocked.append(key)
	_write_json(resolved, {
		"_note": "已解锁的 key。删掉这个文件等于重置图鉴。",
		KEY_UNLOCKED: Array(unlocked),
	})
	return true


static func clear(path: String = "") -> void:
	var resolved := _resolve(path)
	if FileAccess.file_exists(resolved):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(resolved))


## 某一类已解锁几个。prefix 传 "" 就是全部。
static func count_of(prefix: String, path: String = "") -> int:
	var n := 0
	for k in load_unlocked(path):
		if prefix == "" or String(k).begins_with(prefix):
			n += 1
	return n


## 检查语音收集奖励，把满足条件的结局一并解锁。
## 返回这次新解锁的 key，调用方可以据此弹提示。
## 幂等：已经解锁的不会重复返回。
static func check_rewards(path: String = "") -> PackedStringArray:
	var fresh := PackedStringArray()
	for ending_key in VOICE_REWARDS.keys():
		var need: Array = VOICE_REWARDS[ending_key]
		var all_have := true
		for v in need:
			if not is_unlocked("voice_" + String(v), path):
				all_have = false
				break
		if all_have and unlock(String(ending_key), path):
			fresh.append(String(ending_key))
	return fresh


## 某个奖励结局还差哪几条语音。没解锁条件（普通结局）就返回空数组。
static func missing_voice_for(ending_key: String, path: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var need: Variant = VOICE_REWARDS.get(ending_key, null)
	if typeof(need) != TYPE_ARRAY:
		return out
	for v in (need as Array):
		if not is_unlocked("voice_" + String(v), path):
			out.append(String(v))
	return out


## 解锁进度，给菜单按钮上的角标用。
static func progress_text(total: int, path: String = "") -> String:
	var got := load_unlocked(path).size()
	return "%d / %d" % [mini(got, total), total]


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[gallery] 写不了 " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
