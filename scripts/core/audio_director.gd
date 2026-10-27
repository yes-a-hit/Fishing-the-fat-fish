extends Node

## 音频总管（autoload 名 Audio）。
##
## 只管两件事：一条循环的 BGM、一条随时可被打断的语音。
## 为什么是 autoload 而不是挂在某张场景上 —— 换场景时 BGM 不该断，
## 而且音量和开关要活在整局游戏里，不该跟着 main.tscn 一起被释放。
##
## 所有资源缺失都静默跳过：少一个 mp3 不该让游戏起不来。

const BGM_PATH := "res://assets/bgm/lake_loop.ogg"
const VOICE_DIR := "res://assets/voice/"
const MUTE_DB := -60.0

var _bgm: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _voice_cache: Dictionary = {}
var _bgm_on: bool = true
var _bgm_volume: float = 0.55
var _voice_on: bool = true
var _voice_volume: float = 0.85


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	_bgm.bus = "Master"
	add_child(_bgm)

	var stream := _load_stream(BGM_PATH)
	if stream is AudioStreamOggVorbis:
		# ogg 自带 loop 开关，比 wav 省 92% 体积，接缝一样听不出来
		(stream as AudioStreamOggVorbis).loop = true
		_bgm.stream = stream
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		# 循环点设在整段首尾，生成 BGM 时已经做过交叉淡化，听不出接缝
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0
		_bgm.stream = wav
	elif stream != null:
		_bgm.stream = stream
	else:
		push_warning("[audio] BGM 缺失：%s" % BGM_PATH)

	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = "Master"
	add_child(_voice)

	apply_settings(GameSettings.load_settings())


## 把一份玩家偏好灌进来。菜单里改完立刻调它，不用等重开场景。
func apply_settings(s: GameSettings) -> void:
	if s == null:
		return
	_bgm_on = s.bgm_on
	_bgm_volume = clampf(s.bgm_volume, 0.0, 1.0)
	_voice_on = s.voice_on
	_voice_volume = clampf(s.voice_volume, 0.0, 1.0)
	_refresh_bgm()


func play_bgm() -> void:
	if _bgm.stream == null:
		return
	if not _bgm.playing:
		_bgm.play()


func stop_bgm() -> void:
	if _bgm.playing:
		_bgm.stop()


func is_bgm_playing() -> bool:
	return _bgm != null and _bgm.playing


## 播一条台词。同一个 key 只读一次盘，之后走缓存。
## 返回是否真的播了 —— 调用方不用关心，但测试要用。
##
## 解锁放在最前面：这一句在游戏里**走到了**就算收集到，
## 玩家把语音关掉玩通全流程，图鉴里也该是满的 —— 进度不该被音量设置偷走。
##
## 解锁完顺手查一次收集奖励：某个人的语音听全了，她的专属结局就该出现在图鉴里。
func play_voice(key: String) -> bool:
	if key.is_empty():
		return false
	Gallery.unlock("voice_" + key)
	for reward in Gallery.check_rewards():
		print("[gallery] 语音收集奖励解锁: " + reward)
	if not _voice_on or _voice_volume <= 0.001:
		return false
	var stream := _voice_stream(key)
	if stream == null:
		return false
	_voice.stream = stream
	_voice.volume_db = _volume_to_db(_voice_volume)
	_voice.play()
	return true


## 图鉴里点重听。不管开关，只要资源在就放 —— 玩家主动点的，就该出声。
func preview_voice(key: String) -> bool:
	if key.is_empty():
		return false
	var stream := _voice_stream(key)
	if stream == null:
		return false
	_voice.stream = stream
	_voice.volume_db = _volume_to_db(maxf(_voice_volume, 0.35))
	_voice.play()
	return true


func has_voice(key: String) -> bool:
	return _voice_stream(key) != null


func _refresh_bgm() -> void:
	if _bgm == null or _bgm.stream == null:
		return
	if not _bgm_on:
		if _bgm.playing:
			_bgm.stop()
		return
	_bgm.volume_db = _volume_to_db(_bgm_volume)
	if not _bgm.playing:
		_bgm.play()


func _voice_stream(key: String) -> AudioStream:
	if _voice_cache.has(key):
		return _voice_cache[key]
	var path := VOICE_DIR + key + ".mp3"
	var stream := _load_stream(path)
	if stream == null:
		push_warning("[audio] 语音缺失：%s" % path)
	_voice_cache[key] = stream
	return stream


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as AudioStream


func _volume_to_db(linear: float) -> float:
	if linear <= 0.001:
		return MUTE_DB
	return clampf(linear_to_db(linear), MUTE_DB, 0.0)
