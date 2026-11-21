import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cliente mínimo LSP para `dart language-server` (stdio, JSON-RPC).
class LspClient {
  LspClient(this.onDiagnostics, this.onApplyEdit);
  final void Function(String uri, List diags) onDiagnostics;
  final Future<bool> Function(Map edit) onApplyEdit;
  Process? _p;
  int _id = 0;
  final _pending = <int, Completer<dynamic>>{};
  final _buf = <int>[];
  final _ready = Completer<bool>();
  Future<bool> get ready => _ready.future;
  bool get alive => _p != null;

  String _uri(String path) => Uri.file(path).toString();

  Future<void> start(String root) async {
    try {
      _p = await Process.start('dart', ['language-server'], runInShell: true);
      _p!.stdout.listen(_onData);
      _p!.stderr.listen((_) {});
      _p!.exitCode.then((_) {
        _p = null;
        if (!_ready.isCompleted) _ready.complete(false);
      });
      final uri = Uri.directory(root).toString();
      await _request('initialize', {
        'processId': pid,
        'rootUri': uri,
        'workspaceFolders': [{'uri': uri, 'name': 'root'}],
        'capabilities': {
          'textDocument': {
            'completion': {'completionItem': {'snippetSupport': false}},
            'hover': {'contentFormat': ['markdown', 'plaintext']},
            'publishDiagnostics': {},
            'definition': {},
            'documentSymbol': {'hierarchicalDocumentSymbolSupport': true},
            'signatureHelp': {
              'signatureInformation': {
                'documentationFormat': ['markdown', 'plaintext'],
                'parameterInformation': {'labelOffsetSupport': true}
              }
            },
            'references': {},
            'rename': {'prepareSupport': false},
            'codeAction': {
              'codeActionLiteralSupport': {
                'codeActionKind': {
                  'valueSet': ['quickfix', 'refactor', 'refactor.extract', 'refactor.inline', 'refactor.rewrite', 'source', 'source.organizeImports', 'source.fixAll']
                }
              }
            },
          },
          'workspace': {'workspaceFolders': true, 'applyEdit': true, 'workspaceEdit': {'documentChanges': false}},
        },
      }, seconds: 30);
      _notify('initialized', {});
      if (!_ready.isCompleted) _ready.complete(true);
    } catch (_) {
      if (!_ready.isCompleted) _ready.complete(false);
    }
  }

  void _send(Map<String, dynamic> m) {
    final p = _p;
    if (p == null) return;
    final body = utf8.encode(jsonEncode(m));
    p.stdin.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
    p.stdin.add(body);
  }

  void _notify(String method, Map params) => _send({'jsonrpc': '2.0', 'method': method, 'params': params});

  Future<dynamic> _request(String method, Map params, {int seconds = 10}) {
    final id = ++_id;
    final c = Completer<dynamic>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future.timeout(Duration(seconds: seconds), onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  int _headerEnd() {
    for (var i = 0; i + 3 < _buf.length; i++) {
      if (_buf[i] == 13 && _buf[i + 1] == 10 && _buf[i + 2] == 13 && _buf[i + 3] == 10) return i;
    }
    return -1;
  }

  void _onData(List<int> data) {
    _buf.addAll(data);
    while (true) {
      final i = _headerEnd();
      if (i < 0) return;
      final header = ascii.decode(_buf.sublist(0, i), allowInvalid: true);
      final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
      if (m == null) {
        _buf.removeRange(0, i + 4);
        continue;
      }
      final len = int.parse(m.group(1)!);
      if (_buf.length < i + 4 + len) return;
      final body = utf8.decode(_buf.sublist(i + 4, i + 4 + len), allowMalformed: true);
      _buf.removeRange(0, i + 4 + len);
      try {
        _handle(jsonDecode(body) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void _handle(Map<String, dynamic> msg) {
    final method = msg['method'];
    if (method == null && msg['id'] is int) {
      final c = _pending.remove(msg['id']);
      if (c != null && !c.isCompleted) c.complete(msg['error'] != null ? null : msg['result']);
      return;
    }
    if (method == 'textDocument/publishDiagnostics') {
      final prm = msg['params'] as Map;
      onDiagnostics(prm['uri'] as String, (prm['diagnostics'] as List?) ?? []);
      return;
    }
    if (method == 'workspace/applyEdit' && msg.containsKey('id')) {
      final edit = (msg['params']?['edit'] as Map?) ?? {};
      onApplyEdit(edit).then((ok) => _send({'jsonrpc': '2.0', 'id': msg['id'], 'result': {'applied': ok}}));
      return;
    }
    if (method != null && msg.containsKey('id')) {
      // petición del servidor (registerCapability, progress, configuration…)
      dynamic result;
      if (method == 'workspace/configuration') {
        final items = (msg['params']?['items'] as List?) ?? [];
        result = items.map((_) => null).toList();
      }
      _send({'jsonrpc': '2.0', 'id': msg['id'], 'result': result});
    }
  }

  // ---- documentos ----
  Future<void> open(String path, String text, int version) async {
    if (!await ready) return;
    _notify('textDocument/didOpen', {
      'textDocument': {'uri': _uri(path), 'languageId': 'dart', 'version': version, 'text': text}
    });
  }

  Future<void> change(String path, String text, int version) async {
    if (!await ready) return;
    _notify('textDocument/didChange', {
      'textDocument': {'uri': _uri(path), 'version': version},
      'contentChanges': [{'text': text}],
    });
  }

  Future<void> save(String path) async {
    if (!await ready) return;
    _notify('textDocument/didSave', {'textDocument': {'uri': _uri(path)}});
  }

  Future<void> close(String path) async {
    if (!await ready) return;
    _notify('textDocument/didClose', {'textDocument': {'uri': _uri(path)}});
  }

  Map _pos(String path, int l, int c) => {
        'textDocument': {'uri': _uri(path)},
        'position': {'line': l, 'character': c},
      };

  Future<List<Map<String, dynamic>>> completion(String path, int l, int c) async {
    if (!await ready) return [];
    final r = await _request('textDocument/completion', _pos(path, l, c));
    final items = (r is Map ? r['items'] : r) as List? ?? [];
    return [
      for (final i in items.take(120))
        {
          'label': '${i['label']}',
          'kind': i['kind'] ?? 1,
          'insertText': '${i['textEdit']?['newText'] ?? i['insertText'] ?? i['label']}',
          'detail': '${i['detail'] ?? ''}',
          'sort': '${i['sortText'] ?? i['label']}',
        }
    ];
  }

  Future<String?> hover(String path, int l, int c) async {
    if (!await ready) return null;
    final r = await _request('textDocument/hover', _pos(path, l, c));
    if (r == null) return null;
    final c0 = r['contents'];
    String s(dynamic x) => x is Map ? '${x['value'] ?? ''}' : '$x';
    return c0 is List ? c0.map(s).join('\n\n') : s(c0);
  }

  Future<({String path, int line, int col})?> definition(String path, int l, int c) async {
    if (!await ready) return null;
    var r = await _request('textDocument/definition', _pos(path, l, c));
    if (r is List) r = r.isEmpty ? null : r.first;
    if (r is! Map) return null;
    final uri = (r['uri'] ?? r['targetUri']) as String?;
    final range = (r['range'] ?? r['targetSelectionRange']) as Map?;
    if (uri == null || range == null) return null;
    return (path: Uri.parse(uri).toFilePath(), line: range['start']['line'] as int, col: range['start']['character'] as int);
  }

  Future<Map<String, dynamic>?> signatureHelp(String path, int l, int c) async {
    if (!await ready) return null;
    final r = await _request('textDocument/signatureHelp', _pos(path, l, c));
    if (r is! Map) return null;
    String doc(dynamic d) => d == null ? '' : (d is Map ? '${d['value'] ?? ''}' : '$d');
    final sigs = <Map<String, dynamic>>[];
    for (final sg in (r['signatures'] as List? ?? [])) {
      if (sg is! Map) continue;
      sigs.add({
        'label': '${sg['label']}',
        'doc': doc(sg['documentation']),
        'params': [
          for (final pr in (sg['parameters'] as List? ?? []))
            if (pr is Map) {'label': pr['label'], 'doc': doc(pr['documentation'])}
        ],
        'active': sg['activeParameter'],
      });
    }
    if (sigs.isEmpty) return null;
    return {'signatures': sigs, 'activeSignature': r['activeSignature'] ?? 0, 'activeParameter': r['activeParameter'] ?? 0};
  }

  Future<List<Map<String, dynamic>>> codeActions(String path, Map range, {List<String>? only}) async {
    if (!await ready) return [];
    final r = await _request('textDocument/codeAction', {
      'textDocument': {'uri': _uri(path)},
      'range': range,
      'context': {'diagnostics': [], if (only != null) 'only': only},
    });
    return [for (final a in ((r as List?) ?? [])) if (a is Map) Map<String, dynamic>.from(a)];
  }

  Future<dynamic> executeCommand(String cmd, List args) => _request('workspace/executeCommand', {'command': cmd, 'arguments': args}, seconds: 30);

  Future<Map?> rename(String path, int l, int c, String name) async {
    if (!await ready) return null;
    final r = await _request('textDocument/rename', {..._pos(path, l, c), 'newName': name}, seconds: 30);
    return r is Map ? r : null;
  }

  Future<List<Map<String, dynamic>>> references(String path, int l, int c) async {
    if (!await ready) return [];
    final r = await _request('textDocument/references', {..._pos(path, l, c), 'context': {'includeDeclaration': true}}, seconds: 20);
    return [
      for (final x in ((r as List?) ?? []))
        if (x is Map) {'path': Uri.parse(x['uri'] as String).toFilePath(), 'line': x['range']['start']['line'], 'col': x['range']['start']['character']}
    ];
  }

  Future<List<Map<String, dynamic>>> symbols(String path) async {
    if (!await ready) return [];
    final r = await _request('textDocument/documentSymbol', {'textDocument': {'uri': _uri(path)}});
    final out = <Map<String, dynamic>>[];
    void walk(List l, int depth) {
      for (final s in l) {
        if (s is! Map) continue;
        final range = (s['selectionRange'] ?? s['range'] ?? s['location']?['range']) as Map?;
        out.add({'name': '${s['name']}', 'kind': s['kind'] ?? 0, 'depth': depth, 'line': range?['start']?['line'] ?? 0, 'col': range?['start']?['character'] ?? 0});
        if (s['children'] is List) walk(s['children'] as List, depth + 1);
      }
    }

    if (r is List) walk(r, 0);
    return out;
  }

  void dispose() {
    _p?.kill();
    _p = null;
  }
}
