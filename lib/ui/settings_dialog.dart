import 'package:flutter/material.dart';
import '../services/monaco_local.dart';
import 'about_dialog.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'snippets_dialog.dart';

const _fonts = <String>['', 'Cascadia Code', 'JetBrains Mono', 'Fira Code', 'Source Code Pro', 'Consolas', 'Courier New'];

Future<void> showSettings(BuildContext c, IdeState s) => showDialog(context: c, builder: (_) => _SettingsDialog(s));

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog(this.s);
  final IdeState s;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  IdeState get s => widget.s;
  late double fs = s.fontSize;

  Widget _label(String l) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(l, style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: s.theme.muted)),
      );

  Widget _sw(String title, String sub, bool v, void Function(bool) f) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        subtitle: Text(sub, style: TextStyle(fontSize: 12, color: s.theme.muted)),
        value: v,
        onChanged: (x) => setState(() => f(x)),
      );

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.settings_outlined, color: t.accent),
              const SizedBox(width: 10),
              const Expanded(child: Text('Ajustes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            _label('EDITOR'),
            Row(children: [
              const Text('Tamaño de fuente'),
              Expanded(
                child: Slider(
                  min: 10, max: 26, divisions: 16, value: fs, label: fs.round().toString(),
                  onChanged: (v) => setState(() => fs = v),
                  onChangeEnd: (v) => s.updateSettings(font: v),
                ),
              ),
              SizedBox(width: 28, child: Text('${fs.round()}')),
            ]),
            _sw('Minimapa', 'Vista en miniatura del archivo', s.minimap, (v) => s.updateSettings(mm: v)),
            _sw('Ajuste de línea', 'Divide las líneas largas', s.wordWrap, (v) => s.updateSettings(wrap: v)),
            Row(children: [
              const Text('Fuente'),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _fonts.contains(s.fontFamily) ? s.fontFamily : '',
                  dropdownColor: t.side,
                  items: [for (final f in _fonts) DropdownMenuItem(value: f, child: Text(f.isEmpty ? 'Predeterminada (Consolas)' : f))],
                  onChanged: (v) => setState(() => s.updateSettings(family: v ?? '')),
                ),
              ),
            ]),
            _sw('Ligaduras tipográficas', 'Para fuentes como Fira Code o JetBrains Mono (deben estar instaladas)', s.fontLigatures, (v) => s.updateSettings(lig: v)),
            Row(children: [
              const Text('Tamaño de tabulación'),
              const Spacer(),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 4, label: Text('4')), ButtonSegment(value: 8, label: Text('8'))],
                selected: {s.tabSize},
                onSelectionChanged: (v) => setState(() => s.updateSettings(tab: v.first)),
              ),
            ]),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => showSnippetsManager(context, s), icon: const Icon(Icons.bolt, size: 18), label: const Text('Gestionar snippets propios…'))),
            _label('GUARDADO'),
            _sw('Guardado automático', 'Guarda ~1 s después de dejar de escribir (dispara hot reload)', s.autoSave, (v) => s.updateSettings(auto: v)),
            _sw('Formatear al guardar', 'Ejecuta dart format en archivos .dart', s.formatOnSave, (v) => s.updateSettings(fmt: v)),
            _sw('pub get al guardar pubspec.yaml', 'Descarga las dependencias automáticamente', s.autoPubGet, (v) => s.updateSettings(pubget: v)),
            _label('ACTUALIZACIONES'),
            ListenableBuilder(
              listenable: s,
              builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sw('Buscar actualizaciones al iniciar', 'Consulta GitHub Releases una vez al día', s.autoCheckUpdates, (v) => s.setUpdateSettings(auto: v)),
                _sw('Recibir versiones beta', 'Incluye los pre-lanzamientos', s.betaChannel, (v) => s.setUpdateSettings(beta: v)),
                const SizedBox(height: 4),
                OutlinedButton.icon(onPressed: () => showUpdateDialog(context, s), icon: const Icon(Icons.system_update_alt, size: 18), label: const Text('Buscar ahora')),
              ]),
            ),
            _label('EDITOR SIN CONEXIÓN'),
            ListenableBuilder(
              listenable: s,
              builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  monacoInstalled()
                      ? (s.monacoBase != null ? 'Monaco local activo ✓ (el editor funciona sin internet)' : 'Descargado; reinicia la app para activarlo')
                      : 'Ahora el editor usa el CDN (necesita internet). Descarga Monaco (~15 MB) una vez para trabajar sin conexión.',
                  style: TextStyle(fontSize: 12.5, color: s.theme.muted),
                ),
                if (s.monacoBusy) ...[const SizedBox(height: 8), LinearProgressIndicator(value: s.monacoProgress)],
                if (s.monacoStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.monacoStatus, style: const TextStyle(fontSize: 12))),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.icon(onPressed: s.monacoBusy ? null : s.installMonaco, icon: const Icon(Icons.download, size: 18), label: Text(monacoInstalled() ? 'Volver a descargar' : 'Descargar Monaco')),
                  const SizedBox(width: 8),
                  if (monacoInstalled()) OutlinedButton(onPressed: s.monacoBusy ? null : s.removeMonaco, child: const Text('Eliminar copia local')),
                ]),
              ]),
            ),
            _label('TEMA'),
            _sw('Seguir el tema del sistema', 'Cambia entre claro y oscuro automáticamente según Windows', s.followSystem, (v) => s.setFollowSystem(v)),
            if (s.followSystem)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Text('Oscuro'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: s.darkThemeId,
                      dropdownColor: t.side,
                      items: [for (final th in IdeTheme.all.where((x) => x.dark)) DropdownMenuItem(value: th.id, child: Text(th.name))],
                      onChanged: (v) => setState(() => s.setSystemThemes(dark: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('Claro'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: s.lightThemeId,
                      dropdownColor: t.side,
                      items: [for (final th in IdeTheme.all.where((x) => !x.dark)) DropdownMenuItem(value: th.id, child: Text(th.name))],
                      onChanged: (v) => setState(() => s.setSystemThemes(light: v)),
                    ),
                  ),
                ]),
              ),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final th in IdeTheme.all)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => s.setTheme(th)),
                  child: Container(
                    width: 156,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: th.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: s.theme.id == th.id ? th.accent : th.border, width: s.theme.id == th.id ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        for (final c in [th.accent, Color(int.parse('FF${th.syntax[1]}', radix: 16)), Color(int.parse('FF${th.syntax[0]}', radix: 16))])
                          Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 5), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                      ]),
                      const SizedBox(height: 8),
                      Text(th.name, style: TextStyle(fontSize: 12.5, color: th.text, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
