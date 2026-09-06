# Sync V1 Contract 隔离实验

这些程序用于云同步-02 的现状审计、技术可行性和 Contract 参考验证，不进入产品依赖。唯一冻结状态见 `contracts/sync/ct0_gate_status.json`；已封版时由 `contracts/sync/sync_v1_revision_lock.json` 绑定四个下游的同一协议摘要。新增产品能力继续为 planned。

当前交付入口：

- `contracts/run_sync_v1_validation.py`：历史基线、Schema/ref/能力/错误/模型闭包、逐项证据与最终 revision lock。默认入口只在全部证据和封版记录一致时成功。
- `build_fixture_manifest.py --check`：20 个 fixture 族、717 个固定用例和 9 个生成 suite，区分 parser transport 与实际 owner 语义证据。
- `run_cross_language_schema_spike.py`：C++/Java/Kotlin/Dart 共用 1,308 项输入；717 个固定 fixture 完整往返、410 个边界、56 个 Native v2/v3 兼容输入、61 个目标形状和 64 个 JCS 边界。JSON 往返不代替事务或 Android 系统行为。
- `run_client_recovery_spike.py`：26 项完整导入、fresh 恢复、持久策略/先下载门禁、有界维护及保密记录测试，含 17 个实际进程退出点。AEAD 记录证明身份绑定和可信 owner 回执消费，Android key deletion 由独立真机证据覆盖。
- `run_import_saga_spike.py`：53 项导入组件测试；`run_import_capacity_spike.py`：实际 20,000 / 50,000 条混合业务图、完整映射/发布、40 / 100 个有界 chunk 和 count+2 个真实回执。源码变化必须复跑，不手工重写 source hash。
- `run_storage_spike.py`：未修改的生产 C++ v5 checker、11 项 SQLite 检查和 128 个原子回滚边界；隔离 PostgreSQL 40 张新表、125 个字段映射、70 个约束用例。生产 migration、Android v6 全业务图属于 03/04/05。
- `run_protocol_spike.py`：213 个协议/生命周期/错误/私有记录 Schema、96 个固定向量、53 项测试。`run_capability_spike.py`：17 项测试、28 个固定用例、480 个边界 Schema、107 个公开方法和 90 个内部调用。
- `run_domain_spike.py`：12 个 target、125 个 field、61 个固定事实边界和 22 项测试；原 civil 身份及 v1 历史导入由两个链接真实 Core 的独立 runner 验证。
- 其余独立 runner 和已执行 scope 见各 `*_spike_result.json`，包括 counter、cursor、Habit operation、owned graph/sequence/resolution、failed-local、bootstrap、conflict 和 notice。

已通过且来源未变化的 CT0 环境/构建证据保持有效。本次依用户要求缩减重复验证，最终仅复跑受影响证据，不重跑无产品代码变化的整套 Flutter/Backend 构建。历史过程中发生的失败与各阶段 partial 状态保留在 `docs/plan/active/云同步-02-CT0审计与决策记录.md`。

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

`serializer_audit_result.json` 显示 C++/Java/Dart 原始 encoder 均为 `not_jcs`。Windows 现有私有 SHA-256 的8项独立 KAT通过；三 ABI编译成功；后续已补真实 arm64 Android encoder/SHA执行，另两ABI在这个历史encoder审计中仍为compile-only。退出0表示审计成功运行，**不是 JCS spike通过**。本探针没有实现正式 canonicalizer，也没有将 SHA-256提取/接入产品。

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

当前候选三 ABI 的 Storage C API/key symbol 均存在，使用本项目的 SQLite header 和 NDK28.2链接 `sqlcipher_probe.cpp` 成功。AAR metadata 要求 `minCompileSdk=37`，不能直接用于现有 SDK36构建。直接 C 候选已由用户接受；后续固定源码构建结果独立记录，见下节。

`sqlcipher_probe.cpp` 只接受新建 scratch DB路径，包含20,000条合成行、WAL/FULL/defensive、DB/WAL sentinel、wrong-key和重开校验。首次包审计没有执行此程序；后续已在Windows、三ABI Bionic/QEMU-user及真实arm64 Android运行，结果见cipher_source_spike_result.json。它的20,000行仅证明加密容量可行性；完整V1组合图、v5→v6迁移和Keystore仍需独立证据。恢复/temp/FULL测试由另一个cipher_recovery_probe.cpp执行。

`encryption_source_audit.json` 另外保存官方仓库两个 v4.18.0 标签的 peeled commit、Android gitlink 和15份固定 URL 文件的原始 SHA-256。复核时从 `retrieved_files[].url` 读取原始 bytes 后独立计算 SHA-256，不能先做换行转换；这些是外部源码摘要，与本仓库 LF 归一化的 producer 摘要不同。Android 标签 core gitlink 仍为 SQLite3.53.1，而选定 core v4.18.0 为3.53.4。不得默认 submodule update 后就是候选源码，也不能由此推断 Maven AAR 用了旧版本；其源码重建和实际版本均需独立证据。该文件只记录源码来源和顶层许可初审，不是完整许可、构建或密码学通过报告。

## CT0 检查入口与结果含义

```powershell
python contracts/run_sync_v1_validation.py --stage ct0 --self-test
python contracts/run_sync_v1_validation.py
```

第一条校验 CT0–CT4 已交付证据并运行完整参考测试；它可用于冻结前诊断，成功本身不等于封版。第二条是正式默认入口，只有所有证据、来源摘要和最新 revision 锁通过才成功；未冻结时以 Python 退出码 2 返回 `DECISION REQUIRED`。当前状态以 `contracts/sync/ct0_gate_status.json` 为准，5d8fb0a 的 Review 复核及本次兼容修订见 `docs/plan/active/云同步-02-Review复核与兼容修订记录.md`。PowerShell 宿主可能将非零退出映射为 1，反例测试直接检查 Python 子进程结果。

所有fixture/producer source摘要使用UTF-8文本、LF换行，以免Git autocrlf产生伪漂移；golden期望仍是明确的canonical UTF-8 bytes/hex。报告源码或fixture变化必须重跑相关审计，不能手填passed。失败实验、缺失ABI和未验证设备行为不得被 `--stage ct0` 的成功掩盖。


## 接受方向后的源码与恢复实验

现有工具入口如下。`--scratch` 指向独立临时工作目录；下载只取固定官方源码归档并校验摘要，不改产品依赖。需要当前已有的 WSL/make 与 qemu-user-static，不安装或升级工具。

```powershell
python -X utf8 contracts/spikes/sync_v1/run_cipher_source_spike.py `
  --scratch '<独立临时目录>' `
  --cmake A:/Qt/Tools/CMake_64/bin/cmake.exe `
  --ninja A:/Android/sdk/cmake/3.22.1/bin/ninja.exe `
  --gcc D:/mingw/mingw64/bin/gcc.exe --gxx D:/mingw/mingw64/bin/g++.exe `
  --ndk A:/Android/sdk/ndk/28.2.13676358 --wsl C:/Windows/system32/wsl.exe `
  --adb A:/Android/sdk/platform-tools/adb.exe --serial '<连接的arm64测试设备>' `
  --report contracts/spikes/sync_v1/cipher_source_spike_result.json
python -X utf8 contracts/spikes/sync_v1/audit_cipher_sources.py `
  --scratch '<同一临时目录>' `
  --report contracts/spikes/sync_v1/cipher_runtime_source_audit.json
```

源码重建使用独立SQLCipher core 63697beb0fafcb61faa7a3e6fd267036548ab11b 和 LibTomCrypt fork 476a9579ae94f32b9ea9e2747bfb04b302370259。原始archive摘要、amalgamation摘要、构建调用和逐环境执行输出都进入报告。require_os_rng.patch 禁止OS随机源失败后回退时钟采样；rng_failure_probe直接编译该已补丁provider文件并注入OS失败。许可证通知在licenses/，尚未接入产品许可UI。

cipher_recovery_probe使用真实SQLCipher与原生文件VFS。在提交前、WAL sync中、提交后、checkpoint部分写入时真实终止独立进程，随后重开并验证20,000行事实和Outbox全有或全无。FULL通过实际文件VFS的xWrite注入SQLITE_FULL；没有填满用户磁盘。强杀不等于突然断电。QEMU-user的NDK/Bionic执行与完整Android OS明确区分；arm64另有真实设备证据。设备使用随机命名scratch目录，精确清理文件，绝不清空用户App。

## RFC 8785 / SHA-256 扩展验证

```powershell
python -X utf8 contracts/spikes/sync_v1/run_jcs_spike.py `
  --cpp-compiler D:/mingw/mingw64/bin/g++.exe `
  --java A:/Android/AndroidStudio/jbr/bin/java.exe `
  --javac A:/Android/AndroidStudio/jbr/bin/javac.exe `
  --node 'C:/Program Files/nodejs/node.exe' `
  --ndk A:/Android/sdk/ndk/28.2.13676358 --wsl C:/Windows/system32/wsl.exe `
  --adb A:/Android/sdk/platform-tools/adb.exe --serial '<连接的测试设备>' `
  --report contracts/spikes/sync_v1/jcs_spike_result.json
```

固定64个JSON向量、6个非法UTF-8、20,000个有种子的有限IEEE随机数和31,487个系统性浮点边界。后者覆盖全部二进制指数的幂及相邻值、十进制1/3/5/7/9乘幂及相邻值，正负数均测试。数字期望来自独立的现有Node/V8；对象duplicate-key/Unicode校验另有固定期望。首次只有随机样本的版本遗漏了实际舍入错误，已用系统性向量修复并纳入机器校验。

C++仅使用已有标准库的shortest to_chars；Windows reader避开会误舍入的旧CRT strtod，Android当前NDK缺少浮点from_chars，使用经同向量验证的Bionic reader。Java以精确BigDecimal双侧候选选择最短可回读数字，最近值平局选偶数。对象按UTF-16排序，不做Unicode规范化；与identity.yaml的UUID名称数组域独立。SHA-256来自本项目MIT代码的隔离抽取，仅将总字节数改为明确uint64_t并通过9项独立KAT；未修改Core实现或添加生产依赖。

## Counter 和 Anniversary v3 兼容证据

```powershell
python -X utf8 contracts/spikes/sync_v1/run_counter_spike.py `
  --report contracts/spikes/sync_v1/counter_spike_result.json
python -X utf8 contracts/spikes/sync_v1/build_anniversary_v3_revision.py --check
```

counter_reference使用临时SQLite的真实事务、回执、CAS和两个并发连接，覆盖27个owner的81边界向量、54并发双写及持久重放/回滚。它不表示Backend/Broker/Core owner已经实现。Anniversary v3仅按已接受的字段放宽和传递ref派生，保留v2源摘要；15个Schema和28兼容向量仍是planned，不能据此启用产品Native v3或宣称全Sync协议冻结。


## Native v3 capability 与最新设备证据

`run_capability_spike.py` 当前检查 17 项 boundary 回归、28 个 fixed case、480 个独立 Schema，图中为 107 个公开方法及 90 个内部调用。`build_sync_registry_revisions.py` 只为原五份注册表追加 planned 链接。全部符号/DTO 是实现锁目标，不代表同包四语言实现。公共/内部 DTO 分别命名；新事件 envelope 保留既有四类事件，并增加同步/工作区两类；Habit 通知 action 同样必须携带工作区身份。

2026-09-05 最新 cipher report 已完成 Windows、三个 NDK/Bionic QEMU ABI，以及 RMX3687 / API 33 的 arm64 与 armeabi-v7a 各 24 步。runner 在设备声明支持 32-bit 时同时实跑对应产物，并以独立临时目录隔离测试。QEMU 不等于 Android OS，仍不认证 Keystore/backup 或完整 v6 同步图。

2026-09-05 21:59 的统一 drafts 检查通过 149 项、945 Schema、526 fixed/4 suite；Search、Habit、Calendar、Anniversary 四个旧验证器再次通过。Backend 已有 93 unit/58 integration/39 HTTP 通过证据。一次整分钟边界的 RateLimitIT 失败已记录在 CT0 审计 §12，不修改生产 limiter 来掩盖。

## 签名与完整证明

`run_proof_signature_spike.py --serial <测试设备>` 执行 14 个固定 RSA-PSS 原语用例；`run_proof_capsule_spike.py --serial <测试设备>` 执行 49 个完整 capsule 和 12 项独立 SQLite 接纳测试。完整 capsule 的 Java、Windows C++、实际 Android arm64/arm32 C++/JNI 输出一致，签名正确但领域范围、lineage、revision、allocator 不合法的证明仍被拒绝。私钥从未进入固定 fixture，`proof_capsule_seeds.json` 只有公开验签材料。计划的业务消费层仍为 planned。

`build_android_key_contract.py` 定义独立二进制 Keystore wrapper 和排除所有 guest/account 数据的 backup 规则；`run_android_key_spike.py` 构建无联网权限的随机独立测试包，使用已验证 native SQLCipher archive。测试包、数据和别名与产品隔离；不调用任何 cloud 或 D2D transport。最终产品 Manifest 和实际迁移设备行为仍需按报告的独立证据项验证。


## Habit operation 参考验证

`run_habit_operation_spike.py` 执行 11 项测试和 29 个固定操作历史，包括独立增减交换、同 operation 跨 transport 重试、clear/replace 屏障、binary/skipped、快照及正数边界、首次 parent history guard 和五个真实进程退出点。使用真实 SQLite 与原 sequence/receipt 参考模型组合；planned PostgreSQL/SQLite 表保存永久 operation hash 与已成功 effect。机器规则位于 `sync/sync_habit_operation_protocol.yaml`。这些结果不证明生产 Habit 同步 owner、完整 pending/bootstrap 重放或四语言消费已实现。

## 本机意图与重建组合证据

`run_local_intent_spike.py` 执行 29 项测试、8 个固定历史和 18 个实际进程退出点，覆盖同一 SQLite 事务中的待同步/失败记录、普通 typed download、完整 bootstrap、确认水位、效果门禁与 presentation 重投影。真实 Habit operation 结果证明：云端成功而本机回执丢失后，经普通下载或全量重建、重启、duplicate receipt 恢复，500+100 始终为 600。

机器规则位于 `sync/sync_local_intent_protocol.yaml`；冻结请求不会重写，缺少确切回执时保留原请求与可读草稿，失败记录不自动上传。替换失败、无效果替换、版本 MAX 与显式 discard 保留规则均有固定历史。该组合证据仍不覆盖 import publish、完整 resolution writer、生产 owner 或四语言消费；原独立 bootstrap 报告继续如实标记只验证 fresh promotion。
