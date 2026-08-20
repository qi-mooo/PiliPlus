import 'dart:math' as math;

import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final RcmdController controller = Get.put(RcmdController());
  final FocusNode _focusNode = FocusNode(debugLabel: 'RcmdPageGrid');
  int _selectedIndex = 0;
  int _gridCrossAxisCount = 1;
  double _gridTileMainAxisExtent = 0;
  double _gridMainAxisStride = 0;
  bool _showKeyboardSelection = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (PlatformUtils.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    final child = Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: refreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const .only(top: Style.cardSpace, bottom: 100),
              sliver: Obx(
                () => _buildBody(colorScheme, controller.loadingState.value),
              ),
            ),
          ],
        ),
      ),
    );
    if (!PlatformUtils.isMobile) {
      return child;
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _activateCurrent,
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        descendantsAreFocusable: false,
        onKeyEvent: _onKeyEvent,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _focusNode.requestFocus();
            if (_showKeyboardSelection) {
              setState(() => _showKeyboardSelection = false);
            }
          },
          child: child,
        ),
      ),
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Pref.recommendCardWidth,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? _buildGrid(colorScheme, response)
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _buildGrid(ColorScheme colorScheme, List<dynamic> response) {
    final itemCount = _gridItemCount(response);
    _clampSelectedIndex(itemCount);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        _updateGridMetrics(constraints.crossAxisExtent);
        return SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemBuilder: (context, index) {
            if (index == response.length - 1) {
              controller.onLoadMore();
            }
            final selected =
                PlatformUtils.isMobile &&
                _showKeyboardSelection &&
                _selectedIndex == index;
            if (controller.lastRefreshAt != null) {
              if (controller.lastRefreshAt == index) {
                return GestureDetector(
                  onTap: () => controller
                    ..animateToTop()
                    ..onRefresh(),
                  child: Container(
                    foregroundDecoration: selected
                        ? BoxDecoration(
                            border: Border.all(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                            borderRadius: Style.mdRadius,
                          )
                        : null,
                    child: Card(
                      child: Container(
                        alignment: Alignment.center,
                        padding: const .symmetric(horizontal: 10),
                        child: Text(
                          '上次看到这里\n点击刷新',
                          textAlign: .center,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              final actualIndex = index > controller.lastRefreshAt!
                  ? index - 1
                  : index;
              return VideoCardV(
                videoItem: response[actualIndex],
                selected: selected,
                onRemove: () {
                  if (controller.lastRefreshAt != null &&
                      actualIndex < controller.lastRefreshAt!) {
                    controller.lastRefreshAt = controller.lastRefreshAt! - 1;
                  }
                  controller.loadingState
                    ..value.data!.removeAt(actualIndex)
                    ..refresh();
                },
              );
            } else {
              return VideoCardV(
                videoItem: response[index],
                selected: selected,
                onRemove: () => controller.loadingState
                  ..value.data!.removeAt(index)
                  ..refresh(),
              );
            }
          },
          itemCount: itemCount,
        );
      },
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) {
        final context = node.context;
        if (context != null) {
          Navigator.maybeOf(context)?.maybePop();
        }
      }
      return KeyEventResult.handled;
    }
    if (!_isNavigationKey(key)) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    final response = controller.loadingState.value.dataOrNull;
    if (response == null) {
      return KeyEventResult.handled;
    }
    final itemCount = _gridItemCount(response);
    if (itemCount == 0) {
      return KeyEventResult.handled;
    }
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        _moveSelection(-1, itemCount);
      case LogicalKeyboardKey.arrowRight:
        _moveSelection(1, itemCount);
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-_gridCrossAxisCount, itemCount);
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(_gridCrossAxisCount, itemCount);
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space ||
          LogicalKeyboardKey.select:
        if (!_showKeyboardSelection) {
          setState(() => _showKeyboardSelection = true);
        }
        _activateSelected(response);
    }
    return KeyEventResult.handled;
  }

  bool _isNavigationKey(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft ||
    LogicalKeyboardKey.arrowRight ||
    LogicalKeyboardKey.arrowUp ||
    LogicalKeyboardKey.arrowDown ||
    LogicalKeyboardKey.enter ||
    LogicalKeyboardKey.numpadEnter ||
    LogicalKeyboardKey.space ||
    LogicalKeyboardKey.select => true,
    _ => false,
  };

  int _gridItemCount(List<dynamic> response) =>
      controller.lastRefreshAt != null ? response.length + 1 : response.length;

  void _clampSelectedIndex(int itemCount) {
    if (itemCount <= 0) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= itemCount) {
      _selectedIndex = itemCount - 1;
    }
  }

  void _moveSelection(int offset, int itemCount) {
    var nextIndex = _selectedIndex + offset;
    if (nextIndex < 0) {
      nextIndex = 0;
    } else if (nextIndex >= itemCount) {
      nextIndex = itemCount - 1;
    }
    if (nextIndex == _selectedIndex) {
      if (!_showKeyboardSelection) {
        setState(() => _showKeyboardSelection = true);
      }
      _ensureSelectedVisible(nextIndex);
      return;
    }
    setState(() {
      _selectedIndex = nextIndex;
      _showKeyboardSelection = true;
    });
    _ensureSelectedVisible(nextIndex);
  }

  void _activateSelected(List<dynamic> response) {
    if (_selectedIndex == controller.lastRefreshAt) {
      controller
        ..animateToTop()
        ..onRefresh();
      return;
    }
    final actualIndex = _actualIndexFromGridIndex(_selectedIndex);
    if (actualIndex < 0 || actualIndex >= response.length) {
      return;
    }
    final item = response[actualIndex];
    if (item is BaseRcmdVideoItemModel) {
      VideoCardV.pushDetail(item);
    }
  }

  void _activateCurrent() {
    _focusNode.requestFocus();
    final response = controller.loadingState.value.dataOrNull;
    if (response == null || _gridItemCount(response) == 0) {
      return;
    }
    if (!_showKeyboardSelection) {
      setState(() => _showKeyboardSelection = true);
    }
    _activateSelected(response);
  }

  int _actualIndexFromGridIndex(int index) {
    final lastRefreshAt = controller.lastRefreshAt;
    return lastRefreshAt != null && index > lastRefreshAt ? index - 1 : index;
  }

  void _updateGridMetrics(double crossAxisExtent) {
    final crossAxisSpacing = gridDelegate.crossAxisSpacing;
    var crossAxisCount =
        ((crossAxisExtent - crossAxisSpacing) /
                (gridDelegate.maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    if (crossAxisCount < 1) {
      crossAxisCount = 1;
    }
    final usableCrossAxisExtent = math.max(
      0.0,
      crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    _gridCrossAxisCount = crossAxisCount;
    _gridTileMainAxisExtent =
        childCrossAxisExtent / gridDelegate.childAspectRatio +
        gridDelegate.mainAxisExtent;
    _gridMainAxisStride =
        _gridTileMainAxisExtent + gridDelegate.mainAxisSpacing;
  }

  void _ensureSelectedVisible(int index) {
    if (_gridTileMainAxisExtent == 0 ||
        _gridMainAxisStride == 0 ||
        !controller.scrollController.hasClients) {
      return;
    }
    final position = controller.scrollController.position;
    final itemTop =
        Style.cardSpace + (index ~/ _gridCrossAxisCount) * _gridMainAxisStride;
    final itemBottom = itemTop + _gridTileMainAxisExtent;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    double? target;
    if (itemTop < viewportTop) {
      target = itemTop;
    } else if (itemBottom > viewportBottom) {
      target = itemBottom - position.viewportDimension;
    }
    if (target == null) {
      return;
    }
    if (target < position.minScrollExtent) {
      target = position.minScrollExtent;
    } else if (target > position.maxScrollExtent) {
      target = position.maxScrollExtent;
    }
    if ((target - position.pixels).abs() < 1) {
      return;
    }
    controller.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  Widget get _buildSkeleton => SliverGrid.builder(
    gridDelegate: gridDelegate,
    itemBuilder: (context, index) => const VideoCardVSkeleton(),
    itemCount: 10,
  );
}
