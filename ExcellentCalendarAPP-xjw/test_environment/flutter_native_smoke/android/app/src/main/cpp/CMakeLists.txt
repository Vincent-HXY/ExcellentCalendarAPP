cmake_minimum_required(VERSION 3.22.1)

project(native_smoke)

add_library(native_smoke SHARED native_ping.cpp)

target_compile_features(native_smoke PRIVATE cxx_std_17)
