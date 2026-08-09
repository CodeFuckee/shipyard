import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

/// 临时探测测试：dump 设置页语义树，定位 CI 上"添加服务器"按钮
/// 语义节点缺失的根因（与浏览器无关的语义生成问题）。
/// 验证后删除。
void _dumpSemantics(WidgetTester tester, String tag) {
  final nodes = <String>[];
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) {
    // ignore: avoid_print
    print('===== 语义树[$tag] 未启用 =====');
    return;
  }

  void walk(SemanticsNode n, int depth) {
    final label = n.label;
    final props = <String>[
      'label=${label.isEmpty ? '∅' : label.replaceAll('\n', '␊')}',
      'button=${n.hasFlag(SemanticsFlag.isButton)}',
    ];
    nodes.add('${'  ' * depth}${n.role.name}: $props');
    n.visitChildren((child) {
      walk(child, depth + 1);
      return true;
    });
  }

  walk(root, 0);
  // ignore: avoid_print
  print('===== 语义树[$tag] =====');
  for (final line in nodes) {
    // ignore: avoid_print
    print(line);
  }
  // ignore: avoid_print
  print('===== 含 Add Server 的节点: '
      '${nodes.where((l) => l.contains('Add Server')).length} =====');
  // ignore: avoid_print
  print('===== 含 Servers 的节点: '
      '${nodes.where((l) => l.contains('Servers')).length} =====');
}

Future<void> _pump(WidgetTester tester) async {
  PackageInfo.setMockInitialValues(
    appName: 'Test',
    packageName: 'test',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: 'test-signature',
  );
  await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('空列表语义树', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final handle = tester.ensureSemantics();
    await _pump(tester);
    _dumpSemantics(tester, '空列表');
    handle.dispose();
  });

  testWidgets('非空列表（server_list 预置 Default Server）语义树', (tester) async {
    SharedPreferences.setMockInitialValues({
      'server_list': jsonEncodeList(),
      'docker_api_url': 'https://home.chenkaidi.top:507',
    });
    final handle = tester.ensureSemantics();
    await _pump(tester);
    _dumpSemantics(tester, '非空列表');
    handle.dispose();
  });
}

String jsonEncodeList() {
  return '[{"name":"Default Server","url":"https://home.chenkaidi.top:507","apiKey":"k"}]';
}
