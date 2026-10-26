# 架构说明

## 分层

```text
┌──────────────────────────────────────────────────────────────┐
│ data/*.json           数值、文案、立绘和结局路径              │
└──────────────────────────────┬───────────────────────────────┘
                               │ 只有 ConfigLoader 读取
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ scripts/core/         纯规则层（RefCounted，无场景树依赖）     │
│                                                              │
│ FishSpec          单个目标的静态配置                          │
│ GameTuning        全局数值、难度档、可重叠距离带、加权抽鱼      │
│ GameSettings      玩家偏好（难度），读写 user://settings.json  │
│ FightSession      单场圆环搏斗                              │
│ FishingSession    一局状态机、收集、结局与统计                 │
└──────────────────────────────┬───────────────────────────────┘
                               │ 信号与只读快照
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ scripts/ui/           表现层                                  │
│                                                              │
│ menu_root         主菜单 + 难度选择（游戏入口）                │
│ game_root         装配、输入路由、阶段切换                     │
│ lake_view         湖面、浮标、鱼线、水花、鱼影                 │
│ qte_overlay       圆环判定和资源细条                        │
│ landing_view      上鱼演出（当前为静态图占位）                 │
│ 其他视图          HUD、抛竿、短提示、结局                      │
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
| `core/config_loader.gd` | JSON 读取、结构校验、兜底 | 保存一局运行时状态 |
| `ui/menu_root.gd` | 主菜单、难度选择、写入 settings、切到 `main.tscn` | 任何游戏规则 |
| `ui/game_root.gd` | 装配、输入转发、信号连接、阶段显示 | 计算伤害、张力或结局 |
| `ui/lake_view.gd` | 场景绘制和浮标挣扎表现 | 决定何时上鱼 |
| `ui/qte_overlay.gd` | 订阅搏斗信号并绘制反馈 | 修改序列或判定输入 |
| `ui/scene_feedback.gd` | 空竿、断线短提示 | 决定提示对应的结果 |
| `ui/landing_view.gd` | 播放上鱼演出并回报完成 | 记录收集、决定下一阶段 |
| `ui/ending_overlay.gd` | 显示结局、统计和收集项 | 生成统计或判断结局 |
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
            ├─ _weighted_pick(候选池)                → 按 weight 抽一条
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

`summary()` 还包含 `bait_total/bait_left/bait_used`、`caught/caught_count/fish_total`、`landed`（上鱼总次数，可重复）、`good`（= `rounds - miss`）、`claude_caught`。

`ending_overlay.gd` 读 `good/perfect/miss/rounds`。旧的 `keys/best_combo` 都已不存在，不要再按旧字段扩展界面。

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
2. 在 `FishingSession` 增加明确的结局判定分支。
3. 补充逻辑测试。
4. 检查 `EndingOverlay` 的通用布局是否能容纳内容。

### 加新规则

1. 数值进入 `data/tuning.json`，提供默认值。
2. 规则进入 `core/`。
3. 信号登记到本文。
4. 表现进入独立 UI 文件，`game_root` 只负责装配。
5. 添加无窗口逻辑测试；涉及真实输入或布局时另做窗口验证。

---

## 测试边界

- `selftest.gd`：当前覆盖配置、自动分带、加鱼、难度档、设置读写、菜单装配、圆环判定、冷却窗口、循环蓄力、抛竿、空竿、重复上鱼、上鱼、断线、五种结局、场景装配和鼠标策略。
- `screenshot.gd`：输出瞄准、蓄力、搏斗、上鱼、结算五张快照。它验证可见布局，不证明角色动画达标。
- `input_probe.gd`：仍是旧版探针，未接入当前验收口径。

动画完成后还需要连续帧或短视频验证，单张 `04_landing.png` 只能检查某一帧的构图，不能证明姿态真的随时间变化。
