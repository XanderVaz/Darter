import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import '../services/diff_page.dart';
import '../services/monaco_local.dart';
import '../state/ide_state.dart';
import 'common.dart';

String langOf(String path) {
  final e = path.split('.').last.toLowerCase();
  return const {
        'dart': 'dart', 'yaml': 'yaml', 'yml': 'yaml', 'json': 'json', 'md': 'markdown', 'xml': 'xml', 'html': 'html',
        'css': 'css', 'js': 'javascript', 'kt': 'kotlin', 'swift': 'swift', 'gradle': 'groovy', 'sh': 'shell',
      }[e] ??
      'plaintext';
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class DiffController {
  InAppWebViewController? _c;
  bool _ready = false;
  String? _pending;
  bool side = true;

  void show(String original, String modified, String lang) {
    _pending = 'setDiff(${jsonEncode(original)},${jsonEncode(modified)},${jsonEncode(lang)})';
    _flush();
  }

  void setSide(bool v) {
    side = v;
    if (_ready) _c?.evaluateJavascript(source: 'setSide($v)');
  }

  void _flush() {
    final c = _c;
    if (_ready && c != null && _pending != null) {
      c.evaluateJavascript(source: _pending!);
      _pending = null;
    }
  }
}

class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.s, required this.ctrl});
  final IdeState s;
  final DiffController ctrl;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    if (Platform.isLinux) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('La vista de diferencias usa WebView, que aún no está disponible en Linux.\nUsa «git diff» en la terminal.', textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
        ),
      );
    }
    final bg = _hex(t.bg);
    final base = s.monacoBase;
    return InAppWebView(
      key: ValueKey(base),
      initialData: base == null ? InAppWebViewInitialData(data: diffHtml('https://cdn.jsdelivr.net/npm/monaco-editor@$monacoVersion/min/vs', bg), baseUrl: WebUri('https://localhost/')) : null,
      initialUrlRequest: base == null ? null : URLRequest(url: WebUri('$base/diff.html?bg=${Uri.encodeComponent(bg)}')),
      onWebViewCreated: (c) {
        ctrl._c = c;
        c.addJavaScriptHandler(
          handlerName: 'ready',
          callback: (_) {
            ctrl._ready = true;
            c.evaluateJavascript(source: 'applyTheme(${jsonEncode(t.monaco)},"${t.id}",${s.fontSize})');
            c.evaluateJavascript(source: 'setSide(${ctrl.side})');
            ctrl._flush();
          },
        );
      },
    );
  }
}

Widget _sideToggle(DiffController ctrl, VoidCallback refresh) => SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: true, label: Text('Lado a lado'), icon: Icon(Icons.vertical_split, size: 16)),
        ButtonSegment(value: false, label: Text('En línea'), icon: Icon(Icons.view_stream_outlined, size: 16)),
      ],
      selected: {ctrl.side},
      onSelectionChanged: (v) {
        ctrl.setSide(v.first);
        refresh();
      },
    );

/// Diálogo con la comparación de dos textos.
Future<void> showDiffDialog(BuildContext context, IdeState s, {required String title, required String path, required String original, required String modified}) {
  final ctrl = DiffController()..show(original, modified, langOf(path));
  return showDialog<void>(context: context, builder: (_) => _DiffDialog(s, title, ctrl));
}

class _DiffDialog extends StatefulWidget {
  const _DiffDialog(this.s, this.title, this.ctrl);
  final IdeState s;
  final String title;
  final DiffController ctrl;
  @override
  State<_DiffDialog> createState() => _DiffDialogState();
}

class _DiffDialogState extends State<_DiffDialog> {
  @override
  Widget build(BuildContext context) {
    final t = widget.s.theme;
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.border)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width < 1148 ? size.width - 48 : 1100,
        height: size.height < 728 ? size.height - 48 : 680,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.difference_outlined, color: t.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              _sideToggle(widget.ctrl, () => setState(() {})),
              const SizedBox(width: 8),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(child: DiffView(s: widget.s, ctrl: widget.ctrl)),
        ]),
      ),
    );
  }
}

/// Historial de un archivo con diff lado a lado por commit.
Future<void> showFileHistory(BuildContext context, IdeState s, String path) => showDialog<void>(context: context, builder: (_) => _HistoryDialog(s, path));

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog(this.s, this.path);
  final IdeState s;
  final String path;
  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  final ctrl = DiffController();
  List<({String hash, String subject, String author, String date})> log = [];
  int sel = -1;
  bool loading = true;
  IdeState get s => widget.s;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    log = await s.fileLog(widget.path);
    if (!mounted) return;
    setState(() => loading = false);
    _select(0);
  }

  Future<void> _select(int i) async {
    setState(() => sel = i);
    final sides = i == 0 ? await s.gitHeadVsWorking(widget.path) : await s.gitCommitSides(log[i - 1].hash, widget.path);
    if (!mounted || sel != i) return;
    ctrl.show(sides.a, sides.b, langOf(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.border)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width < 1248 ? size.width - 48 : 1200,
        height: size.height < 728 ? size.height - 48 : 700,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.history, color: t.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Historial · ${p.basename(widget.path)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              _sideToggle(ctrl, () => setState(() {})),
              const SizedBox(width: 8),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 310,
                child: loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : ListView.builder(
                        itemCount: log.length + 1,
                        itemBuilder: (_, i) {
                          final selected = i == sel;
                          return InkWell(
                            onTap: () => _select(i),
                            child: Container(
                              color: selected ? t.accent.withAlpha(50) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: i == 0
                                  ? Row(children: [Icon(Icons.edit_note, size: 18, color: t.accent), const SizedBox(width: 8), const Expanded(child: Text('Cambios sin confirmar (vs HEAD)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))])
                                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(log[i - 1].subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(color: t.accent.withAlpha(40), borderRadius: BorderRadius.circular(4)),
                                          child: Text(log[i - 1].hash, style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', fontFamilyFallback: ['monospace'])),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text('${log[i - 1].author} · ${log[i - 1].date}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: t.muted))),
                                      ]),
                                    ]),
                            ),
                          );
                        },
                      ),
              ),
              VerticalDivider(width: 1, color: t.border),
              Expanded(child: DiffView(s: s, ctrl: ctrl)),
            ]),
          ),
        ]),
      ),
    );
  }
}
