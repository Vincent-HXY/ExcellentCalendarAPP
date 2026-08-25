package com.excellentcalendar.cloud.userdevice.domain;

public enum ReminderMethod {
    RING("ring"),
    POPUP("popup"),
    WECHAT("wechat");

    private final String wireValue;

    ReminderMethod(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }

    public static ReminderMethod fromWire(String wireValue) {
        for (ReminderMethod method : values()) {
            if (method.wireValue.equals(wireValue)) {
                return method;
            }
        }
        throw new IllegalArgumentException("unknown reminder method: " + wireValue);
    }
}
