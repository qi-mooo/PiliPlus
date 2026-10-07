import 'dart:async';

import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DLNAPage extends StatelessWidget {
  const DLNAPage({super.key});

  @override
  Widget build(BuildContext context) => SimpleScaffold(
    appBar: AppBar(title: const Text('投屏')),
    body: SingleChildScrollView(
      child: DLNADeviceList(
        mediaUrl: () async => Get.parameters['url']!,
        title: Get.parameters['title'] ?? '',
      ),
    ),
  );
}

/// Shared by the legacy route and the unified casting device sheet.
class DLNADeviceList extends StatefulWidget {
  const DLNADeviceList({
    super.key,
    required this.mediaUrl,
    required this.title,
    this.enabled = true,
    this.onConnected,
    this.onBusyChanged,
    this.manager,
  });
  final Future<String> Function() mediaUrl;
  final String title;
  final bool enabled;
  final Future<void> Function()? onConnected;
  final ValueChanged<bool>? onBusyChanged;
  final DLNAManager? manager;

  @override
  State<DLNADeviceList> createState() => _DLNADeviceListState();
}

class _DLNADeviceListState extends State<DLNADeviceList> {
  late final _searcher = widget.manager ?? DLNAManager();
  final _devices = <String, DLNADevice>{};
  StreamSubscription<Map<String, DLNADevice>>? _subscription;
  Timer? _timer;
  bool _searching = false;
  bool _connecting = false;
  String? _error;
  String? _selected;
  DLNADevice? _lastDevice;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _error = null;
      _devices.clear();
    });
    try {
      await ensureLanCastPermission();
      if (!mounted) return;
      await _subscription?.cancel();
      _timer?.cancel();
      final manager = await _searcher.start();
      if (!mounted) {
        _searcher.stop();
        return;
      }
      _subscription = manager.devices.stream.listen(
        (devices) {
          if (mounted) setState(() => _devices.addAll(devices));
        },
        onError: (Object _) {
          if (mounted) setState(() => _error = 'DLNA 设备搜索失败');
        },
      );
      _timer = Timer(const Duration(seconds: 20), () {
        _searcher.stop();
        if (mounted) setState(() => _searching = false);
      });
    } catch (_) {
      _searcher.stop();
      if (mounted) {
        setState(() {
          _searching = false;
          _error = '无法搜索 DLNA 设备，请检查本地网络权限';
        });
      }
    }
  }

  Future<void> _connect(String key, DLNADevice device) async {
    if (_connecting || key == _selected) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final url = await widget.mediaUrl();
      if (!mounted) return;
      if (_lastDevice != null) await _lastDevice!.pause();
      await device.setUrl(url, title: widget.title);
      await device.play();
      _lastDevice = device;
      _selected = key;
      if (mounted) await widget.onConnected?.call();
    } catch (e) {
      if (mounted) setState(() => _error = 'DLNA 投屏失败：$e');
    } finally {
      if (mounted) {
        widget.onBusyChanged?.call(false);
        setState(() => _connecting = false);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _searcher.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        title: const Text('DLNA 设备'),
        trailing: IconButton(
          tooltip: '搜索 DLNA 设备',
          icon: const Icon(Icons.refresh),
          onPressed: _searching || _connecting || !widget.enabled
              ? null
              : _search,
        ),
      ),
      if (_searching || _connecting) const LinearProgressIndicator(),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            error,
            style: TextStyle(color: ColorScheme.of(context).error),
          ),
        ),
      if (_devices.isEmpty)
        ListTile(title: Text(_searching ? '正在搜索 DLNA 设备…' : '未发现 DLNA 设备')),
      for (final entry in _devices.entries)
        ListTile(
          leading: Icon(
            entry.key == _selected ? Icons.cast_connected : Icons.cast,
          ),
          title: Text(entry.value.info.friendlyName),
          subtitle: const Text('DLNA'),
          selected: entry.key == _selected,
          enabled: widget.enabled && !_connecting,
          onTap: () => _connect(entry.key, entry.value),
        ),
    ],
  );
}
