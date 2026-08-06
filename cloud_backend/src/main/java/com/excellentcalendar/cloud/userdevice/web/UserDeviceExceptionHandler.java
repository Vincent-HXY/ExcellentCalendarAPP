package com.excellentcalendar.cloud.userdevice.web;

import com.excellentcalendar.cloud.platform.web.ProblemDetailFactory;
import com.excellentcalendar.cloud.userdevice.service.UserDeviceException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = UserDeviceExceptionHandler.class)
public class UserDeviceExceptionHandler {

    @ExceptionHandler(UserDeviceException.ProfileNotFound.class)
    public ProblemDetail handleProfileNotFound(UserDeviceException.ProfileNotFound ex) {
        return ProblemDetailFactory.problem(HttpStatus.NOT_FOUND, "PROFILE_NOT_FOUND", ex.getMessage());
    }

    @ExceptionHandler(UserDeviceException.UsernameAlreadyTaken.class)
    public ProblemDetail handleUsernameAlreadyTaken(UserDeviceException.UsernameAlreadyTaken ex) {
        return ProblemDetailFactory.problem(HttpStatus.CONFLICT, "USERNAME_ALREADY_TAKEN", ex.getMessage());
    }

    @ExceptionHandler(UserDeviceException.InvalidFileType.class)
    public ProblemDetail handleInvalidFileType(UserDeviceException.InvalidFileType ex) {
        return ProblemDetailFactory.problem(HttpStatus.BAD_REQUEST, "INVALID_FILE_TYPE", ex.getMessage());
    }

    @ExceptionHandler(UserDeviceException.FileTooLarge.class)
    public ProblemDetail handleFileTooLarge(UserDeviceException.FileTooLarge ex) {
        return ProblemDetailFactory.problem(HttpStatus.BAD_REQUEST, "FILE_TOO_LARGE", ex.getMessage());
    }
}