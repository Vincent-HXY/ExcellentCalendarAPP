# 认证与个人信息 — 本地联调说明

> 适用：后端阶段 0–5 与前端 AI 联调。所有命令在 `cloud_backend/` 目录执行（PowerShell）。

## 1. 环境准备

```powershell
docker compose up -d postgres
docker compose ps
```

## 2. 启动后端（api,local Profile）

```powershell
.\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=api,local"
```

- 监听 `http://localhost:8080`；
- `local` Profile 提供本地开发默认值：PostgreSQL 连接、HS256 开发密钥、头像目录 `./data/avatars`、
  头像 base-url `http://localhost:8080`；**生产环境禁止启用 `local`**；
- 除 `/actuator/health`、16 个已声明端点与头像静态路径外，其余路径保持 403 拒绝。

## 3. dev 邮箱（验证码查看方式）

`api,local`（或 `dev`）Profile 下邮件由 `ConsoleMailSender` 输出到控制台，日志前缀 `[mail.dev]`，
包含收件人、主题与 6 位验证码：

```text
[mail.dev] to=user@example.com subject=... code=123456
```

其余 Profile（含生产 `api`）使用 `UnconfiguredMailSender`：只输出**不含验证码与收件人**的
WARN，验证码永远不会进入日志；生产环境必须接入真实 SMTP 实现并替换该 bean。

联调时在 Spring Boot 控制台日志中查找 `[mail.dev]`。

### 真实 SMTP（可选，验证码发到手机邮箱）

配置 `EXCELLENT_CALENDAR_MAIL_HOST`（非空）后，任何 Profile 都会改用真实 SMTP 发信
（见 ADR-0005），控制台收件箱自动停用。需要在邮箱服务商开启 SMTP 并取得**授权码**
（不是登录密码）。常见配置（写入 `.env` 或系统环境变量）：

```powershell
# QQ 邮箱（授权码）
$env:EXCELLENT_CALENDAR_MAIL_HOST="smtp.qq.com"
$env:EXCELLENT_CALENDAR_MAIL_PORT="465"
$env:EXCELLENT_CALENDAR_MAIL_SSL="true"
$env:EXCELLENT_CALENDAR_MAIL_USERNAME="你的QQ邮箱"
$env:EXCELLENT_CALENDAR_MAIL_PASSWORD="你的SMTP授权码"

# 163 / Outlook / Gmail 改用对应主机与端口（587 STARTTLS 或 465 SSL），见 .env.example 注释
```

- `username`/`password` 缺失而 `host` 已设置时，启动立即失败并提示具体缺失项；
- 邮件正文只有 6 位验证码（本阶段无链接）；发信失败仅记录 WARN（收件人掩码、无验证码），
  已提交的 Challenge 仍可经 resend 端点（60s 间隔）重试；
- 验证码在手机邮件 App 中查看后，回到 §4 的 verify 步骤填码即可。

## 4. 端点示例 curl（Windows PowerShell）

约定：`$BASE = http://localhost:8080/api/v1`。所有响应为 `ApiResult` 信封
（`ok/data/error/contract_version/request_id`）。

### 注册

```powershell
$key = [guid]::NewGuid().ToString()
Invoke-RestMethod -Method Post -Uri "$BASE/auth/register" `
  -Headers @{ "Idempotency-Key" = $key; "Content-Type" = "application/json" } `
  -Body (@{
    email = "user@example.com"; username = "calendar_user"; display_name = "Calendar User"
    password = "CorrectHorseBattery"; locale = "zh-CN"; timezone = "Asia/Shanghai"
    agreement_version = "terms-v1"; agreement_accepted = $true
  } | ConvertTo-Json)
# → RegistrationPendingResponse { account_id, challenge{challenge_id, masked_email, …} }
```

### 验证注册（验证码从控制台 `[mail.dev]` 读取）

```powershell
Invoke-RestMethod -Method Post -Uri "$BASE/auth/registration/verify" `
  -ContentType "application/json" `
  -Body (@{ challenge_id = "<challenge_id>"
            credential = @{ credential_type = "code"; code = "123456" } } | ConvertTo-Json -Depth 5)
# → AuthenticationResponse { current_user, tokens }
```

### 登录 / 刷新 / 退出

```powershell
$login = Invoke-RestMethod -Method Post -Uri "$BASE/auth/login" -ContentType "application/json" `
  -Body (@{ email = "user@example.com"; password = "CorrectHorseBattery" } | ConvertTo-Json)
$rt = $login.data.tokens.refresh_token
$at = $login.data.tokens.access_token

# 刷新（原子轮换，旧 refresh token 立即失效）
Invoke-RestMethod -Method Post -Uri "$BASE/auth/token/refresh" -ContentType "application/json" `
  -Body (@{ refresh_token = $rt } | ConvertTo-Json)

# 当前用户（Bearer）
Invoke-RestMethod -Method Get -Uri "$BASE/users/me" -Headers @{ Authorization = "Bearer $at" }

# 退出当前会话
Invoke-RestMethod -Method Post -Uri "$BASE/auth/logout" -ContentType "application/json" `
  -Body (@{ refresh_token = $rt } | ConvertTo-Json)

# 退出所有设备（Bearer）
Invoke-RestMethod -Method Post -Uri "$BASE/auth/logout-all" -Headers @{ Authorization = "Bearer $at" } `
  -ContentType "application/json" -Body "{}"
```

### 忘记密码 / 重置 / 修改密码

```powershell
Invoke-RestMethod -Method Post -Uri "$BASE/auth/password-reset/request" `
  -Headers @{ "Idempotency-Key" = [guid]::NewGuid().ToString() } -ContentType "application/json" `
  -Body (@{ email = "user@example.com" } | ConvertTo-Json)

Invoke-RestMethod -Method Post -Uri "$BASE/auth/password-reset/confirm" -ContentType "application/json" `
  -Body (@{ email = "user@example.com"; new_password = "NewPassword12345"
            credential = @{ credential_type = "code"; code = "654321" } } | ConvertTo-Json -Depth 5)

Invoke-RestMethod -Method Post -Uri "$BASE/auth/password/change" `
  -Headers @{ Authorization = "Bearer $at" } -ContentType "application/json" `
  -Body (@{ current_password = "CorrectHorseBattery"; new_password = "AnotherPassword" } | ConvertTo-Json)
```

### 修改邮箱（申请 → 新邮箱验证码确认）

```powershell
Invoke-RestMethod -Method Post -Uri "$BASE/auth/email-change/request" `
  -Headers @{ Authorization = "Bearer $at"; "Idempotency-Key" = [guid]::NewGuid().ToString() } `
  -ContentType "application/json" `
  -Body (@{ new_email = "new@example.com"; current_password = "AnotherPassword" } | ConvertTo-Json)

Invoke-RestMethod -Method Post -Uri "$BASE/auth/email-change/confirm" `
  -Headers @{ Authorization = "Bearer $at" } -ContentType "application/json" `
  -Body (@{ email_change_request_id = "<request_id>"
            credential = @{ credential_type = "code"; code = "111111" } } | ConvertTo-Json -Depth 5)
```

### 资料与头像

```powershell
# PATCH 局部更新
Invoke-RestMethod -Method Patch -Uri "$BASE/users/me" -Headers @{ Authorization = "Bearer $at" } `
  -ContentType "application/json" `
  -Body (@{ display_name = "新昵称"; timezone = "Asia/Tokyo" } | ConvertTo-Json)

# 上传头像（multipart part=file）
$file = "A:\path\to\avatar.png"
curl.exe -X POST "$BASE/users/me/avatar" `
  -H "Authorization: Bearer $at" -H "Idempotency-Key: $([guid]::NewGuid())" `
  -F "file=@$file;type=image/png"

# 头像公开读取（内部静态路径，非 ApiResult）
Invoke-WebRequest -Uri "http://localhost:8080/api/v1/media/avatars/<asset_id>" -OutFile avatar.jpg
Invoke-WebRequest -Uri "http://localhost:8080/api/v1/media/avatars/<asset_id>/thumbnail" -OutFile thumb.jpg

# 删除头像
Invoke-RestMethod -Method Delete -Uri "$BASE/users/me/avatar" -Headers @{ Authorization = "Bearer $at" }
```

## 5. 关键行为速查

- Refresh Token 每次刷新即轮换；重放已消费 Token → 撤销整个 token family →
  `AUTH_REFRESH_TOKEN_REUSED`。
- 登录未验证账号 → `AUTH_EMAIL_UNVERIFIED`，`error.context.verification_challenge` 非空。
- 忘记密码申请对未知邮箱与已注册邮箱返回相同成功结构。
- 验证码连续错 5 次 → 该 Challenge 作废，后续验证返回 `AUTH_VERIFICATION_INVALID`。
- 修改密码/确认改邮箱后：当前设备拿到新 Token Pair，其他设备旧会话立即失效
  （Bearer 请求返回 `AUTH_SESSION_EXPIRED`）。
- 上传失败保留旧头像；删除后 `avatar_asset_id=null`，不返回默认头像 URL。

## 6. 构建与测试

```powershell
.\mvnw.cmd test      # 单元/架构/Web slice
.\mvnw.cmd verify    # 含 PostgreSQL 17.11 Testcontainers 集成测试（需要 Docker）
```
