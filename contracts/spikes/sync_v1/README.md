# Sync V1 CT0 实验

这些程序只用于云同步-02 §4.2 的现状/候选审计，不进入产品依赖或 production composition。当前结果是 **CT0 PARTIAL / DECISION REQUIRED**。

## 已有 encoder 复用审计

`run_serializer_audit.py` 构建 Windows C++、Java、Dart 探针，可用现有 NDK 编译三 ABI；`--android-device` 仅运行连接设备支持的 ABI。它使用 `contracts/fixtures/sync/v1/canonical_vectors.json` 中预先固定的等价 JCS 向量，不将 encoder 自身输出作为期望。

```powershell
python contracts/spikes/sync_v1/run_serializer_audit.py `
  --cpp-compiler D:/mingw/mingw64/bin/g++.exe `
  --java-classpath '<现有 jackson-databind、jackson-core、jackson-annotations 三个 JAR，以系统 path separator 分隔>' `
  --dart A:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe `
  --ndk A:/Android/sdk/ndk/28.2.13676358 `
  --report contracts/spikes/sync_v1/serializer_audit_result.json
```

本次使用现有 Jackson 3.1.4 / annotations 2.21；没有升级依赖。每次在系统临时目录编译，退出时清理主机 build。设备执行只使用 `/data/local/tmp/excellent-calendar-sync-ct0-<abi>` 测试二进制，不安装/卸载 App，不访问用户数据库。断连时不得把部分输出当成功；若清理失败，报告精确残留路径。

`serializer_audit_result.json` 显示 C++/Java/Dart 原始 encoder 均为 `not_jcs`。Windows 现有私有 SHA-256 的8项独立 KAT通过；三 ABI编译成功、runtime 未验证。退出0表示审计成功运行，**不是 JCS spike通过**。本探针没有实现正式 canonicalizer，也没有将 SHA-256提取/接入产品。

## SQLCipher 候选包审计

使用隔离临时目录中的 [Maven SQLCipher Community 4.18.0 AAR](https://repo.maven.apache.org/maven2/net/zetetic/sqlcipher-android/4.18.0/sqlcipher-android-4.18.0.aar) 和同路径 `.aar.sha256`，先核对摘要。该包只供探针审计，不复制进产品或改 Gradle。

```powershell
python contracts/spikes/sync_v1/audit_sqlcipher_package.py `
  --aar '<临时目录>/sqlcipher-android-4.18.0.aar' `
  --upstream-sha256 '<临时目录>/sqlcipher-android-4.18.0.aar.sha256' `
  --ndk A:/Android/sdk/ndk/28.2.13676358 `
  --report contracts/spikes/sync_v1/encryption_package_audit.json
```

该入口离线检查已有包，不自动下载、不升级 SDK。实际包摘要：`f59aaf02ffd4de649f85a6c0d296f9a91763764c07707997834abc0cfc745222`。

当前候选三 ABI 的 Storage C API/key symbol 均存在，使用本项目的 SQLite header 和 NDK28.2链接 `sqlcipher_probe.cpp` 成功。AAR metadata 要求 `minCompileSdk=37`，不能直接用于现有 SDK36构建。直接 C 依赖或源码构建方案仍需 ADR 接受和验证。

`sqlcipher_probe.cpp` 只接受新建 scratch DB路径，包含20,000条合成行、WAL/FULL/defensive、DB/WAL sentinel、wrong-key和重开校验。**本轮未执行此程序**，因此不能声称加密/性能/恢复通过。此探针也不覆盖完整 V1组合数据、v5→v6迁移、temporary pages、full-disk、强杀或三 ABI设备矩阵。

`encryption_source_audit.json` 另外保存官方仓库两个 v4.18.0 标签的 peeled commit、Android gitlink 和15份固定 URL 文件的原始 SHA-256。复核时从 `retrieved_files[].url` 读取原始 bytes 后独立计算 SHA-256，不能先做换行转换；这些是外部源码摘要，与本仓库 LF 归一化的 producer 摘要不同。Android 标签 core gitlink 仍为 SQLite3.53.1，而选定 core v4.18.0 为3.53.4。不得默认 submodule update 后就是候选源码，也不能由此推断 Maven AAR 用了旧版本；其源码重建和实际版本均需独立证据。该文件只记录源码来源和顶层许可初审，不是完整许可、构建或密码学通过报告。

## CT0 检查入口与结果含义

```powershell
python contracts/run_sync_v1_validation.py --stage ct0 --self-test
python contracts/run_sync_v1_validation.py
```

第一条只校验CT0证据、旧协议/Storage摘要、现有Schema引用、runtime校准、Backend静态盘点、向量完整性和反例。第二条默认要求冻结，当前必须以Python退出码2返回 `DECISION REQUIRED`；正式CT1–CT4/Sync V1 validator尚未交付。PowerShell宿主可能将非零退出映射为1，反例测试直接检查Python子进程的2。

所有fixture/producer source摘要使用UTF-8文本、LF换行，以免Git autocrlf产生伪漂移；golden期望仍是明确的canonical UTF-8 bytes/hex。报告源码或fixture变化必须重跑相关审计，不能手填passed。失败实验、缺失ABI和未验证设备行为不得被 `--stage ct0` 的成功掩盖。
