#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
progress_view="$repo_root/agata-code-workflow/scripts/progress_view.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing file: $path"
}

assert_contains() {
  local path="$1"
  local needle="$2"
  grep -q "$needle" "$path" || fail "missing [$needle] in $path"
}

write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

######## doc-sample should generate dense static viewer

out_dir="$(mktemp -d)"
log_file="$(mktemp)"
out_dir_real="$(cd "$out_dir" && pwd -P)"

"$progress_view" --project-root "$repo_root/doc-sample" --out-dir "$out_dir" --no-open >"$log_file"

data_file="$out_dir_real/progress-data.json"
html_file="$out_dir_real/progress-view.html"

assert_file "$data_file"
assert_file "$html_file"
assert_contains "$log_file" "^data: $data_file$"
assert_contains "$log_file" "^html: $html_file$"
assert_contains "$log_file" "^opened: no$"
assert_contains "$data_file" '"name": "doc-sample"'
assert_contains "$data_file" '"doc_id": "tk0001"'
assert_contains "$data_file" '"doc_id": "tk0001.s01-sample"'
assert_contains "$data_file" '"preview_url"'
assert_contains "$html_file" 'Workflow Progress'
assert_contains "$html_file" '现状 Current'
assert_contains "$html_file" '历史 History'
assert_contains "$html_file" 'Search issues...'
assert_contains "$html_file" 'Recent Activity'
assert_contains "$html_file" 'Project Memory'
assert_contains "$html_file" 'Archive Years'
assert_contains "$html_file" 'workflow-progress-data'
assert_contains "$html_file" 'doc-sample'
preview_file="$(find "$out_dir_real/md" -type f -name '*.html' | head -n 1)"
assert_file "$preview_file"
assert_contains "$preview_file" 'class="markdown-doc"'
frontmatter_preview="$(grep -rl 'Frontmatter' "$out_dir_real/md" | head -n 1)"
assert_file "$frontmatter_preview"

rm -rf "$out_dir" "$log_file"

######## five-digit projects should also render correctly

project_root="$(mktemp -d)"
mkdir -p "$project_root/issues" "$project_root/docs/reviews" "$project_root/refs"

write_file "$project_root/issues/tk10001.doi.runtime.viewer-test.p1.md" <<'EOF'
---
owner: user
assignee: agent
why: validate the progress viewer
scope: render one active task
risk: low
accept: html and json carry 5-digit ids
memory: required
links:
    - docs/reviews/tk10001.rv001-r1-reviewer.md
    - tk10003
---

# Viewer Test

Render **bold-sample** text.

- [x] checked item
- [ ] unchecked item

> quoted **text**

| Column | Value |
|---|---|
| alpha | **beta** |

[example](https://example.com)
EOF

write_file "$project_root/issues/pl10001.tdo.runtime.viewer-plan.md" <<'EOF'
---
owner: user
assignee: agent
why: same anchor should show derived relations
scope: one plan doc
risk: low
accept: same anchor visible
links:
  - docs/reviews/pl10001.rv001-r1-author.md
---
EOF

write_file "$project_root/issues/tk10003.tdo.runtime.viewer-dag-node.p1.md" <<'EOF'
---
owner: user
assignee: agent
why: tdo can be DAG-blocked without becoming cand
scope: render dependency readiness
risk: low
accept: progress data exposes dag blocked count
memory: none
depends_on:
  - tk10001
links: []
---
EOF

write_file "$project_root/docs/reviews/tk10001.rv001-r1-reviewer.md" <<'EOF'
---
result: pass
---

# tk10001 rv001 r1
EOF

write_file "$project_root/docs/reviews/pl10001.rv001-r1-author.md" <<'EOF'
# pl10001 rv001 r1
EOF

mkdir -p "$project_root/docs/progress"
write_file "$project_root/docs/progress/tk10001.s01-repro.dne.md" <<'EOF'
# tk10001.s01-repro

env: viewer-host:/repo@abc123

## Goal
render progress steps
EOF

write_file "$project_root/docs/progress/tk10001.s02-fix.doi.md" <<'EOF'
# tk10001.s02-fix

env: viewer-host:/repo@abc123

## Goal
show active progress
EOF

write_file "$project_root/refs/project-memory-aaak.md" <<'EOF'
# 项目历史记忆

题: viewer-memory
时: 2026-04-11
锚：tk10001
决: keep one anchor for history panel
源: tk10001
EOF

write_file "$project_root/issues/archive/2026/tk10002.arvd.runtime.viewer-archive.p1.md" <<'EOF'
---
owner: user
assignee: agent
why: validate archive grouping
scope: one archived task
risk: low
accept: archive year visible
links: []
---
EOF

out_dir="$(mktemp -d)"
out_dir_real="$(cd "$out_dir" && pwd -P)"
"$progress_view" --project-root "$project_root" --out-dir "$out_dir" --no-open >/dev/null

data_file="$out_dir_real/progress-data.json"
html_file="$out_dir_real/progress-view.html"

assert_contains "$data_file" '"doc_id": "tk10001"'
assert_contains "$data_file" '"preview_url"'
assert_contains "$data_file" '"doc_id": "tk10003"'
assert_contains "$data_file" '"doc_id": "tk10001.rv001-r1"'
assert_contains "$data_file" '"result": "pass"'
assert_contains "$data_file" '"doc_id": "pl10001.rv001-r1"'
assert_contains "$data_file" '"doc_id": "tk10001.s01-repro"'
assert_contains "$data_file" '"doc_id": "tk10001.s02-fix"'
assert_contains "$data_file" '"anchor_id": "10001"'
assert_contains "$data_file" '"dag_blocked_total": 1'
assert_contains "$data_file" '"progress_doc_total": 2'
assert_contains "$data_file" '"progress_open_total": 1'
assert_contains "$data_file" '"progress_open_count": 1'
assert_contains "$data_file" '"active_progress"'
assert_contains "$data_file" '"ready_status": "dag-blocked"'
assert_contains "$data_file" '"year": "2026"'
bold_preview="$(grep -rl '<strong>bold-sample</strong>' "$out_dir_real/md" | head -n 1)"
assert_file "$bold_preview"
table_preview="$(grep -rl '<table>' "$out_dir_real/md" | head -n 1)"
assert_file "$table_preview"
checked_preview="$(grep -rl '<input type="checkbox" disabled checked>' "$out_dir_real/md" | head -n 1)"
assert_file "$checked_preview"
quote_preview="$(grep -rl '<blockquote>quoted <strong>text</strong></blockquote>' "$out_dir_real/md" | head -n 1)"
assert_file "$quote_preview"
link_preview="$(grep -rl '<a href="https://example.com">example</a>' "$out_dir_real/md" | head -n 1)"
assert_file "$link_preview"
python3 - "$data_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

task = next(item for item in data["current"]["tasks"] if item["doc_id"] == "tk10001")
assert any(
    link["raw"] == "tk10003" and link["exists"] and link.get("preview_url")
    for link in task["links"]
)
PY
assert_contains "$html_file" 'tk10001'
assert_contains "$html_file" 'tk10001.s02-fix'
assert_contains "$html_file" 'tk10001.rv001-r1'
assert_contains "$html_file" 'pl10001.rv001-r1'
assert_contains "$html_file" 'project-memory-aaak'

rm -rf "$project_root" "$out_dir"

echo "ok"
