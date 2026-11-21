import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../app_info.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'about_dialog.dart';
import 'arb_editor.dart';
import 'assets_dialog.dart';
import 'bottom_panel.dart';
import 'command_palette.dart';
import 'common.dart';
import 'logo.dart';
import 'create_project.dart';
import 'debug_panel.dart';
import 'diff_view.dart';
import 'merge_resolver.dart';
import 'deps_panel.dart';
import 'editor.dart';
import 'explorer.dart';
import 'git_panel.dart';
import 'outline_panel.dart';
import 'run_config.dart';
import 'search_panel.dart';
import 'inspector_panel.dart';
import 'settings_dialog.dart';
import 'tasks_dialog.dart';
import 'snippets_dialog.dart';
import 'test_panel.dart';

class IdeShell extends StatefulWidget {
  const IdeShell({super.key, required this.state});
  final IdeState state;
  @override
  State<IdeShell> createState() => _IdeShellState();
}

class _IdeShellState extends State<IdeShell> {
  int side = 0;
  final _visited = <int>{0};
  bool showBottom = true;
  double sideW = 320;
  IdeState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.confirmDiscard = () => confirm(context, s, 'Cambios sin guardar', 'Hay archivos modificados sin guardar. ¿Continuar y descartarlos?', ok: 'Descartar');
    s.onDebugStart = () => setState(() {
      side = 3;
      _visited.add(3);
    });
    s.onOpenResolver = (path) => showMergeResolver(context, s, path);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
    s.onToast = (m) {
      if (!mounted) return;
      final ms = ScaffoldMessenger.of(context);
      ms.hideCurrentSnackBar();
      ms.showSnackBar(SnackBar(content: Text(m, maxLines: 2, overflow: TextOverflow.ellipsis), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating, width: 520));
    };
  }

  void _newProject() => showCreateProject(context, s);

  Future<void> _checkRecovery() async {
    if (!mounted || s.recoverable.isEmpty) return;
    final list = s.recoverable;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.theme.panel,
        surfaceTintColor: Colors.transparent,
        title: const Text('Cambios sin guardar recuperados', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('La sesión anterior terminó con archivos modificados que no se guardaron:'),
            const SizedBox(height: 8),
            for (final r in list.take(8)) Text('•  ${p.basename(r.path)}', style: const TextStyle(fontSize: 13)),
            if (list.length > 8) Text('… y ${list.length - 8} más'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Descartar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok == true) {
      s.restoreRecovered();
    } else {
      s.discardRecovered();
    }
  }

  Future<void> _todos() async {
    final hits = await s.search(r'\b(TODO|FIXME|HACK|XXX)\b', regex: true, caseSensitive: true);
    if (!mounted) return;
    if (hits.isEmpty) {
      s.info('Sin TODO/FIXME en el proyecto ✓');
      return;
    }
    showCommandPalette(context, s, pure: true, placeholder: '${hits.length} tareas pendientes', commands: [
      for (final h in hits)
        PaletteCmd('${p.relative(h.path, from: s.root!)}:${h.line}', Icons.checklist, () => s.openFile(h.path, line: h.line, col: 1), hint: h.text.length > 60 ? h.text.substring(0, 60) : h.text),
    ]);
  }
  void _toggleBottom() => setState(() => showBottom = !showBottom);
  void _f5() {
    if (s.debugActive) {
      if (s.debugPaused) s.dbgContinue();
    } else {
      s.startDebug();
    }
  }
  void _palette(bool commands) => showCommandPalette(context, s, commands: _commands(), commandMode: commands);

  List<PaletteCmd> _commands() => [
        PaletteCmd('Nuevo proyecto…', Icons.add_box_outlined, _newProject),
        PaletteCmd('Abrir carpeta…', Icons.folder_open, () => pickAndOpenFolder(s), hint: 'Ctrl+O'),
        PaletteCmd('Cerrar proyecto', Icons.close, s.closeProject),
        PaletteCmd('Guardar', Icons.save, s.save, hint: 'Ctrl+S'),
        PaletteCmd('Guardar todo', Icons.save_alt, s.saveAll),
        PaletteCmd('Formatear archivo actual', Icons.format_align_left, s.formatCurrent, hint: 'Alt+Shift+F'),
        PaletteCmd('Depurar (iniciar)', Icons.bug_report, s.startDebug, hint: 'F5'),
        PaletteCmd('Run sin depurar', Icons.play_arrow, s.run, hint: 'Ctrl+F5'),
        PaletteCmd('Debug: continuar', Icons.play_arrow, s.dbgContinue),
        PaletteCmd('Debug: step over', Icons.redo, s.dbgNext, hint: 'F10'),
        PaletteCmd('Debug: step into', Icons.south, s.dbgStepIn, hint: 'F11'),
        PaletteCmd('Debug: step out', Icons.north, s.dbgStepOut, hint: 'Shift+F11'),
        PaletteCmd('Debug: detener', Icons.stop, s.stopDebug, hint: 'Shift+F5'),
        PaletteCmd('Quitar todos los breakpoints', Icons.radio_button_unchecked, s.clearBreakpoints),
        PaletteCmd('Hot reload', Icons.bolt, s.hotReload),
        PaletteCmd('Hot restart', Icons.restart_alt, s.hotRestart),
        PaletteCmd('Stop', Icons.stop, s.stop),
        PaletteCmd('Configuración de ejecución…', Icons.tune, () => showRunConfig(context, s)),
        PaletteCmd('Abrir DevTools', Icons.speed, s.openDevTools),
        PaletteCmd('Ajustes…', Icons.settings_outlined, () => showSettings(context, s)),
        PaletteCmd('Alternar terminal', Icons.terminal, _toggleBottom, hint: 'Ctrl+`'),
        PaletteCmd('Pub: get', Icons.download, s.pubGet),
        PaletteCmd('Pub: upgrade', Icons.upgrade, s.pubUpgrade),
        PaletteCmd('Pub: outdated', Icons.list_alt, s.pubOutdated),
        PaletteCmd('Pub: deps (árbol)', Icons.account_tree_outlined, s.pubDeps),
        PaletteCmd('Analyze', Icons.search, s.analyze),
        PaletteCmd('Test (todos)', Icons.science_outlined, s.test),
        PaletteCmd('Test: archivo actual', Icons.science, s.testCurrent),
        PaletteCmd('Pruebas: ejecutar todas (panel)', Icons.science_outlined, () => s.runTests()),
        PaletteCmd('Pruebas: con cobertura (panel)', Icons.shield_outlined, () => s.runTests(coverage: true)),
        PaletteCmd('Nuevo terminal', Icons.add_box_outlined, s.addTerminal),
        PaletteCmd('Emuladores: actualizar lista', Icons.phone_android, s.refreshEmulators),
        PaletteCmd('Dart fix --apply', Icons.auto_fix_high, s.dartFix),
        PaletteCmd('Organizar imports', Icons.sort, s.organizeImports, hint: 'Alt+Shift+O'),
        PaletteCmd('Corregir todo (fix all)', Icons.done_all, s.fixAllIssues),
        PaletteCmd('build_runner: build', Icons.construction, s.buildRunner),
        PaletteCmd('build_runner: watch', Icons.visibility_outlined, s.buildRunnerWatch),
        PaletteCmd('Generar localizaciones (gen-l10n)', Icons.translate, s.genL10n),
        PaletteCmd('Editor de localización (ARB)…', Icons.language, () => showArbEditor(context, s)),
        PaletteCmd('Tareas pendientes (TODO/FIXME)…', Icons.checklist, _todos),
        PaletteCmd('Git: historial del archivo actual', Icons.history, () {
          final d = s.current;
          if (d != null && !d.isImage) showFileHistory(context, s, d.path);
        }),
        PaletteCmd('Git: comparar archivo actual con HEAD', Icons.difference_outlined, () async {
          final d = s.current;
          if (d == null || d.isImage) return;
          final x = await s.gitHeadVsWorking(d.path);
          if (mounted) showDiffDialog(context, s, title: '${d.name} · HEAD ↔ actual', path: d.path, original: x.a, modified: x.b);
        }),
        PaletteCmd('Git: resolver conflictos del archivo actual', Icons.merge_type, () {
          final d = s.current;
          if (d != null && !d.isImage) showMergeResolver(context, s, d.path);
        }),
        PaletteCmd('Git: abortar fusión', Icons.cancel_outlined, s.gitMergeAbort),
        PaletteCmd('Git: concluir fusión', Icons.check_circle_outline, s.gitMergeContinue),
        PaletteCmd('Comparar con el archivo guardado', Icons.compare, () {
          final d = s.current;
          if (d == null || d.isImage) return;
          showDiffDialog(context, s, title: '${d.name} · guardado ↔ editor', path: d.path, original: s.diskText(d.path), modified: d.content);
        }),
        PaletteCmd('Assets y fuentes…', Icons.image_outlined, () => showAssetsManager(context, s)),
        PaletteCmd('Descargar Monaco (editor sin conexión)', Icons.cloud_download_outlined, s.installMonaco),
        PaletteCmd('Acerca de $kAppName', Icons.info_outline, () => showAboutDarter(context, s)),
        PaletteCmd('Buscar actualizaciones…', Icons.system_update_alt, () => showUpdateDialog(context, s)),
        PaletteCmd('Atajos de teclado', Icons.keyboard_outlined, () => showShortcuts(context, s)),
        PaletteCmd('Gestionar snippets propios…', Icons.bolt, () => showSnippetsManager(context, s)),
        PaletteCmd('Tareas del proyecto…', Icons.checklist_rtl, () => showTasksManager(context, s)),
        for (final tk in s.projectTasks) PaletteCmd('Tarea: ${tk['name']}', Icons.play_circle_outline, () => s.runTask(tk)),
        PaletteCmd('Ver registro de errores', Icons.bug_report_outlined, () => showErrorLog(context, s)),
        PaletteCmd('Zoom del editor: aumentar', Icons.zoom_in, () => s.zoom(1), hint: 'Ctrl+='),
        PaletteCmd('Zoom del editor: reducir', Icons.zoom_out, () => s.zoom(-1), hint: 'Ctrl+-'),
        PaletteCmd('Zoom del editor: restablecer', Icons.zoom_out_map, () => s.zoom(0), hint: 'Ctrl+0'),
        PaletteCmd('Flutter clean', Icons.cleaning_services_outlined, s.clean),
        PaletteCmd('Flutter doctor', Icons.medical_services_outlined, s.doctor),
        PaletteCmd('Ir a test / implementación', Icons.swap_horiz, s.toggleTestFile, hint: 'Ctrl+Shift+T'),
        PaletteCmd('Logs del dispositivo (flutter logs)', Icons.receipt_long_outlined, s.flutterLogs),
        PaletteCmd('Build APK', Icons.android, s.buildApk),
        PaletteCmd('Build App Bundle', Icons.inventory_outlined, s.buildAppBundle),
        PaletteCmd('Build Web', Icons.language, s.buildWeb),
        PaletteCmd('Build Desktop', Icons.desktop_windows_outlined, s.buildDesktop),
        PaletteCmd('Git: refrescar', Icons.refresh, s.refreshGit),
        PaletteCmd('Git: pull', Icons.download, s.gitPull),
        PaletteCmd('Git: push', Icons.upload, s.gitPush),
        for (final th in IdeTheme.all) PaletteCmd('Tema: ${th.name}', Icons.palette_outlined, () => s.setTheme(th)),
      ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final t = s.theme;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true): s.save,
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): s.save,
              const SingleActivator(LogicalKeyboardKey.backquote, control: true): _toggleBottom,
              const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => pickAndOpenFolder(s),
              const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => _palette(false),
              const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): () => _palette(true),
              const SingleActivator(LogicalKeyboardKey.f5): _f5,
              const SingleActivator(LogicalKeyboardKey.f5, control: true): s.run,
              const SingleActivator(LogicalKeyboardKey.f5, shift: true): s.stopDebug,
              const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): s.toggleTestFile,
              const SingleActivator(LogicalKeyboardKey.f10): s.dbgNext,
              const SingleActivator(LogicalKeyboardKey.f11): s.dbgStepIn,
              const SingleActivator(LogicalKeyboardKey.f11, shift: true): s.dbgStepOut,
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: t.bg,
                body: Column(children: [
                  _toolbar(t),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _rail(t),
                      SizedBox(width: sideW, child: ColoredBox(color: t.side, child: _sidebar())),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(() => sideW = (sideW + d.delta.dx).clamp(240.0, 640.0)),
                          child: Container(width: 5, color: t.border),
                        ),
                      ),
                      Expanded(
                        child: Column(children: [
                          Expanded(child: EditorArea(s)),
                          if (showBottom) SizedBox(height: 260, child: BottomPanel(s, onClose: _toggleBottom)),
                        ]),
                      ),
                    ]),
                  ),
                  _status(t),
                ]),
              ),
            ),
          );
        },
      );

  Widget _menuBtn(String label, List<PopupMenuEntry<String>> items, void Function(String) onSel) => PopupMenuButton<String>(
        tooltip: '',
        onSelected: onSel,
        itemBuilder: (_) => items,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Text(label, style: const TextStyle(fontSize: 13))),
      );

  Widget _toolbar(IdeTheme t) => Container(
        color: t.side,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          const LogoMark(size: 28, background: true),
          const SizedBox(width: 6),
          _menuBtn('Archivo', [
            const PopupMenuItem(value: 'new', child: Text('Nuevo proyecto…')),
            const PopupMenuItem(value: 'open', child: Text('Abrir carpeta…   Ctrl+O')),
            if (s.recents.isNotEmpty) const PopupMenuDivider(),
            for (final r in s.recents.take(6)) PopupMenuItem(value: 'r:$r', child: Text(r, style: const TextStyle(fontSize: 12))),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'save', child: Text('Guardar   Ctrl+S')),
            const PopupMenuItem(value: 'saveall', child: Text('Guardar todo')),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'close', enabled: s.root != null, child: const Text('Cerrar proyecto')),
          ], (v) {
            if (v == 'new') _newProject();
            if (v == 'open') pickAndOpenFolder(s);
            if (v == 'save') s.save();
            if (v == 'saveall') s.saveAll();
            if (v == 'close') s.closeProject();
            if (v.startsWith('r:')) s.openProject(v.substring(2));
          }),
          _menuBtn('Ver', [
            const PopupMenuItem(value: 'files', child: Text('Abrir archivo…   Ctrl+P')),
            const PopupMenuItem(value: 'cmds', child: Text('Paleta de comandos…   Ctrl+Shift+P')),
            const PopupMenuItem(value: 'term', child: Text('Terminal   Ctrl+`')),
            const PopupMenuItem(value: 'settings', child: Text('Ajustes…')),
            const PopupMenuDivider(),
            for (final th in IdeTheme.all)
              PopupMenuItem(value: 't:${th.id}', child: Row(children: [Icon(s.theme.id == th.id ? Icons.check : null, size: 16), const SizedBox(width: 8), Text(th.name)])),
          ], (v) {
            if (v == 'files') _palette(false);
            if (v == 'cmds') _palette(true);
            if (v == 'term') _toggleBottom();
            if (v == 'settings') showSettings(context, s);
            if (v.startsWith('t:')) s.setTheme(IdeTheme.byId(v.substring(2)));
          }),
          _menuBtn('Ayuda', [
            const PopupMenuItem(value: 'about', child: Text('Acerca de $kAppName')),
            const PopupMenuItem(value: 'update', child: Text('Buscar actualizaciones…')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'keys', child: Text('Atajos de teclado')),
            PopupMenuItem(value: 'notes', enabled: kRepoConfigured, child: const Text('Notas de la versión (GitHub)')),
            PopupMenuItem(value: 'issue', enabled: kRepoConfigured, child: const Text('Reportar un problema')),
            const PopupMenuItem(value: 'log', child: Text('Ver registro de errores')),
          ], (v) {
            if (v == 'about') showAboutDarter(context, s);
            if (v == 'update') showUpdateDialog(context, s);
            if (v == 'keys') showShortcuts(context, s);
            if (v == 'notes') s.openUrl('$kRepoUrl/releases/tag/v$kAppVersion');
            if (v == 'issue') s.openUrl(issueUrl());
            if (v == 'log') showErrorLog(context, s);
          }),
          Expanded(
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _palette(false),
                child: Container(
                  width: 360,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.border)),
                  child: Text(s.root == null ? '$kAppName · Ctrl+P para buscar' : '🔍  ${s.root!.split(RegExp(r'[\\/]')).last}', style: TextStyle(fontSize: 12, color: t.muted)),
                ),
              ),
            ),
          ),
          if (s.isFlutter)
            DropdownButtonHideUnderline(
              child: DropdownButton<Device>(
                value: s.devices.contains(s.device) ? s.device : null,
                hint: const Text('Dispositivo', style: TextStyle(fontSize: 12)),
                dropdownColor: t.side,
                style: TextStyle(fontSize: 12, color: t.text),
                items: [for (final d in s.devices) DropdownMenuItem(value: d, child: Text(d.name))],
                onChanged: s.selectDevice,
              ),
            ),
          if (s.isFlutter) iconBtn(Icons.refresh, 'Refrescar dispositivos', s.refreshDevices),
          if (s.isFlutter)
            PopupMenuButton<String>(
              tooltip: 'Emuladores',
              icon: const Icon(Icons.phone_android, size: 18),
              onSelected: (v) {
                if (v == 'refresh') {
                  s.refreshEmulators();
                } else {
                  final e = s.emulators.where((x) => x.id == v);
                  if (e.isNotEmpty) s.launchEmulator(e.first);
                }
              },
              itemBuilder: (_) => [
                for (final e in s.emulators) PopupMenuItem(value: e.id, child: Text('▶  ${e.name}  (${e.platform})')),
                if (s.emulators.isEmpty) const PopupMenuItem(enabled: false, child: Text('Sin emuladores detectados')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'refresh', child: Text('Actualizar lista')),
              ],
            ),
          if (s.runConfigs.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: s.activeRun,
                dropdownColor: t.side,
                style: TextStyle(fontSize: 12, color: t.text),
                items: [for (var i = 0; i < s.runConfigs.length; i++) DropdownMenuItem(value: i, child: Text(s.runConfigs[i].name))],
                onChanged: (i) => s.selectRunConfig(i ?? 0),
              ),
            ),
          iconBtn(Icons.tune, 'Configuración de ejecución', s.root == null ? null : () => showRunConfig(context, s), color: s.runConfig.mode != 'debug' ? t.accent : null, size: 18),
          if (!s.isRunning) ...[
            iconBtn(Icons.bug_report, 'Depurar (F5)', s.root == null ? null : s.startDebug, color: Colors.orangeAccent, size: 20),
            iconBtn(Icons.play_arrow, 'Run sin depurar (Ctrl+F5)', s.root == null ? null : s.run, color: Colors.greenAccent, size: 22),
          ] else ...[
            if (s.debugActive) ...[
              iconBtn(Icons.play_arrow, 'Continuar (F5)', s.debugPaused ? s.dbgContinue : null, color: Colors.greenAccent, size: 20),
              iconBtn(Icons.pause, 'Pausar', s.debugPaused ? null : s.dbgPause, size: 20),
              iconBtn(Icons.redo, 'Step over (F10)', s.debugPaused ? s.dbgNext : null, size: 20),
              iconBtn(Icons.south, 'Step into (F11)', s.debugPaused ? s.dbgStepIn : null, size: 20),
              iconBtn(Icons.north, 'Step out (Shift+F11)', s.debugPaused ? s.dbgStepOut : null, size: 20),
            ],
            iconBtn(Icons.bolt, 'Hot reload', s.hotReload, color: Colors.amber, size: 20),
            iconBtn(Icons.restart_alt, 'Hot restart', s.hotRestart, size: 20),
            iconBtn(Icons.speed, s.devToolsUrl != null ? 'Abrir DevTools' : 'DevTools (esperando enlace)', s.openDevTools, color: s.devToolsUrl != null ? Colors.lightBlueAccent : t.muted, size: 20),
            iconBtn(Icons.stop, 'Stop', s.stop, color: Colors.redAccent, size: 20),
          ],
          iconBtn(Icons.terminal, 'Terminal', _toggleBottom, color: showBottom ? t.text : t.muted, size: 18),
        ]),
      );

  Widget _rail(IdeTheme t) {
    const items = [
      (Icons.folder_copy_outlined, 'Explorador'),
      (Icons.search, 'Buscar'),
      (Icons.account_tree_outlined, 'Git'),
      (Icons.bug_report_outlined, 'Depurar'),
      (Icons.science_outlined, 'Pruebas'),
      (Icons.format_list_bulleted, 'Esquema'),
      (Icons.inventory_2_outlined, 'Dependencias'),
      (Icons.build_outlined, 'Herramientas'),
      (Icons.widgets_outlined, 'Inspector de widgets'),
    ];
    return Container(
      width: 48,
      color: t.tab,
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(width: 2, color: side == i ? t.accent : Colors.transparent))),
            child: IconButton(
              tooltip: items[i].$2,
              iconSize: 22,
              icon: Icon(items[i].$1, color: side == i ? t.text : t.muted),
              onPressed: () => setState(() {
                side = i;
                _visited.add(i);
              }),
            ),
          ),
        const Spacer(),
        IconButton(tooltip: 'Paleta de comandos (Ctrl+Shift+P)', icon: Icon(Icons.keyboard_command_key, color: t.muted), onPressed: () => _palette(true)),
        IconButton(tooltip: 'Ajustes', icon: Icon(Icons.settings_outlined, color: t.muted), onPressed: () => showSettings(context, s)),
        const SizedBox(height: 6),
      ]),
    );
  }

  final _panelCache = <int, Widget>{};

  Widget _sidebar() {
    final panels = <Widget Function()>[
      () => Explorer(s, onNewProject: _newProject, onOpen: () => pickAndOpenFolder(s)),
      () => SearchPanel(s),
      () => GitPanel(s),
      () => DebugPanel(s),
      () => TestPanel(s),
      () => OutlinePanel(s),
      () => DepsPanel(s),
      _tools,
      () => InspectorPanel(s),
    ];
    return Stack(fit: StackFit.expand, children: [
      for (var i = 0; i < panels.length; i++)
        if (_visited.contains(i)) Offstage(offstage: side != i, child: side == i ? (_panelCache[i] = panels[i]()) : (_panelCache[i] ?? panels[i]())),
    ]);
  }

  Widget _tools() {
    final t = s.theme;
    Widget sec(String l) => Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 4), child: Text(l, style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.muted)));
    Widget it(String l, IconData i, VoidCallback f, {bool always = false}) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(i, size: 18),
          title: Text(l),
          enabled: s.root != null || always,
          onTap: f,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SideHeader(s, 'HERRAMIENTAS'),
      Expanded(
        child: ListView(children: [
          if (s.taskRunning)
            ListTile(
              dense: true,
              tileColor: t.accent.withAlpha(35),
              leading: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('${s.taskName} en ejecución'),
              trailing: iconBtn(Icons.stop, 'Detener', s.stopTask, color: Colors.redAccent),
            ),
          sec('EJECUCIÓN'),
          it('Configuración de ejecución…', Icons.tune, () => showRunConfig(context, s)),
          it('Abrir DevTools', Icons.speed, s.openDevTools, always: true),
          sec('CÓDIGO'),
          it('Formatear archivo actual', Icons.format_align_left, s.formatCurrent),
          it('Formatear proyecto', Icons.auto_fix_high, s.format),
          it('Dart fix --apply', Icons.healing, s.dartFix),
          it('Organizar imports', Icons.sort, s.organizeImports),
          it('Corregir todo (fix all)', Icons.done_all, s.fixAllIssues),
          it('Analyze', Icons.search, s.analyze),
          it('Test (todos)', Icons.science_outlined, s.test),
          it('Test: archivo actual', Icons.science, s.testCurrent),
          sec('GENERACIÓN DE CÓDIGO'),
          it('build_runner: build', Icons.construction, s.buildRunner),
          it('build_runner: watch', Icons.visibility_outlined, s.buildRunnerWatch),
          it('Localizaciones (gen-l10n)', Icons.translate, s.genL10n),
          it('Editor de localización (ARB)…', Icons.language, () => showArbEditor(context, s)),
          it('Assets y fuentes…', Icons.image_outlined, () => showAssetsManager(context, s)),
          sec('PAQUETES'),
          it('pub get', Icons.download, s.pubGet),
          it('pub upgrade', Icons.upgrade, s.pubUpgrade),
          it('pub deps (árbol)', Icons.account_tree_outlined, s.pubDeps),
          sec('BUILD'),
          it('APK', Icons.android, s.buildApk),
          it('App Bundle (.aab)', Icons.inventory_outlined, s.buildAppBundle),
          it('Web', Icons.language, s.buildWeb),
          it('Desktop', Icons.desktop_windows_outlined, s.buildDesktop),
          sec('TAREAS DEL PROYECTO'),
          for (final tk in s.projectTasks) it(tk['name'] ?? '', Icons.play_circle_outline, () => s.runTask(tk)),
          it('Gestionar tareas…', Icons.edit_note, () => showTasksManager(context, s)),
          sec('FLUTTER SDK'),
          it('Doctor', Icons.medical_services_outlined, s.doctor, always: true),
          it('Logs del dispositivo', Icons.receipt_long_outlined, s.flutterLogs),
          it('Ir a test / implementación', Icons.swap_horiz, s.toggleTestFile),
          it('Clean', Icons.cleaning_services_outlined, s.clean),
          it('Channel', Icons.alt_route, s.channel, always: true),
          it('Upgrade', Icons.system_update_alt, s.upgradeFlutter, always: true),
          const SizedBox(height: 16),
        ]),
      ),
    ]);
  }

  Widget _status(IdeTheme t) {
    const st = TextStyle(fontSize: 12, color: Colors.white);
    return Container(
      height: 24,
      color: s.debugActive ? const Color(0xFFCC6633) : t.status,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        if (s.gitRepo) ...[
          InkWell(
            onTap: () => setState(() {
              side = 2;
              _visited.add(2);
            }),
            child: Row(children: [const Icon(Icons.call_split, size: 13, color: Colors.white), const SizedBox(width: 4), Text(s.gitBranch, style: st)]),
          ),
          const SizedBox(width: 14),
        ],
        ValueListenableBuilder<int>(
          valueListenable: s.diagRev,
          builder: (_, __, ___) {
            final all = s.diags.values.expand((e) => e);
            final e = all.where((d) => d.severity == 1).length, w = all.where((d) => d.severity == 2).length;
            return Text('⊗ $e   ⚠ $w', style: st);
          },
        ),
        const Spacer(),
        if (s.taskRunning) Text('⟳ ${s.taskName}   ', style: st),
        if (s.debugActive) Text('🐞 ${s.debugStatus}   ', style: st) else if (s.isRunning) Text('● Running${s.runConfig.mode != 'debug' ? ' (${s.runConfig.mode})' : ''}   ', style: st),
        if (s.autoSave) const Text('Auto-guardado   ', style: st),
        if (s.updateAvailable != null)
          InkWell(
            onTap: () => showUpdateDialog(context, s),
            child: Text('⬆ v${s.updateAvailable!.version} disponible   ', style: st.copyWith(fontWeight: FontWeight.w700)),
          ),
        Text(s.lspStatus, style: st),
        const SizedBox(width: 14),
        Text(s.theme.name, style: st),
      ]),
    );
  }
}
