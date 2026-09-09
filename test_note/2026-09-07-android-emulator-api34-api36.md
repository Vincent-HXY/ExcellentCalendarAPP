# Android 模拟器基础运行记录（API 34 / API 36）

- 验证时间：2026-09-07 19:50 +08:00
- 验证范围：Android 官方 Google APIs x86_64 System Image 的安装、AVD 首次启动、ADB 与 Flutter 设备识别。

## EC_API36

- 设备模板：Pixel 7
- 系统：Android 16 / API 36（SDK target `android-36.1`，System Image revision 4）
- ABI：x86_64
- 结果：无快照冷启动成功，`sys.boot_completed=1`；ADB 返回 AVD 名称 `EC_API36`；Flutter 可识别为 Android 16 / API 36 模拟器。

## EC_API34

- 设备模板：Pixel 7
- 系统：Android 14 / API 34（System Image revision 14）
- ABI：x86_64
- 结果：无快照冷启动成功，`sys.boot_completed=1`；ADB 返回 AVD 名称 `EC_API34`；Flutter 可识别为 Android 14 / API 34 模拟器。

本记录仅证明上述两台模拟器的基础运行环境通过，不代表 ExcellentCalendarAPP 的业务功能、安装包或完整设备验收已经在这些环境中通过。
