# 云同步 05 先验验收设计

编写时间：2026-09-07；顺序：本文件及测试代码先于实现。适用 Skill：android-kotlin-native-feature。

目标协议输入：cloud-sync-v1-contracts-2026-09-06；机器锁声明摘要 `888fee7a8767eed7ac95eb3c7a76707e8bd3ed3264695ebdf750cc837d3643a9`。默认 validator 当前失败，详见 `docs/issues/problem-kotlin.md`；该摘要仅作输入声明，不表示本机验证通过。

| 阶段/章节 | 提前固定的可观察结果 | 测试及依赖边界 |
| --- | --- | --- |
| K0 §3–4、6–8 | v3 与 HTTP 外壳隔离；未知键、类型、版本、重复 JSON 键、非法 UTF-8 拒绝；负例不得进入下层 | StrictBoundaryTest；完整 Schema/方法覆盖仍需要 Contract owner 的默认 gate |
| K1 §5、9 | guest/account runtime 同时存活；CAS 切换一次提交；迟到 route 不可路由；close 拒绝新 lease 并等待旧调用；开库失败保持旧 route | WorkspaceRuntimeRegistryTest，Native 仅测试替身 |
| K1 §10 | 每账号独立 key；AEAD 错 AAD/缺 key 拒绝；binary key 在成功和异常后清零；解密不创建 key | WorkspaceKeyVaultTest，JVM AES-GCM 与模拟 key store；真实 Keystore 未验证 |
| K2 §11 | 100 个并发请求只旋转一次；迟到 refresh 不复活 logout；新 RT 持久成功前不发布 AT；失败不重放旧 RT；提前 401 按 generation 合流 | RefreshFlightCoordinatorTest；adopt/register/legacy migration/logout review 需要后续完整 Broker 套件 |
| K3 §12 | Release 拒绝 HTTP/IP/私网/用户信息；Debug 只放行显式私网；全抖动边界、8 次预算、body/header 提示一致；没有隐式降级 | TransportPolicyTest；实际 HTTP TLS/取消与 endpoint DTO 仍待接入 |
| K4 §13–14 | 10,000 触发最多 current + successor；journal→enqueue 崩溃重放同 id；查询失败不追加；drained 不吞 successor；failed/cancelled 可恢复；游客/关闭同步不唤醒 | SyncWakePumpTest；WorkManager 通过窄端口替代系统执行机会 |
| K5 §15–16 | workspace 平台身份互不覆盖；API24 同 boot 进程恢复，重启换 token；API23 不复用；倒退/坏记录 fail closed；无锚 retain 拒绝；已有 deadline 不延长 | RetentionClockTest、WorkspacePlatformIdentityTest；真实清理 saga 与系统行为不能由时钟单测代替 |
| K6 §18–20 | 已写测试全部通过；JUnit/lint/Debug build 有真实结果；未交付章节不标 complete | 报告写在本文末尾；不得跳过失败测试或弱化断言 |

测试替身位于 `app/src/test`。独立组件位于 `bridge/sync`，未注册到旧生产通道；没有新依赖、工具链或协议升级。K0 未通过期间不提交生产同步调用链。

## 本轮实际结果（2026-09-07）

- 状态：部分完成 / K0 BLOCKED。没有完成全计划的测试先行与实现，K1–K6 不签收。
- 第一批 26 个组件测试先写后实现；最初编译确认尚未实现的类型引用失败，同时暴露既有 Flutter/旧测试编译阻塞。后续增加真实 Contract 前置校验及正式 fixture 消费，共 29 个 JUnit 测试。
- `run-sync-v1-unit-tests.ps1` 默认运行全部 29 项：27 通过、2 失败、0 跳过。失败分别为默认 Contract validator 和当前源文件与输入锁一致性；两项都应当通过，目前如实保留失败。
- `ContractFixtureForwardingTest` 消费 `jcs_boundary_vectors.json` 的全部 64 条向量，覆盖正式正负输入与字节转发保持。没有在 Kotlin 实现/重算 JCS hash；这不是完整 endpoint Schema 验证。
- 组件验证包括 100 并发刷新和 10,000 并发机会调度，以及 journal/enqueue 两侧故障、runtime lease、密钥清零、同 boot/重启和时间回退。
- 最新完整 JUnit 输出：`flutter_client/build/sync-v1-jvm/8e23deb0d71b4feba327504587b50aeb/junit.txt`（本地构建产物，不提交）。
- 标准 `testDebugUnitTest`、`lintDebug` 均被既有 Flutter Appearance 编译错误阻塞。Android 局部 `compileDebugKotlin` 和 `lintDebug` 在显式排除 `compileFlutterBuildDebug` 后通过；不是整体构建通过。
- `assembleDebug`、三 ABI Flutter APK、Release 签名/TLS、connected instrumentation、真实 C++ JNI 和双设备均为 UNVERIFIED；按用户要求不等待手机，不重复执行依赖已知同一失败节点的构建。

复跑全部先行测试（默认保留 K0 硬门禁）：

```powershell
cd A:\calendar\ExcellentCalendarAPP\flutter_client\android
.\run-sync-v1-unit-tests.ps1
```

脚本的 `-Suite foundation` 仅用于定位组件问题，明确排除未通过的 Contract 前置门禁，不得用该子集作为整份计划验收。脚本总会重新编译全部本次 Kotlin 源码和测试，不运行陈旧测试 jar。

完整计划尚需的验收代码（不得因以上测试通过而划去）：全 Method/Native/HTTP Schema fixture 闭包；adopt/register/pending/legacy migration 全强杀点；settings reporter 与 transport lane/fence journal；exchange normal/ack-only/bootstrap/failed/notice/diagnostics/maintenance；全部 import proof/lease/cleanup 分支；logout review/skip/retry/cancel/force-local；active clear-rebuild 每个不可逆点与安全终态抢占；workspace-local Search/Appearance/notification tap 的现有路径迁移；真实多 ABI JNI 与同包 Flutter owner 交接。
