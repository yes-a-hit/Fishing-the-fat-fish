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
const KEY_CLAUDE_STAGE := "claude_stage"
const KEY_DOUBAO_SEEN := "doubao_seen"
const KEY_STORY_QUEUE := "story_queue"
const KEY_STORY_DONE := "story_done"

## 语音收集奖励：把某人的语音听全了，就解锁一个只属于她的结局。
## 这些结局不在正常流程里触发 —— 它们是「你把她听完了」这件事本身的回报，
## 所以挂在 Gallery 而不是 FishingSession 上。
##
## claude_good（私奔）不在这张表里：它走剧情三段线，见下面的 CLAUDE_STAGES。
const VOICE_REWARDS := {
	# 咬钩不发声，所以豆包只剩上鱼与脱钩这两条能收
	"doubao_good": ["doubao_catch", "doubao_escape"],
}

## claude 三段线：按「上过几次真 claude」推进，跨局持久化。
##   第 1 次  封号        claude         —— 她只递通知单，不解释
##   第 2 次  封完就哭    claude_sad     —— 还是照封，但自己先红了眼
##   第 3 次  私奔        claude_good    —— 她决定不递了
##   第 4 次起 不再封号   —— 已经私奔过了，她只是在远洋等你
##
## 为什么按次数而不是按「有没有触发过假 claude」：
## 假的那个是随机的，把它设成前置会让玩家的进度看起来随机丢失。
const CLAUDE_STAGES := ["claude", "claude_sad", "claude_good"]

## 集齐全套（所有结局 + 所有语音）之后解锁的终极结局。
const GRAND_ENDING := "true_end"

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
	_save(resolved, unlocked)
	return true


## 所有落盘都走这里。之前 unlock() 自己拼一份 json，只写 unlocked，
## 把 claude_stage 抹掉了 —— 结果真 claude 永远停在第 1 段，
## claude_sad 和 claude_good 再也见不到。
##
## 现在改成「读出来 → 只改自己那几个键 → 写回去」，
## 谁往里加新字段都不会被隔壁的写入顺手抹掉。
static func _save_patch(resolved: String, patch: Dictionary) -> void:
	var raw: Variant = _read_json(resolved)
	var data: Dictionary = {}
	if typeof(raw) == TYPE_DICTIONARY:
		data = (raw as Dictionary).duplicate(true)
	if not data.has("_note"):
		data["_note"] = "已解锁的 key、claude 相遇次数、待播剧情。删掉这个文件等于重置进度。"
	for k in patch.keys():
		data[k] = patch[k]
	_write_json(resolved, data)


static func _save(resolved: String, unlocked: PackedStringArray) -> void:
	_save_patch(resolved, {
		KEY_UNLOCKED: Array(unlocked),
		KEY_CLAUDE_STAGE: claude_stage(resolved),
	})


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


## 检查收集奖励，把满足条件的结局一并解锁。
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
	if _grand_ready(path) and unlock(GRAND_ENDING, path):
		fresh.append(GRAND_ENDING)
	return fresh


## 齐人之福的门槛：这八条一条不落。豆包那条是硬要求 ——
## 这个结局的画面是四个人挤在一张床上，豆包缺席说不过去。
## 刻意写成显式清单，不用「数量够不够」判：数数会把新增结局悄悄漏掉，
## 也不会因为日后加一条新结局就把门槛意外抬高。
const GRAND_REQUIRED := [
	"feast",        # 三条鱼齐
	"full",         # 吃饱饱
	"hungry",       # 没吃饱
	"doubao_good",  # 白饭来咯
	"claude_good",  # 私奔
	"claude",       # 第一次封号
	"claude_sad",   # 第二次封完就哭
	"claude_fake",  # 掀开头套
]


## 终极结局的门槛：上面那张清单全解锁。
## 早期版本还要求「所有语音都听过」，但那份清单是扫 res://assets/voice 目录得来的 ——
## 导出成 pck 之后 DirAccess 拿不到目录内容，永远返回空，真结局永远不解锁。
## 语音不是通关条件，听不听是玩家自己的事。
static func _grand_ready(path: String = "") -> bool:
	var unlocked := load_unlocked(path)
	for k in GRAND_REQUIRED:
		if not unlocked.has(String(k)):
			return false
	return true


## 外部唯一该调的真结局入口。门槛齐了才解锁，返回 true 表示这次刚解锁。
static func try_grand(path: String = "") -> bool:
	if not _grand_ready(path):
		return false
	return unlock(GRAND_ENDING, path)


static func _all_voice_ready(path: String = "") -> bool:
	# 语音清单以 assets/voice/ 为准，玩家只要把能听到的都听过一遍
	var files := DirAccess.get_files_at("res://assets/voice")
	if files == null or files.is_empty():
		return false
	var unlocked := load_unlocked(path)
	for f in files:
		var name := String(f)
		if not name.ends_with(".mp3"):
			continue
		if not unlocked.has("voice_" + name.get_basename()):
			return false
	return true


## 豆包被钓上来过几次。第二次会触发一段剧情，所以得记着。
static func doubao_seen(path: String = "") -> int:
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	return maxi(int((raw as Dictionary).get(KEY_DOUBAO_SEEN, 0)), 0)


static func bump_doubao_seen(path: String = "") -> int:
	var next := doubao_seen(path) + 1
	_save_patch(_resolve(path), { KEY_DOUBAO_SEEN: next })
	return next


## 待播剧情队列。一局里可能同时欠下好几段，都排进来，一段都不许漏。
static func pending_stories(path: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var list: Variant = (raw as Dictionary).get(KEY_STORY_QUEUE, [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for item in (list as Array):
		var key := String(item)
		if key != "" and not out.has(key):
			out.append(key)
	return out


## 排队。已经在队里或已经播过的不重复排 —— 同一段剧情只播一次。
static func queue_story(id: String, path: String = "") -> bool:
	if id == "":
		return false
	var done := PackedStringArray()
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) == TYPE_DICTIONARY:
		var list: Variant = (raw as Dictionary).get(KEY_STORY_DONE, [])
		if typeof(list) == TYPE_ARRAY:
			for item in (list as Array):
				done.append(String(item))
	if done.has(id) or pending_stories(path).has(id):
		return false
	var queue := pending_stories(path)
	queue.append(id)
	_save_patch(_resolve(path), { KEY_STORY_QUEUE: Array(queue) })
	return true


## 取下一段。取出来的同时记进「已播」，不会再排第二次。
static func pop_story(path: String = "") -> String:
	var queue := pending_stories(path)
	if queue.is_empty():
		return ""
	var id := queue[0]
	var rest: Array = []
	for i in range(1, queue.size()):
		rest.append(queue[i])
	var done := PackedStringArray()
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) == TYPE_DICTIONARY:
		var list: Variant = (raw as Dictionary).get(KEY_STORY_DONE, [])
		if typeof(list) == TYPE_ARRAY:
			for item in (list as Array):
				done.append(String(item))
	done.append(id)
	_save_patch(_resolve(path), {
		KEY_STORY_QUEUE: rest,
		KEY_STORY_DONE: Array(done),
	})
	return id


static func story_done(id: String, path: String = "") -> bool:
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var list: Variant = (raw as Dictionary).get(KEY_STORY_DONE, [])
	if typeof(list) != TYPE_ARRAY:
		return false
	return (list as Array).has(id)


## 上过几次真 claude。跨局持久化，用来推三段线。
static func claude_stage(path: String = "") -> int:
	var raw: Variant = _read_json(_resolve(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	var v: Variant = (raw as Dictionary).get(KEY_CLAUDE_STAGE, 0)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	return maxi(int(v), 0)


## 记一次相遇，返回推进后应该走哪个结局；返回空串表示她已经不封号了。
static func bump_claude_stage(path: String = "") -> String:
	var resolved := _resolve(path)
	var stage := claude_stage(path)
	# 先把新阶段写进去，再读回来时 unlocked 不会丢
	_write_json(resolved, {
		"_note": "已解锁的 key 与 claude 相遇次数。删掉这个文件等于重置图鉴。",
		KEY_UNLOCKED: Array(load_unlocked(path)),
		KEY_CLAUDE_STAGE: stage + 1,
	})
	if stage < CLAUDE_STAGES.size():
		return String(CLAUDE_STAGES[stage])
	return ""


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
