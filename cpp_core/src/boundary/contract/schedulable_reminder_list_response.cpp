#include "excellent_calendar/boundary/contract/schedulable_reminder_list_response.hpp"

namespace excellent_calendar::boundary::contract {

SchedulableReminderListResponse make_schedulable_reminder_list_response(
    const application::SchedulableReminderListResult& result) {
  SchedulableReminderListResponse response;
  response.items.reserve(result.items.size());
  for (const auto& reminder : result.items) {
    response.items.push_back(make_reminder_response(reminder));
  }
  response.selected_count = static_cast<int>(response.items.size());
  response.has_more = result.has_more;
  response.unsupported_reminder_ids = result.unsupported_reminder_ids;
  return response;
}

picojson::value schedulable_reminder_list_response_to_json(
    const SchedulableReminderListResponse& response) {
  picojson::array items;
  for (const auto& reminder : response.items) {
    items.push_back(reminder_response_to_json(reminder));
  }
  picojson::array unsupported;
  for (const auto& id : response.unsupported_reminder_ids) {
    unsupported.push_back(picojson::value(id));
  }
  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  object["selected_count"] = picojson::value(static_cast<double>(response.selected_count));
  object["has_more"] = picojson::value(response.has_more);
  object["unsupported_reminder_ids"] = picojson::value(std::move(unsupported));
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
