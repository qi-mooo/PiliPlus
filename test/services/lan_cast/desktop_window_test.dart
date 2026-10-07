import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/receiver.dart';
import 'package:PiliPlus/utils/desktop_window.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  final _values = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const fullscreen = MethodChannel('com.alexmercerind/media_kit_video');
  final calls = <String>[];
  bool minimized = false;
  bool visible = false;
  bool topmost = false;
  double opacity = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() {
    GStorage.setting = _Settings();
    GStorage.video = _Settings();
    GStorage.localCache = _Settings();
  });
  setUp(() {
    calls.clear();
    minimized = false;
    visible = false;
    topmost = false;
    opacity = 0;
    messenger
      ..setMockMethodCallHandler(window, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'isMinimized':
            return minimized;
          case 'restore':
            minimized = false;
          case 'show':
            visible = true;
          case 'setOpacity':
            opacity = (call.arguments['opacity'] as num).toDouble();
          case 'isAlwaysOnTop':
            return topmost;
          case 'setAlwaysOnTop':
            topmost = call.arguments['isAlwaysOnTop'] as bool;
        }
        return null;
      })
      ..setMockMethodCallHandler(fullscreen, (call) async {
        calls.add(call.method);
        return null;
      });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(window, null)
      ..setMockMethodCallHandler(fullscreen, null);
  });

  test(
    'show restores a hidden transparent window and a minimized window',
    () async {
      await showDesktopWindow();
      expect(visible, isTrue);
      expect(opacity, 1);
      expect(calls.last, 'focus');
      expect(calls, isNot(contains('restore')));
      expect(topmost, isFalse);
      calls.clear();
      minimized = true;
      await showDesktopWindow();
      expect(minimized, isFalse);
      expect(calls.indexOf('restore'), lessThan(calls.indexOf('show')));
      expect(calls.indexOf('show'), lessThan(calls.indexOf('focus')));
    },
  );

  testWidgets(
    'receiving from tray shows the page; fullscreen raises it and disconnect restores it',
    (tester) async {
      const media = LanCastMedia(kind: 'live', roomId: 123, title: '接收直播');
      final player = PlPlayerController.getInstance(isLive: true)
        ..liveRoomId = media.roomId
        ..dataStatus.value = DataStatus.loaded
        ..dataSource = NetworkSource(
          videoSource: 'https://example.com/live',
          audioSource: null,
        );
      final playback = LanCastPagePlayback();
      await tester.pumpWidget(
        GetMaterialApp(
          initialRoute: '/liveRoom',
          getPages: [
            GetPage(
              name: '/liveRoom',
              page: () => const Scaffold(body: Text('直播页')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await playback.load(media);
      expect(visible, isTrue);
      expect(opacity, 1);
      expect(player.isReceivingCast, isTrue);
      expect(player.playerStatus.isPlaying, isTrue);
      expect(topmost, isFalse);
      await playback.command('fullscreen', 1);
      expect(player.isFullScreen.value, isTrue);
      expect(player.isAlwaysOnTop.value, isTrue);
      expect(topmost, isTrue);
      expect(
        calls.indexOf('Utils.EnterNativeFullscreen'),
        lessThan(calls.indexOf('setAlwaysOnTop')),
      );
      calls.clear();
      visible = false;
      opacity = 0;
      minimized = true;
      await playback.command('fullscreen', 1);
      expect(visible, isTrue);
      expect(minimized, isFalse);
      expect(opacity, 1);
      expect(calls, isNot(contains('Utils.EnterNativeFullscreen')));
      expect(calls.last, 'focus');
      // Reloading through the receiver preserves fullscreen without replacing
      // the original non-topmost state with the temporary topmost state.
      await playback.load(media);
      expect(player.isFullScreen.value, isTrue);
      expect(topmost, isTrue);
      // Local exit follows the same cleanup path as a remote exit.
      await player.triggerFullScreen(status: false);
      expect(topmost, isFalse);
      expect(player.isAlwaysOnTop.value, isFalse);
      await playback.command('fullscreen', 1);
      await playback.stop();
      expect(topmost, isFalse);
      expect(player.isReceivingCast, isFalse);
      expect(player.playerStatus.isPaused, isTrue);
      await player.triggerFullScreen(status: false);
      player.controls = false;
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
    },
  );

  test('fullscreen preserves prior topmost state and local playback does not raise the window', () async {
    final player = PlPlayerController.getInstance();
    topmost = true;
    player.receivingCastMediaKey = player.castMediaKey;
    await player.triggerFullScreen();
    await player.triggerFullScreen(status: false);
    expect(topmost, isTrue);
    expect(player.isAlwaysOnTop.value, isTrue);
    player.receivingCastMediaKey = null;
    calls.clear();
    await player.triggerFullScreen();
    await player.triggerFullScreen(status: false);
    expect(calls, [
      'Utils.EnterNativeFullscreen',
      'Utils.ExitNativeFullscreen',
    ]);
  });
}
