# ADR-Sync-03：账号 SQLite 加密候选

Status: Accepted (Plan 02 isolated feasibility verified; product integration remains planned)
Date: 2026-09-05

Acceptance: 用户在本任务后续消息中明确接受“SQLCipher 原生 C 加密候选”，并授权自主完成可逆、只读和已授权工作。新增依赖方向已获接受；本文各项实验和分发审查仍以实际证据为准，不能将接受候选解释为加密已交付。

## Context

当前产品使用普通 SQLite 3.53.4，`calendar_core_v5.sqlite.version_upgrade_forbidden=true`。云同步-01 §7 和云同步-02 §4.2/§18 要求先接受新 Native 依赖与可行性证据，不能以私有目录替代加密。

## Accepted Candidate

建议评估 **SQLCipher Community 4.18.0 的原生 C 接口**，使用其社区 Android crypto provider 的固定来源和版本；不直接引入 Android AAR，也不升级 Flutter、SDK、NDK 或当前 SQLite 3.53.4。

官方 [4.18.0 发布说明](https://www.zetetic.net/blog/2026/08/18/sqlcipher-4.18.0-release/) 指明其 SQLite 基线为 3.53.4，而 Android 包改为 compileSdk 37；因此本项目应先做独立 C/JNI 构建实验，不能直接套用 AAR。官方社区 Android provider 基于 LibTomCrypt 1.18.2，须固定源码 revision/hash 并审计传递组件，不默认改成 OpenSSL。

按官方 [许可证页](https://www.zetetic.net/sqlcipher/license/)，社区版采用 BSD 风格许可证，并要求用户可访问的许可和署名说明。该资料仅支持候选审查；最终必须核对所选源码包及 provider 的原始 LICENSE、变更和分发清单，不能用网页说明代替完整依赖审查。

## Pinned Source and License Evidence

已从官方仓库按不可变 commit 读取 15 份源码说明、构建描述和许可证文件，原始 bytes 的 SHA-256、URL 及 gitlink 记录于 [encryption_source_audit.json](../../../contracts/spikes/sync_v1/encryption_source_audit.json)。此次候选精确到以下来源：

| 组件 | 固定 commit | 审计结果 |
| --- | --- | --- |
| SQLCipher core v4.18.0 | `63697beb0fafcb61faa7a3e6fd267036548ab11b` | `VERSION=3.53.4`，符合当前 SQLite 基线；不是 Android 标签内的旧 core gitlink |
| SQLCipher LibTomCrypt fork | `476a9579ae94f32b9ea9e2747bfb04b302370259` | Android 发布树固定的 provider；不能仅写模糊的上游“1.18.2”而忽略 fork revision |
| Android wrapper v4.18.0，仅作构建参考 | `e15752c3eb4364e27203185587471aab25b0ca91` | core gitlink 为 `e2a6040f2ae5cfff2b3e08eb3320007d93cdf3fc`，其 `VERSION=3.53.1`；不能直接按该 gitlink 重建候选 |

这个源版本差异来自 [Android 发布树](https://github.com/sqlcipher/sqlcipher-android/tree/e15752c3eb4364e27203185587471aab25b0ca91/sqlcipher/src/main/jni/sqlcipher)、[core 标签 VERSION](https://raw.githubusercontent.com/sqlcipher/sqlcipher/63697beb0fafcb61faa7a3e6fd267036548ab11b/VERSION) 和 [Android gitlink VERSION](https://raw.githubusercontent.com/sqlcipher/sqlcipher/e2a6040f2ae5cfff2b3e08eb3320007d93cdf3fc/VERSION)。因此，AAR 摘要/符号通过不证明可由该 Android 标签完整重建。本轮未验证 AAR 的可重现构建，也不推断 AAR 实际用了旧 core；独立原生候选必须从所选 core commit 生成 amalgamation 并验证运行时版本。

顶层许可证初审结论：SQLCipher core 要求保留源码及二进制分发通知、免责声明并限制借作者名义背书；SQLite runtime 为 public domain，但构建辅助工具有独立许可；所选 LibTomCrypt fork 提供 public-domain/WTFPL 双选项，候选采用其 public-domain 选项并保留原 LICENSE。建议在随包第三方许可说明中保留完整原文，并从应用内离线可达。上述条款基于实际固定文件；最终选入的逐文件声明、生成代码及分发清单仍需审查，不将初审标为完整许可门禁通过。C 接口方案不复制 Android wrapper；若后续复制其 JNI 代码，需要追加 Android 来源通知审查。

## Data and Key Boundary

- 每个账号 workspace 独立随机 256-bit DEK，Keystore 包装，AAD 绑定 installation/workspace/schema/account binding。Guest v6 继续独立明文 profile。
- JNI 使用二进制 key 参数；不进 JSON、Event、日志、Registry 或普通缓存。关闭时释放明文，销毁先处理包装材料，文件删除可以后续收尾。
- 先 key 再读 schema，验证账号 metadata/profile、cipher 实际启用与完整性，错误密钥或缺少 key 立即拒绝，不回退 guest 或尝试普通 SQLite 打开账号库。
- 保留 WAL、FULL、BEGIN IMMEDIATE 和 defensive 配置。必须实测 DB、WAL、临时落盘均无明文业务数据，不能只检查主数据库头。

## Acceptance Evidence Required

| 门禁 | 实验与通过条件 | 本次状态 |
| --- | --- | --- |
| 依赖与许可证 | 固定 SQLCipher/provider 原始源码及摘要；批准新增依赖和许可展示位置 | 用户接受候选；固定源码重建及427份runtime/provider文件来源清单、6份完整许可/署名通知已交付；未来APK须离线提供第三方许可入口，产品依赖和UI未改 |
| ABI/API | 当前 NDK 下 arm64-v8a、armeabi-v7a、x86_64 构建；实际链接所需 sqlite3 API | 以现有NDK28.2和SQLite3.53.4固定core源码构建通过；不采用Android标签中3.53.1的gitlink，不引入AAR/SDK37 |
| ABI runtime | 三 ABI 打开/写入/重开、wrong key/profile/binding 显式失败 | Windows、三ABI NDK/Bionic静态程序的QEMU-user及真实arm64/arm32 Android均通过；不把QEMU-user记为三台Android OS设备 |
| 明文泄漏 | WAL/checkpoint/temp/full-disk 错误路径和日志检查 | 合成业务sentinel不在DB/WAL/日志中；temp_store=MEMORY的20,000行排序未打开临时文件；VFS注入SQLITE_FULL后事实/Outbox一起回滚 |
| 数据迁移 | 冻结 v5 checker→guest v6；独立 account encrypted fresh；完整失败回滚 | Plan 02 独立 v5→guest v6 checker、128 回滚边界及 account encrypted fresh 已验证；产品加密 v6 完整业务图仍由 03/05 实现验收 |
| 恢复 | 每个提交点强杀、WAL 重放、key 丢失、磁盘耗尽 | 独立进程在提交前、WAL sync中、提交后和checkpoint中被真实终止，重开完整性及事务一致性通过；无key/错key/错page profile拒绝。Keystore及电源突然断电行为仍属单独证据 |
| 规模 | 20,000 条组合事实的打开、查询、写入和同步压力数据 | 20,000行合成加密读写通过；全target组合图和同步容量尚待CT1/CT4交付，不以普通行测试冒充整图容量 |

本 ADR 的审批对象是上述候选与受隔离的验证工作，不是生产发布。可行性未通过前，`runtime.open_workspace` binary-key 签名、加密 profile、保留账号缓存和 v6 冻结均不能报告完成。失败后回到本 ADR 选择候选，不静默更换密码库或降低保护。

原包/link证据位于 `contracts/spikes/sync_v1/encryption_package_audit.json`，保留为历史的包级审计。后续实际源码和恢复证据见 [cipher_source_spike_result.json](../../../contracts/spikes/sync_v1/cipher_source_spike_result.json)，逐文件来源与通知见 [cipher_runtime_source_audit.json](../../../contracts/spikes/sync_v1/cipher_runtime_source_audit.json)。实际AAR声明 `minCompileSdk=37`，本候选不依赖它。

固定provider的 `rng_get_bytes` 在OS随机源失败后原会尝试ANSI时钟采样。候选使用已记录的 [require_os_rng.patch](../../../contracts/spikes/sync_v1/require_os_rng.patch) 和 `EXCELLENT_CALENDAR_REQUIRE_OS_RNG` 禁止该回退；六个执行环境均运行实际provider函数的OS随机源故障注入，确认返回0而非降级随机数。此项源修订是已授权候选的fail-closed收紧，不能脱离补丁及其源码摘要复用实验结果。

API 行为依据：[SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)；设置 key 成功本身不能证明数据库能够用该 key 读取，探针必须实际读取。
