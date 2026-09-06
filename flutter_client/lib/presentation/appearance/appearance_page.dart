Color colorForHabitToken(HabitProgressColorToken? token) => switch (token) {
  HabitProgressColorToken.blue => const Color(0xFF2563EB),
  HabitProgressColorToken.indigo => const Color(0xFF4F46E5),
  HabitProgressColorToken.green => const Color(0xFF16803A),
  HabitProgressColorToken.orange => const Color(0xFFC2410C),
  HabitProgressColorToken.rose => const Color(0xFFBE123C),
  HabitProgressColorToken.purple => const Color(0xFF7E22CE),
  HabitProgressColorToken.teal => const Color(0xFF0F8C91),
  null => const Color(0xFF546E7A),
};

Color resolvedHabitTokenColor(
  BuildContext context,
  HabitProgressColorToken token,
) => ColorScheme.fromSeed(
  seedColor: colorForHabitToken(token),
  brightness: Theme.of(context).brightness,
).primary;

