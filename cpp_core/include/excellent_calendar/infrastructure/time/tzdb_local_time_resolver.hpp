#pragma once

#include <filesystem>
#include <memory>
#include <string>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::infrastructure::time {

class TzdbLocalTimeResolver final : public domain::LocalTimeResolver {
 public:
  static common::Result<std::shared_ptr<TzdbLocalTimeResolver>> create(
      const std::filesystem::path& tzdb_directory,
      std::string expected_version = "2026c");

  common::Result<common::Unit> validate_timezone(std::string_view timezone) const override;
  common::Result<domain::LocalDateTime> to_local(std::string_view utc_instant,
                                                std::string_view timezone) const override;
  common::Result<domain::ResolvedLocalDateTime> resolve_local_datetime(
      const domain::LocalDateTime& local,
      std::string_view timezone) const override;
  common::Result<std::string> to_utc(const domain::LocalDateTime& local,
                                     std::string_view timezone) const override;
  std::string tzdb_version() const override;

 private:
  explicit TzdbLocalTimeResolver(std::string version);

  std::string version_;
};

}  // namespace excellent_calendar::infrastructure::time
