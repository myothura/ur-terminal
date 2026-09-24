import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native window hooks (see macos/Runner/MainFlutterWindow.swift).
class WindowChrome {
  WindowChrome._();

  static const _channel = MethodChannel('ur/window');

  /// Width reserved on the left of the title bar for the traffic lights.
  static const trafficLightsInset = 78.0;
  static const titleBarHeight = 40.0;

  static Future<void> startDrag() async {
    try {
      await _channel.invokeMethod<void>('startDrag');
    } catch (_) {}
  }

  static Future<void> zoom() async {
    try {
      await _channel.invokeMethod<void>('zoom');
    } catch (_) {}
  }
}

/// Makes its empty area behave like a native title bar: drag to move,
/// double-click to zoom.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowChrome.startDrag(),
      onDoubleTap: WindowChrome.zoom,
      child: child,
    );
  }
}
