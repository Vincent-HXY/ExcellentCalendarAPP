// Isolated CT0 evidence: link the unchanged production Core, use only synthetic dirs.
#include <filesystem>
#include <iostream>
#include "picojson/picojson.h"
#include "excellent_calendar/storage/json/legacy_json_codec.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  namespace codec = excellent_calendar::storage::json;
  auto opened = SqliteCalendarDatabase::open(std::filesystem::u8path(argv[1]));
  if (!opened.ok()) {
    std::cout << "ERROR\t" << opened.error().code << '\n';
    return 0;
  }
  auto events = opened.value()->load_legacy_events();
  auto reminders = opened.value()->load_legacy_reminders();
  auto notifications = opened.value()->load_legacy_notifications();
  auto check = opened.value()->validate();
  if (!events.ok() || !reminders.ok() || !notifications.ok() || !check.ok()) return 3;
  picojson::object output;
  output["events"] = codec::encode_legacy_event_store(events.value());
  output["reminders"] = codec::encode_legacy_reminder_store(reminders.value());
  output["notifications"] = codec::encode_legacy_notification_store(notifications.value());
  picojson::array availability;
  for (const auto& event : events.value()) {
    picojson::object row;
    row["id"] = picojson::value(event.id);
    row["recurrence_revision_present"] = picojson::value(event.recurrence_revision.has_value());
    row["civil_date_range_present"] = picojson::value(event.start_date.has_value() && event.end_date.has_value());
    availability.emplace_back(row);
  }
  output["availability"] = picojson::value(availability);
  std::cout << picojson::value(output).serialize() << '\n';
}
