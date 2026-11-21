import 'package:flutter/material.dart';
import '../state/ide_state.dart';

Future<void> showTasksManager(BuildContext c, IdeState s) => showDialog<void>(context: c, builder: (_) => _Tasks(s));

class _Tasks extends StatefulWidget {
  const _Tasks(this.s);
  final IdeState s;
  @override
  State<_Tasks> createState() => _TasksState();
}

class _TasksState extends State<_Tasks> {
  IdeState get s => widget.s;
  late List<Map<String, String>> list = [for (final e in s.projectTasks) Map<String, String>.from(e)];
  int sel = -1;
  final name = TextEditingController();
  final cmd = TextEditingController();
  String msg = '';

  static const _mono = TextStyle(fontSize: 13, fontFamily: 'Consolas', fontFamilyFallback: ['monospace']);
  static const _suggestions = <(String, String)>[
    ('build_runner: build', 'dart run build_runner build --delete-conflicting-outputs'),
    ('Generar íconos de la app', 'dart run flutter_launcher_icons'),
    ('Generar pantalla de inicio', 'dart run flutter_native_splash:create'),
    ('Analizar', 'flutter analyze'),
    ('Pruebas con cobertura', 'flutter test --coverage'),
    ('Limpiar y reinstalar', 'flutter clean && flutter pub get'),
  ];

  void _select(int i) {
    sel = i;
    name.text = i >= 0 ? list[i]['name'] ?? '' : '';
    cmd.text = i >= 0 ? list[i]['cmd'] ?? '' : '';
    setState(() => msg = '');
  }

  void _persist() => s.saveTasks(list.map((e) => Map<String, String>.from(e)).toList());

  void _save() {
    if (name.text.trim().isEmpty || cmd.text.trim().isEmpty) {
      setState(() => msg = 'El nombre y el comando son obligatorios');
      return;
    }
    final item = {'name': name.text.trim(), 'cmd': cmd.text.trim()};
    setState(() {
      if (sel >= 0) {
        list[sel] = item;
      } else {
        list.add(item);
        sel = list.length - 1;
      }
      msg = 'Guardado ✓';
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
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 520),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              Icon(Icons.checklist_rtl, color: t.accent),
              const SizedBox(width: 10),
              const Expanded(child: Text('Tareas del proyecto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 250,
                child: Column(children: [
                  Padding(padding: const EdgeInsets.all(10), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _select(-1), icon: const Icon(Icons.add, size: 18), label: const Text('Nueva tarea')))),
                  Expanded(
                    child: list.isEmpty
                        ? Center(child: Text('Aún no hay tareas', style: TextStyle(color: t.muted)))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) => ListTile(
                              dense: true,
                              selected: i == sel,
                              selectedTileColor: t.accent.withAlpha(50),
                              title: Text(list[i]['name'] ?? ''),
                              trailing: IconButton(tooltip: 'Ejecutar', icon: const Icon(Icons.play_arrow, size: 18, color: Colors.greenAccent), onPressed: () => s.runTask(list[i])),
                              onTap: () => _select(i),
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
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'build_runner: build')),
                    const SizedBox(height: 10),
                    TextField(controller: cmd, style: _mono, decoration: const InputDecoration(labelText: 'Comando (se ejecuta en una terminal nueva, en la carpeta del proyecto)')),
                    const SizedBox(height: 14),
                    Text('SUGERENCIAS', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: t.muted)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final sg in _suggestions)
                        ActionChip(
                          label: Text(sg.$1, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() {
                            sel = -1;
                            name.text = sg.$1;
                            cmd.text = sg.$2;
                          }),
                        ),
                    ]),
                    const Spacer(),
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
