import 'package:flutter/material.dart';
import '../services/env_check.dart';
import '../state/ide_state.dart';
import 'logo.dart';

Future<void> showEnvCheck(BuildContext c, IdeState s, {bool welcome = false}) => showDialog<void>(context: c, barrierDismissible: !welcome, builder: (_) => _EnvDialog(s, welcome));

class _EnvDialog extends StatefulWidget {
  const _EnvDialog(this.s, this.welcome);
  final IdeState s;
  final bool welcome;
  @override
  State<_EnvDialog> createState() => _EnvDialogState();
}

class _EnvDialogState extends State<_EnvDialog> {
  IdeState get s => widget.s;
  List<EnvItem>? items;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => items = null);
    final r = await checkEnvironment();
    if (mounted) setState(() => items = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final list = items;
    final allOk = list != null && list.where((e) => !e.optional).every((e) => e.ok);
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (widget.welcome) ...[const LogoMark(size: 44, background: true), const SizedBox(width: 14)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.welcome ? '¡Bienvenido a $kAppName!' : 'Verificar entorno', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(widget.welcome ? 'Primero comprobemos que tu equipo tiene lo necesario.' : 'Herramientas que $kAppName usa para trabajar.', style: TextStyle(fontSize: 12.5, color: t.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            if (list == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final e in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: e.ok ? Colors.lightGreenAccent.withAlpha(90) : (e.optional ? Colors.amber.withAlpha(120) : Colors.redAccent.withAlpha(140)))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(e.ok ? Icons.check_circle : (e.optional ? Icons.info_outline : Icons.error_outline), size: 20, color: e.ok ? Colors.lightGreenAccent : (e.optional ? Colors.amber : Colors.redAccent)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${e.name}${e.optional ? '  (opcional)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            SelectableText(e.detail, style: TextStyle(fontSize: 12.5, color: t.muted)),
                            if (!e.ok) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(e.hint, style: const TextStyle(fontSize: 12.5, color: Colors.amber))),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            const SizedBox(height: 10),
            if (list != null) Text(allOk ? '✓ Todo listo para trabajar con Flutter y Dart.' : 'Instala lo que falta, reinicia $kAppName y vuelve a comprobar.', style: TextStyle(color: allOk ? Colors.lightGreenAccent : Colors.amber, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (list != null) TextButton(onPressed: _check, child: const Text('Volver a comprobar')),
              TextButton(onPressed: () => s.openUrl('https://docs.flutter.dev/get-started/install'), child: const Text('Guía de instalación')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(widget.welcome ? 'Empezar' : 'Cerrar')),
            ]),
          ]),
        ),
      ),
    );
  }
}
