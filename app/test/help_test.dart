import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radmanager/ui.dart';
import 'package:radmanager/widgets.dart';
import 'package:sim/sim.dart';

void main() {
  tearDown(() => I18n.lang = Lang.en);

  test('Every explanation has a German translation', () {
    I18n.lang = Lang.de;
    final untranslated = [
      for (final e in statHelp.entries)
        // A text that reads the same in both languages is fine.
        if (tr(e.value) == e.value && e.value != 'Sprint.') e.key,
    ];
    expect(untranslated, isEmpty);
  });

  testWidgets('Labels and column headings show their explanation', (
    tester,
  ) async {
    I18n.lang = Lang.de;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Label(tr('Licence')),
              const Label('Renntage 2026', help: 'Race days'),
              Label(tr('Squad')),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip(tr(statHelp['Licence']!)), findsOneWidget);
    expect(find.byTooltip(tr(statHelp['Race days']!)), findsOneWidget);
    // A heading without an explanation stays plain.
    expect(find.byType(Tooltip), findsNWidgets(2));
  });

  test('An empty help key shows no explanation', () {
    final plain = withHelp('', const Text('Punkte'));
    expect(plain, isA<Text>());
    expect(withHelp('Points', const Text('Points')), isA<Tooltip>());
  });

  test('Every race role says what it does', () {
    for (final role in Role.values) {
      expect(role.help, isNotEmpty, reason: role.name);
    }
  });
}
