import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:window_manager/window_manager.dart';

/// Restore hidden/minimized desktop receivers before opening their video page.
Future<void> showDesktopWindow() async {
  if (!PlatformUtils.isDesktop) return;
  // Windows tray hiding sets opacity to zero, including when focus is refused.
  await windowManager.setOpacity(1);
  // window_manager.show also restores minimized windows.
  await windowManager.show();
  await windowManager.focus();
}
