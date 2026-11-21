import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/widgets.dart';

void main() {
  test('Clock digits are independent of date and app language', () {
    final state = freshState();
    final legacy = <String, dynamic>{'clock': true, 'clockLanguage': 'ar'};
    final ar = WidgetScene.responsive(
      state,
      legacy,
      true,
      const Size(318, 240),
    );
    expect(ar.timeLanguage, 'en');
    expect(ar.dateArabic, isTrue);
    final en = WidgetScene.responsive(
      state,
      {...legacy, 'timeLanguage': 'ar', 'clockLanguage': 'en'},
      false,
      const Size(318, 240),
    );
    expect(en.timeLanguage, 'ar');
    expect(en.dateArabic, isFalse);
    final restored = restoreWidgetDesigns(state, [
      {'id': 'clock', 'name': 'Clock', 'clock': true, 'timeLanguage': 'ar'},
    ]);
    expect(restored.single['timeLanguage'], 'ar');
  });

  test(
    'Installed layouts retain their own labels, direction, date and clock',
    () {
      final state = freshState()
        ..['widgets'] = [
          {
            'id': 'english',
            'enabled': ['water'],
            'widgetLanguage': 'en',
            'clock': true,
          },
          {
            'id': 'arabic',
            'enabled': ['water'],
            'widgetLanguage': 'ar',
            'timeLanguage': 'ar',
            'clockLanguage': 'en',
            'clock': true,
          },
        ];
      final layouts =
          widgetSnapshot(state, true, DateTime(2026, 11, 22))['layouts'] as Map;
      final english = layouts['english'] as Map;
      final arabic = layouts['arabic'] as Map;
      expect(english['ar'], false);
      expect(english['timeLanguage'], 'en');
      expect(english['clockLanguage'], 'en');
      expect(english['cards'].single['title'], 'Water');
      expect(arabic['ar'], true);
      expect(arabic['timeLanguage'], 'ar');
      expect(arabic['clockLanguage'], 'en');
      expect(arabic['cards'].single['title'], 'المياه');
      expect(
        restoreWidgetDesigns(state, state['widgets']).first['widgetLanguage'],
        'en',
      );
    },
  );

  testWidgets(
    'GitHub update center allows downloading and shows Android install permission',
    (tester) async {
      var ready = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(platform, (call) async {
        calls.add(call.method);
        if (call.method == 'downloadUpdate') ready = true;
        if (call.method == 'installUpdate') return 'permission';
        if (call.method != 'updateStatus') return null;
        return {
          'enabled': true,
          'automatic': true,
          'installed': '1.5.0',
          'version': '1.6.0',
          'size': 66264520,
          'progress': -1,
          'ready': ready,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(platform, null));
      await tester.pumpWidget(
        const MaterialApp(home: YawmiUpdateCenter(ar: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new update is available'), findsOneWidget);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(calls, contains('downloadUpdate'));
      await tester.ensureVisible(find.text('Install update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(calls, contains('installUpdate'));
      expect(find.textContaining('Allow installs from Yawmi'), findsOneWidget);
    },
  );
}
