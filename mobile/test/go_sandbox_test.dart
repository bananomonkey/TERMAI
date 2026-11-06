import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';
import 'package:termai/sandbox.dart';

void main() {
  test('echo quotes + go mod init + go run', () {
    final st = SandboxState.fromJson({
      'workdir': '/workspace', 'files': {}, 'images': {}, 'containers': {},
      'volumes': {}, 'networks': ['bridge'], 'events': [], 'k8s': {},
      'k8s_events': [], 'last_output': '',
    });
    tryLocalCommand("echo 'package main' > main.go", st);
    tryLocalCommand('echo \'func main() { fmt.Println("Привет, TERMAI!") }\' >> main.go', st);
    expect(st.files['main.go'], contains('fmt.Println("Привет, TERMAI!")'));
    final mod = tryLocalCommand('go mod init example.com/hello', st);
    expect(mod!.out, contains('go: creating new go.mod'));
    final run = tryLocalCommand('go run main.go', st);
    expect(run!.out, 'Привет, TERMAI!');
    final run2 = tryLocalCommand('go run main.go', st);
    tryLocalCommand("echo 'package main' > vars.go", st);
    tryLocalCommand('echo \'import "fmt"\' >> vars.go', st);
    tryLocalCommand('echo \'func main() { fmt.Printf("%d %s\\n", 42, "ok") }\' >> vars.go', st);
    final run3 = tryLocalCommand('go run vars.go', st);
    expect(run3!.out, '42 ok');
    final build = tryLocalCommand('go build -o server .', st);
    expect(build!.out, '');
    expect(st.files['server'], '<go-binary>');
    final t = tryLocalCommand('go test', st);
    expect(t!.out, contains('[no test files]'));
    tryLocalCommand("echo 'func TestSum(t *testing.T) {}' > main_test.go", st);
    final t2 = tryLocalCommand('go test', st);
    expect(t2!.out, contains('ok'));
    expect(st.events.where((e) => e.startsWith('go ')), isNotEmpty);
  });
}
