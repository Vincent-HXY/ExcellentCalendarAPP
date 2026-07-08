# 整体项目开发

## 整体基本功能逻辑闭环

### reminder功能设计开发

- 2027/7/4 
CPP的支撑函数已经完成开发，下一步进行kotlin开发，完成kotlin的提醒功能实现。

- 2027/7/6
整个已经完成了上面的闭环，正在对于一些问题进行测试和修改

- 2027/7/8
正在对于一些存在的bug进行修复和修改。
今天的重点修复内容是：存在过期Alarm，需要正确初处理这个过期的Alarm
然后就是reminder_id 和 notification_id 这两个id实际上本应是不一样的，但是我们在传给CPP构造的时候，却都是使用的reminder_id，我们应该弄清楚这个reminder_id notification_id的生成权，到底是放在Android还是集中在cpp上面