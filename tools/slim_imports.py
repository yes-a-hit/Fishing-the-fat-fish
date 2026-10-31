"""把 assets 下所有 lossless 导入的纹理改成有损压缩，并清掉 promo 的缓存。

Godot 的 .webp / .png 默认 compress/mode=0（无损），一张 47 KB 的 webp
能编译成几百 KB 的 .ctex。改完 mode 必须删掉旧 .ctex，否则不会重编。

promo/ 是宣发图，只给 itch / bilibili 用，不该进 pck。已放 .gdignore，
但图片是在加 .gdignore 之前导入的，缓存和 .import 还在，得手动清。
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(".")
CACHE = ROOT / ".godot" / "imported"

MODE_RE = re.compile(r"^compress/mode=\d+$", re.M)
LOSSY_RE = re.compile(r"^compress/lossy_quality=[\d.]+$", re.M)


def bump(import_file: pathlib.Path) -> bool:
    text = import_file.read_text(encoding="utf-8")
    if "compress/mode=0" not in text:
        return False
    text = MODE_RE.sub("compress/mode=1", text, count=1)
    if LOSSY_RE.search(text):
        text = LOSSY_RE.sub("compress/lossy_quality=0.85", text, count=1)
    else:
        text = text.rstrip("\n") + "\ncompress/lossy_quality=0.85\n"
    import_file.write_text(text, encoding="utf-8")
    return True


def drop_cache(stem: str) -> int:
    """删掉 .godot/imported 里对应这个源文件的全部缓存文件。"""
    n = 0
    for f in CACHE.glob(stem + "-*"):
        f.unlink()
        n += 1
    return n


def main() -> int:
    changed = 0
    killed = 0

    # 1. assets 下所有还无损的，改成有损
    for imp in ROOT.glob("assets/**/*.import"):
        if bump(imp):
            changed += 1
            src_name = imp.name[: -len(".import")]
            killed += drop_cache(src_name)

    # 2. promo 整目录移出构建：删 .import 与缓存
    promo = ROOT / "promo"
    if promo.exists():
        for imp in promo.glob("*.import"):
            src_name = imp.name[: -len(".import")]
            killed += drop_cache(src_name)
            imp.unlink()
            print("promo 清理:", imp.name)

    print(f"改了 {changed} 个 .import，删了 {killed} 个缓存文件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
