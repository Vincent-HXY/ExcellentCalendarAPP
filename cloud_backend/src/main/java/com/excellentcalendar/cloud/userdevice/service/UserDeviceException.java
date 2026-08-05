package com.excellentcalendar.cloud.userdevice.service;

public abstract class UserDeviceException extends RuntimeException {

    protected UserDeviceException(String message) {
        super(message);
    }

    public static class ProfileNotFound extends UserDeviceException {
        public ProfileNotFound(String message) {
            super(message);
        }
    }

    public static class UsernameAlreadyTaken extends UserDeviceException {
        public UsernameAlreadyTaken(String message) {
            super(message);
        }
    }

    public static class InvalidFileType extends UserDeviceException {
        public InvalidFileType(String message) {
            super(message);
        }
    }

    public static class FileTooLarge extends UserDeviceException {
        public FileTooLarge(String message) {
            super(message);
        }
    }
}