import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../app_info.dart';

const _headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'Darter-Updater', 'X-GitHub-Api-Version': '2022-11-28'};

class ReleaseAsset {
  ReleaseAsset(this.name, this.url, this.size, this.digest);
  final String name, url;
  final int size;
  final String? digest;
}

class ReleaseInfo {
  ReleaseInfo({required this.tag, required this.version, required this.name, required this.body, required this.url, required this.published, required this.prerelease, required this.assets});
  final String tag, version, name, body, url;
  final DateTime? published;
  final bool prerelease;
  final List<ReleaseAsset> assets;
}

/// Compara versiones semánticas (1.2.3, v1.2.3-beta.1). Devuelve >0 si a > b.
int compareVersions(String a, String b) {
  String clean(String v) => v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
  List<int> nums(String v) => clean(v).split('-').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  String pre(String v) {
    final c = clean(v);
    final i = c.indexOf('-');
    return i < 0 ? '' : c.substring(i + 1);
  }

  final x = nums(a), y = nums(b);
  for (var i = 0; i < 3; i++) {
    final m = i < x.length ? x[i] : 0, n = i < y.length ? y[i] : 0;
    if (m != n) return m.compareTo(n);
  }
  final pa = pre(a), pb = pre(b);
  if (pa == pb) return 0;
  if (pa.isEmpty) return 1; // 1.0.0 > 1.0.0-beta
  if (pb.isEmpty) return -1;
  final xa = pa.split('.'), xb = pb.split('.');
  for (var i = 0; i < math.max(xa.length, xb.length); i++) {
    if (i >= xa.length) return -1;
    if (i >= xb.length) return 1;
    final na = int.tryParse(xa[i]), nb = int.tryParse(xb[i]);
    final c = (na != null && nb != null) ? na.compareTo(nb) : xa[i].compareTo(xb[i]);
    if (c != 0) return c;
  }
  return 0;
}

ReleaseInfo _parse(Map m) => ReleaseInfo(
      tag: '${m['tag_name']}',
      version: '${m['tag_name']}'.replaceFirst(RegExp(r'^[vV]'), ''),
      name: '${m['name'] ?? m['tag_name']}',
      body: '${m['body'] ?? ''}',
      url: '${m['html_url']}',
      published: DateTime.tryParse('${m['published_at']}'),
      prerelease: m['prerelease'] == true,
      assets: [
        for (final a in (m['assets'] as List? ?? []))
          ReleaseAsset('${a['name']}', '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0, a['digest'] as String?),
      ],
    );

/// Última versión publicada en GitHub Releases (null = el repo no tiene releases).
Future<ReleaseInfo?> fetchLatestRelease(String owner, String repo, {bool beta = false}) async {
  final uri = Uri.parse(beta ? 'https://api.github.com/repos/$owner/$repo/releases?per_page=10' : 'https://api.github.com/repos/$owner/$repo/releases/latest');
  final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
  if (res.statusCode == 404) return null;
  if (res.statusCode == 403 || res.statusCode == 429) throw 'GitHub limitó las consultas. Inténtalo más tarde.';
  if (res.statusCode != 200) throw 'GitHub respondió con el código ${res.statusCode}.';
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  if (j is Map) return _parse(j);
  if (j is List) {
    ReleaseInfo? best;
    for (final x in j) {
      if (x is! Map || x['draft'] == true) continue;
      final r = _parse(x);
      if (best == null || compareVersions(r.version, best.version) > 0) best = r;
    }
    return best;
  }
  return null;
}

/// Release concreta por etiqueta (para mostrar las novedades tras actualizar).
Future<ReleaseInfo?> fetchReleaseByTag(String owner, String repo, String tag) async {
  final res = await http.get(Uri.parse('https://api.github.com/repos/$owner/$repo/releases/tags/$tag'), headers: _headers).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) return null;
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  return j is Map ? _parse(j) : null;
}

/// Elige el archivo de la release que corresponde a este sistema operativo.
/// Convención: el nombre debe contener «windows», «macos» o «linux».
ReleaseAsset? pickAsset(ReleaseInfo r) {
  final os = Platform.isWindows ? 'win' : (Platform.isMacOS ? 'mac' : 'linux');
  final exts = Platform.isWindows ? ['.zip', '.exe', '.msi'] : (Platform.isMacOS ? ['.dmg', '.zip', '.pkg'] : ['.appimage', '.tar.gz', '.deb', '.zip']);
  ReleaseAsset? best;
  var bestScore = -1;
  for (final a in r.assets) {
    final n = a.name.toLowerCase();
    if (n.endsWith('.sha256') || n.endsWith('.txt') || n.endsWith('.sig') || n.contains('source')) continue;
    if (!n.contains(os) && !(Platform.isMacOS && n.contains('darwin'))) continue;
    final ei = exts.indexWhere((e) => n.endsWith(e));
    if (ei < 0) continue;
    final score = 100 - ei;
    if (score > bestScore) {
      best = a;
      bestScore = score;
    }
  }
  return best;
}

Future<File> downloadAsset(ReleaseAsset a, void Function(double progress) onProgress) async {
  final dir = Directory(p.join(Directory.systemTemp.path, 'darter_update'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final file = File(p.join(dir.path, a.name));
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(a.url))..headers.addAll({'User-Agent': 'Darter-Updater'})).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw 'La descarga falló (código ${res.statusCode}).';
    final total = res.contentLength ?? a.size;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress((got / total).clamp(0, 1).toDouble());
    }
    await sink.close();
    if (a.size > 0 && file.lengthSync() != a.size) throw 'El archivo descargado está incompleto.';
  } finally {
    client.close();
  }
  return file;
}

Future<String?> sha256Of(String path) async {
  try {
    final ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run('certutil', ['-hashfile', path, 'SHA256']);
    } else if (Platform.isMacOS) {
      r = await Process.run('shasum', ['-a', '256', path]);
    } else {
      r = await Process.run('sha256sum', [path]);
    }
    for (final line in const LineSplitter().convert('${r.stdout}')) {
      final t = line.replaceAll(' ', '').trim();
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) return t.toLowerCase();
      final m = RegExp(r'^([0-9a-fA-F]{64})\b').firstMatch(line.trim());
      if (m != null) return m.group(1)!.toLowerCase();
    }
  } catch (_) {}
  return null;
}

/// true = coincide, false = NO coincide, null = la release no publica checksum.
Future<bool?> verifyAsset(File f, ReleaseAsset a, ReleaseInfo r) async {
  String? expected = (a.digest != null && a.digest!.startsWith('sha256:')) ? a.digest!.substring(7).toLowerCase() : null;
  if (expected == null) {
    for (final s in r.assets) {
      final n = s.name.toLowerCase();
      if (n == '${a.name.toLowerCase()}.sha256' || n.contains('sha256sums') || n.contains('checksums')) {
        try {
          final res = await http.get(Uri.parse(s.url), headers: _headers).timeout(const Duration(seconds: 15));
          for (final line in const LineSplitter().convert(utf8.decode(res.bodyBytes))) {
            final m = RegExp(r'\b([0-9a-fA-F]{64})\b').firstMatch(line);
            if (m != null && (line.contains(a.name) || n.endsWith('.sha256'))) {
              expected = m.group(1)!.toLowerCase();
              break;
            }
          }
        } catch (_) {}
        if (expected != null) break;
      }
    }
  }
  if (expected == null) return null;
  final actual = await sha256Of(f.path);
  return actual != null && actual == expected;
}

/// Estado de la firma Authenticode de un archivo (solo Windows): status = Valid, NotSigned, HashMismatch…
Future<({String status, String subject})> readSignature(String path) async {
  if (!Platform.isWindows) return (status: 'NA', subject: '');
  try {
    final script = r"$s = Get-AuthenticodeSignature -LiteralPath '" + path.replaceAll("'", "''") + r"'; $s.Status.ToString() + '|' + $(if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { '' })";
    final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
    final out = '${r.stdout}'.trim();
    final i = out.indexOf('|');
    if (i < 0) return (status: 'Unknown', subject: '');
    return (status: out.substring(0, i).trim(), subject: out.substring(i + 1).trim());
  } catch (_) {
    return (status: 'Unknown', subject: '');
  }
}

/// null = correcto (o no se exige firma); si no, el motivo del rechazo.
Future<String?> _checkSignature(String path) async {
  if (kExpectedSigner.isEmpty || !Platform.isWindows) return null;
  final s = await readSignature(path);
  if (s.status != 'Valid') return 'La firma digital de ${p.basename(path)} no es válida (${s.status}). No se instaló la actualización.';
  if (!s.subject.toLowerCase().contains(kExpectedSigner.toLowerCase())) {
    return 'El archivo está firmado por «${s.subject}», que no coincide con el editor esperado. No se instaló la actualización.';
  }
  return null;
}

/// Instala lo descargado. Devuelve un mensaje si NO reinicia la app; null si se reinicia sola.
Future<String?> applyUpdate(File f) async {
  final n = f.path.toLowerCase();
  if (Platform.isWindows) {
    if (n.endsWith('.exe')) {
      final bad = await _checkSignature(f.path);
      if (bad != null) return bad;
      await Process.start(f.path, [], mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 700));
      exit(0);
    }
    if (n.endsWith('.msi')) {
      final bad = await _checkSignature(f.path);
      if (bad != null) return bad;
      await Process.start('msiexec', ['/i', f.path], mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 700));
      exit(0);
    }
    if (n.endsWith('.zip')) return _applyWindowsZip(f);
  }
  if (Platform.isMacOS) {
    await Process.run('open', [f.path]);
    return 'Descargado. Se abrió ${p.basename(f.path)}: arrastra la app a Aplicaciones para terminar.';
  }
  await Process.run('xdg-open', [p.dirname(f.path)]);
  return 'Descargado en ${f.path}';
}

Future<String?> _applyWindowsZip(File zip) async {
  final exe = Platform.resolvedExecutable;
  final dst = p.dirname(exe);
  if (dst.toLowerCase().contains('${p.separator}build${p.separator}windows')) {
    return 'Estás ejecutando en modo desarrollo: la actualización automática solo se aplica a la app instalada.';
  }
  final dest = Directory(p.join(p.dirname(zip.path), 'extracted'));
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  dest.createSync(recursive: true);
  final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', "Expand-Archive -LiteralPath '${zip.path}' -DestinationPath '${dest.path}' -Force"]);
  if (r.exitCode != 0) return 'No se pudo extraer el .zip: ${r.stderr}';
  String? src;
  for (final e in dest.listSync(recursive: true)) {
    if (e is File && p.basename(e.path).toLowerCase() == 'flutter_windows.dll') {
      src = p.dirname(e.path);
      break;
    }
  }
  if (src == null) return 'El .zip no contiene una compilación de Flutter para Windows (falta flutter_windows.dll).';
  final newExe = File(p.join(src, p.basename(exe)));
  if (newExe.existsSync()) {
    final bad = await _checkSignature(newExe.path);
    if (bad != null) return bad;
  } else if (kExpectedSigner.isNotEmpty) {
    return 'El .zip no contiene ${p.basename(exe)}, así que no se puede verificar la firma.';
  }
  final bat = File(p.join(p.dirname(zip.path), 'darter_update.bat'));
  bat.writeAsStringSync([
    '@echo off',
    'set "SRC=$src"',
    'set "DST=$dst"',
    'set "EXE=$exe"',
    'set /a tries=0',
    ':retry',
    'ping 127.0.0.1 -n 2 >nul',
    'xcopy "%SRC%\\*" "%DST%\\" /E /Y /I /Q >nul 2>&1',
    'if not errorlevel 1 goto done',
    'set /a tries+=1',
    'if %tries% LSS 40 goto retry',
    'start "" explorer "%SRC%"',
    'exit /b 1',
    ':done',
    'start "" "%EXE%"',
    'exit /b 0',
  ].join('\r\n'));
  await Process.start('cmd', ['/c', 'start', '', '/min', bat.path], mode: ProcessStartMode.detached);
  await Future.delayed(const Duration(milliseconds: 900));
  exit(0);
}
