import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'test_utils.dart';

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettingsScreen(WidgetTester tester,
      {String buildTime = ''}) async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'test-token',
      'docker_auth_server_url': 'http://test-server:9000',
      'docker_api_key': 'test-api-key',
      'docker_api_url': 'http://test-server:9000/api',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );
    await tester.pumpWidget(
      buildTestApp(home: SettingsScreen(buildTime: buildTime)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('构建时间为空时设置页不显示构建时间行', (tester) async {
    await pumpSettingsScreen(tester, buildTime: '');

    final t = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)))!;
    expect(find.textContaining(t.labelBuildTime), findsNothing);
  });

  testWidgets('构建时间为纯空白时设置页不显示构建时间行', (tester) async {
    await pumpSettingsScreen(tester, buildTime: '   ');

    final t = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)))!;
    expect(find.textContaining(t.labelBuildTime), findsNothing);
  });

  testWidgets('构建时间非空时设置页显示构建时间', (tester) async {
    const buildTime = '2026-08-02 15:30:45';
    await pumpSettingsScreen(tester, buildTime: buildTime);

    final t = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)))!;
    final labelFinder = find.textContaining(t.labelBuildTime);
    expect(labelFinder, findsOneWidget);
    expect(find.textContaining(buildTime), findsOneWidget);
  });

  testWidgets('构建时间不影响版本号徽章显示（回归）', (tester) async {
    await pumpSettingsScreen(tester, buildTime: '2026-08-02 15:30:45');

    // PackageInfo mock 版本 1.0.0+1 → 徽章文本 v1.0.0+1
    expect(find.text('v1.0.0+1'), findsOneWidget);
  });
}
