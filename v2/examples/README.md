# agtask Examples

These fake data sets are the executable contract for agtask.

Rules:

- Each example root is independent.
- Each invalid example should express one primary failure.
- Tests copy an example root to a temp directory and run the real CLI.
- Do not mock filesystem behavior.
- Generated paths under `.v/` are never truth inputs.

## Valid examples

| Path | Expected |
|---|---|
| `valid/basic` | `agtask check` passes; `agtask ls --tsv` emits one issue. |
| `valid/dependencies` | `agtask check` passes; dependency target exists and is `dne`. |
| `valid/review-block` | `agtask check` passes; `agtask move tk0001 dne` fails with `E011`. |
| `valid/progress` | `agtask check` passes; progress parent exists. |
| `valid/threads` | `agtask check` passes; threads dedupe/order behavior can be tested. |
| `valid/reopen` | `agtask reopen tk0001` can move `dne -> doi`. |

## Invalid examples

| Path | Primary expected failure |
|---|---|
| `invalid/bad-filename` | `E003` invalid state. |
| `invalid/duplicate-id` | `E006` duplicate issue id. |
| `invalid/missing-owner` | `E009` active issue missing owner. |
| `invalid/missing-acceptance` | `E010` p0/p1 issue missing acceptance criteria. |
| `invalid/missing-dependency` | `E007` missing dependency target. |
| `invalid/unresolved-dependency` | `E021` dependency target not done. |
| `invalid/dependency-cycle` | `E008` dependency cycle. |
| `invalid/blocking-review` | `E011` blocking review prevents done. |
| `invalid/illegal-move` | `agtask move tk0001 dne` fails with `E013`. |
| `invalid/forbidden-frontmatter` | `E_PARSE` forbidden path-derived frontmatter. |
| `invalid/progress-bad-parent` | progress parent issue missing. |
| `invalid/changed-generated-path` | `agtask check --changed .v/status/doi/tk0001` fails with `E014`. |

## Command contract examples

Build Now command tests should cover:

- `new`: allocates next global id and writes canonical frontmatter.
- `move`: changes only the state slot.
- `assign`: changes only `owner`.
- `relane`: changes only lane path.
- `reprioritize`: changes only priority slot.
- `rename`: changes only slug slot.
- `join`: appends only to `threads`, deduped in first-seen order.
- `depend add/remove`: changes only `depends_on` and preserves DAG validity.
- `progress`: creates body-only progress evidence.
- `reopen`: only allows `dne -> doi`.
- `lens`: rebuilds `.v/` from truth.
- `ctx`: writes stdout by default and `.v/ctx.md` only when requested.
