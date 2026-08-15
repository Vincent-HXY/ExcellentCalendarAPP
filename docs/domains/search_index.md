## SearchIndex：搜索索引

搜索索引用于加速日程、习惯、纪念日等内容检索。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 索引记录 ID |
| `targetType` | `string` | 是 | 被索引对象类型 |
| `targetId` | `string` | 是 | 被索引对象 ID |
| `titleText` | `string` | 否 | 标题索引文本 |
| `bodyText` | `string` | 否 | 正文索引文本 |
| `keywords` | `string[]` | 否 | 关键词 |
| `categoryId` | `string` | 否 | 从目标对象派生的稳定分类 ID，用于结构化分类过滤 |
| `categoryName` | `string` | 否 | 可重建的分类名称冗余文本，只用于展示或全文检索 |
| `occurAt` | `datetime` | 否 | 发生时间，用于时间排序 |
| `updatedAt` | `datetime` | 是 | 索引更新时间 |

`categoryId/categoryName` 都是索引投影而非新的关系真相源。Category 更名、软删除或索引损坏时，
SearchIndex 必须从目标对象的 `categoryId` 与当前 Category 记录重建；分类筛选不能依赖旧名称。

