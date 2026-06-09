#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string initialize_storage(std::string_view storage_directory);

std::string create_event(std::string_view request_json);

std::string search_events(std::string_view request_json);

std::string complete_event(std::string_view request_json);

std::string reopen_event(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
