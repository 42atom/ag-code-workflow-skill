#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import shutil
import subprocess
import webbrowser
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

######## workflow constants

DOC_RE = re.compile(
    r"^(?P<kind>tk|pl|rs|rf|rp)"
    r"(?P<digits>\d{4,5})\."
    r"(?P<state>tdo|doi|dne|bkd|cand|arvd)\."
    r"(?P<board>[a-z0-9-]+)\."
    r"(?P<slug>[a-z0-9-]+?)"
    r"(?:\.(?P<priority>p[0-2]))?\.md$"
)
RV_RE = re.compile(
    r"^(?P<issue_id>(?P<issue_kind>tk|pl|rs|rf)(?P<digits>\d{4,5}))\."
    r"(?P<thread>rv[0-9]{3})-"
    r"(?P<round>r[0-9]+)-"
    r"(?P<author>[a-z0-9-]+)\.md$"
)
PROGRESS_RE = re.compile(
    r"^(?P<task_id>tk(?P<digits>\d{4,5}))\."
    r"(?P<step>s[0-9]{2}-[a-z0-9-]+)\."
    r"(?P<state>tdo|doi|dne|bkd)\.md$"
)

STATE_ORDER = ["doi", "bkd", "tdo", "dne", "cand", "arvd"]
STATE_LABEL = {
    "tdo": "待做",
    "doi": "进行中",
    "dne": "已完成",
    "bkd": "阻塞",
    "cand": "已取消",
    "arvd": "已归档",
}
STATE_TONE = {
    "tdo": "todo",
    "doi": "active",
    "dne": "done",
    "bkd": "blocked",
    "cand": "cancelled",
    "arvd": "archive",
}
KIND_LABEL = {
    "tk": "任务",
    "pl": "计划",
    "rs": "研究",
    "rf": "参考",
    "rp": "评审",
    "rv": "评审",
    "pg": "进度",
}
PRIORITY_RANK = {"p0": 0, "p1": 1, "p2": 2, "": 9}
ACTIVE_STATES = {"tdo", "doi", "bkd"}
DONE_STATES = {"dne"}
HISTORY_STATES = {"dne", "cand", "arvd"}


######## filesystem and parsing helpers


def find_project_root(start: Path) -> Path:
    cursor = start.resolve()
    if cursor.is_file():
        cursor = cursor.parent

    for candidate in [cursor, *cursor.parents]:
        if (candidate / "issues").is_dir():
            return candidate

    raise SystemExit("error: run from a project directory that contains issues/ or pass --project-root")


def load_template(script_path: Path, template_override: str | None) -> str:
    if template_override:
        template_path = Path(template_override).expanduser().resolve()
    else:
        template_path = script_path.resolve().parent.parent / "templates" / "progress-view.html"

    try:
        return template_path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"error: template not found: {template_path}") from exc


def strip_quotes(value: str) -> str:
    trimmed = value.strip()
    if len(trimmed) >= 2 and trimmed[0] == trimmed[-1] and trimmed[0] in {"'", '"'}:
        return trimmed[1:-1]
    return trimmed


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text

    frontmatter: dict[str, Any] = {}
    index = 1

    while index < len(lines):
        raw = lines[index]
        stripped = raw.strip()

        if stripped == "---":
            body = "\n".join(lines[index + 1 :]).strip()
            return frontmatter, body

        if not stripped:
            index += 1
            continue

        match = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", raw)
        if match:
            key, value = match.groups()
            base_indent = len(raw) - len(raw.lstrip())

            if value in {"|", ">"}:
                block: list[str] = []
                index += 1
                while index < len(lines):
                    nested = lines[index]
                    nested_stripped = nested.strip()
                    nested_indent = len(nested) - len(nested.lstrip())
                    if nested_stripped and nested_indent <= base_indent:
                        break
                    block.append(nested.lstrip() if nested_stripped else "")
                    index += 1
                frontmatter[key] = "\n".join(block).strip("\n")
                continue

            if value == "":
                items: list[str] = []
                probe = index + 1
                while probe < len(lines):
                    nested = lines[probe]
                    nested_stripped = nested.strip()
                    nested_indent = len(nested) - len(nested.lstrip())
                    if not nested_stripped:
                        probe += 1
                        continue
                    if nested_indent <= base_indent:
                        break
                    dash_match = re.match(r"^\s*-\s+(.*)$", nested)
                    if not dash_match:
                        break
                    items.append(strip_quotes(dash_match.group(1)))
                    probe += 1
                if items:
                    frontmatter[key] = items
                    index = probe
                    continue

            cleaned = strip_quotes(value)
            if cleaned.startswith("[") and cleaned.endswith("]"):
                content = cleaned[1:-1].strip()
                if content:
                    frontmatter[key] = [strip_quotes(part) for part in content.split(",")]
                else:
                    frontmatter[key] = []
            else:
                frontmatter[key] = cleaned

        index += 1

    return frontmatter, ""


def first_heading(body: str) -> str:
    for raw in body.splitlines():
        line = raw.strip()
        if line.startswith("#"):
            return line.lstrip("#").strip()
    return ""


def first_paragraph(body: str) -> str:
    paragraph: list[str] = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            if paragraph:
                break
            continue
        if line.startswith("#"):
            continue
        paragraph.append(line)
    return " ".join(paragraph)


def humanize_slug(slug: str) -> str:
    return slug.replace("-", " ")


def format_iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().isoformat(timespec="seconds")


def format_display(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")


def normalize_link(project_root: Path, raw_link: str) -> Path:
    target = strip_quotes(raw_link)
    if not target:
        return project_root
    if target.startswith("/"):
        return Path(target)
    if re.match(r"^(tk|pl|rs|rf)\d{4,5}\..*\.md$", target):
        return project_root / "issues" / target
    if re.match(r"^rp\d{4,5}\..*\.md$", target):
        return project_root / "docs" / "reviews" / target
    if re.match(r"^(tk|pl|rs|rf)\d{4,5}\.rv[0-9]{3}-r[0-9]+-[a-z0-9-]+\.md$", target):
        return project_root / "docs" / "reviews" / target
    if re.match(r"^tk\d{4,5}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd)\.md$", target):
        return project_root / "docs" / "progress" / target
    return project_root / target


def find_issue_anchor_matches(project_root: Path, issue_id: str) -> list[Path]:
    issue_root = project_root / "issues"
    if not issue_root.is_dir():
        return []
    matches = [
        path
        for path in issue_root.rglob(f"{issue_id}.*.md")
        if DOC_RE.match(path.name)
    ]
    return sorted(
        matches,
        key=lambda path: ("archive" in path.relative_to(issue_root).parts, str(path)),
    )


def find_review_anchor_matches(project_root: Path, review_id: str) -> list[Path]:
    review_root = project_root / "docs" / "reviews"
    if not review_root.is_dir():
        return []
    return sorted(review_root.glob(f"{review_id}.*.md"))


def resolve_link_entry(project_root: Path, raw_link: str) -> dict[str, Any]:
    target = strip_quotes(raw_link)

    if re.fullmatch(r"(tk|pl|rs|rf)\d{4,5}", target):
        matches = find_issue_anchor_matches(project_root, target)
        first = matches[0].resolve() if matches else (project_root / "issues" / target).resolve()
        return {
            "raw": raw_link,
            "path": str(first),
            "relative_path": str(first).replace(str(project_root.resolve()) + "/", ""),
            "label": target,
            "exists": bool(matches),
            "file_url": matches[0].resolve().as_uri() if matches else "",
        }

    if re.fullmatch(r"rp\d{4,5}", target):
        matches = find_review_anchor_matches(project_root, target)
        first = matches[0].resolve() if matches else (project_root / "docs" / "reviews" / target).resolve()
        return {
            "raw": raw_link,
            "path": str(first),
            "relative_path": str(first).replace(str(project_root.resolve()) + "/", ""),
            "label": target,
            "exists": bool(matches),
            "file_url": matches[0].resolve().as_uri() if matches else "",
        }

    if re.fullmatch(r"(tk|pl|rs|rf)\d{4,5}\.rv[0-9]{3}-r[0-9]+-[a-z0-9-]+", target):
        path = project_root / "docs" / "reviews" / f"{target}.md"
        exists = path.exists()
        resolved = path.resolve()
        return {
            "raw": raw_link,
            "path": str(resolved),
            "relative_path": str(resolved).replace(str(project_root.resolve()) + "/", ""),
            "label": target,
            "exists": exists,
            "file_url": resolved.as_uri() if exists else "",
        }

    if re.fullmatch(r"tk\d{4,5}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd)", target):
        path = project_root / "docs" / "progress" / f"{target}.md"
        exists = path.exists()
        resolved = path.resolve()
        return {
            "raw": raw_link,
            "path": str(resolved),
            "relative_path": str(resolved).replace(str(project_root.resolve()) + "/", ""),
            "label": target,
            "exists": exists,
            "file_url": resolved.as_uri() if exists else "",
        }

    if re.fullmatch(r"tk\d{4,5}\.s[0-9]{2}-[a-z0-9-]+", target):
        progress_root = project_root / "docs" / "progress"
        matches = sorted(progress_root.glob(f"{target}.*.md")) if progress_root.is_dir() else []
        first = matches[0].resolve() if matches else (progress_root / target).resolve()
        return {
            "raw": raw_link,
            "path": str(first),
            "relative_path": str(first).replace(str(project_root.resolve()) + "/", ""),
            "label": target,
            "exists": bool(matches),
            "file_url": matches[0].resolve().as_uri() if matches else "",
        }

    normalized = normalize_link(project_root, raw_link)
    exists = normalized.exists()
    return {
        "raw": raw_link,
        "path": str(normalized.resolve()),
        "relative_path": str(normalized.resolve()).replace(str(project_root.resolve()) + "/", ""),
        "label": normalized.name or raw_link,
        "exists": exists,
        "file_url": normalized.resolve().as_uri() if exists else "",
    }


def frontmatter_list(frontmatter: dict[str, Any], key: str) -> list[str]:
    value = frontmatter.get(key, [])
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def derive_relation_summary(doc: dict[str, Any], siblings: list[dict[str, Any]], linked_entries: list[dict[str, Any]]) -> dict[str, Any]:
    kind_counts = Counter(item["kind"] for item in siblings)
    derived_bits = [
        f"{kind}" if count == 1 else f"{kind}×{count}"
        for kind, count in ((kind, kind_counts.get(kind, 0)) for kind in ["pl", "rs", "rf", "rp", "rv", "pg", "tk"])
        if count
    ]
    linked_bits = [item["label"] for item in linked_entries[:4]]
    if len(linked_entries) > 4:
        linked_bits.append(f"+{len(linked_entries) - 4}")
    return {
        "count": len(siblings),
        "derived_bits": derived_bits,
        "linked_bits": linked_bits,
        "linked_count": len(linked_entries),
    }


def parse_doc_file(path: Path, project_root: Path) -> dict[str, Any] | None:
    match = DOC_RE.match(path.name)
    rv_match = RV_RE.match(path.name)
    progress_match = PROGRESS_RE.match(path.name)
    if not match and not rv_match and not progress_match:
        return None

    stat = path.stat()
    text = path.read_text(encoding="utf-8")
    frontmatter, body = parse_frontmatter(text)
    links = frontmatter_list(frontmatter, "links")
    depends_on = frontmatter_list(frontmatter, "depends_on")

    rel_path = path.resolve().relative_to(project_root.resolve())
    fallback_slug = match.group("slug") if match else path.stem
    title = first_heading(body) or humanize_slug(fallback_slug)
    summary = frontmatter.get("recap") or frontmatter.get("why") or first_paragraph(body) or frontmatter.get("scope") or title

    normalized_links = []
    for raw in links:
        normalized_links.append(resolve_link_entry(project_root, raw))

    if rv_match:
        issue_id = rv_match.group("issue_id")
        thread = rv_match.group("thread")
        round_id = rv_match.group("round")
        author = rv_match.group("author")
        return {
            "doc_id": f"{issue_id}.{thread}-{round_id}",
            "anchor_id": rv_match.group("digits"),
            "kind": "rv",
            "kind_label": KIND_LABEL["rv"],
            "state": "dne",
            "state_label": STATE_LABEL["dne"],
            "tone": STATE_TONE["dne"],
            "board": author,
            "slug": f"{thread}-{round_id}-{author}",
            "title": title,
            "summary": summary,
            "priority": "",
            "priority_rank": PRIORITY_RANK[""],
            "path": str(rel_path),
            "file_url": path.resolve().as_uri(),
            "modified_at": format_iso(stat.st_mtime),
            "modified_display": format_display(stat.st_mtime),
            "modified_epoch": stat.st_mtime,
            "archived": "docs/reviews/archive/" in str(rel_path).replace("\\", "/"),
            "owner": frontmatter.get("owner", ""),
            "assignee": frontmatter.get("assignee", ""),
            "recap": frontmatter.get("recap", ""),
            "risk": frontmatter.get("risk", ""),
            "accept": frontmatter.get("accept", ""),
            "verify": frontmatter.get("verify", ""),
            "code_version": frontmatter.get("code_version", ""),
            "result": frontmatter.get("result", ""),
            "memory": frontmatter.get("memory", ""),
            "links": normalized_links,
            "depends_on": [],
            "dependencies": [],
            "ready_status": "",
            "dag_blocked": False,
            "progress_steps": [],
            "progress_open_count": 0,
            "active_progress": None,
        }

    if progress_match:
        task_id = progress_match.group("task_id")
        step = progress_match.group("step")
        state = progress_match.group("state")
        return {
            "doc_id": f"{task_id}.{step}",
            "anchor_id": progress_match.group("digits"),
            "parent_id": task_id,
            "kind": "pg",
            "kind_label": KIND_LABEL["pg"],
            "state": state,
            "state_label": STATE_LABEL[state],
            "tone": STATE_TONE[state],
            "board": "progress",
            "slug": step,
            "title": title,
            "summary": summary,
            "priority": "",
            "priority_rank": PRIORITY_RANK[""],
            "path": str(rel_path),
            "file_url": path.resolve().as_uri(),
            "modified_at": format_iso(stat.st_mtime),
            "modified_display": format_display(stat.st_mtime),
            "modified_epoch": stat.st_mtime,
            "archived": "docs/progress/archive/" in str(rel_path).replace("\\", "/"),
            "owner": frontmatter.get("owner", ""),
            "assignee": frontmatter.get("assignee", ""),
            "recap": frontmatter.get("recap", ""),
            "risk": frontmatter.get("risk", ""),
            "accept": frontmatter.get("accept", ""),
            "verify": frontmatter.get("verify", ""),
            "code_version": frontmatter.get("code_version", ""),
            "result": frontmatter.get("result", ""),
            "memory": frontmatter.get("memory", ""),
            "why": frontmatter.get("why", ""),
            "scope": frontmatter.get("scope", ""),
            "links": normalized_links,
            "depends_on": [],
            "dependencies": [],
            "ready_status": "",
            "dag_blocked": False,
            "progress_steps": [],
            "progress_open_count": 0,
            "active_progress": None,
        }

    record = {
        "doc_id": f"{match.group('kind')}{match.group('digits')}",
        "anchor_id": match.group("digits"),
        "kind": match.group("kind"),
        "kind_label": KIND_LABEL[match.group("kind")],
        "state": match.group("state"),
        "state_label": STATE_LABEL[match.group("state")],
        "tone": STATE_TONE[match.group("state")],
        "board": match.group("board"),
        "slug": match.group("slug"),
        "title": title,
        "summary": summary,
        "priority": match.group("priority") or "",
        "priority_rank": PRIORITY_RANK.get(match.group("priority") or "", 9),
        "path": str(rel_path),
        "file_url": path.resolve().as_uri(),
        "modified_at": format_iso(stat.st_mtime),
        "modified_display": format_display(stat.st_mtime),
        "modified_epoch": stat.st_mtime,
        "archived": "issues/archive/" in str(rel_path).replace("\\", "/"),
        "owner": frontmatter.get("owner", ""),
        "assignee": frontmatter.get("assignee", ""),
        "recap": frontmatter.get("recap", ""),
        "risk": frontmatter.get("risk", ""),
        "accept": frontmatter.get("accept", ""),
        "verify": frontmatter.get("verify", ""),
        "code_version": frontmatter.get("code_version", ""),
        "result": frontmatter.get("result", ""),
        "memory": frontmatter.get("memory", "none"),
        "why": frontmatter.get("why", ""),
        "scope": frontmatter.get("scope", ""),
        "links": normalized_links,
        "depends_on": depends_on,
        "dependencies": [],
        "ready_status": "",
        "dag_blocked": False,
        "progress_steps": [],
        "progress_open_count": 0,
        "active_progress": None,
    }

    return record


def resolve_dependency_id(raw: str) -> str:
    value = strip_quotes(raw).strip()
    if re.fullmatch(r"(tk|pl|rs|rf)\d{4,5}", value):
        return value
    return value


def attach_dependency_status(docs: list[dict[str, Any]]) -> None:
    issue_docs = {
        doc["doc_id"]: doc
        for doc in docs
        if doc["kind"] in {"tk", "pl", "rs", "rf"}
    }

    for doc in docs:
        dependencies: list[dict[str, Any]] = []
        for raw_dep in doc.get("depends_on", []):
            dep_id = resolve_dependency_id(raw_dep)
            dep = issue_docs.get(dep_id)
            satisfied = bool(dep and dep["state"] in {"dne", "arvd"})
            dependencies.append(
                {
                    "id": dep_id,
                    "exists": dep is not None,
                    "state": dep["state"] if dep else "",
                    "state_label": dep["state_label"] if dep else "",
                    "path": dep["path"] if dep else "",
                    "file_url": dep["file_url"] if dep else "",
                    "satisfied": satisfied,
                }
            )

        doc["dependencies"] = dependencies
        if doc["kind"] in {"tk", "pl", "rs", "rf"} and doc["state"] == "tdo":
            doc["dag_blocked"] = any(not item["satisfied"] for item in dependencies)
            doc["ready_status"] = "dag-blocked" if doc["dag_blocked"] else "ready"
        else:
            doc["dag_blocked"] = False
            doc["ready_status"] = ""


def parse_memory_anchors(memory_file: Path) -> list[str]:
    if not memory_file.is_file():
        return []

    anchors: list[str] = []
    for raw in memory_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        match = re.match(r"^锚[:：]\s*(.*)$", line)
        if match:
            value = match.group(1).strip()
            for item in re.split(r"[|,\s]+", value):
                if item:
                    anchors.append(item)
    return anchors


######## data model shaping


def collect_docs(project_root: Path) -> list[dict[str, Any]]:
    docs: list[dict[str, Any]] = []
    for base in [project_root / "issues", project_root / "docs" / "reviews", project_root / "docs" / "progress"]:
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.md")):
            parsed = parse_doc_file(path, project_root)
            if parsed:
                docs.append(parsed)
    return docs


def sort_docs(docs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        docs,
        key=lambda item: (
            STATE_ORDER.index(item["state"]) if item["state"] in STATE_ORDER else len(STATE_ORDER),
            item["priority_rank"],
            item["doc_id"],
        ),
    )


def build_dashboard(project_root: Path) -> dict[str, Any]:
    docs = collect_docs(project_root)
    attach_dependency_status(docs)
    anchors = defaultdict(list)
    for doc in docs:
        anchors[doc["anchor_id"]].append(doc)

    progress_by_task = defaultdict(list)
    for doc in docs:
        if doc["kind"] == "pg":
            progress_by_task[doc["parent_id"]].append(doc)

    memory_file = project_root / "refs" / "project-memory-aaak.md"
    memory_anchors = set(parse_memory_anchors(memory_file))

    for doc in docs:
        linked_docs = [item for item in doc["links"] if item["exists"]]
        siblings = [
            sibling
            for sibling in anchors[doc["anchor_id"]]
            if sibling["path"] != doc["path"]
        ]
        doc["relation"] = derive_relation_summary(doc, siblings, linked_docs)
        doc["siblings"] = [
            {
                "doc_id": sibling["doc_id"],
                "kind": sibling["kind"],
                "state": sibling["state"],
                "path": sibling["path"],
                "file_url": sibling["file_url"],
            }
            for sibling in sort_docs(siblings)
        ]
        doc["has_memory_anchor"] = doc["doc_id"] in memory_anchors
        steps = sort_docs(progress_by_task.get(doc["doc_id"], [])) if doc["kind"] == "tk" else []
        doc["progress_steps"] = [
            {
                "doc_id": step["doc_id"],
                "state": step["state"],
                "state_label": step["state_label"],
                "title": step["title"],
                "path": step["path"],
                "file_url": step["file_url"],
            }
            for step in steps
        ]
        doc["progress_open_count"] = sum(1 for step in steps if step["state"] in {"tdo", "doi", "bkd"})
        active_steps = [step for step in steps if step["state"] == "doi"] or [step for step in steps if step["state"] == "bkd"]
        doc["active_progress"] = (
            {
                "doc_id": active_steps[0]["doc_id"],
                "state": active_steps[0]["state"],
                "state_label": active_steps[0]["state_label"],
                "title": active_steps[0]["title"],
                "path": active_steps[0]["path"],
                "file_url": active_steps[0]["file_url"],
            }
            if active_steps
            else None
        )

    current_docs = [doc for doc in docs if not doc["archived"]]
    current_tasks = sort_docs([doc for doc in current_docs if doc["kind"] == "tk"])
    current_non_tasks = sort_docs([doc for doc in current_docs if doc["kind"] in {"pl", "rs", "rf"}])
    review_docs = sort_docs([doc for doc in docs if doc["kind"] in {"rp", "rv"}])
    progress_docs = sort_docs([doc for doc in docs if doc["kind"] == "pg"])
    history_tasks = sorted(
        [doc for doc in docs if doc["kind"] == "tk" and (doc["archived"] or doc["state"] in HISTORY_STATES)],
        key=lambda item: (-item["modified_epoch"], item["doc_id"]),
    )

    current_counts = Counter(doc["state"] for doc in current_tasks)
    active_total = sum(current_counts[state] for state in ACTIVE_STATES)
    done_total = sum(current_counts[state] for state in DONE_STATES)
    cancelled_total = current_counts.get("cand", 0)
    ready_tdo_total = sum(1 for doc in current_tasks if doc["state"] == "tdo" and not doc["dag_blocked"])
    dag_blocked_total = sum(1 for doc in current_tasks if doc["state"] == "tdo" and doc["dag_blocked"])
    progress_open_total = sum(1 for doc in progress_docs if doc["state"] in {"tdo", "doi", "bkd"})
    track_total = max(len(current_tasks) - cancelled_total, 1)
    completion_ratio = round(done_total / track_total, 3)

    board_counts = Counter(doc["board"] for doc in current_tasks)
    archive_counts = Counter()
    for doc in docs:
        if doc["archived"]:
            parts = Path(doc["path"]).parts
            if "archive" in parts:
                idx = parts.index("archive")
                if idx + 1 < len(parts):
                    archive_counts[parts[idx + 1]] += 1

    recent_events = sorted(
        [
            {
                "doc_id": doc["doc_id"],
                "kind": doc["kind"],
                "kind_label": doc["kind_label"],
                "state": doc["state"],
                "state_label": doc["state_label"],
                "title": doc["title"],
                "summary": doc["summary"],
                "result": doc.get("result", ""),
                "path": doc["path"],
                "file_url": doc["file_url"],
                "modified_display": doc["modified_display"],
                "modified_epoch": doc["modified_epoch"],
            }
            for doc in docs
        ],
        key=lambda item: (-item["modified_epoch"], item["doc_id"]),
    )
    if memory_file.exists():
        stat = memory_file.stat()
        recent_events.append(
            {
                "doc_id": "mem",
                "kind": "mem",
                "kind_label": "记忆",
                "state": "dne",
                "state_label": "历史记忆",
                "title": "project-memory-aaak",
                "summary": f"{len(memory_anchors)} anchors",
                "path": str(memory_file.relative_to(project_root)),
                "file_url": memory_file.resolve().as_uri(),
                "modified_display": format_display(stat.st_mtime),
                "modified_epoch": stat.st_mtime,
            }
        )
    recent_events = sorted(recent_events, key=lambda item: (-item["modified_epoch"], item["doc_id"]))[:60]

    memory_watch = [
        doc
        for doc in current_tasks
        if doc["memory"] in {"required", "done"}
    ]

    return {
        "project": {
            "name": project_root.name,
            "root": str(project_root.resolve()),
            "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "generated_display": datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S"),
            "template_version": "2026.04.11",
        },
        "current": {
            "metrics": {
                "task_total": len(current_tasks),
                "active_total": active_total,
                "review_total": len(review_docs),
                "blocked_total": current_counts.get("bkd", 0),
                "ready_tdo_total": ready_tdo_total,
                "dag_blocked_total": dag_blocked_total,
                "progress_doc_total": len(progress_docs),
                "progress_open_total": progress_open_total,
                "done_total": done_total,
                "cancelled_total": cancelled_total,
                "completion_ratio": completion_ratio,
                "review_doc_total": len(review_docs),
                "non_task_total": len(current_non_tasks),
            },
            "state_counts": [
                {
                    "state": state,
                    "label": STATE_LABEL[state],
                    "count": current_counts.get(state, 0),
                    "tone": STATE_TONE[state],
                }
                for state in STATE_ORDER
            ],
            "board_counts": [
                {"board": board, "count": count}
                for board, count in sorted(board_counts.items(), key=lambda item: (-item[1], item[0]))
            ],
            "tasks": current_tasks,
            "non_tasks": current_non_tasks,
            "progress_docs": progress_docs,
            "memory_watch": memory_watch,
        },
        "history": {
            "closed_tasks": history_tasks,
            "archive_years": [
                {"year": year, "count": count}
                for year, count in sorted(archive_counts.items(), key=lambda item: item[0], reverse=True)
            ],
            "recent_events": recent_events,
            "memory_file": {
                "path": str(memory_file.relative_to(project_root)) if memory_file.exists() else "refs/project-memory-aaak.md",
                "file_url": memory_file.resolve().as_uri() if memory_file.exists() else "",
                "exists": memory_file.exists(),
                "anchors": sorted(memory_anchors),
            },
        },
    }


######## rendering


def preview_file_name(relative_path: str) -> str:
    digest = hashlib.sha1(relative_path.encode("utf-8")).hexdigest()[:10]
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", relative_path).strip("-") or "doc"
    return f"{stem[:90]}-{digest}.html"


def split_raw_frontmatter(text: str) -> tuple[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return "", text

    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "\n".join(lines[1:index]).strip(), "\n".join(lines[index + 1 :]).strip()
    return "", text


def render_inline_plain(text: str) -> str:
    chunks: list[str] = []
    cursor = 0
    for match in re.finditer(r"\*\*([^\n]+?)\*\*", text):
        chunks.append(html.escape(text[cursor:match.start()]))
        chunks.append(f"<strong>{html.escape(match.group(1))}</strong>")
        cursor = match.end()
    chunks.append(html.escape(text[cursor:]))
    return "".join(chunks)


def render_inline_markdown(text: str) -> str:
    chunks: list[str] = []
    cursor = 0
    for match in re.finditer(r"`([^`]+)`", text):
        chunks.append(render_inline_plain(text[cursor:match.start()]))
        chunks.append(f"<code>{html.escape(match.group(1))}</code>")
        cursor = match.end()
    chunks.append(render_inline_plain(text[cursor:]))
    return "".join(chunks)


def render_markdown_blocks(text: str) -> str:
    blocks: list[str] = []
    paragraph: list[str] = []
    list_items: list[str] = []
    list_tag = "ul"
    code_lines: list[str] = []
    code_lang = ""
    in_code = False

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            blocks.append(f"<p>{render_inline_markdown(' '.join(paragraph))}</p>")
            paragraph = []

    def flush_list() -> None:
        nonlocal list_items, list_tag
        if list_items:
            items = "".join(f"<li>{render_inline_markdown(item)}</li>" for item in list_items)
            blocks.append(f"<{list_tag}>{items}</{list_tag}>")
            list_items = []
            list_tag = "ul"

    for raw_line in text.splitlines():
        stripped = raw_line.strip()

        if in_code:
            if stripped.startswith("```"):
                lang_class = f" class=\"language-{html.escape(code_lang)}\"" if code_lang else ""
                code_text = "\n".join(code_lines)
                blocks.append(f"<pre><code{lang_class}>{html.escape(code_text)}</code></pre>")
                code_lines = []
                code_lang = ""
                in_code = False
            else:
                code_lines.append(raw_line)
            continue

        if stripped.startswith("```"):
            flush_paragraph()
            flush_list()
            in_code = True
            code_lang = stripped[3:].strip().split(" ", 1)[0]
            continue

        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        heading = re.match(r"^(#{1,4})\s+(.+)$", stripped)
        if heading:
            flush_paragraph()
            flush_list()
            level = len(heading.group(1))
            blocks.append(f"<h{level}>{render_inline_markdown(heading.group(2))}</h{level}>")
            continue

        unordered = re.match(r"^[-*]\s+(.+)$", stripped)
        ordered = re.match(r"^\d+\.\s+(.+)$", stripped)
        if unordered or ordered:
            flush_paragraph()
            next_tag = "ol" if ordered else "ul"
            if list_items and list_tag != next_tag:
                flush_list()
            list_tag = next_tag
            list_items.append((ordered or unordered).group(1))
            continue

        flush_list()
        paragraph.append(stripped)

    if in_code:
        lang_class = f" class=\"language-{html.escape(code_lang)}\"" if code_lang else ""
        code_text = "\n".join(code_lines)
        blocks.append(f"<pre><code{lang_class}>{html.escape(code_text)}</code></pre>")

    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def render_markdown_preview(source_path: Path, project_root: Path) -> str:
    text = source_path.read_text(encoding="utf-8")
    raw_frontmatter, body = split_raw_frontmatter(text)
    title = first_heading(body) or source_path.stem
    relative_path = source_path.resolve().relative_to(project_root.resolve())
    frontmatter_html = ""
    if raw_frontmatter:
        frontmatter_html = (
            "<details class=\"frontmatter\" open>"
            "<summary>Frontmatter</summary>"
            f"<pre><code>{html.escape(raw_frontmatter)}</code></pre>"
            "</details>"
        )

    return f"""<!doctype html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      color-scheme: light;
      --paper: #fffdf8;
      --ink: #25211b;
      --muted: #8a8174;
      --line: #e8dfd2;
      --code: #f6f1e9;
      --accent: #8b5e34;
    }}
    body {{
      margin: 0;
      background: #f3efe7;
      color: var(--ink);
      font: 15px/1.58 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    }}
    .markdown-doc {{
      max-width: 1040px;
      margin: 28px auto;
      padding: 32px 40px;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: 0 12px 34px rgba(62, 45, 24, 0.10);
    }}
    .path {{
      margin-bottom: 18px;
      color: var(--muted);
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
    }}
    h1, h2, h3, h4 {{
      line-height: 1.25;
      margin: 1.35em 0 0.5em;
      font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      letter-spacing: -0.02em;
    }}
    h1 {{ margin-top: 0; font-size: 24px; }}
    h2 {{ font-size: 19px; border-top: 1px solid var(--line); padding-top: 16px; }}
    h3 {{ font-size: 16px; }}
    h4 {{ font-size: 15px; }}
    p {{ margin: 0 0 0.72em; }}
    ul, ol {{ padding-left: 1.25em; margin: 0 0 0.82em; }}
    li {{ margin: 0.12em 0; }}
    code {{
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.92em;
      background: var(--code);
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 0.08em 0.32em;
    }}
    pre {{
      overflow: auto;
      padding: 12px 14px;
      background: var(--code);
      border: 1px solid var(--line);
      border-radius: 10px;
      line-height: 1.48;
    }}
    pre code {{
      padding: 0;
      border: 0;
      background: transparent;
      font-size: 13px;
    }}
    .frontmatter {{
      margin: 0 0 22px;
      color: var(--muted);
    }}
    .frontmatter summary {{
      cursor: pointer;
      color: var(--accent);
      font: 700 12px/1.45 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }}
    @media (max-width: 760px) {{
      .markdown-doc {{
        margin: 0;
        padding: 22px 18px;
        border: 0;
        border-radius: 0;
      }}
    }}
  </style>
</head>
<body>
  <main class="markdown-doc">
    <div class="path">{html.escape(str(relative_path))}</div>
    {frontmatter_html}
    {render_markdown_blocks(body)}
  </main>
</body>
</html>
"""


def attach_preview_urls(payload: dict[str, Any], out_dir: Path, project_root: Path) -> None:
    preview_dir = out_dir / "md"
    if preview_dir.exists():
        shutil.rmtree(preview_dir)
    rendered: dict[str, str] = {}
    project_root_resolved = project_root.resolve()

    def source_for(record: dict[str, Any]) -> Path | None:
        raw_path = record.get("path") or record.get("relative_path")
        if not isinstance(raw_path, str) or not raw_path.endswith(".md"):
            return None
        source_path = Path(raw_path)
        if not source_path.is_absolute():
            source_path = project_root_resolved / raw_path
        try:
            source_path.resolve().relative_to(project_root_resolved)
        except ValueError:
            return None
        return source_path if source_path.is_file() else None

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            source_path = source_for(value)
            if source_path:
                relative_path = str(source_path.resolve().relative_to(project_root_resolved))
                if relative_path not in rendered:
                    preview_dir.mkdir(parents=True, exist_ok=True)
                    preview_path = preview_dir / preview_file_name(relative_path)
                    preview_path.write_text(render_markdown_preview(source_path, project_root_resolved), encoding="utf-8")
                    rendered[relative_path] = preview_path.resolve().as_uri()
                value["preview_url"] = rendered[relative_path]
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(payload)


def inject_template(template: str, payload: dict[str, Any]) -> str:
    data_text = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    return (
        template
        .replace("__AGATA_PROGRESS_DATA__", data_text)
        .replace("__AGATA_PROJECT_NAME__", payload["project"]["name"])
        .replace("__AGATA_GENERATED_AT__", payload["project"]["generated_display"])
    )


def write_outputs(out_dir: Path, project_root: Path, payload: dict[str, Any], template: str) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    attach_preview_urls(payload, out_dir, project_root)
    data_path = out_dir / "progress-data.json"
    html_path = out_dir / "progress-view.html"

    data_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    html_path.write_text(inject_template(template, payload), encoding="utf-8")
    return data_path, html_path


def maybe_open(html_path: Path, should_open: bool) -> bool:
    if not should_open:
        return False

    if shutil.which("open"):
        subprocess.run(["open", str(html_path)], check=False)
        return True

    return webbrowser.open(html_path.resolve().as_uri())


######## cli


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate a dense static HTML snapshot for an Agata workflow project."
    )
    parser.add_argument("--project-root", help="Project root that contains issues/")
    parser.add_argument(
        "--out-dir",
        help="Output directory. Defaults to <project>/aidocs/agata-workflow-status",
    )
    parser.add_argument("--template", help="Override the bundled HTML template")
    parser.add_argument("--no-open", action="store_true", help="Generate files without opening the browser")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    script_path = Path(__file__)
    project_root = find_project_root(Path(args.project_root) if args.project_root else Path.cwd())
    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else project_root / "aidocs" / "agata-workflow-status"

    payload = build_dashboard(project_root)
    template = load_template(script_path, args.template)
    data_path, html_path = write_outputs(out_dir, project_root, payload, template)
    opened = maybe_open(html_path, not args.no_open)

    print(f"data: {data_path}")
    print(f"html: {html_path}")
    print(f"opened: {'yes' if opened else 'no'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
