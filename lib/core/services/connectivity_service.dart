import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络状态 —— 由原生 `util/WifiConnectivitiyUtil.kt` 移植。
enum DataConnection {
  notAvailable,
  connected,
  metered,
  disconnected;

  /// 是否可以直接跑同步（非计费网络）。
  bool get allowsUnmetered => this == DataConnection.connected;
}

class ConnectivityService {
  const ConnectivityService._();

  /// 判定当前连接。
  ///
  /// 原生用 `NetworkCapabilities.NET_CAPABILITY_NOT_METERED`，能识别
  /// **计费热点**；`connectivity_plus` 只能看到链路类型，所以这里是近似：
  ///
  /// * `wifi` / `ethernet` / `vpn` → [DataConnection.connected]
  /// * `mobile` / `bluetooth` / `other` → [DataConnection.metered]
  /// * `none` → [DataConnection.notAvailable]
  ///
  /// ⚠️ 已知差异：**手机热点下的 Wi-Fi 会被误判为非计费**。
  /// 要精确判定需要写平台通道读 `ConnectivityManager`。
  static Future<DataConnection> current() async {
    final List<ConnectivityResult> results =
        await Connectivity().checkConnectivity();
    return _classify(results);
  }

  /// 订阅变化（原生 `SyncWorker` 会在同步过程中监听连接切换并中止）。
  static Stream<DataConnection> watch() =>
      Connectivity().onConnectivityChanged.map(_classify);

  static DataConnection _classify(List<ConnectivityResult> results) {
    if (results.isEmpty ||
        results.every((ConnectivityResult r) => r == ConnectivityResult.none)) {
      return DataConnection.notAvailable;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return DataConnection.metered;
    }
    if (results.any(
      (ConnectivityResult r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    )) {
      return DataConnection.connected;
    }
    return DataConnection.metered;
  }
}
