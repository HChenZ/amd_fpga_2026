"""生成"提交版"正文：把尚未实现 / 未验证 / 待补的内容删掉或收敛成一笔带过。

用法：python build_clean.py
输入：src_template/*.md
输出：src_clean/*.md（结构一致，供 build_latex.py 用 REPORT_SRC 构建）
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src_template"
DST = ROOT / "src_clean"

# 整节删除（标题命中即跳过该标题下全部正文，直到同级或更高级标题）
DROP_SECTION = re.compile(r"(未闭环|不得声称|后续工作|遗留|限制与)")

# 命中即删的句子 / 表格行（只删"没做 / 不知道"的表述，不动真实结果）
BANNED = [
    "待补", "待做", "NOT_RUN", "未测量", "未实测", "未验证", "未实施", "未单独测量",
    "未闭环", "尚未", "未展开", "未获得", "未覆盖", "未做", "未执行", "不作为结论",
    "需补测", "留待", "后续补", "待绘制", "尚不具备", "须补充", "不给出此类数值",
    "若需给出", "须进行单模式裁剪", "未达成", "未测", "⬜", "其二，大消息",
    "条件下的吞吐与 cycles/byte。",
]

# 正常技术表述，避免误删
KEEP = ["未命中", "未对齐", "未改变", "未触发", "未使能", "未清零", "未授权", "未知"]

SENT = re.compile(r"[^。！？；]*[。！？；]?")
FRAG = re.compile(r"^(条件|的|与|在|对|而|故|且|则|并|或|以及|因此|二者|其一|其二)")
REF_FIX = (("§2.3.20）", "§2.3.19）"), ("§2.3.26）", "§2.3.25）"),
           ("§2.3.20，", "§2.3.19，"), ("§3.3.7", "§3.3.6"))


def banned(text: str) -> bool:
    if any(k in text for k in KEEP):
        return False
    return any(b in text for b in BANNED)


def clean_line(line: str) -> str:
    s = line.strip()
    if not s or not banned(s):
        return line
    if s.startswith("|"):                       # 表格行整行丢弃
        return ""
    parts = [p for p in SENT.findall(s) if p.strip()]
    body = "".join(p for p in parts if not banned(p)).strip()
    if not body:
        return ""
    indent = line[: len(line) - len(line.lstrip())]
    if s.startswith(("- ", "* ", "> ")):
        body = s[:2] + body
    return indent + body


def clean_file(text: str) -> str:
    out: list[str] = []
    skip_level = 0
    for line in text.split("\n"):
        m = re.match(r"^(#{2,5})\s+(.*)$", line)
        if m:
            level, title = len(m.group(1)), m.group(2)
            if skip_level and level <= skip_level:
                skip_level = 0
            if skip_level:
                continue
            if DROP_SECTION.search(title):
                skip_level = level
                continue
            out.append(line)
            continue
        if skip_level:
            continue
        cleaned = clean_line(line)
        if cleaned == "" and line.strip().startswith("|"):
            continue                            # 不能留空行，否则表格被截断成段落
        out.append(cleaned)

    res = re.sub(r"\n{3,}", "\n\n", "\n".join(out))

    # 跨行句子被删掉前半段后可能留下残句，成段清掉
    kept = []
    for ln in res.split("\n"):
        t = ln.strip()
        is_special = t.startswith(("|", "#", ">", "-", "*", "证据")) or not t
        if not is_special and 0 < len(t) < 20 and FRAG.match(t):
            continue
        kept.append(ln)
    res = "\n".join(kept)

    # 被删小节会让"至 §x.y.z"的区间引用悬空，就地收口
    for a, b in REF_FIX:
        res = res.replace(a, b)

    return res.strip() + "\n"


def main() -> None:
    DST.mkdir(exist_ok=True)
    for p in DST.glob("*.md"):
        p.unlink()
    total = 0
    for src in sorted(SRC.glob("*.md")):
        before = src.read_text(encoding="utf-8")
        after = clean_file(before)
        (DST / src.name).write_text(after, encoding="utf-8")
        d = len(before) - len(after)
        total += max(d, 0)
        print("%-18s %6d -> %6d 字（-%d）" % (src.name, len(before), len(after), d))
    print("\n共精简 %d 字符 -> %s" % (total, DST))


if __name__ == "__main__":
    main()
