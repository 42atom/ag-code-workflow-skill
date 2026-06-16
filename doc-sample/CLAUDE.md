# Workflow

Use the `ag-code-workflow` skill for file-based task management in this repo.

Apply it whenever you:

- create or rename `tk` / `pl` / `rs` / `rv` files
- move an issue between `tdo` / `doi` / `dne`
- create review records under `docs/reviews/`
- create progress workpad steps under `docs/progress/`
- maintain `refs/agent-names.md`
- maintain `refs/project-memory-aaak.md`

Do not create a second state system. The filename state slot is the truth source.
Use `task.sh move` before manual state-slot rename; manual rename is only a helper-gap fallback and must be followed by `task.sh check`.
Use `aidocs/` only for raw references, design resources, generated reports, drafts, and raw sub-agent run output; promote durable truth to the proper workflow or doc path before closure.
