#pragma once

#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/notification.hpp"

namespace excellent_calendar::repository {

class NotificationRepository {
 public:
  virtual ~NotificationRepository() = default;

  virtual common::Result<domain::Notification> create(const domain::Notification& notification) = 0;

  virtual common::Result<std::optional<domain::Notification>> find_sent_by_reminder_id(
      std::string_view reminder_id) = 0;

  virtual common::Result<std::vector<domain::Notification>> find_all() = 0;
};

}  // namespace excellent_calendar::repository
