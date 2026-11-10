import 'package:flutter/widgets.dart';

/// Completes the initiating route even if an alarm opened another route above it.
void finishRoute(Route<dynamic>? route, [Object? result]) {
  if (route == null || !route.isActive) return;
  final navigator = route.navigator;
  if (navigator == null) return;
  if (route.isCurrent) {
    navigator.pop(result);
  } else {
    navigator.removeRoute(route, result);
  }
}
