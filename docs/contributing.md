# 开发规范

目标：接手者能快速定位规则、表现和配置，新增内容时不需要读懂整个项目，也不把旧机制重新混回来。

---

## 修改前先定位

1. **规则还是表现？** 规则进 `scripts/core/`，表现进 `scripts/ui/`。
2. **数值还是逻辑？** 可调数值进 `data/*.json`，分支和状态推进才写 `.gd`。
3. **当前机制还是历史残留？** 当前搏斗只有单键圆环；方向序列、连击、换串截断均已删除。
4. **已实现还是目标设计？** 角色上鱼动画目前只有设计文档，静态立绘 Tween 仍是占位。

---

## 硬性规矩

### 1. 规则层不依赖场景树

`FishSpec`、`GameTuning`、`FightSession`、`FishingSession` 保持 `RefCounted`。不得在这些文件中使用：

```gdscript
extends Node
add_child()
get_tree()
Input.is_*
FileAccess
await
```

`ConfigLoader` 是配置读取例外；`FishSpec` 只用 `ResourceLoader.exists()` 校验资源路径。输入由 `game_root` 转成明确的方法调用。

### 2. UI 不判断输赢

```gdscript
# 错：UI 自己决定结局
if _caught.size() >= 3:
    _show_ending("win")

# 对：UI 订阅规则结果
_session.finished.connect(_on_finished)
```

UI 不直接扣体力、加张力、推进 `round_index`、修改收集数组或决定结局。需要新规则时，在 core 增加接口和测试，而不是把判断塞进绘制代码。

### 3. 阶段只走 `_set_phase()`

```gdscript
# 错
phase = Phase.FIGHTING

# 对
_set_phase(Phase.FIGHTING)
```

`phase_changed` 是界面切换的唯一依据。`LANDING` 的结束只通过 `landing_done()` 或逻辑超时推进，UI 不直接把阶段改回 `AIMING`。

### 4. 输入职责不能混

- `AIMING`：空格或左键的按下、松开映射到 `press()` / `release()`。
- `FIGHTING`：点击、空格、回车、触摸都映射到 `qte_strike()`。
- `RESOLVING`：主键只用于跳过提示。
- 搏斗忽略键盘 `echo`，不把长按当成连续按键。
- 不把鼠标点击或抛竿条重新接入搏斗判定。

### 5. 配置字段必须有默认值

```gdscript
var new_field: float = maxf(float(src.get("new_field", 5.0)), 0.1)
```

手改 JSON 漏字段不能导致崩溃。新增字段还要同步 `docs/tuning.md`，并说明当前值、单位和合理范围。

### 6. 颜色字号集中管理

新视图使用 `Palette` 和 `UIKit`。不要在多个文件复制同一组颜色、字号或卡片样式；确有新视觉需求时，先增加集中常量或通用工厂。

### 7. 非按钮 Control 不得吞掉抛竿点击

`game_root._apply_mouse_policy()` 会在初始装配后把非按钮 `Control` 设为 `MOUSE_FILTER_IGNORE`。

- 初始视图应在 `_build_ui()` 期间挂到树上。
- 运行时新建的视图要单独检查鼠标策略。
- 新增全屏层后运行 `_case_mouse_policy()`。
- 真实输入修改还要更新并运行窗口输入探针，不能只靠场景断言。

---

## 增加一个钓鱼目标

当前配置示例：

```json
{
  "id": "huge",
  "name": "超大肥鱼",
  "portrait": "res://assets/portrait_big.jpg",
  "tint": "#ffffff",
  "stamina": 260.0,
  "damage_ratio": 0.13,
  "tension_rate": 1.25,
  "tagline": "「你确定？」",
  "blurb": "远洋再往外的家伙。"
}
```

检查清单：

- [ ] `id` 唯一，距离带和收集都使用同一个 id。
- [ ] `portrait` 指向实际存在并已导入的资源。
- [ ] `damage_ratio` 对应合理命中次数，建议保持在 3–8 次内（陷阱 7 次，豆包 1 次是特例）。
- [ ] 三档 `difficulties.*.bait_count` 都提供足够容错。
- [ ] 三档 `difficulties.*.bait_count` 与 `full_catch_threshold` 匹配新目标数量。
- [ ] 三档 `difficulties.*.zones` 都覆盖这个新 id；漏了会静默回退自动分带。
- [ ] `zones` 本身不留空档（`_has_no_gap()` 会验），且与相邻带确有重叠。
- [ ] 特殊鱼要显式声明标记：陷阱 `"claude": true`、豆包 `"doubao": true`，两者都不进收集目标，也都不参与 `auto_zones`。
- [ ] 豆包这类「只给好处」的鱼必须给一条低 `weight` 的窄带，否则显式 zones 会因为缺带而回退自动分带。
- [ ] 新增角色需要的上鱼动作已按动画规范注册，而不是只换 `portrait`。

现有 `_case_extension_add_fish()` 只验证“加鱼能无空档分带和开局”，不验证整局难度，也不验证动画资源。

---

## 角色上鱼动画开发约定

正式实现前先读 [landing-animation.md](landing-animation.md)。以下要求用于防止再次把“图片在动”误当成“角色在动”。

### 必须保持的边界

- `FishingSession` 只负责判定上鱼和进入 `LANDING`。
- `game_root` 只负责把 `FishSpec` 与浮标位置交给演出层，并转发完成信号。
- 演出编排器负责轨迹、场景效果和总流程。
- 角色播放器负责姿态序列或部件动作。
- 角色资源按独立标识注册，不在 UI 中堆 `if fish.id` 分支。

### 完成标准

- 角色自身至少有多个可辨识姿态，不是同一纹理的变换。
- 能看清破水、腾空扑近和到达前景的动作关系。
- 使用透明背景资源或真正的部件动画，不保留 JPG 矩形边界。
- 不同档次角色可以绑定不同片段；缺资源时走明确降级并报警。
- 完成信号只发一次，连续重开不会重复连接或推进两次。
- 逻辑超时仍然有效，但正常演出不会被超时截断。

只改 `FLIGHT_SECONDS`、缩放曲线或旋转幅度，不算完成角色动画任务。

---

## 新增视图

1. 新建 `scripts/ui/xxx_view.gd`。
2. 提供清晰的装配和绑定接口；绑定搏斗等临时对象时同时提供 `unbind()`。
3. 在 `game_root._build_ui()` 中实例化。
4. 在 `_on_phase_changed()` 只控制显示与表现参数。
5. 连接信号时确保重开、换场和释放不会留下旧连接。
6. 检查 `mouse_filter`、不同窗口尺寸和最长文案。

`QteOverlay.bind()/unbind()` 是当前临时搏斗视图的参考，不要再引用已归档的 `fight_panel.gd`。

---

## 新增规则

按完整链路修改：

1. **配置**：字段、默认值、单位。
2. **规则**：放入对应 session 或新的 core 对象。
3. **信号**：需要 UI 响应时定义清楚参数和触发顺序。
4. **表现**：新建独立视图，避免继续膨胀 `game_root`。
5. **装配**：输入和信号只在一个明确位置连接。
6. **测试**：固定随机种子，覆盖成功、失败和边界。
7. **文档**：同步架构信号表、调参字段和设计约束。

---

## 代码风格

- 缩进使用 Tab。
- 函数参数和返回值尽量标注类型。
- 私有成员使用 `_` 前缀。
- 常量使用大写蛇形命名。
- 标识符使用英文；面向玩家的文本和解释性注释可用中文。
- 注释解释“为什么”，不要复述下一行代码。
- 配置缺失使用默认值和必要警告，不静默产出错误规则。
- 不用无上下文的魔法字符串；结果和阶段使用已有常量或枚举。

---

## 测试

### 无窗口自测

```powershell
& $GodotConsole `
    --headless --path . --script "res://tests/selftest.gd"
```

期望最后一行：`[selftest] pass=N fail=0`。不要只写“全绿”，交接时记录实际数字。

当前用例覆盖：配置、自动分带、无空档校验、加鱼、难度档、设置读写、菜单装配、圆环判定、冷却窗口、循环蓄力、抛竿、空竿、重复上鱼、上鱼、断线、五种结局、假陷阱、豆包返还、结局图鉴、场景装配和鼠标策略。

### 添加逻辑测试

在 `tests/selftest.gd` 增加 `_case_xxx()` 并注册到 `_run_all()`。使用 `_check()` 或 `_ok()`，通过固定 `RandomNumberGenerator.seed` 消除随机波动。

搏斗测试直接设 `f.cursor = 0.0` 然后 `session.qte_strike()` 拿到命中，或设 `f.cursor = 0.5` 拿到失手。点完记得 `tick()` 过冷却窗口，否则后续点击会被 `strike_lock` 挡掉。不要恢复 `input(dir)` 或 `perfect/good` 断言。

### 视觉快照

```powershell
& $GodotConsole `
    --path . --script "res://tests/screenshot.gd" --resolution 1280x800
```

输出五张图：瞄准、蓄力、搏斗、上鱼、结算。修改布局后逐张查看，不能只确认脚本退出码。

### 输入探针

`tests/input_probe.gd` 仍是旧版，未接入当前验收口径。要真正覆盖搏斗，需用真实 `InputEventMouseButton` 或 `InputEventScreenTouch` 走一遍 `_unhandled_input`，并检查 `rounds/perfect/miss`。

### 动画验收

静态截图只检查构图。角色动画还需连续帧、录屏或实际播放，核对姿态变化、轨迹同步、透明边缘、结束信号和超时兜底。

---

## 结构失控预警

出现以下情况应先拆分再续写：

- `game_root.gd` 开始计算伤害、张力或结局。
- 某个视图直接修改 session 的运行时字段。
- `core/` 出现 `get_node()`、`await` 或输入读取。
- 新增角色需要在多个 UI 文件中增加 id 分支。
- 同一数值同时硬编码在 JSON、core 和 UI。
- 动画资源路径散落为多个字符串常量。
- 新增面板后点击湖面再次失效。
- 文档重新出现当前代码不存在的字段或类。

---

## 提交或交接前检查

- [ ] 无窗口自测全部通过，并记录通过数。
- [ ] 修改过输入则运行有效的真实输入探针。
- [ ] 修改过 UI 则查看五张快照，而非只生成文件。
- [ ] 修改过动画则查看连续播放，而非只看单帧。
- [ ] 没有遗留旧圆环字段、旧统计字段或失效类引用。
- [ ] 配置字段、目录结构、信号表与文档同步。
- [ ] 未完成项明确写成未完成，不把占位实现包装成最终结果。
