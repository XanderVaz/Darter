import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_info.dart';
import '../services/monaco_local.dart';
import '../services/updater.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'common.dart';
import 'logo.dart';

const _mono = TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']);

Widget _chip(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(40), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withAlpha(130))),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
    );

Widget _h(String t, IdeTheme th) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(t, style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: th.muted)),
    );

// ───────────────────────── Acerca de ─────────────────────────
Future<void> showAboutDarter(BuildContext c, IdeState s) => showDialog<void>(context: c, builder: (_) => _About(s));

class _About extends StatefulWidget {
  const _About(this.s);
  final IdeState s;
  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  IdeState get s => widget.s;
  Map<String, String> sdk = {};

  @override
  void initState() {
    super.initState();
    _loadSdk();
  }

  Future<void> _loadSdk() async {
    try {
      final r = await Process.run('flutter', ['--version', '--machine'], runInShell: true);
      final out = '${r.stdout}';
      final i = out.indexOf('{');
      if (i >= 0) {
        final j = jsonDecode(out.substring(i)) as Map;
        sdk = {'Flutter': '${j['frameworkVersion']} · ${j['channel']}', 'Dart': '${j['dartSdkVersion']}'.split(' ').first};
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  List<(String, String)> _rows() => [
        ('Versión', 'v$kAppVersion  (compilación $kBuildNumber)'),
        ('Canal de actualizaciones', s.betaChannel ? 'Beta' : 'Estable'),
        ('Flutter SDK', sdk['Flutter'] ?? 'no detectado'),
        ('Dart SDK', sdk['Dart'] ?? 'no detectado'),
        ('Motor de la app (Dart)', Platform.version.split(' ').first),
        ('Sistema operativo', '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}'),
        ('Editor (Monaco)', 'v$monacoVersion · ${s.monacoBase != null ? 'copia local (sin conexión)' : 'CDN'}'),
        ('Servidor de lenguaje', s.lspStatus.isEmpty ? '—' : s.lspStatus),
      ];

  String get _info => '$kAppName v$kAppVersion (compilación $kBuildNumber)\n${_rows().skip(1).map((r) => '${r.$1}: ${r.$2}').join('\n')}';

  String get _initials => kCreatorName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

  Widget _link(String label, String url, IconData icon) => TextButton.icon(onPressed: () => s.openUrl(url), icon: Icon(icon, size: 16), label: Text(label));

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height - 48),
        child: ListenableBuilder(
          listenable: s,
          builder: (_, __) => Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 28, 30, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(
                    child: Column(children: [
                      const LogoMark(size: 112, background: true),
                      const SizedBox(height: 14),
                      const Text(kAppName, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: .5)),
                      Text(kAppTagline, style: TextStyle(fontSize: 14, color: t.muted)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [_chip('v$kAppVersion', t.accent), _chip(s.betaChannel ? 'BETA' : 'ESTABLE', s.betaChannel ? Colors.amber : Colors.lightGreenAccent)]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (s.updateAvailable != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      decoration: BoxDecoration(color: Colors.amber.withAlpha(35), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withAlpha(140))),
                      child: Row(children: [
                        const Icon(Icons.system_update_alt, size: 18, color: Colors.amber),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Nueva versión disponible: v${s.updateAvailable!.version}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        FilledButton(onPressed: () => showUpdateDialog(context, s), child: const Text('Ver')),
                      ]),
                    )
                  else if (s.checkingUpdate)
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Buscando actualizaciones…')])
                  else if (s.upToDate)
                    const Center(child: Text('✓ Estás usando la última versión', style: TextStyle(color: Colors.lightGreenAccent))),
                  const SizedBox(height: 14),
                  Text(kAppDescription, textAlign: TextAlign.center, style: TextStyle(height: 1.45, color: t.text.withAlpha(210))),

                  _h('CREADOR', t),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF5B34F0), Color(0xFFC42BC9), Color(0xFFFF4D6D)])),
                          child: Text(_initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(kCreatorName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(kCreatorRole, style: TextStyle(color: t.muted)),
                        ])),
                      ]),
                      Wrap(children: [
                        if (kCreatorEmail.isNotEmpty) _link('Correo', 'mailto:$kCreatorEmail', Icons.mail_outline),
                        if (kCreatorWebsite.isNotEmpty) _link('Sitio web', kCreatorWebsite, Icons.language),
                        if (kCreatorGithub.isNotEmpty) _link('GitHub', 'https://github.com/$kCreatorGithub', Icons.code),
                        if (kRepoConfigured) _link('Repositorio', kRepoUrl, Icons.folder_special_outlined),
                      ]),
                    ]),
                  ),

                  _h('INFORMACIÓN DEL SISTEMA', t),
                  for (final r in _rows())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 190, child: Text(r.$1, style: TextStyle(fontSize: 12.5, color: t.muted))),
                        Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 12.5))),
                      ]),
                    ),

                  _h('CRÉDITOS Y COMPONENTES', t),
                  _credit('Flutter', 'Framework de UI · BSD-3-Clause', 'https://flutter.dev', t),
                  _credit('Dart', 'Lenguaje y SDK · BSD-3-Clause', 'https://dart.dev', t),
                  _credit('Monaco Editor', 'Editor de código · MIT · Microsoft', 'https://microsoft.github.io/monaco-editor/', t),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Paquetes de Dart: flutter_inappwebview, file_picker, http, shared_preferences, path y yaml. Consulta «Licencias de terceros» para ver todos los textos de licencia.', style: TextStyle(fontSize: 12, color: t.muted, height: 1.4)),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: t.border),
                  Text('© $kCopyrightYear $kCreatorName · $kLicenseName', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Flutter y Dart son marcas de Google LLC. Visual Studio Code y Monaco son marcas o productos de Microsoft. $kAppName es un proyecto independiente y no está afiliado, patrocinado ni respaldado por Google ni por Microsoft.',
                    style: TextStyle(fontSize: 11.5, color: t.muted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                ]),
              ),
            ),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: kAppName,
                    applicationVersion: 'v$kAppVersion',
                    applicationIcon: const Padding(padding: EdgeInsets.all(8), child: LogoMark(size: 64, background: true)),
                    applicationLegalese: '© $kCopyrightYear $kCreatorName',
                  ),
                  child: const Text('Licencias de terceros'),
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _info));
                    s.info('Información copiada al portapapeles');
                  },
                  child: const Text('Copiar información'),
                ),
                if (kRepoConfigured) TextButton(onPressed: () => s.openUrl(issueUrl(body: '\n\n---\n$_info')), child: const Text('Reportar un problema')),
                OutlinedButton.icon(onPressed: () => showUpdateDialog(context, s), icon: const Icon(Icons.system_update_alt, size: 18), label: const Text('Buscar actualizaciones')),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _credit(String name, String desc, String url, IdeTheme t) => InkWell(
        onTap: () => s.openUrl(url),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.favorite_border, size: 14, color: t.accent),
            const SizedBox(width: 10),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Expanded(child: Text(desc, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.muted))),
            Icon(Icons.open_in_new, size: 13, color: t.muted),
          ]),
        ),
      );
}

// ───────────────────────── Actualizaciones ─────────────────────────
Future<void> showUpdateDialog(BuildContext c, IdeState s) => showDialog<void>(context: c, builder: (_) => _UpdateDialog(s));

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(this.s);
  final IdeState s;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  IdeState get s => widget.s;

  @override
  void initState() {
    super.initState();
    if (s.updateAvailable == null && !s.checkingUpdate && !s.updateBusy) s.checkForUpdates();
  }

  String _notes(String body) {
    final out = <String>[];
    for (var l in const LineSplitter().convert(body)) {
      l = l.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!).replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1)!).replaceAll('`', '');
      if (l.startsWith('#')) {
        out.add('\n${l.replaceFirst(RegExp(r'^#+\s*'), '').toUpperCase()}');
      } else if (RegExp(r'^\s*[-*]\s+').hasMatch(l)) {
        out.add('  •  ${l.replaceFirst(RegExp(r'^\s*[-*]\s+'), '')}');
      } else {
        out.add(l);
      }
    }
    return out.join('\n').trim();
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 640),
        child: ListenableBuilder(
          listenable: s,
          builder: (_, __) => Padding(
            padding: const EdgeInsets.all(24),
            child: _body(t),
          ),
        ),
      ),
    );
  }

  Widget _body(IdeTheme t) {
    final r = s.updateAvailable;
    Widget title(IconData i, Color c, String text) => Row(children: [Icon(i, color: c, size: 26), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))]);

    if (s.updateBusy) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        title(Icons.downloading, t.accent, 'Actualizando $kAppName…'),
        const SizedBox(height: 20),
        LinearProgressIndicator(value: s.updateProgress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 10),
        Text(s.updateStatus, style: TextStyle(color: t.muted)),
        const SizedBox(height: 8),
        Text('No cierres la aplicación. Se reiniciará sola al terminar.', style: TextStyle(fontSize: 12, color: t.muted)),
      ]);
    }
    if (s.checkingUpdate) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 16),
        const Text('Buscando actualizaciones…'),
        const SizedBox(height: 10),
      ]);
    }
    if (s.updateError.isNotEmpty && r == null) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        title(Icons.error_outline, Colors.redAccent, 'No se pudo buscar'),
        const SizedBox(height: 12),
        SelectableText(s.updateError, style: TextStyle(color: t.muted, height: 1.4)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          const SizedBox(width: 8),
          FilledButton(onPressed: s.checkForUpdates, child: const Text('Reintentar')),
        ]),
      ]);
    }
    if (r == null) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        title(Icons.check_circle, Colors.lightGreenAccent, '$kAppName está actualizado'),
        const SizedBox(height: 10),
        Text('Tienes la versión v$kAppVersion${s.betaChannel ? ' (canal beta)' : ''}.', style: TextStyle(color: t.muted)),
        if (s.updateStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.updateStatus, style: const TextStyle(color: Colors.amber))),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: s.checkForUpdates, child: const Text('Buscar de nuevo')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ]),
      ]);
    }
    final asset = pickAsset(r);
    final d = r.published;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.system_update_alt, color: Colors.amber, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text('$kAppName v${r.version} disponible', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (r.prerelease) _chip('BETA', Colors.amber),
      ]),
      const SizedBox(height: 6),
      Text('Tienes v$kAppVersion${d != null ? '  ·  publicada el ${d.day}/${d.month}/${d.year}' : ''}', style: TextStyle(color: t.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      if (asset != null)
        Row(children: [Icon(Icons.inventory_2_outlined, size: 16, color: t.muted), const SizedBox(width: 8), Expanded(child: Text('${asset.name}  (${_mb(asset.size)})', overflow: TextOverflow.ellipsis, style: _mono))])
      else
        const Text('Esta versión no incluye un archivo para tu sistema. Ábrela en GitHub para descargarla.', style: TextStyle(color: Colors.amber, fontSize: 12.5)),
      const SizedBox(height: 14),
      Text('NOVEDADES', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: t.muted)),
      const SizedBox(height: 6),
      Flexible(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
          child: SingleChildScrollView(child: SelectableText(r.body.trim().isEmpty ? 'Sin notas de la versión.' : _notes(r.body), style: const TextStyle(fontSize: 13, height: 1.45))),
        ),
      ),
      if (s.updateError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: SelectableText(s.updateError, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5))),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        TextButton(onPressed: () { s.skipUpdate(); Navigator.pop(context); }, child: const Text('Omitir esta versión')),
        TextButton(onPressed: () => s.openUrl(r.url), child: const Text('Ver en GitHub')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Más tarde')),
        FilledButton.icon(onPressed: asset == null ? null : s.installUpdate, icon: const Icon(Icons.download, size: 18), label: const Text('Descargar e instalar')),
      ]),
    ]);
  }
}

// ───────────────────────── Atajos de teclado ─────────────────────────
Future<void> showShortcuts(BuildContext c, IdeState s) => showDialog<void>(context: c, builder: (_) => _Shortcuts(s));

class _Shortcuts extends StatelessWidget {
  const _Shortcuts(this.s);
  final IdeState s;

  static const _groups = <String, List<(String, String)>>{
    'General': [('Ctrl+P', 'Abrir archivo'), ('Ctrl+Shift+P', 'Paleta de comandos'), ('Ctrl+S', 'Guardar'), ('Ctrl+O', 'Abrir carpeta'), ('Ctrl+`', 'Panel inferior'), ('Ctrl+Shift+T', 'Ir a test / implementación')],
    'Editor': [('Ctrl+.', 'Acciones de código'), ('F2', 'Renombrar símbolo'), ('F12', 'Ir a la definición'), ('Shift+F12', 'Referencias'), ('Ctrl+Shift+O', 'Ir a símbolo'), ('Alt+Shift+F', 'Formatear'), ('Alt+Shift+O', 'Organizar imports')],
    'Ejecutar y depurar': [('F5', 'Depurar / continuar'), ('Ctrl+F5', 'Ejecutar sin depurar'), ('F9', 'Breakpoint'), ('F10', 'Step over'), ('F11', 'Step into'), ('Shift+F11', 'Step out'), ('Shift+F5', 'Detener')],
  };

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
            child: Row(children: [
              Icon(Icons.keyboard_outlined, color: t.accent),
              const SizedBox(width: 10),
              const Expanded(child: Text('Atajos de teclado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), children: [
              for (final g in _groups.entries) ...[
                _h(g.key.toUpperCase(), t),
                for (final k in g.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(
                        width: 130,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.border)),
                        child: Text(k.$1, style: _mono),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(k.$2)),
                    ]),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
