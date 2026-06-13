# PRD: agtask Rust Binary

Status: active v2 product draft, updated 2026-06-13. Supersedes earlier agtask v2 drafts; do not implement from older copies.

## 1. Introduction

Agata Code Workflow v1 uses the filesystem as the workflow ledger. Issue state lives in filenames, durable context lives in markdown, and helper scripts enforce transitions and checks. This design should stay intact for active users.

`agtask` is the v2 product name for a Rust binary that explores a cleaner future grammar and faster workflow operations while preserving the core principle: files remain the source of truth. Rust replaces the shell-heavy helper layer; it must not introduce a database, daemon, server, or second state system as the primary workflow model.

The first implementation target is a research-grade v2 sample and Build Now CLI. It must prove that the new grammar lowers agent error rate and improves performance before any migration from v1 is considered.

## 2. Goals

- Provide a Rust CLI that parses, validates, renames, lists, and projects workflow files quickly and predictably.
- Keep the workflow source of truth in ordinary files that humans, shell tools, Git, and LLMs can read.
- Separate truth from generated artifacts: `.v/` and `.v/ctx.md` are disposable and rebuildable; `views/*.md` is deferred.
- Reduce duplicated state by deriving hot fields from path and filename instead of repeating them in frontmatter.
- Preserve Unix affordances: stable TSV output, shell-friendly filters, symlink or pointer lenses, and plain markdown.
- Define a staged path from v1 to v2 without forcing current projects to migrate.

## 3. Non-Goals

- No SQLite or embedded database in the MVP.
- No daemon, background service, web server, scheduler, or remote sync.
- No Linear, Notion, GitHub Issues, or bidirectional external integration.
- No migration of active v1 repositories until v2 proves simpler and safer.
- No second truth source: generated files must never override `issues/`.
- No new workflow platform or orchestration layer.
- No broad state expansion. Review remains evidence unless the v2 spec explicitly proves a better state model.

## 4. Product Principle

`agtask` should make the workflow more filesystem-native, not more application-like.

Core rule:

```text
issues/ = truth
.v/ = generated lens
ctx = generated LLM snapshot
Rust binary = parser, checker, projector, and safe rename tool
```

Generated outputs must be safe to delete at any time. If a generated view disagrees with `issues/`, delete and rebuild the view.

## 5. v2 Ledger Grammar

v2 may explore a new grammar in samples only:

```text
issues/<lane>/<id>.<state>.<priority>.<slug>.md
```

Example:

```text
issues/runtime/tk1828.doi.p1.runner-slash-input.md
issues/docs/tk1830.tdo.p2.cleanup-install-docs.md
issues/planning/tk1831.cnl.p3.add-roadmap-view.md
```

Path-derived fields:

- `lane`: directory under `issues/`
- `id`: permanent workflow id
- `state`: lifecycle state
- `priority`: sorting and attention field
- `slug`: human and LLM readable title

Frontmatter must not repeat path-derived fields. It only stores fields that the path cannot express.

Example issue:

```md
---
owner: cal
threads: [thread:019dd9af]
depends_on: [tk1820, tk1819]
tags: [runner, cli]
links: []
---
# pass runner slash input through

## Why

Runner currently drops slash input before execution.

## Acceptance

- slash input passes through unchanged
- existing runner tests still pass
- behavior documented
```

## 6. State Model

The v2 sample should begin with the smallest state set that can represent the workflow:

```text
cnl  = cancelled, dropped, or not-now; outside the active required graph
tdo  = todo / pending required work
doi  = doing / actively claimed work
bkd  = blocked after work started
dne  = done / closed
```

Review remains evidence, not an issue lifecycle state. `agtask` only treats matching `.block.md` review files as close blockers.

Archive is outside the state model. Later cold storage uses `agtask compact` and `agtask restore` to move closed issues through an archive path while preserving the final business state.

## 7. Review and Progress Direction

v2 should keep the successful v1 direction:

- Progress is evidence for a task, not an independent task owner.
- Progress state should be derived from the parent task where possible.
- Review block should be visible in the review filename.
- Blocking review must prevent `dne`.

Candidate review filename:

```text
docs/reviews/tk1828.rv001-r001-cal.block.md
```

Candidate progress filename:

```text
docs/progress/tk1828.s01-repro.md
docs/progress/tk1828.s02-verify.md
```

`agtask` does not provide a review command in MVP. Review files are produced by business workflow; `agtask` only guards close readiness.

## 8. CLI Shape

Primary binary name:

```text
agtask
```

Build Now commands:

```text
agtask new <kind> <lane> <slug> <priority>
agtask ls [--tsv]
agtask check
agtask check --changed <file>...
agtask move <id> <state>
agtask assign <id> <owner>
agtask relane <id> <lane>
agtask reprioritize <id> <priority>
agtask rename <id> <slug>
agtask join <id> [--thread-id <thread>]
agtask depend <id> add <dep>
agtask depend <id> remove <dep>
agtask progress <id> <sNN-slug>
agtask reopen <id> [--owner <owner>] [--thread-id <thread>] [--reason <text>]
agtask lens
agtask ctx
```

Later commands:

```text
agtask compact <id>
agtask restore <id>
agtask retype <id> <kind>
```

Commands intentionally deferred:

```text
agtask batch-close
agtask review
agtask tag
agtask link
agtask sync
agtask server
agtask daemon
```

## 9. TSV Projection

`agtask ls --tsv` is the first critical interface. It turns the filesystem ledger into a stable stream.

Required columns:

```text
id	state	priority	lane	slug	owner	thread_count	depends_on	tags	link_count	blocking_review	open_progress	path
```

Example:

```text
tk1828	doi	p1	runtime	runner-slash-input	cal	2	tk1820,tk1819	runner,cli	1	no	no	issues/runtime/tk1828.doi.p1.runner-slash-input.md
tk1830	tdo	p2	docs	cleanup-install-docs	reviewer	0			0	no	no	issues/docs/tk1830.tdo.p2.cleanup-install-docs.md
```

This stream is the Unix query surface:

```bash
agtask ls --tsv | awk '$2=="doi" && $3=="p1"'
agtask ls --tsv | awk '$4=="runtime"'
agtask ls --tsv | awk '$6=="cal"'
```

Future cache or SQLite internals may sit behind `agtask ls`, but the external interface should stay a stream.

## 10. Lens Generation

`agtask lens` generates a disposable view forest:

```text
.v/
  state/
    cnl/
    tdo/
    doi/
    bkd/
    dne/
  pri/
    p0/
    p1/
    p2/
    p3/
  lane/
    runtime/
    docs/
    planning/
  owner/
    cal/
    agent-docs/
  blocked/
    tk1834/
  tag/
    runner/
    cli/
```

Entries should be symlinks when the platform supports them. If symlinks are unavailable, use small pointer files with the target path.

Lens requirements:

- Rebuild from scratch.
- Never mutate `issues/`.
- Never store non-derivable truth.
- Be gitignored by default.
- Fail loudly on parse errors instead of silently skipping malformed files.

## 11. Context Snapshot

`agtask ctx` emits an LLM-oriented snapshot to stdout by default. `agtask ctx --write .v/ctx.md` may write a generated file.

The snapshot should prioritize actionability:

```md
# Context

## Active P1
- tk1828 doi p1 runtime cal runner-slash-input

## Blocked
- tk1834 blocked by tk1828

## Review Blocks
- tk1811 has blocking review rv001-r001-reviewer.block

## Stale DOI
- tk1771 doi p2 runtime untouched for 4 days

## Recent Done
- tk1801 dne p1 runtime
```

`ctx` is a generated digest, not a memory ledger.

## 12. Check Rules for Build Now

`agtask check` should start with hard structural invariants:

1. Live issue paths and archive issue filenames match the v2 grammar.
2. `id` is globally unique across live and archive issue filenames.
3. `state` is in the allowed set.
4. `priority` is in the allowed set.
5. `lane` is a valid directory segment.
6. `depends_on` targets exist.
7. Dependency graph has no cycles.
8. `dne` is blocked by any matching `.block.md` review file.
9. Active `tdo`, `doi`, and `bkd` issues have an owner.
10. `p0` and `p1` issues have acceptance criteria.
11. Generated `.v/` and `.v/ctx.md` are not treated as truth.
12. Errors and warnings are separated; errors block, warnings are concise.

`agtask check --changed <file>...` must validate only the changed truth files plus the minimum related files required for fast referential integrity. Full graph checks such as dependency-cycle auditing belong to `agtask check`.

## 13. Performance Requirements

Target project sizes:

```text
2k files: check --changed < 1s, full check < 2s
6k files: check --changed < 1s, full check < 5s
20k files: check --changed < 1s, full check < 15s
```

These are local-machine targets, not hard product guarantees. The important rule is that pre-commit should use `--changed` and should not degrade linearly with total repository size for ordinary commits.

## 14. Compatibility with v1

v2 must not replace v1 in place.

Required compatibility stance:

- v1 remains the production workflow contract.
- v2 grammar lives in samples, experiments, or a dedicated branch until proven.
- v2 Rust binary may offer read-only v1 adapters later, but MVP does not require v1 mutation.
- No automatic migration of active v1 repos.
- Any future migration must be reversible and must preserve Git history readability.

## 15. User Stories

### US-001: Stable TSV Projection

As an agent, I want to list all workflow issues as a stable TSV stream so that I can filter state, priority, lane, owner, and dependencies using ordinary shell tools.

Acceptance criteria:

- [ ] `agtask ls --tsv` prints one header row and one row per issue.
- [ ] Columns are stable and documented.
- [ ] Malformed issue filenames fail loudly.
- [ ] Output is deterministic across repeated runs.

### US-002: Fast Structural Check

As a user, I want `agtask check --changed` to validate my staged workflow changes quickly so that pre-commit feedback is immediate.

Acceptance criteria:

- [ ] `agtask check --changed <files...>` accepts changed truth paths.
- [ ] Errors and warnings are printed in separate sections.
- [ ] Structural errors include path, parsed state, and suggested action.
- [ ] Changed-file checks avoid scanning unrelated markdown bodies.

### US-003: Safe State Rename

As an agent, I want `agtask move <id> <state>` to rename the file safely so that state changes stay in the filename truth source.

Acceptance criteria:

- [ ] The command finds exactly one issue by id.
- [ ] The command changes only the state slot.
- [ ] `move <dne-id> doi` is rejected; done-to-doing uses `reopen`.
- [ ] The command refuses ambiguous or duplicate ids.
- [ ] The command blocks `dne` when close-readiness checks fail.

### US-003A: Safe Slot and Field Mutators

As an agent, I want dedicated commands for hot filename slots and structural fields so that I do not hand-edit paths or YAML.

Acceptance criteria:

- [ ] `relane`, `reprioritize`, and `rename` each change only one filename slot while preserving issue id.
- [ ] `assign` changes only `owner`.
- [ ] `join` appends only to `threads`, deduped.
- [ ] `depend add/remove` changes only `depends_on` and preserves DAG validity.

### US-004: Filesystem Lens

As a user, I want `agtask lens` to generate disposable filesystem views so that I can inspect state, priority, owner, and blocked slices with `ls`.

Acceptance criteria:

- [ ] `.v/` is rebuilt from current `issues/`.
- [ ] Lens entries point back to issue files.
- [ ] Deleting `.v/` and rerunning `agtask lens` restores the same view.
- [ ] Lens generation fails on malformed truth files.

### US-005: LLM Context Snapshot

As an agent, I want `agtask ctx` to produce a compact current-world summary so that I can avoid loading thousands of filenames into context.

Acceptance criteria:

- [ ] `agtask ctx` writes to stdout by default.
- [ ] `agtask ctx --write .v/ctx.md` writes a disposable generated snapshot.
- [ ] Snapshot includes active P1, blocked, review blocks, stale DOI, and recent done sections.
- [ ] Snapshot does not introduce any state not derivable from truth files.
- [ ] Stale and recent sections are documented as heuristics, not audit truth.

### US-006: Pre-Commit Incremental Guard

As a user, I want pre-commit to run only changed-path validation so that ordinary commits get feedback quickly even in large repositories.

Acceptance criteria:

- [ ] `agtask check --changed <staged paths...>` is the documented pre-commit path.
- [ ] Generated paths such as `.v/` are rejected as truth inputs.
- [ ] If no staged truth path is present, the command returns `ok` without full body scan.
- [ ] Errors block and warnings print separately.

### US-007: Design-Safe Scope Control

As a maintainer, I want Build Now and Later scope to be explicit so that agtask does not become a platform before the file grammar proves itself.

Acceptance criteria:

- [ ] Build Now and Later commands match the command surface in section 8.
- [ ] `batch-close`, review command, tag command, link command, web UI, sync, daemon, and SQLite cache are deferred.
- [ ] Any scope change updates `DESIGN.md`, `PRD.md`, and `SPEC.md`.

## 16. Core Workflows

Pre-commit:

```text
git staged paths -> agtask check --changed <paths> -> block on errors
```

Agent orientation:

```text
agtask ctx -> open exact issue/review/progress files by id
```

Shell query:

```text
agtask ls --tsv | awk '$2=="doi" && $3=="p1"'
```

Close readiness:

```text
agtask move <id> dne -> fail if active blocking review, missing owner, missing p0/p1 acceptance, or unresolved dependency exists
```

View regeneration:

```text
rm -rf .v && agtask lens
```

## 17. Build Now and Later

Build Now:

- `agtask new`
- `agtask ls --tsv`
- `agtask check`
- `agtask check --changed`
- `agtask move`
- `agtask assign`
- `agtask relane`
- `agtask reprioritize`
- `agtask rename`
- `agtask join`
- `agtask depend add/remove`
- `agtask progress`
- `agtask reopen`
- `agtask lens`
- `agtask ctx`
- parser examples
- validation examples
- performance comparison

Later:

- `agtask compact`
- `agtask restore`
- atomic kind migration / `agtask retype`

Deferred:

- batch close
- review command
- tag command
- link command
- generated `views/*.md`
- SQLite cache
- v1 migration
- web UI
- external sync
- daemon/server
- milestones, scheduling, or workflow engine features

## 18. Product Invariants

- Files are the ledger.
- Generated views are disposable.
- Command output is API.
- Rename is mutation.
- Body is not index.
- Pre-commit must be incremental.
- No hidden service is required.
- v2 must not mutate v1 projects.

## 19. Rejected Designs

- SQLite or embedded database as truth.
- Daemon, server, or background watcher.
- Linear, Notion, GitHub Issues, or bidirectional sync.
- YAML view DSL.
- Review as issue state.
- Progress state slot.
- Root-level permanent `ctx.md`.
- Duplicating path-derived fields in frontmatter.
- Secondary `tk` binary or alias as official contract.
- `cand` as a state name.
- `arvd` as a state slot.
- `risk` or `memory` as MVP frontmatter keys.
- `blocks` or `blocked_by` as frontmatter relation truth.
- In-place v1 migration.

## 20. Execution Plan

### Phase 0: Spec Freeze

Deliverables:

- This PRD.
- v2 grammar examples.
- Explicit non-goals.
- Decision that v1 production grammar is not migrated yet.

Exit criteria:

- User accepts the v2 boundary.
- No disagreement remains on `issues/` as source of truth.

### Phase 1: Rust Skeleton

Deliverables:

- `crates/agtask-cli/` binary crate.
- CLI parser for Build Now commands.
- Sample v2 example tree under `v2/examples/`.

Exit criteria:

- Binary runs locally.
- `agtask --help` documents Build Now commands first, with Later commands clearly marked.

### Phase 2: Parser and Projection

Deliverables:

- Path parser for v2 issue grammar.
- Frontmatter parser for cold fields.
- `agtask new`.
- `agtask ls --tsv`.

Exit criteria:

- Sample issues project to deterministic TSV.
- Parser errors include exact path and rule.

### Phase 3: Check, Move, and Fast Commit Guard

Deliverables:

- Hard invariant checks.
- `agtask check --changed <path>...`.
- Error and warning separation.
- `agtask move <id> <state>`.

Exit criteria:

- Malformed live/archive filename, duplicate id, missing dependency, unresolved dependency, and blocking review examples fail with actionable errors.
- `move` changes only the state slot.
- Illegal close prints the blocking evidence or missing readiness reason.
- Changed checks avoid unrelated markdown bodies.
- Clean sample passes.

### Phase 4: Guarded Mutators and Evidence

Deliverables:

- `agtask assign`.
- `agtask relane`.
- `agtask reprioritize`.
- `agtask rename`.
- `agtask join`.
- `agtask depend add/remove`.
- `agtask progress`.
- `agtask reopen`.

Exit criteria:

- Mutators update only their named slot or field.
- `join` changes threads only and never changes owner.
- `depend` preserves DAG validity.
- Progress has no independent state.
- Reopen is `dne -> doi` only.

### Phase 5: Lens and Context

Deliverables:

- `.v/` lens generation.
- `.v/blocked` derived from `depends_on`.
- `agtask ctx` stdout output.
- Optional `--write .v/ctx.md`.

Exit criteria:

- Deleting and rebuilding `.v/` produces the same lens from unchanged truth.
- Context snapshot stays under a practical LLM budget for large samples.

### Phase 6: Later Storage and Migration

Deliverables:

- `agtask compact`.
- `agtask restore`.
- Atomic `agtask retype` specification, before implementation.

Exit criteria:

- Compact/restore preserve basename and state.
- Kind migration is treated as primary-key migration.
- No partial `retype` implementation is accepted.

### Phase 9: v1 Comparison

Deliverables:

- Benchmark against current `task.sh check` on a representative repo.
- Error-message comparison for known user pain cases.
- Decision memo: keep v2 experimental, ship as optional, or begin migration design.

Exit criteria:

- v2 is measurably faster or simpler on the tested surface.
- Any proposed migration has a rollback path.

## 21. Open Questions

1. Should v2 support read-only parsing of v1 repos before implementing any v2 mutation?
2. Should unknown frontmatter keys remain warnings after MVP, or become errors?

## 22. Decision Gate

Do not migrate v1 until all are true:

- v2 check rules are simpler to explain than v1 rules.
- New agents can use v2 samples without extra oral instruction.
- `agtask check --changed` is consistently fast in pre-commit scale tests.
- Error messages are more actionable than v1 helper messages.
- Migration tooling can run as dry-run, apply, and rollback.
