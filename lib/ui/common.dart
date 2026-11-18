import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../state/ide_state.dart';
import '../theme/ide_theme.dart';

Future<void> pickAndOpenFolder(IdeState s) async {
  final d = await FilePicker.platform.getDirectoryPath();
  if (d != null) await s.openProject(d);
}

Future<String?> promptText(BuildContext c, IdeState s, String title, {String initial = '', String hint = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      backgroundColor: s.theme.panel,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Aceptar')),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

Future<bool> confirm(BuildContext c, IdeState s, String title, String body, {String ok = 'Aceptar'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      backgroundColor: s.theme.panel,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Widget iconBtn(IconData i, String tip, VoidCallback? onTap, {Color? color, double size = 16}) => IconButton(
      tooltip: tip,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: color,
      icon: Icon(i),
      onPressed: onTap,
    );

class SideHeader extends StatelessWidget {
  const SideHeader(this.s, this.title, [this.actions = const []]);
  final IdeState s;
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(children: [
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: s.theme.muted))),
          ...actions,
        ]),
      );
}

IconData fileIcon(String n) {
  if (n == 'pubspec.yaml') return Icons.inventory_2_outlined;
  if (n.endsWith('.dart')) return Icons.code;
  if (n.endsWith('.yaml') || n.endsWith('.yml')) return Icons.tune;
  if (n.endsWith('.json')) return Icons.data_object;
  if (n.endsWith('.md')) return Icons.article_outlined;
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.svg')) return Icons.image_outlined;
  return Icons.insert_drive_file_outlined;
}

Color fileColor(String n, IdeTheme t) {
  if (n == 'pubspec.yaml') return Colors.orangeAccent;
  if (n.endsWith('.dart')) return const Color(0xFF42A5F5);
  if (n.endsWith('.yaml') || n.endsWith('.yml')) return Colors.orange;
  if (n.endsWith('.json')) return Colors.amber;
  if (n.endsWith('.kt') || n.endsWith('.gradle')) return Colors.purpleAccent;
  if (n.endsWith('.swift')) return Colors.deepOrange;
  return t.muted;
}

// ---------- ANSI (colores en terminal / salida) ----------
final _sgrRe = RegExp('\u001B\\[([0-9;]*)m');
final _csiRe = RegExp('\u001B\\[[0-9;?]*[A-Za-ln-z]');

String stripAnsi(String s) => s.replaceAll(RegExp('\u001B\\[[0-9;?]*[A-Za-z]'), '');

const _ansi16 = [
  Color(0xFF7F7F7F), Color(0xFFCD3131), Color(0xFF0DBC79), Color(0xFFE5E510), Color(0xFF2472C8), Color(0xFFBC3FBC), Color(0xFF11A8CD), Color(0xFFE5E5E5),
  Color(0xFF666666), Color(0xFFF14C4C), Color(0xFF23D18B), Color(0xFFF5F543), Color(0xFF3B8EEA), Color(0xFFD670D6), Color(0xFF29B8DB), Color(0xFFFFFFFF),
];

Color _ansi256(int n) {
  if (n < 16) return _ansi16[n];
  if (n >= 232) {
    final v = 8 + (n - 232) * 10;
    return Color.fromARGB(255, v, v, v);
  }
  final i = n - 16;
  int c(int x) => x == 0 ? 0 : 55 + x * 40;
  return Color.fromARGB(255, c(i ~/ 36), c((i % 36) ~/ 6), c(i % 6));
}

TextStyle _sgr(TextStyle cur, TextStyle base, String codes) {
  final cs = codes.isEmpty ? [0] : codes.split(';').map((e) => int.tryParse(e) ?? 0).toList();
  var st = cur;
  for (var i = 0; i < cs.length; i++) {
    final c = cs[i];
    if (c == 0) {
      st = base;
    } else if (c == 1) {
      st = st.copyWith(fontWeight: FontWeight.bold);
    } else if (c == 22) {
      st = st.copyWith(fontWeight: FontWeight.normal);
    } else if (c == 3) {
      st = st.copyWith(fontStyle: FontStyle.italic);
    } else if (c == 4) {
      st = st.copyWith(decoration: TextDecoration.underline);
    } else if (c == 24) {
      st = st.copyWith(decoration: TextDecoration.none);
    } else if (c >= 30 && c <= 37) {
      st = st.copyWith(color: _ansi16[c - 30]);
    } else if (c >= 90 && c <= 97) {
      st = st.copyWith(color: _ansi16[c - 90 + 8]);
    } else if (c == 39) {
      st = st.copyWith(color: base.color);
    } else if (c >= 40 && c <= 47) {
      st = st.copyWith(backgroundColor: _ansi16[c - 40]);
    } else if (c == 38 && i + 1 < cs.length) {
      if (cs[i + 1] == 5 && i + 2 < cs.length) {
        st = st.copyWith(color: _ansi256(cs[i + 2].clamp(0, 255)));
        i += 2;
      } else if (cs[i + 1] == 2 && i + 4 < cs.length) {
        st = st.copyWith(color: Color.fromARGB(255, cs[i + 2].clamp(0, 255), cs[i + 3].clamp(0, 255), cs[i + 4].clamp(0, 255)));
        i += 4;
      }
    }
  }
  return st;
}

List<({String text, TextStyle style})> ansiSegments(String raw, TextStyle base) {
  var line = raw;
  if (line.contains('\r')) {
    final parts = line.split('\r').where((e) => e.isNotEmpty).toList();
    line = parts.isEmpty ? '' : parts.last;
  }
  final out = <({String text, TextStyle style})>[];
  var style = base, i = 0;
  String clean(String t) => t.replaceAll(_csiRe, '');
  for (final m in _sgrRe.allMatches(line)) {
    if (m.start > i) out.add((text: clean(line.substring(i, m.start)), style: style));
    style = _sgr(style, base, m.group(1) ?? '');
    i = m.end;
  }
  if (i < line.length) out.add((text: clean(line.substring(i)), style: style));
  final res = out.where((e) => e.text.isNotEmpty).toList();
  return res.isEmpty ? [(text: ' ', style: base)] : res;
}
