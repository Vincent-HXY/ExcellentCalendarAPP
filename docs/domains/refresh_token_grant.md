## RefreshTokenGrant：Refresh Token 轮换记录

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | Grant UUID |
| `sessionId` | `string` | 是 | 关联 `UserSession.id` |
| `tokenHash` | `string` | 是 | Refresh Token 的不可逆哈希，不保存明文 |
| `parentGrantId` | `string` | 否 | 上一次轮换 Grant ID |
| `issuedAt` | `datetime` | 是 | 签发时间 |
| `expiresAt` | `datetime` | 是 | 过期时间 |
| `consumedAt` | `datetime` | 否 | 成功换取下一组 Token 的时间 |
| `revokedAt` | `datetime` | 否 | 主动撤销时间 |

每次刷新在同一事务中消费当前 Grant、创建子 Grant 并签发新 Token。再次使用已消费 Grant 时撤销整个 `tokenFamilyId`，返回 `AUTH_REFRESH_TOKEN_REUSED`。

