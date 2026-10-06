import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

class LanCastDiscovery extends ChangeNotifier {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final Map<String, LanCastDevice> devices = {};
  String? error;
  bool searching = false;
  bool _disposed = false;

  Future<void> start() async {
    if (searching || _disposed) return;
    searching = true;
    error = null;
    devices.clear();
    notifyListeners();
    try {
      await ensureLanCastPermission();
      if (_disposed) return;
      await _subscription?.cancel();
      if (_discovery case final old? when old.isReady && !old.isStopped) {
        await old.stop();
      }
      final discovery = _discovery = BonsoirDiscovery(
        type: lanCastServiceType,
        printLogs: false,
      );
      await discovery.initialize();
      if (_disposed) {
        await discovery.stop();
        return;
      }
      _subscription = discovery.eventStream!.listen(
        (event) {
          if (_disposed) return;
          switch (event) {
            case BonsoirDiscoveryServiceFoundEvent(:final service):
              service.resolve(discovery.serviceResolver);
            case BonsoirDiscoveryServiceResolvedEvent(:final service):
            case BonsoirDiscoveryServiceUpdatedEvent(:final service):
              final addresses = service.hostAddresses.where((value) {
                final address = InternetAddress.tryParse(value);
                return address != null &&
                    address.type == InternetAddressType.IPv4 &&
                    isLanCastAddress(address);
              });
              if (addresses.isNotEmpty &&
                  service.attributes['v'] == '$lanCastProtocolVersion') {
                devices[service.name] = LanCastDevice(
                  id: service.attributes['id'] ?? service.name,
                  name: service.name,
                  uri: Uri(
                    scheme: 'http',
                    host: addresses.first,
                    port: service.port,
                  ),
                );
                notifyListeners();
              }
            case BonsoirDiscoveryServiceLostEvent(:final service):
              devices.remove(service.name);
              notifyListeners();
            default:
              break;
          }
        },
        onError: (Object _) {
          if (!_disposed) {
            error = '自动发现不可用，可手动输入接收端地址';
            notifyListeners();
          }
        },
      );
      await discovery.start();
    } catch (e) {
      error = e is LanCastException ? e.message : '无法搜索设备，请允许本地网络访问，或手动输入接收端地址';
    } finally {
      searching = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    final discovery = _discovery;
    if (discovery != null && discovery.isReady && !discovery.isStopped) {
      unawaited(discovery.stop().catchError((Object _) {}));
    }
    super.dispose();
  }
}

String get lanCastDeviceName {
  final host = Platform.localHostname.split('.').first;
  final name = host.isEmpty ? Platform.operatingSystem : host;
  return 'PiliPlus ${name.length > 36 ? name.substring(0, 36) : name}';
}
