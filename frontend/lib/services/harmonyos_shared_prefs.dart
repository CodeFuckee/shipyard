import 'harmonyos_platform.dart';

/// 鸿蒙平台的 SharedPreferences 替代实现
/// 使用静态缓存实现同步读取，异步写入
class HarmonyosPreferences {
  HarmonyosPreferences._();

  static final HarmonyosPreferences _instance = HarmonyosPreferences._();
  static final Map<String, String?> _cache = {};

  /// App 使用的所有 preference key，用于初始化时预加载
  static const List<String> _preloadKeys = [
    'docker_api_url',
    'docker_api_key',
    'docker_ignore_ssl',
    'server_list',
    'language_code',
    'timezone_code',
    'container_layout_mode',
    'env_vars_global',
    'env_vars_groups',
  ];

  static Future<HarmonyosPreferences> getInstance() async {
    // 预加载已知 key 到缓存
    for (final key in _preloadKeys) {
      try {
        final value = await HarmonyosPlatform.getString(key);
        if (value != null) {
          _cache[key] = value;
        }
      } catch (_) {
        // 忽略单个 key 加载失败
      }
    }
    return _instance;
  }

  /// 同步读取（从内存缓存）
  String? getString(String key) {
    return _cache[key];
  }

  bool? getBool(String key) {
    final value = _cache[key];
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  /// 异步写入（更新缓存并持久化）
  Future<bool> setString(String key, String value) async {
    _cache[key] = value;
    return HarmonyosPlatform.setString(key, value);
  }

  Future<bool> setBool(String key, bool value) async {
    _cache[key] = value.toString();
    return HarmonyosPlatform.setString(key, value.toString());
  }

  /// 异步删除（移除缓存并持久化）
  Future<bool> remove(String key) async {
    _cache.remove(key);
    return HarmonyosPlatform.remove(key);
  }
}
