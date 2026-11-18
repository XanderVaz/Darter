import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'diff_page.dart';

const monacoVersion = '0.52.0';

String monacoCacheDir() {
  final env = Platform.environment;
  if (Platform.isWindows) return p.join(env['LOCALAPPDATA'] ?? env['USERPROFILE'] ?? '.', 'DartIDE', 'monaco-$monacoVersion');
  if (Platform.isMacOS) return p.join(env['HOME'] ?? '.', 'Library', 'Application Support', 'DartIDE', 'monaco-$monacoVersion');
  return p.join(env['HOME'] ?? '.', '.local', 'share', 'dart_ide', 'monaco-$monacoVersion');
}

String monacoVsDir() => p.join(monacoCacheDir(), 'package', 'min', 'vs');
bool monacoInstalled() => File(p.join(monacoVsDir(), 'loader.js')).existsSync();

/// Descarga monaco-editor desde npm y extrae solo `min/vs` (usa el `tar` del sistema).
Future<void> downloadMonaco(void Function(double? progress, String status) onProgress) async {
  final dir = Directory(monacoCacheDir());
  await dir.create(recursive: true);
  final tgz = File(p.join(dir.path, 'monaco.tgz'));
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse('https://registry.npmjs.org/monaco-editor/-/monaco-editor-$monacoVersion.tgz'));
    final res = await client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    final total = res.contentLength ?? 0;
    final sink = tgz.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      onProgress(total > 0 ? got / total : null, 'Descargando… ${(got / 1048576).toStringAsFixed(1)} MB');
    }
    await sink.close();
  } finally {
    client.close();
  }
  onProgress(null, 'Extrayendo…');
  final r = await Process.run('tar', ['-xzf', tgz.path, '-C', dir.path, 'package/min/vs'], runInShell: true);
  if (r.exitCode != 0) throw 'tar falló: ${r.stderr}';
  try {
    await tgz.delete();
  } catch (_) {}
  if (!monacoInstalled()) throw 'No se encontró loader.js tras extraer';
}

/// Servidor HTTP local (solo loopback) que sirve Monaco y la página del editor.
class MonacoServer {
  HttpServer? _srv;
  String Function(String bg) pageBuilder = (_) => '';
  int get port => _srv?.port ?? 0;
  String get base => 'http://127.0.0.1:$port';

  ContentType _type(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.json':
        return ContentType.json;
      case '.html':
        return ContentType.html;
      case '.ttf':
        return ContentType('font', 'ttf');
      case '.svg':
        return ContentType('image', 'svg+xml');
      default:
        return ContentType.binary;
    }
  }

  Future<void> start() async {
    if (_srv != null) return;
    final root = monacoVsDir();
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _srv = srv;
    srv.listen((req) async {
      try {
        final path = Uri.decodeComponent(req.uri.path);
        if (path == '/editor.html') {
          req.response.headers.contentType = ContentType.html;
          req.response.write(pageBuilder(req.uri.queryParameters['bg'] ?? '#1e1e1e'));
          await req.response.close();
          return;
        }
        if (path == '/diff.html') {
          req.response.headers.contentType = ContentType.html;
          req.response.write(diffHtml('$base/vs', req.uri.queryParameters['bg'] ?? '#1e1e1e'));
          await req.response.close();
          return;
        }
        if (path.startsWith('/vs/')) {
          final f = File(p.normalize(p.join(root, path.substring(4))));
          if (p.isWithin(root, f.path) && await f.exists()) {
            req.response.headers.contentType = _type(f.path);
            await req.response.addStream(f.openRead());
            await req.response.close();
            return;
          }
        }
        req.response.statusCode = 404;
        await req.response.close();
      } catch (_) {
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    await _srv?.close(force: true);
    _srv = null;
  }
}
