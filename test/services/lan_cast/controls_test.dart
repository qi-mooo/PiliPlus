import 'package:PiliPlus/pages/lan_cast/controls.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'remote reflects receiver state and sends bounded seek commands',
    (tester) async {
      final commands = <(String, double?)>[];
      Future<void> command(String action, [double? value]) async {
        commands.add((action, value));
      }

      Widget page(LanCastStatus status) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: LanCastControls(status: status, onCommand: command),
          ),
        ),
      );
      await tester.pumpWidget(
        page(
          const LanCastStatus(
            title: '视频',
            position: 5000,
            duration: 12000,
            playing: true,
          ),
        ),
      );
      await tester.tap(find.byTooltip('暂停'));
      await tester.tap(find.byTooltip('后退 10 秒'));
      await tester.tap(find.byTooltip('快进 10 秒'));
      expect(commands, [('pause', null), ('seek', 0.0), ('seek', 12000.0)]);
      await tester.pumpWidget(
        page(
          const LanCastStatus(
            title: '视频',
            duration: 12000,
            playing: false,
            volume: 0,
            speed: 2,
          ),
        ),
      );
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(find.text('倍速 2.0x ▾'), findsOneWidget);
      await tester.tap(find.byTooltip('取消静音'));
      expect(commands.last, ('volume', 50.0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('live and disconnected remotes disable unavailable controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LanCastControls(
            status: const LanCastStatus(title: '直播', isLive: true),
            enabled: false,
            onCommand: (_, [value]) async {},
          ),
        ),
      ),
    );
    expect(find.text('直播中'), findsOneWidget);
    expect(find.byType(PopupMenuButton<double>), findsNothing);
    for (final tooltip in ['播放', '后退 10 秒', '快进 10 秒', '静音']) {
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == tooltip,
              ),
            )
            .onPressed,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
