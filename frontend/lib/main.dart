import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_tab_screen.dart';
import 'screens/login_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/back_press_service.dart';
import 'services/connect_service.dart';
import 'services/harmonyos_shared_prefs.dart';
import 'services/server_list_storage.dart';
import 'utils/platform_detector.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 通过 URL 参数启用语义树，供 Selenium 测试使用。
  // Flutter Web CanvasKit 模式下，显式激活语义树可确保
  // flt-semantics DOM 元素在页面加载时立即生成，
  // 无需通过点击 flt-semantics-placeholder 触发。
  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.queryParameters['enable_semantics'] == 'true') {
      SemanticsBinding.instance.ensureSemantics();
    }
  }

  // Workaround for Flutter framework bug: on macOS, synthesized Caps Lock
  // KeyUpEvents can arrive without corresponding KeyDownEvents in
  // _pressedKeys, triggering an assertion error in
  // HardwareKeyboard._assertEventIsRegular (hardware_keyboard.dart:522).
  // This only affects debug mode — assert is stripped in release builds.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is AssertionError &&
        error.toString().contains('_pressedKeys.containsKey')) {
      return true; // Silently suppress the Caps Lock assertion
    }
    return false; // Let other errors through
  };

  // /connect 授权回跳处理：必须在 AuthGate 判定之前完成 token 交换与
  // 服务器添加，否则回调参数会被登录门卫拦截丢弃。
  if (kIsWeb && ConnectService.isCallbackUri(Uri.base)) {
    await _handleConnectCallback();
  }

  await NotificationService.instance.initialize();
  BackPressService.initialize();
  String? languageCode;
  if (PlatformDetector.isOhos) {
    final prefs = await HarmonyosPreferences.getInstance();
    languageCode = prefs.getString('language_code');
  } else {
    final prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('language_code');
  }
  runApp(MyApp(initialLanguageCode: languageCode));
}

/// 处理 /connect 授权回跳：校验 state → token 交换 → 写入服务器列表并切换。
///
/// 运行在 AuthGate 之前、无 UI 上下文：先清理 URL 参数（防刷新重复处理），
/// 交换失败静默忽略，用户可重新发起授权添加。
Future<void> _handleConnectCallback() async {
  final uri = Uri.base;
  ConnectService.clearCallbackParams(uri);
  try {
    final result = await ConnectService.completeFlow(uri);
    if (result == null) return; // state 不匹配，非本流程发起的回跳
    await _addServerFromConnect(result);
  } catch (_) {
    // 授权码交换失败：参数已清理，保持静默
  }
}

/// 将授权获取的独立 apikey 写入服务器列表并切换为活动服务器。
///
/// 同 URL 已存在时覆盖 apikey；否则以 URL 主机名作为默认名称添加。
/// 先切换活动服务器（即使列表保存失败，主界面也能立即使用），
/// 列表保存尽力而为（Web 端依赖已登录会话，失败自动落本地缓存）。
Future<void> _addServerFromConnect(ConnectResult result) async {
  final prefs = await SharedPreferences.getInstance();
  final storage = ServerListStorage();
  final servers = await storage.load();

  final url = result.serverUrl;
  final existingIndex = servers.indexWhere((s) => s['url'] == url);
  if (existingIndex >= 0) {
    servers[existingIndex] = {
      ...servers[existingIndex],
      'apiKey': result.apikey,
    };
  } else {
    final host = Uri.tryParse(url)?.host ?? '';
    servers.add({
      'name': host.isEmpty ? url : host,
      'url': url,
      'apiKey': result.apikey,
      'ignoreSsl': 'false',
    });
  }

  await prefs.setString('docker_api_url', url);
  await prefs.setString('docker_api_key', result.apikey);
  await prefs.setString('docker_ignore_ssl', 'false');

  await storage.save(servers);
}

class MyApp extends StatefulWidget {
  final String? initialLanguageCode;
  const MyApp({super.key, this.initialLanguageCode});

  static void setLocale(BuildContext context, Locale? newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    if (widget.initialLanguageCode != null) {
      _locale = Locale(widget.initialLanguageCode!);
    }
  }

  void setLocale(Locale? locale) {
    setState(() {
      _locale = locale;
    });
    _saveLocale(locale);
  }

  Future<void> _saveLocale(Locale? locale) async {
    if (PlatformDetector.isOhos) {
      final prefs = await HarmonyosPreferences.getInstance();
      if (locale == null) {
        await prefs.remove('language_code');
      } else {
        await prefs.setString('language_code', locale.languageCode);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove('language_code');
      } else {
        await prefs.setString('language_code', locale.languageCode);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Docker Monitor',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isLoggedIn!) {
      return const MainTabScreen();
    }

    return const LoginScreen();
  }
}
