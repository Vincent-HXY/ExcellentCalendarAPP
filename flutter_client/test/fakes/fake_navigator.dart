import 'package:excellent_calendar/app/routing/auth_navigator.dart';
import 'package:excellent_calendar/app/routing/auth_route_arguments.dart';

class FakeAuthNavigator implements AuthNavigator {
  final List<String> pushedRoutes = [];
  final List<VerificationPageArguments> verificationArguments = [];
  final List<ResetPasswordPageArguments> resetPasswordArguments = [];
  int goToLoginCalls = 0;
  int goToHomeCalls = 0;
  int goToProfileCalls = 0;
  int popCalls = 0;

  @override
  void goToLogin() {
    goToLoginCalls += 1;
  }

  @override
  void goToHome() {
    goToHomeCalls += 1;
  }

  @override
  void goToProfile() {
    goToProfileCalls += 1;
  }

  @override
  void goToVerification(VerificationPageArguments arguments) {
    verificationArguments.add(arguments);
  }

  @override
  void push(String route) {
    pushedRoutes.add(route);
  }

  @override
  void pushResetPassword(ResetPasswordPageArguments arguments) {
    resetPasswordArguments.add(arguments);
  }

  @override
  void pop() {
    popCalls += 1;
  }
}
