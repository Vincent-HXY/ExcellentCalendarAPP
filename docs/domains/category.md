## Category：分类

分类用于组织日程、习惯、纪念日等对象。Category 是独立配置实体；业务对象只保存稳定的
`categoryId`，分类名称、颜色和列表下标都不能充当关联键。

当前只冻结本地分类本身，不冻结账号归属或系统预设语义。Flutter Fake 中的“默认日程”和
用户名分组仅是开发期数据/展示信息，不产生 `userId`、`isDefault`、`ownerName` 等领域字段。
未分类由业务对象的 `categoryId = null` 表达，不要求存在一条名为“默认日程”的 Category。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 分类 ID；新的正式 writer 由 C++ 生成 UUIDv4 |
| `name` | `string` | 是 | 去除首尾空白后非空，最多 40 个 Unicode 字符 |
| `description` | `string` | 否 | 分类备注；空白规范化为 `null`，最多 200 个 Unicode 字符 |
| `color` | `string` | 否 | 规范化的 `#RRGGBB` 大写十六进制颜色；新建分类时必填，响应保留可空以兼容旧草案 |
| `icon` | `string` | 否 | 稳定图标标识；当前 Flutter 创建页不提交 |
| `sortOrder` | `integer` | 否 | `0..9007199254740991`；`null` 表示没有显式顺序，范围保证 JSON Number 在 Dart/Kotlin/C++ 间精确往返 |
| `createdAt` | `datetime` | 是 | C++ Clock 生成的创建时间 |
| `updatedAt` | `datetime` | 是 | C++ Clock 生成的最近更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间；活动分类为 `null` |

关系与生命周期不变量：

- Category 名称不是身份，也尚未冻结账号范围内的唯一性；当前允许重名，调用方必须使用 `id` 区分。
- `category.list` 只返回 `deletedAt = null` 的活动分类，并按 `sortOrder`（`null` 最后）、
  `createdAt`、`id` 升序稳定排序。
- Category 创建的领域规范化只在 C++ Application/Domain 执行：`name/description/icon` trim，空白
  optional text 变 `null`，`color` 转大写。Flutter/Kotlin 只能校验 wire 结构并原样转发 Schema-valid 值，
  不得提前 trim、blank-to-null 或 uppercase。
- 创建请求未提供显式 `sortOrder` 时，C++ Category workflow 负责选择稳定的追加顺序；
  Flutter/Kotlin 不生成 ID、时间戳或持久化排序值。活动最大值已经是 `9007199254740991` 时返回
  `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。
- Category 软删除不得把 Event、Habit 或 Anniversary 的 `categoryId` 改成名称、颜色或其他替代值。
  Event detail 的 Category 聚合固定为三态：`event.categoryId = null` 时 `category = null`；非空 ID 命中
  活动 Category 时必须返回同 ID 的 Category；非空 ID 悬空或只命中软删除 Category 时返回
  `category = null`，同时原始 `event.categoryId` 必须保留。
- 按分类过滤 Event 必须使用 `categoryId/category_ids`。`categoryName` 只允许作为 SearchIndex 的
  可重建冗余文本，不是结构化过滤或引用完整性的真相源。
- Category 归属于设备、本地资料还是具体云端用户，以及系统默认分类的初始化/隐藏/复制规则，
  仍待账号与同步架构冻结后另行设计；本轮不得据此新增字段或预设写入。

### Category Storage v2 映射（已实现，尚未通过发布集成门禁）

Category 使用 Calendar Core JSON v2 目录中的独立逻辑 Store：

```json
{
  "storage_version": 2,
  "categories": []
}
```

- 文件名固定为 `categories.json`，根对象只允许 `storage_version` 与 `categories`；严格格式由
  `contracts/storage/category_store.schema.json` 定义。
- `CategoryStorageRecord` 与 Create Request、Response DTO、领域对象分离，但使用同一组稳定事实字段：
  `id/name/description/color/icon/sort_order/created_at/updated_at/deleted_at`。所有 nullable 字段也必须
  显式保存，禁止依赖语言默认值补字段。
- 正式本地 Store 比兼容性 Response reader 更严格：`color` 与 `sort_order` 在磁盘上必须非空；
  request 的空顺序由 C++ 在持久化前物化。Response 保留这两项可空只用于既有草案/非 Store reader 兼容，
  不能据此向新 `categories.json` 写入 null。
- 存储快照按 `id` 升序序列化，使同一状态产生稳定文件；本地 Store 投影按
  `sortOrder -> createdAt -> id` 排序，兼容性 Response comparator 仍把非 Store 来源的 null 放在最后；
  任何情况下都不能把数组下标当作排序事实。
- Request、Response 与 Store 的 `sort_order` 都限制为 `0..9007199254740991`。请求直接超限返回
  `CONTRACT_VALIDATION_FAILED`，磁盘记录超限返回 `STORAGE_DATA_CORRUPTED`；`category.create.sort_order = null`
  时 C++ workflow 在目录级写锁内按活动记录的最大 `sort_order + 1` 生成持久化值，没有活动记录时从
  `0` 开始，最大值已达上界时返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。显式重复顺序值合法，
  由列表次级键稳定消歧。
- 当前 create 只修改 `categories.json`，完整快照校验后使用同目录临时文件、flush/fsync、原子替换和目录同步，
  成功完成目录同步才是 Contract 提交点；任何阶段返回失败都必须让旧快照继续权威。单文件原子替换就是事务
  边界，不需要扩展现有 Event/Reminder 或 Anniversary journal。
- 未来若一个 Category workflow 必须同时修改其他逻辑 Store，必须先定义独立的可恢复 journal；不得静默扩大
  两个既有 journal 的精确 Store 集合。
- 已有 Event/Habit/Anniversary 的 `categoryId` 是弱引用：Category Store 加载不扫描、不清空也不规范化其他
  Store 的引用。缺失或软删除 Category 时保留原 ID，聚合投影可以返回空 Category。
- 这是 Storage v2 的可加性独立文件，不改变现有 Store 的根包络、记录 codec 或 journal。合法旧 v2 目录在
  Category Storage 正式激活后只创建空根；若已有 `categories.json`，必须完整校验并原样保留，损坏或未知版本
  显式失败，禁止重置。
- 没有正式 Category v1 Store，也禁止把 Flutter Fake、“默认日程”fixture 或 owner 文案迁入正式存储。
- 当前选择严格 JSON 完整快照，是因为 Category 属于低基数配置数据，公开操作只有 list/create，且可以直接复用
  现有目录锁、原子替换和损坏检测。Repository 边界保持不变；以后出现账号分区同步、高频写入或明显规模压力时，
  再用显式 migration 切换 SQLite，而不是让 UI/DTO 依赖文件格式。

Category 的 C++ Domain/Repository/JSON codec、bootstrap、JNI export 与真实磁盘读写代码已经存在，故 Store
和两条调用统一标记为 `implementation_status: implemented_unintegrated`；但 `release_status: blocked` 仍表示
不能宣称产品闭环已完成。解除条件是 Event detail 聚合、Kotlin Event Category 校验、原子写 post-replace
失败语义、跨层安全整数/规范化一致性、Flutter 生产 composition 与设备 smoke 全部通过。

