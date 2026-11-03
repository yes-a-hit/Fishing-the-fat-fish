# 开发者手册

接手这个项目要读的东西。如果你只想改数值，看 [tuning.md](tuning.md)；想改表现，看 [architecture.md](architecture.md)；想加一条鱼，看 [contributing.md](contributing.md)。

这篇讲的是**为什么代码长成这样**，以及那些踩过一次就不会再踩第二次的坑。

---

## 一、环境

| 项 | 位置 |
|---|---|
| Godot 控制台版 | `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.7.2.stable\` |
| 签名密钥 | `E:\godot_workplace\keys\feedfish.keystore` |
| Android SDK | `D:\Android\Sdk`（build-tools 34.0.0 / platforms android-34） |
| JDK | `D:\JDK`（17） |

**跑命令行一律用 `_console.exe`**。普通 exe 是 GUI 子系统，PowerShell 里什么都不返回。

---

## 二、分层：规则往下沉，表现往上浮

`scripts/core/` 里全是 `RefCounted`，零 Node 依赖，能在 `--headless` 下跑完一整局。`scripts/ui/` 只做表现。

**判断标准**：这段逻辑能不能在不创建任何 Node 的情况下跑完？能，就往 core 放。

好处是自测能覆盖 400+ 条用例而不需要渲染，坏处是 core 里不许用 `Vector2` 之外任何依赖场景树的 API。

---

## 三、几个关键设计决定

### 抛竿为什么是循环条

按住蓄力，游标在 0~1 之间 `fposmod` 循环，松手取当前值。**转多少圈都不算输** —— 这是手机适配的核心，玩家有无限次犹豫的机会，只看最后一刻。

早期版本到顶就归零，结果贴着末端的鱼带（claude 的 `92~100`）会被「一犹豫就跳回近岸」，反馈是「不要突然切换目标」。现在末端留 6 单位缓冲区，过冲只空竿。

### 距离带为什么允许重叠

专属区域的问题是中段那些鱼「只能从一个很窄的缝里钓」，手感差。改成重叠 + 权重抽样后，落点在一个区间里可能钓到两三种鱼，靠 `weight × 中心偏向系数` 决定概率。

**中心偏向**（`BIAS_FLOOR = 0.2`）是为了让落点更靠近的那条鱼更容易上钩。没有它，远洋末端会反复抽到小肥鱼。

**普通鱼之间不许有空档**，因为玩家抛进去钓不到东西却不知道为什么。唯一允许的空档是普通鱼最后一条带的 `to` 与 claude 带的 `from` 之间 —— 陷阱要刻意隔开。

### 搏斗为什么是单键圆环

最早是 WASD 序列，手机上没法玩。改成圆环后只需要一个点击动作，而且「转到黄标再点」这个判定天然适合触屏。

三个细节：
- **游标起点随机**，否则玩家能数节拍闭眼满分。
- **黄标只画一段**，不画完美区。早期画了三层（轨道 + 命中弧 + 完美弧），玩家把内圈金弧当判定区，量错边界，反馈是「明明在区间外还是中了」。
- **体力越低游标越快**，让残局更紧张。

### 为什么豆包的脱钩要单独掷骰

豆包 `damage_ratio = 1.0`，一次命中就上鱼。它永远走不到张力爆表，所以挂在 `RESULT_ESCAPED` 上的分支是**死代码**。必须在咬钩那一刻单独掷 `doubao_escape_chance`。

**教训**：加分支之后要验证它真的能走到。只测「会跑」等于只测了一半，得同时测「开关关掉时它不会跑」。

### 为什么集齐鱼要当场结算

`_advance_after_round()` 里那个分支必须放在 `bait_left <= 0` 之前。晚一步玩家就得把剩下的饵烧完才看到结局，反馈是「集齐鱼后不会自动跳齐鱼之福」。

### 为什么剧情在结算之前播

第二次逮到豆包那一竿，恰好也可能就是集齐三条鱼那一竿。如果先摆结算卡片，剧情永远看不到。所以入队 → 播完 → 再摆结算。

---

## 四、存档

两个文件：

| 文件 | 内容 |
|---|---|
| `user://gallery.json` | `unlocked` / `claude_stage` / `doubao_seen` / `story_queue` / `story_done` |
| `user://settings.json` | `difficulty` / `bgm_on` / `bgm_volume` / `voice_on` / `voice_volume` |

**所有写入走 `Gallery._save_patch(resolved, patch)`**：读整份 json → 只改自己那几个键 → 写回。

早期 `unlock()` 自己拼一份只含 `unlocked` 的 json，把隔壁 `claude_stage` 抹掉了，症状是「claude 三段线永远停在第一段」。**往同一个文件写多个字段时，永远读改写，不要拼新对象。**

---

## 五、坑（按踩到的顺序）

1. **导出成 pck 后 `DirAccess.get_files()` 扫不到文件**。编辑器里好好的，导出后返回空数组 —— 源图不在包里，只有 `.godot/imported/*.ctex`。**任何靠目录扫描发现资源的代码导出后都会静默失效。** 资源路径写成显式常量数组（`landing_view.gd` 的 `SEQUENCES`），逐个 `load()`。
2. **`get_files()` 会把 `.import` 一起列出来**。见到就 `continue`，不要 trim 后缀再判 —— 否则同一个文件被数两遍。
3. **`.webp` 默认按无损导入**。一张 168 KB 的图编译成 923 KB 的 `.ctex`。`.import` 里改 `compress/mode=1` + `compress/lossy_quality=0.85`。
4. **`--export-release "Android"` 报"找不到发布密钥库"**。编辑器设置、`export_credentials.cfg`、ASCII 路径、相对路径全试过都救不回。改走 `--export-debug` → `zipalign -f -p 4` → `apksigner sign`，签出来的证书和 release 一致。
5. **每次导出都重置 `docs/index.html` 的 `ensureCrossOriginIsolationHeaders`**。GitHub Pages 和 itch.io 拿不到 COOP/COEP 头，必须改回 `false`。顺手把 `fileSizes` 里三个字节数一起更新。
6. **空 `.gdignore` 是排除目录最省事的办法**。改 `export_presets.cfg` 的 `exclude_filter` 经常因为编码问题静默不生效（`String.Replace` 和 `[regex]::Replace` 都报过 0 处替换）。
7. **TTS 的 mp3 不能改扩展名当 ogg 用**。必须 `ffmpeg -c:a libvorbis -q:a 8`。`-q:a 5` 只有 5.3 kbps 会明显失真。
8. **`--script` 模式下 autoload 不在作用域**。`Audio.xxx` 报 `Identifier not found`。要从 `Engine.get_main_loop() as SceneTree` 取 `.root.get_node_or_null("Audio")`，调方法用 `audio.call(...)`。
9. **`edit` 工具改 GDScript 时，`old_string` 以「行 + 换行」结尾而 `new_string` 只写行本身会吞换行**，下一行拼上来报 `Unindent doesn't match`。
10. **新增 `class_name` 后要先跑一次 `--import`**，否则 `Identifier "Xxx" not declared`。
11. **自测会写玩家存档**。`_run_all()` 开头把 `Gallery.override_path` 指到 `user://gallery_sandbox.json`，结束时清空并复原。

---

## 六、自测

```powershell
$G = "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$out = & $G --headless --path . --script "res://tests/selftest.gd" 2>&1
$code = $LASTEXITCODE   # 不要经 Select-String 管道，会拿到假的 1
```

- 用 `extend SceneTree`，逻辑写在 `_process` 第一次调用里。`_initialize` 里 `_ready` 不会及时跑。
- 断言三参数用 `_check(label, actual, expected)`，`_ok()` 只收两个。
- 测开关类的功能要两头都测：概率 1 必触发、概率 0 必不触发。

---

## 七、发布 checklist

```
1. --import
2. 三端导出 → dist/windows、dist/web、dist/android
3. APK: zipalign -f -p 4 → apksigner sign
4. dist/web/* → docs/（除 .import）
5. docs/index.html: ensureCrossOriginIsolationHeaders = false
6. docs/index.html: fileSizes 三个字节数换成新值
7. 打包 docs/download/ 三个附件
8. export_presets.cfg 六个 keystore 字段清空
9. git add -A && git commit && git push
```

**第 5、6 步漏了，网页版会卡在加载画面。**

---

## 八、素材

### 立绘 / CG

ComfyUI + `DeepSeek_ZipZipPipe_style_anima2b` LoRA，基座 Anima 2B（不兼容 2.9B）。

- **0.85 强度** → 粗黑描边、高饱和平涂，魔性 chibi。
- **0.45 强度** → 细腻柔和的 galgame 画风，靠 prompt 写 `soft anime illustration, delicate thin lineart, soft gradient shading`，负向压 `thick black outline, bold lineart, high saturation`。

`zipzippipe` 不等于粗线条高饱和，想画细腻的画风就把强度降下来。

### 动画帧

逐帧，不是骨骼。**每帧只交代一个动作**，塞两个就糊。人物尺度要锁，否则帧间大小乱跳。材质要显式写（`shiny stainless steel bowl`），否则默认画成白瓷。

存 `768²` WebP `q90`。

### 音频

- 语音：edge-tts 生成 mp3 → ffmpeg 转 ogg。
- BGM：numpy + scipy 合成（`tools/gen_bgm.py`），**周期性成分的周期必须能整除循环长度**，混响尾巴用 `np.roll` 绕回开头，首尾交叉淡化。

---

## 九、多语言

翻译表是 `data/i18n/strings.csv`，Godot 导入时自动切成 `strings.zh_CN.translation` 和 `strings.en.translation`，在 `project.godot` 的 `[internationalization]` 里注册。

**中文原文直接当键** —— 代码里写 `tr("开 始 钓 鱼")`，CSV 里查不到就原样返回。好处是写代码时不用先起 key 名，坏处是改了中文得同步改 CSV。

三层要分开看：

- **UI 层**：`scripts/ui/` 下的中文字面量已全部包了 `tr()`（`tools/wrap_tr.py` 批量做的，脚本留着，加新文件可以再跑）。
- **数据层**：`fish.json` 的 `display_name` / `tagline` / `blurb`、`endings.json` 的 `title` / `subtitle` / `lines` / `pages[].caption`，在 `ConfigLoader` 加载时过一遍 `TranslationServer.translate()`。用这个而不是 `tr()`，因为 `ConfigLoader` 是纯静态类。
- **切换时机**：`Boot` autoload（排在 `Audio` 前面）在 `_ready` 里读设置并 `set_locale`，保证任何场景建 UI 之前语种已生效。设置页改完语言调 `_rebuild_page()` 整页重画 —— `tr()` 只在构建时求值，不重建文字还是旧语种。

两个坑：

1. **`const` 数组里不能用 `tr()`**。报 `Assigned value for constant "TABS" isn't a constant expression`，改成 `var`。
2. **语言按钮上的名字不走 `tr()`**。中文界面下写「简体中文」，英文界面下它还是「简体中文」—— 用母语写语言名才认得出是哪个。
3. **数据里改文案忘了同步 CSV**，英日界面就会冒出中文。`characters.json` 的人设与口头禅、`escapes.json` 的台词、暂停页按钮，都属于这一类。改完重跑 `--import`。
4. **批量追加 CSV 行时列序容易写反**，把繁体填进 `zh_CN` 列的症状是「简中界面显示繁体」。追加完扫一眼第 2、3 列是否相同。

---

## 十、2026-11 这一轮清掉的结构债

都是「同一件事写了两份」的变体，记下来免得再长回去。

| 原来的样子 | 现在 | 代价 |
|---|---|---|
| 四个页面各一份 `_build_background()/_draw_background()`，逐字相同 | `scripts/ui/lake_backdrop.gd` | 改配色只动一处 |
| `game_root._pause_game()` 内联搭 dim + 卡片 + 三按钮 | `scripts/ui/pause_layer.gd`，只发三个信号 | 暂停层能单独测、单独改 |
| 脱钩演出的图与文案在 `_escape_art_of()` 和 `gallery_root.ESCAPE_ITEMS` 各一份，还带 `fish.id` 分支 | `data/escapes.json` + `ConfigLoader.escape_for()` | 加鱼/改台词只动数据 |
| 图鉴结局顺序写死在 `_ordered_keys()` 的数组里 | `endings.json` 的 `_order` | 加结局不用改 UI |
| `_start_session()` / `_disconnect_session()` 手写十组 connect / is_connected | `SESSION_HOOKS` 表 + 循环 | 加信号加一行 |
| `from_dict()` 与 `apply_difficulty()` 各抄一份字段白名单，漂移后 11 个字段在难度档里静默失效 | `GameTuning.SCALAR_FIELDS` + `_read_scalars()` | 加字段加一行 |
| `good = rounds - miss`（miss 不进 rounds，算出来是假数） | `good = rounds - perfect` | 统计页自洽 |
| `candidates_at()` 算出 `score = weight × 中心偏向`，抽签却只用 `weight` | `_pick_weight()` 优先用 `score` | 文档承诺的中心偏向真的生效 |
| `about_root` 自己 `FileAccess` + `JSON.parse_string` | `ConfigLoader.read_json(PATH_ABOUT)` | 文件入口只有一处 |
| `GameTuning.fish_id_in()` 无人调用 | 删除 | 少一个「兼容旧调用」的幽灵 |
| 设置页三处各写一遍 stylebox 覆盖 | `_paint_button()` | 选中/关闭态一致 |
| 小肥鱼人设「谁给吃的跟谁走」 | 「不是谁都跟，只是认准了你这双手」 | 角色不写成谁都能骗走 |

顺手补的测试（`pass` 从 508 涨到 589）：`_case_escape_data` / `_case_tuning_scalar_coverage` / `_case_summary_math` / `_case_center_bias` / `_case_small_fish_voice`。

两条教训：

1. **同名函数删了要全仓搜**。`about_root._read_json()` 删掉后，自测里还有一处调用，`--headless` 跑出来的是一行 `SCRIPT ERROR`，但退出码仍是 0、`pass=508 fail=0` —— 不盯 stderr 就会以为没事。
2. **`Node.free()` 别写两次**。同一个节点 free 两遍，Windows 上是 `0xC0000409`（栈溢出保护）直接崩，输出只停在上一条 `ok`，很容易误判成别处的问题。

---

## 十一、现在的短板

- 三条鱼共用同一张立绘，只靠缩放区分体型。
- Claude 和豆包没有上鱼动画，还是静态立绘。
- 张力条在 UI 上不够显眼，玩家不知道自己快拉爆了。
- 结局图 832×1216、立绘 768×768，分辨率不一致，混着放会看出来。
- 翻译已覆盖界面骨架、角色页、脱钩页与暂停页；`fish.json` 的 `tagline/blurb`、`story.json` 的剧情台词、`endings.json` 的长正文仍有中文残留。
- `tests/input_probe.gd` 还是旧圆环之前的探针，没接进验收口径。
- `ConfigLoader.FALLBACK_FISH` 与 `fish.json` 仍是两份数据，只作为读档失败时的兜底。
