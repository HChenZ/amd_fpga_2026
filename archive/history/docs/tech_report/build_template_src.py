"""按《技术报告模板》五部分重排 src/*.md -> src_template/。

- 正文一律原样搬运（不改写文字），仅更换标题层级与编号；
- 正文中的 §x.y 交叉引用按 REMAP 改号；若新编号在两个部分中重复，则加"第 N 部分"前缀；
- 模板要求但原稿没有的章节，取自 src_template/new/*.md。
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
NEW = ROOT / "src_template" / "new"
OUT = ROOT / "src_template"

# ---------------------------------------------------------------- 解析原稿
HEAD_RE = re.compile(r"^(#{2,5})\s+(.+?)(\s*\{\.unnumbered\})?\s*$")
NUM_RE = re.compile(r"^(\d+(?:\.\d+)*|[A-Z](?:\.\d+)?)\s+(.*)$")


def parse_sections() -> tuple[dict[str, str], dict[str, str], list[str]]:
    """返回 (编号->正文, 编号->标题, 文档顺序)。标题中已去编号。"""
    bodies: dict[str, str] = {}
    titles: dict[str, str] = {}
    order: list[str] = []
    for f in sorted(SRC.glob("*.md")):
        lines = f.read_text(encoding="utf-8").split("\n")
        cur_key, cur_lines, level = None, [], 0

        def flush():
            if cur_key is None:
                return
            body = "\n".join(cur_lines).strip("\n")
            bodies[cur_key] = body
            order.append(cur_key)

        for ln in lines:
            m = HEAD_RE.match(ln)
            if m and len(m.group(1)) >= 3:
                flush()
                title = m.group(2).strip()
                nm = NUM_RE.match(title)
                if nm:
                    cur_key, titles[cur_key] = nm.group(1), nm.group(2).strip()
                else:
                    cur_key, titles[cur_key] = title, title
                cur_lines, level = [], len(m.group(1))
            elif m and len(m.group(1)) == 2:
                flush()
                cur_key, cur_lines = None, []
                title = m.group(2).strip()
                nm = NUM_RE.match(title)
                if nm:
                    cur_key = nm.group(1)
                    titles[cur_key] = nm.group(2).strip()
                else:
                    cur_key = title
                    titles[cur_key] = title
            else:
                if cur_key is not None:
                    cur_lines.append(ln)
        flush()
    return bodies, titles, order


# ---------------------------------------------------------------- 编号映射
# 旧编号 -> 新完整编号。新编号以部分号开头（1.1、2.2.3.1…），全文唯一，无需再加“第 N 部分”前缀。
REMAP: dict[str, str] = {}
for k in range(2, 11):
    REMAP[f"2.{k}"] = f"2.2.{k+1}"          # CPU 各单元：2.2 处理器架构与设计思路
for k in range(1, 6):
    REMAP[f"3.{k}"] = f"2.3.3.{k}"
for k in range(1, 7):
    REMAP[f"8.{k}"] = f"2.3.3.{k+5}"
for k in range(1, 4):
    REMAP[f"7.{k}"] = f"2.3.4.{k}"
for k in range(1, 8):
    REMAP[f"5.{k}"] = f"3.3.3.{k}"
for k in range(1, 6):
    REMAP[f"6.{k}"] = f"3.3.4.{k}"
REMAP.update({
    "1.1": "1.1",
    "1.2": "附录 D.1",
    "1.3": "2.4.1",
    "1.4": "附录 D.2",
    "1.5": "附录 D.3",
    "2.1": "2.1",
    "4.1": "2.3.1",
    "4.2": "3.3.1",
    "4.3": "3.3.2",
    "4.4": "3.2.1",
    "4.5": "3.2.2",
    "8": "2.3.3.6–2.3.3.11",   # 原第 8 章（PS/PL 与 PYNQ）整体
    "9.1": "3.3.5",
    "9.2": "4.1",
    "9.3": "4.2",
})
AMBIGUOUS: set[str] = set()


def rewrite_refs(text: str) -> str:
    def rep(m):
        old = m.group(1)
        if old not in REMAP:
            return m.group(0)
        new = REMAP[old]
        return new if new.startswith("附录") else f"§{new}"

    # 证据标记中的 §n 属于被引用文档，而非本稿，不应随重排改号。
    return re.sub(
        r'<span class="evid">.*?</span>|§(\d+(?:\.\d+)*)',
        lambda m: m.group(0) if m.group(1) is None else rep(m), text, flags=re.S)


def get(spec: str) -> str:
    """spec: 'new:xxx' 或 'sec:2.2[|标题覆盖]'。"""
    if spec.startswith("new:"):
        return rewrite_refs((NEW / (spec[4:] + ".md")).read_text(encoding="utf-8").strip())
    key = spec[4:]
    if "|" in key:
        key, _ = key.split("|", 1)
    b = BODIES.get(key)
    if b is None:
        raise KeyError(f"缺少原稿小节 {key}")
    result = rewrite_refs(b)
    if key == "附录 C 证据索引":
        raw = (ROOT / "evidence/appendix_c_raw.md").read_text(encoding="utf-8")
        result += "\n\n" + raw.split("\n", 1)[1]
    return result


BODIES, TITLES, ORDER = parse_sections()

_NEEDED = (["1.1", "1.2", "1.3", "1.4", "1.5", "2.1", "9.1", "9.2", "9.3"]
           + [f"2.{k}" for k in range(2, 11)]
           + [f"3.{k}" for k in range(1, 6)]
           + [f"5.{k}" for k in range(1, 8)]
           + [f"6.{k}" for k in range(1, 6)]
           + [f"7.{k}" for k in range(1, 4)]
           + [f"8.{k}" for k in range(1, 7)]
           + [f"B.{k}" for k in range(1, 5)])
_missing = [k for k in _NEEDED if k not in BODIES]
if _missing:
    print("!! src/ 缺少模板映射需要的小节：%s" % "、".join(_missing))
    print("   src/*.md 已被他人更新（章节结构变了）。现有 src_template/ 仍是上一版结构，")
    print("   可直接用 build_latex.py 构建；若要按新内容重排，请先确认这些小节的去向再改 TREE。")
    raise SystemExit(2)

# ---------------------------------------------------------------- 目标结构
TREE = [
    ("摘要", "section*", ["sec:摘要"] if "摘要" in BODIES else ["new:p1_1"]),

    # 标题编号一律带部分号（1.1、2.2.3.1…）；字数按《技术报告模板》限制控制在对应 new/*.md 中
    ("第一部分 作品概述", "chapter", [
        ("1.1 功能与特性", "section", ["new:p1_1", "sec:1.1"]),
        ("1.2 应用领域", "section", ["new:p1_2"]),
        ("1.3 主要技术特点", "section", ["new:p1_3"]),
        ("1.4 主要性能指标", "section", ["new:p1_4"]),
        ("1.5 主要创新点", "section", ["new:p1_5"]),
        ("1.6 设计流程", "section", ["new:p1_6"]),
    ]),
    ("第二部分 系统组成及功能说明", "chapter", [
        ("2.1 整体介绍", "section", ["sec:2.1"]),
        # 处理器单列一节：设计思路、微架构图与各单元
        ("2.2 处理器架构与设计思路", "section", [
            ("2.2.1 设计目标与总体思路", "subsection", ["new:p2_2_1"]),
            ("2.2.2 流水线微架构", "subsection", ["new:p2_2_2"]),
            *[(f"2.2.{k+1} {TITLES[f'2.{k}']}", "subsection", [f"sec:2.{k}"]) for k in range(2, 11)],
        ]),
        ("2.3 硬件系统介绍", "section", [
            ("2.3.1 硬件整体介绍", "subsection", ["sec:4.1"]),
            ("2.3.2 机械设计介绍", "subsection", ["new:p2_2"]),
            ("2.3.3 电路各模块介绍", "subsection", [
                "new:p2_3_intro",
                *[(f"2.3.3.{k} {TITLES[f'3.{k}']}", "subsubsection", [f"sec:3.{k}"]) for k in range(1, 6)],
                *[(f"2.3.3.{k+5} {TITLES[f'8.{k}']}", "subsubsection", [f"sec:8.{k}"]) for k in range(1, 7)],
            ]),
            ("2.3.4 独立扩展原型：RO-PUF 与器件绑定通路", "subsection", [
                "sec:7",
                *[(f"2.3.4.{k} {TITLES[f'7.{k}']}", "subsubsection", [f"sec:7.{k}"]) for k in range(1, 4)],
            ]),
        ]),
        ("2.4 软件系统介绍", "section", [
            ("2.4.1 软件整体介绍", "subsection", ["new:p2_3_1", "sec:1.3"]),
            ("2.4.2 软件各模块介绍", "subsection", [
                ("2.4.2.1 纯软件 AEAD 固件", "subsubsection", ["new:p2_3_2_1"]),
                ("2.4.2.2 MMIO 加速器驱动固件", "subsubsection", ["new:p2_3_2_2"]),
                ("2.4.2.3 定制指令固件", "subsubsection", ["new:p2_3_2_3"]),
                ("2.4.2.4 当前 benchmark 与采样工具", "subsubsection", ["new:p2_3_2_4"]),
                ("2.4.2.5 PS 端服务与帧协议", "subsubsection", ["new:p2_3_2_5"]),
            ]),
        ]),
        # 选题指南 3.3.5.3：大模型协作记录、技能包提炼过程
        ("2.5 大模型协作与技能包", "section", [
            ("2.5.1 协作分工与智能体工作流", "subsection", ["new:p2_4_1"]),
            ("2.5.2 代表性协作记录与纠错轨迹", "subsection", ["new:p2_4_2"]),
            ("2.5.3 技能包的提炼与验证", "subsection", ["new:p2_4_3"]),
            ("2.5.4 原始记录的导出与范围", "subsection", ["new:p2_4_4"]),
        ]),
    ]),
    ("第三部分 完成情况及性能参数", "chapter", [
        ("3.1 整体介绍", "section", ["new:p3_1"]),
        ("3.2 工程成果", "section", [
            "new:p3_2",
            ("3.2.1 资源占用", "subsection", ["sec:4.4"]),
            ("3.2.2 可复现性与产物冻结", "subsection", ["sec:4.5"]),
        ]),
        ("3.3 特性成果", "section", [
            "new:p3_3_intro",
            ("3.3.1 时序收敛结果", "subsection", ["sec:4.2"]),
            ("3.3.2 时钟与 IO 的适用范围", "subsection", ["sec:4.3"]),
            ("3.3.3 功能验证", "subsection", [
                *[(f"3.3.3.{k} {TITLES[f'5.{k}']}", "subsubsection", [f"sec:5.{k}"]) for k in range(1, 8)],
            ]),
            ("3.3.4 性能量化", "subsection", [
                *[(f"3.3.4.{k} {TITLES[f'6.{k}']}", "subsubsection", [f"sec:6.{k}"]) for k in range(1, 6)],
            ]),
            ("3.3.5 完成度与判据矩阵", "subsection", ["sec:9.1"]),
        ]),
        # 选题指南 3.3.5.3：可供他人从零执行的复现说明
        ("3.4 复现说明", "section", [
            ("3.4.1 环境与版本", "subsection", ["new:p3_4_1"]),
            ("3.4.2 主机验证与仿真回归", "subsection", ["new:p3_4_2"]),
            ("3.4.3 固件与比特流构建", "subsection", ["new:p3_4_3"]),
            ("3.4.4 上板运行", "subsection", ["new:p3_4_4"]),
            ("3.4.5 复现边界", "subsection", ["new:p3_4_5"]),
        ]),
    ]),
    ("第四部分 总结", "chapter", [
        ("4.1 可扩展之处", "section", ["new:p4_1"]),
        ("4.2 心得体会", "section", ["sec:9.3"]),
    ]),
    ("第五部分 参考文献", "chapter", ["sec:附录 D 参考文献"]),
    ("附录 A 术语与缩写", "appendix", ["sec:附录 A 术语与缩写"]),
    ("附录 B 地址映射与指令编码", "appendix", [
        "sec:附录 B 地址映射与指令编码",
        *[(TITLES[f"B.{k}"], "subsection", [f"sec:B.{k}"]) for k in range(1, 5)],
    ]),
    ("附录 C 证据索引", "appendix", ["sec:附录 C 证据索引"]),
    # 原第一部分 6.1–6.3：设计流程限 200 字，细节移入附录，正文不删改
    ("附录 D 研制历程、证据分级与统计口径", "appendix", [
        ("研制历程", "subsection", ["sec:1.2"]),
        ("设计准则与证据分级", "subsection", ["sec:1.4"]),
        ("术语与统计口径", "subsection", ["sec:1.5"]),
    ]),
]

def _numbers_in_tree() -> set[str]:
    """统计目标结构中每个编号出现的部分，跨部分重复者需加前缀。"""
    counts: dict[str, set[str]] = {}

    def walk(node, part: str) -> None:
        if isinstance(node, str):
            return
        title, kind, children = node
        nm = NUM_RE.match(title)
        if nm and kind not in ("chapter", "appendix"):
            counts.setdefault(nm.group(1), set()).add(part)
        for ch in children:
            walk(ch, part)

    for node in TREE:
        walk(node, node[0] if not isinstance(node, str) else "前言")
    return {n for n, ps in counts.items() if len(ps) > 1}


AMBIGUOUS |= _numbers_in_tree()

HASH = {"chapter": "##", "section": "###", "subsection": "####",
        "subsubsection": "#####", "appendix": "##", "section*": "##"}


def render(node, out: list[str]):
    if isinstance(node, str):
        out.append(get(node))
        out.append("")          # 与后续标题之间必须有空行，否则会被并入段落
        return
    title, kind, children = node
    unnum = " {.unnumbered}" if kind in ("appendix", "section*") else ""
    out.append(f"{HASH[kind]} {title}{unnum}")
    out.append("")
    for ch in children:
        render(ch, out)
    out.append("")


TABLE_ROW = re.compile(r"^\|[\s:\-|]+\|$")
PART_NO = {"一": "1", "二": "2", "三": "3", "四": "4", "五": "5"}
# 小节标题过于笼统时为表指定标题：(所在标题, 该标题下第几张表) -> 表题
TABLE_TITLE_OVERRIDE = {
    ("2.1 整体介绍", 0): "处理器功能单元组成",
    ("3.1 整体介绍", 0): "整体完成情况",
    ("3.2 工程成果", 0): "工程成果清单",
    ("2.4.1 软件整体介绍", 0): "设计平台与工具链",
    ("2.2.1 设计目标与总体思路", 0): "处理器设计取舍",
    ("附录 C 证据索引", 0): "结论与主要证据对照",
    ("2.2.9 总线与 SoC 外设", 0): "SoC 地址窗口与外设",
    ("2.2.10 流水线控制与冒险处理", 0): "流水线控制事件优先级",
    ("2.3.3.1 算法标准与参数定义", 0): "Ascon-AEAD128 参数",
    ("2.3.3.3 方案二：存储器映射加速器（MMIO／HW）", 0): "MMIO 加速器寄存器",
    ("2.3.3.4 方案三：定制指令扩展（ISE）", 0): "定制指令编码与语义",
    ("2.3.3.6 PS/PL 数据通道方案论证", 0): "PS/PL 数据通道选择依据",
    ("2.3.3.7 结构与寄存器定义", 0): "CONTROL 窗口寄存器",
    ("2.3.3.7 结构与寄存器定义", 1): "MAILBOX 窗口寄存器",
    ("2.3.3.8 服务协议与服务固件", 0): "服务帧类型",
    ("2.3.3.9 Overlay 构建与时序签核", 0): "Overlay 时序与实现结果",
    ("2.3.3.10 验证结果与板上实测", 1): "板上容量内 KAT 与周期统计",
    ("2.3.3.11 未闭环项", 0): "PYNQ 通路未闭环项",
    ("3.2.1 资源占用", 0): "当前 PYNQ 实现时序与 DRC",
    ("3.2.2 可复现性与产物冻结", 0): "发布身份记录",
    ("3.3.1 时序收敛结果", 0): "时序收敛历史记录",
    ("3.3.3.2 L0：标准一致性与向量冻结", 0): "L0 标准一致性检查",
    ("3.3.3.3 L1：模块级 RTL 验证", 0): "L1 模块级 RTL 验证",
    ("3.3.3.4 L2：系统级自动回归", 0): "L2 系统级自动回归",
    ("3.3.3.5 L3：纯 PL 镜像的板级验证", 0): "L3 历史 PL-only 镜像 KAT 与篡改拒绝",
    ("3.3.3.7 未闭环项", 0): "验证未闭环项",
    ("3.3.4.1 当前 PYNQ 固定输入 warm benchmark", 0): "当前 PYNQ 固定输入周期与加速比",
    ("3.3.4.2 PS 调用墙钟与 CPU 周期的区别", 0): "PS 调用中位墙钟",
    ("3.3.4.3 历史 PL-only 基准的独立对照", 0): "历史 PL-only 周期对照",
}


def number_tables(texts: list[str]) -> list[str]:
    """给每张表加表头“表 N-k 标题”，N 为部分号或附录字母，k 在部分内连续。

    表题优先取紧邻表前的加粗短语（如 **CONTROL 窗口**），其次取所在小节标题；
    同一小节内重名时加（一）（二）区分。输出标记 <span class="tabcap">表 N-k</span> **标题**，
    由 build_site 原样显示、build_latex 转为 longtable \\caption 并进入表格目录。
    """
    part, k, head, per_head, seen = None, 0, "", {}, {}
    out_texts = []
    for text in texts:
        lines, out, fence = text.split("\n"), [], False
        for i, ln in enumerate(lines):
            if ln.lstrip().startswith("```"):
                fence = not fence
            if not fence:
                m = re.match(r"^## (?:第([一二三四五])部分|附录 ([A-Z]))", ln)
                if m:
                    part, k, seen = PART_NO.get(m.group(1) or "", m.group(2)), 0, {}
                elif ln.startswith("## "):
                    part = None
                hm = re.match(r"^#{2,5} (.+?)(\s*\{\.unnumbered\})?\s*$", ln)
                if hm:
                    head = hm.group(1).strip()
                    per_head[head] = 0
                is_table = (ln.startswith("|") and i + 1 < len(lines) and TABLE_ROW.match(lines[i + 1].strip())
                            and not (i > 0 and lines[i - 1].startswith("|")))
                if is_table and part:
                    j = len(out) - 1
                    while j >= 0 and not out[j].strip():
                        j -= 1
                    prev = out[j].strip() if j >= 0 else ""
                    bm = re.match(r"^\*\*(.+?)\*\*", prev)
                    idx = per_head.get(head, 0)
                    per_head[head] = idx + 1
                    if (head, idx) in TABLE_TITLE_OVERRIDE:
                        title = TABLE_TITLE_OVERRIDE[(head, idx)]
                    elif bm:
                        title = bm.group(1)
                    else:
                        title = re.sub(r"^(\d+(\.\d+)*|附录 [A-Z]|[A-Z]\.\d+)\s+", "", head)
                    title = title.rstrip("：:。 ")
                    seen[title] = seen.get(title, 0) + 1
                    if seen[title] > 1:
                        title += "（%s）" % "一二三四五六七八九十"[seen[title] - 1]
                    k += 1
                    out += [f'<span class="tabcap">表 {part}-{k}</span> **{title}**', ""]
            out.append(ln)
        out_texts.append("\n".join(out))
    return out_texts


FIGSLOT = re.compile(r'<span class="figslot">图 ([0-9A-Z]+-[0-9]+)</span>')


def number_figures(texts: list[str]) -> list[str]:
    """按出现顺序在各部分内重排图号（图 N-k），并同步改写正文中的“图 x-y”引用。

    图件文件名不变：标记写成 <span class="figslot" data-src="原编号">图 新编号</span>，
    build_latex / verify_report 据 data-src 找到 figs/fig_原编号.pdf。
    """
    mapping, part, k = {}, None, 0
    for text in texts:
        for ln in text.split("\n"):
            m = re.match(r"^## 第([一二三四五])部分", ln)
            if m:
                part, k = PART_NO[m.group(1)], 0
            for fm in FIGSLOT.finditer(ln):
                if part and fm.group(1) not in mapping:
                    k += 1
                    mapping[fm.group(1)] = f"{part}-{k}"
    out = []
    for text in texts:
        text = FIGSLOT.sub(lambda m: '<span class="figslot" data-src="%s">图 %s</span>'
                           % (m.group(1), mapping.get(m.group(1), m.group(1))), text)
        # 正文引用：只改有对应图件的编号；标记内已改过的部分用占位保护
        parts = re.split(r'(<span class="figslot"[^>]*>图 [^<]+</span>)', text)
        parts = [p if p.startswith('<span class="figslot"') else
                 re.sub(r"图 ?([0-9]-[0-9]+)", lambda m: "图 " + mapping.get(m.group(1), m.group(1))
                        if m.group(1) in mapping else m.group(0), p) for p in parts]
        out.append("".join(parts))
    print("图号重排：" + "，".join(f"{a}→{b}" for a, b in mapping.items() if a != b))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "10_part1.md": [TREE[0], TREE[1]],
        "20_part2.md": [TREE[2]],
        "30_part3.md": [TREE[3]],
        "40_part4_5.md": TREE[4:],   # 第四部分、第五部分、附录 A/B/C
    }
    used = set()
    texts = []
    for name, nodes in files.items():
        out: list[str] = []
        for nd in nodes:
            render(nd, out)
        texts.append("\n".join(out))
    for name, text in zip(files, number_figures(number_tables(texts))):
        (OUT / name).write_text(text, encoding="utf-8")
        used.add(name)
    caps = re.findall(r'<span class="tabcap">(表 [^<]+)</span> \*\*(.+?)\*\*', "\n".join((OUT / n).read_text(encoding="utf-8") for n in files))
    print("表格 %d 张：%s" % (len(caps), "；".join(f"{a} {b}" for a, b in caps)))
    # 清理旧生成文件
    for f in OUT.glob("*.md"):
        if f.name not in used:
            f.unlink()
    missing = [k for k in ("1.1", "2.1", "9.3") if k not in BODIES]
    print("生成:", ", ".join(sorted(used)), "| 缺小节省查:", missing or "无")
    print("交叉引用改号样例：", rewrite_refs("见 §2.2、§4.3、§5.5 与 §3.1"))


if __name__ == "__main__":
    main()
