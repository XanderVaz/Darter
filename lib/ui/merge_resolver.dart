import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/merge_conflicts.dart';
import '../state/ide_state.dart';

Future<void> showMergeResolver(BuildContext c, IdeState s, String path) => showDialog<void>(context: c, barrierDismissible: false, builder: (_) => _Resolver(s, path));

class _Resolver extends StatefulWidget {
  const _Resolver(this.s, this.path);
  final IdeState s;
  final String path;
  @override
  State<_Resolver> createState() => _ResolverState();
}

class _ResolverState extends State<_Resolver> {
  late MergeDoc md;
  String msg = '';
  IdeState get s => widget.s;

  static const _mono = TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']);

  @override
  void initState() {
    super.initState();
    md = parseMerge(s.workingText(widget.path));
  }

  Future<void> _save({bool resolve = false}) async {
    final out = md.build();
    await File(widget.path).writeAsString(out);
    s.reloadDoc(widget.path, out);
    if (resolve) {
      await s.gitMarkResolved(widget.path);
      if (mounted) Navigator.pop(context);
    } else if (mounted) {
      setState(() => msg = 'Guardado (los conflictos sin resolver conservan sus marcas)');
    }
  }

  Future<void> _edit(ConflictSeg c) async {
    final ctl = TextEditingController(text: [...c.ours, ...c.theirs].join('\n'));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.theme.panel,
        surfaceTintColor: Colors.transparent,
        title: const Text('Editar resolución', style: TextStyle(fontSize: 16)),
        content: SizedBox(width: 680, child: TextField(controller: ctl, minLines: 8, maxLines: 18, style: _mono)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Aplicar')),
        ],
      ),
    );
    if (r != null) {
      setState(() {
        c.custom = r;
        c.choice = ConflictChoice.custom;
      });
    }
  }

  Widget _pane(String title, List<String> lines, Color color, String btn, VoidCallback onTap) {
    final t = s.theme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(120))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 2),
            child: Row(children: [
              Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color))),
              TextButton(onPressed: onTap, child: Text(btn)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(lines.isEmpty ? '(vacío)' : lines.join('\n'), style: _mono.copyWith(color: lines.isEmpty ? t.muted : t.text)),
          ),
        ]),
      ),
    );
  }

  Widget _ctx(List<String> lines) => lines.isEmpty
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: Text(lines.join('\n'), style: _mono.copyWith(color: s.theme.muted)));

  Widget _card(int n, int total, int segIndex, ConflictSeg c) {
    final t = s.theme;
    final prev = segIndex > 0 && md.segs[segIndex - 1] is TextSeg ? (md.segs[segIndex - 1] as TextSeg).lines : <String>[];
    final next = segIndex + 1 < md.segs.length && md.segs[segIndex + 1] is TextSeg ? (md.segs[segIndex + 1] as TextSeg).lines : <String>[];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.resolved ? Colors.lightGreenAccent.withAlpha(130) : Colors.amber.withAlpha(150))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(children: [
            Icon(c.resolved ? Icons.check_circle : Icons.warning_amber, size: 18, color: c.resolved ? Colors.lightGreenAccent : Colors.amber),
            const SizedBox(width: 8),
            Text('Conflicto $n de $total', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('línea ${c.startLine}', style: TextStyle(fontSize: 12, color: t.muted)),
            const Spacer(),
            if (c.resolved) TextButton.icon(onPressed: () => setState(() => c.choice = ConflictChoice.none), icon: const Icon(Icons.undo, size: 16), label: const Text('Deshacer')),
          ]),
        ),
        _ctx(prev.length > 2 ? prev.sublist(prev.length - 2) : prev),
        if (c.resolved)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.lightGreenAccent.withAlpha(20), borderRadius: BorderRadius.circular(8)),
            child: SelectableText(c.result.isEmpty ? '(se eliminan estas líneas)' : c.result.join('\n'), style: _mono),
          )
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pane('ACTUAL · ${c.oursLabel.isEmpty ? 'HEAD' : c.oursLabel}', c.ours, Colors.tealAccent, 'Aceptar actual', () => setState(() => c.choice = ConflictChoice.ours)),
            _pane('ENTRANTE · ${c.theirsLabel.isEmpty ? 'otra rama' : c.theirsLabel}', c.theirs, Colors.lightBlueAccent, 'Aceptar entrante', () => setState(() => c.choice = ConflictChoice.theirs)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => setState(() => c.choice = ConflictChoice.both), child: const Text('Ambos (actual → entrante)')),
              OutlinedButton(onPressed: () => setState(() => c.choice = ConflictChoice.bothReversed), child: const Text('Ambos (entrante → actual)')),
              OutlinedButton.icon(onPressed: () => _edit(c), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Editar…')),
            ]),
          ),
        ],
        _ctx(next.length > 2 ? next.sublist(0, 2) : next),
        const SizedBox(height: 6),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    final cs = md.conflicts;
    final done = cs.where((c) => c.resolved).length;
    final items = <Widget>[];
    var n = 0;
    for (var i = 0; i < md.segs.length; i++) {
      final seg = md.segs[i];
      if (seg is ConflictSeg) items.add(_card(++n, cs.length, i, seg));
    }
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.border)),
      child: SizedBox(
        width: size.width < 1148 ? size.width - 48 : 1100,
        height: size.height < 748 ? size.height - 48 : 700,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.merge_type, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(child: Text('Resolver conflictos · ${p.basename(widget.path)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              TextButton.icon(onPressed: () => s.openFile(widget.path), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Abrir en el editor')),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: cs.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_outline, size: 54, color: t.muted),
                      const SizedBox(height: 10),
                      Text('No hay marcas de conflicto en este archivo.', style: TextStyle(color: t.muted)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () async {
                        await s.gitMarkResolved(widget.path);
                        if (mounted) Navigator.pop(context);
                      }, child: const Text('Marcar como resuelto (git add)')),
                    ]),
                  )
                : ListView(padding: const EdgeInsets.only(top: 6, bottom: 10), children: items),
          ),
          Divider(height: 1, color: t.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(children: [
              Text('$done de ${cs.length} resueltos', style: TextStyle(color: done == cs.length && cs.isNotEmpty ? Colors.lightGreenAccent : t.muted)),
              const SizedBox(width: 12),
              Expanded(child: Text(msg, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted))),
              if (cs.isNotEmpty) ...[
                OutlinedButton(onPressed: () => setState(() { for (final c in cs) { c.choice = ConflictChoice.ours; } }), child: const Text('Todo actual')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => setState(() { for (final c in cs) { c.choice = ConflictChoice.theirs; } }), child: const Text('Todo entrante')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _save, child: const Text('Guardar')),
                const SizedBox(width: 8),
                FilledButton(onPressed: md.allResolved ? () => _save(resolve: true) : null, child: const Text('Guardar y marcar resuelto')),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
