import 'dart:io';
import 'package:path/path.dart' as p;

/// Registro local de errores (solo en tu equipo; nada se envía a ningún servidor).
class AppLog {
  static File? _file;

  static String dirPath() {
    final env = Platform.environment;
    if (Platform.isWindows) return p.join(env['LOCALAPPDATA'] ?? env['USERPROFILE'] ?? '.', 'Darter', 'logs');
    if (Platform.isMacOS) return p.join(env['HOME'] ?? '.', 'Library', 'Logs', 'Darter');
    return p.join(env['HOME'] ?? '.', '.local', 'share', 'darter', 'logs');
  }

  static String get path => _file?.path ?? '';

  static void init() {
    try {
      final d = Directory(dirPath())..createSync(recursive: true);
      final f = File(p.join(d.path, 'darter.log'));
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        final old = File(p.join(d.path, 'darter.old.log'));
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      _file = f;
      write('INFO', '── inicio de sesión ──');
    } catch (_) {}
  }

  static void write(String level, String msg) {
    try {
      _file?.writeAsStringSync('${DateTime.now().toIso8601String()} [$level] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  static void error(Object e, StackTrace? st) => write('ERROR', '$e\n${st ?? ''}');

  static String tail([int lines = 60]) {
    try {
      final l = _file!.readAsLinesSync();
      return l.skip(l.length > lines ? l.length - lines : 0).join('\n');
    } catch (_) {
      return '';
    }
  }

  static void clear() {
    try {
      _file?.writeAsStringSync('');
    } catch (_) {}
  }
}
