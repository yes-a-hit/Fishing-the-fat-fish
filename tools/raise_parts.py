"""把 NavalArt 存档里所有零件的挂载点整体抬高若干米。

存档是 XML，每个零件有一个 <position x=".." y=".." z=".." />。
船体的形状写在 <vertexData> 里，那是**相对零件挂载点的局部坐标**
（实测 ay 只在 -1~3 之间，而 position 的 y 从 -12 跨到 41），
所以只动 position 的 y，顶点数据一律不碰 —— 碰了就变形。

用法：python raise_parts.py "存档路径" 3.0
"""

import pathlib
import re
import shutil
import sys

# 只匹配 <position ...> 标签内部，别误伤 <rotation> 或 vertexData 里的 y
POS_RE = re.compile(r'(<position\s+x="[^"]*"\s+y=")([^"]*)(")')


def fmt(v: float) -> str:
    """Godot 那边吃 float，给够精度就行，不追求还原原始字符串。"""
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return s if s else "0"


def raise_within(text: str, dy: float) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        try:
            old = float(m.group(2))
        except ValueError:
            return m.group(0)
        count += 1
        return m.group(1) + fmt(old + dy) + m.group(3)

    return POS_RE.sub(repl, text), count


def main() -> int:
    if len(sys.argv) < 3:
        print('用法: python raise_parts.py "存档路径" 3.0')
        return 2
    src = pathlib.Path(sys.argv[1])
    dy = float(sys.argv[2])

    if not src.exists():
        print("找不到:", src)
        return 1

    backup = src.with_suffix(src.suffix + ".bak-lift")
    if not backup.exists():
        shutil.copy2(src, backup)
        print("已备份:", backup.name)
    else:
        print("备份已存在，跳过:", backup.name)

    text = src.read_text(encoding="utf-8")
    out, n = raise_within(text, dy)
    src.write_text(out, encoding="utf-8")
    print(f"{src.name}: 抬了 {n} 个零件，每个 +{dy} 米")
    return 0


if __name__ == "__main__":
    sys.exit(main())
