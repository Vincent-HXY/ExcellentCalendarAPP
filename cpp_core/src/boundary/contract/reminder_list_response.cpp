#include "excellent_calendar/boundary/contract/reminder_list_response.hpp"

#include "excellent_calendar/boundary/contract/reminder_response.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value reminder_list_response_to_json(const application::ReminderListResult& result) {
  picojson::array items;
  items.reserve(result.items.size());
  for (const auto& reminder : result.items) {
    items.push_back(reminder_response_to_json(reminder));
  }

  picojson::object pagination;
  pagination["total"] = picojson::value(static_cast<double>(result.pagination.total));
  pagination["page"] = picojson::value(static_cast<double>(result.pagination.page));
  pagination["page_size"] = picojson::value(static_cast<double>(result.pagination.page_size));
  pagination["has_more"] = picojson::value(result.pagination.has_more);
  pagination["next_cursor"] = result.pagination.next_cursor.has_value()
                                   ? picojson::value(*result.pagination.next_cursor)
                                   : picojson::value();

  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  object["pagination"] = picojson::value(std::move(pagination));
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
