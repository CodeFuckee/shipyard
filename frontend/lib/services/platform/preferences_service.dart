import 'package:shared_preferences/shared_preferences.dart';
import '../../services/harmonyos_shared_prefs.dart';
import '../../utils/platform_detector.dart';

/// 跨平台偏好设置服务
/// HarmonyOS 使用 HarmonyosPreferences，Android/iOS 使用 SharedPreferences
class PreferencesService {
  final dynamic _delegate;
  final bool _isOhos;

  PreferencesService._(this._delegate, this._isOhos);

  static Future<PreferencesService> getInstance() async {
    if (PlatformDetector.isOhos) {
      final delegate = await HarmonyosPreferences.getInstance();
      return PreferencesService._(delegate, true);
    } else {
      final delegate = await SharedPreferences.getInstance();
      return PreferencesService._(delegate, false);
    }
  }

  String? getString(String key) {
    if (_isOhos) {
      return (_delegate as HarmonyosPreferences).getString(key);
    }
    return (_delegate as SharedPreferences).getString(key);
  }

  bool? getBool(String key) {
    if (_isOhos) {
      return (_delegate as HarmonyosPreferences).getBool(key);
    }
    return (_delegate as SharedPreferences).getBool(key);
  }

  Future<bool> setString(String key, String value) async {
    if (_isOhos) {
      return (_delegate as HarmonyosPreferences).setString(key, value);
    }
    return (_delegate as SharedPreferences).setString(key, value);
  }

  Future<bool> setBool(String key, bool value) async {
    if (_isOhos) {
      return (_delegate as HarmonyosPreferences).setBool(key, value);
    }
    return (_delegate as SharedPreferences).setBool(key, value);
  }

  Future<bool> remove(String key) async {
    if (_isOhos) {
      return (_delegate as HarmonyosPreferences).remove(key);
    }
    return (_delegate as SharedPreferences).remove(key);
  }
}
