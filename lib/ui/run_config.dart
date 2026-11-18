import 'package:flutter/material.dart';
import '../state/ide_state.dart';
import 'common.dart';

Future<void> showRunConfig(BuildContext c, IdeState s) => showDialog(context: c, builder: (_) => _RunConfigDialog(s));

class _RunConfigDialog extends StatefulWidget {
  const _RunConfigDialog(this.s);
  final IdeState s;
  @override
  State<_RunConfigDialog> createState() => _RunConfigDialogState();
}

class _RunConfigDialogState extends State<_RunConfigDialog> {
  IdeState get s => widget.s;
  String mode = 'debug';
  final target = TextEditingController();
  final flavor = TextEditingController();
  final defines = TextEditingController();
  final extra = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill();
  }

  void _fill() {
    final c = s.runConfig;
    mode = c.mode;
    target.text = c.target;
    flavor.text = c.flavor;
    defines.text = c.defines;
    extra.text = c.extra;
  }

  RunConfig get cfg => RunConfig(name: s.runConfig.name, mode: mode, target: target.text.trim(), flavor: flavor.text.trim(), defines: defines.text, extra: extra.text);

  Widget _label(String l) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(l, style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: s.theme.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.tune, color: t.accent),
              const SizedBox(width: 10),
              const Text('Configuración de ejecución', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (var i = 0; i < s.runConfigs.length; i++)
                ChoiceChip(
                  label: Text(s.runConfigs[i].name),
                  selected: i == s.activeRun,
                  onSelected: (_) {
                    s.setRunConfig(cfg);
                    s.selectRunConfig(i);
                    setState(_fill);
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Nueva'),
                onPressed: () async {
                  final n = await promptText(context, s, 'Nombre de la configuración', hint: 'dev, staging, prod…');
                  if (n == null) return;
                  s.setRunConfig(cfg);
                  s.addRunConfig(n);
                  setState(_fill);
                },
              ),
              if (s.runConfigs.length > 1)
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Eliminar'),
                  onPressed: () {
                    s.deleteRunConfig(s.activeRun);
                    setState(_fill);
                  },
                ),
            ]),
            if (!s.isFlutter) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Proyecto Dart: solo se aplican el archivo de entrada y los argumentos extra.', style: TextStyle(fontSize: 12, color: t.muted))),
            _label('MODO'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'debug', label: Text('Debug'), icon: Icon(Icons.bug_report_outlined, size: 16)),
                  ButtonSegment(value: 'profile', label: Text('Profile'), icon: Icon(Icons.speed, size: 16)),
                  ButtonSegment(value: 'release', label: Text('Release'), icon: Icon(Icons.rocket_launch_outlined, size: 16)),
                ],
                selected: {mode},
                onSelectionChanged: (v) => setState(() => mode = v.first),
              ),
            ),
            _label('ARCHIVO DE ENTRADA (-t)'),
            TextField(controller: target, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'lib/main.dart')),
            _label('FLAVOR (--flavor)'),
            TextField(controller: flavor, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'dev, staging, prod…')),
            _label('DART DEFINES (uno por línea: CLAVE=valor)'),
            TextField(controller: defines, minLines: 3, maxLines: 5, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'API_URL=https://api.ejemplo.com\nENV=dev')),
            _label('ARGUMENTOS EXTRA'),
            TextField(controller: extra, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: '--no-sound-null-safety, --verbose…')),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
              child: SelectableText('\$ ${s.isFlutter ? 'flutter' : 'dart'} ${cfg.args(s.isFlutter, s.device?.id ?? '<dispositivo>').join(' ')}', style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12, color: t.accent)),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () { s.setRunConfig(cfg); Navigator.pop(context); }, child: const Text('Guardar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Guardar y ejecutar'),
                onPressed: () {
                  s.setRunConfig(cfg);
                  Navigator.pop(context);
                  if (!s.isRunning) s.run();
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
