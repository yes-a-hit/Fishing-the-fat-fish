# 制作人员与素材来源

本项目采用 [CC BY-NC-SA 4.0](LICENSE) 协议发布。

**这个游戏里的角色形象不是我画的。** 下面的清单列出了每一个来源，
二次创作时请一并遵守它们各自的条款。

---

## 代码、玩法、文案、数值

作者：精准投喂的开发者

包括：`scripts/` 下全部 GDScript、`data/` 下全部 JSON、`tests/` 下全部测试、
`docs/` 下全部文档、`tools/` 下的音频生成脚本。

---

## 角色形象

### DeepSeek 鲸鱼娘（蓝发、鲸耳、鲸尾、女仆装）

形象设计：**ZipZipPipe**

画风模型：`DeepSeek_ZipZipPipe_style_anima2b` —— 由 ZipZipPipe 训练的画风 LoRA，
发布在 Civitai：

- 作者本人：https://space.bilibili.com/zh-Hans/4168597
- 作品页：https://civitai.com/models/2919135
- 基座：Anima 2B（UNET `anima-base-v1.0` + CLIP `qwen_3_06b_base` + VAE `qwen_image_vae`）

本项目用这个 LoRA 生成了 `assets/ending_feast.png`。
生成参数：LoRA 强度 0.85、32 步、CFG 5、1216×1216 一次成图。

角色的三档立绘（`portrait_small/mid/big.jpg`）与 `ending_feast.png` 均属此列。

> **使用本项目时，请同样保留 ZipZipPipe 的署名。**
> 如果你把角色裁掉、换成别的东西，那不叫二创，那叫抹除出处。

### Claude 娘（橘发、黑白女仆装、花朵发饰）

形象为社区二创形象，本项目使用的图片包含：

- `assets/claude_chibi.jpg`（原图经 AI 生成工具产出，右下角水印 `Dola AI`）
- `assets/claude_fake_1.png`（本项目用 Anima 2B 基座生成，无 LoRA）
- `assets/claude_fake_3.png`（社区 meme，竖排文案「深度思考中...／我草，用户彻底怒了」）

相关角色与商标归 Anthropic 所有。本项目是**戏仿（parody）**，
与 Anthropic 无任何关联，也未获其授权或背书。

### 豆包

`assets/doubao.png`、`assets/doubao_escape.jpg` 为社区流行的豆包 AI 拟人形象
（黄色 3D 卡通人物）。相关角色与商标归字节跳动所有。
本项目同样为戏仿，无关联、无授权。

`assets/doubao_kick.jpg`（「哪来的奶黄包！」）是网络流传的 meme 改图。

---

## 梗图

以下图片来源于网络流传的 meme，本项目仅作戏仿使用，**不主张任何权利**：

| 文件 | 来源 |
|---|---|
| `assets/ending_win.jpg` | 社区流传的「吃饱饱摸摸肚子」meme |
| `assets/ending_hungry.jpg` | 社区流传的「你这吃白饭的蓝色大肥鱼」meme |
| `assets/claude_fake_2.png` | *Scooby-Doo* 揭头套梗图的手工改图（主人 P 的） |
| `assets/claude_fake_3.png` | 社区 meme，见上 |
| `assets/doubao_kick.jpg` | 网络流传的「哪来的奶黄包」改图 |

*Scooby-Doo* 相关角色与图像归 Warner Bros. Discovery 所有。

---

## 音频

### 语音

12 条台词由 **edge-tts**（微软 Edge 在线语音合成服务）生成，
脚本见 `tools/gen_voice.py`。三档音色：

| 角色 | 音色 | 语速 / 音高 |
|---|---|---|
| DeepSeek | `zh-CN-XiaoyiNeural` | +10% / +14Hz |
| Claude | `zh-CN-XiaoxiaoNeural` | −6% / −6Hz |
| 豆包 | `zh-CN-liaoning-XiaobeiNeural` | −10% / +2Hz |

以下两条**不是** edge-tts 生成的：

- `assets/voice/doubao_catch.mp3` —— 本项目作者本人录制
- `assets/voice/doubao_escape.mp3` —— 网络流传的「奶龙大笑」音效，仅作戏仿使用

### 背景音乐

`assets/bgm/lake_loop.wav` —— 由 `tools/gen_bgm.py` 用 numpy + scipy
**程序合成**，60 秒无缝循环。不含任何采样素材。

---

## 引擎与依赖

- 引擎：**Godot 4.7.2**（MIT 许可）
- 语音合成：**edge-tts**（LGPL-3.0）
- 音频合成：**numpy**（BSD-3-Clause）、**scipy**（BSD-3-Clause）

---

## 二次创作怎么做

1. Fork 之后先读一遍 `LICENSE` 和本文件。
2. 保留 `CREDITS.md`，或者在你的 README 里放一份等效的署名清单。
3. 你的改动必须以 CC BY-NC-SA 4.0 或兼容协议分发。
4. **不要商业使用**，不要投放广告、不要接内购、不要作为商业平台的变现内容。
5. 如果你替换了角色素材，请说明替换了什么 —— 尊重你用的每一个上游作者。

---

## 一句话

这个游戏是免费做的，纯乐子。你要是喜欢，欢迎 Fork、改、再发。
**只求别把名字抹掉。**
