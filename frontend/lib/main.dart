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
import 'services/harmonyos_shared_prefs.dart';
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
