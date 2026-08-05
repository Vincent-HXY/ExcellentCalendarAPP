#include "excellent_calendar/boundary/api/native_runtime.hpp"

#include <filesystem>
#include <mutex>

#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/application/event_lifecycle_workflow_service.hpp"
#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/reminder_service_v2.hpp"
#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_event_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"
#include "excellent_calendar/storage/json/json_event_reminder_transaction.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_notification_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"
#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"
#include "excellent_calendar/storage/json/calendar_core_v2_storage_bootstrap.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::boundary::api {
namespace {

struct RuntimeState {
  std::shared_ptr<storage::json::JsonEventRepository> event_repository;
  std::shared_ptr<application::EventService> event_service;
  std::shared_ptr<storage::json::JsonEventReminderTransaction> event_reminder_transaction;
  std::shared_ptr<application::CreateEventWorkflowService> create_event_workflow_service;
  std::shared_ptr<application::EventLifecycleWorkflowService> event_lifecycle_workflow_service;
  std::shared_ptr<storage::json::JsonReminderRepository> reminder_repository;
  std::shared_ptr<application::ReminderService> reminder_service;
  std::shared_ptr<storage::json::JsonNotificationRepository> notification_repository;
  std::shared_ptr<storage::json::JsonReminderNotificationTransaction> reminder_notification_transaction;
  std::shared_ptr<application::NotificationService> notification_service;
  std::shared_ptr<infrastructure::time::TzdbLocalTimeResolver> local_time_resolver;
  std::shared_ptr<application::RecurrenceService> recurrence_service;
  std::shared_ptr<application::RollingReminderService> rolling_reminder_service;
  std::shared_ptr<storage::json::JsonRecurringEventTransaction> recurring_event_transaction;
  std::shared_ptr<application::RecurringEventQueryService> recurring_event_query_service;
  std::shared_ptr<application::RecurringEventWorkflowService> recurring_event_workflow_service;
  std::shared_ptr<application::RecurringReminderDeliveryWorkflowService>
      recurring_reminder_delivery_workflow_service;
  std::shared_ptr<application::ReminderRecoveryWorkflowService>
      reminder_recovery_workflow_service;
  std::shared_ptr<application::RecurringReminderQueryService>
      recurring_reminder_query_service;
  std::shared_ptr<application::ReminderServiceV2> reminder_service_v2;
  std::shared_ptr<storage::RuntimeStorageLease> writer_lease;
  std::string storage_directory;
  std::string recurring_storage_directory;
};

std::mutex g_state_mutex;
std::mutex g_initialization_mutex;
RuntimeState g_state;

void clear_runtime_state() {
  RuntimeState previous;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    previous = std::move(g_state);
    g_state = RuntimeState{};
  }
  // Do not wait for an in-flight transaction while holding the state mutex.
  // New getters already see an empty runtime; old borrowers are drained and revoked here.
  if (previous.writer_lease) {
    previous.writer_lease->revoke();
  }
}

}  // namespace

common::Result<common::Unit> initialize_runtime(std::string_view storage_directory) {
  std::lock_guard<std::mutex> initialization_lock(g_initialization_mutex);
  clear_runtime_state();
  const auto directory = std::string(storage_directory);
  auto writer_lease = std::make_shared<storage::RuntimeStorageLease>();

  auto event_repository = std::make_shared<storage::json::JsonEventRepository>(
      std::filesystem::path(directory), writer_lease);
  auto event_reminder_transaction =
      std::make_shared<storage::json::JsonEventReminderTransaction>(
          std::filesystem::path(directory), writer_lease);
  auto transaction_initialized = event_reminder_transaction->initialize();
  if (!transaction_initialized.ok()) {
    return common::Result<common::Unit>::failure(transaction_initialized.error());
  }
  auto event_initialized = event_repository->initialize();
  if (!event_initialized.ok()) {
    return common::Result<common::Unit>::failure(event_initialized.error());
  }

  auto reminder_repository = std::make_shared<storage::json::JsonReminderRepository>(
      std::filesystem::path(directory), writer_lease);
  auto reminder_notification_transaction =
      std::make_shared<storage::json::JsonReminderNotificationTransaction>(
          std::filesystem::path(directory), writer_lease);
  auto delivery_transaction_initialized = reminder_notification_transaction->initialize();
  if (!delivery_transaction_initialized.ok()) {
    return common::Result<common::Unit>::failure(delivery_transaction_initialized.error());
  }
  auto reminder_initialized = reminder_repository->initialize();
  if (!reminder_initialized.ok()) {
    return common::Result<common::Unit>::failure(reminder_initialized.error());
  }

  auto notification_repository = std::make_shared<storage::json::JsonNotificationRepository>(
      std::filesystem::path(directory), writer_lease);
  auto notification_initialized = notification_repository->initialize();
  if (!notification_initialized.ok()) {
    return common::Result<common::Unit>::failure(notification_initialized.error());
  }

  auto event_service = std::make_shared<application::EventService>(
      event_repository,
      common::utc_now_iso8601,
      common::generate_uuid_v4);
  auto reminder_service = std::make_shared<application::ReminderService>(
      reminder_repository,
      event_repository,
      common::utc_now_iso8601,
      common::generate_uuid_v4);
  auto notification_service = std::make_shared<application::NotificationService>(
      reminder_repository,
      notification_repository,
      reminder_notification_transaction,
      common::utc_now_iso8601,
      common::generate_uuid_v4);
  auto create_event_workflow_service = std::make_shared<application::CreateEventWorkflowService>(
      event_service,
      reminder_service,
      event_reminder_transaction);
  auto event_lifecycle_workflow_service = std::make_shared<application::EventLifecycleWorkflowService>(
      event_service,
      reminder_repository,
      event_reminder_transaction,
      common::utc_now_iso8601);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_state.event_repository = std::move(event_repository);
    g_state.event_service = std::move(event_service);
    g_state.event_reminder_transaction = std::move(event_reminder_transaction);
    g_state.create_event_workflow_service = std::move(create_event_workflow_service);
    g_state.event_lifecycle_workflow_service = std::move(event_lifecycle_workflow_service);
    g_state.reminder_repository = std::move(reminder_repository);
    g_state.reminder_service = std::move(reminder_service);
    g_state.notification_repository = std::move(notification_repository);
    g_state.reminder_notification_transaction = std::move(reminder_notification_transaction);
    g_state.notification_service = std::move(notification_service);
    g_state.writer_lease = std::move(writer_lease);
    g_state.storage_directory = directory;
  }

  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<RecurringRuntimeInitializationResult> initialize_recurring_runtime(
    std::string_view storage_directory,
    std::string_view tzdb_directory) {
  std::lock_guard<std::mutex> initialization_lock(g_initialization_mutex);
  // A failed re-initialization must never leave a previously opened writer reachable.
  // Candidate services are published only after every v2 preflight succeeds.
  clear_runtime_state();
  if (storage_directory.empty()) {
    return common::Result<RecurringRuntimeInitializationResult>::failure(common::make_error(
        "STORAGE_PATH_INVALID", "Storage path is invalid or not writable",
        {{"field", "storage_directory"}}));
  }
  if (tzdb_directory.empty()) {
    return common::Result<RecurringRuntimeInitializationResult>::failure(common::make_error(
        "TIMEZONE_DATABASE_UNAVAILABLE",
        "Bundled timezone database is missing, corrupted, or has the wrong version",
        {{"field", "tzdb_directory"}}));
  }
  auto resolver = infrastructure::time::TzdbLocalTimeResolver::create(
      std::filesystem::path(std::string(tzdb_directory)));
  if (!resolver.ok()) {
    return common::Result<RecurringRuntimeInitializationResult>::failure(resolver.error());
  }
  const auto archive_time = common::utc_now_iso8601();
  auto prepared_storage = storage::json::prepare_calendar_core_v2_storage(
      std::filesystem::path(std::string(storage_directory)), archive_time);
  if (!prepared_storage.ok()) {
    return common::Result<RecurringRuntimeInitializationResult>::failure(
        prepared_storage.error());
  }
  auto writer_lease = std::make_shared<storage::RuntimeStorageLease>();
  auto transaction = std::make_shared<storage::json::JsonRecurringEventTransaction>(
      std::filesystem::path(std::string(storage_directory)),
      storage::json::JsonRecurringEventTransaction::FailureHook{}, writer_lease);
  auto initialized = transaction->initialize();
  if (!initialized.ok()) {
    return common::Result<RecurringRuntimeInitializationResult>::failure(initialized.error());
  }
  auto recurrence = std::make_shared<application::RecurrenceService>(resolver.value());
  auto rolling = std::make_shared<application::RollingReminderService>(recurrence);
  auto event_workflow = std::make_shared<application::RecurringEventWorkflowService>(
      transaction, recurrence, rolling, common::utc_now_iso8601, common::generate_uuid_v4);
  auto event_query = std::make_shared<application::RecurringEventQueryService>(
      transaction, recurrence);
  auto delivery_workflow =
      std::make_shared<application::RecurringReminderDeliveryWorkflowService>(
          transaction, rolling, common::utc_now_iso8601, common::generate_uuid_v4);
  auto recovery_workflow = std::make_shared<application::ReminderRecoveryWorkflowService>(
      transaction, recurrence, rolling, common::utc_now_iso8601, common::generate_uuid_v4);
  auto reminder_query = std::make_shared<application::RecurringReminderQueryService>(
      transaction, common::utc_now_iso8601);
  auto reminder_service_v2 = std::make_shared<application::ReminderServiceV2>(
      transaction, common::utc_now_iso8601, common::generate_uuid_v4);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_state.local_time_resolver = resolver.value();
    g_state.recurrence_service = std::move(recurrence);
    g_state.rolling_reminder_service = std::move(rolling);
    g_state.recurring_event_transaction = std::move(transaction);
    g_state.recurring_event_query_service = std::move(event_query);
    g_state.recurring_event_workflow_service = std::move(event_workflow);
    g_state.recurring_reminder_delivery_workflow_service = std::move(delivery_workflow);
    g_state.reminder_recovery_workflow_service = std::move(recovery_workflow);
    g_state.recurring_reminder_query_service = std::move(reminder_query);
    g_state.reminder_service_v2 = std::move(reminder_service_v2);
    g_state.writer_lease = std::move(writer_lease);
    g_state.recurring_storage_directory = std::string(storage_directory);
  }
  return common::Result<RecurringRuntimeInitializationResult>::success(
      RecurringRuntimeInitializationResult{true, 2, resolver.value()->tzdb_version()});
}

std::shared_ptr<application::EventService> current_event_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.event_service;
}

std::shared_ptr<application::CreateEventWorkflowService> current_create_event_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.create_event_workflow_service;
}

std::shared_ptr<application::EventLifecycleWorkflowService> current_event_lifecycle_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.event_lifecycle_workflow_service;
}

std::shared_ptr<application::ReminderService> current_reminder_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.reminder_service;
}

std::shared_ptr<application::NotificationService> current_notification_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.notification_service;
}

std::shared_ptr<application::RecurringEventWorkflowService>
current_recurring_event_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.recurring_event_workflow_service;
}

std::shared_ptr<application::RecurringEventQueryService>
current_recurring_event_query_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.recurring_event_query_service;
}

std::shared_ptr<application::RecurringReminderDeliveryWorkflowService>
current_recurring_reminder_delivery_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.recurring_reminder_delivery_workflow_service;
}

std::shared_ptr<application::ReminderRecoveryWorkflowService>
current_reminder_recovery_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.reminder_recovery_workflow_service;
}

std::shared_ptr<application::RecurringReminderQueryService>
current_recurring_reminder_query_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.recurring_reminder_query_service;
}

std::shared_ptr<application::ReminderServiceV2> current_reminder_service_v2() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.reminder_service_v2;
}

std::shared_ptr<domain::LocalTimeResolver> current_local_time_resolver() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.local_time_resolver;
}

common::Error storage_not_initialized_error(std::string operation) {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED",
      "Native storage has not been initialized",
      {{"operation", std::move(operation)}});
}

std::string current_storage_directory() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return !g_state.recurring_storage_directory.empty()
             ? g_state.recurring_storage_directory
             : g_state.storage_directory;
}

}  // namespace excellent_calendar::boundary::api
