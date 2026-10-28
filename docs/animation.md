# 动画帧：素材怎么出、怎么接

现在整个游戏只有静态图和 Tween（位移 / 缩放 / 淡入淡出），一张立绘顶一个角色。真要做逐帧动画，先在动手之前把三件事定下来：**做什么动作**、**素材怎么保证同一个人**、**包体会涨多少**。

---

## 一、先分清三种「动画」

别一上来就说「我要逐帧」。这三类的成本差一个数量级。

### A. 微动效 —— 现在就能做，不需要新素材

靠 `Tween` 改 `scale` / `rotation` / `modulate` / `position`：

- 呼吸：立绘 `scale.y` 在 1.00 ~ 1.015 之间 3 秒来回，`TRANS_SINE` + `EASE_IN_OUT`
- 尾巴摆：单独一张尾巴图挂 `rotation` ±6°，周期 2.4 秒
- 眨眼：两张图（睁眼 / 闭眼）每 4~6 秒瞬切 0.12 秒
- 受击抖：`position.x` 快速左右 3 次衰减

代价是**零张新图**（眨眼要一张闭眼图）。游戏中 80% 的「活起来」靠这个就够。

### B. 拆件骨骼动画 —— 要重画分件图

把角色拆成 头 / 躯干 / 上臂 / 前臂 / 大腿 / 小腿 / 尾巴 / 呆毛，每件一张透明 PNG，在 Godot 里用 `Skeleton2D` + `Bone2D` + `Polygon2D` 拼回去。

- 优点：一个角色一套件，所有动作共用，能做出转身、挥手、被钓上岸的挣扎
- 缺点：要**重新出一套分件图**，而且分件图的关节接缝必须画对（AI 直接出分件图接缝永远对不上，得手修）
- 适合：主角级、出场时间长的角色

### C. 逐帧动画 —— 最贵，也最容易崩

一个动作 6~12 张，每张都得是同一个人的同一个角度。

**AI 出逐帧的真实难度**：固定 seed + 只换动作词，脸部会漂、衣服褶皱会变、尾巴长度都会变。做 12 帧能用的，通常要生成 100+ 张再挑。

---

## 二、AI 出逐帧素材的硬条件

### 当前环境有什么

`E:\Comfy-Desktop\ComfyUI-Shared\models` 里：

| 目录 | 内容 |
|---|---|
| `diffusion_models` | `anima-base-v1.0`（项目基座）、`anima-turbo-v1.1`、`anima-preview3-base` |
| `loras` | `DeepSeek_ZipZipPipe_style_anima2b`（项目风格 LoRA）、`anima-turbo-lora-v0.2` |
| `checkpoints` | SDXL base / refiner、RealVisXL、Realistic Vision |
| `controlnet` | **空** |
| `ipadapter` | **不存在** |
| `clip_vision` | **空** |

**结论：现在出不了真正一致的逐帧。** 缺的是锁人物和锁骨架的两件工具。

### 要做逐帧得先补的两样

1. **IPAdapter**（锁人物脸和画风）
   - `ipadapter` 模型约 1~2 GB，配 `clip_vision` 的 ViT-H（约 2.5 GB），再加 ComfyUI 的 `ComfyUI_IPAdapter_plus` 节点包
   - 用法：把一张「标准姿态」立绘当参考图喂进去，权重 0.6~0.8，后面每帧只改动作词
2. **ControlNet**（锁骨架）
   - 逐帧的话用 `openpose`，先自己摆好 12 个姿势的骨架图（或者用 3D 软件摆），再让模型按骨架出图
   - SDXL 的 openpose 模型约 2.5 GB

两样加起来 5~6 GB，下载前先说一声。

### 不补工具的退路

固定 seed + 同一段完整 prompt，只动一个动作词，一次出 8 张挑 3 张能用。脸部大概率有 5~10% 的漂移，靠后期在 Godot 里对齐眼睛位置（`position` 微调）能压下去一部分，但骗不过眼睛。

**老实讲：这条路性价比很低。** 真要逐帧，建议先补 IPAdapter。

---

## 三、逐帧素材的规格（照着出，别自己发明）

| 项 | 值 | 理由 |
|---|---|---|
| 画布 | 竖版 832×1216 | 和现有立绘一致，换帧不跳尺寸 |
| 角色高度 | 占画布高 78%~82% | 头顶留 8%、脚下留 10%，给抖动和位移留余量 |
| 背景 | 纯色或透明，**不能有渐变和阴影** | 透明通道抠图时渐变边缘会出白边 |
| 格式 | 先存 PNG（RGBA），进项目时转 WebP 有损 q90 | 现在项目里的图全是 WebP，见下文体积 |
| 命名 | `<角色>_<动作>_<两位帧号>.png` | 例：`deepseek_idle_01.png`、`deepseek_bite_03.png` |
| 帧率 | 8~12 fps | 手绘感要低帧率，24 fps 反而像 3D |
| 循环动作 | 首尾帧必须能接上 | 走 01→02→…→N→01 不跳 |
| 单动作帧数 | 4（眨眼级）~8（挥手）~12（上钩挣扎） | 超过 12 帧肉眼看不出提升，只是涨体积 |

**每帧都要单独检查一遍**：眼睛朝向、发梢长度、尾巴尖的位置、裙摆褶皱走向。这四项任一漂了，剪进动画里就是抽搐。

---

## 四、体积代价（这个必须提前算）

项目现在的 `pck` 是 **2.7 MB**，全部图加起来不到 3 MB。加动画会按这个速度涨：

| 内容 | 张数 | WebP q90 实测量级 | 备注 |
|---|---:|---:|---|
| 一条鱼的完整待机（12 帧） | 12 | 约 1.2~1.8 MB | 竖版 832×1216 |
| 眨眼（2 帧） | 2 | 约 0.2 MB | 最划算的一项 |
| 上钩挣扎（10 帧） | 10 | 约 1.0~1.5 MB | |
| 三条鱼各一套待机 + 挣扎 | 66 | 约 7~10 MB | pck 从 2.7 涨到 10 MB 以上 |

**注意**：Godot 导入纹理时如果 `compress/mode` 设成无损，168 KB 的图会变成 923 KB 的 `.ctex`。项目里已经踩过这个坑，现在统一 **有损 + q85**（`export_presets` 与 `.import` 一起改）。新加的图务必检查 import 设置，否则体积直接 quadruple。

**省体积的三招**：

1. 只做主角色（DeepSeek 鲸鱼娘），Claude 和豆包继续用「两张图 + Tween」
2. 用**同一套骨架**跑不同角色：拆件动画只换贴图，不换帧数
3. 循环动作砍到 4~6 帧，靠 Tween 补中间（`scale` 轻微起伏能骗过眼睛）

---

## 五、Godot 侧怎么接

### 逐帧：`AnimatedSprite2D` + `SpriteFrames`

适合场景内的对象（湖面上跳的鱼、甩动的尾巴）：

```gdscript
var frames := SpriteFrames.new()
frames.set_animation_speed("idle", 10.0)
for i in range(1, 13):
    frames.add_frame("idle", load("res://assets/anim/deepseek_idle_%02d.webp" % i))
frames.set_animation_loop("idle", true)

var spr := AnimatedSprite2D.new()
spr.sprite_frames = frames
spr.play("idle")
add_child(spr)
```

### UI 里的立绘：手动切帧，别用 AnimatedSprite2D

`AnimatedSprite2D` 是 2D 世界节点，塞进 `Control` 布局里会有坐标和缩放打架。UI 立绘用 `TextureRect` 自己换 `texture`：

```gdscript
var _frames: Array[Texture2D] = []
var _frame_index := 0
var _frame_timer := 0.0

func _process(delta: float) -> void:
    _frame_timer += delta
    if _frame_timer >= 1.0 / 10.0:
        _frame_timer = 0.0
        _frame_index = (_frame_index + 1) % _frames.size()
        _pic.texture = _frames[_frame_index]
```

用 `TextureRect.EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_CENTERED`，和现有的 `UIKit.picture_fit` 一致，换帧不会跳尺寸。

### 拆件：`Skeleton2D`

节点树大致是：

```
Skeleton2D
├── Bone2D "root"
│   └── Bone2D "torso"
│       ├── Bone2D "head"
│       └── Bone2D "arm_l"
└── Polygon2D × N   (每块贴图)
```

`Polygon2D` 的每个顶点绑到对应骨骼，`Bone2D` 改 `rotation` 就带动贴图。用 `AnimationPlayer` 打关键帧，或者代码里 `rotation = lerp(...)` 都行。

**这条路工作量最大，但一套骨架能跑所有动作，是长期唯一正确的选择。**

---

## 六、这个项目里最值得放动画的五个位置

按「玩家看得见的次数 × 实现成本」排序：

1. **上鱼飞扑**（`scripts/ui/landing_view.gd`）—— 鱼从水里扑出来那一瞬。现在是一个 `Tween` 抛物线 + 缩放，加 4 帧张牙舞爪能立刻有魂
2. **QTE 圆环中心的鱼**（`scripts/ui/qte_overlay.gd`）—— 搏斗全程看着它，加 2 帧（正常 / 吃力）就够
3. **结算页立绘**（`scripts/ui/ending_overlay.gd`）—— 结局 CG 是静态的，加轻微呼吸缩放（Tween，零新图）成本最低
4. **图鉴缩略图**（`scripts/ui/gallery_root.gd`）—— 未解锁格加个循环微光，纯代码
5. **湖面浮标**（`scripts/ui/lake_view.gd`）—— 下沉那一下加 3 帧涟漪

前四个里，只有第 1 和第 2 需要真素材。

---

## 七、要动手时的顺序

1. 先补 IPAdapter + clip_vision（5~6 GB，先问）
2. 出**一张标准姿态**当参考：正面、全身、手放下、无遮挡
3. 用这张当 IPAdapter 参考，固定 seed，只改动作词，一个动作一次出 16 张挑 8 张
4. 每帧过一遍「眼睛 / 发梢 / 尾巴 / 裙摆」四项检查，漂的丢掉重出
5. 统一裁到 832×1216、角色高度 80%，导出 PNG
6. `python tools/make_anim.py`（要新写）批量转 WebP q90 + 生成 `SpriteFrames` 或帧数组
7. 接进上面的第 1、2 两个位置，跑一遍自测看 pck 涨了多少
8. 涨超过 6 MB 就砍帧数，别砍画质

---

## 八、现在**不**建议做的事

- **不要**为了「看起来更贵」给所有静态图加噪点或抖动滤镜 —— 这个项目的观感靠干净的色块和留白
- **不要**做 24 fps —— 手绘感靠低帧率，24 fps 会像廉价 3D
- **不要**给每条鱼都做完整动画 —— 先做一条，验证体积和观感，再决定要不要铺开

---

## 九、已经落地的第一套：小肥鱼被钓上来扣饭盆

ssets/anim/small/ 下六帧，768×768，WebP 有损 q90，共 203 KB（导入后缓存 174 KB）：

| 文件 | 内容 |
|---|---|
|  1_pull.webp | 被鱼线勾住呆毛吊出水面，瞪眼张嘴、水花四溅 |
|  2_bowl_fall.webp | 一个倒扣的白瓷饭盆从上方砸下来，带震动线 |
|  3_bowl_hit.webp | 盆扣死在头上，只剩一张嘴从盆沿下露出来 |
|  4_bowl_slip.webp | 盆歪到一边开始掉米粒，翻白眼吐舌头 |
|  5_rice.webp | 下半身化成一堆白米饭 |
|  6_ricefish.webp | 定型：一坨带小眼睛的白饭团，头顶饭盆，身后一条蓝鲸尾 |

**接入方式**（scripts/ui/landing_view.gd）：

`gdscript
const SEQUENCES := {
    "small": "res://assets/anim/small",
}
`

play() 时先查这张表，有序列就 _load_sequence() 逐帧加载，没有就退回 ish.portrait 那张静态图。每帧停留时间由 (FLIGHT_SECONDS + HOLD_SECONDS - 0.15) / 帧数 自动算出，加帧减帧不用改常量。

**两个必须记住的坑**：

1. DirAccess.get_files() 会把 .import 也列出来。**不要** trim 掉 .import 再判断后缀 —— 那样每帧会被数两遍，六帧变十二帧（自测里真的报了 序列帧数 = 12）。正确做法是见到 .import 直接 continue。
2. 新导入的 .webp 默认 compress/mode=0（**无损**），47 KB 的图会膨胀成几百 KB 的 .ctex。必须改 compress/mode=1 + compress/lossy_quality=0.85，和项目其它图保持一致。

**画魔性动画的关键**：这套图用的是 LoRA 强度 **0.85**（高饱和平涂 + 粗黑描边），和正剧 CG 用的 0.45 不一样。**魔性靠夸张和粗线条，不靠细腻**，所以这里反而要吃满 LoRA。六帧之间的造型漂移在梗图语境下根本不算问题 —— 观众看的是"她被扣了一盆饭"，不是脸有没有偏移三像素。

**代价**：pck 从 2.72 MB 涨到 2.90 MB（+178 KB），exe 从 50.59 MB 涨到 50.77 MB。一套六帧约 0.2 MB，可以做，但别给每条鱼都来一套。