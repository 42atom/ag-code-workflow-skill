#!/bin/bash

set -euo pipefail

######## task workflow helper

VALID_STATES="tdo doi dne bkd cand arvd"
VALID_PROGRESS_STATES="tdo doi dne bkd cand arvd"
RESERVED_STATE_WORDS="tdo doi rvw dne bkd cand arvd"
VALID_REVIEW_RESULTS="block pass note"
VALID_MEMORY_MODES="none required done"
STALE_DOI_SECONDS=259200
ID_DIGITS_RE='[0-9]{4,5}'
TRUTH_SCAN_PATHS=("issues" "docs/reviews" "docs/progress" "refs/agent-names.md" "refs/radar.md" "refs/graph.md" "refs/project-memory-aaak.md")
VALID_KINDS="tk pl rs rf"
NEW_ID_LOCK_DIR=""
declare -a CHECK_ISSUE_FILES=()
declare -a CHECK_REVIEW_FILES=()
declare -a CHECK_PROGRESS_FILES=()
declare -A CHECK_PROGRESS_SLUGS=()
declare -A CHECK_REVIEW_ANCHOR_PREFIXES=()
declare -A CHECK_CHANGED_ISSUE_FILES=()

die() {
  if [[ -t 2 ]]; then
    printf '\033[31merror: %s\033[0m\n' "$*" >&2
  else
    echo "error: $*" >&2
  fi
  exit 1
}

declare -A CHECK_WARNING_COUNTS=()
CHECK_WARNING_TOTAL=0
CHECK_SCOPE_FULL=1
CHECK_SCOPE_MODE=full

warn() {
  local key="warning: $*"
  local count=${CHECK_WARNING_COUNTS["$key"]-0}
  CHECK_WARNING_COUNTS["$key"]=$((count + 1))
  CHECK_WARNING_TOTAL=$((CHECK_WARNING_TOTAL + 1))

  if [[ "${AGATA_SHOW_WARNINGS:-0}" == "1" ]]; then
    if [[ -t 2 ]]; then
      printf '\033[33m%s\033[0m\n' "$key" >&2
    else
      echo "$key" >&2
    fi
  fi
}

emit_warning_summary() {
  local key

  [[ "${AGATA_COLLAPSE_WARNINGS:-1}" == "1" ]] || return 0
  [[ "$CHECK_WARNING_TOTAL" -eq 0 ]] && return 0

  if [[ -t 2 ]]; then
    printf '\n\033[33mwarning summary (%s total):\033[0m\n' "$CHECK_WARNING_TOTAL" >&2
  else
    printf '\nwarning summary (%s total):\n' "$CHECK_WARNING_TOTAL" >&2
  fi

  for key in $(printf '%s\n' "${!CHECK_WARNING_COUNTS[@]}" | sort); do
    printf '  %s (x%s)\n' "$key" "${CHECK_WARNING_COUNTS[$key]-0}" >&2
  done
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
  local file parent_file parent_state progress_state bad_file base step_slug

  [[ "$issue_id" =~ ^tk${ID_DIGITS_RE}$ ]] || return 0
  [[ "$new_state" == "dne" || "$new_state" == "cand" || "$new_state" == "arvd" ]] || return 0
  [[ -d "$root/docs/progress" ]] || return 0

  parent_file="$(find_task_file_anywhere "$root" "$issue_id")"
  parent_state="$(task_state_from_file "$parent_file")"

  while IFS= read -r file; do
    base="$(basename "$file")"
    [[ "$base" =~ ^(tk${ID_DIGITS_RE})\.(s[0-9]{2}-[a-z0-9-]+)\.(tdo|doi|dne|bkd|cand|arvd)\.md$ ]] || continue
    progress_state="${BASH_REMATCH[3]}"
    step_slug="${BASH_REMATCH[2]}"

    bad_file="$root/docs/progress/${issue_id}.${step_slug}.${progress_state}.md"
    if [[ "$parent_state" == "tdo" ]]; then
      die "${bad_file} exists while ${issue_id} is still tdo; move ${issue_id} to doi first"
    fi
    if [[ "$parent_state" == "doi" && "$progress_state" != "doi" && "$progress_state" != "dne" ]]; then
      die "${bad_file} is ${progress_state} but parent is ${issue_id}.${parent_state}; expected doi or dne, move to dne first"
    fi
    if [[ "$parent_state" =~ ^(dne|cand|arvd|bkd)$ && "$progress_state" != "dne" ]]; then
      die "${bad_file} is ${progress_state} but parent is ${issue_id}.${parent_state}; move it to dne before close"
    fi
  done < <(find "$root/docs/progress" -maxdepth 1 -type f -name "${issue_id}.*.md" | sort)

  if [[ "$parent_state" == "dne" || "$parent_state" == "cand" || "$parent_state" == "arvd" || "$parent_state" == "bkd" ]]; then
    return 0
  fi

  if [[ "$parent_state" == "doi" ]]; then
    return 0
  fi
}

assert_blocking_review_gate() {
  local root="$1"
  local issue_id="$2"
  local target_state="$3"
  local review_file

  [[ "$target_state" == "dne" ]] || return 0

  while IFS= read -r review_file; do
    is_review_result_blocking "$review_file" || continue
    die "${review_file} blocks ${issue_id} from dne; resolve this review result or remove review file first"
  done < <(find "$root/docs/reviews" -maxdepth 1 -type f -name "${issue_id}.rv*.md" | sort)
}

reopen_from_progress() {
  local root="$1"
  local issue_id="$2"
  local step_hint="$3"
  local pattern file match_count target
  local -a matches=()

  if [[ "$step_hint" =~ ^s[0-9]{2}-[a-z0-9-]+$ ]]; then
    pattern="${issue_id}.${step_hint}.dne.md"
  elif [[ "$step_hint" =~ ^s[0-9]{2}$ ]]; then
    pattern="${issue_id}.${step_hint}-*.dne.md"
  else
    die "invalid progress step for reopen: ${step_hint}; use sNN or sNN-slug"
  fi

  while IFS= read -r file; do
    matches+=("$file")
  done < <(find "$root/docs/progress" -maxdepth 1 -type f -name "$pattern" | sort)

  match_count="${#matches[@]}"
  [[ "$match_count" -gt 0 ]] || die "progress file not found for ${issue_id} ${step_hint} in dne state"
  [[ "$match_count" -eq 1 ]] || die "multiple progress matches for ${issue_id} ${step_hint}; disambiguate with full step slug"

  file="${matches[0]}"
  target="${file%.dne.md}.doi.md"
  [[ ! -e "$target" ]] || die "cannot reopen progress state: target exists ${target}"
  mv "$file" "$target"
}

print_usage() {
  cat <<'EOF'
usage:
  task.sh new <kind> <board> <slug> [--from pl-id] [prio]
  task.sh review <issue-id> <rvNNN> <rNNN-author> [block|pass|note]
  task.sh progress <task-id> <sNN-slug> [state]
  task.sh ls [state]
  task.sh find <id>
  task.sh show <task-id>
  task.sh move <issue-id> <state>
  task.sh reopen <issue-id> [reason] [--from progress <step>]
  task.sh batch-close <issue-id> [state]
  task.sh archive <task-id>
  task.sh archive-done [--keep N] [--yes]
  task.sh prune <task-id> <base-ref>
  task.sh check [--changed <file> ...]
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

build_check_file_cache() {
  local current_root="$1"
  local semantic_root="$2"
  shift 2
  local file base stem
  local issue_id
  local raw abs
  local -A seen_path=()
  local -A seen_issue_progress=()
  local -a files=("$@")

  CHECK_ISSUE_FILES=()
  CHECK_REVIEW_FILES=()
  CHECK_PROGRESS_FILES=()
  CHECK_PROGRESS_SLUGS=()
  CHECK_REVIEW_ANCHOR_PREFIXES=()
  CHECK_CHANGED_ISSUE_FILES=()
  CHECK_SCOPE_FULL=1
  CHECK_SCOPE_MODE="full"

  if [[ "${#files[@]}" -gt 0 ]]; then
    CHECK_SCOPE_FULL=0
    CHECK_SCOPE_MODE="incremental"

    for raw in "${files[@]}"; do
      if [[ "$raw" == /* ]]; then
        abs="$raw"
      else
        abs="$current_root/$raw"
        if [[ ! -f "$abs" ]]; then
          abs="$semantic_root/$raw"
        fi
      fi

      [[ -f "$abs" ]] || continue
      abs="$(cd "$(dirname "$abs")" && pwd -P)/$(basename "$abs")"
      [[ "$abs" == "$current_root/"* || "$abs" == "$semantic_root/"* ]] || continue
      [[ -n "${seen_path["$abs"]+x}" ]] && continue
      seen_path["$abs"]=1

      if [[ "$abs" == "$current_root/issues/"* || "$abs" == "$semantic_root/issues/"* ]]; then
        CHECK_ISSUE_FILES+=("$abs")
        CHECK_CHANGED_ISSUE_FILES["$abs"]=1
      elif [[ "$abs" == "$current_root/docs/reviews/"* || "$abs" == "$semantic_root/docs/reviews/"* ]]; then
        CHECK_REVIEW_FILES+=("$abs")
      elif [[ "$abs" == "$current_root/docs/progress/"* || "$abs" == "$semantic_root/docs/progress/"* ]]; then
        CHECK_PROGRESS_FILES+=("$abs")
      fi
    done

    if (( ${#CHECK_ISSUE_FILES[@]} + ${#CHECK_REVIEW_FILES[@]} + ${#CHECK_PROGRESS_FILES[@]} == 0 )); then
      warn "no valid changed docs matched check scope; fallback to full scan"
      return 0
    fi

    for file in "${CHECK_PROGRESS_FILES[@]}"; do
      base="$(basename "$file")"
      stem="${base%.md}"
      [[ "$stem" =~ \. ]] && CHECK_PROGRESS_SLUGS["${stem%.*}"]=1
    done

    for file in "${CHECK_ISSUE_FILES[@]}"; do
      issue_id="$(task_id_from_file "$file")"

      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        [[ -n "${seen_issue_progress["$file"]+x}" ]] && continue
        seen_issue_progress["$file"]=1
        CHECK_PROGRESS_FILES+=("$file")

        base="$(basename "$file")"
        stem="${base%.md}"
        [[ "$stem" =~ \.(s[0-9]{2}-[a-z0-9-]+)\. ]] || continue
        CHECK_PROGRESS_SLUGS["${issue_id}.${BASH_REMATCH[1]}"]=1
      done < <(find "$semantic_root/docs/progress" -maxdepth 1 -type f -name "${issue_id}.*.md" 2>/dev/null | sort)
    done

    for file in "${CHECK_ISSUE_FILES[@]}" "${CHECK_REVIEW_FILES[@]}"; do
      base="$(basename "$file")"
      CHECK_REVIEW_ANCHOR_PREFIXES["${base%%.*}"]=1
    done

    return 0
  fi

  if [[ -d "$semantic_root/issues" ]]; then
    mapfile -t CHECK_ISSUE_FILES < <(find "$semantic_root/issues" -maxdepth 1 -type f -name '*.md' | sort)
  fi

  if [[ -d "$semantic_root/docs/reviews" ]]; then
    mapfile -t CHECK_REVIEW_FILES < <(find "$semantic_root/docs/reviews" -maxdepth 1 -type f -name '*.md' | sort)
  fi

  if [[ -d "$semantic_root/docs/progress" ]]; then
    mapfile -t CHECK_PROGRESS_FILES < <(find "$semantic_root/docs/progress" -maxdepth 1 -type f -name '*.md' | sort)
  fi

  for file in "${CHECK_PROGRESS_FILES[@]}"; do
    base="$(basename "$file")"
    stem="${base%.md}"
    [[ "$stem" =~ \. ]] && CHECK_PROGRESS_SLUGS["${stem%.*}"]=1
  done

  for file in "${CHECK_ISSUE_FILES[@]}" "${CHECK_REVIEW_FILES[@]}"; do
    base="$(basename "$file")"
    CHECK_REVIEW_ANCHOR_PREFIXES["${base%%.*}"]=1
  done
}

check_issue_file_list() {
  local root="$1"

  if [[ "${#CHECK_ISSUE_FILES[@]}" -gt 0 ]]; then
    printf '%s\n' "${CHECK_ISSUE_FILES[@]}"
    return 0
  fi

  [[ -d "$root/issues" ]] || return 0
  find "$root/issues" -maxdepth 1 -type f -name '*.md' | sort
}

check_review_file_list() {
  local root="$1"

  if [[ "${#CHECK_REVIEW_FILES[@]}" -gt 0 ]]; then
    printf '%s\n' "${CHECK_REVIEW_FILES[@]}"
    return 0
  fi

  [[ -d "$root/docs/reviews" ]] || return 0
  find "$root/docs/reviews" -maxdepth 1 -type f -name '*.md' | sort
}

check_progress_file_list() {
  local root="$1"

  if [[ "${#CHECK_PROGRESS_FILES[@]}" -gt 0 ]]; then
    printf '%s\n' "${CHECK_PROGRESS_FILES[@]}"
    return 0
  fi

  [[ -d "$root/docs/progress" ]] || return 0
  find "$root/docs/progress" -maxdepth 1 -type f -name '*.md' | sort
}

parse_issue_filename() {
  local file="$1"
  local base kind digits id state board slug rest

  base="$(basename "$file")"
  if [[ "$base" =~ ^(tk|pl|rs|rf)([0-9]{4,5})\.(tdo|doi|dne|bkd|cand|arvd)\.([a-z0-9-]+)\.([a-z0-9-]+)(\.[a-z0-9-]+)?\.md$ ]]; then
    kind="${BASH_REMATCH[1]}"
    digits="${BASH_REMATCH[2]}"
    state="${BASH_REMATCH[3]}"
    board="${BASH_REMATCH[4]}"
    slug="${BASH_REMATCH[5]}"
    rest="${BASH_REMATCH[6]#.}"
    id="${kind}${digits}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$state" "$board" "$slug" "$rest"
    return 0
  fi
  return 1
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
  local result="${5:-}"

  if [[ -n "$result" ]]; then
    printf '%s\n' "$root/docs/reviews/${issue_id}.${thread}-${round_author}.${result}.md"
  else
    printf '%s\n' "$root/docs/reviews/${issue_id}.${thread}-${round_author}.md"
  fi
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
  local recap_or_result="${3:-}"
  local scope_hint="${4:-}"
  local accept_hint="${5:-}"
  local links_block="${6:-'  []'}"
  local recap scope accept

  recap="${recap_or_result:-核:TODO|界:TODO|验:TODO|下:TODO}"
  scope="${scope_hint:-TODO}"
  accept="${accept_hint:-TODO}"

  mkdir -p "$(dirname "$file")"

  case "$kind" in
    rv)
      if [[ -z "$recap_or_result" ]]; then
        recap_or_result="note"
      fi
      [[ "$recap_or_result" =~ ^(block|pass|note)$ ]] || die "invalid review result: ${recap_or_result}"
      cat >"$file" <<EOF
---
owner: user
assignee: agent
result: ${recap_or_result}
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
      recap="$(sanitize_yaml_scalar "$recap")"
      scope="$(sanitize_yaml_scalar "$scope")"
      accept="$(sanitize_yaml_scalar "$accept")"
      cat >"$file" <<EOF
---
owner: user
assignee: agent
recap: "${recap}"
why: TODO
scope: "${scope}"
risk: low
accept: "${accept}"
memory: none
depends_on: []
links:
${links_block}
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

sanitize_yaml_scalar() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="$(printf '%s' "$value" | tr '\n' ' ')"
  printf '%s\n' "$value"
}

sanitize_recap_value() {
  local value="$1"
  value="$(sanitize_yaml_scalar "$value")"
  value="${value//|/}"
  printf '%s\n' "$value"
}

parse_review_outcome_from_filename() {
  local file="$1"
  local base
  base="$(basename "$file")"

  if [[ "$base" == *.block.md ]]; then
    echo "block"
    return 0
  fi
  if [[ "$base" == *.pass.md ]]; then
    echo "pass"
    return 0
  fi
  if [[ "$base" == *.note.md ]]; then
    echo "note"
    return 0
  fi

  echo ""
}

is_review_result_blocking() {
  local file="$1"
  local outcome

  outcome="$(parse_review_outcome_from_filename "$file")"
  [[ "$outcome" == "block" ]] && return 0
  [[ "$(extract_frontmatter_scalar "$file" "result")" == "block" ]] && return 0
  return 1
}

format_frontmatter_links_block() {
  local file="$1"
  local line count=0
  local link output

  output=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    count=$((count + 1))
    link="${line//\\/\\\\}"
    link="${link//\"/\\\"}"
    output="${output}  - \"${link}\""$'\n'
  done < <(extract_frontmatter_links "$file")

  if [[ "$count" -eq 0 ]]; then
    echo "  []"
    return 0
  fi

  printf '%s' "$output"
}

extract_issue_digits() {
  local raw="$1"
  if [[ "$raw" =~ ^tk([0-9]{4,5})$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$raw" =~ ^([0-9]{4,5})$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

expand_issue_range() {
  local range="$1"
  local start_raw end_raw start_num end_num start_digits end_digits width
  start_raw="${range%%..*}"
  end_raw="${range#*..}"

  start_digits="$(extract_issue_digits "$start_raw")"
  end_digits="$(extract_issue_digits "$end_raw")"
  [[ -n "$start_digits" && -n "$end_digits" ]] || die "invalid issue id range: ${range}"

  if ((${#start_digits} != ${#end_digits})); then
    die "issue id width mismatch in range: ${range}"
  fi

  start_num="$((10#${start_digits}))"
  end_num="$((10#${end_digits}))"
  if (( start_num > end_num )); then
    die "range must be ascending: ${range}"
  fi

  width="${#start_digits}"
  for ((i = start_num; i <= end_num; i++)); do
    printf "tk%0*d\n" "$width" "$i"
  done
}

derive_prefill_from_pl() {
  local root="$1"
  local board="$2"
  local slug="$3"
  local requested="$4"
  local match
  local -a matches=()

  if [[ -n "$requested" ]]; then
    requested="$(normalize_issue_id "$requested")"
    match="$(find_issue_file "$root" "$requested")"
    [[ "$requested" == pl* ]] || die "reopen from requires a pl issue id: ${requested}"
    echo "$match"
    return 0
  fi

  if [[ -z "$board" || -z "$slug" ]]; then
    return 1
  fi

  while IFS= read -r match; do
    matches+=("$match")
  done < <(find "$root/issues" -maxdepth 1 -type f -name "pl*.${board}.${slug}.*.md" 2>/dev/null | sort)

  if (( ${#matches[@]} != 1 )); then
    return 1
  fi

  echo "${matches[0]}"
  return 0
}

build_recap_from_pl() {
  local pl_file="$1"
  local scope accept links_summary

  scope="$(sanitize_recap_value "$(extract_frontmatter_scalar "$pl_file" "scope")")"
  accept="$(sanitize_recap_value "$(extract_frontmatter_scalar "$pl_file" "accept")")"
  links_summary="$(extract_frontmatter_links "$pl_file" | tr '\n' ',' | sed 's/,$//')"

  [[ -n "$scope" ]] || scope="TODO"
  [[ -n "$accept" ]] || accept="TODO"
  [[ -n "$links_summary" ]] || links_summary="TODO"
  echo "核:${scope}|界:${accept}|验:TODO|下:${links_summary}"
}

cmd_new() {
  local root="$1"
  local kind="$2"
  local board="$3"
  local slug="$4"
  local from_pl="" prio="" arg prefill_file recap scope accept links
  local digits file

  shift 4
  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      --from)
        shift
        [[ $# -gt 0 ]] || die "usage: task.sh new <kind> <board> <slug> [--from pl-id] [prio]"
        from_pl="$1"
        shift
        ;;
      p[0-9]*)
        prio="$1"
        shift
        ;;
      *)
        die "usage: task.sh new <kind> <board> <slug> [--from pl-id] [prio]"
        ;;
    esac
  done

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

  recap=""
  scope=""
  accept=""
  links="  []"
  if [[ "$kind" == "tk" ]]; then
    prefill_file="$(derive_prefill_from_pl "$root" "$board" "$slug" "$from_pl" || true)"
    if [[ -n "$prefill_file" ]]; then
      recap="$(build_recap_from_pl "$prefill_file")"
      scope="$(extract_frontmatter_scalar "$prefill_file" "scope")"
      accept="$(extract_frontmatter_scalar "$prefill_file" "accept")"
      links="$(format_frontmatter_links_block "$prefill_file")"
    fi
  fi

  acquire_new_id_lock "$root"
  digits="$(next_doc_digits "$root" "$kind")"
  file="$(issue_doc_path "$root" "$kind" "$digits" "$board" "$slug" "$prio")"
  [[ ! -e "$file" ]] || die "document already exists: $file"

  write_new_issue_doc "$file" "$kind" "$recap" "$scope" "$accept" "$links"
  release_new_id_lock
  trap - EXIT
  echo "$file"
}

cmd_progress() {
  local root="$1"
  local task_id step_slug state requested_state file parent_file parent_state

  assert_control_plane_checkout "$root" "progress"
  task_id="$(normalize_task_id "$2")"
  step_slug="$3"
  requested_state="${4:-}"

  parent_file="$(find_task_file_anywhere "$root" "$task_id")"
  parent_state="$(task_state_from_file "$parent_file")"
  [[ "$step_slug" =~ ^s[0-9]{2}-[a-z0-9-]+$ ]] || die "progress step must look like s01-repro"

  if [[ "$parent_state" == "tdo" || "$parent_state" == "cand" || "$parent_state" == "arvd" || "$parent_state" == "bkd" ]]; then
    state="dne"
  else
    state="doi"
  fi

  if [[ -n "$requested_state" && "$requested_state" != "$state" ]]; then
    warn "progress state overridden from ${requested_state} to ${state} for ${task_id}.${step_slug}"
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

  file="$(review_doc_path "$root" "$issue_id" "$thread" "$round_author" "$result")"
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
  if [[ "$raw" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+(\.(tdo|doi|dne|bkd|cand|arvd))?(\.md)?$ ]]; then
    raw="${raw%.md}"
    raw="${raw%.tdo}"
    raw="${raw%.doi}"
    raw="${raw%.dne}"
    raw="${raw%.bkd}"
    raw="${raw%.cand}"
    raw="${raw%.arvd}"
    echo "$raw"
    return 0
  fi
  if [[ "$raw" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?(\.md)?$ ]]; then
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

  if [[ "$doc_id" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?$ ]]; then
    doc_id="${doc_id%.md}"
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
  local issue_or_range="$2"
  local new_state="$3"
  local issue_id

  is_valid_state "$new_state" || die "invalid state: ${new_state}"

  if [[ "$issue_or_range" == *..* ]]; then
    while IFS= read -r issue_id; do
      move_issue_state "$root" "$issue_id" "$new_state" 0
    done < <(expand_issue_range "$issue_or_range")
  else
    move_issue_state "$root" "$issue_or_range" "$new_state" 0
  fi
}

move_issue_state() {
  local root="$1"
  local issue_id="$2"
  local new_state="$3"
  local skip_if_same_state="${4:-0}"
  local file old_state new_file claimed_by claimed_thread_id

  issue_id="$(normalize_issue_id "$issue_id")"

  assert_control_plane_checkout "$root" "move"

  file="$(find_issue_file "$root" "$issue_id")"
  old_state="$(task_state_from_file "$file")"

  if [[ "$old_state" == "$new_state" ]]; then
    if [[ "$skip_if_same_state" == "1" ]]; then
      echo "$file"
      return 0
    fi
    die "issue already in state ${new_state}"
  fi
  can_transition "$old_state" "$new_state" || die "illegal transition: ${old_state} -> ${new_state}"
  assert_memory_gate_for_close "$root" "$file" "$new_state"
  assert_progress_drained_for_close "$root" "$issue_id" "$new_state"
  assert_blocking_review_gate "$root" "$issue_id" "$new_state"

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

find_issue_file_by_depends_on() {
  local root="$1"
  local dep_id="$2"
  local file dep

  while IFS= read -r file; do
    while IFS= read -r dep; do
      dep="$(strip_wrapping_quotes "$dep")"
      [[ "$dep" == "$dep_id" ]] && printf '%s\n' "$file"
    done < <(extract_frontmatter_depends_on "$file")
  done < <(find "$root/issues" -maxdepth 1 -type f -name "*.md" | sort)
}

collect_batch_close_ids() {
  local root="$1"
  local issue_id="$2"
  local -n seen="$3"
  local -n order="$4"
  local file dep_id

  [[ -n "${seen["$issue_id"]+x}" ]] && return 0
  seen["$issue_id"]=1

  while IFS= read -r file; do
    dep_id="$(task_id_from_file "$file")"
    collect_batch_close_ids "$root" "$dep_id" seen order
  done < <(find_issue_file_by_depends_on "$root" "$issue_id")

  order+=("$issue_id")
}

cmd_batch_close() {
  local root="$1"
  local issue_id="$2"
  local target_state="${3:-dne}"
  local -A seen=()
  local -a order=()
  local target

  is_valid_state "$target_state" || die "invalid state: ${target_state}"

  issue_id="$(normalize_issue_id "$issue_id")"
  collect_batch_close_ids "$root" "$issue_id" seen order
  for target in "${order[@]}"; do
    move_issue_state "$root" "$target" "$target_state" 1
  done
}

cmd_reopen() {
  local root="$1"
  local issue_id="$2"
  shift 2

  local reason from_progress
  local file old_state new_file claimed_by claimed_thread_id

  reason=""
  from_progress=""
  while (($# > 0)); do
    case "$1" in
      --from)
        shift
        [[ $# -gt 0 ]] || die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"
        [[ "$1" == "progress" ]] || die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"
        shift
        [[ $# -gt 0 ]] || die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"
        from_progress="$1"
        shift
        ;;
      *)
        if [[ -n "$reason" ]]; then
          die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"
        fi
        reason="$1"
        shift
        ;;
    esac
  done

  assert_control_plane_checkout "$root" "reopen"
  issue_id="$(normalize_issue_id "$issue_id")"
  [[ -n "$reason" || -n "$from_progress" ]] || die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"

  file="$(find_issue_file_anywhere "$root" "$issue_id")"
  old_state="$(task_state_from_file "$file")"
  [[ "$old_state" == "dne" ]] || die "reopen requires dne state: ${old_state}"

  if [[ -n "$from_progress" ]]; then
    reopen_from_progress "$root" "$issue_id" "$from_progress"
  fi

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
  local keep="32"
  local year archive_dir records moved_file count
  local dry_run="1"
  local record_count=0
  local -a candidates=()
  local archived_file target num kind base file

  shift
  while (( $# > 0 )); do
    case "$1" in
      --keep)
        shift
        [[ $# -gt 0 ]] || die "usage: task.sh archive-done [--keep N] [--yes]"
        keep="$1"
        shift
        ;;
      --yes)
        dry_run="0"
        shift
        ;;
      *)
        die "usage: task.sh archive-done [--keep N] [--yes]"
        ;;
    esac
  done

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

  record_count=0
  while IFS=$'\t' read -r num kind base file; do
    [[ -n "$file" ]] || continue
    record_count=$((record_count + 1))
    if (( record_count <= keep )); then
      continue
    fi
    candidates+=("$file")
  done < <(printf '%s\n' "$records" | sort -t $'\t' -k1,1nr -k2,2r -k3,3r)

  if (( ${#candidates[@]} == 0 )); then
    echo "archive-done preview: no files beyond keep=${keep}"
    return 0
  fi

  if [[ "${dry_run}" == "1" ]]; then
    echo "archive-done preview: ${#candidates[@]} file(s) would be moved (add --yes to apply)"
    for archived_file in "${candidates[@]}"; do
      base="$(basename "$archived_file")"
      echo "  would move: ${archived_file} -> ${archive_dir}/${base}"
    done
    echo "archive-done --yes to execute"
    return 0
  fi

  moved_file=0
  for archived_file in "${candidates[@]}"; do
    base="$(basename "$archived_file")"
    target="${archive_dir}/${base}"
    [[ ! -e "$target" ]] || die "archive target already exists: ${target}"
    mv "$archived_file" "$target"
    echo "$target"
    moved_file=1
  done

  if [[ "$moved_file" -eq 0 ]]; then
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
  local path base kind digits num issue_id
  local exact_file bare_file global_file duplicates cross_line cross_warnings
  local -A touched_exact=()
  local -A touched_numeric=()
  local kind_key
  local count=0
  local ids=()
  local id_count=0
  local warn_line

  if [[ "$CHECK_SCOPE_FULL" -eq 1 ]]; then
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
    done < <(check_issue_file_list "$root")

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

    while IFS= read -r cross_line; do
      [[ -n "$cross_line" ]] && warn "$cross_line"
    done < <(awk -F '\t' '
      { seen[$1, $2] = 1 }
      END {
        for (pair in seen) {
          split(pair, parts, SUBSEP)
          key = parts[1]
          id = parts[2]
          ids[key] = ids[key] ? ids[key] ", " id : id
          count[key]++
        }
        for (key in count) if (count[key] > 1) printf "cross-kind numeric id collision: %04d -> %s\n", key, ids[key]
      }
    ' "$global_file"
    )

    rm -f "$exact_file" "$bare_file" "$global_file"

    if [[ -n "$duplicates" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '%s\n' "$line" >&2
      done < <(printf '%s\n' "$duplicates")
      die "duplicate or colliding issue ids detected"
    fi

    return 0
  fi

  while IFS= read -r path; do
    base="$(basename "$path")"
    if [[ "$base" =~ ^(tk|pl|rs|rf)([0-9]{4,5})\. ]]; then
      kind="${BASH_REMATCH[1]}"
      digits="${BASH_REMATCH[2]}"
      touched_exact["${kind}${digits}"]=1
      touched_numeric["$digits"]=1
    fi
  done < <(check_issue_file_list "$root")

  if [[ "${#touched_exact[@]}" -eq 0 ]]; then
    return 0
  fi

  duplicates="$(mktemp)"

  for kind_key in "${!touched_exact[@]}"; do
    count="$(find "$root/issues" -maxdepth 1 -type f -name "${kind_key}.*.md" | wc -l | tr -d ' ')"
    if (( count > 1 )); then
      printf 'exact:%s -> %s\n' "$kind_key" "$(
        find "$root/issues" -maxdepth 1 -type f -name "${kind_key}.*.md" | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//'
      )" >>"$duplicates"
    fi
  done

  for num in "${!touched_numeric[@]}"; do
    ids=()
    id_count=0
    while IFS= read -r kind; do
      if find "$root/issues" -maxdepth 1 -type f -name "${kind}${num}.*.md" -print -quit | grep -q .; then
        ids+=("${kind}${num}")
        id_count=$((id_count + 1))
      fi
    done < <(printf '%s\n' "tk" "pl" "rs" "rf")

    if (( id_count > 1 )); then
      warn_line="$num -> $(printf '%s, ' "${ids[@]}" | sed 's/, $//')"
      warn "cross-kind numeric id collision: ${warn_line}"
    fi
  done

  if [[ -s "$duplicates" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '%s\n' "$line" >&2
    done < "$duplicates"
    rm -f "$duplicates"
    die "duplicate or colliding issue ids detected"
  fi

  rm -f "$duplicates"
}

check_issue_file_names() {
  local root="$1"
  local file issue_spec id state board slug rest
  local -A seen_ids=()

  while IFS= read -r file; do
    if ! issue_spec="$(parse_issue_filename "$file")"; then
      die "invalid issue filename: $file"
    fi
    IFS=$'\t' read -r id state board slug rest <<<"$issue_spec"
    if [[ -n "${seen_ids["$id"]+x}" ]]; then
      die "duplicate issue id with multiple files: ${id} -> ${seen_ids["$id"]}, ${file}"
    fi
    seen_ids["$id"]="$file"
  done < <(check_issue_file_list "$root")
}

check_legacy_rvw_state() {
  local root="$1"
  local file

  while IFS= read -r file; do
    die "rvw state is retired; move the document to doi, dne, cand, bkd, or arvd: $file"
  done < <(
    {
      check_issue_file_list "$root" | grep -E '\.rvw\.[^.]+\.md$' 2>/dev/null
      check_review_file_list "$root" | grep -E '\.rvw\.[^.]+\.md$' 2>/dev/null
    } | sort
  )
}

check_rp_names() {
  local root="$1"
  local file base

  [[ -d "$root/docs/reviews" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    if [[ "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?\.md$ ]]; then
      continue
    fi
    if [[ "$base" =~ \.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?\.md$ ]]; then
      die "unscoped review/audit belongs in aidocs/agent-runs, not docs/reviews: $file"
    fi
    [[ "$base" =~ ^rp${ID_DIGITS_RE}\.(tdo|doi|dne|bkd|cand|arvd)\.[a-z0-9-]+\.(review-r[0-9]+-[a-z0-9-]+|reply-r[0-9]+-[a-z0-9-]+)(\.(block|pass|note))?\.md$ ]] \
      || die "invalid review filename: $file"
  done < <(check_review_file_list "$root")
}

check_rv_names() {
  local root="$1"
  local file base issue_id result

  [[ -d "$root/docs/reviews" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    [[ "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?\.md$ ]] \
      || continue
    issue_id="${base%%.*}"
    find_issue_file_anywhere "$root" "$issue_id" >/dev/null
    result="$(extract_frontmatter_scalar "$file" "result")"
    if [[ -n "$result" && ! "$result" =~ ^(block|pass|note)$ ]]; then
      die "invalid review result in $file: $result"
    fi
  done < <(check_review_file_list "$root")
}

check_progress_names() {
  local root="$1"
  local file base task_id step_slug progress_state parent_file parent_state doi_tmp step_tmp duplicates duplicate_steps mapping_message

  [[ -d "$root/docs/progress" ]] || return 0
  doi_tmp="$(mktemp)"
  step_tmp="$(mktemp)"

  while IFS= read -r file; do
    base="$(basename "$file")"
  [[ "$base" =~ ^(tk${ID_DIGITS_RE})\.(s[0-9]{2}-[a-z0-9-]+)\.(tdo|doi|dne|bkd|cand|arvd)\.md$ ]] \
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

    case "$parent_state" in
      tdo)
        mapping_message="${file} exists while ${task_id} is still tdo; delete progress first and move ${task_id} to doi first"
        rm -f "$doi_tmp" "$step_tmp"
        die "$mapping_message"
        ;;
      doi)
        if [[ "$progress_state" != "doi" && "$progress_state" != "dne" ]]; then
          mapping_message="${file} is ${progress_state} but parent is ${task_id}.doi; expected doi or dne"
          rm -f "$doi_tmp" "$step_tmp"
          die "$mapping_message"
        fi
        ;;
      cand|dne|arvd|bkd)
        if [[ "$progress_state" != "dne" ]]; then
          mapping_message="${file} is ${progress_state} but parent is ${task_id}.${parent_state}; move progress to dne first"
          rm -f "$doi_tmp" "$step_tmp"
          die "$mapping_message"
        fi
        ;;
      *)
        rm -f "$doi_tmp" "$step_tmp"
        die "unknown parent state for ${task_id}: ${parent_state}"
        ;;
    esac
  done < <(check_progress_file_list "$root")

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
  local file base
  local matches

  if [[ ${#CHECK_REVIEW_ANCHOR_PREFIXES[@]} -gt 0 ]]; then
    if [[ -n "${CHECK_REVIEW_ANCHOR_PREFIXES[$review_id]+x}" ]]; then
      echo "$root/${review_id}.md"
      return 0
    fi
    if [[ -f "$root/docs/reviews/${review_id}.md" ]]; then
      echo "$root/docs/reviews/${review_id}.md"
      return 0
    fi
    if [[ -f "$root/issues/${review_id}.md" ]]; then
      echo "$root/issues/${review_id}.md"
      return 0
    fi
    return 1
  fi

  matches="$(
    while IFS= read -r file; do
      base="$(basename "$file")"
      [[ "$base" == "${review_id}."* ]] && printf '%s\n' "$file"
    done < <(find "$root/docs/reviews" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
    while IFS= read -r file; do
      base="$(basename "$file")"
      [[ "$base" == "${review_id}."* ]] && printf '%s\n' "$file"
    done < <(find "$root/issues" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
  )"

  [[ -n "$matches" ]] || return 1
  printf '%s\n' "$matches"
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

      if [[ "$raw_target" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?$ ]]; then
        normalized="$root/docs/reviews/${raw_target}.md"
        [[ -f "$normalized" ]] || die "missing rv link target: $file -> $raw_link"
        continue
      fi

      if [[ "$raw_target" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+$ ]]; then
        if [[ ${#CHECK_PROGRESS_SLUGS[@]} -gt 0 ]]; then
          [[ -n "${CHECK_PROGRESS_SLUGS[$raw_target]+x}" ]] || die "missing progress link target: $file -> $raw_link"
        else
          if ! (find "$root/docs/progress" -maxdepth 1 -type f -name "${raw_target}.*.md" | grep -q .); then
            die "missing progress link target: $file -> $raw_link"
          fi
        fi
        continue
      fi

      normalized="$(normalize_link_target "$root" "$raw_link")"
      base="$(basename "$normalized")"

      if [[ ! "$base" =~ ^rp${ID_DIGITS_RE}\..*\.md$ && ! "$base" =~ ^(tk|pl|rs|rf)${ID_DIGITS_RE}\.rv[0-9]{3}-r[0-9]{3}-[a-z0-9-]+(\.(block|pass|note))?\.md$ && ! "$base" =~ ^tk${ID_DIGITS_RE}\.s[0-9]{2}-[a-z0-9-]+\.(tdo|doi|dne|bkd|cand|arvd)\.md$ ]]; then
        continue
      fi

      [[ -f "$normalized" ]] || die "missing review link target: $file -> $raw_link"
    done < <(extract_frontmatter_links "$file")
  done < <(check_issue_file_list "$root")
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
  done < <(check_issue_file_list "$root")
}

check_arvd_residue() {
  local root="$1"
  local residue
  local path base

  residue="$(while IFS= read -r path; do
    base="$(basename "$path")"
    [[ "$base" =~ ^(tk|pl|rs|rf)[0-9]{4,5}\.arvd\..*\.md$ ]] && printf '%s\n' "$path"
  done < <(check_issue_file_list "$root" ) || true)"
  if [[ -n "$residue" ]]; then
    echo "$residue" >&2
    die "archived issue residue detected in issues/"
  fi
}

check_legacy_reply_chains() {
  local root="$1"
  local legacy
  local path base

  if [[ "$CHECK_SCOPE_FULL" -eq 1 ]]; then
    legacy="$(find "$root/docs" -type f \( -name 're.*.md' -o -name 're.re.*.md' \) 2>/dev/null | sort || true)"
  else
    legacy="$( {
      while IFS= read -r path; do
        base="$(basename "$path")"
        [[ "$base" == re.*.md || "$base" == re.re.*.md ]] && printf '%s\n' "$path"
      done < <(check_issue_file_list "$root")
      while IFS= read -r path; do
        base="$(basename "$path")"
        [[ "$base" == re.*.md || "$base" == re.re.*.md ]] && printf '%s\n' "$path"
      done < <(check_review_file_list "$root")
      while IFS= read -r path; do
        base="$(basename "$path")"
        [[ "$base" == re.*.md || "$base" == re.re.*.md ]] && printf '%s\n' "$path"
      done < <(check_progress_file_list "$root")
    } | sort
    )"
  fi

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
  done < <(check_issue_file_list "$root" | grep -E '/tk[0-9]{4,5}\.md$')
}

check_issue_recap_no_status_slot() {
  local root="$1"
  local file recap

  [[ "$CHECK_SCOPE_FULL" -eq 0 ]] || return 0

  for file in "${CHECK_ISSUE_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    [[ "${CHECK_CHANGED_ISSUE_FILES["$file"]+x}" == "x" ]] || continue
    recap="$(extract_frontmatter_scalar "$file" "recap")"
    [[ -n "$recap" ]] || continue
    if [[ "$recap" == *態:* || "$recap" == *"态:"* ]]; then
      die "issue recap must not include filename-like status slot (态). keep state only in filename: $file"
    fi
  done
}

check_issue_rename_state_only_pair() {
  local root="$1"
  local old_file="$2"
  local new_file="$3"
  local old_issue new_issue
  local old_id old_state new_id new_state
  local old_board old_slug old_rest
  local new_board new_slug new_rest

  if ! old_issue="$(parse_issue_filename "$root/$old_file")"; then
    die "invalid issue source filename in rename: $old_file"
  fi
  if ! new_issue="$(parse_issue_filename "$root/$new_file")"; then
    die "invalid issue destination filename in rename: $new_file"
  fi

  IFS=$'\t' read -r old_id old_state old_board old_slug old_rest <<<"$old_issue"
  IFS=$'\t' read -r new_id new_state new_board new_slug new_rest <<<"$new_issue"

  if [[ "$old_id" != "$new_id" ]]; then
    die "issue rename changed id slot: $old_file -> $new_file; use helper move/alloc for id changes"
  fi
  if [[ "$old_state" == "$new_state" ]]; then
    die "issue rename did not change state slot: $old_file -> $new_file"
  fi
  if [[ "$old_board" != "$new_board" || "$old_slug" != "$new_slug" || "$old_rest" != "$new_rest" ]]; then
    die "issue rename changed non-state parts (board/slug/rest): $old_file -> $new_file; use helper move/alloc for non-state edits"
  fi
}

check_dne_issue_no_blocking_review() {
  local root="$1"
  local file id state

  while IFS= read -r file; do
    id="$(task_id_from_file "$file")"
    state="$(task_state_from_file "$file")"
    [[ "$state" == "dne" ]] || continue
    assert_blocking_review_gate "$root" "$id" "dne"
  done < <(check_issue_file_list "$root")
}

check_issue_rename_is_state_only() {
  local root="$1"
  local status old_file new_file

  while IFS=$'\t' read -r status old_file new_file; do
    [[ "$status" == R* ]] || continue
    [[ "$old_file" == issues/* && "$new_file" == issues/* ]] || continue
    check_issue_rename_state_only_pair "$root" "$old_file" "$new_file"
  done < <(git -C "$root" diff --name-status --find-renames --diff-filter=R -- 2>/dev/null || true)
  while IFS=$'\t' read -r status old_file new_file; do
    [[ "$status" == R* ]] || continue
    [[ "$old_file" == issues/* && "$new_file" == issues/* ]] || continue
    check_issue_rename_state_only_pair "$root" "$old_file" "$new_file"
  done < <(git -C "$root" diff --cached --name-status --find-renames --diff-filter=R -- 2>/dev/null || true)
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
    done < <(check_issue_file_list "$root")
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
  done < <(check_issue_file_list "$root" | grep -E '/tk[0-9]{4,5}\.doi\..*\.md$')
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
  shift 2

  local -a explicit_files=()

  while (($# > 0)); do
    case "$1" in
      --changed|--files)
        shift
        while (($# > 0)); do
          explicit_files+=("$1")
          shift
        done
        ;;
      *)
        die "usage: task.sh check [--changed <file> ...]"
        ;;
    esac
  done

  assert_no_truth_edits_in_linked_worktree "$current_root" "check"
  build_check_file_cache "$current_root" "$semantic_root" "${explicit_files[@]}"
  check_duplicate_issue_ids "$semantic_root"
  check_issue_file_names "$semantic_root"
  check_arvd_residue "$semantic_root"
  check_legacy_rvw_state "$semantic_root"
  check_rp_names "$semantic_root"
  check_rv_names "$semantic_root"
  check_progress_names "$semantic_root"
  check_issue_rename_is_state_only "$semantic_root"
  check_dne_issue_no_blocking_review "$semantic_root"
  check_issue_review_links_exist "$semantic_root"
  check_issue_dependencies_exist "$semantic_root"
  check_legacy_reply_chains "$semantic_root"
  check_project_memory_links "$semantic_root"
  check_issue_recap_no_status_slot "$semantic_root"
  check_banned_arch_terms "$semantic_root"
  check_doi_staleness "$semantic_root"
  emit_warning_summary
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
    batch-close)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 2 && $# -le 3 ]] || die "usage: task.sh batch-close <issue-id> [state]"
      cmd_batch_close "$control_root" "$2" "${3:-dne}"
      ;;
    reopen)
      current_root="$(find_project_root)" || die "run from a project directory that contains issues/"
      control_root="$(find_control_plane_root "$current_root")"
      [[ $# -ge 2 ]] || die "usage: task.sh reopen <issue-id> [reason] [--from progress <step>]"
      issue_id="$2"
      shift 2
      cmd_reopen "$control_root" "$issue_id" "$@"
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
      cmd_archive_done "$control_root" "$@"
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
      cmd_check "$current_root" "$control_root" "${@:2}"
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
