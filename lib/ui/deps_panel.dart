import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../services/pub_service.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';
import 'common.dart';

class _Dep {
  _Dep(this.name, this.constraint, this.kind, this.dev, this.resolved);
  final String name, constraint, kind;
  final bool dev;
  final String? resolved;
  bool get hosted => kind == 'hosted';
}

bool _isNewer(String latest, String cur) {
  List<int> v(String s) => s.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
  final a = v(latest), b = v(cur);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

const _suggested = ['provider', 'riverpod', 'flutter_bloc', 'dio', 'http', 'go_router', 'get_it', 'freezed', 'json_serializable', 'shared_preferences', 'hive', 'drift', 'cached_network_image', 'intl', 'url_launcher'];

class DepsPanel extends StatefulWidget {
  const DepsPanel(this.s, {super.key});
  final IdeState s;
  @override
  State<DepsPanel> createState() => _DepsPanelState();
}

class _DepsPanelState extends State<DepsPanel> {
  int tab = 0;
  final _q = TextEditingController();
  Timer? _deb;
  List<String> _names = _suggested;
  bool _loading = false;
  String _err = '';
  final _busy = <String>{};
  String? _cacheKey;
  List<_Dep> _cache = [];
  IdeState get s => widget.s;

  List<_Dep> _read() {
    final root = s.root!;
    final f = File(p.join(root, 'pubspec.yaml'));
    if (!f.existsSync()) return [];
    final lock = File(p.join(root, 'pubspec.lock'));
    final key = '$root|${f.lastModifiedSync()}|${lock.existsSync() ? lock.lastModifiedSync() : ''}';
    if (key == _cacheKey) return _cache;
    final out = <_Dep>[];
    try {
      final y = loadYaml(f.readAsStringSync());
      final pk = lock.existsSync() ? (loadYaml(lock.readAsStringSync())['packages'] as YamlMap? ?? YamlMap()) : YamlMap();
      for (final sec in ['dependencies', 'dev_dependencies']) {
        final m = y[sec];
        if (m is! YamlMap) continue;
        for (final e in m.entries) {
          final v = e.value;
          var kind = 'hosted', cons = v == null ? 'any' : '$v';
          if (v is YamlMap) {
            kind = v.containsKey('sdk') ? 'sdk' : v.containsKey('git') ? 'git' : v.containsKey('path') ? 'path' : 'hosted';
            cons = kind == 'hosted' ? '${v['version'] ?? 'any'}' : kind;
          }
          out.add(_Dep('${e.key}', cons, kind, sec == 'dev_dependencies', pk['${e.key}']?['version']?.toString()));
        }
      }
    } catch (_) {}
    _cacheKey = key;
    return _cache = out;
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 450), () => _search(v));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _names = _suggested; _err = ''; });
      return;
    }
    setState(() { _loading = true; _err = ''; });
    try {
      final r = await PubService.search(q.trim());
      if (!mounted) return;
      setState(() => _names = r);
    } catch (_) {
      if (mounted) setState(() => _err = 'No se pudo conectar con pub.dev');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _do(String key, Future<void> Function() f) async {
    setState(() => _busy.add(key));
    await f();
    PubService.clearCache();
    if (mounted) setState(() => _busy.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (s.root == null) return const Center(child: Text('Abre un proyecto'));
    final deps = _read();
    return Column(children: [
      SideHeader(s, 'DEPENDENCIAS', [
        iconBtn(Icons.download, 'pub get', s.pubGet),
        iconBtn(Icons.refresh, 'Recargar versiones', () { PubService.clearCache(); setState(() {}); }),
      ]),
      Row(children: [_tab('INSTALADAS (${deps.length})', 0, t), _tab('AÑADIR', 1, t)]),
      Divider(height: 1, color: t.border),
      Expanded(child: tab == 0 ? _installed(deps, t) : _store(deps, t)),
    ]);
  }

  Widget _tab(String l, int i, IdeTheme t) => Expanded(
        child: InkWell(
          onTap: () => setState(() => tab = i),
          child: Container(
            height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2, color: tab == i ? t.accent : Colors.transparent))),
            child: Text(l, style: TextStyle(fontSize: 11, letterSpacing: .8, color: tab == i ? t.text : t.muted)),
          ),
        ),
      );

  Widget _chip(String text, Color c, IdeTheme t) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withAlpha(45), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withAlpha(120))),
        child: Text(text, style: TextStyle(fontSize: 11, color: c)),
      );

  Widget _installed(List<_Dep> deps, IdeTheme t) {
    Widget group(String title, List<_Dep> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 6), child: Text(title, style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.muted))),
            for (final d in list) _installedTile(d, t),
          ]);
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(avatar: const Icon(Icons.upgrade, size: 14), label: const Text('Upgrade', style: TextStyle(fontSize: 12)), onPressed: s.pubUpgrade),
          ActionChip(avatar: const Icon(Icons.rocket_launch_outlined, size: 14), label: const Text('Major versions', style: TextStyle(fontSize: 12)), onPressed: s.pubUpgradeMajor),
          ActionChip(avatar: const Icon(Icons.list_alt, size: 14), label: const Text('Outdated', style: TextStyle(fontSize: 12)), onPressed: s.pubOutdated),
        ]),
      ),
      group('DEPENDENCIES', deps.where((d) => !d.dev).toList()),
      group('DEV DEPENDENCIES', deps.where((d) => d.dev).toList()),
    ]);
  }

  Widget _installedTile(_Dep d, IdeTheme t) {
    final icon = d.kind == 'sdk' ? Icons.settings_suggest_outlined : d.kind == 'git' ? Icons.commit : d.kind == 'path' ? Icons.folder_outlined : Icons.inventory_2_outlined;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
      child: FutureBuilder<PkgInfo>(
        future: d.hosted ? PubService.info(d.name) : null,
        builder: (_, snap) {
          final info = snap.data;
          final upd = d.hosted && info != null && d.resolved != null && info.latest.isNotEmpty && _isNewer(info.latest, d.resolved!);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: t.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (_busy.contains(d.name)) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (d.kind != 'sdk') iconBtn(Icons.delete_outline, 'Quitar', () async {
                if (await confirm(context, s, 'Quitar paquete', '¿Quitar ${d.name} del proyecto?', ok: 'Quitar')) _do(d.name, () => s.removePackage(d.name));
              }),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              _chip(d.constraint, t.muted, t),
              if (d.resolved != null && d.kind != 'sdk') _chip('v${d.resolved}', Colors.lightGreenAccent, t),
              if (upd) _chip('↑ ${info.latest}', Colors.amber, t),
            ]),
            if (info != null && info.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(info.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted))),
            if (upd && !_busy.contains(d.name))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.arrow_circle_up, size: 16),
                  label: Text('Actualizar a ${info.latest}', style: const TextStyle(fontSize: 12)),
                  onPressed: () => _do(d.name, () => s.addPackage('${d.name}:^${info.latest}', dev: d.dev)),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _store(List<_Dep> deps, IdeTheme t) {
    final installed = {for (final d in deps) d.name: d};
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          controller: _q,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Buscar en pub.dev…',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
      ),
      if (_q.text.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 6), child: Align(alignment: Alignment.centerLeft, child: Text('SUGERIDOS', style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.muted)))),
      if (_err.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_err, style: const TextStyle(color: Colors.redAccent))),
      Expanded(
        child: ListView(children: [for (final n in _names) _storeTile(n, installed[n], t)]),
      ),
    ]);
  }

  Widget _storeTile(String name, _Dep? inst, IdeTheme t) => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
        child: FutureBuilder<PkgInfo>(
          future: PubService.info(name),
          builder: (_, snap) {
            final i = snap.data;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (i != null && i.latest.isNotEmpty) _chip(i.latest, t.accent, t),
              ]),
              const SizedBox(height: 4),
              if (snap.connectionState != ConnectionState.done) const LinearProgressIndicator(minHeight: 2)
              else if (i != null && i.description.isNotEmpty) Text(i.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted)),
              if (i != null && (i.likes != null || i.points != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    if (i.likes != null) ...[Icon(Icons.thumb_up_alt_outlined, size: 13, color: t.muted), const SizedBox(width: 3), Text('${i.likes}', style: TextStyle(fontSize: 11.5, color: t.muted)), const SizedBox(width: 12)],
                    if (i.points != null) ...[Icon(Icons.verified_outlined, size: 13, color: t.muted), const SizedBox(width: 3), Text('${i.points}/${i.maxPoints}', style: TextStyle(fontSize: 11.5, color: t.muted)), const SizedBox(width: 12)],
                    if (i.popularity != null) ...[Icon(Icons.trending_up, size: 13, color: t.muted), const SizedBox(width: 3), Text('${(i.popularity! * 100).round()}%', style: TextStyle(fontSize: 11.5, color: t.muted))],
                  ]),
                ),
              const SizedBox(height: 8),
              if (inst != null)
                Row(children: [Icon(Icons.check_circle, size: 16, color: Colors.lightGreenAccent.shade400), const SizedBox(width: 6), Text('Instalado ${inst.resolved != null ? 'v${inst.resolved}' : ''}', style: const TextStyle(fontSize: 12))])
              else if (_busy.contains(name))
                const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Instalando…', style: TextStyle(fontSize: 12))])
              else
                Row(children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Instalar', style: TextStyle(fontSize: 12)),
                    onPressed: () => _do(name, () => s.addPackage(name)),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (v) async {
                      if (v == 'dev') _do(name, () => s.addPackage(name, dev: true));
                      if (v == 'ver') {
                        final ver = await promptText(context, s, 'Versión de $name', hint: '1.2.3 o ^1.2.0');
                        if (ver != null) _do(name, () => s.addPackage('$name:${RegExp(r'^\d').hasMatch(ver) ? '^$ver' : ver}'));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'dev', child: Text('Instalar como dev dependency')),
                      PopupMenuItem(value: 'ver', child: Text('Instalar versión específica…')),
                    ],
                  ),
                ]),
            ]);
          },
        ),
      );
}
