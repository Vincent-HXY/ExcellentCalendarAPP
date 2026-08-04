#pragma once

#include <memory>
#include <string>
#include <string_view>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/application/create_event_workflow_service.hpp"
#include "excellent_calendar/application/event_lifecycle_workflow_service.hpp"
#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/application/reminder_service_v2.hpp"
#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_event_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::boundary::api {

common::Result<common::Unit> initialize_runtime(std::string_view storage_directory);

struct RecurringRuntimeInitializationResult {
  bool initialized = false;
  int storage_format_version = 0;
  std::string tzdb_version;
};

common::Result<RecurringRuntimeInitializationResult> initialize_recurring_runtime(
    std::string_view storage_directory,
    std::string_view tzdb_directory);

std::shared_ptr<application::EventService> current_event_service();

std::shared_ptr<application::CreateEventWorkflowService> current_create_event_workflow_service();

std::shared_ptr<application::EventLifecycleWorkflowService> current_event_lifecycle_workflow_service();

std::shared_ptr<application::ReminderService> current_reminder_service();

std::shared_ptr<application::NotificationService> current_notification_service();

std::shared_ptr<application::RecurringEventWorkflowService>
current_recurring_event_workflow_service();

std::shared_ptr<application::RecurringEventQueryService>
current_recurring_event_query_service();

std::shared_ptr<application::RecurringReminderDeliveryWorkflowService>
current_recurring_reminder_delivery_workflow_service();

std::shared_ptr<application::ReminderRecoveryWorkflowService>
current_reminder_recovery_workflow_service();

std::shared_ptr<application::RecurringReminderQueryService>
current_recurring_reminder_query_service();

std::shared_ptr<application::ReminderServiceV2> current_reminder_service_v2();

common::Error storage_not_initialized_error(std::string operation);

std::string current_storage_directory();

}  // namespace excellent_calendar::boundary::api
