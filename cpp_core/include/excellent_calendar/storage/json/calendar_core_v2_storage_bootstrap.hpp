#pragma once

#include <filesystem>
#include <optional>
#include <string_view>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::storage::json {

struct CalendarCoreV2StoragePreparation {
  bool archived_v1 = false;
  std::optional<std::filesystem::path> archive_directory;
};

/**
 * Classifies the active Calendar Core directory before a v2 writer is opened.
 *
 * A confirmed v1 directory is moved as one directory entry to a timestamped
 * sibling. Confirmation is read-only and validates every present v1 data root,
 * entity record, and transaction-journal snapshot before the rename. It never
 * initializes a v1 repository or replays a journal. No records are migrated and
 * no v2 files are created here. Unknown, corrupted, or mixed-version directories
 * fail without being moved.
 */
common::Result<CalendarCoreV2StoragePreparation> prepare_calendar_core_v2_storage(
    const std::filesystem::path& active_directory,
    std::string_view archived_at_utc);

}  // namespace excellent_calendar::storage::json
