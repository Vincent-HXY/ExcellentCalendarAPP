package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.MailSender;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Fallback for profiles without a real mail provider (including the production {@code api}
 * profile): never logs the verification code. A production SMTP implementation must replace this
 * bean; until then the absence of mail delivery is logged without any credential material.
 */
public class UnconfiguredMailSender implements MailSender {

    private static final Logger log = LoggerFactory.getLogger("mail");

    @Override
    public void sendVerificationCode(String to, EmailActionPurpose purpose, String code) {
        log.warn("[mail] no mail provider configured in the active profile; "
                + "verification email not sent (purpose={})", purpose.wireValue());
    }
}
