# 开发日志

## 2026-08-17 13:51 +08:00 认证与个人信息前后端 Review 计划编制

- 使用 Skill：无（纯文档编制任务）。
- 负责板块：`docs/reviews/active/`；未修改 contracts、plan 与实现代码。
- 任务目标：基于两份 `docs/plan/active/` 计划、`docs/architecture/overview.md` 与 contracts 认证边界，编制前后端针对性 Review 计划，聚焦重点审查内容与 AI 编程高频错误模式。
- 任务结果：新增 `docs/reviews/active/认证与个人信息-01-后端CloudBackend-Review计划.md`（15 个审查域：信封与错误码、Argon2id、Refresh Token 原子轮换、会话撤销矩阵、Challenge 生命周期、幂等、限流、隐私防枚举、Flyway 与并发约束、模块边界、JWT 过滤链、头像上传管线、测试真实性、跨端一致性等）与 `docs/reviews/active/认证与个人信息-02-前端本地-Review计划.md`（14 个审查域：Token 边界、分层、单飞刷新与 200 信封约定、页面状态机、错误映射、启动恢复、Keystore/MethodChannel、dio、表单与缓存、头像、Token Pair 续接、测试真实性、跨端一致性等）。
- 验证状态：纯文档编制，未执行构建/测试（不适用）。
- 开发时间：2026-08-17 13:51（Asia/Shanghai）。

## 2026-08-15 20:47 +08:00 认证两份 plan 与协议同步（经用户授权）

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`docs/plan/active/认证与个人信息-01-后端CloudBackend.md`、`docs/plan/active/认证与个人信息-02-前端本地.md`；未修改 contracts 与实现代码。
- 任务目标：按用户授权，将两份 plan 与已修订协议同步：端点计数 16→17；后端阶段 0/1 纳入 `auth.registration.email.update`；后端登录验收补 `AUTH_EMAIL_UNVERIFIED` 必带非空 `context.verification_challenge`；限流清单纳入新端点。
- 任务结果：后端 plan 五处计数改为 17，§5 幂等与限流清单纳入 `auth.registration.email.update`，阶段 0 核对清单新增密码所有权证明、登录上下文不变量与 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED` 分支，阶段 1 端点列表与验收表新增该端点行并强化 `auth.login` 未验证分支的上下文要求，§7 对应表同步；前端 plan 计数改为 17，阶段 0 走查项同步新端点与上下文不变量，阶段 2 登录"邮箱未验证"分支明确依赖后端保证的上下文，新增"修改邮箱入口"协议调用说明（新邮箱 + 注册密码 + `Idempotency-Key`），§7 对应表同步。grep 复核两份 plan 已无残留"16 个端点"表述。
- 验证状态：纯文档同步，未执行构建/测试。
- 开发时间：2026-08-15 20:47（Asia/Shanghai）。

## 2026-08-15 20:21 +08:00 认证协议两项阻断缺陷研判与修复

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`contracts/`（`backend_api.yaml`、`auth/update_registration_email_request`、`common/api_error`、`common/api_error_context`）与 `docs/domains/user_account.md`、`docs/domains/email_action_challenge.md`；未修改 Flutter、Kotlin、C++、后端实现代码。
- 任务目标：针对外部评审提出的两项阻断缺陷（①注册前更正邮箱缺少所有权证明；②`AUTH_EMAIL_UNVERIFIED` 不保证客户端能继续验证），研判其是否真实存在，存在则修复并输出证据链。
- 任务结果：两项缺陷均确认存在。①公开的 `auth.registration.email.update` 仅凭非秘密的 `account_id`（注册响应与登录错误上下文均携带）即可改变登录身份，结合密码重置可构成完整账号接管链 → 请求 schema 新增必填 `current_password`（注册时设置的密码作为所有权证明），端点错误码新增 `AUTH_CURRENT_PASSWORD_INVALID`；②`ApiError.context` 原为可选可空，Schema 允许返回不带上下文的 `AUTH_EMAIL_UNVERIFIED`，而验证/重发/更正邮箱全部强制 `challenge_id`，客户端会进入死路 → `api_error` 新增 `allOf` 条件（该错误码时 `context` 必填且非空），`api_error_context` 收紧为 `verification_challenge` 必填非空，并新增对应示例。领域文档与契约总则同步所有权证明与上下文不变量。Python 交叉校验（JSON 解析、17 端点引用闭合、错误码双域覆盖、两项修复的结构断言、新码不泄漏进 `native_error`）全部通过。
- 验证状态：协议层结构校验全通过；未执行 Flutter/后端构建与测试（本任务只改协议层，尚无消费方代码）。遗留：两份 plan 仍写“16 个端点”，且后端 plan 阶段 1 登录验收未提及必须携带 `context.verification_challenge`、限流清单未包含新端点，需人工同步。
- 开发时间：2026-08-15 20:21（Asia/Shanghai）。

## 2026-08-15 19:54 +08:00 认证与个人信息模块 Contract 走查与协议补充

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`contracts/`（`backend_api.yaml`、`auth/` 与 `common/` schema、`error_codes.yaml`）及 `docs/domains/user_account.md`；未修改 Flutter、Kotlin、C++、后端实现代码。
- 任务目标：对照 `docs/plan/active/` 中认证与个人信息前后端两份任务清单，逐端点、逐字段走查现有协议能否支撑完整开发；确认缺陷后对协议做最小完整性补充，并输出修改/新增原因的证据链。
- 任务结果：判定协议主体可支撑开发（16 端点、信封、幂等、session_policy、隐私与头像约束均已声明），但存在三处真实缺陷并已修复：① 前端清单要求验证页提供“修改邮箱入口”，但 16 个端点中无任何能力可更正未激活账号邮箱（重新注册会被 `AUTH_USERNAME_ALREADY_EXISTS` 拦截，登录态 `auth.email_change.request` 又不可用）→ 新增 `auth.registration.email.update` 端点与 `update_registration_email_request.schema.json`；② 后端清单要求“错码/过期/已用/超次→对应错误码”，协议缺少超次专用码 → 新增 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED` 并挂入三个 verify/confirm 端点，同时为改邮箱端点新增 `AUTH_ACCOUNT_NOT_FOUND`、`AUTH_ACCOUNT_ALREADY_VERIFIED`；③ 登录未验证路径依赖 `api_error_context.verification_challenge` 但缺 `account_id`，导致该路径无法使用改邮箱能力 → 补充必填 `account_id`。另声明 HTTP 200 + `ApiResult` 统一约定与幂等键冲突规则（消除前后端对 401/429 的分歧），并移除 `user.avatar.delete` 中语义不成立的 `AVATAR_UPLOAD_FAILED`。
- 验证状态：全部 `contracts/*.schema.json` 通过 Python JSON 解析；自研交叉校验脚本通过（17 个端点 request/envelope/data 引用闭合、全部端点错误码同时存在于 `error_codes.yaml` 与 `api_error` 枚举、4 个 `auth.refresh_token.*` MethodChannel schema 引用闭合、新码未泄漏进 `native_error` 枚举）。未执行 Flutter/后端构建与测试（本任务仅改协议层）。两份 plan 中“16 个端点”的表述需人工同步为 17 个。
- 开发时间：2026-08-15 19:54（Asia/Shanghai）。
## 2026-08-18 +08:00 认证前端审查修复逐项复核

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：`flutter_client/` 认证增量修复复核（只读 + 独立实测）；仅追加本日志。
- 任务目标：对照审查 findings 逐项核验修复者声明的 P1×2/P2×7/P3×9 修复是否真实存在于代码、是否产生预期行为，并独立重跑全部验证命令。
- 任务结果：**核心问题已修复**。P1-1 世代机制三处校验 + 3 个黑盒竞态回归测试真实存在且逻辑正确（读后/网络返回后/写回后校验，写回后失配补偿删除）；P1-2 先落盘后启用 AT、store 失败统一清态已实现并有测试。P2 全部可修项已修：状态码感知解析+5 用例、presentation 注入收敛（ProfileViewData 投影）、三 controller 捕获补齐、formatUtcDateTime 保留毫秒（Kotlin 端同步接受小数秒）、格式检查 0 changed、原子写去 delete、端到端并发 401 与敏感日志断言补齐。P3 九项中八项属实并修复/裁定合理，一项（分层小瑕疵）修 1 项留 2 项（rawResponse/systemTemp，判定可接受）。独立复测：`flutter test` **352/352**、`flutter analyze` 0 issue、`dart format --output=none --set-exit-if-changed` **0 changed**、Kotlin **136 项 0 失败**（1 skipped 为既有）、`git diff --check` 干净。残留：①修复者自己的验证产物 `flutter_client/dc_out.txt`、`reg_out.txt`、`android/gradle_out3.txt` 未清理，提交前须删除；②协调器补偿删除（token_refresh_coordinator.dart:101）未校验 delete 结果，属极窄双故障窗口的残余风险；③真实 Keystore cipher 仍无 instrumented/真机覆盖（已如实标注未验证）。
- 验证状态：上述数字均为本次独立实测（非沿用修复者报告）；未修改任何生产代码。
- 开发时间：2026-08-18（Asia/Shanghai）。

## 2026-08-18 10:49 +08:00 认证模块第三轮评审整改（P3 低危批次研判与修复）

- 使用 Skill：`frontend-flutter-feature`（研判 + 修复 + 回归验证）；Kotlin 三项沿用既定授权一并修复。
- 负责板块：`flutter_client/lib|test`、`flutter_client/android`、`docs/log.md`。
- 任务目标：对 P3 批次 8 项逐条研判并修复真实项。结论：①头像 ImageCache 残留【真实】——文件缓存随服务端响应更新，但内存 `NetworkImage` 未 evict；已在 ProfilePage 删除成功后 `unawaited(NetworkImage(old).evict())`（Presentation 负责，保分层）。②验证页 emailChange 模式伪死重发按钮+底部按钮语义不当【真实】——重发按钮改为仅 registration 模式渲染；底部按钮按模式显示"返回登录/返回个人信息"（goToLogin/goToProfile）。③api_field_error.message 原样透传+多数控制器缺字段级映射【真实】——新增共享 `apiFieldErrorText`（本地 23 码文案表优先、契约安全的服务端消息兜底）与 `applyFieldErrors` 路由器，8 个表单控制器全部接入字段级映射（register 原实现一并改为经本地文案表）。④startup exists() 故障与"无 RT"合并【真实】——Keystore 瞬态故障（可重试）改走恢复页；get_current 失败进主页判定为设计决策（ProfilePage 自带错误态+重试，符合清单）。⑤clearLocalSession 忽略 delete 失败【真实】——失败时单次重试，防残留 RT 导致下次自动登录。⑥邮箱正则分隔点未转义【真实】——`user@exampleXcom` 确判合法（我原始意图是转义的 `\.` 被模板串吃掉）；已修复并补 3 例反例测试。⑦报告"新增约 60"测试数不实【真实】——静态计数纠正为 25 个新测试文件（含 6 fakes）、130 test/testWidgets + production_composition 1 例 = 约 131，已更正 2026-08-16 日志条目。⑧Kotlin 杂项【多项真实】——JSONException cause 携带明文已移除；codec/contracts 重复校验与死重载已统一到共享 `AuthRecordPatterns`（含真实日历范围校验，拒绝 2026-13-99T99:99:99Z）；补失败信封形状断言（ok=false→data=null）与 patterns 单测；codec 无内嵌版本字段判定为可接受（文件名 v1 即格式版本）；分层小瑕疵中 MethodChannel 构造移出 data 层（文件移至 `boundary_adapters/dart_method_channel/`），`NativeInvocation.rawResponse` 与 `Directory.systemTemp` 判定为既有项目模式/用户已确认决策，不改。
- 任务结果：修复完成。`flutter test` 352/352 通过、`flutter analyze` 0 issue、`dart format --output=none --set-exit-if-changed lib test` 0 changed、Android `:app:testDebugUnitTest` BUILD SUCCESSFUL（新增 AuthRecordPatternsTest + 信封形状断言）、`flutter build apk --debug` 成功、`git diff --check` 干净。真机 Keystore 行为仍为未验证项。
- 开发时间：2026-08-18 10:49（Asia/Shanghai）。

## 2026-08-17 21:23 +08:00 认证模块第二轮评审整改（7 项 P2 研判与修复）

- 使用 Skill：`frontend-flutter-feature`（研判 + 修复 + 回归验证）；Kotlin 两项经沿用上轮授权一并修复。
- 负责板块：`flutter_client/lib|test`、`flutter_client/android`（Keystore 原子写/单测）、`docs/log.md`。
- 任务目标：对评审 7 项 P2 逐条研判并修复真实项。研判结论：①非2xx误分类+badResponse死代码【真实】——裸 5xx 无信封体因 dio 以 unknown（不带响应状态）抛出只能归为 transport(network)，不会落入契约错误；真正可修的是"非信封 JSON 对象体的 4xx/5xx"分类，已让 `_parseResponse` 状态码感知（5xx→server、其余→contract），`_mapTransport` 的 badResponse 分支确认为防御性死代码并注释。②Presentation 持有下层类型【真实】——forgot/reset/register 页面改注入 AuthService（application），ProfilePage 改只依赖 ProfileController+新增 ProfileViewData 投影（不再 import data/native_contract），AuthService 暴露 profileCache；route-args 携带 DTO 论证为应用内路由数据、可接受。③三控制器缺 SessionEnded/SecureTokenStore 捕获【真实】——email_verification/edit_profile/change_email 补齐两 catch，并统一 secureStoreUnavailableMessage 常量到 5 处。④expires_at 整秒重编码冲突【真实，机制描述有误】——解析端接受毫秒、重编码端抛错；已改 `formatUtcDateTime` 保留精度（纠正：该路径走 MethodChannel 而非 dio，FormatException 会转 CONTRACT_VALIDATION_FAILED 而非 transport）。⑤dart format 报告失真【真实】——实测 32 个增量文件未通过，已 `dart format lib test` 修复，承认此前报告基于范围化检查。⑥Keystore 先删后 rename 破坏原子性【真实】——去掉前置 delete，直接 rename 覆盖。⑦测试覆盖缺口【部分真实】——补客户端 5 个非2xx/信封用例 + e2e 并发 401 单飞用例 + Kotlin sensitive-payload 不打日志断言；instrumented Keystore cipher 在 JVM 无 Robolectric 无法运行，标记未验证不伪造。
- 任务结果：修复完成。`flutter test` 347/347 通过、`flutter analyze` 0 issue、`dart format --output=none --set-exit-if-changed lib test` 0 changed、Android `:app:testDebugUnitTest` BUILD SUCCESSFUL、`flutter build apk --debug` 成功、`git diff --check` 干净。真机 Keystore 加解密路径与裸非 JSON 5xx 的真实分类（unobservable，归 transport 网络类）仍为未验证项。
- 开发时间：2026-08-17 21:23（Asia/Shanghai）。

## 2026-08-17 20:19 +08:00 认证模块评审整改：退出/在途刷新竞态与 RT 写回失败处理

- 使用 Skill：`frontend-flutter-feature`（研判 + 修复 + 回归验证）。
- 负责板块：`flutter_client/lib/application/auth/`（会话世代、刷新协调器）、`flutter_client/test/`（回归测试）、`docs/log.md`。
- 任务目标：对评审提出的两个 P1 问题做研判并修复。研判结论：均真实存在——① `TokenRefreshCoordinator._doRefresh` 在刷新网络返回后无条件 `updateAccessToken`（复活内存会话）并无条件把新 RT 写回 Keystore，与 `LogoutService.logout()`（clearLocalSession）零协调，退出可被在途刷新静默撤销；② `_secureStore.store(...)` 返回值被丢弃，轮换后新 RT 未落盘时下次启动用旧 RT 会触发后端 `AUTH_REFRESH_TOKEN_REUSED` 撤销整个 token family（对照 `AuthService._applyTokenPair` 已有校验）。
- 任务结果：修复完成。`AuthSessionController` 新增单调世代 `generation`（markAuthenticated/markUnauthenticated/clearSilently 递增，同会话的 updateAccessToken/updateCurrentUser 不递增）；`_doRefresh` 在读取后、网络返回后、RT 写回后三处校验世代，失配即丢弃结果并终止（写回后失配额外删除刚写入的 RT，杜绝退出后凭据残留）；写回改为"先落盘新 RT、校验结果、再启用新 AT"，`store.result.ok=false` 时统一 `endSession()` 清态并抛 `SessionEndedException`。新增 5 个回归测试：退出在途刷新不复活会话、存储期间退出删除刚写入 RT、写回失败统一清态（黑盒组合真实 Coordinator+LogoutService+内存 secure store 复现评审场景）、会话世代语义 2 例。验证：`flutter test` 341/341 通过、`flutter analyze` 0 issue、`dart format` 检查通过、`flutter build apk --debug` 成功、`git diff --check` 干净。真机 Keystore 行为仍为未验证项。
- 开发时间：2026-08-17 20:19（Asia/Shanghai）。

## 2026-08-16 00:55 +08:00 认证与个人信息模块——前端本地全量实现（阶段 0–6）

- 使用 Skill：`frontend-flutter-feature`；经用户授权一并完成 `flutter_client/android` 内 Kotlin Keystore 部分（原属 `android-kotlin-native-feature` 范围）。
- 负责板块：`flutter_client/`（Dart + Kotlin）+ `docs/log.md`。未修改 `contracts/`、`cloud_backend/`、`cpp_core/`。
- 任务目标：按 `docs/plan/active/认证与个人信息-02-前端本地.md` 实现 12 项业务能力的本地闭环：dio 统一网络层（ApiResult v1 解析、单飞刷新、单次重试、幂等 Key）、typed DTO（auth/user/common 全量 schema 严格解析）、AuthGateway/UserGateway/RefreshTokenSecureStoreGateway 及实现、认证会话控制器（AT 仅内存）、TokenRefreshCoordinator（并发 401 只刷新一次、失败统一清态）、启动四分支检查、退出服务、cached_current_user v1 文件缓存（损坏视为无缓存，经用户确认替代 SharedPreferences 以守住"仅新增 dio"白名单）、登录/注册/邮箱验证/忘记密码/重置密码/修改密码/资料/编辑资料/修改邮箱/账号安全页面、头像展示与删除（更换入口提示暂不支持）、路由接入认证检查页、Android Keystore AES-256-GCM 的 4 个 `auth.refresh_token.*` MethodChannel handler 及 Kotlin 单测。
- 任务结果：**完整完成（协议缺口切片除外）**。`flutter test` 336/336 通过（新增 25 个测试文件〔含 6 个 fakes/fixtures〕、静态计数 130 个 test/testWidgets 用例 + production_composition_test 1 例 = 约 131；**更正**：此前"新增约 60 个测试"为未核实的估算，实测定量如上，336−131≈205 与历史基线一致。覆盖 DTO 严格解析、client 刷新重试/防循环、协调器并发单飞、启动四分支、控制器全失败分支、Widget 页面流、Fake API 走通注册→验证→退出与重启恢复集成流）；`flutter analyze` 0 issue；`dart format` 检查通过；Android `:app:testDebugUnitTest` BUILD SUCCESSFUL（新增 4 个测试文件）；`flutter build apk --debug` 成功。**协议缺口**：任务清单与后端清单引用的 `auth.registration.email.update` 端点不存在于 `contracts/backend_api.yaml`（契约仅 16 端点，改邮箱仅声明登录后的 `auth.email_change.request/confirm`），按硬边界#2 停做"注册验证页修改邮箱"切片并上报，未发明协议。头像系统相册选择因"仅新增 dio"白名单与无声明通道而跳过（用户确认），更换头像入口显示"暂不支持"。未验证项：无真机/后端联调，Keystore 真机读写、真实 Token 刷新链路与九条端到端验收流程均未执行；生产 baseUrl 默认 `http://10.0.2.2:8080`，可用 `--dart-define=BACKEND_BASE_URL=...` 覆盖。
- 开发时间：2026-08-16 00:55（Asia/Shanghai）。

## 2026-08-14 20:23 +08:00 Anniversary C++ 开发过程归档

- 使用 Skill：未使用专项 Skill；本任务为既有开发过程的纯 Markdown 总结。
- 负责板块：`A:\calendar\docs\plan\completed\纪念日-01-CPP.md`。
- 任务目标：按“最开始的开发要求、为什么改、探索过什么、拒绝了什么、验证过什么、当时有哪些限制、最终结果”归档 Anniversary C++/JNI 开发过程。
- 任务结果：完成纪念日 CPP 层首次完整开发记录，覆盖独立两 Store journal、显式 timezone、真实 JNI smoke、runtime 竞争与 Android lint/Manifest 修复，以及 Reminder/农历/cursor 等明确边界。
- 开发时间：2026-08-14 20:23（Asia/Shanghai）。

## 2026-08-14 18:51 +08:00 R0–R5 产品路线图整理

- 使用 Skill：未使用专项 Skill；本任务为纯文档规划。
- 负责板块：`A:\calendar\docs\status\roadmap.md`；未修改 Contract 或运行时代码。
- 任务目标：依据当前代码基线补齐 R0，并为 R1–R5 制定精炼、可执行的周期目标。
- 任务结果：完成六阶段路线图；R0 纳入已激活的 Category 与本地核心现状，R1–R5 依次覆盖本地 V1/账号、效率视图/同步、领域增强、AI/微信生态及多设备发布质量；全文 1492 字符，符合不超过 1500 字要求。
- 开发时间：2026-08-14 18:51（Asia/Shanghai）。

## 2026-08-14 18:31 +08:00 Category 物理设备验收与解除阻断

- 使用 Skill：`cross-layer-feature`（只读跨层验收）、`android-kotlin-native-feature`、`calendar-data-contracts`、`frontend-flutter-feature`。
- 负责板块：Android 物理设备 JNI/正式 Flutter 全链验收、Category Contract/Store 发布状态、Flutter production composition、可重复 integration test 及进度/问题/审查记录。
- 任务目标：在不放宽既有 Contract 的前提下验证隔离耗尽错误零写入、正式 Category create/list、Event 关联、分类清除/恢复与强停重启；仅在全部通过后统一解除 Category create/list 发布阻断。
- 任务结果：Android 16 arm64 设备通过 max→null JNI instrumentation，精确返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且独立/正式 Store 无写入；正式 Category 页面→MethodChannel→Kotlin→JNI→C++→Storage、Event create/search/detail/update、详情展示及 `force-stop` 后覆盖安装重启读取全部通过，强停前后 `categories.json` SHA-256 一致。MethodChannel、Native Call 和 Category Store 已切换为 `integrated + active`，默认/Release composition 直接使用 Native Repository，验收开关与 blocked Repository 已删除。激活后 Flutter 205/205、analyze、无开关 Debug/Release APK、Android JVM/AndroidTest 与 C++ 6/6 均通过；无验收开关的设备 restart 再次通过，最后已覆盖安装并启动正常 `main.dart` Debug 应用。新增可复用 write/restart integration test。已知影响：首次 `flutter test integration_test` 与 `flutter drive` 会自动卸载正式包并删除设备私有沙盒，导致原设备本地数据不可恢复；最终改用保留安装的 `flutter run --no-resident` 完成有效证据，后续禁止对正式 Store 使用会自动卸载的测试命令。
- 开发时间：2026-08-14 18:31（Asia/Shanghai）。

## 2026-08-14 17:07 +08:00 Category 三项发布阻断整改

- 使用 Skill：`cpp-core-feature`、`android-kotlin-native-feature`、`frontend-flutter-feature`、`calendar-data-contracts`。
- 负责板块：Category JSON 原子恢复协议与 C++ 回归、Kotlin 稳定错误码与独立 JNI 验收入口、Flutter production release gate、Contract 状态复核及进度/问题/审查记录；由三个智能体分别实施三项代码修复，主代理完成跨层审阅和复验。
- 任务目标：关闭“写入失败但新 Category 可见”“Kotlin 丢失 `CATEGORY_SORT_ORDER_EXHAUSTED`”“生产入口无条件使用 blocked Native”三项 P1，同时不影响其他 JSON Store、Android 正式 runtime 或既有 Flutter 功能；手机连接前不得提前激活 Category。
- 任务结果：Category 原子写现持久化 prepared/committed 恢复状态并在读写前收敛，三种 rollback 再失败可恢复或拒读；Kotlin 错误码 56/56 对齐并新增独立进程/Store 的 max→null 零写入 instrumentation；Flutter 默认和 Release 显式阻断，Debug/Profile 仅由验收开关接入 Native。Contract 保持 `implemented_unintegrated + blocked`。C++ check 6/6 且一次早期瞬时崩溃后连续 50 次 Category 重跑稳定；Flutter 208/208、analyze、默认/验收开关 Debug APK 及误传开关的 Release APK，Android JVM 107 项（0 failure/0 error/1 skipped）及 Debug/Test APK 均通过；lint 仍为既有 29 errors/20 warnings，且本次 Category 文件 0 finding。ADB 无设备，最终 JNI 与 Flutter 全链真机验收待后续执行。
- 开发时间：2026-08-14 17:07（Asia/Shanghai）。

## 2026-08-14 15:55 +08:00 全仓库实时代码进度研判

- 使用 Skill：未使用专项 Skill；本任务为跨模块只读代码盘点与状态报告，不实施业务代码修改。
- 负责板块：Flutter、Kotlin/Android、JNI、C++ Core、JSON Storage、Contracts、Cloud Backend、AI/平台占位目录及自动化验证；输出 `A:\calendar\docs\status\current.md`。
- 任务目标：不采用进度文档中的既有结论，仅依据当前生产代码、真实调用链、占位实现和本次验证结果，判断已实现、部分实现、未实现功能及后续顺序。
- 任务结果：研判整体产品范围约完成 40%，本地 Event/Recurrence/Reminder/Anniversary 主链已形成，Category 仍有发布阻断，Habit、完整日历/搜索、账号云端、SQLite/FTS、AI、微信和桌面组件等尚未实现；Flutter 206 项、C++ 6/6、后端 15 项、Android JVM 与 Debug APK 均通过，`flutter analyze` 0 issue；Android Lint 失败（29 errors/20 warnings），当前无连接设备，均已在报告中列为发布风险。
- 开发时间：2026-08-14 15:55（Asia/Shanghai）。

## 2026-08-14 14:58 +08:00 DATA_MODEL 枚举汇总文件

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\ExcellentCalendarAPP\docs\DATA_MODEL.md` 枚举章节的无损提取，以及 `A:\calendar\docs\domains` 汇总索引；未修改原始 Data Model、已有模型文件、Contract 或任何运行时代码。
- 任务目标：在保留各模型文件枚举副本的同时，把 `DATA_MODEL.md` 中全部枚举额外汇总到独立的 `enums.md`，便于一次性指定或读取枚举定义。
- 任务结果：新增 `A:\calendar\docs\domains\enums.md`，逐字包含源文档完整枚举章节，并在 domains `README.md` 增加入口；枚举内容与源片段逐字一致，原始 `DATA_MODEL.md` 未发生改动。
- 开发时间：2026-08-14 14:58（Asia/Shanghai）。

## 2026-08-12 13:40 +08:00 DATA_MODEL 领域文档拆分

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\ExcellentCalendarAPP\docs\DATA_MODEL.md` 的无损结构拆分、枚举归属与 `A:\calendar\docs\domains` 文档索引；未修改原始 Data Model、Contract、Dart、Kotlin、JNI、C++ 或存储实现。
- 任务目标：把统一 Data Model 按单个领域数据结构拆为独立 Markdown 文件，并把枚举原文复制到每个实际使用该枚举的模型文件，便于后续按需读取单一结构。
- 任务结果：生成 25 个模型文件和 1 个 `README.md` 通用语义/索引文件；全部 21 个枚举均已归属，模型章节与枚举块可逐字还原源文档，输出统一为无 BOM UTF-8。源文件 SHA-256 保持 `050F73411E87D5A30BCFCEF30FA74AEF6C566743A7BB606659BAC72A1265F682`，未发生改动。
- 开发时间：2026-08-12 13:40（Asia/Shanghai）。

## 2026-08-11 21:26 +08:00 Category Flutter 审查整改

- 使用 Skill：`frontend-flutter-feature`。
- 负责板块：Flutter Category 生产 Composition、Native Repository/DTO、分类选择与创建状态、新建/重复日程分类交互、Event detail Category 三态展示及 Flutter 测试；未修改 `contracts/`、Kotlin、JNI 或 C++。
- 任务目标：复核 `分类功能审查结果.md` 中 Flutter 主责/协作问题，属实则整改 CAT-002、CAT-003、CAT-007、CAT-008、CAT-009，不属实则保留并说明依据。
- 任务结果：五项均确认属实并完成 Flutter 整改。生产入口改为 `NativeCategoryRepository(MethodChannelCategoryAdapter())`，移除 Fake 与 `vin_star` owner 耦合；新建默认保持 `category_id=null`，Picker 以独立结果区分取消、具体分类和显式未分类，编辑清空提交显式 null，悬空 ID 未主动操作时继续保留；普通/重复详情均展示“未分类 / 活动分类名称与颜色 / 分类不可用或已删除”三态；`sort_order` 改为显式 null-last 并限制 `0..9007199254740991`，自动追加耗尽映射为稳定错误；Native 请求不再 trim、blank→null 或 uppercase，Schema-valid 原值进入 MethodChannel，规范结果由 C++ 返回。定向 51/51、Flutter 全量 206/206、全目录格式检查、`flutter analyze` 与 Debug APK 构建通过，`git diff --check` 无 whitespace error。真机 RMX5100 安装烟测受设备 USB 安装确认/策略阻塞：`flutter install` 返回 `Failure [-99]` 且已先卸载旧调试包，随后非流式恢复安装等待 124 秒超时，当前正式 Debug 包未安装，因此启动、日志和重启恢复同 ID 未验证；APK 保留于 `flutter_client/build/app/outputs/flutter-apk/app-debug.apk`。Contracts 仍为 `implemented_unintegrated + blocked`，本轮未越权切换为 `integrated + active`。
- 开发时间：2026-08-11（截至 21:26，Asia/Shanghai）。

## 2026-08-11 20:50 +08:00 Category Kotlin 审查整改

- 使用 Skill：`android-kotlin-native-feature`。
- 负责板块：Event/Category Kotlin Contract validator、`NativeCategoryBridge` 编译期接口约束、MethodChannel/Bridge 回归测试与正式 Factory 真机 smoke；未修改 Contracts、Flutter 或根 C++。
- 任务目标：逐项复核分类审查中 Kotlin 主责/协作问题，仅整改属实的 CAT-005、CAT-008 Kotlin 项和 CAT-010，并验证 CAT-009 的 Kotlin 原样转发现状。
- 任务结果：确认 CAT-005、CAT-008 Kotlin 项和 CAT-010 属实并完成整改；create/update/search/EventResponse/EventDetail 已严格校验 `category_id/category_ids/category` 与活动投影 ID，一次回调及 omitted/null/string 更新语义保持；Category `sort_order` 已限制为 `0..9007199254740991`；窄 Bridge 删除默认 throw，所有静态实现由编译器强制覆盖。CAT-009 在整改前已原样转发，无重复改动。Category/Event Category 专项 25/25、Android 全量 JVM 105 项（0 failure/0 error/1 skipped）、`flutter analyze`、Debug/AndroidTest/Flutter Debug APK 构建通过；realme RMX5100 真机正式 Factory→JNI→C++→JSON Storage create/list 与 runtime 重载通过、无崩溃。`lintDebug` 仍被范围外既有 29 errors/20 warnings 阻断，本轮文件零 finding。现有 smoke 因无 Category delete API 留下一个幂等测试分类，未直接篡改存储清理。
- 开发时间：2026-08-11（截至 20:50，Asia/Shanghai）。

## 2026-08-11 20:04 +08:00 Category Contracts 审查复核与整改

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category Request/Response/Store Schema、MethodChannel/Native Call 状态、Native Error、Event detail 聚合 Contract、Contracts README、DATA_MODEL、审查/任务结果与项目追踪文档；未修改 Flutter、Kotlin、JNI 或 C++ 运行时代码。
- 任务目标：逐项核验分类功能审查 CAT-001～CAT-010，整改属于 Contracts 开发者的状态真相、安全整数、规范化职责和 Event Category 聚合语义，同时保留跨层未完成项的发布阻断。
- 任务结果：确认十项问题均属实。Category 统一改为 `implemented_unintegrated + blocked`，未提前激活；`sort_order` 冻结为 `0..9007199254740991`，新增 `CATEGORY_SORT_ORDER_EXHAUSTED`；C++ Application/Domain 成为唯一规范化 owner；Event detail 补齐未分类、活动命中、悬空/软删除三态及正反 oracle；目录同步成功被明确为 Store 提交点。131 个 Schema/唯一 `$id`/73 个本地引用、7 个 YAML 和专项边界断言通过；C++ `excellent_calendar_check` 6/6、`git diff --check` 通过。非 Contract 层未整改，整体审查仍为 BLOCK。
- 开发时间：2026-08-11（截至 20:04，Asia/Shanghai）。

## 2026-08-11 16:52 +08:00 Category C++ Core / Android JNI 接入

- 使用 Skill：`cpp-core-feature`、`android-kotlin-native-feature`（后者仅用于用户临时授权的 Category Kotlin/JNI adapter 与验证范围）。
- 负责板块：Category C++ Domain、Application Service、Repository、严格 JSON Storage v2 codec、Boundary/NativeResult、runtime composition、Android JNI exports、Kotlin Bridge 及专项测试；未修改其他业务功能。
- 任务目标：基于现有 Category Contract 打通 Kotlin→JNI→C++→`categories.json` 的 list/create 链路，验证原子落盘、重启读取、错误映射、Unicode 与 Event `category_id` 保留。
- 任务结果：Category C++ 与 Android JNI 代码已接入；规定的 C++ configure/check 6/6、Flutter Category 19/19 与 `flutter analyze`、Android JVM 98 项（0 failure/0 error、1 skipped）、Debug APK、AndroidTest APK 和三个 ABI 的 2/2 Category JNI symbols 均通过。C++ 已真实验证边界调用、磁盘写入、runtime 重初始化恢复与 Event `category_id` 恢复；Android 设备 smoke 已实现但当前无连接设备且无 AVD，未实际执行 JNI/应用进程重启验证。生产 Flutter composition 仍注入 `FakeCategoryRepository`，且未获 Category-only Flutter 修改授权；因此四处 MethodChannel/Native Call 状态与 Category Store 状态继续保持 `planned`，不宣称全链路持久化完成。`lintDebug` 仍被 29 个既有 error/20 warning 阻断，Category 文件 0 finding。
- 开发时间：2026-08-11（截至 16:52，Asia/Shanghai）。

## 2026-08-11 15:10 +08:00 Category JSON Storage v2 结构设计

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category 本地 JSON Storage Contract、严格 Storage Schema、Data Model/Contract 说明、兼容与迁移边界、任务结果及项目追踪文档；未修改 Flutter、Kotlin、JNI 或 C++ 运行时代码。
- 任务目标：为已有 Category 领域/API 契约正式定义本地保存方式，明确文件、根包络、记录字段、版本、排序、原子写入、引用完整性、初始化、迁移和实际实现门禁。
- 任务结果：冻结 `categories -> categories.json` 与精确 `{"storage_version":2,"categories":[]}` 根对象，新增严格 `CategoryStorageRecord` Schema；正式磁盘记录强制 canonical UUIDv4、uppercase color 和已物化非空 sort order，按 ID 稳定序列化，使用目录锁内完整快照原子替换。Category 引用保持弱关联，无 v1/Fake/default seed migration，当前单文件操作无需扩展既有 journal；Store 与 `category.list/create` 继续保持 `planned`，没有伪报真实落盘。131 个 Schema/唯一 `$id`/73 个本地引用、7 个 YAML 及专项语义断言通过，C++ `excellent_calendar_check` 5/5、`git diff --check` 通过；实际 Category 磁盘写入仍未实现/未验证。
- 开发时间：2026-08-11（Asia/Shanghai）。

## 2026-08-11 11:31 +08:00 Category Kotlin 边界与 Native Bridge 接线

- 使用 Skill：`android-kotlin-native-feature`。
- 负责板块：`flutter_client/android` 内 Category typed Contract、MethodChannel Handler、`NativeCategoryBridge` 聚合接线、JVM 测试与无写入真机冒烟；仅按项目要求补写本日志。
- 任务目标：严格对接既有 `category.list` / `category.create` Contract 和 Flutter payload，建立可测试且不直接依赖 JNI 的 Kotlin 边界，并在 C++ Category 尚未实现期间稳定返回 `FEATURE_NOT_IMPLEMENTED`。
- 任务结果：完成严格请求解析与响应校验、异步分发、统一 `NativeResult` 错误转换和 exactly-once 回调测试，并确保 JNI/异常原始 message 不进入 Flutter 错误详情；生产 `JniNativeCalendarCoreBridge` 不声明或触发不存在的 Category JNI 符号，真机通过生产 Factory 验证两方法均返回 `FEATURE_NOT_IMPLEMENTED`。Category JVM 17/17、Android 全量 JVM 97 项（0 failure/0 error/1 skipped）、Flutter Category 19/19、`flutter analyze`、Android Debug/AndroidTest 与 Flutter Debug APK 构建均通过；`lintDebug` 仍被分类范围外既有 29 errors/20 warnings 阻断，本次 Category 文件零 finding。C++ 领域逻辑、JNI export、持久化与 Flutter 生产 composition 切换均未实现，未将接口预留误报为真实能力。
- 开发时间：2026-08-11（Asia/Shanghai）。

## 2026-08-10 20:45 +08:00 Category 数据模型与跨层契约补齐

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category 领域模型说明、JSON Schema、MethodChannel/Native Call 清单、Flutter typed DTO/Gateway/Adapter/Repository、Kotlin Contract/Handler/窄 Bridge，以及相关测试与进度文档。
- 任务目标：依据分类 Flutter 实际实现补齐稳定 `category_id` 关联、list/create 协议和可供后续 JNI/C++/Storage 实现直接采用的跨层边界，同时保留既有 Event 引用兼容性。
- 任务结果：新增并收紧 Category Schema，补齐 Flutter 与 Kotlin typed 边界；新 Category writer 固定 lowercase UUIDv4，Event/Anniversary 历史 `category_id` 保持 opaque reader 兼容。C++/Storage 未实现的两条能力明确维持 `planned`，JNI stub 返回 `FEATURE_NOT_IMPLEMENTED`，正式 App 继续使用严格符合 Contract 的 Fake。130 个 JSON Schema、7 个 YAML、Flutter 194/194、Android JVM 测试、Debug APK、C++ 5/5 和 `git diff --check` 均通过；真实 Category 持久化/真机闭环未验证。
- 开发时间：2026-08-10 20:45 +08:00。

## 2026-08-10 19:31 +08:00 Anniversary list 排序 Contract 收敛

- 使用 skill：`cross-layer-feature`、`calendar-data-contracts`。前者完成架构盘点后因必须修改受保护 Contract 判定 `BLOCKED`，随后转由数据协议专项完成修复。
- 负责板块：Anniversary list request Schema、Dart DTO/Gateway、Kotlin Contract validator、C++ Boundary 与相关跨层测试；不修改领域模型、JNI 签名、Repository 或 Storage。
- 任务目标：核验 Anniversary list top-level 与 nested pagination 排序位置、允许值和默认方向是否存在歧义；若存在，冻结唯一位置并覆盖非法 nested sort、双位置冲突和默认排序。
- 任务结果：确认问题属实。`pagination` 收敛为 `page/page_size/cursor`，`sort_by/sort_direction` 仅允许 top-level，缺失默认 `target_occurrence_date/asc`；Dart 改用 Anniversary 专用分页 DTO，Kotlin/C++ 显式拒绝 nested sort。129 个 Contract JSON/ID/本地引用及排序结构断言通过；Dart 定向 10 项与全量 187 项、Kotlin Anniversary 定向与 Android 全量 JVM 测试、C++ `excellent_calendar_check` 5/5、Flutter analyze、主 APK Debug 构建及 Native Smoke test/analyze/Debug 构建均通过。未重复执行真机 Anniversary list。
- 开发时间：2026-08-10 19:25–19:31（Asia/Shanghai）。

## 2026-08-10 19:25 +08:00 纪念日生产时钟修复

- 使用 skill：`frontend-flutter-feature`。
- 负责板块：Flutter 生产 composition、Anniversary `AppClock`、新建纪念日日期选择器与回归测试；未修改 Contract、Gateway、Kotlin、JNI、C++ 或存储。
- 任务目标：核验生产组合根固定注入 `2026-08-06` 时钟是否属于 Flutter 且真实影响新建纪念日；属实时以最小范围改为系统时钟，保留测试固定时钟注入。
- 任务结果：确认问题属实；原变量实际作为 `showDatePicker.initialDate` 而非具名 `currentDate`，仍会让新建页默认选中陈旧日期。新增 `SystemAppClock`，生产 composition 显式注入系统时钟，选择器的 initial/current date 共用同一注入值，并增加 production composition 与直接确认默认日期回归。定向 14/14 通过，`flutter analyze` 通过，Android Debug APK 构建通过；全库格式门禁仍只命中已记录的 `category_response_dto.dart` 既有差异，全量 Flutter 测试仅未跟踪的 `native_anniversary_gateway_test.dart` 因并行分页 payload 期望不一致失败，两者均未越界修改。
- 开发时间：2026-08-10 19:20–19:25（Asia/Shanghai）。

## 2026-08-10 16:58 +08:00 纪念日全链路架构与未提交代码审查

- 使用 skill：`review-worktree-architecture`。
- 负责板块：Anniversary Contract、Flutter Application/Native adapter、Kotlin MethodChannel、JNI、C++ Domain/Application/Boundary、JSON Storage、测试体系与全部 Anniversary 相关未提交改动；仅写入审查结果和本日志，不修改生产代码。
- 任务目标：按 `docs/review/纪念日功能审查/纪念日功能审查.md` 的阶段顺序，先冻结独立测试 oracle，再执行跨层、真实 Storage 与真机测试，最后完成架构/工作区审查，并同步结果到 `docs/review/纪念日功能审查/纪念日功能审查结果.md`。
- 任务结果：确认六条 Anniversary 方法已形成真实 Flutter→Kotlin→JNI→C++→JSON Storage 基础闭环；C++ check 5/5、Flutter 179/179、analyze、Android JVM/Debug/AndroidTest、APK 与真实设备六方法链路通过，lint 仍被 29 个既有 error/20 warning 阻断。发现 4 项 P1（生产 UI capability 与 Native V1 不匹配、列表只显示默认前 20 条、150 路径混合提交范围、真实 E2E 缺少数据隔离）及 5 项 P2，最终建议为“修复P0/P1后可以提交”。临时 Flutter 真机测试 teardown 曾卸载正式 Debug 包并清空其私有数据，至少确认丢失一条既有活动纪念日；已停止该方式、重装 Debug APK并在报告中完整披露，后续必须使用独立 application id/Storage 根。
- 开发时间：2026-08-10（Asia/Shanghai）。

## 2026-08-10 00:18 +08:00 Anniversary C++ Core / JNI 集成

- 使用 skill：`cpp-core-feature`、`calendar-data-contracts`、`android-kotlin-native-feature`（后两者仅用于用户授权的显式 timezone 跨层同步与 Anniversary Kotlin/JNI 真机验证范围）。
- 负责板块：Anniversary C++ Domain、Application Service、专用 JSON Transaction/Storage、Boundary Contract/API、JNI export 与测试；按用户授权最小同步 Anniversary Contract、Dart DTO/Gateway、Kotlin validator 和 Android JNI smoke。
- 任务目标：按 `docs/task/纪念日CPP层开发要求.md` 有序实现公历 Anniversary V1 六条调用；采用独立两 Store 事务，并让 create/update 显式携带设备 IANA timezone。
- 任务结果：六条 MethodChannel/JNI/C++ 调用和三个 Anniversary Store 已集成，Contract 状态更新为 `integrated`；动态 countdown、年度规则切换、软删除、journal 重放、旧 v2 增量初始化与稳定错误已实现。C++ check 5/5、Flutter 179/179、analyze、Kotlin/JVM、Android Debug/AndroidTest 与 `flutter build apk --debug` 通过；arm64 `.so` 导出 6/6 JNI symbol；realme RMX5100 真机 create → detail 持久化 → soft-delete smoke 通过。`lintDebug` 从 35 error/21 warning 降为 29/20，Anniversary 与 smoke 文件零 finding，剩余均为既有范围外问题。Reminder 为 `not_required`，农历保持显式 unsupported。
- 开发时间：2026-08-09—2026-08-10（Asia/Shanghai）。

## 2026-08-09 21:15 +08:00 日程分类选择与新建分类 Flutter 闭环

- 使用 skill：`frontend-flutter-feature`。
- 负责板块：Flutter Category 领域轻量模型、Application Controller、`CategoryRepository` 边界、共享内存 `FakeCategoryRepository`、分类选择/新建页面、新建日程与现有重复日程编辑入口接入，以及相关 Flutter 测试。
- 任务目标：依据 `docs/task/分类界面设计开发/分类界面设计开发要求-Flutter.md` 和参考图，实现“新建日程选择分类—新增分类—回到列表选择—按 `category_id` 提交 Event”的完整前端闭环；底层 Category 存储与 Contract 未接通期间使用可替换 Fake，且不让 Widget 直接访问 MethodChannel。
- 任务结果：完成 `CategoryPickerPage`、`CreateCategoryPage`、Category 分层接口及 loading/empty/error/retry、表单校验、颜色选择、稳定排序、防重复提交和运行期共享 Fake 数据；默认分类统一为“默认日程”，新建与重复日程编辑均按 Category ID 关联，未知原分类 ID 保留直至用户主动更换。任务相关 23 个 Dart 文件格式检查通过，`flutter analyze` 0 issue、Flutter 全量测试 178/178、Android Debug APK 构建及 `git diff --check` 通过；416×910 Widget 测试渲染完成并人工检查无溢出。全库格式门禁仅命中本次未修改的既有 `category_response_dto.dart` 差异；无可用模拟器，未执行真机交互验证。本次未修改 `contracts/`、`DATA_MODEL.md`、Kotlin、JNI 或 C++，`category.list` / `category.create` 仍为 Fake，真实 Contract、Native 持久化及 Fake Category ID 与 Native Event 外键闭环尚未实现。
- 开发时间：2026-08-09 20:24–21:15（Asia/Shanghai）。

## 2026-08-09 20:23:05 +08:00

- 使用 skill：`calendar-data-contracts`。
- 负责板块：Anniversary 领域模型、Anniversary Native Contract planned schema、根 README 与设计追踪文档。
- 任务目标：设计独立的 `AnniversaryRecurrence` / `anniversary_recurrences` 数据结构，冻结一次性/年度重复引用、日期锚点、动态 occurrence 与规则切换事务语义。
- 任务结果：完成 Data Model、Contract 与 README 同步；V1 固定 `yearly + interval=1`，原始日期只存于 `Anniversary.date`，不预生成 occurrence，规则启用/保留/解除与软删除语义已明确。129 个 Schema 的语法/ID/引用检查、7 个 YAML 解析、15 项 recurrence 结构语义断言、`git diff --check`、Flutter 6 项 Anniversary 定向测试及 Kotlin Anniversary handler 定向测试通过；C++/Storage/JNI 仍为 planned，未伪报实现完成。
- 开发时间：2026-08-09 19:50–20:23（Asia/Shanghai）。

## 2026-08-09 15:33 +08:00 Kotlin 职责审查复核与整改

- 使用 skill：`android-kotlin-native-feature`。
- 负责板块：`flutter_client/android` 的 MethodChannel 分发、Kotlin Contract v2 校验边界与相关 JVM 测试；按用户要求同步标记 `docs/review/审查职责功能.md`。
- 任务目标：复核审查文档中 Kotlin 层职责问题；属实项完成行为兼容整改，不属实项说明保留理由。
- 任务结果：确认并整改 `NativeMethodChannelHandler` 职责混合与 `V2BoundaryContracts` 跨模块集中；保留合理的 `NativeCalendarCoreBridge`、`JniNativeCalendarCoreBridge`、`MainActivity` 聚合职责；定向测试通过，全量 JVM 测试 78 项、0 failure、0 error、1 skipped，`flutter analyze` 与完整 Android Debug 构建通过；lint 仍受项目既有问题阻断，ADB 无连接设备。
- 开发时间：2026-08-09 14:40–15:33（Asia/Shanghai）。

## 2026-08-09 C++ 职责审查复核与整改

- 使用 skill：`cpp-core-feature`。
- 负责板块：`cpp_core/**` Contract v2 Boundary、JSON Storage aggregate validator 与 C++ 测试；按用户要求同步标记 `docs/review/审查职责功能.md`。
- 任务目标：逐项研判审查文档中的 C++ 候选，对属实问题实施行为保持整改，对不成立的问题记录实际架构依据。
- 任务结果：整改 `recurring_v2_api.cpp` God File 和 `validate_recurring_event_state` God Validation Function；保留 Transaction aggregate、Event workflow 与 process-global runtime 的现有合理设计；`excellent_calendar_check` 4/4 通过。
- 开发时间：2026-08-09（Asia/Shanghai）。

## 2026-08-09 15:28:03 +08:00 Flutter 职责审查复核与整改

- 使用 Skill：`frontend-flutter-feature`
- 负责板块：Flutter Presentation、Application/State、通知启动协调与 Flutter 测试
- 任务目标：研判 `docs/review/审查职责功能.md` 中 Flutter 层职责问题；修复属实项并在原审查文档标记
- 任务结果：完成新建日程 workflow、重复日程详情加载/操作、通知 permission/schedule lifecycle 三项职责拆分；相关 35 项测试、`flutter analyze`、165 项全量 Flutter 测试与 Android Debug APK 构建通过；全库格式检查仅剩未修改的 category DTO 既有格式差异
- 开发时间：2026-08-09 15:28:03 +08:00

## 2026-08-14 22:57 +08:00 问题登记册迁移与归档

- 使用 skill：无；本次是 Markdown 问题清单整理，没有适用的专项开发或文档制品 skill。
- 负责板块：`docs/problems.md` 问题提取、当前状态交叉核验，以及 `A:\calendar\docs\issues\open.md` 和 `A:\calendar\docs\issues\resolved\` 的登记册结构。
- 任务目标：提取原问题清单中的全部问题，将仍存在的问题写入开放登记册，并将已解决问题按 Contract/Reminder、Notification/Alarm、Flutter、Kotlin 架构、Anniversary、Category/Storage 模块归档，补齐根因、严重程度、解决方式和教训。
- 任务结果：建立 1 份开放登记册、6 份模块化已解决档案和 1 份源问题覆盖索引；依据 `develop_record.md` 与关键运行时代码纠正源文档中已过期的 v1/design-only 描述，将“代码缺陷已修复但真机/故障验证仍不足”的情况拆成已解决实现与开放验证风险。未修改原 `docs/problems.md`，未覆盖工作区既有修改。
- 开发时间：2026-08-14 22:57 +08:00。

## 2026-08-15 Architecture Overview 架构地图提取

- 使用 skill：无；本次为 Markdown 架构信息提取，没有适用的专项代码或 Office 文档 skill。
- 负责板块：完整阅读根 `README.md`，并结合 `docs/develop_record.md`、`docs/problems.md`、`docs/target.md` 与实际目录，编写 `A:\calendar\docs\architecture\overview.md`。
- 任务目标：把长篇 README 中的系统分层、职责边界、Contract 规则、领域不变量、当前持久化事实、代表性调用流和文档入口提炼为可快速阅读的当前架构地图，明确区分已实现能力与规划能力。
- 任务结果：完成 Android-first / Local-first 主链、Flutter→Kotlin→JNI→C++→JSON Storage v2 分层、可选云端边界、真实源码地图、Contract-first 规则、Event/Reminder/Notification/Recurrence/Anniversary/Habit/Category 不变量、运行时/事务约束与开发放置规则；明确当前生产持久化仍为 JSON Storage v2，SQLite/FTS 尚属后续迁移，避免把 README 的目标描述误写为当前事实。未修改生产代码、Contract 或实时进度文档。
- 开发时间：2026-08-15（Asia/Shanghai）。

## 2026-08-15 Architecture Overview 收敛与领域 ADR 拆分

- 使用 skill：无；本次为 Markdown 架构文档重组，没有适用的专项代码或 Office 文档 skill。
- 负责板块：`A:\calendar\docs\architecture\overview.md` 与 `architecture/decisions/` 的模块化 ADR。
- 任务目标：移除概览中的实时状态和开发守则内容，把 Core Domain Invariants 按 Event、Recurrence、Anniversary、Habit、Category、Common 模块拆成可独立查阅的 Accepted ADR。
- 任务结果：删除 `Current Reality` 与原 `Architecture Guardrails`；概览改为九节纯架构导航，并增加六份 `ADR-模块-01-标题` 决策记录，保留原有领域不变量、决策背景和直接后果，不新增未确认的业务规则。
- 开发时间：2026-08-15（Asia/Shanghai）。

## 2026-08-15 15:18 +08:00 Data Model 拆分文档一致性与歧义审查

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\docs\domains\**` 与项目内 `docs/DATA_MODEL.md` 的领域模型、枚举、时间、状态和文档来源一致性。
- 任务目标：详细核对拆分领域文档与项目数据模型是否一致，并识别内容冲突、未定义边界和可能产生多种实现解释的表述。
- 任务结果：确认 27 份拆分文档中的 64 个对应内容块与项目 `docs/DATA_MODEL.md` 逐字符一致，26 个索引链接有效；发现外部父目录另有一份较旧 `A:\calendar\docs\DATA_MODEL.md`、三处文档均可能被误认作事实源，以及 DST gap occurrence 身份、字段“必填”层级、Habit recurrence、Reminder/Notification 状态与若干计划态模型的语义缺口。未修改被审查文档或代码。
- 验证状态：完成 Markdown 标题/区块逐项比较、索引目标存在性检查、两份聚合 Data Model 哈希与定向差异检查，并对 Event、Habit、Reminder、Notification 的机器 Contract 做定向交叉核对；未执行构建或运行测试（纯文档审查，不适用）。
- 开发时间：2026-08-15 15:18 +08:00（Asia/Shanghai）。

## 2026-08-15 17:45 +08:00 HXY 分支归拢与并行工作树规划

- 使用 Skill：`openai-docs`；依据官方 Codex Worktrees 说明确认并行任务的工作区约束。
- 负责模块：Git 分支与工作树开发流程；不修改产品代码。
- 任务目标：将 `HXY-study` 上的现有提交及未提交文档变化归拢到 `HXY`，并说明从 `HXY` 建立 `HXY-backend`、`HXY-user` 两个独立工作树的安全流程。
- 任务结果：提交当前文档变化，并以 fast-forward 方式同步本地 `HXY`；工作树与派生分支仅提供方案，未在本任务中创建。
- 验证状态：已核对分支祖先关系、工作区状态与工作树列表；纯 Git/文档流程，未执行产品构建或运行测试。

## 2026-08-15 20:12 +08:00 认证与个人信息前后端 Contract 完整性审查

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：`contracts/backend_api.yaml`、认证/用户/公共 JSON Schema、错误码、Refresh Token MethodChannel、相关认证领域文档，以及两份 `docs/plan/active/认证与个人信息-*` 前后端计划。
- 任务目标：判断现有协议能否支撑两份计划的完整 Flutter/Kotlin ↔ CloudBackend 交互，逐字段排除局部不完整造成的误判，并在确认缺陷后给出证据链；不修改协议或实现。
- 任务结果：确认主体认证、Token 轮换与安全存储、资料/偏好缓存、密码与已登录邮箱变更、头像等协议链路基本闭合；确认注册前邮箱更正缺少所有权证明、`AUTH_EMAIL_UNVERIFIED` 未强制携带可继续验证的 Challenge 上下文，并识别用户协议版本语义未冻结。另确认当前 Contract 已有 17 个端点，而两份计划仍按 16 个端点编排且前端仍以 HTTP 401 描述刷新验收，属于计划与协议漂移。
- 验证状态：132 个 JSON 文件均可解析且 `$id` 唯一，本地 `$ref` 与 `backend_api.yaml` 引用均闭合；Backend endpoint 错误码与 `error_codes.yaml`、`ApiError.code` 枚举无缺失。环境缺少完整 JSON Schema metaschema/实例校验器，未执行构建或运行测试（只读协议审查，不适用）。
- 开发时间：2026-08-15 20:12 +08:00（Asia/Shanghai）。

## 2026-08-15 认证与个人信息前后端 Review 计划编制

- 使用 Skill：无；本次为纯文档任务（依据计划、契约与完成报告编制审查要点），不修改代码。
- 负责模块：`docs/reviews/active/认证与个人信息-01-后端CloudBackend-review计划.md`、`docs/reviews/active/认证与个人信息-02-前端本地-review计划.md`。
- 任务目标：针对 `docs/plan/active/` 两份开发计划编制针对性 review 计划，重点标注 AI 编程高频错误点，并把前后端 AI 的完成报告声称列为必须逐项核验的对象。
- 任务结果：两份 review 计划各含事实基线（独立重建，禁止沿用报告结论）、完成报告声称逐项核验、分主题审查要点（协议合规/session_policy/refresh 轮换/Challenge/幂等/隐私/密码/安全链/并发/媒体/模块边界；前端另含分层、Token 边界、单飞刷新、状态机、幂等 Key、缓存、Keystore、导航）、AI 高频错误速查表与四项判定输出要求。编制期间独立核对契约发现：当前 `backend_api.yaml` 实为 17 个端点且 `auth.registration.email.update` 明确存在，而两份完成报告均声称"契约只有 16 个端点、该端点不存在"；另确认契约 `envelope_only_errors: 200` 与"无 Retry-After 语义"约定，与后端报告所述"429+Retry-After/409"冲突，均列为最高优先级核验项。
- 验证状态：已逐条核对 `backend_api.yaml` 17 端点清单、`http_conventions`、`error_codes.yaml` 26 个错误码、`method_channels.yaml` 四方法声明与 `contracts/auth/` schema 存在性；纯文档编制，未执行构建或运行测试。
- 开发时间：2026-08-15（Asia/Shanghai）。

## 2026-08-22 14:23 +08:00 响铃提醒跨层实施计划拆分

- 使用 Skill：`cross-layer-feature`、`calendar-data-contracts`、`frontend-flutter-feature`、`android-kotlin-native-feature`、`cpp-core-feature`。
- 负责模块：`contracts/**`、`cpp_core/**`、`flutter_client/android/**`、`flutter_client/lib/**` 的响铃提醒调用链；本次仅做只读架构盘点与任务编排。
- 任务目标：依据现有 Dispatcher、两阶段投递和 Notification attempt 模型，将响铃提醒目标拆分为 Contracts、C++、Kotlin、Flutter 四个可独立开发并最终集成的执行计划。
- 任务结果：完成四层现状与依赖核对，冻结建议的协议面、层级职责、并行边界、合并顺序和端到端验收矩阵；识别普通 Reminder 多渠道语义、Recovery 溢出计数不变量及 Android 前台服务类型三个必须先处理的架构闸门。未修改产品代码、Contract 或既有计划文件。
- 验证状态：已定向核对权威领域文档、Schema、Dart 创建链路、Kotlin 调度/投递链路、C++ 校验/恢复链路和 Android 平台约束；本次为计划任务，未执行构建或运行测试，实施后的分层验证要求已纳入计划。
- 开发时间：2026-08-22 14:23 +08:00（Asia/Shanghai）。

## 2026-08-22 15:31 +08:00 响铃功能 Contract R1 冻结

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：`contracts/**` 与 `docs/domains/reminder.md`、`notification.md`、`reminder_recovery_batch.md`、`enums.md`；Flutter、Kotlin、JNI、C++ 实现保持只读。
- 任务目标：严格落实 `docs/plan/active/响铃功能-03-contracts设计.md`，冻结普通 ring Reminder、Notification sent 语义、5 分钟 Recovery、公开 `ring.*`、内部 `reminder.snooze`、隐私安全状态 DTO、错误码、身份、兼容与 fixture。
- 任务结果：普通 Reminder 成功态收口为单一 popup/ring、重复 Reminder 保持 popup，新增七个 blocked `ring.*` MethodChannel、`ring.state_changed` EventChannel、内部 snooze Schema/UUIDv5、Ring settings/capability/session/state DTO 与稳定错误；Recovery 固定 4:59/5:00/5:01 边界，并为避免计划外 JSON v2 migration 保留原 Batch 记录形状，将 `window_overflow_count` 冻结为全部窗口内摘要成员数。新增 19 个 Golden/正反例；能力保持 `planned/blocked`，等待架构批准及 04–06 层实现。
- 验证状态：168 个 Contract JSON 可解析，148 个 Draft 2020-12 Schema 元校验通过，7 份 YAML 可解析，全部本地 `$ref`、MethodChannel/JNI Schema 引用、错误码、枚举、UUIDv5 向量及 19 个 fixture 断言通过；Dart Reminder/Notification 合同回归 7 项通过。Android 既有回归未验证：首次被本机 Gradle 8.14 全局缓存损坏阻断，隔离缓存两次重跑又被 plugins.gradle.org TLS 握手中断，均未进入项目编译；未修改或清理用户全局缓存。未执行 C++/APK/真机验证（本轮不修改实现层且 ring 发布状态仍 blocked）。
- 开发时间：2026-08-22 15:31 +08:00（Asia/Shanghai）。

## 2026-08-22 18:01 +08:00 响铃功能 Kotlin/Android 原生实现

- 使用 Skill：`android-kotlin-native-feature`。
- 负责模块：`flutter_client/android/**` 的 ring 投递分流、持久化会话、前台服务、声音/振动、通知/锁屏交互、能力检测、`ring.*` MethodChannel/EventChannel、Native workflow 适配及测试。
- 任务目标：依据 `docs/plan/active/响铃功能-05-Kotlin开发.md` 实现 Android 响铃能力；对尚未可用的 C++ snooze/complete 上游仅在 Debug 构建使用确定性假结果，不让 Kotlin 开发等待下层。
- 任务结果：完成 popup/ring 分流、prepare→可见控制通知→输出→finalize 顺序、单一持久化 RingSession（含并发 revision、去重、进程恢复和 5 分钟硬上限）、API 31+ exact-alarm FGS 交接、静音独立控制通道、单/多条操作、隐私安全全屏页、铃声选择/测试、能力与设置状态、全部 ring 方法/事件以及 Debug-only Native fake；Release 在 JNI 缺失时保持失败，不伪造底层成功。
- 验证状态：`:app:compileDebugKotlin`、`:app:testDebugUnitTest`（112 项，0 失败、1 跳过；其中 Ring 新增 5 项全通过）和 `:app:assembleDebug` 通过；Lint 的 ring 相关错误为 0，但全项目 `:app:lintDebug` 仍被既有 API 24 `java.time` 等 29 个错误阻断。Debug APK 已在 Android 13/API 33 国产 ROM 真机安装并启动，无启动崩溃；设备通知权限处于 denied，未擅自授权，因此真实响铃输出未执行。`connectedDebugAndroidTest` 因设备 instrumentation 退出后 UTP 客户端无结果挂起而中止；JNI smoke 及 API 24/31/34/35/36 矩阵未验证。按计划完成标准，本轮不得宣称响铃功能整体完成。
- 开发时间：2026-08-22 18:01 +08:00（Asia/Shanghai）。

## 2026-08-22 19:12 +08:00 响铃功能跨层审查、真实 Native 收口与集成验证

- 使用 Skill：`review-worktree-architecture`、`cross-layer-feature`、`debug`。
- 负责模块：响铃 Contracts、Flutter、Kotlin/Android、JNI、C++ Core 的跨层一致性审查；修正范围为 `flutter_client/android/**` 与 C++ Category 测试生命周期缺陷，并保护工作区既有认证、后端及其他未提交修改。
- 任务目标：逐项核验四层完成报告是否由真实实现支撑，移除假数据路径，补齐 Flutter → Kotlin → JNI → C++ 的真实调用链，并按原四层计划重跑构建、测试和设备 smoke。
- 任务结果：确认 Contracts、C++ 与 Flutter 主体实现符合计划；发现 Kotlin 声明了 `nativeSnoozeReminderV2` 但 APK JNI adapter 未导出，且 Debug 在 Native 不可用时伪造 snooze UUID 与 Event 完成成功。现已补齐 JNI 导出、删除全部 Debug fake 并增加失败回归测试；将前台服务的 Native/音频准备移至单线程执行器，避免阻塞主线程；启用官方 Android core library desugaring 并修正 API 31 能力检查，关闭原有 29 个 API 24 lint 错误；仅忽略 Flutter 在 Windows 自动生成且不入库的 `local.properties` 驱动器转义提示。最终 C++ 复跑另发现 Category 测试 helper 从临时 JSON 返回内部引用导致悬空引用，已改为按值返回并消除约 10% 的随机段错误。
- 验证状态：Contract 168 个 JSON 解析及 87 个本地 `$ref` 目标闭合；C++ Category 复现为修复前 20 次失败 2 次、修复后连续 30 次零失败，随后 `excellent_calendar_check` 6/6 通过；Flutter `flutter test` 225 项通过、`flutter analyze` 0 问题、`flutter build apk --debug` 通过；Kotlin JVM 114 项通过（0 失败、1 跳过，Ring 7 项通过）、`:app:lintDebug`、`:app:assembleDebug` 通过；APK 的 arm64 Native Library 已确认导出 `nativeSnoozeReminderV2`；Android 13/API 33 realme RMX3687 真机覆盖安装、冷启动成功且进程存活。API 24/31/34/35/36 设备矩阵、真实响铃声音/振动/锁屏/进程恢复和 ring 动作到 C++ 的设备级调用仍未验证，因此 Contract 的 `planned/blocked` 发布闸门保持不变，未宣称整体发布完成。
- 开发时间：2026-08-22 19:12 +08:00（Asia/Shanghai）。

## 2026-08-22 20:02 +08:00 Flutter 真机启动与 Android 时区链路修复

- 使用 Skill：`cross-layer-feature`、`debug`。
- 负责模块：本机 Gradle 8.14 缓存、`flutter_client/android/app/src/main/cpp/CMakeLists.txt`、vendored `date` Android 时区加载边界；其余响铃 Contracts、Flutter、Kotlin 与 C++ 业务实现仅做回归验证。
- 任务目标：解决无额外环境变量执行 `flutter run -d ZXNZDEW4ZPN7499L` 时的 Gradle transform metadata 损坏，并确保应用启动后的 Flutter → Kotlin → JNI → C++ 提醒/响铃链路真实可用。
- 任务结果：停止 Gradle daemon 后，将 42 个缺少 `metadata.bin` 的 transform 目录移动到可恢复备份 `C:\Users\vincent\.gradle\caches\8.14\transforms.corrupt-20260822-flutter-run-1918`，从已验证的隔离缓存恢复 41 个同哈希目录并非破坏性合并完整 module/transform 缓存，未删除用户缓存。随后真机暴露独立的 `TIMEZONE_DATABASE_UNAVAILABLE`：原 Android CMake 通过 `-UANDROID/-U__ANDROID__` 让 date v3.0.4 走源码 TZDB，却同时破坏平台头文件选择；改为在系统头解析后仅关闭 date 自身的 Android 二进制分支，并在源码 TZDB 行读取处归一化 Windows CRLF，消除空行 `\r` 触发的 `ios_base::clear`。未修改 Contract、提醒语义或存储格式。
- 验证状态：全局 Gradle active transform 2841 个且缺失 metadata 为 0；最终原样 `flutter run -d ZXNZDEW4ZPN7499L` 成功构建、安装、连接 VM Service，应用保持运行，启动日志中 `ring.get_state`、四次 `event.search`、`reminder.reconcile_schedule` 均 `ok=true`，ReminderQueue Worker 为 `SUCCESS`；真机独立 JNI persistence/reinitialize smoke 通过；`flutter build apk --debug`、`flutter analyze`、Flutter 225 项测试、Android `testDebugUnitTest`、C++ `excellent_calendar_check` 6/6、`git diff --check` 均通过。未擅自授予设备通知权限，因此真实声音、振动、锁屏全屏和 ring 操作链仍按原发布闸门标记为未验证。
- 开发时间：2026-08-22 20:02 +08:00（Asia/Shanghai）。

## 2026-08-23 14:49 +08:00 “123456”日程响铃 ADB 只读核验

- 使用 Skill：`debug`。
- 负责模块：Android 真机上的 Event、Reminder 持久化状态与 AlarmManager Dispatcher 调度状态，只读诊断，未修改设备数据或业务代码。
- 任务目标：通过 ADB 检查标题为“123456”的日程是否成功创建响铃提醒。
- 任务结果：确认 Event `d29c46a3-f766-4e42-b9fd-246bf2db23a0` 存在且为 active；关联 Reminder `6102788a-688c-407f-92c0-42f747aa3cb2` 使用 `ring`，本地计划时间为 2026-08-23 14:50，状态为 `scheduled` 且无失败原因；Android AlarmManager 中存在同一时刻的精确 `REMINDER_DISPATCH_ALARM`，精确闹钟权限为 allow。由此确认响铃提醒已成功创建并进入系统调度。
- 验证状态：已在 RMX5100 / Android 16 / `com.excellentcalendar.excellent_calendar` debug 包上完成 ADB 真机核验；复查时设备时间为 14:48:52，尚未到触发时刻，因此本次未验证到点后的实际声音、振动、控制通知及 Native 投递终态。
- 开发时间：2026-08-23 14:49 +08:00（Asia/Shanghai）。

## 2026-08-23 14:54 +08:00 “123456”日程到点响铃行为 ADB 复查

- 使用 Skill：`debug`。
- 负责模块：Android Reminder 到点投递、Ring 前台控制通知、声音、振动与会话状态，只读真机诊断。
- 任务目标：确认“123456”在 14:50 到点后是否出现预期响铃行为。
- 任务结果：Dispatcher Alarm 与 `START_RING_SERVICE` 均实际唤醒；Reminder 在 14:50:05 转为 `sent`，对应 `ring` Notification attempt 完成 prepare/finalize 且无错误码；Android MediaPlayer 于 14:50:05.702 使用 `USAGE_ALARM` 启动，振动于 14:50:05.711 启动并持续约 9 秒，控制通知也曾发布。发现厂商系统在 14:50:06.104 记录 `AudioHardening background playback would be muted`，MediaPlayer 随即被静音，因此声音只启动约 0.4 秒，未达到持续响铃预期。复查时 Ring 持久化会话为 null、服务已结束，未发现业务投递失败或崩溃。
- 验证状态：RMX5100 / Android 16 真机 ADB 已确认调度、Native 投递终态、通知、音频启动和振动启动；声音持续性未通过，领先原因是 realme/OPPO 厂商后台音频限制，尚未通过改变前台/锁屏状态等区分实验确认应用侧可规避方案。本轮未修改业务代码或设备设置。
- 开发时间：2026-08-23 14:54 +08:00（Asia/Shanghai）。

## 2026-08-23 15:00 +08:00 Anniversary occurrence 查询与日历聚合方案解释

- 使用 Skill：`self-learning`。
- 负责模块：Anniversary、Event occurrence 与 Calendar Query Engine 的查询职责和架构边界，只读分析。
- 任务目标：解释路线图中“提供日历聚合所需的 occurrence 查询”的必要性，并比较不提供独立 occurrence 查询时的替代方案。
- 任务结果：确认当前 Anniversary list 是以“本地今天”为基准的下一次 occurrence/countdown 投影，不能完整回答任意月/周/日半开区间内的所有实例；Calendar 聚合需要按区间动态展开 Anniversary occurrence，并与普通 Event、重复 Event occurrence、Habit 等统一排序。比较了领域 occurrence 查询、聚合服务内嵌展开、前端展开、有限窗口物化索引、影子 Event 等方案；推荐保留 C++ 领域内唯一日期规则，并由 Calendar Query Engine 调用有界 occurrence 查询或等价的内部查询接口。
- 验证状态：已核对 `docs/status/roadmap.md`、`docs/status/current.md`、Anniversary/Event occurrence 领域文档与 ADR、现有 `event.list_occurrences` Contract/C++ 实现及 Calendar Query Engine 职责；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-23 15:00 +08:00（Asia/Shanghai）。

## 2026-08-23 15:05 +08:00 Recurrence 与 occurrence 心智模型校准

- 使用 Skill：`self-learning`。
- 负责模块：重复日程动态展开、日历查询投影与 occurrence 稀疏状态持久化的概念边界，只读教学说明。
- 任务目标：确认“通过 occurrence 引擎计算每次重复日期并记录到日历”的理解，并纠正可能导致无限预生成的误区。
- 任务结果：确认主线理解正确；补充区分 Recurrence 规则、Occurrence 实例投影和 EventOccurrenceState 稀疏状态，强调普通 occurrence 默认按查询窗口动态展开、不逐条持久化，只有完成、跳过、取消、重新打开等用户操作才保存对应 occurrence 的状态。
- 验证状态：基于上一轮已核对的 Event occurrence Contract、C++ 查询实现、领域文档与 ADR 完成解释；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-23 15:05 +08:00（Asia/Shanghai）。

## 2026-08-23 15:10 +08:00 多领域 occurrence 日历统一投影解释

- 使用 Skill：`self-learning`。
- 负责模块：Event、Anniversary、未来 Habit 到 Calendar Query Engine 的统一读取投影边界，只读架构教学。
- 任务目标：确认多种领域对象生成 occurrence 后统一汇入日历视图是否合理。
- 任务结果：确认该方向适合作为 Calendar read model；强调只统一日历所需的公共投影，不统一各领域实体、Recurrence Contract、身份、状态和操作语义。Event、Anniversary、Habit 应由各自领域查询生成 occurrence，再由 Calendar Query Engine 归一化、合并和排序，并通过 source type/id 路由详情和操作。
- 验证状态：依据已核对的 Recurrence/Anniversary ADR、Calendar Query Engine 职责和当前 occurrence Contract 完成解释；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-23 15:10 +08:00（Asia/Shanghai）。

## 2026-08-23 C++ Core 初学者项目走读与能力训练路线

- 使用 Skill：`self-learning`。
- 负责模块：`cpp_core` 架构、Event 创建调用链、Repository、JSON Storage、错误模型、构建与测试入口；只读教学分析。
- 任务目标：为刚接触项目的 C++ 初学者建立分层地图、推荐走读顺序，以及面向实际开发的分阶段能力训练方案。
- 任务结果：选定 Event 创建为第一条代表性主链，梳理了 Boundary API → Workflow → Application Service → Repository → JSON Storage 的控制流，以及 Native Runtime 的对象组装、`Result<T>` 错误传播、`shared_ptr` 生命周期、RAII 加锁和 CMake 测试目标；给出从可复述到可修改、可调试、可设计的渐进练习。
- 验证状态：已核对架构概览、文档索引、Event 领域定义与 Accepted ADR、C++ 实际实现、CMake 和测试入口；本任务未修改业务代码，未执行构建或测试。当前工作区存在用户已有的大量未提交修改，教学结论已区分稳定架构与在开发实现。
- 开发时间：2026-08-23（Asia/Shanghai）。

## 2026-08-24 C++ Core 项目地图复述评估与概念校准

- 使用 Skill：`self-learning`。
- 负责模块：`cpp_core` 的 include/src 组织，以及 Application、Boundary、Contract、Common、Domain、Infrastructure、Repository、Storage 职责边界；只读教学分析。
- 任务目标：评估学习者对 C++ 项目目录地图的口语化复述，确认已掌握内容并纠正影响后续走读的概念偏差。
- 任务结果：确认学习者已能识别主要层级及总体依赖方向，当前约达到“能解释”等级；重点校准了头文件声明与编译/链接边界不等同于依赖倒置、Boundary 仅建立结构可信而不能替代领域校验、Contract 同时覆盖请求/响应类型但当前旧路径存在解析职责混放、Domain 头文件与源文件分别承载类型声明和规则实现、Infrastructure 负责领域所需外部技术能力的具体适配等概念。
- 验证状态：已核对架构概览、文档索引，以及 Anniversary Query Service、Event Boundary/Contract、Common DateTime/Error Metadata、LocalTimeResolver/TZDB Infrastructure、Anniversary Domain、Event Repository/JSON Storage 的实际头文件和实现；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-24 C++ 抽象依赖与校验分层掌握检验

- 使用 Skill：`self-learning`。
- 负责模块：Anniversary 时间解析依赖、Event Boundary/Application 校验、Event Repository 抽象及测试替身；只读教学反馈。
- 任务目标：评估学习者对 `LocalTimeResolver`、Boundary 与业务校验、`EventRepository` 可替换性的三项回答，并纠正依赖方向表述。
- 任务结果：确认三项核心判断均正确，掌握程度达到“2 能解释”；补充指出 `TzdbLocalTimeResolver` 是项目内 Infrastructure 适配器而非第三方代码本身，替换实现时通常不修改 `LocalTimeResolver` 接口；Boundary 会验证 `start_at/end_at` 均为 ISO 8601 字符串，Application 再比较时间先后；`JsonEventRepository` 实现而非被 `EventRepository` 调用，迁移 SQLite 时新增实现并在 composition root 更换注入，同时测试可继续使用 InMemory/Failing Repository。
- 验证状态：已核对 Event Boundary 时间格式校验、EventService 时间关系校验、Native Runtime 的 Resolver 注入，以及 Event Repository 测试替身；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-23 16:06 +08:00 响铃稍后提醒与恢复投递一致性修复

- 使用 Skill：`cross-layer-feature`、`debug`。
- 负责模块：Android/Kotlin Ring session workflow、Flutter Ring EventChannel 边界、Reminder recovery/live reconcile 失败隔离及相关 JVM 回归测试；Contracts、C++ snooze 语义与 Flutter 页面协议保持只读。
- 任务目标：核验并修复评审发现的“C++ 已创建稍后 Reminder 但当前 Ring session 未移除/未停止”、`RING_SETTINGS_STORAGE_FAILED` 误报及恢复失败阻断后续合法实时 Reminder 的跨层一致性问题。
- 任务结果：确认问题真实存在。根因一是 Ring session 持久化、内存提交与 EventChannel 广播共用同一异常边界，广播异常会被误报为存储失败；根因二是 snooze 忽略 session remove 结果且没有统一触发 Reminder 重规划；根因三是 V2 due batch 对首个投递失败直接返回。现已拆分持久化与广播边界并将 Ring 状态事件切回 Android 主线程；新增单一 `RingSnoozeWorkflowCoordinator`，严格按 C++ 逐项结果移除成功项、保留失败项、阻止旧 revision 重放，并同步触发权威队列重规划，调度失败时入 WorkManager 恢复且通过 `ALARM_SCHEDULE_FAILED` 明确返回“已创建、调度待恢复”；通知栏和全屏页也会显示部分失败/待恢复反馈。V2 reconcile 改为记录失败 Reminder、继续同批后续投递并重挂未来队首，避免 recovery/ring 局部失败污染合法实时提醒。
- 验证状态：新增回归在修复前 2/2 稳定失败，修复后通过；Android JVM 119 项 0 失败、1 跳过，`lintDebug`、`assembleDebug` 通过，Debug APK 已生成；Flutter 225 项、`flutter analyze`、Dart format 242 文件通过；C++ 构建后 `excellent_calendar_check` 6/6 通过；`git diff --check` 无格式错误（仅既有 LF/CRLF 提示）。当前 ADB 无连接设备且无本地 AVD，因此本轮修复后的真机“稍后全部 → 10 分钟后重响”和 API 24/31/33/34/35/36 矩阵仍未验证；Contract 的 `planned/blocked` 发布状态未提前修改。
- 开发时间：2026-08-23 16:06 +08:00（Asia/Shanghai）。

## 2026-08-23 16:55 +08:00 响铃跨层真机验收与发布状态校准

- 使用 Skill：`android-kotlin-native-feature`、`calendar-data-contracts`。
- 负责模块：Android/Kotlin Ring snooze 响应映射、Android device acceptance instrumentation、Flutter→Android 构建安装链路，以及 Ring MethodChannel/EventChannel/JNI Contract 发布状态。
- 任务目标：在物理 Android 设备复验评审阻断项、确认 Gradle transforms 构建问题消失，并在满足发布门禁后解除 Ring Contract 阻塞。
- 任务结果：真机首轮复现了新的跨层数值映射缺陷：C++ JSON 将 Contract integer `snooze_minutes=10` 序列化为 `10.0`，Kotlin 只接受 `Int/Long`，导致 C++ 已创建稍后 Reminder 后被误报为 `NATIVE_INTERNAL_ERROR`。现已按 JSON integer 语义接受值为 10 的任意 `Number`，增加 JVM 回归与脱敏错误日志。新增设备验收入口，以正式 AlarmManager→Dispatcher→JNI→C++→RingRuntime 链路验证双 Reminder 单会话合并、稍后全部逐项成功、成功项立即移除、C++ UUID 幂等重放、重复 Android 操作拒绝、随后新普通 Ring 正常投递并 finalize sent、五分钟自动转为 quiet_pending、输出停止但控制通知保留，以及进程结束后按原 session/deadline 恢复并可关闭。测试 Event 均在 finally 中软删除，Ring active session、重启 marker 和精确 Reminder Alarm 均已清理；未清空应用数据、未修改设备权限或系统设置。原 Gradle metadata 故障未复现，`flutter run --no-resident` 已在同一设备重新构建、安装并冷启动成功。
- 验证状态：realme RMX5100 / Android 16（API 36）通知权限和 exact alarm 能力通过；Ring quick、five-minute、restart prepare/verify 四项 instrumentation 均通过，关键日志无 `RING_SETTINGS_STORAGE_FAILED`、`ok=false`、`NATIVE_INTERNAL_ERROR` 或崩溃；Android JVM 120 项 0 失败、1 跳过，`lintDebug`、Debug APK 与 androidTest APK 构建通过；Flutter 225/225、`flutter analyze` 通过；C++ 构建后 `excellent_calendar_check` 6/6 通过；相关 `git diff --check` 无错误，仅既有 LF/CRLF 提示。当前机器只有 API 36 真机且没有 system image/AVD，Kotlin 有效计划要求的 API 24、31、33、34、35 运行矩阵无法执行；因此 Contract 已从不准确的 `planned` 校准为 `implemented_unintegrated`，但 `release_status` 继续保持 `blocked`，未虚假解除发布门禁。
- 开发时间：2026-08-23 16:55 +08:00（Asia/Shanghai）。

## 2026-08-23 17:03 +08:00 响铃一期发布门禁豁免与 Contract 激活

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Ring 一期发布门禁、Flutter↔Kotlin MethodChannel/EventChannel 能力图、Kotlin↔C++ `reminder.snooze` 内部能力图及 Contract 发布说明。
- 任务目标：依据用户明确批准，以 realme RMX5100 / Android 16（API 36）国产 ROM 验收替代一期 API 24/31/33/34/35/36 完整矩阵，并解除 Ring 发布阻塞。
- 任务结果：有效 Kotlin 计划已将 API 36 国产 ROM 的 AlarmManager、Dispatcher、JNI/C++、声音/振动、稍后提醒、五分钟安全停止和进程恢复验收确认为一期发布门禁；API 24、31、33、34、35 调整为后续非阻塞兼容矩阵，API 24 静态 lint 仍为必过项。七个 `ring.*` MethodChannel、`ring.state_changed` EventChannel 和内部 `reminder.snooze` 已统一切换为 `implementation_status: integrated`、`release_status: active`，Contract README 的发布状态与兼容说明同步收口。此次仅改变发布状态和验收规则，不改变 Native Contract v2 payload、业务语义、错误码、身份、Storage 格式或历史数据解释，因此无需版本提升或数据迁移。
- 验证状态：168 份 Contract JSON 解析通过；七个 Ring MethodChannel、一个 Ring EventChannel 和 `reminder.snooze` 状态逐项检查均为 integrated / active；相关 `git diff --check` 无格式错误，仅既有 LF/CRLF 提示。激活所依赖的同一 APK 真机与全量回归证据来自紧邻上一轮记录：API 36 四项 device instrumentation、Android JVM 120 项、lint/Debug APK、Flutter 225 项/analyze、C++ 6/6 均通过。
- 开发时间：2026-08-23 17:03 +08:00（Asia/Shanghai）。

## 2026-08-23 21:01 +08:00 纪念日 Reminder 与 Occurrence 需求冻结及开发计划

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Anniversary、Reminder、Notification、Recovery、日历 occurrence projection，以及 JSON Repository 到未来 SQLite transaction 的存储边界；本轮仅完成需求分析与计划文档，未修改业务代码。
- 任务目标：结合现有 Anniversary/Reminder/Occurrence 架构，通过分轮产品访谈冻结一次性与年度提醒、多个 popup、当地时间与时区、迟到补发、聚合通知、编辑删除联动、日历历史 occurrence 和摘要查询需求，并形成可执行的跨层开发计划。
- 任务结果：新增 Active Plan `docs/plan/active/纪念日-02-Reminder与Occurrence开发计划.md`。确认每个纪念日最多 5 条、默认关闭、0～365 天和分钟级当地时间、跟随设备时区；补发有效期延续至 occurrence 当天结束；同一 occurrence 多条逾期 Reminder 只展示一条聚合 Notification，但 covered Reminder 均以同一 fulfillment delivery 进入 sent 并分别滚动 successor；occurrence 查询使用最多 400 个自然日的半开窗口、无 200 条总上限、内部 cursor 分批并返回标题/周年数/分类/重要性/小铃铛/提醒数量摘要。架构采用 Application Workflow + 窄 Repository port；当前 JSON 使用可恢复的 scoped logical commit，未来由 SQLite transaction 替换，不建设大型统一 CalendarTransaction；Scheduler 在数据提交后 reconciliation。`docs/index.md` 已增加该 Active Plan 导航。
- 验证状态：已核对当前架构概览、Anniversary/Reminder/Recurrence/Notification 领域文档、Accepted ADR、Active status/roadmap/open issue、相关 Contract、C++ Workflow/Repository/JSON transaction 和 Flutter prototype；`git diff --check` 无错误，仅报告 `docs/index.md` 既有行尾转换提示。计划文件的关键规则、阶段门禁、跨层清单、迁移与测试矩阵已完成定向一致性检查；本轮为文档规划任务，未运行构建、单元测试或真机验证。
- 开发时间：2026-08-23 21:01 +08:00（Asia/Shanghai）。

## 2026-08-23 22:09 +08:00 纪念日 Reminder 与 Occurrence 白盒 Review 计划

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：Anniversary、Reminder、Notification、Recovery、Occurrence projection 的 Contract、C++ Domain/Application/Boundary、JSON Storage、Kotlin/JNI/Android Scheduler/Notification、Dart/Flutter 及跨层验证；本轮只制定未来审查计划，未修改生产代码。
- 任务目标：为尚未实施的 `纪念日-02-Reminder与Occurrence开发计划.md` 预先冻结一份偏白盒、面向真实代码控制流和故障场景的 Review 计划，重点标明项目中最容易被混淆、遗漏或以假实现通过的风险。
- 任务结果：新增 `docs/reviews/active/纪念日-02-Reminder与Occurrence-review计划.md` 并在 `docs/index.md` 增加导航。计划包含发布阻断红线、跨层能力闭环、date-only occurrence、身份与 DST、编辑/暂停/恢复并发状态机、聚合履约、共享 `reminders.json` 的跨 journal 覆盖、v2→v3 migration、C++/JNI/Kotlin/Flutter 白盒检查、既有 Event/Ring/Recovery 回归、独立 test oracle、崩溃注入点、测试质量和 AI/赶工高频错误速查表；同时纳入 Contract 子计划的总开关/单条开关语义、partial-success、日末补发与既有 72 小时 Recovery 关系等停止条件。
- 验证状态：已读取项目级 Agent 规则、架构概览、文档索引、上位计划、Contract 子计划、相关领域文档与 Accepted ADR、开放风险、跨层审查参考、现有 Contract 和真实 C++/Kotlin/Dart 代码入口；新增文档引用路径均存在。相关 `git diff --check` 无格式错误，仅有 `docs/index.md` 既有 LF/CRLF 转换提示。本轮为文档规划任务，未运行构建、单元测试或真机验收；工作树中其他计划移动和新增文件均保留且未改动。
- 开发时间：2026-08-23 22:09 +08:00（Asia/Shanghai）。

## 2026-08-23 22:16 +08:00 纪念日 Reminder 与 Occurrence 四层执行计划拆分

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Anniversary、Reminder、Notification、Recovery、Calendar occurrence projection 的 Contracts、Flutter、Kotlin/Android、C++ Core/JSON Storage 任务边界，以及最终跨层集成门禁；本轮只制定计划，未修改业务代码。
- 任务目标：在不改变 `纪念日-02-Reminder与Occurrence开发计划.md` 任何产品行为、领域不变量、测试或完成标准的前提下，拆成四份可分别交给 Contracts、Flutter、Kotlin、C++ 负责人的可执行计划；Contract 先行冻结，后三层基于同一提交使用受控 Fake/Test Double 并行开发，最后由集成人接入真实链路并清理生产 Fake。
- 任务结果：新增 `纪念日-03-contracts设计.md`、`纪念日-04-Flutter开发.md`、`纪念日-05-Kotlin开发.md`、`纪念日-06-CPP开发.md`。每份计划均包含当前代码基线、目录所有权、禁止范围、分阶段任务、Fake 边界、需求追踪、测试矩阵、交接包、停止条件和“并行交付就绪”定义；总计划新增四计划导航、共同真相源、分支/worktree 规则、责任覆盖矩阵，并将实施拓扑调整为 Contract 唯一前置、三层并行、最终按 Contract→C++→Kotlin/JNI→Flutter 合并、生产 Fake 审计和跨层真机门禁。`docs/index.md` 已补充导航，同时保留并发加入的白盒 Review 计划入口。
- 验证状态：已核对架构总览、文档索引、当前状态/路线图/open issue、Anniversary/Reminder/Notification/Recovery 领域文档与 Accepted ADR、相关 Contract，以及真实 Dart/Kotlin/JNI/C++/JSON 入口；五份计划文件均存在、标题结构完整、相对链接目标存在，`git diff --check` 无格式错误，仅有既有 LF/CRLF 转换提示。本轮为文档计划任务，未运行业务构建、单元测试或真机验证。
- 开发时间：2026-08-23 22:16 +08:00（Asia/Shanghai）。

## 2026-08-23 23:26 +08:00 纪念日 Reminder 与 Occurrence Contract R1 冻结

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Anniversary、Reminder、Notification、ReminderRecoveryBatch 领域语义；Native MethodChannel/JNI Schema、枚举、错误、UUIDv5 identity；Calendar Core JSON v2→v3 目标迁移；Anniversary 与既有 Ring Contract fixture。
- 任务目标：执行 `纪念日-03-contracts设计.md`，在不修改 Dart、Kotlin、JNI、C++ 生产实现的前提下冻结 Anniversary date-only occurrence、最多五条 popup 模板、create/update/toggle/delete 生命周期、日末补发聚合、真实 delivery 履约、partial-success、分页 cursor、身份算法和 Storage migration，使三层实现可从同一基线并行开发。
- 任务结果：新增 Accepted ADR 与四份领域文档闭环；新增 Anniversary template/plan/settings/capability、occurrence request/summary/page、toggle/delete response、catch-up group 等强类型 Schema；Reminder 改为 Event/Habit/Anniversary 严格 target-specific 分支，Notification/Recovery/prepare/finalize/tap 冻结 `anniversary_catch_up`、covered membership 和 fulfillment 关系；新增 15 类稳定错误、相关枚举、4 个 namespace 与 9 个 Anniversary identity vectors；Native Wire 保持 v2 但受影响方法准确标记 blocked，Calendar Core 明确采用 planned/blocked v3 与可恢复 v2→v3 migration/shared coordinator；交接与追踪矩阵位于 `contracts/anniversary/README.md`。冻结提交为 `7217523`。
- 验证状态：隔离验证环境中实际执行 `python contracts/validate_anniversary_r1.py`，162 个 Draft 2020-12 Schema 通过 metaschema、唯一 `$id` 与 `$ref` 闭合检查，Anniversary/Ring 43 个正反 fixture 通过，16 个 UUIDv5 vector 独立重算一致；`git diff --cached --check` 通过，仅有仓库既有 LF/CRLF 转换提示。未运行 Dart/Kotlin/C++ 构建、真实 v2→v3 migration、JNI/APK/Alarm/Notification 或真机测试，因为本阶段禁止修改并尚未接入这些实现；相关能力保持 blocked，不能据此宣称功能已集成或可发布。
- 开发时间：2026-08-23 23:26 +08:00（Asia/Shanghai）。

## 2026-08-24 15:08 +08:00 纪念日 Reminder 与 Occurrence Flutter 并行交付

- 使用 Skill：`frontend-flutter-feature`。
- 负责模块：Flutter Anniversary typed DTO/Gateway/Application、创建/编辑/详情提醒交互、Notification permission/capability 展示、typed occurrence 自动分页 port、Notification tap 路由及直接相关测试；生产组合继续使用真实 `MethodChannelAnniversaryAdapter`。
- 任务目标：执行 `纪念日-04-Flutter开发.md`，依据冻结 Contract R1 实现纪念日提醒总开关、最多五条 popup 模板、暂停/恢复、保存与调度部分成功反馈、权限与 exact alarm 降级提示、date-only occurrence 查询和聚合通知点击详情，同时不在 Dart 重算 occurrence、周年数、DST、successor 或底层 identity。
- 任务结果：新增分钟级当地时间与提醒模板强类型、Reminder plan/settings/capability/mutation/detail/delete/occurrence 严格 mapper、`anniversary.set_reminders_enabled` 与 `anniversary.list_occurrences` MethodChannel 接线、窄 occurrence Gateway 和全页 Use Case；表单支持当天/提前 1 天/提前 7 天快捷项、自定义 0～365 天、逐条启停/编辑/删除、重复与五条上限即时校验，权限拒绝后仍保留草稿并允许保存；详情展示活动数量、模板、暂停/恢复、pending reconciliation 和系统设置入口；normal/aggregate Anniversary tap 均透传 occurrence identity 到真实详情路由。生产入口未引入本功能 Fake 或占位成功，范围外 `FakeAnniversaryShareGateway` 保持不变。开发期间工作区同时出现的 C++/Kotlin/文档并行改动均未修改或整理。
- 验证状态：纪念日定向 DTO/Gateway/Application/Widget/路由测试通过；`dart format --output=none --set-exit-if-changed lib test` 通过（246 文件、0 变化）；`flutter analyze` 通过；`flutter test` 236 项全部通过；`flutter build apk --debug` 成功生成 `build/app/outputs/flutter-apk/app-debug.apk`；`git diff --check` 无错误，仅有既有 LF/CRLF 提示。Flutter 单层已达到计划定义的“并行交付就绪”；未执行物理设备上的真实 Flutter→Kotlin→JNI→C++→JSON→Alarm→Notification 到点/补发/权限/时区/旧 Alarm 验收，因此不能据此宣称上位跨层计划完成或 Contract 可发布。
- 开发时间：2026-08-24 15:08 +08:00（Asia/Shanghai）。

## 2026-08-24 15:18 +08:00 纪念日 Reminder 与 Occurrence Kotlin/Android 并行交付

- 使用 Skill：`android-kotlin-native-feature`。
- 负责模块：`flutter_client/android/**` 内的 Anniversary MethodChannel/Kotlin Contract/JNI、Reminder reconciliation、Alarm 调度、系统恢复触发、Notification/Recovery v2 投递与点击边界，以及直接相关 JVM/Android smoke 测试。
- 任务目标：执行 `纪念日-05-Kotlin开发.md`，依据冻结 Contract R1 接通 Anniversary 提醒计划、暂停/恢复和 occurrence 查询，保证逻辑提交后的可恢复调度、popup exact-alarm 近似降级、系统/权限恢复、同 occurrence 聚合补发一次 post、稳定 delivery identity 与 Anniversary detail 点击载荷；不得引入 production Fake 或在 Kotlin 重算 occurrence/successor/identity。
- 任务结果：新增严格 request/response validator 和窄 `AnniversaryMethodOrchestrator`，接通 `anniversary.set_reminders_enabled`、`anniversary.list_occurrences`、partial-success capability 与提交后统一 reconciliation；notification permission 拒绝或调度失败时保留数据并进入现有 retry。共享 Dispatcher 仅允许 popup 在 exact 权限缺失时走 inexact Alarm，Ring 继续要求 exact；补齐 `DATE_CHANGED` 和权限授权后的主动恢复。Recovery/Delivery/Notification Contract 支持冻结的 Anniversary catch-up group、covered Reminder membership、单 prepared attempt/单 finalize、delivery 稳定 tag 和 occurrence 点击 identity。并行 C++ Boundary 已提供真实 API 后，补上 `nativeSetAnniversaryRemindersEnabledV2` 与 `nativeListAnniversaryOccurrencesV2` 生产 JNI thunk；debug 设备 smoke 扩展为 create→update→detail→toggle→occurrence 正反例。生产 source set 未加入 Fake、占位成功或第二套 Anniversary Alarm。
- 验证状态：定向测试与 `:app:testDebugUnitTest` 通过，共 127 项、0 failure、0 error、1 项既有 skip；`:app:lintDebug`、`:app:assembleDebug`、`:app:assembleDebugAndroidTest` 均通过，arm64-v8a/armeabi-v7a/x86_64 CMake/JNI 构建成功；用 NDK `llvm-nm` 在 x86_64 `libexcellent_calendar_native.so` 中确认两个新增 JNI symbol 已导出；`git diff --check -- flutter_client/android` 无格式错误，仅报告既有 LF/CRLF 转换提示。`adb devices -l` 未发现在线设备，因此 instrumentation、真实 Alarm 到点、聚合通知、权限/时区变化、旧 Alarm 拒绝、冷/热启动点击及进程重启幂等仍为 **未验证**，不能据此宣称上位跨层计划已完成或可发布。工作树中并行存在的 C++、Flutter、Contract/计划改动均保留，未由本任务整理或覆盖。
- 开发时间：2026-08-24 15:18 +08:00（Asia/Shanghai）。

## 2026-08-24 15:51 +08:00 Anniversary finalize 时区 Contract 兼容修正

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：共享 `reminder.finalize_delivery`、`plan_recovery`、`prepare_delivery` Contract，Anniversary finalize/Recovery 语义、幂等 golden fixture 与 Contract 验证门禁；未修改 Flutter、Kotlin、JNI 或 C++ 代码。
- 任务目标：解除 C++ 年度 successor 无法在重启后可靠进行 DST 投影的协议阻塞，同时保持 Event、Ring 和普通 Recovery 旧 finalize payload 的 Native v2 兼容性。
- 任务结果：为共享 finalize 请求新增结构可选、非空 IANA `timezone`；冻结 prepared attempt 加载后的条件语义——Anniversary Reminder 与 `anniversary_catch_up` 缺失时返回 `CONTRACT_VALIDATION_FAILED`、非法 ID 返回 `TIMEZONE_ID_INVALID`，普通旧调用方无需补字段。首次成功 finalize 使用当前时区持久化 successor；提交后重放返回原对象且不因新时区重算，timezone 不进入 Reminder/delivery/attempt identity，可重试失败不生成 successor。`plan_recovery.timezone` 继续必填并负责 Anniversary 日末、expired successor 与 Recovery 重物化；`prepare_delivery` 明确不接收时区。新增有效、缺失、非法、Event/Ring 回归和跨时区重放 fixtures，并提供标准库自举入口将验证依赖安装到系统临时缓存。兼容修正冻结提交为 `1961953`。
- 验证状态：实际执行 `python contracts/run_anniversary_r1_validation.py` 成功，自举安装 `jsonschema`、`PyYAML` 与 `tzdata`；162 个 Draft 2020-12 Schema、49 个 Anniversary/Ring fixture、16 个 UUIDv5 vector 全部通过。全部 Contract JSON 解析与相关 `git diff --check` 通过，仅有仓库既有 LF/CRLF 转换提示。未运行或修改 Dart/Kotlin/C++ 构建、测试、JNI/APK 与真机流程；这些层仍需按新 Contract 接线并完成各自验证。
- 开发时间：2026-08-24 15:51 +08:00（Asia/Shanghai）。

## 2026-08-24 Contracts 计划向上交付总结补充

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：`纪念日-03-contracts设计.md` 交付记录。
- 任务目标：将 Anniversary finalize 时区兼容修正的开发结果精炼为面向上级的交付总结，不包含下游实现指导。
- 任务结果：在计划末尾追加交付结果、完成内容、验证证据和状态边界，明确 Contract 修正提交 `1961953`、兼容策略及整体能力仍 blocked；未修改任何业务代码。
- 验证状态：新增计划内容经 `git diff --check` 检查；本轮为文档整理，不重复运行业务构建和 Contract 门禁。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-24 纪念日 C++ Core 交付总结回填

- 使用 Skill：`cpp-core-feature`。
- 负责模块：纪念日 C++ Core 开发计划交付记录。
- 任务目标：将已完成内容、验证结果、剩余门禁和关键约束精炼追加到对应计划。
- 任务结果：已在 `纪念日-06-CPP开发.md` 末尾追加实施交付总结，明确 C++ 核心业务能力已完成，Storage v3/shared coordinator 与跨层真机验收仍待完成。
- 验证状态：已检查文档差异和格式；本轮未修改业务代码，未重复运行构建测试。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-24 纪念日 Flutter 交付总结回填

- 使用 Skill：未使用专项 Skill（仅进行计划文档回填）。
- 负责模块：纪念日 Flutter 开发计划交付记录。
- 任务目标：将 Flutter 已完成内容、验证结果和后续修复注意事项精炼追加到对应计划，删除对维护无帮助的过程性描述。
- 任务结果：已在 `纪念日-04-Flutter开发.md` 末尾追加实施交付总结，明确功能落点、关键语义、验证证据和未完成的真机集成门禁。
- 验证状态：已检查目标文档差异和格式；本轮未修改业务代码，未重复运行 Flutter 测试或构建。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-24 纪念日 Kotlin/Android 交付总结回填

- 使用 Skill：未使用专项 Skill（仅进行计划文档回填）。
- 负责模块：纪念日 Kotlin/Android 开发计划交付记录。
- 任务目标：将 Kotlin/Android 已完成内容、验证结果和交付边界精炼追加到对应计划，仅陈述实际工作，不包含上层验收建议或 C++ 后续安排。
- 任务结果：已在 `纪念日-05-Kotlin开发.md` 末尾追加开发交付总结，覆盖 Anniversary Channel/JNI、提醒调度、通知与恢复、时区协同、测试范围和关键约束。
- 验证状态：检查目标文档差异及格式；本轮未修改业务代码，未重复运行 Android 测试或构建。
- 开发时间：2026-08-24（Asia/Shanghai）。

## 2026-08-24 18:11 +08:00 Calendar Core Storage v3 与跨 Workflow 一致性

- 使用 Skill：`cpp-core-feature`。
- 负责模块：`cpp_core/**` 的 Calendar Core JSON Storage v3、v2→v3 migration、统一 workflow transaction coordinator、generation/CAS、Runtime bootstrap 与专项测试。
- 任务目标：将 Storage v3 从占位状态落为正式可运行格式，无损升级非空及部分 v2 真机旧存储，统一 Anniversary、Event、Recovery、Delivery、Snooze 对共享 Store 的提交和恢复，并阻止陈旧 after-image 覆盖新数据。
- 任务结果：全部正式 Store 严格读写 `storage_version: 3`；新增可中断续跑、保存 source hash/after-image/阶段的幂等迁移，迁移前严格恢复两类 v2 journal，缺少后加入 Anniversary/统一事务文件的非空 v2 可安全升级且不生成虚假 Reminder；新增目录锁级统一事务协调器，将相关 Workflow 接入同一 `calendar_workflow_transactions.json`，使用持久化 Store generation、`before_generation` CAS 和冻结 after-image 完成提交/重放；Runtime 按迁移、校验、统一恢复、服务构造顺序启动并报告 format v3。未修改冻结 Contract、JNI、Kotlin 或持久化 `projection_timezone`。
- 验证状态：新增完整 populated/partial/空存储迁移、两类遗留 journal、11 个 Store 替换点故障恢复、重复迁移、v3 round-trip、未知/缺失字段、非法与陈旧 generation、跨 Workflow 顺序写、CAS 冲突及统一 journal 重启恢复测试；实际执行规定的 CMake 配置和 `excellent_calendar_check`，7/7 测试目标全部通过，`git diff --check -- cpp_core` 无格式错误（仅既有 LF/CRLF 提示）。跨层 APK/真机验收不属于本轮 C++ 单层门禁，仍未执行。
- 开发时间：2026-08-24 18:11 +08:00（Asia/Shanghai）。

## 2026-08-24 20:01 +08:00 纪念日 Reminder 与 Occurrence 最终跨层整合

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`。
- 负责模块：Anniversary Reminder/Occurrence 的 Contract、Flutter/Dart、Kotlin/Android、JNI、C++ Core、Calendar Core JSON Storage v3 真实接线，以及跨层和物理设备验收。
- 任务目标：审计四层并行交付，依据总计划修正偏差，移除生产可达的本功能 Fake/占位链路，并完成 Flutter→MethodChannel→Kotlin→JNI→C++→JSON→Alarm→Notification→详情点击整合。
- 任务结果：统一 Runtime Contract 与 Kotlin bootstrap 为 Native Contract v2/Storage format v3；修复 notification permission 拒绝时关闭或删除提醒被错误阻塞的问题；冻结并实现普通 Anniversary notification tap 的 `anniversary.detail` route；生产 Flutter 使用真实 `NativeAnniversaryGateway`，Android 使用真实 `AndroidNativeBridgeFactory`/JNI，C++ 使用 Storage v3 JSON Repository 与统一 workflow coordinator。新增真实 Flutter 设备集成测试和进程终止后的 Alarm/Notification/tap instrumentation；受影响 Contract 能力标记为已整合，但在完整真机矩阵完成前保持发布 blocked。测试 Fake 仅保留在测试边界；范围外 `FakeAnniversaryShareGateway` 未修改。
- 验证状态：Contract 校验通过（162 schemas、54 fixtures、16 identity vectors）；C++ 构建后 `excellent_calendar_check` 7/7 通过；Flutter 236 项测试、`flutter analyze`、`flutter build apk --debug` 通过；Android `testDebugUnitTest`、`lintDebug`、Debug APK 与 androidTest APK 构建通过；独立 `test_environment/flutter_native_smoke` test/analyze/build 通过。物理设备 RMX3687 完成真实 create/detail/toggle/occurrence/update/list/delete round-trip、Storage v2→v3 smoke、进程终止后正常 Alarm 到点、单 Notification、年度 successor、普通 Anniversary 详情 route 与重复点击去重。总计划要求的真机聚合补发、时区切换、exact-alarm 拒绝近似降级、删除/改期后的真实陈旧 Alarm 仍未逐项执行，相关逻辑由 Contract/C++/Kotlin 自动测试覆盖但标记为真机未验证。
- 设备与数据说明：Flutter integration test runner 在测试流程中卸载应用，导致设备原应用私有数据被清除；之后已重装 APK，当前 Store 仅包含验收产生并软删除的记录，无法恢复测试前私有数据。验收后已恢复通知权限为拒绝、移除 device-idle 白名单并在 ColorOS UI 关闭完全后台/自启动；系统 `RUN_ANY_IN_BACKGROUND` 仍显示 `allow`，无法通过受限 shell 恢复到验收前的 `ignore`。
- 开发时间：2026-08-24 20:01 +08:00（Asia/Shanghai）。

## 2026-08-25 12:26 +08:00 纪念日 Reminder/Occurrence 跨层白盒审查

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：Anniversary Reminder/Occurrence 的未提交 Contract、Flutter、Kotlin/JNI、C++、Storage v3、Android 调度/通知、测试与状态文档。
- 任务目标：依据总计划、专项 review 计划、领域不变量和机器 Contract，对最终整合结果进行 dirty-worktree 架构与白盒审查，不修改生产实现。
- 任务结果：结论为“阻塞，需修正后复审”。确认生产主链已真实接线且常规自动化基线通过，但发现 commit 已权威成立后仍返回 `CALENDAR_WORKFLOW_COMMIT_FAILED`、时区广播未重投影未来 Anniversary `remind_at`、Update 缺少计划要求的 `expected_updated_at` 并发门禁、设备集成测试继续复用正式 application id、Flutter 普通 Anniversary tap 未拒绝缺失 route、occurrence cursor 未绑定真实 Store generation，以及能力/计划/状态文档互相漂移等问题。
- 验证状态：Contract 162 schemas/54 fixtures/16 identity vectors通过；C++ 构建后 `excellent_calendar_check` 7/7 通过；Flutter 236 项测试、`flutter analyze`、Debug APK 通过；Android JVM、lintDebug、androidTest APK 构建通过；独立 Flutter/Native smoke test/analyze/build 通过；`git diff --check` 通过。另以临时独立 oracle 复现“返回 commit failed 但重启后 generation 已权威递增”，并复现 Flutter 接受 Contract 标记为 invalid 的缺 route tap payload；临时文件均已删除。为避免再次清除设备数据，未重跑 Flutter 真机 integration runner；未执行用户列出的剩余物理设备矩阵。
- 开发时间：2026-08-25 12:26 +08:00（Asia/Shanghai）。

## 2026-08-25 13:22 +08:00 纪念日 Reminder/Occurrence 审查问题修正

- 使用 Skill：`debug`、`cross-layer-feature`，并按专项范围使用 `calendar-data-contracts`、`frontend-flutter-feature`、`android-kotlin-native-feature`、`cpp-core-feature`。
- 负责模块：Anniversary Reminder/Occurrence 的 Contract、Flutter/Dart、Kotlin/Android、C++ Application/Storage、设备测试隔离和状态文档。
- 任务目标：逐项复核 2026-08-25 白盒审查的 4 个 P1、4 个 P2；确认真实问题后以总计划、机器 Contract 和领域不变量为准修正，保护现有跨层实现与用户数据。
- 任务结果：8 项 finding 均确认真实并完成修正。Storage v3 在 committed marker 后的 cleanup/compaction 失败不再谎报未保存，重放保持 after-image 与 generation 幂等；Occurrence cursor 原子绑定 Anniversary/Recurrence/Template 的真实 Store generation。时区恢复在同一 C++ 事务内按当前 IANA timezone 重投影所有 open Anniversary Reminder，保留 occurrence/template identity 并使旧 `expected_remind_at` Alarm 失效。Update 全链新增必填 `expected_updated_at`、稳定 `ANNIVERSARY_UPDATE_CONFLICT`、事务内零写入 CAS 与同秒新 token，并覆盖双线程 barrier 竞争。普通 Anniversary tap 强制 `route = anniversary.detail`。Android Debug/integration 默认使用 `.device_test` application ID 与独立 Store，Application 首个业务副作用前校验包名和目录，Release/Profile integration target 在 Gradle 配置期拒绝；Scheduler 的实际 exact/approximate 结果已类型化贯通至 Anniversary capability。identity、Contracts README、status、roadmap、open issue、计划、架构概览和 Anniversary 领域文档已统一为 Storage v3 `integrated + active`、Anniversary R1 `integrated + release blocked`。另修复 Anniversary C++ 测试中引用临时 NativeResult 导致的非确定性悬空引用。
- 验证状态：Contract validator 通过（162 schemas、55 fixtures、16 identity vectors）；Flutter `analyze` 通过，238 项测试全部通过；Android JVM 141 项通过、1 项既有 skip，`lintDebug`、Debug APK、androidTest APK 与 integration Debug target 构建通过，APK/target package 均核验为 `.device_test`，Release integration target 按预期在配置期失败；C++ 按规定重新配置并执行构建后 `excellent_calendar_check`，7/7 通过，Anniversary 套件额外连续运行 10 次通过；`git diff --check` 无空白错误，仅既有 LF/CRLF 提示。realme Android 13 上隔离 APK 安装被 ColorOS 人工确认界面阻塞后安全中止，未卸载/清除正式包、未修改权限；剩余聚合补发、时区切换、exact/inexact、陈旧 Alarm 和重启/离线真机矩阵仍为 **未验证**，因此发布状态继续 blocked。
- 开发时间：2026-08-25 13:22 +08:00（Asia/Shanghai）。

## 2026-08-25 13:43 +08:00 纪念日 Reminder/Occurrence 修正复审

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：Anniversary Reminder/Occurrence 八项审查修正、跨层 Contract、C++ 并发与 cursor、Android 设备测试隔离及状态文档。
- 任务目标：独立核验总工程师报告的八项修正是否真实闭环，并检查修正过程是否引入新的代码、Contract 或架构问题；不修改生产实现。
- 任务结果：原 Storage post-commit、时区重投影、tap route、实际 exact/approximate 结果和设备隔离修正已确认闭环；复审仍判定为 `CHANGES REQUIRED`。发现 `set_reminders_enabled` 在同秒内复用或回退 Anniversary `updated_at`，使关闭提醒前的陈旧编辑仍能通过 `expected_updated_at` 并覆盖完整 Reminder plan；Occurrence cursor 改用 `1.2.3` Store generation 后，生成值不符合 Schema/Kotlin/Dart 共同冻结的无点号正则，导致多页生产链在第一页响应校验处失败；`contracts/README.md` 开头仍保留“v2 active、v3 blocked”的旧描述，与同文件及机器状态冲突。
- 验证状态：Contract validator 162 schemas/55 fixtures/16 identity vectors通过；构建后 C++ `excellent_calendar_check` 7/7 通过，Anniversary 套件连续 10/10 通过；Flutter 238 项测试和 `flutter analyze` 通过；Android JVM 141 项通过、1 项 skip，lint、Debug APK、androidTest APK 通过；integration Debug APK 构建并核验 application id 为 `.device_test`，Release integration dry-run 在 Gradle 配置期按预期拒绝；`git diff --check` 通过。独立临时 C++ oracle 复现陈旧编辑覆盖提醒开关，独立 Schema oracle 证明实际 generation cursor 被当前正则拒绝；临时文件均已删除。未执行真机安装或剩余物理设备矩阵。
- 开发时间：2026-08-25 13:43 +08:00（Asia/Shanghai）。

## 2026-08-25 14:48 +08:00 纪念日 Reminder/Occurrence 二次复审问题修正

- 使用 Skill：`debug`、`cross-layer-feature`；按 `SPECIALIST_SPLIT` 分别处理 C++ 版本令牌、跨层 cursor 契约回归和 Contract 状态文档。
- 负责模块：Anniversary C++ workflow 与 occurrence cursor、Kotlin/Dart cursor validator/DTO 回归、`contracts/README.md` Storage 状态说明。
- 任务目标：复核并修正提醒开关复用 `updated_at`、generation cursor 不符合冻结 grammar、根 Contract README 同时宣称 Storage v2/v3 active 状态的三项复审 finding，且不破坏既有 Storage v3 与跨层生产链。
- 任务结果：三项 finding 均确认真实。Anniversary update/toggle/delete 的当前事实变更统一使用严格单调的逻辑版本令牌；同秒 create→toggle、update→toggle 和真实 toggle/update 竞争均不会再让陈旧完整 Reminder plan 通过 CAS，冲突稳定返回 `ANNIVERSARY_UPDATE_CONFLICT` 且零写入。Occurrence snapshot generation 从 `1.2.3` 改为 grammar 允许且无歧义的 `1-2-3`；C++ 固定真实输入生成精确 cursor golden 并原样完成第二页查询，Kotlin 与 Dart 使用同一 golden 覆盖 response→next request，完整旧点号形状作为负例。根 Contract README 已统一为 Storage v3 `integrated + active`，v2 仅为 migration source/downgrade guard，Category 当前 Store 说明同步为 v3。
- 验证状态：Contract validator 通过（162 schemas、55 fixtures、16 identity vectors）；C++ 按规定执行构建后 `excellent_calendar_check`，7/7 通过，Anniversary 套件并发回归额外连续运行 10/10 通过；Flutter `analyze` 无问题、240 项测试全部通过；Android JVM 143 项、0 failure、0 error、1 skip，`lintDebug` 通过；目标文件 `git diff --check` 无空白错误，仅既有 LF/CRLF 提示。本轮不涉及系统调度行为变更，未重复执行真机矩阵，Anniversary R1 发布状态继续 blocked。
- 开发时间：2026-08-25 14:48 +08:00（Asia/Shanghai）。

## 2026-08-25 17:49 +08:00 纪念日发布文档与设备验收令牌修正

- 使用 Skill：`debug`、`cross-layer-feature`；按 `SPECIALIST_SPLIT` 分别处理发布文档一致性与 Flutter 设备验收脚本。
- 负责模块：`docs/plan/active/纪念日-06-CPP开发.md`、`docs/status/current.md`、`flutter_client/integration_test/anniversary_release_acceptance_test.dart`。
- 任务目标：复核并修正 C++ 计划 Completed 状态与未勾选清单/Storage v3 旧交付说明冲突、Android Lint 旧统计，以及设备验收在两次 Reminder toggle 后仍复用 create `updated_at` 的问题。
- 任务结果：两项 P2 均确认真实。C++ 计划完成清单已全部闭环，交付总结同步 Storage v3 严格读写、v2→v3 migration、统一事务协调器、generation/CAS、Runtime v3 启动与最终 7/7 C++ 门禁，并保留 Anniversary R1 完整真机矩阵的 release blocked 边界。当前状态文档改为强制重跑所得 `0 errors / 37 warnings`，Lint 已无 error 级阻断，API 24–25 仍需真实设备矩阵。设备验收先以 create token 明确断言 `ANNIVERSARY_UPDATE_CONFLICT`，通过 detail/list 双读证明零写入，再使用 `disabled.anniversary.updatedAt` 完成正常更新；生产 Detail/Form Controller 已正确消费 toggle 返回的新 detail，未修改生产代码。
- 验证状态：设备验收 Dart 文件格式检查通过；`flutter analyze` 无问题，Flutter 240 项测试全部通过；integration target 成功构建 Debug APK，并核验 application id 为 `com.excellentcalendar.excellent_calendar.device_test`；Android `:app:lintDebug --rerun-tasks` 成功，XML report 独立解析为 0 errors / 37 warnings；目标文件 whitespace 检查通过。未安装或操作真机，因此修正后的真实 Flutter→Kotlin→JNI→C++→Storage 设备流程仍为 **未验证**；本轮未修改 C++，未重复运行 C++ 门禁。
- 开发时间：2026-08-25 17:49 +08:00（Asia/Shanghai）。

## 2026-08-25 15:59 +08:00 纪念日 Reminder/Occurrence 三项修正复审

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：Anniversary C++ 乐观并发版本令牌与 occurrence cursor、Kotlin/Dart cursor Contract 回归、Contract Storage 状态文档。
- 任务目标：依据实际 dirty worktree 独立复核总工程师报告的三项修正，确认旧问题是否闭环并检查修正是否引入新的代码、Contract 或架构问题；不修改生产实现。
- 任务结果：三项修正均真实闭环，未发现误报或新的可执行 finding。update/toggle/delete 已统一通过旧令牌与当前时钟计算严格单调的 Anniversary `updated_at`，update 的 `expected_updated_at` 比较仍位于同一 Store 事务内，陈旧完整 Reminder plan 返回 `ANNIVERSARY_UPDATE_CONFLICT` 且零写入；Occurrence generation 使用 Contract grammar 允许的 `1-2-3` 形状，C++ 真实 generation golden 可原样通过 Kotlin response/request validator 与 Dart response/request DTO；根 Contract README、Anniversary README 和机器 Storage Contract 一致声明 Storage v3 `integrated + active`、v2 仅作为 migration source/downgrade guard。Anniversary R1 继续保持 `integrated + release blocked`。
- 验证状态：Contract validator 通过（162 schemas、55 fixtures、16 identity vectors）；C++ 按规定重新配置、重新构建并执行 `excellent_calendar_check`，7/7 通过，Anniversary 套件额外连续 10/10 通过；Flutter `analyze` 无问题、240/240 测试通过；Android JVM 全量强制重跑为 143 tests、0 failure、0 error、1 skip，新增 cursor suite 2/2 通过，`lintDebug` 通过；`git diff --check` 退出码 0，仅既有 LF/CRLF 提示。未安装应用、未访问或修改真机数据，也未执行仍待完成的聚合补发、真实时区切换、exact/inexact、陈旧 Alarm、重启/离线物理设备矩阵。
- 开发时间：2026-08-25 15:59 +08:00（Asia/Shanghai）。

## 2026-08-25 16:46 +08:00 纪念日 Reminder/Occurrence 发布黑盒复审

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：Anniversary Reminder/Occurrence 的 Contract、C++ Core/Storage v3、Flutter、Kotlin/JNI、Android Alarm/Notification、发布门禁与状态文档。
- 任务目标：以产品经理和发布经理视角，对当前完整 dirty worktree 执行独立黑盒与发布复审；仅在全部门禁通过时解除 Anniversary R1 的发布阻塞，不修改生产实现。
- 任务结果：结论为 **BLOCKED / 不可定位发布版本**。真机正常到点链路已首次实际通过：隔离 `.device_test` 包在 realme RMX3687 Android 13 上创建年度纪念日、写入 Storage v3、登记精确 Alarm、结束进程后由系统唤醒，产生一个 Notification，Reminder/Notification 共享 delivery identity，年度 successor 唯一生成，tap payload 与重复点击去重通过。但黑盒证据同时确认，Alarm 准时触发后先进入 Recovery，最终持久化为 `kind=anniversary_catch_up`，正文为“你有 1 条纪念日提醒待查看”，未满足计划冻结的当天“今天是……”/提前“距离……还有 N 天”正常通知语义。Flutter 设备验收还因在两次提醒开关更新后复用 create 的旧 `expected_updated_at` 而稳定失败；这是验收脚本令牌使用错误，产品详情 Controller 已使用最新 detail，但当前发布门禁仍无法绿色通过。工作树仍含 180 个未提交路径（143 tracked unstaged、37 untracked），无法形成可复现发布 SHA；同 occurrence 多提醒聚合、日末补发边界、exact 拒绝近似降级、权限拒绝后恢复、时区/DST 与旧 Alarm、改期/暂停/删除陈旧 Alarm、重启/长离线、真实详情页面点击仍未完成物理设备矩阵。Contract 的 Anniversary 新能力保持 `integrated + release_status: blocked`，未解除 `OPEN-ANN-001`。
- 验证状态：Contract validator 通过（162 schemas、55 fixtures、16 identity vectors）；C++ 按规定配置并执行构建后 `excellent_calendar_check`，7/7 通过；Flutter 240/240 测试与 `flutter analyze` 通过；Android `testDebugUnitTest lintDebug --rerun-tasks` 成功，Debug APK、Release APK、androidTest APK 构建成功；独立 `test_environment/flutter_native_smoke` test/analyze/Debug APK 通过；APK 含 arm64/armeabi-v7a/x86_64 `libexcellent_calendar_native.so` 且 Anniversary/Reminder JNI symbols 可见；`git diff --check` 通过。`connectedDebugAndroidTest` 首次因 Maven TLS 下载失败，随后使用本地隔离 APK 手动安装并执行 instrumentation；JNI create/update/detail/toggle/occurrence/recovery/finalize smoke 通过。Flutter 全链设备验收在 stale `expected_updated_at` 处失败；其前置 create/detail/toggle/occurrence 已通过。未执行上述剩余真机矩阵，发布阻塞保留。
- 开发时间：2026-08-25 16:46 +08:00（Asia/Shanghai）。

## 2026-08-25 18:25 +08:00 准时 Anniversary Alarm 被 Recovery 误归类修正

- 使用 Skill：`debug`、`cross-layer-feature`。
- 负责模块：Android Dispatcher Alarm/Reminder V2 协调、C++ 普通 Anniversary Notification 文案、Kotlin/C++ 回归测试。
- 任务目标：复核并修正真机准时 Alarm 在系统晚 2 秒唤醒时先被 Recovery 消费为 `anniversary_catch_up` 的 P1；确保 Alarm 冻结的 `planned_at` 进入权威 C++ 查询，匹配任务优先走普通投递，更早遗留任务随后进入 Recovery，且普通 Notification 使用冻结产品文案。
- 任务结果：finding 确认真实。Dispatcher PendingIntent 原已携带 `planned_at`，但 Receiver 仅记录日志，V2 Coordinator 在任何 due delivery 前先执行 Recovery。现由 Receiver 将 dispatcher `planned_at` 传给内部协调入口；Coordinator 先用现有 `list_schedulable_reminders` 对 `from_at=to_at=planned_at` 查询 C++ 权威 Store，并以现有 `expected_remind_at` prepare CAS 普通投递，成功后再执行 Recovery。陈旧 Alarm 无匹配项时不会普通投递；普通投递发生可重试失败时本轮不进入 Recovery，而是安排 continuation，避免同一任务立即被重新归类为补发。C++ 普通 Anniversary prepare 根据当前标题与 `advance_days` 生成 `kind=reminder` 的“今天是“{title}””或“距离“{title}”还有 N 天”，不改变 Event Reminder 自定义 message 语义。未变更公开 Contract。
- 验证状态：固定 13:38:00 计划、13:38:02 执行的 Kotlin 回归验证普通投递先于 Recovery、精确查询边界原样下传；另覆盖普通投递可重试失败不落入 Recovery。C++ 回归验证当天与提前 7 天 Notification 均为 `kind=reminder` 且正文精确匹配计划。C++ 按规定重新配置并执行构建后 `excellent_calendar_check`，7/7 通过；Android JVM 全量 145 tests、0 failure、0 error、1 skip，`lintDebug` 为 0 error / 37 warning，Debug APK 与 androidTest APK 构建成功；目标文件 `git diff --check` 无空白错误，仅既有 LF/CRLF 提示。随后仅覆盖安装隔离 `.device_test` 包到 realme RMX3687 Android 13：创建计划于设备本地 15:27:00 的精确 Alarm，测试进程退出后由系统于 15:27:02.498 重新唤醒并展示“今天是“{title}””；真机验收同时确认持久化 `kind=reminder`、正文一致、原 Reminder 转 sent、年度 successor 唯一生成、Notification/Reminder delivery identity 一致，以及 tap payload 和重复点击去重通过，测试数据与通知已清理，正式包及其数据未操作。此 P1 的物理到点链路已验证；Anniversary R1 的其余发布矩阵仍保持原有 blocked 状态。
- 开发时间：2026-08-25 18:25 +08:00（Asia/Shanghai）。

## 2026-08-25 20:11 +08:00 Anniversary Reminder R1 发布放行

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Anniversary Reminder/Occurrence 发布 Contract、identity capability、发布验证器、计划/评审归档、状态/路线图与问题登记。
- 任务目标：独立复核准时 Alarm 误归类、C++/状态文档和旧并发令牌设备验收三项修正；确认闭环后按产品负责人明确授权解除 Anniversary R1 发布门禁，同时保留未覆盖设备矩阵的真实风险边界。
- 任务结果：三项修正均确认闭环，未发现新的 P0/P1/P2 可执行 finding。八项 Anniversary MethodChannel/native call 与 `anniversary_reminder_r1` identity capability 统一切换为 `implementation_status: integrated`、`release_status: active`；Contract validator 同步要求 active。`OPEN-ANN-001`、过期的 Android Lint error 阻断和设备测试隔离风险归档为 RES-ANN-005、RES-AND-001、RES-ANN-006；纪念日五份计划移入 `docs/plan/completed/`，白盒评审移入 `docs/reviews/archive/`。测试隔离、安全 guard、权限校验、CAS、Storage 严格校验和数据保护均保留；“解除限制”只作用于 Anniversary R1 发布门禁。API 24–25、更多 ROM、聚合补发、权限恢复、时区/DST、旧 Alarm、重启与长离线仍明确记录为产品负责人接受但未验证的发布残余风险。
- 验证状态：发布状态切换前后 Contract validator 均通过（162 schemas、55 fixtures、16 identity vectors）；C++ 构建后 `excellent_calendar_check` 7/7；Flutter 240/240 且 analyze 无问题；Android JVM 145 tests、0 failure、0 error、1 skip，Lint XML 0 errors / 37 warnings，Debug 与 androidTest APK 构建成功；realme RMX3687 / Android 13 上重新执行 `anniversary_release_acceptance_test.dart` 通过，确认旧 create token 冲突、detail/list 零写入与最新 token 正常更新；`test_environment/flutter_native_smoke` test/analyze/Debug APK 通过；Release APK 构建成功（60.6 MB）；`git diff --check` 无空白错误，仅既有 LF/CRLF 提示。正常到点 Alarm 使用同日 15:27 已保存真机证据；本轮尝试重装 `.device_test` 复验时因 realme USB 安装确认超时未再次执行，不将其计为新的通过记录。正式应用及其数据未被操作，未执行剩余设备矩阵。
- 开发时间：2026-08-25 20:11 +08:00（Asia/Shanghai）。
## 2026-08-15 18:34 +08:00 云后端版本基线与真实数据库测试闭环

- 使用 Skill：`backend-api-development`、`debug`。
- 负责模块：`cloud_backend/` 的 Java/Spring/Maven/PostgreSQL/Testcontainers 基线、Hikari 数据源配置、容器开发环境，以及 `docs/version.md` 版本清单。
- 任务目标：选择并落地适合后续开发的后端框架、中间件和 Java 版本，补齐本地容器环境，确保现有后端测试能够真实运行，并记录已安装、锁定和 BOM 解析版本。
- 任务结果：保留 Java 21 LTS、Spring Boot 4.1.0、Spring Modulith 2.1.0、Maven 3.9.16 的兼容组合；安装 Docker Desktop 4.86.0（Engine 29.7.2、Compose 5.3.1）并补齐用户 PATH；将 PostgreSQL 固定为 17.11-alpine；修复 Hikari `connection-timeout`/`validation-timeout` 使用 Duration 字符串导致 Spring Boot 4.1 无法绑定 `long` 的根因，并增加配置回归测试。未提前引入无真实用例的 Redis、MQ 或对象存储。
- 验证状态：配置定向测试 3/3 通过；`mvnw test` 修复前 15/15 通过；最终 `mvnw verify` 的 16 个单元/架构/Web 测试与 2 个真实 PostgreSQL 17.11 集成测试全部通过，0 失败、0 跳过。Dockerfile 首次镜像构建在 Temurin 基础层下载后因 Docker Desktop 后台 EOF/首次启动异常未完成，需 Windows 重启后重跑；不影响已完成的 Maven 与 Testcontainers 验证。
- 开发时间：2026-08-15 18:15–18:34（Asia/Shanghai）。

## 2026-08-16 12:00 +08:00 认证与个人信息后端（CloudBackend）阶段 0–5 完成

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（identity、userdevice、media、platform），计划文档
  `docs/plan/active/认证与个人信息-01-后端CloudBackend.md`。
- 任务目标：实现 `contracts/backend_api.yaml` 已声明的 16 个认证/个人信息端点，完成
  V1–V3 Flyway Migration、三模块四层架构、HS256 JWT、Argon2id、Refresh Token 原子轮换、
  邮箱 Challenge、幂等键、内存限流、本地磁盘头像，并通过单元与 Testcontainers 集成测试。
- 任务结果：16 端点全部落地（`auth.registration.email.update` 经用户确认推迟，Contract 未
  声明）；技术选型冻结为 ADR-0004，联调说明写入 `cloud_backend/docs/auth-development-guide.md`；
  新增依赖 oauth2-jose（BOM 管理）、bcprov-jdk18on 1.80、webp-imageio 0.1.6（JNI）。
- 验证状态：`.\mvnw.cmd test` 54/54 通过；`.\mvnw.cmd verify` **BUILD SUCCESS**，37 个
  PostgreSQL 17.11 Testcontainers HTTP 端到端测试 0 失败 0 跳过（并发 refresh 单胜者、Token
  family 重放撤销、会话撤销矩阵、未知邮箱隐私、5 次错误码作废、头像 PNG/WebP/ETag、幂等
  重放、限流 429 等）。协议缺口（email.update 缺失、attempts-exceeded 错误码缺失、头像下载
  路径未声明）已按用户决策处理并记录于 ADR-0004 §1。生产 SMTP/对象存储/JWT 密钥轮换未验证。
- 开发时间：2026-08-15 22:00–2026-08-16 12:00（Asia/Shanghai）。

## 2026-08-17 19:00 +08:00 认证与个人信息后端（CloudBackend）独立评审

- 使用 Skill：`review-worktree-architecture`；另派 4 个并行审查子代理（identity 协议/领域、userdevice+media+头像、platform/安全/幂等/迁移、测试质量审计）并独立复读全部契约与核心服务。
- 负责模块：`cloud_backend/`（identity、userdevice、media、platform）相对 `HEAD` 的全部未提交增量；只读评审，未修改任何代码。
- 任务目标：按 `docs/reviews/active/认证与个人信息-01-后端CloudBackend-review计划.md` 逐项核验协议事实、完成度、测试真实性与架构边界，输出 4 项裁决。
- 任务结果：启动 Docker Desktop 后独立复现 `.\mvnw.cmd verify`：54 个单元/架构/Web 测试 + 37 个 Testcontainers 集成测试，0 失败、0 跳过，BUILD SUCCESS，与完成报告数字一致；契约裁定为 16 端点（`auth.registration.email.update` 从未存在于任何提交，推迟成立），评审计划事实基线的 17 端点/26 错误码/`http_conventions` 等条目与实际契约不符。发现 P1×3（multipart 上限未配置致头像实际限 1 MiB、`ConsoleMailSender` 无 Profile 门控致生产日志含验证码、`auth.logout_all` 多发契约清单外的 `AUTH_ACCOUNT_DISABLED`），P2 若干（幂等 TTL 存而不用、用户名并发竞态返回 500、内存限流无惰性清理、404/405 绕过信封等），另有测试覆盖缺口（`AUTH_ACCOUNT_DISABLED` 零覆盖、幂等重放未做字节级断言等）。
- 验证状态：`mvnw verify` 已复现；全部代码级证据附 file:line；multipart 1 MiB 阈值与并发竞态 500 路径未做运行时复现（标记未验证）；工作区初始与结束状态一致（59 项），临时产物已清理。

## 2026-08-17 20:30 +08:00 P1 评审问题修复（multipart 上限 / 邮件 Profile 门控 / logout_all 越清单错误码）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（application.yml、identity/infrastructure、identity/infrastructure/security、测试）。
- 任务目标：对评审报告的 P1×3 逐项证据级研判（存在性确认），真实存在则给出最小修复并用回归测试锁定。
- 任务结果：三项全部确认存在并修复——P1-1 `spring.servlet.multipart.max-file-size/max-request-size: 6MB`（护栏高于契约 5 MiB，精确上限由处理器执行；6MB 而非 5MB 的原因：5MB=5,000,000B 小于 5 MiB=5,242,880B，恰好 5 MiB 的文件仍会被误拒）；P1-2 `MailConfiguration` 按 Profile 二选一（dev/local 控制台收件箱，其余 Profile `UnconfiguredMailSender` 只输出不含验证码/收件人的 WARN）；P1-3 共享解析器对禁用账号改发 `AUTH_SESSION_EXPIRED`（8 个 bearer 端点全部声明该码，login/refresh 仍自行发 `AUTH_ACCOUNT_DISABLED`）。ADR-0004 §6 与联调说明同步更新。
- 验证状态：`.\mvnw.cmd test` 57/57 通过（新增 MailConfigurationTest 3 用例）；`.\mvnw.cmd verify` **BUILD SUCCESS**，39 个 Testcontainers 集成测试 0 失败 0 跳过，其中新增 `AvatarIT.imagesBetweenOneAndFiveMiBAreAccepted`（>1 MiB 噪声 PNG 真实上传 200，运行时证明原 1 MiB 误拒已消除）与 `DisabledAccountIT`（禁用后 logout_all/get_current → 401 `AUTH_SESSION_EXPIRED`、refresh → 403 `AUTH_ACCOUNT_DISABLED`，全部落在契约清单内）。
- 开发时间：2026-08-17 20:00–20:30（Asia/Shanghai）。

## 2026-08-17 21:30 +08:00 P2 评审研判与修复（后端 ×5 修复 / 前端 ×7 证据级裁定）

- 使用 Skill：`backend-api-development`（后端修复）；前端七项为只读研判，未修改 `flutter_client/**`。
- 负责模块：`cloud_backend/`（platform/idempotency、userdevice/application、identity/infrastructure、platform/security、docs/decisions/0004、implementation-status）；只读核验 `flutter_client/**`、`contracts/auth/**`。
- 任务目标：对评审报告 P2 逐项做证据级研判：真实存在则最小修复 + 回归测试，不存在则给出事实依据。
- 任务结果（后端，全部确认存在并修复）：P2-1 幂等 TTL 未被读取路径使用、崩溃 claim 永久卡死 key → claim 改 `ON CONFLICT … WHERE expires_at <= now` 原子接管过期行并清空旧响应，读取只命中未过期行，附限量清理 `deleteExpiredBatch(now, 100)`；P2-2 用户名唯一约束提交时 flush 才暴露、并发竞态 500 → `saveAndFlush` + `DataIntegrityViolationException` 映射 `AUTH_USERNAME_ALREADY_EXISTS`(409)；P2-3 `InMemoryRateLimiter` 从不清理过期窗口（key 无限增长）→ 每 128 次操作或 >4096 条目扫掠；P2-4 404/405 返回框架错误体而非 ApiResult → 判定真实但不可修复（`error_codes.yaml` 无 404/405 码，禁止临时发明），保持最小错误体并新增零泄漏断言；P2-5 非 api Profile 仍要求 JWT 密钥 → `JwtCryptoConfiguration` 加 `@Profile("api")` 且 `@EnableConfigurationProperties(JwtProperties.class)`。ADR-0004 §7/§8 与 `implementation-status.md` 同步更新。
- 任务结果（前端，逐项事实核验）：评审引用的 `dio_backend_api_client.dart`、`profile_page.dart`、`forgot_password_page.dart`、`reset_password_page.dart`、`register_page.dart`、`auth_route_arguments.dart`、`store_refresh_token_request_dto.dart`、`KeystoreRefreshTokenSecureStore.kt` 及 `SessionEnded`/`SecureTokenStoreException` 等符号在当前工作树**均不存在**（flutter_client 无 dio/http 依赖、无任何后端 HTTP 客户端；`contracts/auth/store_refresh_token_request.schema.json` 处于 planned、无实现）。7 项中 6 项判定不存在（含"dart format 32 文件"经实测 `dart format --output=none --set-exit-if-changed lib test integration_test` 为 225 文件 0 变更）；唯一存在的同类模式是 `flutter_client/android/.../CalendarCoreV2RuntimeDirectories.kt:71-76` 的 TZDB "先删后 rename"，与 Keystore 无关且自愈（下次 extract 重建），仅作为可选改进建议移交前端工程师。
- 验证状态：`.\mvnw.cmd test` **64/64 通过**（新增 IdempotencyEdgeIT 3、DefaultProfileServiceUsernameRaceTest 2、InMemoryRateLimiterEvictionTest 1、JwtCryptoProfileTest 3、ApiInfrastructureContextTest +1）；`.\mvnw.cmd verify` **BUILD SUCCESS**（42 个 Testcontainers 集成测试 0 失败 0 跳过）；`git diff --check` 干净（修掉 cloud_backend/README.md 结尾多余空行）。
- 开发时间：2026-08-17 20:50–21:30（Asia/Shanghai）。

## 2026-08-18 11:30 +08:00 P3 评审研判与修复（头像/媒体、identity 细节、profile、配置文档、测试质量）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（media：EXIF/解码上限/ETag/404；identity：resend 禁用分支、deleted→AUTH_ACCOUNT_DISABLED、验证码不烧毁、TimingEqualizer、改当前邮箱、并发申请重试、logout performed；userdevice：PATCH 空体/null、码点长度、IANA 时区、空数组；配置文档：compose secret、package-info、README 导航段、MaxUploadSize 映射收窄；测试）。
- 任务目标：对 P3 × 25 项逐项证据级研判：真实存在则最小修复 + 回归测试；不存在则给出事实依据。
- 任务结果：**确认存在并修复 20 项**——M1 手机竖拍 EXIF Orientation 被忽略（新增 `JpegExifOrientation` 归一化 1–8 号方向）；M2 解码无尺寸上限可 OOM（头尺寸 >2.5 亿像素判 413、>4096 边长子采样、OOM/插件异常包装为 500）；M3 非 UUID assetId 因 catch-all 变 500（改 String 解析，无效 → 404）；M4 If-None-Match 用 String.contains（改 RFC 9110 列表/通配/弱标签匹配）；M8 注释 NightMonkeys→sejda；I1 resend 缺禁用分支（补 403 + 不发信）；I2 refresh deleted 账号错误映射（改 AUTH_ACCOUNT_DISABLED，对齐 ADR §3）；I3 验证码先消费后校验（confirmReset 先验密码策略、confirmChange 先验邮箱占用，verifyCode 最后）；I4 reset 未知邮箱无时序均衡（新增 `TimingEqualizer` 与 login 共用）；I5 改回当前邮箱误导性 ALREADY_EXISTS（改 API_VALIDATION_FAILED + field new_email）；I6 并发 email_change.request 可 500（`PendingEmailChangeRequestPersister`：REQUIRES_NEW + saveAndFlush + 命中部分唯一索引重试一次）；I8 logout 对无效 token 返回 performed:true（返回是否真的撤销）；P1 空体 {} / 显式 null 被接受（控制器按 JsonNode 做协议校验：minProperties:1 + 显式 null 拒绝，随后 Bean Validation 手动校验）；P2 display_name UTF-16 计数（新增 @CodePointLength）；P3 ZoneId.of 接受 +08:00 等偏移（新增 `IanaTimezones`，UTC/GMT 归一化为 Etc/*，偏移被拒）；P4 `[]` 被 @Size(min=1) 误拒（去掉 min=1）；C1 compose 未传 JWT secret（`${...:?...}` 明确报错 + .env.example + README）；C2 package-info 仍写 Planned；C3 README "进一步阅读"导航段被误删（恢复）；C4 MaxUploadSizeExceeded 全局映射收窄到头像路径；T2/T3/T4/T6/T7/T8/T9/T10 测试质量问题 7 修。**判定不存在/不修 5 项**——M5 孤儿扫描（ADR 未声称，可选）；M6 非流式（几十 KB 影响极低）；M7 no-cache（ETag 重校验语义正确，风格偏好）；T1 AUTH_ACCOUNT_DISABLED 零覆盖（评审基于旧树，DisabledAccountIT 已覆盖）；T5 部分成立（mock 服务是基础设施测试合理边界，login 断言已改为证明到达控制器）。**判定真实但修复点在只读范围 1 项**——I7 黑名单 27 条弱于 `docs/domains/password_credential.md` "已泄露密码"措辞（ADR 已如实记录，扩充黑名单属决策问题）。
- 验证状态：`.\mvnw.cmd test` **83/83 通过**（本轮新增 AvatarImageProcessorTest 8、IfNoneMatchTest 6、PendingEmailChangeRequestPersisterTest 2、PasswordServiceTimingEqualizationTest 2、InMemoryRateLimiterTest 重写、Argon2PasswordHasherTest +1、ApiInfrastructureContextTest 收紧，IT 侧新增 AuthFlowIT +3、PasswordFlowIT +1、EmailChangeIT +2、DisabledAccountIT +2、ProfileUpdateIT +4、AvatarIT +2）；`.\mvnw.cmd verify` **BUILD SUCCESS**（56 个 Testcontainers 集成测试 0 失败 0 跳过）。ADR-0004 §3/§5/§6/§9 与 `implementation-status.md` 同步更新。
- 开发时间：2026-08-17 21:30–2026-08-18 11:30（Asia/Shanghai）。

## 2026-08-19 修复后第二轮独立实证核验（P1/P2/P3 修复验证）

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：`cloud_backend/` 修复增量（修复者针对上轮评审 P1×3、P2×5、P3×25 的整改）的只读核验。
- 任务目标：按「修复前行为 → 修复后代码路径 → 预期结果」逐项检验修复是否真实落地、举措是否合理，不推测、不沿用修复者结论。
- 任务结果：P1 三项全部真实修复且回归测试为真实行为断言（multipart 6MB 护栏使处理器 5MiB 检查重新可达，AvatarIT 用 >1MiB 噪声 PNG 实测 200；MailConfiguration 按 Profile 二选一、ConsoleMailSender 不再作为 @Component 存在，api Profile 验证码不可能进日志；禁用账号解析器改发全端点声明的 AUTH_SESSION_EXPIRED，DisabledAccountIT 覆盖 logout_all/get_current/refresh/resend/deleted 五分支）。P2 五项核验通过（幂等 ON CONFLICT DO UPDATE ... WHERE expires_at<=now 原子接管 + 未过期才重放 + 限量清理，IdempotencyEdgeIT 三用例真实；用户名竞态 saveAndFlush 捕获映射 409；限流器抽样扫掠 + 可动时钟真实驱逐测试；404/405 判定不可修成立并固化零泄漏断言、同时修复旧测试 not(403) 假阳性；JWT 配置 @Profile("api") 门控且三 Profile 上下文断言）。P3 抽查（EXIF/解压炸弹/If-None-Match/时序均衡/Challenge 先验后消费/幂等重试/logout performed/PATCH 空体与 null/IANA 时区/README 恢复/compose secret）均代码级确认。第 3 次 `.\mvnw.cmd verify`：83 单元 + 56 Testcontainers，0 失败 0 跳过，BUILD SUCCESS。
- 验证状态：全量测试独立复现通过；残留低严重度观察 5 条（IanaTimezones javadoc 与代码行为不一致、PATCH 未知字段未按 additionalProperties:false 强制拒绝、幂等崩溃 claim 在 TTL 内仍 500 的固有保守语义、限流器饱和时 O(n) 扫描、ADR 一处措辞不精确）；工作区结束状态 67 项与修复后初始一致，临时产物已清理。

## 2026-08-19 21:10 +08:00 SMTP 邮件发送接入（通用适配器）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（pom.xml；identity/infrastructure：MailSendingProperties、SmtpMailSender、MailConfiguration；application.yml、compose.yaml、.env.example；docs：ADR-0005、decisions/README、configuration、auth-development-guide、implementation-status、README）。
- 任务目标：接入真实 SMTP 发信，使注册/改邮箱/重置密码验证码可投递到手机邮箱；未配置时保持 dev 控制台收件箱 / 无码 WARN 兜底行为不变。
- 任务结果：新增 `spring-boot-starter-mail`（BOM 管版本）与通用 SMTP 适配器，opt-in 于 `excellent-calendar.mail.host`（任何 Profile 可启用，生产 api 亦可用）；`SmtpMailSender` 在 afterCommit 尽力发送，失败仅 WARN（收件人掩码、无验证码、无凭据），正文只含 6 位验证码（ADR-0004），587+STARTTLS（防降级）或 465+SSL、连接/读/写超时 10s，不做自动重试（resend 端点承担重试语义）。`MailConfiguration` 优先级固定为 SMTP > dev/local 控制台收件箱 > 无码兜底；host 已设置而 username/password 缺失时启动快速失败并提示缺失项。新增 ADR-0005，同步 README、联调指南、配置文档与实现状态；`.env.example` 附 QQ/163/Outlook/Gmail 配置示例。
- 验证状态：`.\mvnw.cmd test` **91/91 通过**（新增 SmtpMailSenderTest 4 用例：消息形状/主题/失败不传播/掩码；MailConfigurationTest 增至 8 用例含 SMTP 优先与 fail-fast）；`.\mvnw.cmd verify` BUILD SUCCESS，但本机 Docker Desktop 无法启动，56 个 Testcontainers 集成测试**全部跳过**，数据库行为未在本轮验证；真实 SMTP 供应商投递未用真实邮箱账号实测（**未验证**）。
- 开发时间：2026-08-19 20:30–21:10（Asia/Shanghai）。
## 2026-08-17 +08:00 认证与个人信息——前端本地 Review（按 review 计划执行）

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：`flutter_client/` 认证与个人信息增量（Dart + Kotlin）只读审查；仅追加本日志。
- 任务目标：按 `docs/reviews/active/认证与个人信息-02-前端本地-review计划.md` 重建事实基线、裁定两个跳过切片、复现全部验证命令并完成分层/Token/单飞/状态机/缓存/Keystore/导航审查。
- 任务结果：**CHANGES REQUIRED**。裁定：契约实际仅 16 个端点且不含 `auth.registration.email.update`（git 历史确认），前端报告"协议缺口"结论正确、该切片属合规跳过待排期；review 计划第 1 节"17 端点/envelope_only_errors"两处基线错误（契约中均不存在）。复现：`flutter test` 336/336、`flutter analyze` 0 issue、`flutter build apk --debug` 成功、Kotlin 131 项 0 失败（1 skipped）；**`dart format --set-exit-if-changed` 未通过（32 个增量文件）**，与报告"格式检查通过"矛盾；报告"新增约 60"实测约 131。发现 P1×2（退出/刷新竞态复活会话并以独立黑盒测试复现、刷新成功后新 RT 写回失败被忽略）、P2×7（非 2xx 无信封分类与死代码、presentation 持有下层类型、三 controller 未捕获 SessionEnded/SecureTokenStore、expires_at 整秒重编码过严、格式检查声称不实、Keystore 原子写顺序、测试覆盖缺口含真实 Keystore cipher 零覆盖与敏感日志无断言）、P3×9。分层/Token 主体合规，无 debug 降级假实现。
- 验证状态：上述命令均实测执行并记录退出码；审查临时测试文件已删除，`git status` 与初始清单一致；未修改任何生产代码。真机 Keystore、真实刷新链路与九条端到端仍未验证（报告中如实保留）。
- 开发时间：2026-08-17（Asia/Shanghai）。

## 2026-08-25 21:10 +08:00 HXY-study、HXY-backend、HXY-user 三分支整合

- 使用 Skill：`cross-layer-feature`。
- 负责模块：Git 分支整合，以及 Contract、C++ Core/Storage、Flutter/Dart、Kotlin/Android/JNI、CloudBackend 共同生产入口与回归验证。
- 任务目标：将同一 `HXY` 基线上的 `HXY-study`、`HXY-backend`、`HXY-user` 全部合入 `HXY`；按现有架构处理冲突，保护原有日程、纪念日、提醒、响铃能力，并让认证/个人信息前后端正确接入；`.agents/**` 以 `HXY-study` 为准。
- 任务结果：以 `HXY-study → HXY-backend → HXY-user` 的依赖顺序建立三个独立 merge commit。`docs/log.md` 的并行追加全部保留；`MainActivity`、`NativeMethodChannelHandler`、Dart MethodChannel 常量、`AppRouter`、`main.dart` 与 production composition test 的冲突按功能并集解决，同时注册 Ring runtime/handler 与 Auth Keystore/handler，同时保留响铃宿主/路由和认证启动/页面路由。`.agents/**` 与 `HXY-study` 完全一致。排除了 `HXY-user` 带回的 4 份已归档响铃 active 计划副本及 3 个评审明确要求提交前删除的构建输出。另识别到来源分支间既有语义漂移：当前 Contract/active plan 已声明第 17 个 `auth.registration.email.update`，但合入的后端与前端仍按旧 16 端点实现；未回退机器 Contract，也未在纯合并任务中擅自扩展该独立业务切片，需后续专项补齐。
- 验证状态：Contract validator 通过（162 schemas、55 fixtures、16 identity vectors）；C++ 按规定重新配置并执行构建后 `excellent_calendar_check`，7/7 通过；Flutter 定向组合测试 26/26、全量 387/387、`flutter analyze` 与 Debug APK 构建通过；Android JVM 174 tests、0 failure、0 error、1 既有 skip，`lintDebug` 为 0 errors / 38 warnings；独立 Flutter Native smoke 的 test/analyze/Debug APK 通过。CloudBackend `mvnw verify` 在临时启动 Docker Desktop 后通过：91 项单元/架构测试与 56 项 PostgreSQL 17.11 Testcontainers 集成测试均 0 失败、0 跳过，Docker 随后恢复停止。RMX3687 真机在线，但隔离 smoke APK 安装被 ColorOS USB 安装确认阻塞后中止；已确认 smoke 包不存在，正式应用包路径前后不变，因此真机 UI/JNI 返回值本轮未验证，正式应用及数据未被操作。
- 开发时间：2026-08-25 21:10 +08:00（Asia/Shanghai）。

## 2026-08-27 12:14 +08:00 HXY 合并回归与 Calendar Core SQLite Storage v4

- 使用 Skill：`debug`、`calendar-data-contracts`、`cpp-core-feature`、`android-kotlin-native-feature`；`frontend-flutter-feature` 仅用于核对 Flutter 测试修改边界，未越界修改 `integration_test/**`。
- 负责模块：HXY 合并后全仓库运行基线；`cpp_core/**` 的 Storage adapter、迁移与测试；`contracts/storage/**` 和 runtime version；`flutter_client/android/**` 的 Kotlin/JNI 版本映射与 Debug smoke；相关架构、领域、状态和存储文档。
- 任务目标：先独立验证 HXY 在合入 HXY-user、HXY-backend、HXY-study 后仍可构建和运行，再将 Calendar Core 的正式 writer 从 JSON 升级为 SQLite，完整保留 JSON v1/v2/v3 已支持的数据、顺序、软删除、幂等、恢复、跨 Store 原子工作流和全部 C++ Repository/Transaction ports。
- 任务结果：修改前工作树干净，无未解决 merge entry 或源码冲突标记；C++、Flutter、Android 和 CloudBackend 基线全部通过，未发现三分支合并造成的可复现运行回归。新增 Calendar Core SQLite Storage v4 与八组现有 port adapter，捆绑官方 SQLite 3.53.4；十个现代 Store、Category 和三张 v1 兼容表统一进入 `calendar_core.sqlite3`，使用 WAL、`synchronous=FULL`、`BEGIN IMMEDIATE`、主键/业务唯一约束、调度/排序索引、generation 与严格打开校验。v1 在 journal recovery 后无损导入隔离兼容表；v2 先连续恢复/迁移为 v3；v3 十 Store + Category 在单事务中逐字段导入候选库，经 metadata、required schema object、row identity、冻结 codec/聚合校验和 `quick_check` 后刷盘关闭并原子发布；Windows 使用 write-through rename，POSIX 同步父目录。JSON 记录不删除，迁移后只改 envelope 为 `storage_version=4` downgrade guard，不再双写。混合 v1/现代来源、未知版本、损坏 payload、缺表/缺索引均拒绝发布。`auth.registration.email.update` 经复核在机器 Contract 中明确为 `planned`，前后端未实现是已知非活动能力；CloudBackend 文档中“Contract 未声明”属于合并后的文字漂移，不影响当前 16 个 active 端点运行，本任务未越权实现第 17 个端点。
- 验证状态：修改前基线：C++ build-after-test 7/7、Flutter 387/387 + analyze + Debug APK、Android unit/lint/Debug/androidTest APK、独立 Native smoke 1/1、CloudBackend 91 个 JVM 测试 + 56 个 PostgreSQL 17.11 Testcontainers 集成测试全部通过且 0 跳过。最终状态：Contract validator 通过 162 schemas / 56 fixtures / 16 identity vectors；规定的 C++ 重新配置和 `excellent_calendar_check` 7/7 通过，SQLite v4 定向覆盖精确迁移、v1 保留、重开隔离、全 Store 回滚/重试、约束、损坏/未知版本、缺 schema object 和混合来源拒绝；Flutter 387/387、analyze 零问题；Android `testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest` BUILD SUCCESS，arm64-v8a/armeabi-v7a/x86_64 均重编译；独立 Native smoke test/analyze/Debug APK 通过。realme RMX3687（Android 13/API 33，arm64-v8a）隔离 `.device_test` 上 Anniversary JNI SQLite v4 闭环与 Category 极值零写入 instrumentation 均 PASS，Flutter Anniversary 全链路 integration PASS，logcat 无 AndroidRuntime 崩溃；后续 Category Flutter integration 与 runtime timezone 用例因第二次 ColorOS USB 安装确认未操作而中止，不能计为本轮通过，但对应 Host 回归和原生 Category instrumentation 已通过。隔离目标由 Flutter 工具卸载，残留 test package 已清理，正式应用和正式数据未操作。`git diff --check` 无空白错误（仅仓库既有 LF/CRLF 提示）。
- 开发时间：2026-08-27 12:14 +08:00（Asia/Shanghai）。

## 2026-08-27 12:30 +08:00 真机 Flutter 初始化画面卡住修复

- 使用 Skill：`debug`。
- 负责模块：`flutter_client/android/app/src/debug/AndroidManifest.xml`；realme RMX3687 上的正式包与隔离测试包启动验证。
- 任务目标：复现并修复点击应用后长期停留在 Flutter 初始化画面、无法进入主界面的问题，同时保护正式应用数据。
- 任务结果：分别冷启动同机上的正式包 `com.excellentcalendar.excellent_calendar` 与测试包 `com.excellentcalendar.excellent_calendar.device_test`，确认正式包约 2 秒进入日程主界面且 Native 查询成功；稳定卡住的是前一轮 Flutter integration test 遗留的测试目标 APK。该 APK 将 integration-test Dart 文件打包为入口，脱离 instrumentation 控制器从桌面启动时不会进入产品 UI，同时此前与正式包共用 `excellent_calendar` 桌面名称，造成误认。Debug manifest 现将隔离包明确标为 `Excellent Calendar (测试版)`。用正常 `lib/main.dart` Debug APK 覆盖后，测试包冷启动进入登录页，证明产品入口正常；随后卸载 `.device_test` 和对应 `.test` instrumentation 包，手机只保留正式包。正式包再次冷启动进入“日程”页，既有登录状态保留，未清除、卸载或改写正式包数据。
- 验证状态：`flutter build apk --debug` 通过；APK badging 确认 application id 为 `.device_test`、label 为 `Excellent Calendar (测试版)`；`flutter analyze` 0 issue；`flutter test` 387/387 通过；Gradle `:app:testDebugUnitTest :app:lintDebug` BUILD SUCCESS；真机正常 Debug 入口与正式包冷启动均通过，最终设备包清单仅剩正式包；`git diff --check` 无空白错误（仅既有 LF/CRLF 提示）。
- 开发时间：2026-08-27 12:30 +08:00（Asia/Shanghai）。

## 2026-08-27 12:44 +08:00 Flutter Debug 前端本地测试登录

- 使用 Skill：`frontend-flutter-feature`。
- 负责模块：`flutter_client/lib/application/auth/**` 登录流程与 `flutter_client/test/**` 登录测试。
- 任务目标：提供 `admin@admin.com` / `admin` 前端测试账号，输入后无需后端验证即可进入首页，同时不影响普通账号的真实后端登录。
- 任务结果：新增仅在 Flutter Debug 构建启用的本地测试账号；`LoginController` 命中指定凭证后建立包含测试用户资料的内存会话，跳过 `AuthGateway.login`，不写入 Refresh Token 或用户缓存。Profile/Release 构建中该凭证不匹配，其他凭证继续沿用既有后端认证与 Token 持久化流程。
- 验证状态：定向登录控制器与认证页面测试 20/20 通过；`dart format --output=none --set-exit-if-changed lib test` 通过（356 files，0 changed）；`flutter analyze` 0 issue；`flutter test` 389/389 通过；`flutter build apk --debug` 成功并生成 `build/app/outputs/flutter-apk/app-debug.apk`；`git diff --check` 无空白错误（仅仓库既有 LF/CRLF 提示）。未执行真机手工登录，相关行为由 Controller 与 Widget 测试覆盖。
- 开发时间：2026-08-27 12:44 +08:00（Asia/Shanghai）。

## 2026-08-27 13:28 +08:00 Calendar Core JSON → SQLite v4 独立迁移审查

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Calendar Core Storage v4 的架构边界、机器 Contract、Event/Recurrence/Reminder/Notification/Recovery/Anniversary/Category 领域一致性、JSON v1/v2/v3 迁移、SQLite 运行时与 Android 打包链路；本轮只读审查，除本日志外未修改业务代码。
- 任务目标：确认 JSON → SQLite 迁移是否保持既有分层与 Repository/Transaction ports，是否符合当前 Contract 和领域不变量，能否等价承接原 JSON 功能，并独立检查崩溃一致性、迁移幂等、schema 漂移、来源追踪、约束、顺序、事务与打包等常见风险。
- 任务结果：**CHANGES REQUIRED**。正常路径的分层、十个现代 Store + Category、冻结 codec、顺序/软删除、跨 Store 事务、v1/v2/v3 导入及 Android runtime version 基本一致，未发现 Domain/Application/Flutter/生产 Kotlin 直接依赖 SQLite；但独立进程终止测试复现了数据库原子发布后、JSON downgrade guard 安装前的崩溃窗口，旧 JSON writer 可继续成功写入而 SQLite 不变，形成双真相和静默数据丢失风险。另复现同名但错误定义的必需唯一索引可通过打开校验；确认 v1 与空库也被无条件记录为 `calendar_core_json_v3_to_sqlite_v4`，迁移来源审计失真。工作树同时混入独立的 Debug 本地登录与 Manifest 修复，应拆分提交；`contracts/README.md` 的 active/blocked 状态文字及一个 JSON 文件名注释存在陈旧漂移。
- 验证状态：实测 C++ 规定的 build-after-test 7/7、Contract validator（162 schemas / 56 fixtures / 16 identity vectors）、Flutter 389/389 + analyze + Debug APK、Android JVM test 与 lint 全部通过；`git diff --check` 无空白错误（仅 LF/CRLF 提示）。独立黑盒覆盖数据库发布瞬间强杀及旧 JSON writer 续写、同名错误索引篡改、v1 migration history 查询，前两项分别确认崩溃切换缺陷与 schema 校验缺陷。未在本轮重新执行真机、磁盘耗尽或物理掉电测试；临时审查产物已清理，追加日志前工作树清单与初始审查边界一致。
- 开发时间：2026-08-27 13:28 +08:00（Asia/Shanghai）。

## 2026-08-27 14:47 +08:00 SQLite v4 迁移审查缺陷修复

- 使用 Skill：`debug`、`calendar-data-contracts`、`cpp-core-feature`。
- 负责模块：`cpp_core/**` 的 SQLite cutover、Schema/迁移历史校验与 Storage 回归；`contracts/storage/calendar_core_storage.yaml`、Storage ADR、Contract README 和 Repository 接口注释。
- 任务目标：逐项复核独立 review 报告；修复 JSON→SQLite 发布窗口中的双真相风险、同名错误 Schema 可通过校验、迁移历史失真和相关文档漂移，同时保护工作区已有认证、Debug Manifest 与其他 SQLite 增量。
- 任务结果：确认 P0 与两个 P2 技术 finding 均真实。新增持久化 `calendar_core_sqlite_cutover.json` 前向状态机：候选库先完成完整校验、关闭和刷盘，再捕获全部旧 writer 根；所有现存根和必需入口在数据库发布前原子安装并复核 `storage_version=4`，任一根发生第三种变化即阻止发布；数据库或进程在任一阶段中断后按 journal 幂等续跑。对旧实现已发布但尚未 guard 的数据库，只有严格 JSON writer 仍能读取且内容与对应 SQLite Store 完全一致时才允许补 guard，差异按潜在双真相拒绝；严格 codec 本就拒绝的损坏诊断快照继续不阻塞 SQLite。Schema 打开校验升级为对 16 张表和 16 个索引的规范化完整 `CREATE` 定义比对。`create_schema()` 不再写来源历史，fresh、v1、v2→v3→v4、v3→v4 分别记录真实合法组合，并兼容修复旧实现精确的 v1+伪 v3 组合。同步修正 Storage cutover Contract/ADR、Anniversary active 状态漂移及 storage-neutral Transaction 注释。review 中认证与 Debug Manifest 混入属于提交组织 finding；本轮未回退、改写或提交这些用户已有改动，也未擅自拆 commit。
- 验证状态：Storage 定向测试新增 21 个真实子进程强制终止边界（候选刷盘、journal prepare、每个 JSON guard、guards 状态、数据库发布、journal 清理）、发布后旧 JSON writer 拒写、全部必需表/索引同名错误定义负向测试，以及 fresh/v1/v2/v3 迁移历史组合；定向测试 17/17 通过。按规定重新配置并执行构建后 `excellent_calendar_check`，7/7 通过；Contract validator 通过 162 schemas / 56 fixtures / 16 identity vectors；Flutter Android Debug APK（含 Android/JNI/C++ 重新构建链路）构建成功；`git diff --check` 无空白错误，仅输出工作区既有 LF/CRLF 转换提示。未执行物理断电、磁盘耗尽或本轮真机迁移，不能将真实进程强杀等同于硬件掉电验证。
- 开发时间：2026-08-27 14:47 +08:00（Asia/Shanghai）。

## 2026-08-27 19:32 +08:00 Flutter 注册成功响应纳秒时间解析修复

- 使用 Skill：`debug`、`calendar-data-contracts`。
- 负责模块：Flutter Backend API Contract DTO 时间解析、认证回归与真机 Debug APK。
- 任务目标：定位并修复真实 SMTP 邮件已发送、注册成功后 Flutter 显示“服务器返回了无法识别的响应，请稍后重试”的问题。
- 任务结果：确认后端请求 `ffadcf15-3578-436e-9e82-3e872b7d333a` 返回成功，`EmailChallenge` 中 Java `Instant` 被序列化为 9 位纳秒；该值符合现有 Contract，但 Dart `ContractValue` 只接受 1–6 位小数，首次错误边界位于 Flutter UTC 时间解析器。解析器现接受合法 RFC 3339 UTC 秒小数，并在超过 6 位时截断到 Dart 支持的微秒精度；新增基于真实 9 位响应形状的回归测试。未修改 Contract、后端、Kotlin/C++ 或存储代码。
- 验证状态：新增测试在旧实现上按预期失败，修复后通过；认证定向测试 52/52 通过；`flutter analyze` 无问题；完整 `flutter test` 390/390 通过；Debug APK 使用 `BACKEND_BASE_URL=http://10.227.115.151:8080` 构建成功并覆盖安装到 RMX5100，启动后未发现 Flutter、`FormatException` 或致命崩溃；后端健康状态为 `UP`。真实验证码提交仍需用户在修复版界面完成，未记录或索取验证码。
- 开发时间：2026-08-27 19:32 +08:00（Asia/Shanghai）。

## 2026-08-27 19:55 +08:00 过期注册验证码无法重发修复

- 使用 Skill：`debug`、`cross-layer-feature`、`backend-api-development`、`frontend-flutter-feature`。
- 负责模块：Cloud Backend 注册 Challenge 生命周期；Flutter 邮箱验证 Controller、页面反馈及认证回归；Docker API 与真机 Debug APK。
- 任务目标：修复待验证邮箱因旧验证码过期后无法重新注册，登录进入验证页后点击重发又无法获取新验证码的死路。
- 任务结果：确认账户仍为 `pending_verification`，唯一注册 Challenge 已过期但未消费、未作废；登录查询只过滤 consumed/invalidated，错误复用了过期 Challenge，而重发用例又把 expired 判为不可重发，真实请求因此返回 `AUTH_VERIFICATION_EXPIRED`，形成无法恢复闭环。后端现在只复用未过期 Challenge，登录遇到过期 Challenge 会签发并发送新码；重发允许过期但未消费、未作废的 Challenge 换发新码，同时继续拒绝已使用、已作废和禁用账号。Flutter 重发成功后同步清空旧输入、旧过期错误并显示“新验证码已发送，请查收”。Contract、Schema、Migration、Kotlin/C++ 和本地存储未修改。
- 验证状态：四个新增回归场景在旧实现上分别因 HTTP 400、复用相同 Challenge、残留错误与残留输入失败，修复后通过；Cloud Backend `mvnw verify` 通过（91 个单元/上下文测试、58 个 PostgreSQL 集成测试）；Flutter 认证定向 21/21、完整 `flutter test` 392/392、`flutter analyze` 无问题；Docker API 重建后健康状态 `UP`，PostgreSQL 数据卷保留；使用真实过期 Challenge 重发得到 HTTP 200（request_id `681c84a4-5d18-4fd7-aabe-c0f341e18d7c`），旧 Challenge 已作废、新 Challenge 活跃，SMTP 日志确认邮件发送至 `v***y@outlook.com`。Debug APK 使用 `BACKEND_BASE_URL=http://10.227.115.151:8080` 构建并覆盖安装到 RMX5100，启动无 Flutter/Contract/FormatException 致命错误。真实验证码确认仍需用户在手机端完成，未记录或索取验证码。
- 开发时间：2026-08-27 19:55 +08:00（Asia/Shanghai）。

## 2026-08-27 20:07 +08:00 Habit 模块需求发现与现状盘点

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`。
- 负责模块：Habit/HabitCheckIn 领域、Contract 预留、Reminder 关联、SQLite/C++/Kotlin/Dart/Flutter 现状与未来开发拆分。
- 任务目标：在不直接实施功能的前提下，结合仓库真实状态开展 Habit 产品需求访谈，识别现有模型可复用范围、必要协议缺口、提醒设计门禁、页面与统计方案，并为后续正式开发计划收集决策。
- 任务结果：完成首轮只读盘点。确认 Habit 与 HabitCheckIn 的领域分离、目标数量/单位、起止日期、每日快照及四种打卡状态已有设计与 Schema；但当前只有 `habit.create`、`habit.check_in` 两个公开预留方法，没有 native call、C++ Domain/Repository、SQLite 表、Kotlin/Dart 实现或生产 UI。识别到 Habit 专属 recurrence 尚未冻结、现有 planned recurrence 输入与 date-only 语义需统一，以及普通一次性 Habit Reminder 预留不能直接满足每日重复提醒。任务进入产品决策阶段，尚未形成最终计划或修改功能代码。
- 验证状态：仅执行 `git status`、定向文档/Contract/代码检索与调用链盘点；未修改功能代码，未运行构建或测试。工作区原有大量未提交的 SQLite、认证及文档改动均已保留；本次只追加本日志。
- 开发时间：2026-08-27 20:07 +08:00（Asia/Shanghai）。

## 2026-08-27 20:22 +08:00 Flutter 四项底部主导航接入

- 使用 Skill：`frontend-flutter-feature`。
- 负责模块：`flutter_client/lib/presentation/home/`、Inbox 底部导航组件、个人信息页嵌入模式、`main.dart` 组合根及导航 Widget 测试。
- 任务目标：确认个人信息页现状，并参照用户提供的 QQ 截图将主界面底部横栏调整为“日程 / 日历 / 搜索 / 我的”四项；接入已有个人信息页，未完成的日历与搜索页显示开发中占位。
- 任务结果：确认现有个人信息页已实现并复用其真实 AuthService/ProfileController 数据链路；新增持久主 Tab 容器，底部栏采用图标在上、中文文字在下、选中项品牌色高亮的四等分布局。日程页保留既有功能；日历与搜索切换后显示明确的“板块正在开发中”；“我的”按需首次构建并展示个人信息页，避免进入首页即额外请求资料。直接 `/profile` 路由仍保留返回按钮，嵌入主 Tab 时隐藏返回按钮。未修改 Contract、Native、Backend、依赖或工具链，并保护了工作区已有认证等未提交修改。
- 验证状态：新增主导航 Widget 测试 2/2 通过，主导航 + 个人页定向测试 9/9 通过；`dart format --output=none --set-exit-if-changed lib test` 通过（358 files，0 changed）；`flutter analyze` 无问题；完整 `flutter test` 394/394 通过；`flutter build apk --debug` 成功，产物为 `flutter_client/build/app/outputs/flutter-apk/app-debug.apk`；`git diff --check` 无本次空白错误，仅输出仓库既有 LF/CRLF 转换提示。未执行真机手工点击验收。
- 开发时间：2026-08-27 20:22 +08:00（Asia/Shanghai）。

## 2026-08-27 20:23 +08:00 Habit 首轮产品决策冻结

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn 产品语义、每日规则、打卡与统计口径、提醒及页面入口规划。
- 任务目标：记录用户对首轮 Habit 需求方案的选择，并继续收敛第二轮交互、提醒、生命周期和统计边界。
- 任务结果：用户确认采用固定期限挑战、打卡型与数量型并存、时长换算结束日期、独立 HabitRecurrence、稀疏 CheckIn、有效期内可补签、严格达标统计、每日单提醒、无暂停但可提前结束、到期归档并可再来一轮，以及列表/详情/创建编辑/日期详情页面结构。Habit 不进入底部导航，从今日/日程页顶部进入；底部导航按并行落地后的“日程、日历、搜索、我的”四项作为受保护现状。最终开发计划仍待第二轮产品规则确认。
- 验证状态：仅核对 Habit Schema、领域字段及日程页顶部入口和最新导航现状；未修改功能代码，未运行构建或测试。本次只追加需求发现日志。
- 开发时间：2026-08-27 20:23 +08:00（Asia/Shanghai）。

## 2026-08-27 20:54 +08:00 Habit 第二轮交互与统计决策冻结

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit 卡片交互、数量录入、目标可变性、生命周期、统计公式、提醒恢复和通知快捷打卡规划。
- 任务目标：吸收第二轮产品选择，识别卡片多进度语义、通知快捷完成及全局进度色偏好的剩余决策。
- 任务结果：用户确认 Habit 通过日程页顶部更多菜单进入；首页采用进行中卡片与今日汇总；数量型支持 `+1`、直接输入、两位小数和自定义单位；开始记录后锁定目标与单位；同日撤销、历史编辑、skipped 桥接连续达标、严格统计、自然到期/提前结束区分及核心完整统计均按推荐方案执行。卡片新增左侧剩余数量快捷圆圈、右侧以连续天数为中心的百分比圆环、卡片背景进度填充和剩余挑战天数小字；通知采用同日未完成则补发及 V1 通知栏直接完成；图标使用标题 Emoji，不新增 Habit 图标字段。尚待确认卡片两种进度分别代表什么、数量型通知快捷完成语义、未答复的提醒默认权限策略，以及全局进度色的本地/账号归属。
- 验证状态：仅核对现有用户偏好 Schema 和 Flutter Profile 入口；确认尚无可直接复用的本地 Habit 进度色设置。未修改功能代码，未运行构建或测试；本次只追加需求发现日志。
- 开发时间：2026-08-27 20:54 +08:00（Asia/Shanghai）。

## 2026-08-27 21:09 +08:00 Habit V1 正式开发计划定稿

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn/HabitRecurrence/HabitReminderTemplate 领域与 Contract 规划、SQLite v5、C++ 统计与提醒工作流、Kotlin/JNI、Flutter 页面、本机外观偏好及端到端验收。
- 任务目标：将三轮已确认产品需求整理为可执行、可拆分、可验证的 Habit V1 专业开发计划。
- 任务结果：新增 active 主计划 `docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`，冻结固定期限 daily challenge、打卡型/数量型、补签与目标锁定、严格 streak/rate、卡片时间进度/完成率圆环、同日提醒补发、通知栏快捷完成、本机进度色等语义；给出 HabitRecurrence 与 HabitReminderTemplate 的最小新增边界、必要 `ended_date`、Reminder occurrence identity、幂等事务、Storage v4→v5 migration、12 个公开能力、8 个实施阶段、黑盒矩阵和完成定义。`docs/index.md` 已增加当前 Habit 主计划入口。未修改领域/Contract/功能代码，实际实现必须从 Phase 0 开始按专项拆分。
- 验证状态：计划文件共 626 行，章节结构和清单已检查；对计划、索引和日志执行 `git diff --check`，无空白错误，仅有工作区既有 LF/CRLF 转换提示。未运行代码构建或测试，因为本次交付仅为需求与开发计划；仓库其他未提交修改均保留。
- 开发时间：2026-08-27 21:09 +08:00（Asia/Shanghai）。

## 2026-08-27 20:59 +08:00 Flutter 账号与通知三项刷新回归修复

- 使用 Skill：`debug`、`frontend-flutter-feature`。
- 负责模块：Flutter Auth/Profile 路由、登录失败页面状态、通知启动 Host 与相关 Widget 回归测试。
- 任务目标：修复修改登录邮箱验证成功后的黑屏、启动时通知权限说明框被自动跳转冲掉，以及错误邮箱或密码导致登录页整体重建的问题。
- 任务结果：确认“我的”已改为 `/today` 内的 Tab，但邮箱修改成功仍一直弹栈查找独立 `/profile`，最终弹空根路由；现改为优先返回显式 `/profile`，不存在时安全停在承载“我的”的首路由。确认 Flutter 默认会为初始 `/auth-check` 同时生成底层 `/`，而 `/` 被项目映射为已认证首页，导致通知 Host 提前启动并在鉴权清栈时随弹窗一起移除；现启动只生成单一鉴权路由，并让重建后的通知 Host 主动恢复尚未处理的权限说明。确认 `LoginOutcome.failed` 与 `sessionEnded` 共用了 `goToLogin()`，错误地清栈重建登录页；现失败分支原地保留错误和邮箱、仅清空密码，只有会话结束才重新进入登录页。未修改 Backend、Contract、Kotlin/C++、数据库或依赖版本。
- 验证状态：新增黑屏与登录失败测试在旧实现上分别复现为根页面消失、`goToLogin` 被错误调用，通知 Host 重建测试在旧实现上复现为待处理说明无法恢复；修复后认证导航、登录、通知及路由定向测试通过；`flutter analyze` 无问题；完整 `flutter test` 400/400 通过；`flutter build apk --debug` 成功并覆盖安装到 RMX5100。最终真机冷启动停留登录页，鉴权前未提前启动通知模块，未发现 Flutter/Fatal 异常；测试版当前 `POST_NOTIFICATIONS` 已为 granted。为避免再次修改真实邮箱，未重复执行真实邮箱变更提交，相关成功返回后的导航由真实 Navigator Widget 测试覆盖。
- 开发时间：2026-08-27 20:59 +08:00（Asia/Shanghai）。

## 2026-08-28 00:28 +08:00 HXY-study-before-sync1 文档核对

- 使用 Skill：无（纯 Git 文档核对与分支同步）。
- 负责模块：`docs/**` 分支内容比对、关键 Domain/ADR 冲突识别与 HXY 分支提交。
- 任务目标：将 `backup/HXY-study-before-sync1` 中 HXY 尚不存在的文档提交到 `HXY`；同路径关键领域或决策文件不擅自覆盖，留待用户定夺。
- 任务结果：确认来源分支的 68 个文档路径已全部存在于 HXY，HXY 另有 3 个文档，因此没有来源独有文件需要导入；57 个文件内容完全相同，11 个同路径文件内容不同。来源提交 `5f7ae98` 是 HXY 的祖先，差异来自 HXY 后续提交；其中 4 个关键差异位于 Anniversary ADR、Anniversary Domain、Category Domain 与 Domain 索引，主要反映 SQLite Storage v4 落地和 Category active 状态。按用户要求保留 HXY 现状，未用来源旧内容覆盖，最终报告列出冲突供用户决策。
- 验证状态：通过两分支 `docs` tree blob 映射核对文件路径与内容，验证来源提交为 HXY 祖先并审阅 4 个关键文件的逐行差异；本次仅追加日志，提交前执行 `git diff --check` 和分支/文件计数复核。未运行代码构建或测试，因为没有修改功能代码、Contract 或运行时文档定义。
- 开发时间：2026-08-28 00:28 +08:00（Asia/Shanghai）。

## 2026-08-28 00:43 +08:00 R2 入口状态与相关文档同步

- 使用 Skill：无（纯文档状态核对与同步）。
- 负责模块：`docs/status/current.md`、`docs/status/roadmap.md`、架构/领域/索引文档、认证归档计划与 Cloud Backend 实现状态。
- 任务目标：依据当前生产代码、机器 Contract、最近自动化与真机记录，将项目状态从 R1 基线同步到“进入 R2 开发”，并修正相关过期描述。
- 任务结果：重写当前状态与路线图，确认 R1 主体工程完成、R2 成为当前阶段，Habit V1 为唯一 active 主计划；补充认证后端 16 端点、Flutter/Keystore、Ring、SQLite v4、四 Tab 导航及最近验证证据。明确保留 Backend/Auth Contract 仍为 `planned`、通知历史/普通日程管理、生产部署与设备矩阵等 R1 债务。同步修正架构文档旧入口、Category blocked/JSON writer 旧描述、Anniversary Reminder 旧待设计描述，并将两份认证计划标记为主体实现完成后归档。未修改 Contract、功能代码、依赖或工具链；工作区原有两份认证计划从 active 移至 completed 的未提交移动已保留。
- 验证状态：按生产调用链定向核对 Flutter、Kotlin、JNI/C++、SQLite、Cloud Backend Controller/Flyway、Contract 状态和测试记录；执行 Markdown 相对链接检查、状态关键词复查与 `git diff --check`。本次为纯文档同步，未重新运行 C++/Flutter/Android/Backend 构建和测试；文档引用的通过结果均标明为最近一次已记录证据。
- 开发时间：2026-08-28 00:43 +08:00（Asia/Shanghai）。

## 2026-08-28 02:00 +08:00 Habit 四层拆分与 Contracts Phase 0 完成

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn/HabitRecurrence/HabitReminderTemplate 领域与机器 Contract、Reminder/Notification 共享边界、SQLite v5 目标格式、Flutter/Kotlin/C++ 分层计划与总工程合并门禁。
- 任务目标：以总工程师身份将 Habit 总计划拆为 Contracts、C++、Kotlin、Flutter 四份可执行计划，亲自完成 Contract 核心，并为下游交付顺序、阻塞条件和最终合并验收建立统一基线。
- 任务结果：归档完成 `习惯-02-Contracts层开发计划.md`，建立 active 的 `习惯-03-CPP层开发计划.md`、`习惯-04-Kotlin层开发计划.md`、`习惯-05-Flutter层开发计划.md` 并回写主计划。冻结 10 个 Habit 与 2 个本机 Appearance 公开方法、11 个 Habit native call、完整 Schema/错误/枚举/UUIDv5 identity、Habit 专属 Reminder/Notification/action/reconciliation、公开 manual 与内部 notification-action CheckIn 输入隔离、固定点上界及 SQLite v5 四表七索引/原子 v4→v5 target。保留 SQLite v4 为 active writer，全部新 capability 保持 `planned + blocked`；未合并或伪造尚不存在的 C++、Kotlin、Flutter 生产代码。同步领域、ADR、索引、状态、路线图和问题记录，并保留工作区原有认证计划移动及其他用户修改。
- 验证状态：`contracts/run_habit_v1_validation.py` 通过 193 个 Schema、28 个 Habit fixture、4 个 Habit identity vector、12 个公开方法和 11 个 native call；`contracts/run_anniversary_r1_validation.py` 回归通过 56 个 Anniversary/Reminder fixture 与 20 个 identity vector；`git diff --check` 无空白错误，仅有既有 LF/CRLF 提示。未执行 C++、Kotlin、Flutter 构建或真机验证，因为本轮没有这些层的生产代码变更；对应验证已作为下游完成门禁列入分计划。
- 开发时间：2026-08-28 02:00 +08:00（Asia/Shanghai）。

## 2026-08-28 13:29 +08:00 Habit 分层计划与 Contracts 总监审阅

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit 主计划与 Contracts/C++/Kotlin/Flutter 分计划、Habit 领域与 ADR、Habit/Appearance/Reminder/Notification/Storage v5 机器 Contract 及专项 validator。
- 任务目标：以只读总监身份审阅 Habit 分计划是否符合主计划，并审阅现有 Habit Contracts 是否能够安全支撑预期开发；不修改业务代码、计划或协议内容。
- 任务结果：确认四层拆分、`Contracts → C++ → Kotlin → Flutter` 依赖顺序、职责边界和 capability blocked 策略总体合理；但发现 Contract Phase 0 暂不应视为可直接交付 C++ 的安全基线。主要阻断项包括：wire `number` 的两位小数最大值在 IEEE-754 边界不能区分相邻百分位；提醒时间变化会更换 template/occurrence identity，但当前只按 occurrence 去重，无法保证同一 Habit 同一当地日期最多一次真实展示；分页 `habit.list` 缺少首页“今日完成 X/Y”的全量聚合；挑战期限和用户文本缺少上界；DailyStatus 可引用 tombstone CheckIn、detail 锁定/历史边界等响应不变量不完整；reconciliation continuation 缺少零进展/重复 cursor 的防循环门禁。另确认 Kotlin 计划只构建 androidTest APK、未给出实际执行 instrumentation 的命令，validator 直接 fixture 覆盖仅涉及 34 个 Habit Schema 中的 6 个，Storage v5 validator 也未逐个冻结七个索引的精确 SQL。建议先把 Contracts 计划改为 Needs Revision、C++ 改回 blocked，修订协议、领域与 validator 后再恢复下游门禁。
- 验证状态：实际执行 `python contracts/run_habit_v1_validation.py`，通过 193 个 Schema、28 个 fixture、4 个 Habit identity vector、12 个公开方法和 11 个 native call；执行 `python contracts/run_anniversary_r1_validation.py`，通过 193 个 Schema、56 个共享回归 fixture 和 20 个 identity vector；`git diff --check` 通过，仅报告工作区既有 LF/CRLF 提示。另以 IEEE-754 double 实测 `90071992547409.90` 与 `90071992547409.91` 解析为同一数值，证明现有 fixed-point 上界并非跨语言精确。未运行 C++、Kotlin、Flutter 构建或真机测试，因为本次为只读计划/协议审阅且 Habit 生产实现尚不存在。
- 开发时间：2026-08-28 13:29 +08:00（Asia/Shanghai）。

## 2026-08-28 14:00 +08:00 Habit Contracts 总监 review 修订

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn Schema、领域不变量、生命周期矩阵、Reminder reconciliation、SQLite v5 目标约束、专项 fixtures/validator 与 C++/Kotlin/Flutter 分层计划。
- 任务目标：逐项复核总监提出的 7 个协议问题；对真实问题修订 Contract、领域和下游实施计划，同时遵守用户要求，不直接修改 Habit 主计划。
- 任务结果：确认 7 项均真实存在。数量 wire 从 IEEE-754 decimal number 改为 `_hundredths` JSON safe integer，并冻结相邻上界向量；增加 `(habit_id, occurrence_date)` 跨 template 每日单展示和 SQLite sent 唯一索引，明确 sent/prepared 后改时间或关闭重开从下一合法日生效；`habit.list` 增加全局、不受分页/筛选影响的 `today_progress`；冻结 400 天挑战、80/2000/32/500 文本、100 page 和 512 cursor 上限；禁止 tombstone CheckIn 出现在 response，补齐 has-ever/latest 与空历史边界对称条件；新增生命周期 × mutation 机器矩阵及 3 个确定性错误；reconciliation 回显 request limit，processed 精确等于四类 outcome 之和，续页必须正进展。SQLite v5 新索引由七个增为八个，C++/Kotlin/Flutter 分计划增加相邻整数 round-trip、同日提醒事务、重复 cursor 与单次唤醒预算、全局 X/Y 和生命周期 UI 测试。主计划本轮未修改；其旧 decimal 字段、提醒变更语义、验证计数和测试矩阵待用户批准后同步。
- 验证状态：实际执行 `python contracts/run_habit_v1_validation.py`，通过 194 个 Schema、44 个 Habit fixture、4 个 Habit identity vector、12 个公开方法和 11 个 native call；实际执行 `python contracts/run_anniversary_r1_validation.py`，通过 194 个 Schema、56 个共享回归 fixture 和 20 个 identity vector。未运行 C++、Kotlin、Flutter 构建或真机测试，因为这些层尚无 Habit 生产实现，本轮仅修改 Contract、领域和计划；跨语言真实 round-trip 与运行时行为已列入各层开工/完成门禁。
- 开发时间：2026-08-28 14:00 +08:00（Asia/Shanghai）。

## 2026-08-28 14:23 +08:00 Habit 三层独立并行计划改造

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit Contracts 交接说明、C++/Kotlin/Flutter 三份 active 分层计划、架构并行开发规则、R2 索引与状态导航。
- 任务目标：把原串行实现依赖改造成三个可独立运行的并行计划；Kotlin/Flutter 允许使用 Contract-conformant 假数据完成各自开发与验收，三层完成后由总工程师统一接真实链路并清理运行时 Fake，同时不直接修改 Habit 主计划。
- 任务结果：三份计划统一采用 `Contract Ready / Independent Parallel Track`，要求从同一冻结 Contract revision 建立独立分支/worktree，并定义 `Layer Complete / Awaiting Integration` 状态。C++ 独立交付真实 Domain/SQLite v5/Boundary；Kotlin 通过同接口 `FakeNativeHabitBridge` 验证 Handler、调度、通知、Receiver 与 Appearance；Flutter 通过脚本化 Gateway Fake 和显式 preview 入口交付页面与交互。Fake 只能消费预制 Contract 投影，不得复制 C++ 生命周期、统计、身份或提醒规则；默认/Release production composition 禁止回退 Fake。最终集成删除运行时 preview/debug Fake 与 seed，保留 test/instrumentation Fake 作为回归资产，再执行同一 APK、Native smoke 和真机门禁。同步更新 Contracts 完成计划、架构、索引、当前状态、路线图和 Contract README；上位主计划保持未改，并明确记录其旧串行文字待用户单独批准后统一。尚未创建共同基线提交，因为当前工作树包含未提交修改且本任务未授权 Git 提交；并行任务启动前必须先固化并记录该 revision。
- 验证状态：`contracts/run_habit_v1_validation.py` 通过 194 个 Schema、44 个 Habit fixture、4 个 Habit identity vector、12 个公开方法和 11 个 native call；`contracts/run_anniversary_r1_validation.py` 回归通过 194 个 Schema、56 个 fixture 和 20 个 identity vector；Markdown code fence/trailing whitespace 检查通过；`git diff --check` 通过，仅有既有 LF/CRLF 提示。未运行 C++、Kotlin、Flutter 构建或真机测试，因为本轮只调整开发计划与导航，没有修改三层生产代码。
- 开发时间：2026-08-28 14:23 +08:00（Asia/Shanghai）。

## 2026-08-28 15:20 +08:00 Habit Flutter 层独立交付

- 使用 Skill：`frontend-flutter-feature`、`calendar-data-contracts`。
- 负责模块：`flutter_client` 的 Habit DTO/Mapper、Gateway 与 MethodChannel Adapter、Application Controller、列表/表单/详情/指定日页面、通知深链、本机 Appearance、显式 Fake Preview 入口及 Flutter 测试。
- 任务目标：严格执行 `docs/plan/active/习惯-05-Flutter层开发计划.md`，在不复制 C++ 领域计算的前提下，按冻结 Habit/Appearance Contract 完成可独立验收的 Flutter 交付，并确保生产组合不回退 Fake。
- 任务结果：完成 10 个 Habit 方法与 2 个 Appearance 方法的严格 Contract 映射；实现安全整数百分位数量、Unicode 长度和 400 天期限校验；实现列表分组、全局今日进度、快捷/精确打卡、创建编辑、指定日记录、统计热力图、向前分页、提前结束/软删除/再来一轮、前后台刷新和并发门禁；接入通知 occurrence 深链与本机主题色；提供 fixture 派生的脚本化 Fake 和仅由 `main_habit_preview.dart` 启用的预览组合。当前状态为 **Layer Complete / Awaiting Integration**；真实 JNI/C++ 行为与 Android 真机提醒链路留待总工程师集成阶段验证。
- 验证状态：`dart format --output=none --set-exit-if-changed lib test` 通过；`flutter analyze` 通过且无问题；`flutter test` 全量 421 项通过；`flutter build apk --debug -t lib/main_habit_preview.dart` 与 `flutter build apk --debug` 均成功，最终 `app-debug.apk` 为生产入口；未升级 Flutter、Gradle、SDK 或第三方依赖。未执行 Android 真机/ADB、真实 JNI/C++/SQLite 联调，因为本计划是 Contract-first 独立 Flutter 轨道，相关下层实现不属于本次范围。
- 开发时间：2026-08-28 15:20 +08:00（Asia/Shanghai）。

## 2026-08-28 15:46 +08:00 Habit C++ 层独立交付

- 使用 Skill：`cpp-core-feature`。
- 负责模块：`cpp_core` 的 Habit Domain、Application Service、事务仓储、SQLite v5、Reminder/Notification 投递工作流、Boundary v2、Native Runtime 组合及专项测试。
- 任务目标：严格执行 `docs/plan/active/习惯-03-CPP层开发计划.md`，以冻结 Habit Contract 和领域不变量为准，完成可独立构建、测试和交付的真实 C++ 实现，不伪造底层行为、不修改其他层生产代码。
- 任务结果：完成 Habit 生命周期、重复规则、定量/非定量打卡、清除、统计、分页和乐观并发；完成四类 Habit 持久化、严格 JSON/状态校验及原子 SQLite v4→v5 迁移；完成提醒模板、同日唯一投递、prepare/finalize/replay、通知直接打卡、时区/时间变化与权限恢复 reconciliation；完成 11 个 Boundary v2 native 方法、严格请求校验、安全整数 wire 映射和 Native Runtime 组合。因冻结 Contract 已将旧计划中的 IEEE-754 decimal 数量升级为 `_hundredths` JSON safe integer，本实现采用该更高优先级真相源。当前状态为 **Layer Complete / Awaiting Integration**；Kotlin/JNI/APK/真机链路属于最终集成阶段。
- 验证状态：重新配置并构建 `cpp_core/build-ninja`；三个新增测试目标分别通过；`cmake --build cpp_core/build-ninja --target excellent_calendar_check` 完整回归 10/10 通过。`python contracts/run_habit_v1_validation.py` 通过 194 个 Schema、44 个 Habit fixture、4 个 identity vector、12 个公开方法和 11 个 native call；`python contracts/run_anniversary_r1_validation.py` 通过 194 个 Schema、56 个 fixture 和 20 个 identity vector。`git diff --check -- cpp_core docs/log.md` 通过，仅报告仓库既有 LF/CRLF 转换提示。未执行 Kotlin、Flutter、APK、ADB 或真机验证，因为不属于本 C++ 独立计划的允许修改和验收边界。
- 开发时间：2026-08-28 15:46 +08:00（Asia/Shanghai）。

## 2026-08-28 Native Runtime、共享所有权与陌生代码阅读方法教学

- 使用 Skill：`self-learning`。
- 负责模块：`cpp_core` Native Runtime composition root、AnniversaryQueryService 与 LocalTimeResolver 生命周期；只读教学分析。
- 任务目标：评估学习者对 `shared_ptr` 共享所有权的理解，解释 `native_runtime.cpp` 的职责，并建立无需逐行展开全部实现的陌生方法阅读流程。
- 任务结果：确认学习者已掌握引用计数决定共享对象生命周期的核心语义；进一步区分“当前实现采用共享所有权”和“共享所有权必然是最佳设计”，梳理 RuntimeState 的进程级持有、初始化时的依赖创建与注入、线程安全发布、Boundary getter 借用以及重新初始化时撤销旧运行时；给出按当前问题逐层展开头文件、调用点、实现和测试的目标驱动阅读法。
- 验证状态：已核对当前开发工作区中的 SQLite/Habit Native Runtime 组装、Resolver 创建及多 Service 注入、AnniversaryQueryService 成员持有、Runtime getter 和 Result value 语义；未修改业务代码，未运行构建或测试。
- 开发时间：2026-08-28（Asia/Shanghai）。

## 2026-08-28 17:34 +08:00 Habit 三层总审阅、返修与真实链路集成

- 使用 Skill：`review-worktree-architecture`、`cross-layer-feature`、`cpp-core-feature`、`android-kotlin-native-feature`、`frontend-flutter-feature`。
- 负责模块：Habit C++ Core/SQLite v5/Boundary、Android Kotlin/MethodChannel/JNI/提醒调度、Flutter DTO/Application/页面，以及三层真实生产组合和合并门禁。
- 任务目标：审阅 C++、Kotlin、Flutter 三层独立交付；将重大缺陷退回对应负责人修复，由总工程师修复小缺陷；删除并行开发期运行时 Fake/种子入口，接通 `Flutter → MethodChannel → Kotlin → JNI → C++ → SQLite v5`，最后执行合并后的完整主机验证并记录所有问题。
- 任务结果：审阅确认 C++ 有 8 项 P1（upcoming reminder 被取消、failed reminder 被复活、提前结束事务/历史 clear/startDate 更新、fixed-point 词法、SQLite 精确 schema 与 UUID/所有权等），Kotlin 有 1 项 P1（11 个 Habit external 缺少 JNI 导出并可能饿死共享 reconcile），Flutter 有 6 项 P1（DTO 分支不严、生命周期快捷操作、历史日投影、mutation 锁、真实调度 capability 与暗色主题）；均由对应层负责人完成最小返修并新增回归。总工程师另修复提前结束进度冻结、已删除详情错误码、WorkManager continuation 持久化/预算失败、Kotlin 嵌套 DailyStatus/ReminderSettings 校验、Flutter Native `as_of_date` 打卡日期、成功反馈/失败重试。删除 `lib/main_habit_preview.dart` 和 `lib/**` 下 Habit/Appearance 运行时 Fake，将长期测试替身迁入 `test/fakes/**`；生产 composition 保持真实 MethodChannel，无 Fake fallback。未修改 Habit 主计划或 Contract。
- 验证状态：两套 Contract validator 通过（194 schemas、44 Habit fixtures、4 Habit identity vectors、12 public methods、11 native calls；共享回归 56 fixtures/20 vectors）；C++ 按要求重新 configure 并执行 build-after-test，`excellent_calendar_check` 10/10 通过；Flutter format 389 文件/0 变更、`flutter analyze` 0 issues、全量 437 tests 通过、Debug APK 构建成功；Android 38 suites/200 tests（0 failures、0 errors、1 skipped）、lint、Debug APK 与 androidTest APK 全部通过；独立 Native smoke test/analyze/APK 通过；arm64-v8a、armeabi-v7a、x86_64 的 Habit JNI 均为 11/11 导出且 APK 含三 ABI；目标范围无冲突标记、无生产 Habit Fake 引用，`git diff --check` 通过，仅有既有 LF/CRLF 提示。当前 `adb devices -l` 为空且无可用 AVD，因此真实设备上的通知权限允许/拒绝/恢复、前后台/杀进程/重启、同日补发/跨日过期、通知快捷完成及时区/系统时间变化仍为 **未验证**；Contract capability 继续保持 `planned + blocked`，不得据主机结果宣称完整发布激活。
- 开发时间：2026-08-28 17:34 +08:00（Asia/Shanghai）。

## 2026-08-28 18:08 +08:00 Habit 开启提醒后创建提示协议不兼容修复

- 使用 Skill：`debug`、`android-kotlin-native-feature`。
- 负责模块：Android Kotlin Habit mutation orchestration 公开响应拼装及对应单元测试。
- 任务目标：复现并修复新建 Habit、开启每日提醒后点击“开始挑战”出现“数据协议不兼容，请更新应用后重试”的问题，不修改 Habit 主计划或 Contract。
- 任务结果：真机确认不启用提醒时创建正常、启用 09:00 提醒时稳定复现；Native 创建事务和 Android Alarm 实际均成功，但 Kotlin 公开响应仍保留事务提交前 `detail.reminder_settings.schedule_reconciliation_required=true`，同时 capability 已返回调度后的 `false`，Dart 严格 DTO 因两处状态矛盾拒绝响应。现于 Kotlin orchestration 在调度结束后将 mutation/check-in 嵌套 ReminderSettings 投影为最终 capability 状态，并保留权限受阻时的待 reconciliation 状态；新增成功精确调度与权限受阻回归断言。
- 验证状态：`HabitMutationOrchestratorTest` 定向测试通过；Android `testDebugUnitTest`、`lintDebug`、`assembleDebug` 全部通过；Debug APK 安装至 Android 16 realme RMX5100 真机后，使用完成型、21 天、每日 09:00 提醒路径创建成功，页面显示“习惯已保存 / 提醒已按精确时间安排”，日志确认 `reminder.reconcile_schedule` 与 `habit.create ... ok=true`，未再出现协议校验错误。
- 开发时间：2026-08-28 18:08 +08:00（Asia/Shanghai）。

## 2026-08-28 18:25 +08:00 Habit 连续天数圆环与详情快捷操作调整

- 使用 Skill：`frontend-flutter-feature`。
- 负责模块：Flutter Habit 卡片和 Habit 详情页展示、交互及 Widget 回归测试。
- 任务目标：将进行中 Habit 卡片右侧圆环中心由完成率数字改为当前连续完成天数；在详情页直接提供“跳过今天”；把软删除入口移动至右上角垃圾桶按钮，不修改主计划、Contract 或 Native 层。
- 任务结果：圆环弧度继续表达全周期完成率，中心数字改为直接展示 C++ 统计投影 `current_streak`，并补齐“完成率 + 当前连续天数”无障碍语义；详情页对 active 且存在 today 投影的 Habit 显示“跳过今天”，通过现有 `habit.check_in(skipped)` 能力写入，完成后刷新并显示“今天已跳过”；删除入口从列表底部移至 AppBar 右上角垃圾桶，沿用既有二次确认与软删除流程。连续天数及中断归零继续由 C++ 权威统计负责，Flutter 不重复计算。
- 验证状态：Habit Widget 定向 10 项通过；Flutter format 389 文件/0 变更、`flutter analyze` 无问题、全量 439 项测试通过、Debug APK 构建成功。APK 安装至 Android 16 realme RMX5100 真机后，确认完成率 100%/连续 1 天的卡片圆环中心显示 `1`；详情页右上角显示“删除习惯”按钮，底部显示“跳过今天”。真机核对未执行跳过或删除，未修改既有 Habit 数据。
- 开发时间：2026-08-28 18:25 +08:00（Asia/Shanghai）。

## 2026-08-28 18:49 +08:00 Habit 最终集成白盒 Review 计划

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn 全层审阅计划，覆盖 Contract、C++ Core、SQLite v5、Kotlin/JNI/Android 提醒与通知动作、Flutter/Appearance 和共享 Reminder/Notification 回归边界。
- 任务目标：为 Habit 开发结束后的最终集成候选版本建立一份风险导向白盒 Review 计划，提前标出最容易被实现、并行接线和测试遗漏的故障点，不修改当前业务代码。
- 任务结果：新增 active Review 计划，明确发布阻断红线、10 个公开 Habit 方法、2 个 Appearance 方法、11 个 internal native call 的真实闭环，以及定点数精度、Unicode 长度、日期/生命周期、CheckIn tombstone、统计快照、同日跨模板提醒配额、两阶段投递崩溃窗口、通知动作安全、SQLite v4→v5 原子迁移、Fake 隔离和既有功能回归矩阵；同步更新文档索引入口。
- 验证状态：仅新增/更新文档，未审阅或修改当前并行业务实现，未运行构建与业务测试；Habit Contract validator 通过（194 schemas、44 Habit fixtures、4 Habit identity vectors、12 public methods、11 native calls，状态 `planned + blocked`），Review 文档 34 个本地路径引用均存在，17 个风险章节与关键覆盖词检查通过，`git diff --check` 通过，仅有既有 LF/CRLF 提示。
- 开发时间：2026-08-28 18:49 +08:00（Asia/Shanghai）。

## 2026-08-28 19:31 +08:00 Habit 最终集成白盒 Review 执行

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn Contract、C++ Core/SQLite v5/Boundary、Kotlin/JNI/Android Reminder/Notification、Flutter 页面与真实 production composition；仅审阅，不修改业务代码。
- 任务目标：按 active Habit 白盒 Review 计划审阅当前完整工作树，判断实现是否满足主计划、Contract、领域不变量和现实 Android 运行场景，并通过独立构建与测试形成发布判定。
- 任务结果：判定 **CHANGES REQUIRED**。确认 5 项运行时缺陷与 1 项真相源漂移：dispatcher Alarm 绕过 Habit 跨日过期 reconciliation，延迟至次日仍可能投递旧 occurrence；Flutter 对 date-only 期限预设和历史分页使用 `Duration(days)`，跨 DST 会错日；二元 Habit 详情展示 skipped 操作但 C++ 明确拒绝；Habit reconciliation 达 2000 条后续跑不保留 cursor，尾部记录可能永久饥饿；partial Reminder 文案直接展示内部“百分位”且缺失用户单位；active 主计划仍把数量写为 decimal number，与当前 `_hundredths` integer Contract 冲突。生产 composition 已使用真实 MethodChannel，未发现 Habit Fake fallback，SQLite v5、JNI 编译与现有测试基线未发现新的结构性失败。
- 验证状态：Habit Contract validator 通过（194 schemas、44 Habit fixtures、4 identity vectors、12 public methods、11 native calls，状态 `planned + blocked`）；C++ 重新 configure 后 `excellent_calendar_check` 10/10 通过；Flutter 全量 439 tests 通过、`flutter analyze` 无问题；Android `:app:testDebugUnitTest --rerun-tasks`、`lintDebug`、`assembleDebug`、`assembleDebugAndroidTest` 通过；`git diff --check` 无 whitespace error，仅有既有 LF/CRLF 提示。当前 `adb devices -l` 为空，真机通知权限、延迟闹钟跨午夜、系统重启/杀进程、DST/时区变化及通知 action instrumentation 均为 **未验证**，capability 必须继续保持 `planned + blocked`。
- 开发时间：2026-08-28 19:31 +08:00（Asia/Shanghai）。

## 2026-08-28 21:21 +08:00 Habit 最终 Review 问题返修

- 使用 Skill：`debug`、`cross-layer-feature`、`calendar-data-contracts`、`cpp-core-feature`、`android-kotlin-native-feature`、`frontend-flutter-feature`。
- 负责模块：Habit Contract/Domain、C++ 打卡与 Reminder 投递、Android dispatcher/WorkManager reconciliation、Flutter date-only 运算，以及相关跨层回归测试。
- 任务目标：复核最终白盒 Review 提出的 3 类 P1、2 类 P2、1 类 P3，修复确认存在的问题，同时保护当前脏工作树中的既有三层集成修改。
- 任务结果：确认六类问题主体均真实存在并完成返修。dispatcher 现于共享提醒投递前先完成 Habit reconciliation；`prepare_delivery` 接收可选设备 IANA timezone，并由 C++ 对 Habit occurrence 执行同当地日期终检，过期 Reminder 与 prepared Notification 在同一事务中分别转为 expired/abandoned。Flutter 新增纯 civil-date 工具，期限预设、历史分页和 DailyStatus 连续性不再使用本地 `Duration(days)`。按 Contract/主计划统一二元与数量型 Habit 均允许 `skipped`，并修订领域说明。WorkManager continuation 持久化 seek-after cursor、原 trigger、冻结 timezone 和 dispatcher plannedAt；时区变化时丢弃旧 cursor 安全重扫；有下一页时暂缓共享提醒，避免尾页 Habit 尚未清理便被投递。C++ 使用无浮点百分位格式化器生成实际数量与单位，修复 partial Reminder 文案。经本次用户授权，主计划旧 decimal number 描述已同步为 `_hundredths` JSON safe integer。Review 中“旧通知点击会补写昨天”的具体推断在当前实现不成立：既有 C++ notification-action 校验已拒绝非当地今天的 `check_date`；“最终通知一定显示百分位”也不完全成立，因为 prepare 阶段已有动态投影，但持久 Reminder 文案确实错误，现已统一修复。capability 继续保持 `planned + blocked`。
- 验证状态：Habit Contract validator 通过（194 schemas、46 Habit fixtures、4 identity vectors、12 public methods、11 native calls）；Anniversary 共享协议回归通过（194 schemas、56 fixtures、20 vectors）；C++ build-after-test `excellent_calendar_check` 10/10 通过；Flutter format 390 文件/0 变更、`flutter analyze` 无问题、全量 440 tests 通过、Debug APK 构建成功；Android 全量 unit test、`lintDebug`、androidTest APK 构建通过；arm64-v8a、armeabi-v7a、x86_64 的 Habit JNI 导出均为 11/11；`git diff --check` 无 whitespace error，仅有既有 LF/CRLF 提示。当前 `adb devices -l` 为空，真实设备上的跨午夜延迟 Alarm、通知展示/快捷动作、进程死亡/重启、权限和时区变化矩阵仍为 **未验证**，不能据主机门禁宣称发布激活。
- 开发时间：2026-08-28 21:21 +08:00（Asia/Shanghai）。

## 2026-08-28 21:51 +08:00 Habit 最终 Review 返修独立复核

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn Contract、C++ CheckIn 与 Reminder 投递、Android dispatcher/WorkManager continuation、Flutter civil-date、JNI/APK 和共享 Anniversary 协议回归；仅审阅和验证，不修改业务代码。
- 任务目标：独立检查最终白盒 Review 中六类问题的返修是否真实接入生产调用链、满足主计划与 Contract，并复现开发者报告的主机验证结果。
- 任务结果：判定六类返修在主机可验证范围内均成功，未发现需要再次退回的代码缺陷。确认 Habit dispatcher 在共享投递前完成专属 reconciliation，C++ `prepare_delivery` 以当前设备时区执行当地日期终检并原子终结过期 Reminder/prepared Notification；Habit 日期运算已统一经 UTC-backed `CivilDate`；二元与数量型 skipped 均被 C++ 接受且清空完成快照；continuation 持久化 seek-after cursor、原 trigger、时区和 dispatcher plannedAt，并在时区变化时安全重扫、完成前暂缓共享 dispatcher；partial 文案使用无浮点百分位格式化后的实际数量和用户单位；主计划数量 wire 已同步为 `_hundredths` JSON safe integer。复核也确认原审阅关于旧通知 action 和最终系统通知文案的两项影响描述确有扩大：既有 C++ 会拒绝非当地今天的 action，prepare 阶段也会动态生成最终通知正文。Capability 保持 `planned + blocked` 正确。
- 验证状态：Habit Contract validator 通过（194 schemas、46 fixtures、4 identity vectors、12 public methods、11 native calls）；Anniversary 共享回归通过（194 schemas、56 fixtures、20 vectors）；C++ build-after-test 10/10 通过；Flutter format 390 文件/0 变更、`flutter analyze` 无问题、全量 440 tests 和 Debug APK 构建通过；Android `:app:testDebugUnitTest --rerun-tasks --no-daemon` 为 38 suites/205 tests（0 failures、0 errors、1 skipped），其中 skipped 是旧 V1 `ReminderDeliveryService` 的已知 stale Alarm 测试；当前 BuildConfig 固定启用 V2，生产 composition 使用先 prepare 后展示的 `V2ReminderDeliveryService`，故不影响本次 Habit V2 返修判定，但旧 V1 代码与忽略测试仍应在后续兼容清理中处理。`lintDebug` 与 `assembleDebugAndroidTest` 通过；APK 含 arm64-v8a、armeabi-v7a、x86_64，三种 ABI 的 Habit JNI 均为 11/11 导出；`git diff --check` 退出码 0，仅有 LF/CRLF 提示。一次并发合并 Gradle 命令发生 daemon socket 序列化异常，拆分为隔离单次进程后全部通过，判定为本机 daemon 干扰而非代码失败。`adb devices -l` 仍为空，跨午夜延迟 Alarm、进程死亡/重启、真实通知展示/快捷动作、权限与时区变化矩阵未完成真机验证，因此不能标记正式发布激活。
- 开发时间：2026-08-28 21:51 +08:00（Asia/Shanghai）。

## 2026-08-29 20:23 +08:00 Habit 黑盒与异常数据复核

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn Contract、C++ Core/SQLite v5、Kotlin/JNI/Android Reminder、Flutter Habit 页面与生产装配；仅测试和审阅，不修改业务代码。
- 任务目标：以黑盒为主复核 Habit 已实现功能，向 Contract、DTO、Application、Core/Storage 和 Android 边界施加非法、边界、分页及状态组合数据，评估尚未完善的问题并给出修正方向。
- 任务结果：判定 **CHANGES REQUIRED**。一次性独立 Widget/Application 用例确认：Habit 卡片背景使用 `challenge_time_progress`，在完成率 30%、时间进度 80% 时实际填充 80%，与用户最终确认“背景表达完成率、时间进度只显示剩余天数”不符；列表收到 `has_more=true + next_cursor` 后只请求第一页，超过 100 条的 Habit 无法从页面访问。另确认数量型卡片左侧圆圈只显示加号，没有展示已确认的剩余数量；通知进入详情时直接向普通用户展示 occurrence 技术标识；active 计划和 current status 仍描述 C++/Kotlin/Flutter 未实现，与当前生产接线和测试事实不一致，但因缺少设备门禁，机器 capability 保持 `planned + blocked` 仍属正确。临时复现测试已删除，未留下生产或测试文件。
- 验证状态：Habit Contract validator 通过（194 schemas、46 fixtures、4 identity vectors、12 public methods、11 native calls）；Anniversary Contract 回归通过（194 schemas、56 fixtures、20 vectors）；C++ build-after-test `excellent_calendar_check` 10/10 通过；Flutter Habit 定向 36/36、全量 440/440、`flutter analyze` 和 Debug APK 构建通过；Android Habit/Reminder 定向 unit、全量 `:app:testDebugUnitTest`、`lintDebug`、androidTest APK 构建通过；Native smoke test/analyze/Debug APK 通过；Debug APK 包含三种 ABI，Habit JNI 均为 11/11 导出；`git diff --check` 退出码 0，仅有既有 LF/CRLF 提示。当前无 Android 设备或模拟器，真实点击、通知权限/展示/快捷动作、跨午夜、杀进程/重启和时区变化仍为 **未验证**，不得激活 capability。
- 开发时间：2026-08-29 20:23 +08:00（Asia/Shanghai）。

## 2026-08-31 12:48 +08:00 日历月/周分类视图需求发现

- 使用 Skill：`frontend-flutter-feature`、`calendar-data-contracts`。
- 负责模块：日历 Tab、月/周日期网格、Event/Anniversary/Habit 按日聚合的产品与数据边界规划；本轮仅分析，不修改业务代码。
- 任务目标：结合两张参考截图、用户口述和现有项目架构，提取前端要素，盘点真实数据能力，并通过分轮提问收敛交互、范围、聚合语义和开发方案，最终形成可执行计划。
- 任务结果：确认现有日历 Tab 仍为占位；Event 与 Anniversary 已有生产查询，Habit Contract 已冻结但 capability 仍为 `planned + blocked` 且工作树包含在途实现；当前缺少统一日历聚合 Contract/active plan。首轮将围绕导航、日期移动、周/月切换、日期标记、分组卡片、条目动作、创建入口、节假日、错误空态和纯前端编排/统一查询投影取舍向用户确认。
- 验证状态：完成截图原图检查、架构/索引/状态/路线图、相关领域文档、MethodChannel Schema、Flutter 占位入口及现有 Gateway 的只读核对；未运行测试或构建，因为本轮尚未实施代码。工作区原有大量 Habit/Contract/C++/Android/Flutter 未提交改动均未触碰。
- 开发时间：2026-08-31 12:48 +08:00（Asia/Shanghai）。

## 2026-08-31 13:34 +08:00 日历月周分类视图主计划冻结

- 使用 Skill：`frontend-flutter-feature`、`calendar-data-contracts`、`cross-layer-feature`。
- 负责模块：日历 Tab 产品规格、Calendar 只读组合投影、Event/Habit/Anniversary 按日聚合、跨层实施拆分和验收门禁；本轮不修改业务代码或 Contract。
- 任务目标：依据用户三轮选择，将参考截图和口述需求收敛为可执行的专业开发计划，明确产品行为、数据语义、分层职责、实施顺序、风险、测试和完成定义。
- 任务结果：新增 active 主计划 `docs/plan/active/日历-01-月周分类视图与三类数据聚合开发计划.md`，冻结中文年月、周一开头、周/月切换、年月选择、今天按钮、月→周折叠、先展开后刷新、三类圆点、三组 20 条分页、跨日/重复 Event、Habit 日状态、Anniversary 精确 occurrence、新建预填、缓存/错误和主题无障碍行为。可行性判定为 `SPECIALIST_SPLIT`，拟议 `calendar.range_summary` 与 `calendar.list_day_items` 两级只读投影，并拆为 Contract/数据、C++/SQLite、Kotlin/JNI、Flutter、真实集成和独立 Review 六轨。同步更新文档索引、当前状态与路线图，移除“日历无 active 计划”的过期入口。
- 验证状态：计划结构、冻结需求关键词和两级查询方案自检通过；`git diff --check` 无 whitespace error，仅输出工作区既有 LF/CRLF 提示。未运行 Contract validator、C++、Flutter、Android 构建或测试，因为本轮仅建立计划且未实现任何生产代码；工作区原有 Habit/Contract/C++/Android/Flutter 修改均未触碰。
- 开发时间：2026-08-31 13:34 +08:00（Asia/Shanghai）。

## 2026-08-31 12:57 +08:00 Habit 黑盒产品反馈返修

- 使用 Skill：`frontend-flutter-feature`、`debug`。
- 负责模块：Flutter Habit 卡片、列表分页、通知详情呈现、Application/Widget 回归测试，以及 Habit 当前状态导航文档；未修改 Contract、C++、Kotlin/JNI、SQLite 或上位主计划。
- 任务目标：复核总经理反馈的卡片进度、101+ 列表可见性、数量型快捷圆圈和 occurrence 内部标识问题；确认真实存在时做最小修复，并校准与实现事实不一致的项目状态。
- 任务结果：四项反馈均确认真实存在并完成修复。卡片背景改由 `completionRate` 驱动，挑战时间进度只保留“剩余 X 天”文字；列表控制器消费 `has_more/next_cursor`，提供显式“继续加载更多习惯”入口，跨页按 Habit ID 去重并只保留第一页的全局 `today_progress`；数量型快捷圆圈显示 `max(target-completed, 0)`，达标/超额显示勾选，精确数量入口继续保留；详情仍携带 `focusOccurrenceKey` 供路由与诊断使用，但不再向普通用户渲染 UUID。同步更新索引、current status 和 roadmap，明确 UI/分页反馈已关闭，Storage v5 与 Habit capability 仍为 `planned + blocked`，真机矩阵和状态校准仍是发布门禁。
- 验证状态：Habit Application/Widget 定向 29/29 通过；Flutter 全量 444/444 通过；`flutter analyze` 无问题；Debug APK 构建成功。未执行真机通知权限、跨午夜、杀进程/重启、通知快捷动作及时区/系统时间变化矩阵，因此未将 Habit 标记为正式激活或发布完成。
- 开发时间：2026-08-31 12:57 +08:00（Asia/Shanghai）。

## 2026-08-31 13:08 +08:00 Habit 计划与状态文档实时校准

- 使用 Skill：无；本次为纯计划/状态文档治理，不使用会修改代码或 Contract 的专项 Skill。
- 负责模块：Habit 主计划、C++/Kotlin/Flutter 分层计划、active Review、项目 current/roadmap/index，以及与当前状态直接相邻的架构、领域索引和 open issue 说明。
- 任务目标：仅处理黑盒 Review 的 P3“计划和状态文档已经明显落后于代码”，根据当前生产接线、最新返修与验证事实更新文档，不修改或顺带处理其他功能问题。
- 任务结果：主计划和三份分层计划已从“待 C++/并行 Fake/等待真实接线”校准为“实现与真实集成完成、主机门禁通过、最终设备门禁待完成”；同步已完成阶段清单与黑盒矩阵，关闭已经通过验证的 UI/分页项，保留通知权限、跨午夜、进程死亡/重启、通知动作、时区变化、真实 instrumentation 与 TalkBack 等设备依赖项。Review/current/roadmap/index 统一采用同一口径；Storage v5 仅描述为已实现的集成候选，机器 Storage v4 active、Habit `planned + blocked` 均未修改或提前激活。未修改业务代码、Schema、Contract 或其他问题。
- 验证状态：Habit validator 现场通过（194 schemas、46 fixtures、4 identity vectors、12 public methods、11 native calls），并确认机器状态仍为 `planned+blocked`；当前 `adb devices -l` 无设备、`flutter emulators` 无可用模拟器，因此剩余真机矩阵继续标记未验证。已执行目标文档的状态/未勾选项/陈旧措辞检索、路径与范围检查及 `git diff --check`；文档任务未重跑业务构建和全量测试，引用最近一次已记录的主机门禁结果。
- 开发时间：2026-08-31 13:08 +08:00（Asia/Shanghai）。

## 2026-08-31 14:10 +08:00 独立搜索功能需求发现首轮

- 使用 Skill：无；本轮是产品需求发现、参考图拆解和现状只读盘点，尚未进入任何单层或跨层实现。
- 负责模块：搜索 Tab、Event/Habit/Anniversary 三类聚合检索、筛选浮层、结果分组、匹配高亮和本地搜索历史的产品与架构规划。
- 任务目标：结合三张参考图和用户口述，提取可复用前端要素，核对项目已有搜索与三类数据能力，识别关键产品决策，并通过分轮问答收敛为后续可执行的专业开发计划。
- 任务结果：确认搜索 Tab 仍为占位；Event 已具备标题/内容/地点关键字及时间、状态、分类等真实搜索能力，Habit 与 Anniversary 只有列表能力；`SearchIndex` 领域与 response Schema 已存在，但统一 Search Contract、索引维护、历史、中文匹配验收和 SQLite FTS 均未实现。首轮方案建议采用固定“日程 / 习惯 / 纪念日”分组、标题与命中摘要高亮、右侧筛选入口、设备本地历史，以及先冻结统一 C++ 搜索投影、经性能门禁再决定 FTS；同时需与 active Calendar 三类聚合计划共享详情投影边界，避免重复模型。
- 验证状态：完成三张原图、架构/索引/当前状态/路线图、SearchIndex 与 Event/Habit/Anniversary 相关 Schema、C++ Event 搜索实现、Flutter 四 Tab 占位入口及 Calendar active plan 的只读核对；未运行测试或构建，因为本轮尚未实现代码。工作区原有 Habit/Contract/C++/Android/Flutter 大量未提交改动均未触碰。
- 开发时间：2026-08-31 14:10 +08:00（Asia/Shanghai）。

## 2026-08-31 14:22 +08:00 独立搜索功能首轮需求确认

- 使用 Skill：无；本轮继续进行产品需求冻结，未进入代码或 Contract 实施。
- 负责模块：三类聚合搜索行为、匹配范围、结果分组、时间语义、筛选入口与本地历史策略。
- 任务目标：记录用户对首轮九项产品选择的确认，并识别进入正式开发计划前仍需冻结的状态映射、展示密度、排序、筛选提交与状态恢复细节。
- 任务结果：用户确认采用统一 C++ 本地搜索服务且首版不直接建设 FTS；输入停止 `1s` 后自动搜索；检索日程标题/内容/地点/分类名称、习惯标题/描述/分类名称、纪念日标题/备注/分类名称；采用中文原文包含、英文忽略大小写、空格分词 AND；重复对象只显示一个逻辑结果；默认包含并弱化已完成内容；固定按“日程 / 习惯 / 纪念日”分组；确认业务发生日期时间筛选；采用右上角浮层加复杂选项二级面板；历史为设备本地最近 20 个唯一关键字且不保存筛选。
- 验证状态：仅完成需求确认与一致性检查，未运行测试或构建；现有工作树业务改动未触碰。
- 开发时间：2026-08-31 14:22 +08:00（Asia/Shanghai）。

## 2026-08-31 14:43 +08:00 独立搜索功能主计划冻结

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`；前者用于冻结 date/datetime、occurrence、Contract、cursor、history persistence 与未来迁移边界，后者用于完成跨层盘点和 `SPECIALIST_SPLIT` 可行性判定。
- 负责模块：搜索 Tab 产品规格、Event/Habit/Anniversary 三类统一 Search 查询、Kotlin 本地历史、跨层协议、性能/FTS 门禁、实施拆分与验收矩阵；本轮不修改业务代码或现有 Contract。
- 任务目标：依据用户两轮选择，将三张参考图和口述需求收敛为详细、规整、可执行的 active 开发计划，并同步项目导航和阶段状态。
- 任务结果：新增 active 主计划 `docs/plan/active/搜索-01-三类聚合搜索与本地历史开发计划.md`，冻结 1s debounce、三类允许字段、中文连续子串/ASCII 大小写不敏感/空格 token AND、逻辑对象去重、业务日期 occurrence、默认包含完成、固定三组、20 条独立分页、智能/时间/更新排序、右上 staged 筛选浮层、设备本地 20 条历史、长按全体显示删除按钮、清空/撤销、详情返回与会话恢复。可行性判定为 `SPECIALIST_SPLIT / Contract Pending`，建议 `search.query` 加 Kotlin-local history 方法，并拆为 Contract/数据、C++/SQLite、Kotlin/JNI/历史、Flutter、真实集成/性能和独立 Review 六轨。V1 先读 canonical 数据；只有 1k/10k/50k 性能门禁不达标时才建立 SearchIndex/FTS migration 计划。同步更新 `docs/index.md`、`docs/status/current.md` 和 `docs/status/roadmap.md`，移除“搜索无 active 计划”的过期状态。
- 验证状态：计划共 594 行、标题层级与代码围栏结构检查通过；所有用户冻结关键词、历史长按语义、`SPECIALIST_SPLIT`、Contract/性能/FTS 门禁和文档导航入口定向检索通过；受影响文档 `git diff --check` 无 whitespace error，仅有工作区既有 LF/CRLF 提示。未运行 Contract validator、C++、Flutter、Android 构建或测试，因为本轮仅建立计划且未实施生产代码；工作区原有 Habit/Contract/C++/Android/Flutter 在途修改均未触碰。
- 开发时间：2026-08-31 14:43 +08:00（Asia/Shanghai）。

## 2026-08-31 14:14 +08:00 Habit 首次进入时区读取失败修复

- 使用 Skill：`debug`。
- 负责模块：Flutter 生产应用组合、Habit 首次路由时区初始化及对应 Widget 回归测试；未修改 Contract、Kotlin/JNI、C++ 或持久化实现。
- 任务目标：定位并修复安装或进程冷启动后首次进入习惯页面错误显示“无法读取设备时区，习惯功能暂不可用”，点击重试后才恢复的问题。
- 任务结果：确认根因是 `_ExcellentCalendarAppState.initState()` 在 `_timezoneGateway` 赋值前创建 `_habitTimezoneFuture`；Dart async 函数会同步执行到第一个 `await`，因此首次 `_resolveHabitTimezone()` 立即读取未初始化的 `late` 字段并以 `LateInitializationError` 结束，后续重试则因初始化已经完成而成功。现将 Habit 时区 Future 的创建移动到 `MethodChannelTimezoneAdapter` 初始化之后，不增加延时、不吞掉错误、不缓存或伪造时区，也不改变 `runtime.device_timezone` Contract。新增生产组合级回归用例，覆盖冷启动直接构建 Habit 路由、真实 MethodChannel 时区响应、错误页不得出现及 Habit 列表成功显示；该用例在修复前稳定失败且没有发出时区调用，修复后通过。
- 验证状态：Habit composition 4/4 通过；Flutter 全量 445/445 通过；`flutter analyze` 无问题；Debug APK 构建成功；`git diff --check` 无 whitespace error，仅有工作区既有 LF/CRLF 提示。已在 realme RMX5100 Android 真机覆盖安装 `.device_test` Debug 包，强制停止后冷启动，使用既有 Debug 登录入口进入 Habit，页面直接显示现有 9 条 Habit，时区错误与重试页均未出现，logcat 未发现 `LateInitializationError`。未卸载或清除应用数据，避免删除设备现有 Habit，因此“绝对全新安装/清数据”场景仍未单独执行，但本次根因属于每次 State 初始化都会触发的确定性时序错误，已由修复前后回归和真机进程冷启动双重覆盖。
- 开发时间：2026-08-31 14:14 +08:00（Asia/Shanghai）。

## 2026-08-31 14:38 +08:00 日历月周分类视图独立 Review 计划

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`；本轮只制定未来审查规范，不审查当前 Calendar 实现、不形成 Finding 或通过结论。
- 负责模块：Calendar 月/周分类视图、Event occurrence、Habit 日状态、Anniversary occurrence 的只读聚合 Contract、C++/SQLite、Kotlin/JNI、Dart/Flutter、真实 production composition 和独立发布验证计划。
- 任务目标：依据已冻结日历总计划，提前建立开发期 readiness 自检和完工后正式 Review 的详细规范，重点覆盖现实项目中高发的 date/datetime 错日、半开边界、recurrence overlap、混合 snapshot、cursor 漏重、异步 stale response、N+1、手势竞争、Fake 生产链、测试 oracle 污染和设备验证缺口。
- 任务结果：新增 `docs/reviews/active/日历-01-月周分类视图-review计划.md`，明确 Review 尚未开始；建立启动条件、发布红线、分阶段执行流程、Contract/snapshot、时间/occurrence、三类投影、cursor/cache、C++/SQLite、Kotlin/JNI、Flutter 手势/无障碍、共享回归、独立测试矩阵、测试失真模式、Finding 格式和 PASS 门禁。计划同时吸收项目 Anniversary/Habit 历史评审经验及 RFC 5545、Google Calendar、SQLite、Flutter、Android 官方工程实践。同步勾选日历主计划 Track 6 的 Review 文档任务，并更新文档索引入口。
- 验证状态：完成文档结构、关键风险关键词、主计划路径和 Review 状态自检；未运行 Contract validator、C++、Flutter、Android 构建或业务测试，因为本轮只制定计划且 Calendar 尚未实施。当前工作区既有 Habit/Contract/C++/Android/Flutter 大量修改均未触碰；正式 Review 仍须等待 Contract、分层实现、真实 production composition 和清晰 baseline 完成。
- 开发时间：2026-08-31 14:38 +08:00（Asia/Shanghai）。

## 2026-08-31 15:15 +08:00 Habit 最终发布验收

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。
- 负责模块：Habit/HabitCheckIn、Appearance、Reminder/Notification、Flutter → Kotlin → JNI → C++ → SQLite v5 的发布候选审查；本轮不修复生产代码，不修改 Contract capability 状态。
- 任务目标：依据冻结的 Habit 主计划，对当前脏工作树执行独立黑盒、分层自动化和 Android 真机验收；仅在全部门禁通过且不存在缺陷时解除阻断。
- 任务结果：结论为 `CHANGES_REQUIRED / RELEASE_BLOCKED`。发现创建页默认期限实际为 21 天（`HabitFormController` 将结束日初始化为开始日加 20 天），与主计划“默认期限为 30 天”及黑盒矩阵已勾选的“创建默认 30 天”冲突；真机创建也实际显示并保存 21 个计划日。生产链其它已执行场景通过：从日程页“更多”进入 Habit、四项底部导航保持不变、创建完成型 Habit、快捷打卡/撤销、卡片完成率与连续天数更新、详情/历史展示、本机 SQLite v5 持久化、通知权限关闭后的详情提示、已过提醒时间的同日补发，以及系统通知“完成” action 直接写回 CheckIn。真实设备 instrumentation 已执行并通过 production Habit JNI 11/11 导出、Unicode create/get/list/delete 与 SQLite v5；测试专用 Fake smoke 通过。由于默认期限缺陷以及设备重启/跨午夜/时区与系统时间变化/数量型通知 action/真实 TalkBack 等强制设备矩阵仍未闭环，未把 Habit/Appearance MethodChannel、Native call、identity 或 Storage v5 从 `planned + blocked` 改为 active。
- 验证状态：Habit Contract validator 通过（194 schemas、46 fixtures、4 identity vectors、12 public methods、11 native calls）；Anniversary 回归 validator 通过；C++ `excellent_calendar_check` 构建后 10/10 通过；Flutter format 无变化、analyze 无问题、445/445 测试通过、Debug APK 构建成功；Android unit/lint/androidTest APK 组合构建成功；Native smoke 1/1、analyze 与 Debug APK 通过；realme RMX3687 Android 13 真机 production Habit instrumentation 通过。发布候选 Debug APK SHA-256：`1B247DF9C35F544D91F058CEF6DC30C7F938FCC253C8F94419ADCAB68873F543`。未验证项：设备重启、系统杀进程后的 action、跨午夜、时区/系统时间变化、数量型通知 action、重复/陈旧 action、通知点击详情、TalkBack；因此不得报告发布完成。
- 开发时间：2026-08-31 15:15 +08:00（Asia/Shanghai）。

## 2026-08-31 15:30 +08:00 Habit 默认 30 天期限修复

- 使用 Skill：`debug`、`frontend-flutter-feature`。
- 负责模块：Flutter Habit 创建表单 Controller、页面测试注入点、Application/Widget 回归测试；未修改 Contract、C++、Kotlin/JNI、SQLite 或 Habit 上位主计划。
- 任务目标：复核并修复新建 Habit 默认显示和提交 21 个计划日、与冻结计划默认 30 天冲突的问题，同时补齐默认总天数、结束日期和创建请求的稳定回归证据。
- 任务结果：确认问题真实存在。根因是 `HabitFormController` 默认结束日期使用 `addDays(20)`，而 `plannedDays` 按首尾日期计数，导致默认范围只有 21 天。回归测试在修复前稳定得到 `2026-08-28 → 2026-09-17` 并失败；现将默认偏移最小修正为 `addDays(29)`，恢复含首尾共 30 个计划日。表单页新增可选 `initialStartDate` 注入以支持确定性 Widget 测试，不改变生产默认调用；Controller 测试同时断言起止日期、30 天总数和最终 `CreateHabitRequestDto`。原“21 天”快捷项仍正确使用 `addDays(20)`，经窄范围搜索确认没有第二个同类默认值错误。主计划黑盒项本轮未改写；修复和回归通过后，其默认 30 天 `[x]` 现已有真实自动化依据。
- 验证状态：修复前 Habit 定向回归按预期失败 2 项；修复后 Habit Application/Widget 定向 31/31 通过；Flutter 格式检查 390 文件/0 变化、`flutter analyze` 无问题、全量 447/447 通过、Debug APK 构建成功。未重复执行真机创建；本次为纯 Flutter date-only 默认值修复，既有真机系统行为矩阵缺口仍不因此解除。
- 开发时间：2026-08-31 15:30 +08:00（Asia/Shanghai）。

## 2026-08-31 15:50 +08:00 Habit V1 发布状态激活

- 使用 Skill：`frontend-flutter-feature`、`calendar-data-contracts`。前者用于确认默认 30 天修复及 Flutter 回归，后者用于同步跨层 capability、identity、Schema 与 Storage v5 的机器发布状态。
- 负责模块：Habit/Appearance MethodChannel 与 Native call、Habit/Appearance Schema、Habit identity/lifecycle matrix、Calendar Core Storage v5、Habit validator、Contract 说明、Habit 当前状态/路线/索引/主计划与开放问题；未修改 C++、Kotlin/JNI 或 Android 生产逻辑，未处理其它模块问题。
- 任务目标：按产品负责人明确决定，将尚未闭环的真机发布矩阵和局部计划/ADR 状态漂移登记为后续统一处理的非阻断债；在确认不存在其它阻断级问题后，把 Habit V1 开发结果切换为发布态。
- 任务结果：新增 `OPEN-HAB-001`，逐项记录已通过与仍未验证的真机系统行为，并明确“接受发布债不等于测试通过”；新增 `OPEN-HAB-002`，记录真实 instrumentation 复选框与两个 Habit ADR 的局部状态尾债。默认 30 天缺陷已由当前 Flutter 改动修复并有请求级回归。10 个 Habit 公共方法、2 个 Appearance 本机方法、11 个 Habit internal call、37 个 Habit/Appearance Schema、Habit identity/lifecycle matrix 统一切换为 `integrated + active`；Calendar Core 顶层 writer 从 v4 切换为 v5，同时保留冻结 v4 节点及其 SHA-256 迁移输入约束。主计划、current、roadmap、index 和 Contract README 已同步发布结论；按用户要求未伪造未执行设备项，也未在本轮清理两个 ADR/分计划归档尾项。
- 验证状态：Habit validator 通过（194 schemas、46 fixtures、4 identity vectors、12 public methods、11 native calls，`status=integrated+active`）；Anniversary 共享回归通过（194 schemas、56 fixtures、20 identity vectors）；C++ 重新 configure 后 `excellent_calendar_check` 构建后 10/10；Flutter 默认 30 天专项测试通过、格式检查 2 文件/0 变化、全量 447/447、analyze 无问题、Debug APK 构建成功；Android `testDebugUnitTest`、`lintDebug`、androidTest APK 构建成功；Native smoke 1/1、analyze 与 Debug APK 通过；`git diff --check` 无 whitespace error。发布 Debug APK SHA-256：`7E84981ADB102447C8C738F5963FBEA086708985E1D60C4E67709380F18FE103`。本轮未重复执行实机矩阵；此前已通过的 production JNI/SQLite v5 与实机主链路证据继续有效，剩余场景严格保留在 `OPEN-HAB-001`。
- 开发时间：2026-08-31 15:50 +08:00（Asia/Shanghai）。

## 2026-08-31 16:04 +08:00 Habit 重大架构决策收录

- 使用 Skill：`calendar-data-contracts`。
- 负责模块：Habit ADR、架构概览决策索引、项目文档索引，以及与 ADR 状态直接相关的 `OPEN-HAB-002`；未修改 Contract、业务代码、测试或其它模块决策。
- 任务目标：结合 Habit 总计划及 Contract、C++、Kotlin、Flutter 分层计划，从本次开发中筛选 2–4 项最可能影响后续开发的稳定决策写入 `docs/architecture/decisions/`。
- 任务结果：最终保留三项决策主题。ADR-Habit-01 固化 Habit 定义与 CheckIn 事实分离、统计动态投影和百分位整数；ADR-Habit-02 固化 date-only 每日挑战、确定性 Reminder/Occurrence/action identity、同日补发及 C++ 事务仲裁；新增 ADR-Habit-03，固化 Contract-first 同 APK 升级、C++/SQLite v5 单一真相源、v4→v5 原子迁移和 production 禁止 Fake fallback。两个旧 ADR 的实施状态已校准为 Accepted/Implemented，Architecture Overview 和 `docs/index.md` 已加入第三个 ADR；`OPEN-HAB-002` 仅保留计划/Review 归档尾项。未把页面入口、卡片样式、预设颜色等可调整产品选择升级为 ADR。
- 验证状态：三个 Habit ADR 状态与路径检查通过；新增 ADR 被架构概览和项目索引引用；Habit Contract validator 继续通过；受影响文档 `git diff --check` 无 whitespace error。纯文档/决策任务未重跑 C++、Flutter 或 Android 构建，沿用 15:50 发布激活记录中的完整构建证据。
- 开发时间：2026-08-31 16:04 +08:00（Asia/Shanghai）。

## 2026-08-31 16:07 +08:00 Habit 高价值缺陷经验归档

- 使用 Skill：`debug`。
- 负责模块：Habit 开发期问题复盘、`docs/issues/resolved/` 经验归档及 resolved 索引；未修改 Contract、生产代码、测试或 capability 状态。
- 任务目标：结合 Habit Contract、分层实现、白盒 Review、黑盒反馈、发布验收和首次启动缺陷，不按表面严重程度机械排序，选出两条对后续开发最有指导价值的问题并归档。
- 任务结果：新增 `docs/issues/resolved/08-habit-implementation.md`，对本轮主要问题分类评估并说明未入选原因。最终归档 `RES-HAB-002`“调度回调未在副作用前重验目标业务合法性”，沉淀 Alarm/WorkManager/恢复回调只是可能陈旧的提示、Android 先编排 reconciliation 且 C++ 在事务内做最终当地日期裁决的通用约束；归档 `RES-HAB-003`“将 civil date 当作 24 小时时长导致 DST 错日”，沉淀 Contract `date` 必须保持年月日值类型、禁止本地 `DateTime + Duration(days)` 代替日历日运算的通用约束。批次 continuation 被评为高价值首要候补；首次进入页面的 `late` 初始化顺序错误虽然用户影响直接，但可迁移经验较弱，未因表面阻断级别占用名额。同步更新 resolved README 入口，并明确跨午夜真机矩阵仍由 `OPEN-HAB-001` 跟踪，resolved 代码缺陷不冒充设备场景已验证。
- 验证状态：`RES-HAB-002/003` 编号全仓唯一性检查通过；两条记录引用的 Kotlin/C++/Flutter 实现、测试和 Open Issue 路径均存在；resolved README 链接检查通过；新文档和既有 tracked 差异均无 whitespace error，仅有工作区既有 LF/CRLF 提示。纯文档复盘未运行 Contract validator、C++、Flutter 或 Android 测试与构建。
- 开发时间：2026-08-31 16:07 +08:00（Asia/Shanghai）。

## 2026-08-31 17:59 +08:00 搜索四层计划拆分与 Search V1 Contract 冻结

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`；前者用于由总工程师亲自冻结 Search 的 wire、date/datetime、occurrence、cursor、history CAS 与兼容边界，后者用于按 C++、Kotlin/JNI、Flutter 三个可并行执行面完成只读盘点和最终集成门禁拆分。
- 负责模块：搜索主计划、Search 领域说明、Contracts/Schema/enum/error/capability map/fixture/validator，以及 C++/SQLite、Kotlin/JNI/本地历史、Flutter 聚合页面三份派发计划；本轮未实现或改写三个下层的生产业务代码。
- 任务目标：把已冻结的三类聚合搜索总计划拆成 Contracts、C++、Kotlin、Flutter 四个清晰责任面，由总工程师完成核心 Contracts，并为三个下层建立能独立派发、最终统一合并的实施与验收入口；Flutter 计划额外冻结现代视觉、动效、无障碍和 production composition 要求。
- 任务结果：完成 `搜索-02` Contract 计划并冻结 `search.query`、两个 Kotlin-local history 方法、12 个 Search Schema、6 个 Search 错误、4 组 enum、23 组 schema/semantic/golden fixture 与专项 validator。明确 `query_generation` 为 wire safe-integer 且 response 原样回显；冻结 Unicode whitespace、ASCII-only fold、token AND、Category 三态、三类 typed projection、date/datetime occurrence、相关度/排序、独立分页与 snapshot-bound cursor、本地历史 revision CAS 和 Android backup/device-transfer 排除。V1 保持 SQLite v5 不变，不引入 FTS/SearchIndex migration。新增 `搜索-03/04/05` 三份下层计划，其中 Flutter 单列视觉系统、组件密度、类型色、高亮、staged filter、1s debounce、竞态防护、微动效、Reduced Motion、无障碍及 Golden/Widget 验收。主计划、领域说明、文档索引和当前状态已同步；Search capability 保持 `planned + blocked`，等待三层完成后由总工程师统一真实接线、性能门禁与发布 Review。
- 验证状态：Search validator 通过（213 schemas、23 fixtures、3 public methods、1 native call、FTS deferred）；Calendar View 回归通过（213 schemas、19 fixtures）；Habit 回归通过（213 schemas、46 fixtures、4 identity vectors、`integrated+active`）；Anniversary 回归通过（213 schemas、56 fixtures、20 identity vectors）。计划路径和机器入口存在性检查通过；`git diff --check` 无 whitespace error，仅有工作区既有 LF/CRLF 提示。工作区中并行存在的 Calendar/Habit/Anniversary/C++/Android/Flutter 在途改动均保留，未被回滚或格式化。
- 开发时间：2026-08-31 17:59 +08:00（Asia/Shanghai）。

## 2026-08-31 19:55 +08:00 Calendar View R1 四层实现与总工程师汇整

- 使用 Skill：`calendar-data-contracts`、`cpp-core-feature`、`android-kotlin-native-feature`、`frontend-flutter-feature`、`cross-layer-feature`、`review-worktree-architecture`。总工程师亲自完成 Calendar Contract/机器不变量与最终状态汇整，并按 C++/SQLite、Kotlin/JNI、Flutter 三个独立责任面派发实现，最后执行跨层接线和独立复读。
- 负责模块：`calendar.range_summary`、`calendar.list_day_items` 的八个 Schema、十九组 fixture、错误/枚举/capability/validator；C++ Calendar Query Service、SQLite v5 read snapshot、九 Store generation、固定 Clock、三类投影与 keyset cursor；Kotlin Handler/Bridge/JNI/三 ABI；Flutter CalendarPage、Controller、缓存/分页/路由、Material 3 视觉/动画/无障碍；四份分层计划、Calendar domain、当前状态与正式 Review。
- 任务目标：把日历总计划拆成 Contracts、C++、Kotlin/JNI、Flutter 四份可执行计划；由总工程师完成关键 Contracts，统筹下层实现，并将真实 Flutter→MethodChannel→Kotlin→JNI→C++→SQLite 链、测试和状态统一汇整。
- 任务结果：四层代码与 production composition 已落地。C++ 使用同一 SQLite read transaction 读取九个贡献 Store/generation，snapshot 固定 evaluation Clock，cursor 绑定完整查询与排序，无 Calendar 表/writer/Storage migration；Flutter 已替换占位 Tab，完成月周网格、三类圆点/卡片、独立分页、缓存刷新、三类创建/详情回跳、主题派生视觉、160–260 ms 动效、reduce-motion、360dp/200%/深浅色与 Semantics。独立 Review 发现的 Habit 数量关系、civil-date DST、section 起手手势、inactive 跨午夜/时区和状态文档漂移均已返修，最终无开放 P0/P1/P2/P3，结论 `PASS WITH RISKS`。机器状态统一为 `implemented_unintegrated + blocked`，未提前激活。
- 验证状态：Calendar validator 通过（213 schemas、19 fixtures、2 public methods、2 native calls），Anniversary 56 fixtures/20 identity vectors 与 Habit 46 fixtures/4 identity vectors 回归通过；C++ 构建后 `excellent_calendar_check` 11/11，独立 Calendar test 1/1，Release host stress P95 为 range42 `126.54 ms`、Event20 `157.33 ms`、三 section `406.72 ms`；Android Calendar 定向 16 项、全量 unit、lint、Debug 主/测试 APK、三 ABI/JNI symbols 通过，既有 Android 13 production 只读 smoke 通过；Flutter 定向 76 项、全量 535 项、analyze、Debug APK 通过。最终 Debug APK 为 204023430 bytes，SHA-256 `759D59849330624B1C031C0EE47A464BA390BED60EC58693A619E75B69D601AD`。`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 未验证与阻断：ADB 当前无设备，新安全 `CalendarSeededIntegrationSmokeRunner` 的“只读 → Event/Habit/Anniversary seed → 只读”真机序列未执行；同一 APK 真实三类 UI、真机手势/TalkBack/动态主题/200% 字体、进程恢复、设备时区/DST 与 Android 16 参考性能未闭环；Release Flutter/native 三 ABI 已编译，但最终 Java 打包被既有 release classpath 缺少 `integration_test` plugin 阻塞。Contract bootstrap runner 因本机代理不能重装已清理的临时依赖，已使用仓库现存隔离环境直接执行同一 validator 并通过。主计划、四份分层计划和 Review 保持 active，不归档。
- 工作树保护：并行 Search Contract/docs 及用户原有 Habit active→completed 计划移动均保留，未回滚、覆盖、归因或整理。
- 开发时间：2026-08-31 19:55 +08:00（Asia/Shanghai）。

## 2026-08-31 21:00 +08:00 Search V1 开发前复核与 Contract Revision 2

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`。前者用于由总工程师修订跨 Dart/Kotlin/C++ 的机器协议与共享 Event 真相源，后者用于同步主计划及 C++、Kotlin/JNI、Flutter 三份下层派发计划；本轮未实现三层生产业务代码，也未激活 Search capability。
- 负责模块：`contracts/search/` 的 12 个 Search Schema 与不变量、Search fixture/validator、Search domain/Contract README、搜索-01/02/03/04/05 计划、文档索引与当前状态；保留工作区既有 Calendar/Habit/C++/Android/Flutter 修改。
- 任务目标：复核“Contract Frozen / Downstream Ready”是否过早，逐项判断 Event occurrence、状态、当地日期/DST overlap、分页守恒、history 触发与 revision、cursor 认证、前台跨午夜/时区以及主计划状态漂移，并对真实问题做定向补强。
- 任务结果：确认所有提出的技术缺口真实存在，但不需要推倒重做。撤回从未投产的 Search Revision 1，冻结 Revision 2：范围内 Event 改回“资格过滤后最近 occurrence”，open 不再优先；Event 五态逐字段对齐 Calendar Contract，补齐 reopen、ongoing distance、timed/all-day、跨午夜/多日和 TZDB gap/fold 规则；page size 固定 20，并新增实际 Schema request-response pair/cursor-chain 守恒，覆盖缺 section、提前 terminal、跨页重漏、cursor 不前进与 total/timezone/evaluated_at/snapshot 漂移；cursor/snapshot 固定为每进程 OS-CSPRNG key 的 full-tag HMAC-SHA-256、独立 domain、canonical Base64URL 与 constant-time 验签，禁止 FNV/Calendar checksum 复用；history 改用 `AtomicFile + noBackupFilesDir`，冻结 durable success 后才发布内存快照、revision 上界 fail-closed 及键盘/历史点击/结果打开的记录时机；Flutter 计划补齐 resume、当地午夜和前台最多 60 秒时区 guard。31 组 fixture 新增原始反例、23h/25h 日、午夜 gap/fold、HMAC tamper/旧进程 key 和 history 上界向量。搜索-02 标记为 `Contract Frozen Revision 2 / Downstream Ready`，搜索-03/04/05 仍为 Not Started；Track 5 继续是总工程师正式集成/设备性能/能力激活门禁。
- 验证状态：Search validator 通过（213 schemas、31 fixtures、3 public methods、1 native call、`planned+blocked`、FTS deferred）；Calendar View 回归通过（213 schemas、19 fixtures）；Habit 回归通过（213 schemas、46 fixtures、4 identity vectors、`integrated+active`）；Anniversary 回归通过（213 schemas、56 fixtures、20 identity vectors）；Search validator `py_compile` 通过；`git diff --check` 无 whitespace error，仅有工作区既有 LF/CRLF 转换提示。标准 bootstrap runner 被本机旧 Python/pip 的系统代理异常阻断，已使用满足 `requirements-validation.txt` 版本范围的隔离 Python 3.12 依赖直接运行同一 validator；这是环境入口问题，不是 Contract failure。
- 开发时间：2026-08-31 21:00 +08:00（Asia/Shanghai）。

## 2026-09-01 13:08 +08:00 Search V1 Flutter 聚合搜索页面开发

- 使用 Skill：`frontend-flutter-feature`。
- 负责模块：`flutter_client/lib` 与 `flutter_client/test` 内的 Search typed boundary、MethodChannel adapter、Gateway、Controller/History/Civil Clock coordinator、Material 3 聚合搜索页、筛选与结果组件、详情 route outcome、底部 Search Tab 及相关测试；按项目规则仅额外追加本日志。
- 任务目标：严格实施 `docs/plan/active/搜索-05-Flutter聚合搜索页面开发计划.md`，基于 Search Contract Revision 2 落地三类聚合搜索的 Flutter 分层、交互、视觉、竞态保护、本地历史协调与 production composition，不在 Dart 伪造 Native 搜索或激活 capability。
- 任务结果：已完成严格 DTO/Mapper 与错误映射、`SearchGateway`/`SearchHistoryGateway`、真实 `MethodChannelSearchAdapter`、独立 generation/section epoch/history revision 状态机、1 秒 debounce 与 IME composing/pending submit、三组独立分页/过期刷新/详情回流恢复深度、CivilDate 日期筛选与 resume/当地午夜/60 秒时区 guard、五组 staged filter 和 Category 三态、history CAS 串行写/冲突重试/回滚/清空撤销、深浅色/动效/reduce-motion/Semantics/200% 字体友好布局，以及 `ContentDetailRouteOutcome` 导航回流。`MainTabPage.searchBuilder` 为懒加载且 `IndexedStack` 保留会话状态；production 注入真实 adapter、Category repository 与 timezone source。Fake 仅位于 `test/`，运行时无 Fake/seed。当前结论为 **Layer Complete / Awaiting Integration**，Search capability 继续 `planned + blocked`。
- 验证状态：31 组 Revision 2 fixture 均由 Dart contract test 消费；Search contract/adapter/date/controller/widget/golden 定向测试通过，并覆盖 generation、section epoch、cursor/page size/total 守恒、history revision 冲突与写入失败、详情回流、懒加载会话保留；4 幅深浅色 history/ready/filter Golden 通过并完成视觉检查。`dart format --output=none --set-exit-if-changed lib test` 通过（445 文件、0 变化），`flutter analyze` 无问题，全量 `flutter test` 571/571 通过，`flutter build apk --debug` 成功产出 `build/app/outputs/flutter-apk/app-debug.apk`，`git diff --check` 无 whitespace error（仅工作区既有 LF/CRLF 提示）。
- 未验证与集成门禁：当前下层 Search Kotlin/JNI/C++/SQLite 尚未由本 Flutter 任务做真实集成，因此未在设备执行中文输入法、TalkBack、旋转/窗口、进程死亡/本地 history 持久化、真实三类 Flutter→MethodChannel→Kotlin→JNI→C++→SQLite 链路与设备性能矩阵；这些严格标记为 **未验证**，留给 Track 5 总工程师统一集成、正式 Review 和 capability 激活。
- 工作树保护：保留了开始时已存在的 Contract、C++、Android、Calendar 和其它在途修改；本次与 Calendar 共享的 `main.dart`、`app_router.dart`、`main_tab_page.dart`、`bottom_nav_bar.dart`、`bottom_nav_item.dart`、Event/Habit/Anniversary 详情页与相关测试为定向合并，未回滚或整理用户/并行工作内容。
- 开发时间：2026-09-01 13:08 +08:00（Asia/Shanghai）。

## 2026-09-01 13:08 +08:00 Search V1 C++ 与 SQLite 查询层完成

- 使用 Skill：`cpp-core-feature`。严格执行 `docs/plan/active/搜索-03-CPP与SQLite查询开发计划.md`，源码修改限制在 `cpp_core/**`，仅按项目要求追加本日志；未修改 Contract、Flutter、Kotlin/JNI、SQLite v5 schema/version 或 capability 状态。
- 负责模块：Search Unicode/匹配领域能力、`SearchQueryService`、Event/Habit/Anniversary/Category 只读投影、`SearchQueryRepository`、SQLite v5 deferred read snapshot、稳定排序/分页、HMAC cursor/snapshot、严格 Boundary/API、native runtime 注入、Core/Boundary/SQLite/性能测试。
- 任务目标：消费已冻结 Search Contract Revision 2，实现唯一 internal `search.query` 的 C++/SQLite 下层；保持旧 `event.search` 不变，不引入 FTS/SearchIndex writer/migration，并提供 Kotlin JNI 后续可调用的 `search_query_v2(std::string_view)`。
- 任务结果：完成冻结 Unicode White_Space、严格 UTF-8、128 scalar/512 bytes、ASCII-only fold、跨字段 token AND、7 级相关度和 200-scalar snippet；在一个 deferred SQLite transaction 中按目标只读 `events/recurrence_versions/event_occurrence_states/categories`、`habits/habit_recurrences/categories`、`anniversaries/anniversary_recurrences/categories` 及 generation，相关 mutation 精确失效而无关 mutation不失效。三类 projection 复用现有 TZDB、有限 recurrence seek、Event occurrence UUIDv5、Habit lifecycle/百分位整数和 Anniversary leap identity；输出固定 section、精确 total、稳定 keyset pagination。cursor/snapshot 使用每进程 OS CSPRNG 32-byte Search-only key、独立 domain 的 full-tag HMAC-SHA-256、canonical Base64URL、constant-time tag compare 与 versioned length-prefixed binary；完整 query binding 以 Search-only HMAC digest 压缩，100 个 Category ID 仍满足 2057 字符 cursor 上限。runtime 保持单一 SQLite owner；旧 `EventService::search_events` 及其 endpoint/test 零改动。结果状态：`Layer Complete / Awaiting Integration`，Search capability 仍应保持 `planned + blocked`，等待 Kotlin/JNI、Flutter 与总工程师最终集成。
- 验证状态：Search Contract validator 通过（213 schemas、31 fixtures、3 public methods、1 native call、Revision 2、`planned+blocked`、FTS deferred），并已纳入 CTest；默认构建执行 `cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON` 与 `cmake --build cpp_core/build-ninja --target excellent_calendar_check`，13/13 全部通过。真实 SQLite 测试确认 target-only load、同 snapshot facts+generation、Event/Habit/Category generation 失效边界及查询前后 DB bytes 零变化；Boundary 覆盖 valid/invalid Contract fixture、missing/extra/null/type/enum/date/safe integer/cursor/UTF-8，Core 覆盖 Unicode、跨字段相关度、DST 23h overlap、all-day 状态、recurring occurrence 选择、2100 leap、pagination、tamper/domain/旧 key、query mismatch。最终 Release 性能原始摘要：1k cold `11.891 ms`/warm P50 `11.482 ms`/P95 `12.128 ms`/peak `21,221,376 B`；10k cold `123.024 ms`/P50 `122.061 ms`/P95 `123.814 ms`/peak `71,979,008 B`，满足 ≤300ms；50k cold `637.992 ms`/P50 `617.411 ms`/P95 `653.464 ms`/peak `290,299,904 B`，无卡死/OOM。三档均为 18 条只读 SQL、candidate 守恒；本次小时级长 recurrence 实测每个 Event 检查 6 个邻域候选，一般上界为“事件跨度折算的 recurrence 数 + 该系列 occurrence-state 数量的两倍 + 6”，不随 anchor 到查询窗口的距离增长。未验证 Kotlin/JNI、Flutter、Android 设备、端到首屏 ≤500ms 与真实设备内存；这些属于后续分层/集成门禁。
- 开发时间：2026-09-01 13:08 +08:00（Asia/Shanghai）。

## 2026-09-01 16:06 +08:00 Search V1 三层生产汇整与主机集成验收

- 使用 Skill：`cross-layer-feature`、`calendar-data-contracts`。前者用于核对并汇整 Flutter → MethodChannel → Kotlin → JNI → C++ → SQLite v5 的真实生产链路，后者只用于修复集成前发现的 Search History Contract 元数据漂移并增加机器防回归门禁。
- 负责模块：Search production composition、MethodChannel/Handler/JNI/API/runtime 接线、本机 AtomicFile History、三 ABI 符号与 APK 组合、跨层回归及性能复核；未修改 Calendar/Habit/Anniversary 的领域行为、SQLite schema/version、旧 `event.search`、依赖版本或 FTS/SearchIndex。
- 任务目标：在搜索-03/04/05 均回报 `Layer Complete / Awaiting Integration` 后，由总工程师保护共享脏工作树并完成三层汇整，确认生产 Search 使用真实 canonical SQLite 数据、运行时没有 Search Fake/seed，并依据 Track 5 证据决定是否允许激活 capability。
- 任务结果：真实链路已闭合为 `SearchPage/SearchController → MethodChannelSearchAdapter → SearchMethodHandler → nativeQuerySearchV2 → search_query_v2 → 进程级 SearchQueryService → 同一 SQLite v5 runtime`；History 固定留在 Kotlin `SearchHistoryStoreProvider → AtomicFileSearchHistoryStore(noBackupFilesDir)`，没有 JNI/C++/SQLite History 入口。生产组合中未发现 Search Fake/seed，测试 Fake 保留在 `flutter_client/test`；Search Tab 的旧占位分支在 `buildProductionApp` 组合中不可达。确认 `contracts/method_channels.yaml` 两条 History 路径仍误写为 SharedPreferences，与 Revision 2 和实际实现冲突，现已改为 `atomic_file_search_history_store`，并在 Search validator 中冻结三条公开方法的完整 implementation path。三层生产代码已正确定向合并，无需为汇整重写业务规则或增加第二套事实源；Search V1 继续不启用 FTS。
- 验证状态：Search validator 通过（213 schemas、31 fixtures、3 public methods、1 native call），Calendar 19 fixtures、Habit 46 fixtures/4 identity vectors、Anniversary 56 fixtures/20 identity vectors 回归通过；C++ 重新 configure 后构建后 `excellent_calendar_check` 13/13。Release Search 性能复测：1k cold `11.584 ms`/warm P95 `11.019 ms`，10k cold `117.114 ms`/warm P50 `115.905 ms`/P95 `117.793 ms`（满足 ≤300ms），50k cold `583.768 ms`/warm P50 `574.491 ms`/P95 `587.600 ms`，三档均为 18 条只读 SQL，50k 未卡死或 OOM。Flutter 格式检查 448 文件/0 变化、analyze 无问题、全量 571/571、Debug APK 构建成功；Android Search 定向及全量 unit、lint、Debug 主 APK/androidTest APK 均通过。arm64-v8a、armeabi-v7a、x86_64 各恰好导出一个 `nativeQuerySearchV2`，History JNI symbol 为 0，Debug APK 包含三 ABI native 库；既有 Flutter Native smoke 格式/analyze/test/Debug APK 通过；`git diff --check` 无 whitespace error，仅有工作区既有 LF/CRLF 提示。
- 未验证与放行结论：`adb devices -l` 无 Android 设备，`flutter emulators` 也无可用模拟器，因此未执行安全 instrumentation 中已经准备好的三类 seeded 真实查询、AtomicFile `prepare → force-stop → restart` 恢复、同 APK UI/详情回跳、中文输入法/TalkBack/旋转/进程恢复及设备端请求到首屏 ≤500ms/1k-50k 性能矩阵。按主计划 Track 5，这些证据缺失时不得伪装完成发布，故 `search.*` 保持 `planned + blocked`；当前准确状态是 **Production Integrated / Host Verified / Awaiting Android Device Gate**。
- 工作树保护：保留并行 Calendar/Habit/Anniversary 及三层已有修改；本轮只定向修复 Search Contract 元数据/validator 并追加本日志，没有回滚、覆盖、格式化或归因用户已有内容。
- 开发时间：2026-09-01 16:06 +08:00（Asia/Shanghai）。

## 2026-09-01 18:08 +08:00 日历月/周分类视图独立 Review

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。前者用于按脏工作树、架构边界和独立黑盒 oracle 审查 Calendar 候选，后者用于核对 Calendar 跨层 Contract、九 Store snapshot、时间/重复/映射与兼容不变量；本轮未修改产品代码或测试。
- 负责模块：Calendar Contract/fixture、C++/SQLite Query Service、Kotlin/MethodChannel/JNI、Flutter Controller/Page/production composition，以及共享 Event/Habit/Anniversary/Reminder 边界；并行 Search 与用户既有 Habit 归档修改只在触及共享边界时纳入，没有回滚、整理或重新归因。
- 任务目标：依据 `docs/reviews/active/日历-01-月周分类视图-review计划.md` 对完成候选执行正式独立审查，不接受实现方自报 `PASS WITH RISKS` 作为 oracle，独立验证易错的自然日/DST、重复系列状态、snapshot/cursor、分页、异步缓存、JNI/ABI、真实 SQLite、性能与发布门禁。
- 任务结果：结论为 **CHANGES REQUIRED**。确认 1 个 P1：`CalendarViewQueryService` 对 `Event.status=completed` 的重复系列仍按无限 Recurrence 展开，且把 `completed_at` 之后新生成的所有未来 occurrence 投影为 `completed`；独立探针中系列于 `2026-08-15` 完成，查询 `2026-09-01` 仍返回 1 条新 occurrence。确认 1 个 P2：production Calendar 新建 Habit 复用应用启动时缓存的 `_habitTimezoneFuture`，而 Calendar 查询会在恢复时重新读取设备 timezone；设备时区变化后可用新时区浏览、却用旧时区创建 Habit。另确认 SQLite 每个公开调用都会读取/解码九个完整 Store，主机 Release stress 当前仍低于冻结阈值，因此保留为设备/规模风险而不另报 Finding。未修改现有 Review 文档中的实现方自报结论，最终独立结论以本次报告与日志为准。
- 验证状态：Calendar validator 通过（213 schemas、19 fixtures、2 public methods、2 native calls，`implemented_unintegrated+blocked`）；C++ 重新 configure 后构建后 `excellent_calendar_check` 13/13；Flutter Calendar 定向 83/83、全量 571/571、`flutter analyze` 无问题；Android Calendar JVM 16/16、`lintDebug`、Debug 主/测试 APK 通过，三 ABI 各导出 2 个 Calendar JNI symbol。独立 Release benchmark：typical P95 range/event/三 section 为 `13.66/16.84/44.56 ms`，stress 为 `129.64/156.17/415.14 ms`，均低于 `250/150/450` 与 `750/400/1200 ms` 门槛；Debug APK SHA-256 为 `87C8C296F0BD669B1CC0BEF0731B38E9D1D07BE8D8657DBE819722487B73DDFB`。`assembleRelease` 独立复现既有 `integration_test` release classpath 缺失而失败；`adb devices` 无设备，seeded 三类 UI、手势、TalkBack、进程恢复、设备时区/DST 和 Android 16 性能仍未验证。`git diff --check` 无 whitespace error，仅有既有 LF/CRLF 提示；临时独立探针及外部 Release build 目录均已删除。
- 开发时间：2026-09-01 18:08 +08:00（Asia/Shanghai）。

## 2026-09-01 18:09 +08:00 Search V1 三类聚合与本地历史独立 Review

- 使用 Skill：`review-worktree-architecture`。依据 HXY 分支当前 HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 冻结脏工作树范围，并由独立测试 oracle 先从 Contract、架构和 active plan 推导预期，再检查实现；本轮未修改产品代码或既有测试。
- 负责模块：Search Revision 2 Contract、C++/SQLite 查询与 recurrence 展开、Kotlin/MethodChannel/JNI/AtomicFile History、Flutter DTO/Controller/History/Page、production composition、跨层构建和发布门禁；Calendar/Habit 等并行变更仅在触及共享边界时分类，没有重新审查其独立功能。
- 任务目标：执行 `搜索-01-三类聚合搜索与本地历史-review计划.md`，核对计划偏差、跨层职责、Contract 充分性、实现完整性、历史并发、Unicode、分页/occurrence、性能证据、真实生产接线与设备放行条件。
- 任务结果：结论为 **CHANGES REQUIRED**。确认 3 个 P1：Flutter History CAS conflict reload 后未把当前用户操作重放到最新快照，会以旧 `_desired` 覆盖并发新增；Dart 使用 UTF-16 `String.length` 与运行时 `trim()/\\s`，不符合 128 Unicode scalar 和冻结 whitespace 集，合法的 128 emoji 与仅含 U+FEFF 的关键字/历史会在 Flutter 层被拒绝或改义；C++ recurrence 候选半径随 occurrence-state 数增长并最高循环到约一百万索引，违反 50k 不得百万级展开的门禁，而性能测试输出的 `sql_statements=18`、`recurrence_seek_observed_candidates=6` 是硬编码文本，未测得该最坏路径。另确认 2 个 P2：非 Search Tab 恢复 App 时 SearchPage 自行把 controller 设为 active，绕过 Tab 前台条件；当前 status/index 与搜索-01/03/04/05 仍写“占位/尚未实现/Not Started”，与已有三层 production 实现冲突，但 capability 因设备门禁未完成继续保持 `planned + blocked` 是正确的。未实施修复。
- 独立验证状态：Search validator 通过（213 schemas、31 fixtures、3 public methods、1 native call、`planned+blocked`），Calendar/Habit/Anniversary validator 回归通过；C++ 重新 configure 后 build-after-test `excellent_calendar_check` 13/13。独立 Release 性能复测为 1k P95 `11.562 ms`、10k P95 `121.100 ms`、50k P95 `627.940 ms`，当前普通数据通过，但测试数据未覆盖长 occurrence-state 历史，不能消除无界展开 finding；默认未优化构建的 10k P95 `370.604 ms` 不作为产品 finding。Flutter format/analyze/571 tests/Debug APK 通过；Android unit/lint/Debug APK/androidTest APK 通过；Native smoke analyze/test/Debug APK 通过。临时 Flutter 黑盒探针独立复现：history 并发新增 `gamma` 被下一次 replace 丢失，U+FEFF history 被 Dart DTO 抛出 `FormatException`；探针和独立 Release build 目录已删除，复核前后工作树清单一致。
- 未验证与放行结论：`adb devices -l` 无连接设备，因此 seeded 三类真实查询、force-stop 后 AtomicFile History、中文 IME、TalkBack、旋转/窗口、真实端到首屏 P95、设备 1k/10k/50k 与内存均未执行。即使修复上述 findings，也必须完成代表性 Android 设备门禁后才能激活 `search.*`；当前仍为 **Production Integrated / Host Verified / Changes Required / Awaiting Android Device Gate**。
- 开发时间：2026-09-01 18:09 +08:00（Asia/Shanghai）。

## 2026-09-01 18:42 +08:00 Calendar 独立 Review P1/P2 返修

- 使用 Skill：`debug`、`calendar-data-contracts`、`cpp-core-feature`、`frontend-flutter-feature`。按证据驱动流程先建立修复前失败回归，再冻结 completed 重复系列边界并分别修改 Contract、C++ 投影与 Flutter production composition。
- 负责模块：Calendar completed recurring-series 可见性、Calendar Query Contract/validator、C++ `range_summary/list_day_items` 统一投影、Calendar→Habit 创建时区接线及对应 C++/Flutter 回归；未修改 Kotlin/JNI、SQLite schema/version、Search 业务实现、依赖版本或 capability 状态。
- 任务目标：独立判断后续 Review 报告的“completed 系列继续生成未来 occurrence”P1 和“设备时区变化后 Calendar 新建 Habit 使用旧时区”P2 是否真实，并在真实存在时完成最小完整返修。
- 任务结果：两项均由修复前回归稳定复现。completed 系列冻结为 occurrence 锚点严格早于 `completed_at` 才保留：timed 使用 `occurrence_start_at`，all-day 使用 recurrence timezone 当地日初；精确等于截止点排除，截止前已开始的跨时/多日 occurrence 保留完整区间。该规则写入机器 invariant 和领域文档，并在 C++ 摘要/日列表共用同一过滤。Calendar 新建 Habit 改为进入创建页前重新读取真实设备 timezone，不再消费启动时 `_habitTimezoneFuture`。Review/主计划/current status 已校准为 Findings 已返修但等待独立复审；`calendar.*` 继续 `implemented_unintegrated + blocked`。
- 验证状态：修复前 C++ 回归失败于“锚点等于 completed_at 仍出现”，Flutter composition 回归实际提交 `America/Los_Angeles` 而非 Calendar 已刷新到的 `Asia/Tokyo`；修复后两项定向通过。Calendar validator 通过 `213 schemas / 19 fixtures / 2 public methods / 2 native calls`，Search 共享回归 validator 通过；重新 configure 后 `excellent_calendar_check` 13/13；`flutter analyze` 无问题、全量 575/575、`habit_composition_test.dart` 5/5，Debug APK 构建通过，SHA-256 `1D0E901CA4474C415022A63418FD3CF315BC306D3E09C391BFD0F6616EDB321D`。Android 设备复审、Release APK 和原发布设备矩阵仍未验证，不据此解除 blocked。
- 开发时间：2026-09-01 18:42 +08:00（Asia/Shanghai）。

## 2026-09-01 18:47 +08:00 Search V1 独立 Review findings 返修

- 使用 Skill：`debug`。按证据驱动流程先建立修复前失败回归，再在 Flutter boundary/application、C++ Search application/SQLite diagnostics 和 production composition 所属层实施最小修复；未升级依赖、Schema/SQLite version、FTS 或 capability。
- 负责模块：Search History CAS drain、Dart Search Unicode scalar/frozen whitespace、Search Controller/Page Tab×App lifecycle、C++ recurring Event occurrence-state seek、运行时 SQL/candidate 性能诊断、Search 分计划与当前状态校准；保护并行 Calendar/Habit/Anniversary 与用户既有脏工作树。
- 任务目标：独立判断 Search Review 的 3 个 P1 和 2 个 P2 是否成立，修复真实偏差并提供可供复审的失败前/通过后证据。
- 任务结果：四项代码 finding 均真实并已返修。History coordinator 由旧完整 `_desired` 重试改为 pending intent 队列，conflict reload 后在最新 committed 快照上按序重放；独立用例由错误 `[beta, alpha]` 修正为 `[beta, gamma, alpha]`。新增唯一 Dart `SearchTextContract`，严格扫描 UTF-16 surrogate、统计 Unicode scalar/UTF-8 bytes，仅按 Revision 2 冻结 whitespace 归一化并执行 ASCII fold；Request/Response/History/Controller/Page/highlight 共用，128 emoji 与 U+FEFF 边界通过。Search active 改为 Tab 可见与 App lifecycle 的合取，resume 不再覆盖非 Search Tab。C++ 不再以 state rows 作为展开半径，而把 state start 映射为 recurrence index、合并连续 closed/cancelled 区间，仅计算 seek 窗口和区间边界；10 万 state 回归实际只计算 22 个 occurrence，仍能找到第 100001 个开放 occurrence。性能测试的 SQL/candidate 输出改为运行时 diagnostics。Review 日志中可定位的第二个 P2 是计划/status/index 仍写占位/Not Started，现已校准；用户消息正文没有第五个代码 finding。
- 验证状态：修复前定向回归分别复现 History 覆盖、128 emoji 拒绝、U+FEFF 改义；修复后 Search Flutter 定向 30/30、`flutter analyze` 无问题、全量 Flutter 576/576、Debug APK 成功。C++ Search core（含 10 万 state）通过；Release 性能 1k/10k/50k warm P95 为 `19.091/120.749/569.948 ms`，三档实测 `sql_statements=18`、`recurrence_candidates=13`。Android `testDebugUnitTest + lintDebug + assembleDebugAndroidTest`、三 ABI CMake 与既有 Flutter Native smoke analyze/test/Debug APK 通过；`git diff --check` 无 whitespace error，仅有既有 LF/CRLF 提示。`adb devices -l` 仍无设备，seeded 查询、AtomicFile force-stop 恢复、IME/TalkBack/旋转/进程恢复和设备性能未验证。
- 新发现阻断：全套 C++ build-after-test 中 12/13 通过，唯一失败是 Search Contract validator。`contracts/calendar/calendar_query_invariants.yaml` 刚加入 `completed_recurring_series` cutoff，而 `contracts/search/search_query_invariants.yaml` 的 `event.status_projection` 尚未同步；validator 明确报 `Search and Calendar Event status projection drift`。本轮没有静默选择或修改该真相源，Search completed recurring-series 的 Contract 与实现对齐需单独授权/决策。故 Review 原四项代码 finding 可提交复审，但整体状态仍是 **Production Integrated / Host Verified / Review Findings Repaired / Contract Drift Blocked / Awaiting Independent Re-review & Android Device Gate**，`search.*` 保持 `planned + blocked`。
- 开发时间：2026-09-01 18:47 +08:00（Asia/Shanghai）。

## 2026-09-01 20:16 +08:00 Calendar P1/P2 返修独立复审

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。前者用于重新冻结当前脏工作树范围、从公开规则派生独立 oracle 并执行黑盒返修复审，后者用于核对 completed recurrence 的 occurrence/时区/半开边界及 Calendar→Habit 跨层时区事实源；本轮未修改产品代码或既有测试。
- 负责模块：`contracts/calendar/calendar_query_invariants.yaml`、`docs/domains/calendar_view.md`、C++ `CalendarViewQueryService` completed-series 投影、Flutter production Calendar→Habit composition 及直接回归；并行 Search/Habit 等修改仅在共享 Contract 回归处验证，没有回滚、整理或重新归因。
- 任务目标：不采用开发侧“已修复”自报结论，独立确认 P1“completed 重复系列仍产生未来 occurrence”和 P2“Calendar 新建 Habit 使用启动缓存旧时区”是否真实关闭，并保持设备/Release 发布门禁与代码 Finding 分离。
- 任务结果：两项 Finding 均独立关闭。C++ 共用判定以 timed `occurrence_start_at` 或 all-day recurrence timezone 当地日初为 anchor，执行严格 `anchor < completed_at`，且在摘要和日列表展开后、状态投影前一致过滤；等号和未来实例排除，截止前实例保留完整区间，显式 occurrence state 仍优先。Flutter Calendar→Habit 分支在导航前直接 `await _resolveHabitTimezone()`，不读取 `_habitTimezoneFuture`，提交使用本次刷新值。独立外部探针额外通过：前一日开始并跨到次日的 timed instance、两日 all-day instance、请求时区与 recurrence 时区不同的当地日初等号边界；探针源码和可执行文件已精确删除，复审前后工作树清单哈希均为 `d69ca00a1f08e251d1f133b006f4002a0ac52bef33c84387f4300fbf3ac33435`（追加本日志前）。代码复审结论为 **PASS WITH RISKS**，原 P1/P2 可标记 Closed；`calendar.*` 仍保持 `implemented_unintegrated + blocked`，不因本次复审自动激活。
- 验证状态：Calendar validator 通过（213 schemas、19 fixtures、2 public methods、2 native calls）；Search 共享 validator 同步通过（213 schemas、31 fixtures、3 public methods、1 native call）；C++ 重新 configure 后 build-after-test `excellent_calendar_check` 13/13；独立 C++ 黑盒探针通过；`habit_composition_test.dart` 5/5、`flutter analyze` 无问题、Flutter 全量 576/576、Debug APK 构建成功，SHA-256 `058FDEB262CB829B04A4CBD7ED32D6C60BCA9A18AA7F76EECE8F3D95936165B9`；`git diff --check` 无 whitespace error，仅工作树既有 LF/CRLF 提示。`adb devices` 仍无设备。
- 剩余风险与文档偏差：seeded 真机三类数据、真实 UI/手势/TalkBack/进程恢复、设备时区/DST、Android 16 参考性能和 Release Java 打包本轮未执行，原发布阻断保持。另发现 `docs/status/current.md:19,112,135` 与 `docs/index.md:228` 仍写 Search/Calendar status projection drift、Search validator 失败，但本次实际 Search validator 与 C++ 全门禁均通过；这是非 Calendar 代码修复的 P3 状态文档漂移，需由 Search/总工程师在其独立复审轨更新，不影响本次两项 Finding 的关闭。
- 开发时间：2026-09-01 20:16 +08:00（Asia/Shanghai）。

## 2026-09-01 20:28 +08:00 Search V1 Review findings 返修独立复核

- 使用 Skill：`review-worktree-architecture`。以 HXY HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 为基线重新冻结当前脏工作树，并由未读取实现的独立 oracle 先从 Search/Calendar Contract 与 active plan 派生 History、Unicode、lifecycle、长期 recurrence 和 completed-series 边界；本轮未修改产品代码或既有测试。
- 负责模块：Flutter Search History CAS、SearchTextContract/DTO/Controller/Page/highlight、Tab×App lifecycle、C++ Search recurrence seek 与 diagnostics、Search/Calendar Event completed-series Contract 闭包、计划/状态文档和主机/Android 构建门禁；并行 Calendar 复审修改只作为共享 Contract 事实读取，没有回滚或重新归因。
- 任务目标：独立确认上一轮 Search Review 的 3 个 P1、2 个 P2 是否真实修复，并判断总工程师新增的 Search/Calendar Event status projection 问题是否存在及其可行解法。
- 任务结果：上一轮四项代码 finding 均独立关闭。History conflict 已改为 pending intent 队列，reload 后在最新 committed 上按序重放；独立用例得到 `[beta, gamma, alpha]`。Dart 已统一使用 scalar/UTF-8/frozen-whitespace 工具，128 emoji 接受、129 emoji 拒绝、U+FEFF 保留；Controller/Page/highlight 不再使用平台 `trim/\\s` 作为 Search 规则。Search active 已变为 Tab selected 与 App resumed 的合取，非 Search Tab resume 不再激活。C++ 10 万连续 state 回归只计算 22 个 occurrence，Release 三档 diagnostics 为运行时值，原近百万 occurrence 展开与硬编码计数均关闭。原文档 P2 的“Not Started/占位”主状态已校准，但 `docs/status/current.md:86,135`、`docs/index.md:228` 及搜索计划头仍声称 Search validator 失败，`docs/status/roadmap.md:50` 还称 C++ P1 未修，形成新的 P3 状态文档漂移。
- 新问题判断：**底层语义问题真实，但总工程师报告的具体失败证据不准确。** 当前 `python contracts/run_search_v1_validation.py` 实际通过；validator 只比较 Calendar `status_projection` 子树，而新 `completed_recurring_series_cutoff` 是其兄弟节点，故不会报 drift。与此同时 machine Contract 确有欠规范/冲突：Calendar 要求 completed 系列只保留 anchor 严格早于 `completed_at` 的 occurrence，Search 未声明该 cutoff 且计划仍允许选择未来 occurrence。独立 C++ 黑盒探针在系列 `completed_at=2026-08-15T00:00:00Z`、查询时钟 `2026-09-01` 时实际选中 `2026-09-01`，若采用 Calendar/domain 的“系列彻底结束”语义，正确最后保留项应为 `2026-08-15`。因此应以 **Contract alignment blocker** 处理，在决策前不能把某一侧实现静默认定为唯一正确。
- 可行方案：推荐把 Search 显式对齐 Calendar cutoff：在 Search machine invariant 引用/复制完整 cutoff 闭包并加强 validator sentinel，抽取 C++ 公共 completed-series eligibility helper 供 Calendar/Search 共用，然后覆盖 timed/all-day、anchor `< / == / > completed_at`、跨区、跨时/多日、显式 state 与 `include_completed`。备选是明确规定 Search 采用不同的“历史系列模板”语义并新增独立 projection/导航 Contract，但会产生明显跨页面不一致，成本更高；临时方案可在完成决策前隐藏 completed recurring series，但会损失默认“包含已完成”能力，只适合作为阻断期 fail-closed，不宜作为最终语义。仅修改 validator 文案不能修复行为。
- 验证状态：Search/Calendar/Habit/Anniversary validator 均通过；C++ 重新 configure 后 build-after-test 13/13。独立 Release Search core 通过，10 万 state 为 22 candidates；性能 1k/10k/50k warm P95 为 `11.896/117.196/599.941 ms`，均为实测 `sql_statements=18`、`recurrence_candidates=13`。Flutter analyze 无问题，全量含 2 个临时独立 oracle 为 578/578（产品既有 576），Debug APK 通过；Android unit/lint/androidTest APK 与三 ABI CMake 通过。独立 completed-series C++ 探针按 Calendar cutoff 预期失败并稳定复现未来 occurrence；所有临时 Dart/C++ 探针、可执行文件和独立 Release build 目录均已精确删除。`adb devices -l` 无设备，真机门禁仍未验证。
- 工作树保护：初始清单为 255 路径；复核期间并行 Calendar reviewer 删除了其预先存在的 `.codex-review-calendar-rereview-probe.cpp` 并追加 20:16 日志，故本轮清理自身探针后为 254 路径。该并行变化不是本 Review 所为；除追加本日志外没有改变产品工作树。
- 开发时间：2026-09-01 20:28 +08:00（Asia/Shanghai）。

## 2026-09-01 20:57 +08:00 Calendar 真机黑盒与异常数据复核

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。以前者冻结 Calendar 范围、从需求/Contract 独立派生黑盒 oracle 并审查当前脏工作树，以后者核对自然日、重复 occurrence、snapshot/cursor、Habit 日状态和跨层时区边界；本轮只测试和报告，没有修改产品代码或既有测试。
- 负责模块：Calendar Contract、C++/SQLite Query Snapshot、Kotlin/JNI/MethodChannel、Flutter Controller/页面/三类创建入口、Android Debug 隔离包与真机 UI；并行 Search/Habit 改动仅在共享构建中回归，没有重新归因或回滚。
- 任务目标：在已基本完成的 Calendar 实现上执行主机与 Android 真机黑盒测试，通过真实三类数据、非法 Unicode timezone/超长 cursor、历史日期创建、月周切换、相邻月、今天、未开放按钮、详情导航和布局检查，判断是否仍有可行动问题。
- 任务结果：结论为 **CHANGES REQUIRED**，确认 3 项问题。P1：Calendar SQLite 九 Store 窄快照加载 `reminders` 却不加载 `reminder_recovery_batches`，随后对该不完整切片调用完整 `validate_recurring_event_state`；只要合法 Reminder 带 `recovery_batch_id`，Calendar 两接口即返回 `STORAGE_DATA_CORRUPTED / Reminder recovery batch is missing`，真机保留旧隔离数据升级安装后已实际复现，纯净数据才通过。P1：从历史日期进入“新建日程”会按要求预填历史日，但页面默认启用“15 分钟前”提醒，直接保存稳定失败为 `REMINDER_TIME_INVALID`；关闭提醒后同一日程可成功保存、出蓝点/卡片并进入详情，且失败提示直接泄漏英文错误码和 request id。P2：月视图的 overlay FAB 与滚动内容没有可靠避让，真机截图中覆盖空态说明和日程卡片右下区域，违反主计划“不得遮挡月历、卡片、加载更多或底部导航”的验收条款。此前 completed recurring cutoff 与 Calendar→Habit 当前时区两项返修均独立复核通过。
- 验证状态：Calendar validator 通过（213 schemas、19 fixtures、2 public methods、2 native calls）；重新 configure 后 `excellent_calendar_check` 13/13；Calendar C++ benchmark typical P95 为 `range42=38.71 ms / event20=50.09 ms / three sections=129.78 ms`，stress P95 为 `354.68 / 492.17 / 1204.20 ms`。Calendar Flutter 专项 83/83、Flutter 全量 576/576、`flutter analyze`、Android 重跑 Calendar unit、`lintDebug`、Debug APK 和 androidTest APK 均通过。Android 16 真机隔离包通过 production JNI 2/2、Unicode 非法时区、超长 cursor，以及真实 MethodChannel→JNI→C++→SQLite 三类 Unicode seeded 查询 `{event=1, habit=1, anniversary=1}` 并自动清理；手工完成周/月、左右滑月、相邻月日期、年月面板、今天、两个未开放提示、历史日期三类预填、Event 创建/圆点/卡片/详情。测试结束后已卸载 `.device_test` 与其 test 包，正式应用和正式数据未变更。
- 未验证：Release APK、TalkBack 实际朗读、系统 200% 字体/减少动画真机、设备时区/DST 切换、强杀/升级矩阵和 Android 参考设备 frame/heap 指标；其中 Widget 级 360dp/200%/深浅色/Semantics/减少动画测试已通过，不能替代上述设备门禁。
- 开发时间：2026-09-01 20:57 +08:00（Asia/Shanghai）。

## 2026-09-01 21:13 +08:00 Calendar 三项 Review Finding 返修

- 使用 Skill：`debug`、`calendar-data-contracts`、`cpp-core-feature`、`frontend-flutter-feature`。按复现证据定位首个错误边界，并分别在 C++/SQLite、Flutter Application 与页面布局所属层完成最小闭环修复。
- 负责模块：Calendar SQLite 九 Store 查询切片及 Reminder recovery 引用校验、Calendar 历史日期 Event 创建默认值与提交错误映射、Calendar 创建入口布局避让，以及对应 Contract/领域说明和回归测试；未修改 Kotlin/JNI、Storage schema/version、依赖或工具链。
- 任务目标：研判并修复三项外部 Review Finding：合法 recovery batch 引用导致 Calendar 全量失败、历史日期 Event 默认 15 分钟提醒无法保存、月视图 overlay FAB 遮挡卡片/空态/加载更多。
- 任务结果：三项 Finding 均确认真实并已修复。Calendar token 仍只覆盖冻结的九个 generation-contributing Store，但同一 SQLite read transaction 会额外只读 `ReminderRecoveryBatch` identity 作为关系校验辅助事实；专用 Calendar slice validator 放行合法引用，同时继续把真实孤儿引用判为 `STORAGE_DATA_CORRUPTED`，不会忽略所有恢复关系错误。历史日期仍按 Calendar 选择值预填，不强制改为今天，但页面默认设为“不提醒”；用户手动添加的已失效一次性提醒会在时区解析后、Native create 前被拦截，Native `REMINDER_TIME_INVALID` 及其他失败也映射为中文且不再暴露 code/request id。创建 FAB 改为参与 Scaffold 布局的底部操作区，普通与 200% 字体均不覆盖滚动正文。
- 验证状态：Calendar Contract runner 通过（213 schemas、19 fixtures、2 public methods、2 native calls，状态保持 `implemented_unintegrated + blocked`）；C++ 定向真实 SQLite 回归通过，覆盖合法 batch 引用与直接删除 batch 后的真实孤儿引用；重新 configure 后 build-after-test `excellent_calendar_check` 13/13；Flutter 返修定向 44/44、全量 580/580、`flutter analyze` 0 issue；360×800 Widget 矩形回归覆盖 Event 卡片、空态和加载更多，均与创建按钮不相交；最终 C++ 收口后重新构建 Debug APK 成功，SHA-256 `5D2738CE40D31A8C50B0A5F79FB9A8576578902835EB5CF16EA6B506383F10BB`；`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 剩余门禁：本轮未执行 Release APK、TalkBack 真机朗读、系统 200% 字体/减少动画真机、真机时区/DST、强杀恢复及完整升级矩阵；因此 Calendar 继续保持 `implemented_unintegrated + blocked`，不得据此解除发布门禁。
- 开发时间：2026-09-01 21:13 +08:00（Asia/Shanghai）。

## 2026-09-01 21:49 +08:00 Search 真机黑盒、异常数据与性能复核

- 使用 Skill：`review-worktree-architecture`。先依据 Search Contract Revision 2、领域不变量和 active 计划冻结独立黑盒 oracle，再审查当前 Search 跨层实现；本轮不修改产品代码或既有测试，只追加审查日志。
- 负责模块：Flutter Search 页面、筛选、1 秒防抖、历史管理和本地化；Kotlin AtomicFile/noBackup History 与 MethodChannel；JNI/C++/SQLite 三类聚合查询、分页/快照和性能；Android 16 隔离 Debug 真机流程。
- 任务目标：在搜索功能基本完成后，以黑盒和跨层异常输入验证三类聚合搜索、筛选、历史删除/清空/撤销、进程恢复、中文界面、数据规模和端到端真机链路，并给出缺口与修改方向。
- 任务结果：结论为 **CHANGES REQUIRED**。确认四项问题：P1，10k Search core warm P95 `399.315 ms`，超过 active plan 的 `≤300 ms` 门禁，50k 档因此未执行；P1，Android `search_seeded` 真机脚本把 Anniversary create 的直接 `AnniversaryDetailResponse` 错当成 `data.detail`，在三类 query 前失败且遗留已创建纪念日，导致真实 Event+Habit+Anniversary 端到端门禁不可用；P2，清空历史后的撤销条没有任何超时，独立 Widget 黑盒和 Android 16 真机均证明 30 秒后仍常驻，不符合“短暂撤销提示”；P2，应用未注册 Flutter 中文本地化 delegate/locale，Search 自定义日期选择器显示 `Save/Close/September/英文星期`，已应用筛选删除语义显示 `Delete`，不符合中文界面要求。
- 通过项：Search validator 通过（213 schemas、31 fixtures、3 public methods、1 native call，状态仍 `planned+blocked`）；C++ 重新 configure 后 build-after-test 13/13；Flutter Search 专项 39/39、全量 580/580、`flutter analyze` 0 issue；Android unit、lint、Debug APK、androidTest APK和三 ABI CMake 构建成功。Android 16 真机通过真实 Search 页面打开、1 秒停顿搜索、ASCII 不区分大小写、关键词高亮、纪念日分组、键盘提交写入历史、长按进入逐条删除、清空/撤销、仅纪念日筛选，以及 AtomicFile interrupted-write 强杀恢复。测试历史已撤销恢复，正式应用数据未清空。
- 未验证与边界：因 `search_seeded` 测试脚本自身失败，未获得三类真实 Store 同次查询和自动清理证据；50k 性能档被 10k 门禁提前中止；TalkBack 实际朗读、旋转/分屏、系统 200% 字体、设备时区/DST 切换和 Release APK 未执行。真机隔离 Debug 的本地测试登录不会跨进程保存，但不归因于 Search。
- 工作树保护：一次性独立撤销超时 Widget 用例稳定失败后已精确删除；未修复发现项。审查期间工作树存在并行任务变化，最终以当前状态重新核对，`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 开发时间：2026-09-01 21:49 +08:00（Asia/Shanghai）。

## 2026-09-02 11:10 +08:00 Search completed recurring-series cutoff 独立复核

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。以前者在 HXY HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 上冻结当前脏工作树、由未读取实现的独立 oracle 从公开领域规则与机器 Contract 派生测试矩阵并执行独立黑盒探针；以后者核对 completed series 的 timed/all-day anchor、严格截止、时区和显式 occurrence state 优先级。本轮未修改产品代码、Contract 或既有测试。
- 负责模块：`contracts/calendar/calendar_query_invariants.yaml`、`contracts/search/search_query_invariants.yaml`、Search validator、C++ `SearchQueryService` completed recurring Event 候选选择，以及相关 Search/Calendar 领域与 active plan 状态说明。
- 任务目标：核实总工程师报告的“Calendar cutoff 未同步、Search validator drift、C++ build-after-test 12/13”是否真实，并给出可行修复策略及利弊，不实施修复。
- 任务结果：**底层 Contract/行为问题真实，但报告的 validator/构建失败证据不真实。** Calendar 已冻结 `occurrence_anchor < completed_at` 的 completed-series cutoff；Search 只复用其同级的 `status_projection` 子树，未声明 cutoff。当前 validator 也只深比较 `status_projection`，因此 `python contracts/run_search_v1_validation.py` 实际通过，重新 configure 后 build-after-test 为 13/13，不是 12/13。独立静态 sentinel 因 Search `completed_recurring_series_cutoff=null` 按预期失败；独立 C++ 黑盒在 `completed_at=2026-08-15T01:00:00Z` 的每日 timed 系列上，于 `2026-09-01` 实际选择 `2026-09-01T01:00:00Z` 并投影 completed，证明 cutoff 后 occurrence 仍进入 Search。临时探针源码和可执行文件均已精确删除。
- 修复建议：首选让 Search 显式复用 Calendar 的完整 cutoff 闭包、让 validator 同时深比较 status 与 cutoff、在 C++ 抽取 Calendar/Search 共用 eligibility helper，并补齐 timed/all-day、`< / == / >`、request timezone 与 recurrence timezone、跨 cutoff 长区间、显式 completed/skipped/cancelled、`include_completed`、total/cursor 语义测试。Search 尚为 `planned + blocked` 且未发布，可选择 Revision 2 amendment（改动较小但审计性较弱）或 Revision 3 重新冻结（审计清晰但同步成本更高）。仅扩 validator 不能修复运行时；暂时隐藏全部 completed recurring series 只能作为有损 fail-closed；另立 Search-specific “历史模板”语义会造成 Calendar/Search 不一致和更高导航/维护成本。
- 验证状态：Search validator 通过（213 schemas、31 fixtures、3 public methods、1 native call）；Calendar validator 通过（213 schemas、19 fixtures、2 public methods、2 native calls）；C++ `excellent_calendar_check` 13/13；独立 Contract sentinel 与 C++ cutoff 黑盒均按预期失败并揭示覆盖缺口。未执行 Android 设备门禁，因为本任务只核实 Contract/C++ blocker，且设备验证不能替代该语义决策。
- 开发时间：2026-09-02 11:10 +08:00（Asia/Shanghai）。

## 2026-09-02 11:10 +08:00 Calendar 三项返修独立复审

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。重新冻结 HXY 当前脏工作树、Calendar Contract/领域/active plan 与跨层边界，先定义 recovery 引用完整性、历史日期创建、错误本地化和正文避让的独立 oracle，再审查实现并运行一次性黑盒探针；未修改产品代码或既有测试。
- 负责模块：Calendar C++/SQLite 九 Store 查询快照及 ReminderRecoveryBatch 辅助校验、Flutter Calendar 创建入口和 NewSchedule/Event 创建流程、Android Debug 主机门禁；Search 等并行改动仅随全量构建回归，不重新归因。
- 任务目标：独立验证 2026-09-01 21:13 报告的三项返修是否真实关闭，并继续检查边界和异常输入。
- 任务结果：原 Event recovery 合法引用/孤儿引用主路径、历史 timed Event 默认不提醒与失效提醒本地拦截、Native create 错误本地化、创建按钮正文避让均通过；但结论仍为 **CHANGES REQUIRED**。P1：SQLite 调用前先删除所有非 Event Reminder，Calendar 专用 recovery 引用校验因此看不到 Anniversary Reminder；独立真实 SQLite 探针在合法 Anniversary recovery 状态提交后直接删除 batch，`load_snapshot()` 仍成功并输出 `ANNIVERSARY_ORPHAN_ACCEPTED`，违反 `validation_support_stores` 对所有 Reminder 引用的完整性要求。P2：一次性失效提醒预检只位于 `!draft.isAllDay` 分支，历史全天 Event 手动恢复 15 分钟提醒仍调用 Native；独立 Flutter 探针期望本地 `validationFailure`/0 次 create，实际得到 `nativeFailure`/1 次 create。该页每小时最后 15 分钟还可能生成“下一整点 + 默认 15 分钟提醒”，提醒已失效，默认保存会被新预检拒绝。P3：设备时区读取、当地时间解析及响铃能力失败仍拼接 `${error.code}: ${error.message}`；独立探针得到 `TIMEZONE_READ_FAILED: native detail`，技术错误仍可直接展示给用户。
- 验证状态：Calendar validator `213 schemas / 19 fixtures / 2 public methods / 2 native calls` 通过且保持 `implemented_unintegrated + blocked`；C++ 重新 configure 后 build-after-test 13/13；Flutter 返修相关既有定向 47/47、全量 580/580、`flutter analyze` 0 issue；Android `testDebugUnitTest lintDebug`、三 ABI `assembleDebugAndroidTest` 与 `flutter build apk --debug` 通过。重建 Debug APK SHA-256 为 `6C88BAE8C243499181E40B016A61589E38799067E8BD322AB5F11DD5A4F58DBD`，与开发侧旧 Debug 产物哈希不同，不据此判断代码回归。两个临时 Flutter 探针和一个 C++/SQLite 探针均已精确删除。
- 未验证与门禁：`adb devices -l` 无设备，故同一 APK 真机 UI、Android 16 seeded recovery、TalkBack、系统 200% 字体/减少动画、设备时区/DST、进程恢复、参考设备性能与 Release 包仍未验证；发布 blocked 状态正确保留。
- 开发时间：2026-09-02 11:10 +08:00（Asia/Shanghai）。

## 2026-09-02 11:37 +08:00 Calendar recovery 与创建边界二次返修

- 使用 Skill：`debug`、`calendar-data-contracts`、`cpp-core-feature`、`frontend-flutter-feature`。以复审给出的触发条件建立独立失败回归，再分别在 Contract、C++/SQLite 与 Flutter Application/Presentation 所属层完成最小修复。
- 负责模块：Calendar 查询快照的全 Reminder recovery 引用完整性、一次性全天 Event 提醒的绝对时刻解析与失效预检、新建日程默认时间边界、创建流程时区/响铃错误本地化；未修改 Kotlin/JNI、SQLite schema/version、依赖或工具链。
- 任务目标：研判并修复 Anniversary Reminder 孤儿 recovery 引用漏检、历史全天提醒绕过本地预检及 `HH:45`/`23:xx` 默认时间失效、创建流程泄漏 Native 错误码三项复审 Finding。
- 任务结果：三项 Finding 均确认真实并已关闭。Calendar 现在先在未按 target 过滤的全部 Reminder 上验证 `recovery_batch_id`，再使用 Event 子集执行结构关系校验；合法 Anniversary recovery batch 不阻断加载，删除 batch 后稳定返回 `STORAGE_DATA_CORRUPTED / Reminder recovery batch is missing`。一次性全天 Event 以设备时区下开始自然日 `00:00` 为锚点解析 UTC，并向 Native 提交绝对 `remind_at`；失效提醒在 Event create 前本地拦截。默认开始时间继续采用整点，但保证“开始时间 - 15 分钟”严格晚于页面时钟，`23:xx` 可自然跨到次日而不再夹到 23:00。设备时区读取、当地时间解析和响铃能力检查统一返回中文用户提示，不再拼接 Native code/message/request id。
- 验证状态：新增失败回归在修复前分别复现 `Anniversary orphan unexpected success`、全天提醒实际 create、三条原生错误直出，修复后均通过；Calendar Contract runner `213 schemas / 19 fixtures / 2 public methods / 2 native calls`；C++ 重新 configure 后 build-after-test `excellent_calendar_check` 13/13；Flutter 创建控制器 12/12、新建页 12/12、全量 587/587，`flutter analyze` 0 issue；Android `testDebugUnitTest`、`lintDebug`、三 ABI `assembleDebugAndroidTest` 与 `flutter build apk --debug` 通过。Debug APK SHA-256 为 `16974D8743B16C544D7018BBD01B32B2C5948029BDB5E35FEDE7DA8C932B05FF`；`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 剩余门禁：本轮未执行真机测试、Release APK、TalkBack、系统 200% 字体/减少动画真机、设备时区/DST 切换、强杀恢复及完整升级矩阵；Calendar 继续保持 `implemented_unintegrated + blocked`，本次返修不解除发布门禁。
- 开发时间：2026-09-02 11:37 +08:00（Asia/Shanghai）。

## 2026-09-02 11:58 +08:00 Search completed recurring-series cutoff 闭包与 C++ 返修

- 使用 Skill：`calendar-data-contracts`、`debug`。先核验机器真相源和实际门禁，再分别建立 validator sentinel 与 C++ 黑盒失败回归；采用 Calendar Contract 为共同真相源完成 Revision 2 发布前 amendment 和最小运行时修复。
- 负责模块：Search completed recurring-series invariant/validator、Search 领域说明与 active 状态、C++ Calendar/Search 共用 occurrence eligibility、Search cutoff 附近有界 seek/选择/分页及回归测试；未改变 Dart/Kotlin/JNI wire DTO、SQLite schema/version、历史格式、依赖版本或 capability 状态，并保护工作树内其他 Calendar/Habit/Search 在途修改。
- 任务目标：研判“Search 缺少 Calendar completed-series cutoff、validator 未覆盖且 C++ 会返回 cutoff 后 occurrence”是否真实，确认此前“validator 失败、C++ 12/13”证据是否准确，并在真实问题存在时按 timed/all-day、时区/DST、显式 state、完成开关、total/cursor 规格修复。
- 任务结果：结论与独立复核一致：业务/实现问题真实，但旧门禁失败说法不真实。修复前 Search validator 实际通过、完整 C++ build-after-test 为 13/13；新增 validator 深比较后旧 Search invariant 按预期失败，新增 C++ 回归也稳定复现“截止前无 occurrence 的 completed series 仍被返回”。最终保留 Contract Revision 2，并记录 2026-09-02 pre-release amendment，因为没有 wire shape、reader/writer、持久化或已发布 cursor 迁移；Search 现完整引用并复制 Calendar cutoff，validator 同时深比较 status projection 与 cutoff 并强制 eligibility 顺序。C++ 抽取 `completed_recurring_series_eligibility` 供 Calendar/Search 共用：timed start instant 或 recurrence timezone 全天日初必须严格 `< completed_at`；等号/之后排除，截止前长区间保留，显式 completed/skipped 不得复活。Search 固定执行 cancelled → cutoff → overlap → include_completed → selection → total/sort/cursor；无日期 completed series 选择 cutoff 前最后一个 eligible occurrence，无 eligible occurrence 则不返回。
- 验证状态：Search/Calendar/Habit/Anniversary validator 全部通过（213 schemas；Search 31 fixtures，Calendar 19，Habit 46，Anniversary 56）；重新 configure 后 `excellent_calendar_check` 13/13。Search C++ 回归覆盖 timed/all-day、`< / == / >`、America/Los_Angeles DST fold、请求/recurrence timezone、跨 cutoff 长区间、显式 state、include_completed、无日期最后 eligible、精确 total 与两页 cursor 守恒。Release 1k/10k/50k warm P95 为 `11.259/114.548/593.120 ms`，三档实测 `sql_statements=18`、`recurrence_candidates=13`。Flutter analyze 无问题、全量 587/587；Android unit/lint/androidTest APK、三 ABI CMake、主 Debug APK和 Native smoke analyze/test/APK 全部通过；Debug APK SHA-256 `198022B9C7F6B6876CF2105D202BEFC47B59A80F417BA7850CCC37E702AC59DC`。`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 剩余门禁：`adb devices -l` 无设备，本轮未执行 seeded 三类真实查询、AtomicFile force-stop 恢复、IME/TalkBack/旋转/进程恢复或设备性能。此修复只关闭 completed-series Contract/C++ blocker，不代替后续 Review 中 seeded 脚本、撤销时限、本地化和设备性能等独立 finding 的返修/复审；`search.*` 保持 `planned + blocked`。
- 开发时间：2026-09-02 11:58 +08:00（Asia/Shanghai）。

## 2026-09-02 12:58 +08:00 Search 真机脚本、撤销时限、本地化与性能门禁返修

- 使用 Skill：`debug`、`cross-layer-feature`。先按 Review 的四个触发条件核对实际代码并建立 Flutter 失败回归，再在 Search 对应层做最小修复；未修改 Contract、SQLite schema/version、Search 业务排序/匹配、其他领域行为或 capability 状态。
- 负责模块：Search Android seeded instrumentation、Flutter History Application 协调、应用级中文本地化、筛选无障碍语义，以及 C++ 性能测试构建配置门禁。
- 任务目标：独立判断 10k 性能、三类真机脚本、清空历史撤销常驻和英文 Material 控件四项 Review Finding；修复真实偏差，并防止错误性能构建再次产生误导证据。
- 任务结果：seeded 脚本、撤销时限和本地化三项均确认真实并已修复。`anniversary.create` 直连 Native 返回 `AnniversaryDetailResponse`，脚本现从 `data.anniversary` 读取 ID；运行前和 finally 均按隔离测试标题分页发现并删除遗留纪念日，解析失败后仍可兜底清理。History 撤销窗口冻结为 6 秒，超时、后续 History intent、离开/暂停 Search 及 Controller dispose 都会取消计时并清除临时状态；撤销成功会取消旧计时器，避免稍后误删恢复后的历史。顶层应用注册 `zh_CN` 及 Material/Widgets/Cupertino delegates，日期范围选择器与筛选删除提示均使用中文。
- 性能判断：Review 的“10k 产品性能不达标”未复现。相同代码在本机 Release 的 10k warm P95 为 `121.566 ms`，满足 `≤300 ms`；未设置 `CMAKE_BUILD_TYPE` 的同一 Ninja 构建为 `751.409 ms` 并失败，且现存 Review 时段构建目录为未优化配置。原性能程序未声明配置，确有证据歧义，因此新增 Release-only fail-fast；非 Release 现在在造数前明确拒绝。最终 Release 1k/10k/50k warm P95 为 `10.829/121.566/1137.080 ms`，三档 `sql_statements=18`、`recurrence_candidates=13`，50k 未卡死/OOM；真实 Android Release 设备性能仍需独立门禁。
- 验证状态：修复前 Widget 回归稳定复现撤销 7 秒后仍存在且 locale 为 `en_US`；修复后 Search Controller/Page 定向 24/24、Flutter 全量 589/589、`flutter analyze` 0 issue、Debug APK 成功。Search Contract validation 与 C++ 重新 configure 后 build-after-test 13/13；Android `testDebugUnitTest`、`lintDebug`、三 ABI CMake 和 `assembleDebugAndroidTest` 成功，修复后的 Search runner 已进入测试 APK。既有 Flutter Native smoke analyze/test/Debug APK 通过。
- 未验证与放行结论：`adb devices -l` 无连接设备，故修复后的 `search_seeded` 真实 Event+Habit+Anniversary 同次查询、遗留数据兜底清理、中文 IME/TalkBack、旋转/进程恢复及 Android Release 设备 1k/10k/50k 性能仍未执行。代码 Findings 可提交复审，但 `search.*` 继续保持 `planned + blocked`。
- 开发时间：2026-09-02 12:58 +08:00（Asia/Shanghai）。

## 2026-09-02 13:37 +08:00 Search Android 设备复审与发布门禁

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。先冻结 HXY HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 与当前 Search 相关脏工作树范围，依据 Search Revision 2、active 主计划和既有四项 Review Finding 建立独立复审矩阵；本轮未修改产品代码、Contract、既有测试或 capability 状态。
- 负责模块：Search C++/SQLite 性能与 completed recurring-series cutoff；Kotlin/MethodChannel/JNI 三类型 seeded query、AtomicFile History；Flutter Search 历史、中文本地化、筛选和无障碍；Android 13 realme RMX3687（序列号 `ZXNZDEW4ZPN7499L`）隔离 `.device_test` APK。
- 任务目标：在手机连接后复核性能构建模式保护、三类型真机脚本及兜底清理、6 秒撤销、本地化四项返修，并检查是否存在新的发布阻断；只有设备与主机门禁、独立复审全部通过时才允许把 `search.*` 切换到发布态。
- 复审结果：原四项中，性能构建保护、seeded 三类型脚本、撤销时限和可见中文本地化均得到独立证据。非 Release 性能程序在造数前以 exit 2 拒绝；Windows Release 1k/10k/50k warm P95 为 `11.349/121.387/589.251 ms`。同一 arm64 Release 性能程序交叉编译后在设备 Awake 状态得到 `20.294/210.954/1076.98 ms`，10k 满足 `<=300 ms`，50k 峰值内存 `185327616` bytes 且无卡死/OOM；锁屏状态三次 10k P95 `313.720/315.441/317.568 ms`，因 Android 非交互 CPU 策略不作为交互发布基线。`search_seeded` 连续两次通过真实 Event+Habit+Anniversary Unicode query、typed sections 与 cleanup；History interrupted-write prepare -> force-stop -> verify 恢复旧完整 AtomicFile snapshot。真实页面长按历史显示逐项“删除”按钮，清空后立即出现“撤销”，7 秒后撤销和提示均消失；筛选、保存/关闭、月份、星期和日期节点均为中文。
- 新发现：结论仍为 **CHANGES REQUIRED / 不切换发布态**。P2 发布门禁：Flutter 当前 `DateRangePicker` 的 header Semantics 在框架 `date_picker.dart` 中直接拼接英文 `to`，真机无障碍树实际为“选择搜索日期范围 1月18日 to 1月18日”。可见 UI 已中文化，但中文 TalkBack 验收仍不成立；本轮未冒险启用全局 TalkBack 服务，使用真实 Android accessibility/UIAutomator 节点确认该标签。中文搜狗 IME 已真实弹出并可向 Search 输入；候选词 composing 不触发查询由既有 Flutter 回归覆盖，自动化未替代人工听读。
- 主机验证：Search/Calendar Contract runner 均通过（Search 213 schemas、31 fixtures、3 public methods、1 native call，状态保持 `planned + blocked`）；重新 configure 后 `excellent_calendar_check` 13/13；Search 定向 Flutter 35/35、全量 589/589、`flutter analyze` 0 issue；Android `testDebugUnitTest`、`lintDebug`、三 ABI CMake、Debug APK 和 androidTest APK 构建通过。Debug APK SHA-256 为 `4EA2AA9BD1927184C642E2487422BB246D02B1806ADA85A18935DDCBCDEBE9AA`。
- 发布结论：代表设备性能、三类型真实链路、History 强杀恢复及四项原始 Finding 已闭环；但中文 TalkBack 日期范围标题仍有中英混读，违反 active 主计划“TalkBack 和中文通过后才激活”的显式门禁。`contracts/search/**`、`search.*` MethodChannel/native call 继续保持 `planned + blocked`，不得在该语义缺口解决及独立复测前改为 `integrated + active`。
- 开发时间：2026-09-02 13:37 +08:00（Asia/Shanghai）。

## 2026-09-02 13:55 +08:00 Search 日期范围中文 TalkBack 语义返修

- 使用 Skill：`debug`、`frontend-flutter-feature`。先在真实 Widget Semantics 树稳定复现，再核对当前 Flutter SDK 实现和 Search 页面入口，将修复限制在 Flutter Presentation 与对应 Widget 回归；未修改 Flutter SDK、Contract、Application/Controller、Native、依赖、工具链或 capability 状态。
- 负责模块：Search 筛选弹层中的自定义日期范围选择流程及中文无障碍回归测试。
- 任务目标：研判并修复自定义日期范围标题在 Android 无障碍节点中出现“选择搜索日期范围 1月18日 to 1月18日”的中英混读发布阻断，同时保持 inclusive 自定义日期范围、staged filter 和现有 Material 3 交互。
- 任务结果：Finding 确认真实。Flutter SDK `DateRangePicker` header 直接构造 `$helpText $startDateText to $endDateText`，该英文连接词不经过 `MaterialLocalizations`，项目仅注册中文 delegate 无法覆盖；外层 `excludeSemantics` 又会同时屏蔽日历子节点，不能作为修复。Search 改为连续的两个中文 Material 单日选择步骤：先“选择开始日期/下一步”，再“选择结束日期/保存”；第二步以开始日为最早可选日，取消任一步均不改变 staged filter，保存后仍映射为同一 inclusive `SearchDateFilter.custom`。两个步骤复用 SDK 单日历、主题、中文月份/星期、标准动画与日期节点语义，不复制或修改 SDK 源码。
- 验证状态：修复前新增 Widget 回归按预期捕获唯一错误节点 `选择搜索日期范围 8月31日 to 8月31日`；修复后同一回归验证开始/结束两个中文标题、完整语义树无独立英文 `to`，并验证保存后 custom `date_from/date_to_exclusive` 仍正确。Search 六个专项测试文件 41/41、Flutter 全量 589/589、`flutter analyze` 0 issue、两份本次文件定向 format check 通过，Debug APK 构建成功，SHA-256 `2378E61F7505D7C374B00BE4E8D156721238BE4A00E8270BC27FE5A9F59A204B`。Android 13 realme RMX3687 `.device_test` 真机无障碍节点确认第一步为“选择开始日期/1月18日周一”、第二步为“选择结束日期/1月18日周一”，月份、星期、按钮和日期节点均为中文且无 `to`；验证中未创建、删除或修改日历业务数据。
- 限制与状态：仓库级 `dart format --output=none --set-exit-if-changed lib test` 仍报告既有修改文件 `test/create_schedule_controller_test.dart` 需要格式化，本轮为保护无关在途修改未触碰；本次两份目标文件格式正确。未开启 TalkBack 服务进行人工听读，真机证据来自 Android accessibility/UIAutomator 节点，仍建议独立复审时补一次人工焦点顺序与听读。`search.*` 继续保持 `planned + blocked`，本次不擅自解除总发布门禁。
- 开发时间：2026-09-02 13:55 +08:00（Asia/Shanghai）。

## 2026-09-02 15:42 +08:00 Calendar 二次返修独立复核与发布硬门禁检查

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。在 HXY HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 上冻结 265 个未提交路径（68 unstaged、197 untracked）的工作树边界，以 Calendar 机器 Contract、领域文档、active plan/review 和公开创建接口先定义独立 oracle，再审查实现；未修改产品代码、Contract 或既有测试。
- 负责模块：Calendar C++/SQLite ReminderRecoveryBatch 引用完整性；Flutter 新建 Event 的全天提醒、默认时间和用户错误映射；Android Debug/Release 打包、隔离设备 JNI/SQLite smoke 与 Calendar 基本黑盒交互。
- 任务目标：独立复核 Anniversary recovery、全天一次性提醒、`HH:45/23:xx` 默认时间和 Native 错误脱敏返修，并检查是否已具备进入正式发布版的硬门禁。
- 复核结果：四项返修均得到独立证据。混合 SQLite 探针在 Event recovery 仍合法时单独删除 Anniversary batch，查询稳定返回 `STORAGE_DATA_CORRUPTED / Reminder recovery batch is missing`；全天亚洲时区当地午夜 reminder 在“未来 1 秒”允许、恰好等于 now 时本地拒绝且不调用 create；未知 Native code/message/request id 统一映射为中文通用提示；`23:44:59` 默认 15 分钟提醒严格位于未来。一次性 Flutter/C++ 探针均已精确删除。
- 新 Finding：结论为 **CHANGES REQUIRED**。P1 发布硬阻断：`flutter build apk --release` 虽成功，但 `android/app/build.gradle.kts` 的 release 明确复用 debug signing；`apksigner verify --print-certs` 实际证书为 `CN=Android Debug`。该 APK 只能用于本机 release-mode 验证，不能作为正式长期发布签名链。需建立外部化的正式 keystore/CI secret 配置、签名校验门禁和受控备份/轮换方案，禁止凭据入库；修复后重新生成并验证 release APK/AAB。
- 主机验证：Calendar Contract `213 schemas / 19 fixtures / 2 public methods / 2 native calls` 且保持 `implemented_unintegrated + blocked`；C++ 重新 configure 后 build-after-test 13/13；相关 Flutter 定向 27/27，包含独立探针的全量 592/592，`flutter analyze` 0 issue；Android `testDebugUnitTest`、`lintDebug`、三 ABI CMake、Debug APK 和 androidTest APK 构建成功；Release APK 新构建成功，SHA-256 `54DFC3580E11320B90727CF52FE610EF2F40493EABB938353038605B8FCE8555`，但证书门禁失败。
- 设备验证：Android 13 realme RMX3687 隔离 `.device_test` 包通过只读 Calendar JNI 2/2，以及 MethodChannel → JNI → C++ → SQLite 的 Event/Habit/Anniversary 三类 Unicode seeded query、occurrence identity 与自动清理；清理后只读复查三类计数归零。真实页面完成本地测试登录、进入 Calendar、周/月切换、42 日月范围加载、时间线未开放提示、选择历史日后“回到今天”入口和中文 Semantics 基本检查；未触碰发布包或用户业务数据。
- 剩余门禁：未执行正式签名产物、AAB/商店上传校验、设备时区/DST 切换、TalkBack 人工焦点/听读、200% 字体与减少动画真机、强杀恢复、完整升级/回滚矩阵和正式发布签名恢复演练。因此 Calendar 继续保持 `implemented_unintegrated + blocked`，不得激活或描述为发布就绪。
- 工作树保护：审查开始 manifest 为 265 路径、0 staged；Search 与其他并行改动只随全量回归，不归因或整理。全部一次性源码、可执行文件、截图和 UI dump 已精确清理。
- 开发时间：2026-09-02 15:42 +08:00（Asia/Shanghai）。

## 2026-09-02 16:15 +08:00 Search 最终真机复审与发布门禁检查

- 使用 Skill：`review-worktree-architecture`、`calendar-data-contracts`。以 HXY HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08`、Search Revision 2 机器 Contract、领域说明和 active 主计划为基线，复核当前包含 266 个未提交路径的脏工作树；本轮仅增加开发日志，未修改产品代码、Contract、既有测试或 capability 状态。
- 负责模块：Search Contract、C++/SQLite 查询与性能、Kotlin/JNI/MethodChannel、AtomicFile 本地历史、Flutter Search 页面、中文 IME/日期筛选/TalkBack/旋转，以及 Android Release 签名门禁；真机为 Android 13 realme RMX3687（`ZXNZDEW4ZPN7499L`）隔离 `.device_test` 包。
- 已关闭的旧阻断：Search seeded 脚本连续两次通过真实 Event、Habit、Anniversary Unicode 聚合查询、typed section 与兜底清理；History interrupted-write → force-stop → verify 成功恢复旧完整 AtomicFile snapshot；清空历史的“撤销”在 6 秒窗口后消失；搜狗中文 composing 等待 2 秒不发起查询、候选提交及键盘搜索正常；强制横屏后关键字和结果态保持。真实 TalkBack 服务已启用并观察中文焦点；开始/结束日期两步均无英文 `to`，此前日期范围中英混读 Finding 确认关闭。
- 新 Finding 与结论：**CHANGES REQUIRED / 不切换发布态。** P1 无障碍发布阻断：独立 Flutter Semantics 探针显示 Search 顶部输入区域被合并成同一个同时具有 `isButton` 与 `isTextField` 的节点，标签串联“搜索 / 搜索日程、习惯与纪念日 / 筛选”，输入 hint 为空；Android UIAutomator 将覆盖整个标题、输入框和筛选按钮的父节点导出为 `android.widget.Button`，筛选按钮又作为子节点重复出现。TalkBack 无法把搜索输入与筛选识别为两个职责清晰的控件，违反主计划完整 Semantics/TalkBack 门禁。应拆分标题、TextField 和筛选按钮的 semantics boundary，保证输入导出为有限边界的 `EditText`、筛选仅有一个 Button，并补 Flutter 节点角色/顺序与真机 TalkBack 焦点回归。
- 发布运营硬阻断：稳定执行 `flutter build apk --release` 与 Gradle `assembleRelease` 均在造包前按设计拒绝，原因是尚未配置非 Debug 的正式 keystore、五项 `EXCELLENT_CALENDAR_RELEASE_*` 凭据和证书 SHA-256。该 fail-closed 行为是正确的安全保护，不是 Search 业务回归；但在正式签名 APK/AAB、嵌入证书校验及密钥保管/恢复演练证据完成前，不能宣称可正式发布。
- 主机验证：Search/Calendar/Habit/Anniversary validator 均通过（Search 213 schemas、31 fixtures、3 public methods、1 native call，状态仍 `planned + blocked`）；C++ 重新 configure 后 build-after-test 13/13；Windows Release 1k/10k/50k warm P95 为 `10.777/120.377/604.937 ms`。Search Flutter 定向 41/41、全量 592/592、`flutter analyze` 0 issue；Android unit、lint、三 ABI Debug APK 与 androidTest APK 构建通过，Debug APK SHA-256 `5BB121129279583F375854B589F2E56D5F5B99B53B4DE1FCDF2D7A14EB77FE54`。仓库级 Dart format 检查仅报告两个既有非 Search 文件，31 个 Search 目标文件单独检查通过；`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。
- 设备性能与清理：arm64 Release 性能程序在设备 Awake 状态的 1k/10k/50k warm P95 为 `20.239/207.769/1060.820 ms`，10k 满足 `<=300 ms`，50k 峰值约 `185.4 MB` 且无卡死/OOM；三档均 `sql_statements=18`、`recurrence_candidates=13`。测试包、UI dump、设备临时性能程序和 tzdata 已精确删除，旋转恢复自动、TalkBack 关闭，未触碰用户正式应用或业务数据。
- 范围与剩余风险：审查期间 `flutter_client/android/app/build.gradle.kts` 被并行任务更新，已在稳定版本上重新验证 Debug 构建和 Release fail-closed，但当前仍是未冻结、0 staged 的大范围脏工作树；最终发布前还需以冻结提交重跑上述门禁。除搜索框语义结构与正式签名/发布运营链外，本轮测试范围内未发现新的崩溃、数据损坏、三类型链路、历史恢复、中文输入、旋转或性能 P1 阻断。
- 开发时间：2026-09-02 16:15 +08:00（Asia/Shanghai）。

## 2026-09-02 22:03 +08:00 Search V1 发布例外登记与能力激活

- 使用 Skill：`calendar-data-contracts`。按产品负责人本轮明确决定，将最终复审发现的搜索框 TalkBack 语义边界和正式 Release 签名链作为已接受的发布后债务登记，并同步 Search 机器 Contract、领域、计划、索引、当前状态和路线图；未修改搜索业务逻辑、跨层 payload、SQLite schema/version、History format、依赖或用户数据。
- 发布决定：新增 `OPEN-SEA-001`，分别记录合并的输入框/筛选 Semantics 角色风险，以及缺少生产 keystore、正式签名 APK/AAB、商店校验和密钥恢复演练的分发风险。产品负责人明确接受两项在本版本中不再阻断统一 Search Query 与设备本地 History 激活；该接受不表示问题已修复或场景已验证通过。
- Contract 校准：`search.query`、`search.get_local_history`、`search.replace_local_history`、唯一内部 `search.query` native call、11 个 Query/History Schema 和 `search_query_invariants.yaml` 统一切换为 `implementation_status: integrated`、`release_status: active`。未实现的 `search_index_response.schema.json` 保持 `planned`，FTS 保持 deferred；Revision 2、wire shape、错误、枚举、fixture 和 Storage 均无变化，因此无需 Contract 升版或数据迁移。
- 文档与计划：更新 `contracts/README.md`、`docs/domains/search_index.md`、`docs/status/current.md`、`docs/status/roadmap.md` 和 `docs/index.md`，将 Search 描述为“已激活并进入带开放债的维护轨”；搜索-01/02/03/04/05 均校准为 Completed/Released 并从 `docs/plan/active/` 归档至 `docs/plan/completed/`。历史派发清单和发布前 `planned + blocked` 证据保留，不伪造未执行项目。
- 验证状态：Search validator 通过 `213 schemas / 31 fixtures / 3 public methods / 1 native call / integrated+active / FTS deferred`；Calendar validator 通过 `213 / 19 / 2 / 2 / integrated+active`；Habit validator 通过 `213 / 46 / 4 identity / 12 public / 11 native / integrated+active`；Anniversary validator 通过 `213 schemas / 56 fixtures / 20 identity vectors`。`git diff --check` 无 whitespace error，仅既有 LF/CRLF 提示。状态检索未发现权威当前文档继续把统一 Search Query/History 描述为 blocked；命中项仅为 SearchIndex planned、发布前历史证据或已接受债务边界。
- 剩余风险：Search V1 可作为正式能力依赖，但当前仍没有生产签名商店产物，搜索框 TalkBack 语义仍需修复；两项均由 `OPEN-SEA-001` 持续跟踪。当前大范围脏工作树不是冻结发布提交，本次只完成能力状态校准，后续实际出包仍需在冻结提交上执行发布流水线。
- 开发时间：2026-09-02 22:03 +08:00（Asia/Shanghai）。

## 2026-09-02 16:19 +08:00 Android Release 正式签名门禁返修

- 使用 Skill：`debug`、`android-kotlin-native-feature`。按复审 Finding 独立核验 Gradle 配置和既有 Release APK，未修改 Contract、Flutter/Dart、Kotlin 业务代码、C++、工具链或依赖版本。
- 负责模块：`flutter_client/android` Release signingConfig、APK/AAB 签名身份校验、私密配置示例与发布签名操作说明。
- 任务目标：判断 Release 复用 Debug 签名是否真实存在；若成立，移除 Debug fallback，使缺少正式身份、使用 Debug 证书或证书指纹不匹配时均无法产出可通过门禁的 Release APK/AAB，同时不把 keystore 或密码提交仓库。
- 任务结果：Finding 确认真实。原 `release.signingConfig` 明确绑定 `debug`；复审所指 APK SHA-256 `54DFC3580E11320B90727CF52FE610EF2F40493EABB938353038605B8FCE8555` 经 `apksigner` 独立确认 signer 为 `CN=Android Debug`、证书 SHA-256 `D32EDEEBBFB537D459A8F6E050426895C93780803A2A9B947532BD024B315AD6`。现已改为从 ignored `android/key.properties` 或五项 `EXCELLENT_CALENDAR_RELEASE_*` 环境变量注入，要求固定证书 SHA-256；Release 任务图在执行前校验配置和 keystore 身份，明确拒绝 Debug 证书，并在构建后再次校验 APK signer 与 AAB 每个内容项的 signer。新增 `verifyReleaseApkSigning`、`verifyReleaseBundleSigning` 两个 CI 入口；`.p12/.pfx` 也已加入忽略规则。
- 独立门禁验证：未配置签名时，`flutter build apk --release`、`flutter build appbundle --release` 和包含 Release 的 Gradle aggregate assemble 均在造包前按预期失败；配置默认 Android Debug keystore 即使指纹正确也按预期失败。仓库外一次性 3072-bit RSA PKCS12（证书 SHA-256 `D5EA7DE7A803941759DF7504E70EF96E9A343ED093394FBE715EFE42DF1B995E`）下，APK/AAB 两个校验任务成功，产物内嵌证书均与 pinned fingerprint 一致；验证 APK/AAB SHA-256 分别为 `5919C647E5BB3F4D869D89BEF045B3AE762CEAA18AC265E6FA16BBC5C398329A`、`C3DCE6F014AAB7FA3746D164CEC1E5141B3AEF8AE30825FD01DCD3217DC65635`。一次性私钥、证书及其 Release 产物随后已精确删除，避免被误认为正式发布包。
- 回归与设备：Android `testDebugUnitTest`、`lintDebug`、`assembleDebug` 均成功。Android 13 realme RMX3687 的隔离 `.device_test` Debug APK 最终重新安装成功，冷启动成功，应用进程无 `AndroidRuntime`/`FATAL EXCEPTION` 标记；未触碰正式应用包或业务数据。
- 发布状态与剩余条件：代码层的 Debug-signing fallback 已关闭，但仓库不能代替发布负责人创建、保管或授权真实生产密钥。正式发布仍需发布负责人在私密环境/CI 注入生产 keystore 与 pinned fingerprint，完成至少一次加密备份恢复和轮换演练，并保存 APK/AAB 验签证据；在此之前保持发布门禁阻塞是正确结论。
- 开发时间：2026-09-02 16:19 +08:00（Asia/Shanghai）。

## 2026-09-02 17:03 +08:00 Local-first 云同步概念与项目基线讲解

- 使用 Skill：`self-learning`。按“直觉模型 → 分布式问题 → 专业机制 → 项目落点 → 反例与掌握检验”梳理云同步，不实施同步代码、Contract 或数据库迁移。
- 负责模块：跨设备 Local-first 同步概念；Calendar Core SQLite v5、本地 Event/Anniversary/Habit 数据边界；Cloud Backend 认证基座、planned sync/calendar 模块与同步占位 Contract。
- 任务目标：结合 ExcellentCalendarAPP 当前实现，向用户讲清副本与最终一致性、原子操作日志、增量游标与幂等、版本/冲突/删除语义，以及同步数据和设备本地数据的边界，为后续项目专项设计建立共同概念模型。
- 任务结果：确认当前项目已具备本地 SQLite v5 事务/软删除/稳定身份和账号后端基座，但没有生产同步 API、服务端日历业务表、设备注册或客户端同步引擎；现有 `SyncOperation`/`SyncResult` 只作为未发布概念占位。识别后续设计前必须冻结的关键问题：账号与本地数据归属、Outbox 与业务写同事务、服务端 change sequence/cursor、实体版本与本地 generation/recurrence revision 分离、删除 tombstone/恢复/清理、冲突矩阵，以及 Reminder 用户意图与每设备投递状态的重新分界。
- 验证状态：只读核对架构概览、文档索引、R2 当前状态/路线、同步与账号领域说明、同步 Schema、SQLite v5 Contract、相关 ADR、Cloud Backend 模块/架构和实际源码入口；未执行构建、测试或设备验证，本任务无产品代码改动。
- 开发时间：2026-09-02 17:03 +08:00（Asia/Shanghai）。

## 2026-09-02 17:07 +08:00 Calendar V1 发布例外登记与 capability 激活

- 使用 Skill：`calendar-data-contracts`。按用户明确的产品发布决定核对 Calendar 领域说明、公开/内部 capability、Schema 状态、专项 validator、当前状态、路线图、计划、Review 与开放问题；未修改 wire 字段、Native v2、Calendar View revision、Storage v5、数据模型、迁移链或产品实现。
- 负责模块：Calendar View R1 的发布状态一致性、`OPEN-CAL-001` 风险登记、五份开发计划与专项 Review 归档。
- 任务目标：将正式生产签名/商店上传、真机时区与 DST、TalkBack、200% 字体/减少动画、强杀恢复、升级回滚/签名密钥恢复及正式 Release UI 全链登记为后续问题；在没有其他新硬缺陷的前提下，将 Calendar V1 从 `implemented_unintegrated + blocked` 切换为发布能力。
- 任务结果：新增 `OPEN-CAL-001`，逐项记录七项未验证矩阵、影响、关闭条件与 2026-09-02 产品负责人非阻断接受决定。同步将两个 `calendar.*` MethodChannel、两个 internal call、八个 Calendar Schema、查询不变量和机器 validator 校准为 `integrated + active`；领域、Contract README、架构、索引、当前状态与路线图同步。五份日历计划移入 `docs/plan/completed/`，专项 Review 移入 `docs/reviews/archive/`；Review 保留“生产签名/商店与设备矩阵未通过”的历史事实，不倒写成完整 PASS。
- 签名边界校准：本轮读取到并行返修已移除 Release Debug fallback，缺少生产配置、Debug 证书或指纹不匹配时均 fail-closed；一次性非生产密钥已验证 APK/AAB 门禁，且临时密钥与产物已删除。当前准确残余风险是尚无生产密钥保管/恢复演练、生产签名产物和商店上传证据，而不是仍允许生成 Debug 签名 Release。
- 验证状态：Calendar validator 通过 `213 schemas / 19 fixtures / 2 public methods / 2 native calls / integrated+active`；Anniversary 通过 `213 schemas / 56 fixtures / 20 identity vectors`；Habit 通过 `213 schemas / 46 fixtures / 4 identity vectors / 12 public / 11 native / integrated+active`；Search 通过 `213 schemas / 31 fixtures / 3 public / 1 native / planned+blocked`。本次仅改 Contract 状态、validator 断言和文档，没有重新运行 C++、Flutter、Android 或真机测试；其最近证据与未验证边界均原样记录。
- 开发时间：2026-09-02 17:07 +08:00（Asia/Shanghai）。

## 2026-09-02 22:28 +08:00 Local-first 云同步需求发现与可行性门禁

- 使用 Skill：`calendar-data-contracts`、`cross-layer-feature`、`backend-api-development`。按项目架构、文档索引、当前状态、R2 路线、同步/用户领域占位、机器 Contract、SQLite v5、本地 Appearance、Cloud Backend 迁移与实际源码入口进行只读盘点；未实施同步代码、协议或数据库迁移。
- 负责模块：账号与个人资料、Event/Anniversary/Habit 及其依赖实体、用户偏好、提醒同步边界、设备身份、客户端操作日志、Backend 增量同步与冲突处理的需求与分层规划。
- 任务目标：以产品经理式问答发掘多设备共享、提醒同步和个性化设置同步的完整需求，先识别必须由用户决定的产品语义，再形成可执行的分层开发计划。
- 任务结果：可行性判定为 `SPECIALIST_SPLIT / DECISION_REQUIRED`。现有账号/个人资料后端和 Flutter 会话链已实现但 `backend_api.yaml` 与 Auth MethodChannel 仍为 planned；Calendar Core SQLite v5、本地 Event/Anniversary/Habit 已激活，但没有账号分区、原子 Sync Outbox、设备注册、生产 Sync API、服务端日历业务表或客户端同步引擎。现有 `sync.apply`、`SyncOperation`、`SyncResult`、Sync Log/Adapter 与 Backend sync/calendar 包均为概念占位，不足以安全实施。Appearance 当前协议和 UI 明确为 Kotlin 本机配置且不进入云同步，新需求将要求显式 Contract revision，而不能静默复用现状。
- 关键设计门禁：登录时既有游客数据归属、退出/换号后的本地隔离；同步实体闭包与派生/设备数据排除；提醒意图和每设备调度/权限的两级开关；个性化设置类型化；实体版本、幂等键、设备游标、删除墓碑与恢复窗口；冲突 UX；首轮 bootstrap、弱网后台策略、端到端加密边界和多平台范围。完成用户选择前不创建 active plan 或写实现。
- 验证状态：完成只读 Git 状态与实现盘点；确认 `cloud_backend/**` 当前无未提交修改，而仓库其他层存在大量用户在途修改，后续必须保护。当前仅为需求发现，无构建、测试或设备验证；下一步等待用户完成第一轮产品决策，再输出冲突矩阵、阶段拆分和正式开发计划清单。
- 开发时间：2026-09-02 22:28 +08:00（Asia/Shanghai）。

## 2026-09-02 22:27 +08:00 RAG 概念与项目落地路径讲解

- 使用 Skill：`self-learning`。按“直觉模型 → 反面推演 → 专业原理 → 项目落点 → 最小实践 → 掌握检验”解释 Retrieval-Augmented Generation，并结合当前代码库推演只读问答与候选日程两类落地方式。
- 负责模块：AI Pipeline、`ai.extract` Contract、Cloud Backend planned AI/Search/Calendar 模块、Calendar Core SQLite v5 与 Search V1 查询边界。
- 任务目标：说明 RAG 的检索、上下文组装与生成流程，区分关键词搜索、向量检索和 RAG，并给出符合 Android-first、Local-first、Contract-first 架构的开发阶段、数据流、安全边界与验收思路。
- 任务结果：确认当前 AI/OCR 只有 Schema、MethodChannel 声明和 README 骨架，`ai.extract` 未标记 integrated/active；Cloud Backend AI/Search/Calendar 仍为 planned，SearchIndex/FTS 也未实现。建议先建立只读、可追溯、带引用的日历问答 MVP；任何写操作必须生成 Candidate Event，经 Contract 校验、C++ AI Result Validator 与用户确认后再进入既有 Event 创建链路，禁止模型直接写 SQLite 或绕过 C++ Domain。
- 验证状态：只读核对架构概览、文档索引、当前状态与路线图、AI Pipeline/Validator 说明、AI Schema、MethodChannel 声明及 Backend 模块占位；未实施产品代码，未执行构建、测试或设备验证。除本条追加日志外未修改项目文件。
- 开发时间：2026-09-02 22:27 +08:00（Asia/Shanghai）。

## 2026-09-02 22:31 +08:00 项目状态与文档索引实时校准

- 使用 Skill：`review-worktree-architecture`。以 HEAD `3c06eb501a2a58c2b7cb75076fda47efaeb37f08` 和当前 274 个未提交路径（0 staged、72 unstaged、202 untracked）为边界，核对机器 Contract、production composition、计划/Review 归档、开放问题和最近实际验证；只修改状态、路线、索引与本条日志，不修改业务代码、Contract 或测试。
- 负责模块：`docs/status/current.md`、`docs/status/roadmap.md`、`docs/index.md` 和开发日志。
- 任务目标：根据当前工作树实时更新项目状态与导航入口，消除 Calendar/Search 已激活结论和旧 `blocked` 中间验证记录之间的矛盾，并把最新 Local-first 云同步需求盘点纳入 R2 当前拓扑。
- 任务结果：`current.md` 将研判时间更新到 2026-09-02 22:31，收敛为 Habit、Calendar、Search 已 `integrated + active` 且分别保留 `OPEN-HAB-001`、`OPEN-CAL-001`、`OPEN-SEA-001` 发布后债；删除当前验证基线中的 Calendar/Search 旧阻塞中间态，改用 2026-09-02 最终主机与 Android 13 证据。云同步明确为 `SPECIALIST_SPLIT / DECISION_REQUIRED`：只完成需求与架构盘点，尚无 active plan、生产 Contract、服务端日历表、本地 Outbox、设备注册或客户端同步引擎。`roadmap.md` 补齐产品决策、Contract/数据和分层实施顺序；`index.md` 新增最小同步资料入口，并明确概念 Schema/空包不证明实现。
- 验证状态：Calendar validator 通过 `213 schemas / 19 fixtures / 2 public methods / 2 native calls / integrated+active`；Search 通过 `213 / 31 / 3 / 1 / integrated+active / FTS deferred`；Habit 通过 `213 schemas / 46 fixtures / 4 identity vectors / 12 public methods / 11 native calls / integrated+active`；Anniversary 通过 `213 schemas / 56 fixtures / 20 identity vectors`。新增索引路径全部存在，当前状态文档未再命中 Calendar/Search/Habit 的旧 active-plan 或 blocked 表述，`docs/plan/active/` 当前文件数为 0；`git diff --check HEAD --` 无 whitespace error，仅既有 LF/CRLF 提示。因本任务只改 Markdown，未重复执行 C++、Flutter、Android 或真机测试，文中相应结果均明确引用最近已记录证据。
- 剩余边界：`docs/domains/README.md` 仍包含 Storage v4 active、Habit planned/blocked 等较早状态描述；它低于机器 Contract 和当前状态文档，且不在本次指定修改范围内，后续应单独校准，避免领域总览继续制造导航噪声。
- 开发时间：2026-09-02 22:31 +08:00（Asia/Shanghai）。

## 2026-09-02 22:45 +08:00 云同步第一轮产品决策与扩展能力澄清

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。基于上一轮同步基线，解释游客本机数据归属、账号缓存保留、可见冲突、HTTPS、公网 IP、云备份/历史版本及服务端提醒；未实施同步代码、Contract 或数据库迁移。
- 负责模块：Local-first workspace/账号隔离、同步冲突 UX、传输安全、备份恢复边界、设备推送与本地提醒协作。
- 已确认产品决策：V1 为 Android 多设备但协议跨平台；首次登录由用户选择是否合并游客数据；退出后保留加密账号缓存；同步完整业务事实及完成/打卡历史；提醒采用账号级跨设备策略与设备级接收开关；同步可移植个性化设置；冲突采用自动合并与显式字段冲突提示；同步触发、删除墓碑、安全、设备管理和分阶段上线均采用推荐方案。
- 设计澄清：建议使用互斥的游客 workspace 与账号 workspace，而非靠每条记录的松散布尔值判断是否上传；同步引擎只绑定账号 workspace，本机 workspace 永不创建云端 Outbox。选择不合并时数据保留在独立“本机数据”空间，后续可由用户显式迁移到账号。`3B` 意味着后续必须单独设计账号级数据库加密、Keystore 密钥生命周期、退出隐藏、设备撤销与本地擦除边界。
- HTTPS 结论：截至 2026-09-02，Let's Encrypt 已正式支持公网 IPv4/IPv6 的 IP 地址证书，但证书有效期约 160 小时，需支持 shortlived profile 的 ACME 客户端和可靠自动续期；Android 9+ 默认禁止明文 HTTP。公网 IP 不再是开发 HTTPS 的绝对阻塞，但稳定域名仍更易运维，正式账号/同步数据不得使用明文 HTTP或自签名证书绕过系统信任。
- 扩展能力结论：同步只保证当前状态收敛，不等于备份；历史恢复应以新版本操作恢复，不能回拨 change cursor 或直接覆盖在线数据库。服务端推送分为“数据变化唤醒”与“到期提醒投递”；前者可作为后续同步加速，后者会与本地 Alarm/Notification 产生去重、准时性和双真相源风险，不建议纳入同步 V1。
- 验证状态：完成官方 Let's Encrypt IP 证书、Certbot 支持和 Android cleartext 规则核对，并核对 Firebase 对 Doze、消息延迟与投递接受不等于设备送达的官方说明。当前仍为需求设计，无构建、测试或设备验证；等待用户确认本机空间展示方式、恢复层级和推送范围后进入下一轮计划冻结。
- 开发时间：2026-09-02 22:45 +08:00（Asia/Shanghai）。

## 2026-09-02 23:02 +08:00 README 与领域文档实时同步

- 使用 Skill：`calendar-data-contracts`。以当前机器 Contract、SQLite v5、已激活查询能力、开放验证债、Local-first 同步需求盘点和实际跨端目录为真相源，保持既有 README 与 `docs/domains/` 的说明、表格和目录树风格进行文档校准。
- 负责模块：根 `README.md`、`docs/domains/README.md`、Anniversary、Category、SyncOperation、UserSyncState 领域文档及开发日志；保留用户已有的 `search_index.md` 修改和未跟踪 `calendar_view.md`，未改业务代码、Contract、Schema 或测试。
- 任务目标：消除 README 与领域总览中 Storage v4 仍为 active、Habit 尚待激活、Calendar/Search 缺失、同步占位容易被误解为已实现，以及跨端文件示例过时等描述，使项目入口与实时开发状态一致。
- 任务结果：README 新增 R2 当前状态表和权威导航，明确 SQLite v5 是唯一 live writer、Habit/Calendar/Search 已 `integrated + active` 且保留对应开放验证债、SearchIndex/FTS deferred、Backend Auth 代码完成但机器 Contract planned、Local-first Sync 为 `SPECIALIST_SPLIT / DECISION_REQUIRED`；同步更新领域对象、Contract 目录、Dart/Kotlin/JNI/C++ 示例和 planned 能力标记。领域总览补入 CalendarView/SearchQuery，校准 v4→v5 迁移与事务边界；Anniversary/Category 说明 v4 引入且由 v5 继承；SyncOperation/UserSyncState 明确仍是未冻结的概念模型和实施前产品门禁。
- 验证状态：README 中 31 个 Schema 引用全部可解析，README 与领域总览中的 33 个本地 Markdown 链接全部存在，目标文件 `git diff --check` 无 whitespace error（仅既有 LF/CRLF 提示）。Calendar validator 通过 `213 schemas / 19 fixtures / 2 public methods / 2 native calls / integrated+active`；Search 通过 `213 / 31 / 3 / 1 / integrated+active / FTS deferred`；Habit 通过 `213 schemas / 46 fixtures / 4 identity vectors / 12 public methods / 11 native calls / integrated+active`；Anniversary 通过 `213 schemas / 56 fixtures / 20 identity vectors`。本任务仅修改 Markdown，未重复执行 C++、Flutter、Android 构建或真机测试。
- 开发时间：2026-09-02 23:02 +08:00（Asia/Shanghai）。

## 2026-09-03 19:39 +08:00 云同步第二轮决策冻结与环境边界

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。继续收敛 Local-first 云同步需求与安全边界，未修改产品代码、Contract 或数据库。
- 负责模块：游客/账号 workspace、版本恢复、提醒触发、退出缓存隐私、开发与正式网络环境。
- 已确认产品决策：本机空间与账号空间分开展示（13A）；V1 当前状态同步、V1.1 单条数据 30 天历史、V2 整账号备份（14A）；V1 不接入 FCM，依靠前台、网络恢复、手动与系统后台机会同步，提醒继续由设备本地调度（15A）；开发环境使用私网 IP，正式环境使用可访问 80/443 的公网 IP（16）；退出登录后保留的加密账号缓存完全隐藏，仅重新登录同一账号后可见（17A）。
- 环境设计边界：开发版允许显式配置私网 HTTP 与测试账号；正式版必须使用公网 HTTPS、禁止明文回退，并补齐 Release 网络权限、环境配置校验及密钥/日志隔离。公网 IP 是否固定、证书自动续期与生产入口稳定性仍待确认。
- 验证状态：本轮为需求设计与决策记录，没有执行构建、测试或设备验证。下一步继续确认首次迁移粒度、同步总开关、提醒默认值、退出缓存保留期、云端数据清除、附件范围和同步状态 UX。
- 开发时间：2026-09-03 19:39 +08:00（Asia/Shanghai）。

## 2026-09-03 19:50 +08:00 云同步第三轮产品决策冻结

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。结合现有 Event、Anniversary、Habit、HabitCheckIn、Category、Profile 与 Appearance Contract，继续收敛云同步 V1 产品语义；未修改产品代码、Contract 或数据库。
- 负责模块：游客数据迁移、同步开关、提醒跨设备策略、退出缓存、账号删除、个性化设置、同步状态、附件范围与后台时效。
- 已确认产品决策：首次迁移采用数量预览后全量原子迁移（18A）；同步总开关按设备独立控制，关闭期间修改进入本地待同步队列（19A）；提醒规则同步但其他设备是否执行由账号策略与设备开关共同决定（20A）；退出后加密缓存保留 30 天并支持立即清除（21A）；V1 暂不提供账号注销（22C）；个性化设置采用可移植字段白名单（23A）；正常同步保持安静、异常和冲突明显展示（24A）；V1 不同步业务附件，仅同步结构化字段、文字与头像（25A）；无 FCM 时采用系统机会型后台同步，不承诺固定分钟时效（26A）。
- 风险与门禁：22C 仅视为当前测试阶段范围决定；公开发布前必须重新评审账号注销和云端个人数据删除能力。30 天缓存清理按“到期后在下次启动或系统允许时执行”设计，不能承诺设备长期关机时准点清除。公网 IP 是否固定仍待用户补充。
- 验证状态：本轮为需求设计与现有 Contract 字段核对，无构建、测试或设备验证。下一步确认首次账号同步方向、实体级冲突策略、重复日程语义、设备数量、安全验证及 V1 发布性质。
- 开发时间：2026-09-03 19:50 +08:00（Asia/Shanghai）。

## 2026-09-03 20:00 +08:00 云同步第四轮冲突与设备规则冻结

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。继续收敛云同步冲突模型、时间语义、重复规则与设备治理；未修改产品代码、Contract 或数据库。
- 负责模块：退出前同步、发布边界、首次账号同步、字段级冲突、HabitCheckIn 并发、删除与编辑竞争、跨时区语义、重复系列、设置同步和设备管理。
- 已确认产品决策：退出前尝试最终同步并提示未上传数量（27A）；V1 为内测/有限测试，公开发布前补齐账号注销与云端数据删除（28A）；首次登录先取得云端基线再合并本机待同步操作（29A）；不同字段自动合并、相同字段进入用户冲突处理（30A）；习惯增量打卡按幂等操作累计，清空或直接改总数发生竞争时提示冲突（31A）；删除优先隐藏对象但保留竞争编辑版本供恢复（32A）；按定时、全天、纪念日/打卡日期与重复规则分别保持正确时区语义（33A）；重复日程同步系列规则与稳定例外记录（34A）；个人信息与可移植设置采用服务端接收顺序，不进入业务冲突中心（35A）；最多 10 台活跃设备，支持命名、重新验证后移除及联网后清缓存（36A）。
- 冲突管理 UX：入口固定为“我的 → 冲突管理”；存在未解决冲突时卡片右上角显示红点，全部解决后消失。详情必须展示业务对象、具体冲突字段、本机与云端值、修改设备及时间，并提供保留本机、保留云端或手动编辑。
- 验证状态：本轮仅完成需求设计和开发日志追加，未执行构建、测试或设备验证。下一步确认未解决对象行为、冲突留存、多账号与共享范围、运营备份、部署监控、内测容量及公网 IP 稳定性，再形成正式开发计划。
- 开发时间：2026-09-03 20:00 +08:00（Asia/Shanghai）。

## 2026-09-03 20:23 +08:00 云同步最终产品与内测运维决策冻结

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。完成冲突中心、多账号、共享边界和内测运维的产品决策收敛；未修改产品代码、Contract 或数据库。
- 负责模块：冲突态交互、冲突副本保留、多账号缓存隔离、跨账号共享边界、服务器备份、部署拓扑、监控告警、冲突提示和容量基线。
- 已确认产品决策：冲突对象可查看，修改须经冲突详情完成（37A）；未解决冲突持续保留、解决后保留30天（38A）；同一时刻仅一个活跃账号但允许多个独立加密缓存（39A）；V1不支持跨账号分享或协作（40A）；内测期暂不做服务器灾难恢复备份（41B）；采用单台Linux服务器部署且数据库/Redis不暴露公网（42A）；仅保留服务器日志并人工排查（43B）；新冲突使用一次性应用内提示与“我的”红点（44A）；首轮按100账号、每账号最多10台设备和数万条结构化记录设计及压测（45A）。
- 风险与发布门槛：41B和43B只适用于可接受数据丢失与人工排障的小规模内测，产品不得把云同步宣传为可靠备份。公开发布前必须至少补齐离机加密备份及恢复演练、证书/服务/磁盘/备份失败基础告警，并重新评审账号注销与云端数据删除。
- 验证状态：本轮为需求设计和风险记录，没有执行构建、测试或设备验证。正式计划仍需确认公网IP稳定性、服务器操作系统及CPU/内存/磁盘规格；未知时可采用显式容量假设，不阻塞架构计划，但会使部署容量结论保持未验证。
- 开发时间：2026-09-03 20:23 +08:00（Asia/Shanghai）。

## 2026-09-03 20:41 +08:00 云同步 active 总计划建立

- 使用 Skill：`calendar-data-contracts`、`backend-api-development`。根据已完成的需求访谈、当前 SQLite v5/Android/Cloud Backend 代码基线与测试服务器条件，建立 Local-first 多设备同步正式总计划；未实施产品代码、Contract、数据库迁移或服务器变更。
- 负责模块：同步产品边界、workspace/账号隔离、SQLite Outbox 与加密、Backend 设备/版本/change feed、字段级冲突、提醒意图、本机调度、Kotlin 后台同步、Flutter 冲突 UX、测试部署和端到端验收。
- 任务结果：新增 `docs/plan/active/云同步-01-Local-first多设备同步开发计划.md`，共 27 节、209 项已确认/待办清单，覆盖 V1 数据闭包、分层职责、SQLite v6、设备顺序与 Cursor、冲突算法、SessionCredentialBroker、分阶段实施、验证矩阵、容量目标、风险、工作量及 V1.1/V2 演进；同步将 current/roadmap/index 与 SyncOperation/UserSyncState 状态更新为 `ACTIVE PLAN / CONTRACT PENDING`，并继续明确现有 Schema/空包不代表同步已实现。
- 测试服务器结论：CentOS 7、4 核、4 GB、50 GB 仅作为 100 账号以内的短期测试环境。CentOS 7 已 EOL，当前 Docker 官方不再支持该版本；计划要求只复用经验证可工作的现有容器运行时，预构建镜像后部署，PostgreSQL/8080 不暴露公网，无法兼容时更换受支持系统。41B/43B 的无灾备和仅日志人工排查仅作为内测风险，公开发布前必须补齐。
- 关键停止条件：账号缓存加密依赖需先完成 ADR、许可证/三 ABI/迁移/性能 spike；后台同步前必须统一 Refresh Token 刷新所有权；生产同步 Contract 冻结前不得开始各层业务实现。
- 验证状态：计划文件存在，共 982 行、209 个清单项、无行尾空白；相关状态文档未再命中“同步尚无 active plan / DECISION_REQUIRED”；目标 tracked 文档 `git diff --check` 通过，仅有仓库既有 LF/CRLF 提示。由于本任务只建立计划和文档，未执行 C++、Backend、Flutter、Android 构建、测试或真机验证。
- 开发时间：2026-09-03 20:41 +08:00（Asia/Shanghai）。

## 2026-09-04 00:09 +08:00 Flutter 启动入口目录误用诊断

- 使用 Skill：`debug`。按证据驱动流程核对运行目录、Flutter 包名和 Dart 入口；未修改产品代码或构建配置。
- 负责模块：Flutter 启动入口与本地真机运行命令。
- 任务目标：确认从 `A:\calendar\Flutter_test` 执行 `flutter run -d 3L1F96E8NZVEBNH2` 是否错误启动了学习工程，以及 ExcellentCalendarAPP 的正确入口。
- 任务结果：确认当前目录的 `pubspec.yaml` 声明包名 `beginner_flutter_app`，其 `lib/main.dart` 启动 `BeginnerFlutterApp`；正式客户端位于 `A:\calendar\ExcellentCalendarAPP\flutter_client`，包名为 `excellent_calendar`，入口 `lib/main.dart` 启动 `buildProductionApp()`。根因是运行目录选错，不是 `-d` 设备参数选错。
- 验证状态：完成静态路径、包名、入口函数、Android applicationId/label 与项目运行指南核对；未实际执行 `flutter run`，未对真机安装状态作变更。

## 2026-09-04 00:29 +08:00 ReminderResponse `advance_days` 协议漂移修复

- 使用 Skill：`debug`、`calendar-data-contracts`。按证据驱动流程复现报错，并核对 Reminder 领域文档、Accepted ADR、Contract、C++ writer、Kotlin validator 与 Dart reader。
- 负责模块：Flutter Dart Gateway/DTO 边界及 ReminderResponse 契约回归测试。
- 任务目标：修复创建含提醒日程后，合法 Native v2 ReminderResponse 因 `advance_days` 被 Dart 误判为未知字段的问题，并检查同一共享响应中的相邻字段与枚举漂移。
- 任务结果：确认 2026-08-23 起 Anniversary/Habit 扩展已同步到 JSON Schema、C++ 与 Kotlin，但 Dart `ReminderResponseDto` 和测试 fixture 仍停留在旧字段集。现已补齐 6 个 target-specific 字段、Anniversary/Habit 取消与过期枚举、UUID/单方法/目标互斥分支校验；Event 分支继续要求这些字段存在且为 `null`。Contract、C++、Kotlin、Storage 与版本号均未变更，无数据迁移。
- 验证状态：修复前聚焦测试稳定复现 `ReminderResponse contains unknown field: advance_days`；修复后 Reminder DTO 9/9、相关 Event/Reminder 测试、Flutter 全量 593/593、`flutter analyze`、定向格式检查、Calendar/Anniversary/Habit 机器 Contract 校验、Android Debug APK 构建和 C++ build-after-test 13/13 全部通过。RMX5100 Android 16 真机端到端用例已通过真实 Flutter → Kotlin → JNI → C++ → SQLite 创建带 popup Reminder 的日程、读取并解析 Event Detail/ReminderResponse，并在 `finally` 中成功软删除测试日程。

## 2026-09-04 01:xx +08:00 Tool calling 工程学习说明

- 使用 Skill：`self-learning`、`openai-docs`。
- 负责模块：AI Pipeline / AI Extraction 架构理解。
- 任务目标：说明应用接入自定义 AI tool calling 的实现步骤、生产环境风险与需掌握的底层原理。
- 任务结果：核对当前 AI 提取 Contract、候选结果边界与官方 Function Calling 文档；未修改任何运行时代码或协议。
- 验证状态：完成文档与只读代码/Contract 核对；无构建或测试需要执行。

## 2026-09-04 15:26 +08:00 日历页 Presentation 视觉统一

- 使用 Skill：`frontend-flutter-feature`。按参考图收敛日历页背景与顶部栏，仅修改 Flutter Presentation、视觉 token 和 Widget 测试；未新增依赖，未修改 Application、Gateway、Contract、Native 或领域逻辑。
- 负责模块：共享页面背景 token、Inbox 日程页背景引用、Calendar 页面背景、CalendarHeader 顶部月份与三个工具按钮、日历页回归测试。
- 任务目标：使浅色模式下日历背景与日程页统一；年月标题改为“一月”至“十二月”的纯中文月份，字号缩为原来的 2/3；顶部按参考图保留视图、时间线、更多三个自然融入背景的图标按钮，同时保留年月选择、横滑翻页、周/月切换和“今天”返回能力。
- 任务结果：新增共享浅蓝灰页面背景 token；日历浅色背景与日程页统一为 `#E6F8FA`，深色模式继续使用 Theme surface 以保持对比度；标题移除年份、数字月份、下拉箭头和显式前后翻页按钮，标准 360dp 宽度下与三个工具按钮同行；工具按钮改为透明表面、28dp 现代图标和纵向更多菜单样式。现有控制器、数据状态与回调语义未变。
- 验证状态：目标 6 个 Dart 文件格式检查通过；日历页定向测试 28/28、Flutter 全量测试 594/594、`flutter analyze`、`flutter build apk --debug` 和目标 diff check 均通过。仓库级全量格式检查另发现本轮未修改的 `test/create_schedule_controller_test.dart` 既有格式差异，未越界改动；未执行真机视觉、TalkBack 或不同厂商字体渲染验证。

## 2026-09-04 17:27 +08:00 云同步 active 分计划一致性审阅

- 使用 Skill：`calendar-data-contracts`。按总计划、当前状态/路线图、领域真相源、Contracts 分计划及四层实现分计划的顺序进行只读交叉审阅；未修改任何计划正文、Contract 或产品代码。
- 负责模块：`docs/plan/active/` 中云同步 01–06 总计划与分计划，以及相关同步、提醒、偏好、重复日程和数据迁移边界。
- 任务目标：检查分计划缺陷、相对总计划/路线图的偏差、分计划间冲突，以及冗长和重复表述。
- 任务结果：确认存在 Source of Truth 顺序、Android run intent 闭包、冲突解决后的提醒 reconcile、通配 `_count` 上限规则等直接口径冲突；发现 WorkManager 机会调度、30 天缓存计时、timezone/follow-device、默认提醒方式、导入后本机审计数据、Search History 处置等未闭合设计；同时确认重复抄写已造成语义漂移，工作量估算与分计划实际范围不匹配。问题明细已在本次审阅回复中按严重度和文件行号列出。
- 验证状态：完成 6 份 active 云同步计划（合计约 5,150 行、439.5 KiB）与相关架构、状态、路线图、领域文档和现有同步占位 Contract 的静态核对；执行行长/重复度统计和定向关键词交叉检查。由于本次仅审阅文档，未运行 C++、Backend、Flutter、Android 构建、测试或真机验证。

## 2026-09-04 17:39 +08:00 日历画布与折叠分组卡片美化

- 使用 Skill：`frontend-flutter-feature`。依据参考图调整 Calendar Presentation，复用 Inbox 日程页的加号组件与折叠动效；未修改 Application、Gateway、Contract、Kotlin、C++ 或持久化逻辑，未新增依赖。
- 负责模块：CalendarGrid 日历画布、CalendarSections 日期内容分组、CalendarPage 新建入口、Inbox AddTaskButton 可访问标签复用及日历 Widget 测试。
- 任务目标：移除日历网格的灰色卡片外框并融入页面背景；在日期标题下按“已完成、日程、习惯、纪念日”展示与日程页一致的白色折叠卡片；将当天完成日程与完成习惯聚合到第一组且避免重复；将扩展 FAB 替换为日程页同款圆形加号。
- 任务结果：网格移除 tonal panel、outline 与阴影，保留日期选中态、圆点和手势；四张卡片固定显示并提供数量、空态、右侧旋转箭头和 AnimatedSize 展开/折叠，已完成组默认折叠、其余组默认展开；完成 Event/Habit 仅在已完成组展示，原分页、详情回跳、错误/加载状态及创建底部面板继续使用现有回调；右下角直接复用 58dp AddTaskButton，并使用日历专属 Semantics 标签。
- 验证状态：本轮目标 5 个 Dart 文件格式检查通过；日历页定向测试 30/30、Flutter 全量测试 596/596、`flutter analyze`、`flutter build apk --debug` 和 `git diff --check` 均通过。仓库级全量格式检查仍仅报告本轮未修改的 `test/create_schedule_controller_test.dart` 既有格式差异，未越界修改；未执行真机视觉、TalkBack 或不同厂商字体渲染验证。

## 2026-09-04 17:57 +08:00 日历动态空态与跟手月份滑动

- 使用 Skill：`frontend-flutter-feature`。仅调整 Calendar Presentation 和 Widget 测试；未修改 Application、Gateway、Contract、Kotlin、C++、持久化或第三方依赖。
- 负责模块：CalendarSections 动态分组可见性与无任务插画、CalendarGrid 前后月份预览和横向跟手分页、CalendarPage 手势归属、日历页面回归测试。
- 任务目标：无待处理日程、习惯或纪念日时隐藏对应卡片；全部类别均为空且已完成也为零时，直接在背景显示插画及“空空如也的任务”；横滑日历时同步露出灰色相邻月份，越过中点后自然完成翻页。
- 任务结果：已完成组仅在存在完成日程或完成习惯时显示，其余三组仅在存在对应未完成内容或仍需承载分页/错误状态时显示；全空状态使用主题色 CustomPainter 绘制轻量清单插画，文字置于图下且没有卡片背景。日历新增前一页/当前页/后一页三页轨道，拖动实时跟随手指，相邻页降为 46% 不透明度，50% 位移或快速甩动触发 360ms 缓出归位/翻页；实际月份与数据仍由既有 CalendarController 切换。
- 验证状态：修改文件定向格式检查、日历页测试 31/31、Flutter 全量测试 597/597、`flutter analyze`、Android Debug APK 构建和目标 diff check 均通过。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有格式差异，未越界处理；未执行真机触控、视觉或 TalkBack 验证。

## 2026-09-04 18:24 +08:00 日历分页流畅度与上下分区拖动修正

- 使用 Skill：`debug`、`frontend-flutter-feature`。先根据现有实现和 Widget 场景定位卡顿领先原因，再仅修改 Flutter Calendar Presentation 与对应测试；未修改 Application、Gateway、Contract、Native、持久化或依赖。
- 负责模块：CalendarGrid 横向分页绘制与固定六行布局、CalendarPage 上下分区和展开进度、分隔拖柄、下方日程独立滚动、手势回归测试。
- 任务目标：改善左右滑动不自然和月份行数变化导致的上下跳动；加入可拖动短横线，使上方日历可跟手收起到选中日期所在的一周；上方日历纵向手势提供同样效果，下方日程只滚动自身。
- 任务结果：确认上一版横滑在每一帧 `setState` 重建三页日期网格，并按相邻月份行数插值改变高度，这是卡顿与垂直抖动的高置信度代码原因；现改为由轻量位移监听器只更新三页轨道 Transform，并用 RepaintBoundary 隔离日期网格，余程决定 240ms 内的缓出时间。月历 Presentation 固定生成 42 个日期位置和六行高度，相邻月继续弱化，加载条预留固定高度。页面拆成上方日历、28dp 可点击/可拖动短横线、下方独立 RefreshIndicator/CustomScrollView；日历或拖柄纵向拖动时连续更新 1–6 行高度，并同步平移网格使选中日所在周始终留在裁剪窗口，结束后才调用既有 Controller 提交 week/month 状态。CalendarState 的 selectedDate 始终必填，冷启动已由既有 Controller 设为 today，因此无需新增“无选中日期”业务分支。
- 验证状态：日历页测试 30/30、Flutter 全量测试 596/596、`flutter analyze`、Android Debug APK 构建、目标文件格式和 `git diff --check` 均通过；新增覆盖固定六行、相邻月灰显、上方直接拖动、拖柄跟手且保留选中周、下方独立滚动、水平预览与翻页。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有格式差异。未执行真机帧时间 profiling、触控手感、TalkBack 或厂商字体验证，因此“主观手感改善”仍需设备确认。

## 2026-09-04 18:41 +08:00 云同步计划外部审阅问题复核与协调修订

- 使用 Skill：`calendar-data-contracts`。逐项对照云同步01–06、当前领域不变量、Accepted ADR/路线图、机器Contract占位状态、现有分层架构与Android官方后台任务/时钟语义；未实施产品代码、机器Contract、数据库或服务端接口。
- 负责模块：云同步总计划、Contracts/数据、C++/SQLite v6、CloudBackend、Kotlin/Android、Flutter五份分计划，以及`docs/index.md`、`docs/status/current.md`、`docs/status/roadmap.md`中的计划状态口径。
- 任务目标：验证外部审阅提出的15项问题是否真实存在，只修订成立或部分成立的内容，并重新校准五层之间及其与总计划、现有架构/路线图的关系。
- 研判结果：12项成立，3项部分成立，0项完全不成立。部分成立的是30天缓存的严格物理删除承诺、本机导入后审计/搜索历史问题、`PLAN COMPLETE`等状态标签；其核心风险真实，但审阅中的“可以构造精确跨重启本地时钟”“Search History具有业务对象/标题引用（实际只存规范化关键词，文本仍可能与标题相同）”及“PLAN COMPLETE必然等于能力完成”等推论不完整。
- 修订结果：统一双阶段Source of Truth裁决；补齐五态run intent；禁止本地冲突提交提前reconcile；把checked increment限制到机器counter registry；固定WorkManager `APPEND_OR_REPLACE`与耐久补排；冻结workspace/OS timezone双轴、默认提醒目标矩阵、workspace-scoped Search History方案和guest导入后的live/执行/审计处置；将locale移出同步白名单并保留注册固定`zh-CN`兼容；把重复Event三作用域退回R3；统一六份计划状态，重做早期ROM、M0拆分与重估门禁，并把自审结论降为Contract冻结前的计划级目标。
- 验证状态：18项定向跨计划一致性断言全部通过；六份计划均为合法UTF-8、无冲突标记，tracked `git diff --check`通过，02–06逐文件no-index检查仅在清理前发现标题区Markdown硬换行尾空格并已移除。由于本任务只审阅和修订计划，未运行C++、Backend、Flutter、Android构建、测试或真机验证；ADR、机器Contract、fixture和生产实现仍为待办。
- 开发时间：2026-09-04 18:41 +08:00（Asia/Shanghai）。

## 2026-09-04 19:31 +08:00 搜索页方案 C 视觉美化

- 使用 Skill：`frontend-flutter-feature`。仅修改 Search Presentation、Widget 测试与既有 Golden；未修改 Application、Gateway、Contract、Kotlin、C++、持久化、依赖或工具链。
- 负责模块：SearchPage 页面背景与焦点状态桥接、SearchHeader 标题/搜索框过渡、SearchHistoryCard 紧凑历史标签、SearchSectionCard 三类结果卡片、SearchLoadingSkeleton 和搜索页面视觉回归测试。
- 任务目标：采用用户确认的方案 C；页面背景与日程/日历统一；历史按钮及文字缩小到参考稿约 2/3；“搜索”标题缩小到原来的 3/4；点击输入框后标题自然消失并让搜索框缓慢上移到顶部；结果尽量贴近参考稿的柔和卡片风格。
- 任务结果：浅色 Search 使用共享 `AppColors.lightPageBackground`；标题按 0.75 比例呈现，搜索框获得焦点时通过 300ms 淡出/尺寸过渡收起标题并同步上移；筛选入口并入白色胶囊搜索框；历史由整块列表卡改为 28dp 高、12sp 字体的轻量胶囊标签，同时保留长按管理、删除、清空与撤销；日程/习惯/纪念日结果改为白色圆角卡片、蓝/绿/粉侧边强调和轻阴影，深色主题继续由 Theme 派生。
- 验证状态：搜索页定向测试 9/9、Flutter 全量测试 598/598、`flutter analyze`、Android Debug APK 构建、目标文件格式与目标 diff check 均通过；4 张 Search Golden 已更新并人工检查布局/颜色。仓库级格式检查仍仅报告本轮未修改的 `test/create_schedule_controller_test.dart` 既有格式差异，未越界修改；未执行真机触控手感、输入法、TalkBack 或厂商字体渲染验证。

## 2026-09-04 19:55 +08:00 搜索分组计数与模块色高亮调整

- 使用 Skill：`frontend-flutter-feature`。仅调整 Search Presentation、Widget 测试和既有 Golden；未修改搜索状态、查询、排序、分页、Gateway、Contract 或 Native。
- 负责模块：SearchSectionCard 分组标题/计数、SearchResultRow 模块色传递、HighlightedSearchText 命中样式、SearchDesignTokens 同系高亮色和 Search 页面视觉测试。
- 任务目标：把结果分组标题改为“日程（数量）/习惯（数量）/纪念日（数量）”；标题与数量使用模块色；移除偏黄色的命中高亮并改为对应模块色。
- 任务结果：分组标题与数量合并为一个紧邻文本，日程使用蓝色、习惯按参考图和模块既有语义使用绿色、纪念日使用粉色；标题与摘要中的关键词改为对应模块色文字叠加 16% 浅色背景，深色模式使用 24% 同系背景，不再使用黄色 token；同一卡片只计算一次模块色并传给所有结果行，未复制业务逻辑。
- 验证状态：搜索页定向测试 9/9、Flutter 全量测试 598/598、`flutter analyze`、Android Debug APK 构建、Search 目标格式检查与 Golden 更新/人工检查均通过。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有差异；未执行真机颜色、TalkBack 或厂商字体渲染验证。

## 2026-09-04 20:07 +08:00 搜索历史浅蓝标签与结果密度调整

- 使用 Skill：`frontend-flutter-feature`。仅修改 Search Presentation、Widget 测试和既有 Golden；未修改 Application、Gateway、Contract、Native、持久化或依赖。
- 负责模块：SearchPalette 历史标签颜色 token、SearchHistoryCard 标签绘制、SearchResultRow 字号与垂直密度、Search 页面行为/视觉回归测试。
- 任务目标：历史按钮使用参考图中的浅蓝色而非灰色；搜索结果标题字号缩为分组标题约 3/4；同卡片内相邻搜索结果的纵向距离缩为当前约 2/3。
- 任务结果：浅色历史标签固定为浅蓝底、淡蓝描边和蓝色文字，深色模式提供同系适配；结果标题由 16sp 缩至 12sp；结果行上下 padding 由 15dp 缩至 10dp，标题、元数据、摘要和状态之间的间隔同步缩小，常规结果行仍高于最小触控高度；业务点击范围和数据逻辑保持不变。
- 验证状态：搜索页定向测试 9/9、Flutter 全量测试 598/598、`flutter analyze`、Android Debug APK 构建、Search 目标格式检查和 4 张 Search Golden 更新/人工检查均通过。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有差异；未执行真机字体、触控密度或 TalkBack 验证。

## 2026-09-04 20:19 +08:00 搜索结果卡片细节对齐参考图

- 使用 Skill：`frontend-flutter-feature`。仅修改 Search Presentation、Widget 测试和既有 Golden；未修改查询、分页状态、Gateway、Contract、Native 或依赖。
- 负责模块：SearchSectionCard 分隔线/更多结果行、SearchResultRow 对齐/尾部信息、SearchDesignTokens 卡片内容间距，以及 Search 页面布局和大字体回归测试。
- 任务目标：在保持现有字体大小和模块颜色不变的前提下，对齐参考图中的卡片空白、文字基线、分隔线与箭头细节。
- 任务结果：结果正文左侧缩进改为与分组标题文字对齐；移除标题下方整行分隔线、普通结果之间的分隔线以及每条结果右侧的重复箭头；仅在存在更多分页结果时显示一条从正文缩进开始的分隔线，并提供“还有 N 个日程/习惯/纪念日”与右箭头，继续调用原有 loadMore；Event 开始时间和 Anniversary 相对天数移到行尾，Anniversary 左侧元数据仅保留日期；未添加缺少真实导航行为的装饰性“查看全部”按钮。
- 验证状态：搜索页定向测试 11/11、Flutter 全量测试 600/600、`flutter analyze`、Android Debug APK 构建、Search 目标格式检查和 4 张 Search Golden 更新/人工检查均通过；新增覆盖唯一分页箭头、仅一条分页分隔线、正文/标题对齐及 360dp + 200% 字号结果卡无溢出。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有差异；未执行真机触控、TalkBack 或厂商字体渲染验证。

## 2026-09-04 19:10 +08:00 云同步 15 项返修结果独立复核

- 使用 Skill：`review-worktree-architecture`。按当前架构、状态、领域规则、机器 Contract 与云同步 01–06 active 计划建立独立判据，只读复核返修说明；未修改计划正文、Contract 或产品代码。
- 负责模块：Local-first 云同步计划、状态口径、WorkManager 唤醒、退出缓存保留、提醒偏好、冲突生命周期、测试服务器网络边界。
- 任务目标：判断外部返修给出的 15 项结论是否合理，确认当前真实状态、用户仍需决定的事项和返修后残留的不一致。
- 任务结果：确认五态 run intent、服务端 resolved/effect apply 后才产生 affected identities、counter registry、timezone 双轴、Reminder 适用矩阵、重复 Event 三作用域延后、计划状态与早期 ROM 等主体修订方向成立；识别出 `APPEND_OR_REPLACE` 每次 writer 均追加可能造成无界 Worker 链、force-local 无可信时间锚时缓存可能无限期隐藏、IP 证书与 DNS-only 公网要求冲突、提醒偏好“只影响未来设备”与字段命名/首设备例外未完全闭合，以及同步领域页/旧 `sync.apply`/Auth status/Contracts-02 真相源表述仍未完全校准。导入后的审计 anchor 仍须由 ADR/机器 Contract 唯一冻结，不能视为已经可实现。
- 验证状态：完成六份计划状态、关键枚举、旧估算/状态标签、locale、重复编辑范围和跨层关键语义的定向静态断言；六份计划本地 Markdown 链接检查为 0 个缺失，`git diff --check` 无空白错误（仅既有 LF/CRLF 提示）。依据 Android 官方文档复核 WorkManager policy、`elapsedRealtime` 与后台执行时点；依据官方资料复核 CentOS 7 EOL、Docker 当前支持范围及公网 IP 证书可用性。任务为文档审阅，未运行 C++、Backend、Flutter、Android 构建、测试或真机验证。
- 开发时间：2026-09-04 19:10 +08:00（Asia/Shanghai）。

## 2026-09-04 19:07 +08:00 搜索页面视觉方向调研

- 使用 Skill：`frontend-flutter-feature`、`imagegen`。结合现有 Search Presentation、公开的 Android Material、Apple 搜索规范与成熟产品搜索范式，制作三种仅用于方向选择的界面概念稿。
- 负责模块：Search 页面视觉层次、背景、搜索框、筛选入口、历史记录与三类结果分组的展示方案；未修改 Flutter 页面、Application、Gateway、Contract、Native、持久化或依赖。
- 任务目标：统一日程/日历页浅蓝背景，并在需求尚未具体化时提供可直观比较的轻盈聚焦、效率优先、柔和卡片三种现代搜索页方向。
- 任务结果：完成 A/B/C 三方案对比与适用场景分析；基于用户既有“减少灰色卡片、融入背景”的偏好，建议以 A 轻盈聚焦为主体，并在结果较多时吸收 B 的类型筛选标签和紧凑结果行。等待用户确认方向后再实施 Presentation 修改。
- 验证状态：本轮未修改产品代码，因此未运行 Flutter 格式化、静态分析、测试、构建或真机验证；生成图仅为视觉沟通稿，不作为最终像素规格。

## 2026-09-04 19:19 +08:00 云同步分计划返修说明二次审阅

- 使用 Skill：`calendar-data-contracts`。只读对照云同步 01–06、同步/提醒/偏好领域文档、当前机器 Contract 与状态文档，并复核 Android 官方 WorkManager、`SystemClock` 和后台执行时点说明；未修改计划正文、Contract 或产品代码。
- 负责模块：Local-first 云同步总计划、Contracts/数据、C++/SQLite v6、CloudBackend、Kotlin/Android、Flutter 五份分计划及相关状态/领域口径。
- 任务目标：独立判断返修方对 15 项审阅意见的判断与处理是否合理，确认哪些问题已关闭、哪些仍需产品负责人决策，以及是否出现新的跨计划缺口或冗余。
- 任务结果：确认 1–4、6–7、12、14–15 已在计划层基本闭合，9 的事实纠正成立且其审计表示仍受 ADR/Contract 冻结门禁，10–11 的方案技术上可行但属于产品取舍；5 的 `KEEP` 丢唤醒判断成立，但 `APPEND_OR_REPLACE` 不提供请求去重，现有“unique chain 去重”表述会留下高频写入下的冗余 Worker 链；8 将严格 30 天改为目标窗口符合 Android 能力边界，但离线 force-local 无可信锚时允许缓存无限期隐藏，仍需产品负责人明确接受或改为隐私优先销毁。另发现同 boot 证明所需 `boot_id` 没有冻结来源/轮换规则、总计划仍写“IP 证书”而 Backend/Android 分计划只允许 DNS hostname、两个同步领域页仍写“产品决策已经冻结”，与当前 `CONTRACT PENDING` 状态冲突。六份计划共 5,223 行，293 行超过 300 字、28 行超过 800 字，长句和跨计划重复仍是明确审阅债。
- 验证状态：完成关键枚举、状态标签、时区/提醒矩阵、locale、重复 Event 范围、Search History、导入审计、WorkManager 队列、保留时钟和公网入口的定向静态核验；未运行代码构建、测试或真机验证，因为本次为文档审阅。工作区存在用户/其他任务的既有修改与未跟踪计划文件，均保持原状。

## 2026-09-04 20:31 +08:00 搜索结果标题字号微调

- 使用 Skill：`frontend-flutter-feature`。仅修改 Search Presentation 的字号令牌、对应 Widget 测试和既有 Golden；未修改搜索业务逻辑、状态、Gateway、Contract、Native 或依赖。
- 负责模块：SearchResultRow 搜索结果标题展示与搜索页视觉回归。
- 任务目标：将日程、习惯和纪念日栏目内的搜索结果标题，调整为原结果标题字号与栏目标题字号的中间值。
- 任务结果：结果标题比例由 0.75 调整为 0.875；当前主题下由 12sp 调整为 14sp，正好位于结果原字号 12sp 和栏目标题 16sp 之间；卡片间距、颜色、分隔线、箭头与搜索行为保持不变。
- 验证状态：搜索页定向测试 11/11、Search Golden 4/4、Flutter 全量测试 600/600、`flutter analyze`、Android Debug APK 构建和 Search 目标格式检查均通过；视觉基准已更新并人工检查。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有差异；未执行真机厂商字体渲染验证。

## 2026-09-04 20:42 +08:00 日历分界线拖动触发下半区闪刷修复

- 使用 Skill：`debug`。按分界线拖动 → 视图模式提交 → CalendarController 状态切换 → CalendarSections 动画链路复现并修复；未修改 Contract、Gateway、Native、持久化或领域数据规则。
- 负责模块：Flutter CalendarController 视图模式状态过渡、CalendarSections 内容切换动画与 CalendarPage 手势回归测试。
- 任务目标：上下拖动日历与日程分界线时，只改变布局，不让已经显示的选中日内容清空、出现骨架屏或因快照编号变化整块重新淡入。
- 任务结果：确认根因是 `setViewMode` 在布局模式切换时立即丢弃完整快照并把三个栏目重置为 loading，且结果区动画 Key 包含 snapshot token；现改为在月/周范围后台更新期间保留当前完整日内容，并仅在选中日期或可见条目标识真实变化时切换结果区。范围摘要与快照一致性校验仍保留，真实数据变化仍会正常更新。
- 验证状态：新增回归测试在修复前稳定失败、修复后通过；Calendar Controller + Page 定向测试 66/66、Flutter 全量测试 601/601、`flutter analyze`、Android Debug APK 构建、目标格式检查和 `git diff --check` 均通过。仓库级格式检查仍只报告未修改的 `test/create_schedule_controller_test.dart` 既有格式差异；未执行真机手势录屏或厂商帧率验证。

## 2026-09-04 20:47 +08:00 云同步分计划语义去重与锚点收口

- 使用 Skill：`calendar-data-contracts`。按 Contract 唯一语义、跨层字段闭包和迁移可追踪原则审阅并精简计划；未修改机器 Contract、Schema、产品代码或数据库。
- 负责模块：云同步-02 Contracts、云同步-03 C++/SQLite、云同步-04 CloudBackend、云同步-05 Kotlin/Android、云同步-06 Flutter 五份分计划；用户明确排除的云同步-01 总计划本轮未修改。
- 任务目标：独立判断外部审阅所称的重复啰嗦是否真实存在，区分必要的接口追踪与危险的语义重定义，只修改成立或部分成立的问题。
- 研判结果：Contracts、C++、Backend、Android 的后段阶段/测试/交接/DoD 确有对前段算法换词重述的问题，Flutter 仅测试与 DoD 部分成立；方法签名、字段映射、层级职责和测试消费关系虽会重复出现，但承担可追踪性，不应删除。长行数量只能作为可读性信号，不能单独证明语义重复。
- 修订结果：为 02–06 增加文内语义锚点；Contracts 将导入唯一收口为 `IMP-01`–`IMP-12`，将跨层测试唯一登记为 20 个 `FX-*` fixture 族；03–06 的阶段、测试、交接和完成定义改为引用规范章节与 fixture，不再另写算法；C++ 约 2,045 字符的错误所有权段改为职责表，并校准压缩后阶段/测试表的章节引用。五份分计划由 4,104 行、623,223 bytes 精简为 3,797 行、555,157 bytes，超过 800 字符的行由 28 降为 0。
- 验证状态：137 项状态、Source of Truth、导入锚点、fixture 闭包、五态 run intent、冲突 reconcile、WorkManager policy、UTF-8、代码围栏、冲突标记和本地链接断言通过；02–06 全局不存在长度至少 80 字符的完全重复行，281 个长段落的 8 字符 shingle 检查未发现相似度至少 0.45 的同文件近重复。`git diff --check` 通过，未跟踪的 02–06 逐文件无空白错误；仅有仓库既有的 LF→CRLF 提示。本任务只修改计划，未运行 C++、Backend、Flutter、Android 构建、测试或真机验证，机器 Contract 与实现仍为待办。

## 2026-09-04 21:38 +08:00 云同步队列、保留时钟与公网口径复审修订

- 使用 Skill：`calendar-data-contracts`。按领域→Contract→Android/Flutter映射顺序审阅计划与当前实现，并以Android官方WorkManager、SystemClock和BOOT_COUNT语义校准平台约束。
- 负责模块：云同步-01总计划、云同步-02 Contracts、云同步-04 CloudBackend、云同步-05 Kotlin/Android、云同步-06 Flutter，以及`sync_operation`、`user_sync_state`两份领域状态说明；未修改产品代码或现有机器Contract。
- 任务目标：独立判断外部审阅提出的APPEND去重、无可信时间锚的30天保留、`boot_id`生成、公网入口和状态标签五项问题，并只修正确实存在的缺口。
- 研判与结果：五项均真实存在。APPEND_OR_REPLACE只串行追加而不去重，现冻结Application级`SyncWakePump`、稳定WorkRequest id、每workspace最多一个running加一个successor及10,000次触发门禁；30天产品分支按隐私优先收口，无同boot可信锚的force-local只能destroy-now或取消/重试，retain返回`RETENTION_TRUSTED_TIME_REQUIRED`且零终止；新增`allowed_cache_policies`跨层闭包。`boot_id`固定为Kotlin-local UUIDv4，由API24+ BOOT_COUNT与elapsed校验、API23 process-only降级、no-backup AEAD记录及异常fail-closed共同定义。公网入口统一为受控DNS hostname/SAN，IP literal/IP证书退出目标状态；两份领域页恢复为`ACTIVE PLAN / CONTRACT PENDING / IMPLEMENTATION NOT STARTED`。
- 验证状态：定向检索确认当前仓库没有SyncCoordinator/SyncWorker/RetentionDeadline/BootEpoch实现，现有APPEND_OR_REPLACE只属于Reminder队列且WorkManager依赖为2.11.2；新旧口径静态断言、UTF-8、代码围栏、≤800字符行与目标文件尾随空白检查通过，`git diff --check`无空白错误（仅既有LF→CRLF提示）。本任务为计划修订，未运行C++、Backend、Flutter、Android构建、测试或真机验证；受控公网域名/DNS权限、机器Contract与实现仍为待办。

## 2026-09-05 11:44 +08:00 云同步五项返修最终复核

- 使用 Skill：`calendar-data-contracts`；负责模块：云同步总计划、Contracts、Android、Backend、Flutter与同步领域状态说明。
- 任务目标：复核工程师五项修订的实际落点与平台依据，判断是否存在阻碍进入下一阶段的重大问题。
- 任务结果：五项在计划层基本闭合；唤醒合并已明确串行owner、两节点上限、稳定WorkRequest身份和崩溃恢复验收；无可信锚force-local不允许retain且错误请求不自动删除；boot identity来源、存储、降级和异常路径已明确；DNS与领域状态口径已统一。本轮定向复核未发现新增重大阻断，可推进M0 ADR/spike与M1 Contract冻结；既定加密/协议实验、机器Contract/fixture和实现验收仍须执行，受控域名与DNS权限仍是公网验收前置条件。
- 验证状态：只读检查实际计划、相关领域状态与Android生产代码，并通过Android官方文档确认setId自WorkManager 2.8.0提供、BOOT_COUNT自API 24提供且值类型为int。实际WorkManager依赖为2.11.2；未运行代码构建、压力测试、故障注入或真机验证，不能将计划中的10,000次触发等验收条目描述为已经通过。本轮仅追加此日志，保留用户既有修改。


## 2026-09-05 12:25 +08:00 习惯页面风格统一与美化
- 使用 Skill：`frontend-flutter-feature`。负责模块：Habit presentation（列表、卡片、详情、日期记录、新建/编辑、局部主题与公共视觉组件）及相关 Widget 回归。
- 任务目标：按用户要求将习惯相关页面统一到应用的浅青背景、白色卡片与清爽视觉风格；本轮和后续界面美化优先限定 presentation，保留现有业务功能与流程。可行性 GO，沿用现有 Page → Controller → HabitGateway → typed DTO / MethodChannel 链路；未修改 Application、Gateway、DTO、Native、业务规则、依赖或工具链，保留用户与并行任务的 Contracts / Sync / ADR 修改。
- 任务结果：实现统一的 Habit 局部主题、导航栏、卡片、按钮、弹窗与日期/时间选择器；整理今日总进度、生命周期分组、统计、日期范围、中文历史状态及热力图；新建/编辑表单按目标、周期、提醒分组，保存按钮固定在可视区域并适配键盘。数量快捷 +1、精确输入/长按、撤销确认、跳过、备注、分页、编辑、提前结束、删除、再来一轮、提醒能力提示均保留原有调用。现有颜色偏好仍驱动进度颜色，支持深浅色、长标题、大字体和减少动画。
- 渲染与可访问性修正：实际 Flutter 预览发现卡片完成率背景在 Align 的松高度约束下没有可见高度，现补齐 heightFactor=1，仍使用原 completionRate；圆环补齐 Stack 内尺寸约束，列表圆环中心仍是连续天数，详情圆环仍表达原挑战时间进度。热力图触控区域至少 48dp，中文状态同时用图标表达，并显式保留读屏点击动作。
- 验证状态：本次 9 个 Dart 文件格式校验通过；flutter analyze 退出 0；Habit 定向 5 文件 47/47 通过，最终 flutter test 全量 604/604 通过，flutter build apk --debug 退出 0，生成 flutter_client/build/app/outputs/flutter-apk/app-debug.apk；git diff --check 通过。新增 3 个场景测试覆盖 320dp/200% 字体下热力图与读屏日期操作、320dp 软键盘下保存按钮可达性、长标题卡片的快捷/精确/详情点击隔离；原测试仅补充新版布局需要的滚动步骤，保留原断言。
- 全库格式例外：dart format --output=none --set-exit-if-changed lib test 退出 1，仅报告 test/create_schedule_controller_test.dart 的既有格式差异；该文件与 HEAD 无 diff，本轮未改动，未为美化扩大整理范围。
- 视觉证据：使用真实 Flutter Widget 渲染及测试专用投影生成 12 张浅/深色截图，输出在 C:/Users/vincent/.codex/visualizations/2026/09/05/01a06fb6-8d4a-7791-a5c2-4c2643aa9490/habit/；检查列表、详情、历史、表单/周期、日期记录的实际排版。临时截图测试已删除，未将 Fake 或预览数据接入生产。此为主机视觉验证，字体与 Emoji 使用 Windows 本机字体，不代表 Android 真机截图。
- 结果边界：界面实现及主机测试/构建完成；全库格式门禁存在上述既有例外。真机在任务中途断开，最终 adb devices 为空，本轮真机安装、实际交互、TalkBack 与系统提醒端到端未验证，也未变更这些底层行为。查看入口：日程页 → 更多 → 习惯；进入卡片详情、右上角新建或详情中的编辑查看完整样式。

## 2026-09-05 12:34 +08:00 云同步-02 CT0基线校准、兼容保护与决策审计

- 使用 Skill：`calendar-data-contracts`。负责模块：同步Contract前置审计、runtime版本校准、七项ADR提案、Contract验证工具与隔离spike；未修改Flutter/Kotlin/C++/Backend产品代码或构建依赖。
- 任务目标：严格按云同步-02与总计划完成协议开发，保护既有Contract及历史数据；当前结果为 **部分完成 / DECISION REQUIRED / CT0 PARTIAL**，未达到CONTRACT FROZEN，CT1–CT4尚未开始。
- 已交付：runtime.initialize Schema与fixture校准到已集成Storage v5，v4/v6响应明确拒绝；sync.apply及旧宽松Sync Schema标记deprecated/blocked且保持形状。记录基线commit 3ccc2b681f75fbbbfcfb80b94891ee40053da5b5并保护220份Schema/核心YAML；冻结v4/v5节点摘要，未改历史migration。新增七项Proposed ADR、CT0审计、Backend17声明/16Controller的可重算源码/DTO顶级字段/错误HTTP映射盘点，记录HTTP200与语义状态、request_digest缺失、Anniversary UUID category_id与opaque弱引用等真实冲突。
- 实验：13个固定JCS等价边界向量证实现有Windows C++ picojson、Java Jackson、Dart json原始encoder不能直接复用为JCS；8项Windows既有私有SHA-256 KAT通过，Android三ABI encoder探针编译成功。SQLCipher Community4.18.0隔离AAR校验上游SHA-256一致，三ABI必要sqlite3/key符号存在并以当前NDK链接scratch加密探针成功；包minCompileSdk=37，未引入产品、未升级SDK/SQLite。源码构建、完整许可与实际加密/20,000组合事实/故障恢复未验证，不能把链接探针当加密交付。
- 验证：`python contracts/run_sync_v1_validation.py --stage ct0 --self-test`通过，15项反例包含旧协议漂移、v5定义变化、错误runtime版本、重复JSON/YAML key、未闭合ref/fragment、fixture/hash篡改、伪冻结与默认Python退出码2门禁；默认入口明确拒绝冻结，正式CT1–CT4/Sync V1 validator未交付。Anniversary/Habit/Calendar/Search现有validator全部通过（58/46/19/31 fixtures）；CMake重新配置并`cmake --build cpp_core/build-ninja --target excellent_calendar_check`修改后13/13通过。smoke工程`flutter test --no-pub`1/1、`flutter analyze --no-pub`、`flutter build apk --debug --no-pub`通过。Python编译、文档链接/围栏与任务范围diff空白检查通过。
- 未验证与恢复：设备在encoder探针执行时断开，全部新Android ABI runtime以及真实smoke APK设备运行均未取得通过证据；可能残留`/data/local/tmp/excellent-calendar-sync-ct0-arm64-v8a`单个合成测试二进制，重连后仅清该精确路径，不清用户App。Backend HTTP/Testcontainers、完整历史身份审计、counter golden、SQLCipher/JCS正式spike、v6/PG模型及四层consumer未交付/未验证。
- 继续条件：按原计划§4.1/§4.2接受ADR/依赖与兼容版本方案，并关闭实际spike门禁后再进入CT1–CT4；审批不替代测试。完整记录见`docs/plan/active/云同步-02-CT0审计与决策记录.md`。执行期间出现的其他任务Habit UI/测试及其他日志追加均保留，不归入本任务更改或验证结论。
- 最终审阅补充（2026-09-05T12:40+08:00）：ADR-Sync-05 将 Anniversary 兼容建议具体化为保留 Native v2 定义、另立 Native v3 修订，覆盖写入/筛选/组合投影/缓存；解释了单独 sync projection 无法保护旧 reader 的原因。此为待接受提案，尚未变更任何协议版本或实现。CT0 15项反例复跑通过；新增29个文件的空白/文档链接/围栏检查通过。
- 加密来源审计补充（2026-09-05T12:45+08:00）：固定SQLCipher core v4.18.0 commit 63697beb0fafcb61faa7a3e6fd267036548ab11b与SQLCipher LibTomCrypt fork 476a9579ae94f32b9ea9e2747bfb04b302370259，记录15份来源/构建说明/顶层许可文件的原始SHA-256；SQLCipher三条款、SQLite public domain及构建例外、LibTomCrypt public-domain/WTFPL双选项已初审。发现Android v4.18.0标签core gitlink e2a6040仍为SQLite3.53.1，与独立core标签3.53.4不同；已在ADR-Sync-03及CT0-C13记录，不能据AAR摘要/ABI链接宣称源码可重现或正式许可门禁通过。逐文件分发审查、源码构建和设备runtime仍未验证，产品依赖未变。


## 2026-09-05 14:35（进行中）云同步-02 接受候选后的继续开发

- Skill：calendar-data-contracts。负责 contracts/**、同步 ADR 与计划记录；本轮起点 HEAD 32b463d415ccc992b798be7f93ca1e1c6573cdc8，工作树原为干净，未修改产品业务代码。
- 目标：在用户已接受 SQLCipher 原生 C 和保留 Native v2 的 Anniversary Native v3 修订后，自主完成云同步-02。七项 ADR 设计方向已登记；接受设计不等于冻结或实现完成。
- 当前结果：固定 SQLCipher/LTC 源码重建，Windows/三 NDK-Bionic ABI QEMU-user/真实 arm64 Android 的真实加密文件与四点强杀恢复、临时文件、密钥错误、VFS磁盘不足注入通过；427文件来源清单及6份通知保留。发现并禁止OS RNG失败后provider时钟回退，未升级工具链/SQLite或引入产品依赖。
- 准确性修复：扩展JCS数字边界发现Windows CRT舍入及原最短小数选择算法问题，已修复；64固定JSON、6非法UTF-8、20,000随机数和31,487系统边界在六个实际消费者环境bytes/hash一致，独立SHA KAT通过。明确QEMU-user与完整Android OS验证的区别。
- 数据模型/兼容进度：26计数器owner/MAX注册，78 golden、52并发双写、26持久重放和26回滚案例通过；新建15个独立Native v3 Anniversary直接/传递Schema，28兼容向量及旧Anniversary结构回归通过。220份旧Contract及v4/v5节点未漂移。CT0相关29项测试通过。
- 状态：任务仍进行中，未冻结。完整实体身份、field registry、HTTP/Native映射、v6/PG逻辑模型、Keystore/Backup、全target容量、20族fixture及四层revision/hash签署尚待交付。本条只记录已发生的进度，不报告整项完成；下一次最终验证后继续追加实际结果。

### 2026-09-05 16:25 — 云同步 02 持续开发（CT1 / CT2 / CT3 草案）
- Skill：calendar-data-contracts。负责模块：contracts/**、同步领域与计划文档；未修改生产业务代码。
- 目标：在用户已接受 Native C 加密候选和 Native v3 Anniversary 兼容方向后，继续补齐 02 所要求的机器模型。
- 结果：完成首批 12 target / 125 field 事实注册表与身份参考模型；新增 mutation、回执、normal/ack-only、下载组、bootstrap、import 与 Workspace/Session/Device/Retention 的严格 Schema 草案。新增 12 项真实 SQLite 事务参考测试，覆盖因果链、重放、部分合并、拒绝意图保留及 ack→apply 崩溃窗；模型明确不冒充 Backend/Native/完整导入引擎。
- 验证：此前 16 项领域/身份测试、61 个领域固定用例和 Backend 93 单元 + 58 集成 + 39 HTTP 观测通过；本次 12 项协议参考测试通过。当前 420 个 Schema 的 Draft 2020-12 / ref closure 检查通过。新增 recurrence_revision 计数器及生命周期 Schema 的完整用例尚在补充，整体验证证据须在收尾时重新生成。
- 限制：Contract 未冻结；原子依赖整图、完整能力图、SQLite v6 / PostgreSQL 模型、四语言消费与全部 FX-* 尚未完成。Android 手机仍未连接，最新 24 步 cipher 中新增二进制 key / bound-open 的实机结果未验证，Windows / 三 ABI QEMU 不替代实机。所有下游 production capability 继续 planned / blocked。


### 2026-09-05 17:33 — 云同步-02 协议与逻辑存储继续开发

- Skill：`calendar-data-contracts`。负责模块：contracts/sync、native_v3、storage、隔离参考程序及相关文档。目标：依原 02 计划完成强类型协议、v6/PG 模型并保护 Native v2 与 Storage v5。
- 结果：planned 协议/生命周期/错误 Schema 176 个；Counter 27 个 owner；v6 独立追加 34 表/12 索引/65 triggers；PostgreSQL 35 表/125 字段映射。澄清原 20 表含 3 个元数据表，保护 v4/v5 节点 hash；基线仅比较精确历史投影，未重建原 220 项摘要。Search 新 history 文件移至 native_v3/search，旧目录 12 个 Schema 不变。用户已接受的两个方向未重复请求确认。
- 验证：统一 drafts self-test 87/87 通过、429 Schema/ref closure、220 旧 Contract 保护；C++ 构建后测试 13/13 通过。SQLite 9 项测试及 113 个回滚点通过，调用未修改的生产 v5 checker；隔离 PostgreSQL 17.11 的 22 个约束用例、125 字段 catalog 映射、MAX 并发单赢家通过。账号加密完整图/Android v6/四语言消费及完整 owned graph/capability 仍未验证，默认冻结入口继续拒绝，不表示整项任务完成。

### 2026-09-05 18:52 — 云同步 02：接口映射与边界复验

- Skill：calendar-data-contracts。范围：contracts、同步领域/审计文档；未修改生产 Backend、Native、Flutter 业务实现。
- 补充 Native v3 recurrence 安全整数/通知 workspace 兼容修订、29 个内部基础形状、107 个公开方法与 90 个内部调用的 planned 映射、18 个新增 HTTP 端点和三态中央权限矩阵。旧 220 个 Contract 通过历史投影保护；根注册表仅追加 planned 修订引用。
- 已验证：12 项 capability 边界测试、6 项 Backend 修订测试；SQLite 最新 9 项/113 个回滚边界与 PostgreSQL 22 项用例通过。
- 本次 Backend 全量复验：58 项集成测试中 RateLimitIT.loginIsThrottledPerIpAndEmailWithRetryHint 失败 1 项，期望 429、实际 401。日志显示请求开始于 18:46:59.909，测试结束于 18:47:00；现有 InMemoryRateLimiter 按整分钟 fixed window 分桶，测试三次请求跨窗口时会发生此结果。保留失败记录并复验，不以重跑抹去该测试稳定性问题；生产修复归 04。
- 未完成/未验证：完整 owned graph、签名证明、导入/bootstrap 组合事务、四语言完整消费和真机新版本矩阵。默认冻结入口仍拒绝通过；正在继续开发。

### 2026-09-05 19:06 — 云同步 02：统一回归与双 ABI 真机证据

- Skill：calendar-data-contracts；负责 contracts / 同步模型与审计文档。继续按总计划保护旧边界，未改生产业务或升级依赖。
- 结果：13 capability/43 protocol/112 unified draft tests 通过；934 Schema、220 旧 Contract、380 fixed/4 suite；Search/Calendar/Habit/Anniversary 全部回归通过。Backend 原 93 单元/58 集成/39 HTTP 重跑通过，前次 fixed-window 跨分钟失败保留记录。
- 真机：RMX3687 API 33，arm64 与 armeabi-v7a 最新 24 步 SQLCipher 探针均通过；Windows/三 ABI QEMU 同步通过；427 源码/6 份 notice 再核验。
- 验证限制：仍未冻结；完整 owned graph、签名/Keystore/backup、导入/bootstrap 组合事务和四语言全消费继续开发。x86_64 不是完整 Android OS 证据。

### 2026-09-05 19:21 — 云同步 02：认证证明密码服务可行性

- Skill：calendar-data-contracts；负责 contracts/spikes、签名格式草案；未修改生产密码服务或引入第三方依赖。
- 采用平台既有 RSA-PSS SHA-256 / MGF1-SHA256 / salt32 / RSA2048-e65537 做隔离可行性验证。14 个固定验证输入不含私钥；Windows CNG C++、JDK 21、Android API 33 arm64/armeabi-v7a 的 JCA 与真实 JNI 六个 consumer 全部通过；三 ABI JNI 库成功构建，x86_64 未在完整 Android OS 运行。设备临时文件已精确清理。
- 该结果仅证明密码原语与 JNI 适配，尚未证明 capsule、trust-store 轮换、claims/account/purpose/range/CAS 全部认证；新增 4 个独立 proof Schema 与协议草案，继续补充具体绑定验证。默认冻结门禁保持拒绝。


### 2026-09-05 19:50 — 云同步 02 证明认证与事务绑定

- Skill：calendar-data-contracts；模块：contracts/sync/proof、isolated C++/Java/JNI 与验证入口。
- 结果：冻结候选 RSA-PSS/SHA-256、MGF1-SHA256、salt32、RSA2048/exponent65537；新增账号/用途/内容摘要绑定、严格 JCS capsule 与受信任密钥格式，保留所有 Native v2 定义。14 个密码原语用例在 6 个消费环境通过；45 个完整 capsule 用例在 Java、Windows C++、RMX3687/API33 的 arm64 与 arm32 C++/JNI 中逐项一致；12 项真实验签参与的 SQLite 绑定/原子收据测试通过。manifest 439 固定用例。
- 边界：测试私钥仅在生成进程内存中，固定样例只有公开验签材料；未把 Hash 当作身份认证。完整导入 saga、Android 撤销记录持久化和 Backend 账号删除证据 producer 仍未验证；不标记 CONTRACT FROZEN 或激活产品能力。


### 2026-09-05 21:02 — 云同步 02 真机密钥、原始 civil identity 与错误闭包

- Skill：calendar-data-contracts；负责模块：contracts/isolated spikes、机器定义、验证入口；未修改产品 C++/Flutter/Kotlin/Backend 业务。
- 真机结果：RMX3687/API33 的 arm64 与 armeabi-v7a 实际 APK 进程各完成 46 项（共 92 项）Keystore、二进制 JNI key、20,000 条 SQLCipher 数据、进程重启、APK 升级、crypto destroy、卸载重装、残留密文拒绝检查；测试包已经卸载。API23/24 和实际 cloud/D2D transport 均未执行；排除矩阵是已打包 XML/Manifest 的独立证据，未标为产品功能完成。
- 遇到并修正的测试入口问题：OEM 安装确认可晚于 ADB timeout；结果字段解析遗漏数字；exec-out 不传入 stdin；设备忽略 ABI 安装选择而启动 64 位进程；Windows aapt2 ZIP asset 本地头路径分隔符及 resources.arsc 压缩要求。最终使用实际 process bitness 检查、独立 ABI APK、可恢复 phase journal、shell 非 PTY 精确长度传输；失败历史保留，未把错误 ABI 计为通过。新构建入口 build-only 通过，Dex 和三 ABI JNI 与已执行载荷完全一致。
- 原始 occurrence 身份：15 个固定用例使用未修改的实际 Core/TZDB 验证，覆盖 DST gap/fold、半小时偏移、Apia 跳日同 UTC 不同 key、月末/闰日和拒绝边界；不宣称 legacy v1 转换或 Native v3 宽计数 runtime 完成。
- 错误闭包：新草案仅允许明确的 Backend 错误和 Backend counter context；平台、鉴权、存储、协议请求错误不进入 failed-local；逐项 rejected 增加与 code 对应的严格 failure_context，ack 参考事务保留该 context。46 项协议/生命周期测试、13 项 capability 测试、12 项真实证明接纳测试通过；存储 9 项/113 回滚边界与 PostgreSQL 22 项重跑通过。
- 状态：500 fixed/4 generated suite；正在执行统一自测，尚未冻结 CT0–CT4；220 项旧 Contract 和 v5 历史摘要继续受保护。


### 2026-09-05 21:59 — 云同步 02 旧数据与 owned graph 验证

- Skill：calendar-data-contracts；模块：contracts 的隔离参考模型、机器定义、fixtures/validator 与相关文档；产品业务代码未改动。
- 结果：真实 Core v1→v4→v5 迁移和只读投影 19 个合成库场景通过；旧 ID 逐字编码到独立 legacy 命名空间，UUIDv4 映射耐久重放，未知时区/缺失规则/悬空提醒等整批拒绝且源保持不变。4 项 legacy 单元与新增字段/图边界合计 domain 22 项通过。
- owned graph：4 项测试、7 个固定场景及 4 个真实 SQLite 回滚点通过；同 revision 不同规则内容保留整个 schedule component，独立标题可合并；根实体/规则/提醒原子发布、响应丢失后准确重放，orphan/递归依赖拒绝。完整 child causal 与 transport 组合仍未验证。
- 校准：新 Sync UUID 限定 canonical 小写，既有 v2 与 opaque 弱分类引用不变；打卡单位快照改为沿用现有领域的 32 字符，校验目标/单位快照、有效结束日与 owner lifecycle；failed-local 状态统一为总计划的 superseded_pending。公开/内部 DTO 分别命名，设备改名回显 route，习惯通知 action 强制 workspace identity，保留原有四类事件并增加同步/工作区事件。
- 验证：统一 drafts 自测 149 项通过，945 Schema、526 fixed/4 generated suite、220 protected；四个旧领域验证器全部通过。协议 46、capability 17、存储 9/113 与 PostgreSQL 22、45 个完整 proof capsule 在 Java/Windows C++/Android arm64/arm32 重新通过；报告源码摘要检查无过期，git diff --check 通过（仅现有 CRLF 提示）。测试中两处错误 fixture（非法 recurrence interval、提前结束却保持 active）修正为领域合法输入后再验证，未放宽旧规则。
- 尚未完成：import commit typed terminal、完整 import/bootstrap/failed-local/maintenance 参考闭环与四语言消费、最终共同 revision/hash；保持 CT0–CT4 partial，未签署 CONTRACT FROZEN，未激活产品。


## 2026-09-05 23:11 — 云同步-02 游标、严格导入终态与 bootstrap 原子性

- Skill：calendar-data-contracts。负责 contracts/** 与同步模型/计划文档，继续用户已授权的 Contract 开发；无生产业务代码、历史迁移或工具链变更。
- 目标与结果：新增 Backend 私有 HMAC 游标格式及签发范围保留模型；Java/Python 33 个固定用例字节与错误结果一致。PostgreSQL 新增非敏感签发范围表，禁止过早删 key usage、bootstrap identity/item 原位变化，36 个数据库约束用例通过。
- 严格终态：import commit 成功与 repair 拒绝携带独立必要证据；duplicate 外壳与原回执、mutation、完整 per-key 结果相互绑定。本机 ack 增加持久 device binding。发现并修复参考模型的确认水位过早推进：此前收到 effect 回执即可确认，现等待准确 group/末序号原子应用，避免 Backend 提前回收恢复证据；重启、错设备、错序号和回滚均有测试。
- Bootstrap：HTTP/Native/SQLite/PostgreSQL planned identity 补齐总条目数、完整条目摘要、页数与固定 page limit，精确 hash 算法进入机器文件。7 项测试涵盖 10 固定场景、六类 union、500 条分页、重复/乱序/漏页、固定上界/TTL/MAX、provenance 保留与 fresh 确认恢复。10 个 named write boundary 均通过真实子进程无清理退出并重开检查，未发布半份图。
- 验证：统一草案 self-test 167/167 PASS（241.973 秒），946 Schema、220 旧基线、583 fixed + 4 suite；协议 51/208 schema/96 fixed，SQLite 9/113 回滚点，PostgreSQL 36 用例。Search/Habit/Calendar/Anniversary 四个旧 validator 均 PASS，git diff --check PASS（仅既有换行提示）。报告 source hash 与 gate evidence 已更新到实际执行结果。
- 剩余工作：bootstrap 单独组件对非空 pending/failed/effect gate 明确返回需要组合重放，不能冒称该部分完成；import saga/发布、Habit operation、完整 child causal、冲突解决、四语言适用 fixture 消费及下游 revision/hash 锁仍需闭合。状态保持 CT0–CT4 PARTIAL / DECISION REQUIRED，尚未 CONTRACT FROZEN。

## 2026-09-05 23:29 +08:00 — 响铃设置界面美化与入口迁移

- 使用 Skill：frontend-flutter-feature。
- 负责模块：Flutter Presentation / Ring Settings、Profile、Inbox 入口及对应页面测试；main.dart 仅移除旧入口的两行导航回调。
- 任务目标：保持业务逻辑与基本功能不变，统一响铃设置视觉并将入口迁移至“我的”。
- 任务结果：响铃设置采用共享浅青背景、跟随主题色的圆角卡片与深色适配；整理提醒偏好、测试响铃按钮、设备权限与受限提示；支持下拉刷新及小屏大字号换行。“我的”新增本机设置分组，资料加载中、成功及失败时均提供响铃入口；日程更多菜单移除原入口，习惯与倒数纪念日入口保留。铃声选择、强提醒、开始/停止测试、活动响铃禁用测试、错误/取消提示、能力状态及底层调用保持既有规则。未改 Application、Gateway、Contract、Native、依赖或工具链。
- 验证：相关 5 组测试 36 项通过；最终 flutter test 全部 608 项通过；flutter analyze 无问题；flutter build apk --debug 成功；本次 7 个 Dart 文件格式化及 git diff --check 通过。390×844 浅色/深色页面实际 Widget 渲染已目视检查，320 宽/2 倍字号/受限状态测试通过；新增正常与离线个人资料场景的入口往返测试。临时截图测试已移除，预览保存在工作区外 Codex visualizations/ring。
- 验证边界：未验证真机播放/系统铃声选择器；全局 format --output=none --set-exit-if-changed lib test 发现既有 test/create_schedule_controller_test.dart 格式问题（退出 1），未改动无关文件。用户已有 Contracts/Sync/ADR/docs 等修改予以保留。
- 文档定位：docs/index.md 未直接索引响铃/个人设置相关入口，本次依照范围定向定位既有实现、路由、Ring Contract 和相关测试，未扩改索引或业务规格。

## 2026-09-05 23:35 +08:00 — 日程列表留白、字号与圆圈对齐

- 使用 Skill：frontend-flutter-feature。
- 负责模块：Flutter Presentation / Inbox 任务列表组件与视觉 token；两处既有测试文件仅移除已删除的 showDivider 构造参数。
- 任务目标：按用户参考图取消日程间分隔线，调整文字与完成圆圈大小，使圆圈可见左缘与“即将到期”等分组标题起点对齐。
- 方案与结果（GO）：移除 TaskListItem 分隔线及专用参数；标题改为 16 / w400、日期 13；标准行高 52，大字号时自动增高；圆圈直径 20、描边 1.5，点击区域保留并扩大为 48×48。根据分组标题边距与圆圈可见尺寸计算行左边距，避免点击区域内居中造成额外缩进；完成划线绘制跟随系统文字缩放。未改变任务分组、完成命令、详情导航、重要性颜色、完成/移除时序与数据逻辑；本轮生产改动仅限 presentation。
- 验证：相关交互动画和详情测试 14 项通过；完整 flutter test 608 项通过；flutter analyze 无问题；Android Debug APK 构建成功；本轮 6 个 Dart 文件格式化及 git diff --check 通过。临时 Widget 渲染分别检查 390 宽标准字号、320 宽两倍字号，测量确认圆圈左缘与“即将到期”左缘相等、圆圈与行文字垂直居中、点击区域 48×48；无布局异常，预览已目视确认，临时测试已移除。
- 验证边界：未进行真机安装或触摸验证；全局只读格式检查仍仅报告原有 test/create_schedule_controller_test.dart 格式问题（退出 1），保留未改。既有响铃入口迁移与其他用户修改全部保留。没有新增显示设置功能或引入依赖。


## 2026-09-05 23:33 — 云同步-02 后端完整请求/DTO 校准

- Skill：calendar-data-contracts。模块：contracts 的 Backend 校准探针、验证器与同步 ADR。
- 结果：JVM 探针核对 17 个 HTTP 声明、16 个 Controller、24 个已编译 DTO 的全部字段和嵌套 Bean Validation/容器约束；绑定旧/目标 Schema 完整引用闭包、每个声明错误及 HTTP 状态、幂等规则与 39 个已执行 HTTP 观测。无新请求实例、应用上下文或外部服务写入。
- 差异处置：Java String @Size 的 UTF-16 单元上限与 Contract Unicode code point 不同；04 的同版严格绑定修订须同时调整旧窄限制。unknown key、scalar coercion、nullable/union、profile/preferences owner、request digest 和缺少的错误 producer 均有明确目标处置，旧 Contract 不改。
- 验证：backend_shape_audit_result PASS，17/24 完整；针对遗漏端点、嵌套 ref、处置与反射字段的负例测试 PASS。统一草案静态入口 PASS，220 旧定义/946 Schema 保持；最近完整 self-test 为 23:11 的 167 项，新增校准负例另运行 1 项，不冒称已重新跑完整 168 项。
- 门禁范围校正：CT0 encryption/identity/backend 审计已通过；账号完整生产组合、child causal transport、Backend 修复依照 02 §18 分属后续实现/组合验收，不再错挂为 CT0 可行性决策。Android backup/两目标恢复 fixture 矩阵继续补齐，CT1–CT4 与 Contract freeze 仍未完成。


## 2026-09-05 23:48 — 云同步-02 备份策略矩阵与并行 Contract 冲突

- Skill：calendar-data-contracts。完成 25 类合成数据、API23/24/30/31/33 cloud/D2D XML 分支及同源两目标策略 fixture，共 11 固定场景、4 项测试 PASS；额外负例逐项删除 18 个 modern 域排除条目，能检测 guest 文件变为可导出。旧身份复用与未经允许的 guest re-home 拒绝。无实际云备份/OEM迁移/API23或24 OS执行声明，生产 restore owner 未实现。
- CT0 范围：按 02 §4.2 的 fixture 与 §18 的实现边界，现状/候选/备份材料已齐；API33 双 ABI 92 项实际 APK 证据独立保留。整项任务尚未冻结。
- 新冲突：173 项 self-test 运行期间出现非本任务 Appearance/字体改动，两个既有 v2 Schema 新增 display，另增加 display_preferences.schema.json 及多处 Flutter 字体代码。HEAD 仍为 32b463d415ccc992b798be7f93ca1e1c6573cdc8。原 220 定义保护测试和关联 field registry fingerprint 测试失败，实际为 171 PASS / 2 FAIL；随后的 --stage ct0 也正确拒绝旧定义漂移。不能使用该运行最初的 946 Schema/220 PASS 静态输出冒充结束时工作区通过。
- 处置：保留非本任务改动，旧基线不重建；按用户“保留旧 Contracts”指令及 AGENTS §7 记录具体冲突，已异步询问是否来自并行字体任务。相关整体兼容门禁暂停，继续独立的同步 Contract 工作；当前文件数新增到 947 Schema 是外观修改带来的状态，不是本任务新增一个同步 Schema。

## 2026-09-05 23:54:35 +08:00 — 外观显示设置开发暂停（用户明确要求）

- 使用 Skill：frontend-flutter-feature、calendar-data-contracts；已读取 android-kotlin-native-feature 的相关约束。
- 负责模块：Appearance 外观设置 / Flutter 字体展示 / Kotlin 本机偏好 / Appearance Contract。
- 任务目标：从“我的”进入外观设置，上方“主题”“显示”双页签；主题暂不支持；显示提供字号、字重、字体及预览，默认更细。用户已确认先提供几种常用字体以减小安装包。
- 暂停结果：收到用户“先暂停开发，进行等待，保留工作痕迹，等待下一次开发”后立即停止实现。未提交、未回滚、未清理现有工作。
- 已写入的工作：新增 DisplayPreferences Schema/Dart DTO/Kotlin model；Appearance 请求和响应添加可选 display；Controller、测试 Fake、Kotlin Store/Contract/Handler 已做部分接线；新增 AppTypography/AppText 初稿；pubspec 声明两种离线字体及许可证；assets/fonts 中保留裁剪字体与说明（约 9 MB）。此前响铃设置迁移和日程列表美化修改均保留。
- 当前代码未完成，不能视为可构建交付：appearance_page.dart 正处于页面替换中，仅保留颜色辅助函数，尚缺页面类和 imports；main.dart 尚未接入字体/字号作用域；AppText 尚未应用到现有页面；Kotlin 测试 Store 尚未实现新增接口；新字段枚举登记、完整兼容说明、许可证注册、设置页及相关测试仍待完成。尚未进行本轮格式化、analyze、完整测试、Kotlin 测试、APK 构建或设备验证。
- 下次恢复：先检查工作区变化，接续上述未完成文件；实现双页签及三项设置、即时预览与本机保存；保留旧颜色存储；完成全局字体应用、失败/取消/加载/重启恢复验证、Contract/Native/Flutter 测试与构建。不要重复覆盖用户或其他任务的修改。
- 临时工作痕迹：系统 TEMP/excellent-calendar-font-sources 保留上游原字体和许可证；TEMP/excellent-calendar-font-tools 保存临时 fontTools 4.64.0（没有升级项目依赖或系统工具链）。本轮没有安排自动恢复或定时任务。

## 2026-09-06 00:21:32 +08:00 — AI 协作开发效率初步诊断

- 使用 Skill：self-learning。
- 负责模块：项目开发流程与学习诊断；未修改业务代码。
- 任务目标：结合当前项目寻找 AI 协作瓶颈，并询问用户实际耗时与返工案例。
- 任务结果：读取架构、索引、当前阶段与验证入口，抽样查看 Appearance Controller 和同步 CT0 门禁；发现工作区存在外观与同步两类修改，门禁记录外观协议变更影响同步校验。提出共享协议变更协调、小批次闭环验收和记录实际返工耗时的初步建议。个人瓶颈仍待用户实例确认，不能据此认定技术能力不足。
- 验证状态：仅文档与代码只读取证；未执行构建或测试，门禁中的历史结果未重新验证。仅追加本日志，保留已有修改。


## 2026-09-06 00:47 — 云同步 02 持续开发：Habit operation 与隔离验收
- Skill：calendar-data-contracts。
- 负责模块：contracts/sync、contracts/storage、contracts/spikes/sync_v1、相关 fixtures/tests 与同步领域/审计文档。
- 目标：按总计划 01 §9.3 和 02 §7/10/11 完成 Habit 打卡增量、去重、clear/replace 屏障及持久化边界，保护旧 Contract。
- 结果：原并行 Appearance/Flutter/Kotlin 修改保留；已在 codex/cloud-sync-02-contracts 工作副本继续。隔离基线 173 tests/946 schemas/220 protected 全通过。新增 Habit 操作规则、typed error 生产范围/私有 context、公有脱敏投影、29 个固定场景、operation ledger/barrier 与五个实际进程退出点；源 v2/v5、历史 migration、生产业务代码未改。
- 已验证：Habit 11 项测试、29 fixed、5 实际强杀点；Protocol 51 项/208 schemas/96 fixed；Storage 9 项/115 回滚点、PostgreSQL 38 新表/125 字段/48 约束用例；Capability 17 项、Owned graph 4 项、Bootstrap 7 项/10 实际强杀点。45 capsule 在 Java/Windows C++/Android arm64+arm32 再次输出一致并清理测试目录。fixture manifest 为 635 fixed/4 generated suites。
- 验证状态：总入口 ct0+self-test 正在运行，尚未记录本轮全套通过。仍为部分完成/DECISION REQUIRED；后续继续 pending/failed/effect 重放、owned child 因果组合、完整 import、冲突/maintenance 与四语言消费/冻结。原工作目录的字体兼容差异留待整合复核，不通过修改基线掩盖。


## 2026-09-06 00:52 — 云同步 02 本轮统一复验通过
- Skill：calendar-data-contracts；模块：同步 Contract、逻辑存储与隔离验证。
- 目标/结果：Habit operation 组件闭合后复验现有全部证据，仍按部分完成管理。
- 实际验证：隔离副本 `run_sync_v1_validation.py --stage ct0 --self-test` 185 项通过（266.754 秒），946 Schema、220 受保护 Contract、635 fixed/4 generated suites；Search 31、Habit 46+4 identity、Calendar 19、Anniversary 58+20 identity 全通过；`git diff --check` 通过。
- 边界：这些是 Contract/隔离参考模型证据；没有宣称生产同步、多设备集成、完整 pending/import 状态机或 CONTRACT FROZEN 完成。继续实现下载/bootstrap 下本机意图与回执恢复。

### 2026-09-06 01:46 云同步 02：本机意图与下载/重建组合验证
- Skill：calendar-data-contracts；模块：contracts/sync、contracts/spikes/sync_v1、contracts/tests 与同步模型文档。
- 目标：补齐 pending / failed-local / effect-gate 在普通下载、全量重建及重启下的原子恢复，不改变旧 Contract 或生产业务代码。
- 结果：隔离工作树完成冻结 journal、准备请求绑定、普通 typed group/page 原子应用和 bootstrap 重投影；发送后回执丢失时保留原请求/草稿，真实 Habit 500+100 在普通下载与重建恢复后均为 600。旧库不得凭 server confirmed 跳过本地缺失回执，已 resolved 冲突不会被迟到 created 重新打开，field version 倒退与错配响应均零写拒绝。
- 验证：local-intent 29 项测试 / 8 固定历史 / 18 实际进程退出点 PASS（111.938s）；独立 bootstrap 7 项 / 10 固定历史 / 10 实际进程退出点重新 PASS（181.551s）；fixture manifest 为 643 fixed / 4 generated suites。新的统一 CT0 + self-test 正在执行，尚不宣称通过。
- 状态：本计划继续部分完成；导入发布、完整 resolution writer、owned-child causal 组合与四语言消费仍待验证。修改位于 A:/calendar/ExcellentCalendarAPP-sync-contracts，尚未将后续隔离开发集成回原工作区；保留用户并行字体/外观修改。

### 2026-09-06 01:59 云同步 02：215 项统一验收检查点
- Skill：calendar-data-contracts；模块：同步 Contract / 模型 / 隔离验证。
- 目标与结果：完成本机意图、普通下载和 bootstrap 的组合恢复证据登记，继续保护 Native v2 和冻结 SQLite v5。
- 验证：run_sync_v1_validation.py --stage ct0 --self-test 实际 PASS，215 tests / 418.912s；946 schemas / 220 protected contracts / 643 fixed fixtures / 4 generated suites；git diff --check PASS。各报告对应源码哈希由实际 runner 生成，门禁仍为 CT0_AUDIT_ONLY_NOT_FROZEN。
- 剩余：完整冲突解决、导入、owned-child 因果组合、四语言消费及最终工作区集成；不能把本检查点解释成整份计划已完成或生产功能已接入。


## 2026-09-06 12:10 云同步-02：冲突解决与通知组合验证（继续开发，未冻结）

- Skill：calendar-data-contracts。模块：contracts/sync、fixtures、isolated spikes/tests 及同步领域说明；本次没有修改生产业务代码。
- 结果：root 冲突解决 16 项测试/8 个固定场景/5 个实际强杀点通过；新增通知 journal 与 ordinary download/bootstrap 同事务组合，9 项测试/6 个固定场景/14 个实际强杀点通过，包含迟到/重复、并发领取、响应丢失、MAX 和 bootstrap 续接未通知发现集。
- 容量：实际运行 1,000,000 个通知窗口和领取，每 1,000 个窗口一批提交，共 1,000 次提交；最终通知/成员/窗口/discovery 均为零行，checkpoint 后数据库 36,864 bytes。该容量实验不等于百万次独立 fsync，也不认证产品 UI。
- 复验：手机重新连接后，45 个证明 capsule 在 Java21、Windows CNG C++、真实 Android arm64/arm32 结果一致；SQLite 9 项/115 迁移回滚点和 PostgreSQL 48 约束通过；bootstrap 7 项/10 强杀、本机意图 29 项/18 强杀复跑通过。Docker 启动曾因遗留零字节 IPC 文件失败；保留原文件目录，用户修复无权限目录并重启后数据库复验成功，未改容器数据。
- 当前清单为 657 fixed/5 generated suites，24 份证据摘要已核对；统一 ct0+self-test 正在执行，本条不宣称其已经通过。
- 状态：CT0–CT4 PARTIAL / DECISION REQUIRED；尚需 owned child 因果与 resolution 组合、完整 import、四语言消费、capability/error 闭包和最终同版锁定。原并行 Appearance 修改保持原样，整合回原工作副本仍待完成。


## 2026-09-06 12:15 云同步-02：243 项统一验收检查点

使用 calendar-data-contracts Skill，负责同步 Contract/参考模型。`run_sync_v1_validation.py --stage ct0 --self-test` 实际 243 项测试通过（452.904s），946 Schema、220 protected Contract、657 fixed/5 generated suites；24 份已登记证据与来源摘要一致，diff whitespace 检查通过。本检查点不认证尚在开发的 owned sequence 组合，也不表示完整计划完成、Contract 冻结或生产能力激活；后续修改须复跑受影响证据。

### 2026-09-06 12:54 云同步-02 owned 因果组合与冲突候选复核（继续开发，未冻结）
- Skill：calendar-data-contracts；模块：contracts/、同步领域与计划审计。
- 目标：保持旧 Contract，补齐主对象/子项连续写与 resolution 的真实参考验证。
- 结果：owned sequence 组件历史执行 12 项/7 fixed/7 实际强杀通过；manifest 新增 7 场景至 664 fixed。新建 planned owned 规则；未发布子项的 server candidate 增加严格 absent 分支，原 v2 不变。新增 resolution-only 候选非法错误和只读/Habit 历史保护；owned resolution 正在测试。
- 验证：12:15 的 243 项统一检查仍是上一个完整检查点。本次公共 helper/schema 已更新，相关源摘要需实际复跑；当前不能以旧报告宣称新草案已通过。导入、四语言、同版锁定及原工作区整合仍未完成。

### 2026-09-06 13:44｜云同步-02：导入暂存与统一校验继续推进（未完成）

- Skill：calendar-data-contracts；负责模块：contracts/** 的隔离协议 reference、fixture/validator 与同步领域文档。
- 目标：按总计划和 02 计划闭合协议与数据模型，保留旧 Contract 和用户并行字体修改。
- 本轮已完成：统一 ct0+self-test 278 项测试（1025.813 秒）、946 Schema、220 受保护旧 Contract 通过；26 份已登记证据在该轮启动时均为实际复跑后的新鲜结果。Owned sequence 12 项、owned resolution 11 项、root resolution 19 项，手机 45 项证明用例两个架构与 Java/Windows 一致，SQLite/PostgreSQL 复验通过。
- 导入新增验证：初始 staging/commit 的 6 项测试（47.351 秒）通过，含 6 个真实进程退出恢复点；摘要/分块独立测试已有一次 6 项通过。新增下载端跨页可见性测试尚在运行，未计入上述 278 项。
- 限制与后续：统一测试退出时 Python 临时目录清理遇到 storage_v5_probe.exe 的 Windows 异常，需修复资源收尾并复验。正在扩展导入下载、双库 lease、修复/范围关闭和退休清理；四语言消费、同版锁定和原工作区最终整合仍未完成。后续共享 reference 修改将要求更新受影响证据，不以历史通过代替当前通过。保持 DECISION REQUIRED、implementation_allowed=false，不宣称冻结或产品实现。

### 2026-09-06 15:45｜云同步-02：设备/数据库恢复与导入后继验证（继续开发，未冻结）

- Skill：calendar-data-contracts；负责模块：contracts/** 的隔离参考模型、Schema、逻辑存储与相关验证。
- 目标：在保留 Native v2、Storage v5 与并行字体修改的前提下，继续完成 02 计划的导入与跨语言验收。
- 本轮验证：手机证明验签 45 用例在 Java/Windows/Android arm64/arm32 结果一致，摘要 70ddd7d8f4243ccec7e976ac4dae5af9c058422260f4c79e49d0af2454d518cb；Docker 恢复后 PostgreSQL 52 用例及 SQLite 9 项/118 回滚边界通过。随后 v6 新增服务器状态缓存列，该存储报告须再次复跑，不作为当前版本已验证证据。
- 导入组件：cleanup 8 项（88.150 秒）、status 5 项（23.424 秒）、后继图 5 项（23.822 秒）实际通过；cleanup 包含 9 个真实进程退出点。后继图覆盖持久 ID 映射、完整历史删除集合、旧发布记录不变、已消费失败后的修复和云端字段冲突与独立合并。后继发布的强杀恢复等组合仍在补充。
- 跨语言：C++/Java 21/Kotlin 2.2.20/Dart 各 389 个 Schema 边界用例通过，四者输出摘要均为 0539732cb652e76ce74fed7405e3324ed79ef7471b915fa4916baa8d36764dfb；该范围不等同全部 FX 家族已闭合，也未计入新的统一检查。
- 进行中及限制：20k/50k 完整组合图容量测试仍运行，20k 已暂存至末尾，最终发布校验耗时正在分析；新增组件尚需登记 fixture/报告与统一回归。当前修改在 A:/calendar/ExcellentCalendarAPP-sync-contracts 隔离工作副本；原工作区字体改动未覆盖。后续同版锁定、最终整合和全计划冻结仍未完成，保持 implementation_allowed=false。


### 2026-09-06 16:48 +0800 云同步-02：组件复验与后继双库恢复（继续开发）

- Skill：calendar-data-contracts。负责 contracts/docs 隔离工作副本；保持生产代码、Native v2 与 SQLite v5 冻结定义不变。
- 目标：复验共享 Schema/删除锚点/导入状态修正，补齐整图后继导入的本机双库 lease 与清理组合。
- 已执行：38 组共 288 项回归，287 项通过，1 项为 Native v3 导入状态派生文件未重生成；同步生成后该组 17 项全部通过。Java/Windows C++/Android 真机 arm64、armv7 各 45 个 capsule 验签用例结果一致。17 份组件报告全部实际复跑通过；其中 SQLite 9 项/118 回滚边界，PostgreSQL 52 个实际数据库用例；四语言各 389 个 Schema/round-trip 边界一致。
- 容量：再次实际发布 20,000 与 50,000 条十类组合事实，分别 40/100 个分块，全部 mapping 与实际 receipt 完整。没有把 opaque 行数替代业务图。
- 验收门禁新增导入组件、容量与四语言边界报告检查及缺用例/缺消费者/缺强杀点/越界宣称负例。一次 validator 中 target 字符串校正导致 import_saga/import_capacity 两份源码绑定过期，须再复跑，未手工改写报告 source hash。其余报告当前源码扫描无过期项。
- 正在开发：FullGraphAccountImport/FullGraphGuestImport 双库整图后继、旧 lease 恢复、当前源对象计数和历史 delete 清理，尚处新组合测试阶段；新增 guest replacement journal 的正式 v6 映射仍待补齐。
- 状态：部分完成，未执行本轮最终统一门禁；不宣称 CONTRACT FROZEN、全生命周期完成或下游生产激活。原工作区字体修改保持原样，最终整合未完成。

### 2026-09-06 同步 02：完整导入及 fresh 恢复继续验证
- Skill：calendar-data-contracts；模块：Contracts、v6 / PostgreSQL 逻辑模型、隔离 reference 与验收测试。
- 目标：保留旧 Native v2 / SQLite v5 定义，闭合双库导入与账号缓存丢失后的恢复边界。
- 结果：完整导入 8 项测试实际通过（79.245 秒，8 个进程强杀点）；fresh 恢复 6 项测试实际通过（51.006 秒，5 个进程强杀点），覆盖已发布回执丢失、未上传 gap、旧 origin 撤销、伪造证明、reserved successor 缓存丢失及完整 bootstrap / ack 门禁。后续新改动仍须统一复验。
- 存储复验：SQLite 11 项 / 128 个回滚边界、PostgreSQL 66 个真实用例通过；planned v6 新增 37 张表，PostgreSQL 新增 40 张表。220 个旧定义保护基线不修改。
- 验收状态：仍为部分完成；策略持久化 / maintenance、剩余四端消费、源哈希统一证据及原工作区整合未闭合，不标记 CONTRACT FROZEN，不激活产品实现。


## 2026-09-06 18:47 云同步-02 Contract 与数据模型完成

- 使用 Skill：calendar-data-contracts。
- 负责模块：contracts、同步领域/ADR/计划与隔离参考验证；无产品 C++/Dart/Kotlin/Backend 业务代码变更。
- 任务目标：严格完成云同步-02，保护既有 Contract，落实已接受的 SQLCipher 原生 C 与独立 Native v3 修订。
- 结果：同步工作副本 `A:/calendar/ExcellentCalendarAPP-sync-contracts` 的默认入口通过，CONTRACT FROZEN；revision `cloud-sync-v1-contracts-2026-09-06`，SHA-256 `e3229e43a9ef29584ffc625c28cf371c13136da05d054f93599a261145ef04e2`。03–06 输入已锁定，新增产品能力仍 planned。
- 验证：951 Schema/220 protected、717 fixed/9 suites、四端 1,308 项、43 门禁回归、26 恢复组合、53 导入组件、20k/50k 容量、SQLite 128 回滚点、PostgreSQL 70 用例、Android 49 证明用例通过；四个原领域 validator 通过。依用户要求省去未受影响的重复全量产品构建，保留原始通过记录，没有声称本轮重跑。
- 交付边界：原工作副本字体/外观修改保留，未合并入冻结输入。详情见同步工作副本 `docs/plan/active/云同步-02-冻结验收与交付记录.md`。


## 2026-09-06 19:10 +0800 云同步-02 成果同步至 HXY（整合中）

- 使用 Skill：calendar-data-contracts；模块：contracts、同步领域、ADR、计划与交付文档。
- 任务目标：按用户明确要求，将已冻结的 Plan 02 成果同步进入 HXY 分支，保护暂停的字体/外观开发。
- 当前结果：已将同步专属内容同步到 HXY 工作目录并准备独立提交；33 个其他任务文件按原字节保留，4 条其他任务日志保留为未提交内容，历史日志仅追加。
- 验证状态：准备从暂存内容导出独立快照，核验冻结修订、历史 Contract 与证据来源；不重复已经通过且源码未变的耗时实验。字体任务的两份旧 Appearance Schema 扩展不计入本次提交，本次不声明混合工作目录通过冻结校验。


## 2026-09-06 19:16 +0800 云同步-02 HXY 整合验收通过

- 使用 Skill：calendar-data-contracts；负责模块：本次同步 Contracts、逻辑模型、隔离验证与交付文档。
- 任务目标与结果：将 Plan 02 的冻结成果独立提交到 HXY；保留 33 个字体/界面等其他任务文件的原始内容，4 条其他任务日志继续保留为未提交修改，未合入其他任务代码。
- 必要交付补充：干净暂存快照首次校验发现 `cpp_core/third_party/tzdata/2026c/Makefile` 被全局 Makefile 忽略规则漏收。该文件是既有时区实验报告记录的原始上游输入，本次仅纳入版本管理，内容及证据摘要一致；没有改动 C++ 业务实现、构建配置或升级依赖。
- 验证：从本次暂存树导出的独立快照运行 `contracts/run_sync_v1_validation.py` 实际通过，返回 CONTRACT FROZEN、220 protected Contracts、951 Schema、5 runtime fixtures、17 Backend 声明/16 Controller、13 canonical integrity checks；全部实验报告来源摘要匹配。Contracts 与已冻结开发副本内容一致，沿用其已通过实验，不重复构建或运行耗时容量/设备测试。
- 差异检查：本次编写的文件通过空白检查；5 份上游许可证/版权声明的 6 处原始空白提示保持原样，未修改来源文件或其摘要。
- 验收边界：本次通过的是 HXY 提交内容的快照；工作目录仍保留字体任务修改的两份旧 Appearance Contract，其兼容调整未由本次完成，也不声明混合工作目录通过冻结校验。无远程推送。

## 2026-09-06 20:04 +08:00 最近提交规模与耗时快速审阅

- 使用 Skill：`review-worktree-architecture`；负责范围：提交 `5d8fb0a` 相对父提交 `32b463d`，用户要求快速解释文件规模、任务耗时和工作重心，未开展完整实现审计。
- 结果：提交改动1,062文件（新增1,031、修改31），新增222,364行、删除242行；1,042文件位于contracts，19份文档，另1份既有上游tzdata Makefile。Native v3占504文件，包含独立公开/内部封装及兼容引用闭包；spikes占196文件，其中40份reference、38份生成/构建器、30份runner、31份报告；fixtures仅25文件但新增56,885行。文件与行数不能等同手写产品功能量。
- 耗时判断：提交时间间隔约30小时14分，仅代表日历跨度。提交日志显示工作集中于同步状态机/双库导入与恢复、SQLCipher/JCS/签名/真机实验、旧Contract兼容和跨语言机器闭包；公共源码变化引发证据摘要过期、多轮回归，以及Docker/设备/Windows清理故障增加耗时。没有完整执行时间轨迹，不给出各模块耗时百分比。
- 快速发现：`contracts/spikes/sync_v1/README.md:63`仍称默认入口应失败且未冻结，与同文件开头、机器CONTRACT FROZEN和交付记录冲突；属于非重大文档收尾遗漏。超大单次封版提交降低独立审阅与定位效率，但抽查生成器和参考程序用途支持其主要范围，未因文件多直接认定越界。
- 验证：独立Git提交级数量/目录/扩展名统计、生成器与参考验证入口抽查、提交内日志时间线核对及diff空白检查；空白检查只报告5份上游许可文件的6处原始空白。未重跑耗时实验、产品构建或全量冻结门禁，交付报告测试结果作为历史证据引用。保留当前外观任务的未提交修改，本轮仅追加日志。

## 2026-09-06 22:05 +08:00 Native v3文件扩张实例说明

- 使用上下文：沿用已读取的calendar-data-contracts规则；模块：Native v3协议与生成器。目标：用真实event.complete接口解释v3的身份包装、旧协议复用、兼容引用传播与重复文件来源。
- 结果：公开v3请求的payload直接引用旧complete_event_request；内部请求增加runtime binding并引用生成的internal_payloads副本，副本保留相同业务字段约束。因此接口身份升级必要，但每个方法独立落盘、对未改变payload也展开复制属于当前生成器组织选择，并非v3版本必然要求。event_response的计数约束变更会沿详情/列表等引用传播。未发现本提交重写旧contracts/event定义，不把计划协议误称为已接入产品。
- 验证：实际Schema、v2/v3映射、生成器plain_body/public_legacy/native_payload与event_response差异只读比对；无代码修改、无构建测试，仅追加说明日志。

## 2026-09-06 22:08 +08:00 Contracts封版下游阻断快速审阅

- 使用 Skill：calendar-data-contracts；范围：提交5d8fb0a的Contracts交付与总计划要求，重点关注03–06分计划的接口依赖，不实施修复。
- 确认问题：总计划第269行和Contracts计划IMP规则要求guest导入退休以source_migrated终结Reminder与prepared Notification，但Native v3 Reminder响应last_cancellation_reason、Notification响应abandon_reason及其abandoned条件分支均不接受该原因。import_cleanup_reference使用简化表写Notification state=cancelled，而实际Notification状态枚举只有prepared/sent/failed/abandoned，现有cleanup测试未验证真实审计对象的Schema闭包。该同一根因需Contracts补齐后再封版，影响03的导入退休/审计与05的执行取消对接，不要求暂停无关模块。
- 其他抽查：五类run intent、conflict resolve意图提交响应、默认提醒适用矩阵、退出缓存策略响应和冻结状态未发现新的明显矛盾；不将有限抽查等同完整无缺陷证明。
- 验证：从HEAD读取Schema并独立检查枚举，确认两个原因字段均拒绝source_migrated；核对Native v3 reminder.list引用链、总计划、导入参考程序与测试。当前Python无jsonschema，未安装依赖，未运行完整Schema验证、耗时spike或产品构建。保留外观任务全部未提交修改，仅追加日志。

## 2026-09-06 22:40 +08:00 Contracts 提交与分计划一致性扩展审阅

- 使用 Skill：calendar-data-contracts、review-worktree-architecture；后者要求独立测试设计，由独立测试子任务依据计划先建立预期，再验证协议与精确 DDL。
- 负责模块与目标：固定提交 5d8fb0a6debe3dc4e99e8aed5213ed9d3b43731d，对照父提交与当前 Contracts 计划、Native V2 保护基线，审阅新增协议、生成器、存储模型、参考程序及验证证据；不实施修复、不提供修复方案。
- 结果：归并确认 11 类问题：导入控制消息被 Outbox target CHECK 拒绝；resolution 的 Outbox codec 与 Native prepare/ack 不能承载专用 HTTP 路由；guest 退休 reason 与真实审计 Schema 不一致；Native import_status 缺少计划要求的 affected identities；混合 Calendar/Search 查询仍只有单 timezone；workspace.activate 参考门禁把目标误当当前 workspace；普通同步 cleanup UTC 水位缺少正式 v6 持久化映射；Native resolution 返回 Kotlin-owned status_revision；新 Event fact 四个 lifecycle datetime 未落实 UTC 限制；Java/Dart 对真实 Habit start_date 的 year 0000 接受结果不同；30 份新 Native v3 payload 残留 integrated 状态标注。未将缺少后续产品实现、获准的 Native v3 版本化和原始 tzdata Makefile 纳入问题。
- 验证：从 HEAD 导出隔离快照，使用已有离线 Python 依赖运行 validate_sync_v1.py --self-test。机器审计通过 CONTRACT FROZEN、220 protected、951 Schema；执行 348 项测试，无断言失败，但 StorageTests setUpClass 因快照缺少预构建 C++ 静态库而报错，整体退出 1，不能声明全套测试通过。另完成独立 exact Outbox DDL/codec 和 Native/HTTP 反例，两个普通 exchange 对照通过；运行 Java/Dart 原始探针复现日期差异；解析 181 份 Python 文件 AST。未重跑 Android 真机、全套四端编译、PostgreSQL 环境实验或产品构建；原提交实验报告的摘要校验不等于本轮重新执行实验。
- 修改范围：仅追加本日志，诊断脚本与快照位于系统临时目录；保留其他任务的外观与界面未提交修改。详细问题、源码位置与判断理由在本任务最终审阅结论列出。


## 2026-09-06 23:15 +0800 云同步-02 Review 复核与修订开始

- Skill：calendar-data-contracts、debug。模块：Contracts、planned Native v3 / SQLite v6、隔离参考与回归验证。
- 目标：独立核实提交 5d8fb0a 的 11 类 review 问题，确认存在后修复，保护历史 220 份定义与其他任务修改。
- 结果：11 类均确认；实际 SQLite Outbox CHECK、HTTP→Native schema、workspace.activate CAS、Event UTC、Java/Dart 日期探针均复现。第 3 类通过独立 v3 审计修订解决，旧 Notification 的拒绝行为不改。暂撤销冻结与下游实施许可，修订验证完成后重新锁定。
- 当前状态：在 A:/calendar/ExcellentCalendarAPP-sync-review 的 codex/cloud-sync-02-review 隔离工作副本修订中；尚未完成，不声称旧 1308 个样本覆盖新增场景。


## 2026-09-07 00:42 +0800 云同步-02 Review 兼容修订验收

- Skill：calendar-data-contracts、debug。模块：Contracts、planned Native v3/SQLite v6、隔离参考与验证、同步计划交接文档。
- 目标与依据：固定5d8fb0a独立复核用户提供的11类问题，确认事实后按02目标及01裁决顺序修订；旧Native v2和active SQLite v4/v5保持原定义。
- 结果：11类均成立并修复。补齐import控制消息及resolution的Outbox/Native链路、v3完整退休审计和持久affected execution、双时区owner、目标workspace激活CAS、正式UTC清理水位、Native revision owner、UTC/date边界、planned标注；修正生成器共享日期字典副作用并验证重复/组合生成一致性。旧Notification拒绝新reason是合理旧行为，本次使用独立v3修订。
- 验证：默认门禁CONTRACT FROZEN，220 protected/961 Schema/1197机器输入，43项门禁反例通过；四语言1376项一致，协议53项、能力及Review22项、导入组件54项、组合恢复27项通过；SQLite11项/134回滚边界、PostgreSQL70项、20k/50k完整发布通过；手机64/32位及Java/Windows各49项证明验签通过。所有证据来源摘要匹配，未手改报告制造通过。
- 冻结锁：888fee7a8767eed7ac95eb3c7a76707e8bd3ed3264695ebdf750cc837d3643a9；03–06同版输入，新产品能力仍planned。本轮未改产品业务源码，未重跑完整产品应用构建，既有未受影响的系统实验按原始证据保留。
- Git交接：目标HXY；隔离分支codex/cloud-sync-02-review只提交Contracts及相关文档。33个外观/界面等其他任务文件和原有日志已备份并按摘要保护，不纳入本次提交；具体问题及验证详见云同步-02-Review复核与兼容修订记录.md。

## 2026-09-07 02:00 +0800 云同步-03 C0 先行测试与冻结输入阻塞

- Skill：cpp-core-feature、calendar-data-contracts。模块：cpp_core 测试/CMake、C++ 云同步问题文档与索引。
- 目标：按云同步-03 C0–C8 顺序实施，正式开发前先写验证代码与预期；本次无手机，未决跨层问题记录 problem-cpp.md 并使用测试专用冻结输入。
- 结果：部分完成 / C0 BLOCKED。新增正式冻结 preflight、只读 fixture 输入适配器、5 项输入准备测试、3 个真实 C++ SQLite/lease 基础场景及 writer 初步盘点/后续章节预期；未修改生产源码，C1–C8 未实施，不标记 Layer Complete。
- 根因：37c3521 的 Appearance display 扩展修改两个受保护 request/response，并新增引用 Schema；当前同步旧基线与来源锁未接纳该兼容修订。官方默认入口实际报 Protected Contract drift。全部锁定来源比对只有这两项不匹配；问题、准确摘要、Source of Truth、影响与最小解除条件已写 docs/issues/problem-cpp.md（CPP-SYNC-001）。不撤销界面修改、不重写旧摘要伪造冻结。
- 测试先行：所有新增代码均为测试和测试输入读取器。首次测试构建发现 UUIDv4 声明头文件遗漏，初次执行发现 fixture 文件的不同 expected 形状及 Category 持久化需要非空 sort_order；修正测试构造/解析后重建，不修改生产规则或削弱断言。
- 验证：cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON 退出 0；cmake --build cpp_core/build-ninja --target excellent_calendar_check 最终退出 0，15/15 目标通过，50.63 秒；其中 fixture 751 条仅做输入/预期闭合核对，不冒充 751 项同步行为通过。excellent_calendar_sync_v1_preflight 与 python contracts/run_sync_v1_validation.py 均退出 1（上述真实冻结冲突），不能由回归绿灯抵消。git diff --check 通过。
- 未验证：v6/多 runtime/业务+Outbox/apply/bootstrap/import/SQLCipher 生产能力、性能、三 ABI 加密 APK、JNI/Backend/Flutter 消费签收和真实设备行为。本轮没有把 fake 接入生产路径。
- 修改保护：开工工作区 clean；工作期间出现其他 Kotlin/Flutter 测试和 problem-kotlin.md，未读取、改写或回滚。无提交/推送。

## 2026-09-07 02:05:30 +08:00 — 云同步-06 Flutter 测试先行与前置门禁

- Skill：frontend-flutter-feature。
- 负责模块：Flutter 云同步 F0 测试输入检查与 F1–F7 验收预期；未修改生产 Dart、Contract、Kotlin 或 C++。
- 任务目标：按云同步-06 章节顺序完成产品功能，正式实现前先写测试及预期；无手机环节以测试替代，冲突记录到 docs/issues/problem-flutter.md。
- 本次结果：部分完成/前置门禁未通过。新增 flutter_client/test/sync_v1/contract_preflight_test.dart，覆盖默认 validator、四端输入锁、35 个公开方法和 16 类 fixture 入口。新增云同步-06-Flutter测试先行验收矩阵.md，明确 F1–F7 仍为行为规格、尚未全部转成测试代码，不能据此宣称用户目标完成。
- 冲突：两份 Appearance JSON Schema 的结构化摘要偏离冻结保护基线；现有会话仍是旧 Dart owner，新的同包 Native owner 尚待交接；既有 AppearancePage 缺失导致全项目 analyze 失败。记录 FLT-SYNC-001 至 FLT-SYNC-004，未重置摘要或隐藏失败。
- 验证：默认 Contract validator 退出 1；Flutter F0 套件 54 项，53 通过、1 因真实冻结 gate 失败；新增测试格式化已执行；flutter analyze --no-pub test/sync_v1 通过；全项目 flutter analyze --no-pub 退出 1，26 项既有 Appearance 相关问题。全量 Flutter 测试、Debug APK、真实 Kotlin Handler/手机/多设备 smoke 未执行，均 UNVERIFIED。
- 保护范围：保留同期 C++/Kotlin 任务和 docs/index.md/docs/log.md 的既有修改；索引仅增加本任务入口，日志仅追加。不提交、不升级依赖、不接入生产 Fake。

## 2026-09-07 — 云同步-05 Kotlin 先行测试、隔离组件与 K0 阻塞

- Skill：android-kotlin-native-feature。
- 负责模块：flutter_client/android 的 bridge/sync 隔离组件、JVM 先行验收和 K0 Contract 输入检查。
- 任务目标：按云同步-05 章节顺序实施，正式开发前先写相关测试与预期；无手机用测试替代，未决冲突写入 docs/issues/problem-kotlin.md。
- 实际结果：部分完成 / K0 BLOCKED。先写第一批 26 个组件测试，再实现路由/lease、刷新 single-flight、AEAD binary key、严格 JSON 输入/URL/退避、耐久唤醒端口合并、BootEpoch/retention 时间计算及平台身份。后补正式 fixture/前置 gate，共 29 项；完整计划的所有功能测试尚未写完，K1–K6 没有签收。新增入口 run-sync-v1-unit-tests.ps1、sync-v1-acceptance.md，更新计划检查点与索引。
- 验证：同版本 Kotlin/JUnit 重新编译运行 29 项，27 通过、2 失败、0 跳过；64 条正式 JCS 输入向量全部按预期拒绝或原样转发；100 并发 refresh 和 10,000 次 wake 合并通过。两项失败为默认 Contract validator 及归一化源摘要检查，均定位两份 Appearance Schema 漂移，没有改摘要、skip 或弱化 gate。最新输出为 flutter_client/build/sync-v1-jvm/8e23deb0d71b4feba327504587b50aeb/junit.txt。
- 构建：标准 testDebugUnitTest/lintDebug 均因既有 Flutter AppearancePage/类型缺失失败；排除该已知 Flutter 编译节点后 compileDebugKotlin 与最终 lintDebug 成功。旧 HabitMethodHandlerTest 的 AppearancePreferencesStore 替身另有未实现方法。完整 APK、三 ABI、Release/TLS、真实 JNI/SQLCipher/Keystore、connected instrumentation 与多设备为 UNVERIFIED，没有把局部 lint 或 JVM 替身当作整体通过。
- 边界：没有修改 Contract/C++/Flutter 实现，没有接入生产 v3 通道或新的 RT owner，没有新增依赖/升级版本。跨层替身仅在 src/test；bridge/sync 仍未组装进生产 Application/Worker/JNI。保留同期其他任务的文件和日志修改；日志仅追加。冲突、解除条件及剩余章节记录 KOT-SYNC-001 至 006。

## 2026-09-07 02:19:35 +08:00 — 云同步 C++/Kotlin/Flutter 限制解除条件分析

- 使用 Skill：calendar-data-contracts；负责模块：云同步 Plan 02/03/05/06 的 Contract、实施门禁与跨层交接分析。
- 任务目标：只读核对 `problem-cpp.md`、`problem-kotlin.md`、`problem-flutter.md`，说明解除当前 C0/K0/F0 限制及完成三个分计划至少需要的工作；不实施功能修复。
- 结果：确认三层共享的即时硬阻塞是 Appearance display 扩展未纳入 Sync V1 保护基线、完整来源闭包和四端 revision/hash。解除当前生产编码暂停至少需要保留 display 行为、完成新旧 reader/writer 兼容矩阵与受审阅的 Contract 修订、纳入 `display_preferences.schema.json`、重跑消费证据并重新封版；不得只替换摘要。进一步完成 C++、Kotlin、Flutter 分计划分别仍需 C1–C8、K1–K6、F1–F7，且 Kotlin/Flutter 生产集成依赖 C++-03、Backend-04 和同包 Session owner 迁移。
- 实际验证：当前工作树执行 `python contracts/run_sync_v1_validation.py` 退出 1；`excellent_calendar_sync_v1_preflight` 退出 1；两者均复现 `local_appearance_response.schema.json` 与 `update_local_appearance_request.schema.json` 的受保护来源漂移。仅作门禁诊断，未运行 Flutter/Android 全量构建或设备测试。
- 修改范围：仅向本日志追加本条；保留当前工作树内其他 C++、Kotlin、Flutter、计划、索引和问题文档修改，未改写或回滚。

## 2026-09-07 16:06 +08:00 — Native v3 必要性与过度设计分析

- 使用 Skill：`self-learning`、`calendar-data-contracts`；负责模块：Native v2/v3 Contract、云同步 workspace 路由与兼容边界。
- 任务目标：通俗说明 `contracts/native_v3` 的来源、主要解决的问题与必要程度，并批判性判断是否存在过度设计；不修改产品代码或 Contract。
- 结果：确认 Native v3 同时承载 Anniversary 分类弱引用放宽、显式 workspace/route/runtime 绑定、新同步与账号能力、recurrence counter 扩宽、通知路由和双时区修订。若继续实现多 workspace 云同步，建立 breaking Native revision 有较强必要性；但当前 510 文件、107 个公开方法与 90 个内部调用的整版快照明显扩大了认知和实施成本，完整形态的必要性仅为中低。v2 仍 active，v3 全部 planned，产品代码中未发现 v3 生产实现。
- 验证状态：只读核对 ADR、领域模型、活动计划、机器冻结状态、v2/v3 注册表、代表性 Schema、生成器、文件数量及生产代码引用；未运行 Contract 全量验证、构建或设备测试。另确认 `docs/status/current.md` 仍写 Contract Pending，而机器 gate 与最新活动计划写 Contract Frozen，属于状态文档滞后。
- 修改范围：仅追加本日志；保留工作树中全部既有修改，未改写 Contract、实现或测试。

## 2026-09-07 16:13 +08:00 — `.agents/skills` 文档一致性审查

- 使用 Skill：`review-worktree-architecture`；负责模块：`.agents/skills/**`、项目文档导航与当前架构基线。
- 任务目标：只读检索 Skill 文档中技术细节过度固化、不符合当前开发状态、以及与当前 `docs/index.md`/项目级 `AGENTS.md` 冲突的内容。
- 结果：判定 `CHANGES REQUIRED`。确认 C++ 与数据 Contract Skill 仍把 JSON 视为当前 writer，与 active SQLite v5 机器 Contract 冲突；Backend Skill 在 `backend/**` 与 `cloud_backend/**` 间自相矛盾并包含无效命令/路径；9 个 Skill 均未引用 `docs/index.md`，多份 Skill 绕过固定导航顺序、提高 README 优先级或把 `docs/log.md` 设为只读；另有不存在的 `DATA_MODEL.md`、`BUG_REPORT_TEMPLATE.md` 引用和大量易过期的领域/实现细节复制。
- 验证状态：完整读取 9 个 `SKILL.md`，核对根 `AGENTS.md`、当前工作树 `docs/index.md`、`docs/architecture/overview.md`、`docs/status/current.md`、Storage v5 机器 Contract、Backend POM 与实际目录；执行定向路径存在性和引用检索。未运行产品构建或测试，因为本任务只审查文档；未创建独立测试文件。
- 修改范围：仅追加本日志；未修改 Skill、索引、Contract、实现或测试，保留工作树中原有云同步相关修改。

## 2026-09-07 16:17 +08:00 — `docs/domains` 与 `contracts` 对应关系审计

- 使用 Skill：`calendar-data-contracts`；负责模块：领域模型文档、Native/Backend/Storage/Sync Contract 与事实源优先级。
- 任务目标：只读判断当前 `contracts/` 是否能与 `docs/domains/` 相互对应，并评估“领域文档优先于传输 Contract”的设计理念是否已被项目规则一致表达。
- 结果：部分对应，不能认定完整闭合。Event、OccurrenceState、Recurrence、Reminder、Notification、RecoveryBatch、Habit 四模型、Category、SearchIndex、SyncOperation、DatedMessage、UserPreferences 等核心响应字段可按 camelCase↔snake_case 对齐；Anniversary、Calendar/Search 投影和 Backend-only 认证模型属于跨多个 DTO/协议的职责对应，不是文件一一对应。`contracts/` 同时包含平台能力、公共包装、存储、生成的 Native v3 镜像、fixtures、tests 与 spikes，本就不应全部被解释为领域实体。
- 发现：数据 Contract Skill 已明确 `用户需求 → docs/domains 领域语义 → contracts 传输协议 → 持久化 → 实现`，但根 `AGENTS.md` 的默认冲突顺序仍将 machine-verifiable contracts 排在 current domain invariants 前；`docs/domains/enums.md` 的 NotificationKind 汇总遗漏 `anniversary_catch_up`；旧 `sync_operation.md`/领域 README 仍写 Contract Pending/Decision Required，而机器 gate 已为 CONTRACT FROZEN；`contracts/README.md` 局部仍把 SQLite v4 写成当前 writer，与领域 README 和机器 Storage v5 冲突；Appearance display Contract 没有对应领域文档或完整状态元数据，且未进入 Sync 受审阅基线。
- 验证：`run_anniversary_r1_validation.py`、`run_calendar_v1_validation.py`、`run_search_v1_validation.py` 退出 0；`run_habit_v1_validation.py` 退出 1（`display_preferences.schema.json` 缺少 integrated 状态）；`run_sync_v1_validation.py` 退出 1（受保护的 `local_appearance_response.schema.json` 漂移）。通过的套件证明 Schema/$ref 与对应模块机器规则闭合，不等于领域文档全量一致。
- 修改范围：仅追加本日志；未修改 `docs/domains/`、`contracts/`、实现或测试，保留工作区中既有 C++/Kotlin/Flutter/计划/问题文档修改。
