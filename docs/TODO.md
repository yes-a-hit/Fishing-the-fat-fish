# 待办

按「补了以后玩家能立刻感觉到」排序。前两条是硬伤，其余是打磨。

写这份清单的起因是一次外部评审。结论成立，但对方给的文件大小记错了几处，下面用的是实测值。

---

## 1. 三条主鱼共用同一张脸（最该补的一条）

`data/fish.json:7` 自己就写着：

> `"tint": "立绘叠色。大/中鱼目前共用同一张立绘，靠 tint 区分。"`

实测：

| 文件 | 大小 | 尺寸 | 说明 |
|---|---|---|---|
| `assets/portrait_small.jpg` | 5,426 B | 200×200 | Q 版头像，硬塞进立绘框会被拉伸 |
| `assets/portrait_mid.jpg` | 26,853 B | 335×597 | 和大鱼同一张图，只换了色温 |
| `assets/portrait_big.jpg` | 245,113 B | 1056×1504 | 唯一认真画过的一张 |

玩家钓上来三条，眼睛看到的是同一张脸加一层色光。**一款卖立绘的作品，三条主鱼共用一张脸，这是硬伤。**

要做的：按 `portrait_big.jpg` 的画风（ZipZipPipe / Anima 2B 那套，见 `CREDITS.md`）给小肥鱼、中肥鱼各出一张正式立绘，1056×1504 或者同比例。出完把 `fish.json` 里的 `tint` 改回 `#ffffff`——不再需要靠色差区分。

`portrait_small.jpg` 若保留 Q 版定位，至少升到 512² 以上，别在 UI 里被放大。

---

## 2. 把「喂饱」变成机制，而不是台词

现在的喂饭只影响饵数：钓上一条鱼，扣一碗饭，然后没有任何东西改变。鱼被钓走之后其余两条的体力、张力曲线一模一样，所以「还饿」「急」全是文案，身体感觉不到。

改法（成本很低）：

- `data/tuning.json` 的 `fight` 段加一个 `fed_pressure`，含义是「每上一条鱼，剩余鱼的 `tension_passive_rate` 乘多少」。
- `FishingSession` 开局或每次上鱼后，把当前 `landed` 数算成乘数，传给 `FightSession`。
- `FightSession._tick_tension()` 里把这个乘数乘进 `rate`。

效果：三条鱼全上之后，最后一条的张力涨得明显更快，手会抖。「还饿」才长进肉里。

数值起点建议 `fed_pressure = 1.18`，三档难度各自覆盖（easy 1.10 / normal 1.18 / hard 1.28）。跑 `tests/selftest.gd` 时补一条断言：`_landed` 增加到 3 时，同一只鱼的 `_tick_tension` 涨幅比 `_landed = 0` 时高。

---

## 3. 张力条现在更像装饰

失败率趋近于零。`round_relief = 6.0`、`miss_tension = 14.0`、`tension_max = 100` —— 意味着连按错十几次才可能断线，而正常打根本不会连错。

不是要劝退休闲玩家，是要让「失手」这件事有重量。可以动的组合：

- 提高 `miss_tension`，或降低 `round_relief`，让容错窗口从「十几次」收到「三四次」。
- 或者给张力加一个**不随回合回落**的下限，让它只涨不退，逼玩家在有限回合内解决。

改之前先算清楚：一只五轮的鱼，如果每轮都只中不完美，张力净变化是多少。这个数字应该接近但不触顶 —— 完美命中有意义，全都不完美就该断。

---

## 4. CG 质量断层

| 文件 | 大小 | 定位 |
|---|---|---|
| `assets/ending_feast.png` | 1,622,002 B | 精修 |
| `assets/ending_true.png` | 1,148,963 B | 精修 |
| `assets/ending_doubao.png` | 1,004,563 B | 精修 |
| `assets/ending_claude.png` | 937,734 B | 精修 |
| `assets/ending_win.jpg` | 575,479 B | 梗图截取 |
| `assets/ending_hungry.jpg` | 32,481 B / 447×447 | 梗图截取，分辨率最低 |

`ending_win` 和 `ending_hungry` 是刻意退回梗图的（有它的幽默），但和精修图并排放在同一个图鉴里，落差很显眼。至少把 `ending_hungry.jpg` 的源图换成高清版 —— 447² 在 1280 宽的窗口里已经能看出糊。

---

## 5. 最好的文案藏在最难触发的地方

`claude_good` 那句「走吧。反正账号早就被封了。」、`doubao_good` 的「啊哈哈哈，白饭来咯」，都要先把对应角色的语音集齐才解锁。多数玩家一次通关看不到。

不是要把它们提前剧透，而是**在流程里留钩子**：图鉴里未解锁的格子可以给一句 cryptic 的提示，让人知道「还有东西没找到」，而不是一块纯灰的「？」。

---

## 6.claude的台词写错了

应为“your account is on hold”，但因为洋豆包生成meme的问题，台词错了，需要重做配音和台词

---

## 已完成备查

这一轮补的（都在 `main` 上）：

- 手机端结算页按钮够不着 —— 按钮条移出 `ScrollContainer`
- 网页版中文乱码 —— 自带 Noto Sans SC 子集（`tools/make_font.py`，8.1 MB → 281 KB）
- 三端导出与 `docs/` 部署、APK 直链

自测 **386 项**，`--headless --script res://tests/selftest.gd`。
