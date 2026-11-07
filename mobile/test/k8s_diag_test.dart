import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';

void main() {
  test('решение диагностики k8s доводит под до Running', () {
    final courses = jsonDecode(File('assets/courses.json').readAsStringSync()) as List;
    final k = courses.firstWhere((c) => c['id'] == 'kubernetes');
    final t = (k['tasks'] as List).firstWhere((x) => x['id'] == 'k8s-34-diag');
    final st = SandboxState.fromJson(jsonDecode(jsonEncode(t['start_state'])));
    final sol = (t['solution'] as String).replaceAll('```', '').split('\nОжидаемо').first.trim();
    var out = '';
    for (final line in sol.split('\n').where((l) => l.trim().isNotEmpty)) {
      final r = tryLocalCommand(line.trim(), st);
      if (r != null && r.out.trim().isNotEmpty) out += '${r.out}\n';
    }
    // ignore: avoid_print
    print(out);
    expect(out, contains('CrashLoopBackOff'));
    expect(out, contains('api-fixed'));
    expect(st.k8s['pod/default/api-fixed']?['status'], 'Running');
  });
}
