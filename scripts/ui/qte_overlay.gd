class_name QteOverlay
extends Control

## 搏斗期的场景内 QTE 显示 —— 没有面板、没有边框卡片。
##
## 屏幕上只有两样东西：
##   1. 顶部两条细长的体力 / 张力指示条
##   2. 屏幕下方的圆环，游标从顶部顺时针转
##
## 圆环顶部一段**黄色**的弧是命中区，只有这一段，没有第二层。
## 黄标的宽度和游标转速都由难度档决定：
##   easy   216° / 0.34 圈每秒
##   normal 173° / 0.45
##   hard   122° / 0.58
## 也就是说低难度黄标几乎铺满半个圆、游标还慢；高难度只剩三分之一圆、游标快三成。
## 手机上手指出点偏差必须还能中，所以最窄也不许低于 100°（hit_half 0.14）。
##
## 完美判定仍在 FightSession 里生效（命中区正中一小段额外减张力），但**不画出来** ——
## 画了就是第二层，玩家会去追那条窄弧，反而不敢按。
##
## 击打冷却（每次点完之后的一小段）里游标压暗、中心提示「等」，
## 那时候按下去不算数。
##
## 这里只画，不做任何判定。命中与否由 FightSession.strike() 决定。

const METER_W := 440.0
const METER_H := 8.0
const METER_TOP := 104.0
const RING_RADIUS := 116.0
const RING_W := 16.0
const CURSOR_LEN := 14.0

var _cursor: float = 0.0
var _stamina: float = 1.0
var _tension: float = 0.0
var _locked: bool = false
var _hit_half: float = 0.24
var _center: float = 0.0   ## 黄标中点。困难难度下随爆冲左右摆
var _flash: float = 0.0
var _flash_kind: String = ""
var _fight: FightSession = null
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if _fight == null:
		return
	# 游标每帧都在动，所以无条件重绘
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.2, 0.0)
	# 爆冲时黄标自己也在挪，每帧跟一遍，别让它和判定脱节
	_center = _fight.hit_center()
	queue_redraw()


## 接上一场搏斗。重复调用会先断开上一场。
func bind(fight: FightSession) -> void:
	unbind()
	if fight == null:
		return
	_fight = fight
	_cursor = fight.cursor
	_stamina = fight.stamina_ratio()
	_tension = fight.tension_ratio()
	_locked = fight.input_locked()
	_hit_half = fight.current_hit_half()
	_center = fight.hit_center()
	_flash = 0.0

	fight.cursor_changed.connect(_on_cursor)
	fight.stamina_changed.connect(_on_stamina)
	fight.tension_changed.connect(_on_tension)
	fight.strike_result.connect(_on_strike)
	fight.input_lock_changed.connect(_on_lock)
	queue_redraw()


func unbind() -> void:
	if _fight == null:
		return
	var f := _fight
	_fight = null
	if f.cursor_changed.is_connected(_on_cursor):
		f.cursor_changed.disconnect(_on_cursor)
	if f.stamina_changed.is_connected(_on_stamina):
		f.stamina_changed.disconnect(_on_stamina)
	if f.tension_changed.is_connected(_on_tension):
		f.tension_changed.disconnect(_on_tension)
	if f.strike_result.is_connected(_on_strike):
		f.strike_result.disconnect(_on_strike)
	if f.input_lock_changed.is_connected(_on_lock):
		f.input_lock_changed.disconnect(_on_lock)


func _draw() -> void:
	if size.x < 4.0:
		return
	_draw_meters()
	_draw_ring()


func _draw_meters() -> void:
	var x := (size.x - METER_W) * 0.5
	_draw_meter(x, METER_TOP, _stamina, Palette.GOOD.lerp(Palette.BAD, 1.0 - _stamina))
	_draw_meter(x, METER_TOP + 18.0, _tension,
		Palette.ACCENT.lerp(Palette.BAD, clampf(_tension * 1.4, 0.0, 1.0)))

	if _font != null:
		draw_string(_font, Vector2(x - 44.0, METER_TOP + 8.0), tr("体力"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.F_SMALL, Palette.INK_SOFT)
		draw_string(_font, Vector2(x - 44.0, METER_TOP + 26.0), tr("张力"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.F_SMALL,
			Palette.BAD if _tension > 0.7 else Palette.INK_SOFT)


func _draw_meter(x: float, y: float, value: float, color: Color) -> void:
	draw_style_box(_round(Color(1, 1, 1, 0.55), int(METER_H * 0.5)),
		Rect2(x, y, METER_W, METER_H))
	if value > 0.001:
		draw_style_box(_round(color, int(METER_H * 0.5)),
			Rect2(x, y, maxf(METER_W * value, METER_H), METER_H))


func _draw_ring() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.68)
	var r := RING_RADIUS

	# 轨道：一圈细白线，只表明「游标是沿这个圆走的」，不参与判定
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.26), RING_W * 0.5, true)

	# 命中区：整段就是一块黄标。没有第二层、没有内圈、没有渐变。
	# 宽度由难度的 hit_half 决定，黄标多宽就是命中区多宽 ——
	# 玩家一眼量的就是这两道刀口之间的距离。
	#
	# 中点在 hit_center()：平常钉在顶部，困难难度下鱼会爆冲，整块黄标左右摆。
	# 判定和画面用同一个函数，不会出现「看着在标里却判失手」。
	var mid := _center
	draw_arc(c, r, _angle(mid - _hit_half), _angle(mid + _hit_half), 96,
		Palette.ACCENT, RING_W, true)

	# 黄标两端各一道刀口。没有它，玩家不知道黄色从哪开始、到哪结束。
	_draw_edge_tick(c, r, mid - _hit_half, Palette.ACCENT_DEEP)
	_draw_edge_tick(c, r, mid + _hit_half, Palette.ACCENT_DEEP)

	# 命中闪光：整段黄标一起亮一下，亮完就退，不额外画别的东西
	if _flash > 0.0:
		var col := Palette.BAD if _flash_kind == "miss" else Palette.GOOD
		if _flash_kind == "round":
			col = Palette.ACCENT
		var w := RING_W + 12.0 * _flash
		draw_arc(c, r, _angle(mid - _hit_half), _angle(mid + _hit_half), 96,
			Color(col, 0.5 * _flash), w, true)

	# 游标
	var a := _angle(_cursor)
	var dir := Vector2(cos(a), sin(a))
	var dim := 0.35 if _locked else 1.0
	var ink := Color(Palette.INK, dim)
	draw_line(c + dir * (r - RING_W * 0.5 - CURSOR_LEN),
		c + dir * (r + RING_W * 0.5 + CURSOR_LEN), ink, 5.0, true)
	draw_circle(c + dir * (r + RING_W * 0.5 + CURSOR_LEN), 6.0, ink)

	# 中心
	if _font == null:
		return
	if _locked:
		_center_text(tr("等"), Palette.F_H2, Color(Palette.INK_FAINT, 0.7), 8.0)
		return
	_center_text(tr("点一下"), Palette.F_H2, Palette.INK_SOFT, 8.0)
	if _fight != null:
		var done := _fight.rounds_done()
		var need := _fight.rounds_needed()
		if need > 0:
			_center_text("%d / %d" % [mini(done, need), need], Palette.F_SMALL,
				Palette.INK_FAINT, 30.0)


func _center_text(text: String, font_size: int, color: Color, dy: float) -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.68)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, c + Vector2(-w * 0.5, dy), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## 判定区端点刻线：从轨道内缘捅到外缘，加一个小圆帽。
func _draw_edge_tick(c: Vector2, r: float, pos: float, color: Color) -> void:
	var a := _angle(pos)
	var dir := Vector2(cos(a), sin(a))
	draw_line(c + dir * (r - RING_W * 0.5 - 6.0), c + dir * (r + RING_W * 0.5 + 6.0),
		color, 3.0, true)
	draw_circle(c + dir * (r + RING_W * 0.5 + 9.0), 4.0, color)


## 归一化角度 → 弧度。0 在正上方，顺时针为正。
func _angle(t: float) -> float:
	return -PI * 0.5 + t * TAU


func _round(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


# ---------- 信号回调 ----------

func _on_cursor(pos: float) -> void:
	_cursor = pos


func _on_stamina(ratio: float) -> void:
	_stamina = ratio


func _on_tension(ratio: float) -> void:
	_tension = ratio


func _on_strike(kind: String) -> void:
	match kind:
		"round":
			_flash = 1.0
			_flash_kind = "round"
		"good":
			_flash = 0.6
			_flash_kind = "good"
		_:
			_flash = 1.0
			_flash_kind = "miss"


func _on_lock(locked: bool) -> void:
	_locked = locked
