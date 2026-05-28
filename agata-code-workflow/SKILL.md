---
name: agata-code-workflow
description: Create, update, review, or validate file-workflow artifacts: issues, progress, reviews, radar, graph, agent names, and aligned project docs.
---

# Agata Code Workflow

## Position

This skill is the file-based execution substrate for async engineering agents.

Flow:

```text
goal -> issue truth -> isolated execution -> progress evidence -> review evidence -> verified close-out -> durable memory/graph
```

It is not a chat protocol, scheduler, project manager, graph database, or orchestration platform.

Use it when work touches `issues/`, `docs/progress/`, `docs/reviews/`, `refs/project-memory-aaak.md`, `refs/radar.md`, `refs/graph.md`, `refs/agent-names.md`, file-name state transitions, review/progress naming, workflow helper scripts, or ordinary project docs that must stay aligned with these boundaries.

## State Glossary

- `tdo` = todo / pending required work. It may be DAG-blocked by `depends_on`.
- `doi` = doing / actively claimed work.
- `dne` = done / closed. Never treat `dne` as pending, design, backlog, or planning.
- `bkd` = blocked after work started; keep the frozen scene.
- `cand` = withdrawn from the active required graph; deferred / cancelled / not-now. It is not candidate backlog.
- `arvd` = archived / cold history.

Only `tdo`, `doi`, and `bkd` count as the active execution surface. `dne` is closed evidence; old priority labels on `dne` issues do not create current backlog pressure.

## Core Contract

1. `issues/` is the task truth source; the filename state slot is lifecycle truth.
2. Do not invent a second state system, index page, generated cache, graph, chat thread, branch, or commit convention as task truth.
3. `pl` is discussion/spec, `rs` is research, `tk` is executable work, and issue-scoped `rv` is review exchange evidence.
4. Backlog is `tk.tdo`; do not add `bl` or use `cand` for dependency waiting.
5. Future required work with unmet prerequisites stays `tdo` and uses `depends_on`.
6. `tk` / `pl` / `rs` / `rf` share one global numeric namespace, including archived issues. Kind is type, not id namespace.
7. Links use stable anchors such as `tk0001`, `tk0001.rv001-r001-reviewer`, or `tk0001.s01-repro`; never link stateful full filenames.
8. Review is evidence, not a task state. Do not restore `rvw`.
9. New review records use `docs/reviews/<issue-id>.rvMMM-rNNN-author.md` and frontmatter `result: block|pass|note`.
10. Progress files use `docs/progress/<tk-id>.sNN-<slug>.<state>.md`; progress never decides parent closure.
11. `refs/project-memory-aaak.md` stores durable historical judgments, not task truth.
12. `refs/radar.md` stores low-trust observations with triggers, not backlog, review evidence, or memory.
13. `refs/graph.md` stores durable typed relations for context synthesis; it never carries task status, owner, or completion truth.
14. `refs/agent-names.md` records user naming intent only; it is never task state.
15. `aidocs/` is staging for raw input, design resources, AI drafts, and raw sub-agent output. Promote durable material before close.
16. Default to one primary agent, one controlling task line, and one dedicated execution worktree.
17. The shared root checkout is the workflow control plane; task worktrees are execution sites, not second control planes.
18. Cross-boundary contracts must name who defines, produces, and consumes before implementation.
19. Cross-process communication, persistence, state machines, lifecycle, replay, debug, and contract changes need real-boundary smoke/integration evidence, not only single-process unit tests.

## Standard Path

1. Read the live root issues and direct anchors first. Do not bulk-read archived bodies.
2. Classify the request: unclear facts -> `rs`; unsettled direction -> `pl`; executable required work -> `tk.tdo`; immediate work -> `tk.tdo` then `tk.doi`.
3. Before creating a workflow doc, search current truth for duplicate scope. `task.sh new` allocates ids; it is not a semantic deduplicator.
4. Before batching a plan, generate a read-only coverage table: `plan clause -> owning tk -> state -> dispatch/action -> gap`.
5. Claim before implementation: move `tdo -> doi` on the shared control plane, then work in the dedicated worktree.
6. If live repro or runtime trace changes diagnosis, stop coding and update the controlling `tk` / `rv` first.
7. Keep review rounds in `rv`; close only after blockers are fixed or explicitly overruled.
8. Close code tasks only after implementation is landed on target mainline, verification evidence is written, progress is drained, `task.sh check` passes, and cleanup is ready.
9. Use `task.sh reopen <id> <reason>` when review, smoke, or user acceptance finds same-task work after `dne`. New scope gets a new `tk`.
10. After close-out, run `task.sh archive-done --keep 32` for context hygiene; archive location expresses hot/cold storage, not lifecycle.

## Risk Gates

- Lock and sequencing code: first collaborate with the human to freeze the single owner, state machine diagrams / sequence diagrams, and failure paths; then let AI fill in the implementation.

## Bundled Helpers

Use the bundled scripts from this skill directory; do not assume project-local `./scripts/task.sh` exists.

High-frequency commands:

```text
task.sh new <kind> <board> <slug> [prio]
task.sh move <issue-id> <state>
task.sh reopen <issue-id> <reason>
task.sh review <issue-id> <rvNNN> <rNNN-author> [block|pass|note]
task.sh progress <task-id> <sNN-slug> [state]
task.sh check
task.sh orphan-scan <base-ref> [filter]
task.sh prune <task-id> <base-ref>
task.sh archive-done [--keep N]
progress_view.py [--project-root <path>] [--no-open]
```

Use helper commands for legal renames, id allocation, review/progress file creation, archive cleanup, orphan scans, and validation. If a helper cannot express a clearly legal state-slot rename, manual rename is a helper gap: update the same document, run `task.sh check`, and report the gap.

## Minimal Shapes

Issue frontmatter stays small:

```yaml
owner: user
assignee: agent
recap: "态:tdo|核:TODO|界:TODO|验:TODO|下:TODO"
why: TODO
scope: TODO
accept: TODO
risk: low
memory: none
depends_on: []
links: []
```

Radar entry:

```md
## obYYYYMMDD-001 short-slug

时: YYYY-MM-DD
源: tkNNNN
域: area
观: observation
判: why not a task yet
触: concrete trigger
动: promote action
态: watching
```

Agent names:

- Interactive new sessions ask for a name or inheritance; do not show `sid`.
- Write `refs/agent-names.md` only after the user confirms a name.
- `engine` must be the current runtime; do not copy example values.
- Use `sid` for `claimed_by`, review author, and commit trailers. `name` is for humans.
- Derive `sid` from thread id when possible; otherwise use timestamp plus short random/local suffix. Never use global counters.
- No `online` / `offline`; there is no heartbeat.

```md
# Agent Names

## Bindings

| name | sid | slot | engine | role | binding | note |
|---|---|---|---|---|---|---|
| ana | sid019dd9af | A | current-runtime | ui | thread:019dd9af... | continue tk0001 |
```

## Coverage Tables

Coverage tables are read-only snapshots, not a second ledger.

- Generate from current `issues/` immediately before use.
- If the table disagrees with `issues/`, discard and regenerate it.
- Use `dispatch/action`, not `ready?`: `closed`, `active`, `dispatchable`, `blocked`, `gap`, `evidence-only`.
- `dne` / `arvd` rows are `closed`; never report them as backlog, pending, design-in-progress, or priority pressure.

## References

Read only what the task needs. Do not open `workflow-rules.md` end-to-end by default; search or open the relevant section.

- `references/workflow-rules.md`: exact naming, states, transitions, script semantics, worktree rules, review/progress details, concurrency, dispatch loop, and edge cases.
- `references/aaak-zh.md`: dense semantic compression and memory-style body blocks.
- `references/aaak-profiles.md`: workflow-specific AAAK profiles for `tk`, `rs`, `rv`, and project memory.
- `references/project-docs.md`: ordinary project docs that must not become workflow truth.
- `references/agent-names-lib.md`: name suggestions only when the project lacks a usable pool or the user asks.

Project refs are loaded only by direct need: `refs/project-memory-aaak.md`, `refs/radar.md`, `refs/graph.md`, and `refs/agent-names.md`.

## Output Discipline

- Prefer modifying the existing truth-source file over creating a new explanatory document.
- Use the shared root checkout control plane for workflow truth edits.
- Treat unrelated truth edits as foreign active lines, not noise.
- Answer worktree status as: `clean`, `single-task dirty, can continue`, or `contaminated, must split`.
- Keep close-out claims scoped to the current task; do not generalize to the whole repo.
- If automation is needed, start with a thin shell entrypoint, not a platform.
- Multi-agent dispatch is opt-in. The primary agent owns task state, triage, closure, and promotion of durable conclusions.
- End each phase with one next-step marker:
  `[本轮完成，下一阶段：动作(...)-目标(...)]` or `[本轮已完成(...)，阶段结束]`.
