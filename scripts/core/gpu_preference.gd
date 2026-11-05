class_name GpuPreference
extends RefCounted

## Windows 允许按程序指定用哪块显卡，落点在注册表：
##   HKCU\Software\Microsoft\DirectX\UserGpuPreferences
##   值名 = exe 全路径，值 = "GpuPreference=1;"（1 省电 / 集显，2 高性能 / 独显）
##
## 这个游戏一屏就几张贴图和一个圆环，集显足够，没必要把独显从待机里叫醒
## （笔记本上表现为风扇突然起转、掉电快）。所以导出后第一次启动写一条省电偏好，
## 之后系统会在「图形设置」里记住它，玩家也能自己改回去。
##
## 只在导出版生效：编辑器里写会把 godot.exe 一起设成省电，开发时反而更卡。

const REG_PATH := "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences"
const SENTINEL := "user://gpu_pref_v1.txt"
const POWER_SAVING := "GpuPreference=1;"


## 写一次就够了，用 user:// 里的标记文件记住「已经写过」。
static func prefer_integrated() -> void:
	if not OS.has_feature("windows"):
		return
	if OS.has_feature("editor"):
		return
	if FileAccess.file_exists(SENTINEL):
		return

	var exe := OS.get_executable_path()
	if exe.is_empty():
		return

	var args := [
		"add", REG_PATH,
		"/v", exe,
		"/t", "REG_SZ",
		"/d", POWER_SAVING,
		"/f",
	]
	# 不阻塞启动：reg.exe 起来写完就退，失败也只是继续用系统默认
	var pid := OS.create_process("reg.exe", args)
	if pid <= 0:
		return

	var f := FileAccess.open(SENTINEL, FileAccess.WRITE)
	if f != null:
		f.store_string("GpuPreference=1 for %s\n" % exe)


## 只读查询，给自测用：返回注册表里这台机器上该 exe 的值（没有就空串）。
static func read_preference() -> String:
	if not OS.has_feature("windows"):
		return ""
	var exe := OS.get_executable_path()
	var out: Array = []
	var code := OS.execute("reg", ["query", REG_PATH, "/v", exe], out, true)
	if code != 0 or out.is_empty():
		return ""
	var text := String(out[0])
	var idx := text.find("GpuPreference=")
	if idx < 0:
		return ""
	return text.substr(idx, text.find("\n", idx) - idx).strip_edges()
