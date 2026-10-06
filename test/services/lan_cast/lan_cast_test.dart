import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/server.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:flutter_test/flutter_test.dart';

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
  videoUrl: 'https://example.com/video?sign=a;b,c',
  audioUrl: 'https://example.com/audio',
  position: 42000,
  speed: 1.5,
);

void main() {
  group('media protocol', () {
    test('preserves split audio, signed URLs and playback position', () {
      final parsed = LanCastMedia.fromJson(_media.toJson());
      expect(parsed.toJson(), _media.toJson());
      expect(
        parsed.playableUrl,
        'edl://!no_chapters;%${utf8.encode(_media.videoUrl).length}%${_media.videoUrl};!new_stream;!no_chapters;%${utf8.encode(_media.audioUrl!).length}%${_media.audioUrl}',
      );
      expect(
        const LanCastMedia(
          title: '直播',
          videoUrl: 'https://example.com/live',
          isLive: true,
        ).playableUrl,
        'https://example.com/live',
      );
    });

    test('rejects file access, mpv protocols and invalid numbers', () {
      for (final url in [
        'file:///etc/passwd',
        'edl://payload',
        'https://user:password@example.com/v',
        'https://example.com/a\nheader',
      ]) {
        expect(
          () => LanCastMedia.fromJson({..._media.toJson(), 'videoUrl': url}),
          throwsA(isA<LanCastException>()),
        );
      }
      for (final speed in [-1, 0, 5, double.nan, double.infinity, '1']) {
        expect(
          () => LanCastMedia.fromJson({..._media.toJson(), 'speed': speed}),
          throwsA(isA<LanCastException>()),
        );
      }
      expect(
        () => LanCastMedia.fromJson({..._media.toJson(), 'position': -1}),
        throwsA(isA<LanCastException>()),
      );
    });

    test('only accepts explicit local IP endpoints', () {
      expect(lanCastAddress('192.168.1.10:51000').host, '192.168.1.10');
      expect(lanCastAddress('http://10.0.0.2:1234/').path, '');
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
  });

  group('real LAN HTTP session', () {
    late _Playback playback;
    late LanCastServer server;
    late Uri uri;
    late LanCastClient client;

    setUp(() async {
      playback = _Playback();
      server = LanCastServer(name: '客厅电脑', playback: playback);
      await server.start(address: InternetAddress.loopbackIPv4);
      uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      client = LanCastClient(uri);
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test(
      'pairs, pushes DASH media, reports state and controls playback',
      () async {
        final info = await client.info();
        expect(info.name, '客厅电脑');
        expect(info.id, server.id);
        await expectLater(
          client.status(),
          throwsA(
            isA<LanCastException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        await client.pair(server.pairingCode, '手机');
        final state = await client.load(_media);
        expect(state.title, '测试视频');
        expect(state.position, 42000);
        expect(state.speed, 1.5);
        expect(state.playing, isTrue);
        expect(playback.media?.audioUrl, _media.audioUrl);
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
        await client.disconnect();
        expect(server.paired, isFalse);
        expect(playback.stopped, 1);
        await expectLater(client.status(), throwsA(isA<LanCastException>()));
      },
    );

    test('wrong codes, second senders and invalid commands cannot control playback', () async {
      final other = LanCastClient(uri);
      addTearDown(other.close);
      final badCode = server.pairingCode == '000000' ? '111111' : '000000';
      await expectLater(
        client.pair(badCode, '陌生设备'),
        throwsA(
          isA<LanCastException>().having((e) => e.statusCode, 'status', 403),
        ),
      );
      await client.pair(server.pairingCode, '手机');
      await expectLater(
        other.pair(server.pairingCode, '平板'),
        throwsA(
          isA<LanCastException>().having((e) => e.statusCode, 'status', 409),
        ),
      );
      await expectLater(
        other.command('pause'),
        throwsA(isA<LanCastException>()),
      );
      await expectLater(
        client.command('volume', 101),
        throwsA(isA<LanCastException>()),
      );
      await expectLater(
        client.command('shell'),
        throwsA(isA<LanCastException>()),
      );
      expect(playback.commands, isEmpty);
    });

    test('limits pairing attempts', () async {
      final badCode = server.pairingCode == '000000' ? '111111' : '000000';
      for (var i = 0; i < 6; i++) {
        await expectLater(
          client.pair(badCode, '手机'),
          throwsA(isA<LanCastException>()),
        );
      }
      await expectLater(
        client.pair(server.pairingCode, '手机'),
        throwsA(
          isA<LanCastException>().having((e) => e.statusCode, 'status', 429),
        ),
      );
    });

    test('rejects live seeking and speed adjustments', () async {
      await client.pair(server.pairingCode, '手机');
      await client.load(
        const LanCastMedia(
          title: '直播',
          videoUrl: 'https://example.com/live',
          isLive: true,
        ),
      );
      await expectLater(
        client.command('seek', 100),
        throwsA(isA<LanCastException>()),
      );
      await expectLater(
        client.command('speed', 2),
        throwsA(isA<LanCastException>()),
      );
      await client.command('volume', 20);
      expect(playback.commands, [('volume', 20.0)]);
    });

    test('receiver revocation invalidates the old token', () async {
      await client.pair(server.pairingCode, '手机');
      await client.load(_media);
      await server.disconnect();
      await expectLater(
        client.command('play'),
        throwsA(
          isA<LanCastException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      await client.pair(server.pairingCode, '手机');
      expect((await client.load(_media)).playing, isTrue);
    });

    test(
      'serializes load and disconnect to prevent playback after disconnect',
      () async {
        await client.pair(server.pairingCode, '手机');
        playback.loading = Completer<void>();
        final loading = client.load(_media);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final disconnecting = client.disconnect();
        playback.loading!.complete();
        await loading;
        await disconnecting;
        expect(playback.media, isNull);
        expect(playback.playing, isFalse);
      },
    );

    test('rejects browser requests and oversized JSON without exposing credentials', () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final request = await http.getUrl(uri.replace(path: '/info'));
      request.headers.set('Origin', 'https://example.com');
      expect((await request.close()).statusCode, 403);
      final oversized = await http.postUrl(uri.replace(path: '/pair'));
      oversized.headers.contentType = ContentType.json;
      oversized.write(jsonEncode({'code': '1' * (lanCastBodyLimit + 1)}));
      final response = await oversized.close();
      expect(response.statusCode, 413);
      expect(
        await utf8.decodeStream(response),
        isNot(contains(server.pairingCode)),
      );
    });

    test(
      'remote session survives navigation and releases a failed push',
      () async {
        final session = LanCastSession();
        addTearDown(() {
          session
            ..forget()
            ..dispose();
        });
        final device = await client.info();
        playback.failLoad = true;
        await expectLater(
          session.connect(device, server.pairingCode, _media),
          throwsA(isA<LanCastException>()),
        );
        expect(session.connected, isFalse);
        expect(server.paired, isFalse);
        playback.failLoad = false;
        await session.connect(device, server.pairingCode, _media);
        expect(session.connected, isTrue);
        expect(session.status.title, _media.title);
        await session.command('pause');
        expect(session.status.playing, isFalse);
        await session.disconnect();
        expect(session.connected, isFalse);
        expect(playback.playing, isFalse);
      },
    );
  });
}
