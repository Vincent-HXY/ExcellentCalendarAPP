cmake_minimum_required(VERSION 3.22.1)

project(excellent_calendar_core LANGUAGES C CXX)

add_library(
    excellent_calendar_sqlite
    STATIC
    third_party/sqlite/sqlite3.c
)

set_target_properties(
    excellent_calendar_sqlite
    PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
)

target_compile_definitions(
    excellent_calendar_sqlite
    PRIVATE
    SQLITE_DEFAULT_FOREIGN_KEYS=1
    SQLITE_DEFAULT_WAL_SYNCHRONOUS=2
    SQLITE_DQS=0
    SQLITE_ENABLE_API_ARMOR=1
    SQLITE_OMIT_LOAD_EXTENSION=1
    SQLITE_TEMP_STORE=2
    SQLITE_THREADSAFE=1
)

target_include_directories(
    excellent_calendar_sqlite
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sqlite
)

add_library(
    excellent_calendar_date_tz
    STATIC
    third_party/date/src/tz.cpp
)

target_compile_features(excellent_calendar_date_tz PUBLIC cxx_std_17)
target_compile_definitions(
    excellent_calendar_date_tz
    PUBLIC
    USE_OS_TZDB=0
    PRIVATE
    AUTO_DOWNLOAD=0
    DATE_DISABLE_WINDOWS_ZONE_MAPPING=1
    HAS_REMOTE_API=0
)
target_include_directories(
    excellent_calendar_date_tz
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/date/include
)

if(NOT MSVC)
    find_package(Threads REQUIRED)
    target_link_libraries(excellent_calendar_date_tz PUBLIC Threads::Threads)
endif()

add_library(
    excellent_calendar_core
    STATIC
    src/application/anniversary_reminder_projection.cpp
    src/application/anniversary_query_service.cpp
    src/application/anniversary_workflow_service.cpp
    src/application/category_service.cpp
    src/application/calendar_view_query_service.cpp
    src/application/completed_recurring_series_eligibility.cpp
    src/application/event_service.cpp
    src/application/create_event_workflow_service.cpp
    src/application/event_lifecycle_workflow_service.cpp
    src/application/recurrence_service.cpp
    src/application/recurring_event_query_service.cpp
    src/application/recurring_event_workflow_service.cpp
    src/application/recurring_reminder_delivery_workflow_service.cpp
    src/application/recurring_reminder_query_service.cpp
    src/application/reminder_recovery_workflow_service.cpp
    src/application/reminder_snooze_workflow_service.cpp
    src/application/reminder_service.cpp
    src/application/reminder_service_v2.cpp
    src/application/rolling_reminder_service.cpp
    src/application/search_query_service.cpp
    src/application/notification_service.cpp
    src/boundary/api/event_api.cpp
    src/boundary/api/anniversary_v2_endpoint.cpp
    src/boundary/api/habit_v2_endpoint.cpp
    src/boundary/api/category_v2_endpoint.cpp
    src/boundary/api/calendar_view_v2_endpoint.cpp
    src/boundary/api/event_v2_endpoint.cpp
    src/boundary/api/native_runtime.cpp
    src/boundary/api/notification_api.cpp
    src/boundary/api/recurring_v2_api_support.cpp
    src/boundary/api/recurring_v2_api.cpp
    src/boundary/api/reminder_api.cpp
    src/boundary/api/reminder_v2_endpoint.cpp
    src/boundary/api/search_v2_endpoint.cpp
    src/boundary/api/runtime_v2_endpoint.cpp
    src/boundary/contract/consume_reminder_after_delivery_response.cpp
    src/boundary/contract/anniversary_json.cpp
    src/boundary/contract/habit_json.cpp
    src/boundary/contract/category_json.cpp
    src/boundary/contract/calendar_view_json.cpp
    src/boundary/contract/event_list_response.cpp
    src/boundary/contract/event_response.cpp
    src/boundary/contract/native_result.cpp
    src/boundary/contract/notification_response.cpp
    src/boundary/contract/reminder_list_response.cpp
    src/boundary/contract/reminder_response.cpp
    src/boundary/contract/recurring_v2_json.cpp
    src/boundary/contract/schedulable_reminder_list_response.cpp
    src/boundary/contract/search_json.cpp
    src/common/clock.cpp
    src/common/datetime.cpp
    src/common/error_code_metadata.cpp
    src/common/failure_reason.cpp
    src/common/id_generator.cpp
    src/common/string_utils.cpp
    src/common/search_token_crypto.cpp
    src/common/uuid.cpp
    src/application/habit_service.cpp
    src/domain/data_source.cpp
    src/domain/anniversary.cpp
    src/domain/category.cpp
    src/domain/event_status.cpp
    src/domain/habit.cpp
    src/domain/event_occurrence_state.cpp
    src/domain/importance.cpp
    src/domain/local_time_resolver.cpp
    src/domain/notification.cpp
    src/domain/recurrence.cpp
    src/domain/reminder.cpp
    src/domain/reminder_recovery_batch.cpp
    src/domain/search.cpp
    src/infrastructure/time/tzdb_local_time_resolver.cpp
    src/storage/runtime_storage_lease.cpp
    src/storage/json/atomic_json_file_store.cpp
    src/storage/json/anniversary_json_codec.cpp
    src/storage/json/category_json_codec.cpp
    src/storage/json/habit_json_codec.cpp
    src/storage/json/habit_state_validator.cpp
    src/storage/json/calendar_core_v2_storage_bootstrap.cpp
    src/storage/json/calendar_core_v3_storage_bootstrap.cpp
    src/storage/json/calendar_workflow_coordinator.cpp
    src/storage/json/json_event_repository.cpp
    src/storage/json/json_anniversary_transaction.cpp
    src/storage/json/json_category_repository.cpp
    src/storage/json/json_event_reminder_transaction.cpp
    src/storage/json/json_notification_repository.cpp
    src/storage/json/json_reminder_repository.cpp
    src/storage/json/json_reminder_notification_transaction.cpp
    src/storage/json/json_recurring_event_transaction.cpp
    src/storage/json/json_snapshot_transaction.cpp
    src/storage/json/recurring_event_json_codec.cpp
    src/storage/json/recurring_event_state_validator.cpp
    src/storage/sqlite/sqlite_calendar_database.cpp
    src/storage/sqlite/sqlite_repository_adapters.cpp
)

target_compile_features(excellent_calendar_core PUBLIC cxx_std_17)

target_link_libraries(
    excellent_calendar_core
    PUBLIC
    excellent_calendar_date_tz
    PRIVATE
    excellent_calendar_sqlite
)

if(WIN32)
    target_link_libraries(excellent_calendar_core PRIVATE bcrypt)
endif()

target_include_directories(
    excellent_calendar_core
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

option(EXCELLENT_CALENDAR_BUILD_TESTS "Build Excellent Calendar C++ tests" OFF)

if(EXCELLENT_CALENDAR_BUILD_TESTS)
    enable_testing()
    find_package(Python3 COMPONENTS Interpreter REQUIRED)

    add_test(
        NAME excellent_calendar_search_contract_validation
        COMMAND ${Python3_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/../contracts/run_search_v1_validation.py
    )

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

    add_executable(
        excellent_calendar_recurrence_tests
        tests/recurrence_core_tests.cpp
    )

    target_compile_definitions(
        excellent_calendar_recurrence_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
    )

    target_link_libraries(
        excellent_calendar_recurrence_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(NAME excellent_calendar_recurrence_tests COMMAND excellent_calendar_recurrence_tests)

    add_executable(
        excellent_calendar_boundary_v2_tests
        tests/boundary_v2_characterization_tests.cpp
    )

    target_link_libraries(
        excellent_calendar_boundary_v2_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(
        NAME excellent_calendar_boundary_v2_tests
        COMMAND excellent_calendar_boundary_v2_tests
    )

    add_executable(
        excellent_calendar_anniversary_tests
        tests/anniversary_core_tests.cpp
    )

    target_compile_definitions(
        excellent_calendar_anniversary_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
    )

    target_link_libraries(
        excellent_calendar_anniversary_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(
        NAME excellent_calendar_anniversary_tests
        COMMAND excellent_calendar_anniversary_tests
    )

    add_executable(
        excellent_calendar_category_tests
        tests/category_core_tests.cpp
    )

    target_compile_definitions(
        excellent_calendar_category_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
    )

    target_link_libraries(
        excellent_calendar_category_tests
        PRIVATE
        excellent_calendar_core
    )

    add_test(
        NAME excellent_calendar_category_tests
        COMMAND excellent_calendar_category_tests
    )

    add_executable(
        excellent_calendar_storage_v3_tests
        tests/storage_v3_tests.cpp
    )

    target_link_libraries(
        excellent_calendar_storage_v3_tests
        PRIVATE
        excellent_calendar_core
    )

    target_compile_definitions(
        excellent_calendar_storage_v3_tests
        PRIVATE
        EXCELLENT_CALENDAR_STORAGE_V3_GOLDEN="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/fixtures/anniversary/storage_v2_to_v3.golden.json"
    )

    add_test(
        NAME excellent_calendar_storage_v3_tests
        COMMAND excellent_calendar_storage_v3_tests
    )

    add_executable(
        excellent_calendar_storage_v5_tests
        tests/storage_v5_tests.cpp
    )
    target_link_libraries(
        excellent_calendar_storage_v5_tests
        PRIVATE
        excellent_calendar_core
    )
    add_test(
        NAME excellent_calendar_storage_v5_tests
        COMMAND excellent_calendar_storage_v5_tests
    )

    add_executable(
        excellent_calendar_habit_tests
        tests/habit_core_tests.cpp
    )
    target_link_libraries(
        excellent_calendar_habit_tests
        PRIVATE
        excellent_calendar_core
    )
    target_compile_definitions(
        excellent_calendar_habit_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
    )
    add_test(
        NAME excellent_calendar_habit_tests
        COMMAND excellent_calendar_habit_tests
    )

    add_executable(
        excellent_calendar_habit_reminder_tests
        tests/habit_reminder_tests.cpp
    )
    target_link_libraries(
        excellent_calendar_habit_reminder_tests
        PRIVATE
        excellent_calendar_core
    )
    add_test(
        NAME excellent_calendar_habit_reminder_tests
        COMMAND excellent_calendar_habit_reminder_tests
    )

    add_executable(
        excellent_calendar_view_query_tests
        tests/calendar_view_query_tests.cpp
    )
    target_compile_definitions(
        excellent_calendar_view_query_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
    )
    target_link_libraries(
        excellent_calendar_view_query_tests
        PRIVATE
        excellent_calendar_core
        excellent_calendar_sqlite
    )
    add_test(
        NAME excellent_calendar_view_query_tests
        COMMAND excellent_calendar_view_query_tests
    )

    add_executable(
        excellent_calendar_search_tests
        tests/search_core_tests.cpp
    )
    target_link_libraries(
        excellent_calendar_search_tests
        PRIVATE
        excellent_calendar_core
        excellent_calendar_sqlite
    )
    target_compile_definitions(
        excellent_calendar_search_tests
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
        EXCELLENT_CALENDAR_SEARCH_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/fixtures/search"
    )
    add_test(
        NAME excellent_calendar_search_tests
        COMMAND excellent_calendar_search_tests
    )

    add_executable(
        excellent_calendar_search_performance
        tests/search_performance_tests.cpp
    )
    target_compile_definitions(
        excellent_calendar_search_performance
        PRIVATE
        EXCELLENT_CALENDAR_TEST_TZDB_DIR="${CMAKE_CURRENT_SOURCE_DIR}/third_party/tzdata/2026c"
        EXCELLENT_CALENDAR_SEARCH_PERFORMANCE_RELEASE=$<IF:$<CONFIG:Release>,1,0>
    )
    target_link_libraries(
        excellent_calendar_search_performance
        PRIVATE
        excellent_calendar_core
        excellent_calendar_sqlite
    )
    if(WIN32)
        target_link_libraries(excellent_calendar_search_performance PRIVATE psapi)
    endif()

    add_custom_target(
        excellent_calendar_check
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
        DEPENDS
        excellent_calendar_core_tests
        excellent_calendar_reminder_tests
        excellent_calendar_recurrence_tests
        excellent_calendar_boundary_v2_tests
        excellent_calendar_anniversary_tests
        excellent_calendar_category_tests
        excellent_calendar_storage_v3_tests
        excellent_calendar_storage_v5_tests
        excellent_calendar_habit_tests
        excellent_calendar_habit_reminder_tests
        excellent_calendar_view_query_tests
        excellent_calendar_search_tests
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        USES_TERMINAL
    )
endif()
