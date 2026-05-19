import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SmokeTestApp());
}

class SmokeTestApp extends StatefulWidget {
  const SmokeTestApp({super.key});

  @override
  State<SmokeTestApp> createState() => _SmokeTestAppState();
}

class _SmokeTestAppState extends State<SmokeTestApp> {
  static const MethodChannel _channel = MethodChannel(
    'excellent_calendar/native_smoke',
  );

  String _message = 'Waiting for native ping...';

  @override
  void initState() {
    super.initState();
    _pingNative();
  }

  Future<void> _pingNative() async {
    try {
      final message = await _channel.invokeMethod<String>('pingNative');
      setState(() {
        _message = message ?? 'Native returned null';
      });
    } on PlatformException catch (error) {
      setState(() {
        _message = 'Native call failed: ${error.code}';
      });
    } on MissingPluginException {
      setState(() {
        _message = 'Native channel is not available in this environment';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Chain Smoke Test')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }
}
