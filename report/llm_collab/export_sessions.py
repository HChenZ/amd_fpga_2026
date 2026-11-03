#!/usr/bin/env python
"""导出本仓库的大模型协作原始记录（只读，不改动任何工具数据库）。

来源（均为本机工具自动保存的原始会话，不做内容改写）：
  - OpenCode: ~/.local/share/opencode/opencode.db（先复制到临时目录再读）
  - Claude Code: ~/.claude/projects/<本仓库>/*.jsonl
  - Codex: ~/.codex/sessions/**/*.jsonl（按 cwd 过滤本仓库）

输出：
  sessions/<日期>_<工具>_<短ID>.md   每个会话一份：用户提示词原文、模型回答正文、工具调用摘要
  index.md                           会话清单与统计
仅做以下处理：工具输出（命令回显、文件内容）折叠为一行摘要；超长回答保留首尾；疑似密钥按正则打码；
OMIT_PROMPTS 列出的与工程无关的提示只保留轮次、省略原文。
为在 GitHub 上正确渲染，另做只改标记、不改文字的处理（md_safe / code_span）：工具调用摘要放进行内代码；
正文代码以外，GitHub 会剥除的 HTML 样式标签与可能配成删除线的单个 ~ 加反斜杠转义；
因中文标点无法被 GitHub 识别的 **粗体** 改写为 <strong>。
用法：python -X utf8 report/llm_collab/export_sessions.py [--tool codex] [--full-text]
增量更新：保留其他设备/工具的既有 Markdown 和索引；时间统一为 Asia/Shanghai。
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import shutil
import sqlite3
import string
import tempfile
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
OUT = HERE / "sessions"
HOME = Path(os.path.expanduser("~"))
REPO_KEY = "amd_fpga_2026"

SECRET = re.compile(r"(sk-[A-Za-z0-9_\-]{16,}|ghp_[A-Za-z0-9]{20,}|xox[bp]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16})")
MAX_TEXT = 6000          # 单条回答超长时截断（保留首尾），全文仍在原始工具数据中
# 与工程内容无关、经项目方决定省略的用户提示：(会话 ID, 提示开头)。只替换提示正文，保留该轮次与计数。
OMIT_PROMPTS = {("ses_e74984c85ffeYhQ8kkpMuEl9y9", "请你看一看这个想法，我认为可以的，你可以采用当前项目的历史记录")}
OMIT_NOTE = "（本条提示与工程内容无关，导出时省略原文。）"


def omitted(sid: str, text: str) -> bool:
    return any(sid == s and (text or "").lstrip().startswith(p) for s, p in OMIT_PROMPTS)


def clean(text: str) -> str:
    text = SECRET.sub("[REDACTED]", text or "")
    text = "\n".join(line.rstrip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"))
    if MAX_TEXT and len(text) > MAX_TEXT:
        text = text[:MAX_TEXT // 2] + "\n\n…（中间省略 %d 字）…\n\n" % (len(text) - MAX_TEXT) + text[-MAX_TEXT // 2:]
    return text.strip()


def ts(ms: float | None) -> str:
    if not ms:
        return "?"
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone(dt.timedelta(hours=8))).strftime("%Y-%m-%d %H:%M")


# ------------------------------------------------------------------ GitHub 渲染安全（只改标记，不改文字）
# GitHub 允许保留的 HTML 元素；其余标签会被剥除，所以正文中出现时按文字显示。
GH_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8", "br", "b", "i", "strong", "em", "a", "pre", "code", "img",
           "tt", "div", "ins", "del", "sup", "sub", "p", "ol", "ul", "table", "thead", "tbody", "tfoot", "blockquote",
           "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr", "ruby", "rt", "rp", "li", "tr", "td", "th", "s",
           "strike", "summary", "details", "caption", "figure", "figcaption", "abbr", "bdo", "cite", "dfn", "mark",
           "small", "span", "time", "wbr", "picture", "source", "input"}
_TAG = re.compile(r"(?<!\\)<(?=/?([A-Za-z][A-Za-z0-9-]*)[\s/>])")
_TILDE = re.compile(r"(?<![~\\])~(?!~)")
_FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
# 行首出现即开始 HTML 块的标签（CommonMark 第 6 类）；块内不解析 Markdown，转义会原样露出。
_BLOCK_TAGS = {"address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col",
               "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure",
               "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr",
               "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol",
               "optgroup", "option", "p", "param", "section", "source", "summary", "table", "tbody", "td", "tfoot",
               "th", "thead", "title", "tr", "track", "ul"}
_HTML_LINE = re.compile(r"^ {0,3}<(/?)([A-Za-z][A-Za-z0-9-]*)(?=[\s/>]|$)")


def code_span(text: str) -> str:
    """把任意文字放进 Markdown 行内代码（反引号长度与内容自适应）。"""
    if not text.strip():
        return text
    n = max((len(r) for r in re.findall(r"`+", text)), default=0) + 1
    pad = " " if text[0] == "`" or text[-1] == "`" or (text[0] == " " and text[-1] == " ") else ""
    return "`" * n + pad + text + pad + "`" * n


def _is_space(ch: str) -> bool:
    return ch == "" or ch in "\t\n\f\r" or unicodedata.category(ch) == "Zs"


def _is_punct(ch: str) -> bool:
    return ch != "" and (ch in string.punctuation or unicodedata.category(ch).startswith("P"))


def _segments(s: str):
    """按 CommonMark 规则切出行内代码段，返回 [(是否代码, 文字)]。"""
    segs, i, start = [], 0, 0
    while i < len(s):
        if s[i] == "\\":
            i += 2
            continue
        if s[i] != "`":
            i += 1
            continue
        j = i
        while j < len(s) and s[j] == "`":
            j += 1
        k, close = j, None
        while k < len(s):
            if s[k] != "`":
                k += 1
                continue
            m = k
            while m < len(s) and s[m] == "`":
                m += 1
            if m - k == j - i:
                close = m
                break
            k = m
        if close is None:
            i = j
            continue
        segs += [(False, s[start:i]), (True, s[i:close])]
        i = start = close
    segs.append((False, s[start:]))
    return segs


def _strong_fix(s: str, masked: str) -> str:
    """GitHub 不认的 **粗体**（定界符贴着中文标点）改为 <strong>；成对且可判定时才改。"""
    pos = [m.start() for m in re.finditer(r"(?<!\*)\*\*(?!\*)", masked)]
    if len(pos) % 2:
        return s

    def at(i):
        return masked[i] if 0 <= i < len(masked) else ""

    for o, c in reversed(list(zip(pos[::2], pos[1::2]))):
        if _is_space(at(o + 2)) or _is_space(at(c - 1)):
            continue                      # 贴空格的不是标点问题，原样保留
        nxt, prv = at(o + 2), at(o - 1)
        left = not _is_space(nxt) and (not _is_punct(nxt) or _is_space(prv) or _is_punct(prv))
        prv, nxt = at(c - 1), at(c + 2)
        right = not _is_space(prv) and (not _is_punct(prv) or _is_space(nxt) or _is_punct(nxt))
        if not (left and right):
            s = s[:o] + "<strong>" + s[o + 2:c] + "</strong>" + s[c + 2:]
    return s


def _inline_safe(para: str) -> str:
    segs = _segments(para)
    text = [t for code, t in segs if not code]
    # 段内有会被 GitHub 剥除的标签（多为工具/IDE 注入的 XML 样式文本）时，整段标签都按文字显示。
    escape_tags = any(m.group(1).lower() not in GH_TAGS for t in text for m in _TAG.finditer(t))
    if not escape_tags and any((m := _HTML_LINE.match(ln)) and m.group(2).lower() in _BLOCK_TAGS
                               for ln in para.split("\n")):
        return para                       # 作者写的原始 HTML 块：不解析 Markdown，保持原样
    tildes = sum(len(_TILDE.findall(t)) for t in text)
    out = []
    for code, t in segs:
        if not code:
            if escape_tags:
                t = _TAG.sub(r"\\<", t)
            if tildes >= 2:
                t = _TILDE.sub(r"\\~", t)
        out.append(t)
    s = "".join(out)
    # 粗体配对在转义之后的文字上判断；代码段内容用占位字母遮住，两端反引号保留为标点。
    masked = "".join(t if not code else t[:1] + "x" * (len(t) - 2) + t[-1:] for code, t in _segments(s))
    return _strong_fix(s, masked)


def md_safe(text: str) -> str:
    """对一段 Markdown 正文做 GitHub 渲染安全处理；围栏代码块与行内代码保持原样。"""
    out, para, fence = [], [], ""

    def flush():
        if para:
            out.extend(_inline_safe("\n".join(para)).split("\n"))
            para.clear()

    for line in text.split("\n"):
        m = _FENCE.match(line)
        if m and m.group(1)[0] == "`" and "`" in line.strip()[len(m.group(1)):]:
            m = None                      # ```x``` 是行内代码，不是围栏
        if fence:
            out.append(line)
            run = m.group(1) if m else ""
            if run and run[0] == fence[0] and len(run) >= len(fence) and not line.strip()[len(run):].strip():
                fence = ""
            continue
        if m:
            flush()
            fence = m.group(1)
            out.append(line)
        elif not line.strip():
            flush()
            out.append(line)
        else:
            para.append(line)
    flush()
    return "\n".join(out)


def tool_line(name: str, inp) -> str:
    if isinstance(inp, dict):
        key = next((inp[k] for k in ("path", "command", "pattern", "description", "file_path", "cmd") if k in inp), "")
    else:
        key = inp
    key = SECRET.sub("[REDACTED]", str(key)).replace("\n", " ")[:140]
    return f"- `{name}` {code_span(key)}".rstrip()


# ------------------------------------------------------------------ OpenCode
def opencode_sessions():
    src = HOME / ".local/share/opencode/opencode.db"
    if not src.exists():
        return []
    tmp = Path(tempfile.mkdtemp()) / "oc.db"
    for ext in ("", "-wal", "-shm"):
        if Path(str(src) + ext).exists():
            shutil.copy2(str(src) + ext, str(tmp) + ext)
    con = sqlite3.connect(tmp)
    out = []
    for sid, parent, directory, title, model, created in con.execute(
            "select id, parent_id, directory, title, model, time_created from session_v2 order by time_created"):
        if REPO_KEY not in (directory or ""):
            continue
        turns = []
        for mtype, data in con.execute(
                "select type, data from session_message where session_id=? order by seq", (sid,)):
            d = json.loads(data)
            t = d.get("time", {}).get("created")
            if mtype == "user":
                turns.append(("user", t, d.get("metadata", {}).get("displayText") or d.get("text", ""), []))
            elif mtype == "assistant":
                texts, tools = [], []
                for c in d.get("content", []):
                    if c.get("type") == "text":
                        texts.append(c.get("text", ""))
                    elif c.get("type") == "tool":
                        tools.append(tool_line(c.get("name", "?"), c.get("state", {}).get("input", {})))
                if texts or tools:
                    turns.append(("assistant", t, "\n\n".join(texts), tools))
        m = json.loads(model) if model else {}
        out.append(dict(tool="opencode", id=sid, parent=parent, title=title or "", model=m.get("id", "?"),
                        created=created, turns=turns))
    return out


# ------------------------------------------------------------------ Claude Code
def _claude_content(content):
    texts, tools = [], []
    if isinstance(content, str):
        return content, tools
    for c in content or []:
        if c.get("type") == "text":
            texts.append(c.get("text", ""))
        elif c.get("type") == "tool_use":
            tools.append(tool_line(c.get("name", "?"), c.get("input", {})))
    return "\n\n".join(texts), tools


def claude_sessions():
    base = HOME / ".claude/projects"
    out = []
    for d in base.glob("*"):
        if "amd-fpga-2026" not in d.name.lower():
            continue
        for f in sorted(d.glob("*.jsonl")):
            turns, model, first = [], "?", None
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if r.get("type") not in ("user", "assistant"):
                    continue
                msg = r.get("message", {})
                when = r.get("timestamp")
                t = dt.datetime.fromisoformat(when.replace("Z", "+00:00")).timestamp() * 1000 if when else None
                first = first or t
                text, tools = _claude_content(msg.get("content"))
                if r["type"] == "user":
                    if isinstance(msg.get("content"), list) and all(c.get("type") == "tool_result" for c in msg["content"]):
                        continue          # 工具回显不计为用户提示词
                    turns.append(("user", t, text, []))
                else:
                    model = msg.get("model", model)
                    if text or tools:
                        turns.append(("assistant", t, text, tools))
            if turns:
                out.append(dict(tool="claude-code", id=f.stem, parent="agent" if f.stem.startswith("agent-") else None,
                                title=next((x[2][:40] for x in turns if x[0] == "user"), ""), model=model,
                                created=first, turns=turns))
    return out


# ------------------------------------------------------------------ Codex
def codex_sessions():
    out = []
    for f in sorted([*glob.glob(str(HOME / ".codex/sessions/**/*.jsonl"), recursive=True),
                     *glob.glob(str(HOME / ".codex/archived_sessions/**/*.jsonl"), recursive=True)]):
        lines = Path(f).read_text(encoding="utf-8", errors="replace").splitlines()
        try:
            meta = json.loads(lines[0]).get("payload", {})
        except (IndexError, json.JSONDecodeError):
            continue
        if REPO_KEY not in str(meta.get("cwd", "")).lower():
            continue
        turns, model = [], meta.get("model_provider", "?")
        for line in lines[1:]:
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            p = r.get("payload", {})
            when = r.get("timestamp")
            t = dt.datetime.fromisoformat(when.replace("Z", "+00:00")).timestamp() * 1000 if when else None
            if r.get("type") == "response_item" and p.get("type") == "message":
                text = "\n".join(c.get("text", "") for c in p.get("content", []) if "text" in c)
                if p.get("role") == "user" and not text.lstrip().startswith(("<environment_context", "<user_instructions", "# AGENTS.md", "<external_codex_apps_open_page>")):
                    turns.append(("user", t, text, []))
                elif p.get("role") == "assistant" and p.get("channel") in (None, "final", "commentary") and text:
                    turns.append(("assistant", t, text, []))
            elif r.get("type") == "response_item" and p.get("type") in ("function_call", "local_shell_call", "custom_tool_call"):
                args = p.get("arguments") or p.get("input") or p.get("action", {})
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        pass
                if turns and turns[-1][0] == "assistant":
                    turns[-1][3].append(tool_line(p.get("name", "shell"), args))
                else:
                    turns.append(("assistant", t, "", [tool_line(p.get("name", "shell"), args)]))
        if any(x[0] == "user" for x in turns):
            out.append(dict(tool="codex", id=meta.get("id", Path(f).stem), parent=None,
                            title=next((x[2][:40] for x in turns if x[0] == "user"), ""), model=model,
                            created=turns[0][1], turns=turns))
    return out


# ------------------------------------------------------------------ 输出
def write(sessions):
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for s in sessions:
        # 标题取第一条真实提示词，去掉 IDE/命令注入的标签
        first = next((re.sub(r"<[^>]+>[^<]*</[^>]+>|<[^>]+>", " ", x[2]).strip()
                      for x in s["turns"] if x[0] == "user" and not x[2].lstrip().startswith(("<local-command", "<command-"))), "")
        s["title"] = s["title"] if s["tool"] == "opencode" else re.sub(r"\s+", " ", first.split("## My request:")[-1].strip())[:40]
    for s in sorted(sessions, key=lambda s: s["created"] or 0):
        day = ts(s["created"])[:10].replace("-", "") if s["created"] else "unknown_date"
        name = f"{day}_{s['tool']}_{re.sub(r'[^a-z0-9]', '', s['id'].lower())[-8:]}.md"
        users = [x for x in s["turns"] if x[0] == "user"]
        ntools = sum(len(x[3]) for x in s["turns"])
        lines = [f"# {s['title'] or '(无标题)'}", "",
                 f"- 工具：{s['tool']}；模型：{s['model']}；会话：`{s['id']}`" + ("（子代理）" if s["parent"] else ""),
                 f"- 开始：{ts(s['created'])}；用户提示 {len(users)} 条；工具调用 {ntools} 次", ""]
        for role, t, text, tools in s["turns"]:
            if role == "user":
                body = OMIT_NOTE if omitted(s["id"], text) else md_safe(clean(text))
                lines += [f"## 用户提示（{ts(t)}）", "", body, ""]
            else:
                if text.strip():
                    lines += [f"### 模型回答（{ts(t)}）", "", md_safe(clean(text)), ""]
                if tools:
                    lines += ["<details><summary>工具调用 %d 次</summary>" % len(tools), ""] + tools + ["", "</details>", ""]
        (OUT / name).write_text("\n".join(lines), encoding="utf-8", newline="\n")
        kind = ("子代理" if s["parent"] else "主会话") if ntools else "问答/环境自检"
        rows.append((ts(s["created"]), s["tool"], s["model"], kind,
                     len(users), ntools, s["title"].replace("|", "/")[:40], name))
    # Other machines/tools may not exist here. Keep their exports and index rows.
    written = {r[7] for r in rows}
    previous = HERE / "index.md"
    if previous.exists():
        for line in previous.read_text(encoding="utf-8").splitlines():
            cols = [c.strip() for c in line.strip("|").split("|")]
            if len(cols) != 8 or not cols[4].isdigit() or not cols[5].isdigit():
                continue
            match = re.search(r"\(sessions/([^/)]+)\)", cols[7])
            if match and match[1] not in written and (OUT / match[1]).is_file():
                rows.append((*cols[:4], int(cols[4]), int(cols[5]), cols[6], match[1]))
    rows.sort(key=lambda r: (r[0], r[7]))
    work = [r for r in rows if r[5]]
    idx = ["# 大模型协作原始记录索引（自动导出）", "",
           "由 `export_sessions.py` 从本机工具会话库只读导出；提示词与回答为原文，"
           "统一换行并去除行尾空白；工具输出仅保留调用摘要；本次刷新记录的提示词和可见回答按 --full-text 选项决定是否截断，既有导出保留原截断边界；打码疑似密钥，并省略 1 条与工程无关的用户提示原文（保留轮次与计数）。"
           "为在 GitHub 上正确渲染，另做只改标记、不改文字的处理：工具调用摘要放进行内代码，"
           "正文中会被剥除的 HTML 样式标签和单个 `~` 加转义，贴着中文标点而失效的 `**粗体**` 改写为 `<strong>`；"
           "2026-10-30 那次导出的逐字节原件见 `archive/evidence/raw_records_20261102.zip`。"
           "公开前请人工复核隐私信息。", "",
           f"导出时间 {dt.datetime.now(dt.timezone(dt.timedelta(hours=8))):%Y-%m-%d %H:%M}（Asia/Shanghai）。会话 {len(rows)} 个，其中有工具调用的工程会话 {len(work)} 个"
           f"（用户提示 {sum(r[4] for r in work)} 条、工具调用 {sum(r[5] for r in work)} 次）；"
           "其余为无工具调用的问答或模型/工具自检，一并保留，不删除。", "",
           "范围限制：保留既有导出，本次仅刷新所选工具在本机保存的项目会话（Codex 含 archived_sessions）；不含未保存或其他设备上的对话。当前会话仅截至导出时，工具输出为摘要，图片不内嵌，系统/开发者指令及隐藏推理不导出。", "",
           "| 开始时间 | 工具 | 模型 | 类型 | 提示 | 工具调用 | 标题 | 文件 |", "|---|---|---|---|---:|---:|---|---|"]
    idx += [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | [{r[7]}](sessions/{r[7]}) |" for r in rows]
    (HERE / "index.md").write_text("\n".join(idx) + "\n", encoding="utf-8")
    print("exported", len(rows), "sessions ->", OUT)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", choices=["all", "codex", "claude-code", "opencode"], default="all")
    parser.add_argument("--full-text", action="store_true", help="不截断提示词和可见回答；工具调用仍为摘要")
    args = parser.parse_args()
    if args.full_text:
        MAX_TEXT = 0
    selected = {"opencode": opencode_sessions, "claude-code": claude_sessions, "codex": codex_sessions}
    write([s for name, reader in selected.items() if args.tool in ("all", name) for s in reader()])
