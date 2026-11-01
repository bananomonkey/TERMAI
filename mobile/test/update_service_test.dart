import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termai/update_service.dart';

void main() {
  Map<String, dynamic> release(String tag) => {
        'tag_name': tag,
        'body': 'Новая версия',
        'html_url': 'https://github.com/bananomonkey/TERMAI/releases/tag/$tag',
        'assets': [
          {
            'name': 'TERMAI.apk',
            'browser_download_url': 'https://example.com/v$tag/TERMAI.apk',
          },
          {
            'name': 'TERMAI-arm64-v8a.apk',
            'browser_download_url':
                'https://example.com/v$tag/TERMAI-arm64-v8a.apk',
          },
          {
            'name': 'TERMAI-armeabi-v7a.apk',
            'browser_download_url':
                'https://example.com/v$tag/TERMAI-armeabi-v7a.apk',
          },
        ],
      };

  test('update check selects an ABI-compatible APK', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode(release('v1.22.0')), 200, headers: {
          'content-type': 'application/json; charset=utf-8',
        }));
    final arm64 = await UpdateService.check(
      currentVersionOverride: '1.21.0+47',
      supportedAbis: ['arm64-v8a'],
      client: client,
    );
    expect(arm64.available, isTrue);
    expect(arm64.apkUrl, endsWith('TERMAI-arm64-v8a.apk'));

    final arm32 = await UpdateService.check(
      currentVersionOverride: '1.21.0+47',
      supportedAbis: ['armeabi-v7a'],
      client: client,
    );
    expect(arm32.apkUrl, endsWith('TERMAI-armeabi-v7a.apk'));
  });

  test('update check falls back and compares versions correctly', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode(release('v1.21.0')), 200, headers: {
          'content-type': 'application/json; charset=utf-8',
        }));
    final same = await UpdateService.check(
      currentVersionOverride: '1.21.0+47',
      supportedAbis: ['x86_64'],
      client: client,
    );
    expect(same.available, isFalse);
    expect(same.apkUrl, endsWith('TERMAI.apk'));
  });

  test('temporary GitHub errors are retried', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls < 3) return http.Response('rate limit', 500);
      return http.Response(jsonEncode(release('v1.22.0')), 200, headers: {
        'content-type': 'application/json; charset=utf-8',
      });
    });
    final info = await UpdateService.check(
      currentVersionOverride: '1.21.0+47',
      supportedAbis: ['arm64-v8a'],
      retries: 3,
      client: client,
    );
    expect(calls, 3);
    expect(info.available, isTrue);
  });
}
