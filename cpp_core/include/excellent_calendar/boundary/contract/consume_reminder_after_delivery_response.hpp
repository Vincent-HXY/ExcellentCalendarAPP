#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/boundary/contract/notification_response.hpp"
#include "excellent_calendar/boundary/contract/reminder_response.hpp"

namespace excellent_calendar::boundary::contract {

struct ConsumeReminderAfterDeliveryResponse {
  ReminderResponse reminder;
  NotificationResponse notification;
};

ConsumeReminderAfterDeliveryResponse make_consume_reminder_after_delivery_response(
    const application::ConsumeReminderAfterDeliveryResult& result);

picojson::value consume_reminder_after_delivery_response_to_json(
    const ConsumeReminderAfterDeliveryResponse& response);

}  // namespace excellent_calendar::boundary::contract
