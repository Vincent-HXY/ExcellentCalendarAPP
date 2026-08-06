# Text Extraction

负责清洗文本并提取可能的日程信息。

## 具体任务

- 清洗 OCR 或分享文本中的噪声。
- 提取标题、时间描述、地点、人物、事项、备注等线索。
- 标记不确定字段。
- 输出给 Time Parser、Category Recommender、Candidate Event Builder。

## 交付标准

- 不直接创建日程。
- 保留原文引用，方便用户确认。
- 对低置信度字段明确标记。
