#pragma once

#include <filesystem>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::storage::json {

struct CalendarCoreV2StoragePreparation {
  bool discarded_v1 = false;
};

/**
 * Classifies the active Calendar Core directory before a v2 writer is opened.
 *
 * A confirmed v1 directory is removed after read-only validation; V1 data is
 * not preserved. Confirmation validates every present v1 data root, entity
 * record, and transaction-journal snapshot before the removal. It never
 * initializes a v1 repository or replays a journal. No records are migrated and
 * no v2 files are created here. Unknown, corrupted, or mixed-version
 * directories fail without being removed.
 */
common::Result<CalendarCoreV2StoragePreparation> prepare_calendar_core_v2_storage(
    const std::filesystem::path& active_directory);

}  // namespace excellent_calendar::storage::json
