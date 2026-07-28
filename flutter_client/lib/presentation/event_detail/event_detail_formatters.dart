String formatEventDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}/$month/$day';
}

String formatEventTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String eventWeekdayLabel(DateTime value) {
  const labels = <String>[
    '\u661f\u671f\u4e00',
    '\u661f\u671f\u4e8c',
    '\u661f\u671f\u4e09',
    '\u661f\u671f\u56db',
    '\u661f\u671f\u4e94',
    '\u661f\u671f\u516d',
    '\u661f\u671f\u65e5',
  ];
  return labels[value.weekday - 1];
}
