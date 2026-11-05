import 'package:flutter/material.dart';

import '../report_error.dart';

/// Runs [start] and shows its widget once it succeeds.
///
/// If [start] throws, shows [StartupErrorApp] with a Retry that runs [start]
/// again, instead of leaving a blank page.
class StartupHost extends StatefulWidget {
  const StartupHost({super.key, required this.start});

  final Future<Widget> Function() start;

  @override
  State<StartupHost> createState() => _StartupHostState();
}

class _StartupHostState extends State<StartupHost> {
  Widget? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      final app = await widget.start();
      if (mounted) setState(() => _app = app);
    } catch (e, stack) {
      reportError(e, stack, source: 'startup');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return app;
    return StartupErrorApp(error: _error, onRetry: _run);
  }
}

/// Shown while starting (no [error]) and when starting failed.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shukan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator(key: Key('startupProgress'))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        "shukan couldn't start.",
                        key: Key('startupErrorMessage'),
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('startupRetryButton'),
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
