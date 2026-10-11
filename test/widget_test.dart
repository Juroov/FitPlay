import 'package:flutter/material.dart';
import 'package:fitplay/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'fittrack_dark_mode': true});
  });

  testWidgets('sign-in button validates fields and opens the app', (
    WidgetTester tester,
  ) async {
    final appState = AppState(initialDarkMode: true);
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: appState, child: const FitTrackApp()),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Minimum 8 characters'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'athlete@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password1',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add New Workout'));
    await tester.pumpAndSettle();
    expect(find.text('New Routine'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pump();
    expect(find.text('Please enter a routine name'), findsOneWidget);
  });

  testWidgets('resume and complete workout buttons save one workout', (
    WidgetTester tester,
  ) async {
    final appState = AppState(initialDarkMode: true);
    addTearDown(appState.dispose);
    await appState.login('athlete@example.com', 'password1');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: appState, child: const FitTrackApp()),
    );
    await tester.pump();

    appState.startWorkoutSession(appState.workouts.first);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Complete & Save Workout'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(appState.activeWorkoutSession!.exercises.first.isCompleted, isTrue);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Complete & Save Workout'),
    );
    await tester.pumpAndSettle();

    expect(appState.isSessionRunning, isFalse);
    expect(appState.logs, hasLength(1));
    expect(find.text('Resume'), findsNothing);
  });

  test('logout cancels an active workout session', () async {
    final appState = AppState(initialDarkMode: true);
    addTearDown(appState.dispose);
    await appState.login('athlete@example.com', 'password1');
    appState.startWorkoutSession(appState.workouts.first);

    await appState.logout();

    expect(appState.isAuthenticated, isFalse);
    expect(appState.isSessionRunning, isFalse);
    expect(appState.sessionSeconds, 0);
  });

  test('completing the same workout twice in a day is idempotent', () async {
    final appState = AppState(initialDarkMode: true);
    addTearDown(appState.dispose);
    await appState.login('athlete@example.com', 'password1');

    final workout = appState.workouts.first;
    appState.startWorkoutSession(workout);
    await appState.completeActiveSession();
    appState.startWorkoutSession(workout);
    await appState.completeActiveSession();

    expect(appState.logs, hasLength(1));
    expect(appState.logs.single.id, contains(workout.id));
  });
}
