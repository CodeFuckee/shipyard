import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/widgets/code_editor.dart';

import 'test_utils.dart';

/// 代码编辑器（Dockerfile 高亮）空格保留测试：
/// 语法高亮渲染后的纯文本必须与原始内容完全一致，
/// 不得吞掉 token 之间的空格（行首缩进、参数分隔、多空格对齐）。
void main() {
  /// 渲染 CodeEditor 并返回高亮后的纯文本。
  Future<String> renderSpanText(
    WidgetTester tester,
    String content, {
    String language = 'dockerfile',
  }) async {
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: CodeEditor(
          content: content,
          onChanged: (_) {},
          language: language,
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    final controller = textField.controller!;
    final context = tester.element(find.byType(TextField));
    final span = controller.buildTextSpan(
      context: context,
      style: null,
      withComposing: false,
    );
    return span.toPlainText();
  }

  testWidgets('Dockerfile 高亮保留指令后的参数空格', (tester) async {
    const content = 'RUN apt-get update && apt-get install -y curl\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '指令参数之间的空格被高亮吞掉');
  });

  testWidgets('Dockerfile 高亮保留 WORKDIR/COPY 等单空格参数', (tester) async {
    const content = 'FROM python:3.12-slim\n'
        'WORKDIR /app\n'
        'COPY requirements.txt /app/requirements.txt\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '单空格参数分隔符被高亮吞掉');
  });

  testWidgets('Dockerfile 高亮保留行首缩进', (tester) async {
    // Dockerfile 延续行（行首空格是语法的一部分）
    const content = 'RUN apt-get update \\\n'
        '    && apt-get install -y curl \\\n'
        '    && rm -rf /var/lib/apt/lists/*\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '延续行的行首缩进被高亮吞掉');
  });

  testWidgets('Dockerfile 高亮保留多空格对齐', (tester) async {
    const content = 'ENV   PYTHONUNBUFFERED=1\n'
        'LABEL  org.opencontainers.image.title="shipyard"\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '多空格对齐被高亮吞掉');
  });

  testWidgets('Dockerfile 高亮保留引号内字符串与 CMD 参数', (tester) async {
    const content = 'CMD ["python", "app.py"]\n'
        'ENTRYPOINT ["sh", "-c"]\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '引号/JSON 参数内的空格被高亮吞掉');
  });

  testWidgets('Dockerfile 注释行与普通行空格不变', (tester) async {
    const content = '#  this is a comment\n'
        'FROM node:20\n'
        'this is not a directive\n';
    final rendered = await renderSpanText(tester, content);
    expect(rendered, content,
        reason: '注释/普通行渲染与原文不一致');
  });

  testWidgets('YAML 高亮同样保留空格', (tester) async {
    const content = 'services:\n'
        '  web:\n'
        '    image: nginx:latest\n'
        '    ports:\n'
        '      - "8080:80"\n';
    final rendered =
        await renderSpanText(tester, content, language: 'yaml');
    expect(rendered, content, reason: 'YAML 高亮渲染与原文不一致');
  });
}
