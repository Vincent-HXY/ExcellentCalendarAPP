#include "excellent_calendar/boundary/api/native_runtime.hpp"

#include <filesystem>
#include <mutex>

#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"
#include "excellent_calendar/storage/json/json_event_reminder_transaction.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_notification_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"

namespace excellent_calendar::boundary::api {
namespace {

struct RuntimeState {
  std::shared_ptr<storage::json::JsonEventRepository> event_repository;
  std::shared_ptr<application::EventService> event_service;
  std::shared_ptr<storage::json::JsonEventReminderTransaction> event_reminder_transaction;
  std::shared_ptr<application::CreateEventWorkflowService> create_event_workflow_service;
  std::shared_ptr<storage::json::JsonReminderRepository> reminder_repository;
  std::shared_ptr<application::ReminderService> reminder_service;
  std::shared_ptr<storage::json::JsonNotificationRepository> notification_repository;
  std::shared_ptr<storage::json::JsonReminderNotificationTransaction> reminder_notification_transaction;
  std::shared_ptr<application::NotificationService> notification_service;
  std::string storage_directory;
};

std::mutex g_state_mutex;
RuntimeState g_state;

}  // namespace

common::Result<common::Unit> initialize_runtime(std::string_view storage_directory) {
  const auto directory = std::string(storage_directory);

  auto event_repository = std::make_shared<storage::json::JsonEventRepository>(
      std::filesystem::path(directory));
  auto event_reminder_transaction =
      std::make_shared<storage::json::JsonEventReminderTransaction>(std::filesystem::path(directory));
  auto transaction_initialized = event_reminder_transaction->initialize();
  if (!transaction_initialized.ok()) {
    return common::Result<common::Unit>::failure(transaction_initialized.error());
  }
  auto event_initialized = event_repository->initialize();
  if (!event_initialized.ok()) {
    return common::Result<common::Unit>::failure(event_initialized.error());
  }

  auto reminder_repository = std::make_shared<storage::json::JsonReminderRepository>(
      std::filesystem::path(directory));
  auto reminder_notification_transaction =
      std::make_shared<storage::json::JsonReminderNotificationTransaction>(
          std::filesystem::path(directory));
  auto delivery_transaction_initialized = reminder_notification_transaction->initialize();
  if (!delivery_transaction_initialized.ok()) {
    return common::Result<common::Unit>::failure(delivery_transaction_initialized.error());
  }
  auto reminder_initialized = reminder_repository->initialize();
  if (!reminder_initialized.ok()) {
    return common::Result<common::Unit>::failure(reminder_initialized.error());
  }

  auto notification_repository = std::make_shared<storage::json::JsonNotificationRepository>(
      std::filesystem::path(directory));
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

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_state.event_repository = std::move(event_repository);
    g_state.event_service = std::move(event_service);
    g_state.event_reminder_transaction = std::move(event_reminder_transaction);
    g_state.create_event_workflow_service = std::move(create_event_workflow_service);
    g_state.reminder_repository = std::move(reminder_repository);
    g_state.reminder_service = std::move(reminder_service);
    g_state.notification_repository = std::move(notification_repository);
    g_state.reminder_notification_transaction = std::move(reminder_notification_transaction);
    g_state.notification_service = std::move(notification_service);
    g_state.storage_directory = directory;
  }

  return common::Result<common::Unit>::success(common::Unit{});
}

std::shared_ptr<application::EventService> current_event_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.event_service;
}

std::shared_ptr<application::CreateEventWorkflowService> current_create_event_workflow_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.create_event_workflow_service;
}

std::shared_ptr<application::ReminderService> current_reminder_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.reminder_service;
}

std::shared_ptr<application::NotificationService> current_notification_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.notification_service;
}

common::Error storage_not_initialized_error(std::string operation) {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED",
      "Native storage has not been initialized",
      {{"operation", std::move(operation)}});
}

std::string current_storage_directory() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.storage_directory;
}

}  // namespace excellent_calendar::boundary::api
