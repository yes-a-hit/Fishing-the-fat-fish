"""把 UI 脚本里的中文字面量包进 tr()，供 Godot 的 TranslationServer 查表。

只在 scripts/ui/ 下跑。跳过：
  - 已经有 tr(...) 包裹的
  - 以 ## 或 # 开头的注释行
  - 形如 key 的短标识（length <= 1）
"""

import pathlib
import re
import sys

CJK = re.compile(r'[\u4e00-\u9fa5]')
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')

TARGETS = [
    "scripts/ui/settings_root.gd",
    "scripts/ui/ending_overlay.gd",
    "scripts/ui/hud_view.gd",
    "scripts/ui/cast_panel.gd",
    "scripts/ui/qte_overlay.gd",
    "scripts/ui/story_overlay.gd",
    "scripts/ui/about_root.gd",
    "scripts/ui/gallery_root.gd",
    "scripts/ui/game_root.gd",
]


def wrap_line(line: str) -> str:
    stripped = line.lstrip()
    if stripped.startswith("#"):
        return line

    out = []
    i = 0
    while i < len(line):
        if line[i] != '"':
            out.append(line[i])
            i += 1
            continue
        m = STR.match(line, i)
        if not m:
            out.append(line[i])
            i += 1
            continue
        literal = m.group(0)
        inner = m.group(1)
        # 前面紧邻 tr( 的跳过
        head = "".join(out)
        if head.rstrip().endswith("tr(") or head.rstrip().endswith("tr ("):
            out.append(literal)
        elif CJK.search(inner):
            out.append("tr(" + literal + ")")
        else:
            out.append(literal)
        i = m.end()
    return "".join(out)


def main() -> int:
    root = pathlib.Path(".")
    changed = []
    for rel in TARGETS:
        p = root / rel
        if not p.exists():
            print("SKIP (missing)", rel)
            continue
        src = p.read_text(encoding="utf-8")
        lines = src.split("\n")
        new_lines = [wrap_line(ln) for ln in lines]
        dst = "\n".join(new_lines)
        if dst != src:
            p.write_text(dst, encoding="utf-8")
            n = sum(1 for a, b in zip(lines, new_lines) if a != b)
            changed.append((rel, n))
            print("OK  ", rel, "改了", n, "行")
        else:
            print("SAME", rel)
    if not changed:
        print("没有需要改的")
    return 0


if __name__ == "__main__":
    sys.exit(main())
