import 'dart:convert';

import 'package:flutter/material.dart';

Future<void> showNativeResultDialog({
  required BuildContext context,
  required String title,
  required Map<String, dynamic> rawResponse,
}) {
  final formatted = const JsonEncoder.withIndent('  ').convert(rawResponse);

  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              formatted,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
