#include "excellent_calendar/application/anniversary_workflow_service.hpp"

#include <algorithm>
#include <optional>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace excellent_calendar::application {
namespace {

struct ProjectionContext {
  std::string now;
  domain::LocalDate today;
};

common::Error not_found(const std::string& id) {
  return common::make_error(
      "ANNIVERSARY_NOT_FOUND", "Anniversary not found", {{"id", id}});
}

common::Error corrupted(std::string reason) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
      {{"field", "anniversary"}, {"reason", std::move(reason)}});
}

common::Error internal(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

common::Result<ProjectionContext> projection_context(
    const std::shared_ptr<domain::LocalTimeResolver>& resolver,
    const AnniversaryWorkflowService::Clock& clock,
    const std::string& timezone) {
  if (!resolver || !clock) {
    return common::Result<ProjectionContext>::failure(
        internal("Anniversary projection dependencies are unavailable"));
  }
  if (timezone.empty()) {
    return common::Result<ProjectionContext>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "timezone"}, {"reason", "timezone is required"}}));
  }
  auto timezone_valid = resolver->validate_timezone(timezone);
  if (!timezone_valid.ok()) {
    return common::Result<ProjectionContext>::failure(timezone_valid.error());
  }
  const auto now = clock();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<ProjectionContext>::failure(
        internal("Anniversary Clock returned an invalid UTC instant"));
  }
  auto local = resolver->to_local(now, timezone);
  if (!local.ok()) return common::Result<ProjectionContext>::failure(local.error());
  return common::Result<ProjectionContext>::success(
      ProjectionContext{now, domain::LocalDate{
                                 local.value().year,
                                 local.value().month,
                                 local.value().day}});
}

common::Result<AnniversaryDetail> detail_for(
    const domain::Anniversary& anniversary,
    const std::optional<domain::AnniversaryRecurrence>& recurrence,
    const ProjectionContext& context,
    const std::string& timezone) {
  auto countdown = domain::calculate_anniversary_countdown(
      anniversary.date, recurrence.has_value(), context.today, timezone, context.now);
  if (!countdown.ok()) {
    return common::Result<AnniversaryDetail>::failure(countdown.error());
  }
  return common::Result<AnniversaryDetail>::success(
      AnniversaryDetail{anniversary, recurrence, countdown.value()});
}

}  // namespace

AnniversaryWorkflowService::AnniversaryWorkflowService(
    std::shared_ptr<repository::AnniversaryTransaction> transaction,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
    Clock clock,
    IdGenerator id_generator)
    : transaction_(std::move(transaction)),
      local_time_resolver_(std::move(local_time_resolver)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<AnniversaryDetail> AnniversaryWorkflowService::create(
    const CreateAnniversaryCommand& command) {
  if (!transaction_ || !id_generator_) {
    return common::Result<AnniversaryDetail>::failure(
        internal("Anniversary workflow dependencies are unavailable"));
  }
  auto valid = domain::validate_anniversary_input(
      command.input.title, command.input.date, command.input.calendar_type,
      command.input.category_id, command.input.importance);
  if (!valid.ok()) return common::Result<AnniversaryDetail>::failure(valid.error());
  auto context = projection_context(local_time_resolver_, clock_, command.input.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());

  const auto anniversary_id = id_generator_();
  const auto recurrence_id = command.input.repeats_yearly
                                 ? std::optional<std::string>(id_generator_())
                                 : std::nullopt;
  const auto transaction_id = id_generator_();
  if (!common::is_uuid(anniversary_id) ||
      (recurrence_id.has_value() && !common::is_uuid(*recurrence_id)) ||
      !common::is_uuid(transaction_id)) {
    return common::Result<AnniversaryDetail>::failure(
        internal("Anniversary ID generator returned an invalid UUID"));
  }

  domain::Anniversary created;
  std::optional<domain::AnniversaryRecurrence> created_recurrence;
  auto committed = transaction_->execute(
      "anniversary_create", transaction_id, context.value().now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        const bool anniversary_duplicate = std::any_of(
            state.anniversaries.begin(), state.anniversaries.end(),
            [&](const auto& value) { return value.id == anniversary_id; });
        const bool recurrence_duplicate = recurrence_id.has_value() && std::any_of(
            state.recurrences.begin(), state.recurrences.end(),
            [&](const auto& value) { return value.id == *recurrence_id; });
        if (anniversary_duplicate || recurrence_duplicate) {
          return common::Result<common::Unit>::failure(
              internal("Anniversary ID generator produced a duplicate UUID"));
        }
        if (recurrence_id.has_value()) {
          created_recurrence = domain::AnniversaryRecurrence{
              *recurrence_id,
              std::string(domain::kAnniversaryRecurrenceYearly),
              1,
              context.value().now,
              std::nullopt};
          state.recurrences.push_back(*created_recurrence);
        }
        created = domain::Anniversary{
            anniversary_id,
            common::trim_ascii(command.input.title),
            command.input.date,
            command.input.calendar_type,
            command.input.category_id,
            recurrence_id,
            command.input.note,
            command.input.importance,
            context.value().now,
            context.value().now,
            std::nullopt};
        state.anniversaries.push_back(created);
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) {
    return common::Result<AnniversaryDetail>::failure(committed.error());
  }
  return detail_for(created, created_recurrence, context.value(), command.input.timezone);
}

common::Result<AnniversaryDetail> AnniversaryWorkflowService::update(
    const UpdateAnniversaryCommand& command) {
  if (!transaction_ || !id_generator_) {
    return common::Result<AnniversaryDetail>::failure(
        internal("Anniversary workflow dependencies are unavailable"));
  }
  if (!common::is_uuid(command.id)) {
    return common::Result<AnniversaryDetail>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "id"}, {"reason", "id must be a UUID"}}));
  }
  auto valid = domain::validate_anniversary_input(
      command.input.title, command.input.date, command.input.calendar_type,
      command.input.category_id, command.input.importance);
  if (!valid.ok()) return common::Result<AnniversaryDetail>::failure(valid.error());
  auto context = projection_context(local_time_resolver_, clock_, command.input.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());
  const auto transaction_id = id_generator_();
  if (!common::is_uuid(transaction_id)) {
    return common::Result<AnniversaryDetail>::failure(
        internal("Anniversary ID generator returned an invalid UUID"));
  }

  domain::Anniversary updated;
  std::optional<domain::AnniversaryRecurrence> response_recurrence;
  auto committed = transaction_->execute(
      "anniversary_update", transaction_id, context.value().now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        auto anniversary = std::find_if(
            state.anniversaries.begin(), state.anniversaries.end(),
            [&](const auto& value) { return value.id == command.id && !value.deleted_at; });
        if (anniversary == state.anniversaries.end()) {
          return common::Result<common::Unit>::failure(not_found(command.id));
        }

        auto recurrence = state.recurrences.end();
        if (anniversary->recurrence_id.has_value()) {
          recurrence = std::find_if(
              state.recurrences.begin(), state.recurrences.end(),
              [&](const auto& value) { return value.id == *anniversary->recurrence_id; });
          if (recurrence == state.recurrences.end() || recurrence->deleted_at.has_value()) {
            return common::Result<common::Unit>::failure(
                corrupted("Active Anniversary recurrence is missing or deleted"));
          }
        }

        std::optional<std::string> recurrence_id = anniversary->recurrence_id;
        if (command.input.repeats_yearly && recurrence == state.recurrences.end()) {
          const auto generated = id_generator_();
          if (!common::is_uuid(generated) || std::any_of(
                  state.recurrences.begin(), state.recurrences.end(),
                  [&](const auto& value) { return value.id == generated; })) {
            return common::Result<common::Unit>::failure(
                internal("Anniversary recurrence ID generator returned an invalid UUID"));
          }
          response_recurrence = domain::AnniversaryRecurrence{
              generated,
              std::string(domain::kAnniversaryRecurrenceYearly),
              1,
              context.value().now,
              std::nullopt};
          state.recurrences.push_back(*response_recurrence);
          recurrence_id = generated;
        } else if (command.input.repeats_yearly) {
          response_recurrence = *recurrence;
        } else if (recurrence != state.recurrences.end()) {
          recurrence->deleted_at = context.value().now;
          recurrence_id = std::nullopt;
        }

        anniversary->title = common::trim_ascii(command.input.title);
        anniversary->date = command.input.date;
        anniversary->calendar_type = command.input.calendar_type;
        anniversary->category_id = command.input.category_id;
        anniversary->recurrence_id = recurrence_id;
        anniversary->note = command.input.note;
        anniversary->importance = command.input.importance;
        anniversary->updated_at = context.value().now;
        updated = *anniversary;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) {
    return common::Result<AnniversaryDetail>::failure(committed.error());
  }
  return detail_for(updated, response_recurrence, context.value(), command.input.timezone);
}

common::Result<domain::Anniversary> AnniversaryWorkflowService::remove(
    const DeleteAnniversaryCommand& command) {
  if (!transaction_ || !clock_ || !id_generator_) {
    return common::Result<domain::Anniversary>::failure(
        internal("Anniversary workflow dependencies are unavailable"));
  }
  if (!common::is_uuid(command.id)) {
    return common::Result<domain::Anniversary>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "id"}, {"reason", "id must be a UUID"}}));
  }
  const auto now = clock_();
  const auto transaction_id = id_generator_();
  if (!common::is_iso8601_utc_datetime(now) || !common::is_uuid(transaction_id)) {
    return common::Result<domain::Anniversary>::failure(
        internal("Anniversary Clock or ID generator returned an invalid value"));
  }

  domain::Anniversary removed;
  auto committed = transaction_->execute(
      "anniversary_delete", transaction_id, now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        auto anniversary = std::find_if(
            state.anniversaries.begin(), state.anniversaries.end(),
            [&](const auto& value) { return value.id == command.id && !value.deleted_at; });
        if (anniversary == state.anniversaries.end()) {
          return common::Result<common::Unit>::failure(not_found(command.id));
        }
        if (anniversary->recurrence_id.has_value()) {
          auto recurrence = std::find_if(
              state.recurrences.begin(), state.recurrences.end(),
              [&](const auto& value) { return value.id == *anniversary->recurrence_id; });
          if (recurrence == state.recurrences.end() || recurrence->deleted_at.has_value()) {
            return common::Result<common::Unit>::failure(
                corrupted("Active Anniversary recurrence is missing or deleted"));
          }
          recurrence->deleted_at = now;
        }
        anniversary->updated_at = now;
        anniversary->deleted_at = now;
        removed = *anniversary;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok()
             ? common::Result<domain::Anniversary>::success(std::move(removed))
             : common::Result<domain::Anniversary>::failure(committed.error());
}

}  // namespace excellent_calendar::application
