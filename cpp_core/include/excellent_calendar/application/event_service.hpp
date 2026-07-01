#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/repository/event_repository.hpp"

namespace excellent_calendar::application {

/** 创建事件用的命令对象，由 boundary 层解析 JSON 后得到。 */
struct CreateEventCommand {
  std::string title;
  std::optional<std::string> content;
  std::string start_at;
  std::string end_at;
  bool is_all_day = false;
  std::optional<std::string> category_id;
  std::optional<std::string> importance;
  std::optional<std::string> location;
  std::optional<std::string> timezone;
  std::string source;
};

/** 分页请求。当前使用 page/page_size 形式，page 从 1 开始。 */
struct PaginationRequest {
  int page = 1;
  int page_size = 20;
};

/** 搜索事件的查询条件。空 optional/空 vector 表示不使用该过滤条件。 */
struct EventQuery {
  std::optional<std::string> keyword;
  std::optional<std::string> start_at_from;
  std::optional<std::string> start_at_to;
  /** 空数组表示使用默认状态 active；非空数组表示显式状态过滤。 */
  std::vector<std::string> status;
  std::vector<std::string> category_ids;
  std::vector<std::string> importance;
  std::optional<std::string> location;
  std::optional<bool> has_recurrence;
  std::vector<std::string> source;
  bool include_deleted = false;
  PaginationRequest pagination;
  std::string sort_by = "start_at";
  std::string sort_direction = "asc";
};

struct CompleteEventCommand {
  std::string event_id;
  std::string completed_at;
  std::string source;
  std::optional<std::string> note;
};

struct ReopenEventCommand {
  std::string event_id;
};

/** 分页响应。next_cursor 为将来 cursor 分页预留，当前通常为空。 */
struct PaginationResponse {
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

/** 搜索结果：当前页事件列表和分页信息。 */
struct EventSearchResult {
  std::vector<domain::Event> items;
  PaginationResponse pagination;
};

/**
 * 事件应用服务。
 *
 * application 层承载业务规则：例如标题不能为空、开始时间早于结束时间、
 * 搜索条件是否合法、如何过滤排序分页。它通过 repository 接口读写数据，
 * 因此不依赖具体的 JSON 文件实现。
 */
class EventService {
 public:
  /** 注入时钟函数，方便测试时固定时间。 */
  using ClockFn = std::function<std::string()>;
  /** 注入 id 生成函数，方便测试时固定 id。 */
  using IdGeneratorFn = std::function<std::string()>;

  /** 构造服务。shared_ptr 表示 repository 可以被多个对象共享持有。 */
  EventService(
      std::shared_ptr<repository::EventRepository> repository,
      ClockFn clock,
      IdGeneratorFn id_generator);

  /** 创建事件：校验业务规则，补齐 id/status/created_at 等字段，然后写入仓库。 */
  common::Result<domain::Event> create_event(const CreateEventCommand& command);

  /** 搜索事件：从仓库读取全部事件，再按 query 做过滤、排序和分页。 */
  common::Result<EventSearchResult> search_events(const EventQuery& query);

  /** 将单次事件标记为已完成。当前阶段不处理重复日程 occurrence。 */
  common::Result<domain::Event> complete_event(const CompleteEventCommand& command);

  /** 撤销单次事件的完成状态，让它回到 active。 */
  common::Result<domain::Event> reopen_event(const ReopenEventCommand& command);

 private:
  std::shared_ptr<repository::EventRepository> repository_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
