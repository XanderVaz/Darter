import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';
import 'common.dart';

class DebugPanel extends StatefulWidget {
  const DebugPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  final _expr = TextEditingController();
  final _watch = TextEditingController();
  final _collapsed = <String>{};
  String _out = '';
  IdeState get s => widget.s;

  Widget _hint(String m) => Padding(padding: const EdgeInsets.fromLTRB(14, 6, 10, 8), child: Text(m, style: TextStyle(fontSize: 12, color: s.theme.muted)));

  Widget _section(String title, List<Widget> children, {Widget? trailing}) {
    final t = s.theme;
    final closed = _collapsed.contains(title);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() {
          closed ? _collapsed.remove(title) : _collapsed.add(title);
        }),
        child: Container(
          color: t.tab,
          padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
          child: Row(children: [
            Icon(closed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600))),
            if (trailing != null) trailing,
          ]),
        ),
      ),
      if (!closed) ...children,
    ]);
  }

  Widget _controls() {
    final paused = s.debugPaused;
    if (!s.debugActive) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: s.root == null ? null : s.startDebug, icon: const Icon(Icons.bug_report, size: 18), label: const Text('Iniciar depuración (F5)')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(children: [
        iconBtn(Icons.play_arrow, 'Continuar (F5)', paused ? s.dbgContinue : null, color: Colors.greenAccent, size: 20),
        iconBtn(Icons.pause, 'Pausar', paused ? null : s.dbgPause, size: 20),
        iconBtn(Icons.redo, 'Step over (F10)', paused ? s.dbgNext : null, size: 20),
        iconBtn(Icons.south, 'Step into (F11)', paused ? s.dbgStepIn : null, size: 20),
        iconBtn(Icons.north, 'Step out (Shift+F11)', paused ? s.dbgStepOut : null, size: 20),
        iconBtn(Icons.bolt, 'Hot reload', s.hotReload, color: Colors.amber, size: 20),
        iconBtn(Icons.restart_alt, 'Hot restart', s.hotRestart, size: 20),
        iconBtn(Icons.stop, 'Detener (Shift+F5)', s.stopDebug, color: Colors.redAccent, size: 20),
      ]),
    );
  }

  Widget _var(DbgVar v, int depth) {
    final t = s.theme;
    final kids = v.expanded ? s.varCache[v.ref] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: v.ref > 0
            ? () {
                setState(() => v.expanded = !v.expanded);
                if (v.expanded && !s.varCache.containsKey(v.ref)) s.loadVars(v.ref);
              }
            : null,
        child: Padding(
          padding: EdgeInsets.only(left: 10.0 + depth * 14, right: 8, top: 3, bottom: 3),
          child: Row(children: [
            Icon(v.ref > 0 ? (v.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right) : null, size: 16, color: t.muted),
            const SizedBox(width: 2),
            Flexible(
              child: Text.rich(
                TextSpan(children: [TextSpan(text: '${v.name}: ', style: TextStyle(color: t.accent)), TextSpan(text: v.value)]),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
              ),
            ),
          ]),
        ),
      ),
      if (kids != null) for (final k in kids) _var(k, depth + 1),
    ]);
  }

  List<Widget> _vars() {
    final t = s.theme;
    if (!s.debugActive) return [_hint('Sin sesión de depuración')];
    if (!s.debugPaused) return [_hint('La app se está ejecutando…')];
    if (s.scopes.isEmpty) return [_hint('Sin variables')];
    final out = <Widget>[];
    for (final sc in s.scopes) {
      out.add(Padding(padding: const EdgeInsets.fromLTRB(12, 6, 8, 2), child: Text(sc.name, style: TextStyle(fontSize: 11.5, color: t.muted, fontWeight: FontWeight.w600))));
      final list = s.varCache[sc.ref];
      if (list == null) {
        out.add(Padding(padding: const EdgeInsets.only(left: 8), child: TextButton(onPressed: () => s.loadVars(sc.ref), child: const Text('Cargar'))));
      } else if (list.isEmpty) {
        out.add(_hint('(vacío)'));
      } else {
        out.addAll(list.map((v) => _var(v, 0)));
      }
    }
    return out;
  }

  List<Widget> _watchRows() {
    final t = s.theme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: TextField(
          controller: _watch,
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(hintText: 'Añadir expresión a vigilar', prefixIcon: Icon(Icons.visibility_outlined, size: 16)),
          onSubmitted: (v) {
            s.addWatch(v.trim());
            _watch.clear();
          },
        ),
      ),
      for (final w in s.watches)
        Padding(
          padding: const EdgeInsets.only(left: 14, right: 4, top: 2, bottom: 2),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [TextSpan(text: '$w: ', style: TextStyle(color: t.accent)), TextSpan(text: s.watchValues[w] ?? '…')]),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
              ),
            ),
            iconBtn(Icons.close, 'Quitar', () => s.removeWatch(w), size: 14),
          ]),
        ),
    ];
  }

  List<Widget> _stack() {
    final t = s.theme;
    if (!s.debugPaused || s.frames.isEmpty) return [_hint(s.debugActive ? 'La app se está ejecutando…' : 'Sin sesión de depuración')];
    return [
      for (var i = 0; i < s.frames.length; i++)
        InkWell(
          onTap: () => s.selectFrame(i),
          child: Container(
            color: i == s.selFrame ? t.accent.withAlpha(50) : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              Icon(i == s.selFrame ? Icons.arrow_right : null, size: 16),
              Expanded(child: Text(s.frames[i].name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: s.frames[i].path == null ? t.muted : t.text))),
              Text(s.frames[i].path == null ? '' : '${p.basename(s.frames[i].path!)}:${s.frames[i].line}', style: TextStyle(fontSize: 11, color: t.muted)),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _bps() {
    final list = s.breakpointList;
    if (list.isEmpty) return [_hint('Haz clic en el margen izquierdo del editor (o pulsa F9) para añadir uno')];
    return [
      for (final b in list)
        InkWell(
          onTap: () => s.openFile(b.path, line: b.line, col: 1),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 4, top: 2, bottom: 2),
            child: Row(children: [
              const Icon(Icons.circle, size: 10, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(child: Text('${p.basename(b.path)}:${b.line}', style: const TextStyle(fontSize: 12.5))),
              iconBtn(Icons.close, 'Quitar', () => s.toggleBreakpoint(b.path, b.line), size: 14),
            ]),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Column(children: [
      SideHeader(s, 'DEPURAR${s.debugActive ? ' · ${s.debugStatus}' : ''}'),
      _controls(),
      Expanded(
        child: ListView(children: [
          _section('VARIABLES', _vars()),
          _section('WATCH', _watchRows()),
          _section('PILA DE LLAMADAS', _stack()),
          _section('BREAKPOINTS (${s.breakpointList.length})', _bps(), trailing: iconBtn(Icons.delete_sweep_outlined, 'Quitar todos', s.breakpoints.isEmpty ? null : s.clearBreakpoints)),
        ]),
      ),
      Divider(height: 1, color: t.border),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
        child: Row(children: [
          const Text('Pausar en excepciones', style: TextStyle(fontSize: 12)),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: s.exceptionMode,
              dropdownColor: t.side,
              style: TextStyle(fontSize: 12, color: t.text),
              items: const [
                DropdownMenuItem(value: 'None', child: Text('Ninguna')),
                DropdownMenuItem(value: 'Unhandled', child: Text('No controladas')),
                DropdownMenuItem(value: 'All', child: Text('Todas')),
              ],
              onChanged: (v) => s.setExceptionMode(v ?? 'Unhandled'),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _expr,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
            decoration: const InputDecoration(hintText: 'Evaluar expresión (Enter)', prefixIcon: Icon(Icons.terminal, size: 16)),
            onSubmitted: (v) async {
              if (v.trim().isEmpty) return;
              final r = await s.evaluate(v.trim());
              s.info('> $v\n$r');
              if (mounted) setState(() => _out = '$v  →  $r');
            },
          ),
          if (_out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_out, style: TextStyle(fontSize: 12, color: t.muted, fontFamily: 'Consolas', fontFamilyFallback: const ['monospace']))),
        ]),
      ),
    ]);
  }
}
