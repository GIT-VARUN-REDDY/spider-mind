import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spider_mind/app.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-End App Flow: Auth, Spaces, Web Canvas and Navigation', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final state = AppState.test(
      auth: AuthStatus.signedIn,
      spaces: const [
        Space(id: 's_work', name: 'Work', colorHex: '#32B4FF', order: 0),
        Space(id: 's_pers', name: 'Personal', colorHex: '#FF2A44', order: 1),
      ],
      threads: [
        Thread.draft(title: 'Master the 3D web', spaceId: 's_work', type: ThreadType.goal),
        Thread.draft(title: 'Review audio cues', spaceId: 's_pers', type: ThreadType.idea),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SpiderApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify Home Shell loaded with spaces
    expect(find.text('Work'), findsWidgets);
    expect(find.text('Personal'), findsWidgets);

    // 2. Navigate to Threads List tab
    await tester.tap(find.text('Threads'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Master the 3D web'), findsOneWidget);
    expect(find.text('Review audio cues'), findsOneWidget);

    // 3. Search filter
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Master');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Master the 3D web'), findsOneWidget);
    expect(find.text('Review audio cues'), findsNothing);

    // Clear search
    await tester.enterText(searchField, '');
    await tester.pump(const Duration(milliseconds: 100));

    // 4. Navigate to Insights tab
    await tester.tap(find.text('Insights'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Insights'), findsWidgets);

    // 5. Navigate to Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Settings'), findsWidgets);

    // 6. Return to Web Canvas tab
    await tester.tap(find.text('Web'));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
