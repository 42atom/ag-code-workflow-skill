#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_sh="$repo_root/agata-code-workflow/scripts/task.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1"
  local want="$2"
  local message="$3"

  [[ "$got" == "$want" ]] || fail "${message}: expected [${want}] got [${got}]"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "${message}: missing [${needle}] in [${haystack}]"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "${message}: unexpected [${needle}] in [${haystack}]"
}

run_task() {
  local project_root="$1"
  shift

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  (
    cd "$project_root"
    "$task_sh" "$@"
  ) >"$stdout_file" 2>"$stderr_file"
  task_status=$?
  set -e

  task_stdout="$(cat "$stdout_file")"
  task_stderr="$(cat "$stderr_file")"

  rm -f "$stdout_file" "$stderr_file"
}

make_project() {
  local project_root
  project_root="$(mktemp -d)"
  mkdir -p "$project_root/issues" "$project_root/docs/reviews" "$project_root/refs"
  project_root="$(cd "$project_root" && pwd -P)"
  printf '%s\n' "$project_root"
}

make_git_project() {
  local project_root
  project_root="$(make_project)"
  write_file "$project_root/README.md" <<'EOF'
# test repo
EOF
  write_file "$project_root/issues/.gitkeep" <<'EOF'
EOF
  write_file "$project_root/docs/reviews/.gitkeep" <<'EOF'
EOF
  write_file "$project_root/refs/.gitkeep" <<'EOF'
EOF
  (
    cd "$project_root"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Task Helper Test"
    git add README.md issues/.gitkeep docs/reviews/.gitkeep refs/.gitkeep
    git commit -qm "chore: init"
  )
  printf '%s\n' "$project_root"
}

make_linked_worktree() {
  local project_root="$1"
  local branch_name="$2"
  local holder worktree_root

  holder="$(mktemp -d)"
  worktree_root="$holder/linked"
  (
    cd "$project_root"
    git worktree add -q -b "$branch_name" "$worktree_root"
  )
  worktree_root="$(cd "$worktree_root" && pwd -P)"
  printf '%s\n' "$worktree_root"
}

remove_linked_worktree() {
  local project_root="$1"
  local worktree_root="$2"

  (
    cd "$project_root"
    git worktree remove --force "$worktree_root"
  ) >/dev/null 2>&1 || true
  rm -rf "$(dirname "$worktree_root")"
}

write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

task_status=0
task_stdout=""
task_stderr=""

######## archive find should resolve archived tk ids

project_root="$(make_project)"
write_file "$project_root/issues/tk10001.dne.runtime.archive-me.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: archive lookup should keep history reachable
scope: archive one task
risk: low
accept: archived task remains discoverable
memory: none
links: []
---
EOF

run_task "$project_root" archive 10001
assert_eq "$task_status" "0" "archive command should succeed"
archive_year="$(date +%Y)"
archived_path="$project_root/issues/archive/${archive_year}/tk10001.arvd.runtime.archive-me.p1.md"
assert_eq "$task_stdout" "$archived_path" "archive command should move into yearly archive"

run_task "$project_root" find tk10001
assert_eq "$task_status" "0" "find should locate archived task id"
assert_eq "$task_stdout" "$archived_path" "find should resolve archived task path"

rm -rf "$project_root"

######## archive-done should keep only the warm done buffer in issues root

project_root="$(make_project)"
for digits in 10001 10002 10003 10004 10005; do
  write_file "$project_root/issues/tk${digits}.dne.runtime.done-${digits}.p1.md" <<EOF
---
owner: user
assignee: codex
why: done buffer fixture ${digits}
scope: prove archive-done keeps only recent done docs
risk: low
accept: older dne docs move to archive without changing state
memory: none
links: []
---
EOF
done
write_file "$project_root/issues/pl10006.dne.product.done-plan.md" <<'EOF'
---
owner: user
assignee: codex
why: done plan also belongs to the done buffer
scope: prove archive-done applies to issue docs, not only tk
risk: low
accept: older done issue docs move physically
links: []
---
EOF
write_file "$project_root/issues/tk10007.tdo.runtime.live-task.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: live tasks must stay in root
scope: prove archive-done ignores active states
risk: low
accept: tdo remains in issues root
memory: none
links: []
---
EOF

run_task "$project_root" archive-done --keep 3
assert_eq "$task_status" "0" "archive-done should succeed"
archive_year="$(date +%Y)"
assert_contains "$task_stdout" "$project_root/issues/archive/${archive_year}/tk10001.dne.runtime.done-10001.p1.md" "archive-done should move oldest done task"
assert_contains "$task_stdout" "$project_root/issues/archive/${archive_year}/tk10003.dne.runtime.done-10003.p1.md" "archive-done should move done docs beyond keep count"
[[ -f "$project_root/issues/pl10006.dne.product.done-plan.md" ]] || fail "archive-done should keep highest-id done issue in root"
[[ -f "$project_root/issues/tk10005.dne.runtime.done-10005.p1.md" ]] || fail "archive-done should keep recent done task in root"
[[ -f "$project_root/issues/tk10004.dne.runtime.done-10004.p1.md" ]] || fail "archive-done should keep recent done task in root"
[[ -f "$project_root/issues/tk10007.tdo.runtime.live-task.p1.md" ]] || fail "archive-done should ignore live task states"
[[ -f "$project_root/issues/archive/${archive_year}/tk10001.dne.runtime.done-10001.p1.md" ]] || fail "archive-done should preserve dne state in archive"

run_task "$project_root" archive-done --keep nope
assert_eq "$task_status" "1" "archive-done should reject invalid keep values"
assert_contains "$task_stderr" "keep must be a non-negative integer" "archive-done should explain invalid keep"

rm -rf "$project_root"

######## archive-done default should keep thirty-two done docs

project_root="$(make_project)"
for number in $(seq 1 33); do
  digits="$(printf '%05d' "$((10000 + number))")"
  write_file "$project_root/issues/tk${digits}.dne.runtime.default-buffer-${digits}.p1.md" <<EOF
---
owner: user
assignee: codex
why: default done buffer fixture ${digits}
scope: prove archive-done default keeps thirty-two docs
risk: low
accept: only the oldest done doc moves with default keep
memory: none
links: []
---
EOF
done

run_task "$project_root" archive-done
assert_eq "$task_status" "0" "archive-done default should succeed"
archive_year="$(date +%Y)"
assert_eq "$task_stdout" "$project_root/issues/archive/${archive_year}/tk10001.dne.runtime.default-buffer-10001.p1.md" "archive-done default should move only the oldest thirty-third done doc"
[[ -f "$project_root/issues/tk10002.dne.runtime.default-buffer-10002.p1.md" ]] || fail "archive-done default should keep thirty-two done docs in root"
[[ -f "$project_root/issues/tk10033.dne.runtime.default-buffer-10033.p1.md" ]] || fail "archive-done default should keep newest done doc in root"

rm -rf "$project_root"

######## root-level arvd residue should fail check

project_root="$(make_project)"
write_file "$project_root/issues/tk10011.arvd.runtime.archive-residue.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: root-level arvd files should not survive after archive
scope: detect half-migrated archive residue
risk: low
accept: check fails on residue
memory: none
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on root-level arvd residue"
assert_contains "$task_stderr" "archived task residue detected" "check should explain archive residue failure"

rm -rf "$project_root"

######## legacy docs/plan should not be an active check target

project_root="$(make_project)"
mkdir -p "$project_root/docs/plan"
write_file "$project_root/refs/task-check-banned-terms.tsv" <<'EOF'
forbidden-shim
EOF
write_file "$project_root/docs/plan/pl0001.rvw.repo.legacy-plan.md" <<'EOF'
# Legacy Plan

This retired docs/plan file mentions forbidden-shim but must not affect active checks.
EOF
write_file "$project_root/issues/tk10030.tdo.runtime.clean-active-target.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: active issues remain the banned-term target
scope: prove docs plan is legacy-only
risk: low
accept: check ignores legacy docs plan
memory: none
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should ignore legacy docs/plan for active banned terms"
assert_eq "$task_stdout" "ok" "legacy docs/plan should not trip active checks"

write_file "$project_root/issues/tk10031.tdo.runtime.banned-active-target.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: forbidden-shim in active issue should still fail
scope: prove active issue remains checked
risk: low
accept: active issue fails banned-term check
memory: none
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should still scan active issue files for banned terms"
assert_contains "$task_stderr" "banned architecture term" "check should report active banned terms"

rm -rf "$project_root"

######## progress workpad command and validation

project_root="$(make_project)"
write_file "$project_root/issues/tk10040.tdo.runtime.progress-parent.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: progress files should hang off a parent task
scope: validate docs/progress helper
risk: low
accept: progress helper creates a task-scoped workpad
memory: none
links: []
---
EOF

run_task "$project_root" progress tk10040 s01-repro
assert_eq "$task_status" "0" "progress command should create a default tdo step"
assert_eq "$task_stdout" "$project_root/docs/progress/tk10040.s01-repro.tdo.md" "progress path should be task-scoped"
assert_contains "$(cat "$task_stdout")" "env:" "progress file should include env stamp"

run_task "$project_root" find tk10040.s01-repro
assert_eq "$task_status" "0" "find should locate progress by stable step id"
assert_eq "$task_stdout" "$project_root/docs/progress/tk10040.s01-repro.tdo.md" "find should return current progress path"

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept valid progress file"
assert_eq "$task_stdout" "ok" "valid progress file should pass"

run_task "$project_root" move tk10040 doi
assert_eq "$task_status" "0" "move to doi should still work with open progress"
run_task "$project_root" move tk10040 dne
assert_eq "$task_status" "1" "move to dne should reject open progress"
assert_contains "$task_stderr" "open progress must be drained" "move should explain open progress gate"

mv "$project_root/docs/progress/tk10040.s01-repro.tdo.md" "$project_root/docs/progress/tk10040.s01-repro.doi.md"
write_file "$project_root/docs/progress/tk10040.s02-fix.doi.md" <<'EOF'
# tk10040.s02-fix
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should reject multiple doi progress steps"
assert_contains "$task_stderr" "multiple doi progress steps" "check should explain multiple doi progress"

rm -rf "$project_root"

######## closed tasks cannot keep open progress

project_root="$(make_project)"
write_file "$project_root/issues/tk10041.dne.runtime.closed-parent.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: closed parent cannot keep open progress
scope: validate progress drain rule
risk: low
accept: open progress under dne parent fails
memory: none
links: []
---
EOF

run_task "$project_root" progress tk10041 s01-late
assert_eq "$task_status" "1" "progress command should reject open progress for closed parent"
assert_contains "$task_stderr" "closed task cannot start open progress" "progress should explain closed parent"

write_file "$project_root/docs/progress/tk10041.s01-late.tdo.md" <<'EOF'
# tk10041.s01-late
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should reject stranded open progress under closed parent"
assert_contains "$task_stderr" "closed task has open progress" "check should explain stranded progress"

rm -rf "$project_root"

######## aidocs should be staging, not workflow truth

project_root="$(make_git_project)"
mkdir -p "$project_root/aidocs/inbox" "$project_root/aidocs/design" "$project_root/aidocs/agent-runs"
write_file "$project_root/refs/task-check-banned-terms.tsv" <<'EOF'
forbidden-shim
EOF
write_file "$project_root/aidocs/inbox/tk9999.rvw.runtime.raw-drop.p1.md" <<'EOF'
# Raw Drop

This filename looks like workflow truth and mentions forbidden-shim, but aidocs is staging.
EOF
write_file "$project_root/aidocs/design/pl9999.tdo.visual.reference.md" <<'EOF'
# Design Reference

This is a raw design note, not a workflow plan.
EOF
write_file "$project_root/aidocs/agent-runs/tk9999.impl-codex-20260430T1030Z.md" <<'EOF'
# Failed Sub-Agent Run

This mentions tk9999.rvw and forbidden-shim, but remains low-trust staging.
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should ignore aidocs staging files"
assert_eq "$task_stdout" "ok" "aidocs staging should not trip active checks"

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "0" "orphan-scan should ignore untracked aidocs files"
assert_eq "$task_stdout" "ok" "aidocs staging should not be reported as truth drift"

rm -rf "$project_root"

######## rvw state residue should fail check

project_root="$(make_project)"
write_file "$project_root/issues/tk10002.rvw.runtime.retired-state.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: rvw is retired as a task state
scope: reject retired state residue
risk: low
accept: check rejects rvw residue
memory: none
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on retired rvw state"
assert_contains "$task_stderr" "rvw state is retired" "check should explain retired rvw state"

rm -rf "$project_root"

######## move should reject new rvw targets

project_root="$(make_project)"
write_file "$project_root/issues/tk0003.doi.runtime.no-rvw-target.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: rvw must no longer be a legal target state
scope: reject new moves into rvw
risk: low
accept: move rvw fails
memory: none
claimed_at: 2026-04-16T00:00:00Z
claimed_by: codex
links: []
---
EOF

run_task "$project_root" move 0003 rvw
assert_eq "$task_status" "1" "move should reject rvw as a new target"
assert_contains "$task_stderr" "invalid state: rvw" "move should explain invalid rvw target"

rm -rf "$project_root"

######## legacy rvw tasks should be movable out for migration

project_root="$(make_project)"
write_file "$project_root/issues/tk10006.rvw.runtime.legacy-review.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: old projects need a direct escape from retired rvw
scope: migrate old rvw tasks back to doi
risk: low
accept: move rvw to doi succeeds
memory: none
links: []
---
EOF

run_task "$project_root" move 10006 doi
assert_eq "$task_status" "0" "move should allow legacy rvw tasks to leave rvw"
assert_eq "$task_stdout" "$project_root/issues/tk10006.doi.runtime.legacy-review.p1.md" "legacy rvw should migrate to doi"

rm -rf "$project_root"

######## legacy rvw plans should be movable out for migration

project_root="$(make_project)"
write_file "$project_root/issues/pl10006.rvw.model.legacy-plan-review.p2.md" <<'EOF'
---
owner: user
assignee: codex
why: old projects may have non-task docs stranded in retired rvw
scope: migrate old rvw plans to a legal terminal state
risk: low
accept: move pl rvw to dne succeeds
memory: none
links: []
---
EOF

run_task "$project_root" move pl10006 dne
assert_eq "$task_status" "0" "move should allow legacy rvw plans to leave rvw"
assert_eq "$task_stdout" "$project_root/issues/pl10006.dne.model.legacy-plan-review.p2.md" "legacy rvw plan should migrate to dne"

rm -rf "$project_root"

######## memory gate should only trust explicit anchors

project_root="$(make_project)"
write_file "$project_root/issues/tk10004.dne.runtime.memory-anchor.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: memory gate should require an explicit anchor
scope: close task with memory gate
risk: low
accept: reject weak memory mention
memory: required
links: []
---
EOF
write_file "$project_root/refs/project-memory-aaak.md" <<'EOF'
# 项目历史记忆

题: tk10004-memory
时: 2026-04-11
决: only mentioning the task id should not pass
源: tk10004
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail when memory anchor is missing"
assert_contains "$task_stderr" "missing project memory anchor" "check should ask for explicit memory anchor"

write_file "$project_root/refs/project-memory-aaak.md" <<'EOF'
# 项目历史记忆

题: tk10004-memory
时: 2026-04-11
锚：tk10004
决: explicit anchor should satisfy memory gate
源: tk10004
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should pass once memory anchor exists"
assert_eq "$task_stdout" "ok" "successful check should print ok"

rm -rf "$project_root"

######## 4-digit and 5-digit ids should not collide by bare numeric value

project_root="$(make_project)"
write_file "$project_root/issues/tk0001.tdo.runtime.numeric-collision-four.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: bare numeric ids must stay unique
scope: detect 4-digit and 5-digit collisions
risk: low
accept: colliding ids fail check
memory: none
links: []
---
EOF
write_file "$project_root/issues/tk00001.tdo.runtime.numeric-collision-five.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: bare numeric ids must stay unique
scope: detect 4-digit and 5-digit collisions
risk: low
accept: colliding ids fail check
memory: none
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on colliding bare numeric issue ids"
assert_contains "$task_stderr" "duplicate or colliding issue ids detected" "check should explain numeric id collision"

rm -rf "$project_root"

######## different issue kinds may reuse the same numeric id

project_root="$(make_project)"
write_file "$project_root/issues/tk0001.tdo.runtime.same-number-task.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: kind prefixes are separate id namespaces
scope: allow tk and pl to share the same digits
risk: low
accept: cross-kind numeric reuse passes check
memory: none
links: []
---
EOF
write_file "$project_root/issues/pl0001.tdo.product.same-number-plan.md" <<'EOF'
---
owner: user
assignee: codex
why: plans have their own id namespace
scope: allow pl and tk to share the same digits
risk: low
accept: cross-kind numeric reuse passes check
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept same digits across different issue kinds"
assert_eq "$task_stdout" "ok" "cross-kind numeric reuse should still print ok"

write_file "$project_root/issues/pl00001.tdo.product.plan-width-collision.md" <<'EOF'
---
owner: user
assignee: codex
why: same-kind 4-digit and 5-digit ids still collide
scope: catch pl0001 versus pl00001
risk: low
accept: same-kind numeric collision fails check
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on same-kind numeric collisions"
assert_contains "$task_stderr" "duplicate or colliding issue ids detected" "check should explain same-kind numeric collision"

rm -rf "$project_root"

######## five-digit tk and rp ids should pass end-to-end

project_root="$(make_project)"
write_file "$project_root/issues/tk10005.tdo.runtime.five-digit-pass.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: 5-digit ids should work across task and review lookup
scope: prove 5-digit task and review ids
risk: low
accept: 5-digit ids pass helper validation
code_version: abc123
verify: bash verify.sh
links:
  - rp10005
---
EOF
write_file "$project_root/docs/reviews/rp10005.dne.runtime.review-r1-codex.md" <<'EOF'
# tk10005 review-r1
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept valid 5-digit task and review ids"
assert_eq "$task_stdout" "ok" "successful 5-digit check should print ok"

run_task "$project_root" show 10005
assert_eq "$task_status" "0" "show should accept raw 5-digit task ids"
assert_eq "$task_stdout" "$project_root/issues/tk10005.tdo.runtime.five-digit-pass.p1.md" "show should resolve 5-digit task ids"

run_task "$project_root" find rp10005
assert_eq "$task_status" "0" "find should locate 5-digit review ids"
assert_eq "$task_stdout" "$project_root/docs/reviews/rp10005.dne.runtime.review-r1-codex.md" "find should resolve 5-digit review ids"

rm -rf "$project_root"

######## legacy rp review anchors under issues should still resolve

project_root="$(make_project)"
write_file "$project_root/issues/tk10018.tdo.runtime.legacy-rp-review-anchor.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: legacy repos may still carry rp review docs under issues
scope: keep stable rp anchors valid during migration
risk: low
accept: check accepts rp anchors that resolve under issues
memory: none
links:
  - rp10018
---
EOF
write_file "$project_root/issues/rp10018.dne.runtime.review-r1-codex.md" <<'EOF'
# legacy rp review
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept legacy rp review anchors under issues"
assert_eq "$task_stdout" "ok" "legacy rp anchor should not block check"

rm -rf "$project_root"

######## stateful workflow link targets should fail

project_root="$(make_project)"
write_file "$project_root/issues/tk10016.tdo.runtime.stateful-link-source.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: links must use stable id anchors
scope: reject stateful filenames in links
risk: low
accept: check fails on stateful workflow link targets
memory: none
links:
  - issues/tk10017.tdo.runtime.stateful-link-target.p1.md
---
EOF
write_file "$project_root/issues/tk10017.tdo.runtime.stateful-link-target.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: stateful link target fixture
scope: provide a file that should not be linked by full name
risk: low
accept: stable id is the only allowed anchor
memory: none
links: []
---
EOF

AGATA_STRICT_STABLE_LINKS=1 run_task "$project_root" check
assert_eq "$task_status" "1" "check should reject stateful workflow link targets"
assert_contains "$task_stderr" "stateful workflow links are forbidden" "check should explain stable id anchor rule"

rm -rf "$project_root"

######## issue-scoped rv review docs should be created and validated

project_root="$(make_project)"
write_file "$project_root/issues/tk10009.doi.runtime.issue-scoped-review.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: review messages should encode parent issue and thread in the filename
scope: create one issue-scoped rv message
risk: low
accept: review command creates docs/reviews/tk10009.rv001-r001-gemini.md
memory: none
claimed_at: 2026-04-16T00:00:00Z
claimed_by: codex
links:
  - docs/reviews/tk10009.rv001-r001-gemini.md
---
EOF

run_task "$project_root" review tk10009 rv001 r001-gemini
assert_eq "$task_status" "0" "review command should create issue-scoped rv docs"
assert_eq "$task_stdout" "$project_root/docs/reviews/tk10009.rv001-r001-gemini.md" "review command should encode task, thread, round, and author"
[[ -f "$task_stdout" ]] || fail "review command should create the rv file"
! grep -q '^reviewer:' "$task_stdout" || fail "review docs should not include static reviewer"

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept valid issue-scoped rv docs"
assert_eq "$task_stdout" "ok" "valid rv check should print ok"

run_task "$project_root" find tk10009.rv001-r001-gemini
assert_eq "$task_status" "0" "find should locate issue-scoped rv docs by full review id"
assert_eq "$task_stdout" "$project_root/docs/reviews/tk10009.rv001-r001-gemini.md" "find should resolve full issue-scoped rv ids"
printf 'r001-marker\n' >>"$project_root/docs/reviews/tk10009.rv001-r001-gemini.md"

run_task "$project_root" review tk10009 rv001 r002-codex
assert_eq "$task_status" "0" "review command should create the next message in the same thread"
printf 'r002-marker\n' >>"$project_root/docs/reviews/tk10009.rv001-r002-codex.md"

thread_view="$(cat "$project_root"/docs/reviews/tk10009.rv001-r*.md)"
assert_contains "$thread_view" "r001-marker" "plain cat should read r001"
assert_contains "$thread_view" "r002-marker" "plain cat should read r002"
[[ "$thread_view" == *"r001-marker"*"r002-marker"* ]] || fail "plain cat should preserve padded round order"

write_file "$project_root/issues/pl10010.doi.runtime.plan-review.p2.md" <<'EOF'
---
owner: user
assignee: codex
why: plans also need pre-implementation review evidence
scope: create one plan-scoped rv message
risk: low
accept: review command creates docs/reviews/pl10010.rv001-r001-opus.md
memory: none
links:
  - docs/reviews/pl10010.rv001-r001-opus.md
---
EOF

run_task "$project_root" review pl10010 rv001 r001-opus
assert_eq "$task_status" "0" "review command should support non-task issue parents"
assert_eq "$task_stdout" "$project_root/docs/reviews/pl10010.rv001-r001-opus.md" "review command should encode plan parent, thread, round, and author"

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept valid plan-scoped rv docs"

run_task "$project_root" review tk10009 rv1 r2-gpt
assert_eq "$task_status" "1" "review command should reject non-padded thread ids"
assert_contains "$task_stderr" "review thread must look like rv001" "review should explain thread shape"

run_task "$project_root" review tk10009 rv001 r2-gpt
assert_eq "$task_status" "1" "review command should reject non-padded round ids"
assert_contains "$task_stderr" "review round must look like r001-author" "review should explain round shape"

rm -rf "$project_root"

######## issue-scoped rv docs should require an existing parent issue

project_root="$(make_project)"
write_file "$project_root/docs/reviews/tk10010.rv001-r001-gemini.md" <<'EOF'
---
owner: user
assignee: codex
why: orphan review docs should fail loudly
scope: reject rv docs without parent issue
risk: low
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on orphan issue-scoped rv docs"
assert_contains "$task_stderr" "issue file not found for tk10010" "check should explain missing parent issue"

rm -rf "$project_root"

######## comprehensive audits without one parent issue belong in aidocs

project_root="$(make_project)"
write_file "$project_root/docs/reviews/codex-recent-10h.rv001-r001-antigravity.md" <<'EOF'
# Codex Recent 10h Antigravity Review

This is a cross-task comprehensive audit, not one issue-scoped review exchange.
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should reject unscoped comprehensive audits in docs/reviews"
assert_contains "$task_stderr" "unscoped review/audit belongs in aidocs/agent-runs" "check should route comprehensive audits to aidocs"

rm -rf "$project_root"

project_root="$(make_project)"
mkdir -p "$project_root/aidocs/agent-runs"
write_file "$project_root/aidocs/agent-runs/codex-recent-10h.review-antigravity-20260501.md" <<'EOF'
# Codex Recent 10h Antigravity Review

This is raw comprehensive audit material. Triage may later reject, attach, or split findings.
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept comprehensive audits in aidocs staging"
assert_eq "$task_stdout" "ok" "aidocs comprehensive audit should not trip review checks"

rm -rf "$project_root"

######## depends_on should validate issue DAG edges without new states

project_root="$(make_project)"
write_file "$project_root/issues/tk10013.dne.runtime.completed-prereq.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: completed prerequisite
scope: dependency target
risk: low
accept: dependency exists
memory: none
links: []
---
EOF
write_file "$project_root/issues/tk10014.tdo.runtime.waiting-on-prereq.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: required future work can wait in tdo
scope: dependency source
risk: low
accept: depends_on validates existing issue ids
memory: none
depends_on:
  - tk10013
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "check should accept valid depends_on issue ids"
assert_eq "$task_stdout" "ok" "valid dependency check should print ok"

write_file "$project_root/issues/tk10015.tdo.runtime.missing-prereq.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: missing DAG target should fail loudly
scope: dependency source
risk: low
accept: missing depends_on target fails
memory: none
depends_on: [tk19999]
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "1" "check should fail on missing depends_on targets"
assert_contains "$task_stderr" "issue file not found for tk19999" "check should explain missing dependency target"

rm -rf "$project_root"

######## new should allocate ids from the shared control plane

project_root="$(make_git_project)"

mkdir "$project_root/.agata-new-id.lock"
run_task "$project_root" new tk runtime locked-attempt p1
assert_eq "$task_status" "1" "new should fail while the id allocation lock exists"
assert_contains "$task_stderr" "new id allocation is busy" "new should explain id allocation lock contention"
rmdir "$project_root/.agata-new-id.lock"

run_task "$project_root" new tk runtime sample-created p1
assert_eq "$task_status" "0" "new tk should succeed in shared root checkout"
assert_eq "$task_stdout" "$project_root/issues/tk0001.tdo.runtime.sample-created.p1.md" "new tk should allocate first 4-digit id"
[[ -f "$task_stdout" ]] || fail "new tk should create the file"
grep -q "memory: none" "$task_stdout" || fail "new tk should include default memory mode"
grep -Fqx 'recap: "态:tdo|核:TODO|界:TODO|验:TODO|下:TODO"' "$task_stdout" || fail "new tk should include default recap index"
grep -Fqx 'depends_on: []' "$task_stdout" || fail "new tk should include default dependency list"
! grep -q '^reviewer:' "$task_stdout" || fail "new tk should not include static reviewer"
[[ ! -d "$project_root/.agata-new-id.lock" ]] || fail "new should release the id allocation lock"

run_task "$project_root" new pl product sample-plan
assert_eq "$task_status" "0" "new pl should succeed in shared root checkout"
assert_eq "$task_stdout" "$project_root/issues/pl0001.tdo.product.sample-plan.md" "new pl should allocate from the pl namespace"

run_task "$project_root" new tk runtime second-task p2
assert_eq "$task_status" "0" "new tk should ignore pl ids while allocating"
assert_eq "$task_stdout" "$project_root/issues/tk0002.tdo.runtime.second-task.p2.md" "new tk should advance only the tk namespace"

run_task "$project_root" new tk rvw reserved-board p1
assert_eq "$task_status" "1" "new should reject rvw as a retired reserved board name"
assert_contains "$task_stderr" "board must not be a workflow state" "new should explain reserved board names"

run_task "$project_root" new rp runtime legacy-review
assert_eq "$task_status" "1" "new should reject legacy global rp docs"
assert_contains "$task_stderr" "rp is legacy" "new should point review creation to issue-scoped review command"

linked_root="$(make_linked_worktree "$project_root" "task/new-control-plane")"
run_task "$linked_root" new rs runtime linked-attempt
assert_eq "$task_status" "0" "new should route to the shared control plane from a linked worktree"
assert_eq "$task_stdout" "$project_root/issues/rs0001.tdo.runtime.linked-attempt.md" "linked worktree new should still create truth on the control plane"
[[ -f "$task_stdout" ]] || fail "linked worktree new should create the control-plane file"
[[ ! -f "$linked_root/issues/rs0001.tdo.runtime.linked-attempt.md" ]] || fail "linked worktree new should not write the mirror truth path locally"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## check should reject direct truth edits inside linked worktrees

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10008.doi.runtime.truth-edit-drift.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: linked worktrees must not edit truth files directly
scope: fail check on local truth drift
risk: low
accept: check rejects truth edits in linked worktree
memory: none
claimed_at: 2026-04-16T00:00:00Z
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10008.doi.runtime.truth-edit-drift.p1.md
  git commit -qm "plan(runtime): add truth edit drift test [tk10008]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10008-truth-drift")"
cat >>"$linked_root/issues/tk10008.doi.runtime.truth-edit-drift.p1.md" <<'EOF'

# 本地草稿

1. this should not live in a linked worktree truth file
EOF

run_task "$linked_root" check
assert_eq "$task_status" "1" "check should fail when linked worktree edits truth files"
assert_contains "$task_stderr" "truth-source edits in a linked worktree" "check should explain linked worktree truth drift"

run_task "$linked_root" orphan-scan main 10008
assert_eq "$task_status" "1" "orphan-scan should still inspect the current linked worktree for truth drift"
assert_contains "$task_stdout" "worktree M issues/tk10008.doi.runtime.truth-edit-drift.p1.md" "orphan-scan should report linked worktree truth edits"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## doi tasks should warn on missing or stale claimed_at without failing

project_root="$(make_project)"
write_file "$project_root/issues/tk10013.doi.runtime.stale-claim.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: stale doi claims should surface during check
scope: warn on zombie lock candidates
risk: low
accept: stale doi shows a warning
memory: none
claimed_at: 2000-01-01T00:00:00Z
claimed_by: codex
claimed_thread_id: thread-stale
links: []
---
EOF
write_file "$project_root/issues/tk10014.doi.runtime.missing-claim.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: missing claim timestamps should also surface
scope: warn on malformed doi metadata
risk: low
accept: missing claimed_at shows a warning
memory: none
links: []
---
EOF
write_file "$project_root/issues/tk10015.doi.runtime.generic-claimant-without-thread.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: generic engine claimants need a thread marker
scope: warn when same-engine concurrency cannot be disambiguated
risk: low
accept: missing claimed_thread_id shows a warning
memory: none
claimed_at: 2026-04-16T00:00:00Z
claimed_by: codex
links: []
---
EOF

run_task "$project_root" check
assert_eq "$task_status" "0" "stale doi warnings should not fail check"
assert_eq "$task_stdout" "ok" "stale doi warnings should still finish with ok"
assert_contains "$task_stderr" "warning: stale doi task: tk10013" "check should warn on stale doi"
assert_contains "$task_stderr" "warning: doi task missing claimed_at: tk10014" "check should warn on missing claim timestamp"
assert_contains "$task_stderr" "warning: doi task missing claimed_by: tk10014" "check should warn on missing claim owner"
assert_contains "$task_stderr" "warning: doi task generic claimant needs claimed_thread_id: tk10015 -> codex" "check should warn when generic claimants lack a thread id"

rm -rf "$project_root"

######## linked worktree check should use control-plane semantics, not stale mirror truth

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10024.doi.runtime.control-plane-check-stale.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: linked check must not judge stale doi from an old mirror
scope: semantic checks should read the control plane
risk: low
accept: linked check ignores stale doi that only exists in the mirror
memory: none
claimed_at: 2000-01-01T00:00:00Z
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10024.doi.runtime.control-plane-check-stale.p1.md
  git commit -qm "plan(runtime): add linked check stale mirror case [tk10024]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10024-check")"

run_task "$project_root" move 10024 bkd
assert_eq "$task_status" "0" "control plane should be able to move the task away from stale doi"

run_task "$linked_root" check
assert_eq "$task_status" "0" "linked worktree check should still pass after control plane releases the stale doi"
assert_eq "$task_stdout" "ok" "linked worktree check should still finish with ok"
assert_not_contains "$task_stderr" "stale doi task: tk10024" "linked worktree check should not warn on stale mirror doi"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## linked worktree check should still see duplicate issue ids from the control plane

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10025.tdo.runtime.control-plane-check-duplicate-a.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: linked check must judge duplicate ids from the control plane
scope: duplicate detection should not use stale mirror-only view
risk: low
accept: linked check fails on control-plane duplicate ids
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10025.tdo.runtime.control-plane-check-duplicate-a.p1.md
  git commit -qm "plan(runtime): add linked check duplicate base [tk10025]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10025-check")"
write_file "$project_root/issues/tk10025.doi.runtime.control-plane-check-duplicate-b.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: duplicate id exists only on the control plane branch history
scope: make sure linked check still sees the collision
risk: low
accept: duplicate detection uses the control-plane issue namespace
memory: none
claimed_at: 2026-04-16T00:00:00Z
links: []
---
EOF

run_task "$linked_root" check
assert_eq "$task_status" "1" "linked worktree check should fail on control-plane duplicate ids"
assert_contains "$task_stderr" "duplicate or colliding issue ids detected" "linked worktree check should report control-plane duplicate ids"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## move and show should route control-plane truth through a linked worktree

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10007.tdo.runtime.control-plane-move.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: workflow state changes should route through the shared control plane
scope: linked worktrees should not mutate their local truth mirror
risk: low
accept: linked worktree move updates the control-plane task only
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10007.tdo.runtime.control-plane-move.p1.md
  git commit -qm "plan(runtime): add control-plane move test [tk10007]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10007")"

CODEX_THREAD_ID="thread-tk10007" run_task "$linked_root" move 10007 doi
assert_eq "$task_status" "0" "move should route to the shared control plane from a linked worktree"
assert_eq "$task_stdout" "$project_root/issues/tk10007.doi.runtime.control-plane-move.p1.md" "linked worktree move should rename the control-plane task"
grep -q "^claimed_at: " "$task_stdout" || fail "move to doi should stamp claimed_at"
grep -q "^claimed_by: codex$" "$task_stdout" || fail "move to doi should stamp claimed_by"
grep -q "^claimed_thread_id: thread-tk10007$" "$task_stdout" || fail "move to doi should stamp claimed_thread_id from runtime env"
[[ -f "$linked_root/issues/tk10007.tdo.runtime.control-plane-move.p1.md" ]] || fail "linked worktree mirror should stay on its own branch copy"

run_task "$linked_root" show 10007
assert_eq "$task_status" "0" "show should read the control-plane truth from a linked worktree"
assert_eq "$task_stdout" "$project_root/issues/tk10007.doi.runtime.control-plane-move.p1.md" "show should ignore the stale linked worktree mirror"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## archive should route control-plane truth through a linked worktree

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10012.dne.runtime.control-plane-archive.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: archive should land on the shared control plane even when called from a linked worktree
scope: route archive through the authoritative checkout
risk: low
accept: linked worktree archive updates the control-plane task only
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10012.dne.runtime.control-plane-archive.p1.md
  git commit -qm "plan(runtime): add control-plane archive test [tk10012]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10012")"

run_task "$linked_root" archive 10012
assert_eq "$task_status" "0" "archive should route to the shared control plane from a linked worktree"
archive_year="$(date +%Y)"
assert_eq "$task_stdout" "$project_root/issues/archive/${archive_year}/tk10012.arvd.runtime.control-plane-archive.p1.md" "linked worktree archive should move the control-plane task into yearly archive"
[[ -f "$linked_root/issues/tk10012.dne.runtime.control-plane-archive.p1.md" ]] || fail "linked worktree mirror should stay on its own branch copy after archive routing"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## prune should reject active doi worktrees

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10020.doi.runtime.prune-live-claim.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: prune must not silently delete an active claim
scope: block cleanup while doi lock is still held
risk: low
accept: prune rejects doi tasks
memory: none
claimed_at: 2026-04-16T00:00:00Z
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10020.doi.runtime.prune-live-claim.p1.md
  git commit -qm "plan(runtime): add prune doi guard [tk10020]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10020")"

run_task "$project_root" prune 10020 main
assert_eq "$task_status" "1" "prune should fail while task is still doi"
assert_contains "$task_stderr" "task in state doi cannot be pruned" "prune should explain live claim guard"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## prune should reject blocked frozen worktrees

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10021.bkd.runtime.prune-frozen-worktree.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: blocked tasks may intentionally keep a frozen worktree
scope: block prune on bkd state
risk: low
accept: prune rejects frozen blocked worktrees
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10021.bkd.runtime.prune-frozen-worktree.p1.md
  git commit -qm "plan(runtime): add prune bkd guard [tk10021]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10021")"

run_task "$project_root" prune 10021 main
assert_eq "$task_status" "1" "prune should fail while task is frozen in bkd"
assert_contains "$task_stderr" "task in state bkd cannot be pruned" "prune should explain blocked-state guard"

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## prune should refuse to delete the worktree that contains the current shell cwd

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10026.dne.runtime.prune-self-destruct-guard.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: prune should not remove the directory the current shell is standing in
scope: block self-destructing prune calls from the target worktree
risk: low
accept: prune fails before removing the active cwd worktree
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10026.dne.runtime.prune-self-destruct-guard.p1.md
  git commit -qm "plan(runtime): add prune self-destruct guard [tk10026]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10026")"

run_task "$linked_root" prune 10026 main
assert_eq "$task_status" "1" "prune should fail when called from inside the target worktree"
assert_contains "$task_stderr" "prune cannot remove the linked worktree that contains the current shell cwd" "prune should explain the self-destruct guard"
[[ -d "$linked_root" ]] || fail "self-destruct guard should keep the linked worktree in place"
(
  cd "$project_root"
  if ! git rev-parse --verify --quiet refs/heads/task/tk10026 >/dev/null; then
    fail "self-destruct guard should keep the local branch"
  fi
)

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## prune should remove a settled worktree whose execution diff is already landed

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10022.dne.runtime.prune-landed-worktree.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: landed task worktrees should be removable from the control plane
scope: delete linked worktree and its local branch after reconciliation
risk: low
accept: prune removes the clean linked worktree
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10022.dne.runtime.prune-landed-worktree.p1.md
  git commit -qm "plan(runtime): add prune success case [tk10022]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10022")"
write_file "$linked_root/src/prune-landed.js" <<'EOF'
export const pruneLanded = true;
EOF
(
  cd "$linked_root"
  git add src/prune-landed.js
  git commit -qm "feat(runtime): add landed prune sample [tk10022]"
)
(
  cd "$project_root"
  git merge --no-ff -qm "merge task/tk10022" task/tk10022
)

run_task "$project_root" prune 10022 main
assert_eq "$task_status" "0" "prune should succeed once code is landed and task is closed"
assert_contains "$task_stdout" "branch: task/tk10022" "prune should report the cleaned local branch"
[[ ! -d "$linked_root" ]] || fail "prune should remove the linked worktree directory"
(
  cd "$project_root"
  if git rev-parse --verify --quiet refs/heads/task/tk10022 >/dev/null; then
    fail "prune should delete the local branch"
  fi
)

rm -rf "$project_root"

######## prune should reject closed tasks whose execution diff is not yet landed

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10023.dne.runtime.prune-unlanded-worktree.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: cleanup must stop if code still lives only in the task branch
scope: block prune on outstanding execution diff
risk: low
accept: prune fails until branch content is landed
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10023.dne.runtime.prune-unlanded-worktree.p1.md
  git commit -qm "plan(runtime): add prune diff guard [tk10023]"
)
linked_root="$(make_linked_worktree "$project_root" "task/tk10023")"
write_file "$linked_root/src/prune-unlanded.js" <<'EOF'
export const pruneUnlanded = true;
EOF
(
  cd "$linked_root"
  git add src/prune-unlanded.js
  git commit -qm "feat(runtime): add unlanded prune sample [tk10023]"
)

run_task "$project_root" prune 10023 main
assert_eq "$task_status" "1" "prune should fail when execution diff is still unique to the task branch"
assert_contains "$task_stderr" "linked worktree still carries execution diff vs main for tk10023" "prune should explain outstanding execution drift"
[[ -d "$linked_root" ]] || fail "failed prune should keep the linked worktree in place"
(
  cd "$project_root"
  if ! git rev-parse --verify --quiet refs/heads/task/tk10023 >/dev/null; then
    fail "failed prune should keep the local branch"
  fi
)

remove_linked_worktree "$project_root" "$linked_root"
rm -rf "$project_root"

######## orphan-scan should fail on untracked truth files in current worktree

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10058.tdo.runtime.stranded-worktree.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: orphan-scan should catch untracked truth in current worktree
scope: detect stranded truth before cleanup
risk: low
accept: orphan-scan fails on untracked truth
memory: none
links: []
---
EOF

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "1" "orphan-scan should fail on current worktree truth drift"
assert_contains "$task_stdout" "worktree ?? issues/tk10058.tdo.runtime.stranded-worktree.p1.md" "orphan-scan should report untracked truth path"

rm -rf "$project_root"

######## orphan-scan should treat docs/progress as workflow truth

project_root="$(make_git_project)"
write_file "$project_root/issues/tk10059.tdo.runtime.progress-truth.p1.md" <<'EOF'
---
owner: user
assignee: codex
why: docs/progress should not strand in worktrees
scope: validate progress truth scan
risk: low
accept: orphan-scan reports untracked progress files
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/tk10059.tdo.runtime.progress-truth.p1.md
  git commit -qm "test: add progress parent"
)
write_file "$project_root/docs/progress/tk10059.s01-repro.tdo.md" <<'EOF'
# tk10059.s01-repro
EOF

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "1" "orphan-scan should fail on untracked progress truth"
assert_contains "$task_stdout" "worktree ?? docs/progress/tk10059.s01-repro.tdo.md" "orphan-scan should report untracked progress path"

rm -rf "$project_root"

######## orphan-scan should treat refs/radar.md as workflow control-plane truth

project_root="$(make_git_project)"
write_file "$project_root/refs/radar.md" <<'EOF'
# Radar

## ob20260517-001 duplicate-helper

时: 2026-05-17
源: tk10059
域: runtime
位: src/runtime/helper.ts
观: duplicate helper is visible but not worth a task yet.
判: watch until another copy appears.
触: third copy appears.
动: promote to shared helper task.
态: watching
EOF

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "1" "orphan-scan should fail on untracked radar truth"
assert_contains "$task_stdout" "worktree ?? refs/radar.md" "orphan-scan should report untracked radar path"

rm -rf "$project_root"

######## orphan-scan should treat refs/agent-names.md as workflow control-plane truth

project_root="$(make_git_project)"
write_file "$project_root/refs/agent-names.md" <<'EOF'
# Agent Names

## Bindings

| name | sid | slot | engine | role | binding | note |
|---|---|---|---|---|---|---|
| neo | sid019dd9af | A | codex | frontend | thread:019dd9af | continue tk10060 |

## Pool

- ana
- ben
- neo
EOF

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "1" "orphan-scan should fail on untracked agent-name truth"
assert_contains "$task_stdout" "worktree ?? refs/agent-names.md" "orphan-scan should report untracked agent-name path"

rm -rf "$project_root"

######## orphan-scan should fail when another branch holds truth not on base

project_root="$(make_git_project)"
(
  cd "$project_root"
  git checkout -qb task/pl10042
)
write_file "$project_root/issues/pl10042.tdo.runtime.stranded-plan.md" <<'EOF'
---
owner: user
assignee: codex
why: orphan-scan should catch branch-only plan truth
scope: detect truth stranded in another branch
risk: low
accept: orphan-scan reports branch-only truth files
memory: none
links: []
---
EOF
(
  cd "$project_root"
  git add issues/pl10042.tdo.runtime.stranded-plan.md
  git commit -qm "plan(runtime): stranded proposal [pl10042]"
  git checkout -q main
)

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "1" "orphan-scan should fail when another branch carries truth drift"
assert_contains "$task_stdout" "branch:task/pl10042" "orphan-scan should report branch owner for stranded truth"
assert_contains "$task_stdout" "issues/pl10042.tdo.runtime.stranded-plan.md" "orphan-scan should report branch-only truth path"

rm -rf "$project_root"

######## orphan-scan should ignore non-truth files

project_root="$(make_git_project)"
write_file "$project_root/src/app.js" <<'EOF'
console.log("code-only drift");
EOF

run_task "$project_root" orphan-scan main
assert_eq "$task_status" "0" "orphan-scan should ignore code-only changes"
assert_eq "$task_stdout" "ok" "code-only drift should not trip orphan-scan"

rm -rf "$project_root"

echo "ok"
