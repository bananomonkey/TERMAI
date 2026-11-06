// sandbox.dart — локальный fast-path команд без ИИ (порт local.go):
// pwd/echo/ls/cat/cd и docker ps/images/volume/network/rm/stop/start/restart/rmi.
import 'dart:math';
import 'k8s_sandbox.dart';
import 'models.dart';

String fakeID(String seed) {
  // короткий детерминированный id из sha1-подобного хеша (FNV-1a, hex)
  int h = 0x811c9dc5;
  for (final b in seed.codeUnits) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final r = Random(h).nextInt(0xffffffff);
  return (h.toRadixString(16).padLeft(8, '0') +
          r.toRadixString(16).padLeft(8, '0'))
      .substring(0, 12);
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
      final prev = redirect.group(2) == '>>' && st.files.containsKey(file)
          ? st.files[file]!
          : '';
      st.files[file] = prev + inner.out;
      return LocalResult(true, '');
    }
    return null;
  }
  final fields =
      raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (fields.isEmpty) return null;
  switch (fields[0]) {
    case 'whoami':
      return LocalResult(true, 'user');
    case 'uname':
      return LocalResult(
          true, 'Linux termai 6.1.0-generic #1 SMP x86_64 GNU/Linux');
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
      final targets = fields
          .skip(1)
          .where((x) => x != '-r' && x != '-f' && x != '-rf')
          .toList();
      if (targets.isEmpty) return LocalResult(true, 'rm: missing operand');
      for (final t in targets) {
        st.files.remove(t);
        st.files.remove('' + t + '/');
        st.files.removeWhere((k, v) => k.startsWith('' + t + '/'));
      }
      return LocalResult(true, '');
    case 'mv':
    case 'cp':
      if (fields.length < 3)
        return LocalResult(true, fields[0] + ': missing destination');
      final src = fields[1], dst = fields[2];
      final body = st.files[src];
      if (body == null && !st.files.containsKey('' + src + '/')) {
        return LocalResult(true,
            fields[0] + ': cannot stat ' + src + ': No such file or directory');
      }
      if (st.files.containsKey('' + src + '/')) {
        // перенос каталога
        st.files = st.files.map((k, v) => MapEntry(
            k.startsWith('' + src + '/')
                ? dst + '/' + k.substring(('' + src + '/').length)
                : k,
            v));
        if (fields[0] == 'mv') st.files.remove('' + src + '/');
        st.files['' + dst + '/'] = '';
      } else {
        st.files[dst] = body!;
        if (fields[0] == 'mv') st.files.remove(src);
      }
      return LocalResult(true, '');
    case 'grep':
      if (fields.length < 3)
        return LocalResult(true, 'usage: grep PATTERN FILE');
      final body = st.files[fields[2]];
      if (body == null)
        return LocalResult(
            true, 'grep: ' + fields[2] + ': No such file or directory');
      final hits =
          body.split('\n').where((l) => l.contains(fields[1])).toList();
      return LocalResult(true, hits.isEmpty ? '' : hits.join('\n'));
    case 'head':
    case 'tail':
      if (fields.length < 2)
        return LocalResult(true, 'usage: ' + fields[0] + ' FILE');
      final body = st.files[fields[1]];
      if (body == null)
        return LocalResult(
            true, fields[0] + ': ' + fields[1] + ': No such file or directory');
      final lines = body.split('\n');
      return LocalResult(
          true,
          (fields[0] == 'head'
                  ? lines.take(10)
                  : lines.length > 10
                      ? lines.skip(lines.length - 10)
                      : lines)
              .join('\n'));
    case 'git':
      return _git(fields.sublist(1), st);
    case 'pwd':
      return LocalResult(true, st.workdir);
    case 'echo':
      // Реальный шелл снимает обрамляющие кавычки: это позволяет писать
      // исходники Go через echo '...' > file.go без экранирования.
      var text = raw.trim().replaceFirst(RegExp(r'^echo\b'), '').trim();
      var unwrapped = false;
      if (text.length >= 2) {
        final q = text[0];
        if ((q == '"' || q == "'") && text.endsWith(q)) {
          text = text.substring(1, text.length - 1);
          unwrapped = true;
        }
      }
      if (!unwrapped) {
        text = fields.skip(1).map((f) {
          if (f.length >= 2 &&
              ((f.startsWith('"') && f.endsWith('"')) ||
                  (f.startsWith("'") && f.endsWith("'")))) {
            return f.substring(1, f.length - 1);
          }
          return f;
        }).join(' ');
      }
      return LocalResult(true, text);
    case 'ls':
      final prefix =
          fields.length > 1 ? fields[1].replaceAll(RegExp(r'^/+|/+$'), '') : '';
      final names = st.files.keys
          .where((n) => prefix.isEmpty || n.startsWith(prefix))
          .toList()
        ..sort();
      return LocalResult(true, names.join('   '));
    case 'cat':
      if (fields.length < 2) return LocalResult(true, 'cat: missing operand');
      final body = st.files[fields[1]];
      return LocalResult(
          true, body ?? 'cat: ${fields[1]}: No such file or directory');
    case 'cd':
      String target;
      if (fields.length > 1) {
        target = fields[1];
        if (!target.startsWith('/'))
          target = '${st.workdir.replaceAll(RegExp(r'/+$'), '')}/$target';
        st.workdir = _clean(target);
      } else {
        st.workdir = '/';
      }
      return LocalResult(true, '');
    case 'docker':
      if (fields.length < 2) return null;
      return _localDocker(fields.sublist(1), st);
    case 'kubectl':
      return tryKubectl(fields.sublist(1), st);
    case 'go':
      return _go(fields.sublist(1), st);
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
      final b = StringBuffer(
          'CONTAINER ID   IMAGE                  STATUS         PORTS                    NAMES');
      final names = st.containers.keys.toList()..sort();
      for (final n in names) {
        final c = st.containers[n]!;
        if (!all && c.status != 'running') continue;
        var status = 'Up';
        if (c.status != 'running')
          status =
              c.status.startsWith('exited') ? 'Exited' : 'Exited (${c.status})';
        b.write(
            '\n${c.id.padRight(14)} ${c.image.padRight(22)} ${status.padRight(14)} ${c.ports.padRight(24)} $n');
      }
      return LocalResult(true, b.toString());
    case 'images':
      final b = StringBuffer('REPOSITORY      TAG       IMAGE ID        SIZE');
      final keys = st.images.keys.toList()..sort();
      for (final k in keys) {
        final img = st.images[k]!;
        final id = img.id.replaceFirst('sha256:', '');
        b.write(
            '\n${img.repo.padRight(15)} ${img.tag.padRight(9)} sha256:$id ${img.sizeMb.round()}MB');
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
        b.write(
            '\n${fakeID('net:$n').padRight(14)} ${n.padRight(8)} ${n == 'none' ? 'null' : n}');
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
  if (targets.isEmpty)
    return LocalResult(true, '"docker rm" requires at least 1 argument.');
  final out = <String>[];
  for (final t in targets) {
    final name = _findContainer(st, t);
    if (name == null) {
      out.add('Error response from daemon: No such container: $t');
      continue;
    }
    if (st.containers[name]!.status == 'running' && !force) {
      out.add(
          'Error response from daemon: You cannot remove a running container $name. Stop the container before attempting removal or force remove');
      continue;
    }
    st.containers.remove(name);
    out.add(name);
  }
  return LocalResult(true, out.join('\n'));
}

LocalResult _dockerLifecycle(
    List<String> args, SandboxState st, String cmd, String status) {
  if (args.isEmpty)
    return LocalResult(true, '"docker $cmd" requires at least 1 argument.');
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
  if (args.isEmpty)
    return LocalResult(true, '"docker rmi" requires at least 1 argument.');
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

// _go — минимальный эмулятор Go-инструментов поверх файлов песочницы.
// Поддержан учебный минимум: version/env, mod init, run, build, test, vet, fmt.
// go run исполняет упрощённую модель: печатает результаты fmt.Print* со
// строковыми литералами в порядке следования в исходнике.
LocalResult _go(List<String> args, SandboxState st) {
  if (args.isEmpty) {
    return LocalResult(
        true,
        'usage: go <command> [arguments]\n\n'
        'Commands:\n'
        '  mod init   создать go.mod\n'
        '  run        скомпилировать и запустить\n'
        '  build      скомпилировать бинарник\n'
        '  test       запустить тесты\n'
        '  version    версия Go');
  }
  switch (args[0]) {
    case 'version':
      return LocalResult(true, 'go version go1.22.5 linux/amd64');
    case 'env':
      return LocalResult(true,
          'GOARCH="amd64"\nGOOS="linux"\nGOPATH="/workspace/go"\nGOROOT="/usr/local/go"');
    case 'mod':
      if (args.length < 3 || args[1] != 'init') {
        return LocalResult(true, 'usage: go mod init [module-path]');
      }
      final name = args[2];
      st.files['go.mod'] = 'module $name\n\ngo 1.22\n';
      st.events.add('go mod init $name');
      return LocalResult(true, 'go: creating new go.mod: module $name');
    case 'run':
      if (args.length < 2) {
        return LocalResult(true, 'go: no go files listed');
      }
      return _goRun(args[1] == '.' ? null : args[1], st);
    case 'build':
      return _goBuild(args.sublist(1), st);
    case 'test':
      return _goTest(st);
    case 'vet':
    case 'fmt':
      return LocalResult(true, '');
  }
  return LocalResult(true, 'go ${args[0]}: unknown command');
}

/// _goSource — находит исходник для run/build: явный файл или main.go при ".".
({String name, String src})? _goSource(String? arg, SandboxState st) {
  if (arg != null && arg != '.') {
    final src = st.files[arg];
    if (src == null) return null;
    return (name: arg, src: src);
  }
  if (st.files.containsKey('main.go')) {
    return (name: 'main.go', src: st.files['main.go']!);
  }
  for (final e in st.files.entries) {
    if (e.key.endsWith('.go') && e.value.contains('package main')) {
      return (name: e.key, src: e.value);
    }
  }
  return null;
}

LocalResult _goRun(String? arg, SandboxState st) {
  final src = _goSource(arg, st);
  if (src == null) {
    return LocalResult(
        true, 'go: stat ${arg ?? '.'}: no such file or directory');
  }
  if (!src.src.contains('package main')) {
    return LocalResult(true, 'go: cannot run non-main package');
  }
  st.events.add('go run ${arg ?? '.'}');
  return LocalResult(true, _execGo(src.src));
}

/// _GoEnv — мини-окружение исполнения: простые переменные, поля структур,
/// map и срезы, созданные литералами. Достаточно для учебных программ.
class _GoEnv {
  final Map<String, String> vals = {};
  final Map<String, Map<String, String>> maps = {};
  final Map<String, List<String>> slices = {};
}

/// _execGo — упрощённое исполнение учебной программы: обходит инструкции
/// main по порядку, связывает литеральные присваивания и печатает вывод
/// fmt.Print*. Всё, что не вычисляется (вызовы функций, каналы), пропускается.
String _execGo(String src) {
  final env = _GoEnv();
  final out = StringBuffer();
  _runStmts(_goStatements(_mainBody(src)), src, env, out, 0);
  return out.toString().trimRight();
}

/// _runStmts — исполняет список инструкций: присваивания, вызовы fmt.Print*
/// и вызовы функций, объявленных в исходнике (глубина до 3).
void _runStmts(List<String> stmts, String src, _GoEnv env, StringBuffer out,
    int depth) {
  for (final stmt in stmts) {
    final bind = RegExp(r'^([A-Za-z_]\w*)\s*:=\s*(.+)$').firstMatch(stmt);
    if (bind != null) {
      _bind(bind.group(1)!, bind.group(2)!, env);
      continue;
    }
    final idxAssign =
        RegExp(r'^([A-Za-z_]\w*)\[(.+)\]\s*=\s*(.+)$').firstMatch(stmt);
    if (idxAssign != null) {
      final m = env.maps[idxAssign.group(1)!];
      if (m != null) {
        m[_goEval(idxAssign.group(2)!, env) ?? ''] =
            _goEval(idxAssign.group(3)!, env) ?? '';
      }
      continue;
    }
    final call = RegExp(r'fmt\.(Println|Printf|Print)\s*\(').firstMatch(stmt);
    if (call != null) {
      _execPrint(stmt, call, env, out);
      continue;
    }
    if (depth < 3) _execFnCall(stmt, src, env, out, depth);
  }
}

/// _execFnCall — находит в исходнике объявление вызванной функции/метода
/// и исполняет её тело тем же интерпретатором.
void _execFnCall(
    String stmt, String src, _GoEnv env, StringBuffer out, int depth) {
  final m = RegExp(r'([A-Za-z_]\w*)\s*\(').firstMatch(stmt);
  if (m == null) return;
  final name = m.group(1)!;
  if (['if', 'for', 'range', 'switch', 'func', 'make', 'len', 'go', 'defer']
      .contains(name)) {
    return;
  }
  final def =
      RegExp('func\\s+(?:\\([^)]*\\)\\s+)?$name\\s*\\(').firstMatch(src);
  if (def == null) return;
  final open = src.indexOf('{', def.end);
  if (open < 0) return;
  var d = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') d++;
    if (src[j] == '}') {
      d--;
      if (d == 0) {
        _runStmts(_goStatements(src.substring(open + 1, j)), src, env, out,
            depth + 1);
        return;
      }
    }
  }
}

/// _mainBody — текст тела func main (упрощённо: до последней '}' исходника).
String _mainBody(String src) {
  final i = src.indexOf('func main()');
  if (i < 0) return '';
  final open = src.indexOf('{', i);
  if (open < 0) return '';
  var depth = 0;
  for (var j = open; j < src.length; j++) {
    final c = src[j];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return src.substring(open + 1, j);
    }
  }
  return src.substring(open + 1);
}

/// _goStatements — делит тело на инструкции по ';' верхнего уровня.
List<String> _goStatements(String body) {
  final res = <String>[];
  var depth = 0;
  var cur = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ';' && depth == 0) {
      final t = cur.toString().trim();
      if (t.isNotEmpty) res.add(t);
      cur = StringBuffer();
    } else {
      cur.write(c);
    }
  }
  final t = cur.toString().trim();
  if (t.isNotEmpty) res.add(t);
  return res;
}

/// _bind — связывает имя со значением: литерал, map/срез или
/// составной литерал структуры (поля сохраняются как name.Field).
void _bind(String name, String rhs, _GoEnv env) {
  final t = rhs.trim();
  if (t.startsWith('"')) {
    env.vals[name] = _goUnquote(t);
    return;
  }
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t) || t == 'true' || t == 'false') {
    env.vals[name] = t;
    return;
  }
  final mapm =
      RegExp(r'^map\[[^\]]+\][\w\*\.]*\{(.*)\}$').firstMatch(t);
  if (mapm != null) {
    final m = <String, String>{};
    for (final e in _splitGoArgs(mapm.group(1)!)) {
      final kv = e.split(':');
      if (kv.length >= 2) {
        m[_goUnquote(kv[0])] = _goUnquote(kv.sublist(1).join(':'));
      }
    }
    env.maps[name] = m;
    return;
  }
  final slicem =
      RegExp(r'^\[\][\w\*\.]+\{(.*)\}$').firstMatch(t);
  if (slicem != null) {
    env.slices[name] =
        _splitGoArgs(slicem.group(1)!).map((e) => _goUnquote(e)).toList();
    return;
  }
  final structm = RegExp(r'^[A-Z]\w*\{(.*)\}$').firstMatch(t);
  if (structm != null) {
    for (final e in _splitGoArgs(structm.group(1)!)) {
      final kv = e.split(':');
      if (kv.length >= 2) {
        final v = _goEval(kv.sublist(1).join(':'), env);
        if (v != null) env.vals['$name.${kv[0].trim()}'] = v;
      }
    }
    return;
  }
  // Всё остальное (вызовы, каналы) не связываем — вывод по ним пропустится.
}

/// _execPrint — исполняет один вызов fmt.Print* с вычислением аргументов.
void _execPrint(
    String stmt, RegExpMatch call, _GoEnv env, StringBuffer out) {
  // Закрывающая скобка вызова — по балансу от открывающей.
  final open = call.end - 1;
  var depth = 0;
  var close = -1;
  for (var j = open; j < stmt.length; j++) {
    if (stmt[j] == '(') depth++;
    if (stmt[j] == ')') {
      depth--;
      if (depth == 0) {
        close = j;
        break;
      }
    }
  }
  if (close < 0) return;
  final fn = call.group(1)!;
  final argv = _splitGoArgs(stmt.substring(open + 1, close));
  if (fn == 'Printf') {
    if (argv.isEmpty) return;
    var fmtStr = _goUnquote(argv[0]);
    var vi = 0;
    fmtStr = fmtStr.replaceAllMapped(RegExp(r'%(?:[svdgtqx]|w)'), (_) {
      if (vi >= argv.length - 1) return '?';
      return _goEval(argv[++vi], env) ?? '?';
    });
    out.write(fmtStr);
    if (!fmtStr.endsWith('\n')) out.write('\n');
    return;
  }
  final sep = fn == 'Println' ? ' ' : '';
  final parts = <String>[];
  for (final a in argv) {
    final v = _goEval(a, env);
    if (v != null) parts.add(v);
  }
  out.write(parts.join(sep));
  if (fn == 'Println') out.write('\n');
}

/// _splitGoArgs — делит список аргументов по запятым верхнего уровня.
List<String> _splitGoArgs(String s) {
  final res = <String>[];
  var depth = 0, inStr = false;
  var cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      cur.write(c);
      if (c == r'\' && i + 1 < s.length) {
        cur.write(s[++i]);
      } else if (c == '"') {
        inStr = false;
      }
      continue;
    }
    if (c == '"') {
      inStr = true;
      cur.write(c);
    } else if (c == '(' || c == '[' || c == '{') {
      depth++;
      cur.write(c);
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      cur.write(c);
    } else if (c == ',' && depth == 0) {
      final t = cur.toString().trim();
      if (t.isNotEmpty) res.add(t);
      cur = StringBuffer();
    } else {
      cur.write(c);
    }
  }
  final t = cur.toString().trim();
  if (t.isNotEmpty) res.add(t);
  return res;
}

/// _goUnquote — снимает кавычки и раскрывает escapes (\n \t \" \\).
String _goUnquote(String a) {
  var t = a.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    t = t.substring(1, t.length - 1);
  }
  return t
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\');
}

/// _goEval — простые выражения: литералы, переменные окружения, поля
/// структур, len(...). null — не вычислимо, аргумент пропускается.
String? _goEval(String a, _GoEnv env) {
  final t = a.trim();
  if (t.startsWith('"')) return _goUnquote(t);
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t)) return t;
  if (t == 'true' || t == 'false') return t;
  if (env.vals.containsKey(t)) return env.vals[t];
  final len = RegExp(r'^len\((.*)\)$').firstMatch(t);
  if (len != null) {
    final inner = len.group(1)!.trim();
    if (inner.startsWith('"')) return _goUnquote(inner).length.toString();
    if (env.maps.containsKey(inner)) return env.maps[inner]!.length.toString();
    if (env.slices.containsKey(inner)) {
      return env.slices[inner]!.length.toString();
    }
  }
  return null;
}

LocalResult _goBuild(List<String> args, SandboxState st) {
  var outName = '';
  String? srcArg;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-o' && i + 1 < args.length) {
      outName = args[++i];
    } else if (!args[i].startsWith('-')) {
      srcArg = args[i];
    }
  }
  final src = _goSource(srcArg ?? '.', st);
  if (src == null) {
    return LocalResult(
        true, 'go: stat ${srcArg ?? '.'}: no such file or directory');
  }
  if (!src.src.contains('package main')) {
    return LocalResult(true, 'go: cannot build non-main package');
  }
  outName = outName.isNotEmpty ? outName : 'app';
  st.files[outName] = '<go-binary>';
  st.events.add('go build ${srcArg ?? '.'}');
  return LocalResult(true, '');
}

LocalResult _goTest(SandboxState st) {
  final module = st.files['go.mod']?.split('\n').first ?? 'module app';
  final modName = module.replaceFirst('module ', '').trim();
  final tests = st.files.keys.where((k) => k.endsWith('_test.go')).toList();
  st.events.add('go test');
  if (tests.isEmpty) {
    return LocalResult(true, '?   $modName [no test files]');
  }
  final failing = tests.any((t) => st.files[t]!.contains('t.Fail()'));
  if (failing) {
    return LocalResult(true, '--- FAIL: TestXxx\nFAIL');
  }
  return LocalResult(true, 'PASS\nok  \t$modName\t0.42s');
}

// _git — минимальный оффлайн-git поверх файлов песочницы.
LocalResult _git(List<String> args, SandboxState st) {
  const gitDir = '.git/HEAD';
  switch (args.isEmpty ? '' : args[0]) {
    case 'init':
      st.files[gitDir] = 'ref: refs/heads/main';
      st.files['.git/committed.txt'] = '';
      st.events.add('git init');
      return LocalResult(
          true, 'Initialized empty Git repository in /workspace/.git');
    case 'add':
      if (!st.files.containsKey(gitDir))
        return LocalResult(true,
            'fatal: not a git repository (or any of the parent directories): .git');
      st.events.add('git add ' + args.skip(1).join(' '));
      return LocalResult(true, '');
    case 'commit':
      if (!st.files.containsKey(gitDir))
        return LocalResult(true, 'fatal: not a git repository');
      final mi = args.indexOf('-m');
      final msg =
          mi >= 0 && mi + 1 < args.length ? args[mi + 1] : '(без сообщения)';
      st.files['.git/committed.txt'] =
          st.files.keys.where((k) => !k.startsWith('.git')).join('\n');
      final id = fakeID('commit:' + msg + st.events.length.toString());
      st.events.add('commit ' + id + ' ' + msg);
      return LocalResult(true, '[main ' + id.substring(0, 7) + '] ' + msg);
    case 'status':
      if (!st.files.containsKey(gitDir))
        return LocalResult(true, 'fatal: not a git repository');
      final committed = (st.files['.git/committed.txt'] ?? '')
          .split('\n')
          .where((s) => s.isNotEmpty)
          .toSet();
      final untracked = st.files.keys
          .where((k) => !k.startsWith('.git') && !committed.contains(k))
          .toList();
      if (untracked.isEmpty)
        return LocalResult(
            true, 'On branch main\nnothing to commit, working tree clean');
      return LocalResult(
          true,
          'On branch main\nUntracked files:\n' +
              untracked.map((u) => '  ' + u).join('\n'));
    case 'log':
      if (!st.files.containsKey(gitDir))
        return LocalResult(true, 'fatal: not a git repository');
      final commits =
          st.events.where((e) => e.startsWith('commit ')).toList().reversed;
      if (commits.isEmpty)
        return LocalResult(true,
            'fatal: your current branch (main) does not have any commits yet');
      return LocalResult(true,
          commits.map((c) => c.replaceFirst('commit ', 'commit ')).join('\n'));
    case 'branch':
      if (args.length > 1) {
        st.events.add('branch ' + args[1]);
        return LocalResult(true, '');
      }
      return LocalResult(true, '* main');
  }
  return LocalResult(
      true, 'git: ' + (args.isEmpty ? '' : args[0]) + ' — см. help');
}
