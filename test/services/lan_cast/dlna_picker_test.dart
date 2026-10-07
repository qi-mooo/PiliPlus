import 'package:PiliPlus/pages/dlna/view.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Discovery extends Fake implements DLNAManager {
  final devices = DeviceManager();
  @override
  Future<DeviceManager> start({dynamic reusePort = false}) async => devices;
  @override
  void stop() => devices.dispose();
}

class _Device extends Fake implements DLNADevice {
  final calls = <String>[];
  bool fail = false;
  @override
  DeviceInfo get info =>
      DeviceInfo('http://192.168.1.2', 'MediaRenderer', '客厅电视', []);
  @override
  Future<String> setUrl(
    String url, {
    String title = '',
    PlayType type = VideoMime.any,
  }) async {
    calls.add('url:$url:$title');
    if (fail) throw StateError('电视拒绝播放');
    return '';
  }

  @override
  Future<String> play() async {
    calls.add('play');
    return '';
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'DLNA only fetches URL on selection and reports ${fail ? 'failure' : 'success'} before pausing local playback',
      (tester) async {
        final discovery = _Discovery();
        final device = _Device()..fail = fail;
        var resolved = 0;
        var connected = 0;
        final busy = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DLNADeviceList(
                manager: discovery,
                title: '视频标题',
                mediaUrl: () async {
                  resolved++;
                  return 'https://example.com/tv.mp4';
                },
                onConnected: () async {
                  connected++;
                },
                onBusyChanged: busy.add,
              ),
            ),
          ),
        );
        await tester.pump();
        discovery.devices.devices.add({'tv': device});
        await tester.pump();
        expect(resolved, 0);
        expect(find.text('客厅电视'), findsOneWidget);
        await tester.tap(find.text('客厅电视'));
        await tester.pump();
        expect(resolved, 1);
        expect(device.calls.first, 'url:https://example.com/tv.mp4:视频标题');
        expect(device.calls.contains('play'), !fail);
        expect(connected, fail ? 0 : 1);
        expect(busy, [true, false]);
        if (fail) expect(find.textContaining('DLNA 投屏失败'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
