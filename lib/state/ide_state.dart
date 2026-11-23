import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Brightness;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dap.dart';
import '../services/terminal_session.dart';
import '../services/test_runner.dart';
import '../app_info.dart';
import '../services/lsp.dart';
import '../services/updater.dart';
import '../services/app_log.dart';
import '../services/vm_service.dart';
import '../services/merge_conflicts.dart';
import '../services/monaco_local.dart';
import '../theme/ide_theme.dart';

const kHidden = {'.dart_tool', 'build', '.git', '.idea', '.gradle', 'Pods', 'node_modules'};
const _binExt = {'png', 'jpg', 'jpeg', 'gif', 'ico', 'webp', 'ttf', 'otf', 'woff', 'woff2', 'zip', 'jar', 'exe', 'dll', 'so', 'dylib', 'class', 'pdf', 'mp3', 'mp4', 'keystore'};

const _imgExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'};

String norm(String path) => Platform.isWindows ? p.normalize(path).toLowerCase() : p.normalize(path);

class OpenDoc {
  OpenDoc(this.path, this.content);
  final String path;
  String content;
  bool dirty = false;
  int version = 1;
  bool isImage = false;
  String get name => p.basename(path);
}

class Device {
  Device(this.id, this.name);
  final String id, name;
}

class Diag {
  Diag(this.path, this.line, this.col, this.endLine, this.endCol, this.severity, this.message, this.code);
  final String path, message, code;
  final int line, col, endLine, endCol, severity;
}

class SearchHit {
  SearchHit(this.path, this.line, this.text);
  final String path, text;
  final int line;
}

class GitChange {
  GitChange(this.x, this.y, this.path);
  final String x, y, path;
  bool get untracked => x == '?';
  bool get conflicted => x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D');
  bool get staged => !conflicted && x != ' ' && x != '?';
  bool get unstaged => !conflicted && (y != ' ' || untracked);
  String get label => untracked ? 'U' : (y != ' ' ? y : x);
}

class DbgFrame {
  DbgFrame(this.id, this.name, this.path, this.line, this.col);
  final int id, line, col;
  final String name;
  final String? path;
}

class DbgScope {
  DbgScope(this.name, this.ref, this.expensive);
  final String name;
  final int ref;
  final bool expensive;
}

class DbgVar {
  DbgVar(this.name, this.value, this.type, this.ref);
  final String name, value, type;
  final int ref;
  bool expanded = false;
}

class Emu {
  Emu(this.id, this.name, this.platform);
  final String id, name, platform;
}

class RunConfig {
  RunConfig({this.name = 'Predeterminada', this.mode = 'debug', this.target = '', this.flavor = '', this.defines = '', this.extra = ''});
  String name, mode, target, flavor, defines, extra;
  Map<String, dynamic> toJson() => {'name': name, 'mode': mode, 'target': target, 'flavor': flavor, 'defines': defines, 'extra': extra};
  factory RunConfig.fromJson(Map j) => RunConfig(name: j['name'] ?? 'Predeterminada', mode: j['mode'] ?? 'debug', target: j['target'] ?? '', flavor: j['flavor'] ?? '', defines: j['defines'] ?? '', extra: j['extra'] ?? '');
  List<String> args(bool flutter, String? deviceId, {String? override}) {
    final tgt = override ?? target;
    final ex = extra.trim().isEmpty ? <String>[] : extra.trim().split(RegExp(r'\s+'));
    if (!flutter) return ['run', if (tgt.isNotEmpty) tgt, ...ex];
    return [
      'run',
      if (deviceId != null) ...['-d', deviceId],
      if (mode != 'debug') '--$mode',
      if (tgt.isNotEmpty) ...['-t', tgt],
      if (flavor.isNotEmpty) ...['--flavor', flavor],
      for (final l in defines.split('\n')) if (l.trim().isNotEmpty) '--dart-define=${l.trim()}',
      ...ex,
    ];
  }
}

class IdeState extends ChangeNotifier {
  SharedPreferences? _prefs;
  Process? _task;
  String taskName = '';
  String? devToolsUrl;
  double fontSize = 14;
  bool minimap = true, wordWrap = false, autoSave = false, formatOnSave = false, autoPubGet = true;
  String fontFamily = '';
  bool fontLigatures = false;
  int tabSize = 2;
  int settingsRev = 0, saveRev = 0;
  Timer? _autoTimer;
  final dirtyRev = ValueNotifier<int>(0);
  Future<bool> Function()? confirmDiscard;
  bool get hasDirty => docs.any((d) => d.dirty);
  final themeNotifier = ValueNotifier<IdeTheme>(IdeTheme.all.first);
  IdeTheme get theme => themeNotifier.value;

  String? root;
  String? lastDir;
  List<String> recents = [];
  final docs = <OpenDoc>[];
  int active = -1;
  final log = <String>[];
  final logRev = ValueNotifier<int>(0);
  final diagRev = ValueNotifier<int>(0);
  final expanded = <String>{};
  List<Device> devices = [];
  Device? device;
  Process? _running;
  LspClient? _lsp;
  String lspStatus = '';
  final diags = <String, List<Diag>>{};
  ({String path, int line, int col})? reveal;
  bool gitRepo = false;
  String gitBranch = '';
  List<GitChange> gitChanges = [];

  void Function(String path, List<Diag> list)? onMarkers;
  void Function(String path)? onDocClosed;
  void Function(String path, String text)? onExternalChange;
  StreamSubscription? _watchSub;
  Timer? _watchTimer, _diagTimer, _gitTimer;
  String _gitSig = '';

  bool get isRunning => _running != null || _dap != null;
  OpenDoc? get current => active >= 0 && active < docs.length ? docs[active] : null;
  bool? _flutterCache;
  String? _flutterKey;
  int _flutterAt = 0;

  /// ¿El proyecto abierto es Flutter? (con caché de 3 s: antes leía el archivo en cada redibujado)
  bool get isFlutter {
    final r = root;
    if (r == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_flutterCache != null && _flutterKey == r && now - _flutterAt < 3000) return _flutterCache!;
    var v = false;
    try {
      v = File(p.join(r, 'pubspec.yaml')).readAsStringSync().contains(RegExp(r'sdk:\s*flutter'));
    } catch (_) {}
    _flutterCache = v;
    _flutterKey = r;
    _flutterAt = now;
    return v;
  }

  String get _tool => isFlutter ? 'flutter' : 'dart';
  bool _isDart(String path) => path.endsWith('.dart');
  OpenDoc? _doc(String path) {
    final k = norm(path);
    for (final d in docs) {
      if (norm(d.path) == k) return d;
    }
    return null;
  }

  void _add(String l) {
    log.add(l);
    if (log.length > 5000) log.removeRange(0, 1000);
    logRev.value++;
  }

  void clearLog() {
    log.clear();
    logRev.value++;
  }

  void Function(String msg)? onToast;
  void info(String m) {
    _add(m);
    if (!m.contains('\n') && m.length < 160) onToast?.call(m);
  }
  int fsRev = 0;
  final _dirCache = <String, ({DateTime m, int rev, List<FileSystemEntity> items})>{};

  /// Lista un directorio con caché (se invalida si cambia su fecha de modificación o al refrescar).
  List<FileSystemEntity> listDir(String dir) {
    DateTime m;
    try {
      m = Directory(dir).statSync().modified;
    } catch (_) {
      return const [];
    }
    final c = _dirCache[dir];
    if (c != null && c.m == m && c.rev == fsRev) return c.items;
    List<FileSystemEntity> items;
    try {
      items = Directory(dir).listSync()
        ..sort((a, b) {
          final ad = a is Directory, bd = b is Directory;
          if (ad != bd) return ad ? -1 : 1;
          return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
        });
    } catch (_) {
      items = const [];
    }
    _dirCache[dir] = (m: m, rev: fsRev, items: items);
    return items;
  }

  void refresh() {
    fsRev++;
    notifyListeners();
  }

  // ---------- Persistencia ----------
  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    themeNotifier.value = IdeTheme.byId(_prefs!.getString('theme'));
    recents = _prefs!.getStringList('recents') ?? [];
    lastDir = _prefs!.getString('lastDir');
    fontSize = _prefs!.getDouble('fontSize') ?? 14;
    minimap = _prefs!.getBool('minimap') ?? true;
    wordWrap = _prefs!.getBool('wordWrap') ?? false;
    autoSave = _prefs!.getBool('autoSave') ?? false;
    formatOnSave = _prefs!.getBool('formatOnSave') ?? false;
    autoPubGet = _prefs!.getBool('autoPubGet') ?? true;
    autoCheckUpdates = _prefs!.getBool('autoCheckUpdates') ?? true;
    betaChannel = _prefs!.getBool('betaChannel') ?? false;
    skippedVersion = _prefs!.getString('skippedVersion') ?? '';
    lastUpdateCheck = _prefs!.getInt('lastUpdateCheck') ?? 0;
    fontFamily = _prefs!.getString('fontFamily') ?? '';
    fontLigatures = _prefs!.getBool('fontLigatures') ?? false;
    tabSize = _prefs!.getInt('tabSize') ?? 2;
    followSystem = _prefs!.getBool('followSystem') ?? false;
    lightThemeId = _prefs!.getString('lightThemeId') ?? 'light';
    darkThemeId = _prefs!.getString('darkThemeId') ?? 'dark';
    lastSeenVersion = _prefs!.getString('lastSeenVersion') ?? '';
    _loadSnippets();
    final r = _prefs!.getString('root');
    if (r != null && Directory(r).existsSync()) await openProject(r, restoreTabs: true);
    if (terminals.isEmpty) addTerminal();
    _scanRecovery();
    applySystemTheme();
    await initMonaco();
    if (autoCheckUpdates && DateTime.now().millisecondsSinceEpoch - lastUpdateCheck > 20 * 3600 * 1000) {
      checkForUpdates(silent: true);
    }
  }

  void setLastDir(String d) {
    lastDir = d;
    _prefs?.setString('lastDir', d);
  }

  void setTheme(IdeTheme t) {
    themeNotifier.value = t;
    _prefs?.setString('theme', t.id);
    notifyListeners();
  }

  void _persistTabs() {
    _prefs?.setStringList('open', docs.map((d) => d.path).toList());
    _prefs?.setInt('active', active);
  }

  // ---------- Proyecto ----------
  Future<void> openProject(String dir, {bool restoreTabs = false}) async {
    if (hasDirty && !(await (confirmDiscard?.call() ?? Future.value(true)))) return;
    await _closeInternal();
    root = dir;
    expanded
      ..clear()
      ..add(dir);
    _prefs?.setString('root', dir);
    _loadRunConfig();
    _loadBps();
    _syncTerminals(dir);
    _loadTasks();
    recents = [dir, ...recents.where((e) => e != dir)].take(8).toList();
    _prefs?.setStringList('recents', recents);
    _add('Proyecto abierto: $dir');
    _startWatch();
    _startLsp();
    if (restoreTabs) {
      for (final f in _prefs?.getStringList('open') ?? <String>[]) {
        if (File(f).existsSync()) _addDoc(f);
      }
      active = docs.isEmpty ? -1 : math.min(_prefs?.getInt('active') ?? 0, docs.length - 1);
    }
    notifyListeners();
    refreshDevices();
    refreshEmulators();
    refreshGit();
  }

  Future<void> _closeInternal() async {
    if (_running != null) stop();
    if (_task != null) stopTask();
    if (_dap != null) _dapCleanup(kill: true);
    testRunner.stop();
    testRunner.clear();
    _watchSub?.cancel();
    _watchSub = null;
    _lsp?.dispose();
    _lsp = null;
    lspStatus = '';
    for (final d in docs) {
      _clearRecovery(d.path);
      onDocClosed?.call(d.path);
    }
    docs.clear();
    active = -1;
    diags.clear();
    diagRev.value++;
    gitRepo = false;
    gitBranch = '';
    gitChanges = [];
  }

  Future<void> closeProject() async {
    if (hasDirty && !(await (confirmDiscard?.call() ?? Future.value(true)))) return;
    await _closeInternal();
    root = null;
    await _prefs?.remove('root');
    await _prefs?.remove('open');
    _add('Proyecto cerrado');
    notifyListeners();
  }

  void collapseAll() {
    expanded
      ..clear()
      ..add(root!);
    notifyListeners();
  }

  void toggleDir(String d) {
    expanded.contains(d) ? expanded.remove(d) : expanded.add(d);
    notifyListeners();
  }

  void _startWatch() {
    try {
      _watchSub = Directory(root!).watch(recursive: true).listen((e) {
        try {
          if (p.split(p.relative(e.path, from: root!)).any(kHidden.contains)) return;
        } catch (_) {}
        if (e.type == FileSystemEvent.modify) {
          // cambios de contenido: solo actualiza Git (no reconstruye toda la interfaz)
          _gitTimer?.cancel();
          _gitTimer = Timer(const Duration(milliseconds: 1500), refreshGit);
          return;
        }
        _watchTimer?.cancel();
        _watchTimer = Timer(const Duration(milliseconds: 600), () {
          fsRev++;
          notifyListeners();
          refreshGit();
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  // ---------- LSP ----------
  void _startLsp() {
    lspStatus = 'Dart: iniciando…';
    final c = LspClient(_onDiag, applyWorkspaceEdit);
    _lsp = c;
    c.start(root!).then((_) {
      if (_lsp != c) return;
      lspStatus = c.alive ? 'Dart ✓' : 'Dart: sin servidor';
      notifyListeners();
    });
  }

  void _onDiag(String uri, List raw) {
    String path;
    try {
      path = Uri.parse(uri).toFilePath();
    } catch (_) {
      return;
    }
    final list = <Diag>[
      for (final d in raw)
        Diag(path, d['range']['start']['line'], d['range']['start']['character'], d['range']['end']['line'],
            d['range']['end']['character'], d['severity'] ?? 1, '${d['message'] ?? ''}', '${d['code'] ?? ''}')
    ];
    final k = norm(path);
    list.isEmpty ? diags.remove(k) : diags[k] = list;
    final doc = _doc(path);
    if (doc != null) onMarkers?.call(doc.path, list);
    _diagTimer?.cancel();
    _diagTimer = Timer(const Duration(milliseconds: 200), () => diagRev.value++);
  }

  Future<List<Map<String, dynamic>>> lspCompletion(String path, int l, int c) async => await _lsp?.completion(path, l, c) ?? [];
  Future<String?> lspHover(String path, int l, int c) async => await _lsp?.hover(path, l, c);
  Future<void> lspDefinition(String path, int l, int c) async {
    final r = await _lsp?.definition(path, l, c);
    if (r == null) {
      _add('Definición no encontrada');
      return;
    }
    openFile(r.path, line: r.line + 1, col: r.col + 1);
  }

  // ---------- Documentos ----------
  bool _addDoc(String path) {
    if (_imgExt.contains(p.extension(path).replaceFirst('.', '').toLowerCase())) {
      docs.add(OpenDoc(path, '')..isImage = true);
      return true;
    }
    try {
      final d = OpenDoc(path, File(path).readAsStringSync());
      docs.add(d);
      if (_isDart(path)) _lsp?.open(path, d.content, d.version);
      return true;
    } catch (_) {
      _add('No se puede abrir (¿binario?): $path');
      return false;
    }
  }

  void openFile(String path, {int? line, int? col}) {
    final existing = _doc(path);
    if (existing != null) {
      active = docs.indexOf(existing);
    } else if (_addDoc(path)) {
      active = docs.length - 1;
    }
    if (line != null && current != null) reveal = (path: current!.path, line: line, col: col ?? 1);
    _persistTabs();
    notifyListeners();
  }

  void setActive(int i) {
    active = i;
    _persistTabs();
    notifyListeners();
  }

  void closeDoc(int i) {
    final d = docs.removeAt(i);
    _clearRecovery(d.path);
    onDocClosed?.call(d.path);
    if (_isDart(d.path)) _lsp?.close(d.path);
    if (active >= docs.length) active = docs.length - 1;
    _persistTabs();
    notifyListeners();
  }

  void markDirty(String path) {
    final d = _doc(path);
    if (d != null && !d.dirty) {
      d.dirty = true;
      dirtyRev.value++;
    }
  }

  void onEdit(String path, String text) {
    final d = _doc(path);
    if (d == null) return;
    d.content = text;
    d.version++;
    if (_isDart(path)) _lsp?.change(path, text, d.version);
    if (!d.dirty) {
      d.dirty = true;
      dirtyRev.value++;
    }
    _scheduleRecovery(d);
    if (autoSave) {
      _autoTimer?.cancel();
      _autoTimer = Timer(const Duration(milliseconds: 900), () {
        final dd = _doc(path);
        if (dd != null && dd.dirty) saveDoc(dd);
      });
    }
  }

  void reloadDoc(String path, String text) {
    final d = _doc(path);
    if (d == null) return;
    d.content = text;
    d.dirty = false;
    d.version++;
    if (_isDart(path)) _lsp?.change(d.path, text, d.version);
    onExternalChange?.call(d.path, text);
    notifyListeners();
  }

  Future<void> saveDoc(OpenDoc d) async {
    if (d.isImage) return;
    await File(d.path).writeAsString(d.content);
    d.dirty = false;
    _clearRecovery(d.path);
    if (formatOnSave && _isDart(d.path)) {
      try {
        final r = await Process.run('dart', ['format', d.path], runInShell: true);
        if (r.exitCode == 0) {
          final t = File(d.path).readAsStringSync();
          if (t != d.content) reloadDoc(d.path, t);
        }
      } catch (_) {}
    }
    if (_isDart(d.path)) _lsp?.save(d.path);
    saveRev++;
    refreshGutter(d.path);
    notifyListeners();
    if (isRunning && _isDart(d.path)) hotReload();
    if (autoPubGet && p.basename(d.path) == 'pubspec.yaml' && root != null) pubGet();
  }

  Future<void> save() async {
    final d = current;
    if (d != null) await saveDoc(d);
  }

  Future<void> saveAll() async {
    for (final d in docs.where((d) => d.dirty)) {
      await File(d.path).writeAsString(d.content);
      d.dirty = false;
      _clearRecovery(d.path);
    }
    notifyListeners();
  }

  Future<void> formatCurrent() async {
    final d = current;
    if (d == null || !_isDart(d.path)) return;
    await File(d.path).writeAsString(d.content);
    final code = await execArgs('dart', ['format', d.path]);
    if (code == 0) reloadDoc(d.path, File(d.path).readAsStringSync());
  }

  // ---------- Operaciones de archivos ----------
  Future<void> createFile(String dir, String name) async {
    try {
      final f = File(p.join(dir, name));
      await f.create(recursive: true);
      expanded.add(dir);
      openFile(f.path);
    } catch (e) {
      _add('Error creando archivo: $e');
    }
  }

  Future<void> createDir(String dir, String name) async {
    try {
      final d = Directory(p.join(dir, name));
      await d.create(recursive: true);
      expanded..add(dir)..add(d.path);
      notifyListeners();
    } catch (e) {
      _add('Error creando carpeta: $e');
    }
  }

  List<OpenDoc> _under(String path) => docs.where((d) => norm(d.path) == norm(path) || p.isWithin(path, d.path)).toList();

  Future<void> renameEntity(String path, String newName) async {
    try {
      final np = p.join(p.dirname(path), newName);
      final affected = _under(path).map((d) => d.path).toList();
      for (final a in affected) {
        closeDoc(docs.indexOf(_doc(a)!));
      }
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).rename(np);
      } else {
        await File(path).rename(np);
      }
      for (final a in affected) {
        openFile(p.join(np, p.relative(a, from: path) == '.' ? '' : p.relative(a, from: path)));
      }
      notifyListeners();
    } catch (e) {
      _add('Error renombrando: $e');
    }
  }

  Future<void> deleteEntity(String path) async {
    try {
      for (final a in _under(path).map((d) => d.path).toList()) {
        closeDoc(docs.indexOf(_doc(a)!));
      }
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      notifyListeners();
    } catch (e) {
      _add('Error eliminando: $e');
    }
  }

  // ---------- Búsqueda ----------
  Stream<File> _files(String dir, {bool all = false}) async* {
    await for (final e in Directory(dir).list(followLinks: false)) {
      final n = p.basename(e.path);
      if (kHidden.contains(n)) continue;
      if (e is Directory) {
        yield* _files(e.path, all: all);
      } else if (e is File && (all || !_binExt.contains(p.extension(n).replaceFirst('.', '').toLowerCase()))) {
        yield e;
      }
    }
  }

  RegExp _re(String q, bool cs, bool rx, bool ww) {
    var src = rx ? q : RegExp.escape(q);
    if (ww) src = '\\b(?:$src)\\b';
    return RegExp(src, caseSensitive: cs);
  }

  Future<List<SearchHit>> search(String q, {bool caseSensitive = false, bool regex = false, bool whole = false, String include = '', String exclude = ''}) async {
    if (root == null) return [];
    final re = _re(q, caseSensitive, regex, whole);
    final out = <SearchHit>[];
    var n = 0;
    final inc = _globs(include), exc = _globs(exclude);
    await for (final f in _files(root!)) {
      if (!_passes(f.path, inc, exc)) continue;
      try {
        if (f.lengthSync() > 1500000) continue;
        final lines = const LineSplitter().convert(await f.readAsString());
        for (var i = 0; i < lines.length; i++) {
          if (re.hasMatch(lines[i])) {
            out.add(SearchHit(f.path, i + 1, lines[i].trim()));
            if (out.length >= 2000) return out;
          }
        }
      } catch (_) {}
      if (++n % 20 == 0) await Future.delayed(Duration.zero);
    }
    return out;
  }

  Future<int> replaceAll(String q, String repl, {bool caseSensitive = false, bool regex = false, bool whole = false, String include = '', String exclude = ''}) async {
    if (root == null) return 0;
    final re = _re(q, caseSensitive, regex, whole);
    var files = 0;
    final inc = _globs(include), exc = _globs(exclude);
    await for (final f in _files(root!)) {
      if (!_passes(f.path, inc, exc)) continue;
      try {
        if (f.lengthSync() > 1500000) continue;
        final src = await f.readAsString();
        if (!re.hasMatch(src)) continue;
        final out = src.replaceAllMapped(re, (m) => regex ? repl.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g[1]!)) ?? '') : repl);
        await f.writeAsString(out);
        files++;
        if (_doc(f.path) != null) reloadDoc(f.path, out);
      } catch (_) {}
    }
    return files;
  }

  // ---------- Git ----------
  Future<ProcessResult?> _git(List<String> args) async {
    if (root == null) return null;
    try {
      return await Process.run('git', args, workingDirectory: root, stdoutEncoding: const Utf8Codec(allowMalformed: true), stderrEncoding: const Utf8Codec(allowMalformed: true));
    } catch (e) {
      _add('git no disponible: $e');
      return null;
    }
  }

  Future<void> refreshGit() async {
    final r = await _git(['status', '--porcelain=v1', '-b']);
    if (r == null || r.exitCode != 0) {
      gitRepo = false;
      gitBranch = '';
      gitChanges = [];
      notifyListeners();
      return;
    }
    gitRepo = true;
    gitMerging = root != null && File(p.join(root!, '.git', 'MERGE_HEAD')).existsSync();
    final ch = <GitChange>[];
    for (final l in const LineSplitter().convert(r.stdout as String)) {
      if (l.startsWith('## ')) {
        var b = l.substring(3);
        if (b.startsWith('No commits yet on ')) b = b.substring(18);
        gitBranch = b.split('...').first.split(' ').first;
        continue;
      }
      if (l.length < 4) continue;
      var path = l.substring(3);
      if (path.contains(' -> ')) path = path.split(' -> ').last;
      ch.add(GitChange(l[0], l[1], path.replaceAll('"', '')));
    }
    final sig = '$gitBranch|$gitMerging|${ch.map((x) => '${x.x}${x.y}${x.path}').join(';')}';
    gitChanges = ch;
    if (sig != _gitSig) {
      _gitSig = sig;
      notifyListeners();
      for (final d in docs.take(12)) {
        refreshGutter(d.path);
      }
    }
  }

  Future<void> gitRun(List<String> args) async {
    _add('\$ git ${args.join(' ')}');
    final r = await _git(args);
    if (r != null) {
      for (final l in const LineSplitter().convert('${r.stdout}${r.stderr}')) {
        if (l.trim().isNotEmpty) _add(l);
      }
    }
    await refreshGit();
  }

  Future<void> gitStage(String path) => gitRun(['add', '--', path]);
  Future<void> gitUnstage(String path) => gitRun(['restore', '--staged', '--', path]);
  Future<void> gitStageAll() => gitRun(['add', '-A']);
  Future<void> gitCommit(String msg) => gitRun(['commit', '-m', msg]);
  Future<void> gitPull() => gitRun(['pull']);
  Future<void> gitPush() => gitRun(['push']);
  Future<void> gitInit() => gitRun(['init']);
  Future<void> gitDiscard(GitChange c) async {
    if (c.untracked) {
      await deleteEntity(p.join(root!, c.path));
      await refreshGit();
    } else {
      await gitRun(['checkout', '--', c.path]);
      final d = _doc(p.join(root!, c.path));
      if (d != null) reloadDoc(d.path, File(d.path).readAsStringSync());
    }
  }

  // ---------- Comandos ----------
  void _pipe(Process proc) {
    void onLine(String l) {
      _add(l);
      final vmm = RegExp(r'Dart VM Service.*?available at:\s*(http\S+)').firstMatch(l);
      if (vmm != null) vmServiceUri = vmm.group(1);
      final m = RegExp(r'DevTools.*?available at:\s*(http\S+)').firstMatch(l);
      if (m != null) {
        devToolsUrl = m.group(1);
        notifyListeners();
      }
    }

    proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(onLine);
    proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(onLine);
  }

  /// Comando escrito por el usuario en la terminal (se interpreta con el shell).
  Future<int> exec(String cmd, {String? cwd}) async {
    _add('\$ $cmd');
    try {
      final proc = await Process.start(cmd, [], workingDirectory: cwd ?? root, runInShell: true);
      _pipe(proc);
      final code = await proc.exitCode;
      _add('[terminó con código $code]');
      onToast?.call(code == 0 ? 'Comando terminado ✓' : 'El comando terminó con código $code');
      notifyListeners();
      return code;
    } catch (e) {
      _add('Error: $e');
      return -1;
    }
  }

  /// Ejecuta con lista de argumentos (sin problemas de comillas/espacios).
  Future<int> execArgs(String exe, List<String> args, {String? cwd}) async {
    _add('\$ $exe ${args.join(' ')}');
    try {
      final proc = await Process.start(exe, args, workingDirectory: cwd ?? root, runInShell: true);
      _pipe(proc);
      final code = await proc.exitCode;
      _add('[terminó con código $code]');
      onToast?.call(code == 0 ? 'Comando terminado ✓' : 'El comando terminó con código $code');
      notifyListeners();
      return code;
    } catch (e) {
      _add('Error: $e');
      return -1;
    }
  }

  Future<void> refreshDevices() async {
    try {
      final r = await Process.run('flutter', ['devices', '--machine'], runInShell: true);
      final list = jsonDecode(r.stdout as String) as List;
      devices = [for (final d in list) Device(d['id'], d['name'])];
      device ??= devices.isNotEmpty ? devices.first : null;
      notifyListeners();
    } catch (_) {}
  }

  void selectDevice(Device? d) {
    device = d;
    notifyListeners();
  }

  Future<void> run({String? target}) async {
    if (root == null || isRunning) return;
    final args = runConfig.args(isFlutter, device?.id, override: target);
    _add('\$ $_tool ${args.join(' ')}');
    final proc = await Process.start(_tool, args, workingDirectory: root, runInShell: true);
    _running = proc;
    _pipe(proc);
    proc.exitCode.then((c) {
      _running = null;
      devToolsUrl = null;
      _vmReset();
      _add('[$_tool run terminó: $c]');
      notifyListeners();
    });
    notifyListeners();
  }

  void hotReload() {
    if (_dap != null) {
      _dap!.request('hotReload', {'reason': 'manual'});
      _add('⚡ Hot reload (depuración)');
      return;
    }
    _running?.stdin.writeln('r');
    _add('⚡ Hot reload');
  }

  void hotRestart() {
    if (_dap != null) {
      _dap!.request('hotRestart', {'reason': 'manual'});
      _add('🔄 Hot restart (depuración)');
      return;
    }
    _running?.stdin.writeln('R');
    _add('🔄 Hot restart');
  }

  void stop() {
    if (_dap != null) {
      stopDebug();
      return;
    }
    final r = _running;
    r?.stdin.writeln('q');
    Future.delayed(const Duration(seconds: 2), () {
      if (r != null && _running == r) _killTree(r);
    });
  }

  // ---------- Ajustes / ejecución / tareas ----------
  void updateSettings({double? font, bool? mm, bool? wrap, bool? auto, bool? fmt, bool? pubget, String? family, bool? lig, int? tab}) {
    autoPubGet = pubget ?? autoPubGet;
    _prefs?.setBool('autoPubGet', autoPubGet);
    fontFamily = family ?? fontFamily;
    fontLigatures = lig ?? fontLigatures;
    tabSize = tab ?? tabSize;
    _prefs?.setString('fontFamily', fontFamily);
    _prefs?.setBool('fontLigatures', fontLigatures);
    _prefs?.setInt('tabSize', tabSize);
    fontSize = font ?? fontSize;
    minimap = mm ?? minimap;
    wordWrap = wrap ?? wordWrap;
    autoSave = auto ?? autoSave;
    formatOnSave = fmt ?? formatOnSave;
    _prefs?.setDouble('fontSize', fontSize);
    _prefs?.setBool('minimap', minimap);
    _prefs?.setBool('wordWrap', wordWrap);
    _prefs?.setBool('autoSave', autoSave);
    _prefs?.setBool('formatOnSave', formatOnSave);
    settingsRev++;
    notifyListeners();
  }

  void _loadRunConfig() {
    runConfigs = [RunConfig()];
    activeRun = 0;
    try {
      final j = _prefs?.getString('runs:$root');
      if (j != null) {
        final m = jsonDecode(j) as Map;
        final list = (m['list'] as List).map((e) => RunConfig.fromJson(e as Map)).toList();
        if (list.isNotEmpty) {
          runConfigs = list;
          activeRun = ((m['active'] as num?)?.toInt() ?? 0).clamp(0, list.length - 1);
        }
      } else {
        final old = _prefs?.getString('run:$root');
        if (old != null) runConfigs = [RunConfig.fromJson(jsonDecode(old) as Map)];
      }
    } catch (_) {}
  }

  void setRunConfig(RunConfig c) {
    runConfigs[activeRun] = c;
    _saveRunConfigs();
    notifyListeners();
  }

  Future<void> _killTree(Process pr) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/pid', '${pr.pid}', '/T', '/F']);
      } else {
        pr.kill();
      }
    } catch (_) {
      pr.kill();
    }
  }

  bool get taskRunning => _task != null;

  Future<void> startTask(String name, String exe, List<String> args) async {
    if (_task != null) {
      _add('Ya hay una tarea en ejecución: $taskName');
      return;
    }
    _add('\$ $exe ${args.join(' ')}');
    try {
      final pr = await Process.start(exe, args, workingDirectory: root, runInShell: true);
      _task = pr;
      taskName = name;
      _pipe(pr);
      pr.exitCode.then((c) {
        _task = null;
        _add('[$name terminó: $c]');
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      _add('Error: $e');
    }
  }

  void stopTask() {
    final t = _task;
    if (t != null) _killTree(t);
  }

  Future<void> openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      _add('No se pudo abrir el navegador: $e');
    }
  }

  Future<void> openDevTools() async {
    if (devToolsUrl != null) {
      await openUrl(devToolsUrl!);
    } else {
      _add('Sin app en ejecución: iniciando "dart devtools"…');
      startTask('DevTools', 'dart', ['devtools']);
    }
  }

  Future<List<Map<String, dynamic>>> lspSymbols(String path) async => await _lsp?.symbols(path) ?? [];

  void openPath(String raw, int line, int col) {
    var path = raw;
    if (path.startsWith('package:')) path = 'lib/${path.replaceFirst(RegExp(r'^package:[^/]+/'), '')}';
    if (!p.isAbsolute(path) && root != null) path = p.join(root!, path);
    if (File(path).existsSync()) {
      openFile(path, line: line, col: col);
    } else {
      _add('No existe: $path');
    }
  }

  Future<List<String>> listFiles() async {
    if (root == null) return [];
    final out = <String>[];
    await for (final f in _files(root!, all: true)) {
      out.add(p.relative(f.path, from: root!));
      if (out.length > 8000) break;
    }
    return out;
  }

  Future<void> buildRunner() => execArgs('dart', ['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
  Future<void> buildRunnerWatch() => startTask('build_runner watch', 'dart', ['run', 'build_runner', 'watch', '--delete-conflicting-outputs']);
  Future<void> genL10n() => execArgs('flutter', ['gen-l10n']);
  Future<void> dartFix() => execArgs('dart', ['fix', '--apply']);
  Future<void> pubDeps() => pub(['deps']);
  Future<void> buildAppBundle() => execArgs('flutter', ['build', 'appbundle']);
  Future<void> testCurrent() async {
    final d = current;
    if (d == null || root == null) return;
    await execArgs(_tool, ['test', p.relative(d.path, from: root!)]);
  }

  // ---------- Refactors / acciones de código ----------
  String _applyEdits(String text, List edits) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) starts.add(i + 1);
    }
    int off(Map pos) {
      final l = (pos['line'] as int).clamp(0, starts.length - 1);
      return math.min(starts[l] + (pos['character'] as int), text.length);
    }

    final list = [for (final e in edits) (a: off(e['range']['start']), b: off(e['range']['end']), t: '${e['newText']}')];
    list.sort((x, y) => y.a.compareTo(x.a));
    var out = text;
    for (final e in list) {
      out = out.replaceRange(e.a, e.b, e.t);
    }
    return out;
  }

  Future<bool> applyWorkspaceEdit(Map edit) async {
    final byUri = <String, List>{};
    final ch = edit['changes'];
    if (ch is Map) ch.forEach((k, v) => byUri['$k'] = List.of(v as List));
    final dc = edit['documentChanges'];
    if (dc is List) {
      for (final x in dc) {
        if (x is Map && x['textDocument'] is Map && x['edits'] is List) {
          byUri.putIfAbsent('${x['textDocument']['uri']}', () => []).addAll(x['edits'] as List);
        }
      }
    }
    if (byUri.isEmpty) return false;
    var n = 0;
    for (final e in byUri.entries) {
      try {
        final path = Uri.parse(e.key).toFilePath();
        final doc = _doc(path);
        final text = doc?.content ?? File(path).readAsStringSync();
        final out = _applyEdits(text, e.value);
        if (doc != null) {
          reloadDoc(doc.path, out);
          doc.dirty = true;
        } else {
          File(path).writeAsStringSync(out);
        }
        n++;
      } catch (err) {
        _add('Error aplicando edición: $err');
      }
    }
    notifyListeners();
    _add('Cambios aplicados en $n archivo(s)');
    return n > 0;
  }

  Future<List<Map<String, dynamic>>> lspCodeActions(String path, int sl, int sc, int el, int ec, {List<String>? only}) async =>
      await _lsp?.codeActions(path, {'start': {'line': sl, 'character': sc}, 'end': {'line': el, 'character': ec}}, only: only) ?? [];

  Future<void> applyCodeAction(Map<String, dynamic> a) async {
    if (a['edit'] is Map) await applyWorkspaceEdit(a['edit'] as Map);
    final cmd = a['command'];
    if (cmd is Map) {
      await _lsp?.executeCommand('${cmd['command']}', (cmd['arguments'] as List?) ?? []);
    } else if (cmd is String) {
      await _lsp?.executeCommand(cmd, (a['arguments'] as List?) ?? []);
    }
  }

  Future<void> lspRename(String path, int l, int c, String name) async {
    final edit = await _lsp?.rename(path, l, c, name);
    if (edit == null) {
      _add('No se pudo renombrar ese símbolo');
      return;
    }
    await applyWorkspaceEdit(edit);
  }

  Future<List<Map<String, dynamic>>> lspReferences(String path, int l, int c) async => await _lsp?.references(path, l, c) ?? [];

  String lineText(String path, int line) {
    try {
      final lines = const LineSplitter().convert(_doc(path)?.content ?? File(path).readAsStringSync());
      final t = lines[line].trim();
      return t.length > 70 ? '${t.substring(0, 70)}…' : t;
    } catch (_) {
      return '';
    }
  }

  Future<void> _sourceAction(String kind, String emptyMsg) async {
    final d = current;
    if (d == null || !_isDart(d.path)) return;
    final n = '\n'.allMatches(d.content).length + 1;
    final acts = await lspCodeActions(d.path, 0, 0, n, 0, only: [kind]);
    if (acts.isEmpty) {
      _add(emptyMsg);
      return;
    }
    await applyCodeAction(acts.first);
  }

  Future<void> organizeImports() => _sourceAction('source.organizeImports', 'Imports ya organizados');
  Future<void> fixAllIssues() => _sourceAction('source.fixAll', 'No hay correcciones automáticas');

  // ---------- Git diff ----------
  Future<String> gitDiff(GitChange c, {bool staged = false}) async {
    if (c.untracked) {
      try {
        final lines = File(p.join(root!, c.path)).readAsLinesSync();
        return '+++ ${c.path} (archivo nuevo)\n${lines.map((l) => '+$l').join('\n')}';
      } catch (_) {
        return '(archivo nuevo)';
      }
    }
    final r = await _git(['diff', if (staged) '--staged', '--', c.path]);
    final out = '${r?.stdout ?? ''}'.trim();
    return out.isEmpty ? '(sin diferencias)' : out;
  }

  // ---------- Plantillas Flutter / assets ----------
  String _pascal(String snake) => snake.split('_').where((e) => e.isNotEmpty).map((e) => e[0].toUpperCase() + e.substring(1)).join();

  String _template(String kind, String name) {
    final c = _pascal(name);
    switch (kind) {
      case 'stateless':
        return "import 'package:flutter/material.dart';\n\nclass $c extends StatelessWidget {\n  const $c({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return const Placeholder();\n  }\n}\n";
      case 'stateful':
        return "import 'package:flutter/material.dart';\n\nclass $c extends StatefulWidget {\n  const $c({super.key});\n\n  @override\n  State<$c> createState() => _${c}State();\n}\n\nclass _${c}State extends State<$c> {\n  @override\n  Widget build(BuildContext context) {\n    return const Placeholder();\n  }\n}\n";
      case 'screen':
        return "import 'package:flutter/material.dart';\n\nclass $c extends StatelessWidget {\n  const $c({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      appBar: AppBar(title: const Text('$c')),\n      body: const Center(child: Text('$c')),\n    );\n  }\n}\n";
      case 'model':
        return "class $c {\n  const $c({required this.id});\n\n  final String id;\n\n  $c copyWith({String? id}) => $c(id: id ?? this.id);\n}\n";
      case 'notifier':
        return "import 'package:flutter/foundation.dart';\n\nclass $c extends ChangeNotifier {\n  int _count = 0;\n  int get count => _count;\n\n  void increment() {\n    _count++;\n    notifyListeners();\n  }\n}\n";
      case 'test':
        return "import 'package:flutter_test/flutter_test.dart';\n\nvoid main() {\n  test('$name', () {\n    expect(1 + 1, 2);\n  });\n}\n";
      default:
        return '';
    }
  }

  Future<void> createFromTemplate(String dir, String kind, String raw) async {
    var name = raw.trim().toLowerCase().replaceAll(RegExp(r'\.dart$'), '').replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (name.isEmpty) return;
    if (kind == 'test' && !name.endsWith('_test')) name = '${name}_test';
    final f = File(p.join(dir, '$name.dart'));
    if (f.existsSync()) {
      _add('Ya existe: ${f.path}');
      return;
    }
    await f.create(recursive: true);
    await f.writeAsString(_template(kind, name));
    expanded.add(dir);
    openFile(f.path);
  }

  Future<void> addAssetFolder(String dirPath) async {
    if (root == null) return;
    final f = File(p.join(root!, 'pubspec.yaml'));
    if (!f.existsSync()) return;
    var rel = p.relative(dirPath, from: root!).replaceAll('\\', '/');
    if (!rel.endsWith('/')) rel += '/';
    var src = f.readAsStringSync();
    if (RegExp('^\\s*-\\s*${RegExp.escape(rel)}\\s*\$', multiLine: true).hasMatch(src)) {
      _add('Ya registrado en pubspec: $rel');
      return;
    }
    final assetsRe = RegExp(r'^  assets:\s*$', multiLine: true);
    final flutterRe = RegExp(r'^flutter:\s*$', multiLine: true);
    if (assetsRe.hasMatch(src)) {
      src = src.replaceFirstMapped(assetsRe, (m) => '  assets:\n    - $rel');
    } else if (flutterRe.hasMatch(src)) {
      src = src.replaceFirstMapped(flutterRe, (m) => 'flutter:\n  assets:\n    - $rel');
    } else {
      src = '$src\nflutter:\n  assets:\n    - $rel\n';
    }
    f.writeAsStringSync(src);
    if (_doc(f.path) != null) reloadDoc(f.path, src);
    _add('Assets registrados en pubspec.yaml: $rel (haz hot restart)');
  }

  void closeOthers(int i) {
    final keep = docs[i];
    for (final d in List.of(docs)) {
      if (d != keep && !d.dirty) closeDoc(docs.indexOf(d));
    }
  }

  void closeAllDocs() {
    for (final d in List.of(docs)) {
      if (!d.dirty) closeDoc(docs.indexOf(d));
    }
  }

  // ---------- Depurador (DAP) ----------
  final breakpoints = <String, Set<int>>{};
  final _bpPath = <String, String>{};
  DapClient? _dap;
  bool debugPaused = false;
  String debugStatus = '';
  int? _threadId;
  List<DbgFrame> frames = [];
  int selFrame = 0;
  List<DbgScope> scopes = [];
  final varCache = <int, List<DbgVar>>{};
  ({String path, int line})? debugLine;
  final watches = <String>[];
  final watchValues = <String, String>{};
  String exceptionMode = 'Unhandled';
  void Function(String path, List<int> lines)? onBreakpoints;
  void Function(String? path, int line)? onDebugLine;
  VoidCallback? onDebugStart;

  bool get debugActive => _dap != null;

  List<({String path, int line})> get breakpointList {
    final out = <({String path, int line})>[];
    for (final e in breakpoints.entries) {
      final lines = e.value.toList()..sort();
      for (final l in lines) {
        out.add((path: _bpPath[e.key] ?? e.key, line: l));
      }
    }
    out.sort((a, b) => a.path != b.path ? a.path.compareTo(b.path) : a.line.compareTo(b.line));
    return out;
  }

  void _saveBps() {
    _prefs?.setString('bp:$root', jsonEncode({for (final e in breakpoints.entries) (_bpPath[e.key] ?? e.key): e.value.toList()}));
  }

  void _loadBps() {
    breakpoints.clear();
    _bpPath.clear();
    try {
      final j = _prefs?.getString('bp:$root');
      if (j != null) {
        (jsonDecode(j) as Map).forEach((k, v) {
          final key = norm('$k');
          _bpPath[key] = '$k';
          breakpoints[key] = {for (final x in (v as List)) (x as num).toInt()};
        });
      }
    } catch (_) {}
  }

  void _pushBps(String key) {
    final path = _bpPath[key];
    if (path == null) return;
    final d = _doc(path);
    if (d != null) onBreakpoints?.call(d.path, (breakpoints[key]?.toList() ?? <int>[])..sort());
  }

  Future<void> _syncBps(String key) async {
    final dap = _dap, path = _bpPath[key];
    if (dap == null || path == null) return;
    await dap.request('setBreakpoints', {
      'source': {'path': path},
      'breakpoints': [for (final l in (breakpoints[key] ?? <int>{})) {'line': l}],
    });
  }

  void toggleBreakpoint(String path, int line) {
    final k = norm(path);
    _bpPath[k] = path;
    final set = breakpoints.putIfAbsent(k, () => <int>{});
    if (!set.remove(line)) set.add(line);
    if (set.isEmpty) breakpoints.remove(k);
    _saveBps();
    _pushBps(k);
    _syncBps(k);
    notifyListeners();
  }

  void bpsChangedFromEditor(String path, List<int> lines) {
    final k = norm(path);
    _bpPath[k] = path;
    final cur = breakpoints[k] ?? <int>{};
    final next = lines.toSet();
    if (cur.length == next.length && cur.containsAll(next)) return;
    if (next.isEmpty) {
      breakpoints.remove(k);
    } else {
      breakpoints[k] = next;
    }
    _saveBps();
    _syncBps(k);
    notifyListeners();
  }

  void clearBreakpoints() {
    final keys = breakpoints.keys.toList();
    breakpoints.clear();
    _saveBps();
    for (final k in keys) {
      _pushBps(k);
      _syncBps(k);
    }
    notifyListeners();
  }

  String _defaultTarget() {
    if (runConfig.target.isNotEmpty) return runConfig.target;
    if (isFlutter) return 'lib/main.dart';
    final bin = Directory(p.join(root!, 'bin'));
    if (bin.existsSync()) {
      final f = bin.listSync().whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
      if (f.isNotEmpty) return p.relative(f.first.path, from: root!);
    }
    return 'lib/main.dart';
  }

  Future<void> startDebug({String? target, bool test = false, String? testName}) async {
    if (root == null || isRunning) return;
    final program = p.join(root!, target ?? _defaultTarget());
    if (!File(program).existsSync()) {
      _add('No existe el archivo de entrada: $program');
      return;
    }
    final flutter = isFlutter;
    debugStatus = 'Iniciando…';
    debugPaused = false;
    _add('Iniciando depuración con "${flutter ? 'flutter' : 'dart'} debug_adapter"…');
    final dap = DapClient(onEvent: _onDapEvent, onExit: () => _dapCleanup());
    _dap = dap;
    onDebugStart?.call();
    notifyListeners();
    try {
      await dap.start(flutter ? 'flutter' : 'dart', ['debug_adapter', if (test) '--test'], root!);
    } catch (e) {
      _add('No se pudo iniciar el adaptador: $e');
      _dapCleanup();
      return;
    }
    final init = await dap.request('initialize', {
      'clientID': 'dart_ide',
      'clientName': 'Dart IDE',
      'adapterID': 'dart',
      'linesStartAt1': true,
      'columnsStartAt1': true,
      'pathFormat': 'path',
      'supportsVariableType': true,
      'supportsRunInTerminalRequest': false,
    });
    if (init['success'] != true) {
      _add('El adaptador rechazó initialize: ${init['message'] ?? ''}');
      _dapCleanup(kill: true);
      return;
    }
    final ex = runConfig.extra.trim().isEmpty ? <String>[] : runConfig.extra.trim().split(RegExp(r'\s+'));
    final app = flutter && !test;
    final toolArgs = <String>[
      if (app && device != null) ...['-d', device!.id],
      if (app && runConfig.flavor.isNotEmpty) ...['--flavor', runConfig.flavor],
      if (app) for (final l in runConfig.defines.split('\n')) if (l.trim().isNotEmpty) '--dart-define=${l.trim()}',
      if (app) ...ex,
    ];
    dap.request('launch', {
      'request': 'launch',
      'type': 'dart',
      'name': 'Dart IDE',
      'program': program,
      'cwd': root,
      'toolArgs': toolArgs,
      if (test) 'args': <String>[if (testName != null) ...['--plain-name', testName]] else if (!flutter) 'args': ex,
      'noDebug': false,
      'console': 'debugConsole',
    }, 900).then((r) {
      if (r['success'] != true && _dap == dap) {
        _add('Error al lanzar: ${r['message'] ?? 'desconocido'}');
        _dapCleanup(kill: true);
      }
    });
  }

  Future<void> _configureDebug() async {
    final dap = _dap;
    if (dap == null) return;
    for (final e in breakpoints.entries) {
      await dap.request('setBreakpoints', {
        'source': {'path': _bpPath[e.key] ?? e.key},
        'breakpoints': [for (final l in e.value) {'line': l}],
      });
    }
    await dap.request('setExceptionBreakpoints', {'filters': exceptionMode == 'None' ? <String>[] : [exceptionMode]});
    await dap.request('configurationDone');
    if (!debugPaused) debugStatus = 'En ejecución';
    notifyListeners();
  }

  Future<void> _onDapEvent(String ev, Map body) async {
    switch (ev) {
      case 'initialized':
        await _configureDebug();
      case 'output':
        if ('${body['category']}' == 'telemetry') return;
        for (final l in const LineSplitter().convert('${body['output'] ?? ''}')) {
          if (l.trim().isEmpty) continue;
          _add(l);
          final m = RegExp(r'DevTools.*?available at:\s*(http\S+)').firstMatch(l);
          if (m != null) {
            devToolsUrl = m.group(1);
            notifyListeners();
          }
        }
      case 'stopped':
        debugPaused = true;
        _threadId = (body['threadId'] as num?)?.toInt() ?? _threadId;
        debugStatus = 'Pausado (${body['reason'] ?? ''})';
        notifyListeners();
        await _loadStack();
      case 'continued':
        _markRunning();
      case 'terminated':
      case 'exited':
        _dapCleanup(kill: true);
      case 'dart.debuggerUris':
        _add('VM Service: ${body['vmServiceUri']}');
        vmServiceUri = '${body['vmServiceUri']}';
      case 'flutter.appStarted':
        if (!debugPaused) {
          debugStatus = 'En ejecución';
          notifyListeners();
        }
    }
  }

  void _markRunning() {
    debugPaused = false;
    frames = [];
    scopes = [];
    varCache.clear();
    debugLine = null;
    onDebugLine?.call(null, 0);
    if (_dap != null) debugStatus = 'En ejecución';
    notifyListeners();
  }

  Future<void> _loadStack() async {
    final dap = _dap;
    if (dap == null) return;
    if (_threadId == null) {
      final t = await dap.request('threads');
      final l = t['body']?['threads'] as List?;
      if (l != null && l.isNotEmpty) _threadId = (l.first['id'] as num).toInt();
    }
    final tid = _threadId;
    if (tid == null) return;
    final r = await dap.request('stackTrace', {'threadId': tid, 'startFrame': 0, 'levels': 40});
    final list = (r['body']?['stackFrames'] as List?) ?? [];
    frames = [
      for (final f in list)
        DbgFrame((f['id'] as num).toInt(), '${f['name']}', f['source']?['path'] as String?, (f['line'] as num?)?.toInt() ?? 0, (f['column'] as num?)?.toInt() ?? 0)
    ];
    final first = frames.indexWhere((f) => f.path != null && File(f.path!).existsSync());
    await selectFrame(first >= 0 ? first : 0);
  }

  Future<void> selectFrame(int i) async {
    if (i < 0 || i >= frames.length) return;
    selFrame = i;
    final f = frames[i];
    if (f.path != null && File(f.path!).existsSync()) {
      debugLine = (path: f.path!, line: f.line);
      openFile(f.path!, line: f.line, col: math.max(1, f.col));
      onDebugLine?.call(_doc(f.path!)?.path ?? f.path!, f.line);
    } else {
      debugLine = null;
      onDebugLine?.call(null, 0);
    }
    notifyListeners();
    final dap = _dap;
    if (dap == null) return;
    final r = await dap.request('scopes', {'frameId': f.id});
    scopes = [
      for (final sc in ((r['body']?['scopes'] as List?) ?? []))
        DbgScope('${sc['name']}', (sc['variablesReference'] as num).toInt(), sc['expensive'] == true)
    ];
    varCache.clear();
    for (final sc in scopes) {
      if (!sc.expensive) await loadVars(sc.ref);
    }
    notifyListeners();
    _refreshWatches();
  }

  Future<void> loadVars(int ref) async {
    final dap = _dap;
    if (dap == null || ref == 0) return;
    final r = await dap.request('variables', {'variablesReference': ref});
    varCache[ref] = [
      for (final v in ((r['body']?['variables'] as List?) ?? []))
        DbgVar('${v['name']}', '${v['value']}', '${v['type'] ?? ''}', (v['variablesReference'] as num?)?.toInt() ?? 0)
    ];
    notifyListeners();
  }

  Future<String> evaluate(String expr) async {
    final dap = _dap;
    if (dap == null) return 'Sin sesión de depuración activa';
    final fid = debugPaused && selFrame < frames.length ? frames[selFrame].id : null;
    final r = await dap.request('evaluate', {'expression': expr, if (fid != null) 'frameId': fid, 'context': 'repl'});
    return r['success'] == true ? '${r['body']?['result']}' : 'Error: ${r['message'] ?? 'no se pudo evaluar'}';
  }

  void addWatch(String e) {
    if (e.isEmpty || watches.contains(e)) return;
    watches.add(e);
    notifyListeners();
    _refreshWatches();
  }

  void removeWatch(String e) {
    watches.remove(e);
    watchValues.remove(e);
    notifyListeners();
  }

  Future<void> _refreshWatches() async {
    if (!debugPaused) return;
    for (final w in List.of(watches)) {
      watchValues[w] = await evaluate(w);
    }
    notifyListeners();
  }

  Future<void> _step(String cmd) async {
    final dap = _dap, tid = _threadId;
    if (dap == null || tid == null || !debugPaused) return;
    _markRunning();
    await dap.request(cmd, {'threadId': tid});
  }

  Future<void> dbgContinue() => _step('continue');
  Future<void> dbgNext() => _step('next');
  Future<void> dbgStepIn() => _step('stepIn');
  Future<void> dbgStepOut() => _step('stepOut');

  Future<void> dbgPause() async {
    final dap = _dap;
    if (dap == null) return;
    await dap.request('pause', {'threadId': _threadId ?? 1});
  }

  Future<void> stopDebug() async {
    final dap = _dap;
    if (dap == null) return;
    debugStatus = 'Deteniendo…';
    notifyListeners();
    await dap.request('disconnect', {'terminateDebuggee': true}, 6);
    _dapCleanup(kill: true);
  }

  void setExceptionMode(String m) {
    exceptionMode = m;
    _dap?.request('setExceptionBreakpoints', {'filters': m == 'None' ? <String>[] : [m]});
    notifyListeners();
  }

  void debugKey(String k) {
    switch (k) {
      case 'f5':
        if (debugActive) {
          if (debugPaused) dbgContinue();
        } else {
          startDebug();
        }
      case 'next':
        dbgNext();
      case 'in':
        dbgStepIn();
      case 'out':
        dbgStepOut();
      case 'stop':
        stopDebug();
      case 'gotest':
        toggleTestFile();
    }
  }

  void _dapCleanup({bool kill = false}) {
    final dap = _dap;
    if (dap == null) return;
    _dap = null;
    if (kill) dap.kill();
    debugPaused = false;
    debugStatus = '';
    _threadId = null;
    frames = [];
    scopes = [];
    varCache.clear();
    debugLine = null;
    devToolsUrl = null;
    _vmReset();
    onDebugLine?.call(null, 0);
    _add('[sesión de depuración terminada]');
    notifyListeners();
  }

  // ---------- Terminales / pruebas / emuladores ----------
  final terminals = <TerminalSession>[];
  int activeTerminal = 0;
  final testRunner = TestRunner();
  List<Emu> emulators = [];

  String get _homeDir => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

  TerminalSession addTerminal() {
    final t = TerminalSession('Terminal ${terminals.length + 1}', root ?? _homeDir);
    terminals.add(t);
    activeTerminal = terminals.length - 1;
    notifyListeners();
    return t;
  }

  void closeTerminal(int i) {
    if (i < 0 || i >= terminals.length) return;
    terminals[i].dispose();
    terminals.removeAt(i);
    if (activeTerminal >= terminals.length) activeTerminal = math.max(0, terminals.length - 1);
    notifyListeners();
  }

  void _syncTerminals(String dir) {
    for (final t in terminals) {
      if (t.lines.isEmpty && !t.running) t.cwd = dir;
    }
  }

  Future<void> runTests({String? file, String? name, String? namePattern, bool coverage = false}) {
    if (root == null) return Future.value();
    return testRunner.run(root: root!, flutter: isFlutter, file: file, plainName: name, namePattern: namePattern, coverage: coverage, log: _add);
  }

  Future<void> refreshEmulators() async {
    try {
      final r = await Process.run('flutter', ['emulators'], runInShell: true);
      final out = <Emu>[];
      for (final l in const LineSplitter().convert('${r.stdout}')) {
        if (!l.contains('•')) continue;
        final parts = l.split('•').map((e) => e.trim()).toList();
        if (parts.length < 3 || parts[0].toLowerCase() == 'id') continue;
        out.add(Emu(parts[0], parts[1], parts.last));
      }
      emulators = out;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> launchEmulator(Emu e) async {
    _add('Iniciando emulador ${e.name}…');
    await execArgs('flutter', ['emulators', '--launch', e.id]);
    Future.delayed(const Duration(seconds: 12), refreshDevices);
  }

  // ---------- Monaco sin conexión ----------
  final monacoServer = MonacoServer();
  String? monacoBase;
  String monacoStatus = '';
  double? monacoProgress;
  bool monacoBusy = false;
  int monacoRev = 0;
  int _lastPct = -1;

  Future<void> initMonaco() async {
    if (!monacoInstalled()) return;
    try {
      await monacoServer.start();
      monacoBase = monacoServer.base;
      monacoRev++;
      notifyListeners();
    } catch (e) {
      _add('No se pudo iniciar el servidor local de Monaco: $e');
    }
  }

  Future<void> installMonaco() async {
    if (monacoBusy) return;
    monacoBusy = true;
    monacoStatus = 'Iniciando descarga…';
    _lastPct = -1;
    notifyListeners();
    try {
      await downloadMonaco((pr, st) {
        final pct = pr == null ? -2 : (pr * 100).floor();
        if (pr != null && pct == _lastPct) return;
        _lastPct = pct;
        monacoProgress = pr;
        monacoStatus = st;
        notifyListeners();
      });
      await initMonaco();
      monacoStatus = 'Listo: editor sin conexión activado ✓';
    } catch (e) {
      monacoStatus = 'Error: $e';
    }
    monacoBusy = false;
    monacoProgress = null;
    notifyListeners();
  }

  Future<void> removeMonaco() async {
    await monacoServer.stop();
    monacoBase = null;
    monacoRev++;
    try {
      Directory(monacoCacheDir()).deleteSync(recursive: true);
    } catch (_) {}
    monacoStatus = 'Copia local eliminada (se usará el CDN)';
    notifyListeners();
  }

  // ---------- Git avanzado / CodeLens / configuraciones de ejecución ----------
  List<String> gitBranches = [];
  List<({String hash, String subject, String author, String date})> gitLog = [];

  void _reloadCleanDocs() {
    for (final d in List.of(docs)) {
      if (d.dirty || d.isImage) continue;
      try {
        final t = File(d.path).readAsStringSync();
        if (t != d.content) reloadDoc(d.path, t);
      } catch (_) {}
    }
  }

  Future<void> refreshBranches() async {
    final r = await _git(['branch', '--format=%(refname:short)']);
    if (r != null && r.exitCode == 0) {
      gitBranches = const LineSplitter().convert('${r.stdout}').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      notifyListeners();
    }
  }

  Future<void> refreshGitLog() async {
    final r = await _git(['log', '-60', '--pretty=format:%h%x1f%s%x1f%an%x1f%ar']);
    if (r == null || r.exitCode != 0) {
      gitLog = [];
      notifyListeners();
      return;
    }
    final out = <({String hash, String subject, String author, String date})>[];
    for (final l in const LineSplitter().convert('${r.stdout}')) {
      final x = l.split('\x1f');
      if (x.length >= 4) out.add((hash: x[0], subject: x[1], author: x[2], date: x[3]));
    }
    gitLog = out;
    notifyListeners();
  }

  Future<void> gitCheckout(String b) async {
    await gitRun(['checkout', b]);
    _reloadCleanDocs();
    await refreshBranches();
    await refreshGitLog();
  }

  Future<void> gitNewBranch(String n) async {
    await gitRun(['checkout', '-b', n]);
    await refreshBranches();
  }

  Future<void> gitDeleteBranch(String b) async {
    await gitRun(['branch', '-d', b]);
    await refreshBranches();
  }

  Future<void> gitMerge(String b) async {
    await gitRun(['merge', b]);
    _reloadCleanDocs();
    await refreshGitLog();
  }

  Future<void> gitStash() async {
    await gitRun(['stash', 'push', '-u']);
    _reloadCleanDocs();
  }

  Future<void> gitStashPop() async {
    await gitRun(['stash', 'pop']);
    _reloadCleanDocs();
  }

  Future<String> gitShow(String hash) async {
    final r = await _git(['show', '--stat', '--patch', '--no-color', hash]);
    final t = '${r?.stdout ?? ''}'.trim();
    return t.isEmpty ? '(sin contenido)' : t;
  }

  Future<void> lens(String kind, String path, String name) async {
    if (root == null) return;
    final rel = p.relative(path, from: root!);
    switch (kind) {
      case 'run':
        await run(target: rel);
      case 'debug':
        await startDebug(target: rel);
      case 'test':
        await runTests(file: rel, name: name);
      case 'cur':
      case 'inc':
      case 'both':
        await resolveConflictAt(path, int.tryParse(name) ?? 0, kind);
      case 'resolver':
        onOpenResolver?.call(path);
      case 'debugtest':
        await startDebug(target: rel, test: true, testName: name.isEmpty ? null : name);
    }
  }

  List<RunConfig> runConfigs = [RunConfig()];
  int activeRun = 0;
  RunConfig get runConfig => runConfigs[activeRun];

  void _saveRunConfigs() => _prefs?.setString('runs:$root', jsonEncode({'active': activeRun, 'list': runConfigs.map((c) => c.toJson()).toList()}));

  void selectRunConfig(int i) {
    activeRun = i.clamp(0, runConfigs.length - 1);
    _saveRunConfigs();
    notifyListeners();
  }

  void addRunConfig(String name) {
    runConfigs.add(RunConfig(name: name));
    activeRun = runConfigs.length - 1;
    _saveRunConfigs();
    notifyListeners();
  }

  void deleteRunConfig(int i) {
    if (runConfigs.length <= 1) return;
    runConfigs.removeAt(i);
    activeRun = activeRun.clamp(0, runConfigs.length - 1);
    _saveRunConfigs();
    notifyListeners();
  }

  // ---------- Contenido para diffs / historial por archivo ----------
  String _rel(String path) => './${p.relative(path, from: root!).replaceAll('\\', '/')}';

  Future<String> _gitContent(String spec) async {
    final r = await _git(['show', spec]);
    return (r != null && r.exitCode == 0) ? '${r.stdout}' : '';
  }

  String diskText(String path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  String _workingText(String path) {
    final d = _doc(path);
    return (d != null && !d.isImage) ? d.content : diskText(path);
  }

  Future<({String a, String b})> gitHeadVsWorking(String path) async => (a: await _gitContent('HEAD:${_rel(path)}'), b: _workingText(path));

  Future<({String a, String b})> gitCommitSides(String hash, String path) async =>
      (a: await _gitContent('$hash^:${_rel(path)}'), b: await _gitContent('$hash:${_rel(path)}'));

  Future<({String a, String b})> gitSides(GitChange c, bool staged) async {
    final abs = p.join(root!, c.path);
    if (staged) return (a: await _gitContent('HEAD:${_rel(abs)}'), b: await _gitContent(':${_rel(abs)}'));
    if (c.untracked) return (a: '', b: _workingText(abs));
    return (a: await _gitContent(':${_rel(abs)}'), b: _workingText(abs));
  }

  Future<List<({String hash, String subject, String author, String date})>> fileLog(String path) async {
    final r = await _git(['log', '--follow', '-80', '--pretty=format:%h%x1f%s%x1f%an%x1f%ar', '--', _rel(path)]);
    final out = <({String hash, String subject, String author, String date})>[];
    if (r == null || r.exitCode != 0) return out;
    for (final l in const LineSplitter().convert('${r.stdout}')) {
      final x = l.split('\x1f');
      if (x.length >= 4) out.add((hash: x[0], subject: x[1], author: x[2], date: x[3]));
    }
    return out;
  }

  // ---------- Conflictos de fusión ----------
  bool gitMerging = false;
  void Function(String path)? onOpenResolver;

  String workingText(String path) => _workingText(path);

  Future<void> resolveConflictAt(String path, int line, String choice) async {
    final d = _doc(path);
    final md = parseMerge(d?.content ?? diskText(path));
    final c = md.conflicts.where((x) => x.startLine == line).toList();
    if (c.isEmpty) return;
    c.first.choice = switch (choice) {
      'cur' => ConflictChoice.ours,
      'inc' => ConflictChoice.theirs,
      _ => ConflictChoice.both,
    };
    final out = md.build();
    if (d != null) {
      reloadDoc(d.path, out);
      d.dirty = true;
      notifyListeners();
    } else {
      File(path).writeAsStringSync(out);
    }
  }

  Future<void> gitMergeAbort() async {
    await gitRun(['merge', '--abort']);
    _reloadCleanDocs();
  }

  Future<void> gitMergeContinue() => gitRun(['commit', '--no-edit']);

  Future<void> gitMarkResolved(String path) => gitRun(['add', '--', path]);

  Future<void> gitTakeSide(String path, bool ours) async {
    await gitRun(['checkout', ours ? '--ours' : '--theirs', '--', path]);
    await gitRun(['add', '--', path]);
    final abs = p.join(root!, path);
    final d = _doc(abs);
    if (d != null) reloadDoc(d.path, diskText(abs));
  }

  // ---------- Ir a test / implementación ----------
  String _pubName() {
    try {
      final m = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(File(p.join(root!, 'pubspec.yaml')).readAsStringSync());
      return m?.group(1) ?? 'app';
    } catch (_) {
      return 'app';
    }
  }

  String _testStub(String libRel) {
    final cls = _pascal(p.basenameWithoutExtension(libRel));
    final fw = isFlutter ? 'flutter_test/flutter_test.dart' : 'test/test.dart';
    return "import 'package:$fw';\nimport 'package:${_pubName()}/${libRel.substring(4)}';\n\nvoid main() {\n  group('$cls', () {\n    test('funciona', () {\n      // TODO: escribir la prueba\n    });\n  });\n}\n";
  }

  Future<void> toggleTestFile() async {
    final d = current;
    if (d == null || root == null || !_isDart(d.path)) return;
    final rel = p.relative(d.path, from: root!).replaceAll('\\', '/');
    String other;
    if (rel.startsWith('lib/')) {
      other = 'test/${rel.substring(4).replaceAll(RegExp(r'\.dart$'), '_test.dart')}';
    } else if (rel.startsWith('test/') && rel.endsWith('_test.dart')) {
      other = 'lib/${rel.substring(5).replaceAll(RegExp(r'_test\.dart$'), '.dart')}';
    } else {
      info('Esta acción funciona con archivos de lib/ o de test/');
      return;
    }
    final f = File(p.join(root!, other));
    if (f.existsSync()) {
      openFile(f.path);
      return;
    }
    if (!rel.startsWith('lib/')) {
      info('No existe $other');
      return;
    }
    await f.create(recursive: true);
    await f.writeAsString(_testStub(rel));
    info('Test creado: $other');
    openFile(f.path);
  }

  Future<void> flutterLogs() => startTask('flutter logs', 'flutter', ['logs']);

  // ---------- Actualizaciones (GitHub Releases) ----------
  bool autoCheckUpdates = true, betaChannel = false;
  String skippedVersion = '';
  int lastUpdateCheck = 0;
  ReleaseInfo? updateAvailable;
  bool checkingUpdate = false, updateBusy = false, upToDate = false;
  String updateError = '', updateStatus = '';
  double? updateProgress;
  int _lastUpdPct = -1;

  void setUpdateSettings({bool? auto, bool? beta}) {
    autoCheckUpdates = auto ?? autoCheckUpdates;
    betaChannel = beta ?? betaChannel;
    _prefs?.setBool('autoCheckUpdates', autoCheckUpdates);
    _prefs?.setBool('betaChannel', betaChannel);
    notifyListeners();
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    if (checkingUpdate || updateBusy) return;
    if (!kRepoConfigured) {
      updateError = 'Falta configurar el repositorio de GitHub: edita kGithubOwner y kGithubRepo en lib/app_info.dart.';
      notifyListeners();
      return;
    }
    checkingUpdate = true;
    updateError = '';
    updateStatus = '';
    upToDate = false;
    notifyListeners();
    try {
      final r = await fetchLatestRelease(kGithubOwner, kGithubRepo, beta: betaChannel);
      lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      _prefs?.setInt('lastUpdateCheck', lastUpdateCheck);
      final newer = r != null && compareVersions(r.version, kAppVersion) > 0;
      if (newer && !(silent && r.version == skippedVersion)) {
        updateAvailable = r;
        if (silent) onToast?.call('Nueva versión disponible: v${r.version} (Ayuda → Buscar actualizaciones)');
      } else {
        updateAvailable = null;
        upToDate = !newer;
      }
    } catch (e) {
      if (!silent) updateError = '$e';
    }
    checkingUpdate = false;
    notifyListeners();
  }

  Future<void> installUpdate() async {
    final r = updateAvailable;
    if (r == null || updateBusy) return;
    final asset = pickAsset(r);
    if (asset == null) {
      updateError = 'Esta versión no incluye un archivo para tu sistema. Ábrela en GitHub.';
      notifyListeners();
      return;
    }
    updateBusy = true;
    updateError = '';
    updateProgress = 0;
    updateStatus = 'Descargando…';
    _lastUpdPct = -1;
    notifyListeners();
    try {
      final f = await downloadAsset(asset, (pr) {
        final pct = (pr * 100).floor();
        if (pct == _lastUpdPct) return;
        _lastUpdPct = pct;
        updateProgress = pr;
        updateStatus = 'Descargando… $pct%';
        notifyListeners();
      });
      updateProgress = null;
      updateStatus = 'Verificando integridad (SHA-256)…';
      notifyListeners();
      final ok = await verifyAsset(f, asset, r);
      if (ok == false) throw 'La verificación SHA-256 falló: el archivo no coincide con el publicado. No se instaló nada.';
      updateStatus = 'Instalando…';
      notifyListeners();
      await saveAll(); // nunca pierdas cambios al reiniciar
      final msg = await applyUpdate(f);
      if (msg != null) updateStatus = msg;
    } catch (e) {
      updateError = '$e';
      updateStatus = '';
    }
    updateBusy = false;
    updateProgress = null;
    notifyListeners();
  }

  void skipUpdate() {
    final r = updateAvailable;
    if (r == null) return;
    skippedVersion = r.version;
    _prefs?.setString('skippedVersion', r.version);
    updateAvailable = null;
    notifyListeners();
  }

  // ---------- Archivos: copiar / pegar / mover / duplicar ----------
  String? _fileClip;
  bool _clipCut = false;
  bool get hasFileClip => _fileClip != null;

  void clipFile(String path, {bool cut = false}) {
    _fileClip = path;
    _clipCut = cut;
    info('${cut ? 'Cortado' : 'Copiado'}: ${p.basename(path)}');
  }

  String _uniquePath(String dir, String name) {
    var cand = p.join(dir, name);
    if (FileSystemEntity.typeSync(cand) == FileSystemEntityType.notFound) return cand;
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 1;
    do {
      cand = p.join(dir, '$base copia${i > 1 ? ' $i' : ''}$ext');
      i++;
    } while (FileSystemEntity.typeSync(cand) != FileSystemEntityType.notFound);
    return cand;
  }

  Future<void> _copyEntity(String src, String dst) async {
    if (await FileSystemEntity.isDirectory(src)) {
      await Directory(dst).create(recursive: true);
      await for (final e in Directory(src).list(followLinks: false)) {
        await _copyEntity(e.path, p.join(dst, p.basename(e.path)));
      }
    } else {
      await File(src).copy(dst);
    }
  }

  Future<void> pasteInto(String dir) async {
    final src = _fileClip;
    if (src == null) return;
    try {
      if (_clipCut) {
        await moveEntity(src, dir);
        _fileClip = null;
      } else {
        await _copyEntity(src, _uniquePath(dir, p.basename(src)));
        expanded.add(dir);
        fsRev++;
        notifyListeners();
      }
    } catch (e) {
      _add('Error al pegar: $e');
    }
  }

  Future<void> duplicate(String path) async {
    try {
      final dst = _uniquePath(p.dirname(path), p.basename(path));
      await _copyEntity(path, dst);
      fsRev++;
      notifyListeners();
      if (File(dst).existsSync()) openFile(dst);
    } catch (e) {
      _add('Error al duplicar: $e');
    }
  }

  Future<void> moveEntity(String src, String destDir) async {
    try {
      final dst = p.join(destDir, p.basename(src));
      if (norm(dst) == norm(src)) return;
      if (norm(destDir) == norm(src) || p.isWithin(src, destDir)) {
        info('No se puede mover una carpeta dentro de sí misma');
        return;
      }
      if (FileSystemEntity.typeSync(dst) != FileSystemEntityType.notFound) {
        info('Ya existe "${p.basename(src)}" en la carpeta de destino');
        return;
      }
      final isDir = await FileSystemEntity.isDirectory(src);
      final affected = _under(src).map((d) => d.path).toList();
      for (final a in affected) {
        closeDoc(docs.indexOf(_doc(a)!));
      }
      if (isDir) {
        await Directory(src).rename(dst);
      } else {
        await File(src).rename(dst);
      }
      for (final a in affected) {
        final rel = p.relative(a, from: src);
        openFile(rel == '.' ? dst : p.join(dst, rel));
      }
      expanded.add(destDir);
      fsRev++;
      notifyListeners();
    } catch (e) {
      _add('Error al mover: $e');
    }
  }

  Future<void> revealPath(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,$path']);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else {
        await Process.run('xdg-open', [FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path)]);
      }
    } catch (e) {
      _add('No se pudo abrir el explorador: $e');
    }
  }

  void openTerminalAt(String dir) {
    final t = addTerminal();
    t.cwd = dir;
    notifyListeners();
  }

  // ---------- Gutter de Git: líneas añadidas / modificadas / eliminadas ----------
  void Function(String path, List<List<int>> ranges)? onGutter;

  Future<void> refreshGutter(String path) async {
    final d = _doc(path);
    if (d == null || d.isImage || root == null) return;
    if (!gitRepo) {
      onGutter?.call(d.path, const []);
      return;
    }
    final out = <List<int>>[];
    final untracked = gitChanges.any((c) => c.untracked && norm(p.join(root!, c.path)) == norm(d.path));
    if (untracked) {
      out.add([1, '\n'.allMatches(d.content).length + 1, 0]);
    } else {
      final r = await _git(['diff', 'HEAD', '-U0', '--no-color', '--', _rel(d.path)]);
      if (r != null && r.exitCode == 0) {
        final re = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', multiLine: true);
        for (final m in re.allMatches('${r.stdout}')) {
          final oldLen = m.group(2) == null ? 1 : int.parse(m.group(2)!);
          final ns = int.parse(m.group(3)!);
          final newLen = m.group(4) == null ? 1 : int.parse(m.group(4)!);
          if (newLen == 0) {
            out.add([math.max(1, ns), math.max(1, ns), 2]);
          } else if (oldLen == 0) {
            out.add([ns, ns + newLen - 1, 0]);
          } else {
            out.add([ns, ns + newLen - 1, 1]);
          }
        }
      }
    }
    onGutter?.call(d.path, out);
  }

  // ---------- Snippets propios y zoom ----------
  List<Map<String, String>> userSnippets = [];

  void _loadSnippets() {
    try {
      final j = _prefs?.getString('userSnippets');
      if (j != null) userSnippets = [for (final e in (jsonDecode(j) as List)) Map<String, String>.from(e as Map)];
    } catch (_) {}
  }

  void saveSnippets(List<Map<String, String>> list) {
    userSnippets = list;
    _prefs?.setString('userSnippets', jsonEncode(list));
    settingsRev++;
    notifyListeners();
  }

  void zoom(int dir) {
    final f = dir == 0 ? 14.0 : (fontSize + dir).clamp(8.0, 40.0).toDouble();
    updateSettings(font: f);
  }

  // ---------- Recuperación de cambios sin guardar ----------
  Timer? _recTimer;
  List<({String path, String content})> recoverable = [];

  String _recDir() => p.join(p.dirname(AppLog.dirPath()), 'recovery');

  int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  File _recFile(String path) => File(p.join(_recDir(), '${_fnv(norm(path)).toRadixString(16)}.json'));

  void _scheduleRecovery(OpenDoc d) {
    _recTimer?.cancel();
    _recTimer = Timer(const Duration(seconds: 3), () {
      try {
        for (final x in docs.where((x) => x.dirty && !x.isImage)) {
          final f = _recFile(x.path);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(jsonEncode({'path': x.path, 'content': x.content}));
        }
      } catch (_) {}
    });
  }

  void _clearRecovery(String path) {
    try {
      final f = _recFile(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _scanRecovery() {
    recoverable = [];
    try {
      final d = Directory(_recDir());
      if (!d.existsSync()) return;
      for (final f in d.listSync().whereType<File>()) {
        try {
          final j = jsonDecode(f.readAsStringSync()) as Map;
          final path = '${j['path']}';
          final content = '${j['content']}';
          if (!File(path).existsSync() || File(path).readAsStringSync() == content) {
            f.deleteSync();
            continue;
          }
          recoverable.add((path: path, content: content));
        } catch (_) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void restoreRecovered() {
    for (final r in recoverable) {
      openFile(r.path);
      final d = _doc(r.path);
      if (d != null) {
        reloadDoc(d.path, r.content);
        d.dirty = true;
        dirtyRev.value++;
      }
    }
    recoverable = [];
    notifyListeners();
  }

  void discardRecovered() {
    for (final r in recoverable) {
      _clearRecovery(r.path);
    }
    recoverable = [];
    notifyListeners();
  }

  // ---------- Búsqueda: incluir / excluir archivos ----------
  RegExp _globRe(String g) {
    g = g.replaceAll('\\', '/');
    if (g.endsWith('/')) return RegExp('(^|/)${RegExp.escape(g)}');
    final re = RegExp.escape(g).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*').replaceAll(r'\?', '.');
    return RegExp('(^|/)$re\$');
  }

  List<RegExp> _globs(String s) => [for (final g in s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) _globRe(g)];

  bool _passes(String path, List<RegExp> inc, List<RegExp> exc) {
    final rel = p.relative(path, from: root!).replaceAll('\\', '/');
    if (inc.isNotEmpty && !inc.any((r) => r.hasMatch(rel))) return false;
    return !exc.any((r) => r.hasMatch(rel));
  }

  // ---------- Tareas del proyecto ----------
  List<Map<String, String>> projectTasks = [];

  void _loadTasks() {
    projectTasks = [];
    try {
      final j = _prefs?.getString('tasks:$root');
      if (j != null) projectTasks = [for (final e in (jsonDecode(j) as List)) Map<String, String>.from(e as Map)];
    } catch (_) {}
  }

  void saveTasks(List<Map<String, String>> list) {
    projectTasks = list;
    _prefs?.setString('tasks:$root', jsonEncode(list));
    notifyListeners();
  }

  void runTask(Map<String, String> t) {
    if (root == null) return;
    final term = addTerminal();
    term.name = t['name'] ?? 'Tarea';
    term.cwd = root!;
    term.run(t['cmd'] ?? '');
    info('Tarea «${term.name}» iniciada en una terminal nueva');
  }

  // ---------- Ayuda de firmas (LSP) ----------
  Future<Map<String, dynamic>?> lspSignature(String path, int l, int c) async => await _lsp?.signatureHelp(path, l, c);

  // ---------- Inspector de widgets y herramientas de Flutter (VM Service) ----------
  VmService? _vm;
  String? vmServiceUri;
  Map? inspectorTree;
  String inspectorError = '';
  bool inspectorBusy = false;
  final flutterToggles = <String, bool>{};
  bool slowAnimations = false;

  void _vmReset() {
    vmServiceUri = null;
    _vm?.close();
    _vm = null;
    inspectorTree = null;
    inspectorError = '';
    flutterToggles.clear();
    slowAnimations = false;
  }

  Future<VmService> _vmConn() async {
    final uri = vmServiceUri;
    if (uri == null) throw 'No hay una app Flutter en ejecución. Pulsa Run o Depurar.';
    var v = _vm;
    if (v == null || !v.connected) {
      v = VmService();
      await v.connect(uri);
      _vm = v;
    }
    return v;
  }

  Future<void> refreshInspector() async {
    if (inspectorBusy) return;
    inspectorBusy = true;
    inspectorError = '';
    notifyListeners();
    try {
      final v = await _vmConn();
      try {
        await v.ext('ext.flutter.inspector.setPubRootDirectories', {'arg0': Uri.directory(root ?? '.').toString()});
      } catch (_) {}
      dynamic t = await v.ext('ext.flutter.inspector.getRootWidgetSummaryTree', {'objectGroup': 'darter'});
      if (t is String) t = jsonDecode(t);
      inspectorTree = t is Map ? t : null;
      if (inspectorTree == null) inspectorError = 'El inspector no devolvió un árbol de widgets.';
    } catch (e) {
      inspectorError = '$e';
      inspectorTree = null;
    }
    inspectorBusy = false;
    notifyListeners();
  }

  Future<void> toggleFlutterExt(String ext) async {
    try {
      final v = await _vmConn();
      final on = !(flutterToggles[ext] ?? false);
      await v.ext(ext, {'enabled': on ? 'true' : 'false'});
      flutterToggles[ext] = on;
      notifyListeners();
    } catch (e) {
      info('$e');
    }
  }

  Future<void> toggleSlowAnimations() async {
    try {
      final v = await _vmConn();
      final on = !slowAnimations;
      await v.ext('ext.flutter.timeDilation', {'timeDilation': on ? '5.0' : '1.0'});
      slowAnimations = on;
      notifyListeners();
    } catch (e) {
      info('$e');
    }
  }

  // ---------- Tema del sistema y primer inicio / novedades ----------
  bool followSystem = false;
  String lightThemeId = 'light', darkThemeId = 'dark';
  String lastSeenVersion = '';

  bool get firstRun => lastSeenVersion.isEmpty;
  bool get versionChanged => lastSeenVersion.isNotEmpty && lastSeenVersion != kAppVersion;

  void markVersionSeen() {
    lastSeenVersion = kAppVersion;
    _prefs?.setString('lastSeenVersion', kAppVersion);
  }

  void applySystemTheme() {
    if (!followSystem) return;
    final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final id = b == Brightness.dark ? darkThemeId : lightThemeId;
    if (theme.id != id) setTheme(IdeTheme.byId(id));
  }

  void setFollowSystem(bool v) {
    followSystem = v;
    _prefs?.setBool('followSystem', v);
    if (v) applySystemTheme();
    notifyListeners();
  }

  void setSystemThemes({String? light, String? dark}) {
    lightThemeId = light ?? lightThemeId;
    darkThemeId = dark ?? darkThemeId;
    _prefs?.setString('lightThemeId', lightThemeId);
    _prefs?.setString('darkThemeId', darkThemeId);
    applySystemTheme();
    notifyListeners();
  }

  // ---------- Atajos ----------
  Future<int> pub(List<String> a) => execArgs(_tool == 'flutter' ? 'flutter' : 'dart', ['pub', ...a]);
  Future<void> pubGet() => pub(['get']);
  Future<void> pubUpgrade() => pub(['upgrade']);
  Future<void> pubUpgradeMajor() => pub(['upgrade', '--major-versions']);
  Future<void> pubOutdated() => pub(['outdated']);
  Future<void> addPackage(String spec, {bool dev = false}) => pub(['add', if (dev) '--dev', spec]);
  Future<void> removePackage(String n) => pub(['remove', n]);
  Future<void> analyze() => execArgs(_tool, ['analyze']);
  Future<void> format() => execArgs('dart', ['format', '.']);
  Future<void> test() => execArgs(_tool, ['test']);
  Future<void> clean() => execArgs('flutter', ['clean']);
  Future<void> doctor() => execArgs('flutter', ['doctor', '-v']);
  Future<void> buildApk() => execArgs('flutter', ['build', 'apk']);
  Future<void> buildWeb() => execArgs('flutter', ['build', 'web']);
  Future<void> buildDesktop() => execArgs('flutter', ['build', Platform.isWindows ? 'windows' : Platform.isMacOS ? 'macos' : 'linux']);
  Future<void> upgradeFlutter() => execArgs('flutter', ['upgrade']);
  Future<void> channel() => execArgs('flutter', ['channel']);

  @override
  void dispose() {
    _lsp?.dispose();
    _watchSub?.cancel();
    super.dispose();
  }
}
