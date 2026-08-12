#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"

#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "recurring_v2_api_internal.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/reminder_service_v2.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::api {
namespace {

using detail::contract_error;
using detail::field;
using detail::nullable_bool;
using detail::nullable_int;
using detail::nullable_string;
using detail::parse_object;
using detail::reject_unknown;
using detail::require_bool;
using detail::require_int;
using detail::require_string;
using detail::respond_v2;
using detail::string_array;

common::Result<application::ListRecurringSchedulableRemindersCommand> parse_schedulable(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"from_at", "to_at", "cursor", "limit", "include_scheduled", "supported_methods"},
      "ListSchedulableRemindersRequest");
  if (!known.ok()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(known.error());
  }
  application::ListRecurringSchedulableRemindersCommand command;
  auto from = nullable_string(object, "from_at", "ListSchedulableRemindersRequest", false);
  auto to = nullable_string(object, "to_at", "ListSchedulableRemindersRequest", false);
  if (!from.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(from.error());
  if (!to.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(to.error());
  command.from_at = from.value();
  command.to_at = to.value();
  if (const auto* value = field(object, "limit"); value != nullptr) {
    auto limit = require_int(object, "limit", "ListSchedulableRemindersRequest");
    if (!limit.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(limit.error());
    command.limit = limit.value();
  }
  if (const auto* value = field(object, "include_scheduled"); value != nullptr) {
    auto include = require_bool(object, "include_scheduled", "ListSchedulableRemindersRequest");
    if (!include.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(include.error());
    command.include_scheduled = include.value();
  }
  const auto* methods = field(object, "supported_methods");
  if (methods == nullptr || !methods->is<picojson::array>()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
        contract_error("ListSchedulableRemindersRequest.supported_methods", "array is required"));
  }
  for (const auto& value : methods->get<picojson::array>()) {
    if (!value.is<std::string>()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
          contract_error("ListSchedulableRemindersRequest.supported_methods", "items must be strings"));
    }
    command.supported_methods.push_back(value.get<std::string>());
  }
  if (const auto* cursor = field(object, "cursor"); cursor != nullptr && !cursor->is<picojson::null>()) {
    if (!cursor->is<picojson::object>()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
          contract_error("ListSchedulableRemindersRequest.cursor", "cursor must be object or null"));
    }
    auto cursor_known = reject_unknown(
        cursor->get<picojson::object>(), {"remind_at", "reminder_id"},
        "ListSchedulableRemindersRequest.cursor");
    if (!cursor_known.ok()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(cursor_known.error());
    }
    auto remind_at = require_string(
        cursor->get<picojson::object>(), "remind_at", "ListSchedulableRemindersRequest.cursor");
    auto reminder_id = require_string(
        cursor->get<picojson::object>(), "reminder_id", "ListSchedulableRemindersRequest.cursor");
    if (!remind_at.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(remind_at.error());
    if (!reminder_id.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(reminder_id.error());
    command.cursor_remind_at = remind_at.value();
    command.cursor_reminder_id = reminder_id.value();
  }
  return common::Result<application::ListRecurringSchedulableRemindersCommand>::success(
      std::move(command));
}

common::Result<application::PrepareDeliveryCommand> parse_prepare(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object, {"kind", "reminder_id", "recovery_batch_id", "method", "expected_remind_at"},
      "PrepareDeliveryRequest");
  if (!known.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(known.error());
  auto kind = require_string(object, "kind", "PrepareDeliveryRequest");
  auto reminder_id = nullable_string(object, "reminder_id", "PrepareDeliveryRequest", true);
  auto batch_id = nullable_string(object, "recovery_batch_id", "PrepareDeliveryRequest", true);
  auto method = require_string(object, "method", "PrepareDeliveryRequest");
  auto remind_at = nullable_string(object, "expected_remind_at", "PrepareDeliveryRequest", true);
  if (!kind.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(kind.error());
  if (!reminder_id.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(reminder_id.error());
  if (!batch_id.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(batch_id.error());
  if (!method.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(method.error());
  if (!remind_at.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(remind_at.error());
  return common::Result<application::PrepareDeliveryCommand>::success(
      {kind.value(), reminder_id.value(), batch_id.value(), method.value(), remind_at.value()});
}

common::Result<application::FinalizeDeliveryCommand> parse_finalize(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object, {"delivery_attempt_id", "outcome", "failure_class", "error_code"},
      "FinalizeDeliveryRequest");
  if (!known.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(known.error());
  auto id = require_string(object, "delivery_attempt_id", "FinalizeDeliveryRequest");
  auto outcome = require_string(object, "outcome", "FinalizeDeliveryRequest");
  auto failure = nullable_string(object, "failure_class", "FinalizeDeliveryRequest", true);
  auto error = nullable_string(object, "error_code", "FinalizeDeliveryRequest", true);
  if (!id.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(id.error());
  if (!outcome.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(outcome.error());
  if (!failure.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(failure.error());
  if (!error.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(error.error());
  return common::Result<application::FinalizeDeliveryCommand>::success(
      {id.value(), outcome.value(), failure.value(), error.value()});
}

common::Result<application::CreateReminderV2Command> parse_create_reminder(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"target_type", "target_id", "remind_at", "advance_minutes", "methods",
       "message", "is_enabled", "source"},
      "CreateReminderRequest");
  if (!known.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        known.error());
  }
  auto target_type = require_string(object, "target_type", "CreateReminderRequest");
  auto target_id = require_string(object, "target_id", "CreateReminderRequest");
  auto remind_at = nullable_string(
      object, "remind_at", "CreateReminderRequest", false);
  auto advance = nullable_int(
      object, "advance_minutes", "CreateReminderRequest", false);
  auto methods = string_array(
      object, "methods", "CreateReminderRequest", true, true);
  auto message = nullable_string(
      object, "message", "CreateReminderRequest", false);
  auto enabled = require_bool(object, "is_enabled", "CreateReminderRequest");
  auto source = require_string(object, "source", "CreateReminderRequest");
  if (!target_type.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        target_type.error());
  }
  if (!target_id.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        target_id.error());
  }
  if (!remind_at.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        remind_at.error());
  }
  if (!advance.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        advance.error());
  }
  if (!methods.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        methods.error());
  }
  if (!message.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        message.error());
  }
  if (!enabled.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        enabled.error());
  }
  if (!source.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        source.error());
  }
  if (remind_at.value().has_value() == advance.value().has_value()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        contract_error(
            "CreateReminderRequest", "exactly one reminder time mode is required"));
  }
  return common::Result<application::CreateReminderV2Command>::success(
      {target_type.value(), target_id.value(), remind_at.value(), advance.value(),
       std::move(methods.value()), message.value(), enabled.value(), source.value()});
}

common::Result<application::UpdateReminderV2Command> parse_update_reminder(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"reminder_id", "target_type", "target_id", "remind_at", "advance_minutes",
       "methods", "message", "source"},
      "UpdateReminderRequest");
  if (!known.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        known.error());
  }
  auto reminder_id = require_string(
      object, "reminder_id", "UpdateReminderRequest");
  if (!reminder_id.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        reminder_id.error());
  }
  application::UpdateReminderV2Command command;
  command.reminder_id = reminder_id.value();
  if (field(object, "target_type") != nullptr) {
    auto value = require_string(object, "target_type", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.target_type = {true, value.value()};
  }
  if (field(object, "target_id") != nullptr) {
    auto value = require_string(object, "target_id", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.target_id = {true, value.value()};
  }
  if (field(object, "remind_at") != nullptr) {
    auto value = nullable_string(
        object, "remind_at", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.remind_at = {true, value.value()};
  }
  if (field(object, "advance_minutes") != nullptr) {
    auto value = nullable_int(
        object, "advance_minutes", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.advance_minutes = {true, value.value()};
  }
  if (field(object, "methods") != nullptr) {
    auto value = string_array(
        object, "methods", "UpdateReminderRequest", true, true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.methods = {true, std::move(value.value())};
  }
  if (field(object, "message") != nullptr) {
    auto value = nullable_string(
        object, "message", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.message = {true, value.value()};
  }
  if (field(object, "source") != nullptr) {
    auto value = require_string(object, "source", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.source = {true, value.value()};
  }
  return common::Result<application::UpdateReminderV2Command>::success(
      std::move(command));
}

common::Result<application::ReminderIdV2Command> parse_reminder_id(
    std::string_view request_json,
    const std::string& parent) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(parsed.error());
  }
  auto known = reject_unknown(parsed.value(), {"reminder_id"}, parent);
  if (!known.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(known.error());
  }
  auto reminder_id = require_string(parsed.value(), "reminder_id", parent);
  if (!reminder_id.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(
        reminder_id.error());
  }
  return common::Result<application::ReminderIdV2Command>::success(
      {reminder_id.value()});
}

common::Result<application::ReminderListQueryV2> parse_reminder_list(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderListQueryV2>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"target_type", "target_id", "recurrence_revision", "occurrence_key",
       "remind_at_from", "remind_at_to", "methods", "status", "is_enabled",
       "include_deleted", "pagination", "sort_by", "sort_direction"},
      "ListRemindersRequest");
  if (!known.ok()) {
    return common::Result<application::ReminderListQueryV2>::failure(known.error());
  }
  application::ReminderListQueryV2 query;
  auto target_type = nullable_string(
      object, "target_type", "ListRemindersRequest", false);
  auto target_id = nullable_string(
      object, "target_id", "ListRemindersRequest", false);
  auto revision = nullable_int(
      object, "recurrence_revision", "ListRemindersRequest", false);
  auto occurrence_key = nullable_string(
      object, "occurrence_key", "ListRemindersRequest", false);
  auto remind_at_from = nullable_string(
      object, "remind_at_from", "ListRemindersRequest", false);
  auto remind_at_to = nullable_string(
      object, "remind_at_to", "ListRemindersRequest", false);
  auto methods = string_array(object, "methods", "ListRemindersRequest");
  auto status = string_array(object, "status", "ListRemindersRequest");
  auto enabled = nullable_bool(
      object, "is_enabled", "ListRemindersRequest", false);
  if (!target_type.ok()) return common::Result<application::ReminderListQueryV2>::failure(target_type.error());
  if (!target_id.ok()) return common::Result<application::ReminderListQueryV2>::failure(target_id.error());
  if (!revision.ok()) return common::Result<application::ReminderListQueryV2>::failure(revision.error());
  if (!occurrence_key.ok()) return common::Result<application::ReminderListQueryV2>::failure(occurrence_key.error());
  if (!remind_at_from.ok()) return common::Result<application::ReminderListQueryV2>::failure(remind_at_from.error());
  if (!remind_at_to.ok()) return common::Result<application::ReminderListQueryV2>::failure(remind_at_to.error());
  if (!methods.ok()) return common::Result<application::ReminderListQueryV2>::failure(methods.error());
  if (!status.ok()) return common::Result<application::ReminderListQueryV2>::failure(status.error());
  if (!enabled.ok()) return common::Result<application::ReminderListQueryV2>::failure(enabled.error());
  query.target_type = target_type.value();
  query.target_id = target_id.value();
  query.recurrence_revision = revision.value();
  query.occurrence_key = occurrence_key.value();
  query.remind_at_from = remind_at_from.value();
  query.remind_at_to = remind_at_to.value();
  query.methods = std::move(methods.value());
  query.status = std::move(status.value());
  query.is_enabled = enabled.value();
  if (field(object, "include_deleted") != nullptr) {
    auto value = require_bool(object, "include_deleted", "ListRemindersRequest");
    if (!value.ok()) return common::Result<application::ReminderListQueryV2>::failure(value.error());
    query.include_deleted = value.value();
  }
  if (const auto* pagination = field(object, "pagination"); pagination != nullptr) {
    if (!pagination->is<picojson::object>()) {
      return common::Result<application::ReminderListQueryV2>::failure(
          contract_error("ListRemindersRequest.pagination", "pagination must be an object"));
    }
    const auto& value = pagination->get<picojson::object>();
    auto pagination_known = reject_unknown(
        value, {"page", "page_size", "cursor", "sort_by", "sort_direction"},
        "ListRemindersRequest.pagination");
    if (!pagination_known.ok()) {
      return common::Result<application::ReminderListQueryV2>::failure(
          pagination_known.error());
    }
    if (field(value, "page") != nullptr && !field(value, "page")->is<picojson::null>()) {
      auto page = require_int(value, "page", "ListRemindersRequest.pagination");
      if (!page.ok()) return common::Result<application::ReminderListQueryV2>::failure(page.error());
      query.page = page.value();
    }
    if (field(value, "page_size") != nullptr &&
        !field(value, "page_size")->is<picojson::null>()) {
      auto page_size = require_int(
          value, "page_size", "ListRemindersRequest.pagination");
      if (!page_size.ok()) return common::Result<application::ReminderListQueryV2>::failure(page_size.error());
      query.page_size = page_size.value();
    }
    auto cursor = nullable_string(
        value, "cursor", "ListRemindersRequest.pagination", false);
    auto nested_sort = nullable_string(
        value, "sort_by", "ListRemindersRequest.pagination", false);
    auto nested_direction = nullable_string(
        value, "sort_direction", "ListRemindersRequest.pagination", false);
    if (!cursor.ok()) return common::Result<application::ReminderListQueryV2>::failure(cursor.error());
    if (!nested_sort.ok()) return common::Result<application::ReminderListQueryV2>::failure(nested_sort.error());
    if (!nested_direction.ok()) return common::Result<application::ReminderListQueryV2>::failure(nested_direction.error());
    query.cursor = cursor.value();
    if (nested_sort.value().has_value()) query.sort_by = *nested_sort.value();
    if (nested_direction.value().has_value()) {
      query.sort_direction = *nested_direction.value();
    }
  }
  auto sort_by = nullable_string(
      object, "sort_by", "ListRemindersRequest", false);
  auto sort_direction = nullable_string(
      object, "sort_direction", "ListRemindersRequest", false);
  if (!sort_by.ok()) return common::Result<application::ReminderListQueryV2>::failure(sort_by.error());
  if (!sort_direction.ok()) return common::Result<application::ReminderListQueryV2>::failure(sort_direction.error());
  if (sort_by.value().has_value()) query.sort_by = *sort_by.value();
  if (sort_direction.value().has_value()) {
    query.sort_direction = *sort_direction.value();
  }
  return common::Result<application::ReminderListQueryV2>::success(std::move(query));
}

}  // namespace

std::string create_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_create_reminder(request_json);
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.create"));
    }
    auto reminder = service->create(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string update_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_update_reminder(request_json);
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.update"));
    }
    auto reminder = service->update(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string cancel_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "CancelReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.cancel"));
    }
    auto reminder = service->cancel(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string list_reminders_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto query = parse_reminder_list(request_json);
    if (!query.ok()) {
      return common::Result<picojson::value>::failure(query.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.list"));
    }
    auto page = service->list(query.value());
    if (!page.ok()) return common::Result<picojson::value>::failure(page.error());
    picojson::array items;
    items.reserve(page.value().items.size());
    for (const auto& reminder : page.value().items) {
      items.push_back(contract::reminder_response_v2_to_json(reminder));
    }
    picojson::object pagination;
    pagination["total"] = picojson::value(static_cast<double>(page.value().total));
    pagination["page"] = picojson::value(static_cast<double>(page.value().page));
    pagination["page_size"] =
        picojson::value(static_cast<double>(page.value().page_size));
    pagination["has_more"] = picojson::value(page.value().has_more);
    pagination["next_cursor"] = page.value().next_cursor.has_value()
                                      ? picojson::value(*page.value().next_cursor)
                                      : picojson::value();
    picojson::object data;
    data["items"] = picojson::value(std::move(items));
    data["pagination"] = picojson::value(std::move(pagination));
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string enable_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "EnableReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.enable"));
    }
    auto reminder = service->enable(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string disable_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "DisableReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.disable"));
    }
    auto reminder = service->disable(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string list_schedulable_recurring_reminders_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_schedulable(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.list_schedulable"));
    }
    auto page = service->list_schedulable(command.value());
    return page.ok()
               ? common::Result<picojson::value>::success(
                     contract::schedulable_reminder_page_v2_to_json(page.value()))
               : common::Result<picojson::value>::failure(page.error());
  });
}

std::string get_recurring_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"reminder_id"}, "GetReminderRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "reminder_id", "GetReminderRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.get"));
    }
    auto reminder = service->get_reminder(id.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string mark_recurring_reminder_scheduled_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"reminder_id", "expected_remind_at", "scheduled_at"},
        "MarkReminderScheduledRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "reminder_id", "MarkReminderScheduledRequest");
    auto expected_remind_at = require_string(
        parsed.value(), "expected_remind_at", "MarkReminderScheduledRequest");
    auto scheduled_at = require_string(
        parsed.value(), "scheduled_at", "MarkReminderScheduledRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    if (!expected_remind_at.ok()) {
      return common::Result<picojson::value>::failure(expected_remind_at.error());
    }
    if (!scheduled_at.ok()) return common::Result<picojson::value>::failure(scheduled_at.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.mark_scheduled"));
    }
    auto reminder = service->mark_scheduled(
        {id.value(), expected_remind_at.value(), scheduled_at.value()});
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string prepare_recurring_reminder_delivery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_prepare(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_delivery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.prepare_delivery"));
    }
    auto prepared = service->prepare_delivery(command.value());
    return prepared.ok()
               ? common::Result<picojson::value>::success(
                     contract::prepare_delivery_response_v2_to_json(prepared.value()))
               : common::Result<picojson::value>::failure(prepared.error());
  });
}

std::string finalize_recurring_reminder_delivery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_finalize(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_delivery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.finalize_delivery"));
    }
    auto finalized = service->finalize_delivery(command.value());
    return finalized.ok()
               ? common::Result<picojson::value>::success(
                     contract::finalize_delivery_response_v2_to_json(finalized.value()))
               : common::Result<picojson::value>::failure(finalized.error());
  });
}

std::string plan_recurring_reminder_recovery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"recovery_request_id", "trigger_source"}, "PlanRecoveryRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto request_id = require_string(parsed.value(), "recovery_request_id", "PlanRecoveryRequest");
    auto source = require_string(parsed.value(), "trigger_source", "PlanRecoveryRequest");
    if (!request_id.ok()) return common::Result<picojson::value>::failure(request_id.error());
    if (!source.ok()) return common::Result<picojson::value>::failure(source.error());
    const auto service = current_reminder_recovery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.plan_recovery"));
    }
    auto planned = service->plan_recovery({request_id.value(), source.value()});
    return planned.ok()
               ? common::Result<picojson::value>::success(
                     contract::plan_recovery_response_v2_to_json(planned.value()))
               : common::Result<picojson::value>::failure(planned.error());
  });
}

}  // namespace excellent_calendar::boundary::api
