extends Node

## 启动时把玩家选的语言套上去。
##
## 为什么要单独一个 autoload：TranslationServer 是全局的，设置必须在**任何场景
## 构建 UI 之前**生效。挂在场景里做就会晚一帧，玩家会看到中文闪一下再变英文。
##
## 注意 autoload 的顺序 —— 这个要排在 Audio 前面。

func _ready() -> void:
	var s := GameSettings.load_settings()
	s.apply_language()
	print("[boot] 语言 = ", s.language, "  实际语种 = ", TranslationServer.get_locale())
