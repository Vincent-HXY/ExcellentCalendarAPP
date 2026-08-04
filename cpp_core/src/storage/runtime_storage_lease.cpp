#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage {

thread_local std::unordered_map<const RuntimeStorageLease*, std::size_t>
    RuntimeStorageLease::access_depths_;

}  // namespace excellent_calendar::storage
