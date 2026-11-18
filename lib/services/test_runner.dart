import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum TestStatus { running, passed, failed, skipped }

class TestCase {
  TestCase(this.id, this.name, this.suiteId, this.path, this.line);
  final int id, suiteId, line;
  final String name;
  final String? path;
  TestStatus status = TestStatus.running;
  String error = '', stack = '';
}

class CoverFile {
  CoverFile(this.path, this.found, this.hit);
  final String path;
  final int found, hit;
  double get pct => found == 0 ? 0 : hit * 100 / found;
}

/// Ejecuta `flutter test --reporter json` y construye el árbol de resultados.
class TestRunner extends ChangeNotifier {
  final suites = <int, String>{};
  final tests = <int, TestCase>{};
  List<CoverFile> coverage = [];
  String status = '';
  Process? _proc;
  String? _root;

  bool get running => _proc != null;
  int get total => tests.length;
  int get passed => tests.values.where((t) => t.status == TestStatus.passed).length;
  int get failed => tests.values.where((t) => t.status == TestStatus.failed).length;
  int get skipped => tests.values.where((t) => t.status == TestStatus.skipped).length;
  int get finished => tests.values.where((t) => t.status != TestStatus.running).length;
  double get coveragePct {
    final f = coverage.fold<int>(0, (a, b) => a + b.found);
    final h = coverage.fold<int>(0, (a, b) => a + b.hit);
    return f == 0 ? 0 : h * 100 / f;
  }

  void clear() {
    suites.clear();
    tests.clear();
    status = '';
    notifyListeners();
  }

  Future<void> run({
    required String root,
    required bool flutter,
    String? file,
    String? plainName,
    String? namePattern,
    bool coverage = false,
    void Function(String)? log,
  }) async {
    if (_proc != null) return;
    clear();
    _root = root;
    final args = flutter ? ['test', '--reporter', 'json'] : ['test', '-r', 'json'];
    if (coverage && flutter) args.add('--coverage');
    if (plainName != null) args.addAll(['--plain-name', plainName]);
    if (namePattern != null) args.addAll(['--name', namePattern]);
    if (file != null) args.add(file);
    status = 'Ejecutando…';
    notifyListeners();
    log?.call('\$ ${flutter ? 'flutter' : 'dart'} ${args.join(' ')}');
    try {
      final pr = await Process.start(flutter ? 'flutter' : 'dart', args, workingDirectory: root, runInShell: true);
      _proc = pr;
      const dec = Utf8Decoder(allowMalformed: true);
      final s1 = pr.stdout.transform(dec).transform(const LineSplitter()).listen((l) {
        try {
          final j = jsonDecode(l);
          if (j is Map) {
            _event(j);
            return;
          }
        } catch (_) {}
        log?.call(l);
      });
      final s2 = pr.stderr.transform(dec).transform(const LineSplitter()).listen((l) => log?.call(l));
      final code = await pr.exitCode;
      await Future.wait([s1.asFuture(), s2.asFuture()]).timeout(const Duration(seconds: 3), onTimeout: () => <void>[]);
      _proc = null;
      for (final t in tests.values) {
        if (t.status == TestStatus.running) t.status = TestStatus.failed;
      }
      status = total == 0 ? 'Sin pruebas (código $code)' : (failed > 0 ? '$failed fallida(s)' : 'Todas correctas');
      if (coverage) _loadCoverage(root);
      notifyListeners();
    } catch (e) {
      _proc = null;
      status = 'Error: $e';
      notifyListeners();
    }
  }

  void _event(Map e) {
    switch (e['type']) {
      case 'suite':
        {
          final s = e['suite'] as Map;
          suites[(s['id'] as num).toInt()] = '${s['path'] ?? ''}';
        }
      case 'testStart':
        {
          final t = e['test'] as Map;
          final id = (t['id'] as num).toInt();
          final sid = (t['suiteID'] as num?)?.toInt() ?? 0;
          String? path;
          final url = t['url'] as String?;
          if (url != null && url.startsWith('file:')) {
            path = Uri.parse(url).toFilePath();
          } else if (suites[sid] != null && _root != null) {
            final sp = suites[sid]!;
            path = p.isAbsolute(sp) ? sp : p.join(_root!, sp);
          }
          tests[id] = TestCase(id, '${t['name']}', sid, path, (t['line'] as num?)?.toInt() ?? 0);
        }
      case 'testDone':
        {
          final id = (e['testID'] as num).toInt();
          final tc = tests[id];
          if (tc != null) {
            if (e['hidden'] == true) {
              tests.remove(id);
            } else {
              tc.status = e['skipped'] == true ? TestStatus.skipped : (e['result'] == 'success' ? TestStatus.passed : TestStatus.failed);
            }
          }
        }
      case 'error':
        {
          final tc = tests[(e['testID'] as num).toInt()];
          if (tc != null) {
            tc.error = '${e['error']}';
            tc.stack = '${e['stackTrace'] ?? ''}';
          }
        }
    }
    notifyListeners();
  }

  void _loadCoverage(String root) {
    try {
      final f = File(p.join(root, 'coverage', 'lcov.info'));
      if (!f.existsSync()) return;
      String? sf;
      var lf = 0, lh = 0;
      final out = <CoverFile>[];
      for (final l in f.readAsLinesSync()) {
        if (l.startsWith('SF:')) {
          sf = l.substring(3);
          lf = 0;
          lh = 0;
        } else if (l.startsWith('LF:')) {
          lf = int.tryParse(l.substring(3)) ?? 0;
        } else if (l.startsWith('LH:')) {
          lh = int.tryParse(l.substring(3)) ?? 0;
        } else if (l == 'end_of_record' && sf != null) {
          out.add(CoverFile(p.isAbsolute(sf) ? sf : p.join(root, sf), lf, lh));
          sf = null;
        }
      }
      out.sort((a, b) => a.pct.compareTo(b.pct));
      coverage = out;
    } catch (_) {}
  }

  void stop() {
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
  }
}
