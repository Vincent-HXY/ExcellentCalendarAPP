# 云同步 Flutter 问题与实施门禁

## FLT-SYNC-001：当前工作树未通过冻结 Contract 验证

- 发现时间：2026-09-07。
- 关联：云同步-06 开头协议输入锁、§4、F0、§15.4、§18；云同步-01 §1.1；`contracts/sync/sync_v1_baseline.json`。
- 实际命令：`python contracts/run_sync_v1_validation.py`，退出码 1。
- 首个错误：`Protected Contract drift: contracts/appearance/local_appearance_response.schema.json; add a reviewed compatibility revision, not a regenerated baseline`。
- 补充只读核对：两个受保护 JSON 的结构化摘要与基线不符，均有 `description` 和 `properties` 变化；不是 CRLF 差异。

| 文件 | 基线摘要 | 当前结构化摘要 |
| --- | --- | --- |
| `contracts/appearance/local_appearance_response.schema.json` | `5beb10c70b59a82ab856b95bf39427053b056ae941a476e2ddb45d89963922e4` | `def8113cefb45acd39b9b17ea7ade5a782ef8e29a40a6dbc929224dbf8a404dc` |
| `contracts/appearance/update_local_appearance_request.schema.json` | `a450758518b43cea5afc2ad97df0388f7cac6708a70d69f918a4c0ac948dc22f` | `d5bc5e713e9f7b937eae6c12bf4dc7c6170bc4a593ed75db7a03e39a29830401` |

### 冲突及采用的依据

计划及锁文件声明 CONTRACT FROZEN；当前 active Appearance 已有字体扩展，而同步校验器仍保护扩展前内容。采用实际机器验证结果判断是否可签收，不删除字体字段、不重新生成受保护旧摘要、不修改 Contract 或伪造冻结证据。两边都需要保留其原有语义，由 Contract 兼容修订明确同包输入。

### 影响与可继续范围

F0 尚未通过，不能签收生产协议迁移或本计划完成。可以继续写测试、验收预期和使用正式 fixture 的隔离测试；用户已授权跨层缺口使用临时假数据，但假数据不能证明当前 Contract 摘要正确。新测试 `flutter_client/test/sync_v1/contract_preflight_test.dart` 保留这一真实失败，不 skip、不改成期望失败。

解除条件：Contract owner 对当前 Appearance 字体扩展作正式兼容修订，默认完整 validator 通过，并确认四端同一摘要。只修复第一个文件后仍需重新检查第二个文件及后续门禁；本记录没有断言除此之外无其他问题。

## FLT-SYNC-002：新会话、工作区和真实产品组合尚未交付

- 初始盘点：Flutter `main.dart` 的 `buildAuthDependencies` 仍组合 `TokenRefreshCoordinator`、`MethodChannelRefreshTokenSecureStore`、`UserProfileFileCache`；没有新 Workspace/Sync 产品链。
- Kotlin 初始定向搜索未发现 Session/Workspace/Sync v3 Handler。其他任务正在同一工作区开发 C++/Kotlin，状态可能继续变化，应以其交接及真实实现重新判断，不能覆盖它们的文件。
- Source of Truth：`ADR-Sync-04-SessionCredentialBroker.md` 的 Compatibility and Verification 要求新 Broker 实现、测试及同包组合就绪前保留旧生产 owner；Plan 06 F7 要求最终移除旧 owner。两者规定的是迁移先后关系，不能提前删除现有登录能力。
- 测试替代：只使用合成身份、受控 Future/Event、正式 fixture 和测试专用 Gateway/MethodChannel handler；不得将替身接入默认/Release 组合，不能把测试数据的账号准备、缓存销毁或导入成功说成真实底层完成。
- 影响：生产 Session 接线、账号根图、Profile 缓存迁移、真实 v3 smoke 与双向交接尚未完成。解除条件为对应 owner 交付及同一 APK 接线验证。

## FLT-SYNC-003：无手机的验证边界

- 用户明确本次无法连接手机，相关环节以自动化测试替代，不等待或申请连接手机。
- 可以用测试覆盖 Widget 200% 字体/主题/语义、通知先激活再导航、迟到 Future/Event、重启快照恢复、退出/清缓存操作序列及失败投影。
- 这些结果不能证明 Android Keystore、真实 SQLCipher/JNI、系统调度、OEM 清理时机或双设备联网行为。真实设备项记录为 UNVERIFIED；本次不因此要求用户提供手机。
- 当前只有 F0 前置套件已实际编写和执行；完整产品场景的目标见 `docs/plan/active/云同步-06-Flutter测试先行验收矩阵.md`，该矩阵不是测试通过证据。

## FLT-SYNC-004：既有 Appearance 页面无法通过 Flutter 静态分析

- 实际执行 `flutter analyze --no-pub`：退出码 1，26 项问题。
- 首个错误为 `lib/main.dart:605` 的 `AppearancePage` 未定义；`lib/presentation/appearance/appearance_page.dart` 中 `Color`、`BuildContext`、`HabitProgressColorToken` 等未定义；`test/habit_widget_test.dart:255` 同样无法找到 `AppearancePage`。
- 本任务未修改这些文件，检查时它们也未出现在 Git 未提交修改列表中；这是当前检出内容的既有问题，不能归为新增前置测试造成。
- 影响：全项目 analyze 门禁未通过，Debug APK 和完整产品测试不能标记通过。没有为绕过此问题删测试、隐藏分析错误或重写其他任务的外观实现。
- 解除条件：恢复/修复 Appearance 页面及其类型依赖，运行对应现有 Widget 回归和全项目分析。此问题与 FLT-SYNC-001 的兼容基线问题分别处理。
