import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'services/app_log.dart';
import 'state/ide_state.dart';
import 'theme/ide_theme.dart';
import 'ui/logo.dart';
import 'ui/shell.dart';

Future<void> main() async {
  AppLog.init();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    AppLog.error(d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    AppLog.error(e, st);
    return true;
  };
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final s = IdeState();
    await s.restore(); // reabre el último proyecto y sus pestañas
    runApp(DartIdeApp(state: s));
  }, (e, st) => AppLog.error(e, st));
}

class DartIdeApp extends StatefulWidget {
  const DartIdeApp({super.key, required this.state});
  final IdeState state;
  @override
  State<DartIdeApp> createState() => _DartIdeAppState();
}

class _DartIdeAppState extends State<DartIdeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => widget.state.applySystemTheme();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<IdeTheme>(
        valueListenable: widget.state.themeNotifier,
        builder: (_, t, __) => MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: t.material,
          home: IdeShell(state: widget.state),
        ),
      );
}
