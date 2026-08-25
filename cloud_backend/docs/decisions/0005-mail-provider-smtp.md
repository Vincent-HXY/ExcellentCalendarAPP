# ADR-0005：邮件 Provider —— 通用 SMTP 适配器

> 状态：Accepted（2026-08-19）
> 范围：`identity` 模块验证码邮件的首个真实投递用例。
> 依据：`docs/decisions/README.md`（邮件 Provider 需在首个受影响切片开始前新增 ADR）、
> ADR-0004 §6（生产接入真实 SMTP 时必须替换 `UnconfiguredMailSender`）。

## 1. 背景

- 注册/改邮箱/重置密码的 6 位验证码经 `MailSender` 端口发送，调用点在业务事务
  `afterCommit`（ADR-0004 §6），事务回滚不会发信。
- 此前只有 `ConsoleMailSender`（dev/local，验证码进控制台）与 `UnconfiguredMailSender`
  （其他 Profile，无码 WARN），无任何真实投递能力。
- 邮件正文只含 6 位验证码（本阶段无链接 Token，ADR-0004 §6），主题按 purpose 区分。

## 2. 决策

1. **通用 SMTP 适配器**：新增 `spring-boot-starter-mail`（版本由 Spring Boot BOM 管理），
   在 `identity/infrastructure` 实现 `SmtpMailSender`，基于 `JavaMailSender`，不绑定任何
   具体供应商。QQ/163/Outlook/Gmail 等通过配置切换，不改代码。
2. **opt-in 激活**：仅在 `excellent-calendar.mail.host` 非空时启用，优先级固定为
   SMTP > dev/local 控制台收件箱 > 无码 WARN 兜底；任何 Profile（含生产 `api`）均可启用，
   未配置时行为与 ADR-0004 完全一致。
3. **类型安全配置** `MailSendingProperties`（`excellent-calendar.mail.*`）：host/port/
   username/password/from/start-tls/ssl 与 connect/read/write 超时；密钥只从环境变量注入。
   host 已配置但 username/password 为空时启动立即失败并给出明确报错。
4. **尽力发送**：`SmtpMailSender` 捕获 `MailException/MessagingException` 仅记 WARN
   （收件人掩码、无验证码、无凭据），不向已提交的业务流传播。Challenge 已持久化，用户可经
   resend 端点（60s 间隔）重试，SMTP 故障不会让注册/重置流程 500。
5. **传输安全与超时**：587+STARTTLS（默认，含 `starttls.required` 防降级）或
   465+implicit SSL（`ssl=true`）；连接/读/写超时默认各 10s。SMTP 不做自动重试（连接类错误
   重试意义有限，resend 端点承担重试语义）。
6. **本阶段不做**：退信/弹回处理、发信域名（DKIM/SPF/DMARC）、发送限额与模板版本化、
   Outbox 化异步发送（afterCommit 同步发送即可满足验证码场景，失败可重发）。

## 3. 后果

- 优点：验证码可真实投递到用户手机邮箱；配置即切换供应商；不配置时零行为变化；
  失败模式对核心事务无副作用。
- 代价与风险：SMTP 投递仍是尽力而为（无退信告警、无投递回执）；发送在 HTTP 线程的
  afterCommit 阶段同步执行，极端情况下最长阻塞为超时之和；真实供应商的限流/反垃圾策略
  需在启用后实测（本项目尚未用真实账号验证投递）。
