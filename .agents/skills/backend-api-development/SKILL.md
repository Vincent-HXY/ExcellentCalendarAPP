---
name: backend-api-development
description: 在 cloud_backend 内使用仓库现有 Java/Spring 技术栈实现、修改或修复云端后端能力。用于 API、认证、同步、持久化、异步任务和相关测试；不用于修改客户端、C++ Core 或跨层 Contract。
---

# Cloud Backend Development

## 目标

在 `cloud_backend/**` 内交付符合 Local-first 边界、当前 Machine Contract 和既有模块架构的后端功能。Skill 不固定框架版本、端点清单、认证参数、同步算法或数据库现状；每次任务从当前资料与实现确认。

## 范围

默认可修改：

```text
cloud_backend/**
docs/log.md
test_note/**  # 仅记录本次实际通过的设备或模拟器验收
```

`contracts/**`、`cpp_core/**`、`flutter_client/**` 和其他项目文档默认只读。`docs/log.md` 仅追加本次记录；`test_note/**` 仅在按 `AGENTS.md` 实际完成设备或模拟器验收后新增对应记录。构建产物和测试容器数据可由工具生成，但不得手工修改或提交。

不得在后端复制第二套 Contract、重写本地领域真相或用兼容分支掩盖缺失协议。若公开 API、Schema、错误码或跨层语义必须变化，停止受影响实现并报告 Contract 前置任务。

## 强制项目导航

开始规划或修改前，按顺序读取：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 解析用户行为、权限边界、事务/并发风险、范围外内容和验收标准；
4. `docs/index.md`，据此定位当前 Domain、Accepted ADR、Active Plan、Machine Contract、状态、问题、版本和验证指南；
5. `cloud_backend` 的实际构建文件、模块入口、迁移、配置、调用链和测试。

Source of Truth 和冲突裁决完全遵循 `AGENTS.md`。不存在或未被 index 选中的旧数据模型文档、README 示例和历史实现不得作为当前规范。

## 稳定边界

- 后端是可选云端协调者，不替代本地离线能力或绕过本地正式 Application/Contract 路径。
- API 层负责传输、认证上下文、输入边界和错误映射；Application 负责用例、授权、事务和编排；Domain/Ports 保存稳定语义与抽象；Infrastructure 负责数据库和外部提供方；Boot 只装配。
- 模块间只通过公开 Application API、端口或明确事件协作，不直接引用其他模块内部持久化实现。
- 认证身份必须来自已验证上下文；所有输入、回调和外部响应均按不可信边界处理。
- 业务状态、幂等记录、同步版本、消息投递和数据库并发版本不得混为同一概念；具体语义从当前 Contract/ADR 读取。
- 事务内外部副作用、异步可靠性、重试和清理策略必须由当前架构与计划明确，不自行引入新基础设施。

## 工作流

### 1. 现状与闭环

- 检查 Git 状态和 `cloud_backend` diff，保护用户修改。
- 追踪入口 → DTO/认证 → Application → Domain/Port → Persistence/Provider → 响应/事件 → 测试。
- 核对公开 Contract 状态、迁移基线、数据约束、事务边界、授权范围、幂等和失败恢复。
- 区分 production 已接线、仅实现、planned、占位、缺失和未验证。

### 2. 可行性闸门

- `GO`：任务可在 `cloud_backend/**` 内依据当前 Contract 和已存在基础完成。
- `DECISION_REQUIRED`：存在会改变公开协议、迁移/回滚、兼容性、安全或基础设施路线的选择。
- `BLOCKED`：缺少 Contract/Schema/错误定义、必须越界、迁移基线无法确认、依赖能力不存在或关键安全行为不可验证。

后两种情况停止受影响部分，报告冲突、影响、仍可继续范围和最小解除条件。


用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。

### 3. 实现

- 复用现有模块、异常、时钟、ID、事务、Repository、Provider 和测试基础。
- 将授权、领域校验和事务放在拥有该策略的层；Controller/消息入口保持轻薄。
- 持久化变更使用新的连续迁移，并明确现有数据、约束、索引、部署和失败恢复影响。
- 外部调用设置边界、超时和可诊断错误；日志不得包含凭据、令牌、隐私数据或密钥。
- 并发正确性依赖可证明的事务和数据库约束，不依赖进程内偶然顺序。
- 为改变的行为添加 unit、web、persistence、integration、security 或 worker 测试中适用的层级。

## 停止条件

暂停受影响实现，当：

- Contract/ADR/Active Plan 与现有实现冲突且优先级无法直接裁决；
- 需要改变跨层协议、客户端行为或本地领域规则；
- Migration 可能破坏数据且没有可验证恢复方案；
- 队列、对象存储、密钥、部署或其他基础设施选择会实质改变设计；
- 无法保护用户已有修改或隔离测试副作用。

## 验证纪律

通过 `docs/index.md` 定位当前版本和验证指南，并从 `cloud_backend` 的实际 Wrapper/构建配置选择命令：

- 先运行最相关测试，再运行受影响模块的完整检查；
- 数据库行为使用项目声明的真实数据库测试路径，不用不等价替代品证明方言、锁或迁移；
- 执行适用的 Contract、认证/授权、并发、幂等、迁移、回滚和集成验证；
- 检查应用启动、Migration 和生产配置门禁，禁止用旧报告或缓存证明通过。

完成后检查 `cloud_backend/**`、`docs/log.md` 和本次实际新增的 `test_note/**` 记录。每项未执行或环境受限的验证必须明确列出。

## 完成标准与交付报告

仅当需求已实现、修改未越界、可行性为 `GO`、职责与依赖正确、测试实际通过、最终 diff 无无关修改时，才能标记“完整完成”。否则使用：

```text
部分完成
实现完成但验证未完成
被决策阻塞
被基础能力阻塞
```

报告结果、调用链和职责、文件变更、Contract/存储/兼容影响、实际测试与构建结果、未验证项和风险，并追加 `docs/log.md`。

最终报告必须包含：

1. **结果状态**：完整、部分、未验证或阻塞及原因；
2. **分析与拆分**：调用链、可复用基础、模块归属、依赖与耦合处理、本次不实现内容；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：逐项说明完成度和阻塞的最小解除条件；
5. **架构与一致性**：Contract、DTO、Application、Domain、JPA、Migration、Outbox、安全；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **局限**：只读边界、缺失基础、未验证 Android/JNI/设备行为和后续决策。
