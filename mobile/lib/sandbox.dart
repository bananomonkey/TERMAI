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
  // перенаправление: cmd > file / cmd >> file (только для локальных команд)
  final redirect = RegExp(r'^(.*?)\s*(>>?)\s*(\S+)$').firstMatch(raw.trim());
  if (redirect != null && redirect.group(1)!.trim().isNotEmpty) {
    final inner = tryLocalCommand(redirect.group(1)!, st);
    if (inner != null && inner.handled) {
      final file = redirect.group(3)!;
      final prev = redirect.group(2) == '>>' && st.files.containsKey(file) ? st.files[file]! : '';
      st.files[file] = prev + inner.out;
      return LocalResult(true, '');
    }
    return null;
  }
  final fields = raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (fields.isEmpty) return null;
  switch (fields[0]) {
    case 'whoami':
      return LocalResult(true, 'user');
    case 'uname':
      return LocalResult(true, 'Linux termai 6.1.0-generic #1 SMP x86_64 GNU/Linux');
    case 'date':
      return LocalResult(true, DateTime.now().toString().substring(0, 19));
    case 'mkdir':
      for (final f in fields.where((x) => x != 'mkdir' && x != '-p')) {
        st.files['' + f + '/'] = '';
      }
      return LocalResult(true, '');
    case 'touch':
      for (final f in fields.skip(1)) {
        st.files.putIfAbsent(f, () => '');
      }
      return LocalResult(true, '');
    case 'rm':
      final targets = fields.skip(1).where((x) => x != '-r' && x != '-f' && x != '-rf').toList();
      if (targets.isEmpty) return LocalResult(true, 'rm: missing operand');
      for (final t in targets) {
        st.files.remove(t);
        st.files.remove('' + t + '/');
        st.files.removeWhere((k, v) => k.startsWith('' + t + '/'));
      }
      return LocalResult(true, '');
    case 'mv':
    case 'cp':
      if (fields.length < 3) return LocalResult(true, fields[0] + ': missing destination');
      final src = fields[1], dst = fields[2];
      final body = st.files[src];
      if (body == null && !st.files.containsKey('' + src + '/')) {
        return LocalResult(true, fields[0] + ': cannot stat ' + src + ': No such file or directory');
      }
      if (st.files.containsKey('' + src + '/')) {
        // перенос каталога
        st.files = st.files.map((k, v) => MapEntry(k.startsWith('' + src + '/') ? dst + '/' + k.substring(('' + src + '/').length) : k, v));
        if (fields[0] == 'mv') st.files.remove('' + src + '/');
        st.files['' + dst + '/'] = '';
      } else {
        st.files[dst] = body!;
        if (fields[0] == 'mv') st.files.remove(src);
      }
      return LocalResult(true, '');
    case 'grep':
      if (fields.length < 3) return LocalResult(true, 'usage: grep PATTERN FILE');
      final body = st.files[fields[2]];
      if (body == null) return LocalResult(true, 'grep: ' + fields[2] + ': No such file or directory');
      final hits = body.split('\n').where((l) => l.contains(fields[1])).toList();
      return LocalResult(true, hits.isEmpty ? '' : hits.join('\n'));
    case 'head':
    case 'tail':
      if (fields.length < 2) return LocalResult(true, 'usage: ' + fields[0] + ' FILE');
      final body = st.files[fields[1]];
      if (body == null) return LocalResult(true, fields[0] + ': ' + fields[1] + ': No such file or directory');
      final lines = body.split('\n');
      return LocalResult(true, (fields[0] == 'head' ? lines.take(10) : lines.length > 10 ? lines.skip(lines.length - 10) : lines).join('\n'));
    case 'git':
      return _git(fields.sublist(1), st);
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

// _git — минимальный оффлайн-git поверх файлов песочницы.
LocalResult _git(List<String> args, SandboxState st) {
  const gitDir = '.git/HEAD';
  switch (args.isEmpty ? '' : args[0]) {
    case 'init':
      st.files[gitDir] = 'ref: refs/heads/main';
      st.files['.git/committed.txt'] = '';
      st.events.add('git init');
      return LocalResult(true, 'Initialized empty Git repository in /workspace/.git');
    case 'add':
      if (!st.files.containsKey(gitDir)) return LocalResult(true, 'fatal: not a git repository (or any of the parent directories): .git');
      st.events.add('git add ' + args.skip(1).join(' '));
      return LocalResult(true, '');
    case 'commit':
      if (!st.files.containsKey(gitDir)) return LocalResult(true, 'fatal: not a git repository');
      final mi = args.indexOf('-m');
      final msg = mi >= 0 && mi + 1 < args.length ? args[mi + 1] : '(без сообщения)';
      st.files['.git/committed.txt'] = st.files.keys.where((k) => !k.startsWith('.git')).join('\n');
      final id = fakeID('commit:' + msg + st.events.length.toString());
      st.events.add('commit ' + id + ' ' + msg);
      return LocalResult(true, '[main ' + id.substring(0, 7) + '] ' + msg);
    case 'status':
      if (!st.files.containsKey(gitDir)) return LocalResult(true, 'fatal: not a git repository');
      final committed = (st.files['.git/committed.txt'] ?? '').split('\n').where((s) => s.isNotEmpty).toSet();
      final untracked = st.files.keys.where((k) => !k.startsWith('.git') && !committed.contains(k)).toList();
      if (untracked.isEmpty) return LocalResult(true, 'On branch main\nnothing to commit, working tree clean');
      return LocalResult(true, 'On branch main\nUntracked files:\n' + untracked.map((u) => '  ' + u).join('\n'));
    case 'log':
      if (!st.files.containsKey(gitDir)) return LocalResult(true, 'fatal: not a git repository');
      final commits = st.events.where((e) => e.startsWith('commit ')).toList().reversed;
      if (commits.isEmpty) return LocalResult(true, 'fatal: your current branch (main) does not have any commits yet');
      return LocalResult(true, commits.map((c) => c.replaceFirst('commit ', 'commit ')).join('\n'));
    case 'branch':
      if (args.length > 1) {
        st.events.add('branch ' + args[1]);
        return LocalResult(true, '');
      }
      return LocalResult(true, '* main');
  }
  return LocalResult(true, 'git: ' + (args.isEmpty ? '' : args[0]) + ' — см. help');
}
