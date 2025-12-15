import 'package:flutter/material.dart';

class NavigationService {
  static final NavigationService instance = NavigationService._();
  NavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Map<String, dynamic>? _pendingNavigation;

  void setPendingNavigation(Map<String, dynamic> data) {
    _pendingNavigation = data;
  }

  Map<String, dynamic>? consumePendingNavigation() {
    final nav = _pendingNavigation;
    _pendingNavigation = null;
    return nav;
  }
}
