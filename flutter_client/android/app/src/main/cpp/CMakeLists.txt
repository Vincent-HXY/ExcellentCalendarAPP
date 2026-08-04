cmake_minimum_required(VERSION 3.22.1)

project(excellent_calendar_native)

add_subdirectory(
    ../../../../../../cpp_core
    ${CMAKE_CURRENT_BINARY_DIR}/excellent_calendar_core
)

# The v2 runtime installs the bundled IANA source database into app-private storage.
# Howard Hinnant date otherwise selects Android's binary tzdata reader from compiler
# predefined macros, which is incompatible with that directory format.
if(ANDROID)
    target_compile_options(
        excellent_calendar_date_tz
        PUBLIC
        -UANDROID
        -U__ANDROID__
    )
    # Android's libc does not provide wordexp(3). A harmless initial install
    # token disables that lookup; Kotlin supplies the real app-private path to
    # date::set_install before the database is loaded.
    target_compile_definitions(excellent_calendar_date_tz PRIVATE INSTALL=.)
endif()

add_library(
    excellent_calendar_native
    SHARED
    boundary/adapter/jni/event_jni.cpp
)

target_compile_features(excellent_calendar_native PRIVATE cxx_std_17)

target_link_libraries(
    excellent_calendar_native
    PRIVATE
    excellent_calendar_core
    log
)
