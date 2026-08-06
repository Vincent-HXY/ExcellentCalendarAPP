#pragma once

#include <map>
#include <optional>
#include <string>
#include <utility>

namespace excellent_calendar::common {

/**
 * 表示“没有实际返回值但操作成功”的占位类型。
 *
 * C++ 的模板 Result 需要一个具体类型，例如初始化存储只关心成功/失败，
 * 成功时没有业务数据，就使用 Result<Unit>。
 */
struct Unit {};

/**
 * 跨 C++ 内核、JNI、Kotlin、Dart 的统一错误结构。
 *
 * code 给程序判断，message 给人看，details 保存字段名/原因等上下文，
 * retryable 表示调用方稍后重试是否可能成功。
 */
struct Error {
  std::string code;
  std::string message;
  std::map<std::string, std::string> details;
  bool retryable = false;
};

/**
 * 简化版 Result 类型：一个函数要么返回 T，要么返回 Error。
 *
 * 项目里多数可预期错误（参数非法、存储不可写、数据损坏）不使用异常抛出，
 * 而是用 Result 显式返回。这样调用链每一层都能把错误转换成 NativeResult JSON。
 *
 * 注意：调用 value() 前应先确认 ok()==true；调用 error() 前应确认 ok()==false。
 */
template <typename T>
class Result {
 public:
  /** 构造成功结果。std::move 避免不必要复制，尤其 T 是 vector/object 时更重要。 */
  static Result success(T value) {
    Result result;
    result.value_ = std::move(value);
    return result;
  }

  /** 构造失败结果。 */
  static Result failure(Error error) {
    Result result;
    result.error_ = std::move(error);
    return result;
  }

  /** 是否成功。这里用 value_ 是否存在作为判断依据。 */
  bool ok() const { return value_.has_value(); }

  /** 读取成功值的 const 版本，不允许修改内部值。 */
  const T& value() const { return value_.value(); }

  /** 读取成功值的可修改版本。 */
  T& value() { return value_.value(); }

  /** 读取失败错误。 */
  const Error& error() const { return error_.value(); }

 private:
  /** std::optional<T> 表示“可能有值，也可能没有值”。 */
  std::optional<T> value_;
  std::optional<Error> error_;
};

/** 创建 Error 的小工具，集中处理 move 和默认参数。 */
inline Error make_error(
    std::string code,
    std::string message,
    std::map<std::string, std::string> details = {},
    bool retryable = false) {
  return Error{std::move(code), std::move(message), std::move(details), retryable};
}

}  // namespace excellent_calendar::common
