import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../services/terminal_session.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'common.dart';

class BottomPanel extends StatefulWidget {
  const BottomPanel(this.s, {super.key, required this.onClose});
  final IdeState s;
  final VoidCallback onClose;
  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  int tab = 2; // 0 = salida, 1 = problemas, 2+ = terminales
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _filter = TextEditingController();
  final _focus = FocusNode();
  bool onlyErrors = false;
  int _hi = 0;
  IdeState get s => widget.s;

  Widget _tabBtn(String label, int i, IdeTheme t, {int badge = 0, VoidCallback? onClose}) => InkWell(
        onTap: () => setState(() => tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2, color: tab == i ? t.accent : Colors.transparent))),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 11, letterSpacing: 1, color: tab == i ? t.text : t.muted)),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(8)),
                child: Text('$badge', style: TextStyle(fontSize: 10, color: t.onAccent)),
              ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(onTap: onClose, child: Icon(Icons.close, size: 12, color: t.muted)),
            ],
          ]),
        ),
      );

  void _closeTerm(int i) {
    s.closeTerminal(i);
    setState(() => tab = s.terminals.isEmpty ? 0 : 2 + math.min(i, s.terminals.length - 1));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (_, __) {
          final t = s.theme;
          if (tab >= 2 + s.terminals.length) tab = s.terminals.isEmpty ? 0 : 1 + s.terminals.length;
          final ts = tab >= 2 ? s.terminals[tab - 2] : null;
          return Container(
            decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.border))),
            child: Column(children: [
              SizedBox(
                height: 34,
                child: Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _tabBtn('SALIDA', 0, t),
                        ValueListenableBuilder<int>(valueListenable: s.diagRev, builder: (_, __, ___) => _tabBtn('PROBLEMAS', 1, t, badge: s.diags.values.fold(0, (a, b) => a + b.length))),
                        for (var i = 0; i < s.terminals.length; i++) _tabBtn(s.terminals[i].name.toUpperCase(), 2 + i, t, onClose: () => _closeTerm(i)),
                      ]),
                    ),
                  ),
                  iconBtn(Icons.add, 'Nuevo terminal', () {
                    s.addTerminal();
                    setState(() => tab = 1 + s.terminals.length);
                  }),
                  iconBtn(Icons.delete_outline, 'Limpiar', () => ts != null ? ts.clear() : s.clearLog()),
                  iconBtn(Icons.close, 'Cerrar panel', widget.onClose),
                ]),
              ),
              Divider(height: 1, color: t.border),
              Expanded(child: tab == 0 ? _output(t) : tab == 1 ? _problems(t) : _term(ts!, t)),
            ]),
          );
        },
      );

  Color _lineColor(String l, IdeTheme t) {
    final x = l.toLowerCase();
    if (l.startsWith(r'$ ')) return t.accent;
    if (x.contains('error') || x.contains('failed')) return Colors.redAccent;
    if (x.contains('warning')) return Colors.amber;
    return t.text;
  }

  bool _isErr(String l) {
    final x = l.toLowerCase();
    return x.contains('error') || x.contains('exception') || x.contains('failed');
  }

  static final _pathRe = RegExp(r'((?:package:\w+/|[A-Za-z]:[\\/]|\.{0,2}[\\/])?[\w\-./\\]+\.dart):(\d+)(?::(\d+))?');

  TextSpan _line(String raw, IdeTheme t) {
    final base = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['Menlo', 'monospace'], fontSize: 12.5, color: _lineColor(stripAnsi(raw), t));
    final spans = <InlineSpan>[];
    for (final sg in ansiSegments(raw, base)) {
      var i = 0;
      for (final m in _pathRe.allMatches(sg.text)) {
        if (m.start > i) spans.add(TextSpan(text: sg.text.substring(i, m.start), style: sg.style));
        spans.add(TextSpan(
          text: m.group(0),
          style: sg.style.copyWith(color: t.accent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => s.openPath(m.group(1)!, int.parse(m.group(2)!), int.tryParse(m.group(3) ?? '') ?? 1),
        ));
        i = m.end;
      }
      if (i < sg.text.length) spans.add(TextSpan(text: sg.text.substring(i), style: sg.style));
    }
    return TextSpan(style: base, children: spans);
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Widget _output(IdeTheme t) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(hintText: 'Filtrar salida…', prefixIcon: Icon(Icons.filter_list, size: 16), contentPadding: EdgeInsets.zero),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Solo errores', style: TextStyle(fontSize: 12)), selected: onlyErrors, onSelected: (v) => setState(() => onlyErrors = v)),
          ]),
        ),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: s.logRev,
            builder: (_, __, ___) {
              final f = _filter.text.toLowerCase();
              final lines = s.log.where((l) => (f.isEmpty || l.toLowerCase().contains(f)) && (!onlyErrors || _isErr(l))).toList();
              _toBottom();
              return ListView.builder(
                key: const ValueKey('out'),
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: lines.length,
                itemBuilder: (_, i) => SelectableText.rich(_line(lines[i], t)),
              );
            },
          ),
        ),
      ]);

  Widget _term(TerminalSession ts, IdeTheme t) => ListenableBuilder(
        listenable: ts,
        builder: (_, __) {
          _toBottom();
          return Column(children: [
            Expanded(
              child: ListView.builder(
                key: ValueKey(ts),
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: ts.lines.length,
                itemBuilder: (_, i) => SelectableText.rich(_line(ts.lines[i], t)),
              ),
            ),
            Focus(
              onKeyEvent: (n, e) {
                final h = ts.history;
                if (e is KeyDownEvent && h.isNotEmpty) {
                  _hi = _hi.clamp(0, h.length);
                  if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _hi = math.max(0, _hi - 1);
                  } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _hi = math.min(h.length, _hi + 1);
                  } else {
                    return KeyEventResult.ignored;
                  }
                  _input.text = _hi < h.length ? h[_hi] : '';
                  _input.selection = TextSelection.collapsed(offset: _input.text.length);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _input,
                focusNode: _focus,
                style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Menlo', 'monospace'], fontSize: 13),
                decoration: InputDecoration(
                  prefixText: ts.running ? '⏵ ' : '${p.basename(ts.cwd)} \$ ',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(10),
                  hintText: ts.running ? 'Entrada para el proceso en ejecución…' : 'flutter pub add http · dart run · git status · cd carpeta',
                  suffixIcon: ts.running ? iconBtn(Icons.stop_circle_outlined, 'Interrumpir (Ctrl+C)', ts.interrupt, color: Colors.redAccent, size: 20) : null,
                ),
                onSubmitted: (v) {
                  _input.clear();
                  ts.run(v);
                  _hi = ts.history.length;
                  _focus.requestFocus();
                },
              ),
            ),
          ]);
        },
      );

  Widget _problems(IdeTheme t) => ValueListenableBuilder<int>(
        valueListenable: s.diagRev,
        builder: (_, __, ___) {
          final all = s.diags.values.expand((e) => e).toList()..sort((a, b) => a.severity != b.severity ? a.severity.compareTo(b.severity) : a.path.compareTo(b.path));
          if (all.isEmpty) return Center(child: Text('Sin problemas detectados ✓', style: TextStyle(color: t.muted)));
          return ListView.builder(
            itemCount: all.length,
            itemBuilder: (_, i) {
              final d = all[i];
              final icon = d.severity == 1 ? Icons.error_outline : d.severity == 2 ? Icons.warning_amber : Icons.info_outline;
              final col = d.severity == 1 ? Colors.redAccent : d.severity == 2 ? Colors.amber : Colors.lightBlueAccent;
              final rel = s.root == null ? d.path : p.relative(d.path, from: s.root!);
              return InkWell(
                onTap: () => s.openFile(d.path, line: d.line + 1, col: d.col + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    Icon(icon, size: 15, color: col),
                    const SizedBox(width: 8),
                    Expanded(child: Text(d.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                    const SizedBox(width: 10),
                    Text('$rel:${d.line + 1}', style: TextStyle(fontSize: 11.5, color: t.muted)),
                  ]),
                ),
              );
            },
          );
        },
      );
}
