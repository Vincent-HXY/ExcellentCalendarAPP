package com.excellentcalendar.cloud;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.MailSender;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

/**
 * Test mail capture: verification codes become assertable instead of console lines. Shared by all
 * integration tests through the common test base class.
 */
@Configuration(proxyBeanMethods = false)
public class MailCaptureConfiguration {

    @Bean
    @Primary
    CapturingMailSender capturingMailSender() {
        return new CapturingMailSender();
    }

    public static class CapturingMailSender implements MailSender {

        private final ConcurrentLinkedQueue<Mail> sent = new ConcurrentLinkedQueue<>();
        private final Map<String, String> latestCodeByEmail = new ConcurrentHashMap<>();

        @Override
        public void sendVerificationCode(String to, EmailActionPurpose purpose, String code) {
            sent.add(new Mail(to, purpose.wireValue(), code));
            latestCodeByEmail.put(to, code);
        }

        public Mail last() {
            Mail mail = sent.poll();
            if (mail == null) {
                throw new IllegalStateException("no verification mail captured");
            }
            return mail;
        }

        public String latestCode(String email) {
            String code = latestCodeByEmail.get(email);
            if (code == null) {
                throw new IllegalStateException("no code captured for " + email);
            }
            return code;
        }

        public boolean hasMailFor(String email) {
            return latestCodeByEmail.containsKey(email);
        }

        public void clear() {
            sent.clear();
            latestCodeByEmail.clear();
        }
    }

    public record Mail(String to, String purpose, String code) {
    }
}
