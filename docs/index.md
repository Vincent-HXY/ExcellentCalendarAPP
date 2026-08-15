# ExcellentCalendarAPP 文档索引

## 1. 定位

本文件用于指导 Codex 按任务定向找到强相关资料。

它只负责说明：

- 什么任务应读取什么位置；
- 哪些资料是当前依据，哪些只是历史参考；
- 如何逐步扩大检索范围；
- 何时停止加载上下文并开始开发。

本文件不是架构、领域规则、计划或项目状态的 Source of Truth。最终结论必须来自其指向的权威文档、专项 Skill、机器可验证协议、实际代码和测试。

所有路径均相对于仓库根目录，本文统一使用 `/`；Windows 下等价于 `.\`。

## 2. 每个任务的固定入口

读取当前目录范围内实际生效的 `AGENTS.md` 后，每个独立任务必须按以下顺序开始：

1. 阅读 `docs/architecture/overview.md`，理解项目架构、目录组织、设计理念和硬性要求。
2. 解析任务，明确：
   - 任务类型；
   - 目标行为和验收标准；
   - 相关模块、实体和功能；
   - 可能涉及的层级、调用链和直接依赖；
   - 本次范围外内容；
   - 需要执行的测试、构建或环境验证。
3. 根据本索引选择最小且足够的文档集。
4. 先读当前权威资料，再定位目标代码、直接依赖和测试入口。
5. 只有信息不足、来源冲突、影响范围不清或验证异常时，才逐层扩大搜索。

默认顺序：

> `overview.md` → 任务解析 → 当前权威资料 → 代码与直接依赖 → 测试与构建 → 必要的历史证据

禁止默认全文读取根目录 `README.md`、整个 `docs/`、全部计划、全部 Issue、全部 Review、完整 `docs/log.md` 或无关模块。

## 3. 核心导航表

| 需要了解的内容                     | 首选位置                           | 读取规则                                               |
| ---------------------------------- | ---------------------------------- | ------------------------------------------------------ |
| 项目架构、组织、设计理念和硬性要求 | `docs/architecture/overview.md`    | 每个独立任务必读                                       |
| 某模块、领域实体或数据形式         | `docs/domains/`                    | 按模块名、实体名、字段名和功能关键词定位；不读完整目录 |
| 已确认的重大设计取舍               | `docs/architecture/decisions/`     | 检索与目标模块或决策主题相关的 Accepted ADR            |
| 工具、SDK、依赖和构建版本          | `docs/guides/version.md`           | 版本、依赖、工具链或兼容性任务时读取                   |
| Windows 安装与开发环境配置         | `docs/guides/dev-setup-windows.md` | 安装、环境恢复或环境故障任务时读取                     |
| 构建、测试、smoke test 和验收步骤  | `docs/guides/verification.md`      | 确定或执行验证范围时读取相关章节                       |
| 当前已知问题、缺陷和阻塞           | `docs/issues/open.md`              | Bug、故障排查和风险评估优先读取                        |
| 已解决的相似问题                   | `docs/issues/resolved/`            | 仅在追查相似根因、修复模式或回归时定向读取             |
| 当前正在执行的任务与详细计划       | `docs/plan/active/`                | 功能开发、范围确认和进度任务优先定位对应计划           |
| 过去已完成的开发计划               | `docs/plan/completed/`             | 只作为历史证据；现行资料不足时有限查阅                 |
| 当前项目真实状态                   | `docs/status/current.md`           | 判断能力是否已完成、部分完成、未验证或未开始           |
| 后续方向和阶段规划                 | `docs/status/roadmap.md`           | 讨论未来工作、优先级和依赖顺序时读取                   |
| 当前正在进行的评审                 | `docs/reviews/active/`             | Review 任务优先读取与目标变更相关的内容                |
| 过去相似模块的评审经验             | `docs/reviews/archive/`            | 仅检索相同失败模式、架构问题或历史回归                 |
| 开发日志                           | `docs/log.md`                      | 每个任务结束时追加；正常开发不全文读取                 |
| 临时内容                           | `docs/temp.md`                     | 仅作短期记录，不作为正式依据                           |
| 早期背景或当前文档未覆盖的信息     | `README.md`                        | 最后兜底，只读取相关章节                               |

目录中的文件应先按文件名和关键词筛选，再读取命中章节。目录存在不代表需要读取其中全部文件。

## 4. 按任务类型选择资料

| 任务类型                       | 必须优先读取                                                 | 仅在需要时补充                                               |
| ------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 开发新模块或新增功能           | `overview.md`；目标 `domains/` 文档；相关 Accepted ADR；对应 `plan/active/`；目标代码与测试 | `status/current.md`；`roadmap.md`；相似 completed plan、resolved issue、archived review |
| 修改数据结构、领域规则或持久化 | `overview.md`；对应领域文档；数据所有权、身份、事务、迁移或兼容性 ADR；专项 Skill 和机器可验证定义；读写路径与测试 | 已完成计划和已解决问题中的兼容历史                           |
| 修复 Bug、故障或回归           | `overview.md`；`issues/open.md`；目标领域文档；相关 ADR；复现路径、失败测试和实现 | `issues/resolved/`；对应 active plan；相似 archived review   |
| 了解项目状态或制定计划         | `overview.md`；`status/current.md`；`status/roadmap.md`；相关 `plan/active/` | `plan/completed/` 中的前置工作和历史演进                     |
| 安装、环境或版本问题           | `overview.md`；`version.md`；需要时读取 `dev-setup-windows.md` | 相关验证章节、实际构建配置和失败日志                         |
| 验证、构建或 smoke test        | `overview.md`；`verification.md`；受影响模块文档和构建入口   | 环境指南、版本文档、历史构建问题                             |
| 代码或架构 Review              | `overview.md`；目标领域文档；相关 ADR；对应 active plan；`reviews/active/`；实际 diff 和独立测试 | `reviews/archive/` 中相同模块或失败模式                      |
| 含义不明确或资料冲突           | `overview.md`；目标领域文档；相关 ADR；当前计划、状态、Open Issue 和机器可验证定义 | completed plan、resolved issue、archived review；最后才读 README 或扩大仓库搜索 |

任务涉及跨语言协议、Contract、存储、平台能力或其他专项边界时，应按生效的 `AGENTS.md` 加载对应专项 Skill。本文不重复这些 Skill 的规则。

## 5. 强相关判断

满足以下任一条件的资料通常属于强相关：

- 直接定义目标模块、实体、数据结构或业务规则；
- 直接规定本次涉及的接口、调用链、存储、错误处理或平台行为；
- Accepted ADR 明确约束本次设计选择；
- Active Plan、Open Issue 或 Active Review 明确覆盖当前任务；
- 包含相同方法名、错误码、字段、类、函数、测试或失败模式；
- 给出本次必须执行的版本、安装或验证要求。

以下内容默认不加载：

- 只与目标处于同一技术层、但没有直接依赖的模块；
- 与当前问题机制不同的历史计划、Issue 或 Review；
- 只偶然出现相同关键词、但不提供定义或约束的文档；
- 已被更具体当前文档替代的 README 概述；
- 与本次验收标准无关的代码和测试。

代码存在不等于设计正确，历史文档也不等于当前规格。出现冲突时按 `AGENTS.md` 的 Source of Truth 规则处理。

## 6. 渐进式检索层级

### Level 0：固定入口

- 生效的 `AGENTS.md`；
- `docs/architecture/overview.md`；
- 本文件；
- 任务解析结果。

### Level 1：当前权威资料

按任务选择：

- 目标 `docs/domains/` 文档；
- 相关 Accepted ADR；
- Active Plan；
- `status/current.md`；
- `issues/open.md`；
- Active Review；
- 专项 Skill 和机器可验证协议。

### Level 2：实现与验证

- 目标代码入口；
- 直接调用者和被调用者；
- 数据读写路径；
- 相关测试、构建目标和验证脚本；
- 与修改直接相邻的实现。

### Level 3：历史证据

仅在必要时读取：

- `docs/plan/completed/`；
- `docs/issues/resolved/`；
- `docs/reviews/archive/`；
- 被替代或历史 ADR。

### Level 4：广范围兜底

只有前述层级仍不足时，才扩大到：

- `README.md` 的相关章节；
- 更大范围文档；
- 更广范围仓库符号检索；
- 无直接索引的旧资料。

只有以下情况允许扩大一级：

- 当前资料没有定义目标行为或验收标准；
- 无法确认调用链、数据所有权或影响范围；
- 权威来源发生冲突；
- 需要解释兼容性、迁移或历史取舍；
- 构建或测试出现当前资料无法解释的异常；
- 怀疑当前问题是历史问题的回归；
- 索引缺失、路径失效或文档明显过期。

每次只扩大一级。找到足够证据后立即停止，不为“了解更多”继续收集无关上下文。

## 7. 定向检索方法

先从任务中提取：

- 模块名和中文业务名；
- 领域实体和字段名；
- 方法名、接口名和错误码；
- 类名、函数名和测试名；
- 决策主题，例如 `recurrence`、`timezone`、`transaction`、`storage`、`identity`；
- Plan、Issue 或 Review 的编号和标题关键词。

先查文件名，再查内容：

```text
rg --files docs/domains docs/architecture/decisions docs/plan/active docs/issues docs/reviews
rg -n -i "<module>|<entity>|<method>|<error_code>|<feature>" <candidate paths>
```

大文件先查看标题和命中位置，只打开相关段落：

```text
rg -n "^#{1,4} " <file>
rg -n -i "<keyword>" <file>
```

结果较多时按以下顺序筛选：

1. 精确实体、方法、错误码或测试名；
2. Current Status、Active Plan、Open Issue 和 Active Review；
3. Accepted ADR；
4. 直接依赖模块；
5. completed、resolved 和 archive；
6. README 或更广仓库。

## 8. Anniversary 示例

开发 Anniversary 模块时：

1. 阅读 `docs/architecture/overview.md`；
2. 解析具体目标，例如创建、更新、查询、年度重复、倒计时或持久化；
3. 在 `docs/domains/` 中检索 `anniversary`、`AnniversaryRecurrence`、`纪念日`，只读取对应领域资料及确认存在的直接依赖；
4. 在 `docs/architecture/decisions/` 中检索年度重复、日期锚点、时区、身份、事务和存储等与本次目标有关的 ADR；
5. 查找对应 `docs/plan/active/`；需要判断实际完成度时再读取 `docs/status/current.md`；
6. 根据文档中的实体、方法和调用链定位代码与测试；
7. 只有规则不明、来源冲突或验证异常时，才查 Anniversary 相关的 completed plan、resolved issue 和 archived review。

除非实际数据关系、调用链或测试影响证明相关，不加载 Habit、Search、Sync 等其他模块的全部资料。

## 9. 开发前的停止条件

开始修改代码前，Codex 应能够明确回答：

- 目标行为和验收标准是什么；
- 当前权威文档有哪些；
- 哪些 ADR 约束了设计；
- 目标模块和直接依赖是什么；
- 涉及哪些层级、接口和数据流；
- 代码入口、测试入口和验证方式在哪里；
- 是否存在冲突、缺失信息或风险；
- 哪些内容明确不在本次范围内。

这些问题已有可靠答案时，应停止继续加载文档并进入实施；无法回答时，按第 6 节仅扩大一级。

## 10. 索引维护

新增、移动、替代或归档文档时，应在同一变更中更新本文件。

维护原则：

- 只记录“在哪里、何时读、用什么关键词找”，不复制完整规格；
- 新领域文档使用稳定、可检索的模块名和实体名；
- ADR 明确状态、决策主题和适用模块；
- 完成的计划从 `plan/active/` 移入 `plan/completed/`；
- 已解决问题从 `issues/open.md` 移出，并在 `issues/resolved/` 保留症状、根因和修复关键词；
- 完成的 Review 从 `reviews/active/` 移入 `reviews/archive/`；
- `status/current.md` 只记录当前事实，`status/roadmap.md` 只记录未来方向；
- `docs/log.md` 只追加，不作为默认检索入口；
- 路径缺失、索引过期或同一主题出现不一致入口时，必须报告，不得猜测。

本索引应保持简洁、稳定和可导航，不能演变为需要每次全文阅读的大型项目说明书。