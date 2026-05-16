ExcellentCalendarAPP
│
├── Flutter Client 客户端表现层
│   ├── Presentation Layer
│   │   └── 负责页面展示、用户输入、按钮、弹窗、loading 状态
│   │
│   ├── Application Layer
│   │   └── 负责编排业务流程，例如创建日程、AI 导入、搜索、生成今日任务
│   │
│   ├── State Management
│   │   └── 负责页面状态管理，例如当前选中日期、搜索结果、表单状态
│   │
│   └── Dart Gateway Interfaces
│       └── 定义 Dart 层调用底层能力的接口契约
│
├── Boundary / Adapter Layer 边界适配层
│   ├── Dart MethodChannel Adapter
│   │   └── 将 Dart 请求转换为 MethodChannel 调用
│   │
│   ├── Kotlin MethodChannel Handler
│   │   └── 接收 Flutter 调用，并转发给 Android 服务或 C++ Core
│   │
│   ├── JNI Adapter
│   │   └── 负责 Kotlin 与 C++ 之间的参数转换和函数调用
│   │
│   ├── Storage Adapter
│   │   └── 负责 C++ 领域模型与 SQLite 数据结构之间的转换
│   │
│   └── Backend Sync Adapter
│       └── 负责本地同步模块与云端 API 之间的通信
│
├── Android Native Layer Android 系统能力层
│   ├── Notification Service
│   │   └── 负责系统通知、通知渠道、弹窗通知
│   │
│   ├── Alarm Scheduler
│   │   └── 负责定时提醒、系统闹钟、开机后恢复提醒
│   │
│   ├── Permission Manager
│   │   └── 负责通知权限、闹钟权限、文件权限等
│   │
│   ├── Share Receiver
│   │   └── 负责接收其他 App 分享来的文本或图片
│   │
│   ├── Widget Provider
│   │   └── 负责桌面小组件，例如今日日程、习惯、最近三天
│   │
│   └── WeChat Bridge
│       └── 负责微信登录、微信分享、微信推送相关能力
│
├── C++ Core Engine 核心引擎层
│   ├── Event Engine
│   │   └── 负责日程创建、修改、删除、查询、基础校验（防御性编程，这里的东西也是必须的）
│   │
│   ├── Reminder Engine
│   │   └── 负责提醒时间计算、默认提醒规则、生成提醒任务
│   │
│   ├── Recurrence Engine
│   │   └── 负责重复日程规则解析、展开、下一次发生时间计算
│   │
│   ├── Search Engine
│   │   └── 负责全文搜索、条件过滤、排序、分页
│   │
│   ├── Habit Engine
│   │   └── 负责习惯打卡、统计、连续天数、完成率
│   │
│   ├── Calendar Query Engine
│   │   └── 负责年/月/周/日/最近三日视图的数据聚合
│   │
│   ├── Quadrant Engine
│   │   └── 负责按照重要性和紧急性生成四象限数据
│   │
│   ├── AI Result Validator
│   │   └── 负责校验 AI 生成的候选日程是否可靠、合法
│   │
│   ├── Sync Log Engine
│   │   └── 负责记录本地操作日志，为后续云同步和冲突处理做准备
│   │
│   ├── Crypto / Export Engine
│   │   └── 负责本地数据加密、备份导出、备份导入
│   │
│   └── Storage Repository
│       └── 负责统一访问 SQLite，避免各个 Engine 直接乱写 SQL，所有的SQL语句都写在这里
│
├── Local Storage 本地存储层，所有的数据库文件，内容都写在这里
│   ├── SQLite
│   │   └── 负责结构化数据持久化
│   │
│   ├── SQLite FTS
│   │   └── 负责全文搜索索引
│   │
│   ├── Attachment Store
│   │   └── 负责保存图片、导入文件、附件
│   │
│   └── Operation Log
│       └── 负责保存本地增删改操作记录
│
├── AI Pipeline AI 输入管道
│   ├── OCR Adapter
│   │   └── 负责从图片中提取文字
│   │
│   ├── Text Extraction
│   │   └── 负责清洗文本、提取可能包含日程的信息
│   │
│   ├── Time Parser
│   │   └── 负责识别“明天上午”“下周五”等自然语言时间
│   │
│   ├── Category Recommender
│   │   └── 负责推荐分类，例如学习、工作、购物、纪念日
│   │
│   ├── Reminder Recommender
│   │   └── 负责推荐提前多久提醒
│   │
│   └── Candidate Event Builder
│       └── 负责生成候选日程，等待用户确认
│
└── Optional Cloud Backend 可选云端
    ├── Auth
    │   └── 负责账号登录和身份验证
    │
    ├── Sync API
    │   └── 负责多设备数据同步
    │
    ├── Backup API
    │   └── 负责云端备份和恢复
    │
    ├── AI API Proxy
    │   └── 负责转发 AI 请求，隐藏密钥和控制成本
    │
    └── WeChat Push Gateway
        └── 负责服务端微信提醒推送
