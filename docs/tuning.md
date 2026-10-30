# 调参手册

当前数值位于 `data/fish.json` 和 `data/tuning.json`。本文描述 **单键圆环版本**；方向序列、`sequence_len`、`seq_max_extra`、`key_relief`、`input_lock` 都已随序列机制一起删除。

---

## 三个核心公式

### 1. 完成一场搏斗需要几轮

```text
完整轮数 = ceil(1 / fish.damage_ratio)
每轮伤害 = fish.stamina × fish.damage_ratio
```

| 目标 | `damage_ratio` | 完整轮数 |
|---|---:|---:|
| 小肥鱼 | 0.25 | 4 |
| 中肥鱼 | 0.20 | 5 |
| 大肥鱼 | 0.20 | 5 |
| 陷阱 | 0.15 | 7 |

`stamina` 决定体力上限和每条鱼的绝对数值，每命中一次按上限比例扣减。因此改变 `stamina` 本身不会改变理论轮数；要调长短，优先改 `damage_ratio`。

### 2. 游标每秒转多少圈

```text
speed = fight.cursor_speed
      × [1 + (1 - stamina_ratio) × fight.cursor_accel]

本帧推进：cursor = fposmod(cursor + speed × delta, 1.0)
```

`cursor` 是归一化的环形位置，0 在正上方，顺时针增加，绕满一圈回零。体力越低转得越快 —— 最后一段最紧，这是「末段难度」的来源之一；另一部分来自难度档直接覆盖的 `cursor_speed`。

### 2b. 判定：环形距离

```text
d = min(|cursor|, 1 - |cursor|)     # 到顶部 0 的最近距离

d ≤ fight.perfect_half   → 完美（削一轮 + round_relief + perfect_relief）
d ≤ fight.hit_half       → 命中（削一轮 + round_relief）
否则                      → 失手（tension += miss_tension，不算轮次）
```

`hit_half` 就是那块黄标的半宽：黄到哪，判到哪。`perfect_half` 只看不画。

按**环形距离**算，不是「游标在顶部附近」的近似 —— 游标从 359° 滑到 1° 是连续的，不会因为跨过 0 而漏判。

### 3. 张力每秒增长

```text
rate = fight.tension_passive_rate
     × fish.tension_rate
     × [1 + (1 - stamina_ratio) × fight.rage_tension_bonus]

本帧增长：tension += rate × delta
```

另外还有三个离散变化：

- 命中一次：`tension -= fight.round_relief`
- 完美命中：再 `tension -= fight.perfect_relief`
- 失手一次：`tension += fight.miss_tension`，不算轮次

张力始终限制在 `0 ~ tension_max`。达到上限立即断线。

---

## `fish.json`

| 字段 | 类型 | 当前含义 | 建议范围 / 约束 |
|---|---|---|---|
| `id` | string | 唯一标识，距离带和收集按它对应 | 短英文；已有 id 不随意改 |
| `name` | string | 显示名 | 注意长名字的布局 |
| `portrait` | string | 当前立绘路径 | `res://assets/...` |
| `tint` | hex | 立绘叠色 | `#ffffff` 为原色 |
| `stamina` | float | 体力上限 | 大于 0；当前建议 80–300 |
| `damage_ratio` | float | 每命中一次削减的体力比例 | 代码限制 0.02–1.0；建议 0.10–0.30 |
| `tension_rate` | float | 该鱼的张力增长倍率 | 最低 0.1；建议 0.7–1.4 |
| `tagline` | string | 上鱼演出台词 | 短句 |
| `blurb` | string | 图鉴或介绍文案 | 当前结算页未直接使用 |

`FishSpec.rounds_needed()` 是理论命中次数，不包含失手或等待造成的额外耗时。

### 当前角色数值

| id | stamina | damage_ratio | tension_rate | 完整轮数 |
|---|---:|---:|---:|---:|
| `small` | 100 | 0.25 | 0.85 | 4 |
| `mid` | 140 | 0.20 | 1.00 | 5 |
| `big` | 190 | 0.20 | 1.00 | 5 |
| `claude` | 320 | 0.15 | 1.10 | 7 |

---

## `tuning.json`：一局与抛竿

| 字段 | 当前值 | 含义 |
|---|---:|---|
| `bait_count` | 5 | 总抛竿次数；蓄力循环不扣饵 |
| `full_catch_threshold` | 3 | 饵用完时上鱼次数达到该值判 `full`，否则 `hungry` |
| `charge_full_seconds` | 1.6 | 从 0 到 100 一圈的秒数，随后继续从 0 循环 |
| `cast_jitter` | 1.5 | 实际落点的随机误差 ± |
| `bite_delay_min` | 0.8 | 有效抛竿后的最短等待 |
| `bite_delay_max` | 1.7 | 有效抛竿后的最长等待，不低于最小值 |
| `empty_wait` | 1.1 | 空竿的等待时长 |
| `resolve_hold` | 2.0 | 失败提示阶段的停留时间；0.35 秒后可点击跳过 |
| `landing_timeout` | 3.2 | 上鱼演出的逻辑兜底时长 |
| `zones` | 不写 | 顶层不写距离带；分带归难度管，见下节 |
| `doubao_refund` | 2 | 捞到豆包返还的白饭碗数（含刚抛出去的那碗）；结果会被 `bait_max` 截断，最低 1 |
| `difficulties` | 三档 | `easy` / `normal` / `hard`，各自覆盖想改的键 |

`landing_timeout` 不是正常动画必须播满的时长。UI 播完会主动调用 `landing_done()`；只有演出没有正确回报时，逻辑层才等超时兜底。正式角色动画接入后，兜底应略长于最长正常演出，但不应长到出错后像卡死。

### 难度档

`GameTuning.apply_difficulty(key)` 把选中的那一档**叠在顶层之上**：只覆盖它显式写了的键，其余继续用顶层值。未知 key 落回 `normal`，不报错 —— 玩家改坏 `settings.json` 不该让游戏起不来。

| 键 | easy | normal | hard |
|---|---:|---:|---:|
| `bait_count` | 7 | 4 | 3 |
| `charge_full_seconds` | 2.1 | 1.5 | 1.15 |
| `cast_jitter` | 3.0 | 1.2 | 0.6 |
| `fake_claude_chance` | 0.90 | 0.70 | 0.40 |
| `fight.miss_tension` | 8 | 16 | 22 |
| `fight.tension_passive_rate` | 6 | 8 | 11 |
| `fight.round_relief` | 7 | 5 | 3 |
| `fight.hit_half` | 0.32（230°） | 0.20（144°） | 0.14（100°） |
| `fight.cursor_speed` | 0.30 | 0.52 | 0.70 |
| `fight.cursor_accel` | 0.3 | 0.6 | 0.9 |
| `fight.hit_sway` | 0 | 0.07 | 0.18 |

三档的差距铺在四个维度上，任意一个单独看都不足以拉开难度，叠起来才成梯度：

- **黄标宽度** 230° → 144° → 100°，肉眼可见地收窄。
- **游标速度** 0.30 → 0.52 → 0.70 圈/秒，一圈 3.3 秒 → 1.9 秒 → 1.4 秒。
- **张力自然上涨** 6 → 8 → 11。这是难度的主干：拖得越久越危险，不靠反应速度硬卡人。
- **打完一轮的回血** 7 → 5 → 3。轻松档打中就能喘口气，困难档打中了也几乎压不住 —— 必须连着打中才活。

`normal` 开始加爆冲（±0.07，2.4 秒一个来回），`hard` 摆到 ±0.18、1.5 秒一个来回，**黄标会整块挪出去一个半身位**，得追着标打。**判定和画面共用 `FightSession.hit_center()`**，所以不存在「看着在标里却判失手」。

`hard` 的饵只有三碗，正好等于 `full_catch_threshold` —— 三次全中才够「吃饱饱」，一次失误就只能走「没吃饱」。这是有意的：困难档不留容错余量。

难度是**唯一**的玩家设置，存 `user://settings.json`，由 `GameSettings` 读写。

### 距离带：可重叠，无空档

距离带不是「一人一块地」。每条鱼在 0~100 上有一段区间，**区间之间允许重叠**，整条 0~100 **必须被覆盖**，不留空档。

```text
抛到 p → 找出所有覆盖 p 的带 → 去掉已经钓到的鱼 → 按 weight 加权随机抽一条
```

这么设计的理由：

- **容错靠重叠**。抛偏一点不会直接空竿，而是钓到隔壁那条 —— 玩家永远有反馈，不会对着一个没有提示的空洞发呆。
- **难度靠收窄**。`hard` 把每条鱼的区间收窄，重叠只剩 4~6，想钓特定的鱼必须抛得准；`easy` 区间宽、重叠大，随手一抛都有收获。
- **无空档是硬要求**。空档在界面上不可见（本作不画分区），落在上面玩家只会觉得「游戏坏了」。

自动分带（`tuning.json` 不写 zones 时）：

```text
鱼按 stamina 升序排列，等分成 n 份
每带向前后各撑开 AUTO_OVERLAP/2 = 4
第一带起点强制 0.0，最后一带终点强制 100.0
```

所以相邻带天然重叠 8。手动配置必须覆盖全部鱼，缺任何一条都会报警并回退到自动分带，避免新增角色永远无法咬钩。

难度里的 `zones` 示例（`normal`）：

```json
"zones": [
  { "id": "z_small",  "fish": "small",  "from": 0,  "to": 44,  "weight": 3 },
  { "id": "z_mid",    "fish": "mid",    "from": 30, "to": 70,  "weight": 2 },
  { "id": "z_big",    "fish": "big",    "from": 58, "to": 92,  "weight": 2 },
  { "id": "z_claude", "fish": "claude", "from": 84, "to": 100, "weight": 1 },
  { "id": "z_doubao", "fish": "doubao", "from": 0,  "to": 70,  "weight": 1.0 }
]
```

30~44 是 small 与 mid 的重叠，58~70 是 mid 与 big 的，84~92 是 big 与 claude 的。`weight` 是同一落点上被抽中的相对权重。

`z_doubao` 的 `weight` **已经不参与抽签了**，写多少都行。豆包的真实概率来自顶层的正态曲线：

| 键 | 默认 | 含义 |
|---|---|---|
| `doubao_peak_center` | 28 | 峰值落在 0~100 的哪一格 |
| `doubao_peak_chance` | 0.4 | 峰值处的基础概率；三档难度各自覆盖（`easy` 0.3 / `normal` 0.4 / `hard` 0.5） |
| `doubao_peak_sigma` | 18 | 标准差。离峰 18 格掉到 61%，36 格掉到 13% |

`z_doubao` 的 `from` / `to` 现在只划定「它可能在哪一段被撞见」，所以给到 0~70 把整条曲线的有效区间都罩住。它**不在 `_covers_all` 的必需清单里**（豆包不参与收集），但一旦显式写进 zones 就必须给它一条带，否则自动分带的兜底会把它弄丢。`auto_zones` 本身也只给非豆包鱼分带。

### 陷阱鱼怎么藏

`claude` 与 `big` 在 84~92 重叠，玩家抛进那一段时有概率撞上她 —— **这就是全部提示**。

界面上还有三处刻意为之：

- `CastBar` **不画分区**，只画一条槽和一块随游标滑动的牌子，牌子上写「近岸/中段/远洋水域」，不写鱼名。
- `Palette.zone_color("claude")` 仍返回 `ZONE_BIG`，尽管目前没有任何地方用它画分区（保留是因为结界面、HUD 等处可能引用）。
- `_aim_label` 只报状态（按住蓄力 / 松手抛竿），不报瞄准了谁。

玩家知道「往远处抛有东西」，但不知道那一段到底是谁。

### 豆包怎么给

豆包不是「藏起来的鱼」，是**一份额外的容错**。它和收集完全脱钩：

- `damage_ratio: 1.0` —— 一次命中就捞上来，不用打完七下，也不用担心断线。
- 捞上来后 `_landed` 不加、`_caught` 不追加，所以**不算上鱼次数、不进收集、不触发任何结局**。
- 只做一件事：`bait_left = min(bait_left + doubao_refund, bait_max)`，然后发 `doubao_started(refund)` 给 UI 飘卡片。

因为要撞上限，饵满时捞到它等于「把刚花掉的那碗还回来」，饵见底时才是两碗的真实收益。想让救命感更强就调高 `doubao_refund`（比如 3）；想让它更少见就压低 `doubao_peak_chance`，想让它只在中段出没就收窄 `doubao_peak_sigma`。

它还有个饥荒加成：饵剩到 `doubao_mercy_bait`（默认 2）碗以内、且还没集齐，概率乘 `doubao_mercy_gain`（默认 2.4）；集齐三条之后归零。

---

## `tuning.json`：`fight` 段

| 字段 | 当前值 | 含义 | 调整建议 |
|---|---:|---|---|
| `tension_max` | 100.0 | 张力上限 | 通常保持 100，便于读百分比 |
| `tension_passive_rate` | 7.0 | 每秒基础增长 | 难度主旋钮之一 |
| `round_relief` | 6.0 | 命中一次降低的张力 | 提高可奖励持续推进 |
| `perfect_relief` | 3.0 | 完美命中额外降低的张力 | 提高让「卡点准」更值钱 |
| `miss_tension` | 14.0 | 每次失手立即增加的张力 | 过高会让少数失误直接断线 |
| `rage_tension_bonus` | 0.6 | 体力接近空时最多额外增加 60% 基础速率 | 控制末段压力 |
| `hit_half` | 0.22 | 黄标半宽（归一化） | 三档覆盖：easy 0.32 / normal 0.20 / hard 0.14。**不许低于 0.14**（约 100°），否则手机上点不准 |
| `perfect_half` | 0.09 | 完美区半宽 | 必须 ≤ `hit_half`；只影响判定，不画出来 |
| `cursor_speed` | 0.50 | 游标每秒转几圈 | 三档覆盖：easy 0.30 / normal 0.52 / hard 0.70。0.52 ≈ 1.9 秒一圈；0.70 已经开始考反应 |
| `hit_sway` | 0 | 黄标左右摆动的幅度 | 0 = 钉在顶部。normal 0.06 轻微晃，hard 0.13 整块标挪出去一个身位 —— 这就是鱼在爆冲 |
| `sway_period` | 2.2 | 摆动一个来回几秒 | 越小越急。hard 用 1.9 |
| `cursor_accel` | 0.5 | 体力见底时游标额外加速的比例 | 0 = 全程匀速；0.8 以上末段会很难 |
| `strike_lock` | 0.3 | 每次点完锁输入的秒数 | 低于 0.2 手快的人会连点误触 |

### 环上只有一块黄标

`QteOverlay` 只画三样东西：一圈细白轨道、一段黄色命中弧、黄标两端的刀口。

早先的版本在黄标外面还套了一层更宽的浅绿弧，结果玩家把金色内圈当成判定区，按在绿区里也算中，反馈是「明明在区间外还是扣了体力」—— 其实扣的是体力，只是玩家量错了边界。**所以现在只留一层**，黄到哪就是判到哪。

`perfect_half` 仍然生效（正中命中多减 `perfect_relief` 张力），但故意不画。画了就又变成两层，玩家会去追那条窄弧，不敢按。

### 黄标宽度与游标速度都吃难度

这两项由 `difficulties.*.fight` 覆盖，是环上唯一能读出难度差别的地方：

| 难度 | `hit_half` | 弧长 | `cursor_speed` | 一圈用时 |
|---|---:|---:|---:|---:|
| `easy` | 0.32 | 230° | 0.30 | 3.3 s |
| `normal` | 0.20 | 144° | 0.52 | 1.9 s |
| `hard` | 0.14 | 100° | 0.70 | 1.4 s |

`hard` 的黄标只剩三分之一圆，游标还比 `easy` 快七成。

改动这两项时要同时过一遍：`hit_half` 不得低于 0.14；三档的 `hit_half`/`cursor_speed` 组合不得重复（`selftest.gd` 的 `_case_difficulty_affects_game` 会拦）。

### `fight.strike_lock`

每次命中或失手后，`FightSession` 把 `_input_lock` 置为这个值，`strike()` 在锁定期内直接返回空字符串 —— **不判定、不记 miss、不涨张力、不算轮次**。

为什么必须有这个窗口：手机上连点两下是很常见的误触，没有冷却的话第二下必然落在「刚好离开判定区」的位置，白吃一次 `miss_tension`，而玩家完全不知道自己错在哪。

锁定期间 `QteOverlay` 会把游标压暗、中心提示改成「等」，让玩家看得出来现在按下去不算数。

### 游标为什么从随机位置起步

`start()` 里 `cursor = rng.randf()`。如果每次都从顶部起手，玩家数好节拍就能闭眼满分 —— 那不是节奏感，那是背板。随机起点逼玩家真的去看。

---

## 常见调整场景

### 太难，经常断线

按顺序小步调整，每次只改一组：

1. `tension_passive_rate` 降 10%–15%。
2. `miss_tension` 从 14 降到 11–12。
3. `rage_tension_bonus` 略降。
4. 提高 `damage_ratio` 减少所需命中次数。
5. 若是整局容错不足，再增加 `bait_count`。

不要靠缩 `hit_half` 来「平衡」—— 那只会让手机上更难点，难度没变，手感更差。

### 太简单，没有压力

1. 提高 `tension_passive_rate` 或对应鱼的 `tension_rate`。
2. 降低 `damage_ratio` 增加所需命中次数。
3. 提高 `cursor_speed` 或 `cursor_accel`，让游标转得更快。

不要重新引入方向序列或第二根操作条。

### 搏斗太短或太长

- 主要改 `damage_ratio`：直接改变命中次数。
- 辅助改 `cursor_speed`：转速影响每次命中的实际耗时。
- 同时检查张力曲线，避免加长后只是让玩家必然断线。

### 抛竿总是空

1. 先确认 `zones` 是否漏了鱼 —— 缺鱼会回退自动分带，但手写的洞不会自动补。
2. 检查是否有带没覆盖到的落点区间（`tests/selftest.gd` 的 `_has_no_gap` 就是干这个的）。
3. 想更好控，调大 `charge_full_seconds`，不是调小 `cast_jitter`。

`AUTO_OVERLAP` 是 `GameTuning` 里的代码常量（自动分带时相邻带的重叠宽度，当前 8），不是 JSON 字段；改它属于规则改动，需要同步测试。

### 上鱼演出被截断或卡住

- 被截断：确认正常演出总时长是否超过 `landing_timeout`。
- 卡住：检查播放器是否发出完成信号，以及 `game_root` 是否调用 `landing_done()`。
- 不要简单把超时改成极大值，那会把完成信号缺失伪装成“动画特别长”。

---

## 数值之间的耦合

| 修改 | 连带影响 |
|---|---|
| `damage_ratio` | 完整轮数、张力累计时间 |
| `cursor_speed` / `cursor_accel` | 每次命中的实际耗时、末段压力 |
| `tension_passive_rate` | 玩家可用于等准头的时间 |
| `round_relief` / `perfect_relief` | 准确玩家的生存余量 |
| `miss_tension` | 错误容忍次数 |
| `hit_half` | 手机可点性；**不要当难度旋钮用** |
| `bait_count` | 整局容错与 `full_catch_threshold` 的合理性 |
| `difficulties.*` | 覆盖顶层同名键；不写就继承顶层，写错 key 会被静默忽略 |
| 增加鱼数量 | 自动分带变窄、总流程变长、相对容错减少 |
| 增加正式动画时长 | `landing_timeout`、整局节奏、连续上鱼时的等待感 |

---

## 调参后的验证

1. 跑 `tests/selftest.gd`，确认配置、圆环判定、循环蓄力、上鱼和结局仍通过。
2. 用固定种子检查游标起点，不把某一次随机结果当作普遍难度。
3. 至少实际游玩一次，观察「准但慢」的玩家是否仍有生存路径。
4. 改动 UI 或演出后跑 `tests/screenshot.gd`，查看五个阶段。
5. 正式角色动画还需连续播放检查；截图不能替代动作验收。
