# agtask Design Plan

Status: active v2 design draft, updated 2026-06-13. Supersedes earlier agtask v2 drafts; do not implement from older copies.

## 1. Product Name

The product name is `agtask`.

`agtask` is the v2 product line for a Rust-based, file-native task workflow. It inherits the useful idea from Agata Code Workflow v1: workflow truth belongs in files, not in chat state, databases, dashboards, or generated summaries.

The current stage is design planning. Do not start production implementation until the design gates in this file are resolved.

## 2. Positioning

`agtask` is a local-first task ledger for human and AI coding agents.

It is:

- a filesystem grammar
- a Rust CLI
- a validator
- a safe rename tool
- a TSV projector
- a disposable lens generator
- an LLM context snapshot generator

It is not:

- a database product
- a Linear clone
- a task server
- a scheduler
- a multi-agent orchestration platform
- a sync system
- a replacement for Git

The design target is Unix-native Linear affordance: state visibility, slices, blockers, and next-action context without leaving ordinary files.

## 3. Design Thesis

The core thesis:

```text
path + filename = hot truth
frontmatter = cold truth
body = work content
generated views = disposable lens
Rust = fast and strict projection layer
```

Hot truth means fields that agents and tools scan constantly:

```text
lane
id
state
priority
slug
```

Cold truth means fields that matter but should not trigger renames on ordinary edits:

```text
owner
threads
depends_on
tags
links
```

The design must avoid duplicate truth. If a value exists in the path, it does not belong in frontmatter.

## 4. Product Users

Primary users:

- AI coding agents that need low-latency workflow context
- human maintainers reviewing task state through Git and shell tools
- pre-commit hooks that need fast structural validation

Secondary users:

- reviewers checking blockers and close readiness
- maintainers preparing future migration from v1
- tooling authors building optional UIs on top of `agtask ls --tsv`

## 5. Core Objects

Issue:

```text
issues/<lane>/<id>.<state>.<priority>.<slug>.md
```

Review:

```text
docs/reviews/<issue-id>.rv<round>-r<revision>-<author>.<outcome>.md
```

Progress:

```text
docs/progress/<issue-id>.s<step>-<slug>.md
```

Lens:

```text
.v/
```

Context snapshot:

```text
agtask ctx
agtask ctx --write .v/ctx.md
```

## 6. Product Surface

Build Now:

```text
agtask new <kind> <lane> <slug> <priority>
agtask ls --tsv
agtask check
agtask check --changed <path>...
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

Later:

```text
agtask compact <id>
agtask restore <id>
agtask retype <id> <kind>
```

Design rule:

Every command must read truth, validate truth, create a truth file, mutate exactly one named truth slot/field, move closed files between hot/cold ledgers, or generate disposable projection. Scheduling, sync, serving, and orchestration are out of scope.

## 7. Data Flow

```text
issues/ + docs/reviews/ + docs/progress/
  -> parser
  -> normalized in-memory records
  -> check invariants
  -> ls TSV
  -> lens .v/
  -> ctx markdown
```

No generated output feeds back into truth.

Mutators must be narrow. `move` changes state, `assign` changes owner, `relane` changes lane, `reprioritize` changes priority, `rename` changes slug, `join` changes threads, and `depend` changes dependencies.

## 8. Validation Philosophy

`agtask` should fail early, loudly, and specifically.

Good error:

```text
error[E003] issues/runtime/tk1828.foo.p1.runner.md: invalid state "foo"; expected cnl|tdo|doi|bkd|dne
```

Bad error:

```text
check failed
```

Errors block. Warnings inform. Warning noise must not hide blocking errors.

## 9. Performance Model

The performance model is intentionally simple:

- pre-commit uses `check --changed`
- normal query uses `ls --tsv`
- full check is allowed to scale with repo size but should remain predictable
- SQLite is not part of MVP

Optimization order:

1. avoid reading unrelated bodies
2. parse filenames first
3. read frontmatter only when needed
4. build small relation maps
5. profile before adding cache

## 10. LLM Context Model

Current v1 benefit:

```text
LLM can scan many filenames and understand the world.
```

v2 target:

```text
LLM reads agtask ctx first, then opens exact files by id.
```

`ctx` should answer:

- What is active?
- What is high priority?
- What is blocked?
- What has review block?
- What is stale?
- What recently closed?

It must not become memory or truth.

## 11. Design Phases

Phase A: Design Freeze

- freeze name as `agtask`
- finish `PRD.md`
- finish `SPEC.md`
- define example contract
- document Build Now and Later surfaces
- document generated `views/*.md` as deferred

Phase B: CLI Skeleton

- create Rust workspace under `v2/`
- implement `agtask --help`
- implement root discovery
- implement exit code mapping
- implement top-level error formatting

Phase C: Parser and Projection

- parse issue grammar
- parse frontmatter subset
- implement `new`
- implement `ls --tsv`
- guarantee deterministic ordering

Phase D: Check, Move, and Fast Commit Guard

- implement full `check`
- implement `check --changed`
- separate errors from warnings
- implement `move`
- enforce state matrix
- ensure move changes only state
- block done on close-readiness failures

Phase E: Guarded Mutators and Evidence

- implement `assign`
- implement `relane`
- implement `reprioritize`
- implement `rename`
- implement `join`
- implement `depend add/remove`
- implement `progress`
- implement `reopen`

Phase F: Lens and Context

- implement `.v/` generation
- prove `.v/blocked` is derived from `depends_on`
- implement `ctx` stdout
- implement `ctx --write .v/ctx.md`

Phase G: Later Storage and Migration

- implement `compact` only after archive behavior is accepted
- implement `restore` only after archive behavior is accepted
- specify atomic `retype` before implementation
- do not implement partial kind migration

Phase H: v1 Comparison

- compare speed, clarity, and error quality against v1 helper scripts
- decide whether v2 stays experimental, ships optional, or begins migration planning

## 12. Design Gates

Gate 1: Name and Surface

- product name is `agtask`
- primary binary is `agtask`
- secondary binary aliases are rejected

Gate 2: Grammar

- issue path grammar is final for MVP
- review path grammar is final for MVP
- progress path grammar is final for MVP
- path-derived fields are forbidden from frontmatter
- `cnl` is the only cancelled/not-now state
- archive is not a state slot

Gate 3: Validation

- exit codes are stable
- error codes are stable enough for tests
- `check --changed` relation expansion is defined
- warnings cannot hide errors

Gate 4: Generated Outputs

- `.v/` behavior is final
- `ctx` behavior is final
- `views/` is either deferred or specified

Gate 5: Implementation Start

- examples cover valid and invalid grammar
- `SPEC.md` has no unresolved Build Now blockers
- Rust skeleton can begin without changing product design

## 13. Current Decisions

Decided:

- Product name is `agtask`.
- Primary binary is `agtask`.
- v1 remains production and is not migrated in place.
- v2 remains isolated under `v2/`.
- Files remain truth.
- `.v/` and context snapshots are generated.
- SQLite is deferred.
- Server, daemon, sync, and Linear integration are out of scope.
- Review outcome belongs in review filename.
- Progress has no independent state slot in v2 MVP.
- Secondary binary aliases such as `tk` are rejected from the official contract.
- `cand` and `arvd` are rejected from the MVP state set.
- `risk` and `memory` are rejected from MVP frontmatter.
- `.v/blocked` is generated only by reversing `depends_on`.

Open:

- Whether v2 should include read-only v1 parsing before mutation.
- Whether progress grammar needs owner or timestamp fields later.

## 14. Next Design Work

Before coding, resolve:

1. Frontmatter strictness: unknown keys warn forever, or become errors after MVP.
2. Example coverage: add cycle, no owner, missing acceptance, and illegal move examples.

## 15. Design Axioms

Axioms are stronger than preferences. Any new feature must fit them or explicitly change them through a decision record.

A1. Files are the ledger.

`issues/`, `docs/reviews/`, and `docs/progress/` are the only workflow truth surfaces in MVP.

A2. Generated views are disposable.

`.v/` and context snapshots must be rebuildable from truth files.

A3. Command output is API.

`agtask ls --tsv`, error codes, and exit codes are external contracts. Do not casually change them after implementation starts.

A4. Mutation is command-mediated.

All Build Now mutation must go through `agtask` commands. Each mutator changes exactly one named truth slot, one named frontmatter field, or creates one truth evidence file. Manual hand-renaming is outside the contract.

A5. Body is not index.

Markdown body may hold work content and acceptance criteria. High-frequency workflow fields must come from path, filename, or frontmatter.

A6. Pre-commit must be incremental.

The common commit path must use `agtask check --changed` and must not require full repository body scans.

A7. No hidden service.

`agtask` must not require a daemon, server, watcher, background process, or network service.

## 16. Rejected Designs

Rejected for MVP:

- SQLite or embedded database as truth.
- Daemon, server, or background watcher.
- Linear, Notion, GitHub Issues, or other bidirectional sync.
- YAML view DSL.
- Review as issue state.
- Progress state slot.
- `cand` as a state name.
- `arvd` as a state slot.
- `risk` or `memory` as MVP frontmatter keys.
- `blocks` or `blocked_by` as frontmatter relation truth.
- Root-level permanent `ctx.md`.
- Duplicating `id`, `state`, `priority`, `lane`, or `slug` in frontmatter.
- Secondary binary alias such as `tk`.
- Full workflow engine with scheduling, milestones, or orchestration.
- In-place v1 migration.

These can be reconsidered only through decision records and after the MVP proves the core file grammar.

## 17. Core Workflows

Pre-commit flow:

```text
git staged paths
  -> agtask check --changed <paths>
  -> errors block commit
  -> warnings print separately
```

Agent context flow:

```text
agtask ctx
  -> agent reads compact current world
  -> agent opens exact issue/review/progress files by id
```

Claim and close flow:

```text
agtask ls --tsv
  -> choose issue
  -> agtask move <id> doi
  -> work and record evidence
  -> agtask move <id> dne
```

Review block flow:

```text
review file with .block.md
  -> agtask check reports active block
  -> agtask move <id> dne fails close-readiness
  -> business side removes or renames .block.md when no longer blocking
```

Large repo flow:

```text
agtask ls --tsv for table stream
agtask ctx for LLM summary
agtask check --changed for commit path
agtask check for periodic full audit
```

## 18. Invariants

- One live issue id maps to at most one issue file.
- `move` changes only the state slot.
- Blocking review prevents `dne`.
- Progress has no independent state slot in MVP.
- `.v/` can be deleted and regenerated.
- `ctx` can be regenerated.
- Generated paths are not accepted as truth inputs to `--changed`.
- Path-derived fields are forbidden in frontmatter.
- `.v/blocked` is generated only by reversing `depends_on`.
- `move <id> dne` runs close-readiness before renaming.
- `agtask check` separates errors and warnings.
- v2 must not mutate v1 projects.

## 19. Change Policy

Grammar changes require:

- `DESIGN.md` decision record update.
- `SPEC.md` grammar update.
- Example updates for valid and invalid cases.
- PRD impact note if user workflow changes.
- No v1 production impact.

Command output changes require:

- SPEC update.
- Example or snapshot update.
- migration note if scripts may depend on old output.

Build Now scope changes require:

- explicit move between Build Now and Later lists.
- updated phase and gate impact.
- rejection reason if the change adds platform-like behavior.

## 20. Build Now and Later

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
- atomic retype / kind migration

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

MVP state set:

```text
cnl
tdo
doi
bkd
dne
```

## 21. Decision Records

### D001: Product name is agtask

Status: accepted

Reason: short, CLI-friendly, and specific to agent task workflow without overloading the v1 skill name.

### D002: Primary binary is agtask

Status: accepted

Reason: product name and executable should match. A secondary alias adds another public entrypoint without adding workflow power.

### D003: No secondary binary alias

Status: accepted

Reason: `agtask` is short enough, searchable, and explicit. `tk` creates a second contract and conflicts semantically with `tkNNNN` task ids.

### D004: v2 stays isolated under v2/

Status: accepted

Reason: v1 is production. v2 is an experimental product line and must not replace v1 until gates are complete.

### D005: SQLite is deferred

Status: accepted

Reason: the first performance step is filename/frontmatter streaming plus `check --changed`; database cache is only justified after profiling.

### D006: Review is evidence, not issue state

Status: accepted

Reason: review outcome belongs in review filenames. Adding `rev` as an issue state would create state inflation.

### D007: Progress has no independent state slot

Status: accepted

Reason: progress is evidence. Parent task state determines whether evidence is active or closed.

### D008: Generated markdown views are deferred

Status: accepted

Reason: `.v/` and `ctx` prove the lens model first. `views/*.md` can be added later if repeated human-readable reports are still needed.

### D009: Use state, not status

Status: accepted

Reason: the filename slot is a lifecycle state, not a generic status label. TSV headers and errors must use `state`.

### D010: Use cnl, not cand

Status: accepted

Reason: `cand` reads like candidate backlog. `cnl` clearly means cancelled, dropped, or not-now and stays outside the active required graph.

### D011: Archive is path, not state

Status: accepted

Reason: archive is storage temperature. It must not replace the final business state in the filename.

### D012: Header fields stay consumed and small

Status: accepted

Reason: `risk` and `memory` have no MVP consumer and invite header drift. MVP frontmatter keeps only `owner`, `threads`, `depends_on`, `tags`, and `links`.

### D013: Blocked lens is derived from depends_on

Status: accepted

Reason: `blocks` would duplicate `depends_on`. `.v/blocked/<blocking-id>/<blocked-id>` is a generated reverse projection only.

### D014: Owner is responsibility, threads are evidence

Decision: `owner` names the responsible role/person/email. `threads` records participating agent thread ids.

Reason: responsibility should stay human-friendly; trace evidence should stay append-only and non-authoritative. Mixing them makes ownership unreadable.

### D015: `new` is in Build Now

Decision: `agtask new` is part of Build Now.

Reason: if the tool owns grammar, it must own file creation. Manual creation would keep the highest-error step outside the guardrail.

### D016: Id-preserving slot mutators are in Build Now

Decision: `relane`, `reprioritize`, and `rename` are separate commands.

Reason: each command changes one path slot while preserving the issue id. Kind migration is post-MVP because kind is part of the primary id and requires reference migration.

### D017: Review process is outside agtask

Decision: `agtask` has no review command and no pass/latest-outcome state machine.

Reason: review is business workflow. `agtask` only recognizes `.block.md` as close-blocking evidence.

### D018: Compact and restore are storage-temperature operations

Decision: `compact` moves cold `dne/cnl` issues to `archive/issues/`; `restore` moves them back.

Reason: archive is not a lifecycle state. It is cold storage that reduces hot working-set cost.

### D019: Tags and links are fields, not Build Now workflows

Decision: `tags` and `links` are accepted and checked, but `tag` and `link` mutators are deferred.

Reason: both are useful for projection and release slices, but neither is required to make the core ledger safe.

### D020: TSV stays small by counting heavy fields

Decision: `agtask ls --tsv` exposes `thread_count` and `link_count`, not full thread/link arrays.

Reason: TSV is the Unix projection surface. Heavy values remain in the issue file and are read on demand.
