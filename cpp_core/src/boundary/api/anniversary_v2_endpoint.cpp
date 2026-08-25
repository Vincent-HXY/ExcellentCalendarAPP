#include "excellent_calendar/boundary/api/anniversary_api.hpp"

#include <algorithm>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "recurring_v2_api_internal.hpp"
#include "excellent_calendar/application/anniversary_query_service.hpp"
#include "excellent_calendar/application/anniversary_workflow_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/anniversary_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::boundary::api {
namespace {

using detail::contract_error;
using detail::field;
using detail::nullable_int;
using detail::nullable_string;
using detail::parse_object;
using detail::reject_unknown;
using detail::require_int;
using detail::require_bool;
using detail::require_string;
using detail::respond_v2;
using detail::string_array;

common::Result<domain::LocalDate> required_date(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  auto value = require_string(object, key, parent);
  if (!value.ok()) return common::Result<domain::LocalDate>::failure(value.error());
  auto parsed = domain::parse_local_date(value.value());
  return parsed.ok()
             ? parsed
             : common::Result<domain::LocalDate>::failure(
                   contract_error(parent + "." + key, "date must be a valid YYYY-MM-DD"));
}

common::Result<bool> required_recurrence(
    const picojson::object& object,
    const std::string& parent) {
  const auto* value = field(object, "recurrence");
  if (value == nullptr) {
    return common::Result<bool>::failure(
        contract_error(parent + ".recurrence", "required nullable field is missing"));
  }
  if (value->is<picojson::null>()) return common::Result<bool>::success(false);
  if (!value->is<picojson::object>()) {
    return common::Result<bool>::failure(
        contract_error(parent + ".recurrence", "recurrence must be object or null"));
  }
  const auto& recurrence = value->get<picojson::object>();
  auto known = reject_unknown(
      recurrence, {"frequency", "interval"}, parent + ".recurrence");
  if (!known.ok()) return common::Result<bool>::failure(known.error());
  auto frequency = require_string(recurrence, "frequency", parent + ".recurrence");
  auto interval = require_int(recurrence, "interval", parent + ".recurrence");
  if (!frequency.ok()) return common::Result<bool>::failure(frequency.error());
  if (!interval.ok()) return common::Result<bool>::failure(interval.error());
  if (frequency.value() != "yearly" || interval.value() != 1) {
    return common::Result<bool>::failure(contract_error(
        parent + ".recurrence", "recurrence must be yearly with interval 1"));
  }
  return common::Result<bool>::success(true);
}

common::Result<application::AnniversaryWriteInput> write_input(
    const picojson::object& object,
    const std::string& parent,
    bool with_id) {
  std::set<std::string> allowed = {
      "title", "date", "calendar_type", "category_id", "recurrence",
      "note", "importance", "timezone", "reminder_plan"};
  if (with_id) {
    allowed.insert("id");
    allowed.insert("expected_updated_at");
  }
  auto known = reject_unknown(object, allowed, parent);
  if (!known.ok()) {
    return common::Result<application::AnniversaryWriteInput>::failure(known.error());
  }
  auto title = require_string(object, "title", parent);
  auto date = required_date(object, "date", parent);
  auto calendar = require_string(object, "calendar_type", parent);
  auto category = nullable_string(object, "category_id", parent, true);
  auto recurrence = required_recurrence(object, parent);
  auto note = nullable_string(object, "note", parent, true);
  auto importance = require_string(object, "importance", parent);
  auto timezone = require_string(object, "timezone", parent);
  if (!title.ok()) return common::Result<application::AnniversaryWriteInput>::failure(title.error());
  if (!date.ok()) return common::Result<application::AnniversaryWriteInput>::failure(date.error());
  if (!calendar.ok()) return common::Result<application::AnniversaryWriteInput>::failure(calendar.error());
  if (!category.ok()) return common::Result<application::AnniversaryWriteInput>::failure(category.error());
  if (!recurrence.ok()) return common::Result<application::AnniversaryWriteInput>::failure(recurrence.error());
  if (!note.ok()) return common::Result<application::AnniversaryWriteInput>::failure(note.error());
  if (!importance.ok()) return common::Result<application::AnniversaryWriteInput>::failure(importance.error());
  if (!timezone.ok()) return common::Result<application::AnniversaryWriteInput>::failure(timezone.error());
  if (calendar.value() != domain::kAnniversaryCalendarSolar &&
      calendar.value() != domain::kAnniversaryCalendarLunar) {
    return common::Result<application::AnniversaryWriteInput>::failure(
        contract_error(parent + ".calendar_type", "calendar_type is unknown"));
  }
  if (category.value().has_value() && !common::is_uuid(*category.value())) {
    return common::Result<application::AnniversaryWriteInput>::failure(
        contract_error(parent + ".category_id", "category_id must be a UUID or null"));
  }
  if (!domain::is_valid_importance(importance.value())) {
    return common::Result<application::AnniversaryWriteInput>::failure(
        contract_error(parent + ".importance", "importance is unknown"));
  }
  if (timezone.value().size() > 255U) {
    return common::Result<application::AnniversaryWriteInput>::failure(
        contract_error(parent + ".timezone", "timezone is too long"));
  }
  std::optional<application::AnniversaryReminderPlanInput> reminder_plan;
  if (const auto* plan_value = field(object, "reminder_plan"); plan_value != nullptr) {
    if (!plan_value->is<picojson::object>()) {
      return common::Result<application::AnniversaryWriteInput>::failure(
          contract_error(parent + ".reminder_plan", "reminder_plan must be object"));
    }
    const auto& plan_object = plan_value->get<picojson::object>();
    auto plan_known = reject_unknown(
        plan_object, {"reminders_enabled", "templates"}, parent + ".reminder_plan");
    if (!plan_known.ok()) {
      return common::Result<application::AnniversaryWriteInput>::failure(plan_known.error());
    }
    auto enabled = require_bool(
        plan_object, "reminders_enabled", parent + ".reminder_plan");
    const auto* templates_value = field(plan_object, "templates");
    if (!enabled.ok()) {
      return common::Result<application::AnniversaryWriteInput>::failure(enabled.error());
    }
    if (templates_value == nullptr || !templates_value->is<picojson::array>()) {
      return common::Result<application::AnniversaryWriteInput>::failure(
          contract_error(parent + ".reminder_plan.templates", "templates must be array"));
    }
    application::AnniversaryReminderPlanInput parsed_plan;
    parsed_plan.reminders_enabled = enabled.value();
    const auto& templates = templates_value->get<picojson::array>();
    if (templates.size() > 5U) {
      return common::Result<application::AnniversaryWriteInput>::failure(common::make_error(
          "ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED",
          "Anniversary reminder plan contains more than five templates"));
    }
    for (std::size_t index = 0; index < templates.size(); ++index) {
      const auto template_parent = parent + ".reminder_plan.templates[" +
                                   std::to_string(index) + "]";
      if (!templates[index].is<picojson::object>()) {
        return common::Result<application::AnniversaryWriteInput>::failure(
            contract_error(template_parent, "template must be object"));
      }
      const auto& item = templates[index].get<picojson::object>();
      auto item_known = reject_unknown(
          item, {"advance_days", "local_time", "method", "is_enabled"},
          template_parent);
      if (!item_known.ok()) {
        return common::Result<application::AnniversaryWriteInput>::failure(item_known.error());
      }
      auto advance_days = require_int(item, "advance_days", template_parent);
      auto local_time = require_string(item, "local_time", template_parent);
      auto method = require_string(item, "method", template_parent);
      auto item_enabled = require_bool(item, "is_enabled", template_parent);
      if (!advance_days.ok()) return common::Result<application::AnniversaryWriteInput>::failure(advance_days.error());
      if (!local_time.ok()) return common::Result<application::AnniversaryWriteInput>::failure(local_time.error());
      if (!method.ok()) return common::Result<application::AnniversaryWriteInput>::failure(method.error());
      if (!item_enabled.ok()) return common::Result<application::AnniversaryWriteInput>::failure(item_enabled.error());
      parsed_plan.templates.push_back({advance_days.value(), local_time.value(),
                                       method.value(), item_enabled.value()});
    }
    reminder_plan = std::move(parsed_plan);
  }
  return common::Result<application::AnniversaryWriteInput>::success(
      application::AnniversaryWriteInput{
          title.value(), date.value(), calendar.value(), category.value(),
          recurrence.value(), note.value(), importance.value(), timezone.value(),
          reminder_plan});
}

common::Result<std::optional<std::string>> optional_nonnull_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key, "field must be string"));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<application::ListAnniversariesQuery> parse_list_query(
    const picojson::object& object) {
  constexpr const char* parent = "ListAnniversariesRequest";
  auto known = reject_unknown(
      object,
      {"timezone", "category_ids", "importance", "pagination", "sort_by",
       "sort_direction"},
      parent);
  if (!known.ok()) {
    return common::Result<application::ListAnniversariesQuery>::failure(known.error());
  }
  auto timezone = require_string(object, "timezone", parent);
  auto categories = string_array(object, "category_ids", parent, false, true);
  auto importance = string_array(object, "importance", parent, false, true);
  auto top_sort = optional_nonnull_string(object, "sort_by", parent);
  auto top_direction = optional_nonnull_string(object, "sort_direction", parent);
  if (!timezone.ok()) return common::Result<application::ListAnniversariesQuery>::failure(timezone.error());
  if (!categories.ok()) return common::Result<application::ListAnniversariesQuery>::failure(categories.error());
  if (!importance.ok()) return common::Result<application::ListAnniversariesQuery>::failure(importance.error());
  if (!top_sort.ok()) return common::Result<application::ListAnniversariesQuery>::failure(top_sort.error());
  if (!top_direction.ok()) return common::Result<application::ListAnniversariesQuery>::failure(top_direction.error());
  if (timezone.value().size() > 255U) {
    return common::Result<application::ListAnniversariesQuery>::failure(
        contract_error("ListAnniversariesRequest.timezone", "timezone is too long"));
  }
  if (field(object, "category_ids") != nullptr && categories.value().empty()) {
    return common::Result<application::ListAnniversariesQuery>::failure(
        contract_error("ListAnniversariesRequest.category_ids", "array must not be empty"));
  }
  for (const auto& id : categories.value()) {
    if (!common::is_uuid(id)) {
      return common::Result<application::ListAnniversariesQuery>::failure(
          contract_error("ListAnniversariesRequest.category_ids", "array must contain UUIDs"));
    }
  }
  if (field(object, "importance") != nullptr && importance.value().empty()) {
    return common::Result<application::ListAnniversariesQuery>::failure(
        contract_error("ListAnniversariesRequest.importance", "array must not be empty"));
  }
  for (const auto& value : importance.value()) {
    if (!domain::is_valid_importance(value)) {
      return common::Result<application::ListAnniversariesQuery>::failure(
          contract_error("ListAnniversariesRequest.importance", "array contains unknown value"));
    }
  }

  application::ListAnniversariesQuery query;
  query.timezone = timezone.value();
  query.category_ids = std::move(categories.value());
  query.importance = std::move(importance.value());
  if (const auto* pagination_value = field(object, "pagination"); pagination_value != nullptr) {
    if (!pagination_value->is<picojson::object>()) {
      return common::Result<application::ListAnniversariesQuery>::failure(
          contract_error("ListAnniversariesRequest.pagination", "pagination must be object"));
    }
    const auto& pagination = pagination_value->get<picojson::object>();
    auto pagination_known = reject_unknown(
        pagination, {"page", "page_size", "cursor"},
        "ListAnniversariesRequest.pagination");
    if (!pagination_known.ok()) {
      return common::Result<application::ListAnniversariesQuery>::failure(
          pagination_known.error());
    }
    auto page = nullable_int(
        pagination, "page", "ListAnniversariesRequest.pagination", false);
    auto page_size = nullable_int(
        pagination, "page_size", "ListAnniversariesRequest.pagination", false);
    auto cursor = nullable_string(
        pagination, "cursor", "ListAnniversariesRequest.pagination", false);
    if (!page.ok()) return common::Result<application::ListAnniversariesQuery>::failure(page.error());
    if (!page_size.ok()) return common::Result<application::ListAnniversariesQuery>::failure(page_size.error());
    if (!cursor.ok()) return common::Result<application::ListAnniversariesQuery>::failure(cursor.error());
    if (page.value().has_value()) query.page = *page.value();
    if (page_size.value().has_value()) query.page_size = *page_size.value();
    query.cursor = cursor.value();
  }
  query.sort_by = top_sort.value().value_or("target_occurrence_date");
  query.sort_direction = top_direction.value().value_or("asc");
  if ((query.sort_by != "target_occurrence_date" && query.sort_by != "countdown_days") ||
      (query.sort_direction != "asc" && query.sort_direction != "desc")) {
    return common::Result<application::ListAnniversariesQuery>::failure(
        contract_error("ListAnniversariesRequest.sort", "sort is invalid"));
  }
  return common::Result<application::ListAnniversariesQuery>::success(std::move(query));
}

}  // namespace

std::string create_anniversary_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto input = write_input(parsed.value(), "CreateAnniversaryRequest", false);
    if (!input.ok()) return common::Result<picojson::value>::failure(input.error());
    const auto service = current_anniversary_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.create"));
    }
    auto result = service->create(application::CreateAnniversaryCommand{input.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_detail_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string update_anniversary_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto input = write_input(parsed.value(), "UpdateAnniversaryRequest", true);
    if (!input.ok()) return common::Result<picojson::value>::failure(input.error());
    auto id = require_string(parsed.value(), "id", "UpdateAnniversaryRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    auto expected_updated_at = require_string(
        parsed.value(), "expected_updated_at", "UpdateAnniversaryRequest");
    if (!expected_updated_at.ok()) {
      return common::Result<picojson::value>::failure(expected_updated_at.error());
    }
    if (!common::is_uuid(id.value())) {
      return common::Result<picojson::value>::failure(
          contract_error("UpdateAnniversaryRequest.id", "id must be a UUID"));
    }
    if (!common::is_iso8601_utc_datetime(expected_updated_at.value())) {
      return common::Result<picojson::value>::failure(contract_error(
          "UpdateAnniversaryRequest.expected_updated_at",
          "expected_updated_at must be a UTC date-time"));
    }
    const auto service = current_anniversary_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.update"));
    }
    auto result = service->update(
        application::UpdateAnniversaryCommand{
            id.value(), expected_updated_at.value(), input.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_detail_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string delete_anniversary_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"id"}, "DeleteAnniversaryRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "id", "DeleteAnniversaryRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    if (!common::is_uuid(id.value())) {
      return common::Result<picojson::value>::failure(
          contract_error("DeleteAnniversaryRequest.id", "id must be a UUID"));
    }
    const auto service = current_anniversary_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.delete"));
    }
    auto result = service->remove(application::DeleteAnniversaryCommand{id.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_delete_commit_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string get_anniversary_detail_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"id", "timezone"}, "GetAnniversaryDetailRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "id", "GetAnniversaryDetailRequest");
    auto timezone = require_string(
        parsed.value(), "timezone", "GetAnniversaryDetailRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if (!common::is_uuid(id.value()) || timezone.value().size() > 255U) {
      return common::Result<picojson::value>::failure(contract_error(
          "GetAnniversaryDetailRequest", "id or timezone is invalid"));
    }
    const auto service = current_anniversary_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.detail"));
    }
    auto result = service->detail(
        application::GetAnniversaryDetailQuery{id.value(), timezone.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_detail_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string list_anniversaries_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto query = parse_list_query(parsed.value());
    if (!query.ok()) return common::Result<picojson::value>::failure(query.error());
    const auto service = current_anniversary_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.list"));
    }
    auto result = service->list(query.value());
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_list_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string preview_anniversary_countdown_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"date", "calendar_type", "recurrence", "timezone"},
        "PreviewAnniversaryCountdownRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto date = required_date(
        parsed.value(), "date", "PreviewAnniversaryCountdownRequest");
    auto calendar = require_string(
        parsed.value(), "calendar_type", "PreviewAnniversaryCountdownRequest");
    auto recurrence = required_recurrence(
        parsed.value(), "PreviewAnniversaryCountdownRequest");
    auto timezone = require_string(
        parsed.value(), "timezone", "PreviewAnniversaryCountdownRequest");
    if (!date.ok()) return common::Result<picojson::value>::failure(date.error());
    if (!calendar.ok()) return common::Result<picojson::value>::failure(calendar.error());
    if (!recurrence.ok()) return common::Result<picojson::value>::failure(recurrence.error());
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if ((calendar.value() != domain::kAnniversaryCalendarSolar &&
         calendar.value() != domain::kAnniversaryCalendarLunar) ||
        timezone.value().size() > 255U) {
      return common::Result<picojson::value>::failure(contract_error(
          "PreviewAnniversaryCountdownRequest", "calendar_type or timezone is invalid"));
    }
    const auto service = current_anniversary_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.preview_countdown"));
    }
    auto result = service->preview(application::PreviewAnniversaryCountdownQuery{
        date.value(), calendar.value(), recurrence.value(), timezone.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_countdown_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string set_anniversary_reminders_enabled_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"id", "reminders_enabled", "timezone"},
                                "SetAnniversaryRemindersEnabledRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "id", "SetAnniversaryRemindersEnabledRequest");
    auto enabled = require_bool(parsed.value(), "reminders_enabled",
                                "SetAnniversaryRemindersEnabledRequest");
    auto timezone = require_string(parsed.value(), "timezone",
                                   "SetAnniversaryRemindersEnabledRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    if (!enabled.ok()) return common::Result<picojson::value>::failure(enabled.error());
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if (!common::is_uuid(id.value()) || timezone.value().size() > 255U) {
      return common::Result<picojson::value>::failure(contract_error(
          "SetAnniversaryRemindersEnabledRequest", "id or timezone is invalid"));
    }
    const auto service = current_anniversary_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.set_reminders_enabled"));
    }
    auto result = service->set_reminders_enabled(
        {id.value(), enabled.value(), timezone.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_detail_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

std::string list_anniversary_occurrences_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    constexpr const char* parent = "ListAnniversaryOccurrencesRequest";
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"range_start_date", "range_end_date", "timezone", "category_ids",
                         "importance", "cursor", "page_size"}, parent);
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto start = required_date(parsed.value(), "range_start_date", parent);
    auto end = required_date(parsed.value(), "range_end_date", parent);
    auto timezone = require_string(parsed.value(), "timezone", parent);
    auto categories = string_array(parsed.value(), "category_ids", parent, true, true);
    auto importance = string_array(parsed.value(), "importance", parent, true, true);
    auto cursor = nullable_string(parsed.value(), "cursor", parent, true);
    auto page_size = require_int(parsed.value(), "page_size", parent);
    if (!start.ok()) return common::Result<picojson::value>::failure(start.error());
    if (!end.ok()) return common::Result<picojson::value>::failure(end.error());
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if (!categories.ok()) return common::Result<picojson::value>::failure(categories.error());
    if (!importance.ok()) return common::Result<picojson::value>::failure(importance.error());
    if (!cursor.ok()) return common::Result<picojson::value>::failure(cursor.error());
    if (!page_size.ok()) return common::Result<picojson::value>::failure(page_size.error());
    const auto service = current_anniversary_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("anniversary.list_occurrences"));
    }
    auto result = service->list_occurrences({start.value(), end.value(), timezone.value(),
                                             categories.value(), importance.value(),
                                             cursor.value(), page_size.value()});
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::anniversary_occurrence_list_response_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

}  // namespace excellent_calendar::boundary::api
