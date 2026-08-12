abstract interface class AppClock {
  DateTime now();
}

class SystemAppClock implements AppClock {
  const SystemAppClock();

  @override
  DateTime now() => DateTime.now();
}

class FixedAppClock implements AppClock {
  const FixedAppClock(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}
