#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"

#include <algorithm>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/event_status.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kDeliveryNamespace = "74f9acf9-a4ce-59d1-9934-5cd7ce796976";
constexpr std::int64_t kRecoveryWindowSeconds = 72 * 60 * 60;
constexpr std::size_t kMaximumDetailCount = 20;
constexpr int kMaximumExpansionCount = 1000000;

common::Error recovery_conflict(const std::string& id) {
  return common::make_error(
      "RECOVERY_BATCH_CONFLICT", "Another incomplete recovery batch conflicts with this request",
      {{"recovery_batch_id", id}}, true);
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

bool is_open(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
}

domain::Reminder* find_reminder(repository::RecurringEventState& state, const std::string& id) {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

const domain::Reminder* find_reminder(const repository::RecurringEventState& state,
                                      const std::string& id) {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

const domain::Event* find_event(const repository::RecurringEventState& state,
                                const std::string& id) {
  const auto found = std::find_if(state.events.begin(), state.events.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.events.end() ? nullptr : &*found;
}

const domain::Recurrence* find_recurrence(const repository::RecurringEventState& state,
                                          const std::string& id,
                                          int revision) {
  const auto found = std::find_if(
      state.recurrences.begin(), state.recurrences.end(), [&](const auto& value) {
        return value.id == id && value.revision == revision;
      });
  return found == state.recurrences.end() ? nullptr : &*found;
}

bool contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

bool terminal_occurrence(const repository::RecurringEventState& state,
                         const domain::EventOccurrence& occurrence) {
  return std::any_of(state.occurrence_states.begin(), state.occurrence_states.end(),
                     [&](const auto& value) {
                       return value.event_id == occurrence.event_id &&
                              value.recurrence_revision == occurrence.recurrence_revision &&
                              value.occurrence_key == occurrence.occurrence_key &&
                              domain::is_terminal_occurrence_status(value.status);
                     });
}

std::vector<domain::RecurringReminderDraft> templates_for(
    const repository::RecurringEventState& state,
    const domain::Event& event) {
  std::map<int, domain::RecurringReminderDraft> templates;
  for (const auto& reminder : state.reminders) {
    if (reminder.target_id != event.id ||
        reminder.recurrence_revision != event.recurrence_revision ||
        !reminder.advance_minutes.has_value() ||
        reminder.methods != std::vector<std::string>{"popup"}) continue;
    templates[*reminder.advance_minutes] = domain::RecurringReminderDraft{
        *reminder.advance_minutes, reminder.methods, reminder.message, true, reminder.source};
  }
  std::vector<domain::RecurringReminderDraft> result;
  for (const auto& value : templates) result.push_back(value.second);
  return result;
}

struct ExpansionLowerBound {
  std::int64_t epoch = 0;
  bool inclusive = false;
};

std::optional<std::int64_t> latest_completed_recovery_at(
    const repository::RecurringEventState& state) {
  std::optional<std::int64_t> result;
  for (const auto& batch : state.recovery_batches) {
    if (batch.status != domain::kRecoveryCompleted) continue;
    const auto value = common::parse_iso8601_utc_epoch_seconds(batch.started_at);
    if (value.has_value() && (!result.has_value() || *value > *result)) result = value;
  }
  return result;
}

std::optional<ExpansionLowerBound> expansion_lower_bound(
    const repository::RecurringEventState& state,
    const domain::Event& event,
    const domain::RecurringReminderDraft& draft,
    const std::optional<std::int64_t>& recovery_watermark) {
  std::optional<std::int64_t> first_open;
  std::optional<std::int64_t> last_terminal;
  for (const auto& reminder : state.reminders) {
    if (reminder.target_id != event.id ||
        reminder.recurrence_revision != event.recurrence_revision ||
        reminder.advance_minutes != draft.advance_minutes || reminder.methods != draft.methods) continue;
    const auto epoch = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
    if (!epoch.has_value()) continue;
    if (is_open(reminder)) {
      if (!first_open.has_value() || *epoch < *first_open) first_open = epoch;
    } else if (!last_terminal.has_value() || *epoch > *last_terminal) {
      last_terminal = epoch;
    }
  }

  if (first_open.has_value() &&
      (!recovery_watermark.has_value() || *first_open > *recovery_watermark)) {
    return ExpansionLowerBound{*first_open, true};
  }
  if (recovery_watermark.has_value()) {
    return ExpansionLowerBound{*recovery_watermark, false};
  }
  if (last_terminal.has_value()) return ExpansionLowerBound{*last_terminal, false};
  return std::nullopt;
}

bool passes_lower_bound(std::int64_t value, const ExpansionLowerBound& lower) {
  return lower.inclusive ? value >= lower.epoch : value > lower.epoch;
}

common::Result<std::string> summary_delivery_id(const std::string& batch_id) {
  return common::generate_uuid_v5(
      kDeliveryNamespace,
      "[\"recovery_summary\",\"" + batch_id + "\",\"popup\"]");
}

common::Result<common::Unit> ensure_future_successor(
    repository::RecurringEventState& state,
    const domain::Reminder& expired,
    const std::string& now,
    const RollingReminderService& rolling) {
  if (!expired.recurrence_revision.has_value() ||
      !expired.advance_minutes.has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  const auto* event = find_event(state, expired.target_id);
  if (event == nullptr || event->deleted_at.has_value() ||
      event->status != domain::kEventStatusActive ||
      !event->recurrence_id.has_value() ||
      event->recurrence_revision != expired.recurrence_revision) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  const auto* recurrence = find_recurrence(
      state, *event->recurrence_id, *expired.recurrence_revision);
  if (recurrence == nullptr) {
    return common::Result<common::Unit>::failure(
        internal_error("current recurrence revision is missing"));
  }
  return rolling.ensure_next_in_state(
      state, *event, *recurrence, rolling.template_from(expired), now, now);
}

common::Result<common::Unit> resolve_prepared_attempts(
    repository::RecurringEventState& state,
    const domain::ReminderRecoveryBatch& batch,
    const std::set<std::string>& expired_reminder_ids,
    const std::string& now) {
  const std::set<std::string> detail_ids(
      batch.detail_reminder_ids.begin(), batch.detail_reminder_ids.end());
  const std::set<std::string> summary_ids(
      batch.summary_reminder_ids.begin(), batch.summary_reminder_ids.end());
  for (auto& notification : state.notifications) {
    if (notification.kind != "reminder" ||
        notification.status != domain::kNotificationStatusPrepared ||
        !notification.reminder_id.has_value()) {
      continue;
    }
    const auto& reminder_id = *notification.reminder_id;
    const bool adopted_detail = detail_ids.count(reminder_id) != 0U;
    const bool abandoned_summary = summary_ids.count(reminder_id) != 0U;
    const bool abandoned_outside = expired_reminder_ids.count(reminder_id) != 0U;
    if (!adopted_detail && !abandoned_summary && !abandoned_outside) continue;
    if (notification.resolved_by_recovery_batch_id.has_value() &&
        notification.resolved_by_recovery_batch_id != batch.id) {
      return common::Result<common::Unit>::failure(
          recovery_conflict(*notification.resolved_by_recovery_batch_id));
    }

    notification.resolved_by_recovery_batch_id = batch.id;
    notification.updated_at = now;
    if (adopted_detail) {
      continue;
    }
    if (!batch.summary_delivery_id.has_value()) {
      return common::Result<common::Unit>::failure(
          internal_error("abandoned recovery attempt has no summary replacement"));
    }
    notification.status = std::string(domain::kNotificationStatusAbandoned);
    notification.failure_class = std::nullopt;
    notification.error_code = std::nullopt;
    notification.abandon_reason =
        abandoned_summary ? std::optional<std::string>("recovery_summary_superseded")
                          : std::optional<std::string>("recovery_window_elapsed");
    notification.finalized_at = now;
    notification.sent_at = std::nullopt;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::vector<PreparedAttemptRecoveryResolution>> resolutions_for(
    const repository::RecurringEventState& state,
    const domain::ReminderRecoveryBatch& batch) {
  std::vector<PreparedAttemptRecoveryResolution> result;
  for (const auto& notification : state.notifications) {
    if (notification.kind != "reminder" ||
        notification.resolved_by_recovery_batch_id != batch.id) {
      continue;
    }
    if (!notification.delivery_attempt_id.has_value() ||
        !notification.delivery_id.has_value() ||
        !notification.reminder_id.has_value()) {
      return common::Result<std::vector<PreparedAttemptRecoveryResolution>>::failure(
          internal_error("resolved prepared attempt identity is missing"));
    }

    PreparedAttemptRecoveryResolution resolution;
    resolution.delivery_attempt_id = *notification.delivery_attempt_id;
    resolution.delivery_id = *notification.delivery_id;
    resolution.reminder_id = *notification.reminder_id;
    if (notification.abandon_reason == "recovery_summary_superseded") {
      resolution.resolution = "abandoned_to_summary";
      resolution.replacement_delivery_id = batch.summary_delivery_id;
    } else if (notification.abandon_reason == "recovery_window_elapsed") {
      resolution.resolution = "abandoned_outside_window";
      resolution.replacement_delivery_id = batch.summary_delivery_id;
    } else if (contains(batch.detail_reminder_ids, resolution.reminder_id) &&
               notification.status != domain::kNotificationStatusAbandoned) {
      resolution.resolution = "adopted_detail";
      resolution.replacement_delivery_id = std::nullopt;
    } else {
      return common::Result<std::vector<PreparedAttemptRecoveryResolution>>::failure(
          internal_error("resolved prepared attempt disposition is invalid"));
    }
    if (resolution.resolution != "adopted_detail" &&
        !resolution.replacement_delivery_id.has_value()) {
      return common::Result<std::vector<PreparedAttemptRecoveryResolution>>::failure(
          internal_error("abandoned prepared attempt replacement is missing"));
    }
    result.push_back(std::move(resolution));
  }
  std::sort(result.begin(), result.end(), [](const auto& left, const auto& right) {
    return left.delivery_attempt_id < right.delivery_attempt_id;
  });
  return common::Result<std::vector<PreparedAttemptRecoveryResolution>>::success(
      std::move(result));
}

std::vector<domain::Reminder> details_for(
    const repository::RecurringEventState& state,
    const domain::ReminderRecoveryBatch& batch) {
  std::vector<domain::Reminder> result;
  for (const auto& id : batch.detail_reminder_ids) {
    const auto* reminder = find_reminder(state, id);
    if (reminder != nullptr) result.push_back(*reminder);
  }
  return result;
}

}  // namespace

ReminderRecoveryWorkflowService::ReminderRecoveryWorkflowService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    std::shared_ptr<RecurrenceService> recurrence_service,
    std::shared_ptr<RollingReminderService> rolling_reminder_service,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : transaction_(std::move(transaction)),
      recurrence_service_(std::move(recurrence_service)),
      rolling_reminder_service_(std::move(rolling_reminder_service)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<PlanReminderRecoveryResult> ReminderRecoveryWorkflowService::plan_recovery(
    const PlanReminderRecoveryCommand& command) {
  if (!common::is_uuid(command.recovery_request_id) ||
      !domain::is_valid_recovery_trigger_source(command.trigger_source)) {
    return common::Result<PlanReminderRecoveryResult>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "recovery_request_id"}}));
  }
  const auto now = clock_();
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (!now_epoch.has_value()) {
    return common::Result<PlanReminderRecoveryResult>::failure(
        internal_error("recovery clock returned invalid UTC time"));
  }
  const auto window_start_epoch = *now_epoch - kRecoveryWindowSeconds;
  const auto window_start = common::format_epoch_seconds_utc_iso8601(window_start_epoch);
  std::optional<PlanReminderRecoveryResult> output;
  auto committed = transaction_->execute(
      "recovery_batch_reminders_and_summary", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        const auto existing = std::find_if(
            state.recovery_batches.begin(), state.recovery_batches.end(), [&](const auto& batch) {
              return batch.recovery_request_id == command.recovery_request_id;
            });
        if (existing != state.recovery_batches.end()) {
          auto resolutions = resolutions_for(state, *existing);
          if (!resolutions.ok()) return common::Result<common::Unit>::failure(resolutions.error());
          output = PlanReminderRecoveryResult{
              *existing, details_for(state, *existing),
              std::move(resolutions.value()), true};
          return common::Result<common::Unit>::success(common::Unit{});
        }
        const auto active = std::find_if(
            state.recovery_batches.begin(), state.recovery_batches.end(), [](const auto& batch) {
              return batch.status == domain::kRecoveryInProgress;
            });
        if (active != state.recovery_batches.end()) {
          return common::Result<common::Unit>::failure(recovery_conflict(active->id));
        }

        domain::ReminderRecoveryBatch batch;
        batch.id = id_generator_();
        if (!common::is_uuid(batch.id)) {
          return common::Result<common::Unit>::failure(
              internal_error("recovery ID generator returned invalid UUID"));
        }
        batch.recovery_request_id = command.recovery_request_id;
        batch.trigger_source = command.trigger_source;
        batch.started_at = now;
        batch.window_start_at = window_start;
        batch.status = std::string(domain::kRecoveryInProgress);

        std::set<std::string> candidate_ids;
        std::set<std::string> older_occurrences;
        std::set<std::string> expired_reminder_ids;
        std::vector<domain::Reminder> reminders_to_expire;
        int unmaterialized_older_reminders = 0;
        const auto watermark = latest_completed_recovery_at(state);

        for (const auto& event : state.events) {
          if (event.deleted_at.has_value() || event.status != domain::kEventStatusActive ||
              event.is_all_day || !event.recurrence_id.has_value() ||
              !event.recurrence_revision.has_value()) continue;
          const auto* recurrence = find_recurrence(
              state, *event.recurrence_id, *event.recurrence_revision);
          if (recurrence == nullptr) {
            return common::Result<common::Unit>::failure(
                internal_error("current recurrence revision is missing"));
          }
          for (const auto& draft : templates_for(state, event)) {
            const auto lower = expansion_lower_bound(state, event, draft, watermark);
            if (!lower.has_value()) continue;
            bool reached_future = false;
            for (int index = 0; index < kMaximumExpansionCount; ++index) {
              auto occurrence = recurrence_service_->occurrence_at(
                  domain::recurring_schedule_from_event(event), *recurrence, index);
              if (!occurrence.ok()) return common::Result<common::Unit>::failure(occurrence.error());
              auto candidate = rolling_reminder_service_->create_for_occurrence(
                  occurrence.value(), draft, now, batch.id, true);
              if (!candidate.ok()) return common::Result<common::Unit>::failure(candidate.error());
              const auto remind_at = common::parse_iso8601_utc_epoch_seconds(candidate.value().remind_at);
              if (!remind_at.has_value()) {
                return common::Result<common::Unit>::failure(
                    internal_error("expanded Reminder time is invalid"));
              }
              if (!passes_lower_bound(*remind_at, *lower)) continue;
              if (*remind_at > *now_epoch) {
                reached_future = true;
                break;
              }
              if (terminal_occurrence(state, occurrence.value())) continue;
              const auto* stored = find_reminder(state, candidate.value().id);
              if (stored != nullptr) {
                if (is_open(*stored) && *remind_at >= window_start_epoch) {
                  candidate_ids.insert(stored->id);
                }
                continue;
              }
              if (*remind_at < window_start_epoch) {
                ++unmaterialized_older_reminders;
                older_occurrences.insert(
                    event.id + ":" + std::to_string(*event.recurrence_revision) + ":" +
                    occurrence.value().occurrence_key);
                continue;
              }
              state.reminders.push_back(candidate.value());
              candidate_ids.insert(candidate.value().id);
            }
            if (!reached_future) {
              return common::Result<common::Unit>::failure(
                  internal_error("recovery occurrence expansion exceeded safe bound"));
            }
            auto future = rolling_reminder_service_->ensure_next_in_state(
                state, event, *recurrence, draft, now, now);
            if (!future.ok()) return future;
          }
        }

        for (const auto& reminder : state.reminders) {
          if (!is_open(reminder)) continue;
          const auto remind_at = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
          if (!remind_at.has_value()) {
            return common::Result<common::Unit>::failure(
                internal_error("stored Reminder time is invalid"));
          }
          if (*remind_at < window_start_epoch) {
            reminders_to_expire.push_back(reminder);
            expired_reminder_ids.insert(reminder.id);
            continue;
          }
          if (*remind_at <= *now_epoch) {
            candidate_ids.insert(reminder.id);
          }
        }

        for (const auto& expired : reminders_to_expire) {
          auto* reminder = find_reminder(state, expired.id);
          if (reminder == nullptr || !is_open(*reminder)) {
            return common::Result<common::Unit>::failure(
                internal_error("pre-window Reminder disappeared before expiration"));
          }
          reminder->status = std::string(domain::kReminderStatusExpired);
          reminder->is_enabled = false;
          reminder->scheduled_at = std::nullopt;
          reminder->expiration_reason =
              std::string(domain::kReminderExpirationReasonRecoveryWindowElapsed);
          reminder->expired_at = now;
          reminder->updated_at = now;
          auto successor = ensure_future_successor(
              state, expired, now, *rolling_reminder_service_);
          if (!successor.ok()) return successor;
        }

        std::vector<domain::Reminder> candidates;
        for (const auto& id : candidate_ids) {
          auto* reminder = find_reminder(state, id);
          if (reminder == nullptr) {
            return common::Result<common::Unit>::failure(
                internal_error("recovery candidate disappeared"));
          }
          if (reminder->recovery_batch_id.has_value() &&
              reminder->recovery_batch_id != batch.id) {
            return common::Result<common::Unit>::failure(
                recovery_conflict(*reminder->recovery_batch_id));
          }
          reminder->recovery_batch_id = batch.id;
          reminder->updated_at = now;
          candidates.push_back(*reminder);
        }
        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
          if (left.remind_at != right.remind_at) return left.remind_at > right.remind_at;
          return left.id > right.id;
        });
        const auto detail_count = std::min(kMaximumDetailCount, candidates.size());
        std::vector<domain::Reminder> details(candidates.begin(), candidates.begin() + detail_count);
        std::sort(details.begin(), details.end(), [](const auto& left, const auto& right) {
          if (left.remind_at != right.remind_at) return left.remind_at < right.remind_at;
          return left.id < right.id;
        });
        for (const auto& reminder : details) {
          batch.detail_reminder_ids.push_back(reminder.id);
        }

        std::vector<domain::Reminder> summaries(candidates.begin() + detail_count, candidates.end());
        std::sort(summaries.begin(), summaries.end(), [](const auto& left, const auto& right) {
          if (left.remind_at != right.remind_at) return left.remind_at < right.remind_at;
          return left.id < right.id;
        });
        for (const auto& reminder : summaries) batch.summary_reminder_ids.push_back(reminder.id);
        batch.window_overflow_count = static_cast<int>(batch.summary_reminder_ids.size());
        batch.older_skipped_occurrence_count = static_cast<int>(older_occurrences.size());
        batch.older_skipped_reminder_count =
            unmaterialized_older_reminders +
            static_cast<int>(expired_reminder_ids.size());

        const bool needs_summary = !batch.summary_reminder_ids.empty() ||
                                   batch.older_skipped_occurrence_count > 0 ||
                                   batch.older_skipped_reminder_count > 0;
        if (needs_summary) {
          auto delivery = summary_delivery_id(batch.id);
          if (!delivery.ok()) return common::Result<common::Unit>::failure(delivery.error());
          batch.summary_delivery_id = delivery.value();
        }
        auto resolved = resolve_prepared_attempts(
            state, batch, expired_reminder_ids, now);
        if (!resolved.ok()) return resolved;
        if (batch.detail_reminder_ids.empty() && !needs_summary) {
          batch.status = std::string(domain::kRecoveryCompleted);
          batch.completed_at = now;
        }
        state.recovery_batches.push_back(batch);
        auto resolutions = resolutions_for(state, batch);
        if (!resolutions.ok()) return common::Result<common::Unit>::failure(resolutions.error());
        output = PlanReminderRecoveryResult{
            batch, std::move(details), std::move(resolutions.value()), false};
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) {
    return common::Result<PlanReminderRecoveryResult>::failure(committed.error());
  }
  if (!output.has_value()) {
    return common::Result<PlanReminderRecoveryResult>::failure(
        internal_error("recovery planning returned no result"));
  }
  return common::Result<PlanReminderRecoveryResult>::success(std::move(*output));
}

}  // namespace excellent_calendar::application
