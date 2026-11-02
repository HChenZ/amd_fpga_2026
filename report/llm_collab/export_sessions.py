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
用法：python -X utf8 report/llm_collab/export_sessions.py
"""
from __future__ import annotations

import datetime as dt
import glob
import json
import os
import re
import shutil
import sqlite3
import tempfile
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
    if len(text) > MAX_TEXT:
        text = text[:MAX_TEXT // 2] + "\n\n…（中间省略 %d 字）…\n\n" % (len(text) - MAX_TEXT) + text[-MAX_TEXT // 2:]
    return text.strip()


def ts(ms: float | None) -> str:
    if not ms:
        return "?"
    return dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")


def tool_line(name: str, inp) -> str:
    if isinstance(inp, dict):
        key = next((inp[k] for k in ("path", "command", "pattern", "description", "file_path", "cmd") if k in inp), "")
    else:
        key = inp
    key = str(key).replace("\n", " ")[:140]
    return f"- `{name}` {key}"


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
    for f in sorted(glob.glob(str(HOME / ".codex/sessions/**/*.jsonl"), recursive=True)):
        lines = Path(f).read_text(encoding="utf-8", errors="replace").splitlines()
        try:
            meta = json.loads(lines[0]).get("payload", {})
        except (IndexError, json.JSONDecodeError):
            continue
        if REPO_KEY not in str(meta.get("cwd", "")):
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
                if p.get("role") == "user" and not text.lstrip().startswith(("<environment_context", "<user_instructions", "# AGENTS.md")):
                    turns.append(("user", t, text, []))
                elif p.get("role") == "assistant" and text:
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
    for old in OUT.glob("*.md"):
        old.unlink()
    rows = []
    for s in sessions:
        # 标题取第一条真实提示词，去掉 IDE/命令注入的标签
        first = next((re.sub(r"<[^>]+>[^<]*</[^>]+>|<[^>]+>", " ", x[2]).strip()
                      for x in s["turns"] if x[0] == "user" and not x[2].lstrip().startswith(("<local-command", "<command-"))), "")
        s["title"] = s["title"] if s["tool"] == "opencode" else re.sub(r"\s+", " ", first)[:40]
    for s in sorted(sessions, key=lambda s: s["created"] or 0):
        day = ts(s["created"])[:10].replace("-", "")
        name = f"{day}_{s['tool']}_{re.sub(r'[^a-z0-9]', '', s['id'].lower())[-8:]}.md"
        users = [x for x in s["turns"] if x[0] == "user"]
        ntools = sum(len(x[3]) for x in s["turns"])
        lines = [f"# {s['title'] or '(无标题)'}", "",
                 f"- 工具：{s['tool']}；模型：{s['model']}；会话：`{s['id']}`" + ("（子代理）" if s["parent"] else ""),
                 f"- 开始：{ts(s['created'])}；用户提示 {len(users)} 条；工具调用 {ntools} 次", ""]
        for role, t, text, tools in s["turns"]:
            if role == "user":
                body = OMIT_NOTE if omitted(s["id"], text) else clean(text)
                lines += [f"## 用户提示（{ts(t)}）", "", body, ""]
            else:
                if text.strip():
                    lines += [f"### 模型回答（{ts(t)}）", "", clean(text), ""]
                if tools:
                    lines += ["<details><summary>工具调用 %d 次</summary>" % len(tools), ""] + tools + ["", "</details>", ""]
        (OUT / name).write_text("\n".join(lines), encoding="utf-8")
        kind = ("子代理" if s["parent"] else "主会话") if ntools else "问答/环境自检"
        rows.append((ts(s["created"]), s["tool"], s["model"], kind,
                     len(users), ntools, s["title"].replace("|", "/")[:40], name))
    work = [r for r in rows if r[5]]
    idx = ["# 大模型协作原始记录索引（自动导出）", "",
           "由 `export_sessions.py` 从本机工具会话库只读导出；提示词与回答为原文，"
           "仅折叠工具输出、截断超长回答、打码疑似密钥，并省略 1 条与工程无关的用户提示原文（保留轮次与计数）。"
           "公开前请人工复核隐私信息。", "",
           f"导出时间 {dt.datetime.now():%Y-%m-%d %H:%M}。会话 {len(rows)} 个，其中有工具调用的工程会话 {len(work)} 个"
           f"（用户提示 {sum(r[4] for r in work)} 条、工具调用 {sum(r[5] for r in work)} 次）；"
           "其余为无工具调用的问答或模型/工具自检，一并保留，不删除。", "",
           "范围限制：仅含本机 OpenCode / Claude Code / Codex 保存的会话；队友设备、网页对话及 2026-10-09 前的会话未收录。", "",
           "| 开始时间 | 工具 | 模型 | 类型 | 提示 | 工具调用 | 标题 | 文件 |", "|---|---|---|---|---:|---:|---|---|"]
    idx += [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | [{r[7]}](sessions/{r[7]}) |" for r in rows]
    (HERE / "index.md").write_text("\n".join(idx) + "\n", encoding="utf-8")
    print("exported", len(rows), "sessions ->", OUT)


if __name__ == "__main__":
    write(opencode_sessions() + claude_sessions() + codex_sessions())
