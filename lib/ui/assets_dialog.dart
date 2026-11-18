import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../state/ide_state.dart';
import 'common.dart';

Future<void> showAssetsManager(BuildContext c, IdeState s) => showDialog(context: c, barrierDismissible: false, builder: (_) => _AssetsDialog(s));

class _Asset {
  _Asset(this.path, this.rel, this.registered);
  final String path, rel;
  final bool registered;
}

const _imgExt = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
const _reserved = {'class', 'default', 'new', 'const', 'final', 'var', 'in', 'is', 'for', 'if', 'else', 'switch', 'case', 'null', 'true', 'false'};

class _AssetsDialog extends StatefulWidget {
  const _AssetsDialog(this.s);
  final IdeState s;
  @override
  State<_AssetsDialog> createState() => _AssetsDialogState();
}

class _AssetsDialogState extends State<_AssetsDialog> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 2, vsync: this);
  IdeState get s => widget.s;
  String msg = '';

  File get _pubspec => File(p.join(s.root!, 'pubspec.yaml'));

  dynamic _flutterSection(String key) {
    try {
      final y = loadYaml(_pubspec.readAsStringSync());
      return y['flutter']?[key];
    } catch (_) {
      return null;
    }
  }

  List<String> _entries() {
    final a = _flutterSection('assets');
    return a is YamlList ? [for (final e in a) if (e is String) e] : [];
  }

  List<Map<String, dynamic>> _families() {
    final f = _flutterSection('fonts');
    if (f is! YamlList) return [];
    return [
      for (final e in f)
        if (e is YamlMap)
          {
            'family': '${e['family']}',
            'files': [for (final x in (e['fonts'] as YamlList? ?? YamlList())) if (x is YamlMap) {'asset': '${x['asset']}', 'weight': x['weight'], 'style': x['style']}],
          }
    ];
  }

  List<_Asset> _scan(List<String> entries) {
    final root = s.root!;
    final roots = <String>{};
    for (final e in entries) {
      if (e.endsWith('/') && Directory(p.join(root, e)).existsSync()) roots.add(p.normalize(p.join(root, e)));
    }
    final ad = Directory(p.join(root, 'assets'));
    if (ad.existsSync()) roots.add(p.normalize(ad.path));
    final seen = <String>{};
    final out = <_Asset>[];
    void add(File f) {
      final ext = p.extension(f.path).toLowerCase();
      if (ext == '.ttf' || ext == '.otf' || p.basename(f.path).startsWith('.')) return;
      final rel = p.relative(f.path, from: root).replaceAll('\\', '/');
      if (!seen.add(rel)) return;
      final dirRel = p.dirname(rel).replaceAll('\\', '/');
      out.add(_Asset(f.path, rel, entries.contains(rel) || entries.contains('$dirRel/')));
    }

    for (final d in roots) {
      try {
        for (final e in Directory(d).listSync(recursive: true, followLinks: false)) {
          if (e is File) add(e);
        }
      } catch (_) {}
    }
    for (final e in entries) {
      final f = File(p.join(root, e));
      if (!e.endsWith('/') && f.existsSync()) add(f);
    }
    out.sort((a, b) => a.rel.compareTo(b.rel));
    return out;
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null || r.files.isEmpty || !mounted) return;
    final target = await promptText(context, s, 'Carpeta destino (relativa al proyecto)', initial: 'assets/images');
    if (target == null) return;
    final dir = Directory(p.join(s.root!, target))..createSync(recursive: true);
    for (final f in r.files) {
      if (f.path != null) File(f.path!).copySync(p.join(dir.path, p.basename(f.path!)));
    }
    await s.addAssetFolder(dir.path);
    setState(() => msg = '${r.files.length} archivo(s) importados y registrados');
  }

  Future<void> _registerFolder() async {
    final d = await FilePicker.platform.getDirectoryPath(initialDirectory: s.root);
    if (d == null) return;
    if (!p.isWithin(s.root!, d)) {
      setState(() => msg = 'La carpeta debe estar dentro del proyecto');
      return;
    }
    await s.addAssetFolder(d);
    setState(() => msg = 'Carpeta registrada');
  }

  String _camel(String name) {
    final parts = name.split(RegExp(r'[^A-Za-z0-9]+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'asset';
    var r = parts.first.toLowerCase() + parts.skip(1).map((e) => e[0].toUpperCase() + e.substring(1).toLowerCase()).join();
    if (RegExp(r'^[0-9]').hasMatch(r)) r = 'a$r';
    if (_reserved.contains(r)) r = '${r}Asset';
    return r;
  }

  void _genClass(List<_Asset> files) {
    final names = <String>{};
    final b = StringBuffer("// Generado por Dart IDE (Assets y fuentes). No editar a mano.\nclass Assets {\n  Assets._();\n\n");
    for (final f in files.where((f) => f.registered)) {
      var n = _camel(p.basenameWithoutExtension(f.rel));
      if (!names.add(n)) {
        final ext = p.extension(f.rel).replaceFirst('.', '');
        n = '$n${ext.isEmpty ? '' : ext[0].toUpperCase() + ext.substring(1)}';
        var k = 2;
        while (!names.add(n)) {
          n = '$n$k';
          k++;
        }
      }
      b.writeln("  static const String $n = '${f.rel}';");
    }
    b.writeln('}');
    final out = File(p.join(s.root!, 'lib', 'gen', 'assets.dart'))..createSync(recursive: true);
    out.writeAsStringSync(b.toString());
    s.openFile(out.path);
    setState(() => msg = 'Generado lib/gen/assets.dart');
  }

  int _weight(String n) {
    if (n.contains('thin')) return 100;
    if (n.contains('extralight')) return 200;
    if (n.contains('light')) return 300;
    if (n.contains('medium')) return 500;
    if (n.contains('semibold')) return 600;
    if (n.contains('extrabold')) return 800;
    if (n.contains('bold')) return 700;
    if (n.contains('black')) return 900;
    return 400;
  }

  Future<void> _addFont() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
    if (r == null || r.files.isEmpty || !mounted) return;
    final first = p.basenameWithoutExtension(r.files.first.name);
    final fam = await promptText(context, s, 'Nombre de la familia tipográfica', initial: first.split(RegExp(r'[-_ ]')).first);
    if (fam == null) return;
    final dir = Directory(p.join(s.root!, 'assets', 'fonts'))..createSync(recursive: true);
    final b = StringBuffer()
      ..writeln('    - family: $fam')
      ..writeln('      fonts:');
    for (final f in r.files) {
      if (f.path == null) continue;
      final name = p.basename(f.path!);
      File(f.path!).copySync(p.join(dir.path, name));
      final low = name.toLowerCase();
      b.writeln('        - asset: assets/fonts/$name');
      final w = _weight(low);
      if (w != 400) b.writeln('          weight: $w');
      if (low.contains('italic')) b.writeln('          style: italic');
    }
    final block = b.toString().trimRight();
    var src = _pubspec.readAsStringSync();
    final fontsRe = RegExp(r'^  fonts:[ \t]*$', multiLine: true);
    final flutterRe = RegExp(r'^flutter:[ \t]*$', multiLine: true);
    if (fontsRe.hasMatch(src)) {
      src = src.replaceFirstMapped(fontsRe, (m) => '  fonts:\n$block');
    } else if (flutterRe.hasMatch(src)) {
      src = src.replaceFirstMapped(flutterRe, (m) => 'flutter:\n  fonts:\n$block');
    } else {
      src = '$src\nflutter:\n  fonts:\n$block\n';
    }
    _pubspec.writeAsStringSync(src);
    s.reloadDoc(_pubspec.path, src);
    setState(() => msg = 'Fuente "$fam" añadida al pubspec.yaml (usa fontFamily: \'$fam\')');
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    final entries = _entries();
    final assets = _scan(entries);
    final fams = _families();
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: SizedBox(
        width: size.width < 948 ? size.width - 48 : 900,
        height: size.height < 688 ? size.height - 48 : 640,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
            child: Row(children: [
              Icon(Icons.image_outlined, color: t.accent),
              const SizedBox(width: 10),
              const Expanded(child: Text('Assets y fuentes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          TabBar(controller: _tc, labelColor: t.text, unselectedLabelColor: t.muted, indicatorColor: t.accent, tabs: [Tab(text: 'ASSETS (${assets.length})'), Tab(text: 'FUENTES (${fams.length})')]),
          Divider(height: 1, color: t.border),
          Expanded(
            child: TabBarView(controller: _tc, children: [
              // ---- Assets ----
              Column(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Importar archivos…')),
                    OutlinedButton.icon(onPressed: _registerFolder, icon: const Icon(Icons.folder_special_outlined, size: 18), label: const Text('Registrar carpeta…')),
                    OutlinedButton.icon(onPressed: assets.any((a) => a.registered) ? () => _genClass(assets) : null, icon: const Icon(Icons.code, size: 18), label: const Text('Generar clase Assets')),
                    IconButton(onPressed: () => setState(() {}), tooltip: 'Recargar', icon: const Icon(Icons.refresh)),
                  ]),
                ),
                Expanded(
                  child: assets.isEmpty
                      ? Center(child: Text('No hay assets. Importa archivos o registra una carpeta.', style: TextStyle(color: t.muted)))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, childAspectRatio: .82, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemCount: assets.length,
                          itemBuilder: (_, i) {
                            final a = assets[i];
                            final isImg = _imgExt.contains(p.extension(a.path).toLowerCase());
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: a.registered ? t.border : Colors.amber.withAlpha(150))),
                              child: Column(children: [
                                Expanded(
                                  child: isImg
                                      ? Image.file(File(a.path), fit: BoxFit.contain, cacheWidth: 240, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
                                      : Icon(fileIcon(a.rel), size: 40, color: t.muted),
                                ),
                                const SizedBox(height: 4),
                                Text(p.basename(a.rel), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(a.registered ? 'registrado' : 'sin registrar', style: TextStyle(fontSize: 10.5, color: a.registered ? Colors.lightGreenAccent : Colors.amber)),
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  iconBtn(Icons.copy, "Copiar '${a.rel}'", () {
                                    Clipboard.setData(ClipboardData(text: "'${a.rel}'"));
                                    setState(() => msg = "Copiado: '${a.rel}'");
                                  }, size: 15),
                                  if (!a.registered) iconBtn(Icons.add_circle_outline, 'Registrar su carpeta', () async {
                                    await s.addAssetFolder(p.dirname(a.path));
                                    setState(() {});
                                  }, size: 15),
                                  iconBtn(Icons.delete_outline, 'Eliminar archivo', () async {
                                    if (await confirm(context, s, 'Eliminar asset', '¿Eliminar ${a.rel}?', ok: 'Eliminar')) {
                                      await s.deleteEntity(a.path);
                                      setState(() {});
                                    }
                                  }, size: 15),
                                ]),
                              ]),
                            );
                          },
                        ),
                ),
              ]),
              // ---- Fuentes ----
              Column(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: _addFont, icon: const Icon(Icons.font_download_outlined, size: 18), label: const Text('Añadir fuente (.ttf / .otf)…'))),
                ),
                Expanded(
                  child: fams.isEmpty
                      ? Center(child: Text('No hay fuentes registradas en pubspec.yaml', style: TextStyle(color: t.muted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), children: [
                          for (final f in fams)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(f['family'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                  iconBtn(Icons.copy, "Copiar fontFamily: '${f['family']}'", () => Clipboard.setData(ClipboardData(text: "fontFamily: '${f['family']}'"))),
                                ]),
                                _FontPreview(f['family'] as String, [for (final x in (f['files'] as List)) p.join(s.root!, x['asset'] as String)]),
                                const SizedBox(height: 6),
                                for (final x in (f['files'] as List))
                                  Text('${x['asset']}${x['weight'] != null ? '   · peso ${x['weight']}' : ''}${x['style'] != null ? '   · ${x['style']}' : ''}', style: TextStyle(fontSize: 11.5, color: t.muted)),
                              ]),
                            ),
                        ]),
                ),
              ]),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Align(alignment: Alignment.centerLeft, child: Text(msg.isEmpty ? 'Haz hot restart para ver los cambios de assets y fuentes.' : msg, style: TextStyle(fontSize: 12, color: t.muted)))),
        ]),
      ),
    );
  }
}

class _FontPreview extends StatefulWidget {
  const _FontPreview(this.family, this.paths);
  final String family;
  final List<String> paths;
  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  late final String _fam = 'ide_prev_${widget.family}_${widget.paths.join().hashCode}';
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = FontLoader(_fam);
      for (final f in widget.paths) {
        if (File(f).existsSync()) l.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
      }
      await l.load();
      if (mounted) setState(() => _ok = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Aa Bb Cc 0123 — El veloz murciélago hindú comía feliz cardillo y kiwi', style: TextStyle(fontFamily: _ok ? _fam : null, fontSize: 18)),
      );
}
