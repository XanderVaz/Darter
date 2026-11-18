import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/test_runner.dart';
import '../state/ide_state.dart';
import 'common.dart';

class TestPanel extends StatefulWidget {
  const TestPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<TestPanel> createState() => _TestPanelState();
}

class _TestPanelState extends State<TestPanel> {
  final _open = <int>{};
  IdeState get s => widget.s;
  TestRunner get r => s.testRunner;

  Widget _icon(TestCase tc) => switch (tc.status) {
        TestStatus.running => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        TestStatus.passed => const Icon(Icons.check_circle, size: 16, color: Colors.lightGreenAccent),
        TestStatus.failed => const Icon(Icons.cancel, size: 16, color: Colors.redAccent),
        TestStatus.skipped => const Icon(Icons.remove_circle_outline, size: 16, color: Colors.grey),
      };

  void _rerunFailed() {
    final names = r.tests.values.where((t) => t.status == TestStatus.failed).map((t) => RegExp.escape(t.name)).toList();
    if (names.isEmpty) return;
    s.runTests(namePattern: '^(${names.join('|')})\$');
  }

  Color _covColor(double v) => v >= 80 ? Colors.lightGreenAccent : v >= 50 ? Colors.amber : Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (s.root == null) return const Center(child: Text('Abre un proyecto'));
    return ListenableBuilder(
      listenable: r,
      builder: (_, __) {
        final byFile = <String, List<TestCase>>{};
        for (final tc in r.tests.values) {
          byFile.putIfAbsent(tc.path ?? '(desconocido)', () => []).add(tc);
        }
        final cur = s.current?.path;
        final canFile = cur != null && cur.endsWith('_test.dart') && !r.running;
        return Column(children: [
          SideHeader(s, 'PRUEBAS${r.status.isEmpty ? '' : ' · ${r.status}'}', [
            iconBtn(Icons.play_arrow, 'Ejecutar todas', r.running ? null : () => s.runTests(), color: Colors.greenAccent, size: 20),
            iconBtn(Icons.description_outlined, 'Ejecutar el archivo de test actual', canFile ? () => s.runTests(file: p.relative(cur, from: s.root!)) : null),
            iconBtn(Icons.replay, 'Repetir las fallidas', r.running || r.failed == 0 ? null : _rerunFailed),
            iconBtn(Icons.shield_outlined, 'Ejecutar con cobertura', r.running ? null : () => s.runTests(coverage: true)),
            if (r.running) iconBtn(Icons.stop, 'Detener', r.stop, color: Colors.redAccent),
          ]),
          if (r.total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(children: [
                Text('✔ ${r.passed}', style: const TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                Text('✖ ${r.failed}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                Text('⏭ ${r.skipped}', style: TextStyle(color: t.muted)),
                const Spacer(),
                Text('${r.finished}/${r.total}', style: TextStyle(color: t.muted, fontSize: 12)),
              ]),
            ),
          if (r.running) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(children: [
              if (r.tests.isEmpty && !r.running)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Ejecuta las pruebas con ▶. Se buscan en la carpeta test/ del proyecto.', style: TextStyle(color: t.muted)),
                ),
              for (final e in byFile.entries) ...[
                Container(
                  color: t.tab,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(children: [
                    const Icon(Icons.description_outlined, size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e.key == '(desconocido)' ? e.key : p.basename(e.key), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    Text('${e.value.where((x) => x.status == TestStatus.passed).length}/${e.value.length}', style: TextStyle(fontSize: 11, color: t.muted)),
                  ]),
                ),
                for (final tc in e.value) ...[
                  InkWell(
                    onTap: () {
                      if (tc.path != null) s.openFile(tc.path!, line: tc.line > 0 ? tc.line : null, col: 1);
                      if (tc.status == TestStatus.failed) setState(() => _open.contains(tc.id) ? _open.remove(tc.id) : _open.add(tc.id));
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 4, top: 3, bottom: 3),
                      child: Row(children: [
                        _icon(tc),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tc.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                        if (!r.running && tc.path != null) iconBtn(Icons.play_arrow, 'Ejecutar solo esta prueba', () => s.runTests(file: p.relative(tc.path!, from: s.root!), name: tc.name), size: 14),
                      ]),
                    ),
                  ),
                  if (tc.status == TestStatus.failed && _open.contains(tc.id))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(34, 2, 10, 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.redAccent.withAlpha(120))),
                      child: SelectableText(
                        '${tc.error}\n${tc.stack.split('\n').take(6).join('\n')}',
                        style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
                      ),
                    ),
                ],
              ],
              if (r.coverage.isNotEmpty) ...[
                Container(
                  color: t.tab,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(children: [
                    const Icon(Icons.shield_outlined, size: 14),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('COBERTURA', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600))),
                    Text('${r.coveragePct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w700, color: _covColor(r.coveragePct))),
                  ]),
                ),
                for (final c in r.coverage)
                  InkWell(
                    onTap: () => s.openFile(c.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p.relative(c.path, from: s.root!), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                          Text('${c.pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11.5, color: _covColor(c.pct))),
                        ]),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(value: c.pct / 100, minHeight: 3, color: _covColor(c.pct), backgroundColor: t.border),
                      ]),
                    ),
                  ),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}
