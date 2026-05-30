import 'package:cue/widgets/sidebar_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Verifies the sidebar collapsed/expanded preference persists via the app's
// storage layer (SharedPreferences, same as theme), surviving reloads.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset the in-memory singleton between tests (it's a global).
    sidebarNotifier.value = false;
  });

  test('defaults to expanded when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isFalse);
  });

  test('load restores a persisted collapsed=true', () async {
    SharedPreferences.setMockInitialValues({'sidebar_collapsed': true});
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isTrue);
  });

  test('toggle persists; a fresh load (restart) restores the new value',
      () async {
    SharedPreferences.setMockInitialValues({});
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isFalse);

    await sidebarNotifier.toggle(); // → collapsed
    expect(sidebarNotifier.isCollapsed, isTrue);

    // Simulate an app restart: wipe in-memory state, reload from storage.
    sidebarNotifier.value = false;
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isTrue,
        reason: 'collapsed state must survive a reload/restart');
  });

  test('setCollapsed(false) persists the expanded choice', () async {
    SharedPreferences.setMockInitialValues({'sidebar_collapsed': true});
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isTrue);

    await sidebarNotifier.setCollapsed(false);
    sidebarNotifier.value = true; // wipe in-memory
    await sidebarNotifier.load();
    expect(sidebarNotifier.isCollapsed, isFalse);
  });

  test('notifies listeners when the value changes', () async {
    SharedPreferences.setMockInitialValues({});
    await sidebarNotifier.load();
    var notified = 0;
    void listener() => notified++;
    sidebarNotifier.addListener(listener);
    await sidebarNotifier.toggle();
    sidebarNotifier.removeListener(listener);
    expect(notified, greaterThanOrEqualTo(1));
  });
}
