# Claude Code Skills — ExcellentCalendarAPP

这些 Skill 是预定义的提示词模板，用于让 Claude Code 自动生成代码。

## 使用方式

在 Claude Code 中输入 `/<skill-name>` 即可触发对应 Skill。

目前可用的 Skill：

| 命令 | 功能 | 优先级 |
|------|------|--------|
| `/flutter-auth-connect` | 将注册/邮箱验证/忘记密码/重置密码页面的模拟数据替换为真实 API 调用 | 🔴 高 |
| `/flutter-profile-connect` | 将资料页面/头像/改密/改邮箱的模拟数据替换为真实 API 调用 | 🔴 高 |
| `/backend-test-auth` | 为 AuthenticationService、JwtTokenProvider、Controller 添加单元测试 | 🟡 中 |
| `/flutter-test-auth` | 为 AuthController、AuthHttpClient、AuthApiClient 添加 Flutter 测试 | 🟡 中 |

## 各 Skill 执行顺序建议

1. **先跑 `/flutter-auth-connect`** — 让认证页面能用真实 API 注册/登录
2. **再跑 `/flutter-profile-connect`** — 让资料页面能用真实 API 获取/更新数据
3. **跑 `/backend-test-auth`** — 验证后端逻辑的正确性
4. **跑 `/flutter-test-auth`** — 验证前端认证逻辑的正确性

> ⚠️ 每个 Skill 内部包含严格的约束条件，防止 AI 修改已有框架代码。
> 如果执行过程中出现冲突或错误，请检查约束条件是否被违反。