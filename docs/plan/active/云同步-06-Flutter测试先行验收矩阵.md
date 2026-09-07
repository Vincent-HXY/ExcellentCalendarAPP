# 云同步-06：测试先行验收矩阵

日期：2026-09-07。Skill：frontend-flutter-feature。目标：正式实现前锁定正常、失败、恢复和隔离场景的可观察预期，按原计划 F0→F7 实施。

**当前状态：测试准备部分完成，F0 存在真实失败。只有 `flutter_client/test/sync_v1/contract_preflight_test.dart` 已成为可执行代码。以下 F1–F7 是待落地的行为测试规格，不得把表格、fixture 入口存在或测试 Fake 当作产品完成。**

## 测试约束

- 不改用户已有 C++、Kotlin、文档或字体工作；不升级依赖。
- 先写各行为的测试代码，再改对应产品代码；失败必须由实现满足原期望，不能删断言、skip 或重新生成摘要。
- Widget 通过窄 Gateway 注入假数据；Adapter 测试使用正式 fixture 的合成载荷。原始 JSON 只存在测试/边界；没有真实 Native 的场景明确标注。
- 使用可控 Completer、事件流和时钟，不用真实网络/手机或任意睡眠；双击计数、请求参数及没有发生的副作用都断言。
- 核心场景集中执行；实现前一次红灯基线、阶段出口相关套件、最后全量测试/分析/Debug APK，避免每个小修改都跑全量。
- 生命周期序列固定为 A→local→B，再注入 A 的迟到响应与事件；每次检查树、Controller、路由、草稿、头像、搜索和请求 identity。

## F0：输入与冻结门禁

| 编码 | 测试动作 | 预期结果 |
| --- | --- | --- |
| F0-01 | 在当前检出目录运行完整默认 validator | 退出码 0；不得用 CT0 子集替代；当前实测失败 |
| F0-02 | 对比四端消费者的 Contract 与 manifest hash | 四端一致；此项不能替代实际内容校验 |
| F0-03 | 对计划 §7 的 35 个方法逐个检查 | request/data/envelope Schema 均可定位 |
| F0-04 | 检查保留方法与禁止旁路 | sync.apply 只能为 blocked/not-implemented 墓碑；无 device.register 和 R3 Event 三作用域方法 |
| F0-05 | 检查 §15 的 16 类 fixture | 固定 case 的 pointer/expected 有效；生成套件的 runner/input/expected 可定位；不宣称这些 owner 套件已执行 |

## F1：DTO、Gateway、Adapter 和错误

| 编码 | Given / When | Then |
| --- | --- | --- |
| F1-01 | 每个正式 request/result 正例往返 | 字段、nullable、顺序、safe integer、UTC/date/IANA、identity 与 fixture 一致 |
| F1-02 | 加未知字段、删必填、错类型、未知 enum、超过安全整数 | 明确 Contract failure；不默认空值、不归类离线 |
| F1-03 | v2/v3 Native、Backend ApiResult 互换或 malformed envelope | 拒绝；不混淆版本和 envelope |
| F1-04 | 每个 Adapter 发送方法 | 精确 v3 channel/method、显式 workspace/route CAS、业务 CAS 各用所属 revision |
| F1-05 | get-state 调用方不知道 route revision | 允许无 CAS 的恢复读，不能死锁 |
| F1-06 | 错误返回含内部路径/敏感 message | 上层仅 typed code/retryable/经校验 context/request-id；日志无秘密 |
| F1-07 | logout/device/import/conflict oneOf 各分支 | 严格判别及 null 矩阵；未知组合拒绝 |
| F1-08 | Auth/Profile 首次 401，Broker 返回新 generation，再次 401 | rejected generation 原样提交；只重放一次，无 Dart refresh |

## F2：Session 与工作区根图

| 编码 | Given / When | Then |
| --- | --- | --- |
| F2-01 | 无会话冷启动 | local ready 完整主页；不要求登录、不请求 Profile |
| F2-02 | active session + local route 冷启动/丢事件 | 保持 local graph；返回账号仅在显式 activate 后发生 |
| F2-03 | 登录/注册成功 | 完整 AuthenticationResponse 交 adopt；不独立 register、不先构造账号可写 graph |
| F2-04 | adopt 不具备 entitlement | 原 guest graph 保留，显示固定测试未开放文案 |
| F2-05 | pending adoption / registration pending 重启 | 从 Broker status 恢复；不保留旧 AuthenticationResponse；设备清理或退出入口可达 |
| F2-06 | fresh/rebuilding 尚未 fence/bootstrap/import ready | 只有准备/重建状态，不能写业务 |
| F2-07 | activation 失败、锁定、密钥/绑定错误 | 明确阻塞，不隐式回落其他数据库 |
| F2-08 | 连续切换及双击 activate | single-flight；旧 Future/Event 不覆盖新图 |
| F2-09 | A→local→B，A 旧请求完成 | A 标题/邮箱/id/cursor/draft/image/restoration 不可见，B 请求不含 A identity |
| F2-10 | guest 登录页取消 | 同一个 guest graph、未提交输入和本机数据保留 |

## F3：“我的”、同步状态及失败修改

| 编码 | Given / When | Then |
| --- | --- | --- |
| F3-01 | 三种 session×route 组合进入 My | guest 登录/注册；active+account 资料/同步；active+local 返回账号/退出，不能误显示登录 |
| F3-02 | 订阅后事件先于 snapshot、重复或倒序 | 只接纳当前 tuple 且更新的 status revision |
| F3-03 | 注入十种 phase | 各状态有明确文案；idle 有 pending/failure 时不能说已同步 |
| F3-04 | paused/offline_pending 时继续编辑 | 精确权威 pending count；不禁业务、不暂停本机提醒 |
| F3-05 | queued/syncing 中双击手动同步或快速反向开关 | 不重复提交；set-enabled 用 policy revision，不用 status revision |
| F3-06 | App resume / 丢失事件后恢复 | 重新 snapshot；符合条件才调用同一 run-now，无 Dart 队列/定时器 |
| F3-07 | notice claim 前、claimed、no-longer-actionable、随后新 head | 仅 claimed 后显示；不清新 notice、不手改 unresolved 总数 |
| F3-08 | backlog normal/warning/critical | 按权威等级展示；用户显式导出，只显示安全处置结果 |
| F3-09 | failed-local 大于零 | 独立计数/列表/详情；不说自动重试，不计作 pending 或 conflict |
| F3-10 | failed 修改另存，成功 apply 之前/之后 | 走正常业务 Gateway 新 mutation；旧项先保持可恢复，由权威 apply 收口 |
| F3-11 | discard 取消/确认/版本失效 | 取消零调用；确认传精确 revision，重读 status；不手减计数 |
| F3-12 | awaiting-server-adjudication，尚无 created delta | 不预造 conflict 卡片或 toast |

## F4：本机数据及导入

| 编码 | Given / When | Then |
| --- | --- | --- |
| F4-01 | 首次登录与后续本机入口 | 同一 Controller；全量合并/保留本机，不逐条搬 payload |
| F4-02 | preview 正常/过期/source changed | 展示 typed 统计及提醒影响；失效重新 preview，不复用旧快照 |
| F4-03 | previous epoch cleanup pending / source owned / exhausted | 恢复旧清理/安全占用提示/禁新导入；不披露账号、不强制接管 |
| F4-04 | commit 双击及响应丢失 | 原 preview token/batch/revision，只启动一次；恢复相同 batch |
| F4-05 | 重启、返回、无 batch 的 source+epoch 发现 | 附着当前 handle；不误用 completed 旧 epoch |
| F4-06 | 九 stage 与三个独立 enum 组合 | 严格状态闭包；网络失败不是 stage |
| F4-07 | server-confirmed→publish-applied→cleanup-pending→completed | 只有 completed 显示迁移完成；此前不宣称源已清理 |
| F4-08 | repair successor / superseded / range-close / proof null | 旧 handle 只读，权威 successor 恢复；无 proof 显示等待，不自造 id/proof |
| F4-09 | import version conflict | 保留用户意图，重读当前 head/revision；不盲重试 |
| F4-10 | abandon confirmed/unconfirmed/already-confirmed 竞态 | 已取消/待确认/继续 publish 分别展示；不能把未知结果说成完成 |
| F4-11 | published predecessor 的 reconciliation successor | 无普通取消按钮；隐私销毁独立确认 |
| F4-12 | guest epoch 已推进，新数据写入，旧 cleanup 返回 | 新 epoch 内容不被 UI 清除；搜索历史不随导入复制 |
| F4-13 | 提醒切换阶段 | 仅展示 Native 投影，不通过页面生命周期开关提醒 |

## F5：冲突列表与解决

| 编码 | Given / When | Then |
| --- | --- | --- |
| F5-01 | 全部/日程/纪念日/习惯及稳定分页 | 独立 filter/snapshot/cursor；全部包含 Category 等其他合法对象 |
| F5-02 | 切筛选时旧分页迟到、加载更多失败 | 丢旧响应，保留当前数据，独立重试入口 |
| F5-03 | 普通字段/delete-vs-edit/Habit/recurrence detail | 分支专属 UI，云端/本机有文字标签；自动合并字段只读折叠 |
| F5-04 | 四种 resolve mode | 精确 typed resolution、expected-conflict-version；提交前展示结果，危险结果二次确认 |
| F5-05 | resolve 双击及成功响应 | 一次提交，只进入 resolving，不立即移除列表/减少红点 |
| F5-06 | 版本失效/already-resolved | 保留未送出草稿，提示并重读，不自动重提 |
| F5-07 | 本机 effect apply 或其他端 resolved delta | 从权威详情和 status 收敛为 resolved |
| F5-08 | 普通详情继续编辑已有 conflict 对象 | 引导到编辑并解决，不调用普通 update 绕过 |

## F6：设备、偏好、搜索、资料和通知

| 编码 | Given / When | Then |
| --- | --- | --- |
| F6-01 | device fresh/stale/unavailable，pending session | 区分旧快照与不可用；pending 无 current marker，不伪空列表 |
| F6-02 | rename 成功/版本冲突/双击 | 用 response-authoritative 值；冲突重载；一次提交 |
| F6-03 | 两类 device settings 离线提交 | 一次只改一字段；显示 local-saved/remote-pending；云端镜像不回滚本机状态 |
| F6-04 | reauthenticate 成败、换目标、撤销响应丢失 | 立即清 password；grant 绑定目标；不撤销本设备，不自行注册 |
| F6-05 | pending revoke registered/still-limited | 等待准备/刷新列表，不保留旧凭据或伪账号 ready |
| F6-06 | 四字段 preference patch，null/locale/wechat/重复渠道 | 只准冻结语义和白名单；locale 固定兼容读，不可写 |
| F6-07 | A 颜色→local→B；历史 Appearance | 图切换不泄露颜色；历史值只属于 guest |
| F6-08 | workspace timezone 改变与 OS timezone 改变 | 两轴分别刷新；workspace 改动不调用 Reminder reconcile |
| F6-09 | 有序默认提醒与所有业务适用组合 | 选首个合法候选；无交集无默认且允许无提醒保存；不改既有 Reminder |
| F6-10 | 新设备默认策略改变 | 不改变现有设备 receive-reminders，不重置账号首台例外 |
| F6-11 | workspace history CAS/迁移/锁定/导入 | 只迁旧全局到 guest 一次；切换清内存，不跨号回退、不导入 |
| F6-12 | profile cache empty/stale/guest；服务端新旧 revision | guest 无请求；旧 revision 不倒退；无全局文件 fallback |
| F6-13 | 服务端保存成功但 accept 失败 | committed-cache-pending；重新 get+accept，不说服务端未保存、不回滚 |
| F6-14 | 通知本机/当前账号/锁定账号/歧义 legacy/过期 | 先验证和 activate 等图重建再查对象；不可用不泄露、不跨库猜测 |

## F7：退出、清缓存、生产组合与最终门禁

| 编码 | Given / When | Then |
| --- | --- | --- |
| F7-01 | active 首次退出，包括 active+local | 只 Broker attempt-once；目标 session-bound 账号，不先 run-now 或读漂移计数 |
| F7-02 | review retry/cancel/skip，risk revision 过期 | 同 operation+revision；失效重读；返回要显式 cancel 或保留可恢复页 |
| F7-03 | skip 后 server unreachable | 不表示服务端退出；独立 force-local 确认只在 unreachable 证据后出现 |
| F7-04 | 无可信时间锚及 retain 被拒绝 | 仅 destroy/cancel/retry；不静默改选，不改变 session/cache/route |
| F7-05 | active/pending/verified retained cache 分支 | exact oneOf；pending 使用 session-generation；retained 有非 null deadline |
| F7-06 | 30 天期限展示 | 表达目标窗口，不承诺第 30 天整点删除；只有权威终态说已清理 |
| F7-07 | cache-clear preflight/fence 失败 | 常规路径零删除、session 保持、原 graph 可恢复 |
| F7-08 | destroy 后 rebuilding/import recovery、重启 | 账号遮罩，不恢复可写空库、不上传已毁 Outbox；保持 session，guest 不受影响 |
| F7-09 | 安全终止抢占，隐私 destroy future-fence | 严格权威终止投影；不伪造 clear reason、不冒充普通缓存成功 |
| F7-10 | active+local logout 成功 | 原 local graph 保留；清理隐藏账号的页面、头像、历史和恢复状态 |
| F7-11 | 默认 production composition | 真实 Session/Workspace/Sync/Device/Preferences/Profile Adapter；无 runtime Fake，无 RT read/owner，无 sync.apply |
| F7-12 | Debug LocalTestAccount | 固定 local-only，无 device/sync HTTP |
| F7-13 | Release URL 缺省/HTTP/loopback/私网与 Debug 例外 | Release fail closed，Debug 例外不泄漏 |
| F7-14 | 小屏、200% 字体、明暗主题、语义/焦点 | 操作不溢出遮挡；红点读出数量；危险操作明确；密码错误清空且焦点正确 |
| F7-15 | 首次启用/导入、暂停、退出/清缓存文案 | 固定风险提示、云同步不是备份；不承诺实时/永不丢失；明确暂停只停上传下载 |
| F7-16 | 全量 Flutter 测试、analyze、Debug APK、原模块回归 | 实际执行并记录；真机项按用户要求以测试替代且标记真实链路 UNVERIFIED |
| F7-17 | Contract 与四端交接 | 同一 hash 实际签收；最高 Layer Complete / Awaiting Integration，不宣称多设备已完成 |

## 当前执行结果

- `flutter test --no-pub test/sync_v1/contract_preflight_test.dart --reporter expanded`：54 项，53 通过、1 失败；失败为实际完整 Contract gate。
- 初版测试曾将 sync.apply 兼容墓碑视为公开能力、遗漏 generated-suites 中的 import 入口，已按机器 registry/manifest 修正测试解释；最终剩余失败没有被弱化或跳过。
- `dart format test/sync_v1/contract_preflight_test.dart`：已执行。
- `flutter analyze --no-pub`：退出码 1，26 项既有 Appearance 页面/相关类型问题，详见 FLT-SYNC-004。
- Flutter 全量测试、Debug APK 和真实 Kotlin Handler 冒烟：未执行，UNVERIFIED；未通过前置门禁，不重复运行已知会受既有编译缺口影响的广范围检查。
- F1–F7 产品行为测试：尚未编写/运行；不能声称全部测试已提前写完。
- 产品实现和生产组合：尚未修改；原计划完成定义尚未满足。
- 冲突、依赖及解除条件见 `docs/issues/problem-flutter.md`。
