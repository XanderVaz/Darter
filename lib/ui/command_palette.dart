import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';
import 'common.dart';

class PaletteCmd {
  const PaletteCmd(this.label, this.icon, this.run, {this.hint = ''});
  final String label, hint;
  final IconData icon;
  final VoidCallback run;
}

class _Item {
  _Item(this.title, this.sub, this.icon, this.hint, this.run, this.score);
  final String title, sub, hint;
  final IconData icon;
  final VoidCallback run;
  final int score;
}

int _score(String q, String t) {
  if (q.isEmpty) return 0;
  final ql = q.toLowerCase(), tl = t.toLowerCase();
  var qi = 0, sc = 0, last = -2;
  for (var i = 0; i < tl.length && qi < ql.length; i++) {
    if (tl[i] == ql[qi]) {
      sc += (i == last + 1) ? 5 : 1;
      if (i == 0 || '/\\._- '.contains(tl[i - 1])) sc += 3;
      last = i;
      qi++;
    }
  }
  return qi == ql.length ? sc : -1;
}

/// Ctrl+P → abrir archivo · Ctrl+Shift+P (o escribir ">") → comandos.
Future<void> showCommandPalette(BuildContext context, IdeState s, {required List<PaletteCmd> commands, bool commandMode = false, bool pure = false, String? placeholder}) =>
    showDialog(context: context, builder: (_) => _Palette(s, commands, commandMode, pure, placeholder));

class _Palette extends StatefulWidget {
  const _Palette(this.s, this.commands, this.commandMode, this.pure, this.placeholder);
  final IdeState s;
  final List<PaletteCmd> commands;
  final bool commandMode, pure;
  final String? placeholder;
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  int sel = 0;
  List<String> files = [];
  IdeState get s => widget.s;
  static const _h = 40.0, _view = 360.0;

  @override
  void initState() {
    super.initState();
    if (widget.commandMode && !widget.pure) _ctl.text = '>';
    _ctl.addListener(() => setState(() => sel = 0));
    if (!widget.pure) s.listFiles().then((v) {
      if (mounted) setState(() => files = v);
    });
  }

  List<_Item> _items() {
    final t = _ctl.text;
    final out = <_Item>[];
    if (widget.pure || t.startsWith('>')) {
      final q = widget.pure ? t.trim() : t.substring(1).trim();
      for (final c in widget.commands) {
        final sc = _score(q, c.label);
        if (sc >= 0) out.add(_Item(c.label, '', c.icon, c.hint, c.run, sc));
      }
      if (!(widget.pure && q.isEmpty)) out.sort((a, b) => b.score.compareTo(a.score));
      return out.take(widget.pure ? 300 : 60).toList();
    }
    final q = t.trim();
    final open = {for (final d in s.docs) norm(d.path)};
    for (final rel in files) {
      final base = p.basename(rel);
      final a = _score(q, base), b = _score(q, rel);
      var sc = q.isEmpty ? 0 : (a >= 0 ? a + 10 : b);
      if (sc < 0) continue;
      if (open.contains(norm(p.join(s.root!, rel)))) sc += 5;
      final dir = p.dirname(rel);
      out.add(_Item(base, dir == '.' ? '' : dir, fileIcon(base), '', () => s.openFile(p.join(s.root!, rel)), sc));
    }
    out.sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : a.sub.length.compareTo(b.sub.length));
    return out.take(60).toList();
  }

  void _run(_Item it) {
    Navigator.pop(context);
    it.run();
  }

  void _move(int d, int len) {
    if (len == 0) return;
    setState(() => sel = (sel + d).clamp(0, len - 1));
    final top = sel * _h;
    if (!_scroll.hasClients) return;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _h > _scroll.offset + _view) {
      _scroll.jumpTo(top + _h - _view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final items = _items();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 70, left: 24, right: 24),
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.border)),
      child: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Focus(
              onKeyEvent: (n, e) {
                if (e is KeyDownEvent || e is KeyRepeatEvent) {
                  if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _move(1, items.length);
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _move(-1, items.length);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _ctl,
                autofocus: true,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: widget.placeholder ?? 'Buscar archivo…   (escribe  >  para comandos)'),
                onSubmitted: (_) {
                  if (items.isNotEmpty) _run(items[math.min(sel, items.length - 1)]);
                },
              ),
            ),
          ),
          Divider(height: 1, color: t.border),
          SizedBox(
            height: _view,
            child: items.isEmpty
                ? Center(child: Text(s.root == null && !_ctl.text.startsWith('>') ? 'Abre un proyecto o escribe > para comandos' : 'Sin resultados', style: TextStyle(color: t.muted)))
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: _h,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return InkWell(
                        onTap: () => _run(it),
                        child: Container(
                          color: i == sel ? t.accent.withAlpha(60) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(children: [
                            Icon(it.icon, size: 17, color: t.muted),
                            const SizedBox(width: 10),
                            Text(it.title, style: const TextStyle(fontSize: 13.5)),
                            if (it.sub.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Expanded(child: Text(it.sub, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted))),
                            ] else
                              const Spacer(),
                            if (it.hint.isNotEmpty) Text(it.hint, style: TextStyle(fontSize: 11.5, color: t.muted)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
