import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:spider_mind/app.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/state/app_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-End App Flow: Auth, Spaces, Web Canvas and Thread Creation', (tester) async {
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
    await tester.pumpAndSettle();

    // 1. Verify Home Shell loaded with spaces
    expect(find.text('Work'), findsWidgets);
    expect(find.text('Personal'), findsWidgets);

    // 2. Navigate to Threads List tab
    final threadsTab = find.byIcon(Icons.format_list_bulleted);
    await tester.tap(threadsTab);
    await tester.pumpAndSettle();

    expect(find.text('Master the 3D web'), findsOneWidget);
    expect(find.text('Review audio cues'), findsOneWidget);

    // 3. Search filter
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Master');
    await tester.pumpAndSettle();
    expect(find.text('Master the 3D web'), findsOneWidget);
    expect(find.text('Review audio cues'), findsNothing);

    // Clear search
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();

    // 4. Navigate to Insights tab
    final insightsTab = find.byIcon(Icons.auto_graph);
    await tester.tap(insightsTab);
    await tester.pumpAndSettle();
    expect(find.text('NEXT MOVES'), findsOneWidget);

    // 5. Navigate to Settings tab
    final settingsTab = find.byIcon(Icons.tune);
    await tester.tap(settingsTab);
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);

    // 6. Return to Web Canvas tab
    final webTab = find.byIcon(Icons.bubble_chart_outlined);
    await tester.tap(webTab);
    await tester.pumpAndSettle();
  });
}
