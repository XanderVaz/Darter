import 'package:flutter/material.dart';
import '../state/ide_state.dart';
import 'common.dart';

class OutlinePanel extends StatefulWidget {
  const OutlinePanel(this.s, {super.key});
  final IdeState s;
  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  String _key = '';
  Future<List<Map<String, dynamic>>> _future = Future.value([]);
  final _f = TextEditingController();
  IdeState get s => widget.s;

  IconData _icon(int k) => switch (k) {
        5 => Icons.category_outlined,
        6 || 12 => Icons.functions,
        9 => Icons.build_circle_outlined,
        7 || 8 || 13 || 14 => Icons.label_outline,
        10 || 22 => Icons.list_alt,
        11 => Icons.layers_outlined,
        _ => Icons.circle_outlined,
      };

  Color _color(int k) => switch (k) {
        5 => Colors.amber,
        6 || 12 || 9 => Colors.lightBlueAccent,
        10 || 22 => Colors.orangeAccent,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final d = s.current;
    final key = d == null ? '' : '${d.path}|${s.saveRev}|${s.lspStatus}';
    if (key != _key) {
      _key = key;
      _future = (d != null && d.path.endsWith('.dart')) ? s.lspSymbols(d.path) : Future.value(<Map<String, dynamic>>[]);
    }
    return Column(children: [
      SideHeader(s, 'ESQUEMA${d == null ? '' : ' · ${d.name}'}', [
        iconBtn(Icons.refresh, 'Actualizar', () => setState(() => _key = '')),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: TextField(controller: _f, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Filtrar símbolos', prefixIcon: Icon(Icons.filter_list, size: 18))),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            final q = _f.text.toLowerCase();
            final list = (snap.data ?? []).where((e) => q.isEmpty || '${e['name']}'.toLowerCase().contains(q)).toList();
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(d == null ? 'Abre un archivo .dart' : 'Sin símbolos (¿el servidor Dart sigue iniciando?)', textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                ),
              );
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final e = list[i];
                final kind = e['kind'] as int;
                return InkWell(
                  onTap: () => s.openFile(d!.path, line: (e['line'] as int) + 1, col: (e['col'] as int) + 1),
                  child: Padding(
                    padding: EdgeInsets.only(left: 12.0 + (e['depth'] as int) * 14, right: 8, top: 4, bottom: 4),
                    child: Row(children: [
                      Icon(_icon(kind), size: 15, color: _color(kind)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${e['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      Text('${(e['line'] as int) + 1}', style: TextStyle(fontSize: 11, color: t.muted)),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
