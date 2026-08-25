#pragma once

#include <filesystem>
#include <functional>
#include <string_view>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::storage::json {

struct CalendarCoreV3StoragePreparation {
  bool migrated = false;
  bool resumed = false;
  bool already_migrated = false;
};

using StorageMigrationFailureHook =
    std::function<common::Result<common::Unit>(std::string_view phase)>;

common::Result<CalendarCoreV3StoragePreparation>
prepare_calendar_core_v3_storage(
    const std::filesystem::path& active_directory,
    StorageMigrationFailureHook failure_hook = {});

}  // namespace excellent_calendar::storage::json
