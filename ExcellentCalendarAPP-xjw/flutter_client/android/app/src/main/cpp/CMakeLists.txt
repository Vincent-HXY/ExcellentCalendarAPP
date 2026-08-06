cmake_minimum_required(VERSION 3.22.1)

project(excellent_calendar_native)

add_subdirectory(
    ../../../../../../cpp_core
    ${CMAKE_CURRENT_BINARY_DIR}/excellent_calendar_core
)

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
