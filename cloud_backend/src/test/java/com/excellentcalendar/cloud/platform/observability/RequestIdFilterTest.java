package com.excellentcalendar.cloud.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestIdFilterTest {

    @Test
    void requestIdIsAvailableDuringRequestAndRemovedAfterward() throws Exception {
        RequestIdFilter filter = new RequestIdFilter(() -> "request-123");
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<String> requestAttribute = new AtomicReference<>();
        AtomicReference<String> mdcValue = new AtomicReference<>();

        filter.doFilter(request, response, (servletRequest, servletResponse) -> {
            requestAttribute.set((String) servletRequest.getAttribute(RequestIdFilter.REQUEST_ID_ATTRIBUTE));
            mdcValue.set(MDC.get(RequestIdFilter.REQUEST_ID_MDC_KEY));
        });

        assertThat(requestAttribute).hasValue("request-123");
        assertThat(mdcValue).hasValue("request-123");
        assertThat(MDC.get(RequestIdFilter.REQUEST_ID_MDC_KEY)).isNull();
    }
}
