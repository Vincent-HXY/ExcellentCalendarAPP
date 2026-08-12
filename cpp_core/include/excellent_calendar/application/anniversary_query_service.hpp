#pragma once

#include <functional>
#include <memory>
#include <string>

#include "excellent_calendar/application/anniversary_types.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/repository/anniversary_transaction.hpp"

namespace excellent_calendar::application {

class AnniversaryQueryService {
 public:
  using Clock = std::function<std::string()>;

  AnniversaryQueryService(
      std::shared_ptr<repository::AnniversaryTransaction> transaction,
      std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
      Clock clock);

  common::Result<AnniversaryDetail> detail(const GetAnniversaryDetailQuery& query) const;
  common::Result<AnniversaryListPage> list(const ListAnniversariesQuery& query) const;
  common::Result<domain::AnniversaryCountdown> preview(
      const PreviewAnniversaryCountdownQuery& query) const;

 private:
  std::shared_ptr<repository::AnniversaryTransaction> transaction_;
  std::shared_ptr<domain::LocalTimeResolver> local_time_resolver_;
  Clock clock_;
};

}  // namespace excellent_calendar::application
