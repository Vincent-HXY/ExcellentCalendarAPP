/// Single authoritative implementation of the client-side form rules.
/// These only improve UX; the Backend always performs final validation.
class AuthValidators {
  const AuthValidators._();

  static final RegExp emailPattern = RegExp(
    r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$",
  );
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');
  static final RegExp verificationCodePattern = RegExp(r'^[0-9]{6}$');
  static final RegExp localePattern = RegExp(
    r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$',
  );

  static const passwordMinLength = 8;
  static const passwordMaxLength = 128;
  static const displayNameMaxLength = 40;
  static const emailMaxLength = 254;

  static String? emailError(String value) {
    final email = value.trim();
    if (email.isEmpty) {
      return '请输入邮箱';
    }
    if (email.length > emailMaxLength || !emailPattern.hasMatch(email)) {
      return '邮箱格式不正确';
    }
    return null;
  }

  static String? usernameError(String value) {
    if (value.isEmpty) {
      return '请输入用户名';
    }
    if (!usernamePattern.hasMatch(value)) {
      return '用户名需为 3-24 位小写字母、数字或下划线';
    }
    return null;
  }

  static String? displayNameError(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      return '请输入昵称';
    }
    if (name.length > displayNameMaxLength) {
      return '昵称不能超过 40 个字符';
    }
    return null;
  }

  static String? passwordError(String value) {
    if (value.isEmpty) {
      return '请输入密码';
    }
    if (value.length < passwordMinLength) {
      return '密码至少需要 8 个字符';
    }
    if (value.length > passwordMaxLength) {
      return '密码不能超过 128 个字符';
    }
    return null;
  }

  static String? loginPasswordError(String value) =>
      value.isEmpty ? '请输入密码' : null;

  static String? confirmPasswordError(String password, String confirm) {
    if (confirm.isEmpty) {
      return '请再次输入密码';
    }
    if (password != confirm) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  static String? verificationCodeError(String value) {
    if (value.isEmpty) {
      return '请输入验证码';
    }
    if (!verificationCodePattern.hasMatch(value)) {
      return '验证码为 6 位数字';
    }
    return null;
  }

  static String? localeError(String value) {
    if (value.isEmpty || !localePattern.hasMatch(value)) {
      return '语言格式不正确';
    }
    return null;
  }

  static String? timezoneError(String value) => value.isEmpty ? '请选择时区' : null;
}
