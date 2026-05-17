# agata-code-workflow

Agata-style file workflow skill for local Git projects.

Use it when you want a lightweight file-based workflow instead of a separate issue system.

- `issues/` is the truth source
- `tk` carries task state in the filename
- `docs/progress/` carries task-scoped execution workpad steps
- `rv` carries issue-scoped review exchange evidence
- `tk.tdo` is the backlog; do not add a separate `bl` kind
- review files are parent-first and round-based
- `refs/agent-names.md` carries optional human-friendly agent names
- `refs/radar.md` carries non-task observations waiting for a trigger
- `aidocs/` is an AI collaboration staging area, not workflow truth

## What It Covers

- choosing between `pl` / `rs` / `tk` / `rv`
- separating research, plan, and executable backlog semantics
- filename-based state transitions
- parent-first review naming
- retired-state validation
- progress visualization
- file-driven workpad steps under `docs/progress/`
- completion bar / feedback sweep close-out discipline
- optional AAAK memory
- optional agent name registration for multi-session collaboration
- a lean radar log for observations that are not worth a task yet
- keeping review evidence separate from task truth
- plan-to-task coverage checks before batching work
- semantic duplicate checks before creating new workflow ids
- risk-based review and real-runtime verification discipline
- task worktree closure and mainline-drain discipline
- primary-agent dispatch with sub-agent failure takeover
- task DAG dependencies via `depends_on` without adding states
- compact `recap` frontmatter without static reviewer fields

## Install

Install the `agata-code-workflow/` folder as a local skill in your coding agent environment.

In each project, keep `AGENTS.md` or `CLAUDE.md` short:

- point the agent to this skill by name
- keep only project-specific rules locally
- do not copy the whole workflow spec into every repo

Example:

```md
This project uses the `agata-code-workflow` skill.

Use it whenever work touches:

- `issues/`
- `docs/reviews/`
- `refs/agent-names.md`
- `refs/radar.md`
- `refs/project-memory-aaak.md`
- filename-based task state changes

Keep only project-specific rules here.
```

## Commands

This repo ships two thin helpers:

- `agata-code-workflow/scripts/task.sh`
- `agata-code-workflow/scripts/progress_view.py`

Document ids support 4 or 5 digits.

Common commands:

```bash
./agata-code-workflow/scripts/task.sh ls [state]
./agata-code-workflow/scripts/task.sh review tk10061 rv001 r001-gemini
./agata-code-workflow/scripts/task.sh progress tk10061 s01-repro
./agata-code-workflow/scripts/task.sh find tk10061.rv001-r001-gemini
./agata-code-workflow/scripts/task.sh find tk10061.s01-repro
./agata-code-workflow/scripts/task.sh show 10061
./agata-code-workflow/scripts/task.sh new tk runtime add-claim-gate p1
./agata-code-workflow/scripts/task.sh move 10061 doi
./agata-code-workflow/scripts/task.sh move pl10062 doi
./agata-code-workflow/scripts/task.sh archive 10061
./agata-code-workflow/scripts/task.sh archive-done --keep 32
./agata-code-workflow/scripts/task.sh prune 10061 origin/main
./agata-code-workflow/scripts/task.sh check
./agata-code-workflow/scripts/task.sh orphan-scan origin/main
./agata-code-workflow/scripts/progress_view.py --project-root . --no-open
```

For `task.sh new`, the contract is literal: `<kind> <board> <slug> [prio]`.
`board` is the third filename slot, not the state slot. New `pl` / `rs` / `rf` / `tk` docs start as `tdo`. New review exchange docs use `task.sh review <issue-id> <rvNNN> <rNNN-author>`.
Issue ids are allocated per kind. `tk0001` and `pl0001` may coexist; `tk0001` and `tk00001` may not. Existing old numbering is not migrated just to make sequences look tidy.
Review threads are stored as one immutable message per file. Read a thread with plain `cat docs/reviews/<issue-id>.rvNNN-r*.md`; round ids are zero-padded for this.
`task.sh new` uses an atomic `.agata-new-id.lock` directory while allocating ids. If it reports busy, rerun after the other allocator finishes.
Execution workpad steps use `task.sh progress <task-id> <sNN-slug> [state]` and land under `docs/progress/`. Their state is step state only; parent task closure remains in `issues/`.
For state-slot changes, use `task.sh move` first. Manual rename is only a helper-gap fallback for a clearly legal same-file state change; run `task.sh check` immediately and report the helper gap.
Links must use stable anchors such as `tk0001`, `rp0001`, `tk0001.rv001-r001-codex`, or `tk0001.s01-repro`; never link stateful full filenames such as `tk0001.tdo.*.md`.
During migration, `task.sh check` warns on old stateful links by default. Use `AGATA_STRICT_STABLE_LINKS=1 task.sh check` to turn the warning into a failure.
`docs/plan/` is legacy-only. New plans go to `issues/pl...`; still-relevant old plans should be migrated there, and the rest archived under `docs/archive/legacy-plan/`.
`tdo` is the backlog, not "ready now". Required future work with unmet dependencies stays `tdo` and declares `depends_on`; `cand` is not a DAG waiting state.
Fresh `tk` / `pl` / `rs` / `rf` docs use lean frontmatter: `owner`, `assignee`, `recap`, `why`, `scope`, `accept`, `risk`, `memory`, `depends_on`, `links`. `reviewer` is not a static field; review participants belong in `rv` exchange records.
`issues/` root is the live working set plus the latest done buffer. After close-out, run `task.sh archive-done --keep 32`; it moves older `.dne.` issue docs into `issues/archive/YYYY/` without changing their state. Directory location says cold history; filename state still says lifecycle. `task.sh check` never does this automatically.
Selective reading: default to `issues/` root plus direct anchors. Helpers may scan archive paths for ids and validation, but agents should not bulk-read archived bodies unless a direct anchor, regression, duplicate-scope check, or user history request requires it.
Use `refs/agent-names.md` when the project wants short names for agent sessions. The name is for the user; `sid` is the durable audit id. Names may be reused only by explicit user intent.
Use `refs/radar.md` for observations that are real but not yet tasks. Each entry needs a trigger condition; without a trigger, do not write it. Keep one file first and use a `域:` field for scope. Split only when the file itself becomes expensive to read.

No shadow database. No second state system.
Use `aidocs/` for raw materials, external references, design resources, AI-generated drafts, raw sub-agent run output, and generated workflow views. It is not a truth source and should not carry task state, review conclusions, or project memory.
Suggested staging layout: `aidocs/inbox/`, `aidocs/references/`, `aidocs/design/`, `aidocs/generated/`, `aidocs/agent-runs/`.
Before closure, promote anything durable to its real owner: execution truth to `issues/`, execution workpad to `docs/progress/`, review exchange to `docs/reviews/`, observations to `refs/radar.md`, agent names to `refs/agent-names.md`, long-lived memory to `refs/project-memory-aaak.md`, project documentation to `docs/`, and product assets to the product asset tree.
When the user explicitly wants sub-agents, the primary agent owns dispatch, recovery, and closure. Raw sub-agent output is advisory until promoted into `tk`, `rv`, memory, docs, or mainline code. Failed or partial sub-agent runs go to `aidocs/agent-runs/` for recovery, not to workflow truth.
In a linked worktree, local `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, and `refs/project-memory-aaak.md` are branch mirrors, not the authoritative truth view.
Workflow helpers such as `task.sh ls`, `find`, `show`, `new`, `review`, `progress`, `move`, `archive`, and `prune` automatically resolve truth through the shared control plane, even when you call them from a linked task worktree.
`task.sh check` is split on purpose: truth-pollution checks stay local to the current worktree, while all workflow semantics and staleness checks read from the shared control plane. `task.sh orphan-scan` keeps the current-worktree lens while also comparing shared refs.
If a task worktree needs notes or drafts, keep them outside `issues/`, `docs/reviews/`, `docs/progress/`, `refs/agent-names.md`, `refs/radar.md`, and `refs/project-memory-aaak.md` until the authoritative update is ready to land on the shared checkout.
A successful `task.sh check` only says the workflow semantics are valid. It does not mean every dirty truth file on the shared control plane belongs to your current task line.
On the shared control plane, unrelated truth-path edits and untracked workflow docs are foreign active lines by default, not "noise". Inspect their task id, state, `claimed_at`, `claimed_by`, `claimed_thread_id`, links, and nearby review or memory evidence before deciding whether another agent is landing truth.
Unless you are explicitly taking over, do not delete, rename, stage, or absorb those foreign active lines into your own commit.
On the same task line, control-plane writes are serial by default. Do not pipeline multiple `move` calls for one task; let each step land, then re-read truth and gates before the next transition.
Before merge, `dne`, or `prune`, re-check the worktree against the target `base-ref`; do not keep stacking changes on an obviously stale execution plane.
Parallel task worktrees are blind by default: do not consume another task worktree's unlanded code, artifacts, local services, or database state through side channels.
Stale `doi` claims trigger a takeover check, not automatic rollback; inspect the worktree, run `task.sh orphan-scan <base-ref> <task-id>`, then hand off or move state explicitly on the control plane.
When an issue moves to `doi`, `task.sh move` stamps `claimed_at`, `claimed_by`, and, when the runtime exposes it, `claimed_thread_id`. For multiple Codex threads, `claimed_thread_id` is the useful disambiguator.

Use `task.sh prune <task-id> <base-ref>` when a dedicated task worktree is ready to die.
It re-runs `check`, re-runs `orphan-scan`, refuses `doi` / `bkd`, and only removes one linked worktree whose execution diff is already drained against the chosen base ref.
It also refuses to delete the worktree that contains the current shell cwd; `cd` out first.
If you only want inspection or recovery before cleanup, run `task.sh orphan-scan <base-ref>` directly.

## Progress View

Run `progress_view.py` to generate:

- `aidocs/agata-workflow-status/progress-data.json`
- `aidocs/agata-workflow-status/progress-view.html`

The HTML is self-contained and opens directly in a browser.

Example:

![Dense read-only workflow progress view](assets/progress-view-doc-sample.png)

## Progress Workpad

Use `docs/progress/` when a task is too long for one clean handoff message.

Example:

```text
docs/progress/tk0615.s01-repro.dne.md
docs/progress/tk0615.s02-host-io.dne.md
docs/progress/tk0615.s03-electron-bridge.doi.md
```

Rules:

- valid states are `tdo`, `doi`, `dne`, `bkd`
- one parent `tk` may have at most one `doi` progress step
- closed parent tasks cannot leave open progress steps
- progress is workpad evidence, not closure authority
- parent `tk.links` may use stable anchors like `tk0615.s01-repro`

Close-out lives in the parent `tk` as a Completion Bar: progress drained, acceptance met, validation done, review feedback swept, implementation on mainline, `task.sh check` pass, worktree ready for cleanup. `accept` is the task contract; progress is evidence; Completion Bar is the close gate.

## AAAK

This repo includes optional AAAK references for compact writing:

- `agata-code-workflow/references/aaak-zh.md`
- `agata-code-workflow/references/aaak-profiles.md`

Use AAAK for:

- compressed task summaries
- dense review conclusions
- compact research notes
- long-lived project memory

Recommended memory file:

- `refs/project-memory-aaak.md`

It is a memory layer, not the truth source.

## Radar

Use `refs/radar.md` for "noticed, not yet a task" engineering observations.

Allowed states:

- `watching`
- `promoted`
- `dropped`

Minimal entry:

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

When the trigger fires, open a `tk`, change `态:` to `promoted`, and add `升: tkNNNN`. If it proves irrelevant, mark `dropped` with a short reason.

## Agent Names

Use `refs/agent-names.md` only when the user wants short names for agent sessions.
It records user naming intent, not automatic session registration.

Project shape:

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

Rules:

- `name` is for human input.
- `sid` is the durable audit id.
- Derive `sid` from the physical thread id when available, for example `sid019dd9af`; do not allocate sequential `sid` values from this file.
- If no thread id exists, derive `sid` from timestamp plus short random or local unique suffix, for example `sid260517-ab3d`. Never use global pure counters.
- `binding` is physical evidence, usually `thread:<id>`.
- If the same `sid` has multiple binding rows, the latest row in `refs/agent-names.md` is the current human-name mapping.
- No `online` / `offline`; there is no heartbeat.
- Do not write this file at session startup.
- Do not ask for names in non-interactive or background work. Use only `sid`.
- Do not use `name` as review author, `claimed_by`, or commit trailer identity when `sid` exists.
- `references/agent-names-lib.md` is only a starter list. Users may edit the project pool freely.
- This file may be manually trimmed or archived when it gets long. Git history is the audit trail for older rows.

If a task declares:

```yaml
memory: required
```

then it must be recorded in `refs/project-memory-aaak.md` before it closes into `dne` / `arvd`.

Use an anchor like:

```text
锚: tk10061
```

## Minimal Project Layout

```text
your-project/
  AGENTS.md or CLAUDE.md
  issues/
  docs/reviews/
  docs/progress/
  refs/agent-names.md  # optional
  refs/radar.md
  refs/project-memory-aaak.md
```

For the exact rules, read [agata-code-workflow/references/workflow-rules.md](agata-code-workflow/references/workflow-rules.md).
