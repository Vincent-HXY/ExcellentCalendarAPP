package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserAgreementAcceptanceRepository extends Repository<UserAgreementAcceptanceEntity, UUID> {

    UserAgreementAcceptanceEntity save(UserAgreementAcceptanceEntity entity);
}
