## UserAvatarAsset：头像资产

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 头像资产 UUID |
| `userId` | `string` | 是 | 资产所有者 |
| `storageKey` | `string` | 是 | 对象存储内部键，不进入公开响应 |
| `mimeType` | `string` | 是 | `image/jpeg`、`image/png` 或 `image/webp` |
| `sizeBytes` | `number` | 是 | 原始上传最大 5 MiB |
| `width` | `number` | 是 | 服务端处理后图片宽度 |
| `height` | `number` | 是 | 服务端处理后图片高度，必须等于宽度 |
| `etag` | `string` | 是 | 客户端头像缓存失效标识 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `deletedAt` | `datetime` | 否 | 被替换或删除时间 |

公开响应只暴露 `assetId`、可访问 URL、缩略图 URL、`etag` 和 `updatedAt`。删除头像后 `UserProfile.avatarAssetId = null`，不保存默认头像 URL。

