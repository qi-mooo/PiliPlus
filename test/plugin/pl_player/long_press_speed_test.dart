import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/long_press_speed_gesture_recognizer.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/long_press_speed_indicator.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _DelayedSession extends LanCastSession {
  final commands = <(String, double?)>[];
  final replies = <Completer<void>>[];
  Future<void> _queue = Future.value();

  @override
  bool get connected => true;

  @override
  Future<void> command(String action, [double? value]) {
    commands.add((action, value));
    final reply = Completer<void>();
    replies.add(reply);
    return _queue = _queue.then((_) async {
      await reply.future;
      status = LanCastStatus(playing: true, speed: value!);
      notifyListeners();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlPlayerController player;

  setUpAll(() {
    GStorage.setting = _Settings();
    GStorage.video = _Settings();
    GStorage.localCache = _Settings();
  });

  setUp(() async {
    player = PlPlayerController.getInstance()
      ..enableAutoLongPressSpeed = false
      ..playerStatus = .playing
      ..controlsLock.value = false
      ..isSeeking.value = false;
    await player.setPlaybackSpeed(1.25);
  });

  tearDown(() {
    player
      ..detachCast()
      ..controls = false
      ..cancelLongPressTimer();
    player.volumeTimer?.cancel();
  });

  Future<LongPressSpeedGestureRecognizer> mountPlayer(
    WidgetTester tester, {
    VoidCallback? onPan,
    bool disposeOnTearDown = true,
  }) async {
    final longPress = LongPressSpeedGestureRecognizer(player);
    final pan = ScaleGestureRecognizer()..onUpdate = (_) => onPan?.call();
    addTearDown(() {
      if (disposeOnTearDown) longPress.dispose();
      pan.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      longPress.addPointer(event);
                      pan.addPointer(event);
                    },
                  ),
                ),
                LongPressSpeedIndicator(player: player, isFullScreen: false),
              ],
            ),
          ),
        ),
      ),
    );
    return longPress;
  }

  Future<TestGesture> hold(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(200, 180));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    return gesture;
  }

  testWidgets(
    'downward long press locks, then the indicator restores prior speed',
    (tester) async {
      var pans = 0;
      await mountPlayer(tester, onPan: () => pans++);
      final gesture = await hold(tester);
      expect(player.playbackSpeed, 3);
      expect(find.text('下滑锁定倍速'), findsOneWidget);
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      expect(player.longPressLockProgress.value, 0.5);
      expect(player.longPressSpeedLocked.value, isFalse);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.text('3倍速已锁定'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pans, 0);
      expect(player.longPressStatus.value, isFalse);
      expect(player.longPressSpeedLocked.value, isTrue);
      expect(player.playbackSpeed, 3);
      await tester.tap(find.text('3倍速已锁定 · 点击恢复'));
      await tester.pumpAndSettle();
      expect(player.playbackSpeed, 1.25);
      expect(player.longPressSpeedLocked.value, isFalse);
      expect(player.longPressLockProgress.value, 0);
    },
  );

  for (final offset in [
    Offset.zero,
    const Offset(0, 20),
    const Offset(0, -60),
    const Offset(65, 50),
  ]) {
    testWidgets(
      'release restores speed without a deliberate downward swipe: $offset',
      (tester) async {
        await mountPlayer(tester);
        final gesture = await hold(tester);
        await gesture.moveBy(offset);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(player.playbackSpeed, 1.25);
        expect(player.longPressSpeedLocked.value, isFalse);
        expect(player.longPressStatus.value, isFalse);
      },
    );
  }

  testWidgets('swiping before the long press keeps the existing pan gesture', (
    tester,
  ) async {
    var pans = 0;
    await mountPlayer(tester, onPan: () => pans++);
    await tester.dragFrom(const Offset(200, 180), const Offset(0, 70));
    await tester.pumpAndSettle();
    expect(pans, greaterThan(0));
    expect(player.playbackSpeed, 1.25);
    expect(player.longPressSpeedLocked.value, isFalse);
  });

  testWidgets(
    'canceling or disposing an accepted hold restores temporary speed',
    (tester) async {
      final recognizer = await mountPlayer(tester, disposeOnTearDown: false);
      final gesture = await hold(tester);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(player.playbackSpeed, 1.25);
      final second = await hold(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      // Dispose while the pointer is still down, as when replacing a player view.
      recognizer.dispose();
      await tester.pump();
      expect(player.playbackSpeed, 1.25);
      expect(player.longPressStatus.value, isFalse);
      await second.up();
    },
  );

  testWidgets(
    'locked automatic speed does not compound and manual speed wins',
    (tester) async {
      player.enableAutoLongPressSpeed = true;
      await mountPlayer(tester);
      final gesture = await hold(tester);
      await gesture.moveBy(const Offset(0, 60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(player.playbackSpeed, 2.5);
      final second = await hold(tester);
      expect(player.playbackSpeed, 2.5);
      await player.setPlaybackSpeed(1.75);
      await second.moveBy(const Offset(0, 60));
      await second.up();
      await tester.pumpAndSettle();
      expect(player.playbackSpeed, 1.75);
      expect(player.longPressSpeedLocked.value, isFalse);
    },
  );

  test('live, paused, and locked controls cannot start a speed lock', () async {
    player.isLive = true;
    await player.setLongPressStatus(true);
    player.updateLongPressOffset(const Offset(0, 80));
    expect(player.longPressStatus.value, isFalse);
    expect(player.longPressSpeedLocked.value, isFalse);
    player
      ..isLive = false
      ..playerStatus = .paused;
    await player.setLongPressStatus(true);
    player.updateLongPressOffset(const Offset(0, 80));
    expect(player.longPressSpeedLocked.value, isFalse);
    player
      ..playerStatus = .playing
      ..controlsLock.value = true;
    await player.setLongPressStatus(true);
    player.updateLongPressOffset(const Offset(0, 80));
    expect(player.playbackSpeed, 1.25);
    expect(player.longPressStatus.value, isFalse);
  });

  testWidgets(
    'cast lock and unlock preserve command order before speed feedback arrives',
    (tester) async {
      final session = _DelayedSession()
        ..device = LanCastDevice(
          id: 'receiver',
          name: '接收端',
          uri: Uri.parse('http://127.0.0.1:1234'),
        )
        ..online = true
        ..status = const LanCastStatus(playing: true, speed: 1.25);
      await player.attachCast(session);
      player.controls = false;
      final start = player.setLongPressStatus(true);
      player.updateLongPressOffset(const Offset(0, 60));
      await player.setLongPressStatus(false);
      expect(player.playbackSpeed, 1.25); // No receiver reply yet.
      expect(player.activeLongPressSpeed, 3);
      expect(session.commands, [('speed', 3.0)]);
      final unlock = player.unlockLongPressSpeed();
      expect(session.commands, [('speed', 3.0), ('speed', 1.25)]);
      for (final reply in session.replies) {
        reply.complete();
      }
      await Future.wait([start, unlock]);
      expect(player.playbackSpeed, 1.25);
      expect(player.longPressSpeedLocked.value, isFalse);
      player.detachCast();
      session.dispose();
    },
  );

  testWidgets(
    'cast speed limit and disconnect clear the lock without changing receiver speed',
    (tester) async {
      final session = _DelayedSession()
        ..device = LanCastDevice(
          id: 'receiver',
          name: '接收端',
          uri: Uri.parse('http://127.0.0.1:1234'),
        )
        ..online = true
        ..status = const LanCastStatus(playing: true, speed: 3);
      await player.attachCast(session);
      player
        ..controls = false
        ..enableAutoLongPressSpeed = true;
      final start = player.setLongPressStatus(true);
      player.updateLongPressOffset(const Offset(0, 60));
      await player.setLongPressStatus(false);
      expect(player.activeLongPressSpeed, 4);
      session.replies.single.complete();
      await start;
      player.detachCast();
      await player.setLongPressStatus(false);
      expect(player.longPressSpeedLocked.value, isFalse);
      expect(session.commands, [('speed', 4.0)]);
      session.dispose();
    },
  );
}
