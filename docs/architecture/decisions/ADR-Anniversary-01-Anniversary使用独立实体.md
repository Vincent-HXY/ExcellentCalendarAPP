# ADR-Anniversary-01: Anniversary 使用独立实体

Status: Accepted
Date: 2026-08-10

## Context

纪念日具有年度重复、剩余天数计算、特殊展示和独立提醒策略。若继续作为 Event 的特殊类型，会增加大量 nullable 字段和条件分支，并混淆日程时间点与本地纪念日期。

## Decision

- Anniversary 建模为独立 Domain Entity，不是 Event 的特殊类型。
- Flutter、Kotlin、JNI、C++ 使用独立 Anniversary Contract 和调用入口。
- 一次性纪念日使用 `recurrence_id = null`；年度重复使用独立 `AnniversaryRecurrence`，V1 固定为 `yearly + interval=1`。
- 原始日期和历史年份只保存在 `Anniversary.date`；规则不重复保存月、日、RRULE 或 UTC occurrence。
- 下一次 occurrence 和倒计时由 C++ 按请求 IANA timezone 动态计算，不预生成多年记录。
- 年度重复切换为一次性时，清空引用与软删除旧规则在同一 Anniversary transaction 中完成。
- Anniversary Reminder 在 occurrence identity、幂等和调度语义完成独立设计前不接入。

## Consequences

- Anniversary 可以独立演进公历、农历、展示和提醒策略，不污染 Event 模型。
- Calendar 聚合应动态读取 Anniversary occurrence，不能复制为 Event。
- 2 月 29 日等日期规则在 C++ 保持唯一实现，各端不重复推导。
