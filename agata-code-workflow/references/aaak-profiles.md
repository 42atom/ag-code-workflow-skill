# AAAK Workflow Profiles

These are narrow AAAK profiles for `agata-code-workflow`.

Do not use the full RFC field set by default.
Use the smallest profile that preserves task meaning.

## Shared Rule

For workflow files:

- filename state remains the truth source
- front matter remains the control plane
- AAAK is a compressed body format

AAAK should usually appear near the top of the body.

Style rule:

- 文言优先，白话兜底
- command, path, enum, verify, acceptance, source locator keep plain
- if brevity harms judgment, use plain Chinese immediately

## AAAK-TK

Use for executable task files.

Recommended fields:

```text
题
时
态
项
因
范
非
验
依
源
```

Meaning:

- `题`: task topic
- `时`: task date
- `态`: human-readable state mirror
- `项`: what to do
- `因`: why it exists
- `范`: scope
- `非`: non-scope
- `验`: acceptance
- `依`: dependency
- `源`: commits, checklists, source docs

Example:

```text
题: quick-render-priority
时: 2026-04-10
态: doi
项: quick 任务优先于 batch backlog
因: 客户快速预览被饿死
范: worker claim 顺序
非: 不拆 worker|不改 renderer
验: quick 优先 claim|batch 不被抢占
依: tk0058
源: commit 3dff5c2|docs/operator-checklist-tk0059.md
```

More compressed variant:

```text
题: 快产先取
时: 2026-04-10
态: doi
项: quick 先于 batch backlog
因: 快览久饿
范: claim 次序
非: 不拆 worker|不改 renderer
验: quick 先取|batch 不夺
依: tk0058
源: commit 3dff5c2
```

## AAAK-RS

Use for research, facts, and recommendation notes.

Recommended fields:

```text
题
时
问
实
决
风
待
源
```

Meaning:

- `问`: research question
- `实`: facts
- `决`: recommendation or outcome
- `风`: risk
- `待`: next step

Example:

```text
题: queue-overview-poll
时: 2026-04-11
问: 当前轮询是否重复请求
实: navbar 与 queue page 双拉 overview
决: 收口为单心跳
风: 低
待: 评估 provider vs event relay
源: app-navbar.jsx|task-queue.jsx
```

More compressed variant:

```text
题: 概览轮询
时: 2026-04-11
问: 是否双拉
实: navbar|queue 双取 overview
决: 收一心跳
风: 低
待: 估 provider vs event relay
源: app-navbar.jsx|task-queue.jsx
```

## AAAK-RV

Use for `rv` review exchanges and reply summaries.

Recommended fields:

```text
题
时
轮
决
阻
因
验
源
```

Meaning:

- `轮`: review round
- `决`: pass / fail / partial pass
- `阻`: blockers
- `因`: reason
- `验`: required verification
- `源`: commit, file, test, screenshot, log

Example:

```text
题: tk0061
时: 2026-04-11
轮: r001
决: 不通过
阻: 跨午夜 batch 重复计数
因: item归日 + batch总数混用
验: 同一 batch 跨两天时不得重复放大 output_count
源: commit 9297321|render_repo.py|runner.py
```

More compressed variant:

```text
题: tk0061
时: 2026-04-11
轮: r001
决: 不过
阻: 跨午夜复计
因: item归日|batch总数混写
验: 不得重放 output_count
源: commit 9297321|render_repo.py|runner.py
```

## AAAK-MEM

Use for project history and long-lived memory notes.

Recommended fields:

```text
题
时
锚
决
因
链
评
源
```

Meaning:

- `决`: what changed
- `因`: why it changed
- `锚`: stable task anchor such as `tk0061`
- `链`: relation to earlier or later notes
- `评`: present status or interpretation

Example:

```text
题: workflow-review-model
时: 2026-04-11
锚: tk0061
决: review 文档改为 parent-first + rNNN
因: re.re 命名链过深且不利于 grep
链: follows=旧 docs/opus-feedback 流
评: 新增内容按新规，历史文档暂不批量迁移
源: agata-code-workflow/references/workflow-rules.md
```

More compressed variant:

```text
题: 评审制式迁移
时: 2026-04-11
锚: tk0061
决: review 改 parent-first+rNNN
因: re.re 过深|grep 不利
链: follows=旧 docs/opus-feedback 流
评: 新文从新|旧档暂存
源: workflow-rules.md
```

## Placement

Recommended body shape:

```text
AAAK:
题: ...
时: ...
...
```

Then continue with normal markdown for:

- shell commands
- long rationale
- operator steps
- screenshots or evidence blocks

## Anti-Pattern

Do not:

1. replace front matter with AAAK
2. replace filename state with AAAK `态`
3. compress command sequences into unreadable dense lines
4. drop source just to save tokens

Allowed exception: front matter may contain one AAAK-style `recap` index, for example `态:tdo|核:...|界:...|验:...|下:...`. It does not replace `accept`, `depends_on`, `links`, or review evidence.
