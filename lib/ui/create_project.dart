import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';

void showCreateProject(BuildContext c, IdeState s) => showDialog(context: c, barrierDismissible: false, builder: (_) => CreateProjectDialog(s));

class _Tpl {
  const _Tpl(this.id, this.title, this.desc, this.icon, {this.platforms = false, this.empty = false, this.org = true});
  final String id, title, desc;
  final IconData icon;
  final bool platforms, empty, org;
}

const _flutterTpls = [
  _Tpl('app', 'Aplicación', 'App Flutter multiplataforma lista para ejecutar.', Icons.phone_android, platforms: true, empty: true),
  _Tpl('skeleton', 'App con estructura', 'Incluye tema, localización (l10n) y pantalla de ajustes.', Icons.dashboard_customize_outlined, platforms: true),
  _Tpl('package', 'Paquete', 'Código Dart/Flutter reutilizable para publicar en pub.dev.', Icons.inventory_2_outlined),
  _Tpl('plugin', 'Plugin', 'Paquete con código nativo por plataforma (Kotlin, Swift, C++…).', Icons.extension_outlined, platforms: true),
  _Tpl('plugin_ffi', 'Plugin FFI', 'Plugin que llama a código C/C++ vía dart:ffi.', Icons.memory, platforms: true),
  _Tpl('module', 'Módulo (add-to-app)', 'Integra Flutter dentro de una app Android/iOS existente.', Icons.layers_outlined),
];

const _dartTpls = [
  _Tpl('console', 'Consola', 'Aplicación de línea de comandos simple.', Icons.terminal, org: false),
  _Tpl('cli', 'CLI avanzada', 'CLI con parseo de argumentos (package:args).', Icons.keyboard_command_key, org: false),
  _Tpl('package', 'Paquete', 'Librería Dart reutilizable.', Icons.inventory_2_outlined, org: false),
  _Tpl('server-shelf', 'Servidor Shelf', 'Servidor HTTP con package:shelf.', Icons.dns_outlined, org: false),
  _Tpl('web', 'Web (Dart)', 'Aplicación web con Dart puro.', Icons.language, org: false),
];

const _allPlatforms = {
  'android': Icons.android, 'ios': Icons.phone_iphone, 'web': Icons.language,
  'windows': Icons.desktop_windows_outlined, 'macos': Icons.laptop_mac, 'linux': Icons.computer,
};

const _reserved = {'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with', 'flutter', 'test', 'dart', 'async', 'await'};

class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog(this.s, {super.key});
  final IdeState s;
  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  bool flutter = true;
  _Tpl tpl = _flutterTpls.first;
  final name = TextEditingController(text: 'mi_app');
  final org = TextEditingController(text: 'com.example');
  final desc = TextEditingController(text: 'Un nuevo proyecto Flutter.');
  late final TextEditingController dir;
  bool empty = false, noPub = false, git = false, busy = false;
  String? error;
  final platforms = <String>{..._allPlatforms.keys};
  IdeState get s => widget.s;

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    dir = TextEditingController(text: s.lastDir ?? home);
  }

  List<_Tpl> get tpls => flutter ? _flutterTpls : _dartTpls;

  String? get nameError {
    final n = name.text.trim();
    if (n.isEmpty) return 'Escribe un nombre';
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(n)) return 'Usa minúsculas, números y _ (debe empezar con letra)';
    if (_reserved.contains(n)) return '"$n" es una palabra reservada';
    if (dir.text.isNotEmpty && Directory(p.join(dir.text, n)).existsSync()) return 'Ya existe una carpeta con ese nombre';
    return null;
  }

  String? get orgError => flutter && tpl.org && !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$').hasMatch(org.text.trim()) ? 'Formato: com.empresa' : null;
  String? get platError => flutter && tpl.platforms && platforms.isEmpty ? 'Selecciona al menos una plataforma' : null;
  bool get valid => nameError == null && orgError == null && platError == null && dir.text.isNotEmpty && Directory(dir.text).existsSync();

  List<String> get args => flutter
      ? [
          'create', '--template=${tpl.id}', '--org', org.text.trim(),
          if (tpl.platforms) '--platforms=${platforms.join(',')}',
          if (tpl.empty && empty) '--empty',
          if (noPub) '--no-pub',
          name.text.trim(),
        ]
      : ['create', '-t', tpl.id, if (noPub) '--no-pub', name.text.trim()];

  Future<void> _create() async {
    setState(() { busy = true; error = null; });
    final exe = flutter ? 'flutter' : 'dart';
    final code = await s.execArgs(exe, args, cwd: dir.text);
    if (code != 0) {
      if (mounted) setState(() { busy = false; error = 'La creación falló (código $code). Revisa los mensajes de abajo.'; });
      return;
    }
    final path = p.join(dir.text, name.text.trim());
    // La descripción se escribe en el pubspec (evita problemas de comillas en el shell).
    if (flutter && desc.text.trim().isNotEmpty) {
      try {
        final f = File(p.join(path, 'pubspec.yaml'));
        final d = desc.text.trim().replaceAll('"', r'\"');
        f.writeAsStringSync(f.readAsStringSync().replaceFirst(RegExp(r'^description:.*$', multiLine: true), 'description: "$d"'));
      } catch (_) {}
    }
    if (git) {
      try {
        await Process.run('git', ['init'], workingDirectory: path);
      } catch (_) {}
    }
    s.setLastDir(dir.text);
    await s.openProject(path);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    final preview = '${flutter ? 'flutter' : 'dart'} ${args.join(' ')}';
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: SizedBox(
        width: size.width < 948 ? size.width - 48 : 900,
        height: size.height < 688 ? size.height - 48 : 640,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: t.accent.withAlpha(40), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.create_new_folder_outlined, color: t.accent)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Crear nuevo proyecto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text('Elige una plantilla y configura tu proyecto', style: TextStyle(fontSize: 12.5, color: t.muted)),
              ])),
              IconButton(onPressed: busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 290, child: _left(t)),
              VerticalDivider(width: 1, color: t.border),
              Expanded(child: _form(t)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
                child: busy
                    ? ValueListenableBuilder<int>(
                        valueListenable: s.logRev,
                        builder: (_, __, ___) => Text(s.log.skip(s.log.length > 4 ? s.log.length - 4 : 0).join('\n'), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12, color: t.muted)),
                      )
                    : SelectableText('\$ $preview', style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12, color: t.accent)),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5))),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: valid && !busy ? _create : null,
                  icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rocket_launch, size: 18),
                  label: Text(busy ? 'Creando…' : 'Crear proyecto'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _left(t) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Flutter'), icon: Icon(Icons.flutter_dash, size: 18)),
                ButtonSegment(value: false, label: Text('Dart'), icon: Icon(Icons.code, size: 18)),
              ],
              selected: {flutter},
              onSelectionChanged: busy ? null : (v) => setState(() { flutter = v.first; tpl = tpls.first; }),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), children: [
            for (final x in tpls)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: busy ? null : () => setState(() => tpl = x),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tpl == x ? t.accent.withAlpha(35) : t.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tpl == x ? t.accent : t.border, width: tpl == x ? 1.5 : 1),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(x.icon, color: tpl == x ? t.accent : t.muted),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(x.desc, style: TextStyle(fontSize: 12, color: t.muted)),
                      ])),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]);

  Widget _label(String l, t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(l, style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: t.muted)));

  Widget _form(t) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('NOMBRE DEL PROYECTO', t),
          TextField(controller: name, enabled: !busy, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.badge_outlined, size: 18), errorText: nameError, hintText: 'mi_app')),
          _label('UBICACIÓN', t),
          Row(children: [
            Expanded(child: TextField(controller: dir, enabled: !busy, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.folder_outlined, size: 18)))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: busy ? null : () async {
                final d = await FilePicker.platform.getDirectoryPath();
                if (d != null) setState(() => dir.text = d);
              },
              child: const Text('Examinar'),
            ),
          ]),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Se creará en: ${p.join(dir.text, name.text.trim())}', style: TextStyle(fontSize: 12, color: t.muted))),
          if (flutter && tpl.org) ...[
            _label('ORGANIZACIÓN (ID DEL PAQUETE)', t),
            TextField(controller: org, enabled: !busy, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.business_outlined, size: 18), errorText: orgError, hintText: 'com.empresa')),
          ],
          if (flutter) ...[
            _label('DESCRIPCIÓN', t),
            TextField(controller: desc, enabled: !busy, decoration: const InputDecoration(prefixIcon: Icon(Icons.notes, size: 18))),
          ],
          if (flutter && tpl.platforms) ...[
            _label('PLATAFORMAS', t),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _allPlatforms.entries)
                FilterChip(
                  avatar: Icon(e.value, size: 16),
                  label: Text(e.key),
                  selected: platforms.contains(e.key),
                  onSelected: busy ? null : (v) => setState(() => v ? platforms.add(e.key) : platforms.remove(e.key)),
                ),
            ]),
            Row(children: [
              TextButton(onPressed: () => setState(() => platforms.addAll(_allPlatforms.keys)), child: const Text('Todas')),
              TextButton(onPressed: () => setState(platforms.clear), child: const Text('Ninguna')),
              if (platError != null) Text(platError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ]),
          ],
          _label('OPCIONES', t),
          if (flutter && tpl.empty) _opt('Proyecto vacío', 'Sin la app de ejemplo del contador (--empty)', empty, (v) => empty = v),
          _opt('Omitir pub get', 'No descargar dependencias al crear (--no-pub)', noPub, (v) => noPub = v),
          _opt('Inicializar repositorio Git', 'Ejecuta git init en la carpeta del proyecto', git, (v) => git = v),
        ]),
      );

  Widget _opt(String title, String sub, bool v, void Function(bool) set) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        subtitle: Text(sub, style: TextStyle(fontSize: 12, color: s.theme.muted)),
        value: v,
        onChanged: busy ? null : (x) => setState(() => set(x)),
      );
}
