# SPEC: agtask Rust Build Now

Status: active v2 implementation contract, updated 2026-06-13. Supersedes earlier agtask v2 drafts; do not implement from older copies.

## 1. Purpose

This document is the implementation contract for the v2 Rust Build Now surface, plus Later boundaries that must not be implemented accidentally.

`PRD.md` explains why v2 exists. This file defines what an implementation must parse, print, reject, rename, and generate.

v2 remains isolated from the v1 production skill. Nothing in this directory changes the current `ag-code-workflow/` contract.

## 2. System Boundary

Source of truth:

```text
issues/
archive/issues/
docs/reviews/
docs/progress/
```

Generated, disposable outputs:

```text
.v/
.v/ctx.md
```

Reserved future generated outputs:

```text
.v/graph.nodes.tsv
.v/graph.edges.tsv
```

The Rust binary may read generated outputs only for cleanup or overwrite decisions. It must not treat them as authoritative workflow state.

## 3. CLI Binary

Primary binary:

```text
agtask
```

Product command surface:

```text
Build Now:
agtask new <kind> <lane> <slug> <priority>
agtask ls [--tsv]
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
agtask ctx [--write <path>]

Later:
agtask compact <id>
agtask restore <id>
agtask retype <id> <kind>
```

All commands must resolve the project root by walking upward from the current working directory until an `issues/` directory is found.

If no project root is found, fail with `E_ROOT`.

## 4. Exit Codes

```text
0 = success
1 = validation failed or workflow invariant blocked the action
2 = usage error
3 = project root not found
4 = I/O error
5 = internal bug
```

No command may fail with an unclassified shell-style or signal-style code. The process must catch top-level errors and map them to this table.

## 5. Output Streams

Normal command results go to stdout.

Errors and warnings go to stderr.

`agtask check` format:

```text
errors:
error[E001] issues/runtime/tk1828.foo.p1.runner.md: invalid state "foo"; expected cnl|tdo|doi|bkd|dne

warnings:
warn[W001] issues/runtime/tk1828.doi.p1.runner.md: doi issue has no recent progress evidence
```

If there are no warnings, omit the `warnings:` section.

If there are no errors, `agtask check` prints:

```text
ok
```

## 6. Error Codes

Initial error code set:

```text
E_ROOT    project root not found
E_USAGE   invalid CLI arguments
E_IO      filesystem read/write/rename error
E_PARSE   file path or frontmatter parse failed
E001      invalid issue path grammar
E002      invalid issue id
E003      invalid state
E004      invalid priority
E005      invalid lane
E006      duplicate issue id
E007      missing dependency target
E008      dependency cycle
E009      active issue missing owner
E010      p0/p1 issue missing acceptance criteria
E011      blocking review prevents done
E012      move target is ambiguous
E013      illegal state transition
E014      generated path used as truth input
E015      target path already exists
E016      invalid owner
E017      invalid thread id
E018      invalid tag
E019      invalid link
E020      operation not allowed for current state
E021      dependency target not done
```

Initial warning code set:

```text
W001      doi issue has no recent progress evidence
W002      dne issue has open progress evidence
W003      unknown frontmatter key
W004      large context snapshot
W005      stale doi issue
```

Warnings must never block `agtask move` unless the same condition also has an error code.

## 7. Issue Path Grammar

Canonical issue path:

```text
issues/<lane>/<id>.<state>.<priority>.<slug>.md
```

Regex:

```text
^issues/(?P<lane>[a-z][a-z0-9-]{1,39})/(?P<id>(tk|pl|rs|rf)[0-9]{4,6})\.(?P<state>cnl|tdo|doi|bkd|dne)\.(?P<priority>p[0-3])\.(?P<slug>[a-z0-9][a-z0-9-]{1,79})\.md$
```

Rules:

- `lane` is lowercase kebab-case.
- `id` kind is `tk`, `pl`, `rs`, or `rf`.
- `id` number is 4 to 6 digits.
- `kind` is the id prefix; it is part of the primary key.
- `lane` is domain, module, or workstream; it is not kind.
- `state` is one of the allowed states.
- `priority` is `p0`, `p1`, `p2`, or `p3`.
- `slug` is lowercase kebab-case.
- No underscores.
- No uppercase letters.
- No spaces.
- No path nesting below lane in the MVP.

Valid examples:

```text
issues/runtime/tk1828.doi.p1.runner-slash-input.md
issues/docs/tk1830.tdo.p2.cleanup-install-docs.md
issues/planning/pl1831.cnl.p3.add-roadmap-view.md
```

Invalid examples:

```text
issues/tk1828.doi.runtime.runner.p1.md
issues/runtime/tk1828.rev.p1.runner.md
issues/runtime/tk1828.doi.high.runner.md
issues/runtime/tk1828.doi.p1.Runner.md
issues/runtime/1828.doi.p1.runner.md
```

## 8. State Model

Allowed states:

```text
cnl  = cancelled, dropped, or not-now; outside the active required graph
tdo  = todo / pending required work
doi  = doing / actively claimed work
bkd  = blocked after work started
dne  = done / closed
```

Active execution states:

```text
tdo
doi
bkd
```

Closed states:

```text
dne
cnl
```

Review is not a task state in the MVP. Do not introduce `rev`.

Archive is not a task state. Cold storage uses the archive path while preserving the final business state:

```text
archive/issues/<lane>/<id>.<state>.<priority>.<slug>.md
```

Default `agtask check` must parse archive issue filenames enough to validate grammar and extract ids. A malformed archive issue filename is `E001`; id allocation and restore cannot be trustworthy if archive filenames are skipped.

## 9. Frontmatter Contract

Frontmatter is optional for `cnl` and `dne`, but recommended.

Frontmatter is required for `tdo`, `doi`, and `bkd`.

Allowed keys:

```text
owner: string
threads: list<string>
depends_on: list<string>
tags: list<string>
links: list<string>
```

Forbidden frontmatter keys:

```text
id
state
status
priority
lane
slug
blocks
blocked_by
risk
memory
```

If a forbidden key appears, `agtask check` must fail with `E_PARSE`.

`owner` is the responsibility identity. It can be an agent name, role name, team token, or external collaborator identity.

Owner regex:

```text
^[A-Za-z0-9._@+-]{1,80}$
```

`threads` is a participating thread set, not an event log.

Thread id regex:

```text
^[A-Za-z0-9:._@/+~-]{1,160}$
```

Thread rules:

- dedupe
- preserve first-seen order
- no repeated thread ids
- only active states `tdo`, `doi`, and `bkd` may append threads
- multiple participation events belong in progress, review, or body evidence

Supported YAML subset:

```yaml
owner: cal
threads: [thread:019dd9af]
depends_on: [tk1820, tk1819]
tags: [runner, cli]
links: []
```

The Rust implementation may use a real YAML parser. If it does, it must still enforce this subset for v2 files.

Empty value rules:

- Missing `owner` is empty.
- Missing lists are empty lists.
- `[]` is an empty list.
- Inline arrays and block arrays are accepted.
- Multiline scalar values are rejected in MVP frontmatter.

Unknown keys produce `W003` in MVP, not an error, unless they are forbidden path-derived keys.

## 10. Body Contract

Markdown body is freeform except for acceptance detection.

Acceptance exists if the body contains a level-2 heading named `Acceptance` and at least one list item under it.

Accepted headings:

```text
## Acceptance
## Accept
## 验收
```

`p0` and `p1` issues in `tdo`, `doi`, or `bkd` must have acceptance criteria. Missing acceptance is `E010`.

## 11. Review Block Evidence

`agtask` does not manage review workflow and does not provide a review command.

It only recognizes review block files as close blockers.

Review persistence boundary:

- Transient review feedback is chat-level correction and is not persisted by `agtask`.
- Decision-grade review evidence may be persisted by business workflow.
- `agtask` only treats `.block.md` review evidence as close-blocking.
- There is no command that turns chat or nit feedback into a review file in MVP.

Blocking review path:

```text
docs/reviews/<issue-id>.*.block.md
```

Regex:

```text
^docs/reviews/(?P<id>(tk|pl|rs|rf)[0-9]{4,6})\..*\.block\.md$
```

Any matching `.block.md` prevents `agtask move <id> dne`.

There is no `latest outcome wins`, no mandatory `pass`, and no override in MVP. Business-side review tooling may create, rename, or remove review evidence; `agtask` only guards close readiness.

## 12. Progress Grammar

Canonical progress path:

```text
docs/progress/<issue-id>.s<step>-<slug>.md
```

Regex:

```text
^docs/progress/(?P<id>tk[0-9]{4,6})\.s(?P<step>[0-9]{2})-(?P<slug>[a-z0-9][a-z0-9-]{1,79})\.md$
```

Progress has no independent state slot in v2 MVP.

Progress is evidence. Parent task state determines whether progress is active or closed.

`agtask progress <id> <sNN-slug>` creates a markdown body template only:

```md
# sNN-slug

## Notes

TODO
```

Progress files have no frontmatter in MVP.

## 13. TSV Projection

Command:

```text
agtask ls --tsv
```

Header:

```text
id	state	priority	lane	slug	owner	thread_count	depends_on	tags	link_count	blocking_review	open_progress	path
```

Column rules:

- Fields are tab-separated.
- Header is always printed.
- Rows are sorted by `priority`, then `state`, then `id`, then `path`.
- Empty scalar field is empty string.
- Empty list field is empty string.
- Non-empty list field is comma-separated with no spaces.
- Boolean fields use `yes` or `no`.
- Paths are project-root relative with `/` separators.
- `thread_count` is numeric; full thread ids stay in the issue file.
- `link_count` is numeric; full links stay in the issue file.

Example:

```text
id	state	priority	lane	slug	owner	thread_count	depends_on	tags	link_count	blocking_review	open_progress	path
tk1828	doi	p1	runtime	runner-slash-input	cal	2	tk1820,tk1819	runner,cli	1	no	yes	issues/runtime/tk1828.doi.p1.runner-slash-input.md
```

`agtask ls` without `--tsv` may print a compact human table, but tests should target `--tsv`.

## 14. Check

Command:

```text
agtask check
agtask check --changed <path>...
```

Full check scans:

```text
issues/
docs/reviews/
docs/progress/
```

Default full check scans `archive/issues/` filenames for grammar validity and id uniqueness only.

Full check ignores:

```text
.v/
views/
target/
.git/
```

`--changed` accepts project-root relative paths or absolute paths inside the project root.

`--changed` path handling:

- If a changed path is under `issues/`, parse that issue and load directly referenced dependency target filenames.
- If a changed path is under `docs/reviews/`, parse that review and load the parent issue.
- If a changed path is under `docs/progress/`, parse that progress file and load the parent task.
- If a changed path is generated output, fail with `E014`.
- If no changed path is a truth path, print `ok` without full scan.

Fast relation expansion:

- To check duplicate ids, scan issue filenames only.
- To check missing dependency target, scan issue filenames only.
- To check blocking review for a changed issue or move-to-done candidate, scan review filenames for that issue.
- To check progress evidence for a changed issue, scan progress filenames for that issue.

Full dependency-cycle auditing belongs to `agtask check`, not to `agtask check --changed`.

The implementation must avoid reading unrelated markdown bodies in `--changed` mode. Do not add a second `--strict` changed mode in MVP; full check is the strict path.

## 15. Move

Command:

```text
agtask move <id> <state>
```

Lookup:

- Find exactly one live issue with matching `id`.
- If zero found, fail `E012`.
- If more than one found, fail `E006`.

Rename rule:

- Only the `state` slot changes.
- Lane, id, priority, and slug remain unchanged.
- Parent directory remains unchanged.

Transition matrix:

```text
cnl  -> tdo  allowed
cnl  -> doi  forbidden
cnl  -> bkd  forbidden
cnl  -> dne  forbidden

tdo  -> cnl allowed
tdo  -> doi  allowed
tdo  -> bkd  forbidden
tdo  -> dne  forbidden

doi  -> tdo  allowed
doi  -> bkd  allowed
doi  -> dne  allowed if close-ready
doi  -> cnl forbidden

bkd  -> doi  allowed
bkd  -> tdo  allowed
bkd  -> dne  forbidden
bkd  -> cnl forbidden

dne  -> doi  forbidden; use `agtask reopen`
dne  -> tdo  forbidden
dne  -> bkd  forbidden
dne  -> cnl forbidden
```

Illegal transitions fail with `E013`.

`move` does not accept owner or thread flags. Claiming work is explicit:

```text
agtask assign <id> <owner>
agtask join <id> --thread-id <thread>
agtask move <id> doi
```

`move <id> dne` must run a close-readiness subset before renaming.

Close-readiness requirements:

- no matching `.block.md` review file exists
- owner is present
- p0/p1 issue has acceptance criteria
- every `depends_on` target exists and is `dne`

`move <id> dne` fails with `E011` for blocking review, `E009` for missing owner, `E010` for missing acceptance, `E007` for missing dependency target, and `E021` for dependency target that exists but is not `dne`.

## 16. New Issue

Command:

```text
agtask new <kind> <lane> <slug> <priority> [--owner <owner>] [--thread-id <thread>] [--depends-on <id>]...
```

ID allocation:

- `tk`, `pl`, `rs`, and `rf` share one global numeric namespace.
- Allocate the next id by scanning live and archive issue filenames.
- Use a local `.agtask-new.lock` file for local concurrent creation.
- Do not introduce a daemon or distributed allocator.

Owner source:

```text
--owner > AGTASK_OWNER > error E009
```

Thread source:

```text
--thread-id > AGTASK_THREAD_ID > omit
```

`--depends-on` is repeatable and targets must exist.

New issue state is `tdo`.

Template:

```md
---
owner: cal
threads:
  - thread:019dd9af
depends_on: []
tags: []
links: []
---
# runner slash input

## Why

TODO

## Acceptance

- TODO
```

## 17. Safe Single-Slot Mutators

Every mutator changes only its named slot and performs only command-local checks.

Commands:

```text
agtask assign <id> <owner>
agtask relane <id> <lane>
agtask reprioritize <id> <priority>
agtask rename <id> <slug>
```

Rules:

- `assign` changes only `owner`.
- `relane` changes only lane.
- `reprioritize` changes only priority.
- `rename` changes only slug.
- all commands fail if target path already exists.

Kind migration is not an MVP command. Kind is part of the issue id, so changing `rs0031` to `pl0031` is primary-key migration, not a simple filename-slot edit. Post-MVP `agtask retype` may be added only as a separate atomic migration feature, not as a slot mutator.

Lane is domain, module, or workstream. It is not issue kind.

## 18. Thread Join

Command:

```text
agtask join <id> [--thread-id <thread>]
```

Thread source:

```text
--thread-id > AGTASK_THREAD_ID > error E017
```

`join` only appends to `threads`, dedupes, and preserves first-seen order.

`join` is allowed only for `tdo`, `doi`, and `bkd`. It is forbidden for `dne` and `cnl`.

`join` must not change owner.

## 19. Dependency Mutator

Commands:

```text
agtask depend <id> add <dep>
agtask depend <id> remove <dep>
```

Rules:

- `add` requires target exists.
- `add` rejects duplicates.
- `add` rejects dependency cycles.
- `remove` requires the dependency exists in the current list.
- the command changes only `depends_on`.

## 20. Reopen

Command:

```text
agtask reopen <id> [--owner <owner>] [--thread-id <thread>] [--reason <text>]
```

Rules:

- only `dne -> doi`
- `cnl` cannot reopen
- owner source is `--owner > AGTASK_OWNER > keep existing owner`
- thread source is `--thread-id > AGTASK_THREAD_ID > no append`
- threads append and dedupe
- reason is optional

If `--reason` is present, append to body:

```md
## Reopen Log

- thread:019dd9af: regression found
```

If any matching `.block.md` exists, include the latest block review path in the log when writing a log entry.

## 21. Compact and Restore

Commands:

```text
agtask compact <id>
agtask restore <id>
```

`compact` moves a closed live issue into cold storage:

```text
issues/<lane>/<id>.<state>.<priority>.<slug>.md
-> archive/issues/<lane>/<id>.<state>.<priority>.<slug>.md
```

`restore` moves it back without changing basename, state, or frontmatter.

Rules:

- `compact` only allows `dne` and `cnl`.
- `compact` fails if archive target exists.
- `restore` fails if live target exists.
- neither command changes frontmatter.

## 22. Lens

Command:

```text
agtask lens
```

Output root:

```text
.v/
```

Required directories:

```text
.v/state/<state>/<id>
.v/pri/<priority>/<id>
.v/lane/<lane>/<id>
.v/owner/<owner>/<id>
.v/tag/<tag>/<id>
.v/blocked/<blocking-id>/<id>
.v/review-block/<id>
```

`.v/blocked/<blocking-id>/<blocked-id>` is generated only by reversing `depends_on`. Do not add `blocks` or `blocked_by` frontmatter as a second relation truth source.

Generation strategy:

- Parse and check truth files first.
- If validation fails, do not alter existing `.v/`.
- Build a temporary `.v.tmp.<pid>/`.
- Replace `.v/` after successful generation.
- Use relative symlinks when supported.
- If symlink creation fails, create pointer files containing one project-root relative target path plus trailing newline.

Pointer file format:

```text
issues/runtime/tk1828.doi.p1.runner-slash-input.md
```

The lens must contain no derived facts that cannot be regenerated from truth files.

## 23. Context Snapshot

Command:

```text
agtask ctx
agtask ctx --write .v/ctx.md
```

Default behavior prints markdown to stdout.

`--write` may only write under `.v/` in MVP. Writing to `ctx.md` at project root is forbidden in MVP.

Required sections:

```text
# Context
## Active P1
## Blocked
## Review Blocks
## Stale DOI
## Recent Done
```

Ordering:

- Active P1: `p0`, then `p1`, then id.
- Blocked: blocking id, then blocked id.
- Review Blocks: issue id, then latest block path.
- Stale DOI: best-effort evidence age descending, then id.
- Recent Done: best-effort modified time descending, max 20.

`ctx` must not invent summary state. Every row must be derivable from parsed files.

Stale and recent sections are heuristics for orientation, not audit truth. Prefer latest progress/review evidence time when available; issue file mtime is a fallback only.

### Future workflow graph boundary

A future workflow graph index may write generated files under `.v/` only:

```text
.v/graph.nodes.tsv
.v/graph.edges.tsv
```

This is not part of Build Now.

Rules:

- The graph index is navigation only.
- The graph index must be rebuildable from `issues/`, `docs/reviews/`, and `docs/progress/`.
- The graph index must not override filename state, owner, dependencies, review blocks, or progress evidence.
- Generated graph paths are not accepted as truth inputs to `agtask check --changed`.
- No daemon, watcher, auto-sync process, or hidden service maintains the graph in MVP.
- Whole-code symbol graphs, call graphs, CodeGraph-style indexing, and codedb-style indexing are references only. `agtask` must not depend on them.

If a future edge format is accepted, each edge must identify its evidence source:

```text
src_id	edge_type	dst_id	evidence_path	evidence_hash
```

## 24. Example Layout

Required example roots:

```text
v2/examples/valid/basic/
v2/examples/invalid/bad-filename/
v2/examples/invalid/duplicate-id/
v2/examples/invalid/missing-dependency/
v2/examples/invalid/blocking-review/
v2/examples/invalid/dependency-cycle/
v2/examples/invalid/no-owner/
v2/examples/invalid/missing-acceptance/
v2/examples/invalid/illegal-move/
v2/examples/large/
```

Example rule:

- Valid examples must pass `agtask check`.
- Invalid examples must fail with the expected error code.
- Large examples are generated or checked in only if size is reasonable.
- Example files should be plain markdown, not snapshots from v1.

## 25. Test Contract

Rust tests should cover:

- Path parser accepts valid issue paths.
- Path parser rejects invalid issue paths with exact error codes.
- Frontmatter parser rejects path-derived duplicate truth keys.
- `ls --tsv` output is deterministic.
- `check` reports errors and warnings separately.
- `check --changed` does not read unrelated issue bodies.
- `move` changes only the state slot.
- `move <dne-id> doi` is rejected; `reopen` is the only done-to-doing path.
- `move dne` is blocked by close-readiness failures.
- id-preserving slot mutators change only their named slot.
- `new` allocates ids from the global numeric namespace.
- `lens` is rebuildable from truth.
- `ctx` writes stdout by default and `.v/ctx.md` only when requested.

Later tests should cover:

- `compact` and `restore` preserve basename and state.
- `retype` is specified as atomic primary-key migration before implementation.

No test may depend on network, external services, a daemon, or global machine state.

## 26. Contract Invariants

Implementation must enforce these invariants:

- One live issue id maps to at most one issue file.
- Live plus archive issue ids are globally unique.
- `move` changes only the state slot.
- Blocking review prevents `dne`.
- Progress has no independent state slot in MVP.
- `.v/` can be deleted and regenerated.
- `ctx` can be regenerated.
- Future `.v/graph.*` indexes can be deleted and regenerated.
- Generated paths are not accepted as truth inputs to `--changed`.
- Path-derived fields are forbidden in frontmatter.
- `check` separates errors and warnings.
- `threads` is a deduped participating thread set, not an event log.
- Transient review feedback is not workflow truth.
- v2 must not mutate v1 projects.

## 27. Build Now and Later

Build Now:

```text
agtask new <kind> <lane> <slug> <priority>
agtask ls [--tsv]
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
agtask ctx [--write <path>]
```

Later:

```text
agtask compact <id>
agtask restore <id>
agtask retype <id> <kind>
```

Rejected commands and surfaces:

```text
agtask batch-close
agtask review
agtask tag
agtask link
views/*.md
SQLite cache
v1 migration
web UI
external sync
daemon/server
milestone/scheduling commands
secondary binary aliases
```

Rejected items must not appear in Build Now tests except as explicit rejection cases.

## 28. Change Policy

Grammar changes require:

- DESIGN decision record update.
- SPEC grammar update.
- Example update for accepted and rejected cases.
- PRD note if user workflows change.
- No v1 production impact.

Command output changes require:

- SPEC output contract update.
- Tests or examples that prove the new output.
- Compatibility note if shell pipelines may break.

Scope changes require:

- item moved between Build Now and Later.
- updated implementation order if needed.
- explicit rejection of platform behavior if the item resembles sync, server, scheduler, or orchestration.

## 29. Performance Measurement

Benchmark commands:

```text
agtask check
agtask check --changed <one issue>
agtask ls --tsv
agtask lens
agtask ctx
```

Report:

```text
example	files	command	wall_ms	bytes_read
```

Build Now target:

```text
2k files: check --changed < 1000 ms, full check < 2000 ms
6k files: check --changed < 1000 ms, full check < 5000 ms
20k files: check --changed < 1000 ms, full check < 15000 ms
```

If full check exceeds target, do not add SQLite first. Profile parser, directory walk, frontmatter reads, and dependency graph construction first.

## 30. Migration Boundary

v2 Build Now must not mutate a v1 project.

Future v1 support can be added in this order:

1. Read-only v1 parser.
2. v1-to-v2 dry-run migration report.
3. v1-to-v2 generated sample copy.
4. reversible migration script.

No in-place migration before the user explicitly accepts the migration plan.

## 31. Implementation Order

Build Now:

1. CLI skeleton and exit code mapping.
2. Project root discovery.
3. Issue path parser.
4. Frontmatter parser.
5. `new`.
6. `ls --tsv`.
7. Full `check`.
8. `check --changed`.
9. `move`.
10. `assign`.
11. `relane`.
12. `reprioritize`.
13. `rename`.
14. `join`.
15. `depend add/remove`.
16. Review/progress parsers.
17. `progress`.
18. `reopen`.
19. `lens`.
20. `ctx`.

Later:

21. `compact` and `restore`.
22. Specify atomic `retype` before implementation.

Cross-cutting:

23. Performance examples and comparison.
