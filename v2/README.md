# agtask

`agtask` is the isolated Rust-based v2 product line for file-native task workflow.

Status: active v2 entrypoint, updated 2026-06-13. The documents in this directory supersede earlier agtask v2 drafts.

The current production skill remains in `ag-code-workflow/`.

v2 rules:

- Do not treat this directory as the v1 production contract.
- Do not migrate existing v1 workflow files from here.
- Keep generated artifacts disposable and rebuildable.
- Keep `issues/` as the workflow truth source in any v2 sample.
- Keep Rust as a parser, checker, projector, and safe rename layer; do not introduce a database or daemon as truth.

Start here:

- `SKILL.md`
- `FITNESS.md`
- `DESIGN.md`
- `PRD.md`
- `SPEC.md`
- `examples/`
