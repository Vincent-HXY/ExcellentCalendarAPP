cmake_minimum_required(VERSION 3.22.1)
project(sync_cipher_source_spike LANGUAGES C CXX)
file(TO_CMAKE_PATH "${SQLCIPHER_SOURCE}" SQLCIPHER_SOURCE)
file(TO_CMAKE_PATH "${LTC_SOURCE_DIR}" LTC_SOURCE_DIR)

# Isolated build; SQLCIPHER_SOURCE and LTC_SOURCE_DIR are verified scratch trees.
# Never changes the product SQLite provider or downloads a build dependency.
if(NOT EXISTS "${SQLCIPHER_SOURCE}/sqlite3.c" OR NOT EXISTS "${LTC_SOURCE_DIR}/src/headers/tomcrypt.h")
  message(FATAL_ERROR "Supply the pinned, generated SQLCipher and provider sources")
endif()
file(READ "${LTC_SOURCE_DIR}/src/prngs/rng_get_bytes.c" RNG_SOURCE)
if(NOT RNG_SOURCE MATCHES "!defined\\(EXCELLENT_CALENDAR_REQUIRE_OS_RNG\\)")
  message(FATAL_ERROR "The pinned provider needs the reviewed fail-closed OS entropy patch")
endif()
option(SYNC_SPIKE_STATIC_ANDROID "Run a Bionic-static ABI probe under QEMU/user or Android" OFF)
file(GLOB_RECURSE LTC_SOURCES CONFIGURE_DEPENDS "${LTC_SOURCE_DIR}/src/*.c")
add_library(sync_spike_ltc STATIC ${LTC_SOURCES})
target_include_directories(sync_spike_ltc PUBLIC "${LTC_SOURCE_DIR}/src/headers")
target_compile_definitions(sync_spike_ltc PUBLIC
  LTC_NOTHING LTC_NO_MATH LTC_RIJNDAEL LTC_CBC_MODE LTC_SHA1 LTC_SHA256 LTC_SHA512
  LTC_HMAC LTC_PKCS_5 LTC_HASH_HELPERS LTC_FORTUNA LTC_RNG_GET_BYTES
  LTC_DEVRANDOM LTC_TRY_URANDOM_FIRST LTC_CLEAN_STACK
  EXCELLENT_CALENDAR_REQUIRE_OS_RNG)
target_compile_definitions(sync_spike_ltc PRIVATE LTC_SOURCE)
set_target_properties(sync_spike_ltc PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)

add_library(sync_spike_sqlcipher STATIC "${SQLCIPHER_SOURCE}/sqlite3.c")
target_link_libraries(sync_spike_sqlcipher PUBLIC sync_spike_ltc)
# The upstream VERSION file shadows C++ <version> on case-insensitive Windows
# filesystems. Export only the generated public header directory to C++ callers.
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated_include")
configure_file("${SQLCIPHER_SOURCE}/sqlite3.h" "${CMAKE_CURRENT_BINARY_DIR}/generated_include/sqlite3.h" COPYONLY)
target_include_directories(sync_spike_sqlcipher PUBLIC "${CMAKE_CURRENT_BINARY_DIR}/generated_include")
target_compile_definitions(sync_spike_sqlcipher PRIVATE
  SQLITE_HAS_CODEC SQLCIPHER_CRYPTO_LIBTOMCRYPT
  SQLITE_EXTRA_INIT=sqlcipher_extra_init SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown
  SQLITE_DEFAULT_FOREIGN_KEYS=1 SQLITE_DEFAULT_WAL_SYNCHRONOUS=2 SQLITE_DQS=0
  SQLITE_ENABLE_API_ARMOR=1 SQLITE_OMIT_LOAD_EXTENSION=1 SQLITE_TEMP_STORE=2 SQLITE_THREADSAFE=1
  SQLCIPHER_OMIT_LOG_DEVICE SQLCIPHER_LOG_LEVEL_DEFAULT=0)
set_target_properties(sync_spike_sqlcipher PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)
if(WIN32)
  target_link_libraries(sync_spike_ltc PUBLIC advapi32)
endif()
add_executable(cipher_probe ../sqlcipher_probe.cpp)
target_compile_features(cipher_probe PRIVATE cxx_std_17)
target_link_libraries(cipher_probe PRIVATE sync_spike_sqlcipher)
add_executable(cipher_recovery_probe ../cipher_recovery_probe.cpp)
target_compile_features(cipher_recovery_probe PRIVATE cxx_std_17)
target_link_libraries(cipher_recovery_probe PRIVATE sync_spike_sqlcipher)
add_executable(rng_failure_probe ../rng_failure_probe.c)
target_include_directories(rng_failure_probe PRIVATE "${LTC_SOURCE_DIR}/src/prngs")
target_link_libraries(rng_failure_probe PRIVATE sync_spike_ltc)
foreach(probe cipher_probe cipher_recovery_probe rng_failure_probe)
  if(MINGW OR (ANDROID AND SYNC_SPIKE_STATIC_ANDROID))
    target_link_options(${probe} PRIVATE -static)
  elseif(ANDROID)
    target_link_options(${probe} PRIVATE -static-libstdc++)
  endif()
endforeach()
