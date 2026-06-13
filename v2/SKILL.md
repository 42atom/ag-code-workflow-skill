---
name: agtask
description: "Experimental v2 skill for designing and eventually implementing agtask, a Rust-based file-native task workflow. Use when working on agtask v2 design, grammar, CLI contract, examples, Rust implementation planning, or migration boundaries. This skill is isolated under v2/ and must not replace agata-code-workflow v1 until the v2 design gates are complete."
---

# agtask

Status: active v2 skill draft, updated 2026-06-13. Supersedes earlier agtask v2 drafts; do not implement from older copies.

## Status

This is an experimental v2 skill draft.

It lives in `v2/` on purpose. Do not install, publish, or use it as a replacement for `agata-code-workflow/` until the v2 design gates are complete.

Current stage:

```text
design planning
```

Default action:

```text
refine design, spec, examples, and decision gates before implementation
```

## Product Contract

`agtask` is a local-first, Rust-based, file-native task workflow.

It keeps this source-of-truth model:

```text
issues/ = workflow truth
docs/reviews/ = review evidence
docs/progress/ = progress evidence
.v/ = disposable generated lens
ctx = disposable generated LLM snapshot
```

Rust is only the parser, validator, projector, context generator, and safe rename layer.

Do not introduce:

- database truth
- daemon
- server
- scheduler
- Linear or Notion sync
- multi-agent orchestration platform
- generated view as authority

## Required Reading

Read only the file needed for the task:

- `DESIGN.md`: product shape, design thesis, phases, gates, current decisions, open questions.
- `PRD.md`: goals, non-goals, user stories, success criteria, rollout boundaries.
- `SPEC.md`: implementation contract for grammar, CLI, exit codes, errors, checks, move, lens, ctx, examples.
- `examples/README.md`: example layout and test expectations.

Routing:

- For product or architecture discussion, read `DESIGN.md`.
- For scope, user stories, or phase planning, read `PRD.md`.
- For Rust implementation, parser/check/move/lens/ctx behavior, read `SPEC.md`.
- For test planning or sample data, read `examples/README.md` and the relevant example.

## Hard Boundaries

Keep v1 and v2 separate:

```text
agata-code-workflow/ = production v1 skill
v2/ = agtask experimental product line
```

Do not edit v1 files while working on agtask unless the user explicitly asks for v1 documentation changes.

Do not migrate v1 projects in place.

Do not make v2 discoverable as the default workflow skill until:

- product name and command surface are final
- grammar gates are closed
- examples cover valid and invalid contracts
- Rust MVP exists
- v1 comparison is complete
- migration plan has dry-run, apply, and rollback paths

## Design Rules

Use this model:

```text
path + filename = hot truth
frontmatter = cold truth
body = work content
generated views = disposable lens
Rust = fast and strict projection layer
```

Hot truth:

```text
lane
id
state
priority
slug
```

Cold truth:

```text
owner
threads
depends_on
tags
links
```

Do not duplicate path-derived fields in frontmatter.

## Build Now and Later

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

Implement in this order:

1. Build Now.
2. Later only after archive behavior and atomic retype are separately accepted.

Every Build Now command must either:

- read truth
- validate truth
- rename truth
- generate disposable projection

Later commands must not change the truth model.

## Implementation Discipline

Before writing Rust:

1. Check `DESIGN.md` open questions.
2. Check `SPEC.md` for the exact contract.
3. Add or update examples before implementing behavior.
4. Keep all implementation under `v2/`.
5. Do not touch v1 production helper scripts.

Rust implementation order:

```text
CLI skeleton
project root discovery
issue path parser
frontmatter parser
new
ls --tsv
full check
review/progress parsers
move
id-preserving slot mutators
assign/join/depend/progress
reopen
compact/restore
check --changed
lens
ctx
performance comparison
```

## Output Discipline

When answering about agtask, separate:

```text
Decided
Open
Next design work
```

When editing docs, keep the same boundary:

```text
PRD.md = why and what
DESIGN.md = product shape and gates
SPEC.md = exact implementation contract
examples/ = executable examples
SKILL.md = agent entrypoint
```

Do not turn `SKILL.md` into the full spec. Link to the right document instead.
