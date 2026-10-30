// update_service.dart — проверка обновлений через GitHub Releases.
//
// Полностью тихо обновиться на Android вне Play/enterprise нельзя:
// система всё равно покажет подтверждение установки. Поэтому мы открываем
// APK в браузере, а пользователь нажимает «Установить».
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final bool available;
  final String current;
  final String latest;
  final String notes;
  final String releaseUrl;
  final String apkUrl;

  UpdateInfo({
    required this.available,
    required this.current,
    required this.latest,
    required this.notes,
    required this.releaseUrl,
    required this.apkUrl,
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

  static Future<UpdateInfo> check() async {
    final pkg = await PackageInfo.fromPlatform();
    final current = '${pkg.version}+${pkg.buildNumber}';
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final resp = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'TERMAI-mobile',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('GitHub ответил ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').trim();
    final latest = tag.replaceFirst(RegExp(r'^v'), '');
    final available = latest.isNotEmpty && _cmp(latest, current) > 0;
    final assets = (data['assets'] as List?) ?? const [];
    String apk = '';
    // Приоритет: arm64 (большинство телефонов), затем universal/любой APK.
    for (final a in assets) {
      final m = a as Map<String, dynamic>;
      final name = (m['name'] as String? ?? '').toLowerCase();
      final url = m['browser_download_url'] as String? ?? '';
      if (!name.endsWith('.apk')) continue;
      if (name.contains('arm64') || name.contains('aarch64')) {
        apk = url;
        break;
      }
      if (apk.isEmpty) apk = url;
    }
    return UpdateInfo(
      available: available,
      current: current,
      latest: latest,
      notes: (data['body'] as String? ?? '').trim(),
      releaseUrl: (data['html_url'] as String? ?? '').trim(),
      apkUrl: apk,
    );
  }
}
