#pragma once

#include <functional>
#include <memory>
#include <string>

#include "excellent_calendar/application/anniversary_types.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/repository/anniversary_transaction.hpp"

namespace excellent_calendar::application {

class AnniversaryWorkflowService {
 public:
  using Clock = std::function<std::string()>;
  using IdGenerator = std::function<std::string()>;

  AnniversaryWorkflowService(
      std::shared_ptr<repository::AnniversaryTransaction> transaction,
      std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
      Clock clock,
      IdGenerator id_generator);

  common::Result<AnniversaryDetail> create(const CreateAnniversaryCommand& command);
  common::Result<AnniversaryDetail> update(const UpdateAnniversaryCommand& command);
  common::Result<domain::Anniversary> remove(const DeleteAnniversaryCommand& command);

 private:
  std::shared_ptr<repository::AnniversaryTransaction> transaction_;
  std::shared_ptr<domain::LocalTimeResolver> local_time_resolver_;
  Clock clock_;
  IdGenerator id_generator_;
};

}  // namespace excellent_calendar::application
