## PasswordCredential：密码凭证

`PasswordCredential` 是 Backend-only 安全模型，只保存不可逆密码哈希。它不得进入 API 响应、Flutter 缓存、Android 安全记录或日志。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联 `UserAccount.id` |
| `passwordHash` | `string` | 是 | 包含算法、盐和参数的 Argon2id PHC 编码字符串 |
| `algorithm` | `string` | 是 | 当前固定为 `argon2id`，用于算法迁移审计 |
| `passwordChangedAt` | `datetime` | 是 | 最近一次设置或修改密码的时间 |

密码规则为 8 至 128 个 Unicode 字符，不强制字符组合；服务端还必须拒绝常见或已泄露密码。注册、修改密码和密码重置使用同一规则。

