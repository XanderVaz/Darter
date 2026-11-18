import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cliente mínimo del Debug Adapter Protocol (`flutter debug_adapter` / `dart debug_adapter`).
class DapClient {
  DapClient({required this.onEvent, required this.onExit});
  final void Function(String event, Map body) onEvent;
  final void Function() onExit;
  Process? _p;
  int _seq = 0;
  final _pending = <int, Completer<Map>>{};
  final _buf = <int>[];
  static final _needle = ascii.encode('Content-Length:');

  Future<void> start(String exe, List<String> args, String cwd) async {
    final p = await Process.start(exe, args, workingDirectory: cwd, runInShell: true);
    _p = p;
    p.stdout.listen(_onData);
    p.stderr.listen((d) => onEvent('output', {'category': 'stderr', 'output': utf8.decode(d, allowMalformed: true)}));
    p.exitCode.then((_) {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.complete({'success': false, 'message': 'El adaptador terminó'});
      }
      _pending.clear();
      _p = null;
      onExit();
    });
  }

  void _send(Map<String, dynamic> m) {
    final p = _p;
    if (p == null) return;
    final body = utf8.encode(jsonEncode(m));
    p.stdin.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
    p.stdin.add(body);
  }

  Future<Map> request(String command, [Map? args, int seconds = 20]) {
    final id = ++_seq;
    final c = Completer<Map>();
    _pending[id] = c;
    _send({'seq': id, 'type': 'request', 'command': command, if (args != null) 'arguments': args});
    return c.future.timeout(Duration(seconds: seconds), onTimeout: () {
      _pending.remove(id);
      return {'success': false, 'message': 'Tiempo de espera agotado ($command)'};
    });
  }

  int _find(List<int> h, List<int> n) {
    for (var i = 0; i + n.length <= h.length; i++) {
      var ok = true;
      for (var j = 0; j < n.length; j++) {
        if (h[i + j] != n[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  void _onData(List<int> data) {
    _buf.addAll(data);
    while (true) {
      final s = _find(_buf, _needle);
      if (s < 0) {
        if (_buf.length > 4096) _buf.clear();
        return;
      }
      if (s > 0) _buf.removeRange(0, s); // descarta basura previa (p. ej. mensajes del script flutter.bat)
      var e = -1;
      for (var i = 0; i + 3 < _buf.length; i++) {
        if (_buf[i] == 13 && _buf[i + 1] == 10 && _buf[i + 2] == 13 && _buf[i + 3] == 10) {
          e = i;
          break;
        }
      }
      if (e < 0) return;
      final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(ascii.decode(_buf.sublist(0, e), allowInvalid: true));
      if (m == null) {
        _buf.removeRange(0, e + 4);
        continue;
      }
      final len = int.parse(m.group(1)!);
      if (_buf.length < e + 4 + len) return;
      final body = utf8.decode(_buf.sublist(e + 4, e + 4 + len), allowMalformed: true);
      _buf.removeRange(0, e + 4 + len);
      try {
        _handle(jsonDecode(body) as Map);
      } catch (_) {}
    }
  }

  void _handle(Map m) {
    final type = m['type'];
    if (type == 'response') {
      final c = _pending.remove((m['request_seq'] as num).toInt());
      if (c != null && !c.isCompleted) c.complete(m);
    } else if (type == 'event') {
      onEvent('${m['event']}', (m['body'] as Map?) ?? {});
    } else if (type == 'request') {
      _send({'seq': ++_seq, 'type': 'response', 'request_seq': m['seq'], 'success': false, 'command': m['command'], 'message': 'No soportado'});
    }
  }

  void kill() {
    final p = _p;
    if (p == null) return;
    try {
      if (Platform.isWindows) {
        Process.run('taskkill', ['/pid', '${p.pid}', '/T', '/F']);
      } else {
        p.kill();
      }
    } catch (_) {
      p.kill();
    }
  }
}
