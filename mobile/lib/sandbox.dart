// sandbox.dart — локальный fast-path команд без ИИ (порт local.go):
// pwd/echo/ls/cat/cd и docker ps/images/volume/network/rm/stop/start/restart/rmi.
import 'dart:math';
import 'models.dart';

String fakeID(String seed) {
  // короткий детерминированный id из sha1-подобного хеша (FNV-1a, hex)
  int h = 0x811c9dc5;
  for (final b in seed.codeUnits) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final r = Random(h).nextInt(0xffffffff);
  return (h.toRadixString(16).padLeft(8, '0') + r.toRadixString(16).padLeft(8, '0')).substring(0, 12);
}

class LocalResult {
  final bool handled;
  final String out;
  LocalResult(this.handled, [this.out = '']);
}

LocalResult? tryLocalCommand(String raw, SandboxState st) {
  final fields = raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (fields.isEmpty) return null;
  switch (fields[0]) {
    case 'pwd':
      return LocalResult(true, st.workdir);
    case 'echo':
      return LocalResult(true, fields.skip(1).join(' '));
    case 'ls':
      final prefix = fields.length > 1 ? fields[1].replaceAll(RegExp(r'^/+|/+$'), '') : '';
      final names = st.files.keys.where((n) => prefix.isEmpty || n.startsWith(prefix)).toList()..sort();
      return LocalResult(true, names.join('   '));
    case 'cat':
      if (fields.length < 2) return LocalResult(true, 'cat: missing operand');
      final body = st.files[fields[1]];
      return LocalResult(true, body ?? 'cat: ${fields[1]}: No such file or directory');
    case 'cd':
      String target;
      if (fields.length > 1) {
        target = fields[1];
        if (!target.startsWith('/')) target = '${st.workdir.replaceAll(RegExp(r'/+$'), '')}/$target';
        st.workdir = _clean(target);
      } else {
        st.workdir = '/';
      }
      return LocalResult(true, '');
    case 'docker':
      if (fields.length < 2) return null;
      return _localDocker(fields.sublist(1), st);
  }
  return null;
}

String _clean(String p) {
  final abs = p.startsWith('/');
  final parts = p.split('/').where((s) => s.isNotEmpty && s != '.').toList();
  final res = <String>[];
  for (final part in parts) {
    if (part == '..') {
      if (res.isNotEmpty) res.removeLast();
    } else {
      res.add(part);
    }
  }
  return (abs ? '/' : '') + res.join('/');
}

LocalResult? _localDocker(List<String> a, SandboxState st) {
  switch (a[0]) {
    case 'ps':
      final all = a.length > 1 && (a[1] == '-a' || a[1] == '--all');
      final b = StringBuffer('CONTAINER ID   IMAGE                  STATUS         PORTS                    NAMES');
      final names = st.containers.keys.toList()..sort();
      for (final n in names) {
        final c = st.containers[n]!;
        if (!all && c.status != 'running') continue;
        var status = 'Up';
        if (c.status != 'running') status = c.status.startsWith('exited') ? 'Exited' : 'Exited (${c.status})';
        b.write('\n${c.id.padRight(14)} ${c.image.padRight(22)} ${status.padRight(14)} ${c.ports.padRight(24)} $n');
      }
      return LocalResult(true, b.toString());
    case 'images':
      final b = StringBuffer('REPOSITORY      TAG       IMAGE ID        SIZE');
      final keys = st.images.keys.toList()..sort();
      for (final k in keys) {
        final img = st.images[k]!;
        final id = img.id.replaceFirst('sha256:', '');
        b.write('\n${img.repo.padRight(15)} ${img.tag.padRight(9)} sha256:$id ${img.sizeMb.round()}MB');
      }
      return LocalResult(true, b.toString());
    case 'volume':
      if (a.length < 2 || a[1] != 'ls') return null;
      final b = StringBuffer('DRIVER   VOLUME NAME');
      for (final v in (st.volumes.keys.toList()..sort())) {
        b.write('\nlocal    $v');
      }
      return LocalResult(true, b.toString());
    case 'network':
      if (a.length < 2 || a[1] != 'ls') return null;
      final b = StringBuffer('NETWORK ID     NAME     DRIVER');
      for (final n in st.networks) {
        b.write('\n${fakeID('net:$n').padRight(14)} ${n.padRight(8)} ${n == 'none' ? 'null' : n}');
      }
      return LocalResult(true, b.toString());
    case 'rm':
      return _dockerRM(a.sublist(1), st);
    case 'stop':
      return _dockerLifecycle(a.sublist(1), st, 'stop', 'exited');
    case 'start':
      return _dockerLifecycle(a.sublist(1), st, 'start', 'running');
    case 'restart':
      return _dockerLifecycle(a.sublist(1), st, 'restart', 'running');
    case 'rmi':
      return _dockerRMI(a.sublist(1), st);
  }
  return null;
}

String? _findContainer(SandboxState st, String ref) {
  if (st.containers.containsKey(ref)) return ref;
  for (final e in st.containers.entries) {
    if (e.value.id == ref) return e.key;
  }
  return null;
}

LocalResult _dockerRM(List<String> args, SandboxState st) {
  var force = false;
  final targets = <String>[];
  for (final x in args) {
    if (x == '-f' || x == '--force') {
      force = true;
    } else {
      targets.add(x);
    }
  }
  if (targets.isEmpty) return LocalResult(true, '"docker rm" requires at least 1 argument.');
  final out = <String>[];
  for (final t in targets) {
    final name = _findContainer(st, t);
    if (name == null) {
      out.add('Error response from daemon: No such container: $t');
      continue;
    }
    if (st.containers[name]!.status == 'running' && !force) {
      out.add('Error response from daemon: You cannot remove a running container $name. Stop the container before attempting removal or force remove');
      continue;
    }
    st.containers.remove(name);
    out.add(name);
  }
  return LocalResult(true, out.join('\n'));
}

LocalResult _dockerLifecycle(List<String> args, SandboxState st, String cmd, String status) {
  if (args.isEmpty) return LocalResult(true, '"docker $cmd" requires at least 1 argument.');
  final out = <String>[];
  for (final t in args) {
    final name = _findContainer(st, t);
    if (name == null) {
      out.add('Error response from daemon: No such container: $t');
      continue;
    }
    st.containers[name]!.status = status;
    out.add(name);
  }
  return LocalResult(true, out.join('\n'));
}

String? _findImage(SandboxState st, String ref) {
  if (st.images.containsKey(ref)) return ref;
  for (final e in st.images.entries) {
    final img = e.value;
    if (img.id == ref || img.id.startsWith(ref)) return e.key;
    if ('${img.repo}:${img.tag}' == ref || img.repo == ref) return e.key;
  }
  return null;
}

LocalResult _dockerRMI(List<String> args, SandboxState st) {
  if (args.isEmpty) return LocalResult(true, '"docker rmi" requires at least 1 argument.');
  final out = <String>[];
  for (final t in args) {
    final key = _findImage(st, t);
    if (key == null) {
      out.add('Error response from daemon: No such image: $t');
      continue;
    }
    st.images.remove(key);
    out.add('Untagged: $t');
  }
  return LocalResult(true, out.join('\n'));
}

/// termPrompt — приглашение как в реальном Linux: user@termai:~$
String termPrompt(SandboxState st) {
  var cwd = st.workdir.isEmpty ? '/' : st.workdir;
  const home = '/workspace'; // «домашняя» папка песочницы
  if (cwd == home) {
    cwd = '~';
  } else if (cwd.startsWith('$home/')) {
    cwd = '~${cwd.substring(home.length)}';
  }
  return 'user@termai:$cwd\$ ';
}
