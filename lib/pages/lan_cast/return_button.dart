import 'package:PiliPlus/services/lan_cast/navigation.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// In-app entry point only; playback controls remain on the normal video page.
class LanCastReturnOverlay extends StatefulWidget {
  const LanCastReturnOverlay({
    super.key,
    required this.child,
    this.session,
    this.navigation,
  });
  final Widget child;
  final LanCastSession? session;
  final LanCastNavigation? navigation;
  @override
  State<LanCastReturnOverlay> createState() => _LanCastReturnOverlayState();
}

class _LanCastReturnOverlayState extends State<LanCastReturnOverlay> {
  late final _session = widget.session ?? LanCastSession.instance;
  late final _navigation = widget.navigation ?? LanCastNavigation.instance;
  Offset? _position;

  Future<void> _return() async {
    try {
      await _navigation.returnToControls(_session);
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_session, _navigation]),
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_session.connected &&
            !_navigation.isOnControlPage(_session) &&
            !_navigation.hasPopup)
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const width = 176.0, height = 48.0;
                  final maxX = (constraints.maxWidth - width - 8).clamp(
                    8.0,
                    double.infinity,
                  );
                  final maxY =
                      (constraints.maxHeight -
                              height -
                              8 -
                              MediaQuery.viewInsetsOf(context).bottom)
                          .clamp(8.0, double.infinity);
                  final position =
                      _position ?? Offset(maxX, (maxY - 72).clamp(8.0, maxY));
                  final x = position.dx.clamp(8.0, maxX),
                      y = position.dy.clamp(8.0, maxY);
                  return Stack(
                    children: [
                      Positioned(
                        left: x,
                        top: y,
                        width: width,
                        height: height,
                        child: GestureDetector(
                          onPanUpdate: (details) => setState(
                            () => _position = Offset(
                              (x + details.delta.dx).clamp(8.0, maxX),
                              (y + details.delta.dy).clamp(8.0, maxY),
                            ),
                          ),
                          child: Material(
                            color: ColorScheme.of(context).primaryContainer,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(24),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _navigation.opening ? null : _return,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _session.online
                                          ? Icons.cast_connected
                                          : Icons.wifi_off,
                                      color: ColorScheme.of(context)
                                          .onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _navigation.opening
                                            ? '正在返回…'
                                            : '返回投屏控制',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: ColorScheme.of(context)
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    ),
  );
}
