# Project Docs Boundary

Use this reference when the task is about ordinary project documentation rather than workflow truth.

## 1. Boundary

Workflow truth stays in the workflow system:

- `issues/` for `pl` / `rs` / `tk`
- `docs/reviews/` for issue-scoped `rv`
- `docs/progress/` for task-scoped execution workpad steps
- `refs/agent-names.md` for optional agent session names
- `refs/radar.md` for non-task observations waiting for a trigger
- `refs/project-memory-aaak.md` for long-lived project memory

Ordinary docs are things like:

- `README`
- architecture notes
- runbooks
- usage guides
- delivery / handoff notes
- module-local design docs that do not carry workflow state

Do not turn ordinary docs into fake workflow files.
Do not use ordinary docs to override task state, review state, or memory gates.

## 2. Placement

Prefer the repo's existing doc layout first.

If the repo has no clear convention:

- repo-wide docs go in root or `docs/`
- module-specific docs live near the module they describe

Do not create `docs/plan/` or `docs/research/` as a second workflow system.
If a project already has `docs/plan/`, treat it as legacy read-only material. Move still-relevant plans into `issues/pl...`; archive the rest under `docs/archive/legacy-plan/`.

## aidocs Staging

Use `aidocs/` for material that is useful to agents but is not yet project truth:

- raw user drops
- copied external references
- design inspiration and art resources
- AI-generated drafts
- raw sub-agent run output
- generated read-only reports

Suggested layout:

```text
aidocs/
  inbox/
  references/
  design/
  generated/
  agent-runs/
```

Rules:

- do not put task state, review conclusions, or project memory there
- do not treat files under `aidocs/` as workflow ids, even if their names mention `tk`, `pl`, `rv`, or old states
- keep `aidocs/agent-runs/` low-trust; promote only primary-agent-approved conclusions into workflow truth
- promote stable project docs to `docs/`
- promote execution truth to `issues/`
- promote durable execution workpad steps to `docs/progress/`
- promote review exchange to `docs/reviews/`
- promote agent session names to `refs/agent-names.md`
- promote non-task observations with triggers to `refs/radar.md`
- promote long-lived memory to `refs/project-memory-aaak.md`
- put runtime product assets in the repo's product asset tree, not in `aidocs/`

## 3. Naming

For ordinary docs:

- prefer stable, lowercase, kebab-case filenames
- name by topic, not by temporary status
- avoid workflow slots like `.tdo.` / `.doi.` unless the file is truly a workflow artifact

Examples:

- `README.md`
- `docs/runtime-architecture.md`
- `docs/deployment-runbook.md`
- `src/auth/README.md`

## 4. Editing Rules

- prefer updating the canonical doc over creating a parallel explainer
- keep one doc to one responsibility
- link to workflow truth instead of copying task state into prose
- link workflow artifacts by stable id anchor, not by stateful full filename
- record decisions and constraints, not chat transcripts
- if front matter is needed, keep it short and use real responsible humans unless the repo already defines another convention

## 5. Relationship To Workflow Files

Use a workflow file when the document must carry execution state, execution workpad evidence, review evidence, or task ownership.

Use an ordinary doc when the document explains:

- how the system works
- how to operate it
- how to use it
- what was delivered

If unsure:

- execution truth -> `pl` / `rs` / `tk` / `rv`
- execution workpad -> `docs/progress/`
- explanatory material -> ordinary doc
