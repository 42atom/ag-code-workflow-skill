### coder workflow rule

## 1. 主链

工作流只认三条主链：

- 研究 -> Plan -> 实现 -> 验证 -> 关闭
- Bug -> 理解 -> 分析 -> 计划 -> 修复 -> 验证
- 派单 -> Plan -> 拆分 -> 派发 -> 跟踪 -> 验收

原则：

- 不新增无职责文件
- 不让索引页承载状态真相
- 文件名状态槽是唯一状态真相源
- 默认单 agent 直推主链；阶段标签用于表达进度，不是审批闸门
- 排单覆盖表只读，不承载状态；必须从当前 `issues/` 生成；发现缺口先整理真相源，再进入实现
- review 深度跟风险走；跨进程、持久化、状态机、生命周期、合同变更不能只靠浅层单测背书
- 用户明确要求多 agent / 子代理时，主控 agent 可以派发实现和审阅，但主控 agent 仍是唯一裁决者
- DAG 依赖边不进入状态槽；状态表达生命周期，依赖表达 ready 条件

## 2. 真相源

真相源统一为：

- `issues/`

规则：

- 不再使用 `docs/plan/issues/` 这类历史路径
- `docs/plan/` 只作 legacy 只读目录；不新增、不作为活跃真相、不参与 `task.sh check` 的活跃语义
- 仍有价值的旧 `docs/plan/*` 迁到 `issues/pl...`；无继续价值的归入 `docs/archive/legacy-plan/`
- `docs/progress/` 是 task-scoped 执行 workpad，不是第二套 issue 系统
- `refs/agent-names.md` 是 agent 名字登记，只解决人类呼叫名到 `sid` 的映射；不是任务状态
- `refs/radar.md` 是观察点日志，只记录“真实但尚未立项”的工程雷达点；不是 backlog、review、progress 或 memory
- `refs/graph.md` 是 context synthesis 关系图；不是任务状态、owner 或 completion 真相
- `aidocs/` 只作 AI 协作暂存区，不是真相源，不参与 workflow id、状态、review、memory 判断
- `active-mainline.md` 只做导航，不承载状态
- `issues/` 根目录是 live working set 加最近 `dne` 缓冲；旧 `dne` 物理归档到 `issues/archive/YYYY/`，状态仍保持 `dne`
- 目录表达冷热层，文件名状态槽表达生命周期；不要因为文件进了 archive 目录就再改状态槽
- 默认读取面只包括 `issues/` 根目录、当前 controlling issue、同父 `rv` / progress、相关 radar 条目、相关 memory 锚点；不得无触发全量读取 archive 正文
- 工具可以扫描 archive 路径做 id、唯一性、依赖和链接校验；路径扫描不是正文阅读
- 状态变更只改 `tk` 文件名，不靠正文或索引页
- 若目标项目要偏离这条真相路径，必须有项目级 `AGENTS.md` / `CLAUDE.md` 或当前控制面真相的明确证据；零散历史文件不足以推翻共享规则

## 3. 文档命名

统一格式：

`<kind><id-NNNN|NNNNN>.<state>.<board>.<slug>[.<prio>].md`

kind：

- `tk` = task
- `rs` = research
- `rf` = ref
- `rv` = issue-scoped review exchange record
- `pg` = 只读视图里的 progress 记录；文件名前缀不用 `pg`
- `rp` = legacy global review record; read-only compatibility for old projects
- `pl` = plan

禁止新增 `bl` kind。Backlog 不是文件类型，而是 `tk.tdo` 这一个状态切面。

state：

- `tdo`
- `doi`
- `dne`
- `bkd`
- `cand`
- `arvd`

语义：

- `tdo` = 待办池；可包含尚未 ready 的 DAG 节点
- `doi` = 正在执行
- `dne` = 已完成
- `bkd` = 已推进后被阻塞，保留冻结现场
- `cand` = 退出活跃必做图 / 取消 / 暂不做；不是 candidate backlog
- `arvd` = 历史归档

规则：

- `id` 永远在最前
- `id` 支持 4 位或 5 位数字；现有 4 位文件无需迁移
- `tk` / `pl` / `rs` / `rf` 共享全局数字命名空间；`kind` 是类型，不是编号命名空间
- archive 中的历史 issue 也占号；新建文件不得复用冷历史数字
- 历史跨 kind 同号可在迁移期 warning；新发号必须避开
- 同一 `kind` 内不允许裸数字碰撞；禁止 `tk0001` 与 `tk00001` 共存，禁止 `pl0001` 与 `pl00001` 共存
- `board` 用模块短词或场景码
- `board` 不得使用 `tdo` / `doi` / `rvw` / `dne` / `bkd` / `cand` / `arvd` 这类状态保留词；`rvw` 已退休但仍保留，避免旧状态歧义
- `slug` 只允许 `[a-z0-9-]`
- owner / 时间 / 原因进 front matter，不进文件名
- 文档引用必须使用稳定锚点，不引用带状态位的完整文件名

## 4. 语义映射

- `pl` = 需求讨论 / spec / proposal
- `rs` = 调研 / 事实收集 / 可行性分析
- `tk` = 正式执行任务，等价于 issue
- `rv` = 一次性 review 交换消息，等价于 PR review thread 内的一条消息
- `rp` = 旧式全局 review 记录；新增 review 默认不用它
- `commit / branch` = 实现轨迹，不承载任务状态真相
- `docs/progress/<tk-id>.sNN-<slug>.<state>.md` = 任务执行 workpad；不承载父任务状态真相
- `refs/radar.md` = 观察点孵化器；不承载任务状态真相

规则：

- 需求未收敛，先落 `pl`
- 需要摸底验证，落 `rs`
- 范围和验收清楚后，才创建 `tk`
- review 讨论、阻断点、回合往返，都落 `rv`
- 读取完整 review thread 时用 `cat docs/reviews/<issue-id>.rvNNN-r*.md`；不要为了阅读方便把多条 `rv` 合成一个可写文件
- `pl` 不是 backlog；backlog 是已收敛但未开做的 `tk.tdo`
- 受资料启发但事实未明，先落 `rs`
- 有方向但不适合马上执行，落 `pl` 并保持 `tdo`
- 立刻可执行且验收清楚，落 `tk.tdo`，认领后进 `tk.doi`
- 未来必做但依赖未满足，仍落 `tk.tdo`，用 `depends_on` 写前置；不得用 `cand` 表示 DAG 等待
- 资料原文、设计参考、AI 草稿、生成报告，先放 `aidocs/`；稳定后再迁到 `issues/`、`docs/reviews/`、`docs/progress/`、`refs/radar.md`、`refs/graph.md`、`refs/project-memory-aaak.md`、`docs/` 或产品资源目录
- 子代理原始输出、失败记录、半成品回传，先放 `aidocs/agent-runs/`；只有主控 agent 裁决后，才提升到 `tk` / `rv` / memory / mainline
- 综合审计、最近 N 小时审计、全仓审计、跨任务 review、没有唯一父 issue 的审阅，先放 `aidocs/agent-runs/`；它们是低信任审计材料，不是正式 review
- 综合审计经主控 triage 后，每条 finding 只能三种去向：`reject` 留在原始材料，`attach` 到已有父 issue 的 `rv`，或 `split` 成一个具体 `tk`
- `docs/reviews/` 只接收有且只有一个父 issue 的 exchange message；`recent-audit.rv001-r001-reviewer.md` 这类无父 issue 文件非法
- 长任务执行过程、阶段性验证、接手信息，落 `docs/progress/`；不要让它们只留在聊天转发里
- 批量从 `pl` 拆 `tk` 前，必须先输出只读覆盖表：`计划条款 -> 承接 tk -> 状态 -> dispatch/action -> 缺口`
- 计划条款没有承接 `tk` 的，标为缺口；不得靠聊天记忆派实现
- `tk` 只覆盖计划一部分时，必须写明剩余条款是另拆、延后，还是明确不做
- 覆盖表必须按当前 `issues/` 重算；若表格与文件名状态冲突，表格作废，不得作为决策依据
- `dispatch/action` 只写 `closed` / `active` / `dispatchable` / `blocked` / `gap` / `evidence-only`；已 `dne` / `arvd` 的行不写“否”
- 审计材料归档、raw review 存放、links 整理属于过程证据，不是计划条款；除非目标就是修改 workflow，否则不要为它们单独拆 `tk`
- 单独拆 `tk` 必须有独立范围、owner、验证和关闭价值；一行断言、小 hardening、review nit 应挂父 `tk` 的 `Completion Bar` 或并入下一张自然 hardening 单
- 新建 `tk` / `pl` / `rs` / `rf` / `rv` 前，先查当前 `issues/`、`docs/reviews/`、相关 radar 和相关记忆，确认不是同 scope 重复立项
- 去重先看 live root 与 memory；只有 direct anchor、回归考古、用户问历史、或根目录加 memory 仍无法判定时，才打开 archive 正文
- `task.sh new` 只负责唯一发号，不负责语义去重；scope 去重必须由操作者读取真相源后判断
- `task.sh new` 按 `tk` / `pl` / `rs` / `rf` 共享数字命名空间发号；kind 是类型，不是编号命名空间
- `task.sh new` 用 `.ag-new-id.lock` 做原子 ID 分配锁；并发看到 busy 就重跑，不手扫 max id
- `.ag-new-id.lock/owner` 的 `pid` 仍存活才算 busy；pid 已消失的孤儿锁由 helper 清理后重试
- `task.sh` 是 workflow 底座，不依赖 Python 运行时；文件扫描、排序、frontmatter 小改动用 bash / awk / find / sort
- 新增 IPC、事件、channel、protocol、projection 或跨边界合同前，必须明确三类 owner：谁定义、谁生产、谁消费；缺任一角色视为计划缺口，不进入实现

稳定引用规则：

- issue 引用用 `tk0001` / `pl0001` / `rs0001` / `rf0001`
- legacy review 引用用 `rp0001`
- issue-scoped review 引用用 `tk0001.rv001-r001-reviewer`
- progress 引用用 `tk0001.s01-repro`
- 禁止在 `links` 写 `tk0001.tdo.*.md`、`tk0001.doi.*.md`、`rp0001.dne.*.md` 或 `tk0001.s01-repro.dne.md`
- 文件名是瞬时投影；id 才是永久锚点
- `docs/plan/` 旧链接只作为 legacy 迁移材料容忍，不作为新规则样板
- 迁移期 `task.sh check` 默认警告状态全名链接；设置 `AG_STRICT_STABLE_LINKS=1` 时失败

默认 front matter：

```yaml
owner: user
assignee: agent
recap: "核:TODO|界:TODO|验:TODO|下:TODO"
why: TODO
scope: TODO
risk: low
accept: TODO
memory: none
depends_on: []
links: []
```

规则：

- `recap` 是一行 AAAK 风格索引，用来省上下文 token；不是第二套真相
- `depends_on` 只写 DAG 前置边
- `links` 只挂证据、参考、review/progress/memory 锚点或相关文档
- 默认不写 `reviewer`；审阅者是运行时参与者，正式审阅事实在 `rv` 文件名和正文里
- `claimed_*` 只在 `doi` claim 后出现；`code_version` / `verify` 只在收尾证据里出现

DAG 依赖写法：

```yaml
depends_on:
  - tk0001
  - pl0002
ready_when:
  - tk0001.dne
  - pl0002.dne
```

规则：

- `depends_on` 是机器可读依赖边，只放 `tk` / `pl` / `rs` / `rf` id
- `ready_when` 是人读说明，可选，不作状态真相
- `tdo + depends_on 未满足` = 待办池里的 DAG-blocked 节点
- `tdo + depends_on 已满足或为空` = 可考虑派发
- `bkd` 只给已推进后被阻塞并需冻结现场的 issue
- `cand` 不表示“候选必做”，不表示“依赖未满足”；未来必做不用它

## 4.1 Progress Workpad

命名：

```text
docs/progress/tk0001.s01-repro.dne.md
docs/progress/tk0001.s02-fix.dne.md
docs/progress/tk0001.s03-verify.doi.md
```

格式：

```text
<tk-id>.sNN-<slug>.<state>.md
```

状态：

- `tdo`
- `doi`
- `dne`
- `bkd`

规则：

- progress 只挂 `tk`，不挂 `pl` / `rs` / `rf`
- progress state 是步骤状态，不是父 `tk` 状态
- 同一 `tk` 最多一个 progress 为 `doi`
- 父 `tk` 进入 `dne` / `cand` / `arvd` 前，所有 progress 必须为 `dne`
- progress 文件必须放在共享控制面，不能只留在 task worktree
- progress 可以被父 `tk.links` 以稳定锚 `tk0001.s01-repro` 引用，但是否关单仍看父 `tk`

最小内容：

```md
# tk0001.s03-verify

env: <host>:<abs-workdir>@<short-sha>

## Done
已完成内容。

## Verify
验证命令与结果。

## Next
下一刀或交接点。

## Risk
阻塞、疑点、未验证项。
```

收口检查放父 `tk`，不是 progress：

- `accept` = 任务契约
- `Completion Bar` = 关单 checklist
- progress 只作证据，不作关单权威

```md
## Completion Bar
- [ ] progress drained
- [ ] acceptance met
- [ ] focused tests pass
- [ ] typecheck/build pass
- [ ] review blockers resolved
- [ ] PR / inline / bot feedback swept
- [ ] implementation drained to target mainline
- [ ] task.sh check pass
- [ ] worktree ready for cleanup
```

`bkd` progress 或父 `tk.bkd` 必须写 blocker brief：

```md
## Blocker
missing:
impact:
tried:
unblock_action:
```

## 4.2 主控派发闭环

只在用户明确要求“派发给子代理 / 多 agent 完成 / 并行审阅”时启用。默认仍是单 agent 直推主链。

主控规则：

- 主控 agent 拥有最终裁决权；子代理只拥有被派发的文件、模块、验证面或审阅面
- 派发前必须有 controlling `tk` / `pl`；禁止先让子代理实现，事后补任务真相
- 派发内容必须写清：任务、真相源、范围、非范围、验收、验证、回传格式
- 实现子代理只回传代码结果、验证证据、未完成项和接手说明；不直接关闭 `tk`
- 审阅子代理只产出 `rv` 或原始审阅回传；不直接移动 controlling issue 状态
- 阻断 review 必须由主控 agent 裁决：修复、驳回、转新 `tk`、继续复审，或请求用户决策
- `dne` 只能由主控 agent 在代码已进 mainline、阻断 review 已处理、验证已写回、`task.sh check` 通过后执行

失败接管：

- 默认子代理会失败；失败不是用户转发责任
- 子代理原始失败输出落 `aidocs/agent-runs/<issue-id>.<role>-<agent>-<timestamp>.md`
- `aidocs/agent-runs/` 低可信，只作恢复材料，不是真相源
- 失败回传至少写：尝试了什么、改了什么、验证了什么、失败在哪里、下一位如何接手
- 子代理失联或输出不可用时，主控 agent 读 controlling issue、git diff、worktree 状态和 `aidocs/agent-runs/` 后直接接手或缩小范围重派
- 同一失败不允许无限重试；一次恢复周期后，主控 agent 必须接手、重派更小 scope，或把 controlling issue 标 `bkd` 并写明阻断
- 只有主控 agent 提升后的内容才进入 `tk` / `rv` / memory / mainline

## 5. Agent 名字

允许在仓库内放：

- `refs/agent-names.md`

它的职责只有一个：

- 记录用户给 agent session 的命名语义

它不负责：

- 任务状态
- 在线状态
- 心跳
- 调度权限
- 长期人格画像

最小格式：

```md
# Agent Names

## Bindings

| name | sid | slot | engine | role | binding | note |
|---|---|---|---|---|---|---|
| ana | sid019dd9af | A | current-runtime | ui | thread:019dd9af... | continue tk0001 |

## Pool

- ana
- ben
- cal
- nia
```

规则：

- `name` 是人类输入层，不是唯一身份
- `sid` 是本轮上下文的唯一追责锚
- 日常身份初始化只问 `name`，不要主动把 `sid` 暴露给用户；`sid` 只用于文件、review author、commit trailer
- `engine` 必须写当前 runtime，如 `current-runtime` / `alternate-runtime` / `review-runtime`；不要照抄示例值
- 有物理 thread id 时，从 thread id 派生 `sid`，如 `sid019dd9af`；不从 `refs/agent-names.md` 顺序发号
- 没有 thread id 时，用时间戳加短随机或本地唯一后缀派生 `sid`，如 `sid260517-ab3d`；禁止全局纯自增
- `slot` 是可选口头槽位，如 `A` / `B` / `C`
- `binding` 是物理证据，如 `thread:<id>`
- 同一 `sid` 出现多行时，以 `refs/agent-names.md` 中最新一行为当前人名映射
- 不写 `online` / `offline`；没有心跳，就没有活跃状态
- `references/agent-names-lib.md` 只是参考名字库；项目可自由增删 `Pool`
- session 启动时不自动写 `refs/agent-names.md`
- 交互式新 session 应主动问用户要一个新名字或继承旧名字；只问 `name`，不提 `sid`
- 非交互或后台任务不询问、不占名，只用 `sid`
- 用户说“继续 ana 的工作”时，追加新行：`name=ana`、当前 `sid`、`note=continue ...`
- 用户说“取个新名字”时，只在交互场景从项目 `Pool` 取第一个未绑定过的名字
- `Pool` 耗尽时不自动造名，继续用 `sid`，提示用户后续补名字
- 用户指定自定义名时，先查冲突；已存在则在交互场景问继承还是重置，非交互场景只用 `sid`
- 已知 `sid` 时，通过 `AG_CLAIMANT` 让 `claimed_by`、review author、commit trailer 写 `sid`；未传入时 helper 回退到 `assignee` / `owner`
- `name` 只辅助人读
- 文件变长时允许人工裁剪或归档旧行，只保留近期有用映射；旧映射由 Git 历史承担审计

## 6. 历史记忆层

允许在仓库内放：

- `refs/project-memory-aaak.md`

它的职责只有一个：

- 承载低噪声、高密度的项目历史记忆

规则：

- 它是历史入口，不是任务状态真相
- 与当前状态冲突时，以 `issues/` 与证据链为准
- 只记里程碑、关键决策、流程迁移、冻结节点、关键阻断
- 不记逐条流水账，不替代 `tk` / `rv`
- 稳定的架构审查判断、冻结点、反复出现的风险规则，应在对后续对话仍有价值时写入 memory

记忆 front matter 扩展：

- `memory: none | required | done`

语义：

- `none` = 不要求进入项目历史记忆
- `required` = 关闭前必须写入 `refs/project-memory-aaak.md`
- `done` = 已写入项目历史记忆，且记忆文件必须能回指该任务
- 新建 `pl` / `rs` / `tk` 时，不因为“顺手一起落盘”就提前写 memory；只有形成稳定里程碑、关键决策，或任务明确要求 `memory: required` 时才写

记忆锚点：

- 对带 `memory: required | done` 的任务，记忆文件必须显式写 `锚: tkNNNN` / `锚：tkNNNN` 或 `锚: tkNNNNN` / `锚：tkNNNNN`
- 只认稳定 id 锚点，不认正文里偶然出现一次的 task id

## 6.1 Graph 关系图

文件：

- `refs/graph.md`

职责：

- 保存长期稳定 typed relations，帮助 context synthesis 少猜
- 作为可读、可编辑、可版本控制的关系图

禁止：

- 不承载 task status / owner / completion
- 不复制 plan coverage state
- 不替代 `depends_on` / `links` / `rv` / progress / radar
- 不把生成的 HTML / JSON 当 workflow truth

规则：

- node state 只从文件名解析
- graph 输出若和 `issues/` 冲突，永远以 `issues/` 为准
- 新 entity 必须满足：被 3 个以上稳定文档/任务反复引用，或是多个 entity 的关系枢纽，或不写会导致 context synthesis 靠猜
- 默认边类型只允许：`type`、`defined_by`、`uses`、`used_by`、`avoids`、`related_to`、`separate_from`、`records`、`updated`
- 不得新增 entity 或 edge type，除非现有 entity / field 无法表达

## 6.2 Radar 观察点

文件：

- `refs/radar.md`

职责：

- 记录观察到、但尚未值得立项的工程点
- 给后续 triage 提供小抄
- 在触发条件满足时孵化为 `tk`

禁止：

- 不当 backlog
- 不替代 `issues/`
- 不写阻断 review 结论
- 不替代 progress
- 不承载长期架构记忆

状态：

- `watching` = 持续观察
- `promoted` = 已升格为具体 `tk`
- `dropped` = 判断为噪声或不再相关

规则：

- 单文件优先：默认只用 `refs/radar.md`
- 不按域提前拆 `radar-ui.md` / `radar-runtime.md`
- scope 写进 `域:` 字段
- 只有当 `watching` 超过 80 条、文件超过 2000 行、单域超过 50 条，或清理 radar 本身变贵时，才考虑物理拆分
- 每条必须有 `触:`；没有触发条件，不写 radar
- 触发后开 `tk`，把 `态:` 改为 `promoted`，补 `升: tkNNNN`
- 被证伪或不再值得跟踪，改 `态: dropped`，补一行原因
- 稳定架构判断进 `refs/project-memory-aaak.md`，不进 radar
- 阻断项回 controlling `tk` / `rv`，不进 radar

最小格式：

```md
## ob20260517-001 local-storage-read-helper-dup

时: 2026-05-17
源: tk0001
域: ui
位: module-a / module-b
观: localStorage read helpers are duplicated.
判: not worth a task until reuse grows.
触: third copy appears or defaults diverge again.
动: promote to shared ui helper task.
态: watching
```

## 7. 状态与评审规则

任务主流状态：

`tdo -> doi -> dne`

补充：

- 任意中间态可进 `bkd`
- 任意非终态可进 `cand`
- `dne` / `cand` 可选进 `arvd`
- `dne -> doi` 只能走 `task.sh reopen <id> <reason>`，不属于普通 `move`

重开规则：

- 刚关单后，review / smoke / 用户验收发现同一任务线仍需修复，应直接 `reopen`，不等归档
- 验证证据失效、实现遗漏、同范围缺口、后关单即时审查问题，都属于 `reopen`
- 新需求、新 owner、新模块、新验收线、后续别的改动引入的回归，一律新建 `tk` 并链接旧单
- 如果原单在 `issues/archive/YYYY/`，`reopen` 先把它移回 `issues/` 根目录，再改为 `doi`
- 旧 `code_version` / `verify` 保留为历史关闭证据；再次收口时写新的关闭证据

任务与评审分工：

- `tk` 负责状态推进
- `rv` 负责评审交换证据
- `rv` 不替代 `tk`
- 新增 review 默认使用 `docs/reviews/<issue-id>.rvMMM-rNNN-author.md`
- 旧 `rpNNNN` 只作历史兼容；不再作为新增 review 主线
- 综合审计不写 `rv`，除非主控已经把某条 finding 绑定到一个具体父 issue
- review 结论要回写到 `tk`
- review 是 `rv` 证据链，不是 `tk` 状态；`tk` 保持在 `doi` 直到 owner 修完阻断并关闭
- review 按风险排深度；跨进程通信、持久化、状态机、生命周期、合同变更优先深审，纯投影或纯 UI 可轻审
- review 必须主动搜索重复路径：同一 `id` / `ref` / `result` / `status` / owner / 恢复链 / prompt surface / UI-debug surface 是否被两条路径同时生产或消费
- 发现双写、双读、双 surface 时默认阻断；除非 controlling `tk` 或 `pl` 明确写清唯一 owner 与旧路径退出计划

review 命名规则：

- 评审文档必须 parent-first
- 禁止 `re.` / `re.re.` 链式命名
- 新增 review 文件统一格式：`<issue-id>.rvMMM-rNNN-author.md`
- `<issue-id>` 是父 `tk` / `pl` / `rs` / `rf`；`rvMMM` 是同一问题线；`rNNN` 是该问题线内的第 N 次交换；`author` 是写入者
- 一次发言一份文件；同一问题线继续同一个 `rvMMM`，新问题线才开新的 `rvMMM`
- `rv` 一经成文默认冻结；新回合新增新文件，不回头改旧 `rv`
- 旧 `rpNNNN.state.board.review-rNNN-author.md` / `reply-rNNN-author.md` 文件可读可查，但新增不再使用

审核隔离规则：

- 审核时允许使用 `git worktree` 拉出独立工作目录，避免和实现中的工作区互相打架
- `worktree` 只是隔离执行环境，不是第二套任务真相源；状态、结论、往返记录仍回写 `tk` / `rv`
- 当前 worktree 必须使用本地依赖面验证；不允许拿 A 工作树的 `node_modules`、生成物或验证结果给 B 工作树背书
- 不要求每次机械重装依赖；先判断当前 worktree 的 `node_modules` / tool binary 是否存在且与 lockfile 匹配
- 若依赖缺失或 stale，再在当前 worktree 内跑确定性安装：`pnpm install --frozen-lockfile` / `npm ci` / `yarn install --frozen-lockfile`
- npm/pnpm/yarn 全局缓存可复用；缓存不是验证真相，当前 worktree 的依赖树才是验证面

工作树语义规则：

- 一个活跃 task 默认对应一个专属 worktree
- 主 checkout 是共享控制面；helper 可从 linked worktree 调用并把真相写回主 checkout
- `issues/`、`docs/reviews/`、`docs/progress/`、`refs/agent-names.md`、`refs/radar.md`、`refs/graph.md`、`refs/project-memory-aaak.md` 的权威改动只落在共享控制面
- linked worktree 里的这些 truth path 只是该分支镜像，不是权威真相视图
- linked task worktree 若需要写验证记录、review 草稿或实现笔记，先写在非真相路径；不得直接改上述真相路径里的正式文件
- `tdo -> doi`、`doi -> bkd|cand|dne`、`rv` 新建/回合推进、memory 锚点、派单更新都属于控制面动作，必须先在主 checkout 落盘
- 创建 `task/tkNNNN-*` 分支或对应 task worktree 前，`issues/` 里必须已存在同号 controlling `tk`；禁止先实现后补真相
- 创建 review 分支或 review worktree 前，必须已存在同号 controlling `tk` 与目标 review 轮次真相
- 分支名表达工作流角色，不表达执行者身份；默认用 `task/tkNNNN-<slug>`、`review/tkNNNN-<slug>`、`salvage/<name>`、`release/<version>`，项目级规则可收窄但不应退回 agent 身份命名
- task / review / salvage worktree 默认放在仓库目录外部的项目级 worktree 根下；禁止放进被编辑仓库内部，也不要平铺在仓库同级制造混乱
- `doi` 落盘后，才在该 task 的专属 worktree 中推进实现
- task worktree 只做代码、测试、生成物和临时草稿，不偷偷改 workflow 状态槽，不把自己当第二控制面
- `task.sh ls` / `find` / `show` / `new` / `review` / `progress` / `move` / `archive` / `prune` 默认穿透到共享控制面，不以当前 linked worktree 里的镜像 truth path 为准
- `task.sh check` 例外：只有“当前 worktree 有没有 truth 污染”这一刀留在本地；重复 id、review 约束、memory、staleness 等全局语义仍由共享控制面裁决
- `task.sh check` 通过只说明工作流语义合法，不说明当前共享控制面上的所有脏改都属于你
- 状态槽迁移默认走 `task.sh move`；只有 helper 明确表达不了合法 rename 时，才允许手动改同一文件的状态槽
- 手动状态槽 rename 仍必须满足同一套状态机；`cand -> dne`、`dne -> doi` 这类非法转移不能借 `git mv` 绕过
- 手动状态槽 rename 后必须立刻跑 `task.sh check`，并在回传里说明这是 helper gap，不把手动路径常态化
- helper 保持薄，不自动暂存 Git index；Git rename 血统用于诊断，不是工作流真相
- 同一 task line 的控制面写操作必须串行；不得对同一 task 预发多个 `move`，每次状态落盘后都要重读真相与 gate，再决定下一跳
- `task.sh orphan-scan` 例外：它既看当前 worktree 的 truth 漂移，也看共享 refs 的差异
- 单任务 worktree 在执行中可以是脏的，这是正常态
- 进入 `dne`、准备合并或 `prune` 前，必须相对目标 `base-ref` 检查真相漂移与执行差异；明显过期的 worktree 先对齐，再继续推进
- 同一 worktree 出现多个 task 的实现改动，或出现当前 task 之外的无关修改 / 未跟踪文件，视为污染
- 切任务 = 切 worktree，不继续复用当前脏树
- 平行 task worktree 默认双盲；一个 task worktree 不得直接依赖另一个 task worktree 的未落地代码、生成物、本地服务端口或数据库状态
- 跨 task 交付、协作或 review 邀请，必须先落成控制面可见的共享证据，再由接收方消费；禁止通过跨目录读取另一个 task worktree 走私中间态
- 复审可在独立 review worktree 中做验证，但 `tk` / `rv` 结论仍回主 checkout 落盘
- 代码任务收口顺序固定：专属 worktree 完成实现与验证 -> 代码并回目标主线 -> 主单推进到 `dne` -> `task.sh archive-done --keep 32 --yes` -> 清理该任务的 worktree 与本地分支
- `dne` 不表示“代码仍留在 task worktree”；若实现尚未并回目标主线，禁止关单后直接删树
- 同一 task 续做时复用原 worktree
- 任务进入 `dne` / `cand` / `arvd` 且已收口后，应移除对应 worktree；`bkd` 可保留 worktree 但冻结，不得混入别的 task
- worktree 收尾是控制面对执行面的最后一次对账，不是顺手删目录
- 优先用 `task.sh prune <task-id> <base-ref>` 收尾；它只做校验和回收，不代替控制面自动改状态
- `prune` 只接受 `dne` / `cand` / `arvd`；`doi` 必须先释放，`bkd` 默认保留冻结现场
- `prune` 前必须满足：主 checkout 的 `task.sh check` 通过、`task.sh orphan-scan <base-ref> <task-id>` 无漂移、目标 linked worktree 干净、且相对 `base-ref` 已无执行差异
- 禁止在“旧进程 + 新代码”混合运行态上给出验证结论；必须先退出旧进程，再在新构建/新运行态上验证
- 跨进程通信、IPC、BroadcastChannel、SharedArrayBuffer、持久化、状态机、生命周期、replay、debug 和合同任务，必须在真实运行边界上提供 smoke / integration 证据；单进程单测不能作为唯一验证
- UI 反馈只表达阶段状态，不反推生命周期真相；完成与失败仍以 controlling task、ledger 或项目定义的唯一真相源为准
- `prune` 不得从目标 worktree 自己内部执行；若当前 shell cwd 落在待删 worktree 内，必须先 `cd` 出去
- `prune` 成功时同时回收 linked worktree 和对应本地 branch；默认不碰 remote branch
- worktree 只是执行空间，不是任务真相源

共享真相可达性规则：

- `pl` 与任何 `tdo` 态文档属于共享待排期真相，不允许只存在于临时 task worktree / snapshot branch
- 共享控制面上，`issues/`、`docs/reviews/`、`docs/progress/`、`refs/agent-names.md`、`refs/radar.md`、`refs/graph.md`、`refs/project-memory-aaak.md` 的无关脏改，以及未跟踪 `tk` / `pl` / `rs` / `rf` / `rv` 文件，默认视为外来活动线，不叫“噪声”
- 判断外来活动线时，先看 task id、state、`claimed_at`、`claimed_by`、`claimed_thread_id`、links、相邻 review / radar / memory / agent-name 锚点；没有证据前，不得擅自当成废稿或顺手并入当前提交
- 未经明确接管，不得删除、改名、暂存或提交外来活动线；当前提交只收自己的真相改动，别线单独报告
- 若某个 task worktree 中出现了只在本地可见的 `doi` / `rv` / memory 改动，视为控制面漂移；必须先收回主 checkout，再继续执行
- 清理 worktree / 删除快照分支前，必须先跑 `task.sh orphan-scan <base-ref>`；只要它报出 `issues/`、`docs/reviews/`、`docs/progress/`、`refs/radar.md`、`refs/graph.md`、`refs/project-memory-aaak.md` 的漂移，就不能直接清理
- 若项目记忆、review、progress 或 git 历史提到某个 `tk` / `pl` / `rs` / `rf` / `rv`，但当前真相源找不到，先跑 `task.sh orphan-scan <base-ref> <id>`，再用 `git log --all` / `git grep` 追溯；禁止直接假定它不存在
- 任何 `tkNNNN-*` 测试文件命名前，必须确认 `issues/` 中已有同号 controlling `tk`
- 若测试只是服务已有主单的 source-lock、回归或结构断言，不得新占一个 task id；复用 owner task 号或使用非 task-id 命名

工作树状态判断：

- `干净`
- `单任务脏，可继续`
- `污染，必须切分`

例子：

- `tk0001.rv001-r001-current-runtime.md`
- `tk0001.rv001-r002-author-a.md`
- `tk0001.rv001-r003-current-runtime.md`

## 8. dne 关闭门槛

代码任务进入 `dne` 前，至少要有：

- `accept`
- `verify`
- `code_version`

没有这些证据，不算真正关闭。

补充：

- `accept` / `code_version` / `verify` 不能为空值
- `verify` 是验证口径或命令，不是“已测试”这类空话
- `verify` 可写成多行块，比如 `verify: |`
- `links` 可写成 inline 数组，也可写成缩进列表
- 如果发生 review，任务至少要有同父任务前缀的 `rv` 证据文件，或挂接 legacy `rp` 证据链接
- 所有关联 `rv` / legacy `rp` 的阻断意见必须已回复或由 controlling owner 明确裁决
- 如果存在 `docs/progress/<tk-id>.*`，所有 progress 必须已 drain 到 `dne`
- 如果存在 PR、inline review 或 bot feedback，关闭前必须 sweep，并在父 `tk` 里写明处理结果
- 如果任务涉及跨进程、持久化、状态机、生命周期或合同变更，`verify` 必须写明真实运行边界的 smoke / integration 命令或证据位置

## 8.1 归档残留

规则：

- `arvd` 是终态，不应残留在 `issues/` 根目录
- 归档后的任务应位于 `issues/archive/YYYY/`
- `check` 发现根目录 `{tk,pl,rs,rf}*.arvd.*.md` 时必须失败
- `dne` 是完成态，可在根目录保留最近缓冲；收尾最后一步运行 `task.sh archive-done --keep 32 --yes`
- `archive-done` 只做物理归档，不把 `.dne.` 改成 `.arvd.`
- `issues/archive/YYYY/` 已经说明文件是冷历史；不需要再用文件名重复表达“已归档”
- `task.sh check` 不自动移动 `dne` 文件，最多由操作者显式清理上下文
- `task.sh archive` 只服务 legacy / manual `.arvd.` 冷归档；普通 done 收口不要用它

## 9. 提交规范

commit：

`{action}({board}): {slug}  [tkNNNN]` 或 `{action}({board}): {slug}  [tkNNNNN]`

branch：

`task/tkNNNN-<slug>` / `review/tkNNNN-<slug>` / `salvage/<name>` / `release/<version>`

action：

- `feat`
- `fix`
- `refactor`
- `test`
- `plan`
- `pass`
- `report`
- `proto`
- `docs`
- `chore`

规则：

- 有 task 就必须带 `[tkNNNN]` 或 `[tkNNNNN]`
- `board` 必须和任务文件第三槽一致
- 需要验收时在 commit body 追加 `Reviewed-by`
- 任务分支不使用 agent 身份命名；执行者写入 front matter、claim 字段或 review 记录，不写进长期分支语义
- 版本号只用于 `release/*`，不塞进长期开发分支或日常任务分支

## 9.1 发号与认领保活

规则：

- 新建 `tk` / `pl` / `rs` / `rf` 时，优先走 `task.sh new`，由共享控制面按全局数字命名空间分配下一个可用 id
- 新建 `rv` 时走 `task.sh review <issue-id> <rvNNN> <rNNN-author>`，不走全局发号
- review 结果槽变更走 `task.sh review-result <issue-id.rvNNN-rNNN-author> <block|pass|note>`，只改 outcome 槽并同步 frontmatter `result`
- 新建 progress 时走 `task.sh progress <task-id> <sNN-slug> [state]`
- progress 状态槽变更走 `task.sh progress-move <tk-id.sNN-slug> <state>`，不改父任务状态
- `task.sh new` / `task.sh review` / `task.sh progress` 前必须先读相关 `pl` / `rs` / `tk` / `rv` / progress 真相源，确认当前 scope 没有被已有任务覆盖
- 不手工在并发 shell 里做 `max(id)+1` 发号
- `task.sh move <id> <state>` 支持 `tkNNNN` / `plNNNN` / `rsNNNN` / `rfNNNN`，裸数字仍默认 `tkNNNN`
- `task.sh move <id> doi` 会写入 `claimed_at`、`claimed_by`，以及当前 runtime 能提供时的 `claimed_thread_id`
- `task.sh reprio <id> <pN|none>` 只允许 `tdo` / `doi` / `bkd`，只修改文件名优先级槽；`none` 表示移除优先级
- `task.sh reopen <id> <reason>` 只接受当前或已归档的 `dne` issue，写入 `reopened_at` / `reopen_reason`，并重新写入 `claimed_*`
- `move` 是单步控制面动作，不是流水线；尤其 `dne` / `arvd` 这类带 gate 的状态，必须等上一步成功落盘并重读真相后再推进
- `task.sh check` 对缺失 `claimed_at` 或长时间未推进的 `doi` 发警告，不自动回滚、不新增旁路锁文件
- 当多个 agent 共享同一个引擎名（例如都叫 `current-runtime`）时，`claimed_thread_id` 是主识别信号；`claimed_by` 只保留粗粒度身份
- `doi` 超时只触发接管检查，不触发自动回滚；接手前必须检查现场、跑 `task.sh orphan-scan <base-ref> <task-id>`，并在控制面显式改状态或交接

## 9.2 收尾回收

规则：

- `task.sh prune <task-id> <base-ref>` 是薄终结器，不是状态机；它不替你自动推进 `tk`
- 若任务仍在 `doi`，`prune` 必须失败，防止删除活跃认领
- 若任务在 `bkd`，`prune` 默认失败，防止误删冻结现场
- 若任务在 `dne` / `cand` / `arvd`，`prune` 仍要确认目标 linked worktree 已无未提交修改，且相对 `base-ref` 不再携带执行面独有差异
- `prune` 只处理单一明确绑定的 linked worktree；找不到或找到多个都应失败，不替操作者猜

## 9.3 helper 拆分预研

当前不做物理拆分，只记边界：

- 新功能默认不进 `task.sh`；先问能否用 `find` / `cat` / `mv` / `git` 组合解决
- 若必须加 helper，优先删掉同类 helper 复杂度，而不是继续扩张入口
- 将来拆分时按子命令物理拆：`task-new`、`task-move`、`task-review`、`task-progress`、`task-check`
- 拆分目标不是迁移代码位置，而是让每片工具职责小到可直接审计

## 10. 回合收口输出

当本轮形成可报告结果时，回答结尾最后一句给出下一步指向；这不自动意味着当前 agent 停止执行。只允许以下两种格式：

- `[本轮完成，下一阶段：动作(文档落盘/实现/审阅/修复/复审/通过/提交/合并与清理/推送/任务完成/需用户决策...)-目标(当前任务/单号/关键字)]`
- `[本轮已完成(当前任务/单号/关键字)，阶段结束]`

规则：

- 这句必须放在整段回复最后一行
- 这是主链指针，不是停止命令；若下一动作仍由当前 agent 可直接完成，当前 agent 继续推进，不因这句人为停下
- `动作` 只写一个当前主动作，保持短、硬、可执行
- `目标` 只写当前任务、单号或稳定关键字，不写长解释
- 收尾说明只写当前 task 的终态、证据和回收；不替整个 repo、全部 worktree 或别的任务下结论
- 清理结果只写“仅回收当前 task 绑定的 worktree / 本地分支”；不写“只剩根仓”“都清掉了”这类 repo 级表述
- 共享控制面上的别线统一叫“外来活动线”，不叫“噪声”或“无关脏改”
- 若任务已 `dne`，review / smoke / 用户验收发现同一任务线问题，用 `task.sh reopen <id> <reason>`；新增范围另开 `tk`
- 收尾前可选做一次“全场快速扫视”：先看控制面外来活动线，再看执行面 worktree，只报压缩结论，不展开全场明细
- “全场快速扫视”只报外来活动线的 `id/state`，以及外来 worktree 的数量或粗归属；默认明确写“均未接管”
- 只有遇到 `需用户决策`、权限阻塞、高风险确认、证据不足或真实责任切换时，才把它当作真正的停点或交接点
- 若仍需外部拍板，优先使用 `需用户决策`
- 若该阶段已真正收口且无需再推进，使用“阶段结束”格式

例子：

- `[本轮完成，下一阶段：实现-tk0001]`
- `[本轮完成，下一阶段：审阅-tk0001]`
- `[本轮完成，下一阶段：修复-tk0001.rv001]`
- `[本轮完成，下一阶段：提交-tk0001]`
- `[本轮完成，下一阶段：推送-tk0001]`
- `[本轮完成，下一阶段：需用户决策-方案取舍]`
- `[本轮已完成(tk0001)，阶段结束]`
- `tk0001 已收口到 dne。task.sh find tk0001：只指向 dne；task.sh check：ok；task.sh prune tk0001 <base-ref>：ok，仅回收 tk0001 绑定的 worktree 与本地分支。根仓仍有外来活动线，未纳入本次提交。`
- `全场快速扫视：控制面另有 tk0002.doi、pl0003.tdo；执行面仍有 2 个外来 worktree，均未接管。`

## 11. 单任务示例

目录：

```text
issues/
  tk0001.doi.runtime.daily-production-stats-log.p1.md

docs/reviews/
  tk0001.rv001-r001-current-runtime.md
  tk0001.rv001-r002-author-a.md
  tk0001.rv001-r003-current-runtime.md

docs/progress/
  tk0001.s01-repro.dne.md
  tk0001.s02-fix.doi.md

refs/
  agent-names.md
  radar.md
  project-memory-aaak.md

docs/
  operator-checklist-tk0001.md
```

流转：

1. 建任务：`tk0001.tdo...`
2. 开做：`tk0001.doi...`
3. 长任务过程：按需新增 `docs/progress/tk0001.sNN-*.state.md`
4. 首轮评审：新增 `tk0001.rv001-r001-current-runtime.md`
5. 回复评审：新增 `tk0001.rv001-r002-author-a.md`
6. 二轮评审：新增 `tk0001.rv001-r003-current-runtime.md`
7. 修复或回复 review：新增后续 `rv` 或 `progress`，任务仍保持 `tk0001.doi...`
8. 人工关闭：progress 全部 `dne`，任务文件改名 `tk0001.dne...`
