import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NavigationService {
  static final NavigationService instance = NavigationService._();
  NavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Map<String, dynamic>? _pendingNavigation;

  // Active DM tracking - used to suppress notifications for the DM user is viewing
  String? _activeDmId;

  /// Set the currently active DM (user is viewing this DM chat)
  void setActiveDM(String? dmId) {
    debugPrint('NavigationService.setActiveDM: $dmId (was: $_activeDmId)');
    _activeDmId = dmId;
  }

  /// Get the currently active DM ID
  String? get activeDmId => _activeDmId;

  // Callbacks for navigation events
  final List<VoidCallback> _navigationListeners = [];

  void setPendingNavigation(Map<String, dynamic> data) {
    _pendingNavigation = data;
  }

  Map<String, dynamic>? consumePendingNavigation() {
    final nav = _pendingNavigation;
    _pendingNavigation = null;
    return nav;
  }

  Map<String, dynamic>? peekPendingNavigation() {
    return _pendingNavigation;
  }

  /// Add a listener that will be called when navigation is triggered
  void addNavigationListener(VoidCallback callback) {
    _navigationListeners.add(callback);
  }

  /// Remove a navigation listener
  void removeNavigationListener(VoidCallback callback) {
    _navigationListeners.remove(callback);
  }

  /// Notify all listeners that navigation should be checked
  void notifyNavigationListeners() {
    for (final listener in _navigationListeners) {
      listener();
    }
  }
}
