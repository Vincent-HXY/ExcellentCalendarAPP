#pragma once

#include <memory>
#include <string>
#include <string_view>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/application/create_event_workflow_service.hpp"
#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::boundary::api {

common::Result<common::Unit> initialize_runtime(std::string_view storage_directory);

std::shared_ptr<application::EventService> current_event_service();

std::shared_ptr<application::CreateEventWorkflowService> current_create_event_workflow_service();

std::shared_ptr<application::ReminderService> current_reminder_service();

std::shared_ptr<application::NotificationService> current_notification_service();

common::Error storage_not_initialized_error(std::string operation);

std::string current_storage_directory();

}  // namespace excellent_calendar::boundary::api
