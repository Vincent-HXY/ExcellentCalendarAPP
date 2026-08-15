## DatedMessage：投送消息

投送消息用于在指定日期或时间向用户展示内容，例如每日提醒、节日提示或运营消息。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 消息 ID |
| `title` | `string` | 是 | 消息标题 |
| `content` | `string` | 是 | 消息内容 |
| `deliverAt` | `datetime` | 是 | 投送时间 |
| `expireAt` | `datetime` | 否 | 过期时间 |
| `channel` | `string` | 是 | 投送渠道，例如 `in_app`、`notification`、`wechat` |
| `targetUserId` | `string` | 否 | 指定用户 ID；为空可表示全量或规则投放 |
| `targetRule` | `object` | 否 | 投放规则 |
| `status` | `string` | 是 | 状态，例如 `draft`、`scheduled`、`sent`、`cancelled` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

