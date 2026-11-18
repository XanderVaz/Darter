import 'dart:convert';
import 'package:http/http.dart' as http;

class PkgInfo {
  PkgInfo({required this.name, this.latest = '', this.description = '', this.likes, this.points, this.maxPoints, this.popularity});
  final String name, latest, description;
  final int? likes, points, maxPoints;
  final double? popularity;
}

class PubService {
  static final _cache = <String, Future<PkgInfo>>{};
  static const _t = Duration(seconds: 10);

  static Future<List<String>> search(String q) async {
    final r = await http.get(Uri.parse('https://pub.dev/api/search?q=${Uri.encodeQueryComponent(q)}')).timeout(_t);
    final list = (jsonDecode(r.body)['packages'] as List?) ?? [];
    return [for (final e in list.take(12)) e['package'] as String];
  }

  static Future<PkgInfo> info(String name) {
    final f = _cache.putIfAbsent(name, () => _fetch(name));
    f.then((v) {
      if (v.latest.isEmpty) _cache.remove(name);
    });
    return f;
  }

  static Future<PkgInfo> _fetch(String name) async {
    try {
      final r = await Future.wait([
        http.get(Uri.parse('https://pub.dev/api/packages/$name')).timeout(_t),
        http.get(Uri.parse('https://pub.dev/api/packages/$name/score')).timeout(_t),
      ]);
      final a = jsonDecode(r[0].body) as Map;
      final latest = (a['latest'] as Map?) ?? {};
      final sc = r[1].statusCode == 200 ? jsonDecode(r[1].body) as Map : {};
      return PkgInfo(
        name: name,
        latest: '${latest['version'] ?? ''}',
        description: '${latest['pubspec']?['description'] ?? ''}'.trim(),
        likes: sc['likeCount'] as int?,
        points: sc['grantedPoints'] as int?,
        maxPoints: sc['maxPoints'] as int?,
        popularity: (sc['popularityScore'] as num?)?.toDouble(),
      );
    } catch (_) {
      return PkgInfo(name: name);
    }
  }

  static void clearCache() => _cache.clear();
}
