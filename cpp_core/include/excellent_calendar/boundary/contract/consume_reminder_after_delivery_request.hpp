#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::boundary::contract {

struct ConsumeReminderAfterDeliveryRequest {
  std::string reminder_id;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::string sent_at;
  bool delete_after_sent = true;
};

}  // namespace excellent_calendar::boundary::contract
