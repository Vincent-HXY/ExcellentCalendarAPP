#pragma once

#include <filesystem>
#include <mutex>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {

/**
 * 基于 JSON 文件的事件仓库实现。
 *
 * 这是 repository::EventRepository 的一个具体实现。它把所有事件保存到
 * `storage_directory/events.json` 中，并用 mutex 保护并发读写。
 */
class JsonEventRepository final : public repository::EventRepository {
 public:
  /** explicit 防止 std::filesystem::path 被隐式转换成仓库对象。 */
  explicit JsonEventRepository(std::filesystem::path storage_directory);

  /** 创建目录并检查目录可写。 */
  common::Result<common::Unit> initialize();

  /** 追加保存一个事件。内部会读全量 JSON、追加、再写回文件。 */
  common::Result<domain::Event> create(const domain::Event& event) override;

  /** 按 id 查找事件。 */
  common::Result<std::optional<domain::Event>> find_by_id(std::string_view id) override;

  /** 读取全部事件。 */
  common::Result<std::vector<domain::Event>> find_all() override;

  /** 返回当前仓库使用的存储目录。 */
  const std::filesystem::path& storage_directory() const { return store_.storage_directory(); }

 private:
  /** 读取 events.json。调用者必须已经持有 mutex_，所以函数名带 locked。 */
  common::Result<std::vector<domain::Event>> load_events_locked();

  /** 保存 events.json。调用者必须已经持有 mutex_。 */
  common::Result<common::Unit> save_events_locked(const std::vector<domain::Event>& events);

  AtomicJsonFileStore store_;
  /** mutable 允许 const 成员函数未来也能加锁；当前主要保护 create/find_all/initialize。 */
  mutable std::mutex mutex_;
};

}  // namespace excellent_calendar::storage::json
