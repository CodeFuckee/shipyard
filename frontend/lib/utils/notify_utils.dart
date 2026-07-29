import 'package:flutter/material.dart';
import 'package:mobile_portainer_flutter_module/utils/toast_utils.dart';
import 'package:mobile_portainer_flutter_module/widgets/app_toast.dart';
import 'platform_detector.dart';

class NotifyUtils {
  static void showNotify(BuildContext context, String message) {
    if (PlatformDetector.isOhos || PlatformDetector.isAndroid) {
      ToastUtils.show(message);
    } else {
      AppToast.info(context, message);
    }
  }
}
