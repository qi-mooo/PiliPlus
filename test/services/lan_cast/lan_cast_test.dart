import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/server.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Playback implements LanCastPlayback {
  LanCastMedia? media;
  final commands = <(String, double?)>[];
  bool playing = false;
  int stopped = 0;
  Completer<void>? loading;
  bool failLoad = false;
  @override
  LanCastStatus get status => LanCastStatus(
    title: media?.title ?? '',
    mediaKey: media?.key ?? '',
    position: media?.position ?? 0,
    duration: 120000,
    playing: playing,
    isLive: media?.isLive ?? false,
    speed: media?.speed ?? 1,
  );
  @override
  Future<void> load(LanCastMedia value) async {
    if (failLoad) throw StateError('Playback failed');
    await loading?.future;
    media = value;
    playing = true;
  }

  @override
  Future<void> command(String action, double? value) async {
    commands.add((action, value));
    if (action == 'play') playing = true;
    if (action == 'pause') playing = false;
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
        expect(playback.playing, isFalse);
        await session.connect(device, null, _media);
        await server.revoke(session.store.id);
        await session.refresh();
        expect(session.connected, isFalse);
      },
    );
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
