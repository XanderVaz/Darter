import 'package:flutter/material.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'package:path/path.dart' as p;
import 'command_palette.dart';
import 'diff_view.dart';
import 'merge_resolver.dart';
import 'common.dart';

class GitPanel extends StatefulWidget {
  const GitPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final _msg = TextEditingController();
  IdeState get s => widget.s;

  @override
  void initState() {
    super.initState();
    s.refreshBranches();
    s.refreshGitLog();
  }

  Color _col(String l) => switch (l) {
        'M' => Colors.amber,
        'A' || 'U' => Colors.lightGreenAccent,
        'D' => Colors.redAccent,
        'R' => Colors.lightBlueAccent,
        _ => Colors.grey,
      };

  Widget _row(GitChange c, bool staged) => InkWell(
        onTap: () => s.openFile('${s.root}${s.root!.contains('\\') ? '\\' : '/'}${c.path}'),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(children: [
            Expanded(child: Text(c.path, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
            iconBtn(Icons.history, 'Historial del archivo', () => showFileHistory(context, s, p.join(s.root!, c.path))),
            iconBtn(Icons.difference_outlined, 'Ver cambios (diff lado a lado)', () => _diff(c, staged)),
            if (staged) iconBtn(Icons.remove, 'Quitar de preparados', () => s.gitUnstage(c.path))
            else ...[
              iconBtn(Icons.undo, 'Descartar cambios', () async {
                if (await confirm(context, s, 'Descartar cambios', '¿Descartar los cambios de ${c.path}?', ok: 'Descartar')) s.gitDiscard(c);
              }),
              iconBtn(Icons.add, 'Preparar (stage)', () => s.gitStage(c.path)),
            ],
            SizedBox(width: 18, child: Text(staged ? c.x : c.label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _col(staged ? c.x : c.label)))),
          ]),
        ),
      );

  Widget _mergeBanner(IdeTheme t, bool canFinish) => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.amber.withAlpha(35), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withAlpha(140))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.merge_type, size: 18, color: Colors.amber), SizedBox(width: 8), Text('Fusión en curso', style: TextStyle(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 4),
          Text(canFinish ? 'Todos los conflictos están resueltos.' : 'Resuelve los conflictos y márcalos como resueltos.', style: TextStyle(fontSize: 12, color: t.muted)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: canFinish ? s.gitMergeContinue : null, child: const Text('Concluir fusión')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                if (await confirm(context, s, 'Abortar fusión', 'Se descartará la fusión y sus cambios. ¿Continuar?', ok: 'Abortar')) s.gitMergeAbort();
              },
              child: const Text('Abortar'),
            ),
          ]),
        ]),
      );

  Widget _conflictRow(GitChange c) {
    final abs = p.join(s.root!, c.path);
    return InkWell(
      onTap: () => showMergeResolver(context, s, abs),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 3, bottom: 3),
        child: Row(children: [
          const Icon(Icons.warning_amber, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(c.path, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          PopupMenuButton<String>(
            tooltip: 'Acciones',
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (v) {
              switch (v) {
                case 'res':
                  showMergeResolver(context, s, abs);
                case 'ours':
                  s.gitTakeSide(c.path, true);
                case 'theirs':
                  s.gitTakeSide(c.path, false);
                case 'done':
                  s.gitMarkResolved(c.path);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'res', child: Text('Resolver…')),
              PopupMenuItem(value: 'ours', child: Text('Quedarme con el actual')),
              PopupMenuItem(value: 'theirs', child: Text('Quedarme con el entrante')),
              PopupMenuItem(value: 'done', child: Text('Marcar como resuelto')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _branchBar(IdeTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: PopupMenuButton<String>(
          tooltip: 'Ramas',
          onOpened: s.refreshBranches,
          onSelected: _branchAction,
          itemBuilder: (_) => [
            for (final b in s.gitBranches)
              PopupMenuItem(value: 'co:$b', child: Row(children: [Icon(b == s.gitBranch ? Icons.check : null, size: 16), const SizedBox(width: 8), Text(b)])),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'new', child: Text('Nueva rama…')),
            const PopupMenuItem(value: 'merge', child: Text('Fusionar una rama en la actual…')),
            const PopupMenuItem(value: 'del', child: Text('Eliminar rama…')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'stash', child: Text('Stash (guardar cambios)')),
            const PopupMenuItem(value: 'pop', child: Text('Stash pop (recuperar)')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.border)),
            child: Row(children: [
              const Icon(Icons.call_split, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(s.gitBranch.isEmpty ? '(sin rama)' : s.gitBranch, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
        ),
      );

  Future<void> _pickBranch(String placeholder, Future<void> Function(String) action) async {
    final others = s.gitBranches.where((b) => b != s.gitBranch).toList();
    if (others.isEmpty) {
      s.info('No hay otras ramas');
      return;
    }
    await showCommandPalette(context, s, pure: true, placeholder: placeholder, commands: [for (final b in others) PaletteCmd(b, Icons.call_split, () => action(b))]);
  }

  Future<void> _branchAction(String v) async {
    if (v.startsWith('co:')) {
      await s.gitCheckout(v.substring(3));
      return;
    }
    switch (v) {
      case 'new':
        {
          final n = await promptText(context, s, 'Nombre de la nueva rama', hint: 'feature/mi-cambio');
          if (n != null) await s.gitNewBranch(n);
        }
      case 'merge':
        await _pickBranch('Fusionar en ${s.gitBranch}', s.gitMerge);
      case 'del':
        await _pickBranch('Eliminar rama', s.gitDeleteBranch);
      case 'stash':
        await s.gitStash();
      case 'pop':
        await s.gitStashPop();
    }
  }

  Future<void> _commit(String hash, String subject) async {
    final text = await s.gitShow(hash);
    if (!mounted) return;
    final t = s.theme;
    Color col(String l) => l.startsWith('+') && !l.startsWith('+++') ? Colors.lightGreenAccent : l.startsWith('-') && !l.startsWith('---') ? Colors.redAccent : l.startsWith('@@') ? t.accent : l.startsWith('commit ') ? Colors.amber : t.text;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: t.panel,
        surfaceTintColor: Colors.transparent,
        child: SizedBox(
          width: 900,
          height: 600,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Expanded(child: Text('$hash · $subject', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText.rich(TextSpan(children: [
                  for (final l in text.split('\n')) TextSpan(text: '$l\n', style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12.5, color: col(l))),
                ])),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _diff(GitChange c, bool staged) async {
    final sides = await s.gitSides(c, staged);
    if (!mounted) return;
    showDiffDialog(context, s, title: '${c.path}  ·  ${staged ? 'preparado ↔ HEAD' : 'actual ↔ índice'}', path: c.path, original: sides.a, modified: sides.b);
  }

  // ignore: unused_element
  Future<void> _diffText(GitChange c, bool staged) async {
    final text = await s.gitDiff(c, staged: staged);
    if (!mounted) return;
    final t = s.theme;
    Color col(String l) => l.startsWith('+') && !l.startsWith('+++') ? Colors.lightGreenAccent : l.startsWith('-') && !l.startsWith('---') ? Colors.redAccent : l.startsWith('@@') ? t.accent : t.text;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: t.panel,
        surfaceTintColor: Colors.transparent,
        child: SizedBox(
          width: 900,
          height: 600,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Expanded(child: Text('${c.path}${staged ? '  (preparado)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText.rich(TextSpan(children: [
                  for (final l in text.split('\n')) TextSpan(text: '$l\n', style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12.5, color: col(l))),
                ])),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (s.root == null) return const Center(child: Text('Abre un proyecto'));
    if (!s.gitRepo) {
      return Column(children: [
        SideHeader(s, 'CONTROL DE VERSIONES'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text('Esta carpeta no es un repositorio Git (o git no está instalado).', style: TextStyle(color: t.muted)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: s.gitInit, icon: const Icon(Icons.account_tree_outlined), label: const Text('Inicializar repositorio')),
          ]),
        ),
      ]);
    }
    final staged = s.gitChanges.where((c) => c.staged).toList();
    final changes = s.gitChanges.where((c) => c.unstaged).toList();
    final conflicts = s.gitChanges.where((c) => c.conflicted).toList();
    Widget title(String l, int n, [Widget? trailing]) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Row(children: [Expanded(child: Text('$l ($n)', style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.muted))), if (trailing != null) trailing]),
        );
    return Column(children: [
      SideHeader(s, 'GIT · ${s.gitBranch}', [
        iconBtn(Icons.refresh, 'Refrescar', s.refreshGit),
        iconBtn(Icons.download, 'Pull', s.gitPull),
        iconBtn(Icons.upload, 'Push', s.gitPush),
      ]),
      _branchBar(t),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(children: [
          TextField(controller: _msg, minLines: 2, maxLines: 4, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Mensaje del commit')),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: Text('Commit (${staged.length})'),
              onPressed: staged.isEmpty || _msg.text.trim().isEmpty ? null : () async { await s.gitCommit(_msg.text.trim()); _msg.clear(); setState(() {}); },
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          if (s.gitMerging) _mergeBanner(t, conflicts.isEmpty),
          if (conflicts.isNotEmpty) ...[
            title('CONFLICTOS DE FUSIÓN', conflicts.length),
            for (final c in conflicts) _conflictRow(c),
          ],
          title('CAMBIOS PREPARADOS', staged.length),
          for (final c in staged) _row(c, true),
          title('CAMBIOS', changes.length, iconBtn(Icons.add, 'Preparar todo', changes.isEmpty ? null : s.gitStageAll)),
          for (final c in changes) _row(c, false),
          if (s.gitChanges.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Sin cambios ✓', style: TextStyle(color: t.muted))),
          title('HISTORIAL', s.gitLog.length, iconBtn(Icons.refresh, 'Actualizar historial', s.refreshGitLog)),
          for (final c in s.gitLog)
            InkWell(
              onTap: () => _commit(c.hash, c.subject),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: t.accent.withAlpha(40), borderRadius: BorderRadius.circular(4)),
                    child: Text(c.hash, style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', fontFamilyFallback: ['monospace'])),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.subject, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                  Text(c.date, style: TextStyle(fontSize: 10.5, color: t.muted)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}
