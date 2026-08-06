#include "excellent_calendar/boundary/contract/consume_reminder_after_delivery_response.hpp"

namespace excellent_calendar::boundary::contract {

ConsumeReminderAfterDeliveryResponse make_consume_reminder_after_delivery_response(
    const application::ConsumeReminderAfterDeliveryResult& result) {
  return ConsumeReminderAfterDeliveryResponse{
      make_reminder_response(result.reminder),
      make_notification_response(result.notification),
  };
}

picojson::value consume_reminder_after_delivery_response_to_json(
    const ConsumeReminderAfterDeliveryResponse& response) {
  picojson::object object;
  object["reminder"] = reminder_response_to_json(response.reminder);
  object["notification"] = notification_response_to_json(response.notification);
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
