## UserProfile：个人资料

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 与 `UserAccount` 一对一 |
| `username` | `string` | 是 | 公开用户名，匹配 `[a-z0-9_]{3,24}` |
| `normalizedUsername` | `string` | 是 | 用于唯一索引的规范化用户名，不进入公开响应 |
| `displayName` | `string` | 是 | 1 至 40 个 Unicode 字符的昵称 |
| `avatarAssetId` | `string` | 否 | 当前头像资产 ID；为空表示客户端使用默认头像 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

`normalizedUsername` 在未删除用户中大小写不敏感唯一。资料更新采用最后写入胜出；客户端提交成功后必须使用服务端返回的完整当前用户资料更新正式状态。

