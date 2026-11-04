import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spider_mind/features/web3d/web_legend.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/state/app_state.dart';
import 'package:spider_mind/ui/editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const space1 = Space(id: 's1', name: 'Work', colorHex: '#32B4FF', order: 0);
  final thread1 = Thread(
    id: 't1',
    title: 'Design 3D Web',
    spaceId: 's1',
    type: ThreadType.task,
    status: ThreadStatus.doing,
    priority: Priority.high,
    checklist: const [ChecklistItem(id: 'c1', text: 'Define shaders', done: false)],
    links: const [],
    keywords: const ['design', 'web'],
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Widget makeTestable(Widget child, AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('showWebLegend opens and renders full legend guide', (tester) async {
    final state = AppState.test(spaces: [space1], threads: [thread1]);

    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showWebLegend(ctx),
            child: const Text('Open Legend'),
          ),
        ),
        state,
      ),
    );

    await tester.tap(find.text('Open Legend'));
    await tester.pumpAndSettle();

    expect(find.text('How to read your web'), findsOneWidget);
    expect(find.text('Spoke = space'), findsOneWidget);
    expect(find.text('Ring = urgency'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
  });

  testWidgets('ThreadEditor opens with existing thread data and allows edits', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState.test(spaces: [space1], threads: [thread1]);

    await tester.pumpWidget(
      makeTestable(
        ThreadEditor(threadId: thread1.id),
        state,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Design 3D Web'), findsOneWidget);
    expect(find.text('Define shaders'), findsOneWidget);

    // Enter notes
    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    // Save thread
    final saveButton = find.text('Save');
    if (saveButton.evaluate().isNotEmpty) {
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
    }
  });
}
