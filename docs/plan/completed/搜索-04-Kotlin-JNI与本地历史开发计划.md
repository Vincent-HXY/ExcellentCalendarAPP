# 搜索-04：Kotlin、JNI 与本地历史开发计划

Status: Completed / Production Integrated / Host + Android Device Verified / Released

> 2026-09-02 发布校准：真实 JNI endpoint、Kotlin handler、AtomicFile/noBackupFilesDir History、连续 seeded 三类型查询与 force-stop 恢复均已完成主机和 Android 13 设备验证。产品负责人接受 `OPEN-SEA-001` 发布后债务后，本层随 Search V1 激活；下方未勾选项保留为原始派发验收矩阵。

负责人：Android/Kotlin 下层（`android-kotlin-native-feature`）  
允许修改：`flutter_client/android/**`  
依赖：搜索-02 Contract；Search query 真实联调依赖搜索-03 C++ endpoint  
禁止修改：Contract、C++ 领域规则、Flutter 页面、依赖/工具链版本

## 1. 交付目标

在现有单一 Calendar Core runtime owner 上新增窄 Search handler/bridge，把 `search.query` 严格接到唯一 C++ endpoint；同时在 Kotlin 以 `AtomicFile` 实现两个设备本地 history 方法、revision compare-and-replace、损坏修复与 confirmed durable commit。

Kotlin/JNI 不实现关键词规范化结果、匹配、相关度、完成状态、occurrence、排序或分页真相。History 不进入 JNI/C++/SQLite。

## 2. 当前基线与风险

- `NativeMethodChannelHandler` 已有模块化注册和 `SingleCompletion`；
- `NativeCallExecutor` 可在单线程后台执行 native/operation 并回主线程完成；
- `NativeCalendarCoreBridge`、`AndroidNativeBridgeFactory`、`JniNativeCalendarCoreBridge` 维持一个进程级 runtime；
- Habit/Category 的 JNI 路径已有严格 UTF-16 ↔ UTF-8 转换可复用；旧 `event_jni.cpp` 的 `GetStringUTFChars/NewStringUTF` 不适合 emoji/补充平面字符；
- `SharedPreferencesAppearanceStore` 只适合简单偏好，不能复用到需要 confirmed CAS 的 Search history：SharedPreferences 会先改变内存状态，`commit=false` 无法证明旧快照仍是唯一权威；
- History 固定写入 `Context.noBackupFilesDir/excellent_calendar_search_history_v1.json` 并由 `android.util.AtomicFile` 管理，因此无需也不得新增与实际文件无关的 backup XML/Manifest 声明；
- Calendar 与 Search 会共同触碰 handler、aggregate bridge、JNI runtime、CMake、MainActivity 与错误 registry，这些共享文件由最终集成人员统一处理冲突。

## 3. 建议文件与符号

新增：

- `bridge/contract/SearchContracts.kt`；
- `bridge/channel/SearchMethodHandler.kt`；
- `bridge/native/NativeSearchBridge.kt`；
- `bridge/native/JniSearchBridge.kt`；
- `android/search/SearchHistoryStore.kt`、`SearchHistoryCodec.kt`；
- `src/main/cpp/boundary/adapter/jni/search_jni.cpp`；
- 对应 Contract/Handler/Store/JNI/Symbol 测试。

共享修改：

- `NativeMethodChannelHandler`：注册三方法；
- `NativeCalendarCoreBridge`：聚合窄 `NativeSearchBridge`；
- `JniNativeCalendarCoreBridge`：通过现有 runtime 调用唯一 Search symbol；
- `MainActivity`/production composition：注入 application-context、进程单例的 AtomicFile history store；
- `NativeErrorContract`：增加 6 个冻结错误；
- Android CMake：仅加入 `search_jni.cpp`；

建议唯一符号链：

```text
SearchMethodHandler
  → NativeSearchBridge.querySearch(requestJson)
  → JniSearchBridge / JniNativeCalendarCoreBridge.nativeQuerySearchV2
  → search_jni.cpp
  → excellent_calendar boundary search_query_v2
```

最终符号名以 C++ 下层回报为准；只能有一个 Search JNI query。

## 4. 实现拆解

### K0：Contract 与共享文件门禁

- [ ] 先运行 Search validator，Kotlin 正反例直接消费 31 fixtures；任何 `x-search-contract-revision != 2` 立即停止；
- [ ] 等待 C++ endpoint/ownership/signature 冻结后再接真实 JNI；
- [ ] 对 Calendar/Habit 在途共享 diff 建立逐文件 owner，禁止覆盖；
- [ ] 不修改旧 `event.search` 或添加 V1 fallback；
- [ ] `search.*` 保持 planned/blocked。

### K1：严格 Contract adapter

- [ ] 三个公开方法名与 request/result Schema 精确一致；
- [ ] 顶层 object、required、额外字段、显式 null、safe integer、enum、date、UTC、array、cursor 全部严格校验；
- [ ] `query_generation` 只验证/透传，并校验 response 精确回显；不得与 Store generation 混合；
- [ ] keyword 原始 Unicode 无损转发，孤立 surrogate/长度错误返回冻结错误；Kotlin 不先替 C++决定匹配结果；
- [ ] Category 三态、target/section 固定顺序、多 section 首屏/单 section continuation 规则严格一致；
- [ ] typed response discriminator、matched fields/snippet、Category、Event time/navigation、Habit/Anniversary date-only 严格校验；
- [ ] page size 只接受 20；校验 `total_count/items/has_more/next_cursor` 和 section identity/顺序；初始 response 缺 requested section 必须失败，不能补空 section；
- [ ] malformed native JSON/union/NativeResult 仍为 `CONTRACT_VALIDATION_FAILED`，不包装成空成功。

### K2：本地 SearchHistoryStore

内部格式是一个有序 JSON 文件，不使用 SharedPreferences 或无序 `StringSet`：

```json
{
  "schema_version": 1,
  "revision": 0,
  "keywords": []
}
```

物理路径固定为 `Context.noBackupFilesDir/excellent_calendar_search_history_v1.json`，并由一个进程单例 `AtomicFile` owner 管理；`.bak` 等恢复文件也只能位于同目录。

- [ ] `get` 返回完整有序 items + revision；缺失文件为 revision 0/空列表；
- [ ] 所有 `get/read-repair/replace` 在同一个 store instance 的互斥锁内串行；`replace` 比较 `expected_revision`，失配零写入并返回 `SEARCH_HISTORY_CONFLICT`；
- [ ] 列表相同则幂等返回原 revision；revision 已达 `9007199254740991` 时仍可幂等成功且零写入；
- [ ] 列表真实变化或损坏修复需要加一但 revision 已达上界时，返回 `SEARCH_HISTORY_STORAGE_FAILED`，原 bytes、revision、committed snapshot 均保持不变；
- [ ] 严格写入拒绝 >20、空白、超长、非规范化、非法 scalar、ASCII-insensitive duplicate；不得静默截断 caller payload；
- [ ] 已知 v1 损坏数据按 Contract 规范化/去重/保序/截断；只有 AtomicFile 修复落盘成功后才把修复结果作为 response/内存 committed snapshot 发布；
- [ ] 未知 future version 原样保留并返回 storage failure，不覆盖；
- [ ] 写入固定流程为 `startWrite → encode/write → finishWrite`；任一异常调用 `failWrite`，返回 `SEARCH_HISTORY_STORAGE_FAILED`，且不更新进程内 committed snapshot；禁止先发布内存值再尝试磁盘写入；
- [ ] 进程启动/每次 read 由 `AtomicFile.openRead` 完成 backup 恢复；增加 prepare→kill→restart 测试证明只读到旧完整或新完整版本，不出现混合/半文件；
- [ ] 日志只记录损坏类别/版本，不记录 keyword、原 JSON 或用户内容；
- [ ] get/replace 都通过 `NativeCallExecutor.executeOperation`，主线程不做磁盘 I/O；
- [ ] 只依赖 application context，不新增账号、网络、Worker、Receiver 或权限。

### K3：Cloud backup 与设备迁移排除

“仅当前设备”按严格语义执行：

- [ ] 运行时断言 canonical path 的父目录等于 `applicationContext.noBackupFilesDir`，拒绝路径漂移到 filesDir、cacheDir 或 shared_prefs；
- [ ] 不设置全局 `allowBackup=false`，不修改其他模块的备份策略；
- [ ] 不新增 Search 专用 `fullBackupContent`/`dataExtractionRules`，因为真实文件不在这些备份域；若未来迁出 no-backup 目录，必须先回到 Contract 评审；
- [ ] unit/instrumentation 与打包验收同时检查文件绝对归属、进程重启持久化，以及现有 Manifest 未被 Search 改成全局禁用备份。

### K4：Handler 与线程边界

| 方法 | 后台工作 | 结果 |
| --- | --- | --- |
| `search.query` | `executeNative` → 窄 bridge | C++ NativeResult 原样类型化映射 |
| `search.get_local_history` | `executeOperation` → Store read/repair | SearchHistoryResponse |
| `search.replace_local_history` | `executeOperation` → CAS durable replace | SearchHistoryResponse |

- [ ] 参数小型结构校验在平台线程，JNI/JSON 大结果/磁盘 I/O 在既有单线程 executor；
- [ ] 回调统一回主线程并由 `SingleCompletion` 恰好完成一次；
- [ ] executor rejection/shutdown、engine detach、native late response 不 double callback；
- [ ] error code/details/retryable/request_id 安全透传，details 不含 keyword/history 正文；
- [ ] production 未注入 bridge/store 时返回真实不可用错误，不 fallback Fake/seed/旧 Event 搜索。

### K5：JNI 与 Unicode

- [ ] 新建独立 `search_jni.cpp`，禁止复用旧 modified-UTF-8 helper；
- [ ] 采用严格 UTF-16 surrogate 校验和标准 UTF-8 编解码，覆盖中文、emoji、组合字符、补充平面；
- [ ] Kotlin String → UTF-8 JSON → C++ → UTF-8 JSON → Kotlin String 全程无损；
- [ ] JNI string/array/local/global refs 和 exception 全部释放/清除；C++ exception 不跨 JVM；
- [ ] 通过 `callWithRuntime`/正式 factory 复用同一 Storage v5/TZDB owner；
- [ ] JNI 不解析 keyword token、cursor payload、日期、状态、排序或 occurrence；
- [ ] 增加 `SearchJniSymbolManifest`，三 ABI 只能出现冻结 symbol，不生成 history symbol。

## 5. 错误映射

| 场景 | Error | 自动重试 |
| --- | --- | --- |
| 业务关键字/filter/date/section 非法 | `SEARCH_QUERY_INVALID` | 否 |
| cursor 格式/auth 非法 | `SEARCH_CURSOR_INVALID` | 否 |
| cursor 与 query 不一致 | `SEARCH_CURSOR_QUERY_MISMATCH` | 否 |
| 相关 Store generation 变化 | `SEARCH_CURSOR_EXPIRED` | 是，仅刷新该 section |
| history expected revision 失配 | `SEARCH_HISTORY_CONFLICT` | 是，先 reload/rebase |
| history read/repair/AtomicFile durable commit 不可确认或 revision 耗尽 | `SEARCH_HISTORY_STORAGE_FAILED` | 是，保留已提交 UI 状态 |

Timezone、Storage、Contract、runtime/JNI 通用错误沿用现有 registry。不得增加自由文本错误码。

## 6. 测试矩阵

### Contract/Handler

- 顶层非 object、missing/extra/null/type、generation 范围/回显；
- Unicode whitespace、emoji、isolated surrogate、128/129 scalar；
- timezone、target order/duplicate、date pair、Category 三态、sort、section/cursor；
- 三类 union、matched field、snippet、Category、time/date/navigation identity；
- 固定 page size 20、section 0/1/20/21、initial requested section 守恒、exact total、terminal/nonterminal cursor；
- NativeResult success/failure、未知 error、malformed JSON、一次完成。

### History Store

- 0/1/20/21 items、ASCII-case duplicate、规范化、顺序；
- first read、idempotent replace、revision+1、revision 上界幂等/变化/修复、conflict、clear；
- known corruption repair、future version preserve、startWrite/write/finishWrite/failWrite 故障注入、并发 CAS；
- 失败保持旧 snapshot，日志不含内容；
- process restart prepare→kill→verify，只允许旧完整或新完整文件；
- canonical path 位于 `noBackupFilesDir`，APK/Manifest 没有 Search 专用虚假 backup XML 或全局 `allowBackup=false` 改动。

### JNI/ABI/回归

- 中文/英文/emoji/组合字符和大 response round trip；
- runtime 未初始化、native null/exception、executor shutdown；
- 真实三类 query，不用固定 pong 或只测 malformed；
- arm64-v8a、armeabi-v7a、x86_64 symbol；
- Event/Habit/Anniversary/Calendar/Reminder handler 回归；
- Debug APK 与 androidTest APK。

必须执行适用的 Gradle wrapper 任务：定向 unit、`:app:testDebugUnitTest`、`:app:lintDebug`、`:app:assembleDebug`、`:app:assembleDebugAndroidTest`，再执行项目 Native smoke。设备未执行项必须标记未验证。

## 7. 完成门禁与下层回报

Kotlin 独立层完成条件：

- 三个公开方法经过同一模块 handler；
- query 只依赖一个窄 native bridge，history 完全 Kotlin-local；
- 主线程无 JNI/磁盘 I/O；
- strict Unicode 与三 ABI 证据成立；
- history restart、corruption、AtomicFile failure、revision exhaustion、CAS 和 no-backup 路径验证通过；
- `src/main` 无 Fake/seed/fallback；
- 不新增权限、后台组件、第三方依赖或 Contract 字段；
- 未激活 capability。

若 C++ endpoint 尚未合入，只能报告 `Layer Complete / Awaiting Real JNI Integration`。回报必须包含：修改文件/注册点、字段映射、线程模型、AtomicFile canonical path/format/lock owner/failure injection、JNI symbol/ownership、fixture 对应、所有命令结果、三 ABI/设备证据、未验证项和共享文件冲突说明。
