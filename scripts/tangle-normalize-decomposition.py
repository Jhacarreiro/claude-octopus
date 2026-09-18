#!/usr/bin/env python3
from __future__ import annotations
import re, sys

HEAD = re.compile(r"^\s*(?:#{1,6}\s*)?(\d+)[.)]\s*\[(CODING|REASONING)\]\s*(.*?)\s*$", re.I)
LABEL = re.compile(r"^\s*(?:\*\*)?(Reads|Files|Creates|Task|Inputs|Output|Expected output|Verification|Dependencies|Acceptance evidence|Blocks(?: on)?)(?::)?(?:\*\*)?\s*(?::\s*)?(.*)$", re.I)
ACTION = re.compile(r"^\s*((?:Verify|Implement|Update|Document)\b.*?)\s*:\s*$", re.I)
BULLET = re.compile(r"^\s*[-*]\s+(.*)$")
BACKTICK = re.compile(r"`([^`]+)`")

SCOPE_LABELS = {"reads", "files", "creates"}
TASK_SECTIONS = {"task", "output", "expected output", "verification"}
IGNORE_SECTIONS = {"inputs", "dependencies", "acceptance evidence", "blocks", "blocks on"}

def clean_text(s: str) -> str:
    s = re.sub(r"\s+", " ", s.strip())
    # The wire format uses both em dashes and hyphens surrounded by spaces as
    # field separators. Keep provider-controlled prose in a separator-safe
    # representation so Task/title text cannot be truncated on re-parsing.
    return re.sub(r"\s[-—]\s", " | ", s)

def scope_items(text: str) -> list[str]:
    vals = BACKTICK.findall(text)
    if vals:
        # Backticked tokens grant scope only when the surrounding bullet is
        # separators/punctuation. Prose such as "excluding `.env`" is context,
        # not filesystem authority.
        remainder = BACKTICK.sub("", text)
        remainder = re.sub(r"[\s,;:/+&()\[\]-]+", "", remainder)
        if remainder:
            return []
    else:
        vals = [x.strip() for x in re.split(r"[,;]", text)]
    out = []
    for val in vals:
        val = val.strip().strip("`\"'")
        if not val or val.lower() in {"none", "n/a", "na", "nothing", "no-new-files"}:
            continue
        if " " in val and not (val.startswith("/") or val.startswith("./")):
            continue
        if not (
            val.startswith(("/", "./", "../"))
            or "/" in val
            or re.search(r"\.[A-Za-z0-9]{1,8}$", val)
            or "*" in val
            or re.fullmatch(r"[A-Za-z0-9_.@%+-]+", val)
        ):
            continue
        if val not in out:
            out.append(val)
    return out

def parse_block(num: str, kind: str, title: str, lines: list[str]) -> str | None:
    scopes = {"reads": [], "files": [], "creates": []}
    task_parts: list[str] = []
    section = "task"
    for raw in lines:
        line = raw.rstrip()
        if not line.strip() or line.strip() == "---":
            continue
        m = LABEL.match(line)
        if m:
            section = m.group(1).lower()
            inline = m.group(2).strip()
            if section in TASK_SECTIONS:
                if inline:
                    task_parts.append(clean_text(inline))
            elif section in SCOPE_LABELS and inline:
                scopes[section].extend(x for x in scope_items(inline) if x not in scopes[section])
            continue
        a = ACTION.match(line)
        if a:
            section = "task"
            task_parts.append(clean_text(line))
            continue
        b = BULLET.match(line)
        payload = b.group(1).strip() if b else line.strip()
        if section in SCOPE_LABELS:
            for item in scope_items(payload):
                if item not in scopes[section]:
                    scopes[section].append(item)
            continue
        if section in IGNORE_SECTIONS:
            continue
        if payload.startswith("**") and payload.endswith("**"):
            payload = payload.strip("*")
        cleaned = clean_text(BACKTICK.sub(lambda m: m.group(1), payload))
        if cleaned:
            task_parts.append(cleaned)

    if kind.upper() == "CODING" and not (scopes["files"] or scopes["creates"]):
        return None
    task = clean_text(" ".join(task_parts))
    if not task:
        return None
    title = clean_text(title).strip("# ") or f"Subtask {num}"
    parts = [f"{num}. [{kind.upper()}] {title}"]
    for label in ("reads", "files", "creates"):
        if scopes[label]:
            parts.append(f"{label.title()}: {', '.join(scopes[label])}")
    parts.append(f"Task: {task}")
    return " — ".join(parts)

def normalize(text: str) -> list[str]:
    blocks = []
    current = None
    for line in text.splitlines():
        m = HEAD.match(line)
        if m:
            if current:
                blocks.append(current)
            current = [m.group(1), m.group(2), m.group(3), []]
        elif current:
            current[3].append(line)
    if current:
        blocks.append(current)
    if not blocks:
        return []
    out = []
    for num, kind, title, lines in blocks:
        item = parse_block(num, kind, title, lines)
        if not item:
            return []
        out.append(item)
    return out

if __name__ == "__main__":
    rows = normalize(sys.stdin.read())
    if not rows:
        raise SystemExit(1)
    sys.stdout.write("\n".join(rows) + "\n")
