#pragma once

#include <cstdint>
#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {

struct CalendarCoreV3StoreDefinition {
  const char* logical_name;
  const char* file_name;
  const char* collection_name;
};

const std::vector<CalendarCoreV3StoreDefinition>&
calendar_core_v3_data_stores();

class CalendarWorkflowCoordinator {
 public:
  using GenerationMap = std::map<std::string, std::int64_t>;
  using FailureHook =
      std::function<common::Result<common::Unit>(std::string_view phase)>;

  struct CommitRequest {
    std::string operation;
    std::string transaction_id;
    std::string prepared_at;
    GenerationMap before_generation;
    picojson::object after_stores;
  };

  explicit CalendarWorkflowCoordinator(
      std::filesystem::path storage_directory,
      FailureHook failure_hook = {});

  common::Result<common::Unit> initialize();
  common::Result<common::Unit> recover();
  common::Result<GenerationMap> load_generations();
  common::Result<common::Unit> execute(const CommitRequest& request);

  static picojson::value empty_journal();

 private:
  struct JournalState {
    GenerationMap generations;
    std::optional<picojson::object> transaction;
  };

  common::Result<JournalState> read_journal_locked() const;
  common::Result<common::Unit> recover_locked();
  common::Result<common::Unit> validate_candidate_locked(
      const picojson::object& after_stores) const;
  common::Result<common::Unit> apply_after_stores_locked(
      const picojson::object& after_stores,
      bool invoke_hooks) const;
  common::Result<common::Unit> call_hook(std::string_view phase) const;

  AtomicJsonFileStore store_;
  FailureHook failure_hook_;
};

common::Error calendar_workflow_commit_failed(std::string reason);
common::Error calendar_workflow_recovery_failed(std::string reason);

}  // namespace excellent_calendar::storage::json
