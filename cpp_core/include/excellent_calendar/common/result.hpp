#pragma once

#include <map>
#include <optional>
#include <string>
#include <utility>

namespace excellent_calendar::common {

struct Unit {};

struct Error {
  std::string code;
  std::string message;
  std::map<std::string, std::string> details;
  bool retryable = false;
};

template <typename T>
class Result {
 public:
  static Result success(T value) {
    Result result;
    result.value_ = std::move(value);
    return result;
  }

  static Result failure(Error error) {
    Result result;
    result.error_ = std::move(error);
    return result;
  }

  bool ok() const { return value_.has_value(); }

  const T& value() const { return value_.value(); }

  T& value() { return value_.value(); }

  const Error& error() const { return error_.value(); }

 private:
  std::optional<T> value_;
  std::optional<Error> error_;
};

inline Error make_error(
    std::string code,
    std::string message,
    std::map<std::string, std::string> details = {},
    bool retryable = false) {
  return Error{std::move(code), std::move(message), std::move(details), retryable};
}

}  // namespace excellent_calendar::common
