import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/server.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Playback implements LanCastPlayback, LanCastSettingsPlayback {
  LanCastMedia? media;
  final commands = <(String, double?)>[];
  final loads = <LanCastMedia>[];
  Completer<void>? loadStarted;
  bool playing = false;
  bool fullscreen = false;
  bool completed = false;
  bool reportCurrentMedia = false;
  bool buffering = false;
  int stopped = 0;
  Completer<void>? loading;
  bool failLoad = false;
  bool failAfterLoad = false;
  bool danmaku = true;
  double scale = 100;
  String quality = '80';
  final settingsChanges = <(String, Object)>[];
  Completer<void>? applyingSetting;
  Completer<void>? settingStarted;
  @override
  LanCastStatus get status => LanCastStatus(
    title: media?.title ?? '',
    mediaKey: media?.key ?? '',
    position: completed ? 120000 : media?.position ?? 0,
    duration: 120000,
    playing: playing,
    buffering: buffering,
    currentMedia: reportCurrentMedia ? media : null,
    isLive: media?.isLive ?? false,
    speed: media?.speed ?? 1,
    fullscreen: fullscreen,
    canFullscreen: true,
    settings: [
      LanCastSetting(
        key: 'danmaku',
        label: '显示弹幕',
        group: '弹幕设置',
        value: danmaku,
      ),
      LanCastSetting(
        key: 'dmScale',
        label: '字体大小',
        group: '弹幕设置',
        value: scale,
        min: 50,
        max: 600,
        divisions: 550,
      ),
      LanCastSetting(
        key: 'quality',
        label: '选择画质',
        group: '播放设置',
        value: quality,
        options: const {'80': '1080P', '64': '720P'},
      ),
    ],
  );
  @override
  Future<void> setSetting(String key, Object value) async {
    settingsChanges.add((key, value));
    settingStarted?.complete();
    settingStarted = null;
    await applyingSetting?.future;
    switch (key) {
      case 'danmaku':
        danmaku = value as bool;
      case 'dmScale':
        scale = value as double;
      case 'quality':
        quality = value as String;
    }
  }

  @override
  Future<void> load(LanCastMedia value) async {
    loads.add(value);
    loadStarted?.complete();
    loadStarted = null;
    if (failLoad) throw StateError('Playback failed');
    await loading?.future;
    if (failAfterLoad) {
      failAfterLoad = false;
      media = null;
      throw StateError('Failed after closing previous video');
    }
    media = value;
    completed = false;
    playing = true;
  }

  @override
  Future<void> command(String action, double? value) async {
    commands.add((action, value));
    if (action == 'play') playing = true;
    if (action == 'pause') playing = false;
    if (action == 'fullscreen') fullscreen = value == 1;
  }

  @override
  Future<void> stop() async {
    media = null;
    playing = false;
    stopped++;
  }
}

const _media = LanCastMedia(
  title: '测试视频',
  aid: 170001,
  bvid: 'BV17x411w7KC',
  cid: 279786,
  position: 42000,
  speed: 1.5,
);
const _live = LanCastMedia(title: '直播', kind: 'live', roomId: 1234);
Matcher _status(int code) => throwsA(
  isA<LanCastException>().having((e) => e.statusCode, 'status', code),
);

Future<LanCastStore> _store() async {
  final store = LanCastStore({}, (_) async {});
  await store.initializeIdentity();
  return store;
}

void main() {
  test(
    'identities round-trip without sending playback URLs or credentials',
    () {
      for (final media in [
        _media,
        _live,
        const LanCastMedia(
          title: '番剧',
          kind: 'pgc',
          aid: 1,
          cid: 2,
          epId: 3,
          seasonId: 4,
        ),
        const LanCastMedia(title: '课程', kind: 'pugv', aid: 1, cid: 2, epId: 3),
      ]) {
        expect(LanCastMedia.fromJson(media.toJson()).toJson(), media.toJson());
        expect(media.toJson(), isNot(contains('videoUrl')));
        expect(media.toJson(), isNot(contains('audioUrl')));
      }
    },
  );

  test('rejects invalid identities and playback values', () {
    for (final change in <Map<String, dynamic>>[
      {'kind': 'file'},
      {'aid': -1},
      {'cid': null},
      {'bvid': 'file:///video'},
      {'kind': 'pgc', 'epId': null},
      {'kind': 'live', 'roomId': 0},
      {'speed': double.nan},
      {'speed': 5},
      {'position': -1},
    ]) {
      expect(
        () => LanCastMedia.fromJson({..._media.toJson(), ...change}),
        throwsA(isA<LanCastException>()),
      );
    }
  });

  test(
    'list sources round-trip as API identifiers without copying entries',
    () {
      const source = LanCastListSource(
        type: 'fav',
        id: 123,
        title: '收藏夹',
        desc: true,
      );
      final json = {..._media.toJson(), 'listSource': source.toJson()};
      final media = LanCastMedia.fromJson(json);
      expect(media.listSource?.toJson(), source.toJson());
      expect(media.toJson(), isNot(contains('playlist')));
      expect(media.toJson(), isNot(contains('token')));
      final state = LanCastStatus(mediaKey: media.key, currentMedia: media);
      expect(
        LanCastStatus.fromJson(state.toJson()).currentMedia?.listSource?.id,
        123,
      );
      expect(
        LanCastStatus.fromJson(const LanCastStatus().toJson()).currentMedia,
        isNull,
      );
      for (final change in [
        {'type': 'file'},
        {'id': 0},
        {'id': 1.5},
        {'mediaType': 1.5},
        {'sortField': 1.5},
        {'desc': 'true'},
      ]) {
        expect(
          () => LanCastListSource.fromJson({...source.toJson(), ...change}),
          throwsA(isA<LanCastException>()),
        );
      }
    },
  );

  test('only explicit LAN IP endpoints are allowed', () {
    expect(lanCastAddress('192.168.1.10:51000').host, '192.168.1.10');
    for (final address in [
      '8.8.8.8:80',
      'example.com:80',
      '192.168.1.2',
      '192.168.1.2:80/status',
      'https://192.168.1.2:80',
      'http://user:pass@192.168.1.2:80',
      '192.168.1.2:0',
    ]) {
      expect(() => lanCastAddress(address), throwsA(isA<LanCastException>()));
    }
  });

  group('real HTTP pairing and playback', () {
    late _Playback playback;
    late LanCastStore store;
    late LanCastServer server;
    late LanCastClient client;
    late Uri uri;

    Future<void> pair([String id = 'phone']) async {
      server.beginPairing();
      await client.pair(server.pairingCode!, '手机', id);
      await client.connect();
    }

    setUp(() async {
      playback = _Playback();
      store = await _store();
      server = LanCastServer(name: '电脑', playback: playback, store: store);
      await server.start(address: InternetAddress.loopbackIPv4);
      uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      client = LanCastClient(uri);
    });
    tearDown(() async {
      client.close();
      await server.close();
    });

    test(
      'requires explicit pairing mode, closes it after one successful pair',
      () async {
        await expectLater(client.pair('123456', '手机', 'phone'), _status(403));
        await expectLater(client.status(), _status(401));
        await pair();
        expect(server.pairingCode, isNull);
        expect(store.peers['phone']?['name'], '手机');
        final state = await client.load(_media);
        expect(state.position, 42000);
        expect(state.mediaKey, _media.key);
        expect(state.speed, 1.5);
        await client.command('pause');
        expect((await client.status()).playing, isFalse);
        await client.command('seek', 90000);
        await client.command('volume', 40);
        await client.command('speed', 2);
        expect(playback.commands, [
          ('pause', null),
          ('seek', 90000.0),
          ('volume', 40.0),
          ('speed', 2.0),
        ]);
      },
    );

    test('disconnect stops playback but retains trust for reconnect', () async {
      await pair();
      final token = client.token;
      await client.load(_media);
      await client.disconnect();
      expect(playback.playing, isFalse);
      expect(server.paired, isFalse);
      expect(client.token, token);
      await expectLater(client.command('play'), _status(409));
      await client.connect();
      expect((await client.load(_media)).playing, isTrue);
    });

    test('settings use receiver options, require active pairing and reject stale media', () async {
      await expectLater(
        client.setSetting(_media.key, 'danmaku', false),
        _status(401),
      );
      await pair();
      await client.load(_media);
      final state = await client.setSetting(_media.key, 'dmScale', 600);
      expect(state.settings.firstWhere((e) => e.key == 'dmScale').value, 600);
      await client.setSetting(_media.key, 'danmaku', false);
      await client.setSetting(_media.key, 'quality', '64');
      expect(playback.danmaku, isFalse);
      expect(playback.quality, '64');
      for (final (key, value) in <(String, Object)>[
        ('dmScale', 601),
        ('dmScale', '600'),
        ('danmaku', 1),
        ('quality', '120'),
        ('quality', 80),
      ]) {
        await expectLater(
          client.setSetting(_media.key, key, value),
          _status(400),
        );
      }
      await expectLater(
        client.setSetting(_media.key, 'mpvProperty', 'file:///tmp/private'),
        _status(422),
      );
      await client.load(_live);
      await expectLater(
        client.setSetting(_media.key, 'danmaku', true),
        _status(422),
      );
      expect(playback.settingsChanges.length, 3);
      await client.disconnect();
      await expectLater(
        client.setSetting(_live.key, 'danmaku', true),
        _status(409),
      );
    });

    test(
      'settings share load queue and obsolete queued changes are discarded',
      () async {
        final senderStore = await _store();
        final session = LanCastSession(trustStore: senderStore);
        server.beginPairing();
        await session.connect(
          LanCastDevice(id: server.id, name: server.name, uri: uri),
          server.pairingCode,
          _media,
        );
        playback
          ..applyingSetting = Completer<void>()
          ..settingStarted = Completer<void>();
        final first = session.setSetting('dmScale', 600);
        await playback.settingStarted!.future;
        final obsolete = session.setSetting('danmaku', false);
        final replace = session.replaceMedia(_live);
        playback.applyingSetting!.complete();
        await first;
        await obsolete;
        await replace;
        expect(playback.settingsChanges, [('dmScale', 600.0)]);
        expect(session.mediaKey, _live.key);
        expect(
          session.status.settings.firstWhere((e) => e.key == 'dmScale').value,
          600,
        );
        await session.disconnect();
        session.dispose();
      },
    );

    test('fullscreen command is explicit, validates its value and works for live video', () async {
      await pair();
      await client.load(_live);
      expect((await client.command('fullscreen', 1)).fullscreen, isTrue);
      expect((await client.command('fullscreen', 1)).fullscreen, isTrue);
      expect((await client.command('fullscreen', 0)).fullscreen, isFalse);
      for (final value in [-1.0, 0.5, 2.0]) {
        await expectLater(client.command('fullscreen', value), _status(400));
      }
      expect(playback.playing, isTrue);
      expect(playback.commands, [
        ('fullscreen', 1.0),
        ('fullscreen', 1.0),
        ('fullscreen', 0.0),
      ]);
    });

    test(
      'receiver restart retains identity and accepts saved credentials',
      () async {
        await pair();
        final id = (await client.info()).id;
        final token = client.token;
        await server.close();
        server = LanCastServer(
          name: '电脑',
          playback: playback,
          store: LanCastStore(
            Map<String, dynamic>.from(
              jsonDecode(jsonEncode(store.data)) as Map,
            ),
            (_) async {},
          ),
        );
        await server.start(address: InternetAddress.loopbackIPv4);
        client.close();
        client = LanCastClient(uri.replace(port: server.port))..token = token;
        expect((await client.info()).id, id);
        expect(server.pairingCode, isNull);
        await client.connect();
        expect((await client.load(_media)).playing, isTrue);
      },
    );

    test('revocation and unpair invalidate remembered credentials', () async {
      await pair();
      await client.load(_media);
      await server.revoke('phone');
      expect(playback.playing, isFalse);
      await expectLater(client.connect(), _status(401));
      await pair();
      await client.unpair();
      expect(store.peers, isEmpty);
      await expectLater(client.connect(), _status(401));
    });

    test(
      'only active sender can control even if multiple devices are trusted',
      () async {
        await pair();
        final other = LanCastClient(uri);
        addTearDown(other.close);
        server.beginPairing();
        await other.pair(server.pairingCode!, '平板', 'tablet');
        await expectLater(other.connect(), _status(409));
        await expectLater(other.command('pause'), _status(409));
        await client.disconnect();
        await other.connect();
        await expectLater(client.command('pause'), _status(409));
      },
    );

    test('rate limits incorrect pairing codes', () async {
      server.beginPairing();
      final badCode = server.pairingCode == '000000' ? '111111' : '000000';
      for (var i = 0; i < 6; i++) {
        await expectLater(client.pair(badCode, '手机', 'phone'), _status(403));
      }
      await expectLater(
        client.pair(server.pairingCode!, '手机', 'phone'),
        _status(429),
      );
    });

    test('validates command range and live playback capabilities', () async {
      await pair();
      await client.load(_live);
      await expectLater(client.command('seek', 100), _status(400));
      await expectLater(client.command('speed', 2), _status(400));
      await expectLater(client.command('volume', 101), _status(400));
      await expectLater(client.command('shell'), _status(400));
      await client.command('volume', 20);
      expect(playback.commands, [('volume', 20.0)]);
    });

    test('serializes loading and disconnect', () async {
      await pair();
      playback.loading = Completer<void>();
      final loading = client.load(_media);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final disconnecting = client.disconnect();
      playback.loading!.complete();
      await loading;
      await disconnecting;
      expect(playback.playing, isFalse);
    });

    test('rejects browser requests and oversized JSON', () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final request = await http.getUrl(uri.replace(path: '/info'));
      request.headers.set('Origin', 'https://example.com');
      expect((await request.close()).statusCode, 403);
      final oversized = await http.postUrl(uri.replace(path: '/pair'));
      oversized.headers.contentType = ContentType.json;
      oversized.write(jsonEncode({'code': '1' * (lanCastBodyLimit + 1)}));
      expect((await oversized.close()).statusCode, 413);
    });

    test(
      'session remembers pairing after a failed load and queues gestures',
      () async {
        final session = LanCastSession(trustStore: await _store());
        addTearDown(session.dispose);
        final device = await client.info();
        server.beginPairing();
        playback.failLoad = true;
        await expectLater(
          session.connect(device, server.pairingCode, _media),
          _status(500),
        );
        expect(session.connected, isFalse);
        expect(server.paired, isFalse);
        expect(session.store.targets, contains(device.id));
        playback.failLoad = false;
        await session.connect(device, null, _media);
        expect(session.media?.toJson(), _media.toJson());
        await Future.wait([
          session.command('speed', 3),
          session.command('speed', 1.5),
          session.command('seek', 55000),
          session.command('play'),
        ]);
        expect(playback.commands, [
          ('speed', 3.0),
          ('speed', 1.5),
          ('seek', 55000.0),
          ('play', null),
        ]);
        await session.disconnect();
        expect(session.media, isNull);
        expect(playback.playing, isFalse);
        await session.connect(device, null, _media);
        await server.revoke(session.store.id);
        await session.refresh();
        expect(session.connected, isFalse);
      },
    );

    Future<LanCastSession> connectedSession() async {
      final session = LanCastSession(trustStore: await _store());
      addTearDown(session.dispose);
      server.beginPairing();
      await session.connect(await client.info(), server.pairingCode, _media);
      return session;
    }

    test('completion keeps the receiver connected and the next selected video starts immediately', () async {
      final session = await connectedSession();
      final device = session.device;
      playback
        ..playing = false
        ..completed = true;
      for (var i = 0; i < 3; i++) {
        await session.refresh();
        expect(session.connected, isTrue);
        expect(session.status.playing, isFalse);
        expect(session.status.position, session.status.duration);
        expect(session.error, isNull);
      }
      const next = LanCastMedia(title: '播完后点选的新视频', aid: 100, cid: 200);
      expect(await session.replaceMedia(next), isTrue);
      expect(session.device, same(device));
      expect(session.connected, isTrue);
      expect(session.status.mediaKey, next.key);
      expect(session.status.playing, isTrue);
      expect(session.status.position, 0);
      expect(playback.loads.map((e) => e.key), [_media.key, next.key]);
      expect(playback.stopped, 0);
      expect(server.pairingCode, isNull);
    });

    test('receiver playlist transitions update identity without reloading or reconnecting', () async {
      final session = await connectedSession();
      final device = session.device;
      const next = LanCastMedia(
        title: '接收端下一集',
        kind: 'pgc',
        aid: 10,
        cid: 20,
        epId: 30,
        seasonId: 40,
      );
      playback
        ..reportCurrentMedia = true
        ..media = next
        ..buffering = true;
      // Controls sent before the next status poll cannot seek the new episode.
      await session.command('seek', 90000);
      expect(playback.commands, isEmpty);
      expect(session.connected, isTrue);
      await session.refresh();
      expect(session.mediaKey, next.key);
      expect(session.media?.toJson(), next.toJson());
      expect(session.device, same(device));
      expect(session.status.buffering, isTrue);
      expect(session.error, isNull);
      expect(playback.loads.length, 1);
      playback.buffering = false;
      await session.command('pause');
      expect(playback.commands, [('pause', null)]);
      expect(await session.replaceMedia(next), isTrue);
      expect(playback.loads.length, 1);
      playback.media = _media; // Loop back to the first item.
      await session.refresh();
      expect(session.mediaKey, _media.key);
      expect(session.connected, isTrue);
    });

    test('unrelated receiver navigation still ends the session', () async {
      final session = await connectedSession();
      playback.media =
          _live; // No receiving identity is reported for this page.
      await session.refresh();
      expect(session.connected, isFalse);
      expect(session.error, isNotNull);
    });

    test(
      'switches video, episode and live using the same pairing and connection',
      () async {
        final session = await connectedSession();
        final trust = jsonEncode(session.store.targets);
        const episode = LanCastMedia(
          title: '下一集',
          kind: 'pgc',
          aid: 10,
          cid: 20,
          epId: 30,
          position: 8000,
          speed: 2,
        );
        expect(await session.replaceMedia(episode), isTrue);
        expect(session.status.position, 8000);
        expect(session.status.speed, 2);
        await session.connect(session.device!, null, _live);
        expect(session.mediaKey, _live.key);
        expect(session.status.isLive, isTrue);
        expect(playback.loads.map((e) => e.key), [
          _media.key,
          episode.key,
          _live.key,
        ]);
        expect(playback.stopped, 0);
        expect(server.paired, isTrue);
        expect(jsonEncode(session.store.targets), trust);
        await session.replaceMedia(_live);
        expect(
          playback.loads.length,
          3,
        ); // Returning to controls must not reload.
      },
    );

    test(
      'rapid selections supersede queued media and stale gestures',
      () async {
        final session = await connectedSession();
        playback.loading = Completer<void>();
        final started = playback.loadStarted = Completer<void>();
        final first = session.replaceMedia(_live);
        await started.future;
        const middle = LanCastMedia(title: '中间视频', aid: 10, cid: 20);
        final second = session.replaceMedia(middle);
        final stalePause = session.command('pause');
        final last = session.replaceMedia(_media);
        await session.refresh();
        expect(session.connected, isTrue);
        expect(session.busy, isTrue);
        playback.loading!.complete();
        expect(await first, isFalse);
        expect(await second, isFalse);
        expect(await last, isTrue);
        await stalePause;
        expect(playback.loads.map((e) => e.key), [
          _media.key,
          _live.key,
          _media.key,
        ]);
        expect(playback.commands, isEmpty);
        expect(playback.playing, isTrue);
        expect(playback.stopped, 0);
        expect(session.mediaKey, _media.key);
        expect(session.busy, isFalse);
      },
    );

    test(
      'failed switching can retry without unpairing or disconnecting',
      () async {
        final session = await connectedSession();
        playback.failLoad = true;
        await expectLater(session.replaceMedia(_live), _status(500));
        playback.media = null; // Receiver may have already closed its old page.
        await session.refresh();
        expect(session.connected, isTrue);
        expect(session.busy, isFalse);
        expect(session.error, isNotNull);
        playback.failLoad = false;
        expect(await session.replaceMedia(_live), isTrue);
        expect(session.error, isNull);
        expect(session.status.isLive, isTrue);
        expect(playback.stopped, 0);
      },
    );

    test('disconnect during a switch cannot restore the old session', () async {
      final session = await connectedSession();
      playback.loading = Completer<void>();
      final started = playback.loadStarted = Completer<void>();
      final switching = session.replaceMedia(_live);
      await started.future;
      final disconnecting = session.disconnect();
      playback.loading!.complete();
      expect(await switching, isFalse);
      await disconnecting;
      expect(session.connected, isFalse);
      expect(session.media, isNull);
      expect(playback.playing, isFalse);
    });

    test('a superseded failed switch reloads the previous video when selected again', () async {
      final session = await connectedSession();
      playback
        ..loading = Completer<void>()
        ..failAfterLoad = true;
      final started = playback.loadStarted = Completer<void>();
      final failed = session.replaceMedia(_live);
      await started.future;
      final returning = session.replaceMedia(_media);
      playback.loading!.complete();
      expect(await failed, isFalse);
      expect(await returning, isTrue);
      expect(playback.loads.map((e) => e.key), [
        _media.key,
        _live.key,
        _media.key,
      ]);
      expect(session.status.mediaKey, _media.key);
      expect(session.online, isTrue);
      expect(session.connected, isTrue);
    });
  });

  test(
    'trust and receiving preference persist on disk outside settings export',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'piliplus-cast-trust-',
      );
      Hive.init(directory.path);
      try {
        await LanCastStore.initialize();
        final first = LanCastStore.instance;
        final id = first.id;
        first.data['enabled'] = true;
        await first.put('peers', 'phone', {'name': '手机', 'token': 'secret'});
        await Hive.close();
        await LanCastStore.initialize();
        expect(LanCastStore.instance.id, id);
        expect(LanCastStore.instance.enabled, isTrue);
        expect(LanCastStore.instance.peers['phone']?['token'], 'secret');
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
