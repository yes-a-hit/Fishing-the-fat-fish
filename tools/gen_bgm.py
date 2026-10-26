"""生成湖面 BGM。

ComfyUI 那边没有音频模型（`models/audio_encoders` 是空的，`checkpoints` 全是图像模型），
要跑 ACE-Step 得先下 3.5 GB，所以这里先用合成器搭一版能听的底噪：

  海浪  —— 白噪过低通 + 0.05 Hz 的慢包络
  拨弦  —— A 小调五声音阶，指数衰减，轻微 detune 做出「水面反射」的双音
  垫音  —— A2 长音 + 慢颤音，把整体撑住

60 秒，首尾交叉淡化，可以直接循环。用法：python tools/gen_bgm.py
"""

import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100
DUR = 60.0
N = int(SR * DUR)
RNG = np.random.default_rng(20261026)

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "bgm", "lake_loop.wav"
)

# A 小调五声：A C D E G，跨两个八度
SCALE = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25, 783.99]


def envelope(n, attack, decay):
    """快起慢落的包络，attack/decay 都是秒。"""
    t = np.arange(n) / SR
    env = np.exp(-t / max(decay, 1e-4))
    if attack > 0:
        a = np.clip(t / attack, 0.0, 1.0)
        env *= a
    return env


def waves(n_seconds):
    """海浪：低通白噪 + 慢包络。"""
    n = int(SR * n_seconds)
    raw = RNG.standard_normal(n)
    b, a = butter(2, 380.0 / (SR / 2), btype="low")
    body = lfilter(b, a, raw)
    # 两个互质的 LFO 叠起来，60 秒内正好整数周期，循环点听不出接缝
    t = np.arange(n) / SR
    lfo = 0.55 + 0.45 * np.sin(2 * np.pi * t / 12.0) * np.sin(2 * np.pi * t / 20.0)
    return body * lfo


def pluck(freq, n_seconds, gain):
    """拨弦：基音 + 两个泛音，各自轻微失谐。"""
    n = int(SR * n_seconds)
    t = np.arange(n) / SR
    env = envelope(n, 0.006, 0.55)
    sig = np.zeros(n)
    sig += np.sin(2 * np.pi * freq * t)
    sig += 0.32 * np.sin(2 * np.pi * freq * 2.0 * 1.001 * t)
    sig += 0.14 * np.sin(2 * np.pi * freq * 3.0 * 0.999 * t)
    return sig * env * gain


def pad(freq, n_seconds, gain):
    """垫音：长音 + 慢颤音。"""
    n = int(SR * n_seconds)
    t = np.arange(n) / SR
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * t / 7.0)
    return np.sin(2 * np.pi * freq * vib * t) * gain


def build() -> np.ndarray:
    buf = np.zeros(N)

    # 1. 海浪铺底
    sea = waves(DUR)
    sea /= max(np.max(np.abs(sea)), 1e-9)
    buf += sea * 0.22

    # 2. 垫音：A2 贯穿全曲，两端淡入淡出由循环交叉淡化处理
    buf += pad(110.0, DUR, 0.10)
    buf += pad(164.81, DUR, 0.045)  # E3，五度

    # 3. 拨弦旋律：八分音符网格，留大量空白，听起来才像背景而不是曲子
    step = 0.75
    pos = 0.4
    while pos < DUR - 1.0:
        note = SCALE[int(RNG.integers(0, len(SCALE)))]
        dur = float(RNG.uniform(1.6, 3.2))
        gain = float(RNG.uniform(0.055, 0.115))
        start = int(pos * SR)
        seg = pluck(note, dur, gain)
        end = min(start + len(seg), N)
        buf[start:end] += seg[: end - start]
        # 偶尔叠一个高八度的弱音，像水面的回声
        if RNG.random() < 0.28:
            echo = pluck(note * 2.0, dur * 0.7, gain * 0.35)
            delay = int(0.28 * SR)
            s2 = start + delay
            e2 = min(s2 + len(echo), N)
            if s2 < N:
                buf[s2:e2] += echo[: e2 - s2]
        pos += step * float(RNG.integers(1, 4))

    # 4. 简易混响：三路错开的延迟，尾巴绕回开头保证循环无缝
    for delay_s, fb in ((0.137, 0.30), (0.211, 0.24), (0.307, 0.18)):
        d = int(delay_s * SR)
        delayed = np.roll(buf, d) * fb
        buf = buf + delayed

    # 5. 首尾各 0.6 秒交叉淡化，循环点没有咔哒
    fade = int(0.6 * SR)
    ramp = np.linspace(0.0, 1.0, fade)
    head = buf[:fade].copy()
    tail = buf[-fade:].copy()
    buf[:fade] = head * ramp + tail * (1.0 - ramp)
    buf[-fade:] = tail * ramp + head * (1.0 - ramp)

    # 6. 归一化到 -6 dBFS，留 headroom
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf *= 0.5 / peak
    return buf


def write_wav(path: str, data: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(data, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("写出 %s  %.1f MB  %d Hz  %.1f 秒" % (path, os.path.getsize(path) / 1048576, SR, len(data) / SR))


if __name__ == "__main__":
    write_wav(OUT, build())
