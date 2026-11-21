import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cliente mínimo del Dart VM Service (JSON-RPC por WebSocket) para el inspector y las herramientas de Flutter.
class VmService {
  WebSocket? _ws;
  int _id = 0;
  final _pending = <String, Completer<Map>>{};
  String? isolateId;
  bool get connected => _ws != null;

  Future<void> connect(String httpUri) async {
    await close();
    var u = httpUri.trim();
    if (!u.endsWith('/')) u += '/';
    final ws = '${u.replaceFirst(RegExp(r'^http'), 'ws')}ws';
    final sock = await WebSocket.connect(ws).timeout(const Duration(seconds: 6));
    _ws = sock;
    sock.listen(_onMsg, onDone: () {
      _ws = null;
      isolateId = null;
    }, onError: (_) {
      _ws = null;
    });
  }

  void _onMsg(dynamic data) {
    try {
      final m = jsonDecode(data as String) as Map;
      final c = _pending.remove('${m['id']}');
      if (c != null && !c.isCompleted) c.complete(m);
    } catch (_) {}
  }

  Future<Map> call(String method, [Map<String, dynamic>? params]) async {
    final ws = _ws;
    if (ws == null) throw 'Sin conexión con el VM Service de la app.';
    final id = '${++_id}';
    final c = Completer<Map>();
    _pending[id] = c;
    ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params ?? {}}));
    final m = await c.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(id);
      throw 'Tiempo de espera agotado ($method).';
    });
    if (m['error'] != null) throw '${(m['error'] as Map)['message'] ?? m['error']}';
    return (m['result'] as Map?) ?? {};
  }

  Future<String> findIsolate() async {
    final vm = await call('getVM');
    for (final i in (vm['isolates'] as List? ?? [])) {
      final iso = await call('getIsolate', {'isolateId': i['id']});
      final rpcs = (iso['extensionRPCs'] as List? ?? []).map((e) => '$e');
      if (rpcs.any((e) => e.startsWith('ext.flutter.inspector'))) return isolateId = '${i['id']}';
    }
    throw 'No se encontró el isolate de Flutter (¿la app ya terminó de arrancar?).';
  }

  /// Llama a una extensión de servicio (ext.flutter.*) y devuelve su resultado.
  Future<dynamic> ext(String method, [Map<String, dynamic>? args]) async {
    final iso = isolateId ?? await findIsolate();
    final r = await call(method, {'isolateId': iso, ...?args});
    return (r['type'] == '_extensionType' && r.containsKey('result')) ? r['result'] : r;
  }

  Future<void> close() async {
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    isolateId = null;
    _pending.clear();
  }
}
