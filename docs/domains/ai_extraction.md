## AIExtraction：AI 解析结果

AI 解析结果保存从自然语言、图片或分享文本中提取出的候选结构化数据。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | AI 解析结果 ID |
| `inputType` | `string` | 是 | 输入类型，例如 `text`、`image`、`share` |
| `rawInput` | `string` | 是 | 原始输入内容或引用 |
| `extractedType` | `string` | 是 | 解析出的对象类型，例如 `event`、`reminder` |
| `extractedData` | `object` | 是 | 结构化解析结果 |
| `confidence` | `number` | 否 | 置信度，建议范围 `0-1` |
| `candidateEventId` | `string` | 否 | 生成的候选日程 ID |
| `status` | `string` | 是 | 状态，例如 `pending_review`、`accepted`、`rejected` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

