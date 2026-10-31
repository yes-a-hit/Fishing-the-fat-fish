extends Node

## 启动时把玩家选的语言套上去，顺带加载玩家自己放的翻译。
##
## 为什么要单独一个 autoload：TranslationServer 是全局的，设置必须在**任何场景
## 构建 UI 之前**生效。挂在场景里做就会晚一帧，玩家会看到中文闪一下再变英文。
##
## 注意 autoload 的顺序 —— 这个要排在 Audio 前面。

## 玩家自备翻译放这里。文件名就是语言代码，例如 `user://i18n/ko.csv`。
## 格式跟 data/i18n/strings.csv 一样：`keys,<locale>` 两列，中文原文当键。
## 加载后会**盖住**内置翻译里同名的条目，所以想改哪句就只写那一句。
const USER_I18N_DIR := "user://i18n"


func _ready() -> void:
	_load_user_translations()
	var s := GameSettings.load_settings()
	s.apply_language()
	print("[boot] 语言 = ", s.language, "  实际语种 = ", TranslationServer.get_locale())


## 玩家自备的翻译表。做这件事的理由很简单：一个人翻不完所有语言，
## 但想翻的人不该去改源码重编 —— 扔个 csv 进存档目录就行。
func _load_user_translations() -> void:
	if not DirAccess.dir_exists_absolute(USER_I18N_DIR):
		return
	var dir := DirAccess.open(USER_I18N_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var name := String(f)
		if not name.ends_with(".csv"):
			continue
		var locale := name.get_basename()
		var path := USER_I18N_DIR.path_join(name)
		var tr_obj := _read_csv_translation(path, locale)
		if tr_obj != null:
			TranslationServer.add_translation(tr_obj)
			print("[boot] 已加载自备翻译: ", path)


func _read_csv_translation(path: String, locale: String) -> Translation:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[boot] 打不开 %s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var lines := text.split("\n", false)
	if lines.size() < 2:
		return null

	# 表头里找这个 locale 在第几列。找不到就当第二列 —— 玩家多半只写两列。
	var head := _split_csv_line(lines[0])
	var col := 1
	for i in head.size():
		if head[i].strip_edges().to_lower() == locale.to_lower():
			col = i
			break

	var t := Translation.new()
	t.locale = locale
	var count := 0
	for i in range(1, lines.size()):
		var cells := _split_csv_line(lines[i])
		if cells.size() <= col:
			continue
		var key := cells[0]
		var val := cells[col]
		if key.is_empty() or val.is_empty() or key == val:
			continue
		t.add_message(key, val)
		count += 1
	if count == 0:
		push_warning("[boot] %s 里没有可用的条目" % path)
		return null
	print("[boot] %s: %d 条" % [locale, count])
	return t


## 只处理这几种情况：逗号分隔、双引号包裹、引号内逗号、`""` 转义。
## 刻意不写完整 CSV 解析 —— 玩家的表不会比这更复杂。
func _split_csv_line(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quoted:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					cur += "\""
					i += 1
				else:
					quoted = false
			else:
				cur += ch
		else:
			if ch == "\"":
				quoted = true
			elif ch == ",":
				out.append(cur)
				cur = ""
			elif ch != "\r":
				cur += ch
		i += 1
	out.append(cur)
	return out
