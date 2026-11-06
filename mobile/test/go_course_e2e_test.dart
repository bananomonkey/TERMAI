import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';

void main() {
  test('все решения go-курса исполняются в песочнице', () {
    final courses = jsonDecode(File('assets/courses.json').readAsStringSync()) as List;
    final go = courses.firstWhere((c) => c['id'] == 'go-basics');
    for (final t in (go['tasks'] as List)) {
      final st = SandboxState.fromJson(jsonDecode(jsonEncode(t['start_state'])));
      var sol = (t['solution'] as String)
          .replaceAll('```', '')
          .split('\nОжидаемо')
          .first
          .trim();
      final lines = sol.split('\n').where((l) => l.trim().isNotEmpty).toList();
      String out = '';
      for (final line in lines) {
        final r = tryLocalCommand(line.trim(), st);
        if (r == null) out += '[ИИ-симулятор] $line\n';
        else if (r.out.trim().isNotEmpty) out += '${r.out}\n';
      }
      // ignore: avoid_print
      print('=== ${t['id']}\n$out');
      expect(st.events.where((e) => e.startsWith('go ')), isNotEmpty,
          reason: '${t['id']}: нет go-событий');
    }
  });
}
