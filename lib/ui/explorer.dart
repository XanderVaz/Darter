import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';
import 'common.dart';
import 'diff_view.dart';

class Explorer extends StatelessWidget {
  const Explorer(this.s, {super.key, required this.onNewProject, required this.onOpen});
  final IdeState s;
  final VoidCallback onNewProject, onOpen;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (s.root == null) return _empty(t);
    final rows = <Widget>[];
    void walk(String dir, int depth) {
      final items = s.listDir(dir);
      for (final e in items) {
        final name = p.basename(e.path);
        if (kHidden.contains(name)) continue;
        final isDir = e is Directory;
        final open = s.expanded.contains(e.path);
        final selected = s.current != null && norm(s.current!.path) == norm(e.path);
        rows.add(GestureDetector(
          onSecondaryTapDown: (d) => _menu(context, d.globalPosition, e.path, isDir),
          child: InkWell(
            onTap: () => isDir ? s.toggleDir(e.path) : s.openFile(e.path),
            child: Container(
              color: selected ? t.accent.withAlpha(50) : null,
              padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 4, bottom: 4),
              child: Row(children: [
                Icon(isDir ? (open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right) : null, size: 16, color: t.muted),
                Icon(isDir ? (open ? Icons.folder_open : Icons.folder) : fileIcon(name), size: 16, color: isDir ? Colors.amber : fileColor(name, t)),
                const SizedBox(width: 6),
                Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ),
        ));
        if (isDir && open) walk(e.path, depth + 1);
      }
    }

    walk(s.root!, 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SideHeader(s, p.basename(s.root!).toUpperCase(), [
        iconBtn(Icons.note_add_outlined, 'Nuevo archivo', () => _create(context, s.root!, false)),
        iconBtn(Icons.create_new_folder_outlined, 'Nueva carpeta', () => _create(context, s.root!, true)),
        iconBtn(Icons.refresh, 'Refrescar', s.refresh),
        iconBtn(Icons.unfold_less, 'Contraer todo', s.collapseAll),
        iconBtn(Icons.close, 'Cerrar carpeta', s.closeProject),
      ]),
      Expanded(child: ListView(children: rows)),
    ]);
  }

  Widget _empty(t) => ListView(padding: const EdgeInsets.all(16), children: [
        const SideHeader2('EXPLORADOR'),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: onNewProject, icon: const Icon(Icons.add), label: const Text('Nuevo proyecto')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.folder_open), label: const Text('Abrir carpeta')),
        if (s.recents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('RECIENTES', style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.muted)),
          for (final r in s.recents)
            ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history, size: 16), title: Text(p.basename(r)), subtitle: Text(r, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)), onTap: () => s.openProject(r)),
        ],
      ]);

  Future<void> _create(BuildContext c, String dir, bool isDir) async {
    final n = await promptText(c, s, isDir ? 'Nueva carpeta' : 'Nuevo archivo', hint: isDir ? 'nombre_carpeta' : 'archivo.dart');
    if (n == null) return;
    isDir ? s.createDir(dir, n) : s.createFile(dir, n);
  }

  Future<void> _menu(BuildContext c, Offset pos, String path, bool isDir) async {
    final v = await showMenu<String>(
      context: c,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'file', child: Text('Nuevo archivo…')),
        const PopupMenuItem(value: 'dir', child: Text('Nueva carpeta…')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'tpl:stateless', child: Text('Nuevo StatelessWidget…')),
        const PopupMenuItem(value: 'tpl:stateful', child: Text('Nuevo StatefulWidget…')),
        const PopupMenuItem(value: 'tpl:screen', child: Text('Nueva pantalla (Scaffold)…')),
        const PopupMenuItem(value: 'tpl:model', child: Text('Nuevo modelo de datos…')),
        const PopupMenuItem(value: 'tpl:notifier', child: Text('Nuevo ChangeNotifier…')),
        const PopupMenuItem(value: 'tpl:test', child: Text('Nuevo archivo de test…')),
        if (isDir) const PopupMenuItem(value: 'assets', child: Text('Registrar como assets (pubspec)')),
        if (!isDir) const PopupMenuDivider(),
        if (!isDir) const PopupMenuItem(value: 'history', child: Text('Historial del archivo (Git)')),
        if (!isDir) const PopupMenuItem(value: 'diffhead', child: Text('Comparar con HEAD')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'rename', child: Text('Renombrar…')),
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
        const PopupMenuItem(value: 'copy', child: Text('Copiar ruta')),
      ],
    );
    if (v == null || !c.mounted) return;
    final dir = isDir ? path : p.dirname(path);
    if (v.startsWith('tpl:')) {
      final n = await promptText(c, s, 'Nombre del archivo (snake_case)', hint: 'mi_widget');
      if (n != null) s.createFromTemplate(dir, v.substring(4), n);
      return;
    }
    switch (v) {
      case 'file':
      case 'dir':
        await _create(c, dir, v == 'dir');
      case 'rename':
        final n = await promptText(c, s, 'Renombrar', initial: p.basename(path));
        if (n != null && n != p.basename(path)) s.renameEntity(path, n);
      case 'delete':
        if (await confirm(c, s, 'Eliminar', '¿Eliminar "${p.basename(path)}"? No se puede deshacer.', ok: 'Eliminar')) s.deleteEntity(path);
      case 'copy':
        Clipboard.setData(ClipboardData(text: path));
      case 'assets':
        await s.addAssetFolder(path);
      case 'history':
        showFileHistory(c, s, path);
      case 'diffhead':
        {
          final x = await s.gitHeadVsWorking(path);
          if (c.mounted) showDiffDialog(c, s, title: '${p.basename(path)} · HEAD ↔ actual', path: path, original: x.a, modified: x.b);
        }
    }
  }
}

class SideHeader2 extends StatelessWidget {
  const SideHeader2(this.t, {super.key});
  final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600));
}
