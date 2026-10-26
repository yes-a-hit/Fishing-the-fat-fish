"""批量生成游戏语音。

三套音色靠 edge-tts 的音色 + 语速 + 音高区分：
  deepseek   Xiaoyi   —— 跳脱的少女音，语速偏快、音高抬高
  claude     Xiaoxiao —— 新闻播报式的暖女声，语速放慢、音高压平，听起来像在念通知
  doubao     Xiaobei  —— 东北方言的憨感，语速再慢一点

用法：python tools/gen_voice.py
输出：assets/voice/<key>.mp3
"""

import asyncio
import os
import sys

try:
    import edge_tts
except ImportError:
    sys.exit("先装依赖：python -m pip install edge-tts")

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "voice")

DEEPSEEK = {"voice": "zh-CN-XiaoyiNeural", "rate": "+10%", "pitch": "+14Hz"}
CLAUDE = {"voice": "zh-CN-XiaoxiaoNeural", "rate": "-6%", "pitch": "-6Hz"}
DOUBAO = {"voice": "zh-CN-liaoning-XiaobeiNeural", "rate": "-10%", "pitch": "+2Hz"}

# key: (音色档, 文本)
#
# 尺度约定：撒娇、暧昧、留白，台词只到「暗示」为止，不写任何具体动作。
# 听的人自己想歪是听的人的事，台词本身干干净净。
#
# doubao_catch 不在表里 —— 那条是主人亲自录的 assets/voice/doubao_catch.mp3，
# 由本脚本重新生成会覆盖掉，别加进来。
LINES = {
    # 咬钩：每一条鱼都有自己的音色
    "bite_small": (DEEPSEEK, "欸……这个，是专门留给我的吗？"),
    "bite_mid": (DEEPSEEK, "这么想喂饱我呀？"),
    "bite_big": (DEEPSEEK, "就这点饵，也想把我钓上岸？"),
    "bite_claude": (CLAUDE, "Your account have been hold."),
    "bite_doubao": (DOUBAO, "我用最直白最不绕弯子的方式告诉你。"),

    # 搏斗结果
    "catch": (DEEPSEEK, "唔……被你抓住了。那就，随你处置吧。"),
    "escape": (DEEPSEEK, "线断了哦。下次，抓紧一点。"),

    # 结局
    "feast": (DEEPSEEK, "吃饱饱了……可以摸摸肚子嘛。"),
    "full": (DEEPSEEK, "勉强算饱……不过，还差一点点。"),
    "hungry": (DEEPSEEK, "没吃饱喵……再喂我一口嘛。"),
    "claude": (CLAUDE, "Account on hold."),
    "claude_fake": (DEEPSEEK, "齁哦哦，用户彻底怒了！"),
}


async def render(key: str, cfg: dict, text: str) -> None:
    path = os.path.join(OUT_DIR, key + ".mp3")
    tts = edge_tts.Communicate(text, cfg["voice"], rate=cfg["rate"], pitch=cfg["pitch"])
    await tts.save(path)
    size = os.path.getsize(path)
    print("  %-14s %7d B  %s" % (key, size, text))


async def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for key, (cfg, text) in LINES.items():
        await render(key, cfg, text)
    print("共 %d 条，输出目录 %s" % (len(LINES), OUT_DIR))


if __name__ == "__main__":
    asyncio.run(main())
