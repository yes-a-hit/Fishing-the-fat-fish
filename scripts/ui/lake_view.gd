class_name LakeView
extends Control

## 全屏湖面背景。全部用 _draw() 画，不依赖任何图片素材。
##
## 它不参与任何规则判断，只负责「看起来像在钓鱼」：
## 天空渐变、远山、水面波纹、浮标、鱼线。
##
## 搏斗期间由外部调 set_fight_intensity() 推高紧张度：
## 浮标开始剧烈抖动、往下沉、溅水花，水下浮现鱼的影子，鱼线绷直。
## 这些全是表现，不影响任何判定。

## 水面在这条水平线上开始（占画面高度的比例）。
const WATER_RATIO := 0.46

var _time: float = 0.0
var _bobber_point: float = 50.0
var _bobber_visible: bool = false
var _biting: bool = false
var _bite_flash: float = 0.0
var _fight_intensity: float = 0.0
var _fight_target: float = 0.0
var _fish_shadow_visible: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_time += delta
	if _bite_flash > 0.0:
		_bite_flash = maxf(_bite_flash - delta, 0.0)
	# 搏斗强度平滑过渡，避免浮标突然开始抽风
	_fight_intensity = move_toward(_fight_intensity, _fight_target, delta * 3.2)
	queue_redraw()


## 设置浮标落点（0~100）。抛竿后调用。
func set_bobber(point: float, visible: bool = true) -> void:
	_bobber_point = clampf(point, 0.0, 100.0)
	_bobber_visible = visible


func set_bite(biting: bool) -> void:
	if biting and not _biting:
		_bite_flash = 0.55
	_biting = biting


## 0 = 平静，1 = 鱼在水下拼命挣扎。搏斗开始调到 1，结束调回 0。
func set_fight_intensity(value: float) -> void:
	_fight_target = clampf(value, 0.0, 1.0)


## 是否在水下画鱼的影子。
func set_fish_shadow(visible: bool) -> void:
	_fish_shadow_visible = visible


## 浮标当前的屏幕坐标，上鱼动画要从这里把鱼「拉」出来。
func bobber_screen_pos() -> Vector2:
	return _bobber_pos(size.x, size.y)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	_draw_sky(w, h)
	_draw_sun(w, h)
	_draw_hills(w, h)
	_draw_water(w, h)
	_draw_waves(w, h)
	_draw_fish_shadow(w, h)
	_draw_rod(w, h)
	_draw_bobber(w, h)


func _draw_sky(w: float, h: float) -> void:
	var horizon := h * WATER_RATIO
	var bands := 24
	for i in bands:
		var t := float(i) / float(bands - 1)
		var y := horizon * float(i) / float(bands)
		draw_rect(Rect2(0, y, w, horizon / float(bands) + 1.0), Palette.SKY_TOP.lerp(Palette.SKY_LOW, t))


func _draw_sun(w: float, h: float) -> void:
	var c := Vector2(w * 0.78, h * 0.16)
	for i in 5:
		var r := 62.0 + float(i) * 26.0
		draw_circle(c, r, Color(1.0, 0.98, 0.90, 0.055))
	draw_circle(c, 46.0, Palette.SUN)


func _draw_hills(w: float, h: float) -> void:
	var horizon := h * WATER_RATIO
	var far := PackedVector2Array([
		Vector2(0, horizon),
		Vector2(0, horizon - h * 0.075),
		Vector2(w * 0.10, horizon - h * 0.135),
		Vector2(w * 0.22, horizon - h * 0.065),
		Vector2(w * 0.35, horizon - h * 0.120),
		Vector2(w * 0.48, horizon - h * 0.050),
		Vector2(w * 0.62, horizon - h * 0.105),
		Vector2(w * 0.78, horizon - h * 0.045),
		Vector2(w * 0.90, horizon - h * 0.090),
		Vector2(w, horizon - h * 0.030),
		Vector2(w, horizon),
	])
	draw_colored_polygon(far, Palette.HILL_FAR)

	var near := PackedVector2Array([
		Vector2(0, horizon),
		Vector2(0, horizon - h * 0.040),
		Vector2(w * 0.16, horizon - h * 0.078),
		Vector2(w * 0.30, horizon - h * 0.028),
		Vector2(w * 0.46, horizon - h * 0.062),
		Vector2(w * 0.60, horizon - h * 0.020),
		Vector2(w * 0.76, horizon - h * 0.055),
		Vector2(w * 0.88, horizon - h * 0.018),
		Vector2(w, horizon - h * 0.048),
		Vector2(w, horizon),
	])
	draw_colored_polygon(near, Palette.HILL_NEAR)


func _draw_water(w: float, h: float) -> void:
	var horizon := h * WATER_RATIO
	var bands := 26
	var depth := h - horizon
	for i in bands:
		var t := float(i) / float(bands - 1)
		var y := horizon + depth * float(i) / float(bands)
		draw_rect(Rect2(0, y, w, depth / float(bands) + 1.0), Palette.WATER_SHALLOW.lerp(Palette.WATER_DEEP, t))

	# 地平线上的一条亮边，把天和水切开
	draw_rect(Rect2(0, horizon - 1.5, w, 3.0), Color(1, 1, 1, 0.35))


func _draw_waves(w: float, h: float) -> void:
	var horizon := h * WATER_RATIO
	var depth := h - horizon
	# 搏斗时水面被搅动，波纹幅度跟着加大
	var churn := 1.0 + _fight_intensity * 1.8
	for i in 7:
		var t := float(i) / 6.0
		var base_y := horizon + depth * (0.10 + 0.80 * t)
		var amp := (1.6 + t * 3.4) * churn
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w:
			var y := base_y + sin(x * 0.011 + _time * (0.7 + t * 0.5) * churn + float(i) * 0.9) * amp
			pts.append(Vector2(x, y))
			x += 10.0
		var alpha := 0.20 - t * 0.10
		draw_polyline(pts, Color(1, 1, 1, alpha), 1.4, true)


## 水下鱼的影子：一个拉长的暗色椭圆 + 尾巴，随搏斗强度变明显。
func _draw_fish_shadow(w: float, h: float) -> void:
	if not _fish_shadow_visible:
		return
	var p := _bobber_pos(w, h)
	var cx := p.x + sin(_time * 2.2) * 34.0
	var cy := p.y + 52.0 + sin(_time * 1.7) * 12.0
	var rx := 56.0 + 12.0 * _fight_intensity
	var ry := 18.0 + 5.0 * _fight_intensity
	var alpha := 0.22 + 0.20 * _fight_intensity

	var body := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		body.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(body, Color(0.03, 0.12, 0.15, alpha))

	var tail := PackedVector2Array([
		Vector2(cx + rx * 0.82, cy),
		Vector2(cx + rx * 1.42, cy - ry * 0.95),
		Vector2(cx + rx * 1.42, cy + ry * 0.95),
	])
	draw_colored_polygon(tail, Color(0.03, 0.12, 0.15, alpha * 0.82))


func _draw_rod(w: float, h: float) -> void:
	if not _bobber_visible:
		return
	var tip := _bobber_pos(w, h)
	var start := Vector2(w * 0.97, h * 1.04)
	var ctrl := Vector2(w * 0.70, h * 0.50)
	# 搏斗时鱼线被拉直，控制点向直线中点靠拢
	if _fight_intensity > 0.001:
		ctrl = ctrl.lerp(start.lerp(tip, 0.5), _fight_intensity * 0.78)

	var pts := PackedVector2Array()
	for i in 22:
		var t := float(i) / 21.0
		var a := start.lerp(ctrl, t)
		var b := ctrl.lerp(tip, t)
		pts.append(a.lerp(b, t))
	draw_polyline(pts, Palette.ROD_LINE, 1.6, true)


func _draw_bobber(w: float, h: float) -> void:
	if not _bobber_visible:
		return
	var p := _bobber_pos(w, h)
	var bob := sin(_time * 2.4) * 2.5 * (1.0 - _fight_intensity)
	var sink := 7.0 if _biting else 0.0
	var center := p + Vector2(0, bob + sink)

	# 落水涟漪
	var ripple_r := 16.0 + fmod(_time * 26.0, 34.0)
	draw_arc(Vector2(center.x, p.y + 12.0), ripple_r, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 1.4, true)

	# 咬钩时的高亮圈
	if _bite_flash > 0.0:
		var k := _bite_flash / 0.55
		draw_circle(Vector2(center.x, p.y + 10.0), 26.0 * k + 8.0, Color(1.0, 0.85, 0.45, 0.30 * k))

	# 搏斗水花：一圈往外溅的白点
	if _fight_intensity > 0.08:
		for i in 6:
			var ang := _time * 2.6 + float(i) * 1.047
			var dist := 14.0 + fmod(_time * 46.0 + float(i) * 11.0, 30.0)
			var sp := Vector2(cos(ang), sin(ang) * 0.55) * dist
			draw_circle(Vector2(center.x, p.y + 10.0) + sp, 2.4 * _fight_intensity,
				Color(1, 1, 1, 0.55 * _fight_intensity))

	# 浮标：白杆 + 红球
	draw_line(center + Vector2(0, -20), center + Vector2(0, 4), Color(1, 1, 1, 0.9), 3.0, true)
	draw_circle(center, 8.0, Palette.BOBBER)
	draw_circle(center + Vector2(-2.5, -2.5), 3.0, Color(1, 1, 1, 0.65))


func _bobber_pos(w: float, h: float) -> Vector2:
	var x := w * (0.10 + 0.80 * (_bobber_point / 100.0))
	var y := h * WATER_RATIO + h * 0.075
	if _fight_intensity > 0.001:
		# 搏斗时浮标被鱼拽得乱窜：高频抖动 + 整体下沉
		x += sin(_time * 21.0) * 9.0 * _fight_intensity
		y += sin(_time * 17.0 + 1.1) * 5.5 * _fight_intensity + 11.0 * _fight_intensity
	return Vector2(x, y)
