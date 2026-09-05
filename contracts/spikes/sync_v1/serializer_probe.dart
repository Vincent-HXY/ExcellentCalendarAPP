// CT0 audit only; not imported by flutter_client.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      final bytes = utf8.encode(jsonEncode(jsonDecode(line)));
      stdout.writeln(
        'OK\t${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}',
      );
    } on FormatException {
      stdout.writeln('ERROR');
    }
  }
}
