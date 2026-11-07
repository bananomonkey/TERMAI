import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termai/k8s_sandbox.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';

void main() {
  test('kubectl apply создаёт Deployment и проверка проходит', () {
    final st = SandboxState(files: {
      'deployment.yaml': '''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27
'''
    });
    final result = tryLocalCommand('kubectl apply -f deployment.yaml', st)!;
    expect(result.handled, isTrue);
    expect(st.k8s.keys, contains('deployment/default/web'));

    final task = Task(
      id: 't',
      title: 'Deployment',
      goal: 'apply',
      verify: {
        'checks': [
          {
            'kind': 'Deployment',
            'name': 'web',
            'field': 'spec.replicas',
            'equals': 2,
          }
        ]
      },
    );
    expect(tryVerifyTask(task, st)?.ok, isTrue);
  });

  test('kubectl apply создаёт Pod и статус Running проверяется', () {
    final st = SandboxState(files: {
      'pod.yaml': '''
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
    - name: web
      image: nginx:1.27
'''
    });
    tryLocalCommand('kubectl apply -f pod.yaml', st);
    final task = Task(
      id: 'p',
      title: 'Pod',
      goal: 'apply',
      verify: {
        'checks': [
          {
            'kind': 'Pod',
            'name': 'web',
            'field': 'status',
            'equals': 'Running',
          }
        ]
      },
    );
    expect(tryVerifyTask(task, st)?.ok, isTrue);
  });

  test('kubectl scale меняет replicas, rollback меняет revision', () {
    final st = SandboxState(k8s: {
      'deployment/default/web': {
        'kind': 'Deployment',
        'name': 'web',
        'namespace': 'default',
        'spec': {'replicas': 1},
        'replicas': 1,
        'revision': 1,
        'raw': 'kind: Deployment',
      }
    });
    tryLocalCommand('kubectl scale deployment/web --replicas=3', st);
    final scaleCheck = tryVerifyTask(
      Task(id: 's', title: 'scale', goal: 'scale', verify: {
        'checks': [
          {
            'kind': 'Deployment',
            'name': 'web',
            'field': 'spec.replicas',
            'equals': 3,
          }
        ]
      }),
      st,
    );
    expect(scaleCheck?.ok, isTrue);

    tryLocalCommand('kubectl rollout undo deployment/web', st);
    final undoCheck = tryVerifyTask(
      Task(id: 'u', title: 'undo', goal: 'undo', verify: {
        'checks': [
          {
            'kind': 'Deployment',
            'name': 'web',
            'field': 'revision',
            'equals': 2,
          }
        ]
      }),
      st,
    );
    expect(undoCheck?.ok, isTrue);
  });

  test('kubectl logs и describe дают материал для диагностики', () {
    final st = SandboxState(
      k8s: {
        'pod/default/api-broken': {
          'kind': 'Pod',
          'name': 'api-broken',
          'namespace': 'default',
          'status': 'CrashLoopBackOff',
          'logs': 'panic: database connection refused',
          'raw': 'kind: Pod',
        }
      },
      k8sEvents: [
        'Warning FailedScheduling 1m default-scheduler Insufficient cpu.'
      ],
    );
    tryLocalCommand('kubectl logs api-broken', st);
    expect(st.lastOutput, contains('panic'));

    tryLocalCommand('kubectl describe pod api-broken', st);
    expect(st.lastOutput, contains('CrashLoopBackOff'));
    expect(st.lastOutput, contains('Insufficient cpu'));
  });

  test('финальный проект Kubernetes проходит локальную проверку', () {
    final raw = File('assets/courses.json').readAsStringSync();
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final k8s =
        list.map(Course.fromJson).firstWhere((c) => c.id == 'kubernetes');
    final task = k8s.tasks.firstWhere((t) => t.id == 'k8s-33-final');
    final st = task.start.clone();
    tryLocalCommand('kubectl apply -f app.yaml', st);
    final check = tryVerifyTask(task, st);
    expect(check?.ok, isTrue, reason: check?.message);
  });

  test('все практические задания Kubernetes проходят по своим решениям', () {
    final raw = File('assets/courses.json').readAsStringSync();
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final k8s =
        list.map(Course.fromJson).firstWhere((c) => c.id == 'kubernetes');
    final block = RegExp(r'```bash\n(.*?)```', dotAll: true);

    for (final task in k8s.tasks) {
      if (task.verify.isEmpty) continue;
      final st = task.start.clone();
      final hist = <HistEntry>[];
      final matches = block.allMatches(task.solution);
      expect(matches, isNotEmpty, reason: '${task.id}: нет bash-решения');
      for (final m in matches) {
        for (final line in m.group(1)!.split('\n')) {
          final cmd = line.trim();
          if (cmd.isEmpty || cmd.startsWith('#')) continue;
          final r = tryLocalCommand(cmd, st);
          // как в приложении: команда и вывод попадают в transcript проверки
          hist.add(HistEntry(cmd: cmd, out: r?.out ?? ''));
        }
      }
      final check = tryVerifyTask(task, st, history: hist);
      expect(check?.ok, isTrue, reason: '${task.id}: ${check?.message}');
    }
  });
}
