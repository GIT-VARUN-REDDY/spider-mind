import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spider_mind/data/api.dart';
import 'package:spider_mind/data/store.dart';
import 'package:spider_mind/logic/outbox.dart';
import 'package:spider_mind/models/misc.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalStore & Models unit tests', () {
    test('LocalStore reads, writes and clears data correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final store = LocalStore(p);

      expect(store.clientId, startsWith('app-'));
      expect(store.serverUrl, isNull);
      await store.setServerUrl('http://10.0.2.2:4000');
      expect(store.serverUrl, 'http://10.0.2.2:4000');

      const settings = AppSettings(theme: ThemeModeSetting.dark, digestEnabled: true, digestMinutes: 540);
      await store.saveSettings(settings);
      expect(store.settings.theme, ThemeModeSetting.dark);
      expect(store.settings.digestEnabled, isTrue);
      expect(store.settings.digestMinutes, 540);

      const user = UserProfile(id: 'u1', email: 'spidey@nyc.gov', name: 'Peter Parker', timezone: 'EST');
      await store.saveUser(user);
      expect(store.user?.email, 'spidey@nyc.gov');
      expect(store.user?.name, 'Peter Parker');

      final thread = Thread.draft(title: 'Save City', spaceId: 's1');
      await store.saveThreads([thread]);
      expect(store.threads, hasLength(1));
      expect(store.threads.first.id, thread.id);

      final space = Space.create('Patrol', '#FF2A44', 0);
      await store.saveSpaces([space]);
      expect(store.spaces, hasLength(1));
      expect(store.spaces.first.name, 'Patrol');

      final op = OutboxOp(kind: OutboxKind.putThread, id: thread.id, body: thread.toJson());
      await store.saveOutbox([op]);
      expect(store.outbox, hasLength(1));
      expect(store.outbox.first.id, thread.id);

      await store.saveCursor('2026-11-04T00:00:00Z');
      expect(store.cursor, '2026-11-04T00:00:00Z');

      await store.clearAccountData();
      expect(store.threads, isEmpty);
      expect(store.spaces, isEmpty);
      expect(store.outbox, isEmpty);
      expect(store.cursor, isNull);

      await store.clearAccount();
      expect(store.user, isNull);
    });

    test('Misc models serialization and copyWith', () {
      const u = UserProfile(id: 'u1', email: 'peter@spider.io', name: 'Peter', timezone: 'UTC');
      final uj = u.toJson();
      final uCopy = UserProfile.fromJson(uj);
      expect(uCopy.id, u.id);
      expect(uCopy.email, u.email);

      final now = DateTime.now().toUtc();
      final a = ActivityEntry(id: 'a1', kind: ActivityKind.created, threadId: 't1', message: 'Created thread', at: now);
      expect(a.id, 'a1');
      expect(a.message, 'Created thread');
      expect(a.kind, ActivityKind.created);

      final ex = ApiException(404, 'Not found', code: 'E_NOT_FOUND');
      expect(ex.status, 404);
      expect(ex.offline, isFalse);
      expect(ex.toString(), 'Not found');

      final offlineEx = ApiException(0, 'No net');
      expect(offlineEx.offline, isTrue);

      const tokens = AuthTokens('acc', 'ref');
      expect(tokens.access, 'acc');
      expect(tokens.refresh, 'ref');
    });

    test('LocalStore.noop handles operations without errors', () async {
      final noop = LocalStore.noop();
      expect(noop.clientId, 'test-client-id');
      expect(noop.serverUrl, isNull);
      await noop.setServerUrl('http://test');
      expect(noop.settings.digestMinutes, 540);
      await noop.saveSettings(const AppSettings());
      expect(noop.user, isNull);
      await noop.saveUser(null);
      expect(noop.threads, isEmpty);
      expect(noop.spaces, isEmpty);
      expect(noop.outbox, isEmpty);
      expect(noop.cursor, isNull);
      await noop.saveThreads([]);
      await noop.saveSpaces([]);
      await noop.saveOutbox([]);
      await noop.saveCursor(null);
      await noop.clearAccountData();
      await noop.clearAccount();
    });
  });
}
