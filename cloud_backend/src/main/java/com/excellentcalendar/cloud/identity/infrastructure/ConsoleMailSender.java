package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.MailSender;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Development mail sender for the {@code dev}/{@code local} profiles only: prints the verification
 * code to the console as the integration inbox. Registered by {@link MailConfiguration}; the
 * verification code must never reach logs in any other profile.
 */
public class ConsoleMailSender implements MailSender {

    private static final Logger log = LoggerFactory.getLogger("mail.dev");

    @Override
    public void sendVerificationCode(String to, EmailActionPurpose purpose, String code) {
        log.info("[mail.dev] to={} purpose={} subject=\"ExcellentCalendarAPP 验证码\" code={}",
                to, purpose.wireValue(), code);
    }
}
