import 'package:flutter/material.dart';
import '../state/ide_state.dart';
import 'common.dart';

class InspectorPanel extends StatefulWidget {
  const InspectorPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  IdeState get s => widget.s;
  final _open = <String>{};
  Map? _seen;

  void _autoOpen(Map n, int depth, String key) {
    if (depth >= 4) return;
    _open.add(key);
    final kids = (n['children'] as List?) ?? const [];
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] is Map) _autoOpen(kids[i] as Map, depth + 1, '$key/$i');
    }
  }

  void _flatten(Map n, int depth, String key, List<(Map, int, String)> out) {
    out.add((n, depth, key));
    if (!_open.contains(key)) return;
    final kids = (n['children'] as List?) ?? const [];
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] is Map) _flatten(kids[i] as Map, depth + 1, '$key/$i', out);
    }
  }

  void _goto(Map loc) {
    try {
      final f = '${loc['file']}';
      final path = f.startsWith('file:') ? Uri.parse(f).toFilePath() : f;
      s.openFile(path, line: (loc['line'] as num?)?.toInt(), col: (loc['column'] as num?)?.toInt());
    } catch (_) {}
  }

  Widget _chip(String label, IconData icon, bool on, VoidCallback f) => FilterChip(
        avatar: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        selected: on,
        onSelected: (_) => f(),
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final tree = s.inspectorTree;
    if (tree != null && !identical(tree, _seen)) {
      _seen = tree;
      _open.clear();
      _autoOpen(tree, 0, 'r');
    }
    final rows = <(Map, int, String)>[];
    if (tree != null) _flatten(tree, 0, 'r', rows);
    return Column(children: [
      SideHeader(s, 'INSPECTOR', [iconBtn(Icons.refresh, 'Actualizar el árbol de widgets', s.refreshInspector)]),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          _chip('Debug paint', Icons.border_style, s.flutterToggles['ext.flutter.debugPaint'] ?? false, () => s.toggleFlutterExt('ext.flutter.debugPaint')),
          _chip('Rendimiento', Icons.speed, s.flutterToggles['ext.flutter.showPerformanceOverlay'] ?? false, () => s.toggleFlutterExt('ext.flutter.showPerformanceOverlay')),
          _chip('Repaint rainbow', Icons.gradient, s.flutterToggles['ext.flutter.repaintRainbow'] ?? false, () => s.toggleFlutterExt('ext.flutter.repaintRainbow')),
          _chip('Seleccionar widget', Icons.touch_app, s.flutterToggles['ext.flutter.inspector.show'] ?? false, () => s.toggleFlutterExt('ext.flutter.inspector.show')),
          _chip('Animación lenta (5×)', Icons.slow_motion_video, s.slowAnimations, s.toggleSlowAnimations),
        ]),
      ),
      if (s.inspectorBusy) const LinearProgressIndicator(minHeight: 2),
      if (s.inspectorError.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 6), child: Text(s.inspectorError, style: const TextStyle(fontSize: 12, color: Colors.amber))),
      Expanded(
        child: tree == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Ejecuta tu app con Run o Depurar y pulsa ⟳ para ver su árbol de widgets. Pulsa un widget para ir a su código.', textAlign: TextAlign.center, style: TextStyle(color: t.muted, height: 1.4)),
                ),
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final (n, depth, key) = rows[i];
                  final kids = (n['children'] as List?) ?? const [];
                  final open = _open.contains(key);
                  final loc = n['creationLocation'] as Map?;
                  final mine = n['createdByLocalProject'] == true;
                  return InkWell(
                    onTap: loc == null ? null : () => _goto(loc),
                    child: Padding(
                      padding: EdgeInsets.only(left: 6.0 + depth * 14, right: 6, top: 2, bottom: 2),
                      child: Row(children: [
                        SizedBox(
                          width: 18,
                          child: kids.isEmpty
                              ? null
                              : InkWell(
                                  onTap: () => setState(() {
                                    open ? _open.remove(key) : _open.add(key);
                                  }),
                                  child: Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: t.muted),
                                ),
                        ),
                        Expanded(
                          child: Text('${n['description'] ?? n['type'] ?? '?'}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: mine ? FontWeight.w700 : FontWeight.w400, color: mine ? t.text : t.muted)),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
