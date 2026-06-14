#pragma once

#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"

namespace excellent_calendar::repository {

/**
 * 事件仓库接口。
 *
 * 这是 C++ 里的抽象类：包含纯虚函数 `= 0`，不能直接实例化。
 * application 层依赖接口而不是 JSON 文件实现，因此以后可以替换成 SQLite、云同步缓存等。
 */
class EventRepository {
 public:
  /** 虚析构函数保证通过基类指针删除派生类对象时能正确释放资源。 */
  virtual ~EventRepository() = default;

  /** 保存一个事件并返回保存后的事件。 */
  virtual common::Result<domain::Event> create(const domain::Event& event) = 0;

  /** 按 id 查找事件；返回 nullopt 表示没有对应记录。 */
  virtual common::Result<std::optional<domain::Event>> find_by_id(std::string_view id) = 0;

  /** 读取所有事件；过滤和分页由 EventService 处理。 */
  virtual common::Result<std::vector<domain::Event>> find_all() = 0;
};

}  // namespace excellent_calendar::repository
