#pragma once

#include <condition_variable>
#include <cstddef>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::storage {

/**
 * Revocable process-runtime lease for a storage writer.
 *
 * Every transaction operation holds shared access for its complete duration.
 * Runtime replacement takes exclusive access, waits for in-flight work, and then
 * revokes the generation so already-borrowed services cannot write an old path.
 */
class RuntimeStorageLease final {
 public:
  class Access final {
   public:
    Access(const Access&) = delete;
    Access& operator=(const Access&) = delete;

    Access(Access&& other) noexcept : lease_(std::exchange(other.lease_, nullptr)) {}

    Access& operator=(Access&& other) noexcept {
      if (this != &other) {
        release();
        lease_ = std::exchange(other.lease_, nullptr);
      }
      return *this;
    }

    ~Access() { release(); }

   private:
    friend class RuntimeStorageLease;

    explicit Access(const RuntimeStorageLease* lease) : lease_(lease) {}

    void release() {
      if (lease_ != nullptr) {
        lease_->release();
        lease_ = nullptr;
      }
    }

    const RuntimeStorageLease* lease_ = nullptr;
  };

  std::optional<Access> acquire() const {
    // A legacy workflow transaction acquires the generation and then invokes
    // repositories that share the same generation. Count that same-thread
    // nesting only once globally so transaction callbacks cannot deadlock.
    auto nested = access_depths_.find(this);
    if (nested != access_depths_.end()) {
      ++nested->second;
      return std::optional<Access>(Access(this));
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (!active_) return std::nullopt;
    ++active_operations_;
    access_depths_.emplace(this, 1U);
    return std::optional<Access>(Access(this));
  }

  void revoke() {
    std::unique_lock<std::mutex> lock(mutex_);
    // Close admission before waiting. Existing operations may finish (and may
    // acquire nested access on their own thread), while new callers fail fast.
    active_ = false;
    drained_.wait(lock, [this] { return active_operations_ == 0U; });
  }

 private:
  void release() const {
    auto nested = access_depths_.find(this);
    if (nested == access_depths_.end()) return;
    if (--nested->second != 0U) return;
    access_depths_.erase(nested);

    std::lock_guard<std::mutex> lock(mutex_);
    if (active_operations_ != 0U) --active_operations_;
    if (active_operations_ == 0U) drained_.notify_all();
  }

  static thread_local std::unordered_map<const RuntimeStorageLease*, std::size_t>
      access_depths_;
  mutable std::mutex mutex_;
  mutable std::condition_variable drained_;
  mutable std::size_t active_operations_ = 0U;
  bool active_ = true;
};

inline common::Error runtime_storage_revoked_error(std::string operation) {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
      {{"operation", std::move(operation)}});
}

}  // namespace excellent_calendar::storage
