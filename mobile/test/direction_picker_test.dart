import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/ui/direction_picker.dart';
import 'package:termai/ui/theme.dart';

void main() {
  testWidgets('direction picker fits small screens and keeps multi-select',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Set<String>? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await showDirectionPicker(
                  context,
                  selected: {'devops'},
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Направления'), findsOneWidget);
    expect(find.text('Выбрано: 1'), findsOneWidget);
    await tester.tap(find.text('Английский'));
    await tester.pump();
    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(result, containsAll(<String>['devops', 'english']));
    expect(tester.takeException(), isNull);
  });
}
