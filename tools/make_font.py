"""把 Noto Sans SC 子集化成「项目实际用到的字符」那一份。

Godot 4 的默认字体不含中日韩字形。桌面端靠系统字体回退还能显示，
Web 端没有可靠回退，中文就变成乱码或豆腐块 —— 所以必须自带字体。

完整 Noto Sans SC 有 8 MB，其中 95% 的字这游戏一辈子用不到。
这里扫描 scripts/ 和 data/ 里出现过的每一个字符，只保留它们。

用法：
    python tools/make_font.py [--hello]

    --hello   不扫项目，只取一份固定的常用字表（给控制台/调试界面备用）
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Regular.otf")
DST = os.path.join(ROOT, "assets", "fonts", "game_sc.otf")

# 标点、符号、界面常用词。这些即使当前没出现也留着，
# 免得改一句文案就要重新子集化一次。
EXTRA = (
    "✓✗×…—–·「」『』（）《》【】〈〉、。，！？：；“”‘’～"
    "0123456789"
    "第条项次轮秒分时天日年月"
    "上下左右前后中大小多少高低长短新旧"
    "开关闭启停继续返回取消确认是否"
)


def collect(hello: bool) -> str:
    chars: set[str] = set()
    for code in range(0x20, 0x7F):
        chars.add(chr(code))
    chars.update(EXTRA)

    if hello:
        chars.update("你好世界测试中文字体渲染")
        return "".join(sorted(chars))

    patterns = [
        os.path.join(ROOT, "scripts", "**", "*.gd"),
        os.path.join(ROOT, "data", "*.json"),
        os.path.join(ROOT, "*.tscn"),
        os.path.join(ROOT, "project.godot"),
    ]
    files: list[str] = []
    for pat in patterns:
        files.extend(glob.glob(pat, recursive=True))

    for path in files:
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        for ch in text:
            if ord(ch) > 0x7F:
                chars.add(ch)

    print(f"扫描 {len(files)} 个文件")
    return "".join(sorted(chars))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hello", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(SRC):
        print(f"缺少源字体：{SRC}", file=sys.stderr)
        print("下载：https://raw.githubusercontent.com/googlefonts/noto-cjk/main/"
              "Sans/SubsetOTF/SC/NotoSansSC-Regular.otf", file=sys.stderr)
        return 1

    text = collect(args.hello)
    print(f"保留字符 {len(text)} 个")

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables = ["DSIG"]

    font = subset.load_font(SRC, opts)
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(text=text)
    subsetter.subset(font)
    subset.save_font(font, DST, opts)

    src_kb = os.path.getsize(SRC) / 1024
    dst_kb = os.path.getsize(DST) / 1024
    print(f"{src_kb:,.0f} KB → {dst_kb:,.0f} KB（{dst_kb / src_kb:.1%}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
