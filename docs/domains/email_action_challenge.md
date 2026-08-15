## EmailActionChallenge：邮箱动作挑战

同一个 Challenge 可以同时签发 6 位验证码和邮件链接 Token；两者只保存哈希，任一凭证验证成功都会消费整个 Challenge 并使另一种凭证失效。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | Challenge UUID |
| `userId` | `string` | 是 | 关联用户 |
| `purpose` | `EmailActionPurpose` | 是 | 注册验证、改邮箱或密码重置 |
| `targetEmail` | `string` | 是 | 本次动作接收邮件的地址 |
| `codeHash` | `string` | 否 | 6 位验证码哈希 |
| `linkTokenHash` | `string` | 否 | 深度链接不透明 Token 哈希 |
| `failedAttemptCount` | `number` | 是 | 验证失败次数，初始为 0 |
| `maxAttempts` | `number` | 是 | 固定为 5 |
| `expiresAt` | `datetime` | 是 | 注册/改邮箱 10 分钟，密码重置 15 分钟 |
| `resendAvailableAt` | `datetime` | 是 | 创建后 60 秒 |
| `consumedAt` | `datetime` | 否 | 验证成功时间 |
| `invalidatedAt` | `datetime` | 否 | 重发、取消或安全事件导致的失效时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |

## 枚举定义

### VerificationCredentialType

| 值 | 说明 |
| --- | --- |
| `code` | 用户手动输入的 6 位数字验证码 |
| `link_token` | 邮件深度链接携带的不透明验证 Token |

### EmailActionPurpose

| 值 | 说明 |
| --- | --- |
| `registration_verification` | 注册邮箱验证 |
| `email_change` | 新登录邮箱验证 |
| `password_reset` | 忘记密码后的重置验证 |

