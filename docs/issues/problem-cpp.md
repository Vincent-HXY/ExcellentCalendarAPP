# C++ 云同步实施问题

## CPP-SYNC-001：Plan 03 C0 正式冻结门禁被后续 Appearance 改动破坏

- 时间：2026-09-07（Asia/Shanghai）。
- 状态：**OPEN / C0 BLOCKED；C1–C8 未实施**。
- 任务：按顺序完成云同步-03；正式编码前先写测试；无法连接手机；未决冲突记录本文、层级交互使用测试假数据。
- Skill：cpp-core-feature、calendar-data-contracts。

### 复现与冲突双方

`python contracts/run_sync_v1_validation.py` 实际退出 1：

```text
Sync CT0 validation failed: Protected Contract drift: contracts/appearance/local_appearance_response.schema.json; add a reviewed compatibility revision, not a regenerated baseline
```

1. `contracts/sync/ct0_gate_status.json` 声明 `CONTRACT FROZEN`、`implementation_allowed=true`，Plan 03 §4 与输入锁要求默认校验通过才能开始生产实现。
2. 后续提交 `37c3521`（界面美化）相对 `027d342` 修改了 Appearance 请求/响应并新增 `display_preferences.schema.json`：新增 optional `display`、描述历史默认字体设置和同包严格 reader 兼容。此工作应保留，不能退回旧外观协议。
3. `contracts/sync/sync_v1_baseline.json` 与 `sync_v1_revision_lock.json` 仍锁定这次界面变更前的协议；校验器按解析后的结构计算 protected digest，所以不是 CRLF、缩进或缓存问题。

已遍历本机锁文件的全部 `sources_sha256`，发现以下两个来源不匹配；其余已列入锁的来源一致。新增 display Schema 没有进入旧锁闭包，后续重新冻结还需检查它的 `$ref`、兼容性与消费证据，不能只替换两个摘要。

| 文件 | 锁定的来源 SHA-256 | 当前来源 SHA-256 |
| --- | --- | --- |
| `contracts/appearance/local_appearance_response.schema.json` | `530b272f091060f2e5f5e14fe88ba6aa41aa94fd0fae04e5ad9bbcc02ba82ec4` | `9a9a8fad3d89b81f96a829a99d46a498934b36d18508c9d29068b250dd99b1df` |
| `contracts/appearance/update_local_appearance_request.schema.json` | `52a7369c985113a25eeaff37e28a49f093dfaf1a1ab8246c56d17c00911e742a` | `5e4f8c1faa19696d08816c9f482a84b6312e1ccb1a62108e0920cb4e5144af84` |

来源摘要使用校验器同域的 newline-normalized UTF-8；它与 protected parsed-structure hash 是两个不同摘要域。
当前四端共同合同摘要仍为 `888fee7a8767eed7ac95eb3c7a76707e8bd3ed3264695ebdf750cc837d3643a9`；不能把其静态存在当成通过证据。

### 本轮裁决与影响

采用**当前文件 + 实际机器校验结果**，不采用过时的“已冻结”文字作为放行依据；符合总计划 §1.1 和 Plan 03 §4/§16 C0。
本轮不撤销界面功能，不改写旧基线，不新增未审阅兼容例外，也不伪造四端重新签收。
新 display 的兼容修订与冻结证据需要 Contracts 层处理；Plan 03 限定的 C++ 生产实现不能自行解决这一共享接口问题。

暂停 C1–C8 的生产实现；继续 C0 writer 初步盘点、先行测试、已有 C++ 回归，以及只读 fixture 假数据适配。
本轮 `cpp_core/tests/sync_v1/contract_input.py` 直接读取已有冻结 fixture 并返回独立副本，不模拟数据库成功、上传回执、合并或系统加密；不会进入生产 runtime。
用假数据替代手机/Backend 输入不会令不一致的机器 Contract 自动变成有效冻结状态。

### 最小解除条件

1. 保留新的 Appearance display 行为，针对两个旧协议及新增引用定义审阅兼容修订，明确旧请求/响应、缺省/完整 display 和四端严格 reader 的矩阵；不得简单重建旧 baseline。
2. 按 Contracts-02 正式流程重跑受影响消费测试与证据检查，更新完整机器来源闭包和四端共同 revision/hash/manifest 锁。
3. 当前工作区 `python contracts/run_sync_v1_validation.py` 和 `excellent_calendar_sync_v1_preflight` 均返回 0；再从 C1 开始、按阶段先测试后实现。

不需要手机即可处理此次冻结冲突；设备不可用不是当前 C0 失败的根因。

### 验证边界

先行测试及后续预期见 `cpp_core/tests/sync_v1/README.md`。回归通过只说明既有能力与测试资产可用。
本轮没有新增 v6/runtime/Outbox/apply/bootstrap/import/SQLCipher 生产代码；不能声称 Plan 03 或全部提前验收代码已经通过。
实际手机、三 ABI 加密 APK、JNI/Backend/Flutter 消费签收及双设备行为均未验证。

2026-09-07 02:00 +0800 本轮实际结果：CMake Ninja 配置退出 0；`excellent_calendar_check` 构建后 15/15 测试目标通过（50.63 秒），包含新增 3 个真实 C++ 场景与 5 项 fixture 准备测试；`excellent_calendar_sync_v1_preflight` 退出 1，完整报告上述两个漂移并复现官方失败。前者不覆盖后者；C0 仍未通过。
