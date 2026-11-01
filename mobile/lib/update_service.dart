// update_service.dart — проверка обновлений через GitHub Releases.
//
// Полностью тихо обновиться на Android вне Play/enterprise нельзя:
// система всё равно покажет подтверждение установки. Поэтому мы открываем
// APK в браузере, а пользователь нажимает «Установить».
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final bool available;
  final String current;
  final String latest;
  final String notes;
  final String releaseUrl;
  final String apkUrl;
  final String apkName;

  UpdateInfo({
    required this.available,
    required this.current,
    required this.latest,
    required this.notes,
    required this.releaseUrl,
    required this.apkUrl,
    this.apkName = '',
  });

  static UpdateInfo none(String current) => UpdateInfo(
        available: false,
        current: current,
        latest: current,
        notes: '',
        releaseUrl: '',
        apkUrl: '',
      );
}

class UpdateService {
  static const repo = 'bananomonkey/TERMAI';
  static const checkInterval = Duration(hours: 6);

  static int _cmp(String a, String b) {
    List<int> parts(String s) {
      final clean = s.replaceFirst(RegExp(r'^v'), '').split('+').first;
      return clean
          .split('.')
          .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final pa = parts(a), pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Future<bool> open(String url) async {
    if (url.isEmpty) return false;
    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<String> currentVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    return '${pkg.version}+${pkg.buildNumber}';
  }

  /// supportedAbis — реальные ABI устройства. Если не переданы, на Android
  /// спрашиваем device_info_plus; в тестах список передаётся явно.
  static Future<List<String>> androidAbis() async {
    if (!Platform.isAndroid) return const [];
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.supportedAbis;
    } catch (_) {
      return const [];
    }
  }

  static String _pickApk(List<dynamic> assets, List<String> abis) {
    final byName = <String, String>{};
    for (final a in assets) {
      final m = a as Map<String, dynamic>;
      final name = (m['name'] as String? ?? '').toLowerCase();
      final url = m['browser_download_url'] as String? ?? '';
      if (name.endsWith('.apk') && url.isNotEmpty) byName[name] = url;
    }
    // Сначала точное совпадение с ABI устройства.
    for (final abi in abis) {
      final key = 'termai-${abi.toLowerCase()}.apk';
      final url = byName[key];
      if (url != null) return url;
    }
    // Универсальный/старый псевдоним. В текущем CI TERMAI.apk = arm64.
    if (byName.containsKey('termai.apk')) return byName['termai.apk']!;
    for (final entry in byName.entries) {
      if (entry.key.contains('arm64')) return entry.value;
    }
    return byName.values.isEmpty ? '' : byName.values.first;
  }

  static String _apkName(String url) {
    final part = Uri.tryParse(url)?.pathSegments;
    return part == null || part.isEmpty ? '' : part.last;
  }

  static Future<UpdateInfo> check({
    String? currentVersionOverride,
    List<String>? supportedAbis,
    int retries = 2,
    http.Client? client,
  }) async {
    final current =
        currentVersionOverride ?? await UpdateService.currentVersion();
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final resp = await (client?.get(uri, headers: {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'TERMAI-mobile',
                }) ??
                http.get(uri, headers: {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'TERMAI-mobile',
                }))
            .timeout(const Duration(seconds: 18));
        if (resp.statusCode == 403 || resp.statusCode == 429) {
          throw Exception('GitHub временно ограничил запросы');
        }
        if (resp.statusCode != 200) {
          throw Exception('GitHub ответил ${resp.statusCode}');
        }
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true))
                as Map<String, dynamic>;
        final tag = (data['tag_name'] as String? ?? '').trim();
        final latest = tag.replaceFirst(RegExp(r'^v'), '');
        final available = latest.isNotEmpty && _cmp(latest, current) > 0;
        final assets = (data['assets'] as List?) ?? const [];
        final abis = supportedAbis ??
            (Platform.isAndroid ? await androidAbis() : const []);
        final apk = _pickApk(assets, abis);
        return UpdateInfo(
          available: available,
          current: current,
          latest: latest,
          notes: (data['body'] as String? ?? '').trim(),
          releaseUrl: (data['html_url'] as String? ?? '').trim(),
          apkUrl: apk,
          apkName: _apkName(apk),
        );
      } catch (e) {
        lastError = e;
        if (attempt < retries) {
          await Future<void>.delayed(
              Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
    }
    throw Exception('Не удалось проверить обновления: $lastError');
  }

  /// Состояние уведомлений переживает перезапуск и фоновый isolate.
  static Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/termai-update-state.json');
  }

  static Future<Map<String, dynamic>> readState() async {
    try {
      final f = await _stateFile();
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> writeState(Map<String, dynamic> state) async {
    try {
      final f = await _stateFile();
      await f.writeAsString(jsonEncode(state));
    } catch (_) {}
  }

  static Future<bool> shouldNotify(String version) async {
    final state = await readState();
    return (state['last_notified'] as String? ?? '') != version;
  }

  static Future<void> markNotified(String version) async {
    final state = await readState();
    state['last_notified'] = version;
    state['last_notified_at'] = DateTime.now().toIso8601String();
    await writeState(state);
  }

  /// Конфиг для фонового isolate: читаем локальный JSON без AppController.
  static Future<Map<String, dynamic>> backgroundConfig() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/termai.json');
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }
}
