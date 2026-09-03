#include "excellent_calendar/storage/sqlite/sqlite_repository_adapters.hpp"

#include <algorithm>
#include <optional>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace excellent_calendar::storage::sqlite {
namespace {

common::Error revoked(std::string operation) {
  return storage::runtime_storage_revoked_error(std::move(operation));
}

common::Error not_found(std::string code, std::string message, std::string id) {
  return common::make_error(std::move(code), std::move(message),
                            {{"id", std::move(id)}});
}

common::Error invalid_workflow_identity() {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", "workflow identity is invalid"}});
}

common::Error invalid_anniversary_metadata() {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error",
      {{"reason", "Anniversary transaction metadata is invalid"}});
}

common::Error invalid_category_operation() {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error",
      {{"reason", "Category repository operation is invalid"}});
}

bool is_anniversary_operation(std::string_view operation) {
  return operation == "anniversary_create" ||
         operation == "anniversary_update" ||
         operation == "anniversary_delete" ||
         operation == "anniversary_toggle_reminders" ||
         operation == "anniversary_timezone_recalculate";
}

}  // namespace

SqliteEventRepository::SqliteEventRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteEventRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("event_repository.initialize"))
             : database_->validate();
}

common::Result<domain::Event> SqliteEventRepository::create(
    const domain::Event& event) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<domain::Event>::failure(
        revoked("event_repository.create"));
  }
  auto committed = database_->transaction([&]() {
    auto loaded = database_->load_legacy_events();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    after.push_back(event);
    return database_->write_legacy_events(after);
  });
  return committed.ok()
             ? common::Result<domain::Event>::success(event)
             : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::Event> SqliteEventRepository::update(
    const domain::Event& event) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<domain::Event>::failure(
        revoked("event_repository.update"));
  }
  auto committed = database_->transaction([&]() {
    auto loaded = database_->load_legacy_events();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    const auto found = std::find_if(
        after.begin(), after.end(),
        [&](const domain::Event& current) { return current.id == event.id; });
    if (found == after.end()) {
      return common::Result<common::Unit>::failure(
          not_found("EVENT_NOT_FOUND", "Event not found", event.id));
    }
    *found = event;
    return database_->write_legacy_events(after);
  });
  return committed.ok()
             ? common::Result<domain::Event>::success(event)
             : common::Result<domain::Event>::failure(committed.error());
}

common::Result<std::optional<domain::Event>> SqliteEventRepository::find_by_id(
    std::string_view id) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::optional<domain::Event>>::failure(
        revoked("event_repository.find_by_id"));
  }
  auto loaded = database_->load_legacy_events();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Event>>::failure(
        loaded.error());
  }
  const auto found =
      std::find_if(loaded.value().begin(), loaded.value().end(),
                   [&](const domain::Event& event) { return event.id == id; });
  return common::Result<std::optional<domain::Event>>::success(
      found == loaded.value().end() ? std::optional<domain::Event>{}
                                    : std::optional<domain::Event>{*found});
}

common::Result<std::vector<domain::Event>> SqliteEventRepository::find_all() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::vector<domain::Event>>::failure(
        revoked("event_repository.find_all"));
  }
  return database_->load_legacy_events();
}

SqliteReminderRepository::SqliteReminderRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteReminderRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("reminder_repository.initialize"))
             : database_->validate();
}

common::Result<domain::Reminder> SqliteReminderRepository::create(
    const domain::Reminder& reminder) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<domain::Reminder>::failure(
        revoked("reminder_repository.create"));
  }
  auto committed = database_->transaction([&]() {
    auto loaded = database_->load_legacy_reminders();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    after.push_back(reminder);
    return database_->write_legacy_reminders(after);
  });
  return committed.ok()
             ? common::Result<domain::Reminder>::success(reminder)
             : common::Result<domain::Reminder>::failure(committed.error());
}

common::Result<std::optional<domain::Reminder>>
SqliteReminderRepository::find_by_id(std::string_view id) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::optional<domain::Reminder>>::failure(
        revoked("reminder_repository.find_by_id"));
  }
  auto loaded = database_->load_legacy_reminders();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(
        loaded.error());
  }
  const auto found = std::find_if(
      loaded.value().begin(), loaded.value().end(),
      [&](const domain::Reminder& reminder) { return reminder.id == id; });
  return common::Result<std::optional<domain::Reminder>>::success(
      found == loaded.value().end() ? std::optional<domain::Reminder>{}
                                    : std::optional<domain::Reminder>{*found});
}

common::Result<domain::Reminder> SqliteReminderRepository::update(
    const domain::Reminder& reminder) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<domain::Reminder>::failure(
        revoked("reminder_repository.update"));
  }
  auto committed = database_->transaction([&]() {
    auto loaded = database_->load_legacy_reminders();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    const auto found = std::find_if(after.begin(), after.end(),
                                    [&](const domain::Reminder& current) {
                                      return current.id == reminder.id;
                                    });
    if (found == after.end()) {
      return common::Result<common::Unit>::failure(
          not_found("REMINDER_NOT_FOUND", "Reminder not found", reminder.id));
    }
    *found = reminder;
    return database_->write_legacy_reminders(after);
  });
  return committed.ok()
             ? common::Result<domain::Reminder>::success(reminder)
             : common::Result<domain::Reminder>::failure(committed.error());
}

common::Result<std::vector<domain::Reminder>>
SqliteReminderRepository::find_all() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        revoked("reminder_repository.find_all"));
  }
  return database_->load_legacy_reminders();
}

SqliteNotificationRepository::SqliteNotificationRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteNotificationRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("notification_repository.initialize"))
             : database_->validate();
}

common::Result<domain::Notification> SqliteNotificationRepository::create(
    const domain::Notification& notification) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<domain::Notification>::failure(
        revoked("notification_repository.create"));
  }
  auto committed = database_->transaction([&]() {
    auto loaded = database_->load_legacy_notifications();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    after.push_back(notification);
    return database_->write_legacy_notifications(after);
  });
  return committed.ok()
             ? common::Result<domain::Notification>::success(notification)
             : common::Result<domain::Notification>::failure(committed.error());
}

common::Result<std::optional<domain::Notification>>
SqliteNotificationRepository::find_sent_by_reminder_id(
    std::string_view reminder_id) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::optional<domain::Notification>>::failure(
        revoked("notification_repository.find_sent_by_reminder_id"));
  }
  auto loaded = database_->load_legacy_notifications();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Notification>>::failure(
        loaded.error());
  }
  for (auto it = loaded.value().rbegin(); it != loaded.value().rend(); ++it) {
    if (it->reminder_id ==
            std::optional<std::string>(std::string(reminder_id)) &&
        it->status == std::string(domain::kNotificationStatusSent)) {
      return common::Result<std::optional<domain::Notification>>::success(*it);
    }
  }
  return common::Result<std::optional<domain::Notification>>::success(
      std::nullopt);
}

common::Result<std::vector<domain::Notification>>
SqliteNotificationRepository::find_all() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<std::vector<domain::Notification>>::failure(
        revoked("notification_repository.find_all"));
  }
  return database_->load_legacy_notifications();
}

SqliteEventReminderTransaction::SqliteEventReminderTransaction(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteEventReminderTransaction::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("event_reminder_transaction.initialize"))
             : database_->validate();
}

common::Result<common::Unit> SqliteEventReminderTransaction::execute(
    const Operation& operation) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("event_reminder_transaction.execute"))
             : database_->transaction(operation);
}

SqliteReminderNotificationTransaction::SqliteReminderNotificationTransaction(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit>
SqliteReminderNotificationTransaction::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("reminder_notification_transaction.initialize"))
             : database_->validate();
}

common::Result<common::Unit> SqliteReminderNotificationTransaction::execute(
    const Operation& operation) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("reminder_notification_transaction.execute"))
             : database_->transaction(operation);
}

SqliteRecurringEventTransaction::SqliteRecurringEventTransaction(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteRecurringEventTransaction::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("v4_transaction.initialize"))
             : database_->validate();
}

common::Result<repository::RecurringEventState>
SqliteRecurringEventTransaction::load() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::RecurringEventState>::failure(
                   revoked("v4_transaction.load"))
             : database_->load_recurring_state();
}

common::Result<common::Unit>
SqliteRecurringEventTransaction::prepare_notification(
    const NotificationPrepareOperation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked("v4_transaction.prepare_notification"));
  }
  return database_->transaction([&]() {
    auto loaded = database_->load_recurring_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(loaded.value(), after.notifications);
    return applied.ok()
               ? database_->write_recurring_changes(loaded.value(), after)
               : applied;
  });
}

common::Result<common::Unit> SqliteRecurringEventTransaction::update_reminders(
    const ReminderUpdateOperation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked("v4_transaction.update_reminders"));
  }
  return database_->transaction([&]() {
    auto loaded = database_->load_recurring_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(loaded.value(), after.reminders);
    return applied.ok()
               ? database_->write_recurring_changes(loaded.value(), after)
               : applied;
  });
}

common::Result<common::Unit> SqliteRecurringEventTransaction::execute(
    std::string_view operation, std::string transaction_id,
    std::string prepared_at, const Operation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked("v4_transaction.execute"));
  }
  if (!common::is_uuid(transaction_id) ||
      !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(invalid_workflow_identity());
  }
  (void)operation;
  return database_->transaction([&]() {
    auto loaded = database_->load_recurring_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(after);
    return applied.ok()
               ? database_->write_recurring_changes(loaded.value(), after)
               : applied;
  });
}

SqliteAnniversaryTransaction::SqliteAnniversaryTransaction(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteAnniversaryTransaction::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("anniversary_transaction.initialize"))
             : database_->validate();
}

common::Result<repository::AnniversaryState>
SqliteAnniversaryTransaction::load() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::AnniversaryState>::failure(
                   revoked("anniversary_transaction.load"))
             : database_->load_anniversary_state();
}

common::Result<repository::AnniversaryOccurrenceSnapshot>
SqliteAnniversaryTransaction::load_occurrence_snapshot() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::AnniversaryOccurrenceSnapshot>::
                   failure(revoked(
                       "anniversary_transaction.load_occurrence_snapshot"))
             : database_->load_anniversary_occurrence_snapshot();
}

common::Result<common::Unit> SqliteAnniversaryTransaction::execute(
    std::string_view operation, std::string transaction_id,
    std::string prepared_at, const Operation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked("anniversary_transaction.execute"));
  }
  if (!is_anniversary_operation(operation) ||
      !common::is_uuid(transaction_id) ||
      !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(
        invalid_anniversary_metadata());
  }
  return database_->transaction([&]() {
    auto loaded = database_->load_anniversary_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(after);
    return applied.ok()
               ? database_->write_anniversary_changes(loaded.value(), after)
               : applied;
  });
}

SqliteCategoryRepository::SqliteCategoryRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteCategoryRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("category.initialize"))
             : database_->validate();
}

common::Result<repository::CategoryState> SqliteCategoryRepository::load() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::CategoryState>::failure(
                   revoked("category.list"))
             : database_->load_category_state();
}

common::Result<common::Unit> SqliteCategoryRepository::execute(
    std::string_view operation, const Operation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked(std::string(operation)));
  }
  if (operation != "category_create" || !action) {
    return common::Result<common::Unit>::failure(invalid_category_operation());
  }
  return database_->transaction([&]() {
    auto loaded = database_->load_category_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(after);
    return applied.ok()
               ? database_->write_category_changes(loaded.value(), after)
               : applied;
  });
}

SqliteHabitTransaction::SqliteHabitTransaction(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteHabitTransaction::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("habit_transaction.initialize"))
             : database_->validate();
}

common::Result<repository::HabitState> SqliteHabitTransaction::load() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::HabitState>::failure(
                   revoked("habit_transaction.load"))
             : database_->load_habit_state();
}

common::Result<common::Unit> SqliteHabitTransaction::execute(
    std::string_view operation, const Operation& action) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !access.has_value()) {
    return common::Result<common::Unit>::failure(
        revoked(std::string(operation)));
  }
  if (operation.rfind("habit.", 0) != 0 || !action) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Habit transaction operation is invalid"}}));
  }
  return database_->transaction([&]() {
    auto loaded = database_->load_habit_state();
    if (!loaded.ok())
      return common::Result<common::Unit>::failure(loaded.error());
    auto after = loaded.value();
    auto applied = action(after);
    return applied.ok() ? database_->write_habit_changes(loaded.value(), after)
                        : applied;
  });
}

SqliteCalendarQueryRepository::SqliteCalendarQueryRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteCalendarQueryRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("calendar_query_repository.initialize"))
             : database_->validate();
}

common::Result<repository::CalendarQuerySnapshot>
SqliteCalendarQueryRepository::load_snapshot(
    const std::optional<std::array<
        std::int64_t,
        repository::kCalendarQueryContributingStores.size()>>&
        expected_generations) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::CalendarQuerySnapshot>::failure(
                   revoked("calendar_query_repository.load_snapshot"))
             : database_->load_calendar_query_snapshot(expected_generations);
}

SqliteSearchQueryRepository::SqliteSearchQueryRepository(
    std::shared_ptr<SqliteCalendarDatabase> database,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : database_(std::move(database)), runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> SqliteSearchQueryRepository::initialize() {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<common::Unit>::failure(
                   revoked("search_query_repository.initialize"))
             : database_->validate();
}

common::Result<repository::SearchQuerySnapshot>
SqliteSearchQueryRepository::load_snapshot(
    const std::vector<domain::SearchTargetType>& requested_targets,
    const std::optional<std::array<
        std::int64_t, repository::kSearchQueryContributingStores.size()>>&
        expected_generations) {
  auto access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  return runtime_lease_ && !access.has_value()
             ? common::Result<repository::SearchQuerySnapshot>::failure(
                   revoked("search_query_repository.load_snapshot"))
             : database_->load_search_query_snapshot(requested_targets,
                                                       expected_generations);
}

}  // namespace excellent_calendar::storage::sqlite
