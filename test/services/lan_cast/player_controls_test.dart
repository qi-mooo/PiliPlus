import 'package:PiliPlus/pages/lan_cast/fullscreen_button.dart';
import 'package:PiliPlus/pages/lan_cast/settings_sheet.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/playback_overlay.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/services/lan_cast/page_settings.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Session extends LanCastSession {
  final commands = <(String, double?)>[];
  final loads = <LanCastMedia>[];
  bool active = true;
  final changes = <(String, Object)>[];
  @override
  Future<void> setSetting(String key, Object value) async {
    changes.add((key, value));
    status = LanCastStatus.fromJson({
      ...status.toJson(),
      'settings': [
        for (final setting in status.settings)
          {...setting.toJson(), if (setting.key == key) 'value': value},
      ],
    });
    notifyListeners();
  }

  @override
  bool get connected => active;
  @override
  Future<bool> replaceMedia(LanCastMedia next) async {
    loads.add(next);
    media = next;
    mediaKey = next.key;
    status = LanCastStatus(
      mediaKey: next.key,
      title: next.title,
      playing: true,
      isLive: next.isLive,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<void> command(String action, [double? value]) async {
    commands.add((action, value));
    status = LanCastStatus(
      playing: action == 'play' || (action != 'pause' && status.playing),
      position: action == 'seek' ? value!.round() : status.position,
      duration: 120000,
      speed: action == 'speed' ? value! : status.speed,
      volume: action == 'volume' ? value! : status.volume,
      fullscreen: action == 'fullscreen' ? value == 1 : status.fullscreen,
      canFullscreen: true,
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    active = false;
    notifyListeners();
  }
}

class _Settings extends Fake implements Box<dynamic> {
  final _values = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    _values.addAll(entries);
  }
}

void main() {
  setUpAll(() {
    GStorage.setting = _Settings();
    GStorage.video = _Settings();
    GStorage.localCache = _Settings();
  });

  testWidgets(
    'remote settings preserve local values and hide only playback overlays',
    (tester) async {
      final player = PlPlayerController.getInstance();
      final localDanmaku = player.enableShowDanmaku.value;
      final localScale = DanmakuOptions.danmakuFontScale;
      final localFit = player.videoFit.value;
      player.isLive = false;
      final session = _Session()
        ..device = LanCastDevice(
          id: 'receiver',
          name: '电视',
          uri: Uri.parse('http://127.0.0.1:1234'),
        )
        ..online = true
        ..mediaKey = player.castMediaKey
        ..status = const LanCastStatus(
          settings: [
            LanCastSetting(
              key: 'danmaku',
              label: '显示弹幕',
              group: '弹幕设置',
              value: false,
            ),
            LanCastSetting(
              key: 'dmScale',
              label: '字体大小 (%)',
              group: '弹幕设置',
              value: 300.0,
              min: 50,
              max: 600,
              divisions: 550,
            ),
            LanCastSetting(
              key: 'fit',
              label: '画面比例',
              group: '播放设置',
              value: 'contain',
              options: {'contain': '适应', 'fill': '拉伸'},
            ),
          ],
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlaybackOverlay(player: player, child: const Text('本机弹幕')),
                Expanded(
                  child: LanCastSettingsSheet(player: player, group: '弹幕设置'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('本机弹幕'), findsOneWidget);
      await player.attachCast(session);
      await tester.pump();
      expect(find.text('本机弹幕'), findsNothing);
      expect(find.text('显示弹幕'), findsOneWidget);
      expect(find.text('字体大小 (%)  300'), findsOneWidget);
      expect(player.danmakuEnabled, isFalse);
      expect(player.enableShowDanmaku.value, localDanmaku);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(session.changes.last, ('danmaku', true));
      expect(player.danmakuEnabled, isTrue);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(600);
      slider.onChangeEnd!(600);
      await tester.pump();
      expect(session.changes.last, ('dmScale', 600.0));
      expect(DanmakuOptions.danmakuFontScale, localScale);
      player.toggleVideoFit(VideoFitType.fill);
      await tester.pump();
      expect(session.changes.last, ('fit', 'fill'));
      expect(player.videoFit.value, localFit);
      final changes = session.changes.length;
      await player.setCastSetting('danmaku', false, mediaKey: 'old-video');
      expect(session.changes.length, changes);
      await player.disconnectCast();
      await tester.pump();
      expect(find.text('本机弹幕'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(player.enableShowDanmaku.value, localDanmaku);
      expect(player.videoFit.value, localFit);
      player.controls = false;
      player.volumeTimer?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  test('receiver applies danmaku and subtitle settings through normal player state', () async {
    final player = PlPlayerController.getInstance()..isLive = false;
    final receiver = LanCastPageSettings(player);
    final repeat = player.playRepeat;
    player.receivingCastMediaKey = player.castMediaKey;
    expect(player.playRepeat, PlayRepeat.pause);
    await receiver.apply('repeat', 'singleCycle');
    expect(player.playRepeat, PlayRepeat.singleCycle);
    player
      ..receivingCastMediaKey = null
      ..receivingCastRepeat = null;
    expect(player.playRepeat, repeat);
    final dmScale = DanmakuOptions.danmakuFontScale;
    final subtitleScale = player.subtitleFontScaleFS;
    final flipX = player.flipX.value;
    await receiver.apply('dmScale', 600);
    await receiver.apply('subScaleFS', 600);
    await receiver.apply('flipX', !flipX);
    expect(DanmakuOptions.danmakuFontScale, 6);
    expect(player.subtitleFontScaleFS, 6);
    expect(player.flipX.value, !flipX);
    await expectLater(
      receiver.apply('subScaleFS', 601),
      throwsA(isA<LanCastException>()),
    );
    await expectLater(
      receiver.apply('subWeight', 3.5),
      throwsA(isA<LanCastException>()),
    );
    await expectLater(
      receiver.apply('file', '/private'),
      throwsA(isA<LanCastException>()),
    );
    expect(player.subtitleFontScaleFS, 6);
    await receiver.apply('dmScale', dmScale * 100);
    await receiver.apply('subScaleFS', subtitleScale * 100);
    await receiver.apply('flipX', flipX);
  });

  testWidgets(
    'existing player button and gestures control receiver and reflect its state',
    (tester) async {
      final player = PlPlayerController.getInstance();
      final session = _Session()
        ..device = LanCastDevice(
          id: 'receiver',
          name: '客厅电脑',
          uri: Uri.parse('http://127.0.0.1:1234'),
        )
        ..online = true
        ..status = const LanCastStatus(
          playing: true,
          position: 42000,
          duration: 120000,
          speed: 1.5,
          canFullscreen: true,
        );
      await player.attachCast(session);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlayOrPauseButton(plPlayerController: player),
                LanCastFullscreenButton(player: player, session: session),
              ],
            ),
          ),
        ),
      );
      expect(player.positionInMilliseconds, 42000);
      expect(player.duration.value, 120);
      expect(
        player.videoPlayerController,
        isNull,
      ); // No local/native player involved.
      expect(find.bySemanticsLabel('暂停'), findsOneWidget);
      await tester.tap(find.byType(PlayOrPauseButton));
      await tester.pump();
      expect(session.commands.last, ('pause', null));
      expect(player.playerStatus.isPaused, isTrue);
      expect(find.bySemanticsLabel('播放'), findsOneWidget);
      await player.seekTo(const Duration(seconds: 70));
      await player.setPlaybackSpeed(2);
      await player.setVolume(0.4);
      expect(player.positionInMilliseconds, 70000);
      expect(player.playbackSpeed, 2);
      expect(player.volume.value, 0.4);
      await player.play();
      final beforeLifecycle = session.commands.length;
      await player.pause(localOnly: true);
      await player.pause(isInterrupt: true);
      expect(session.commands.length, beforeLifecycle);
      expect(player.playerStatus.isPlaying, isTrue);
      player.onForward(const Duration(seconds: 10));
      await tester.pump();
      expect(session.commands, contains(('seek', 80000.0)));
      expect(player.positionInMilliseconds, 80000);
      await tester.tap(find.byTooltip('接收端全屏'));
      await tester.pump();
      expect(session.commands.last, ('fullscreen', 1.0));
      expect(player.isFullScreen.value, isFalse);
      await tester.tap(find.byTooltip('退出接收端全屏'));
      await tester.pump();
      expect(session.commands.last, ('fullscreen', 0.0));
      final beforeLeaving = session.commands.length;
      player
        ..onPopInvokedWithResult(true, null)
        ..detachCast();
      await tester.pump();
      expect(session.connected, isTrue);
      expect(session.status.playing, isTrue);
      expect(session.commands.length, beforeLeaving);
      await player.attachCast(session);
      expect(player.positionInMilliseconds, 80000);
      expect(session.commands.length, beforeLeaving);
      player
        ..detachCast()
        ..isLive = true
        ..liveRoomId = 1234
        ..mediaTitle = '新直播'
        ..dataSource = NetworkSource(
          videoSource: 'https://example.com/live',
          audioSource: null,
        );
      await player.castToConnectedDevice(session: session);
      expect(session.loads.single.key, 'live:1234');
      expect(player.isCasting, isTrue);
      expect(session.connected, isTrue);
      expect(session.commands.length, beforeLeaving);
      expect(player.videoPlayerController, isNull);
      await player.disconnectCast();
      expect(player.isCasting, isFalse);
      expect(player.playerStatus.isPaused, isTrue);
      player.controls = false;
      player.volumeTimer?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
