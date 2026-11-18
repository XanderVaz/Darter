import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Terminal con directorio persistente, historial y entrada interactiva (stdin) al proceso en curso.
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.name, this.cwd);
  String name;
  String cwd;
  final lines = <String>[];
  final history = <String>[];
  Process? _proc;
  bool get running => _proc != null;

  void _add(String l) {
    lines.add(l);
    if (lines.length > 4000) lines.removeRange(0, 1000);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  bool _builtin(String c) {
    final lower = c.toLowerCase();
    if (lower == 'cls' || lower == 'clear') {
      lines.clear();
      notifyListeners();
      return true;
    }
    final m = RegExp(r'^cd(?:\s+/d)?(?:\s+(.*))?$', caseSensitive: false).firstMatch(c);
    if (m == null) return false;
    if (m.group(1) == null && Platform.isWindows) {
      _add(cwd);
      return true;
    }
    var t = (m.group(1) ?? '').trim();
    if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
      t = t.substring(1, t.length - 1);
    }
    if (t.isEmpty || t == '~') t = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? cwd;
    final target = p.normalize(p.isAbsolute(t) ? t : p.join(cwd, t));
    if (Directory(target).existsSync()) {
      cwd = target;
      _add(target);
    } else {
      _add('No se encuentra la ruta: $target');
    }
    return true;
  }

  Future<void> run(String cmd) async {
    if (_proc != null) {
      _proc!.stdin.writeln(cmd); // entrada interactiva al proceso en ejecución
      _add(cmd);
      return;
    }
    final c = cmd.trim();
    if (c.isEmpty) return;
    history.add(c);
    _add('\$ $c');
    if (_builtin(c)) return;
    try {
      final pr = await Process.start(c, [], workingDirectory: cwd, runInShell: true);
      _proc = pr;
      notifyListeners();
      const dec = Utf8Decoder(allowMalformed: true);
      final s1 = pr.stdout.transform(dec).transform(const LineSplitter()).listen(_add);
      final s2 = pr.stderr.transform(dec).transform(const LineSplitter()).listen(_add);
      final code = await pr.exitCode;
      await Future.wait([s1.asFuture(), s2.asFuture()]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      _proc = null;
      _add('[código $code]');
    } catch (e) {
      _proc = null;
      _add('Error: $e');
    }
  }

  void interrupt() {
    final pr = _proc;
    if (pr == null) return;
    try {
      if (Platform.isWindows) {
        Process.run('taskkill', ['/pid', '${pr.pid}', '/T', '/F']);
      } else {
        pr.kill();
      }
    } catch (_) {
      pr.kill();
    }
    _add('^C');
  }

  @override
  void dispose() {
    final pr = _proc;
    if (pr != null) {
      try {
        if (Platform.isWindows) {
          Process.run('taskkill', ['/pid', '${pr.pid}', '/T', '/F']);
        } else {
          pr.kill();
        }
      } catch (_) {}
    }
    super.dispose();
  }
}
