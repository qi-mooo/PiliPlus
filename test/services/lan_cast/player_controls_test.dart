import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Session extends LanCastSession {
  final commands = <(String, double?)>[];
  bool active = true;
  @override
  bool get connected => active;
  @override
  Future<void> command(String action, [double? value]) async {
    commands.add((action, value));
    status = LanCastStatus(
      playing: action == 'play' || (action != 'pause' && status.playing),
      position: action == 'seek' ? value!.round() : status.position,
      duration: 120000,
      speed: action == 'speed' ? value! : status.speed,
      volume: action == 'volume' ? value! : status.volume,
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
}

void main() {
  setUpAll(() {
    GStorage.setting = _Settings();
    GStorage.video = _Settings();
    GStorage.localCache = _Settings();
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
        );
      await player.attachCast(session);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlayOrPauseButton(plPlayerController: player)),
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
