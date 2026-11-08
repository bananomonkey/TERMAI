import 'package:flutter_test/flutter_test.dart';
import 'package:termai/incidents.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';
import 'package:termai/k8s_sandbox.dart';

void main() {
  test('каждый инцидент решается своим решением через песочницу', () {
    expect(incidentScenarios.length, greaterThanOrEqualTo(4));
    for (final sc in incidentScenarios) {
      final task = sc.toTask();
      expect(task.id, 'incident-${sc.id}');
      expect(task.verify.isNotEmpty, isTrue,
          reason: '${sc.id}: нет машинной проверки');
      final st = SandboxState.fromJson(
          Map<String, dynamic>.from(sc.startState));
      final hist = <HistEntry>[];
      final sol = sc.solution
          .replaceAll('```bash', '')
          .replaceAll('```', '')
          .trim();
      for (final line in sol.split('\n')) {
        final cmd = line.trim();
        if (cmd.isEmpty) continue;
        final r = tryLocalCommand(cmd, st);
        hist.add(HistEntry(cmd: cmd, out: r?.out ?? ''));
      }
      final check = tryVerifyTask(task, st, history: hist);
      expect(check?.ok, isTrue,
          reason: '${sc.id}: ${check?.message}');
    }
  });

  test('курс инцидента строится и имеет одну cmd-задачу', () {
    final c = buildIncidentCourse(incidentScenarios.first);
    expect(c.id, 'incident-crashloop');
    expect(c.tasks.length, 1);
    expect(c.tasks.first.kind, 'cmd');
    expect(c.direction, 'devops');
  });
}
