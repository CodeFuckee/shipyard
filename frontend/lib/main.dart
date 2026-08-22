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
import 'services/oidc_service.dart';
import 'services/harmonyos_shared_prefs.dart';
import 'services/platform/preferences_service.dart';
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

  // 外部授权回跳必须在 AuthGate 判定前完成令牌交换，否则回调参数会丢失。
  if (kIsWeb && OidcService.isCallbackUri(Uri.base)) {
    await _handleOidcCallback();
  } else if (kIsWeb && ConnectService.isCallbackUri(Uri.base)) {
    await _handleConnectCallback();
  }
  // 移动端：冷启动深链检查与语言设置读取互不依赖，并行启动以缩短
  // 首帧前的串行等待（深链处理仍保持 AuthGate 判定前的时序语义）。
  final Future<Uri?>? linkFuture = kIsWeb ? null : ConnectService.initialLink();
  String? languageCode;
  if (PlatformDetector.isOhos) {
    final prefs = await HarmonyosPreferences.getInstance();
    languageCode = prefs.getString('language_code');
  } else {
    final prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('language_code');
  }
  if (linkFuture != null) {
    final link = await linkFuture;
    if (link != null && OidcService.isCallbackUri(link)) {
      await _handleMobileOidcCallback(link);
    } else if (link != null && ConnectService.isCallbackUri(link)) {
      await _handleMobileConnectCallback(link);
    }
  }
  BackPressService.initialize();
  runApp(MyApp(initialLanguageCode: languageCode));

  // 通知服务初始化与首帧渲染无关（当前无业务调用方），延迟到首帧之后
  // 执行：Android 13+ 的通知权限对话框若在首帧前等待用户响应，会显著
  // 拉长白屏时间。初始化失败不影响主流程，静默忽略。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.initialize().then(
      (_) {},
      onError: (Object _) {},
    );
  });
}

/// 处理 OIDC 回跳：服务端验证 ID Token 后保存 API Key，再进入既有登录态。
Future<void> _handleOidcCallback() async {
  final uri = Uri.base;
  OidcService.clearCallbackParams(uri);
  try {
    final result = await OidcService.completeFlow(uri);
    if (result != null) {
      await AuthService.saveOidcLogin(
        serverUrl: result.serverUrl,
        apiKey: result.apiKey,
      );
    }
  } catch (_) {
    // 令牌校验失败时保持未登录，本地管理员仍可作为紧急回退。
  }
}

/// 移动端 OIDC 深链回跳处理。
Future<void> _handleMobileOidcCallback(Uri uri) async {
  try {
    final result = await OidcService.completeFlow(uri);
    if (result != null) {
      await AuthService.saveOidcLogin(
        serverUrl: result.serverUrl,
        apiKey: result.apiKey,
      );
    }
  } catch (_) {
    // 失败后由登录页继续提供本地管理员回退。
  }
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
/// 存储经 [PreferencesService] 统一走鸿蒙 preferences / SharedPreferences。
Future<void> _addServerFromConnect(ConnectResult result) async {
  final prefs = await PreferencesService.getInstance();

  // 存量用户（web_backend_* 功能上线前部署）首次授权添加时初始化登录
  // 服务器凭据：以当前 docker_auth_* 为准（未切换过则正确），确保列表
  // 保存到登录服务器而非漂移目标；下次登录会写入正确值。
  final backendUrl = prefs.getString('web_backend_url');
  final backendToken = prefs.getString('web_backend_token');
  if ((backendUrl == null || backendUrl.isEmpty) ||
      (backendToken == null || backendToken.isEmpty)) {
    final legacyUrl = prefs.getString('docker_auth_server_url');
    final legacyToken = prefs.getString('docker_auth_token');
    if (legacyUrl != null && legacyUrl.isNotEmpty && legacyToken != null) {
      await prefs.setString('web_backend_url', legacyUrl);
      await prefs.setString('web_backend_token', legacyToken);
    }
  }

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

/// 移动端冷启动深链回跳处理：校验 state → token 交换 → 添加服务器。
///
/// 与 Web 端 [_handleConnectCallback] 行为一致（失败静默，参数一次性），
/// 仅入口不同：移动端由 app_links / 鸿蒙深链提供 URI，无 URL 参数清理。
Future<void> _handleMobileConnectCallback(Uri uri) async {
  try {
    final result = await ConnectService.completeFlow(uri);
    if (result == null) return; // state 不匹配，非本流程发起的回跳
    await _addServerFromConnect(result);
  } catch (_) {
    // 授权码交换失败：流程状态已清理，保持静默
  }
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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Locale? _locale;

  /// 热启动深链处理与 loading 对话框共用的导航 key。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _firstResumed = true;
  bool _handlingPendingLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialLanguageCode != null) {
      _locale = Locale(widget.initialLanguageCode!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 冷启动后的首次 resumed 跳过：深链已在 main() 中消费
    if (_firstResumed) {
      _firstResumed = false;
      return;
    }
    _handlePendingDeepLink();
  }

  /// 热启动深链回跳（用户从系统浏览器授权页返回本 app）。
  ///
  /// 消费一次深链；若为 /connect 回调则弹加载对话框完成 token 交换
  /// 并添加服务器，处理期间防重入。
  Future<void> _handlePendingDeepLink() async {
    if (_handlingPendingLink) return;
    final link = await ConnectService.pendingLink();
    if (link == null ||
        (!ConnectService.isCallbackUri(link) &&
            !OidcService.isCallbackUri(link))) {
      return;
    }
    _handlingPendingLink = true;

    final navContext = _navigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      showDialog(
        context: navContext,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  AppLocalizations.of(dialogContext)!.msgConnectProcessing,
                ),
              ),
            ],
          ),
        ),
      );
    }

    try {
      if (OidcService.isCallbackUri(link)) {
        final result = await OidcService.completeFlow(link);
        if (result != null) {
          await AuthService.saveOidcLogin(
            serverUrl: result.serverUrl,
            apiKey: result.apiKey,
          );
        }
      } else {
        final result = await ConnectService.completeFlow(link);
        if (result != null) {
          await _addServerFromConnect(result);
        }
      }
    } catch (_) {
      // 授权码交换失败：流程状态已清理，保持静默
    } finally {
      _handlingPendingLink = false;
      if (navContext != null && navContext.mounted) {
        Navigator.of(navContext, rootNavigator: true).pop();
      }
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
      navigatorKey: _navigatorKey,
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
      supportedLocales: const [Locale('en'), Locale('zh')],
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isLoggedIn!) {
      return const MainTabScreen();
    }

    return const LoginScreen();
  }
}
