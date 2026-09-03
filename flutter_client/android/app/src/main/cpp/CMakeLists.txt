cmake_minimum_required(VERSION 3.22.1)

project(excellent_calendar_native)

add_subdirectory(
    ../../../../../../cpp_core
    ${CMAKE_CURRENT_BINARY_DIR}/excellent_calendar_core
)

# The v2 runtime installs the bundled IANA source database into app-private storage.
# USE_OS_TZDB=0 is owned by cpp_core and selects Howard Hinnant date's source
# database reader. Keep Android's platform macros intact while system headers are
# parsed, then let the vendored source opt out of date's Android-binary branches.
if(ANDROID)
    target_compile_definitions(
        excellent_calendar_date_tz
        PRIVATE
        EXCELLENT_CALENDAR_DATE_SOURCE_TZDB_ANDROID=1
    )
endif()

add_library(
    excellent_calendar_native
    SHARED
    boundary/adapter/jni/event_jni.cpp
    boundary/adapter/jni/habit_jni.cpp
    boundary/adapter/jni/calendar_view_jni.cpp
    boundary/adapter/jni/search_jni.cpp
)

target_compile_features(excellent_calendar_native PRIVATE cxx_std_17)

target_link_libraries(
    excellent_calendar_native
    PRIVATE
    excellent_calendar_core
    log
)
