cmake_minimum_required(VERSION 3.22.1)

project(excellent_calendar_core LANGUAGES CXX)

add_library(
    excellent_calendar_core
    STATIC
    src/application/event_service.cpp
    src/application/create_event_workflow_service.cpp
    src/application/reminder_service.cpp
    src/application/notification_service.cpp
    src/boundary/api/event_api.cpp
    src/boundary/api/native_runtime.cpp
    src/boundary/api/notification_api.cpp
    src/boundary/api/reminder_api.cpp
    src/boundary/contract/consume_reminder_after_delivery_response.cpp
    src/boundary/contract/event_list_response.cpp
    src/boundary/contract/event_response.cpp
    src/boundary/contract/native_result.cpp
    src/boundary/contract/notification_response.cpp
    src/boundary/contract/reminder_list_response.cpp
    src/boundary/contract/reminder_response.cpp
    src/boundary/contract/schedulable_reminder_list_response.cpp
    src/common/clock.cpp
    src/common/datetime.cpp
    src/common/failure_reason.cpp
    src/common/id_generator.cpp
    src/common/string_utils.cpp
    src/domain/data_source.cpp
    src/domain/event_status.cpp
    src/domain/importance.cpp
    src/domain/notification.cpp
    src/domain/reminder.cpp
    src/storage/json/atomic_json_file_store.cpp
    src/storage/json/json_event_repository.cpp
    src/storage/json/json_event_reminder_transaction.cpp
    src/storage/json/json_notification_repository.cpp
    src/storage/json/json_reminder_repository.cpp
    src/storage/json/json_reminder_notification_transaction.cpp
    src/storage/json/json_snapshot_transaction.cpp
)

target_compile_features(excellent_calendar_core PUBLIC cxx_std_17)

target_include_directories(
    excellent_calendar_core
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

option(EXCELLENT_CALENDAR_BUILD_TESTS "Build Excellent Calendar C++ tests" OFF)

if(EXCELLENT_CALENDAR_BUILD_TESTS)
    enable_testing()

    add_executable(
        excellent_calendar_core_tests
        tests/event_core_tests.cpp
    )

    target_link_libraries(
        excellent_calendar_core_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(NAME excellent_calendar_core_tests COMMAND excellent_calendar_core_tests)

    add_executable(
        excellent_calendar_reminder_tests
        tests/reminder_core_tests.cpp
    )

    target_link_libraries(
        excellent_calendar_reminder_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(NAME excellent_calendar_reminder_tests COMMAND excellent_calendar_reminder_tests)

    add_custom_target(
        excellent_calendar_check
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
        DEPENDS
        excellent_calendar_core_tests
        excellent_calendar_reminder_tests
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        USES_TERMINAL
    )
endif()
