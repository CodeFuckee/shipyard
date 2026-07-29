import 'package:flutter/material.dart';
import 'package:mobile_portainer_flutter_module/widgets/app_toast.dart';
import 'package:mobile_portainer_flutter_module/utils/toast_utils.dart';
import 'platform_detector.dart';

/// Centralized API error handler — extracts a user-friendly message from
/// exceptions thrown by DockerService and shows it as a toast.
class ApiErrorHandler {
  /// Extract a human-readable message from any error thrown by [DockerService].
  static String extractMessage(dynamic error) {
    if (error == null) return 'Unknown error';
    final msg = error.toString();

    // Strip the "Exception: " prefix if present
    if (msg.startsWith('Exception: ')) {
      return msg.substring(11);
    }

    return msg;
  }

  /// Show the error as both a toast (all platforms) and return the message
  /// string for use with ErrorView / state management.
  ///
  /// Call this in your catch blocks alongside setState:
  /// ```dart
  /// catch (e) {
  ///   final msg = ApiErrorHandler.handle(context, e);
  ///   setState(() => _error = msg);
  /// }
  /// ```
  static String handle(BuildContext context, dynamic error) {
    final message = extractMessage(error);

    // Use platform-appropriate toast
    if (PlatformDetector.isOhos || PlatformDetector.isAndroid) {
      ToastUtils.show(message);
    } else {
      AppToast.error(context, message);
    }

    return message;
  }

  /// Convenience: shows error toast without returning the message string.
  static void show(BuildContext context, dynamic error) {
    final message = extractMessage(error);

    if (PlatformDetector.isOhos || PlatformDetector.isAndroid) {
      ToastUtils.show(message);
    } else {
      AppToast.error(context, message);
    }
  }
}
