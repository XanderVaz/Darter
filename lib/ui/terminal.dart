import 'package:flutter/material.dart';
import '../state/ide_state.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _history = <String>[];
  int _h = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.s,
        builder: (_, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
          });
          return Column(children: [
            Container(
              color: const Color(0xFF252526),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                const Text('TERMINAL / SALIDA', style: TextStyle(fontSize: 11, letterSpacing: 1)),
                const Spacer(),
                IconButton(iconSize: 16, tooltip: 'Limpiar', icon: const Icon(Icons.delete_outline), onPressed: () { widget.s.log.clear(); widget.s.refresh(); }),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: widget.s.log.length,
                itemBuilder: (_, i) => SelectableText(widget.s.log[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              ),
            ),
            TextField(
              controller: _input,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(prefixText: r'$ ', isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.all(8), hintText: 'flutter pub add http, dart run, git status...'),
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                _history.add(v);
                _h = _history.length;
                _input.clear();
                widget.s.exec(v);
              },
            ),
          ]);
        },
      );
}
