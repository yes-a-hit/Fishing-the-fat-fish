class_name Palette
extends RefCounted

## 全局配色与尺寸。所有颜色只在这里定义一次。
##
## 风格：日间湖面。天空浅蓝 → 水面青绿，卡片是半透明白，文字深墨蓝。
## 想整体换肤，改这一个文件即可，UI 代码里没有硬编码颜色。

# ---------- 文字 ----------
const INK := Color(0.114, 0.208, 0.251)        # #1d3540 主文字
const INK_SOFT := Color(0.290, 0.392, 0.439)   # #4a6470 次要文字
const INK_FAINT := Color(0.490, 0.580, 0.620)  # #7d949e 弱化文字
const ON_DARK := Color(0.960, 0.980, 0.988)

# ---------- 卡片 ----------
const CARD := Color(0.992, 0.996, 1.000)       # #fdfeff
const CARD_SOFT := Color(0.945, 0.969, 0.976)  # #f1f7f9
const CARD_EDGE := Color(0.788, 0.875, 0.902)  # #c9dfe6
const SHADOW := Color(0.055, 0.149, 0.196, 0.18)

# ---------- 强调 ----------
const ACCENT := Color(0.886, 0.627, 0.247)     # #e2a03f 金
const ACCENT_DEEP := Color(0.741, 0.478, 0.153)
const GOOD := Color(0.247, 0.663, 0.416)       # #3fa96a
const BAD := Color(0.831, 0.333, 0.247)        # #d4553f
const WARN := Color(0.902, 0.541, 0.184)

# ---------- 场景 ----------
const SKY_TOP := Color(0.624, 0.816, 0.910)
const SKY_LOW := Color(0.914, 0.961, 0.976)
const SUN := Color(1.000, 0.976, 0.902)
const HILL_FAR := Color(0.576, 0.722, 0.690)
const HILL_NEAR := Color(0.431, 0.612, 0.580)
const WATER_SHALLOW := Color(0.471, 0.702, 0.753)
const WATER_DEEP := Color(0.169, 0.373, 0.427)
const WATER_LINE := Color(0.824, 0.933, 0.949)
const BOBBER := Color(0.910, 0.329, 0.290)
const ROD_LINE := Color(0.310, 0.235, 0.180, 0.55)

# ---------- 抛竿距离带 ----------
const ZONE_SMALL := Color(0.478, 0.784, 0.706)
const ZONE_MID := Color(0.937, 0.780, 0.427)
const ZONE_BIG := Color(0.886, 0.518, 0.365)
const ZONE_DONE := Color(0.804, 0.839, 0.855)
const ZONE_GAP := Color(0.878, 0.906, 0.918)

# ---------- 字号 ----------
const F_TITLE := 34
const F_H2 := 24
const F_H3 := 19
const F_BODY := 16
const F_SMALL := 13

# ---------- 尺寸 ----------
const RADIUS := 16
const RADIUS_SM := 8
const PAD := 22


## 按鱼 id 取距离带颜色。未知 id 给一个中性色，方便玩家自己加角色。
static func zone_color(fish_id: String) -> Color:
	match fish_id:
		"small":
			return ZONE_SMALL
		"mid":
			return ZONE_MID
		"big":
			return ZONE_BIG
		"claude":
			# 陷阱带刻意与远洋同色：抛竿条上不该让人看出尽头还有东西
			return ZONE_BIG
		_:
			return Color(0.62, 0.72, 0.78)
