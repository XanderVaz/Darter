import 'package:flutter/material.dart';
import 'state/ide_state.dart';
import 'theme/ide_theme.dart';
import 'ui/logo.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = IdeState();
  await s.restore(); // reabre el último proyecto y sus pestañas
  runApp(DartIdeApp(state: s));
}

class DartIdeApp extends StatelessWidget {
  const DartIdeApp({super.key, required this.state});
  final IdeState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<IdeTheme>(
        valueListenable: state.themeNotifier,
        builder: (_, t, __) => MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: t.material,
          home: IdeShell(state: state),
        ),
      );
}
