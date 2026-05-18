# Candidate Event Builder

负责生成候选日程，等待用户确认。

## 具体任务

- 汇总 OCR、文本抽取、时间解析、分类推荐、提醒推荐结果。
- 生成 Candidate Event。
- 标记必填缺失项、低置信度字段和建议默认值。
- 交给 Application Layer 展示确认流程。

## 交付标准

- 不直接写入正式 Event。
- 候选结果必须保留来源文本和置信度。
- 支持用户修改后再创建日程。
