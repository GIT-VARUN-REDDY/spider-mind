import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spider_mind/models/misc.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/state/app_state.dart';
import 'package:spider_mind/ui/editor.dart';
import 'package:spider_mind/ui/insights_screen.dart';
import 'package:spider_mind/ui/settings_screen.dart';
import 'package:spider_mind/ui/shell.dart';
import 'package:spider_mind/ui/theme.dart';
import 'package:spider_mind/ui/threads_screen.dart';

Widget createTestApp({required AppState state, required Widget child}) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: child,
    ),
  );
}

void main() {
  final testSpaces = [
    Space.create('Work', '#32B4FF', 0),
    Space.create('Study', '#3DDC97', 1),
    Space.create('Personal', '#FF2A44', 2),
  ];

  final testThreads = [
    Thread.draft(
      title: 'Task Alpha',
      spaceId: testSpaces[0].id,
      type: ThreadType.task,
      priority: Priority.high,
    ),
    Thread.draft(
      title: 'Idea Beta',
      spaceId: testSpaces[1].id,
      type: ThreadType.idea,
      priority: Priority.medium,
    ),
    Thread.draft(
      title: 'Goal Gamma',
      spaceId: testSpaces[2].id,
      type: ThreadType.goal,
      priority: Priority.high,
    ),
  ];

  group('AuthScreen widget tests', () {
    testWidgets('renders login form and title by default', (tester) async {
      final state = AppState.test(auth: AuthStatus.signedOut);
      await tester.pumpWidget(createTestApp(state: state, child: const AuthScreen()));
      await tester.pump();

      expect(find.text('Project Spider'), findsOneWidget);
      expect(find.text('Your tasks, ideas and goals as one living web.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('New here? Create an account'), findsOneWidget);
      expect(find.text('Server settings'), findsOneWidget);
    });

    testWidgets('switches to register form and back', (tester) async {
      final state = AppState.test(auth: AuthStatus.signedOut);
      await tester.pumpWidget(createTestApp(state: state, child: const AuthScreen()));
      await tester.pump();

      // Tap toggle to register
      await tester.tap(find.text('New here? Create an account'));
      await tester.pump();

      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);

      // Tap back to sign in
      await tester.tap(find.text('I already have an account'));
      await tester.pump();

      expect(find.text('Your name'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('shows validation errors on empty submission', (tester) async {
      final state = AppState.test(auth: AuthStatus.signedOut);
      await tester.pumpWidget(createTestApp(state: state, child: const AuthScreen()));
      await tester.pump();

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
    });

    testWidgets('displays auth error message when state has authError', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedOut,
        authError: 'Invalid email or password',
      );
      await tester.pumpWidget(createTestApp(state: state, child: const AuthScreen()));
      await tester.pump();

      expect(find.text('Invalid email or password'), findsOneWidget);
    });
  });

  group('HomeShell widget tests', () {
    testWidgets('renders navigation bar items and spaces', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const HomeShell()));
      await tester.pump(const Duration(milliseconds: 100));

      // Bottom navigation bar items
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Header and spaces in top bar
      expect(find.text('Your web'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);

      // FAB is present
      expect(find.text('New thread'), findsOneWidget);
    });

    testWidgets('navigates to Threads tab and shows thread list', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const HomeShell()));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Threads tab
      await tester.tap(find.text('Threads'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Task Alpha'), findsOneWidget);
      expect(find.text('Idea Beta'), findsOneWidget);
      expect(find.text('Goal Gamma'), findsOneWidget);
    });

    testWidgets('navigates to Insights tab and displays stats', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const HomeShell()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Insights'));
      await tester.pump(const Duration(milliseconds: 300));

      // Destination label + screen header
      expect(find.text('Insights'), findsNWidgets(2));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Next move'), findsOneWidget);
    });

    testWidgets('navigates to Settings tab', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const HomeShell()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));

      // Destination label + screen header
      expect(find.text('Settings'), findsNWidgets(2));
      expect(find.text('ACCOUNT'), findsOneWidget);
    });
  });

  group('ThreadsScreen widget tests', () {
    testWidgets('filters threads using search query', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const Scaffold(body: ThreadsScreen())));
      await tester.pump();

      expect(find.text('Task Alpha'), findsOneWidget);
      expect(find.text('Idea Beta'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField).first, 'Alpha');
      await tester.pump();

      expect(find.text('Task Alpha'), findsOneWidget);
      expect(find.text('Idea Beta'), findsNothing);
    });
  });

  group('InsightsScreen widget tests', () {
    testWidgets('renders overview metrics and next moves', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
        threads: testThreads,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const Scaffold(body: InsightsScreen())));
      await tester.pump();

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Next move'), findsOneWidget);
      expect(find.text('Task Alpha'), findsOneWidget);
    });
  });

  group('SettingsScreen widget tests', () {
    testWidgets('renders settings options and user account email', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        user: const UserProfile(id: 'u1', email: 'spidertest@mind.app', name: 'Spider Tester', timezone: 'UTC'),
        spaces: testSpaces,
      );
      await tester.pumpWidget(createTestApp(state: state, child: const Scaffold(body: SettingsScreen())));
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Spider Tester'), findsOneWidget);
      expect(find.text('spidertest@mind.app'), findsOneWidget);
      expect(find.text('Daily digest'), findsOneWidget);
    });
  });

  group('ThreadEditor widget tests', () {
    testWidgets('renders title and type choices for new thread', (tester) async {
      final state = AppState.test(
        auth: AuthStatus.signedIn,
        spaces: testSpaces,
      );
      await tester.pumpWidget(createTestApp(
        state: state,
        child: const Scaffold(body: ThreadEditor()),
      ));
      await tester.pump();

      expect(find.text('New thread'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('TYPE'), findsOneWidget);
      expect(find.text('PRIORITY'), findsOneWidget);
      expect(find.text('What is this thread?'), findsOneWidget);
    });
  });
}
