// k8s_sandbox.dart — небольшой, но проверяемый kubectl-слой для курса
// Kubernetes. Он не изображает «нажатие кнопки»: команды меняют состояние
// мини-кластера, а задания проверяют именно это состояние.
import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'models.dart';
import 'sandbox.dart';

class LocalCheck {
  final bool ok;
  final String message;
  const LocalCheck(this.ok, this.message);
}

LocalResult? tryKubectl(List<String> args, SandboxState st) {
  if (args.isEmpty) {
    _out(st,
        'kubectl controls the Kubernetes cluster manager.\n\nUsage:\n  kubectl <command>');
    return LocalResult(true, st.lastOutput);
  }
  var rest = List<String>.from(args);
  var namespace = 'default';
  var allNamespaces = false;
  for (var i = 0; i < rest.length; i++) {
    final a = rest[i];
    if (a == '-n' || a == '--namespace') {
      if (i + 1 < rest.length) {
        namespace = rest[i + 1];
        rest.removeRange(i, i + 2);
        i--;
      }
    } else if (a.startsWith('--namespace=')) {
      namespace = a.substring('--namespace='.length);
      rest.removeAt(i);
      i--;
    } else if (a == '-A' || a == '--all-namespaces') {
      allNamespaces = true;
      rest.removeAt(i);
      i--;
    }
  }
  if (rest.isEmpty) return LocalResult(true, st.lastOutput);
  final cmd = rest.first;
  final a = rest.sublist(1);
  switch (cmd) {
    case 'version':
      _out(st, 'Client Version: v1.31.0\nServer Version: v1.31.0');
      return LocalResult(true, st.lastOutput);
    case 'config':
      _out(st, 'termai-lab');
      return LocalResult(true, st.lastOutput);
    case 'get':
      return _get(st, a, namespace, allNamespaces);
    case 'describe':
      return _describe(st, a, namespace);
    case 'apply':
      return _apply(st, a, namespace);
    case 'create':
      return _create(st, a, namespace);
    case 'delete':
      return _delete(st, a, namespace);
    case 'scale':
      return _scale(st, a, namespace);
    case 'rollout':
      return _rollout(st, a, namespace);
    case 'set':
      return _set(st, a, namespace);
    case 'logs':
      return _logs(st, a, namespace);
    case 'exec':
      return _exec(st, a, namespace);
    case 'top':
      _out(st,
          'NAME        CPU(cores)   MEMORY(bytes)\nnode-1      12m          84Mi');
      return LocalResult(true, st.lastOutput);
  }
  _out(st, 'error: unknown command "$cmd" for "kubectl"');
  return LocalResult(true, st.lastOutput);
}

void _out(SandboxState st, String text) {
  st.lastOutput = text;
  st.events.add('kubectl:${text.split('\n').first}');
}

String _key(String kind, String namespace, String name) =>
    '${kind.toLowerCase()}/$namespace/$name';

String _canonicalKind(String raw) {
  final k = raw.toLowerCase().replaceAll(' ', '');
  return switch (k) {
    'po' || 'pod' || 'pods' => 'Pod',
    'deploy' || 'deployment' || 'deployments' => 'Deployment',
    'rs' || 'replicaset' || 'replicasets' => 'ReplicaSet',
    'sts' || 'statefulset' || 'statefulsets' => 'StatefulSet',
    'ds' || 'daemonset' || 'daemonsets' => 'DaemonSet',
    'svc' || 'service' || 'services' => 'Service',
    'cm' || 'configmap' || 'configmaps' => 'ConfigMap',
    'secret' || 'secrets' => 'Secret',
    'ing' || 'ingress' || 'ingresses' => 'Ingress',
    'netpol' || 'networkpolicy' || 'networkpolicies' => 'NetworkPolicy',
    'ns' || 'namespace' || 'namespaces' => 'Namespace',
    'pv' || 'persistentvolume' || 'persistentvolumes' => 'PersistentVolume',
    'pvc' ||
    'persistentvolumeclaim' ||
    'persistentvolumeclaims' =>
      'PersistentVolumeClaim',
    'sc' || 'storageclass' || 'storageclasses' => 'StorageClass',
    'job' || 'jobs' => 'Job',
    'cronjob' || 'cronjobs' => 'CronJob',
    'sa' || 'serviceaccount' || 'serviceaccounts' => 'ServiceAccount',
    'role' || 'roles' => 'Role',
    'rolebinding' || 'rolebindings' => 'RoleBinding',
    'event' || 'events' => 'Event',
    _ => raw,
  };
}

String _resourceName(Map<String, dynamic> r) =>
    (r['name'] ?? (r['metadata'] as Map?)?['name'] ?? '').toString();

String _resourceNs(Map<String, dynamic> r) =>
    (r['namespace'] ?? (r['metadata'] as Map?)?['namespace'] ?? 'default')
        .toString();

dynamic _deepPlain(dynamic v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), _deepPlain(value)));
  }
  if (v is Iterable) return v.map(_deepPlain).toList();
  return v;
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? _deepPlain(v).cast<String, dynamic>() : <String, dynamic>{};

Map<String, dynamic> _manifest(String raw) {
  final doc = loadYaml(raw);
  if (doc is! Map) return {};
  final map = _asMap(doc);
  final metadata = _asMap(map['metadata']);
  final kind = _canonicalKind((map['kind'] ?? '').toString());
  final name = (metadata['name'] ?? '').toString();
  if (kind.isEmpty || name.isEmpty) return {};
  final ns = kind == 'Namespace'
      ? (metadata['namespace'] ?? name).toString()
      : (metadata['namespace'] ?? 'default').toString();
  final spec = _asMap(map['spec']);
  final data = _asMap(map['data']);
  final replicas = (spec['replicas'] as num?)?.toInt() ??
      (kind == 'Deployment' || kind == 'StatefulSet' ? 1 : 0);
  final images = <String>[];
  final template = _asMap(spec['template']);
  final podSpec = _asMap(template['spec'] ?? spec);
  final containers = (podSpec['containers'] as List?) ?? const [];
  for (final c in containers) {
    final cm = _asMap(c);
    final image = (cm['image'] ?? '').toString();
    if (image.isNotEmpty) images.add(image);
  }
  return {
    'kind': kind,
    'name': name,
    'namespace': ns,
    'apiVersion': map['apiVersion'] ?? '',
    'metadata': metadata,
    'spec': spec,
    'data': data,
    'raw': raw.trim(),
    'replicas': replicas,
    'ready': kind == 'Pod' ? 1 : replicas,
    'status': kind == 'Pod' ? 'Running' : 'Ready',
    'image': images.isEmpty ? '' : images.first,
    'images': images,
    'revision': 1,
  };
}

List<Map<String, dynamic>> _manifests(String text) {
  final out = <Map<String, dynamic>>[];
  final chunks = text.split(RegExp(r'^---\s*$', multiLine: true));
  for (final chunk in chunks) {
    if (chunk.trim().isEmpty) continue;
    try {
      final m = _manifest(chunk);
      if (m.isNotEmpty) out.add(m);
    } catch (_) {
      // невалидный YAML не должен ломать всю песочницу
    }
  }
  return out;
}

Map<String, dynamic>? _find(SandboxState st, String kind, String name,
    {String? namespace}) {
  for (final r in st.k8s.values) {
    if (_resourceName(r).toLowerCase() != name.toLowerCase()) continue;
    if (_canonicalKind((r['kind'] ?? '').toString()).toLowerCase() !=
        kind.toLowerCase()) {
      continue;
    }
    if (kind != 'Namespace' &&
        namespace != null &&
        _resourceNs(r) != namespace) {
      continue;
    }
    return r;
  }
  return null;
}

List<Map<String, dynamic>> _list(SandboxState st, String kind,
    {String? namespace, bool allNamespaces = false}) {
  final out = st.k8s.values.where((r) {
    if (_canonicalKind((r['kind'] ?? '').toString()).toLowerCase() !=
        kind.toLowerCase()) return false;
    if (allNamespaces || kind == 'Namespace') return true;
    return namespace == null || _resourceNs(r) == namespace;
  }).toList()
    ..sort((a, b) => _resourceName(a).compareTo(_resourceName(b)));
  return out;
}

void _put(SandboxState st, Map<String, dynamic> r) {
  st.k8s[_key(_canonicalKind(r['kind'].toString()), _resourceNs(r),
      _resourceName(r))] = r;
}

LocalResult _get(
    SandboxState st, List<String> a, String namespace, bool allNamespaces) {
  if (a.isEmpty) {
    _out(st, 'error: You must specify the type of resource to get');
    return LocalResult(true, st.lastOutput);
  }
  final kind = _canonicalKind(a.first);
  final name = a.length > 1 && !a[1].startsWith('-') ? a[1] : null;
  final items = _list(st, kind,
          namespace: namespace, allNamespaces: allNamespaces)
      .where((r) =>
          name == null || _resourceName(r).toLowerCase() == name.toLowerCase())
      .toList();
  if (items.isEmpty) {
    _out(st, 'No resources found in $namespace namespace.');
    return LocalResult(true, st.lastOutput);
  }
  final showsNs = allNamespaces || kind == 'Namespace';
  final b = StringBuffer();
  if (kind == 'Namespace') {
    b.writeln('NAME              STATUS   AGE');
    for (final r in items) {
      b.writeln('${_resourceName(r).padRight(17)}Active   1m');
    }
  } else if (kind == 'Pod') {
    b.writeln(showsNs
        ? 'NAMESPACE   NAME                 READY   STATUS    RESTARTS   AGE'
        : 'NAME                 READY   STATUS    RESTARTS   AGE');
    for (final r in items) {
      final status = (r['status'] ?? 'Running').toString();
      final ready = status == 'Running' ? '1/1' : '0/1';
      final prefix = showsNs ? '${_resourceNs(r).padRight(11)} ' : '';
      b.writeln(
          '$prefix${_resourceName(r).padRight(20)} $ready   ${status.padRight(9)} 0          1m');
    }
  } else if (kind == 'Deployment' || kind == 'StatefulSet') {
    b.writeln(showsNs
        ? 'NAMESPACE   NAME      READY   UP-TO-DATE   AVAILABLE   AGE'
        : 'NAME      READY   UP-TO-DATE   AVAILABLE   AGE');
    for (final r in items) {
      final n = (r['replicas'] as num?)?.toInt() ?? 0;
      final prefix = showsNs ? '${_resourceNs(r).padRight(11)} ' : '';
      b.writeln(
          '$prefix${_resourceName(r).padRight(9)} $n/$n     $n            $n           1m');
    }
  } else if (kind == 'Service') {
    b.writeln(showsNs
        ? 'NAMESPACE   NAME      TYPE        CLUSTER-IP     PORT(S)   AGE'
        : 'NAME      TYPE        CLUSTER-IP     PORT(S)   AGE');
    for (final r in items) {
      final spec = _asMap(r['spec']);
      final type = (spec['type'] ?? 'ClusterIP').toString();
      final prefix = showsNs ? '${_resourceNs(r).padRight(11)} ' : '';
      b.writeln(
          '$prefix${_resourceName(r).padRight(9)} ${type.padRight(11)} 10.96.0.10     80/TCP    1m');
    }
  } else {
    b.writeln(showsNs
        ? 'NAMESPACE   NAME                 AGE'
        : 'NAME                 AGE');
    for (final r in items) {
      final prefix = showsNs ? '${_resourceNs(r).padRight(11)} ' : '';
      b.writeln('$prefix${_resourceName(r).padRight(20)} 1m');
    }
  }
  _out(st, b.toString().trimRight());
  return LocalResult(true, st.lastOutput);
}

LocalResult _describe(SandboxState st, List<String> a, String namespace) {
  if (a.length < 2) {
    _out(st, 'error: describe requires a resource type and name');
    return LocalResult(true, st.lastOutput);
  }
  final kind = _canonicalKind(a.first);
  final r = _find(st, kind, a[1], namespace: namespace);
  if (r == null) {
    _out(st, 'Error from server (NotFound): $kind "${a[1]}" not found');
    return LocalResult(true, st.lastOutput);
  }
  final events = st.k8sEvents.isEmpty
      ? '  Type     Reason     Age   From               Message\n  Normal   Scheduled  1m    default-scheduler  Successfully assigned'
      : st.k8sEvents.map((e) => '  $e').join('\n');
  _out(st,
      '${r['raw'] ?? ''}\n\nStatus: ${r['status'] ?? 'Ready'}\n\nEvents:\n$events');
  return LocalResult(true, st.lastOutput);
}

LocalResult _apply(SandboxState st, List<String> a, String namespace) {
  final fi = a.indexOf('-f');
  if (fi < 0 || fi + 1 >= a.length) {
    _out(st, 'error: must specify one of -f and -k');
    return LocalResult(true, st.lastOutput);
  }
  final file = a[fi + 1];
  final body = st.files[file];
  if (body == null) {
    _out(st, 'error: the path "$file" does not exist');
    return LocalResult(true, st.lastOutput);
  }
  final list = _manifests(body);
  if (list.isEmpty) {
    _out(st, 'error: no valid Kubernetes objects found in $file');
    return LocalResult(true, st.lastOutput);
  }
  final out = <String>[];
  for (final r in list) {
    if ((r['namespace'] ?? 'default') == 'default' &&
        namespace != 'default' &&
        r['kind'] != 'Namespace') {
      r['namespace'] = namespace;
    }
    _put(st, r);
    out.add(
        '${r['kind'].toString().toLowerCase()}/${_resourceName(r)} created');
    st.k8sEvents.add('Normal Applied ${_resourceName(r)}');
  }
  _out(st, out.join('\n'));
  return LocalResult(true, st.lastOutput);
}

LocalResult _create(SandboxState st, List<String> a, String namespace) {
  if (a.isEmpty) {
    _out(st, 'error: create requires a resource type');
    return LocalResult(true, st.lastOutput);
  }
  if (a.first == 'namespace' && a.length > 1) {
    final r = {
      'kind': 'Namespace',
      'name': a[1],
      'namespace': a[1],
      'raw': 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: ${a[1]}',
      'spec': <String, dynamic>{},
      'replicas': 0,
      'ready': 0,
    };
    _put(st, r);
    _out(st, 'namespace/${a[1]} created');
    return LocalResult(true, st.lastOutput);
  }
  if (a.first == 'deployment' && a.length > 1) {
    final imageArg =
        a.firstWhere((x) => x.startsWith('--image='), orElse: () => '');
    final image = imageArg.isEmpty ? 'nginx' : imageArg.substring(8);
    final name = a[1];
    final r = {
      'kind': 'Deployment',
      'name': name,
      'namespace': namespace,
      'raw':
          'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: $name\nspec:\n  replicas: 1',
      'spec': {
        'replicas': 1,
        'template': {
          'spec': {
            'containers': [
              {'name': name, 'image': image}
            ]
          }
        }
      },
      'replicas': 1,
      'ready': 1,
      'image': image,
    };
    _put(st, r);
    _out(st, 'deployment.apps/$name created');
    return LocalResult(true, st.lastOutput);
  }
  _out(st, 'error: unsupported create form (use YAML with kubectl apply -f)');
  return LocalResult(true, st.lastOutput);
}

LocalResult _delete(SandboxState st, List<String> a, String namespace) {
  if (a.length < 2) {
    _out(st, 'error: delete requires a resource type and name');
    return LocalResult(true, st.lastOutput);
  }
  final kind = _canonicalKind(a.first);
  final r = _find(st, kind, a[1], namespace: namespace);
  if (r == null) {
    _out(st, 'Error from server (NotFound): $kind "${a[1]}" not found');
    return LocalResult(true, st.lastOutput);
  }
  st.k8s.remove(_key(kind, _resourceNs(r), _resourceName(r)));
  _out(st, '${kind.toLowerCase()}/"${a[1]}" deleted');
  return LocalResult(true, st.lastOutput);
}

LocalResult _scale(SandboxState st, List<String> a, String namespace) {
  if (a.isEmpty) {
    _out(st, 'error: scale requires a resource');
    return LocalResult(true, st.lastOutput);
  }
  var ref = a.first;
  String? name;
  String kind = 'Deployment';
  if (ref.contains('/')) {
    kind = _canonicalKind(ref.split('/').first);
    name = ref.split('/').last;
  } else if (a.length > 1) {
    name = a[1];
  }
  final ri = a.indexWhere((x) => x.startsWith('--replicas='));
  final n =
      ri >= 0 ? int.tryParse(a[ri].substring('--replicas='.length)) ?? 1 : 1;
  final r = name == null ? null : _find(st, kind, name, namespace: namespace);
  if (r == null) {
    _out(st, 'error: $kind not found');
    return LocalResult(true, st.lastOutput);
  }
  r['replicas'] = n;
  r['ready'] = n;
  final spec = r['spec'];
  if (spec is Map) spec['replicas'] = n;
  _out(st, '${kind.toLowerCase()}/$name scaled');
  return LocalResult(true, st.lastOutput);
}

LocalResult _rollout(SandboxState st, List<String> a, String namespace) {
  if (a.length < 2) {
    _out(st, 'error: rollout requires status|undo and a resource');
    return LocalResult(true, st.lastOutput);
  }
  final action = a.first;
  final ref = a[1];
  final kind =
      ref.contains('/') ? _canonicalKind(ref.split('/').first) : 'Deployment';
  final name = ref.contains('/') ? ref.split('/').last : ref;
  final r = _find(st, kind, name, namespace: namespace);
  if (r == null) {
    _out(st, 'Error from server (NotFound): $kind "$name" not found');
    return LocalResult(true, st.lastOutput);
  }
  if (action == 'undo') {
    r['revision'] = ((r['revision'] as num?)?.toInt() ?? 1) + 1;
    _out(st, 'deployment.apps/$name rolled back');
  } else {
    _out(st, 'deployment "$name" successfully rolled out');
  }
  return LocalResult(true, st.lastOutput);
}

LocalResult _set(SandboxState st, List<String> a, String namespace) {
  if (a.length < 3 || a.first != 'image') {
    _out(st,
        'error: expected kubectl set image deployment/name container=image');
    return LocalResult(true, st.lastOutput);
  }
  final ref = a[1];
  final kind =
      ref.contains('/') ? _canonicalKind(ref.split('/').first) : 'Deployment';
  final name = ref.contains('/') ? ref.split('/').last : ref;
  final r = _find(st, kind, name, namespace: namespace);
  if (r == null) {
    _out(st, 'Error from server (NotFound): $kind "$name" not found');
    return LocalResult(true, st.lastOutput);
  }
  final image = a[2].contains('=') ? a[2].split('=').last : a[2];
  r['image'] = image;
  r['revision'] = ((r['revision'] as num?)?.toInt() ?? 1) + 1;
  _out(st, '${kind.toLowerCase()}/$name image updated');
  return LocalResult(true, st.lastOutput);
}

LocalResult _logs(SandboxState st, List<String> a, String namespace) {
  if (a.isEmpty) {
    _out(st, 'error: logs requires a pod name');
    return LocalResult(true, st.lastOutput);
  }
  final pod = _find(st, 'Pod', a.first, namespace: namespace);
  if (pod == null) {
    _out(st, 'Error from server (NotFound): pods "${a.first}" not found');
    return LocalResult(true, st.lastOutput);
  }
  final logs = (pod['logs'] ?? '').toString();
  _out(
      st,
      logs.isEmpty
          ? '2026-01-01T10:00:00Z INFO server started\n2026-01-01T10:00:01Z INFO listening on :8080'
          : logs);
  return LocalResult(true, st.lastOutput);
}

LocalResult _exec(SandboxState st, List<String> a, String namespace) {
  if (a.isEmpty) {
    _out(st, 'error: exec requires a pod name');
    return LocalResult(true, st.lastOutput);
  }
  final pod = _find(st, 'Pod', a.first, namespace: namespace);
  if (pod == null) {
    _out(st, 'Error from server (NotFound): pods "${a.first}" not found');
    return LocalResult(true, st.lastOutput);
  }
  _out(st, 'workspace\napp\n');
  return LocalResult(true, st.lastOutput);
}

String? _findSandboxImage(SandboxState st, String ref) {
  if (st.images.containsKey(ref)) return ref;
  for (final e in st.images.entries) {
    final img = e.value;
    if (img.id == ref || img.id.startsWith(ref)) return e.key;
    if ('${img.repo}:${img.tag}' == ref || img.repo == ref) return e.key;
  }
  return null;
}

/// tryVerifyTask — локальная проверка практики по реальному состоянию
/// песочницы: Kubernetes, Docker, файлы и события Git/Linux. Возвращает null,
/// если задача не содержит машинной проверки и должна идти в ИИ.
LocalCheck? tryVerifyTask(Task task, SandboxState st,
    {List<HistEntry> history = const []}) {
  if (task.verify.isEmpty) return null;
  final rawChecks = task.verify['checks'];
  final checks = rawChecks is List
      ? rawChecks.map((e) => _asMap(e)).toList()
      : [task.verify];
  final transcript = [
    st.lastOutput,
    for (final h in history) '${h.cmd}\n${h.out}',
  ].join('\n').toLowerCase();
  final eventHay = '${st.events.join('\n')}\n$transcript'.toLowerCase();
  for (final c in checks) {
    if (c.containsKey('last_output_contains')) {
      final needle = c['last_output_contains'].toString().toLowerCase();
      if (!transcript.contains(needle)) {
        return LocalCheck(false,
            'В выводе пока нет «${c['last_output_contains']}». Выполни нужную команду.');
      }
      continue;
    }
    if (c.containsKey('last_output_regex')) {
      final raw = c['last_output_regex'].toString();
      RegExp re;
      try {
        re = RegExp(raw,
            caseSensitive: c['case_sensitive'] == true, multiLine: true);
      } catch (_) {
        return const LocalCheck(false, 'Ошибка в критерии проверки вывода.');
      }
      if (!re.hasMatch(transcript)) {
        return const LocalCheck(
            false, 'В выводе пока нет нужной структуры. Выполни задание.');
      }
      continue;
    }
    if (c.containsKey('file_exists')) {
      final file = c['file_exists'].toString();
      if (!st.files.containsKey(file)) {
        return LocalCheck(false, 'Файл «$file» ещё не создан.');
      }
      continue;
    }
    if (c.containsKey('file_contains')) {
      final file = c['file_contains'].toString();
      final needle = c['text']?.toString().toLowerCase() ?? '';
      final body = st.files[file]?.toLowerCase() ?? '';
      if (!body.contains(needle)) {
        return LocalCheck(
            false, 'В файле «$file» пока нет нужного содержимого.');
      }
      continue;
    }
    if (c.containsKey('file_regex')) {
      final file = c['file_regex'].toString();
      final body = st.files[file] ?? '';
      final raw = c['pattern']?.toString() ?? c['text']?.toString() ?? '';
      RegExp re;
      try {
        re = RegExp(raw,
            caseSensitive: c['case_sensitive'] == true, multiLine: true);
      } catch (_) {
        return const LocalCheck(false, 'Ошибка в критерии проверки файла.');
      }
      if (!re.hasMatch(body)) {
        return LocalCheck(false, 'В файле «$file» ещё нет нужной структуры.');
      }
      continue;
    }
    if (c.containsKey('image') || c.containsKey('image_exists')) {
      final ref = (c['image'] ?? c['image_exists']).toString();
      final key = _findSandboxImage(st, ref);
      if (key == null) {
        return LocalCheck(false, 'Образ «$ref» пока не собран.');
      }
      final image = st.images[key]!;
      if (c.containsKey('tag') && image.tag != c['tag'].toString()) {
        return LocalCheck(
            false, 'У образа «$ref» тег ${image.tag}, ожидается ${c['tag']}.');
      }
      if (c.containsKey('entrypoint_contains') &&
          !image.entrypoint
              .toLowerCase()
              .contains(c['entrypoint_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'В ENTRYPOINT образа «$ref» нет нужной команды.');
      }
      if (c.containsKey('cmd_contains') &&
          !image.cmd
              .toLowerCase()
              .contains(c['cmd_contains'].toString().toLowerCase())) {
        return LocalCheck(false, 'В CMD образа «$ref» нет нужной команды.');
      }
      if (c.containsKey('env_contains')) {
        final needles = c['env_contains'] is List
            ? (c['env_contains'] as List).map((e) => e.toString()).toList()
            : [c['env_contains'].toString()];
        final env = image.env.join('\n').toLowerCase();
        for (final n in needles) {
          if (!env.contains(n.toLowerCase())) {
            return LocalCheck(false, 'В окружении образа «$ref» нет «$n».');
          }
        }
      }
      if (c.containsKey('size_mb_lt') &&
          image.sizeMb >= (c['size_mb_lt'] as num)) {
        return LocalCheck(false,
            'Образ «$ref» весит ${image.sizeMb.round()} МБ, нужно меньше ${c['size_mb_lt']} МБ.');
      }
      if (c.containsKey('layers_count_gte') &&
          image.layers.length < (c['layers_count_gte'] as num)) {
        return LocalCheck(
            false, 'У образа «$ref» меньше слоёв, чем нужно для задания.');
      }
      if (c.containsKey('layers_contains')) {
        final needles = c['layers_contains'] is List
            ? (c['layers_contains'] as List).map((e) => e.toString()).toList()
            : [c['layers_contains'].toString()];
        final layers = image.layers.join('\n').toLowerCase();
        for (final n in needles) {
          if (!layers.contains(n.toLowerCase())) {
            return LocalCheck(false, 'В слоях образа «$ref» нет «$n».');
          }
        }
      }
      if (c.containsKey('layers_first_contains')) {
        final first = image.layers.isEmpty ? '' : image.layers.first;
        if (!first
            .toLowerCase()
            .contains(c['layers_first_contains'].toString().toLowerCase())) {
          return LocalCheck(
              false, 'Первый слой образа «$ref» не та база, которая нужна.');
        }
      }
      continue;
    }
    if (c.containsKey('container') || c.containsKey('container_exists')) {
      final name = (c['container'] ?? c['container_exists']).toString();
      final box = st.containers[name];
      if (box == null) {
        return LocalCheck(false, 'Контейнер «$name» пока не запущен.');
      }
      if (c.containsKey('status') && box.status != c['status'].toString()) {
        return LocalCheck(false,
            'Контейнер «$name» в статусе ${box.status}, ожидается ${c['status']}.');
      }
      if (c.containsKey('image_contains') &&
          !box.image
              .toLowerCase()
              .contains(c['image_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'Контейнер «$name» запущен не из нужного образа.');
      }
      if (c.containsKey('ports_contains') &&
          !box.ports
              .toLowerCase()
              .contains(c['ports_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'У контейнера «$name» не тот проброс портов: ${box.ports}.');
      }
      if (c.containsKey('mounts_contains') &&
          !box.mounts
              .join('\n')
              .toLowerCase()
              .contains(c['mounts_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'У контейнера «$name» нет нужного монтирования.');
      }
      if (c.containsKey('networks_contains') &&
          !box.networks
              .join('\n')
              .toLowerCase()
              .contains(c['networks_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'Контейнер «$name» не подключён к нужной сети.');
      }
      if (c.containsKey('execs_contains') &&
          !box.execs
              .join('\n')
              .toLowerCase()
              .contains(c['execs_contains'].toString().toLowerCase())) {
        return LocalCheck(
            false, 'Внутри контейнера «$name» не выполнена нужная команда.');
      }
      if (c['logs_viewed'] == true && !box.logsViewed) {
        return LocalCheck(false, 'Логи контейнера «$name» ещё не просмотрены.');
      }
      continue;
    }
    if (c.containsKey('any_container_image_contains')) {
      final needle = c['any_container_image_contains'].toString().toLowerCase();
      final found = st.containers.values
          .any((box) => box.image.toLowerCase().contains(needle));
      if (!found) {
        return LocalCheck(
            false, 'Нет запущенного контейнера из образа «$needle».');
      }
      continue;
    }
    if (c.containsKey('any_container_name_contains')) {
      final needle = c['any_container_name_contains'].toString().toLowerCase();
      final found =
          st.containers.keys.any((name) => name.toLowerCase().contains(needle));
      if (!found) {
        return LocalCheck(false, 'Нет контейнера с именем «$needle».');
      }
      continue;
    }
    if (c.containsKey('volume_exists')) {
      final name = c['volume_exists'].toString();
      if (!st.volumes.containsKey(name)) {
        return LocalCheck(false, 'Том «$name» пока не создан.');
      }
      continue;
    }
    if (c.containsKey('network_exists')) {
      final name = c['network_exists'].toString();
      if (!st.networks.contains(name)) {
        return LocalCheck(false, 'Сеть «$name» пока не создана.');
      }
      continue;
    }
    if (c.containsKey('event_contains')) {
      final needle = c['event_contains'].toString().toLowerCase();
      if (!eventHay.contains(needle)) {
        return LocalCheck(
            false, 'Команда ещё не оставила нужный след в песочнице.');
      }
      continue;
    }
    if (c.containsKey('workdir_equals')) {
      if (st.workdir != c['workdir_equals'].toString()) {
        return LocalCheck(false, 'Текущий каталог: ${st.workdir}.');
      }
      continue;
    }
    final kind = _canonicalKind((c['kind'] ?? '').toString());
    final name = (c['name'] ?? '').toString();
    final ns = (c['namespace'] ?? 'default').toString();
    final r = _find(st, kind, name, namespace: ns);
    final exists = c['exists'] == true;
    if (r == null) {
      if (exists || c['exists'] == null) {
        return LocalCheck(
            false, '$kind «$name» пока не создан в namespace $ns.');
      }
      continue;
    }
    if (c['exists'] == false) {
      return LocalCheck(false, '$kind «$name» всё ещё существует.');
    }
    final field = (c['field'] ?? '').toString();
    if (field.isNotEmpty) {
      final actual = _field(r, field);
      if (c.containsKey('equals') && !_same(actual, c['equals'])) {
        return LocalCheck(false,
            'Поле $field у $kind/$name = $actual, ожидается ${c['equals']}.');
      }
      if (c.containsKey('gte') &&
          (actual is num) &&
          actual < (c['gte'] as num)) {
        return LocalCheck(false,
            'Поле $field у $kind/$name = $actual, нужно не меньше ${c['gte']}.');
      }
    }
    if (c.containsKey('contains')) {
      final needle = c['contains'].toString().toLowerCase();
      final hay = jsonEncode(r).toLowerCase();
      if (!hay.contains(needle)) {
        return LocalCheck(false, '$kind/$name не содержит «${c['contains']}».');
      }
    }
  }
  return const LocalCheck(true, 'Проверка пройдена.');
}

dynamic _field(Map<String, dynamic> r, String path) {
  dynamic cur = r;
  for (final part in path.split('.')) {
    if (cur is Map) {
      cur = cur[part];
    } else if (cur is List) {
      final i = int.tryParse(part);
      if (i == null || i < 0 || i >= cur.length) return null;
      cur = cur[i];
    } else {
      return null;
    }
  }
  return cur;
}

bool _same(dynamic a, dynamic b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a?.toString() == b?.toString();
}
