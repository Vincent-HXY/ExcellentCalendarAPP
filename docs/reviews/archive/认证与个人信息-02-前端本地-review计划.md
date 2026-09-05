# 用户认证与个人信息 — 前端本地 Review 计划

> 审查对象：`flutter_client/`（Dart + `android/` 内 Kotlin）认证与个人信息模块（对应开发计划 `docs/plan/active/认证与个人信息-02-前端本地.md`）。
> 审查依据（Source of Truth）：`contracts/backend_api.yaml` v1、`contracts/auth/`、`contracts/user/`（含 `cached_current_user.schema.json` v1）、`contracts/common/`、`contracts/method_channels.yaml`（`auth.refresh_token.*` 四方法）、`contracts/error_codes.yaml`、`docs/domains/`、`docs/architecture/overview.md` 第 2/8 节分层职责、开发计划第 2/3/5 节。
> 本文只定义审查内容与判定标准；不描述审查流程。所有结论必须给出契约条文、计划条款或代码事实作为证据。

## 1. 事实基线（必须独立重建，禁止沿用完成报告的结论）

| 事实项 | 当前契约事实 |
| --- | --- |
| 后端端点 | **17 个**，其中 `auth.registration.email.update` 存在于契约（PATCH `/auth/registration/email`，schema `update_registration_email_request.schema.json` 存在）——前端报告声称"不存在于契约"，与当前契约矛盾，须按 2.1 裁定 |
| MethodChannel 四方法 | `auth.refresh_token.store` / `read` / `delete` / `exists`：`implementation: kotlin_local`；**store/read/delete 标记 `sensitive_payload: true`，exists 无此标记**（按各方法声明分别处理）；返回信封为 `NativeResult`（NativeResult v2），非 `ApiResult` |
| Token 边界 | 计划第 5 节已冻结决策：AT 仅 Flutter 内存；RT 仅 Android Keystore；Flutter 仅在刷新/退出请求期间经 MethodChannel 短暂读取，用后不保留；页面不得直接读写 Token；退出/刷新失败/密码重置后必须删除本地 RT |
| 业务错误 HTTP 语义 | 后端契约 `envelope_only_errors: true`：业务错误也是 HTTP 200 + `ApiResult` 信封；限流信号只在信封 `retry_after_seconds`（无 Retry-After 头）——前端解析路径必须按此约定，而非默认"非 2xx 即异常" |
| 资料缓存 | `contracts/user/cached_current_user.schema.json` v1：`storage_format_version=1`，只含公开资料，禁止凭证字段 |
| 分层 | `presentation → application → gateway_interfaces → boundary_adapters → native_contract`，`main.dart` 组合根注入；原始 `Map` 只停留适配层；认证流量直连后端，不经过 Kotlin/C++ |
| 依赖边界 | 仅允许新增 `dio`；不得升级或新增其他依赖、SDK、构建组件 |

## 2. 对前端完成报告声称的逐项核验

### 2.1 "协议缺口"裁定（最高优先级）

报告称阶段 0 发现 `auth.registration.email.update` "不存在于契约"并据此停做"注册验证页修改邮箱"切片。当前契约该端点明确存在。用 git 历史裁定：

- 若开发期契约已含该端点 → 报告的缺口结论是对契约的误读，停做依据不成立，该切片属**未完成**而非"合规跳过"；同时后端报告出现同一错误结论，核查是否为交叉复制（前端读后端结论后未独立核对）。
- 若该端点为报告之后人工补入契约 → 核验修订记录与你的确认，评估当时停做的合规性，并确认补契约后该切片仍未实现、需排期。

### 2.2 两个跳过切片的合法性

1. **注册验证页修改邮箱**：依赖 2.1 裁定；核验你的确认记录；代码是否留有清晰扩展点且无半成品残留（未接入口的页面/控制器/死路由）。
2. **头像相册选择与上传**：报告理由为"无插件白名单外依赖/无声明通道"。审查该理由本身是否成立：
   - 头像上传/删除是 HTTP 端点（`user.avatar.upload/delete`），经 dio 即可完成，**"无声明通道"不成立**（上传不需要 MethodChannel）；
   - 真实阻塞点仅是相册选择需 `image_picker` 类插件，超出"仅 dio"依赖白名单——核验你的确认记录与理由的准确性表述；
   - 核验"展示/删除/服务端状态更新已实现"是否属实：`avatar_asset_id=null` 的默认头像语义、删除后旧头像缓存清理、更换按钮提示文案与实现一致、无残留半成品代码。

### 2.3 验证结论复核

1. 复现 `flutter test`（报告 336/336 = 既有 276 回归 + 新增约 60）、`flutter analyze`、`dart format`、Android `:app:testDebugUnitTest`、`flutter build apk --debug`；记录实际数字，**不得以报告数字代替**；无 skip 伪装。
2. 抽查测试质量（AI 高频：快乐路径、mock 掉被测核心、串行"并发"测试、widget 测试断言空泛）：
   - 单飞刷新：并发 N 个 401 是否真实并发、断言只触发一次刷新且其余复用同一结果；
   - Fake API client 是否模拟"HTTP 200 + error 信封"主路径（本项目业务错误也是 200，Fake 若只走异常抛出路径则漏测主约定）；
   - widget 测试断言用户可见行为（文案、状态切换、输入保留），而非仅 `pump` 不崩；
   - Kotlin 测试覆盖 codec 损坏分支、sensitive_payload 不打日志的断言。

### 2.4 范围与依赖

1. `git diff` 核验：仅 `flutter_client/**` + `docs/log.md`；`contracts/`、`cloud_backend/`、`cpp_core/` 未被触碰。
2. `pubspec.yaml` 仅新增 `dio`（声明 5.7.0、解析 5.11.0）；无隐藏依赖升级、无 lockfile 之外的修改。

### 2.5 "未验证"项的审查义务

报告如实标注的真机 Keystore 实际读写、真实 Token 刷新链路、九条端到端流程"未验证"。**未验证 ≠ 不审查**：无设备环境正是 AI 最容易留下假实现（如 debug 下 RT 降级写 SharedPreferences、通道方法未注册、Keystore 实现仅在单测 mock 下通过）的场景，这几部分必须加重静态审查（见 3.8）。

## 3. 重点审查内容

### 3.1 分层与架构边界（架构违规高危）

- 页面（presentation）不得直接持有 dio client、直接读写 SharedPreferences、直接拼 MethodChannel JSON、直接解析 Token；
- application 层（Controller/UseCase）负责流程编排与状态转换；gateway_interfaces 是能力契约；boundary_adapters 是唯一与 dio / MethodChannel 接触的层；native_contract 是 typed DTO；
- 原始 `Map<String, dynamic>` 只停留适配层，不得扩散到 UI 或领域代码；
- `main.dart` 组合根注入全部认证依赖；认证流量直连后端，**C++ 与 Kotlin 未参与认证业务**（Kotlin 仅 Keystore 存取删查，不保存会话真相源）；
- AI 高频违规：page 直接 `await client.post(...)`；controller 手拼 `Map` 绕过 DTO；DTO 层被 `dynamic` 架空；AT/RT 放进全局单例状态对象；Kotlin 侧缓存"登录态"。

### 3.2 Token 边界

- **AT**：仅存 Flutter 内存（认证会话控制器），不落 SharedPreferences/文件/SQLite；退出、刷新失败、密码重置后清 AT；
- **RT**：长期仅存 Android Keystore；Flutter 仅在刷新/退出请求期间短暂读取，**用后不保留在状态对象/字段/闭包中**；不落普通缓存、不写日志；
- 修改密码/改邮箱成功后保存后端返回的新 Token Pair（新 RT 写回 Android）；重置密码成功后清 AT + 删 RT；
- 页面/Widget 不得直接读取或拼接 Token；不得自行决定刷新时机；
- AI 高频：把 AT 写 SharedPreferences"方便恢复"；RT 缓存在静态变量或单例；`print`/`debugPrint`/日志输出 token；测试代码中泄漏真实 token。

### 3.3 单飞刷新（TokenRefreshCoordinator）

- 并发 401：只触发一次刷新，其余请求等待并复用同一结果；刷新成功后统一重试原请求一次；
- 重试后仍失败 → 不再二次刷新，清除登录状态并回登录页；**禁止无限刷新/无限重试循环**；
- 刷新期间到达的新请求排队等待同一刷新结果（不重复触发）；
- 新 RT 刷新成功后写回 Android；失败统一清态；
- AI 高频：每个 401 独立刷新（引发后端 family 撤销风暴）；刷新失败后仍重试原请求并再次刷新；忘记写回新 RT（下次启动用旧 RT）；单飞锁在异常路径不释放；退出/刷新竞态（退出后刷新回调覆盖已清状态）。

### 3.4 错误转换与映射

- transport 失败（断网、超时、DNS、非 2xx 无信封）与后端 `ApiError` 严格分离，走不同状态分支；
- "HTTP 200 + error 信封"按业务错误解析（dio 拦截器不得只按状态码判断成败）；
- 错误码→文案映射表覆盖全部 26 个错误码（重点 `AUTH_*`、`USER_PROFILE_INVALID`、`AVATAR_*`、`API_*`），无码缺省时不得直接展示英文错误码；
- `api_field_error` 显示到对应输入框附近；不向用户展示服务端堆栈、原始异常或内部键；
- AI 高频：把 200+error 当成功解析（静默进主页）；把 transport 错误映射成业务文案；拦截器吞异常；文案表缺码兜底裸码。

### 3.5 页面状态机与表单

- 明确互斥的流程状态（initial/editing/submitting/success/form_error/network_error/server_error/auth_expired），**禁止多个布尔变量组合表达状态**；
- 异步回调更新状态前检查页面存活（mounted/取消机制），页面销毁后不得 setState；
- 防重复提交（提交中禁用 + 异步闭包不可重复触发）；保证不产生重复账号/重复邮件；
- 登录失败保留邮箱输入、清空密码、不保存密码；注册/改邮箱失败保留已填内容；
- 本地校验仅改善体验，不替代服务端校验；
- AI 高频：async 回调未检查 mounted；防重复提交只禁按钮、闭包仍可重入；倒计时 Timer 未随页面销毁清理；验证页重发倒计时在后台恢复/热重载后漂移；忘记密码文案未统一。

### 3.6 幂等 Key

- 注册、验证码重发、改邮箱申请、头像上传携带 `Idempotency-Key`；
- **同一操作的客户端重试复用同一稳定 key**（与防重复提交解耦：重试是同一操作 → 同 key）；非每次点击生成新 UUID；
- AI 高频：每次点击新 key（重试变新操作，后端幂等失效）；把防重复提交当作幂等实现；key 生命周期绑定页面 rebuild。

### 3.7 资料缓存与 DTO

- 内存缓存 + 本地缓存两层；本地缓存按 `cached_current_user.schema.json` v1 写入 SharedPreferences，只含公开资料；
- **两条解析路径语义相反，不得混用**：网络响应的未知字段/枚举/版本 → 显式失败；本地缓存损坏 → 视为无缓存降级、不得崩溃；
- 退出清理敏感会话缓存；资料更新以服务端返回为准（写穿缓存）；陈旧缓存显示"信息可能不是最新"；
- DTO 严格解析（`snake_case` wire format 不变；未知枚举显式失败），不得默认值兜底；
- AI 高频：缓存与网络共用宽松解析（损坏崩溃或协议漂移被吞）；缓存混入 token；更新资料只改内存不写穿。

### 3.8 Kotlin Keystore 安全存储

- AES-256-GCM 主密钥 + 加密文件原子写（应用私有目录，随应用数据清除消失）；不得把 RT 写普通 SharedPreferences；
- **严格 codec**：损坏/版本不符 → 显式失败或"不存在"语义，不得静默覆盖或返回半截数据；
- 四方法严格按 schema 校验参数，返回 `NativeResult` v2 信封；`store/read/delete` 的 `sensitive_payload` 处理（不打日志）；`exists` 按无该标记的声明处理；
- 注册进 `NativeMethodChannelHandler` / `MainActivity` 的方式与既有模式一致；不保存会话真相源；
- 静态核查是否存在 debug 降级路径（真机不可用时 AI 可能留假实现）。

### 3.9 导航与启动

- 启动入口 `/auth-check` 统一认证检查页；四分支正确：无 RT → 登录页；刷新成功 → 更新 AT + 写回 RT + 拉 `user.get_current` → 主页；刷新失败 → 删 RT 清态 → 登录页；断网 → 恢复失败页 + 重试按钮；
- 退出登录：尽力调 `auth.logout`，无论成败本地清 AT/用户状态/敏感缓存、删 Android RT、清导航栈回登录页；**返回键不可回已登录页面**；
- 重置密码成功后清凭证回登录页；修改密码/改邮箱成功后当前设备保持登录（保存新 Token Pair）；
- AI 高频：Navigator pop 可回已登录页面；启动检查与刷新协调器双重刷新；恢复失败页无重试闭环；退出后异步刷新回调复活登录态。

### 3.10 头像（已实现部分）

- 展示路径：`Image.network` 加载头像 URL（对 ETag/304 语义的兼容）；`avatar_asset_id=null` 时恢复客户端默认头像；
- 删除头像后清理旧头像缓存、以服务端返回为准更新状态；
- "更换头像暂不支持"提示与实现一致，无死入口。

### 3.11 与后端的联调一致性

- baseUrl 默认 `http://10.0.2.2:8080` 且可被 `--dart-define=BACKEND_BASE_URL` 覆盖，无硬编码散落；
- 对后端契约的解析与 1 节基线一致（200+envelope 业务错误、无 Retry-After 依赖）；若后端实际违约返回裸 4xx，前端行为是否符合 transport 错误路径（不得映射为业务错误码）。

## 4. AI 高频错误速查表

| 错误模式 | 落点 | 判定标准 |
| --- | --- | --- |
| 幻觉式协议误读（声称契约缺少实际存在的端点） | 2.1 | git 历史裁定；误读即停做依据不成立 |
| 跳过切片的理由不实（"无声明通道"） | 2.2 | 对照契约核实理由逐项真伪 |
| 200+error 信封按默认 HTTP 语义处理 | 3.4 | 拦截器/Fake 的解析路径 |
| Token 落盘/缓存/日志（AT 或 RT） | 3.2 | grep 存储与日志调用点 |
| 每个 401 独立刷新 → family 风暴 | 3.3 | 并发测试 + 协调器代码 |
| 页面销毁后 setState / Timer 泄漏 | 3.5 | mounted 检查与 dispose |
| 每次点击新 Idempotency-Key | 3.6 | key 生成与重试路径 |
| 缓存与网络共用宽松解析 | 3.7 | 两条解析路径语义 |
| Keystore debug 降级假实现 | 3.8 | 静态核查降级分支 |
| 退出后异步回调复活登录态 | 3.9 | 退出与刷新竞态路径 |
| 测试假覆盖（Fake 不走主约定、串行并发） | 2.3 | 复现 + 抽查断言强度 |

## 5. 判定输出要求

审查结论必须包含四项裁决，每项给出证据（契约条文/计划条款/代码位置/复现实测）：

1. **真实完成度**：12 项能力完成度矩阵（注册、邮箱验证、登录、会话自动恢复、查看资料、修改资料、修改邮箱、修改密码、忘记密码重置、主动退出/退出所有设备、AT 自动刷新、RT 失效回登录），每项标注 完成/偏差/未完成/未验证；对两个跳过切片的最终裁定（停做依据是否真实成立）。
2. **问题模块清单**：按严重度列出，每条注明对应契约条文或计划条款及具体偏差。
3. **未完成模块清单**：注册验证页修改邮箱（依赖 2.1 裁定）、头像相册选择与上传；报告第 7 节"未验证项"（真机 Keystore、真实刷新链路、九条端到端）逐项确认如实标注且静态审查已覆盖。
4. **架构违规清单**：逐条对照计划第 2 节硬性边界 5 条 + 第 5 节全局约束（分层、Token 边界、单飞刷新、状态机、缓存、Keystore、导航）+ 3.1 分层边界；每条注明违规位置与修复建议。
