import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../state/ide_state.dart';
import 'common.dart';

Future<void> showArbEditor(BuildContext c, IdeState s) => showDialog(context: c, barrierDismissible: false, builder: (_) => _ArbEditor(s));

class _Loc {
  _Loc(this.code, this.file, this.raw);
  final String code;
  final File file;
  final Map<String, dynamic> raw;
}

class _ArbEditor extends StatefulWidget {
  const _ArbEditor(this.s);
  final IdeState s;
  @override
  State<_ArbEditor> createState() => _ArbEditorState();
}

class _ArbEditorState extends State<_ArbEditor> {
  IdeState get s => widget.s;
  String? dir;
  List<_Loc> locs = [];
  List<String> keys = [];
  final ctl = <String, TextEditingController>{};
  Map<String, dynamic> meta = {};
  String filter = '';
  bool dirty = false;
  String msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map? _l10nYaml() {
    try {
      final f = File(p.join(s.root!, 'l10n.yaml'));
      if (f.existsSync()) return loadYaml(f.readAsStringSync()) as Map?;
    } catch (_) {}
    return null;
  }

  void _load() {
    for (final c in ctl.values) {
      c.dispose();
    }
    ctl.clear();
    keys = [];
    locs = [];
    final y = _l10nYaml();
    final arbDir = y?['arb-dir'] is String ? p.join(s.root!, y!['arb-dir'] as String) : p.join(s.root!, 'lib', 'l10n');
    dir = arbDir;
    final dd = Directory(arbDir);
    if (dd.existsSync()) {
      final files = dd.listSync().whereType<File>().where((f) => f.path.endsWith('.arb')).toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        try {
          final m = Map<String, dynamic>.from(jsonDecode(f.readAsStringSync()) as Map);
          final code = '${m['@@locale'] ?? p.basenameWithoutExtension(f.path).split('_').skip(1).join('_')}';
          locs.add(_Loc(code, f, m));
        } catch (e) {
          msg = 'No se pudo leer ${p.basename(f.path)}: $e';
        }
      }
    }
    if (locs.isNotEmpty) {
      final tf = y?['template-arb-file'] is String ? y!['template-arb-file'] as String : '';
      var ti = locs.indexWhere((l) => p.basename(l.file.path) == tf);
      if (ti < 0) ti = locs.indexWhere((l) => l.code == 'en');
      if (ti > 0) locs.insert(0, locs.removeAt(ti));
      for (final l in locs) {
        for (final e in l.raw.entries) {
          if (!e.key.startsWith('@') && !keys.contains(e.key)) keys.add(e.key);
        }
      }
      meta = {for (final e in locs.first.raw.entries) if (e.key.startsWith('@') && !e.key.startsWith('@@')) e.key: e.value};
      for (final l in locs) {
        for (final k in keys) {
          ctl['${l.code}|$k'] = TextEditingController(text: '${l.raw[k] ?? ''}');
        }
      }
    }
    dirty = false;
    if (mounted) setState(() {});
  }

  int get missing {
    var n = 0;
    for (var i = 1; i < locs.length; i++) {
      for (final k in keys) {
        if ((ctl['${locs[i].code}|$k']?.text ?? '').isEmpty) n++;
      }
    }
    return n;
  }

  Future<void> _save({bool gen = false}) async {
    for (var li = 0; li < locs.length; li++) {
      final l = locs[li];
      final out = <String, dynamic>{'@@locale': l.code};
      for (final k in keys) {
        final v = ctl['${l.code}|$k']!.text;
        if (v.isEmpty && li > 0) continue;
        out[k] = v;
        if (li == 0) {
          final mm = Map<String, dynamic>.from((meta['@$k'] as Map?) ?? {});
          if (!v.contains(', plural') && !v.contains(', select')) {
            final ph = Map<String, dynamic>.from((mm['placeholders'] as Map?) ?? {});
            for (final x in RegExp(r'\{(\w+)\}').allMatches(v)) {
              ph.putIfAbsent(x.group(1)!, () => <String, dynamic>{});
            }
            if (ph.isNotEmpty) mm['placeholders'] = ph;
          }
          if (mm.isNotEmpty) {
            out['@$k'] = mm;
            meta['@$k'] = mm;
          }
        } else if (l.raw['@$k'] != null) {
          out['@$k'] = l.raw['@$k'];
        }
      }
      final text = '${const JsonEncoder.withIndent('  ').convert(out)}\n';
      await l.file.writeAsString(text);
      s.reloadDoc(l.file.path, text);
    }
    dirty = false;
    msg = 'Guardado ✓';
    if (mounted) setState(() {});
    if (gen) await s.genL10n();
  }

  Future<void> _addKey() async {
    final k = await promptText(context, s, 'Nueva clave (camelCase)', hint: 'welcomeMessage');
    if (k == null) return;
    if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(k) || keys.contains(k)) {
      setState(() => msg = 'Clave inválida o repetida: $k');
      return;
    }
    setState(() {
      keys.add(k);
      for (final l in locs) {
        ctl['${l.code}|$k'] = TextEditingController();
      }
      dirty = true;
    });
  }

  Future<void> _addLocale() async {
    final code = await promptText(context, s, 'Código de idioma (es, fr, pt_BR…)', hint: 'es');
    if (code == null || locs.isEmpty) return;
    if (!RegExp(r'^[a-z]{2,3}(_[A-Za-z]{2,4})?$').hasMatch(code) || locs.any((l) => l.code == code)) {
      setState(() => msg = 'Código inválido o repetido: $code');
      return;
    }
    final base = p.basenameWithoutExtension(locs.first.file.path);
    final prefix = base.endsWith('_${locs.first.code}') ? base.substring(0, base.length - locs.first.code.length - 1) : 'app';
    final l = _Loc(code, File(p.join(dir!, '${prefix}_$code.arb')), {'@@locale': code});
    setState(() {
      locs.add(l);
      for (final k in keys) {
        ctl['$code|$k'] = TextEditingController();
      }
      dirty = true;
    });
  }

  void _delKey(String k) {
    setState(() {
      keys.remove(k);
      for (final l in locs) {
        ctl.remove('${l.code}|$k')?.dispose();
      }
      dirty = true;
    });
  }

  Future<void> _setup() async {
    final root = s.root!;
    final l10n = File(p.join(root, 'l10n.yaml'));
    if (!l10n.existsSync()) l10n.writeAsStringSync('arb-dir: lib/l10n\ntemplate-arb-file: app_en.arb\noutput-localization-file: app_localizations.dart\n');
    final d = Directory(p.join(root, 'lib', 'l10n'))..createSync(recursive: true);
    final en = File(p.join(d.path, 'app_en.arb'));
    if (!en.existsSync()) en.writeAsStringSync('{\n  "@@locale": "en",\n  "helloWorld": "Hello World!",\n  "@helloWorld": {\n    "description": "Saludo de ejemplo"\n  }\n}\n');
    final ps = File(p.join(root, 'pubspec.yaml'));
    var src = ps.readAsStringSync();
    if (!RegExp(r'^\s*generate:\s*true', multiLine: true).hasMatch(src)) {
      src = src.replaceFirstMapped(RegExp(r'^flutter:[ \t]*$', multiLine: true), (m) => 'flutter:\n  generate: true');
      ps.writeAsStringSync(src);
      s.reloadDoc(ps.path, src);
    }
    setState(() => msg = 'Instalando flutter_localizations e intl…');
    await s.pub(['add', 'flutter_localizations', '--sdk=flutter']);
    await s.pub(['add', 'intl']);
    _load();
  }

  Future<void> _close() async {
    if (dirty && !await confirm(context, s, 'Cambios sin guardar', 'Hay traducciones sin guardar. ¿Cerrar y descartarlas?', ok: 'Descartar')) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    final shown = keys.where((k) => filter.isEmpty || k.toLowerCase().contains(filter.toLowerCase()) || locs.any((l) => (ctl['${l.code}|$k']?.text ?? '').toLowerCase().contains(filter.toLowerCase()))).toList();
    final w = 240.0 + locs.length * 320.0 + 60;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: SizedBox(
        width: size.width < 1100 ? size.width - 48 : 1060,
        height: size.height < 700 ? size.height - 48 : 660,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
            child: Row(children: [
              Icon(Icons.language, color: t.accent),
              const SizedBox(width: 10),
              const Text('Localización (ARB)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              if (locs.isNotEmpty) SizedBox(width: 220, height: 36, child: TextField(onChanged: (v) => setState(() => filter = v), style: const TextStyle(fontSize: 13), decoration: const InputDecoration(hintText: 'Filtrar claves / textos', prefixIcon: Icon(Icons.search, size: 16), contentPadding: EdgeInsets.zero))),
              const Spacer(),
              if (locs.isNotEmpty) ...[
                TextButton.icon(onPressed: _addKey, icon: const Icon(Icons.add, size: 18), label: const Text('Clave')),
                TextButton.icon(onPressed: _addLocale, icon: const Icon(Icons.translate, size: 18), label: const Text('Idioma')),
                OutlinedButton(onPressed: dirty ? _save : null, child: const Text('Guardar')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => _save(gen: true), child: const Text('Guardar y generar')),
              ],
              IconButton(onPressed: _close, icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: locs.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.translate, size: 56, color: t.muted),
                      const SizedBox(height: 10),
                      Text('No se encontraron archivos .arb en\n${dir ?? ''}', textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                      const SizedBox(height: 14),
                      FilledButton.icon(onPressed: _setup, icon: const Icon(Icons.auto_fix_high), label: const Text('Configurar localización del proyecto')),
                      const SizedBox(height: 6),
                      Text('Crea l10n.yaml, lib/l10n/app_en.arb, activa generate: true\ne instala flutter_localizations e intl.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: t.muted)),
                    ]),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: w,
                      child: Column(children: [
                        Container(
                          color: t.tab,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            const SizedBox(width: 12),
                            const SizedBox(width: 228, child: Text('CLAVE', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600))),
                            for (var i = 0; i < locs.length; i++) SizedBox(width: 320, child: Text(i == 0 ? '${locs[i].code.toUpperCase()}  (plantilla)' : locs[i].code.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final k = shown[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  SizedBox(width: 228, child: Padding(padding: const EdgeInsets.only(top: 10, right: 8), child: SelectableText(k, style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace'])))),
                                  for (var j = 0; j < locs.length; j++)
                                    SizedBox(
                                      width: 320,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: TextField(
                                          controller: ctl['${locs[j].code}|$k'],
                                          minLines: 1,
                                          maxLines: 4,
                                          style: const TextStyle(fontSize: 13),
                                          onChanged: (_) => setState(() => dirty = true),
                                          decoration: InputDecoration(
                                            enabledBorder: (j > 0 && (ctl['${locs[j].code}|$k']?.text ?? '').isEmpty)
                                                ? OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.redAccent.withAlpha(150)))
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  iconBtn(Icons.delete_outline, 'Eliminar clave', () => _delKey(k)),
                                ]),
                              );
                            },
                          ),
                        ),
                      ]),
                    ),
                  ),
          ),
          Divider(height: 1, color: t.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              Text('${keys.length} claves · ${locs.length} idiomas', style: TextStyle(fontSize: 12, color: t.muted)),
              const SizedBox(width: 16),
              if (locs.length > 1) Text(missing == 0 ? 'Traducciones completas ✓' : '$missing traducciones pendientes (en rojo)', style: TextStyle(fontSize: 12, color: missing == 0 ? Colors.lightGreenAccent : Colors.redAccent)),
              const Spacer(),
              Text(msg, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
