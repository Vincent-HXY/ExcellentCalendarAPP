#include "excellent_calendar/application/anniversary_workflow_service.hpp"

#include <algorithm>
#include <set>
#include <tuple>
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
  return common::make_error("ANNIVERSARY_NOT_FOUND", "Anniversary not found", {{"id", id}});
}

common::Error corrupted(std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
                            {{"field", "anniversary"}, {"reason", std::move(reason)}});
}

common::Error internal(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", std::move(reason)}});
}

common::Error update_conflict(
    const std::string& id,
    const std::string& current_updated_at) {
  return common::make_error(
      "ANNIVERSARY_UPDATE_CONFLICT",
      "Anniversary has changed since it was read",
      {{"id", id}, {"current_updated_at", current_updated_at}});
}

common::Result<std::string> next_updated_at(
    const std::string& now,
    const std::string& previous) {
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  const auto previous_epoch = common::parse_iso8601_utc_epoch_seconds(previous);
  if (!now_epoch || !previous_epoch) {
    return common::Result<std::string>::failure(
        corrupted("invalid Anniversary updated_at"));
  }
  if (*now_epoch > *previous_epoch) {
    return common::Result<std::string>::success(now);
  }
  return common::Result<std::string>::success(
      common::format_epoch_seconds_utc_iso8601(*previous_epoch + 1));
}

bool open_reminder(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
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
  if (!timezone_valid.ok()) return common::Result<ProjectionContext>::failure(timezone_valid.error());
  const auto now = clock();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<ProjectionContext>::failure(
        internal("Anniversary Clock returned an invalid UTC instant"));
  }
  auto local = resolver->to_local(now, timezone);
  if (!local.ok()) return common::Result<ProjectionContext>::failure(local.error());
  return common::Result<ProjectionContext>::success(
      ProjectionContext{now, {local.value().year, local.value().month, local.value().day}});
}

common::Result<common::Unit> validate_plan(const AnniversaryReminderPlanInput& plan) {
  if (plan.templates.size() > 5U) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED",
        "Anniversary reminder plan contains more than five templates"));
  }
  std::set<std::tuple<int, std::string, std::string>> unique;
  for (const auto& item : plan.templates) {
    auto identity = domain::anniversary_reminder_template_key(
        "00000000-0000-4000-8000-000000000000", item.advance_days, item.local_time);
    if (!identity.ok() || item.method != domain::kAnniversaryReminderMethodPopup) {
      return common::Result<common::Unit>::failure(common::make_error(
          "ANNIVERSARY_REMINDER_CONFIG_INVALID",
          "Anniversary reminder configuration is invalid"));
    }
    if (!unique.emplace(item.advance_days, item.local_time, item.method).second) {
      return common::Result<common::Unit>::failure(common::make_error(
          "ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE",
          "Anniversary reminder templates contain a duplicate identity tuple"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

std::optional<domain::AnniversaryRecurrence> recurrence_for(
    const domain::Anniversary& anniversary, const repository::AnniversaryState& state) {
  if (!anniversary.recurrence_id.has_value()) return std::nullopt;
  const auto found = std::find_if(state.recurrences.begin(), state.recurrences.end(),
                                  [&](const auto& value) {
                                    return value.id == *anniversary.recurrence_id &&
                                           !value.deleted_at.has_value();
                                  });
  return found == state.recurrences.end() ? std::optional<domain::AnniversaryRecurrence>{}
                                         : std::optional<domain::AnniversaryRecurrence>(*found);
}

AnniversaryReminderSettings settings_for(const domain::Anniversary& anniversary,
                                          const repository::AnniversaryState& state,
                                          bool reconciliation_required) {
  AnniversaryReminderSettings settings;
  settings.reminders_enabled = anniversary.reminders_enabled;
  for (const auto& item : state.reminder_templates) {
    if (item.anniversary_id == anniversary.id && !item.deleted_at.has_value()) {
      settings.templates.push_back(item);
      if (anniversary.reminders_enabled && item.is_enabled) ++settings.active_reminder_count;
    }
  }
  std::sort(settings.templates.begin(), settings.templates.end(),
            [](const auto& left, const auto& right) {
              return left.template_key < right.template_key;
            });
  settings.schedule_reconciliation_required = reconciliation_required;
  return settings;
}

common::Result<AnniversaryDetail> detail_for(
    const domain::Anniversary& anniversary,
    const std::optional<domain::AnniversaryRecurrence>& recurrence,
    const repository::AnniversaryState& state, const ProjectionContext& context,
    const std::string& timezone, bool reconciliation_required) {
  auto countdown = domain::calculate_anniversary_countdown(
      anniversary.date, recurrence.has_value(), context.today, timezone, context.now);
  if (!countdown.ok()) return common::Result<AnniversaryDetail>::failure(countdown.error());
  AnniversaryDetail detail;
  detail.anniversary = anniversary;
  detail.recurrence = recurrence;
  detail.countdown = countdown.value();
  detail.reminder_settings = settings_for(anniversary, state, reconciliation_required);
  return common::Result<AnniversaryDetail>::success(std::move(detail));
}

common::Result<std::string> materialized_remind_at(
    const domain::LocalDate& occurrence_date,
    const domain::AnniversaryReminderTemplate& reminder_template,
    const std::string& timezone,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  const auto reminder_date = domain::add_local_days(occurrence_date, -reminder_template.advance_days);
  const int hour = (reminder_template.local_time[0] - '0') * 10 +
                   reminder_template.local_time[1] - '0';
  const int minute = (reminder_template.local_time[3] - '0') * 10 +
                     reminder_template.local_time[4] - '0';
  auto resolved = resolver->resolve_local_datetime(
      {reminder_date.year, reminder_date.month, reminder_date.day, hour, minute, 0}, timezone);
  return resolved.ok() ? common::Result<std::string>::success(resolved.value().utc_instant)
                       : common::Result<std::string>::failure(resolved.error());
}

common::Result<common::Unit> materialize_template(
    const domain::Anniversary& anniversary, bool repeats_yearly,
    const domain::AnniversaryReminderTemplate& reminder_template,
    const ProjectionContext& context, const std::string& timezone,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver,
    repository::AnniversaryState& state) {
  if (!anniversary.reminders_enabled || !reminder_template.is_enabled ||
      reminder_template.deleted_at.has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(context.now);
  if (!now_epoch.has_value()) return common::Result<common::Unit>::failure(internal("invalid Clock"));
  std::optional<domain::LocalDate> occurrence;
  std::optional<std::string> remind_at;
  const int start_year = repeats_yearly ? std::max(context.today.year, anniversary.date.year)
                                        : anniversary.date.year;
  for (int offset = 0; offset < (repeats_yearly ? 3 : 1); ++offset) {
    const auto candidate = repeats_yearly
                               ? domain::anniversary_occurrence_in_year(anniversary.date,
                                                                         start_year + offset)
                               : anniversary.date;
    if (candidate < anniversary.date) continue;
    auto projected = materialized_remind_at(candidate, reminder_template, timezone, resolver);
    if (!projected.ok()) return common::Result<common::Unit>::failure(projected.error());
    const auto epoch = common::parse_iso8601_utc_epoch_seconds(projected.value());
    if (epoch.has_value() && *epoch > *now_epoch) {
      occurrence = candidate;
      remind_at = projected.value();
      break;
    }
  }
  if (!occurrence.has_value()) return common::Result<common::Unit>::success(common::Unit{});

  auto occurrence_key = domain::anniversary_occurrence_key(anniversary.id, *occurrence);
  if (!occurrence_key.ok()) return common::Result<common::Unit>::failure(occurrence_key.error());
  auto id = domain::anniversary_reminder_id(
      anniversary.id, occurrence_key.value(), reminder_template.template_key);
  if (!id.ok()) return common::Result<common::Unit>::failure(id.error());
  auto existing = std::find_if(state.reminders.begin(), state.reminders.end(),
                               [&](const auto& value) { return value.id == id.value(); });
  if (existing != state.reminders.end()) {
    existing->remind_at = *remind_at;
    existing->updated_at = context.now;
    if (!open_reminder(*existing)) {
      existing->is_enabled = true;
      existing->status = std::string(domain::kReminderStatusPending);
      existing->scheduled_at.reset();
      existing->failure_reason.reset();
      existing->cancellation_reason.reset();
      existing->expiration_reason.reset();
      existing->expired_at.reset();
      existing->reactivated_at = context.now;
      ++existing->reactivation_count;
      existing->fulfillment_delivery_id.reset();
    }
    return common::Result<common::Unit>::success(common::Unit{});
  }
  domain::Reminder reminder;
  reminder.id = id.value();
  reminder.target_type = std::string(domain::kReminderTargetAnniversary);
  reminder.target_id = anniversary.id;
  reminder.occurrence_key = occurrence_key.value();
  reminder.remind_at = *remind_at;
  reminder.methods = {std::string(domain::kReminderMethodPopup)};
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.source = "manual";
  reminder.created_at = context.now;
  reminder.updated_at = context.now;
  reminder.template_key = reminder_template.template_key;
  reminder.occurrence_date = domain::format_local_date(*occurrence);
  reminder.advance_days = reminder_template.advance_days;
  reminder.local_time = reminder_template.local_time;
  reminder.timezone_mode = reminder_template.timezone_mode;
  state.reminders.push_back(std::move(reminder));
  return common::Result<common::Unit>::success(common::Unit{});
}

void cancel_open_reminders(repository::AnniversaryState& state,
                           const std::string& anniversary_id, std::string_view reason,
                           const std::string& now) {
  for (auto& reminder : state.reminders) {
    if (reminder.target_type == domain::kReminderTargetAnniversary &&
        reminder.target_id == anniversary_id && open_reminder(reminder)) {
      reminder.is_enabled = false;
      reminder.status = std::string(domain::kReminderStatusCancelled);
      reminder.scheduled_at.reset();
      reminder.cancellation_reason = std::string(reason);
      reminder.last_cancelled_at = now;
      reminder.updated_at = now;
    }
  }
}

common::Result<common::Unit> replace_templates(repository::AnniversaryState& state,
                                                domain::Anniversary& anniversary,
                                                const AnniversaryReminderPlanInput& plan,
                                                const std::string& now) {
  auto valid = validate_plan(plan);
  if (!valid.ok()) return valid;
  std::set<std::string> requested;
  for (const auto& input : plan.templates) {
    auto key = domain::anniversary_reminder_template_key(
        anniversary.id, input.advance_days, input.local_time);
    if (!key.ok()) return common::Result<common::Unit>::failure(key.error());
    requested.insert(key.value());
    auto existing = std::find_if(state.reminder_templates.begin(), state.reminder_templates.end(),
                                 [&](const auto& value) {
                                   return value.template_key == key.value();
                                 });
    if (existing == state.reminder_templates.end()) {
      state.reminder_templates.push_back({key.value(), anniversary.id, input.advance_days,
                                          input.local_time, "follow_device", input.method,
                                          input.is_enabled, now, now, std::nullopt});
    } else {
      if (existing->anniversary_id != anniversary.id ||
          existing->advance_days != input.advance_days ||
          existing->local_time != input.local_time || existing->method != input.method) {
        return common::Result<common::Unit>::failure(corrupted("template identity collision"));
      }
      existing->is_enabled = input.is_enabled;
      existing->deleted_at.reset();
      existing->updated_at = now;
    }
  }
  for (auto& existing : state.reminder_templates) {
    if (existing.anniversary_id == anniversary.id && !existing.deleted_at.has_value() &&
        requested.count(existing.template_key) == 0U) {
      existing.deleted_at = now;
      existing.updated_at = now;
    }
  }
  anniversary.reminders_enabled = plan.reminders_enabled;
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> materialize_all(
    repository::AnniversaryState& state, const domain::Anniversary& anniversary,
    bool repeats_yearly, const ProjectionContext& context, const std::string& timezone,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  for (const auto& item : state.reminder_templates) {
    if (item.anniversary_id != anniversary.id) continue;
    auto result = materialize_template(anniversary, repeats_yearly, item, context, timezone,
                                       resolver, state);
    if (!result.ok()) return result;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

AnniversaryWorkflowService::AnniversaryWorkflowService(
    std::shared_ptr<repository::AnniversaryTransaction> transaction,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver, Clock clock,
    IdGenerator id_generator)
    : transaction_(std::move(transaction)), local_time_resolver_(std::move(local_time_resolver)),
      clock_(std::move(clock)), id_generator_(std::move(id_generator)) {}

common::Result<AnniversaryDetail> AnniversaryWorkflowService::create(
    const CreateAnniversaryCommand& command) {
  if (!transaction_ || !id_generator_) {
    return common::Result<AnniversaryDetail>::failure(internal("dependencies unavailable"));
  }
  auto valid = domain::validate_anniversary_input(
      command.input.title, command.input.date, command.input.calendar_type,
      command.input.category_id, command.input.importance);
  if (!valid.ok()) return common::Result<AnniversaryDetail>::failure(valid.error());
  const auto plan = command.input.reminder_plan.value_or(AnniversaryReminderPlanInput{});
  auto plan_valid = validate_plan(plan);
  if (!plan_valid.ok()) return common::Result<AnniversaryDetail>::failure(plan_valid.error());
  auto context = projection_context(local_time_resolver_, clock_, command.input.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());
  const auto anniversary_id = id_generator_();
  const auto recurrence_id = command.input.repeats_yearly
                                 ? std::optional<std::string>(id_generator_()) : std::nullopt;
  const auto transaction_id = id_generator_();
  if (!common::is_uuid(anniversary_id) ||
      (recurrence_id && !common::is_uuid(*recurrence_id)) || !common::is_uuid(transaction_id)) {
    return common::Result<AnniversaryDetail>::failure(internal("invalid generated UUID"));
  }
  domain::Anniversary created;
  std::optional<domain::AnniversaryRecurrence> recurrence;
  repository::AnniversaryState committed_state;
  auto committed = transaction_->execute(
      "anniversary_create", transaction_id, context.value().now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        if (std::any_of(state.anniversaries.begin(), state.anniversaries.end(),
                        [&](const auto& value) { return value.id == anniversary_id; })) {
          return common::Result<common::Unit>::failure(internal("duplicate generated UUID"));
        }
        if (recurrence_id) {
          recurrence = domain::AnniversaryRecurrence{*recurrence_id, "yearly", 1,
                                                      context.value().now, std::nullopt};
          state.recurrences.push_back(*recurrence);
        }
        created.id = anniversary_id;
        created.title = common::trim_ascii(command.input.title);
        created.date = command.input.date;
        created.calendar_type = command.input.calendar_type;
        created.category_id = command.input.category_id;
        created.recurrence_id = recurrence_id;
        created.note = command.input.note;
        created.importance = command.input.importance;
        created.created_at = context.value().now;
        created.updated_at = context.value().now;
        state.anniversaries.push_back(created);
        auto templates = replace_templates(state, state.anniversaries.back(), plan,
                                           context.value().now);
        if (!templates.ok()) return templates;
        created = state.anniversaries.back();
        auto tasks = materialize_all(state, created, command.input.repeats_yearly,
                                     context.value(), command.input.timezone,
                                     local_time_resolver_);
        if (!tasks.ok()) return tasks;
        committed_state = state;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) return common::Result<AnniversaryDetail>::failure(committed.error());
  return detail_for(created, recurrence, committed_state, context.value(),
                    command.input.timezone, !plan.templates.empty());
}

common::Result<AnniversaryDetail> AnniversaryWorkflowService::update(
    const UpdateAnniversaryCommand& command) {
  if (!transaction_ || !id_generator_ || !common::is_uuid(command.id) ||
      !common::is_iso8601_utc_datetime(command.expected_updated_at)) {
    return common::Result<AnniversaryDetail>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", !common::is_uuid(command.id) ? "id" : "expected_updated_at"}}));
  }
  auto valid = domain::validate_anniversary_input(
      command.input.title, command.input.date, command.input.calendar_type,
      command.input.category_id, command.input.importance);
  if (!valid.ok()) return common::Result<AnniversaryDetail>::failure(valid.error());
  if (command.input.reminder_plan) {
    auto plan_valid = validate_plan(*command.input.reminder_plan);
    if (!plan_valid.ok()) return common::Result<AnniversaryDetail>::failure(plan_valid.error());
  }
  auto context = projection_context(local_time_resolver_, clock_, command.input.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());
  const auto transaction_id = id_generator_();
  if (!common::is_uuid(transaction_id)) {
    return common::Result<AnniversaryDetail>::failure(internal("invalid generated UUID"));
  }
  domain::Anniversary updated;
  std::optional<domain::AnniversaryRecurrence> response_recurrence;
  repository::AnniversaryState committed_state;
  bool reconciliation_required = false;
  auto committed = transaction_->execute(
      "anniversary_update", transaction_id, context.value().now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        auto anniversary = std::find_if(state.anniversaries.begin(), state.anniversaries.end(),
                                        [&](const auto& value) {
                                          return value.id == command.id && !value.deleted_at;
                                        });
        if (anniversary == state.anniversaries.end()) {
          return common::Result<common::Unit>::failure(not_found(command.id));
        }
        if (anniversary->updated_at != command.expected_updated_at) {
          return common::Result<common::Unit>::failure(
              update_conflict(command.id, anniversary->updated_at));
        }
        auto update_token = next_updated_at(
            context.value().now, anniversary->updated_at);
        if (!update_token.ok()) {
          return common::Result<common::Unit>::failure(update_token.error());
        }
        const bool identity_changed = !(anniversary->date == command.input.date) ||
            anniversary->recurrence_id.has_value() != command.input.repeats_yearly ||
            command.input.reminder_plan.has_value();
        if (identity_changed) {
          cancel_open_reminders(state, command.id,
                                domain::kReminderCancellationReasonAnniversaryUpdated,
                                context.value().now);
          reconciliation_required = true;
        }
        auto old_recurrence = state.recurrences.end();
        if (anniversary->recurrence_id) {
          old_recurrence = std::find_if(state.recurrences.begin(), state.recurrences.end(),
                                        [&](const auto& value) {
                                          return value.id == *anniversary->recurrence_id;
                                        });
          if (old_recurrence == state.recurrences.end() || old_recurrence->deleted_at) {
            return common::Result<common::Unit>::failure(corrupted("missing recurrence"));
          }
        }
        std::optional<std::string> recurrence_id = anniversary->recurrence_id;
        if (command.input.repeats_yearly && old_recurrence == state.recurrences.end()) {
          const auto generated = id_generator_();
          if (!common::is_uuid(generated)) {
            return common::Result<common::Unit>::failure(internal("invalid recurrence UUID"));
          }
          response_recurrence = domain::AnniversaryRecurrence{
              generated, "yearly", 1, context.value().now, std::nullopt};
          state.recurrences.push_back(*response_recurrence);
          recurrence_id = generated;
        } else if (command.input.repeats_yearly) {
          response_recurrence = *old_recurrence;
        } else if (old_recurrence != state.recurrences.end()) {
          old_recurrence->deleted_at = context.value().now;
          recurrence_id.reset();
        }
        anniversary->title = common::trim_ascii(command.input.title);
        anniversary->date = command.input.date;
        anniversary->calendar_type = command.input.calendar_type;
        anniversary->category_id = command.input.category_id;
        anniversary->recurrence_id = recurrence_id;
        anniversary->note = command.input.note;
        anniversary->importance = command.input.importance;
        anniversary->updated_at = update_token.value();
        if (command.input.reminder_plan) {
          auto templates = replace_templates(state, *anniversary, *command.input.reminder_plan,
                                             context.value().now);
          if (!templates.ok()) return templates;
        }
        updated = *anniversary;
        auto tasks = materialize_all(state, updated, command.input.repeats_yearly,
                                     context.value(), command.input.timezone,
                                     local_time_resolver_);
        if (!tasks.ok()) return tasks;
        committed_state = state;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) return common::Result<AnniversaryDetail>::failure(committed.error());
  return detail_for(updated, response_recurrence, committed_state, context.value(),
                    command.input.timezone, reconciliation_required);
}

common::Result<AnniversaryDetail> AnniversaryWorkflowService::set_reminders_enabled(
    const SetAnniversaryRemindersEnabledCommand& command) {
  if (!transaction_ || !id_generator_ || !common::is_uuid(command.id)) {
    return common::Result<AnniversaryDetail>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "id"}}));
  }
  auto context = projection_context(local_time_resolver_, clock_, command.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());
  const auto transaction_id = id_generator_();
  domain::Anniversary updated;
  std::optional<domain::AnniversaryRecurrence> recurrence;
  repository::AnniversaryState committed_state;
  auto committed = transaction_->execute(
      "anniversary_update", transaction_id, context.value().now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        auto anniversary = std::find_if(state.anniversaries.begin(), state.anniversaries.end(),
                                        [&](const auto& value) {
                                          return value.id == command.id && !value.deleted_at;
                                        });
        if (anniversary == state.anniversaries.end()) {
          return common::Result<common::Unit>::failure(not_found(command.id));
        }
        auto update_token = next_updated_at(
            context.value().now, anniversary->updated_at);
        if (!update_token.ok()) {
          return common::Result<common::Unit>::failure(update_token.error());
        }
        if (!command.reminders_enabled) {
          cancel_open_reminders(state, command.id,
                                domain::kReminderCancellationReasonAnniversaryPaused,
                                context.value().now);
        }
        anniversary->reminders_enabled = command.reminders_enabled;
        anniversary->updated_at = update_token.value();
        recurrence = recurrence_for(*anniversary, state);
        if (anniversary->recurrence_id && !recurrence) {
          return common::Result<common::Unit>::failure(corrupted("missing recurrence"));
        }
        updated = *anniversary;
        auto tasks = materialize_all(state, updated, recurrence.has_value(), context.value(),
                                     command.timezone, local_time_resolver_);
        if (!tasks.ok()) return tasks;
        committed_state = state;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) return common::Result<AnniversaryDetail>::failure(committed.error());
  return detail_for(updated, recurrence, committed_state, context.value(), command.timezone, true);
}

common::Result<AnniversaryDeleteResult> AnniversaryWorkflowService::remove(
    const DeleteAnniversaryCommand& command) {
  if (!transaction_ || !clock_ || !id_generator_) {
    return common::Result<AnniversaryDeleteResult>::failure(internal("dependencies unavailable"));
  }
  if (!common::is_uuid(command.id)) {
    return common::Result<AnniversaryDeleteResult>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "id"}}));
  }
  const auto now = clock_();
  const auto transaction_id = id_generator_();
  AnniversaryDeleteResult result;
  auto committed = transaction_->execute(
      "anniversary_delete", transaction_id, now,
      [&](repository::AnniversaryState& state) -> common::Result<common::Unit> {
        auto anniversary = std::find_if(state.anniversaries.begin(), state.anniversaries.end(),
                                        [&](const auto& value) {
                                          return value.id == command.id && !value.deleted_at;
                                        });
        if (anniversary == state.anniversaries.end()) {
          return common::Result<common::Unit>::failure(not_found(command.id));
        }
        auto update_token = next_updated_at(now, anniversary->updated_at);
        if (!update_token.ok()) {
          return common::Result<common::Unit>::failure(update_token.error());
        }
        result.schedule_reconciliation_required = std::any_of(
            state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
              return reminder.target_type == domain::kReminderTargetAnniversary &&
                     reminder.target_id == command.id && open_reminder(reminder);
            });
        cancel_open_reminders(state, command.id,
                              domain::kReminderCancellationReasonAnniversaryDeleted, now);
        for (auto& item : state.reminder_templates) {
          if (item.anniversary_id == command.id && !item.deleted_at) {
            item.deleted_at = now;
            item.updated_at = now;
          }
        }
        if (anniversary->recurrence_id) {
          auto recurrence = std::find_if(state.recurrences.begin(), state.recurrences.end(),
                                         [&](const auto& value) {
                                           return value.id == *anniversary->recurrence_id;
                                         });
          if (recurrence == state.recurrences.end() || recurrence->deleted_at) {
            return common::Result<common::Unit>::failure(corrupted("missing recurrence"));
          }
          recurrence->deleted_at = now;
        }
        anniversary->updated_at = update_token.value();
        anniversary->deleted_at = update_token.value();
        result.anniversary = *anniversary;
        result.deleted_at = anniversary->deleted_at;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<AnniversaryDeleteResult>::success(std::move(result))
                        : common::Result<AnniversaryDeleteResult>::failure(committed.error());
}

}  // namespace excellent_calendar::application
