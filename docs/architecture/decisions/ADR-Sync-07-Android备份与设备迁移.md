# ADR-Sync-07：Android 备份与设备迁移

Status: Accepted (design decision; final Contract evidence is recorded in ct0_gate_status.json)
Date: 2026-09-05

Acceptance: 按用户授权自主落实总计划“游客永不上传”及全量排除规则。不开放 guest direct-transfer 例外；最终 APK/系统行为仍须独立验证。

## Context

当前主 Manifest 没有显式 `allowBackup/fullBackupContent/dataExtractionRules`，无对应规则 XML。总计划明确游客数据也不得上传；不能只排除账号库，或把恢复后更换 identity 当作已经上传的补救。

## Decision

| 数据类别 | Auto Backup / cloud | device-to-device | 恢复策略 |
| --- | --- | --- | --- |
| installation、workspace/device Registry | exclude | exclude | 全新安装重新生成并向服务端登记 |
| Broker token/pending record、Keystore/wrapped key | exclude | exclude | 重新登录，不恢复旧 token family |
| 所有 guest/account DB、WAL、SHM、旧 JSON 和迁移快照 | exclude | exclude | 不走 Android 自动恢复 |
| transport/import/clear/logout journal 与 seed | exclude | exclude | 不跨 installation 复用本机生命周期 |
| remote-device cache、profile cache、search history | exclude | exclude | 同设备正常生命周期受自身 owner 控制 |
| BootEpochRecord、时间锚、retention/lease record | exclude | exclude | installation/AAD/boot 不匹配时 fail closed |

同时配置兼容 Android 旧版 backup XML 与 Android 12+ data extraction rules，对 credential/device protected 的 root/file/database/sharedpref 等实际存储域逐一覆盖；guest 当前数据库位于 files 路径，不能仅排除 database domain。Manifest 明确 allowBackup=false；不得只靠该 flag 推断所有厂商 D2D 都已禁用。

不提供 guest direct-transfer 例外。后续若产品提出迁移，必须另立证明传输不经过第三方云、开放前原子 re-home source/workspace identity 且不重复导入的 ADR。

## Verification and Consequences

按真实最终 merged Manifest 和打包规则验证 API 23、24+、31+ 行为；覆盖卸载重装、cloud restore、D2D、key 缺失和同一源到两台设备。不能对当前用户设备执行清数据/卸载来替代隔离测试。

官方 [Auto Backup 文档](https://developer.android.com/identity/data/autobackup) 区分 Android 12+ 的 cloud/D2D 规则，并说明某些设备的 D2D 不能仅由 allowBackup 控制。因此本提案要求明确规则和设备证据。本次不修改 Android Manifest 或备份行为，验收未执行。

## 2026-09-05 Contract 阶段验证补充

现已交付 `android_backup_policy_v1.yaml`、隔离 APK 的三份规则 XML 和实际打包摘要；API33 arm64/arm32 运行 92 项密钥/JNI/卸载重装/合成密文恢复检查。`backup_policy_vectors.json` 另以 25 类合成数据覆盖 API23/24/30/31/33 的 cloud 与 D2D 规则选择、同源两目标隔离；11 个固定场景与 4 项策略测试通过。负例删除各域 exclude 后能检测 guest 数据被纳入候选集合，验证没有只依赖 allowBackup 标志。

验收范围采用上位 02 §4.2 的 fixture 要求和 §18 的产品代码边界：上述是 Contract 策略、实际隔离打包和 API33 设备证据，不等于实际云/OEM数据搬运、API23/24系统运行或生产 restore owner 已实现。05 仍须在产品 merged Manifest/安装包及系统环境中回报实现证据。V1 不允许 guest direct-transfer/re-home；恢复得到的旧库、身份、Broker/lease/lineage 均不得直接激活。
