// hugging_face.dart — метаданные Hugging Face без загрузки весов.
//
// Поиск и дерево файлов используют cursor-пагинацию HF (заголовок Link).
// В кэш попадают только метаданные. Токен в кэш и на диск не пишется.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class HFException implements Exception {
  final String message;
  final bool authRequired;
  const HFException(this.message, {this.authRequired = false});
  @override
  String toString() => message;
}

class HFModel {
  final String id, author, pipelineTag;
  final int downloads, likes;
  final bool gated;
  final List<String> tags;

  const HFModel({
    required this.id,
    required this.author,
    required this.pipelineTag,
    required this.downloads,
    required this.likes,
    required this.gated,
    required this.tags,
  });

  String get title {
    final slash = id.indexOf('/');
    return slash >= 0 && slash + 1 < id.length ? id.substring(slash + 1) : id;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'pipeline_tag': pipelineTag,
        'downloads': downloads,
        'likes': likes,
        'gated': gated,
        'tags': tags,
      };

  factory HFModel.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? j['modelId'] ?? '').toString();
    final rawGated = j['gated'];
    return HFModel(
      id: id,
      author: id.contains('/') ? id.split('/').first : '',
      pipelineTag: (j['pipeline_tag'] ?? '').toString(),
      downloads: (j['downloads'] as num?)?.toInt() ?? 0,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      gated: rawGated == true || (rawGated is String && rawGated != 'false'),
      tags: ((j['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

class HFFile {
  final String path;
  final int size;
  final bool lfs;

  const HFFile({required this.path, required this.size, required this.lfs});

  String get name => path.split('/').last;

  /// Q4_K_M → Q4_K_M; для неизвестного формата возвращает пустую строку.
  String get quantization {
    final n = name.toLowerCase();
    final m = RegExp(r'(q\d(?:_[a-z0-9]+)*|iq\d(?:_[a-z0-9]+)*|f16|bf16|f32)')
        .firstMatch(n);
    return m?.group(1)?.toUpperCase() ?? '';
  }

  Map<String, dynamic> toJson() => {'path': path, 'size': size, 'lfs': lfs};

  factory HFFile.fromJson(Map<String, dynamic> j) {
    final lfs = j['lfs'] is Map ? j['lfs'] as Map : null;
    final normalSize = (j['size'] as num?)?.toInt() ?? 0;
    final lfsSize = (lfs?['size'] as num?)?.toInt() ?? 0;
    // У LFS в поле size иногда лежит размер pointer-файла. Реальный размер
    // весов — lfs.size; берём его, когда он есть.
    final size = lfsSize > 0 ? lfsSize : normalSize;
    return HFFile(
      path: (j['path'] ?? '').toString(),
      size: size,
      lfs: lfs != null,
    );
  }
}

class HFPage<T> {
  final List<T> items;
  final String nextCursor;
  const HFPage(this.items, this.nextCursor);

  bool get hasMore => nextCursor.isNotEmpty;
}

class HuggingFaceService {
  HuggingFaceService._();
  static final HuggingFaceService instance = HuggingFaceService._();

  final http.Client _client = http.Client();
  final Map<String, _CacheEntry> _cache = {};
  Timer? _saveTimer;
  bool _cacheLoaded = false;

  static const _base = 'huggingface.co';
  static const _searchTtl = Duration(minutes: 5);
  static const _treeTtl = Duration(hours: 6);

  Future<HFPage<HFModel>> search(
    String query, {
    String cursor = '',
    int limit = 20,
    String token = '',
    bool force = false,
  }) async {
    final clean = query.trim();
    final key = 's|$clean|$limit|$cursor';
    final cached = await _readCache(key, _searchTtl, force: force);
    if (cached != null) {
      return HFPage(
        (cached['items'] as List)
            .map((e) => HFModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        (cached['next'] ?? '').toString(),
      );
    }
    final params = <String, String>{
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$limit',
      'full': 'false',
      if (clean.isNotEmpty) 'search': clean,
      if (cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.https(_base, '/api/models', params);
    final response = await _get(uri, token: token);
    final raw = jsonDecode(response.body);
    if (raw is! List) {
      throw const HFException('Hugging Face вернул неожиданный ответ.');
    }
    final models = raw
        .whereType<Map>()
        .map((e) => HFModel.fromJson(e.cast<String, dynamic>()))
        .where((m) => m.id.isNotEmpty)
        .toList(growable: false);
    final next = _nextLink(response.headers['link']);
    await _writeCache(key, {
      'items': models.map((m) => m.toJson()).toList(),
      'next': next,
    });
    return HFPage(models, next);
  }

  Future<HFPage<HFFile>> files(
    String repoId, {
    String cursor = '',
    int limit = 100,
    String token = '',
    bool force = false,
  }) async {
    final key = 't|$repoId|$limit|$cursor';
    final cached = await _readCache(key, _treeTtl, force: force);
    if (cached != null) {
      return HFPage(
        (cached['items'] as List)
            .map((e) => HFFile.fromJson(e as Map<String, dynamic>))
            .toList(),
        (cached['next'] ?? '').toString(),
      );
    }
    final uri = Uri.https(
      _base,
      '/api/models/$repoId/tree/main',
      {
        'recursive': 'true',
        'expand': 'false',
        'limit': '$limit',
        if (cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final response = await _get(uri, token: token);
    final raw = jsonDecode(response.body);
    if (raw is! List) {
      throw const HFException('Hugging Face вернул неожиданный ответ.');
    }
    final files = raw
        .whereType<Map>()
        .where((e) => (e['type'] ?? 'file') == 'file')
        .map((e) => HFFile.fromJson(e.cast<String, dynamic>()))
        .where((f) => f.path.toLowerCase().endsWith('.gguf'))
        .toList(growable: false);
    final next = _nextLink(response.headers['link']);
    await _writeCache(key, {
      'items': files.map((f) => f.toJson()).toList(),
      'next': next,
    });
    return HFPage(files, next);
  }

  String downloadUrl(String repoId, String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://huggingface.co/$repoId/resolve/main/$encoded';
  }

  Future<http.Response> _get(Uri uri, {required String token}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'TERMAI/1.19',
      if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
    };
    http.Response? response;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _client.get(uri, headers: headers).timeout(
              const Duration(seconds: 12),
            );
        if (r.statusCode >= 500 && attempt == 0) {
          lastError = HFException('Hugging Face вернул ${r.statusCode}.');
          continue;
        }
        response = r;
        break;
      } on TimeoutException {
        throw const HFException(
            'Hugging Face не ответил за 12 секунд. Проверь сеть.');
      } catch (e) {
        lastError = e;
        if (attempt == 0) continue;
      }
    }
    if (response == null) {
      throw HFException('Нет связи с Hugging Face: ${_clean(lastError ?? '')}');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const HFException(
        'Модель закрыта (gated). Добавь Hugging Face token с доступом к ней.',
        authRequired: true,
      );
    }
    if (response.statusCode == 429) {
      throw const HFException(
          'Hugging Face временно ограничил запросы. Подожди немного.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HFException('Hugging Face вернул ${response.statusCode}.');
    }
    return response;
  }

  String _nextLink(String? header) {
    if (header == null) return '';
    // <https://...?...cursor=...>; rel="next"
    final match = RegExp(r'<([^>]+)>\s*;\s*rel="next"', caseSensitive: false)
        .firstMatch(header);
    if (match == null) return '';
    try {
      return Uri.parse(match.group(1)!).queryParameters['cursor'] ?? '';
    } catch (_) {
      return '';
    }
  }

  String _clean(Object e) {
    var s = e.toString();
    if (s.length > 160) s = '${s.substring(0, 160)}…';
    return s;
  }

  Future<Map<String, dynamic>?> _readCache(
    String key,
    Duration ttl, {
    required bool force,
  }) async {
    if (!force) {
      final local = _cache[key];
      if (local != null &&
          DateTime.now().difference(local.at) < ttl &&
          local.data.isNotEmpty) {
        return local.data;
      }
    }
    await _loadCache();
    final disk = _cache[key];
    if (!force &&
        disk != null &&
        DateTime.now().difference(disk.at) < ttl &&
        disk.data.isNotEmpty) {
      return disk.data;
    }
    return null;
  }

  Future<void> _writeCache(String key, Map<String, dynamic> data) async {
    _cache[key] = _CacheEntry(DateTime.now(), data);
    if (_cache.length > 80) {
      final oldest = _cache.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in oldest.take(_cache.length - 60)) {
        _cache.remove(e.key);
      }
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveCache);
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      raw.forEach((k, v) {
        if (v is Map) {
          final at = DateTime.tryParse((v['at'] ?? '').toString());
          final data = v['data'];
          if (at != null && data is Map) {
            _cache[k.toString()] =
                _CacheEntry(at, data.cast<String, dynamic>());
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final f = await _cacheFile();
      final raw = <String, dynamic>{};
      for (final e in _cache.entries) {
        raw[e.key] = {
          'at': e.value.at.toIso8601String(),
          'data': e.value.data,
        };
      }
      await f.writeAsString(jsonEncode(raw));
    } catch (_) {}
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/hf_cache.json');
  }
}

class _CacheEntry {
  final DateTime at;
  final Map<String, dynamic> data;
  const _CacheEntry(this.at, this.data);
}
