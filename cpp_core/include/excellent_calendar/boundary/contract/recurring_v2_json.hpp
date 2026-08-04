#pragma once

#include <string>

#include <picojson/picojson.h>

#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"

namespace excellent_calendar::boundary::contract {

std::string native_success_json_v2(
    const picojson::value& data,
    const std::string& request_id);
std::string native_failure_json_v2(
    const common::Error& error,
    const std::string& request_id);

picojson::value event_response_v2_to_json(const domain::Event& event);
picojson::value recurrence_response_v2_to_json(const domain::Recurrence& recurrence);
picojson::value occurrence_state_response_v2_to_json(
    const domain::EventOccurrenceState& state);
picojson::value occurrence_projection_v2_to_json(
    const application::EventOccurrenceProjection& projection);
picojson::value occurrence_page_v2_to_json(
    const application::EventOccurrencePage& page);
picojson::value reminder_response_v2_to_json(const domain::Reminder& reminder);
picojson::value schedulable_reminder_page_v2_to_json(
    const application::RecurringSchedulableReminderPage& page);
picojson::value notification_response_v2_to_json(
    const domain::Notification& notification);
picojson::value recovery_batch_response_v2_to_json(
    const domain::ReminderRecoveryBatch& batch);
picojson::value prepare_delivery_response_v2_to_json(
    const application::PrepareDeliveryResult& result);
picojson::value finalize_delivery_response_v2_to_json(
    const application::FinalizeDeliveryResult& result);
picojson::value plan_recovery_response_v2_to_json(
    const application::PlanReminderRecoveryResult& result);

}  // namespace excellent_calendar::boundary::contract
