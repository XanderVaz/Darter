import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';
import 'common.dart';

class SearchPanel extends StatefulWidget {
  const SearchPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _q = TextEditingController(), _r = TextEditingController();
  bool cs = false, rx = false, ww = false, busy = false;
  List<SearchHit> hits = [];
  String msg = '';
  IdeState get s => widget.s;

  Future<void> _go() async {
    if (_q.text.isEmpty || s.root == null) return;
    setState(() { busy = true; msg = ''; });
    try {
      final r = await s.search(_q.text, caseSensitive: cs, regex: rx, whole: ww);
      if (!mounted) return;
      setState(() { hits = r; msg = '${r.length} resultados en ${r.map((e) => e.path).toSet().length} archivos'; });
    } catch (_) {
      if (mounted) setState(() => msg = 'Expresión inválida');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _replace() async {
    if (_q.text.isEmpty || hits.isEmpty) return;
    final files = hits.map((e) => e.path).toSet().length;
    if (!await confirm(context, s, 'Reemplazar todo', 'Se modificarán $files archivos en disco. ¿Continuar?', ok: 'Reemplazar')) return;
    final n = await s.replaceAll(_q.text, _r.text, caseSensitive: cs, regex: rx, whole: ww);
    await _go();
    if (mounted) setState(() => msg = 'Reemplazado en $n archivos');
  }

  Widget _tog(String l, String tip, bool v, void Function() f) {
    final t = s.theme;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () => setState(f),
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: v ? t.accent.withAlpha(70) : null, borderRadius: BorderRadius.circular(4)),
          child: Text(l, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: v ? t.text : t.muted)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (s.root == null) return const Center(child: Text('Abre un proyecto'));
    final rows = <Widget>[];
    String? last;
    for (final h in hits) {
      if (h.path != last) {
        last = h.path;
        rows.add(Container(
          width: double.infinity,
          color: t.tab,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(p.relative(h.path, from: s.root!), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ));
      }
      rows.add(InkWell(
        onTap: () => s.openFile(h.path, line: h.line, col: 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(children: [
            SizedBox(width: 36, child: Text('${h.line}', style: TextStyle(fontSize: 11.5, color: t.muted))),
            Expanded(child: Text(h.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          ]),
        ),
      ));
    }
    return Column(children: [
      SideHeader(s, 'BUSCAR'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(children: [
          TextField(
            controller: _q,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              hintText: 'Buscar en el proyecto',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                _tog('Aa', 'Mayúsculas/minúsculas', cs, () => cs = !cs),
                _tog('ab', 'Palabra completa', ww, () => ww = !ww),
                _tog('.*', 'Expresión regular', rx, () => rx = !rx),
                const SizedBox(width: 4),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _r, decoration: const InputDecoration(hintText: 'Reemplazar con'))),
            const SizedBox(width: 6),
            iconBtn(Icons.find_replace, 'Reemplazar todo', hits.isEmpty ? null : _replace, size: 20),
          ]),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: Text(busy ? 'Buscando…' : msg, style: TextStyle(fontSize: 12, color: t.muted))),
        ]),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: ListView(children: rows)),
    ]);
  }
}
