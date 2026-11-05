# 架构说明

## 分层

```text
┌──────────────────────────────────────────────────────────────┐
│ data/*.json           数值、文案、立绘、脱钩演出和结局路径      │
└──────────────────────────────┬───────────────────────────────┘
                               │ 只有 ConfigLoader 读取
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ scripts/core/         纯规则层（RefCounted，无场景树依赖）     │
│                                                              │
│ FishSpec          单个目标的静态配置                          │
│ GameTuning        全局数值、难度档、可重叠距离带、加权抽鱼      │
│ GameSettings      玩家偏好（难度、语言、音量）                 │
│ FightSession      单场圆环搏斗                              │
│ FishingSession    一局状态机、收集、结局与统计                 │
└──────────────────────────────┬───────────────────────────────┘
                               │ 信号与只读快照
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ scripts/ui/           表现层                                  │
│                                                              │
│ menu_root         主菜单（游戏入口）                          │
│ game_root         装配、输入路由、阶段切换                     │
│ lake_view         湖面、浮标、鱼线、水花、鱼影                 │
│ qte_overlay       圆环判定和资源细条                        │
│ landing_view      上鱼演出（当前为静态图占位）                 │
│ ending_overlay    结算、统计、收集                            │
│ lake_backdrop     湖面背景（菜单/图鉴/设置/关于共用）           │
│ pause_layer       暂停遮罩（对局内，独立一层）                 │
│ gallery_root      图鉴四页：结局 / 脱钩 / 角色 / 声音           │
│ settings_root     设置页（难度、语言、音量、清档）              │
│ about_root        关于页（协议与出处）                        │
└──────────────────────────────────────────────────────────────┘
```

核心原则是**规则往下沉，表现往上浮**。

`FishSpec`、`GameTuning`、`FightSession`、`FishingSession` 不依赖 `Node`、`Control`、`Input` 或 `get_tree()`。JSON 读取集中在 `ConfigLoader`；`FishSpec` 仅用 `ResourceLoader.exists()` 校验立绘路径。规则因此能在 `--headless` 下完整运行。

---

## 文件职责

| 文件 | 当前职责 | 不应承担 |
|---|---|---|
| `core/fish_spec.gd` | 静态数值、立绘、台词、默认值 | 当前体力、张力、序列进度 |
| `core/game_tuning.gd` | 全局配置、难度档覆盖、可重叠距离带、加权抽鱼 | 输赢判定、画面布局 |
| `core/game_settings.gd` | 读写 `user://settings.json`（难度），坏文件静默回落 | 游戏规则数值 |
| `core/fight_session.gd` | 游标推进、环形判定、体力、张力、冷却 | 绘制、读取输入事件 |
| `core/fishing_session.gd` | 阶段机、抛竿、等待、收集、结局、汇总 | 读文件、创建控件、播放动画 |
| `core/config_loader.gd` | JSON 读取、结构校验、兜底、数据层文案过翻译 | 保存一局运行时状态 |
| `core/score_board.gd` | 命中底分、连击倍率、尾款、最高分读写 | 绘制、读输入 |
| `ui/menu_root.gd` | 主菜单、切到 `main.tscn`（难度在设置页改） | 任何游戏规则 |
| `ui/game_root.gd` | 装配、输入转发、信号连接、阶段显示 | 计算伤害、张力或结局 |
| `ui/lake_view.gd` | 场景绘制和浮标挣扎表现 | 决定何时上鱼 |
| `ui/qte_overlay.gd` | 订阅搏斗信号并绘制反馈 | 修改序列或判定输入 |
| `ui/scene_feedback.gd` | 空竿、断线短提示 | 决定提示对应的结果 |
| `ui/score_layer.gd` | 画分数行与命中飘字，只显示不算分 | 自己累加分数 |
| `ui/landing_view.gd` | 播放上鱼演出并回报完成 | 记录收集、决定下一阶段 |
| `ui/ending_overlay.gd` | 显示结局、统计和收集项 | 生成统计或判断结局 |
| `ui/lake_backdrop.gd` | 绘制湖面背景（天空/水面渐变、两层山、水线） | 处理输入、读取数据 |
| `ui/pause_layer.gd` | 暂停遮罩与三个动作（继续/重开/回菜单），只发信号 | 直接改 paused 之外的状态 |
| `ui/gallery_root.gd` | 图鉴四页；条目来自 `endings.json` / `escapes.json` / `characters.json` / 内置语音表 | 自己写死图片与文案清单 |
| `ui/settings_root.gd` | 难度、语言、音量、清档二次确认 | 直接改对局内数据 |
| `ui/about_root.gd` | 渲染 `about.json`：协议、出处、彩蛋 | 自己读文件（走 `ConfigLoader`） |
| `ui/palette.gd` | 集中颜色、字号等视觉常量 | 业务逻辑 |
| `ui/ui_kit.gd` | 通用控件与贴图工厂 | 游戏规则 |

---

## 状态与结果枚举

```gdscript
FishingSession.Phase = {
    AIMING = 0,
    WAITING = 1,
    FIGHTING = 2,
    LANDING = 3,
    RESOLVING = 4,
    ENDED = 5,
}

FishingSession.RESULT_CAUGHT    = "caught"
FishingSession.RESULT_ESCAPED   = "escaped"
FishingSession.RESULT_EMPTY     = "empty"
FishingSession.RESULT_DUPLICATE = "duplicate"

FightSession.Dir = { UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3 }
FightSession.DIR_LABEL = ["W", "S", "A", "D"]

FightSession.input() 返回 "hit" / "round" / "miss"；非活动状态返回 ""
FightSession.finished 的 reason 为 "landed" / "line_broke"
```

成功上鱼不发送 `resolved("caught")`：它进入 `LANDING` 并发送 `landing_started`。`resolved` 当前只用于断线和空竿。

---

## 信号表

### FishingSession

| 信号 | 参数 | 触发时机 | 当前监听者 |
|---|---|---|---|
| `phase_changed` | `phase: int` | 每次阶段变化 | `game_root` 切换视图 |
| `bait_changed` | `left, total: int` | 开局和抛竿扣饵 | `hud_view` |
| `charge_changed` | `value: float` | 蓄力变化及抛竿归零 | `cast_panel` |
| `cast_made` | `point: float, fish_id: String` | 落点确定 | `game_root` 放置浮标 |
| `bite_started` | `fish: FishSpec, fight: FightSession` | 进入搏斗后 | `qte_overlay` 绑定、湖面反馈 |
| `landing_started` | `fish: FishSpec` | 体力磨空并进入 `LANDING` | `landing_view` 播放 |
| `resolved` | `kind: String, fish: FishSpec` | 断线、空竿 | `scene_feedback` 提示 |
| `doubao_started` | `refund: int` | 豆包被捞上来并返还白饭后 | `game_root` 飘出「哪来的奶黄包！」卡片 |
| `finished` | `ending: String, summary: Dictionary` | 一局结束 | `ending_overlay` |

### FightSession

| 信号 | 参数 | 触发时机 |
|---|---|---|
| `cursor_changed` | `pos: float` | 每帧游标位置变化（0~1 环形） |
| `stamina_changed` | `ratio: float` | 开局和每次命中后 |
| `tension_changed` | `ratio: float` | 开局、自然增长、缓解和失手惩罚 |
| `strike_result` | `kind: String` | `round` 命中 / `good` 普通命中 / `miss` 失手 |
| `input_lock_changed` | `locked: bool` | 点完后进入 / 退出冷却窗口 |
| `finished` | `success: bool, reason: String` | 上鱼或断线 |

`QteOverlay.bind()` 订阅上述表现信号，`unbind()` 必须断开旧搏斗，避免重开或换鱼后重复接收。

### 冷却窗口（`strike_lock`）

每次命中或失手后，`FightSession` 把 `_input_lock` 置为 `tuning.fight.strike_lock`（默认 0.3 秒），
`strike()` 在窗口内直接返回 `""`，不判定、不记 miss、不涨张力、不算轮次。

这个窗口存在是因为手机上连点两下是常见误触：没有冷却的话第二下必然落在「刚好离开判定区」的位置，
白吃一次 `miss_tension`，而玩家完全不知道自己错在哪。锁定期间 `QteOverlay` 会把游标压暗、中心提示改成「等」。

---

## 一局数据流

```text
按住空格 / 左键
  └─ game_root._unhandled_input()
       └─ FishingSession.press()               → 开始蓄力

每帧
  └─ game_root._process(delta)
       └─ FishingSession.tick(delta)
            └─ charge = fmod(charge + speed*delta, 1.0)
                 └─ charge_changed              → 抛竿条重绘

松开空格 / 左键
  └─ FishingSession.release()
       └─ _cast()
            ├─ bait_left -= 1
            ├─ cast_point = charge*100 + RNG(-jitter, jitter)
            ├─ candidates_at(zones, point)         → 覆盖该点的所有带
            ├─ 去掉已钓到的                          → 候选池
            ├─ _weighted_pick(候选池)                → 按 score 抽一条
            │    （score = weight × 中心偏向，越靠带中心越好抽）
            ├─ cast_made.emit(point, 抽中者)
            └─ _set_phase(WAITING)

等待结束
  ├─ 候选池为空 → _resolve(empty / duplicate) → RESOLVING
  └─ 有目标     → _start_fight()
       ├─ 创建 FightSession，并连接 finished
       ├─ _set_phase(FIGHTING)
       ├─ bite_started.emit(fish, fight)
       └─ fight.start()                       → 游标从随机位置起步

搏斗输入
  └─ game_root 把点击 / 空格 / 回车 / 触摸都当作同一个「点一下」
       └─ FishingSession.qte_strike()
            └─ FightSession.strike()
                 ├─ 在完美区：伤害、轮次统计、冷却、额外缓解张力
                 ├─ 在命中区：伤害、轮次统计、冷却、缓解张力
                 └─ 在判定区外：张力增加、冷却

搏斗结束
  ├─ 张力满 → RESOLVING → 断线提示
  └─ 体力空 → 记录收集 → LANDING
       ├─ landing_started.emit(fish)
       ├─ LandingView 播放并 finished.emit()
       ├─ game_root 调 FishingSession.landing_done()
       └─ 或 landing_timeout 到期自动兜底

本轮完全结束
  ├─ 上到陷阱鱼 → ENDED（claude）
  ├─ 三种齐了 → ENDED（feast）
  ├─ 白饭为零 → ENDED（full 或 hungry，看上鱼次数是否达到 full_catch_threshold）
  └─ 其他情况 → AIMING
```

---

## 当前统计结构

`FightSession.stats` 和 `FishingSession.summary()` 使用同一组搏斗汇总键：

| 键 | 含义 |
|---|---|
| `rounds` | 命中的次数，等于削了几次体力 |
| `perfect` | 落在完美区内的命中次数 |
| `miss` | 失手次数 |

`summary()` 还包含 `bait_total/bait_left/bait_used`、`caught/caught_count/fish_total`、`landed`（上鱼总次数，可重复）、`good`（= `rounds - perfect`，普通命中）、`claude_caught`。

`miss` 是空竿，不进 `rounds`。`good` 曾经写成 `rounds - miss`，那在 miss 多于 perfect 时会算出一个没有意义的数；现在 `good + perfect == rounds` 恒成立，`_case_summary_math()` 盯着这条。

`ending_overlay.gd` 读 `good/perfect/miss/rounds`。旧的 `keys/best_combo` 都已不存在，不要再按旧字段扩展界面。

---

## 计分（`ScoreBoard` + `ScoreLayer`）

分数只在 `scripts/core/score_board.gd` 里算，UI 层不许自己加数。

| 规则 | 数值 | 说明 |
|---|---|---|
| 完美命中 | 100 × 倍率 | `PERFECT_BASE` |
| 普通命中 | 45 × 倍率 | `GOOD_BASE` |
| 失手 | 0 | 不加分、不扣分，只清连击 |
| 连击倍率 | `1 + min(combo-1, 9) × 0.15` | 上限 ×2.35，`COMBO_CAP` 卡在 10 连 |
| 上鱼 | 底分 × 倍率 | small 120 / mid 180 / big 240 / doubao 60 / claude 400 |
| 全收 | +300 | `FULL_CATCH_BONUS` |
| 每条鱼剩的饵 | +40 | `PER_BAIT_BONUS` |
| 零失手 | +200 | `CLEAN_RUN_BONUS` |
| 难度系数 | 轻 0.8 / 普通 1.0 / 困难 1.3 | 只乘尾款，不乘单次命中 |

最高分存在 `user://record.json`（`ScoreBoard.PATH`），`finalize()` 读旧记录、破纪录才写盘，返回
`{score, bonus, scale, best_score, best_combo, new_record}`，由 `game_root._on_finished()` 塞进 summary。
同分不算新纪录。记录文件读坏按 0 处理，不拦启动。

界面侧只有两个 Label：
- 分数行（左上第二行）显示「得分 N   x4」，连击直接并进这一行；
- 飘字（画面中上）只报这一次的 `+130`，连击 ≥6 换成发烫的 `HOT_COLOR`。

连击早先单独占一个 Label，实际跑起来总是晚一帧才重绘、而且位置被上鱼演出压住。并进分数行之后就没这问题：
**连击是「此刻的状态」，飘字是「这一下的收益」，两件事不该抢同一块地方。**

`ScoreLayer` 在 `game_root._build_ui()` 里加在 `_landing` **之后**（结算层之前）：上鱼那一刻的 `+240`
必须压在上鱼演出上面才看得见。

---

## 数据文件一览

| 文件 | 内容 | 读取入口 | 改它会影响 |
|---|---|---|---|
| `data/fish.json` | 鱼名、立绘、体力、伤害比、张力率、台词 | `ConfigLoader.load_fish()` → `FishSpec` | 对局数值、HUD、结算收集项 |
| `data/tuning.json` | 全局数值、三档难度、距离带、豆包曲线、DDA | `ConfigLoader.load_tuning()` → `GameTuning` | 手感、难度、抽鱼概率 |
| `data/endings.json` | 结局标题/副标题/正文分页，`_order` 决定图鉴顺序 | `ConfigLoader.load_endings()` | 结算页、图鉴结局页 |
| `data/story.json` | 剧情脚本：`opening`（首次进游戏的开场）+ `ending_<key>`，每项含 `portrait`/`faces`/`pages[]` | `ConfigLoader.load_story()` | 首次进入的开场、结算前的剧情层 |
| `data/characters.json` | 角色名、形态、立绘、人设、口头禅、解锁条件 | `ConfigLoader.load_characters()` | 图鉴角色页 |
| `data/escapes.json` | 脱钩演出：key、认领的鱼、图、标题、台词、说明、语音 | `ConfigLoader.load_escapes()` | 对局内脱钩卡片、图鉴脱钩页 |
| `data/about.json` | 协议、出处分节、彩蛋图 | `ConfigLoader.read_json(PATH_ABOUT)` | 关于页 |
| `data/i18n/strings.csv` | 四语翻译表，中文原文当键 | Godot 导入为 `.translation` | 全界面 + 数据层文案 |

只有 `ConfigLoader` 打开这些文件。UI 里出现 `FileAccess` 或 `JSON.parse_string` 就是走错了路（`about_root.gd` 曾自己读 json，已收回）。

---

## 脱钩演出的单一真相源

脱钩卡片（对局内「她甩着尾巴跑了」那张）与图鉴的脱钩页曾经各写一份图片和文案：`game_root._escape_art_of()` 里堆 `fish.is_claude / fish.id == "big"` 分支，`gallery_root.ESCAPE_ITEMS` 里再抄一遍数组。改一句台词要动两个文件，加一条鱼要同时记得两处，而且直接违反「不在 UI 堆 fish.id 分支」。

现在只有 `data/escapes.json` 一份：

```json
{
  "key": "escape_big",
  "fish": ["big"],
  "image": "res://assets/deepseek_escape_big.webp",
  "title": "大肥鱼",
  "line": "「鲸鱼不是肥，是密度好。」",
  "sub": "她游走了",
  "voice": "escape"
}
```

- `ConfigLoader.load_escapes()` 读表并对 `title/line/sub` 过一次 `TranslationServer.translate()`。
- `ConfigLoader.escape_for(items, fish_id)` 按 `fish` 数组找条目，找不到返回 `{}`。
- `game_root._escape_art_of()` 只做字段改名（`tip = line`、`gain = sub`、`gallery = key`），没有 id 分支；没配的鱼退回纯文字提示，不会崩。
- `gallery_root` 直接用同一份 `_escapes` 渲染，条数跟着数据走。

`_case_escape_data()` 会验：四条都在、图存在、每条鱼都有演出、key 不重复、图鉴条数等于表条数、未知鱼返回空。

---

## 开场剧情（`opening`）

第一次进游戏时先演一段 32 句的开场：周末被大肥鱼和中肥鱼捞起来去钓鱼，中肥鱼抢着表现，自告奋勇下水赶鱼，一去不回；大肥鱼从保温袋里掏出一团小的（小肥鱼）扔下去捞姐姐，也没回来；最后她自己跳下水。玩家一个人在岸上吐槽半天，只好把三条鱼串一根线钓回来。

- 数据在 `data/story.json` 的 `opening`，和其它剧情同一套结构（`portrait` / `bg` / `pages[]`）。
- `pages[]` 的 `who` 白名单是 `""`（旁白）/`你`/`大肥鱼`/`中肥鱼`/`小肥鱼`；`你` 的台词是玩家人格的一部分，不是摄像头。
- `faces`：`who` → 立绘。`StoryOverlay._render()` 先看这一页有没有 `portrait`，没有才查 `faces`，再没有沿用上一页。只有一张整段立绘时，中肥鱼说「主人坐我这边」画面上却是大肥鱼，一眼出戏。
- 玩家自己说「你」的时候立绘压暗（`DIM_NARRATOR`），只有鱼说话时亮着。
- 触发在 `game_root._ready()`：`Gallery.queue_story("opening")` 排在 `_play_pending_story_on_boot()` 之前。去重靠 `Gallery` 自己（已播/已在队都不重复排），不要在别处再记一个「是否看过开场」。
- `ConfigLoader.load_story()` 会对 `pages[].who` 和 `pages[].text` 过 `TranslationServer.translate()` —— **`StoryOverlay` 直接往 Label 写字符串，不会自己 `tr()`**，所以漏进 `strings.csv` 的台词在任何语种下都是中文原句。
- `game_root._begin_story()` 是唯一入口：开播前 `_set_play_chrome(false)` 把 HUD 和右上角暂停键收起来，`finished` 时还原再调 `done`。开场是全屏叙事，顶上的白饭计数压在字上很出戏；直接 `_story.play()` 会绕过收 HUD。
- `_case_opening_story()` 锁死：`pages.size() == 32`、每句非空、`who` 在白名单、`你` 至少 5 句、最后一句是大肥鱼、三条鱼各有专属立绘且文件存在、切英文后每句都变样（缺翻译会列出缺哪几句）、`Gallery` 只排一次。`tests/screenshot.gd` 的第 6 步拍 `06_opening.png`，靠 `while ov._index < 3` 翻到第 4 句，不数点击次数。
- 三张整页 CG 挂在 13–30 句上：
  - `assets/opening_dive.webp` —— 中肥鱼说完就往水里走（第 13 句起）
  - `assets/opening_summon.webp` —— 大肥鱼从保温袋掏出小的、放进水里（第 20 句起）
  - `assets/opening_rod.webp` —— 把竿塞回你手里、自己下水（第 28 句起）
  - 第 26 句用 `"bg": "-"` 把 CG 撤掉，回到只用立绘的水面安静段，再进最后一张。
- `_case_opening_story()` 另外断言：三张 CG 都在、文件存在、带 `hide_face` 的句子 ≥ 15、`"-"` 出现在中段（撤图之后还能回到立绘）。

## 齐鱼之福的后半段（`ending_feast`）

`ending_feast` 现在是 35 句：前 9 句是三条鱼被钓上来的收尾，后 26 句是回小屋之后的「后续」。

- 触发走 `game_root` 的结局流程：`_play_one_story("ending_" + ending, ...)`，不用另外排队。
- 这段是全篇唯一带成人暗示的地方，写法是**留白**：你拉灯 → 黑暗里两声「鲸」→ 大肥鱼说「灯坏了」→ 后半夜水声才停 → 第二天「都吃饱了」。不写身体，画面交给玩家补。
- `faces` 三条鱼都配了（大/中/小各自的立绘），否则中肥鱼说话时还挂着大肥鱼的脸。
- `_case_feast_afterstory()` 锁死：`pages.size() == 35`、三条鱼各有立绘且文件存在、玩家至少 4 句台词、第 10 句以后必须出现「灯」和「吃饱」、逐句不含 `裸 / 性器 / 高潮 / 插入 / 湿透`、最后 7 句必须带 `hide_face` 且页级底图存在。
- 第二天那 7 句用整页 CG（`assets/ending_feast_after.webp`）：第一句写 `"bg"`，7 句都写 `"hide_face": true`。`StoryOverlay` 支持「整段没配 `bg` 时由页级 `bg` 把底图建出来」，所以不用给整段铺图；`hide_face` 是逐页字段，漏写哪页哪页就会把小人弹回来。

---

## 共用视觉件

背景与暂停层曾各抄一份：

- `menu_root` / `gallery_root` / `settings_root` / `about_root` 各自有一份逐字相同的 `_build_background()` + `_draw_background()`（`h * 0.62` 地平线、两层山、2px 水线）。
- `game_root._pause_game()` 内联搭 dim + 卡片 + 三个按钮，和「每个 overlay 一个独立脚本」的惯例不一致。

现在：

- `LakeBackdrop`（`scripts/ui/lake_backdrop.gd`）是背景的唯一实现，`add_child(LakeBackdrop.new())` 放到最底层即可。设置页切语言会整页重建，重建时也要重新挂一次。
- `PauseLayer`（`scripts/ui/pause_layer.gd`）自己管 `process_mode = WHEN_PAUSED` 和信号（`resumed` / `restarted` / `quit_requested`），`game_root` 只负责 `add_child`、接线和 `get_tree().paused = true`。

改背景配色只动 `LakeBackdrop` 与 `Palette`，不要再往页面里贴绘制代码。

---

## 难度档的字段表

`GameTuning.from_dict()` 与 `apply_difficulty()` 曾经各自抄一份「哪些字段要解析」的白名单，两边漂移之后，在 `tuning.json` 的某个难度档里写 `shadow_width`、`empty_wait`、`landing_timeout` 这类字段会被静默吃掉 —— 数据看着生效，实际仍是顶层默认值。

现在只有 `GameTuning.SCALAR_FIELDS` 一张表：`[字段名, 类型, 下限, 上限]` 的数组，两处都走 `_read_scalars()`。新增可被难度覆盖的标量字段，只在这里加一行。

`_case_tuning_scalar_coverage()` 把曾经漏掉的十一个字段一次性写进 easy 档并断言生效，还验了「没写的字段保持默认」和「`bite_delay_max` 不低于 `bite_delay_min`」。

---

## 文案与 i18n

- 界面字符串：`tr("…")`，中文原文当键。
- 数据层文案：`ConfigLoader` 加载时过 `TranslationServer.translate()`，所以 `fish.json` / `endings.json` / `characters.json` / `escapes.json` 里的中文都要在 `data/i18n/strings.csv` 有一行。
- **只改 JSON 不同步 CSV，等于只改了简中**：`tr()` 查不到键会原样返回中文，英/日/繁中界面会出现混排。2026-11 这次给小肥鱼换人设、给脱钩与暂停页加文案时都踩过。
- CSV 列序固定 `keys,zh_CN,zh_TW,en,ja`，`zh_CN` 通常就等于键。批量追加行时容易把繁体塞进 `zh_CN` 列，表现为「简中界面显示繁体」—— 加完随手扫一遍这两列是否相同。
- 加完 CSV 要重跑一次 `--import`，Godot 才会重新生成 `strings.*.translation`。

---

## 输入链路与鼠标策略

```text
鼠标左键 / 键盘
  └─ Viewport 输入与 GUI 链
       ├─ 被 mouse_filter == STOP 的非按钮 Control 接收
       │    → _unhandled_input 收不到，抛竿会“点了没反应”
       └─ 未被 GUI 消费
            └─ game_root._unhandled_input(event)
                 ├─ AIMING    → press() / release()
                 ├─ FIGHTING  → qte_strike()
                 └─ RESOLVING → press() 跳过等待
```

`game_root._apply_mouse_policy()` 在装配后递归处理：非 `BaseButton` 的 `Control` 设为 `MOUSE_FILTER_IGNORE`，按钮保留可点击行为。

运行时动态创建的结算内容只在 `ENDED` 出现，不参与抛竿输入。新增其他动态全屏层时，必须单独检查它是否会在需要点击穿透的阶段出现。

搏斗阶段把点击、空格、回车、`ui_accept` 和 `InputEventScreenTouch` 全部当作同一个「点一下」，忽略 `key.echo`，防止长按被当成连续多次输入。这是为了手机上单手拇指也能玩 —— 不需要方向键，也不需要第二根手指。

### 剧情层为什么不用 `_gui_input`

`story_overlay.gd` 最早用 `_gui_input` 收左键，结果是**点了完全没反应，只能按 Enter**：
对话框里全是 `Label`，`Label` 自己会吃掉落在它身上的鼠标事件，`_gui_input` 永远收不到。
改法是整个覆盖层不碰 `_gui_input`，全部在 `_input` 里按坐标判断：

```gdscript
func _input(event: InputEvent) -> void:
	# 只让「回看」「跳过」两个按钮自己去响应，其余位置一律当作推进
	for b in [_back_btn, _skip_btn]:
		if b != null and b.visible and b.get_global_rect().has_point(get_global_mouse_position()):
			return
	...
```

`_input` 早于 GUI 事件分发，所以不会被 Label 截胡；`_skip_btn` 因此从 `_build()` 里的局部变量提升成了成员。
新增可点区域时必须同时加进这个让位列表，否则点按钮会顺带翻页。

---

## 为什么这样划分

### `RefCounted` 而不是 `Node`

规则对象可以直接 `new()`，不需要场景树、生命周期回调或窗口。测试可以固定随机种子，连续构造多局且互不污染。

### 不用 autoload 单例

依赖通过构造函数显式传入。这样不会把配置、当前局、输入和 UI 全塞进一个全局对象，也能在测试中同时存在多个 session。

### 状态转移只走 `_set_phase()`

`phase_changed` 是 UI 切换表现的唯一依据。直接在其他位置赋值会让界面和规则处于不同阶段。

### RNG 可注入

`FishingSession` 和 `FightSession` 接受可选 `RandomNumberGenerator`。测试使用固定种子验证落点和序列；正常运行才自行随机化。

### 动画完成与规则推进分离

`FishingSession` 决定“已经上鱼”，`LandingView` 只决定“演出何时播完”。UI 调 `landing_done()` 推进；逻辑层保留 `landing_timeout`，避免无窗口或演出异常时永久停留在 `LANDING`。

---

## 上鱼动画的目标边界（尚未实现）

当前 `LandingView` 的整图 Tween 是占位实现。后续升级应保持对 `game_root` 的调用协议稳定，建议拆成三层职责：

| 建议职责 | 内容 | 禁止事项 |
|---|---|---|
| 演出编排 | 从浮标到前景的轨迹、水花、台词、总时长、完成信号 | 根据具体鱼 id 写动作分支 |
| 角色动画播放 | 播放该角色自己的姿态序列或部件动作 | 只拿 `portrait` 做整体移动 |
| 动画配置 | 帧资源、fps、关键帧、缩放、偏移、音效等 | 散落在 UI 常量中 |

`FishSpec` 未来只保存一个表现绑定标识；具体资源进入独立动画配置。这样小、中、大肥鱼以及非鱼类对象都能注册自己的动作，而无需改动 `FishingSession`。

这是目标结构，不代表相关类、字段或 JSON 文件已经存在。完整提案与验收标准见 [landing-animation.md](landing-animation.md)。

---

## 扩展点

### 加一条鱼

当前只改 `data/fish.json`，HUD、抛竿条和结算收集项自动适配。**距离带要另外加**：在三档 `difficulties.*.zones` 里各加一条，必须覆盖全部鱼，否则回退自动分带。

想让它有自己的脱钩演出，再往 `data/escapes.json` 加一条（`fish` 里写上 id，图与台词一起给），并在 `strings.csv` 补四语；不加也能跑，只是脱钩时显示纯文字提示。

加专属上鱼动画目前还不能只靠 JSON；应先完成上述演出系统，再按动画设计文档注册资源。

### 加一条陷阱鱼

`data/fish.json` 里给某条鱼加 `"claude": true`，它就是陷阱：

- `FishingSession` 把它排除在 `_targets` 之外，`fish_total()` 只数收集目标
- HUD 的进度 chips 与结算的收集列表都不会出现它（`game_root._targets` 与 `EndingOverlay` 都不含它）
- 但它**参与距离带划分**，所以能咬钩
- 一旦钓上来，`_advance_after_round()` 第一件事就是 `_finish("claude")`，压过「集齐」和「没饵」两条判断

当前实现里陷阱藏在远洋带的最后一小截，`Palette.zone_color` 让它与大鱼同色，`CastBar` 合并同色相邻带消除接缝 —— 玩家看不出那里还有东西。细节见 [tuning.md](tuning.md#陷阱带)。

### 加一种结局

1. 在 `data/endings.json` 增加 key 与文案。
2. 把它写进 `endings.json` 的 `_order`（图鉴顺序，漏了会排到最后）。
3. 在 `FishingSession` 增加明确的结局判定分支。
4. 补充逻辑测试。
5. 检查 `EndingOverlay` 的通用布局是否能容纳内容。

### 加新规则

1. 数值进入 `data/tuning.json`，提供默认值。
2. 规则进入 `core/`。
3. 信号登记到本文。
4. 表现进入独立 UI 文件，`game_root` 只负责装配。
5. 添加无窗口逻辑测试；涉及真实输入或布局时另做窗口验证。

---

## 测试边界

- `selftest.gd`：当前覆盖配置、脱钩演出表、难度字段全覆盖、结算统计口径、中心偏向抽签、小肥鱼人设、开场剧情（32 句 / 说话人白名单 / 每条鱼一张脸 / 四语覆盖 / 队列只排一次）、齐鱼之福后半段、计分板（底分、倍率、失手清零、尾款、最高分落盘与同分不算新纪录）、剧情层点击与触屏推进（含按钮让位）、自动分带、加鱼、难度档、设置读写、菜单装配、圆环判定、冷却窗口、循环蓄力、抛竿、空竿、重复上鱼、上鱼、断线、五种结局、场景装配和鼠标策略。基线：`[selftest] pass=1093 fail=0`。
- `screenshot.gd`：输出瞄准、蓄力、搏斗、上鱼、结算、开场、齐鱼之福后续、开场三张 CG、计分行共十一张快照。它验证可见布局，不证明角色动画达标。
  **注意 `_shot()` 抓的是上一帧纹理**：同一帧里先改 UI 再 `_shot()` 是拍不到的，计分那张图因此单独占了一个 `_step = 45`，隔一帧再拍。
- `input_probe.gd`：仍是旧版探针，未接入当前验收口径。

动画完成后还需要连续帧或短视频验证，单张 `04_landing.png` 只能检查某一帧的构图，不能证明姿态真的随时间变化。
