import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termai/ai.dart';
import 'package:termai/models.dart';
import 'package:termai/store.dart';

AIClient _testAi(String content, {String finishReason = 'stop'}) {
  AIClient.httpClientFactory = () => MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
                'finish_reason': finishReason,
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
  return AIClient(Config(
    provider: 'custom',
    apiKey: 'test-only',
    model: 'test-model',
    baseUrl: 'https://example.invalid/v1',
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AIClient.httpClientFactory = null);

  test('new installs do not opt in to cloud key sync', () {
    expect(Config().syncKeysToCloud, isFalse);
    expect(Config.fromJson(const {}).syncKeysToCloud, isFalse);
  });

  test('errors shown to users redact common API-key formats', () {
    final text = rawError(Exception(
        'Bearer sk-super-secret-value api_key=or-v1-another-secret-value'));
    expect(text, isNot(contains('super-secret')));
    expect(text, isNot(contains('another-secret')));
    expect(text, contains('••••'));
  });

  test('each task keeps independent terminal state, history and draft', () {
    final c = AppController()
      ..courses = [
        Course(id: 'course', title: 'Курс', tasks: [
          Task(id: 'one', title: 'Один', goal: 'one'),
          Task(id: 'two', title: 'Два', goal: 'two'),
        ])
      ]
      ..courseIdx = 0
      ..viewIdx = 0;
    c.resetCourseState();
    c.termText = r'$ echo one' '\nONE\n';
    c.termInput.text = 'draft-one';
    c.state.files['one.txt'] = 'one';
    c.history[c.stateKey] = [HistEntry(cmd: 'echo one', out: 'ONE')];
    c.cmdHist.add('echo one');

    c.selectTask(1);
    expect(c.termText, isEmpty);
    expect(c.termInput.text, isEmpty);
    expect(c.state.files, isNot(contains('one.txt')));
    expect(c.history[c.stateKey], isEmpty);
    expect(c.cmdHist, isEmpty);
    c.termText = r'$ echo two' '\nTWO\n';
    c.termInput.text = 'draft-two';

    c.selectTask(0);
    expect(c.termText, contains('ONE'));
    expect(c.termText, isNot(contains('TWO')));
    expect(c.termInput.text, 'draft-one');
    expect(c.state.files['one.txt'], 'one');
    expect(c.history[c.stateKey]!.single.cmd, 'echo one');
    expect(c.cmdHist, ['echo one']);
    c.dispose();
  });

  test('SVG generation extracts a real standalone SVG response', () async {
    final ai = _testAi('''```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <path d="M100 300 Q400 40 700 300" fill="#ffd54f"/>
</svg>
```''');
    final svg = await ai.generateSvg('создай SVG фото банана');
    expect(svg, startsWith('<svg'));
    expect(svg, contains('<path'));
    expect(svg, endsWith('</svg>'));
  });

  test('SVG generation reports model refusal instead of generic error',
      () async {
    final ai = _testAi('SVG_UNSUPPORTED');
    expect(
      () => ai.generateSvg('банан'),
      throwsA(predicate((e) => e.toString().contains('svg_model_unsupported'))),
    );
  });
}
