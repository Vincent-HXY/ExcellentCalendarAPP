# 云同步 Kotlin / Android 问题与集成门禁

## KOT-SYNC-001：默认 Contract 验证失败（2026-09-07）

- 入口：`python contracts/run_sync_v1_validation.py`，退出码 1。
- 首个错误：`Protected Contract drift: contracts/appearance/local_appearance_response.schema.json; add a reviewed compatibility revision, not a regenerated baseline`。
- 冲突：计划 05 §4 要求默认验证通过，但当前检出状态无法通过。不得通过重置摘要、删除断言或只跑 CT0 伪造封版成功。
- 采用的依据：机器验证结果。冻结声明不替代可执行结果。
- 影响：K0 尚未通过；v3 生产接线、K6 完整签收暂停。按本次用户指示继续先写测试及隔离组件，跨层仅使用测试数据。
- 解除条件：Contract owner 修复/解释受保护基线差异，默认验证通过且四端摘要一致。

后续独立检查采用 validator 同样的 UTF-8/通用换行归一化，确认摘要不匹配的来源为 `contracts/appearance/local_appearance_response.schema.json` 和 `contracts/appearance/update_local_appearance_request.schema.json`。不是单纯 CRLF 差异。先验测试默认要求通过，当前保留真实失败，不改成 expected-failure。

## KOT-SYNC-002：通道与版本正文落后于机器定义

- 计划 05 §6 写 `excellent_calendar/native`；`contracts/native_v3/method_channels.yaml` 定义 `excellent_calendar/native_v3`、version 3，并保留 v2。
- 采用机器定义与 Session ADR 的同包切换规则；不在旧通道接入 v3，不下线当前生产 RT owner。
- 影响：不能把新增隔离组件的单测通过当成已迁移现有 Flutter 登录。

## KOT-SYNC-003：跨层 owner 尚未交付

- 初始盘点：`cpp_core/src/boundary/api/native_runtime.cpp` 仍为 `RuntimeState g_state`；Flutter `TokenRefreshCoordinator` 及 `auth.refresh_token.read` 调用仍存在。
- 计划 05 §4/§9/§11 要求多 runtime、SQLite v6、正式 Backend device/sync 与同包移除 Dart 刷新 owner。当前目标不允许本层复制这些 owner。
- 替代：测试中的 Native、HTTP、持久化故障及系统调度替身，只使用合成身份/凭据；替身不得进入默认或 Release composition。
- 影响：真实 JNI/SQLCipher、完整 import/fence/clear-rebuild、Flutter owner 迁移与双设备集成必须等待对应计划交付。没有伪造底层成功的生产 adapter。
- 并行工作：盘点后发现 C++ 工作树出现其他任务修改，全部保留；最终状态须依据交接证据重新核对。

## KOT-SYNC-004：本轮没有手机

- 用户明确要求以测试代码替代手机环节；采用可控 boot count/elapsed、并发屏障、模拟掉电/重启、平台调用记录验证编排。
- 这些测试只能证明输入/顺序/隔离规则。实际 Keystore、系统备份搬运、Doze、三 ABI JNI 加载、OEM 行为与双设备联网为 UNVERIFIED，不宣称真机通过。

## KOT-SYNC-005：现有完整构建与旧测试编译阻塞

- `:app:testDebugUnitTest` 和 `:app:lintDebug` 的默认入口均在 `:app:compileFlutterBuildDebug` 失败：`flutter_client/lib/presentation/appearance/appearance_page.dart` 缺少 `Color/BuildContext/HabitProgressColorToken` 与 `AppearancePage` 定义；该文件不属于本次变更。
- 为定位 Android 自身结果，执行 `:app:compileDebugUnitTestKotlin -x :app:compileFlutterBuildDebug`：既有 `bridge/channel/HabitMethodHandlerTest.kt:146` 的 `RecordingAppearanceStore` 未实现 `getDisplayPreferences/updateDisplayPreferences`，另有先验测试预期的未实现引用。没有改动该既有替身。
- 新增 `flutter_client/android/run-sync-v1-unit-tests.ps1` 使用项目已经解析的 Kotlin 2.2.20、JUnit 4.13.2 与 org.json 20240303 缓存，先重新编译本次全部组件和测试，再执行 JUnit；没有下载或升级依赖。
- `:app:compileDebugKotlin -x :app:compileFlutterBuildDebug` 通过；`lintDebug` 排除同一 Flutter 编译阻塞后也通过。这些诊断结果不算完整 Flutter/APK 构建成功。
- 完整 Debug APK、三 ABI 组合构建、Release 签名/TLS 和 connected instrumentation 未验证；已有同一 Flutter 编译根因时，不反复执行依赖相同失败节点的打包命令。

## KOT-SYNC-006：本轮交付范围不等于 K1–K6 完成

- 本轮为 K0 先行验收与 §4 允许的隔离组件验证：路由/lease、刷新 single-flight、AEAD binary key、唤醒合并、HTTP 词法/URL/退避、boot/retention 时间计算和平台身份。
- `bridge/sync` 没有组装到 Application、MethodChannel、Worker 或 JNI；生产 v2 登录和提醒调用链保持原样。私有端口是测试替身插入点，并未伪造 C++ 数据库、Backend mutation 或系统成功。
- 完整测试尚未全部写完：adopt/register/legacy migration、严格 endpoint DTO 全闭包、settings/fence/import/bootstrap/clear-rebuild、真实缓存清理与平台接线等仍列在验收设计的未交付清单中。不得把 27 个已通过组件测试表述为“所有相关功能已验证”。
- 下一步先由 Contract owner 修复 001，再按计划 K1→K6 为剩余章节先写行为测试后实现；跨层缺口可继续采用用户授权的 test-only fixture 替身，但不提前激活生产能力。
