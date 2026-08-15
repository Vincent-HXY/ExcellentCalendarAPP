# 已解决：Flutter Application 与页面路由

## RES-UI-001 通知点击只进入固定“日程不存在”页面

- 严重程度：P1（源文档）
- 产生原因：NotificationTapRouter 虽生成 Event detail route，AppRouter 当时没有真实加载 Event，只返回占位缺失页，导致主链最后一步中断。
- 解决方式：Event 路由现在可注入真实 detail builder，Production composition 已接入 `EventDetailFlowPage`，并保留普通 Event 与 occurrence key 路由参数。
- 可吸取的教训：路由字符串匹配不等于功能闭环；验收必须继续验证目标数据加载、错误态和用户实际页面。
- 来源：`[P1] 通知点击后没有进入可用页面`。真机冷/热启动验证仍在 `open.md`。

## RES-UI-002 Flutter 生产代码依赖 Fake Category 与固定默认项

- 严重程度：P1（评估）
- 产生原因：Category Native 尚未发布时，Fake 数据和 `vin_star` 默认项逐渐进入生产交互，导致 UI 展示事实与领域/Storage 不一致。
- 解决方式：生产代码移除 Fake 和固定 owner 耦合；默认使用未分类，选择器区分取消、未分类和具体分类，编辑可显式清空；默认及 Release composition 统一接入 Native Repository。
- 可吸取的教训：Fake 只能用于测试或明确原型，不能成为生产领域事实；生产依赖必须受发布门禁约束。
- 来源：Category“已关闭的整改项”。
