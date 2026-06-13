# agtask Fitness Matrix

Status: active v2 fitness draft, updated 2026-06-13. Supersedes earlier agtask v2 drafts; do not implement from older copies.

This matrix checks the agtask product surface against real v1 workflow experience.

Classification:

```text
keep     retained in the product surface
defer    needed later, not in the current delivery cut line
future   post-MVP structural feature
reject   intentionally not supported
replace  covered by a smaller mechanism
```

## Matrix

| v1 capability / pain | agtask decision | Class | Rationale |
|---|---|---|---|
| `task.sh new` prevents id and template mistakes | `agtask new` with global id allocation and local lock | keep | Strict grammar needs safe creation. |
| Global id namespace across `tk/pl/rs/rf` | shared numeric namespace | keep | Keeps numeric continuity; future kind migration still needs atomic reference updates. |
| Kind correction | future atomic `agtask retype` | future | Kind is part of the primary id; safe retype is post-MVP primary-key migration, not a normal slot edit. |
| Lane correction | `agtask relane <id> <lane>` | keep | Lane is domain/module/workstream, not kind. |
| Priority correction | `agtask reprioritize <id> <priority>` | keep | Priority is hot filename truth. |
| Slug correction | `agtask rename <id> <slug>` | keep | Avoids hand-renaming filename slots. |
| Owner assignment | `agtask assign <id> <owner>` | keep | Owner is responsibility identity. |
| Agent traceability | `threads` set plus `agtask join` | keep | Threads are evidence set, not event log. |
| Claiming work | `agtask assign` + `agtask join` + `agtask move <id> doi` | keep | Claim stays explicit: owner, thread, and state are separate truth changes. |
| Closing work | `agtask move <id> dne` with close-readiness | keep | Close is a business boundary, not syntax rename. |
| Reopen after post-review | `agtask reopen <id> [--reason]` | keep | Real workflow often closes, reviews, reopens. |
| Progress evidence | `agtask progress <id> <sNN-slug>` | keep | Creates evidence file only; no progress state. |
| Review command | no `agtask review` | reject | Review is business workflow; agtask only guards `.block.md`. |
| Review blocker | any matching `.block.md` blocks close | keep | Minimal, file-native close guard. |
| `pass` review outcome state machine | no latest-outcome logic | reject | Avoids rebuilding review workflow. |
| Dependency creation at new time | `agtask new --depends-on` | keep | DAG is structural truth. |
| Dependency edits | `agtask depend add/remove` | keep | Avoids YAML hand-edit for graph truth. |
| Tags for release/dump | tags field and `.v/tag/` lens | keep | Useful for slices; no mutator yet. |
| Tag command | no `agtask tag` | defer | Tags are auxiliary; manual edit plus check is enough. |
| Links as evidence | links field and check rules | keep | Evidence path remains available. |
| Link command | no `agtask link` | defer | Avoid attachment-manager creep. |
| TSV output | `agtask ls --tsv` | keep | Central Unix projection API. |
| Full links in TSV | `link_count` only | replace | Keeps hot stream short. |
| Full threads in TSV | `thread_count` only | replace | Trace details stay in issue file. |
| Incremental pre-commit | `agtask check --changed` | keep | Fast path for commits. |
| Strict graph audit | `agtask check` | keep | Full check owns graph-wide invariants. |
| Generated lens | `.v/` | keep | Rebuildable filesystem views. |
| Markdown views | no `views/*.md` in Build Now | defer | `.v/` and `ctx` prove lens first. |
| LLM context | `agtask ctx` | keep | Generated orientation, not memory. |
| Stale/recent age | best-effort heuristic | keep | Orientation only; not audit truth. |
| Archive cold storage | `agtask compact` / `restore` | keep | Hot/cold split matters for growing repos. |
| Archive as state | no `arvd` state | reject | Archive is storage temperature, not lifecycle state. |
| Batch close | no `batch-close` in Build Now | defer | Convenience can misclose; single close first. |
| SQLite cache | no cache in Build Now | defer | Profile before caching. |
| Daemon/server/sync | not supported | reject | Violates local file-native scope. |
| `tk` alias | no official alias | reject | One product, one command, one contract. |

## Build Now Fitness Bar

Build Now is fit when:

- agent can create an issue, list it, check it, run changed check, move state, assign, join, edit safe slots, manage dependencies, evidence progress, reopen, build `.v/`, and generate `ctx`
- full check catches duplicate ids, invalid grammar, missing dependencies, cycles, close blockers, and close-readiness failures
- `ls --tsv`, `.v/`, and `ctx` provide enough context without reading all bodies
- `move` changes only state and blocks illegal close

Later fitness is reached when:

- agent can compact and restore cold issues without corrupting live/archive id uniqueness
- atomic `retype` has a separate migration spec before implementation
- every rejected v1-adjacent feature has a documented smaller replacement or explicit defer reason
