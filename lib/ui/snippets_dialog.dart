import 'package:flutter/material.dart';
import '../state/ide_state.dart';

Future<void> showSnippetsManager(BuildContext c, IdeState s) => showDialog<void>(context: c, builder: (_) => _Snippets(s));

class _Snippets extends StatefulWidget {
  const _Snippets(this.s);
  final IdeState s;
  @override
  State<_Snippets> createState() => _SnippetsState();
}

class _SnippetsState extends State<_Snippets> {
  IdeState get s => widget.s;
  late List<Map<String, String>> list = [for (final e in s.userSnippets) Map<String, String>.from(e)];
  int sel = -1;
  final prefix = TextEditingController();
  final desc = TextEditingController();
  final body = TextEditingController();
  String msg = '';

  static const _mono = TextStyle(fontSize: 13, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']);

  void _select(int i) {
    sel = i;
    if (i >= 0) {
      prefix.text = list[i]['prefix'] ?? '';
      desc.text = list[i]['desc'] ?? '';
      body.text = list[i]['body'] ?? '';
    } else {
      prefix.clear();
      desc.clear();
      body.clear();
    }
    setState(() => msg = '');
  }

  void _persist() => s.saveSnippets(list.map((e) => Map<String, String>.from(e)).toList());

  void _save() {
    final pre = prefix.text.trim();
    if (pre.isEmpty || body.text.isEmpty) {
      setState(() => msg = 'El prefijo y el cuerpo son obligatorios');
      return;
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(pre)) {
      setState(() => msg = 'El prefijo solo puede tener letras, números y _');
      return;
    }
    final item = {'prefix': pre, 'desc': desc.text.trim(), 'body': body.text};
    setState(() {
      if (sel >= 0) {
        list[sel] = item;
      } else {
        list.add(item);
        sel = list.length - 1;
      }
      msg = 'Guardado ✓ — ya está disponible al escribir «$pre» en archivos .dart';
    });
    _persist();
  }

  void _delete() {
    if (sel < 0) return;
    list.removeAt(sel);
    _persist();
    _select(-1);
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 580),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              Icon(Icons.bolt, color: t.accent),
              const SizedBox(width: 10),
              const Expanded(child: Text('Snippets propios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 240,
                child: Column(children: [
                  Padding(padding: const EdgeInsets.all(10), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _select(-1), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo snippet')))),
                  Expanded(
                    child: list.isEmpty
                        ? Center(child: Text('Aún no tienes snippets', style: TextStyle(color: t.muted)))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) => InkWell(
                              onTap: () => _select(i),
                              child: Container(
                                color: i == sel ? t.accent.withAlpha(50) : null,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(list[i]['prefix'] ?? '', style: _mono.copyWith(fontWeight: FontWeight.w700)),
                                  if ((list[i]['desc'] ?? '').isNotEmpty) Text(list[i]['desc']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted)),
                                ]),
                              ),
                            ),
                          ),
                  ),
                ]),
              ),
              VerticalDivider(width: 1, color: t.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: prefix, decoration: const InputDecoration(labelText: 'Prefijo (lo que escribes para activarlo)', hintText: 'miwidget')),
                    const SizedBox(height: 10),
                    TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TextField(controller: body, expands: true, maxLines: null, minLines: null, textAlignVertical: TextAlignVertical.top, style: _mono, decoration: const InputDecoration(labelText: 'Cuerpo', alignLabelWithHint: true)),
                    ),
                    const SizedBox(height: 8),
                    Text(r'Usa ${1:nombre} para campos editables (salta con Tab) y $0 para dejar el cursor al final.', style: TextStyle(fontSize: 12, color: t.muted)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text(msg, style: TextStyle(fontSize: 12.5, color: msg.startsWith('Guardado') ? Colors.lightGreenAccent : Colors.amber))),
                      if (sel >= 0) TextButton(onPressed: _delete, child: const Text('Eliminar')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _save, child: const Text('Guardar')),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
