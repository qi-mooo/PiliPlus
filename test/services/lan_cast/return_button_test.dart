import 'dart:async';

import 'package:PiliPlus/pages/lan_cast/return_button.dart';
import 'package:PiliPlus/services/lan_cast/navigation.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _media = LanCastMedia(title: '测试视频', aid: 1, cid: 2);

class _Session extends LanCastSession {
  bool active = true;
  @override
  bool get connected => active;
  @override
  Future<void> disconnect() async {
    active = false;
    notifyListeners();
  }
}

MaterialPageRoute<void> _page(String title) => MaterialPageRoute(
  settings: RouteSettings(name: title),
  builder: (_) => Scaffold(body: Center(child: Text(title))),
);

void main() {
  testWidgets(
    'floating entry returns to existing route or reopens at latest progress, and disappears on disconnect',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      final session = _Session()
        ..media = _media
        ..mediaKey = _media.key
        ..online = true
        ..status = const LanCastStatus(playing: true, position: 75000);
      var opened = 0;
      final navigation = LanCastNavigation(
        openVideo: (media, position, stillValid) async {
          expect(stillValid(), isTrue);
          expect(media.key, _media.key);
          expect(position, 75000);
          opened++;
          unawaited(key.currentState!.push(_page('恢复的视频页')));
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [navigation],
          home: const Scaffold(body: Text('首页')),
          builder: (_, child) => LanCastReturnOverlay(
            session: session,
            navigation: navigation,
            child: child!,
          ),
        ),
      );
      unawaited(key.currentState!.push(_page('原视频页')));
      await tester.pumpAndSettle();
      navigation.rememberControlRoute(_media.key);
      final controlRoute = navigation.currentPageRoute;
      await tester.pumpAndSettle();
      expect(find.text('返回投屏控制'), findsNothing);
      unawaited(key.currentState!.push(_page('其他页面')));
      await tester.pumpAndSettle();
      // A delayed cast response must remember its originating video page.
      navigation.rememberControlRoute(_media.key, route: controlRoute);
      await tester.pumpAndSettle();
      expect(find.text('返回投屏控制'), findsOneWidget);
      final beforeDrag = tester.getTopLeft(find.text('返回投屏控制'));
      await tester.drag(find.text('返回投屏控制'), const Offset(-150, -80));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('返回投屏控制')).dx,
        lessThan(beforeDrag.dx),
      );
      await tester.tap(find.text('返回投屏控制'));
      await tester.pumpAndSettle();
      expect(find.text('原视频页'), findsOneWidget);
      expect(opened, 0);
      expect(session.status.playing, isTrue);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('返回投屏控制'), findsOneWidget);
      await tester.tap(find.text('返回投屏控制'));
      await tester.pumpAndSettle();
      expect(find.text('恢复的视频页'), findsOneWidget);
      expect(find.text('返回投屏控制'), findsNothing);
      expect(opened, 1);
      // A selection sheet can still cover the page when its video changes.
      unawaited(
        showModalBottomSheet<void>(
          context: key.currentContext!,
          builder: (_) => const SizedBox(height: 100, child: Text('选集')),
        ),
      );
      await tester.pumpAndSettle();
      navigation.invalidateCurrentControlRoute();
      expect(navigation.hasPopup, isTrue);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('返回投屏控制'), findsOneWidget);
      await tester.tap(find.text('返回投屏控制'));
      await tester.pumpAndSettle();
      expect(find.text('恢复的视频页'), findsOneWidget);
      expect(opened, 2);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      await session.disconnect();
      await tester.pumpAndSettle();
      expect(find.text('返回投屏控制'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
      session.dispose();
    },
  );

  testWidgets(
    'return does not open stale media after disconnect during loading',
    (tester) async {
      final pending = Completer<void>();
      final session = _Session()
        ..media = _media
        ..mediaKey = _media.key;
      var opened = false;
      final navigation = LanCastNavigation(
        openVideo: (media, position, stillValid) async {
          await pending.future;
          opened = stillValid();
        },
      );
      final first = navigation.returnToControls(session);
      await navigation.returnToControls(
        session,
      ); // Double tap cannot start another load.
      await session.disconnect();
      pending.complete();
      await tester.pump();
      await first;
      expect(opened, isFalse);
      expect(navigation.opening, isFalse);
      navigation.dispose();
      session.dispose();
      await tester.pump();
    },
  );
}
