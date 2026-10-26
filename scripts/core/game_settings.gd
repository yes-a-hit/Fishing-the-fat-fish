class_name GameSettings
extends RefCounted

## 玩家偏好，存 user://settings.json。
##
## 与 data/*.json 的区别：那三份是**游戏规则**（随项目分发、不该被玩家改坏），
## 这一份是**玩家自己选的**（难度、以后可能还有音量之类），放 user:// 里。
##
## 读不到、读坏了、值不认识 —— 一律回落到默认值，不弹错误框。
## 玩家改坏一个 json 不该让游戏起不来。

const PATH := "user://settings.json"
const DEFAULT_DIFFICULTY := "normal"

var difficulty: String = DEFAULT_DIFFICULTY

# 声音偏好。音量都是 0~1 的线性值，播放时再转成 dB。
var bgm_on: bool = true
var bgm_volume: float = 0.55
var voice_on: bool = true
var voice_volume: float = 0.85


static func load_settings(path: String = PATH) -> GameSettings:
	var s := GameSettings.new()
	if not FileAccess.file_exists(path):
		return s

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[settings] 无法打开 %s，使用默认值" % path)
		return s
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[settings] JSON 解析失败（第 %d 行），使用默认值" % json.get_error_line())
		return s
	if not (json.data is Dictionary):
		push_warning("[settings] 顶层不是对象，使用默认值")
		return s

	var data: Dictionary = json.data
	var d := String(data.get("difficulty", DEFAULT_DIFFICULTY))
	if GameTuning.DIFFICULTY_KEYS.has(d):
		s.difficulty = d
	else:
		push_warning("[settings] 未知难度 '%s'，回落到 %s" % [d, DEFAULT_DIFFICULTY])

	s.bgm_on = bool(data.get("bgm_on", s.bgm_on))
	s.voice_on = bool(data.get("voice_on", s.voice_on))
	s.bgm_volume = clampf(float(data.get("bgm_volume", s.bgm_volume)), 0.0, 1.0)
	s.voice_volume = clampf(float(data.get("voice_volume", s.voice_volume)), 0.0, 1.0)
	return s


func save(path: String = PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[settings] 无法写入 %s" % path)
		return
	file.store_string(JSON.stringify({
		"_note": "玩家偏好。难度 key 必须是 easy/normal/hard 之一；音量是 0~1 的线性值。",
		"difficulty": difficulty,
		"bgm_on": bgm_on,
		"bgm_volume": bgm_volume,
		"voice_on": voice_on,
		"voice_volume": voice_volume,
	}, "\t"))
	file.close()
