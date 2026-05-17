---
name: agata-code-workflow
description: Use when the user wants to create, update, review, or validate Agata-style file-based workflow artifacts such as task files, plan files, research files, progress step files, review threads, radar observations, agent names, or operator checklists. Also use it for ordinary project documentation in repos that follow this workflow, so docs stay aligned with the same truth-source boundaries. Covers parent-first review naming, filename-based state transitions, issue/progress/review separation, review round naming, adjacent project docs, and minimal workflow discipline for local Git-based collaboration.
---

# Agata Code Workflow

Use this skill when work touches the file-based workflow itself:

- create or rename `tk` / `pl` / `rs` / `rv` files
- create task-scoped progress step files under `docs/progress/`
- decide where a new request should land
- prepare a plan-to-task coverage table before batching work
- review whether a workflow file is correctly named or placed
- convert loose review notes into parent-first review records
- validate retired states, review rounds, or `refs/agent-names.md`
- organize issue truth source and review evidence in a local Git repo
- write dense AAAK summaries for tasks, research, review, or project memory
- write or triage `refs/radar.md` observations that are real but not yet tasks
- write or revise ordinary project docs without creating a parallel workflow system
- generate a read-only progress board when the user asks to see current project status
- start implementation in a dedicated `git worktree` for the current task
- judge whether a worktree is clean, single-task dirty, or contaminated by another task line
- run review or verification in an isolated `git worktree` when collaboration would otherwise collide
- recover `tk` / `pl` / `rv` truth that may be stranded in another local branch or worktree
- place raw references, design resources, or AI-generated drafts without turning them into workflow truth
- run a file-driven primary-agent dispatch loop when the user explicitly wants sub-agents to implement and review work
- close each finished round with a fixed next-step marker line

Do not invent a second state system. The filename state slot is the truth source.

## Core Rules

1. `issues/` is the task truth source.
2. `issues/` files carry state. Issue-scoped `rv` files carry review exchange evidence.
3. `pl` is for discussion/spec. `rs` is for research. `tk` is the executable issue.
4. Progress files under `docs/progress/` carry execution workpad evidence; they never decide issue closure.
5. Review files are parent-first and thread/round based: `<issue-id>.rvMMM-rNNN-author.md`.
6. `commit` and `branch` are implementation trace, not task truth.
7. `refs/agent-names.md` is an optional human-name registry for agent sessions; it is never task state.
8. Ordinary docs may live outside `issues/`, but they must not redefine workflow state, task truth, progress truth, or review truth.
9. Review depth follows risk. Cross-process communication, persistence, state machines, lifecycle ownership, and contract changes need stronger evidence than pure UI or projection tasks.
10. Backlog is `tk.tdo`, not a separate `bl` kind. Do not add a parallel backlog file type.
11. `aidocs/` is a staging area for raw materials and AI collaboration artifacts. It is not workflow truth.
12. Raw sub-agent output is advisory until the primary agent promotes it. Assigned `rv` review records are evidence, but never task-state or closure authority.
13. DAG readiness is not a state. Keep future required work as `tdo` and express blockers with `depends_on`.
14. `cand` means withdrawn from active required work; it does not mean candidate backlog.
15. `refs/radar.md` is a low-trust observation log, not backlog, task truth, review evidence, progress, or project memory.

## Workflow

1. Read the live root issues and direct anchors before creating anything new. Do not bulk-read archived issue bodies.
2. Choose the file kind by phase:
   - discussion not settled -> `pl`
   - fact-finding or feasibility -> `rs`
   - scoped and executable -> `tk`
   - review exchange -> `rv`
3. Use this intake split:
   - material-inspired or fact-unclear -> `rs`
   - direction exists but the plan is not executable yet -> `pl`
   - executable and accepted for backlog -> `tk.tdo`
   - ready to work now -> `tk.tdo`, then claim as `tk.doi`
4. Before batching a plan into tasks, output a read-only coverage table from the live `issues/` truth: `plan clause -> owning tk -> state -> dispatch/action -> gap`. If a clause has no owning `tk`, mark it as a gap instead of relying on chat memory.
5. Before creating a new workflow doc, search the current truth source for the same scope. `task.sh new` only allocates an id; it is not a semantic deduplicator. Create a new `tk` only for work with independent scope, owner, verification, and closure value; tiny assertions, one-line hardening, or review nits attach to the current parent `tk` / `Completion Bar` or the next natural hardening task.
6. Default to one agent pushing the mainline end-to-end. Do not split work into extra rounds unless the next step is truly blocked by review, user decision, risk confirmation, missing evidence, or a real role handoff.
7. Default to one active task line in one dedicated worktree.
8. When a compiled-app test, live repro, or runtime trace changes the understood root cause, task boundary, or ownership split, stop further implementation and update the controlling `tk` and any linked `rv` first. Do not continue coding on stale workflow truth.
9. During closure, keep exactly one controlling task line. Related tasks may be cited as dependencies, consumers, or historical anchors, but do not advance multiple overlapping `tk` lines in parallel.
10. The shared root checkout is the workflow control plane. Use helpers from any linked worktree; they route truth writes back to shared root.
11. `doi` claims task ownership, and the `tdo -> doi` move must happen on that shared control plane before implementation starts anywhere else.
12. Dedicated task worktrees are execution sites for code, tests, generated files, and temporary drafts. They must not become a second workflow control plane.
13. After the control-plane state is visible in the shared checkout, implementation may proceed in that task's dedicated worktree.
14. A dirty worktree is allowed when all changes belong to the current task line.
15. If unrelated modified or untracked files appear in the current worktree, treat it as contamination and stop stacking work there.
16. Switching tasks means switching worktrees, not continuing in the current dirty checkout.
17. Review may use a separate review worktree for audit or verification, but authoritative `tk` / `rv` updates still return to the shared control plane.
18. Reviewers must actively search for duplicate truth paths: the same id, ref, result, status, owner, recovery path, prompt surface, or UI/debug surface must not have two owners unless the plan explicitly says which one exits.
19. Reuse the same task worktree while the same task is still active. When the task closes into `dne` / `cand` / `arvd` and all related changes are landed, remove that worktree. `bkd` may keep the worktree frozen, but do not mix another task into it.
20. Preserve id-first naming and keep the filename slots stable except for state.
21. When an issue moves state, rename the existing `tk` / `pl` / `rs` / `rf` file; do not create a parallel file.
22. When review happens, create one `rv` file per message: `docs/reviews/<issue-id>.rvMMM-rNNN-author.md`. Use zero-padded rounds so plain `cat docs/reviews/<issue-id>.rvMMM-r*.md` reads in order.
23. `rv` records are immutable exchange messages. Once created, treat them as frozen.
24. Keep the same `rvMMM` for the same review thread; use `r001`, `r002`, `r003` for each exchange message.
25. Review is evidence, not a `tk` state. Keep review rounds in `rv` records and close the controlling `tk` only after blocking review findings are resolved.
26. Links must use stable anchors, not stateful full filenames. Use `tk0001`, `rp0001`, `tk0001.rv001-r001-codex`, or `tk0001.s01-repro`; never link `tk0001.tdo.*.md`.
27. Use `docs/progress/<tk-id>.sNN-<slug>.<state>.md` when a long task needs a file-driven workpad. Valid progress states are `tdo`, `doi`, `dne`, and `bkd`.
28. Progress files are task-scoped execution ledger entries. They may record env stamp, done, verify, next, and risk; they do not replace the parent `tk`.
29. A closed parent `tk` must not leave open progress steps. Drain or close progress before moving the parent to `dne`, `cand`, or `arvd`.
30. `refs/project-memory-aaak.md` is historical memory, not task truth. Memory-gated tasks must anchor there as `锚: tkNNNN` / `锚：tkNNNN` or `锚: tkNNNNN` / `锚：tkNNNNN`.
31. Stable architectural review judgments, freeze points, and recurring risk rules belong in project memory when they will matter after the current chat; routine task progress does not.
32. Keep any helper automation thin. Scripts may validate and rename files, but must not become a second control plane.
33. Use `task.sh move` for state-slot changes by default. If the helper cannot express a clearly legal state-slot rename, a manual rename is allowed only as a helper-gap fallback; update the same document, run `task.sh check` immediately, and report the helper gap.
34. `pl` and any `tdo` document are shared pending truth. Do not leave them only in a disposable task worktree or snapshot branch.
35. Before deleting a worktree or dropping a local snapshot branch, run `task.sh orphan-scan <base-ref>`. If it reports truth drift under `issues/`, `docs/reviews/`, `docs/progress/`, `refs/radar.md`, or `refs/project-memory-aaak.md`, land or hand off that truth first.
36. If memory, review, progress, or git history mentions a `tk` / `pl` / `rs` / `rf` / `rv` file that the current truth source cannot find, first run `task.sh orphan-scan <base-ref> <id>` and then trace git history before concluding the file is gone.
37. A linked task worktree must not directly edit files under `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, or `refs/project-memory-aaak.md`. Use helper commands or draft elsewhere, then land authoritative truth on the control plane.
38. Create new workflow ids through `task.sh new` on the shared control plane instead of scanning `max(id)+1` by hand in parallel shells. The helper allocates ids per kind (`tk`, `pl`, `rs`, `rf`) and uses an atomic mkdir lock; if it reports busy, rerun after the other allocator finishes.
39. `task.sh new` takes `<kind> <board> <slug> [prio]`. `board` is a module or scenario code, not a workflow state. New `pl` / `rs` / `rf` / `tk` docs start at `tdo`; use `task.sh review <issue-id> <rvNNN> <rNNN-author>` for review exchange docs.
40. `docs/plan/` is legacy-only. Do not create new files there, do not treat it as active truth, and do not infer workflow rules from old files there. Migrate still-relevant plans to `issues/pl...` or archive them under `docs/archive/legacy-plan/`.
41. Do not write project memory just because you are creating a fresh `pl` / `rs` / `tk`. Memory is for stable milestones, key decisions, freeze points, or tasks that explicitly require `memory: required`.
42. `task.sh move <id> doi` stamps `claimed_at`, `claimed_by`, and, when the runtime exposes it, `claimed_thread_id`. In same-engine concurrency, thread id is the primary disambiguator.
43. Control-plane mutation on the same task line must be serial. Do not pre-issue multiple `move` commands for the same task; after each successful move, re-read the task truth and gates before deciding the next transition.
44. Worktree teardown is a control-plane reconciliation step. Only prune after the task is already closed into `dne` / `cand` / `arvd`, workflow truth is clean, and the linked worktree no longer carries execution-only diff versus the chosen base ref.
45. `doi` and `bkd` are not prune targets. `doi` must be released first; `bkd` keeps a frozen worktree unless the control plane explicitly changes direction.
46. In a linked worktree, local `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, and `refs/project-memory-aaak.md` are only branch mirrors. They are not the authoritative truth view.
47. Workflow helpers should read and write truth through the shared control plane by default. `check` only keeps the current-worktree view for truth-pollution checks; every global workflow semantic check still reads from the control plane. `orphan-scan` still inspects the current worktree while comparing against shared refs.
48. `prune` must not remove the worktree that contains the current shell cwd. If you are standing in the target worktree, `cd` out first.
49. Dependency and runtime verification are worktree-local. The current worktree must have local dependencies that match its lockfile; never borrow another checkout's `node_modules`.
50. For JS/TS worktrees, detect the package manager from lockfiles. If local dependencies are missing or stale, run the deterministic install for that worktree (`pnpm install --frozen-lockfile` / `npm ci` / `yarn install --frozen-lockfile`); if they are already valid, do not reinstall just for ritual.
51. If verification fails because dependencies are missing or stale, report it as dependency drift in the current worktree, install there, and rerun. Do not hide the failure or claim results from a different dependency tree.
52. Do not create a task branch or task worktree before the controlling `tk` exists in `issues/`. Do not implement first and backfill task truth later.
53. Do not create a review branch or review worktree before both the controlling `tk` and the intended review-round truth exist.
54. Branch names should express workflow role, not agent identity. Prefer `task/tkNNNN-<slug>`, `review/tkNNNN-<slug>`, `salvage/<name>`, and `release/<version>` unless the project defines a stricter local convention.
55. Keep task, review, and salvage worktrees outside the repository directory, under a project-level worktree root when one is defined. Do not hide execution worktrees inside the repo being edited.
56. Close code tasks in this order: finish implementation and verification in the dedicated worktree, land code on the target mainline branch, move the controlling task to `dne`, run `task.sh archive-done --keep 32`, then clean up that task's worktree and local branch.
57. `dne` is not valid while the implementation only exists in a task worktree; code changes must already be drained into the target mainline branch.
58. Test files must not grab a workflow id before the controlling `tk` exists. Regression or source-lock tests that serve an existing task should reuse the owner task id or use non-task-id naming.
59. New IPC, event, channel, protocol, projection, or cross-boundary contract work must name three roles before implementation: who defines it, who produces it, and who consumes it. Missing producer or consumer ownership is a plan gap, not an implementation detail.
60. Cross-process communication, persistence, state-machine, lifecycle, replay, debug, and contract tasks need verification in the real runtime boundary they change. Single-process unit tests cannot be the only evidence for those risks.
61. UI feedback may expose progress, waiting, success, or failure states, but it must not become lifecycle truth. Completion still follows the controlling task, ledger, or project-defined source of truth.
62. Never conclude verification from a mixed runtime (old process + new code). Exit old processes first, then run verification on the new build/runtime only.
63. Use `aidocs/` only for raw input, external references, design resources, AI-generated drafts, raw sub-agent run output, and generated read-only views. Before closure, promote durable material to its real owner: `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, `refs/project-memory-aaak.md`, `docs/`, or the product asset tree.
64. Use `depends_on` for required DAG predecessors. A `tdo` issue with unmet `depends_on` remains in the backlog but is not ready to dispatch. Do not use `cand` to mean dependency-waiting required work.
65. `issues/` root is the live working set plus a small warm buffer of recent `dne` docs. After close-out, run `task.sh archive-done --keep 32` as context hygiene; it physically moves older `dne` docs to `issues/archive/YYYY/` without changing their state. Directory location expresses hot/cold storage; the filename state slot still expresses lifecycle.

## Selective Reading

Default read surface:

- `issues/` root, max depth 1
- the current controlling `tk` / `pl` / `rs` / `rf`
- same-parent `rv` records for the current issue
- same-parent progress records for the current task
- `refs/agent-names.md` only when assigning or resolving an agent name
- matching `refs/radar.md` entries when creating, deduplicating, or triaging tasks
- relevant anchors in `refs/project-memory-aaak.md`

Do not bulk-read:

- `issues/archive/`
- historical review bodies
- historical progress bodies
- old issue bodies unrelated to the current anchor set

Tools may scan cold paths for ids, uniqueness, dependency existence, and link validation. Path scanning is not body reading. Open archived bodies only when a direct `links` / `depends_on` / memory anchor points there, when debugging a regression, when root-plus-memory cannot resolve duplicate scope, or when the user asks for history.

## Frontmatter Recap

Default issue frontmatter stays small:

- `owner`, `assignee`, `recap`, `why`, `scope`, `accept`, `risk`, `memory`, `depends_on`, `links`
- `recap` is a one-line AAAK-style index: `态:<state>|核:<point>|界:<scope>|验:<gate>|下:<next>`
- `recap` compresses reading context; it does not override filename state, `accept`, `depends_on`, or review evidence.
- `depends_on` is only for required DAG predecessors.
- `links` is only for evidence, references, review anchors, progress anchors, memory anchors, or related docs.
- Do not put `reviewer` in default `tk` / `pl` / `rs` / `rf` frontmatter. Reviewers are runtime participants; review truth lives in `rv` records.
- `claimed_*`, `code_version`, and `verify` are state or closure evidence fields. Do not add them to fresh `tdo` templates.

## Radar

Use `refs/radar.md` for observations that are real but not worth an issue yet.

It is a task incubator, not a task ledger:

- not `issues/`
- not backlog
- not review evidence
- not progress
- not project memory

Entry states:

- `watching`
- `promoted`
- `dropped`

Rules:

- Keep one `refs/radar.md` first. Use `域:` for scope; do not create `radar-frontend.md` until the file itself becomes costly.
- Every entry must have `触:`. No trigger means no radar entry.
- If the trigger fires, create a concrete `tk`, change `态:` to `promoted`, and add `升: tkNNNN`.
- If the observation proves irrelevant, change `态:` to `dropped` and add one short reason.
- Stable architectural lessons go to `refs/project-memory-aaak.md`, not radar.
- Blocking review findings go to the controlling `tk` / `rv`, not radar.

Minimal shape:

```md
## ob20260517-001 local-storage-read-helper-dup

时: 2026-05-17
源: tk1026
域: frontend
位: ComposerBar / MessageActionBar
观: localStorage read helpers are duplicated.
判: not worth a task until reuse grows.
触: third copy appears or defaults diverge again.
动: promote to shared renderer helper task.
态: watching
```

## Agent Names

Use `refs/agent-names.md` only when the user wants short names for agent sessions.

This file records user naming intent, not automatic session registration. It solves naming, not scheduling.

Rules:

- `name` is for human input.
- `sid` is the durable audit id.
- Do not expose `sid` in normal user-facing identity prompts. Ask about `name`; keep `sid` for files, review authors, and commit trailers.
- Derive `sid` from the physical thread id when available, for example `sid019dd9af`; do not allocate sequential `sid` values from this file.
- If no thread id exists, derive `sid` from timestamp plus short random or local unique suffix, for example `sid260517-ab3d`. Never use global pure counters.
- `slot` is optional call shorthand such as `A` / `B` / `C`.
- `binding` is physical evidence, usually `thread:<id>`.
- If the same `sid` has multiple binding rows, the latest row in `refs/agent-names.md` is the current human-name mapping.
- No `online` / `offline`; there is no heartbeat.
- Do not use `name` as `claimed_by`, review author, or commit trailer identity when `sid` exists.
- `references/agent-names-lib.md` is only a starter list. Users may edit the project pool freely.
- Do not write this file at session startup.
- Do not ask for a name in non-interactive or background work. Use only `sid`.
- If the user says "continue neo", append a binding row for `neo` with the current `sid`.
- If the user says "take a new name", pick the first unused project-pool name in interactive work only.
- If the pool is exhausted, keep using `sid` and ask the user to add names later.
- If the user gives a custom name that already exists, ask whether to continue that name or reset it in interactive work; in non-interactive work, keep using `sid`.
- This file may be manually trimmed or archived when it gets long. Keep recent and useful mappings; Git history is the audit trail for older rows.

Minimal shape:

```md
# Agent Names

## Bindings

| name | sid | slot | engine | role | binding | note |
|---|---|---|---|---|---|---|
| neo | sid019dd9af | A | codex | frontend | thread:019dd9af... | continue tk1021 |

## Pool

- ana
- ben
- cal
- neo
```

## Completion Bar

Put the close-out checklist in the parent `tk`, not in `docs/progress/`.

Truth split:

- `accept` is the task contract.
- `Completion Bar` is the close gate.
- Progress is evidence, not authority.

Minimal checklist:

- progress drained
- acceptance met
- focused tests pass
- typecheck/build pass when relevant
- review blockers resolved or explicitly overruled
- PR / inline / bot feedback swept when relevant
- implementation drained to target mainline
- `task.sh check` pass
- task worktree and local branch ready for cleanup
- `archive-done --keep 32` run when root `dne` buffer exceeds the warm cache

If the parent `tk` is blocked, write a blocker brief in the parent or current progress file: `missing`, `impact`, `tried`, `unblock_action`.

## Coverage Table Discipline

Coverage tables are read-only snapshots, not a second ledger.

- Generate the table from current `issues/` immediately before using it.
- If the table disagrees with `issues/`, discard and regenerate it; never "fix" reality by editing the table.
- Use `dispatch/action`, not a separate `ready?` column. Suggested values: `closed`, `active`, `dispatchable`, `blocked`, `gap`, `evidence-only`.
- `dne` / `arvd` rows are `closed`; do not mark them "not ready".
- Audit filing, raw review storage, and other process evidence are not plan clauses. Put them in `links` / `aidocs/agent-runs/` unless the workflow itself is the product change.

## Review Intake Router

Formal `rv` files need one existing parent issue.

- Single-issue review: write `docs/reviews/<issue-id>.rvMMM-rNNN-author.md`.
- Comprehensive audit: write `aidocs/agent-runs/<scope>.review-<agent>-<date>.md`.
- Examples of comprehensive audit: recent-N-hours review, whole-repo audit, cross-task review, broad architecture critique, or any review whose target is not exactly one `tk` / `pl` / `rs` / `rf`.
- Comprehensive audit is raw material. It cannot block, approve, or close a task by itself.
- Primary triage is the promotion gate. Each finding becomes one of: `reject`, `attach` to an existing parent `rv`, or `split` into a concrete `tk`.

## Control-Plane Concurrency

- A passing `task.sh check` is a semantic verdict, not an ownership verdict. It does not mean every dirty truth file on the shared control plane belongs to your current task line.
- On the shared control plane, unrelated edits under `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, or `refs/project-memory-aaak.md`, plus untracked `tk` / `pl` / `rs` / `rf` / `rv` files, are foreign active lines by default, not "noise".
- Before touching a foreign active line, inspect the task id, state, `claimed_at`, `claimed_by`, `claimed_thread_id`, links, nearby review, radar, memory, or agent-name anchors when present. Use those signals to decide whether someone else is actively landing truth.
- On the same task line, control-plane writes are serial by default. Do not pipeline `move` calls such as `tdo -> doi -> dne`; each step must land, then re-read truth and gates before the next step.
- Unless you are explicitly taking over, do not delete, rename, stage, or fold a foreign active line into your own commit. Commit only your own truth edits and report the other active line separately.

## Primary-Agent Dispatch Loop

Use this only when the user explicitly wants agent dispatch, parallel agents, or sub-agents. Do not turn ordinary work into delegation by default.

The primary agent owns the mainline decision. Sub-agents may implement, verify, or review, but they do not own task state or closure.

Minimal loop:

1. Primary agent writes or updates the controlling `tk` / `pl` on the shared control plane.
2. Primary agent assigns each sub-agent a bounded scope, owner files/modules, non-scope, verification commands, and expected return format.
3. Implementation sub-agents work in dedicated worktrees and report changed files, verification, unfinished work, and handoff notes.
4. Review sub-agents write findings as `docs/reviews/<issue-id>.rvMMM-rNNN-author.md` when assigned a clean review round; otherwise their raw output goes to `aidocs/agent-runs/`. They do not move the controlling issue state.
5. Primary agent consumes sub-agent output, promotes valid conclusions into `tk` / `rv`, rejects or fixes bad output, and decides whether to repair, re-dispatch, split a new `tk`, request user decision, or close.
6. Primary agent closes only after implementation is on the target mainline, blocking review findings are resolved or explicitly overruled, verification evidence is written back, and `task.sh check` passes.

Failure takeover:

- Treat sub-agent failure as normal, not exceptional. The primary agent must be able to recover from files plus git state without asking the user to forward messages.
- Raw sub-agent output belongs under `aidocs/agent-runs/`, for example `aidocs/agent-runs/tk0615.impl-codex-20260430T1030Z.md` or `aidocs/agent-runs/tk0615.review-gemini-20260430T1110Z.md`.
- `aidocs/agent-runs/` is low-trust staging. It is useful for recovery, but it is not task truth, review truth, or project memory.
- A failed sub-agent run must record what it attempted, what changed, what verified, what failed, and how another agent can resume. If that cannot be recovered, the primary agent inspects the worktree diff and writes a short takeover note before continuing.
- Do not let a failed sub-agent block the mainline more than one recovery cycle. The primary agent either takes over, re-dispatches with a narrower scope, or marks the controlling issue `bkd` with a concrete blocker.
- Promote only durable conclusions: review findings to `rv`, task decisions to `tk`, recurring architectural lessons to project memory, and implementation to mainline code. Leave raw transcripts in `aidocs/agent-runs/`.

## Bundled Script

If the user asks for workflow automation, use `scripts/task.sh` first.
Resolve bundled helper paths relative to this `SKILL.md` file's directory. Do not search for `task.sh` under the current project, and do not assume `./scripts/task.sh` exists there.

Current commands:

- `task.sh new <kind> <board> <slug> [prio]`
- `task.sh review <issue-id> <rvNNN> <rNNN-author>`
- `task.sh progress <task-id> <sNN-slug> [state]`
- `task.sh ls [state]`
- `task.sh find <id>`
- `task.sh show <task-id>`
- `task.sh move <issue-id> <state>`
- `task.sh archive <task-id>`
- `task.sh archive-done [--keep N]`
- `task.sh prune <task-id> <base-ref>`
- `task.sh check`
- `task.sh orphan-scan <base-ref> [filter]`
- `progress_view.py [--project-root <path>] [--no-open]`

Use `task.sh` for legal rename flow, basic validation, archive moves, prune cleanup, done-buffer cleanup, and memory-gated close checks.
For `task.sh new`, remember: `board` is the third filename slot, not the state slot. The helper assigns the initial state itself: new `pl` / `rs` / `rf` / `tk` docs start as `tdo`. For review exchanges, use `task.sh review <issue-id> <rvNNN> <rNNN-author>`; do not allocate global review ids for new work.
`task.sh new` uses per-kind counters. `tk0001` and `pl0001` may coexist; `tk0001` and `tk00001` may not. Do not renumber old files to make sequences look tidy.
Read a review thread with plain `cat docs/reviews/<issue-id>.rvNNN-r*.md`; round ids are zero-padded for this.
For execution workpad steps, use `task.sh progress <task-id> <sNN-slug> [state]`. The helper writes `docs/progress/<task-id>.<sNN-slug>.<state>.md`; progress state only means step state, not parent issue state.
`task.sh check` warns on stateful full-filename links by default. Set `AGATA_STRICT_STABLE_LINKS=1` to make them fail during migration cleanup.
For `task.sh move`, `<issue-id>` may be `tkNNNN`, `plNNNN`, `rsNNNN`, or `rfNNNN`; a bare numeric id still means `tkNNNN`.
For `task.sh move <id> doi`, the helper stamps `claimed_at`, `claimed_by`, and, when available, `claimed_thread_id`. You can override the coarse claimant with `AGATA_CLAIMANT` and the thread marker with `AGATA_CLAIM_THREAD_ID`.
`task.sh ls`, `find`, `show`, `new`, `review`, `progress`, `move`, `archive`, and `prune` may be called from a linked worktree, but they must resolve truth against the shared control plane instead of the local mirror paths.
Use `task.sh check` on the current worktree when you need to catch linked-worktree truth pollution or contamination. Its local view is only for that pollution guard; the rest of the workflow semantics still resolve against the control plane.
Use `task.sh orphan-scan` when you need current-worktree truth drift plus shared-ref comparison before cleanup or recovery.
Use `task.sh prune <task-id> <base-ref>` when a dedicated task worktree is ready to die. It re-checks workflow truth, blocks `doi` / `bkd`, and only removes a single linked worktree whose execution diff is already drained against the chosen base ref. It also refuses to delete the worktree that contains the current shell cwd.
Use `task.sh archive-done --keep 32` as the final close-out cleanup step. It is explicit and never runs from `task.sh check`. Do not rename `.dne.` to `.arvd.` merely because a completed issue moved under `issues/archive/`; the archive directory already says it is cold history.
Use `progress_view.py` when the user wants a dense read-only HTML view of current workflow status and history.
Do not extend it into a scheduler, indexer, or ownership service unless the user explicitly asks.

## When To Read References

Read `references/workflow-rules.md` when you need exact naming, state, or semantic mapping details.

Read `references/aaak-zh.md` when the user wants high-density semantic compression, memory-style summaries, or protocol-like body blocks.

Read `references/aaak-profiles.md` when the user wants a workflow-specific AAAK profile for:

- `tk`
- `rs`
- `rv`
- project memory notes

Read `references/project-docs.md` when the user is writing or revising ordinary project docs such as:

- `README`
- architecture notes
- runbooks
- usage docs
- handoff / delivery notes
- module-local design notes that are not workflow truth

Read `refs/project-memory-aaak.md` when:

- taking over an unfamiliar module
- answering "why did we do this"
- reviewing historical decisions or freeze points
- deciding whether a task must be written into long-term memory

Read `refs/radar.md` when:

- deciding whether a small smell deserves a new `tk`
- checking whether a non-blocking review thorn was already observed
- doing periodic observation cleanup
- seeing a trigger that may promote an observation to a task

Read `refs/agent-names.md` when:

- the user asks this session to inherit a name
- the user asks this session to take a new name
- a review author, claimant, or commit trailer needs a human-friendly name mapping

Read `references/agent-names-lib.md` only when the project has no usable name pool or the user asks for name suggestions.

Typical cases:

- creating a new workflow file
- deciding whether something belongs in `rs`, `pl`, `tk.tdo`, or `tk.doi`
- checking review round naming
- creating or validating `docs/progress/` workpad steps
- checking for retired `rvw` state residue
- preparing a plan-to-task coverage table before batching implementation
- checking whether a new task duplicates existing scope
- recording a non-task observation with a concrete trigger
- checking cross-boundary define / produce / consume ownership
- diagnosing linked-worktree dependency drift before running build/test
- checking `refs/agent-names.md` shape
- creating a new workflow doc id without racing another shell
- checking whether workflow truth is stranded in another local branch or worktree
- writing or revising a non-workflow project doc in an Agata repo
- compressing a long task body into a stable summary block
- drafting project memory in dense structured prose

## Output Discipline

- Prefer modifying the existing truth-source file over creating a new explanatory document.
- Workflow truth edits belong on the shared root checkout control plane. Prefer helper commands from the current worktree over manual `cd` switching.
- After any live repro, compiled-app verification, or runtime trace that changes the current diagnosis, first write back a minimal truth resync note to the controlling workflow artifact before continuing. That note must say: scene, observed truth, root-cause or boundary judgment, and the next cut.
- Do not start the next fix while the controlling `tk` / `rv` still reflects an older diagnosis than the latest live evidence.
- If a linked worktree needs to write task notes, progress drafts, review drafts, radar drafts, or agent-name drafts, keep them outside the truth-source paths until they are ready to land on the control plane.
- For ordinary docs, prefer updating the canonical doc instead of creating a parallel note with overlapping scope.
- If a new review artifact is needed, make it parent-first and minimal.
- If a request can be answered by renaming an existing file, do that instead of adding a layer.
- If the user asks for automation, start with a thin shell entrypoint, not a platform.
- Do not place ordinary project docs under workflow-only slots such as `pl` / `rs` just to make them look tracked.
- For worktree status questions, answer with a three-state verdict first: `clean`, `single-task dirty, can continue`, or `contaminated, must split`.
- Close tasks with scoped evidence only. Do not generalize to the whole repo or all worktrees.
- For cleanup, say only that the current task's bound worktree and local branch were reclaimed. Do not say things like "only the root repo remains" or "everything was cleaned".
- Call unrelated shared-control-plane changes `foreign active lines`, not "noise" or generic dirty state.
- If new scope appears after a task is already `dne`, say it needs a new `tk` instead of writing back into the closed task.
- Before a close-out reply, you may add one thin `全场快速扫视`: control plane first, worktrees second, compressed conclusion only.
- A `全场快速扫视` reports only foreign active lines plus the remaining foreign worktree count or coarse ownership, and says they were not taken over.
- When a phase or round is finished, make the response's last line exactly one next-step marker:
  `[本轮完成，下一阶段：动作(文档落盘/实现/审阅/修复/复审/通过/提交/合并与清理/推送/任务完成/需用户决策...)-目标(当前任务/单号/关键字)]`
  or
  `[本轮已完成(当前任务/单号/关键字)，阶段结束]`
- Treat that marker as a mainline pointer, not a stop signal. If the next action is still owned by the current agent and has no external blocker, continue directly instead of waiting for a new round.
