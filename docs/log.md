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
