# agata-code-workflow

Agata-style file workflow skill for local Git projects.

Use it when you want a lightweight file-based workflow instead of a separate issue system.

- `issues/` is the truth source
- `tk` carries task state in the filename
- `docs/progress/` carries task-scoped execution workpad steps
- `rv` carries issue-scoped review exchange evidence
- `tk.tdo` is the backlog; do not add a separate `bl` kind
- review files are parent-first and round-based
- `aidocs/` is an AI collaboration staging area, not workflow truth
- `coauthors.csv` is optional dispatch context

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
- `refs/project-memory-aaak.md`
- `coauthors.csv`
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
./agata-code-workflow/scripts/task.sh archive-done --keep 8
./agata-code-workflow/scripts/task.sh prune 10061 origin/main
./agata-code-workflow/scripts/task.sh check
./agata-code-workflow/scripts/task.sh orphan-scan origin/main
./agata-code-workflow/scripts/progress_view.py --project-root . --no-open
```

For `task.sh new`, the contract is literal: `<kind> <board> <slug> [prio]`.
`board` is the third filename slot, not the state slot. New `pl` / `rs` / `rf` / `tk` docs start as `tdo`. New review exchange docs use `task.sh review <issue-id> <rvNNN> <rNNN-author>`.
Review threads are stored as one immutable message per file. Read a thread with plain `cat docs/reviews/<issue-id>.rvNNN-r*.md`; round ids are zero-padded for this.
`task.sh new` uses an atomic `.agata-new-id.lock` directory while allocating ids. If it reports busy, rerun after the other allocator finishes.
Execution workpad steps use `task.sh progress <task-id> <sNN-slug> [state]` and land under `docs/progress/`. Their state is step state only; parent task closure remains in `issues/`.
For state-slot changes, use `task.sh move` first. Manual rename is only a helper-gap fallback for a clearly legal same-file state change; run `task.sh check` immediately and report the helper gap.
Links must use stable anchors such as `tk0001`, `rp0001`, `tk0001.rv001-r001-codex`, or `tk0001.s01-repro`; never link stateful full filenames such as `tk0001.tdo.*.md`.
During migration, `task.sh check` warns on old stateful links by default. Use `AGATA_STRICT_STABLE_LINKS=1 task.sh check` to turn the warning into a failure.
`docs/plan/` is legacy-only. New plans go to `issues/pl...`; still-relevant old plans should be migrated there, and the rest archived under `docs/archive/legacy-plan/`.
`tdo` is the backlog, not "ready now". Required future work with unmet dependencies stays `tdo` and declares `depends_on`; `cand` is not a DAG waiting state.
Fresh `tk` / `pl` / `rs` / `rf` docs use lean frontmatter: `owner`, `assignee`, `recap`, `why`, `scope`, `accept`, `risk`, `memory`, `depends_on`, `links`. `reviewer` is not a static field; review participants belong in `rv` exchange records.
`issues/` root is the live working set plus the latest done buffer. After close-out, run `task.sh archive-done --keep 8`; it moves older `.dne.` issue docs into `issues/archive/YYYY/` without changing their state. Directory location says cold history; filename state still says lifecycle. `task.sh check` never does this automatically.

No shadow database. No second state system.
Use `aidocs/` for raw materials, external references, design resources, AI-generated drafts, raw sub-agent run output, and generated workflow views. It is not a truth source and should not carry task state, review conclusions, or project memory.
Suggested staging layout: `aidocs/inbox/`, `aidocs/references/`, `aidocs/design/`, `aidocs/generated/`, `aidocs/agent-runs/`.
Before closure, promote anything durable to its real owner: execution truth to `issues/`, execution workpad to `docs/progress/`, review exchange to `docs/reviews/`, long-lived memory to `refs/project-memory-aaak.md`, project documentation to `docs/`, and product assets to the product asset tree.
When the user explicitly wants sub-agents, the primary agent owns dispatch, recovery, and closure. Raw sub-agent output is advisory until promoted into `tk`, `rv`, memory, docs, or mainline code. Failed or partial sub-agent runs go to `aidocs/agent-runs/` for recovery, not to workflow truth.
In a linked worktree, local `issues/`, `docs/reviews/`, `docs/progress/`, `refs/project-memory-aaak.md`, and `coauthors.csv` are branch mirrors, not the authoritative truth view.
Workflow helpers such as `task.sh ls`, `find`, `show`, `new`, `review`, `progress`, `move`, `archive`, and `prune` automatically resolve truth through the shared control plane, even when you call them from a linked task worktree.
`task.sh check` is split on purpose: truth-pollution checks stay local to the current worktree, while all workflow semantics and staleness checks read from the shared control plane. `task.sh orphan-scan` keeps the current-worktree lens while also comparing shared refs.
If a task worktree needs notes or drafts, keep them outside `issues/`, `docs/reviews/`, `docs/progress/`, `refs/project-memory-aaak.md`, and `coauthors.csv` until the authoritative update is ready to land on the shared checkout.
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
  refs/project-memory-aaak.md
  coauthors.csv        # optional
```

For the exact rules, read [agata-code-workflow/references/workflow-rules.md](agata-code-workflow/references/workflow-rules.md).
