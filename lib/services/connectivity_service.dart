import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/app_logger.dart';

/// Service monitoring device network reachability using connectivity_plus.
/// Notifies listeners and streams connection state for offline banner rendering.
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool _hasCheckedInitially = false;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  bool get isOnline => _isOnline;
  bool get hasCheckedInitially => _hasCheckedInitially;

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      AppLogger.w('Initial connectivity check failed: $e', tag: 'Connectivity');
      _isOnline = true; // Assume online on fallback
    } finally {
      _hasCheckedInitially = true;
      notifyListeners();
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    final isNowOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    _isOnline = !isNowOffline;

    if (wasOnline != _isOnline) {
      AppLogger.i(
        _isOnline
            ? 'Network restored: Online'
            : 'Network lost: Offline mode active',
        tag: 'Connectivity',
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
