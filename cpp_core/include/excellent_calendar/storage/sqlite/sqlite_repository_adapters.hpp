#pragma once

#include <memory>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/repository/anniversary_transaction.hpp"
#include "excellent_calendar/repository/category_repository.hpp"
#include "excellent_calendar/repository/event_reminder_transaction.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/repository/notification_repository.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"
#include "excellent_calendar/repository/reminder_notification_transaction.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

namespace excellent_calendar::storage::sqlite {

class SqliteEventRepository final : public repository::EventRepository {
 public:
  explicit SqliteEventRepository(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();
  common::Result<domain::Event> create(const domain::Event& event) override;
  common::Result<domain::Event> update(const domain::Event& event) override;
  common::Result<std::optional<domain::Event>> find_by_id(
      std::string_view id) override;
  common::Result<std::vector<domain::Event>> find_all() override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteReminderRepository final : public repository::ReminderRepository {
 public:
  explicit SqliteReminderRepository(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();
  common::Result<domain::Reminder> create(
      const domain::Reminder& reminder) override;
  common::Result<std::optional<domain::Reminder>> find_by_id(
      std::string_view id) override;
  common::Result<domain::Reminder> update(
      const domain::Reminder& reminder) override;
  common::Result<std::vector<domain::Reminder>> find_all() override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteNotificationRepository final
    : public repository::NotificationRepository {
 public:
  explicit SqliteNotificationRepository(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();
  common::Result<domain::Notification> create(
      const domain::Notification& notification) override;
  common::Result<std::optional<domain::Notification>> find_sent_by_reminder_id(
      std::string_view reminder_id) override;
  common::Result<std::vector<domain::Notification>> find_all() override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteEventReminderTransaction final
    : public repository::EventReminderTransaction {
 public:
  explicit SqliteEventReminderTransaction(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();
  common::Result<common::Unit> execute(const Operation& operation) override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteReminderNotificationTransaction final
    : public repository::ReminderNotificationTransaction {
 public:
  explicit SqliteReminderNotificationTransaction(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();
  common::Result<common::Unit> execute(const Operation& operation) override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteRecurringEventTransaction final
    : public repository::RecurringEventTransaction {
 public:
  explicit SqliteRecurringEventTransaction(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize() override;
  common::Result<repository::RecurringEventState> load() override;
  common::Result<common::Unit> prepare_notification(
      const NotificationPrepareOperation& action) override;
  common::Result<common::Unit> update_reminders(
      const ReminderUpdateOperation& action) override;
  common::Result<common::Unit> execute(std::string_view operation,
                                       std::string transaction_id,
                                       std::string prepared_at,
                                       const Operation& action) override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteAnniversaryTransaction final
    : public repository::AnniversaryTransaction {
 public:
  explicit SqliteAnniversaryTransaction(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize() override;
  common::Result<repository::AnniversaryState> load() override;
  common::Result<repository::AnniversaryOccurrenceSnapshot>
  load_occurrence_snapshot() override;
  common::Result<common::Unit> execute(std::string_view operation,
                                       std::string transaction_id,
                                       std::string prepared_at,
                                       const Operation& action) override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

class SqliteCategoryRepository final : public repository::CategoryRepository {
 public:
  explicit SqliteCategoryRepository(
      std::shared_ptr<SqliteCalendarDatabase> database,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize() override;
  common::Result<repository::CategoryState> load() override;
  common::Result<common::Unit> execute(std::string_view operation,
                                       const Operation& action) override;

 private:
  std::shared_ptr<SqliteCalendarDatabase> database_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

}  // namespace excellent_calendar::storage::sqlite
