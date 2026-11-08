// incidents.dart — инцидент-режим: сломанная «продукция» в песочнице,
// чинишь по симптомам. Сценарии детерминированные (без ИИ): стартовое
// состояние ломается заранее, проверка — через штатный tryVerifyTask.
import 'dart:convert';

import 'models.dart';

class IncidentScenario {
  final String id;
  final String title;
  final String brief;
  final String goal;
  final List<String> theory;
  final List<String> hints;
  final String check;
  final String solution;
  final Map<String, dynamic> startState;
  final Map<String, dynamic> verify;

  const IncidentScenario({
    required this.id,
    required this.title,
    required this.brief,
    required this.goal,
    required this.theory,
    required this.hints,
    required this.check,
    required this.solution,
    required this.startState,
    required this.verify,
  });

  Task toTask() => Task.fromJson({
        'id': 'incident-$id',
        'title': title,
        'kind': 'cmd',
        'difficulty': 3,
        'theory': theory,
        'goal': goal,
        'hints': hints,
        'check': check,
        'expected_output': '',
        'solution': solution,
        'quiz': const [],
        'start_state': startState,
        'verify': verify,
      });
}

final _ns = {
  'kind': 'Namespace',
  'name': 'default',
  'namespace': 'default',
  'raw': 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: default',
  'spec': {},
  'replicas': 0,
  'ready': 0,
  'status': 'Active',
};

Map<String, dynamic> _deployment(String name, String image, int replicas,
        {int ready = -1}) =>
    {
      'kind': 'Deployment',
      'name': name,
      'namespace': 'default',
      'raw': 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: $name',
      'spec': {'replicas': replicas},
      'replicas': replicas,
      'ready': ready < 0 ? replicas : ready,
      'status': 'Ready',
      'logs': '',
      'revision': 1,
      'image': image,
    };

Map<String, dynamic> _pod(String name, String status, String logs,
        {String image = ''}) =>
    {
      'kind': 'Pod',
      'name': name,
      'namespace': 'default',
      'raw': 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: $name',
      'spec': {},
      'replicas': 0,
      'ready': 0,
      'status': status,
      'logs': logs,
      'revision': 0,
      'image': image,
    };

Map<String, dynamic> _state(Map<String, dynamic> k8s,
        {Map<String, String> files = const {}, List<String> events = const []}) =>
    {
      'workdir': '/workspace',
      'files': Map<String, String>.from(files),
      'images': {},
      'containers': {},
      'volumes': {},
      'networks': ['bridge', 'host', 'none'],
      'events': [],
      // Глубокая копия: сценарии не должны делить ресурсы, песочница
      // мутирует их по ходу разбора.
      'k8s': k8s.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v))),
      'k8s_events': List<String>.from(events),
      'last_output': '',
    };

final List<IncidentScenario> incidentScenarios = [
  IncidentScenario(
    id: 'crashloop',
    title: 'Инцидент: платежи лежат',
    brief:
        'Мониторинг горит: под api в CrashLoopBackOff, платежи не проходят. Разберись и верни сервис.',
    goal:
        'Диагностируй падение пода (logs + describe), исправь манифест на рабочий образ repo/api:v2 и добейся пода в Running.',
    theory: [
      'Порядок разбора инцидента всегда один: `kubectl get pods` — что горит; `kubectl logs ИМЯ` — что говорит приложение; `kubectl describe pod ИМЯ` — Events говорят, что именно сломалось.',
      'CrashLoopBackOff = контейнер стартует и сразу умирает. Причины: паника в коде, неверный конфиг, недоступная зависимость, кривой образ.',
      'Чинится не «перезапуском», а исправлением манифеста: поправил YAML → `kubectl apply -f файл.yaml` → проверил `kubectl get pods`.',
    ],
    hints: [
      'Начни с kubectl get pods — увидишь CrashLoopBackOff.',
      'kubectl logs api-7d9f6-x1 покажет панику.',
      'Исправь образ в api.yaml через echo и примени kubectl apply -f api.yaml.',
    ],
    check: 'Падение продиагностировано (logs/describe), манифест применён, новый под в Running.',
    solution:
        '```bash\nkubectl get pods\nkubectl logs api-7d9f6-x1\nkubectl describe pod api-7d9f6-x1\necho \'apiVersion: v1\' > fix.yaml\necho \'kind: Pod\' >> fix.yaml\necho \'metadata:\' >> fix.yaml\necho \'  name: api-fixed\' >> fix.yaml\necho \'spec:\' >> fix.yaml\necho \'  containers:\' >> fix.yaml\necho \'  - name: api\' >> fix.yaml\necho \'    image: repo/api:v2\' >> fix.yaml\nkubectl apply -f fix.yaml\nkubectl get pods\n```',
    startState: _state({
      'namespace/default/default': _ns,
      'deployment/default/api': _deployment('api', 'repo/api:v2-broken', 1, ready: 0),
      'pod/default/api-7d9f6-x1': _pod('api-7d9f6-x1', 'CrashLoopBackOff',
          'panic: payments config missing: dial tcp 127.0.0.1:8080: connection refused',
          image: 'repo/api:v2-broken'),
    }, events: [
      'Warning BackOff pod/api-7d9f6-x1: Back-off restarting failed container',
      'Warning Failed pod/api-7d9f6-x1: Error: payments config missing',
    ]),
    verify: {
      'checks': [
        {'event_contains': 'logs'},
        {'event_contains': 'describe'},
        {'event_contains': 'apply -f'},
        {
          'kind': 'Pod',
          'name': 'api-fixed',
          'namespace': 'default',
          'field': 'status',
          'equals': 'Running'
        },
      ]
    },
  ),
  IncidentScenario(
    id: 'badrollout',
    title: 'Инцидент: выкатка сломала каталог',
    brief:
        'После выката новой версии каталог отдаёт 500. Откатить на предыдущую ревизию и убедиться, что поды живые.',
    goal:
        'Откати деплоймент catalog через kubectl rollout undo и убедись, что ревизия вернулась и под в Running.',
    theory: [
      '`kubectl rollout history deployment/ИМЯ` показывает ревизии, `rollout undo` откатывает на предыдущую.',
      'Откат через undo — штатная операция: ReplicaSet старой версии уже лежит в кластере, ничего пересобирать не нужно.',
    ],
    hints: [
      'kubectl rollout undo deployment/catalog.',
      'Проверь: kubectl get pods — поды должны быть в Running.',
    ],
    check: 'rollout undo выполнен, деплоймент откати́лся, поды в Running.',
    solution:
        '```bash\nkubectl get pods\nkubectl rollout undo deployment/catalog\nkubectl get pods\n```',
    startState: _state({
      'namespace/default/default': _ns,
      'deployment/default/catalog':
          _deployment('catalog', 'shop/catalog:v9-bad', 2, ready: 0),
      'pod/default/catalog-5cc8a-p1': _pod('catalog-5cc8a-p1', 'CrashLoopBackOff',
          'java.lang.IllegalStateException: schema v9 mismatch', image: 'shop/catalog:v9-bad'),
      'pod/default/catalog-5cc8a-p2': _pod('catalog-5cc8a-p2', 'CrashLoopBackOff',
          'java.lang.IllegalStateException: schema v9 mismatch', image: 'shop/catalog:v9-bad'),
    }, events: [
      'Warning BackOff pod/catalog-5cc8a-p1: Back-off restarting failed container',
    ]),
    verify: {
      'checks': [
        {'event_contains': 'rollout undo'},
        {'event_contains': 'kubectl get pods'},
        {
          'kind': 'Pod',
          'name': 'catalog-5cc8a-p1',
          'namespace': 'default',
          'field': 'status',
          'equals': 'Running'
        },
      ]
    },
  ),
  IncidentScenario(
    id: 'scaledown',
    title: 'Инцидент: кто-то убил реплики',
    brief:
        'Хэлсчек орет: инстансов web ноль. Кто-то отскейлил деплоймент в ночь. Верни 3 реплики.',
    goal: 'Верни деплойменту web 3 реплики через kubectl scale и проверь результат.',
    theory: [
      '`kubectl get deploy` показывает READY 0/3 — контроллер не может поднять нужное число подов.',
      '`kubectl scale deployment/web --replicas=3` возвращает желаемое состояние. Причина таких инцидентов — чужие руки в кластере: меняй через манифест, а не руками.',
    ],
    hints: [
      'kubectl get deployment web — увидишь 0/3.',
      'kubectl scale deployment web --replicas=3.',
    ],
    check: 'У деплоймента web снова 3 реплики.',
    solution:
        '```bash\nkubectl get deployment\nkubectl scale deployment web --replicas=3\nkubectl get deployment\n```',
    startState: _state({
      'namespace/default/default': _ns,
      'deployment/default/web': _deployment('web', 'shop/web:v3', 0, ready: 0),
    }),
    verify: {
      'checks': [
        {'event_contains': 'scale'},
        {
          'kind': 'Deployment',
          'name': 'web',
          'namespace': 'default',
          'field': 'spec.replicas',
          'equals': 3
        },
      ]
    },
  ),
  IncidentScenario(
    id: 'dirtyrepo',
    title: 'Инцидент: чужой коммит в ветке',
    brief:
        'В ветке main появился подозрительный файл config.bak. Найди его, убедись в статусе репозитория и убери.',
    goal: 'Найди лишний файл через git status, удали его с диска и убедись, что рабочее дерево чистое.',
    theory: [
      'Инциденты бывают не только в кластере: чужой артефакт в репозитории — тоже инцидент поставки.',
      '`git status` показывает незакоммиченное. Убрать файл с диска — `rm файл`, статус снова покажет чистое дерево.',
    ],
    hints: [
      'git status покажет untracked config.bak.',
      'rm config.bak, затем git status ещё раз.',
    ],
    check: 'Лишний файл найден и удалён, git status показывает чистое дерево.',
    solution:
        '```bash\ngit status\nrm config.bak\ngit status\n```',
    startState: {
      'workdir': '/workspace',
      'files': {
        '.git/HEAD': 'ref: refs/heads/main',
        '.git/committed.txt': 'app.py\n',
        'app.py': 'print("ok")',
        'config.bak': 'password=hunter2',
      },
      'images': {},
      'containers': {},
      'volumes': {},
      'networks': ['bridge', 'host', 'none'],
      'events': ['git init'],
      'k8s': {},
      'k8s_events': [],
      'last_output': '',
    },
    verify: {
      'checks': [
        {'event_contains': 'git status'},
        {'file_regex': 'app.py'},
      ]
    },
  ),
];

/// buildIncidentCourse — скрытый курс из сценария: переиспользует терминал,
/// проверку и окно завершения. Id начинается с 'incident-', чтобы стор мог
/// почистить его после разбора.
Course buildIncidentCourse(IncidentScenario sc) => Course.fromJson({
      'id': 'incident-${sc.id}',
      'title': sc.title,
      'desc': sc.brief,
      'category': 'professions',
      'direction': 'devops',
      'mode': 'terminal',
      'syllabus': [sc.title],
      'tasks': [sc.toTask().toJson()],
    });

String incidentCourseId(IncidentScenario sc) => 'incident-${sc.id}';

Map<String, dynamic> incidentCourseJson(IncidentScenario sc) =>
    jsonDecode(jsonEncode(buildIncidentCourse(sc).toJson()))
        as Map<String, dynamic>;
