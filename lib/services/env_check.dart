import 'dart:async';
import 'dart:io';

class EnvItem {
  const EnvItem(this.name, this.ok, this.detail, this.hint, {this.optional = false});
  final String name, detail, hint;
  final bool ok, optional;
}

Future<({bool ok, String out})> _run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args, runInShell: true).timeout(const Duration(seconds: 45));
    final lines = '${r.stdout}${r.stderr}'.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return (ok: r.exitCode == 0, out: lines.isEmpty ? '' : lines.first);
  } catch (_) {
    return (ok: false, out: '');
  }
}

/// Comprueba que las herramientas que Darter necesita estén instaladas y en el PATH.
Future<List<EnvItem>> checkEnvironment() async {
  final r = await Future.wait([
    _run('flutter', ['--version']),
    _run('dart', ['--version']),
    _run('git', ['--version']),
    _run('adb', ['version']),
  ]);
  return [
    EnvItem('Flutter SDK', r[0].ok, r[0].ok ? r[0].out : 'No se encontró «flutter» en el PATH', 'Instala Flutter y agrega su carpeta bin al PATH: https://docs.flutter.dev/get-started/install'),
    EnvItem('Dart SDK', r[1].ok, r[1].ok ? r[1].out : 'No se encontró «dart» en el PATH', 'Viene con Flutter: agrega flutter/bin al PATH (incluye dart).'),
    EnvItem('Git', r[2].ok, r[2].ok ? r[2].out : 'No se encontró «git» en el PATH', 'Necesario para el panel Git: https://git-scm.com/downloads'),
    EnvItem('Android Debug Bridge (adb)', r[3].ok, r[3].ok ? r[3].out : 'No se encontró «adb»', 'Solo si usas dispositivos o emuladores Android (Android Studio / platform-tools).', optional: true),
  ];
}
