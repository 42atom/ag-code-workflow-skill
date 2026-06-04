#!/bin/bash

set -euo pipefail

######## task workflow helper

VALID_STATES="tdo doi dne bkd cand arvd"
VALID_PROGRESS_STATES="tdo doi dne bkd"
RESERVED_STATE_WORDS="tdo doi rvw dne bkd cand arvd"
VALID_MEMORY_MODES="none required done"
STALE_DOI_SECONDS=259200
ID_DIGITS_RE='[0-9]{4,5}'
TRUTH_SCAN_PATHS=("issues" "docs/reviews" "docs/progress" "refs/agent-names.md" "refs/radar.md" "refs/graph.md" "refs/project-memory-aaak.md")
VALID_KINDS="tk pl rs rf"
NEW_ID_LOCK_DIR=""

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "warning: $*" >&2
}

is_valid_state() {
  local needle="$1"
  for state in $VALID_STATES; do
    if [[ "$state" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_progress_state() {
  local needle="$1"
  for state in $VALID_PROGRESS_STATES; do
    if [[ "$state" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_reserved_state_word() {
  local needle="$1"
  for state in $RESERVED_STATE_WORDS; do
    if [[ "$state" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_memory_mode() {
  local needle="$1"
  for mode in $VALID_MEMORY_MODES; do
    if [[ "$mode" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_kind() {
  local needle="$1"
  for kind in $VALID_KINDS; do
    if [[ "$kind" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_generic_claimant_label() {
  local raw="$1"

  case "$raw" in
    ""|user|agent|assistant|worker|runtime|current-runtime)
      return 0
      ;;
  esac

  return 1
}

release_new_id_lock() {
  if [[ -n "$NEW_ID_LOCK_DIR" ]]; then
    rm -f "$NEW_ID_LOCK_DIR/owner" 2>/dev/null || true
    rmdir "$NEW_ID_LOCK_DIR" 2>/dev/null || true
  fi
}

read_new_id_lock_pid() {
  local lock_dir="$1"
  local owner_file="$lock_dir/owner"

  [[ -f "$owner_file" ]] || return 1
  awk -F= '$1 == "pid" { print $2; exit }' "$owner_file"
}

pid_is_alive() {
  local pid="$1"

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

clear_stale_new_id_lock() {
  local lock_dir="$1"
  local pid

  pid="$(read_new_id_lock_pid "$lock_dir" || true)"
  if [[ -n "$pid" ]] && pid_is_alive "$pid"; then
    die "new id allocation is busy: ${lock_dir} (pid ${pid})"
  fi

  warn "clearing stale new id allocation lock: ${lock_dir}"
  rm -f "$lock_dir/owner" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || die "stale new id allocation lock is not removable: ${lock_dir}"
}

acquire_new_id_lock() {
  local root="$1"

  NEW_ID_LOCK_DIR="$root/.agata-new-id.lock"
  if ! mkdir "$NEW_ID_LOCK_DIR" 2>/dev/null; then
    clear_stale_new_id_lock "$NEW_ID_LOCK_DIR"
    mkdir "$NEW_ID_LOCK_DIR" 2>/dev/null || die "new id allocation is busy: ${NEW_ID_LOCK_DIR}"
  fi
  printf 'pid=%s\ncreated_at=%s\n' "$$" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >"$NEW_ID_LOCK_DIR/owner"
  trap release_new_id_lock EXIT
}

find_project_root() {
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/issues" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

find_control_plane_root() {
  local root="$1"
  local control_root common_git_dir

  is_git_repo "$root" || {
    printf '%s\n' "$root"
    return 0
  }

  control_root="$(git -C "$root" worktree list --porcelain | awk '
    /^worktree / {
      sub(/^worktree /, "", $0)
      print
      exit
    }
  ')"

  if [[ -d "$control_root/issues" ]]; then
    printf '%s\n' "$control_root"
    return 0
  fi

  common_git_dir="$(resolve_repo_dir "$root" "$(git -C "$root" rev-parse --git-common-dir)")"
  control_root="$(dirname "$common_git_dir")"

  if [[ -d "$control_root/issues" ]]; then
    printf '%s\n' "$control_root"
    return 0
  fi

  printf '%s\n' "$root"
}

normalize_task_id() {
  local raw="$1"
  if [[ "$raw" =~ ^${ID_DIGITS_RE}$ ]]; then
    echo "tk${raw}"
    return 0
  fi
  if [[ "$raw" =~ ^tk${ID_DIGITS_RE}$ ]]; then
    echo "$raw"
    return 0
  fi
  die "task id must be 4 or 5 digits, or tkNNNN / tkNNNNN"
}

normalize_issue_id() {
  local raw="$1"
  if [[ "$raw" =~ ^${ID_DIGITS_RE}$ ]]; then
    echo "tk${raw}"
    return 0
  fi
  if [[ "$raw" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}$ ]]; then
    echo "$raw"
    return 0
  fi
  die "issue id must be 4 or 5 digits, or {tk|pl|rs|rf}NNNN / {tk|pl|rs|rf}NNNNN"
}

strip_wrapping_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s\n' "$value"
}

find_task_file() {
  local root="$1"
  local task_id="$2"
  local matches=()

  while IFS= read -r path; do
    matches+=("$path")
  done < <(find "$root/issues" -maxdepth 1 -type f -name "${task_id}.*.md" | sort)

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "task file not found for ${task_id}"
  fi
  if [[ "${#matches[@]}" -gt 1 ]]; then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple task files found for ${task_id}"
  fi

  echo "${matches[0]}"
}

find_issue_file() {
  local root="$1"
  local issue_id="$2"
  local matches=()

  while IFS= read -r path; do
    matches+=("$path")
  done < <(find "$root/issues" -maxdepth 1 -type f -name "${issue_id}.*.md" | sort)

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "issue file not found for ${issue_id}"
  fi
  if [[ "${#matches[@]}" -gt 1 ]]; then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple issue files found for ${issue_id}"
  fi

  echo "${matches[0]}"
}

task_state_from_file() {
  local file="$1"
  local base stem after_prefix
  base="$(basename "$file")"
  stem="${base%.*}"
  after_prefix="${stem#*.}"
  echo "${after_prefix%%.*}"
}

task_id_from_file() {
  local file="$1"
  basename "$file" | cut -d. -f1
}

extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"

  awk -v wanted="$key" '
    NR == 1 && $0 == "---" { in_yaml = 1; next }
    in_yaml && $0 == "---" {
      if (in_block) {
        print block_value
      }
      exit
    }
    !in_yaml { next }

    in_block {
      if ($0 ~ /^[^[:space:]]/) {
        print block_value
        exit
      }
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (block_started) {
        block_value = block_value ORS line
      } else {
        block_value = line
        block_started = 1
      }
      next
    }

    $0 ~ ("^" wanted ":[[:space:]]*") {
      line = $0
      sub("^" wanted ":[[:space:]]*", "", line)
      if (line == "|" || line == ">") {
        in_block = 1
        block_started = 0
        block_value = ""
        next
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^'\''|'\''$/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "$file"
}

frontmatter_has_key() {
  local file="$1"
  local key="$2"

  awk -v wanted="$key" '
    NR == 1 && $0 == "---" { in_yaml = 1; next }
    in_yaml && $0 == "---" { exit }
    !in_yaml { next }
    $0 ~ ("^" wanted ":[[:space:]]*") { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$file"
}

task_basename_with_state() {
  local file="$1"
  local new_state="$2"
  local base stem prefix after_prefix suffix

  base="$(basename "$file")"
  stem="${base%.*}"
  prefix="${stem%%.*}"
  after_prefix="${stem#*.}"
  suffix="${after_prefix#*.}"
  printf '%s\n' "${prefix}.${new_state}.${suffix}.md"
}

rename_task_state() {
  local file="$1"
  local new_state="$2"
  local dir new_file

  dir="$(dirname "$file")"
  new_file="${dir}/$(task_basename_with_state "$file" "$new_state")"

  mv "$file" "$new_file"
  echo "$new_file"
}

can_transition() {
  local from="$1"
  local to="$2"

  case "$from" in
    tdo) [[ "$to" == "doi" || "$to" == "cand" ]] ;;
    doi) [[ "$to" == "dne" || "$to" == "bkd" || "$to" == "cand" ]] ;;
    rvw) [[ "$to" == "doi" || "$to" == "dne" || "$to" == "bkd" || "$to" == "cand" || "$to" == "arvd" ]] ;;
    bkd) [[ "$to" == "doi" || "$to" == "cand" ]] ;;
    dne) [[ "$to" == "arvd" ]] ;;
    cand) [[ "$to" == "arvd" ]] ;;
    arvd) [[ "$to" == "arvd" ]] ;;
    *) return 1 ;;
  esac
}

project_memory_file() {
  local root="$1"
  echo "$root/refs/project-memory-aaak.md"
}

task_needs_memory_gate() {
  local file="$1"
  local memory_mode state

  memory_mode="$(extract_frontmatter_scalar "$file" "memory")"
  if [[ -z "$memory_mode" || "$memory_mode" == "none" ]]; then
    return 1
  fi

  is_valid_memory_mode "$memory_mode" || die "invalid memory mode: $file -> $memory_mode"

  if [[ "$memory_mode" == "done" ]]; then
    return 0
  fi

  state="$(task_state_from_file "$file")"
  [[ "$state" == "dne" || "$state" == "arvd" ]]
}

memory_entry_exists() {
  local root="$1"
  local task_id="$2"
  local memory_file

  memory_file="$(project_memory_file "$root")"
  [[ -f "$memory_file" ]] || return 1
  awk -v wanted="$task_id" '
    /^锚[:：][[:space:]]*/ {
      line = $0
      sub(/^锚[:：][[:space:]]*/, "", line)
      gsub(/[|,]/, " ", line)
      count = split(line, items, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (items[i] == wanted) {
          found = 1
          exit
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$memory_file"
}

assert_memory_gate_for_close() {
  local root="$1"
  local file="$2"
  local new_state="$3"
  local task_id memory_mode

  if [[ "$new_state" != "dne" && "$new_state" != "arvd" ]]; then
    return 0
  fi

  memory_mode="$(extract_frontmatter_scalar "$file" "memory")"
  if [[ -z "$memory_mode" || "$memory_mode" == "none" ]]; then
    return 0
  fi

  is_valid_memory_mode "$memory_mode" || die "invalid memory mode: $file -> $memory_mode"

  task_id="$(task_id_from_file "$file")"
  memory_entry_exists "$root" "$task_id" || die "missing project memory anchor for ${task_id}: $(project_memory_file "$root")"
}

assert_progress_drained_for_close() {
  local root="$1"
  local issue_id="$2"
  local new_state="$3"
  local open_progress

  [[ "$issue_id" =~ ^tk${ID_DIGITS_RE}$ ]] || return 0
  [[ "$new_state" == "dne" || "$new_state" == "cand" || "$new_state" == "arvd" ]] || return 0
  [[ -d "$root/docs/progress" ]] || return 0

  open_progress="$(find "$root/docs/progress" -maxdepth 1 -type f \( -name "${issue_id}.*.tdo.md" -o -name "${issue_id}.*.doi.md" -o -name "${issue_id}.*.bkd.md" \) | sort)"
  if [[ -n "$open_progress" ]]; then
    printf '%s\n' "$open_progress" >&2
    die "open progress must be drained before closing ${issue_id}"
  fi
}

print_usage() {
  cat <<'EOF'
usage:
  task.sh new <kind> <board> <slug> [prio]
  task.sh review <issue-id> <rvNNN> <rNNN-author> [block|pass|note]
  task.sh progress <task-id> <sNN-slug> [state]
  task.sh ls [state]
  task.sh find <id>
  task.sh show <task-id>
  task.sh move <issue-id> <state>
  task.sh reopen <issue-id> <reason>
  task.sh archive <task-id>
  task.sh archive-done [--keep N]
  task.sh prune <task-id> <base-ref>
  task.sh check
  task.sh orphan-scan <base-ref> [filter]
EOF
}

assert_git_repo() {
  local root="$1"
  local cmd_name="$2"

  git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || die "${cmd_name} requires a git repository"
}

is_git_repo() {
  local root="$1"

  git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1
}

resolve_repo_dir() {
  local root="$1"
  local path="$2"

  if [[ "$path" != /* ]]; then
    path="${root}/${path}"
  fi

  (
    cd "$path"
    pwd -P
  )
}

is_control_plane_checkout() {
  local root="$1"
  local git_dir common_git_dir

  is_git_repo "$root" || return 0

  git_dir="$(resolve_repo_dir "$root" "$(git -C "$root" rev-parse --git-dir)")"
  common_git_dir="$(resolve_repo_dir "$root" "$(git -C "$root" rev-parse --git-common-dir)")"
  [[ "$git_dir" == "$common_git_dir" ]]
}

assert_control_plane_checkout() {
  local root="$1"
  local cmd_name="$2"
  local git_dir common_git_dir control_root

  is_git_repo "$root" || return 0

  git_dir="$(resolve_repo_dir "$root" "$(git -C "$root" rev-parse --git-dir)")"
  common_git_dir="$(resolve_repo_dir "$root" "$(git -C "$root" rev-parse --git-common-dir)")"
  control_root="$(dirname "$common_git_dir")"

  if [[ "$git_dir" != "$common_git_dir" ]]; then
    die "${cmd_name} must run from the shared root checkout control plane: ${control_root}"
  fi
}

assert_no_truth_edits_in_linked_worktree() {
  local root="$1"
  local cmd_name="$2"
  local truth_edits

  is_git_repo "$root" || return 0
  is_control_plane_checkout "$root" && return 0

  truth_edits="$(git -C "$root" status --porcelain --untracked-files=all -- "${TRUTH_SCAN_PATHS[@]}" || true)"
  if [[ -n "$truth_edits" ]]; then
    echo "$truth_edits" >&2
    die "${cmd_name} found truth-source edits in a linked worktree; move them to the shared root checkout control plane"
  fi
}

assert_base_ref() {
  local root="$1"
  local base_ref="$2"

  git -C "$root" rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null 2>&1 \
    || die "unknown base ref: ${base_ref}"
}

emit_orphan_line() {
  local prefix="$1"
  local line="$2"
  local filter="${3:-}"

  [[ -n "$line" ]] || return 0
  line="${line# }"
  if [[ -n "$filter" && "$line" != *"$filter"* ]]; then
    return 0
  fi
  printf '%s %s\n' "$prefix" "$line"
}

scan_worktree_truth() {
  local root="$1"
  local filter="${2:-}"
  local line

  while IFS= read -r line; do
    emit_orphan_line "worktree" "$line" "$filter"
  done < <(git -C "$root" status --porcelain --untracked-files=all -- "${TRUTH_SCAN_PATHS[@]}" || true)
}

scan_ref_truth() {
  local root="$1"
  local base_ref="$2"
  local ref_label="$3"
  local ref_target="$4"
  local filter="${5:-}"
  local line

  while IFS= read -r line; do
    emit_orphan_line "$ref_label" "$line" "$filter"
  done < <(
    git -C "$root" diff --name-status --find-renames --diff-filter=ACMR "${base_ref}...${ref_target}" -- "${TRUTH_SCAN_PATHS[@]}" || true
  )
}

cmd_orphan_scan() {
  local root="$1"
  local base_ref="$2"
  local filter="${3:-}"
  local control_root current_branch ref
  local findings=()

  control_root="$(find_control_plane_root "$root")"

  assert_git_repo "$control_root" "orphan-scan"
  assert_base_ref "$control_root" "$base_ref"

  while IFS= read -r ref; do
    findings+=("$ref")
  done < <(scan_worktree_truth "$root" "$filter")

  while IFS= read -r ref; do
    findings+=("$ref")
  done < <(scan_ref_truth "$root" "$base_ref" "head" "HEAD" "$filter")

  current_branch="$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ "$ref" == "$current_branch" ]] && continue
    [[ "$ref" == "$base_ref" ]] && continue
    while IFS= read -r line; do
      findings+=("$line")
    done < <(scan_ref_truth "$control_root" "$base_ref" "branch:${ref}" "$ref" "$filter")
  done < <(git -C "$control_root" for-each-ref --format='%(refname:short)' refs/heads | sort)

  if [[ "${#findings[@]}" -eq 0 ]]; then
    echo "ok"
    return 0
  fi

  printf '%s\n' "${findings[@]}"
  return 1
}

text_matches_task_id() {
  local text="$1"
  local task_id="$2"

  [[ "$text" =~ (^|[^[:alnum:]])${task_id}([^[:alnum:]]|$) ]]
}

list_matching_linked_worktrees() {
  local root="$1"
  local task_id="$2"
  local control_root current_path current_branch current_detached

  control_root="$(resolve_repo_dir "$root" "$root")"
  current_path=""
  current_branch=""
  current_detached=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      if [[ -n "$current_path" ]]; then
        current_path="$(resolve_repo_dir "$root" "$current_path")"
        if [[ "$current_path" != "$control_root" ]]; then
          if text_matches_task_id "$current_path" "$task_id" || text_matches_task_id "$current_branch" "$task_id"; then
            if (( current_detached )); then
              printf '%s\t%s\n' "$current_path" "__DETACHED__"
            else
              printf '%s\t%s\n' "$current_path" "$current_branch"
            fi
          fi
        fi
      fi
      current_path=""
      current_branch=""
      current_detached=0
      continue
    fi

    case "$line" in
      worktree\ *)
        current_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        current_detached=0
        ;;
      detached)
        current_branch=""
        current_detached=1
        ;;
    esac
  done < <(git -C "$root" worktree list --porcelain; printf '\n')
}

resolve_task_worktree() {
  local root="$1"
  local task_id="$2"
  local matches=()

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    matches+=("$line")
  done < <(list_matching_linked_worktrees "$root" "$task_id")

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "no linked worktree found for ${task_id}; prune only cleans an active dedicated worktree"
  fi

  if [[ "${#matches[@]}" -gt 1 ]]; then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple linked worktrees match ${task_id}; prune needs a single unambiguous target"
  fi

  printf '%s\n' "${matches[0]}"
}

next_doc_digits() {
  local root="$1"
  local kind="$2"
  local path base digits num max_num width next_num

  max_num=0
  width=4
  while IFS= read -r path; do
    base="$(basename "$path")"
    if [[ "$base" =~ ^(tk|pl|rs|rf)([0-9]{4,5})\. ]]; then
      digits="${BASH_REMATCH[2]}"
      num=$((10#$digits))
      (( num > max_num )) && max_num="$num"
      (( ${#digits} > width )) && width="${#digits}"
    fi
  done < <(find "$root/issues" -type f -name "*.md" | sort)

  next_num=$((max_num + 1))
  (( ${#next_num} > width )) && width="${#next_num}"
  printf "%0${width}d\n" "$next_num"
}

issue_doc_path() {
  local root="$1"
  local kind="$2"
  local digits="$3"
  local board="$4"
  local slug="$5"
  local prio="${6:-}"
  local state
  local suffix=""

  case "$kind" in
    *)
      state="tdo"
      ;;
  esac

  if [[ -n "$prio" ]]; then
    suffix=".${prio}"
  fi

  printf '%s\n' "$root/issues/${kind}${digits}.${state}.${board}.${slug}${suffix}.md"
}

review_doc_path() {
  local root="$1"
  local issue_id="$2"
  local thread="$3"
  local round_author="$4"

  printf '%s\n' "$root/docs/reviews/${issue_id}.${thread}-${round_author}.md"
}

progress_doc_path() {
  local root="$1"
  local task_id="$2"
  local step_slug="$3"
  local state="$4"

  printf '%s\n' "$root/docs/progress/${task_id}.${step_slug}.${state}.md"
}

write_new_issue_doc() {
  local file="$1"
  local kind="$2"
  local review_result="${3:-note}"

  mkdir -p "$(dirname "$file")"

  case "$kind" in
    rv)
      cat >"$file" <<EOF
---
owner: user
assignee: agent
result: ${review_result}
why: TODO
scope: TODO
risk: low
links: []
---

# 结论

TODO

# 交换

1. TODO

# 验证

1. TODO
EOF
      ;;
    *)
      cat >"$file" <<'EOF'
---
owner: user
assignee: agent
recap: "态:tdo|核:TODO|界:TODO|验:TODO|下:TODO"
why: TODO
scope: TODO
risk: low
accept: TODO
memory: none
depends_on: []
links: []
---

# 任务

TODO

# 范围

1. TODO

# 非范围

1. TODO
EOF
      ;;
  esac
}

write_new_progress_doc() {
  local file="$1"
  local task_id="$2"
  local step_slug="$3"
  local host workdir sha env_stamp

  mkdir -p "$(dirname "$file")"
  host="$(hostname 2>/dev/null || echo unknown-host)"
  workdir="$(pwd -P)"
  sha="$(git -C "$workdir" rev-parse --short HEAD 2>/dev/null || echo no-git)"
  env_stamp="${host}:${workdir}@${sha}"

  cat >"$file" <<EOF
# ${task_id}.${step_slug}

env: ${env_stamp}

## Done

TODO

## Verify

TODO

## Next

TODO

## Risk

TODO
EOF
}

cmd_new() {
  local root="$1"
  local kind="$2"
  local board="$3"
  local slug="$4"
  local prio="${5:-}"
  local digits file

  assert_control_plane_checkout "$root" "new"
  if [[ "$kind" == "rp" ]]; then
    die "rp is legacy; use: task.sh review <issue-id> <rvNNN> <rNNN-author>"
  fi
  if [[ "$kind" == "rv" ]]; then
    die "rv docs are issue-scoped; use: task.sh review <issue-id> <rvNNN> <rNNN-author>"
  fi

  is_valid_kind "$kind" || die "invalid kind: ${kind}"
  [[ "$board" =~ ^[a-z0-9-]+$ ]] || die "board must match [a-z0-9-]+"
  [[ "$slug" =~ ^[a-z0-9-]+$ ]] || die "slug must match [a-z0-9-]+"

  if is_reserved_state_word "$board"; then
    die "board must not be a workflow state; usage: task.sh new <kind> <board> <slug> [prio]"
  fi

  if [[ -n "$prio" ]]; then
    [[ "$prio" =~ ^p[0-9]+$ ]] || die "prio must look like p0 / p1 / p2"
  fi

  acquire_new_id_lock "$root"
  digits="$(next_doc_digits "$root" "$kind")"
  file="$(issue_doc_path "$root" "$kind" "$digits" "$board" "$slug" "$prio")"
  [[ ! -e "$file" ]] || die "document already exists: $file"

  write_new_issue_doc "$file" "$kind"
  release_new_id_lock
  trap - EXIT
  echo "$file"
}

cmd_progress() {
  local root="$1"
  local task_id step_slug state file parent_file parent_state

  assert_control_plane_checkout "$root" "progress"
  task_id="$(normalize_task_id "$2")"
  step_slug="$3"
  state="${4:-tdo}"

  parent_file="$(find_task_file_anywhere "$root" "$task_id")"
  parent_state="$(task_state_from_file "$parent_file")"
  [[ "$step_slug" =~ ^s[0-9]{2}-[a-z0-9-]+$ ]] || die "progress step must look like s01-repro"
  is_valid_progress_state "$state" || die "invalid progress state: ${state}"
  if [[ "$parent_state" =~ ^(dne|cand|arvd)$ && "$state" != "dne" ]]; then
    die "closed task cannot start open progress: ${task_id}.${step_slug}.${state}"
  fi

  file="$(progress_doc_path "$root" "$task_id" "$step_slug" "$state")"
  [[ ! -e "$file" ]] || die "document already exists: $file"

  write_new_progress_doc "$file" "$task_id" "$step_slug"
  echo "$file"
}

cmd_review() {
  local root="$1"
  local issue_id thread round_author result file

  assert_control_plane_checkout "$root" "review"
  issue_id="$(normalize_issue_id "$2")"
  thread="$3"
  round_author="$4"
  result="${5:-note}"

  find_issue_file_anywhere "$root" "$issue_id" >/dev/null
  [[ "$thread" =~ ^rv[0-9]{3}$ ]] || die "review thread must look like rv001"
  [[ "$round_author" =~ ^r[0-9]{3}-[a-z0-9-]+$ ]] || die "review round must look like r001-author"
  [[ "$result" =~ ^(block|pass|note)$ ]] || die "review result must be block, pass, or note"

  file="$(review_doc_path "$root" "$issue_id" "$thread" "$round_author")"
  [[ ! -e "$file" ]] || die "document already exists: $file"

  write_new_issue_doc "$file" "rv" "$result"
  echo "$file"
}

normalize_doc_id() {
  local raw="$1"
  if [[ "$raw" =~ ^${ID_DIGITS_RE}$ ]]; then
    echo "tk${raw}"
    return 0
  fi
  if [[ "$raw" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+(\.(tdo|doi|dne|bkd))?(\.md)?$ ]]; then
    raw="${raw%.md}"
    raw="${raw%.tdo}"
    raw="${raw%.doi}"
    raw="${raw%.dne}"
    raw="${raw%.bkd}"
    echo "$raw"
    return 0
  fi
  if [[ "$raw" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.md)?$ ]]; then
    echo "${raw%.md}"
    return 0
  fi
  if [[ "$raw" =~ ^(tk|pl|rs|rf|rp)${ID_DIGITS_RE}$ ]]; then
    echo "$raw"
    return 0
  fi
  die "id must be 4 or 5 digits, {tk|pl|rs|rf|rp}NNNN, or <issue-id>.rvNNN-rNNN-author"
}

find_doc_file() {
  local root="$1"
  local doc_id="$2"
  local matches=()
  local path

  if [[ "$doc_id" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+$ ]]; then
    while IFS= read -r path; do
      matches+=("$path")
    done < <(find "$root/docs/progress" -maxdepth 1 -type f -name "${doc_id}.*.md" 2>/dev/null | sort)
    if [[ "${#matches[@]}" -eq 0 ]]; then
      die "document not found for ${doc_id}"
    fi
    if [[ "${#matches[@]}" -gt 1 ]]; then
      printf '%s\n' "${matches[@]}" >&2
      die "multiple progress files found for ${doc_id}"
    fi
    printf '%s\n' "${matches[0]}"
    return 0
  fi

  if [[ "$doc_id" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+$ ]]; then
    path="$root/docs/reviews/${doc_id}.md"
    [[ -f "$path" ]] || die "document not found for ${doc_id}"
    printf '%s\n' "$path"
    return 0
  fi

  while IFS= read -r path; do
    matches+=("$path")
  done < <(
    {
      find "$root/issues" -type f -name "${doc_id}.*.md" 2>/dev/null
      find "$root/docs/reviews" -type f -name "${doc_id}.*.md" 2>/dev/null
    } | sort
  )

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "document not found for ${doc_id}"
  fi

  printf '%s\n' "${matches[@]}"
}

find_task_file_anywhere() {
  local root="$1"
  local task_id="$2"
  local matches=()
  local path

  while IFS= read -r path; do
    [[ "$path" == "$root/issues/"* ]] || continue
    matches+=("$path")
  done < <(find_doc_file "$root" "$task_id")

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "task file not found for ${task_id}"
  fi

  if [[ "${#matches[@]}" -gt 1 ]]; then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple task files found for ${task_id}"
  fi

  printf '%s\n' "${matches[0]}"
}

find_issue_file_anywhere() {
  local root="$1"
  local issue_id="$2"
  local matches=()
  local path

  while IFS= read -r path; do
    [[ "$path" == "$root/issues/"* ]] || continue
    matches+=("$path")
  done < <(find_doc_file "$root" "$issue_id")

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "issue file not found for ${issue_id}"
  fi

  if [[ "${#matches[@]}" -gt 1 ]]; then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple issue files found for ${issue_id}"
  fi

  printf '%s\n' "${matches[0]}"
}

cmd_ls() {
  local root="$1"
  local wanted_state="${2:-}"

  if [[ -n "$wanted_state" ]]; then
    is_valid_state "$wanted_state" || die "invalid state: ${wanted_state}"
    find "$root/issues" -maxdepth 1 -type f -name "tk*.${wanted_state}.*.md" | sort
    return 0
  fi

  find "$root/issues" -maxdepth 1 -type f -name "tk*.md" | sort
}

cmd_show() {
  local root="$1"
  local task_id
  task_id="$(normalize_task_id "$2")"
  find_task_file "$root" "$task_id"
}

cmd_find() {
  local root="$1"
  local doc_id
  doc_id="$(normalize_doc_id "$2")"
  find_doc_file "$root" "$doc_id"
}

upsert_frontmatter_scalar() {
  local file="$1"
  local key="$2"
  local value="$3"
  local temp_file

  temp_file="$(mktemp)"
  if ! awk -v key="$key" -v value="$value" -v src="$file" '
    NR == 1 {
      if ($0 != "---") {
        print "error: missing frontmatter in " src > "/dev/stderr"
        exit 2
      }
      print
      next
    }
    !done {
      if ($0 == "---") {
        if (!written) {
          print key ": " value
        }
        print
        done = 1
        next
      }
      if ($0 ~ "^" key ":") {
        print key ": " value
        written = 1
        next
      }
      print
      next
    }
    { print }
    END {
      if (!done) {
        print "error: unterminated frontmatter in " src > "/dev/stderr"
        exit 2
      }
    }
  ' "$file" >"$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  mv "$temp_file" "$file"
}

resolve_claimed_by() {
  local file="$1"
  local explicit assignee owner

  explicit="${AGATA_CLAIMANT:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  assignee="$(extract_frontmatter_scalar "$file" "assignee")"
  if [[ -n "$assignee" ]]; then
    printf '%s\n' "$assignee"
    return 0
  fi

  owner="$(extract_frontmatter_scalar "$file" "owner")"
  if [[ -n "$owner" ]]; then
    printf '%s\n' "$owner"
    return 0
  fi

  printf '%s\n' "${USER:-unknown}"
}

resolve_claimed_thread_id() {
  local explicit thread_id

  explicit="${AGATA_CLAIM_THREAD_ID:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  thread_id="${CODEX_THREAD_ID:-${CLAUDE_THREAD_ID:-}}"
  if [[ -n "$thread_id" ]]; then
    printf '%s\n' "$thread_id"
    return 0
  fi

  return 1
}

cmd_move() {
  local root="$1"
  local issue_id new_state file old_state new_file claimed_by claimed_thread_id

  assert_control_plane_checkout "$root" "move"
  issue_id="$(normalize_issue_id "$2")"
  new_state="$3"
  is_valid_state "$new_state" || die "invalid state: ${new_state}"

  file="$(find_issue_file "$root" "$issue_id")"
  old_state="$(task_state_from_file "$file")"

  if [[ "$old_state" == "$new_state" ]]; then
    die "issue already in state ${new_state}"
  fi
  can_transition "$old_state" "$new_state" || die "illegal transition: ${old_state} -> ${new_state}"
  assert_memory_gate_for_close "$root" "$file" "$new_state"
  assert_progress_drained_for_close "$root" "$issue_id" "$new_state"

  new_file="$(rename_task_state "$file" "$new_state")"
  if [[ "$new_state" == "doi" ]]; then
    upsert_frontmatter_scalar "$new_file" "claimed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    claimed_by="$(resolve_claimed_by "$new_file")"
    upsert_frontmatter_scalar "$new_file" "claimed_by" "$claimed_by"
    if claimed_thread_id="$(resolve_claimed_thread_id)"; then
      upsert_frontmatter_scalar "$new_file" "claimed_thread_id" "$claimed_thread_id"
    fi
  fi
  echo "$new_file"
}

cmd_reopen() {
  local root="$1"
  local issue_id reason file old_state new_file claimed_by claimed_thread_id

  assert_control_plane_checkout "$root" "reopen"
  issue_id="$(normalize_issue_id "$2")"
  reason="$3"
  [[ -n "$reason" ]] || die "reopen reason is required"

  file="$(find_issue_file_anywhere "$root" "$issue_id")"
  old_state="$(task_state_from_file "$file")"
  [[ "$old_state" == "dne" ]] || die "reopen requires dne state: ${old_state}"

  new_file="$root/issues/$(task_basename_with_state "$file" "doi")"
  [[ ! -e "$new_file" ]] || die "reopen target already exists: ${new_file}"

  mv "$file" "$new_file"
  upsert_frontmatter_scalar "$new_file" "reopened_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  upsert_frontmatter_scalar "$new_file" "reopen_reason" "$reason"
  upsert_frontmatter_scalar "$new_file" "claimed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  claimed_by="$(resolve_claimed_by "$new_file")"
  upsert_frontmatter_scalar "$new_file" "claimed_by" "$claimed_by"
  if claimed_thread_id="$(resolve_claimed_thread_id)"; then
    upsert_frontmatter_scalar "$new_file" "claimed_thread_id" "$claimed_thread_id"
  fi
  echo "$new_file"
}

cmd_archive() {
  local root="$1"
  local task_id file state year archive_dir archived_file

  assert_control_plane_checkout "$root" "archive"
  task_id="$(normalize_task_id "$2")"
  file="$(find_task_file "$root" "$task_id")"
  state="$(task_state_from_file "$file")"
  year="$(date +%Y)"
  archive_dir="$root/issues/archive/${year}"
  mkdir -p "$archive_dir"

  if [[ "$state" != "arvd" ]]; then
    can_transition "$state" "arvd" || die "task in state ${state} cannot be archived"
    assert_memory_gate_for_close "$root" "$file" "arvd"
    assert_progress_drained_for_close "$root" "$task_id" "arvd"
    archived_file="${archive_dir}/$(task_basename_with_state "$file" "arvd")"
  else
    archived_file="${archive_dir}/$(basename "$file")"
  fi

  mv "$file" "$archived_file"
  echo "$archived_file"
}

cmd_archive_done() {
  local root="$1"
  local keep="$2"
  local year archive_dir records record count moved num kind base file archived_file

  assert_control_plane_checkout "$root" "archive-done"
  [[ "$keep" =~ ^[0-9]+$ ]] || die "keep must be a non-negative integer"

  year="$(date +%Y)"
  archive_dir="$root/issues/archive/${year}"
  mkdir -p "$archive_dir"

  records="$(
    while IFS= read -r file; do
      base="$(basename "$file")"
      if [[ "$base" =~ ^(tk|pl|rs|rf)([0-9]{4,5})\.dne\..*\.md$ ]]; then
        kind="${BASH_REMATCH[1]}"
        num=$((10#${BASH_REMATCH[2]}))
        printf '%s\t%s\t%s\t%s\n' "$num" "$kind" "$base" "$file"
      fi
    done < <(find "$root/issues" -maxdepth 1 -type f -name "*.dne.*.md" | sort)
  )"

  count=0
  moved=0
  while IFS=$'\t' read -r num kind base file; do
    [[ -n "$file" ]] || continue
    count=$((count + 1))
    if (( count <= keep )); then
      continue
    fi
    archived_file="${archive_dir}/${base}"
    [[ ! -e "$archived_file" ]] || die "archive target already exists: ${archived_file}"
    mv "$file" "$archived_file"
    echo "$archived_file"
    moved=1
  done < <(printf '%s\n' "$records" | sort -t $'\t' -k1,1nr -k2,2r -k3,3r)

  if [[ "$moved" -eq 0 ]]; then
    echo "ok"
  fi
}

assert_prune_target_clean() {
  local worktree_path="$1"
  local task_id="$2"
  local truth_status status

  truth_status="$(git -C "$worktree_path" status --porcelain --untracked-files=all -- "${TRUTH_SCAN_PATHS[@]}" || true)"
  if [[ -n "$truth_status" ]]; then
    echo "$truth_status" >&2
    die "linked worktree still has truth-source edits for ${task_id}: ${worktree_path}"
  fi

  status="$(git -C "$worktree_path" status --porcelain --untracked-files=all || true)"
  if [[ -n "$status" ]]; then
    echo "$status" >&2
    die "linked worktree still has uncommitted changes for ${task_id}: ${worktree_path}"
  fi
}

linked_worktree_has_execution_diff() {
  local worktree_path="$1"
  local base_ref="$2"
  local -a exec_pathspecs=(
    .
    ":(exclude)issues"
    ":(exclude)docs/reviews"
    ":(exclude)docs/progress"
    ":(exclude)refs/agent-names.md"
    ":(exclude)refs/radar.md"
    ":(exclude)refs/graph.md"
    ":(exclude)refs/project-memory-aaak.md"
  )

  ! git -C "$worktree_path" diff --quiet "$base_ref" -- "${exec_pathspecs[@]}"
}

print_linked_worktree_execution_diff() {
  local worktree_path="$1"
  local base_ref="$2"
  local -a exec_pathspecs=(
    .
    ":(exclude)issues"
    ":(exclude)docs/reviews"
    ":(exclude)docs/progress"
    ":(exclude)refs/agent-names.md"
    ":(exclude)refs/radar.md"
    ":(exclude)refs/graph.md"
    ":(exclude)refs/project-memory-aaak.md"
  )

  git -C "$worktree_path" diff --stat "$base_ref" -- "${exec_pathspecs[@]}" || true
}

assert_prune_not_self_destructing() {
  local worktree_path="$1"
  local current_pwd

  current_pwd="$(pwd -P)"
  if [[ "$current_pwd" == "$worktree_path" || "$current_pwd" == "$worktree_path"/* ]]; then
    die "prune cannot remove the linked worktree that contains the current shell cwd: ${worktree_path}; cd out and rerun"
  fi
}

check_duplicate_issue_ids() {
  local root="$1"
  local exact_file bare_file global_file path base kind digits num issue_id
  local duplicates cross_warnings

  exact_file="$(mktemp)"
  bare_file="$(mktemp)"
  global_file="$(mktemp)"
  while IFS= read -r path; do
    base="$(basename "$path")"
    if [[ "$base" =~ ^(tk|pl|rs|rf)([0-9]{4,5})\. ]]; then
      kind="${BASH_REMATCH[1]}"
      digits="${BASH_REMATCH[2]}"
      num=$((10#$digits))
      issue_id="${kind}${digits}"
      printf '%s\t%s\n' "$issue_id" "$path" >>"$exact_file"
      printf '%s:%s\t%s\n' "$kind" "$num" "$issue_id" >>"$bare_file"
      printf '%s\t%s\n' "$num" "$issue_id" >>"$global_file"
    fi
  done < <(find "$root/issues" -type f -name "*.md" | sort)

  duplicates="$(
    awk -F '\t' '
      { paths[$1] = paths[$1] ? paths[$1] ", " $2 : $2; count[$1]++ }
      END { for (key in count) if (count[key] > 1) print "exact:" key " -> " paths[key] }
    ' "$exact_file"
    awk -F '\t' '
      { seen[$1, $2] = 1 }
      END {
        for (pair in seen) {
          split(pair, parts, SUBSEP)
          key = parts[1]
          id = parts[2]
          ids[key] = ids[key] ? ids[key] ", " id : id
          count[key]++
        }
        for (key in count) if (count[key] > 1) print "bare:" key " -> " ids[key]
      }
    ' "$bare_file"
  )"

  cross_warnings="$(
    awk -F '\t' '
      { seen[$1, $2] = 1 }
      END {
        for (pair in seen) {
          split(pair, parts, SUBSEP)
          key = parts[1]
          id = parts[2]
          ids[key] = ids[key] ? ids[key] ", " id : id
          count[key]++
        }
        for (key in count) if (count[key] > 1) printf "warning: cross-kind numeric id collision: %04d -> %s\n", key, ids[key]
      }
    ' "$global_file"
  )"

  rm -f "$exact_file" "$bare_file" "$global_file"

  if [[ -n "$cross_warnings" ]]; then
    echo "$cross_warnings" >&2
  fi

  if [[ -n "$duplicates" ]]; then
    echo "$duplicates" >&2
    die "duplicate or colliding issue ids detected"
  fi
}

check_legacy_rvw_state() {
  local root="$1"
  local file

  while IFS= read -r file; do
    die "rvw state is retired; move the document to doi, dne, cand, bkd, or arvd: $file"
  done < <(
    {
      find "$root/issues" -type f -name '*.rvw.*.md' 2>/dev/null
      find "$root/docs/reviews" -type f -name '*.rvw.*.md' 2>/dev/null
    } | sort
  )
}

check_rp_names() {
  local root="$1"
  local file base

  [[ -d "$root/docs/reviews" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    if [[ "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+\.md$ ]]; then
      continue
    fi
    if [[ "$base" =~ \.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+\.md$ ]]; then
      die "unscoped review/audit belongs in aidocs/agent-runs, not docs/reviews: $file"
    fi
    [[ "$base" =~ ^rp${ID_DIGITS_RE}\.(tdo|doi|dne|bkd|cand|arvd)\.[a-z0-9-]+\.(review-r[0-9]+-[a-z0-9-]+|reply-r[0-9]+-[a-z0-9-]+)\.md$ ]] \
      || die "invalid review filename: $file"
  done < <(find "$root/docs/reviews" -maxdepth 1 -type f -name '*.md' | sort)
}

check_rv_names() {
  local root="$1"
  local file base issue_id result

  [[ -d "$root/docs/reviews" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    [[ "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+\.md$ ]] \
      || continue
    issue_id="${base%%.*}"
    find_issue_file_anywhere "$root" "$issue_id" >/dev/null
    result="$(extract_frontmatter_scalar "$file" "result")"
    if [[ -n "$result" && ! "$result" =~ ^(block|pass|note)$ ]]; then
      die "invalid review result in $file: $result"
    fi
  done < <(find "$root/docs/reviews" -maxdepth 1 -type f -name '*.md' | sort)
}

check_progress_names() {
  local root="$1"
  local file base task_id step_slug progress_state parent_file parent_state doi_tmp step_tmp duplicates duplicate_steps

  [[ -d "$root/docs/progress" ]] || return 0
  doi_tmp="$(mktemp)"
  step_tmp="$(mktemp)"

  while IFS= read -r file; do
    base="$(basename "$file")"
    [[ "$base" =~ ^(tk${ID_DIGITS_RE})\.(s[0-9]{2}-[a-z0-9-]+)\.(tdo|doi|dne|bkd)\.md$ ]] \
      || die "invalid progress filename: $file"

    task_id="${BASH_REMATCH[1]}"
    step_slug="${BASH_REMATCH[2]}"
    progress_state="${BASH_REMATCH[3]}"
    printf '%s.%s\n' "$task_id" "$step_slug" >>"$step_tmp"

    parent_file="$(find_task_file_anywhere "$root" "$task_id")"
    parent_state="$(task_state_from_file "$parent_file")"

    if [[ "$progress_state" == "doi" ]]; then
      printf '%s\n' "$task_id" >>"$doi_tmp"
    fi

    if [[ "$parent_state" =~ ^(dne|cand|arvd)$ && "$progress_state" != "dne" ]]; then
      rm -f "$doi_tmp" "$step_tmp"
      die "closed task has open progress: ${task_id}.${step_slug}.${progress_state}"
    fi
  done < <(find "$root/docs/progress" -maxdepth 1 -type f -name '*.md' | sort)

  duplicates="$(sort "$doi_tmp" | uniq -d || true)"
  duplicate_steps="$(sort "$step_tmp" | uniq -d || true)"
  rm -f "$doi_tmp" "$step_tmp"
  if [[ -n "$duplicates" ]]; then
    printf '%s\n' "$duplicates" >&2
    die "multiple doi progress steps for the same task"
  fi
  if [[ -n "$duplicate_steps" ]]; then
    printf '%s\n' "$duplicate_steps" >&2
    die "duplicate progress step ids detected"
  fi
}

extract_frontmatter_links() {
  local file="$1"

  awk '
    NR == 1 && $0 == "---" { in_yaml = 1; next }
    in_yaml && $0 == "---" { exit }
    !in_yaml { next }

    in_links {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        sub(/^[[:space:]]*-[[:space:]]+/, "", $0)
        print $0
        next
      }
      if ($0 ~ /^[^[:space:]]/) {
        in_links = 0
      }
      if (!in_links) {
        next
      }
    }

    /^links:[[:space:]]*\[/ {
      line = $0
      sub(/^links:[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*$/, "", line)
      count = split(line, items, /,[[:space:]]*/)
      for (i = 1; i <= count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
        gsub(/^'\''|'\''$/, "", items[i])
        gsub(/^"|"$/, "", items[i])
        if (items[i] != "") {
          print items[i]
        }
      }
      next
    }

    /^links:[[:space:]]*$/ {
      in_links = 1
      next
    }
  ' "$file"
}

extract_frontmatter_depends_on() {
  local file="$1"

  awk '
    NR == 1 && $0 == "---" { in_yaml = 1; next }
    in_yaml && $0 == "---" { exit }
    !in_yaml { next }

    in_deps {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        sub(/^[[:space:]]*-[[:space:]]+/, "", $0)
        print $0
        next
      }
      if ($0 ~ /^[^[:space:]]/) {
        in_deps = 0
      }
      if (!in_deps) {
        next
      }
    }

    /^depends_on:[[:space:]]*\[/ {
      line = $0
      sub(/^depends_on:[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*$/, "", line)
      count = split(line, items, /,[[:space:]]*/)
      for (i = 1; i <= count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
        gsub(/^'\''|'\''$/, "", items[i])
        gsub(/^"|"$/, "", items[i])
        if (items[i] != "") {
          print items[i]
        }
      }
      next
    }

    /^depends_on:[[:space:]]*$/ {
      in_deps = 1
      next
    }
  ' "$file"
}

normalize_link_target() {
  local root="$1"
  local target="$2"

  target="$(strip_wrapping_quotes "$target")"

  if [[ "$target" = /* ]]; then
    echo "$target"
    return 0
  fi

  if [[ "$target" =~ ^rp${ID_DIGITS_RE}\..*\.md$ ]]; then
    echo "$root/docs/reviews/$target"
    return 0
  fi

  if [[ "$target" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+\.md$ ]]; then
    echo "$root/docs/reviews/$target"
    return 0
  fi

  if [[ "$target" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd)\.md$ ]]; then
    echo "$root/docs/progress/$target"
    return 0
  fi

  echo "$root/$target"
}

is_stateful_workflow_reference() {
  local target="$1"
  local base

  target="$(strip_wrapping_quotes "$target")"
  base="$(basename "$target")"

  case "$target" in
    docs/plan/*|*/docs/plan/*)
      return 1
      ;;
  esac

  [[ "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.(tdo|doi|dne|bkd|cand|arvd|rvw)\..*\.md$ ]] && return 0
  [[ "$base" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd)\.md$ ]] && return 0
  [[ "$base" =~ ^rp${ID_DIGITS_RE}\.(tdo|doi|dne|bkd|cand|arvd|rvw)\..*\.md$ ]] && return 0
  return 1
}

find_review_anchor_matches() {
  local root="$1"
  local review_id="$2"

  {
    find "$root/docs/reviews" -maxdepth 1 -type f -name "${review_id}.*.md" 2>/dev/null
    find "$root/issues" -maxdepth 1 -type f -name "${review_id}.*.md" 2>/dev/null
  } | sort
}

check_issue_review_links_exist() {
  local root="$1"
  local file raw_link raw_target normalized base

  while IFS= read -r file; do
    while IFS= read -r raw_link; do
      raw_target="$(strip_wrapping_quotes "$raw_link")"

      if is_stateful_workflow_reference "$raw_target"; then
        if [[ "${AGATA_STRICT_STABLE_LINKS:-0}" == "1" ]]; then
          die "stateful workflow links are forbidden; use a stable id anchor: $file -> $raw_link"
        fi
        warn "stateful workflow link should use a stable id anchor: $file -> $raw_link"
        continue
      fi

      if [[ "$raw_target" =~ ^rp${ID_DIGITS_RE}$ ]]; then
        if ! find_review_anchor_matches "$root" "$raw_target" | grep -q .; then
          die "missing review link target: $file -> $raw_link"
        fi
        continue
      fi

      if [[ "$raw_target" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+$ ]]; then
        normalized="$root/docs/reviews/${raw_target}.md"
        [[ -f "$normalized" ]] || die "missing rv link target: $file -> $raw_link"
        continue
      fi

      if [[ "$raw_target" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+$ ]]; then
        if ! find "$root/docs/progress" -maxdepth 1 -type f -name "${raw_target}.*.md" 2>/dev/null | grep -q .; then
          die "missing progress link target: $file -> $raw_link"
        fi
        continue
      fi

      normalized="$(normalize_link_target "$root" "$raw_link")"
      base="$(basename "$normalized")"

      if [[ ! "$base" =~ ^rp${ID_DIGITS_RE}\..*\.md$ && ! "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+\.md$ && ! "$base" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd)\.md$ ]]; then
        continue
      fi

      [[ -f "$normalized" ]] || die "missing review link target: $file -> $raw_link"
    done < <(extract_frontmatter_links "$file")
  done < <(find "$root/issues" -maxdepth 1 -type f -name '*.md' | sort)
}

check_issue_dependencies_exist() {
  local root="$1"
  local file issue_id raw_dep dep_id

  while IFS= read -r file; do
    issue_id="$(basename "$file")"
    issue_id="${issue_id%%.*}"
    while IFS= read -r raw_dep; do
      dep_id="$(strip_wrapping_quotes "$raw_dep")"
      [[ -n "$dep_id" ]] || continue
      [[ "$dep_id" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}$ ]] \
        || die "depends_on must use issue ids only: $file -> $raw_dep"
      [[ "$dep_id" != "$issue_id" ]] \
        || die "issue depends_on itself: $file -> $raw_dep"
      find_issue_file_anywhere "$root" "$dep_id" >/dev/null
    done < <(extract_frontmatter_depends_on "$file")
  done < <(find "$root/issues" -maxdepth 1 -type f -name '*.md' | sort)
}

check_arvd_residue() {
  local root="$1"
  local residue

  residue="$(find "$root/issues" -maxdepth 1 -type f \( -name 'tk*.arvd.*.md' -o -name 'pl*.arvd.*.md' -o -name 'rs*.arvd.*.md' -o -name 'rf*.arvd.*.md' \) | sort)"
  if [[ -n "$residue" ]]; then
    echo "$residue" >&2
    die "archived issue residue detected in issues/"
  fi
}

check_legacy_reply_chains() {
  local root="$1"
  local legacy

  legacy="$(find "$root/docs" -type f \( -name 're.*.md' -o -name 're.re.*.md' \) 2>/dev/null | sort || true)"
  if [[ -n "$legacy" ]]; then
    echo "$legacy" >&2
    die "legacy reply-chain filenames detected"
  fi
}

check_project_memory_links() {
  local root="$1"
  local file task_id

  while IFS= read -r file; do
    if ! task_needs_memory_gate "$file"; then
      continue
    fi

    task_id="$(task_id_from_file "$file")"
    memory_entry_exists "$root" "$task_id" || die "missing project memory anchor for ${task_id}: $(project_memory_file "$root")"
  done < <(find "$root/issues" -maxdepth 1 -type f -name 'tk*.md' | sort)
}

banned_terms_file() {
  local root="$1"
  local file="$root/refs/task-check-banned-terms.tsv"
  [[ -f "$file" ]] || return 1
  printf '%s\n' "$file"
}

collect_banned_term_targets() {
  local root="$1"
  local file base

  if [[ -d "$root/issues" ]]; then
    while IFS= read -r file; do
      base="$(basename "$file")"
      if [[ "$base" =~ \.(tdo|doi|bkd|cand)\. ]]; then
        printf '%s\n' "$file"
      fi
    done < <(find "$root/issues" -maxdepth 1 -type f -name '*.md' | sort)
  fi
}

check_banned_arch_terms() {
  local root="$1"
  local cfg line pattern allow_regex reason matches filtered found
  local targets=()

  cfg="$(banned_terms_file "$root" || true)"
  [[ -n "$cfg" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    targets+=("$line")
  done < <(collect_banned_term_targets "$root")

  [[ "${#targets[@]}" -gt 0 ]] || return 0

  found=0
  while IFS=$'\t' read -r pattern allow_regex reason; do
    [[ -n "${pattern:-}" ]] || continue
    [[ "$pattern" =~ ^# ]] && continue

    matches="$(rg -n --no-heading -e "$pattern" "${targets[@]}" || true)"
    [[ -n "$matches" ]] || continue

    filtered="$matches"
    if [[ -n "${allow_regex:-}" ]]; then
      filtered="$(printf '%s\n' "$matches" | rg -v -e "$allow_regex" || true)"
    fi

    [[ -n "$filtered" ]] || continue

    found=1
    printf '%s\n' "$filtered" >&2
    if [[ -n "${reason:-}" ]]; then
      printf 'error: banned architecture term "%s": %s\n' "$pattern" "$reason" >&2
    else
      printf 'error: banned architecture term "%s"\n' "$pattern" >&2
    fi
  done < "$cfg"

  if [[ "$found" -ne 0 ]]; then
    die "banned architecture terms detected; fix terms or tighten allow regex in ${cfg}"
  fi
}

timestamp_to_epoch() {
  local raw="$1"
  local bsd_raw="$raw"

  if [[ "$bsd_raw" =~ ^(.+)([+-][0-9]{2}):([0-9]{2})$ ]]; then
    bsd_raw="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  elif [[ "$bsd_raw" =~ Z$ ]]; then
    bsd_raw="${bsd_raw%Z}+0000"
  fi

  if date -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd_raw" "+%s" >/dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd_raw" "+%s"
    return 0
  fi

  if date -d "$raw" "+%s" >/dev/null 2>&1; then
    date -d "$raw" "+%s"
    return 0
  fi

  return 1
}

check_doi_staleness() {
  local root="$1"
  local now file task_id claimed_at claimed_epoch age claimed_by claimed_thread_id

  now="$(date +%s)"

  while IFS= read -r file; do
    task_id="$(task_id_from_file "$file")"
    claimed_at="$(extract_frontmatter_scalar "$file" "claimed_at")"
    claimed_by="$(extract_frontmatter_scalar "$file" "claimed_by")"
    claimed_thread_id="$(extract_frontmatter_scalar "$file" "claimed_thread_id")"

    if [[ -z "$claimed_at" ]]; then
      warn "doi task missing claimed_at: ${task_id} (${file})"
    elif ! claimed_epoch="$(timestamp_to_epoch "$claimed_at")"; then
      warn "invalid claimed_at on ${task_id}: ${claimed_at}"
    else
      age=$((now - claimed_epoch))
      if (( age > STALE_DOI_SECONDS )); then
        warn "stale doi task: ${task_id} claimed_at ${claimed_at}"
      fi
    fi

    if [[ -z "$claimed_by" ]]; then
      warn "doi task missing claimed_by: ${task_id} (${file})"
      continue
    fi

    if is_generic_claimant_label "$claimed_by" && [[ -z "$claimed_thread_id" ]]; then
      warn "doi task generic claimant needs claimed_thread_id: ${task_id} -> ${claimed_by}"
    fi
  done < <(find "$root/issues" -maxdepth 1 -type f -name 'tk*.doi.*.md' | sort)
}

cmd_prune() {
  local root="$1"
  local task_id="$2"
  local base_ref="$3"
  local file state orphan_output match worktree_path branch_name

  assert_git_repo "$root" "prune"
  assert_control_plane_checkout "$root" "prune"
  assert_base_ref "$root" "$base_ref"
  task_id="$(normalize_task_id "$task_id")"
  file="$(find_task_file_anywhere "$root" "$task_id")"
  state="$(task_state_from_file "$file")"

  case "$state" in
    doi)
      die "task in state doi cannot be pruned; release the claim first"
      ;;
    bkd)
      die "task in state bkd cannot be pruned; keep the frozen worktree or move it to doi / cand explicitly"
      ;;
    dne|cand|arvd)
      ;;
    *)
      die "task in state ${state} cannot be pruned; close it into dne / cand / arvd first"
      ;;
  esac

  cmd_check "$root" "$root" >/dev/null

  if ! orphan_output="$(cmd_orphan_scan "$root" "$base_ref" "$task_id")"; then
    printf '%s\n' "$orphan_output" >&2
    die "prune found workflow truth drift for ${task_id}"
  fi

  match="$(resolve_task_worktree "$root" "$task_id")"
  IFS=$'\t' read -r worktree_path branch_name <<<"$match"

  if [[ "$branch_name" == "__DETACHED__" || -z "$branch_name" ]]; then
    die "linked worktree for ${task_id} is detached; prune requires a named local branch"
  fi

  assert_prune_not_self_destructing "$worktree_path"
  assert_prune_target_clean "$worktree_path" "$task_id"

  if linked_worktree_has_execution_diff "$worktree_path" "$base_ref"; then
    print_linked_worktree_execution_diff "$worktree_path" "$base_ref" >&2
    die "linked worktree still carries execution diff vs ${base_ref} for ${task_id}"
  fi

  git -C "$root" worktree remove "$worktree_path"
  git -C "$root" branch -D "$branch_name" >/dev/null
  printf 'worktree: %s\nbranch: %s\n' "$worktree_path" "$branch_name"
}

cmd_check() {
  local current_root="$1"
  local semantic_root="${2:-$1}"

  assert_no_truth_edits_in_linked_worktree "$current_root" "check"
  check_duplicate_issue_ids "$semantic_root"
  check_arvd_residue "$semantic_root"
  check_legacy_rvw_state "$semantic_root"
  check_rp_names "$semantic_root"
  check_rv_names "$semantic_root"
  check_progress_names "$semantic_root"
  check_issue_review_links_exist "$semantic_root"
  check_issue_dependencies_exist "$semantic_root"
  check_legacy_reply_chains "$semantic_root"
  check_project_memory_links "$semantic_root"
  check_banned_arch_terms "$semantic_root"
  check_doi_staleness "$semantic_root"
  echo "ok"
}

main() {
  local current_root control_root cmd issue_id

  cmd="${1:-}"

  case "$cmd" in
    ""|-h|--help|help)
      print_usage
      ;;
    new)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 4 && $# -le 5 ]] || die "usage: task.sh new <kind> <board> <slug> [prio]"
      cmd_new "$control_root" "$2" "$3" "$4" "${5:-}"
      ;;
    review)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 4 && $# -le 5 ]] || die "usage: task.sh review <issue-id> <rvNNN> <rNNN-author> [block|pass|note]"
      cmd_review "$control_root" "$2" "$3" "$4" "${5:-note}"
      ;;
    progress)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 3 && $# -le 4 ]] || die "usage: task.sh progress <task-id> <sNN-slug> [state]"
      cmd_progress "$control_root" "$2" "$3" "${4:-tdo}"
      ;;
    ls)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      shift
      cmd_ls "$control_root" "${1:-}"
      ;;
    find)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 2 ]] || die "usage: task.sh find <id>"
      cmd_find "$control_root" "$2"
      ;;
    show)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 2 ]] || die "usage: task.sh show <task-id>"
      cmd_show "$control_root" "$2"
      ;;
    move)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 3 ]] || die "usage: task.sh move <issue-id> <state>"
      cmd_move "$control_root" "$2" "$3"
      ;;
    reopen)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 3 ]] || die "usage: task.sh reopen <issue-id> <reason>"
      issue_id="$2"
      shift 2
      cmd_reopen "$control_root" "$issue_id" "$*"
      ;;
    archive)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 2 ]] || die "usage: task.sh archive <task-id>"
      cmd_archive "$control_root" "$2"
      ;;
    archive-done)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      case "$#" in
        1)
          cmd_archive_done "$control_root" "32"
          ;;
        3)
          [[ "$2" == "--keep" ]] || die "usage: task.sh archive-done [--keep N]"
          cmd_archive_done "$control_root" "$3"
          ;;
        *)
          die "usage: task.sh archive-done [--keep N]"
          ;;
      esac
      ;;
    prune)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 3 ]] || die "usage: task.sh prune <task-id> <base-ref>"
      cmd_prune "$control_root" "$2" "$3"
      ;;
    check)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -eq 1 ]] || die "usage: task.sh check"
      cmd_check "$current_root" "$control_root"
      ;;
    orphan-scan)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      [[ $# -ge 2 && $# -le 3 ]] || die "usage: task.sh orphan-scan <base-ref> [filter]"
      cmd_orphan_scan "$current_root" "$2" "${3:-}"
      ;;
    *)
      die "unknown command: ${cmd}"
      ;;
  esac
}

main "$@"
