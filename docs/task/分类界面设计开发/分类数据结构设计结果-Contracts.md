# 分类数据结构设计结果（Contracts）

> 完成时间：2026-08-10；Category Storage v2 补充：2026-08-11
>
> 使用 Skill：`calendar-data-contracts`
>
> 范围：Category 数据模型、跨层 Contract、Flutter typed boundary、Kotlin Bridge 计划边界、Category JSON Storage v2 格式
>
> 实现状态：业务/API 协议、两端边界与 JSON Storage 格式已完成；C++ Category Repository/codec/bootstrap、真实 JNI 和磁盘写入仍为 `planned`

## 一、结论

本次已把 Flutter 分类页面的实际需求收敛为两条稳定的 Native 能力：

- `category.list`：加载全部活动分类；
- `category.create`：创建一个分类。

“选择分类”是 Flutter 页面之间返回一个 Category/Category ID 的本地交互，不是持久化操作，因此没有新增 `category.select` MethodChannel。Event、Anniversary 和后续检索只通过稳定 `category_id` 关联 Category，不使用名称、颜色或列表下标作为外键。

本次已完成 DATA_MODEL、JSON Schema、MethodChannel/Native Call 清单、Flutter typed DTO/Gateway/Adapter/Repository、Kotlin Contract/Handler/窄 Bridge，以及独立 `categories.json` 的严格 Storage v2 格式。由于 C++ Category Domain/Repository/codec/bootstrap 尚不存在，两条能力和 Category Store 仍标记 `implementation_status: planned`；`JniNativeCalendarCoreBridge` 明确返回 `FEATURE_NOT_IMPLEMENTED`，正式 App 继续注入可替换 Fake，没有伪造 Native 持久化成功。

需求文档中给出的 Flutter 结果路径 `docs/task/分类几面设计开发/分类界面设计开发结果-Flutter.md` 不存在。实际定位并读取的文件为：

- `docs/task/分类界面设计开发/分类界面设计开发结果-Flutter.md`

## 二、前端实际所需数据与操作

### 2.1 稳定数据

| 数据 | 用途 | 是否进入领域/Contract |
| --- | --- | --- |
| `id` | 分类身份、Event/Anniversary 关联、选择结果 | 是 |
| `name` | 列表和表单展示 | 是 |
| `description` | 可选分类说明 | 是 |
| `color` | 分类视觉标识；创建时必填 | 是 |
| `icon` | 可选稳定图标 key；当前创建页不提交 | 是 |
| `sortOrder` | 稳定列表顺序 | 是 |
| `createdAt/updatedAt/deletedAt` | 生命周期与软删除 | 是 |
| loading、empty、error、retry、submitting | 页面流程状态 | 否，仅 Flutter State |
| selected category、cancel result | 页面导航/选择状态 | 否，不持久化 |
| Fake owner 文案、“默认日程” | 开发期展示/fixture | 否，不冻结为系统默认语义 |

### 2.2 实际操作

- 加载活动分类，并支持 loading、empty、error、retry；
- 创建分类，包含名称、说明、颜色，以及当前未使用的 icon/显式顺序扩展位；
- 从分类页选择一条 Category，或返回/取消；
- 新建和编辑日程只提交被选择 Category 的 `id`；
- 创建失败时保留表单输入，连续提交只执行一次。

现有 `CategoryListController` 与 `CreateCategoryController` 已承担加载/创建 Application Service 职责。选择行为只返回 Category，不额外制造无业务价值的 UseCase 或跨层方法。

## 三、开发前缺口与最小修正

| 层 | 原缺口 | 本次结果 |
| --- | --- | --- |
| DATA_MODEL | Category 字段、软删除、排序、未分类语义和引用规则不完整 | 补齐稳定领域字段、约束、生命周期及 Event/Anniversary/SearchIndex 关系 |
| Category Schema | Create/Response 约束较松，缺少 list response | 收紧 Create/Response，新增 `CategoryListResponse` |
| MethodChannel | 无正式 Category 方法映射 | 新增 `category.list/create`，统一 `NativeResult<T>`，状态为 `planned` |
| Native Call | 无 Kotlin → C++ Category 映射 | 同步新增两条 planned internal call |
| Event/Search | Event 已有 nullable `category_id`，但 SearchIndex 缺稳定分类 ID 说明 | 保留 Event 兼容 reader，补 `SearchIndex.category_id`，结构化过滤继续使用 `category_ids` |
| Flutter | 只有页面/Fake/部分 Response DTO，没有完整 typed Native 链路 | 补 Request/List/Response DTO、mapper、Gateway、Adapter、Native repository |
| Fake | 旧开发 ID/时间可能不满足正式协议 | 使用 canonical lowercase UUIDv4、整秒 UTC、正式字段和稳定排序 |
| Kotlin | 无 Category validator、handler、窄 Bridge | 补齐严格边界并在 C++ 缺失时显式 unsupported |
| C++/Storage | 无 Category Domain/Workflow/Repository/Store | 已冻结独立 JSON Store 格式、原子写入和兼容规则；运行时代码仍保持 planned，不伪造落盘 |

本次发现的兼容冲突是：Native Contract v2 已允许 Event 的 `category_id` 为普通字符串，早期 Flutter 还曾提交非 UUID 值；若现在把所有 Event reader 收紧为 UUID，会破坏历史数据和既有调用方。最小修正方案是仅要求“新 Category writer”生成 UUIDv4，Event/Anniversary 的既有 `category_id` 继续作为 nullable opaque string 读取。

## 四、DATA_MODEL 修改与理由

`docs/DATA_MODEL.md` 已补充：

- Category 是独立配置实体，业务对象只保存稳定 `categoryId`；
- `id`、`name`、`description`、`color`、`icon`、`sortOrder`、三类时间字段的来源、必填性、校验与空值语义；
- `categoryId = null` 表示未分类，不要求存在名为“默认日程”的系统记录；
- 当前允许重名，身份只由 ID 决定；
- active list 的稳定顺序为 `sortOrder`（null 最后）→ `createdAt` → `id`；
- Category 软删除或引用无法解析时，Event/Anniversary 保留原始 ID，聚合展示的 Category 可以为空；
- Event 分类过滤使用 `categoryId/category_ids`，`categoryName` 只作为可重建搜索冗余；
- SearchIndex 增加稳定 `categoryId` 结构化字段；
- 用户归属、系统默认分类等未从现有资料证明的概念没有进入领域模型。

## 五、Contract 文件清单

### 5.1 新增

- `contracts/category/category_list_response.schema.json`

### 5.2 修改

- `contracts/category/create_category_request.schema.json`
- `contracts/category/category_response.schema.json`
- `contracts/search/search_index_response.schema.json`
- `contracts/method_channels.yaml`
- `contracts/native_calls.yaml`
- `contracts/README.md`
- `docs/DATA_MODEL.md`
- `contracts/storage/calendar_core_storage.yaml`

### 5.3 2026-08-11 Storage 补充新增

- `contracts/storage/category_store.schema.json`

### 5.4 检查后保持不变

- `contracts/error_codes.yaml`：已有 `CATEGORY_NAME_EMPTY`、`CATEGORY_NOT_FOUND` 和所需公共/Storage 错误，无需制造重复错误码；
- `contracts/enums.yaml`：Category 当前没有稳定传输枚举；
- Event create/update/detail/search Schema：已经使用 `category_id` / `category_ids`，为兼容已发布 reader 不收紧格式。

## 六、字段协议

### 6.1 CreateCategoryRequest

五个字段都必须在对象中出现；nullable 字段也不能省略，以避免不同语言默认值漂移。

| 字段 | 必填 | 默认/空值 | 校验 | 生成/维护层 |
| --- | --- | --- | --- | --- |
| `name` | 是 | 无默认 | trim 后非空，最多 40 Unicode 字符 | Flutter 收集；C++ 最终规范化/校验 |
| `description` | 是（可为 null） | 空白规范化为 null | 非空时最多 200 字符 | Flutter 收集；C++ 维护 |
| `color` | 是 | 无默认 | 输入 `#RRGGBB`，大小写均可；writer 规范化大写 | Flutter 收集；C++ 维护 |
| `icon` | 是（可为 null） | 当前页面传 null | 非空时最多 64 字符 | Flutter 收集；C++ 维护 |
| `sort_order` | 是（可为 null） | null 表示由 workflow 稳定追加 | 非负整数 | C++ workflow 最终决定 |

Category `id`、`created_at`、`updated_at` 不由 Flutter/Kotlin 提交，未来由 C++ writer 生成。

### 6.2 CategoryResponse

所有九个字段都必须出现：

| 领域字段 | Wire 字段 | 规则 |
| --- | --- | --- |
| `id` | `id` | canonical lowercase UUIDv4；仅约束新的 Category writer |
| `name` | `name` | 非空，最多 40 字符 |
| `description` | `description` | null 或 1–200 字符 |
| `color` | `color` | null 或 canonical uppercase `#RRGGBB`；create response 必须非空 |
| `icon` | `icon` | null 或 1–64 字符 |
| `sortOrder` | `sort_order` | null 或非负整数 |
| `createdAt` | `created_at` | 整秒 ISO 8601 UTC |
| `updatedAt` | `updated_at` | 整秒 ISO 8601 UTC，不能早于 created_at |
| `deletedAt` | `deleted_at` | null 或整秒 ISO 8601 UTC |

`CategoryListResponse.items` 只允许活动记录（`deleted_at = null`），禁止重复 ID，并要求已经按 Contract 顺序返回。

## 七、MethodChannel 与 Native Call

| 方法 | Request Schema | Response data Schema | 主要错误码 | Flutter 调用方 | Android 接收方 | 后续 Native 实现 |
| --- | --- | --- | --- | --- | --- | --- |
| `category.list` | `common/native_empty_request.schema.json`（显式 `{}`） | `category/category_list_response.schema.json` | 当前：`CONTRACT_VALIDATION_FAILED`、`FEATURE_NOT_IMPLEMENTED`；集成后还可能返回 `STORAGE_NOT_INITIALIZED`、`STORAGE_IO_ERROR`、`STORAGE_DATA_CORRUPTED`、`NATIVE_INTERNAL_ERROR` | `MethodChannelCategoryAdapter.listCategories` | `CategoryMethodHandler` | `NativeCategoryBridge.listCategories` → `JniNativeCalendarCoreBridge.listCategories` → 未来 C++ Category query API |
| `category.create` | `category/create_category_request.schema.json` | `category/category_response.schema.json` | 当前：`CATEGORY_NAME_EMPTY`、`CONTRACT_VALIDATION_FAILED`、`FEATURE_NOT_IMPLEMENTED`；集成后还可能返回上述 Storage/Internal 错误 | `MethodChannelCategoryAdapter.createCategory` | `CategoryMethodHandler` | `NativeCategoryBridge.createCategory` → `JniNativeCalendarCoreBridge.createCategory` → 未来 C++ Category workflow API |

两条方法在 `method_channels.yaml` 与 `native_calls.yaml` 中一一对应，均使用 `common/native_result.schema.json` 外壳，`implementation: cpp`、`implementation_status: planned`。

`CATEGORY_NOT_FOUND` 保留给未来 get/update/delete 等按 ID 操作；当前 list/create 不应凭空返回它。

## 八、Flutter 设计与依赖方向

```text
Category UI
  → CategoryListController / CreateCategoryController
  → CategoryRepository
      → FakeCategoryRepository（当前生产 composition）
      → NativeCategoryRepository（未来替换）
          → CategoryNativeGateway
          → MethodChannelCategoryAdapter
          → excellent_calendar/native
```

新增/补齐的 typed boundary：

- `CreateCategoryRequestDto`：负责明确字段和请求侧校验/序列化；
- `CategoryResponseDto`：严格拒绝缺字段、未知字段、非法 UUID/颜色/时间；
- `CategoryListResponseDto`：解析 typed items、拒绝重复 ID 和非法顺序；
- `CategoryMapper`：只在 MethodChannel 边界把动态 data 转为 DTO；
- `CategoryNativeGateway`：只暴露 list/create typed invocation；
- `MethodChannelCategoryAdapter`：唯一 MethodChannel 调用点；
- `NativeCategoryRepository`：把 DTO 映射成 Flutter Category domain model，并把稳定 Native error 映射成 Application failure；
- `FakeCategoryRepository`：继续可替换使用，但 fixture、ID、颜色、时间与排序严格符合正式 Contract。

UI 和 Controller 不拼装跨层 Map，也不引用 MethodChannel。动态 `Map<String, dynamic>` 仅存在于 DTO/Adapter 边界。

## 九、Android 设计与依赖方向

```text
NativeMethodChannelHandler registry
  → CategoryMethodHandler
  → CategoryRequestContracts / CategoryResponseContracts
  → NativeCallExecutor
  → NativeCategoryBridge
  → NativeCalendarCoreBridge（聚合 composition）
  → JniNativeCalendarCoreBridge
  → 未来 JNI export / C++ Category API
```

具体结果：

- Kotlin request validator 要求精确字段集合，拒绝未知/缺失字段；
- response validator 校验 UUIDv4、文本、颜色、整数、整秒 UTC、更新时间、active list、重复 ID 与稳定顺序；
- `CategoryMethodHandler` 只做解析、校验、转发和返回包装，不包含默认分类、唯一性或排序分配等领域规则；
- `NativeCategoryBridge` 是 Category 专属窄接口；
- `NativeCalendarCoreBridge` 通过继承窄接口进行 composition 扩展；
- `JniNativeCalendarCoreBridge` 已保留稳定方法签名，但 C++ 未实现期间不加载 library，返回带 `FEATURE_NOT_IMPLEMENTED` 的 `NativeResult`；
- Kotlin 测试覆盖正确路由、请求边界拒绝、列表响应拒绝和 planned stub 行为。

## 十、真实实现与计划能力

### 10.1 已真实实现

- DATA_MODEL 与 Category/Search 关系设计；
- Category create/response/list JSON Schema；
- MethodChannel/Native Call planned 映射；
- Flutter typed DTO/Gateway/Adapter/Native repository；
- 当前 UI 使用的 CategoryRepository、Application controllers、选择/创建流程；
- Contract-conformant Fake（UUIDv4、整秒 UTC、字段/顺序/错误）；
- Kotlin Contract validator、Handler、窄 Bridge、聚合扩展与显式 unsupported stub；
- Category JSON Storage v2 的逻辑文件、严格根包络、记录 Schema、原子写入、引用完整性和可加性兼容设计；
- Dart/Kotlin 单元测试、全量静态检查与 Debug 构建。

### 10.2 仅预留或尚未实现

- C++ Category Domain、Application Workflow/Query Service；
- Category Repository、JSON codec、bootstrap 和真实文件写入；
- SQLite Store（当前阶段明确不做）以及未来从 JSON 切换时所需 migration；
- 真实 JNI external/export 和 Native category persistence；
- 正式 App composition 从 Fake 切换到 `NativeCategoryRepository`；
- Category update/delete/restore/reorder；
- 真机 Category 创建、重启读取、软删除和 Event 聚合端到端测试；
- 用户归属、同步、系统默认分类和名称唯一性。

## 十一、一致性与兼容性检查

### 11.1 字段一致性

| 语义 | DATA_MODEL | JSON Wire | Dart | Kotlin |
| --- | --- | --- | --- | --- |
| 稳定身份 | `Category.id` | `id` | `String id` | UUIDv4 validator |
| 说明 | `description` | `description` | `String?` | nullable text validator |
| 颜色 | `color` | `color` | `String?` response / required request | input/canonical color validator |
| 图标 | `icon` | `icon` | `String?` | nullable text validator |
| 顺序 | `sortOrder` | `sort_order` | `int?` | nullable non-negative integer |
| 生命周期 | camelCase timestamps | snake_case timestamps | UTC `DateTime` | whole-second UTC validator |
| Event 关联 | `categoryId` | `category_id` | selected Category ID | opaque nullable string in Event contract |
| 搜索过滤 | `categoryId` | request `category_ids` / index `category_id` | ID filter | ID filter boundary |

检查结论：DATA_MODEL 使用本层命名，Wire 全部 snake_case；Request、Response、Domain Model、UI State 相互分离；Flutter 与 Kotlin 都拒绝未知字段和非法外壳，没有以默认值掩盖 Contract 错误。

### 11.2 兼容与迁移

- 本次不修改 Event/Anniversary 既有 reader 的 `category_id` 类型，不需要迁移历史非 UUID 引用；
- 新 Category writer 才强制 UUIDv4，随后自然写入同一 opaque reference 字段；
- Category response 的 `color` 保持 nullable reader 兼容，create response 则强制非空；
- Category 现在已有 planned 的正式 Store 格式，但仓库仍没有实际 Category 文件或正式历史数据；因此不存在 v1/Fake 数据 migration；
- `categories.json` 作为独立文件加入 Storage v2，不改变既有 Store 根包络、codec 或 journal；旧 v2 runtime 忽略并保留该未知文件，故不提升 `storage_format_version`；
- 两条新方法仍为 planned、未对外集成，不提升现有 Native Contract v2 版本；
- 删除/缺失分类不级联清空业务对象引用，避免静默数据丢失。

## 十二、尚待用户/架构决策

这些问题不阻塞本次稳定 list/create 边界，但会影响后续 C++/Storage/同步架构，实施前必须确认：

1. Category 是设备级、本地资料级还是具体云端用户级实体；
2. “默认日程”是否为系统记录，是否不可删除/重命名，未分类是否应映射到它；
3. 分类名称是否唯一，唯一作用域是什么，大小写与 Unicode 规范化规则是什么；
4. update/delete/restore/reorder 的并发、事务和错误码；
5. 删除分类后 Event/Anniversary 的展示、筛选、恢复与同步冲突策略。

在这些决策完成前，本次没有新增 `user_id`、`is_default`、唯一索引或默认分类初始化逻辑。

## 十三、2026-08-10 边界实现验证结果（历史记录）

本节只记录 2026-08-10 当时的仓库状态；Category C++/JNI/Storage 随后已经出现真实实现，当前结论见第十五节。

- Dart 格式化：本次 Category 相关 Dart 文件通过；
- Contract JSON：130 个 Schema 均可解析，均声明 Draft 2020-12，`$id` 唯一；65 个本地 `$ref` 及 JSON Pointer 闭合；Category required 字段、Schema 映射和 SearchIndex 断言通过；
- Contract YAML：7 个文件使用禁重键设置解析通过；`category.list/create` 在 MethodChannel/Native Call 中各出现一次且保持 planned；
- Flutter 定向测试：30/30 通过；
- `flutter analyze`：无问题；
- Flutter 全量测试：194/194 通过；
- Kotlin Category 定向测试：4/4 通过；
- Android JVM 全量测试：84 项，0 failure、0 error、1 项既有 skipped；
- Android Debug APK：构建成功，产物为 `flutter_client/build/app/outputs/flutter-apk/app-debug.apk`；
- C++ 基线：重新配置后执行 `excellent_calendar_check`，5/5 通过；本轮没有修改 C++；
- `git diff --check`：通过；
- 当时未验证：真实 Category C++/JSON Storage/JNI/真机持久化链路；该结论不再代表 2026-08-11 审查时的代码存在状态。

## 十四、2026-08-11 Category Storage v2 设计补充

### 14.1 最终存储决策

| 项目 | 决策 |
| --- | --- |
| 逻辑 Store | `categories` |
| 文件 | `categories.json` |
| 所在目录 | Android 正式 Calendar Core v2 目录 `files/local_storage/calendar_core_storage_json` |
| 根集合 | `categories` |
| Storage 版本 | `2`，作为不改动既有 Store 的可加性独立文件 |
| 严格 Schema | `contracts/storage/category_store.schema.json` |
| 当前实现状态 | `implemented_unintegrated + blocked`；C++/JNI/Store 代码已存在，但尚未通过统一发布门禁 |
| 文件事务边界 | 一个完整、已校验的 Category 快照原子替换 |
| Journal | 当前不需要；任何未来跨 Store 操作必须单独设计 |

选择严格 JSON 完整快照而不是现在引入 SQLite，原因是 Category 是低基数配置数据，当前只有 list/create，完整加载与校验成本很低，并且可以复用 Calendar Core 已验证的目录锁和原子替换能力。Repository 仍是唯一持久化边界；以后账号分区同步、高频写入或实际数据规模证明完整快照不合适时，再通过显式 migration 切换 SQLite，不让 Flutter/Kotlin DTO 感知底层变化。

空 Store 的精确内容是：

```json
{
  "storage_version": 2,
  "categories": []
}
```

根对象和每条记录都拒绝未知字段。`CategoryStorageRecord` 精确保存：

```text
id, name, description, color, icon, sort_order,
created_at, updated_at, deleted_at
```

Request、Response、领域对象和 Storage record 仍是不同模型；字段事实一致不代表可以直接复用同一个类型。

### 14.2 规范化与排序

- Category 记录 ID 只接受 C++ writer 生成的 canonical lowercase UUIDv4；
- `name/description/icon` 保存 trim 后的规范文本，空白 optional text 保存为 `null`；
- `color` 在正式本地 Store 中必须是 uppercase `#RRGGBB`，不得为 null；
- `sort_order` 在正式本地 Store 中必须位于 `0..9007199254740991`；create request 的 null 会在持久化前物化，不会原样写盘；
- nullable 字段也必须显式出现；缺字段不是旧值或默认值，而是 `STORAGE_DATA_CORRUPTED`；
- 文件数组按 `id` 升序保存，保证同一状态有稳定序列化；
- 本地 `category.list` 按 `sort_order -> created_at -> id` 排序，不依赖磁盘数组下标；Response 的 null-last 规则继续服务非 Store/早期草案兼容 reader；
- create 请求的 `sort_order=null` 时，C++ 在同一目录写锁内把活动记录的最大顺序值加一；没有活动记录时从 `0` 开始。最大值已为 `9007199254740991` 时返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。显式重复值允许存在，并由次级排序键消歧。

### 14.3 写入和失败语义

C++ writer 的正式 Contract 顺序如下：

1. 获取现有 Calendar Core 目录级递归锁和单 writer lease；
2. 加载并完整校验当前 `categories.json`；
3. 在内存执行 Category domain command；
4. 校验完整新快照、UUID 唯一性、字段规范和时间不变量；
5. 按 ID 排序后写同目录临时文件，flush/fsync；
6. 原子替换 `categories.json` 并同步目录；成功同步目录才到达 Contract 提交点。

任一校验或 I/O 失败都以旧 `categories.json` 为权威，禁止部分写入、默认值修复或清空重建。create/reorder/未来软删除都只改一个文件，因此无需把 Category 塞入 Event/Reminder 六 Store journal 或 Anniversary 两 Store journal。

### 14.4 引用、初始化和迁移

- Event、Habit、Anniversary、SearchIndex 的 `category_id` 对 Category 是弱引用；加载 Category Store 不扫描或改写其他 Store。
- 既有业务记录中的非 UUID Category ID 继续作为 opaque string 读取。它找不到活动 Category 时，原始 ID 保留，聚合投影可返回 `category=null`。
- 新 v2 目录创建精确空根；合法旧 v2 目录在 Category Store 激活后也只补空根。
- 已存在的合法 `categories.json` 原样加载；未知版本、错误根、非法字段、重复 ID 或损坏 JSON 显式失败并保留原文件。
- 不存在正式 Category v1 Store，不读取旧 `test_storage_json`，不导入 Flutter Fake，不自动写入“默认日程”或 owner fixture。
- 旧 v2 runtime 会忽略这个独立未知文件并保持不动；回到支持 Category 的 runtime 后数据仍可读取。

### 14.5 尚未关闭的发布门禁

C++ Domain、Workflow/Query、Repository、JSON codec、bootstrap 文件集、Boundary/JNI export 和真实磁盘读写代码已经存在；当前缺口不再是“尚未实现”，而是 Event detail Category 聚合、Kotlin Event Category 字段校验、post-replace 失败回滚、安全整数和规范化的所有层同步、Flutter 生产 composition，以及真机端到端 smoke。全部通过后才能同时把 Category Store 与 `category.list/create` 从 `implemented_unintegrated + blocked` 切换为 `integrated + active`。

本设计没有冻结用户归属、系统默认分类、名称唯一性、update/delete/restore/reorder API 或同步冲突规则；这些问题仍需在相应能力开发前由产品和架构共同确认。

### 14.6 2026-08-11 Storage 设计轮验证（历史记录）

- 131 个 Contract JSON Schema 全部可解析，均声明 Draft 2020-12，131 个 `$id` 唯一；73 个本地 `$ref` 与 JSON Pointer 全部闭合；
- Category Store 的精确根字段、九字段严格记录、UUIDv4、非空 canonical `color/sort_order`、空根和样例结构断言通过；
- 7 个 YAML 使用禁重键设置解析通过；当时 Category 逻辑文件、v2 根包络、per-store `planned`、弱引用、无 v1/Fake migration、单文件无 journal，以及 MethodChannel/Native Call 的 planned 断言通过；该状态已被第十五节的审查整改替代；
- 按项目规定重新配置 C++ 并执行 `excellent_calendar_check`，5/5 通过；
- `git diff --check` 通过，仅输出仓库既有的 LF→CRLF 提示，没有 whitespace error；
- 当时未验证：真实 Category C++ Repository/codec/bootstrap/JNI/磁盘写入和真机重启读取；本轮也没有重复执行 Flutter/Android 构建。

## 十五、2026-08-11 分类功能审查后的 Contracts 整改

### 15.1 逐项真实性判断

| 编号 | 判断 | Contracts 整改结论 | 仍需其他层处理 |
| --- | --- | --- | --- |
| CAT-001 | 属实 | 原资料把已经存在的 Native/Store 代码写成 `planned/future/未实现`，同时又不能在发布门禁未通过时误改为 `integrated`。现统一为 `implementation_status: implemented_unintegrated`、`release_status: blocked`，并正式定义状态含义和激活条件。 | C++ CAT-004/CAT-006、Kotlin CAT-005、Flutter 生产切换及设备 smoke 完成后，才能统一切为 `integrated + active`；当前 P1 不能由 Contracts 单层宣称完全关闭。 |
| CAT-002 | 属实 | 无 Contract 文件需要修改。 | Flutter 生产 composition 仍注入 Fake。 |
| CAT-003 | 属实 | 既有 Contract 已明确未分类是 `category_id=null`、列表顺序不代表默认身份，因此不是 Contract 缺口。 | Flutter 必须移除自动选择第一项，并区分取消、选择和清空。 |
| CAT-004 | 属实 | `event_detail_response.schema.json` 原描述只覆盖“无分类”，未完整冻结活动、悬空和软删除三态。现已增加三态不变量、活动 Category 限制、三个正例和七组正反 oracle；原始 Event ID 保留。 | C++ Application aggregate 仍需按该规则返回 Category，Flutter 仍需展示三态。 |
| CAT-005 | 属实 | Event/Category Schema 原本已规定正确类型，本轮进一步明确 detail 聚合语义；不存在通过放宽 Schema 修复 Kotlin 的理由。 | Kotlin Event validator 必须补 `category_id/category_ids/category` 校验。 |
| CAT-006 | 属实 | 现有 Storage Contract 的“任何失败旧快照继续权威”是合理事务保证，不应为现有实现缺陷而弱化。现仅明确成功目录同步才是提交点。 | C++ 原子文件 Store 必须补 post-replace 失败回滚和四阶段故障注入。 |
| CAT-007 | 属实 | 三态读取语义已在 Event detail Contract 与 DATA_MODEL 冻结。 | Flutter detail state/page 仍需保留并展示 Category。 |
| CAT-008 | 属实 | Request、Response、Store 三处统一最大值 `9007199254740991`；`9007199254740992` 为首个非法值。请求超限=`CONTRACT_VALIDATION_FAILED`，磁盘超限=`STORAGE_DATA_CORRUPTED`，自动追加耗尽=`CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。 | C++/Kotlin/Dart 必须同步上界；Flutter comparator 必须显式处理 null，不能使用整数哨兵。 |
| CAT-009 | 属实 | 统一 C++ Application/Domain 为唯一规范化 owner；Schema-valid 的空白文本和小写颜色必须由 Flutter/Kotlin 原样转发，C++ 返回 trim/null/uppercase 的规范结果。已删除 Flutter 特例和 future writer 文案，并补 raw wire 正例。 | Flutter Native Repository 仍需移除 trim、blank-to-null 和 uppercase。 |
| CAT-010 | 属实 | 不涉及 Contract 形状或错误语义变更。 | Kotlin `NativeCategoryBridge` 必须删除默认 throwing stub。 |

### 15.2 本轮 Contract 影响矩阵

| 边界 | 本轮变化 | 兼容/迁移结论 |
| --- | --- | --- |
| MethodChannel / JNI 清单 | Category 状态从含义错误的 `planned` 改为 `implemented_unintegrated + blocked` | 不改变方法名、请求、响应或 Native Contract v2 版本；这不是激活。 |
| Create Request | 明确 C++ 单点规范化；冻结 `sort_order` 安全整数上界和边界 oracle | Category 尚未正式激活，属于激活前收紧；调用方必须同步后才能放行。 |
| Category Response | `sort_order` 同步安全整数上界 | 超限成功响应是 Contract 违规，不允许以精度损失继续传递。 |
| Category Store | 状态改为 implemented/unintegrated；冻结数值范围、错误映射和目录同步提交点 | Storage 版本仍为 2，不生成伪 migration；实验性超限记录按 `STORAGE_DATA_CORRUPTED` 处理，禁止截断或默认修复。 |
| Event Detail | 冻结未分类、活动命中、悬空/软删除三态 | 不改变字段形状；补强既有弱引用语义。跨对象 ID 相等由显式 Contract invariant 与各层测试执行。 |
| Native Error | 新增 `CATEGORY_SORT_ORDER_EXHAUSTED` | Category 未激活阶段可同步加入；所有消费者完成映射后才可激活。 |

### 15.3 当前结论

Contracts 主责的 CAT-008、CAT-009 和 CAT-004 协作项已经完成协议冻结；CAT-001 已修正“代码存在状态”的错误资料，并把最终发布状态明确保持为 blocked。由于 CAT-004～CAT-006 及 Flutter 生产链路仍未全部关闭，本轮没有把 Category 标记为 `integrated`，也不把底层调用成功等同于产品可发布。

### 15.4 验证结果

- 131 个 JSON Schema 均可解析并声明 Draft 2020-12，131 个 `$id` 唯一，73 个本地 `$ref` 与 JSON Pointer 闭合；
- 7 个 Contract YAML 使用禁重键加载器解析通过；MethodChannel、Native Call、逻辑 Store 和 Store Schema 的 Category 状态均为 `implemented_unintegrated + blocked`；
- 专项 oracle 通过：`9007199254740991` 为最大合法值、`9007199254740992` 为首个非法值；带前后空白文本和小写颜色的 create raw payload 保持 Schema-valid；Event detail 的未分类、活动命中、悬空三个正例和四个合法/三个非法语义 oracle 完整；
- 按项目规定重新配置 C++ 后执行 `excellent_calendar_check`，6/6 通过；这只能证明当前既有测试基线未回归，不代表 C++ 已满足本轮新增的 max/max+1、Event aggregate 或 post-replace failure oracle；
- `git diff --check` 通过，仅有仓库既有 LF→CRLF 提示；
- 未执行 Flutter/Kotlin/Android 构建或设备 smoke，因为本轮没有越界修改这些实现层。CAT-002～CAT-010 的对应实现整改仍应由各层开发者完成。
