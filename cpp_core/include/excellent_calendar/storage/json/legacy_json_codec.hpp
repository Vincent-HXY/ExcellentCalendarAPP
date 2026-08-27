#pragma once

#include <picojson/picojson.h>

#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::storage::json {

// Frozen JSON v1 codecs used both by the legacy file repositories and by the
// SQLite v4 compatibility tables. Keeping one decoder prevents the migration
// from silently changing fields or accepting records the former repository
// would reject.
common::Result<std::vector<domain::Event>> decode_legacy_event_store(
    const picojson::value& root);
picojson::value encode_legacy_event_store(
    const std::vector<domain::Event>& events);

common::Result<std::vector<domain::Reminder>> decode_legacy_reminder_store(
    const picojson::value& root);
picojson::value encode_legacy_reminder_store(
    const std::vector<domain::Reminder>& reminders);

common::Result<std::vector<domain::Notification>>
decode_legacy_notification_store(const picojson::value& root);
picojson::value encode_legacy_notification_store(
    const std::vector<domain::Notification>& notifications);

}  // namespace excellent_calendar::storage::json
