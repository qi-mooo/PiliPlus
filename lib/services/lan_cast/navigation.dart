import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart' hide navigator;
import 'package:material_ui/material_ui.dart';

/// Shared normal-page navigation for receiving and returning to sender controls.
Future<void> openLanCastVideo(
  LanCastMedia media, {
  bool receiving = false,
  bool replacePage = false,
  int? position,
  bool Function()? stillValid,
}) async {
  if (media.isLive) {
    if (stillValid?.call() == false) return;
    PageUtils.toLiveRoom(
      media.roomId,
      off: Get.currentRoute == '/liveRoom',
      lanCast: receiving,
    );
    return;
  }
  final extra = <String, dynamic>{
    receiving ? 'lanCast' : 'lanCastResume': true,
  };
  if (media.listSource case final source?) {
    extra.addAll({
      'sourceType': SourceType.values.byName(source.type),
      'mediaId': source.id,
      'favTitle': source.title,
      'desc': source.desc,
      if (source.mediaType != null) 'mediaType': source.mediaType,
      'sortField': source.sortField,
      'isContinuePlaying': true,
      'oid': media.aid,
    });
  }
  if (media.kind != 'ugc') {
    final result =
        await (media.kind == 'pgc'
                ? SearchHttp.pgcInfo(epId: media.epId)
                : SearchHttp.pugvInfo(
                    epId: media.epId,
                    seasonId: media.seasonId,
                  ))
            .timeout(const Duration(seconds: 8));
    if (result case Success(:final response)) {
      extra['pgcItem'] = response;
    } else {
      throw const LanCastException('无法获取节目详情，请检查登录状态', 422);
    }
  }
  if (stillValid?.call() == false) return;
  // Do not await the route result: it completes when the video page is closed.
  PageUtils.toVideoPage(
    videoType: VideoType.values.byName(media.kind),
    aid: media.aid,
    bvid: media.bvid,
    cid: media.cid!,
    epId: media.epId,
    seasonId: media.seasonId,
    pgcType: media.pgcType,
    title: media.title,
    progress: position ?? media.position,
    extraArguments: extra,
    off: replacePage,
  );
}

class LanCastNavigation extends NavigatorObserver with ChangeNotifier {
  LanCastNavigation({this.openVideo});
  static final instance = LanCastNavigation();
  final Future<void> Function(LanCastMedia, int, bool Function())? openVideo;
  final _routes = <Route<dynamic>>[];
  Route<dynamic>? _controlRoute;
  String? _controlKey;
  bool opening = false;
  bool _scheduled = false;
  bool _disposed = false;

  Route<dynamic>? get currentPageRoute {
    final pages = _routes.whereType<PageRoute<dynamic>>();
    return pages.where((route) => route.isCurrent).lastOrNull ??
        pages.where((route) => route.isActive).lastOrNull;
  }

  void rememberControlRoute(String key, {Route<dynamic>? route}) {
    final page = route ?? currentPageRoute;
    _controlRoute = _routes.contains(page) ? page : null;
    _controlKey = key;
    _changed();
  }

  bool isOnControlPage(LanCastSession session) =>
      _controlKey == session.mediaKey &&
      _controlRoute != null &&
      _routes.lastOrNull == _controlRoute;

  bool get hasPopup => _routes.lastOrNull is PopupRoute;

  void invalidateCurrentControlRoute() {
    if (_routes.whereType<PageRoute<dynamic>>().lastOrNull == _controlRoute) {
      _controlRoute = null;
      _controlKey = null;
      _changed();
    }
  }

  Future<void> followReceiver(
    LanCastSession session,
    String previousKey,
  ) async {
    if (_controlKey != previousKey ||
        _controlRoute == null ||
        _routes.lastOrNull != _controlRoute) {
      return;
    }
    await returnToControls(session, replacePage: true);
  }

  Future<void> returnToControls(
    LanCastSession session, {
    bool replacePage = false,
  }) async {
    final media = session.media;
    if (opening || !session.connected || media == null) return;
    if (_controlKey == media.key && _routes.contains(_controlRoute)) {
      navigator?.popUntil((route) => identical(route, _controlRoute));
      return;
    }
    opening = true;
    _changed();
    bool stillValid() => session.connected && identical(session.media, media);
    try {
      if (openVideo case final open?) {
        await open(media, session.status.position, stillValid);
      } else {
        await openLanCastVideo(
          media,
          replacePage: replacePage,
          position: session.status.position,
          stillValid: stillValid,
        );
      }
      // Navigator delivers route observer notifications after pushing the page.
      await WidgetsBinding.instance.endOfFrame;
      if (stillValid()) rememberControlRoute(media.key);
    } finally {
      opening = false;
      _changed();
    }
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute != null) {
        _routes[index] = newRoute;
      } else {
        _routes.removeAt(index);
      }
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
