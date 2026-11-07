import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';

void main() {
  test('debug apply pod', () {
    final courses = jsonDecode(File('assets/courses.json').readAsStringSync()) as List;
    final k = courses.firstWhere((c) => c['id'] == 'kubernetes');
    final t = (k['tasks'] as List).firstWhere((x) => x['id'] == 'k8s-34-diag');
    final st = SandboxState.fromJson(jsonDecode(jsonEncode(t['start_state'])));
    final sol = (t['solution'] as String).replaceAll('```', '').split('\nОжидаемо').first.trim();
    for (final line in sol.split('\n').where((l) => l.trim().isNotEmpty)) {
      final r = tryLocalCommand(line.trim(), st);
      if (line.contains('apply')) {
        // ignore: avoid_print
        print('APPLY OUT: ${r?.out}');
      }
    }
    // ignore: avoid_print
    print('K8S KEYS: ${st.k8s.keys}');
    // ignore: avoid_print
    print('pod file: ${st.files['pod-api.yaml']}');
  });
}
