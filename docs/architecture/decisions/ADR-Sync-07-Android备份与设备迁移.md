# ADR-Sync-07：Android 备份与设备迁移

Status: Proposed
Date: 2026-09-05

## Context

当前主 Manifest 没有显式 `allowBackup/fullBackupContent/dataExtractionRules`，无对应规则 XML。总计划明确游客数据也不得上传；不能只排除账号库，或把恢复后更换 identity 当作已经上传的补救。

## Proposed Decision

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
