class_name StoryDirector
extends RefCounted

## 剧情播放的唯一调度点：取哪一段、什么时候收界面、播完接着做什么。
##
## 抽出来的原因：这几件事原来散在 `game_root` 的六个函数里，而且每一件都
## 硬连着另一个全局对象 —— 队列在 `Gallery`、界面开关在 `_hud`/`_score_layer`、
## 语音在 `Audio`。结果是「改剧情」要读整个对局脚本。
##
## 现在这一层只认三样东西：一个 `StoryOverlay`、一份 `id → 剧情` 的字典、
## 一个收放界面的回调。队列用 `pop_story` 注入 —— 想换成别的来源（调试菜单、
## 播放列表）不需要动 `game_root`。

var _overlay: StoryOverlay
var _stories: Dictionary
var _chrome: Callable

## `func() -> String`：取出下一段要播的剧情 id，没有就返回空串。
var pop_story: Callable = Callable()


func _init(overlay: StoryOverlay, stories: Dictionary, chrome: Callable) -> void:
	_overlay = overlay
	_stories = stories
	_chrome = chrome


## 把队列里欠下的剧情一段段播完，最后调 done。队列空就直接 done。
func play_queue(done: Callable) -> void:
	var id := ""
	if pop_story.is_valid():
		id = String(pop_story.call())
	if id.is_empty():
		done.call()
		return
	var story: Dictionary = _stories.get(id, {})
	if story.is_empty() or (story.get("pages", []) as Array).is_empty():
		# 数据写坏了就跳过这一段，不要卡住整条链
		play_queue(done)
		return
	begin(story, play_queue.bind(done))


## 播指定的一段，播完调 done。结局剧情走这里，不进队列 —— 它每局都要放。
func play(id: String, done: Callable) -> void:
	var story: Dictionary = _stories.get(id, {})
	if story.is_empty() or (story.get("pages", []) as Array).is_empty():
		done.call()
		return
	begin(story, done)


## 真正开播：先收界面，再接线，最后 play。
## 收界面这件事只有这一处做，漏一次就会在剧情里看到白饭计数和暂停圈。
func begin(story: Dictionary, done: Callable) -> void:
	_set_chrome(false)
	_overlay.finished.connect(
		func() -> void:
			_set_chrome(true)
			done.call(),
		CONNECT_ONE_SHOT
	)
	_overlay.play(story)


func _set_chrome(on: bool) -> void:
	if _chrome.is_valid():
		_chrome.call(on)
