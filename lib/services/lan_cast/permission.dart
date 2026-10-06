import 'dart:io';

import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/permission_handler.dart';

Future<void>? _request;

Future<void> ensureLanCastPermission() {
  if (!Platform.isAndroid || DeviceUtils.sdkInt < 37) {
    return Future.value();
  }
  return _request ??= _ensurePermission().whenComplete(() => _request = null);
}

Future<void> _ensurePermission() async {
  if (!await Permission.accessLocalNetwork.isGranted &&
      !await Permission.accessLocalNetwork.request().isGranted) {
    throw const LanCastException('请在系统设置中允许 PiliPlus 访问本地网络');
  }
}
