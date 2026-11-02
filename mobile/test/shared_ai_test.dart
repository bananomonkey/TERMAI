import 'package:flutter_test/flutter_test.dart';
import 'package:termai/attachments.dart';
import 'package:termai/shared_ai.dart';

void main() {
  test('promo config is active only before its shared end date', () {
    final active = SharedAiPromo.fromJson({
      'enabled': true,
      'ends_at':
          DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
      'notice_version': 2,
      'model': 'deepseek-v4.1-flash:free',
    });
    expect(active.active, isTrue);
    expect(active.noticeVersion, 2);
    expect(active.model, 'deepseek-v4.1-flash:free');

    final ended = SharedAiPromo.fromJson({
      'enabled': true,
      'ends_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
      'notice_version': 1,
    });
    expect(ended.active, isFalse);

    final disabled = SharedAiPromo.fromJson({
      'enabled': false,
      'ends_at':
          DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
    });
    expect(disabled.active, isFalse);
  });

  test('SVG sanitizer strips code fences and adds required attributes', () {
    final svg = sanitizeSvg('''```svg
<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>
```''');
    expect(svg.startsWith('<svg'), isTrue);
    expect(svg.contains('xmlns="http://www.w3.org/2000/svg"'), isTrue);
    expect(svg.contains('viewBox="0 0 10 10"'), isTrue);
    expect(svg.contains('circle'), isTrue);
  });

  test('SVG sanitizer rejects scripts and external resources', () {
    expect(
      () => sanitizeSvg('<svg xmlns="http://www.w3.org/2000/svg">'
          '<script>alert(1)</script></svg>'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => sanitizeSvg('<svg xmlns="http://www.w3.org/2000/svg">'
          '<image href="https://evil.example/a.png"/></svg>'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => sanitizeSvg('<svg xmlns="http://www.w3.org/2000/svg">'
          '<a href="https://evil.example">x</a></svg>'),
      throwsA(isA<Exception>()),
    );
  });

  test('SVG sanitizer rejects output without an svg root', () {
    expect(() => sanitizeSvg('просто текст'), throwsA(isA<Exception>()));
  });
}
