# AAAK-ZH Reference

AAAK-ZH is a high-density Chinese semantic encoding style for LLM, RAG, and agent memory.

Use it when the user wants:

- dense task or review summaries
- decision compression
- project memory notes
- long-lived research snapshots
- explicit relation and source recovery

Do not use it as a full replacement for:

- legal or medical originals
- operator checklists
- step-by-step procedures
- long command sequences
- evidence text that must stay verbatim

## Three Layers

AAAK-ZH uses three layers:

- 核: the stable meaning of one record
- 链: explicit relations between records or nodes
- 源: source and recovery entry

Short rule:

```text
核定形，链定联，源定真
```

Meaning:

- single-item meaning -> 核
- cross-item relation -> 链
- evidence and backtrace -> 源

## Basic Syntax

Format:

```text
字段: 内容
```

Example:

```text
题: 认证迁移
时: 2026-04-08
决: Auth0→Clerk
因: 价低+DX佳
评: 已定
源: readme
```

Common operators:

```text
|   parallel
>   preference / comparison
→   change / migration
=   same
≠   not same
```

## Style Strategy

Default style:

```text
文言优先，白话兜底
```

Meaning:

- if classical phrasing makes the line shorter without changing meaning, prefer it
- if classical phrasing introduces ambiguity, immediately fall back to plain Chinese
- compression is for expression, not for removing semantic boundary

Never classicalize these by force:

- shell commands
- file paths
- enum values
- error messages
- acceptance criteria
- `未定义` / `禁推` boundaries
- commit ids, URLs, code symbols, API names

Mixed style is allowed:

- stable field keys
- values may mix 文言, 白话, English, paths, hashes

Judgment rule:

```text
能简而不歧，则从文言；一有歧义，立退白话
```

## Core Field Families

For workflow usage, the most useful fields are:

```text
题 时 态 项 决 因 风 待 评 源
```

Suggested meaning:

- `题`: topic / entry key
- `时`: time
- `态`: state
- `项`: concrete work item
- `决`: decision
- `因`: reason
- `风`: risk
- `待`: pending action
- `评`: judgment / conclusion / inference
- `源`: source

## Constraint Fields

Use these when the user needs explicit protocol boundary:

```text
真 枚 必 选 恢 未定义 禁推 扩展
```

Suggested meaning:

- `真`: truth source
- `枚`: valid enum
- `必`: required fields
- `选`: optional fields
- `恢`: recovery path
- `未定义`: intentionally undefined area
- `禁推`: do not infer beyond source
- `扩展`: not in current profile but allowed later

## Chain Layer

Use chain-layer only when relation matters.

Recommended fields:

```text
点 链 依 承 弧
```

Use them like:

```text
点0: 类=DECISION | 决=Clerk>Auth0 | 因=价低+DX佳
点1: 类=TECHNICAL | 待=下轮推Clerk
链: 点0<->点1 | 关=supports
```

Minimal relation types:

```text
supports
depends_on
contradicts
follows
same_topic
```

Rule:

```text
链层只连，不推
```

## Source Layer

Long-lived compressed notes should always have source.

At minimum, keep:

```text
源
时
```

If source is missing, the note is weak memory, not strong memory.

## Where AAAK Fits In This Skill

Inside `agata-code-workflow`, AAAK should be used as a dense body block, not as the task truth source.

Keep this split:

- filename -> workflow state truth
- front matter -> control fields (`owner`, `accept`, `verify`, etc.)
- AAAK block -> dense semantic summary
- normal markdown -> commands, exceptions, long explanations

## Practical Rule

Use AAAK when compression helps.

Do not force AAAK for every paragraph.

Best fit:

- `rs` conclusions
- `rv` review exchanges
- top summary block in `tk`
- project memory notes

Weak fit:

- operator procedures
- long command walkthroughs
- high-stakes legal or evidence text
