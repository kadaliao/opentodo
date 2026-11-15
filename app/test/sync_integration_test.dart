// Two simulated devices sync through the real Go server, built and started
// by this test. Skipped when Go isn't installed.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/sync/account.dart';
import 'package:opentodo/sync/sync_engine.dart';

late String serverUrl;
Process? _server;
Directory? _tmp;
var _emails = 0;

bool get goAvailable {
  try {
    return Process.runSync('go', ['version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> startServer() async {
  _tmp = await Directory.systemTemp.createTemp('opentodo-sync-test');
  final bin = '${_tmp!.path}/opentodo-server';
  final build = await Process.run('go', ['build', '-o', bin, './cmd/opentodo-server'],
      workingDirectory: '../server');
  if (build.exitCode != 0) throw StateError('go build failed:\n${build.stderr}');

  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  // Every test signs devices in afresh; more than the default limit allows.
  _server = await Process.start(bin, [
    '-addr', '127.0.0.1:$port',
    '-db', '${_tmp!.path}/test.db',
    '-auth-per-minute', '1000',
  ]);
  _server!.stderr.drain<void>();
  serverUrl = 'http://127.0.0.1:$port';
  for (var i = 0; i < 100; i++) {
    try {
      final r = await http.get(Uri.parse('$serverUrl/v1/health'));
      if (r.statusCode == 200) return;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('server did not start');
}

class Device {
  Device() : db = AppDatabase(NativeDatabase.memory()) {
    repo = TaskRepo(db, clock: () => now);
    engine = SyncEngine(db, client);
  }

  final AppDatabase db;
  final client = http.Client();
  late final TaskRepo repo;
  late final SyncEngine engine;
  DateTime now = DateTime(2026, 11, 15, 10);

  void advance([Duration d = const Duration(minutes: 1)]) => now = now.add(d);

  Future<void> signIn(String email, {bool register = false}) async {
    final account = await AuthApi(client).signIn(
        serverUrl: serverUrl, email: email, password: 'correct horse', register: register);
    await completeSignIn(db, account);
  }

  Future<SyncReport> sync() => engine.sync();

  Future<List<Task>> tasks() => repo.watchTasks().first;
  Future<Task?> task(String id) async =>
      (await tasks()).where((t) => t.id == id).firstOrNull;

  Future<void> close() async {
    client.close();
    await db.close();
  }
}

String newEmail() => 'user${_emails++}-${DateTime.now().microsecondsSinceEpoch}@example.com';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final skip = goAvailable ? null : 'Go is not installed';

  setUpAll(() async {
    if (skip == null) await startServer();
  });
  tearDownAll(() async {
    _server?.kill();
    await _server?.exitCode;
    await _tmp?.delete(recursive: true);
  });

  late Device phone, mac;
  setUp(() {
    phone = Device();
    mac = Device();
  });
  tearDown(() async {
    await phone.close();
    await mac.close();
  });

  test('two devices converge: create, edit, delete', () async {
    final email = newEmail();
    await phone.signIn(email, register: true);
    await mac.signIn(email);

    final listId = await phone.repo.addList('工作', emoji: '💼');
    final taskId = await phone.repo.addTask(title: '写周报', listId: listId);
    await phone.repo.addChecklistItem(taskId, '整理数据');
    expect((await phone.sync()).pushed, 3);

    await mac.sync();
    expect((await mac.repo.watchLists().first).single.name, '工作');
    expect((await mac.task(taskId))!.title, '写周报');
    expect((await mac.repo.watchChecklist(taskId).first).single.title, '整理数据');

    // Everything the Mac received is clean; nothing to push back.
    expect(await watchDirtyCount(mac.db).first, 0);

    mac.advance();
    await mac.repo.setTitle(taskId, '写周报（周五前）');
    await mac.repo.setCompleted(taskId, true);
    await mac.sync();
    await phone.sync();
    final onPhone = (await phone.task(taskId))!;
    expect(onPhone.title, '写周报（周五前）');
    expect(onPhone.status, TaskStatus.done);

    phone.advance();
    await phone.repo.trashTask(taskId);
    await phone.repo.emptyTrash();
    await phone.sync();
    await mac.sync();
    expect(await mac.task(taskId), isNull);
    expect(await mac.repo.watchChecklist(taskId).first, isEmpty);
    // Tombstones the server has are purged locally.
    expect(await mac.repo.getTask(taskId), isNull);
  }, skip: skip);

  test('the newer edit wins a conflict', () async {
    final email = newEmail();
    await phone.signIn(email, register: true);
    await mac.signIn(email);
    final id = await phone.repo.addTask(title: '原标题');
    await phone.sync();
    await mac.sync();

    // Both edit offline; the Mac's edit is later but the phone syncs first.
    phone.advance(const Duration(minutes: 1));
    await phone.repo.setTitle(id, '手机改的');
    mac.advance(const Duration(minutes: 2));
    await mac.repo.setTitle(id, '电脑改的');

    await phone.sync();
    await mac.sync(); // later edit: accepted
    await phone.sync(); // phone takes it
    expect((await phone.task(id))!.title, '电脑改的');
    expect((await mac.task(id))!.title, '电脑改的');

    // Now the reverse: the phone's stale edit is pushed after a newer one.
    mac.advance(const Duration(minutes: 5));
    await mac.repo.setPriority(id, Priority.high);
    await mac.sync();
    await phone.repo.setPriority(id, Priority.low); // phone clock is behind
    await phone.sync();
    final p = (await phone.task(id))!;
    expect(p.priority, Priority.high);
    expect(p.dirty, isFalse);
  }, skip: skip);

  test('signing in drops untouched welcome items but keeps real work', () async {
    final email = newEmail();
    await mac.signIn(email, register: true);
    await mac.repo.addTask(title: '已有的任务');
    await mac.sync();

    // A fresh install: welcome items, plus one the person ticked off and one
    // they wrote themselves.
    await phone.repo.seedIfEmpty();
    final seeded = await phone.tasks();
    phone.advance();
    await phone.repo.setCompleted(seeded.first.id, true);
    await phone.repo.addTask(title: '离线时记的');

    await phone.signIn(email);
    await phone.sync();
    final titles = (await phone.tasks()).map((t) => t.title).toSet();
    expect(titles, containsAll(['已有的任务', '离线时记的', seeded.first.title]));
    expect(titles.length, 3);

    await mac.sync();
    expect((await mac.tasks()).length, 3);
  }, skip: skip);

  test('two installs that both kept the welcome items share one copy', () async {
    final email = newEmail();
    await phone.repo.seedIfEmpty();
    await mac.repo.seedIfEmpty();
    // Both tick off the same welcome task, so neither drops it on sign-in.
    phone.advance();
    mac.advance(const Duration(minutes: 2));
    await phone.repo.setCompleted('seed-today', true);
    await mac.repo.setCompleted('seed-today', true);

    await phone.signIn(email, register: true);
    await phone.sync();
    await mac.signIn(email);
    await mac.sync();
    await phone.sync();
    for (final d in [phone, mac]) {
      final titles = (await d.tasks()).map((t) => t.title).toList();
      expect(titles, ['看看“今天”和“最近7天”']);
    }
  }, skip: skip);

  test('a repeating task: reminders and repeat travel, finishing it moves it on everywhere', () async {
    final email = newEmail();
    await phone.signIn(email, register: true);
    await mac.signIn(email);
    final id = await phone.repo.addTask(
      title: '吃药',
      dueDate: DateTime(2026, 11, 15),
      dueTime: 8 * 60,
      reminders: [0, -10],
      repeatRule: 'FREQ=DAILY;INTERVAL=2',
      repeatFrom: 1,
    );
    await phone.sync();
    await mac.sync();
    var t = (await mac.task(id))!;
    expect(t.reminders, [0, -10]);
    expect(t.repeatRule, 'FREQ=DAILY;INTERVAL=2');
    expect(t.repeatFrom, 1);

    mac.advance();
    final done = (await mac.repo.setCompleted(id, true))!;
    await mac.sync();
    await phone.sync();
    t = (await phone.task(id))!;
    expect(t.dueDate, '2026-11-17');
    expect(t.status, TaskStatus.open);
    final copy = (await phone.task(done.copyId))!;
    expect(copy.status, TaskStatus.done);
    expect(copy.dueDate, '2026-11-15');
  }, skip: skip);

  test('both devices finishing the same occurrence offline leave one copy', () async {
    final email = newEmail();
    await phone.signIn(email, register: true);
    await mac.signIn(email);
    final id = await phone.repo.addTask(
      title: '打卡',
      dueDate: DateTime(2026, 11, 15),
      repeatRule: 'FREQ=DAILY',
    );
    await phone.sync();
    await mac.sync();

    phone.advance();
    mac.advance(const Duration(minutes: 2));
    await phone.repo.setCompleted(id, true);
    await mac.repo.setCompleted(id, true);
    await phone.sync();
    await mac.sync();
    await phone.sync();

    for (final d in [phone, mac]) {
      final tasks = await d.tasks();
      expect(tasks.length, 2, reason: 'the task and one finished copy');
      expect((await d.task(id))!.dueDate, '2026-11-16');
      expect(tasks.where((t) => t.status == TaskStatus.done).length, 1);
    }
  }, skip: skip);

  test('filters sync: create, edit, delete', () async {
    final email = newEmail();
    await phone.signIn(email, register: true);
    await mac.signIn(email);

    final id = await phone.repo.addFilter(
        '本周重要', '{"match":"all","conditions":[{"field":"date","values":["thisWeek"]}]}');
    expect(await watchDirtyCount(phone.db).first, 1);
    await phone.sync();
    await mac.sync();
    final onMac = (await mac.repo.watchFilters().first).single;
    expect(onMac.name, '本周重要');
    expect(onMac.rule, contains('thisWeek'));
    expect(await watchDirtyCount(mac.db).first, 0);

    mac.advance();
    await mac.repo.updateFilter(id, name: '本周', rule: '{"match":"any","conditions":[]}');
    await mac.sync();
    await phone.sync();
    final onPhone = (await phone.repo.watchFilters().first).single;
    expect(onPhone.name, '本周');
    expect(onPhone.rule, '{"match":"any","conditions":[]}');

    phone.advance();
    await phone.repo.deleteFilter(id);
    await phone.sync();
    await mac.sync();
    expect(await mac.repo.watchFilters().first, isEmpty);
    expect(await mac.db.select(mac.db.taskFilters).get(), isEmpty); // tombstone purged
  }, skip: skip);

  test('a bad token reports that sign-in is needed', () async {
    await phone.signIn(newEmail(), register: true);
    await phone.db.setValue(Keys.token, 'expired');
    await expectLater(
      phone.sync(),
      throwsA(isA<SyncException>().having((e) => e.isAuth, 'isAuth', isTrue)),
    );
  }, skip: skip);
}
