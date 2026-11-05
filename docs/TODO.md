# 待办

按「补了以后玩家能立刻感觉到」排序。前两条是硬伤，其余是打磨。

写这份清单的起因是一次外部评审。结论成立，但对方给的文件大小记错了几处，下面用的是实测值。

---

## 1. 三条主鱼共用同一张脸（已解决，留作记录）

`data/fish.json` 的 `_field_help` 曾经写着：

> `"tint": "立绘叠色。大/中鱼目前共用同一张立绘，靠 tint 区分。"`

实测：

| 文件 | 大小 | 尺寸 | 说明 |
|---|---|---|---|
| `assets/portrait_small.webp` | 小 | 200×200 | Q 版头像，硬塞进立绘框会被拉伸；小肥鱼是大肥鱼的子代理，共用这张 |
| `assets/portrait_mid.webp` | 114 KB | 920×971 | 已换成上善无形原版 Q 版汉服造型（浅蓝大袖外衫 + 深蓝襦裙 + 白花），透明底 |
| `assets/portrait_big.webp` | 245 KB | 1056×1504 | ZipZipPipe 女仆装版本，唯一认真画过的一张 |

~~三条主鱼共用一张脸~~ —— 中肥鱼不再和大肥鱼同脸。现在中肥鱼是上善无形的 Q 版汉服造型，
大肥鱼保持 ZipZipPipe 的女仆装，小肥鱼作为大肥鱼的子代理继续共用立绘（设定上就是「造出来的小的」）。
中肥鱼的 `tint` 已回 `#ffffff`，不再靠色差区分。
还想要的：中肥鱼那张是方图转竖版，比大肥鱼矮一截，摆在一起高度不齐 —— 要么重绘成 1056×1504，
要么在 `landing_view` 里按角色给缩放系数（`portrait_scale`）。

`portrait_small.webp` 若保留 Q 版定位，至少升到 512² 以上，别在 UI 里被放大。

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
| `assets/ending_feast.jpg` | 1,622,002 B | 精修 |
| `assets/ending_true.png` | 1,148,963 B | 精修 |
| `assets/ending_doubao.jpg` | 1,004,563 B | 精修 |
| `assets/ending_claude.jpg` | 937,734 B | 精修 |
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

## 7. 剩下的小尾巴（结构债，玩家看不见）

- `tests/input_probe.gd` 还是圆环之前的探针，没接进验收口径。
- `ConfigLoader.FALLBACK_FISH` 与 `fish.json` 两份数据，只作读档失败兜底；可以考虑改成「读不到就报错退出」，让失败显性化。
- 翻译残留：`fish.json` 的 `tagline/blurb`、`endings.json` 长正文（`story.json` 的 `opening` 与结局台词已在 2026-11-04 补齐）。
- `tests/screenshot.gd` 出的六张图还没按新布局重拍（`06_opening.png` 是新拍的）。

---

## 已完成备查

这一轮补的（都在 `main` 上）：

- 手机端结算页按钮够不着 —— 按钮条移出 `ScrollContainer`
- 网页版中文乱码 —— 自带 Noto Sans SC 子集（`tools/make_font.py`，8.1 MB → 281 KB）
- 三端导出与 `docs/` 部署、APK 直链

2026-11-03 结构债清理：

- 脱钩演出与图鉴脱钩页统一到 `data/escapes.json`，`_escape_art_of()` 不再按 `fish.id` 分支
- 四份复制的湖面背景合进 `LakeBackdrop`；暂停遮罩抽成 `PauseLayer`（自己处理 `WHEN_PAUSED`）
- 难度字段表 `GameTuning.SCALAR_FIELDS`：修掉 11 个字段「写在难度档里不生效」
- 中心偏向真的进了抽签（`_pick_weight` 用 `score = weight × bias`）
- 结算 `good` 改为 `rounds − perfect`，`good + perfect == rounds` 恒成立
- 图鉴结局顺序挪进 `endings.json` 的 `_order`
- 关于页不再自己开 `FileAccess`，统一走 `ConfigLoader`
- 小肥鱼人设从「谁给吃的跟谁走」改成「不是谁都跟，只是认准了你这双手」，四语同步
- 自测 508 → 589（新增脱钩表、难度字段、统计口径、中心偏向、人设五组）

2026-11-04 开场剧情：

- `data/story.json` 加 `opening`：32 句，周末钓鱼 —— 中肥鱼自告奋勇下水赶鱼没回来，大肥鱼造了小肥鱼下去捞，也没回来，最后自己跳下去；玩家在岸上吐槽半天，把三条鱼串一根线钓回来
- 首次进游戏自动排队播放（`Gallery.queue_story("opening")`，去重靠 Gallery 自己），播完才开始钓鱼
- 剧情期间收起 HUD 与暂停键（`game_root._begin_story()` / `_set_play_chrome()`）
- `faces` 表：谁说话换谁的立绘，玩家自己说话时立绘压暗
- 33 行台词四语进 `strings.csv`；`screenshot.gd` 多拍一张 `06_opening.png`
- 自测 589 → 829（开场 32 句 / 说话人白名单 / 三条鱼各有立绘 / 四语覆盖 / 队列只排一次）

2026-11-05 形象与后续：

- 中肥鱼换成上善无形的 Q 版汉服立绘（`portrait_mid.webp`）+ 顶锅彩蛋图（`assets/easter/easter_mid_bowl.webp`），动作四帧同步重画；大肥鱼、小肥鱼仍是 ZipZipPipe 的女仆装
- 署名拆成两位：角色原作上善无形、女仆装版本 ZipZipPipe，写进 `CREDITS.md` / `about.json` / `README.md`
- `ending_feast`（齐鱼之福）重绘：三条同框，中肥鱼汉服、另两条女仆装（anima-turbo + ZipZipPipe LoRA）
- 齐鱼之福追加 26 句后续：拉灯 → 奇怪的鲸鱼叫 → 第二天「都吃饱了」，玩家有 4 句台词；只到暗示为止
- 自测 829 → 1058（新增中肥鱼立绘、齐鱼之福后续两组）
- 立绘设定：大肥鱼、小肥鱼是女仆装（ZipZipPipe 版），中肥鱼是 Q 版汉服（上善无形原版造型，浅蓝大袖外衫 + 深蓝襦裙）—— 写动作前先看对应那张图；中肥鱼没有外套、帽子、女仆围裙可脱

2026-11-05 第二天 CG 与导出：

- 新增 `assets/ending_feast_after.webp`（三条鱼趴在你身上、你只露胸腹与两只手的第一人称 POV，1216²），挂在齐鱼之福最后 7 句上：页级 `bg` + 逐句 `hide_face: true`
- `StoryOverlay` 支持「整段没 `bg` 时由页级 `bg` 建底图」，并新增页字段 `hide_face`
- 导出三端：`dist/钓肥鱼.exe`（54.87 MB）、`dist/web/*`、`dist/android/钓肥鱼.apk`（debug 签名，release 缺发布密钥库）、`dist/钓肥鱼_web.zip`（17.15 MB）
- 自测 1058 → 1061（第二天 CG 覆盖 7 句、底图存在）

2026-11-05 开场 CG 与 v1.1.0 发布：

- 开场三张整页 CG：中肥鱼走进水里 / 大肥鱼造小肥鱼 / 把竿塞回你手里再自己下水；第 26 句用 `bg: "-"` 撤图，回到只用立绘的水面安静段
- 剧情层新增 `hide_face` 与 `bg: "-"`；整页 CG 改成等比完整显示，不再把第一人称的手裁掉
- GitHub 推送并发布 `v1.1.0`（Windows exe / Android apk / Web zip 三个资产），自测 1067

2026-11-05 计分、点击推进与中肥鱼四帧：

- 新增 `core/score_board.gd` + `ui/score_layer.gd`：完美 100 / 普通 45、连击倍率 `1+min(combo-1,9)×0.15`、上鱼底分（小 120 / 中 180 / 大 240 / 豆包 60 / 克劳德 400）、全收 300、剩饵 40/条、零失手 200、难度系数 0.8/1.0/1.3；最高分存 `user://record.json`
- 结算页加分数块（总分大字 + 「得分」+ 最高连击 / 最高分 / 新纪录）
- 连击并进分数行（`得分 1860   x4`），飘字只报单次收益；`ScoreLayer` 加在 `LandingView` 之上，上鱼那一刻的 `+240` 才不会被演出压住
- 修 `StoryOverlay` 左键点击推进：原先 `Label` 吃掉事件，只能按 Enter；改为 `_input` 里按坐标判定并给两个按钮让位，触屏同样生效
- 修 `FightSession` 只 emit "round"，导致 `qte_overlay` 的 "good" 分支从未触发
- 中肥鱼上鱼四帧重画（被拉起 / 歪头 / 笑眼水花 / 甩尾），按非白包围盒统一缩放到 660px 高再贴 768² 白底
- 自测 1067 → 1093

2026-11-05 开场收尾砍短：

- `opening` 32 → 29 句：删掉「……行吧。我一个人在岸上，钓三条傻鱼。」「你把竿甩了出去……」「……别说出去。」三句，大肥鱼自己也跳下水就是最后一句，直接进对局
- `strings.csv` 同步删掉这三条键（168 行），`_case_opening_story()` 改为 29 句并断言最后一句含「跳了下去」
- 自测 1093 → 1072（少三页，逐句断言随之减少）
