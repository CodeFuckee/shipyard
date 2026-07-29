import 'package:flutter/material.dart';

/// 代码编辑器组件
/// 支持 Dockerfile 和 YAML 的基础语法高亮，带行号显示
class CodeEditor extends StatefulWidget {
  final String content;
  final ValueChanged<String> onChanged;
  final String language; // 'dockerfile' 或 'yaml'
  final bool readOnly;

  const CodeEditor({
    super.key,
    required this.content,
    required this.onChanged,
    this.language = 'dockerfile',
    this.readOnly = false,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = _HighlightController(
      content: widget.content,
      language: widget.language,
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content &&
        _controller.text != widget.content) {
      _controller.text = widget.content;
    }
    if (oldWidget.language != widget.language) {
      (_controller as _HighlightController).language = widget.language;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _lineCount => '\n'.allMatches(_controller.text).length + 1;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final editorBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final lineNumBg = isDark ? const Color(0xFF252526) : const Color(0xFFEEEEEE);
    final lineNumColor = isDark ? const Color(0xFF858585) : const Color(0xFF999999);
    final textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF333333);
    final cursorColor = colorScheme.primary;

    return Container(
      color: editorBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号区域
          Container(
            width: 48,
            color: lineNumBg,
            padding: const EdgeInsets.only(top: 16, right: 8),
            child: Text(
              _buildLineNumbers(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: lineNumColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // 分割线
          Container(
            width: 1,
            color: isDark
                ? const Color(0xFF3E3E3E)
                : const Color(0xFFDDDDDD),
          ),
          // 编辑区域
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: widget.readOnly,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: textColor,
              ),
              cursorColor: cursorColor,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
                isCollapsed: true,
              ),
              onChanged: widget.onChanged,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ],
      ),
    );
  }

  String _buildLineNumbers() {
    final buffer = StringBuffer();
    for (int i = 1; i <= _lineCount; i++) {
      buffer.writeln('$i');
    }
    return buffer.toString();
  }
}

/// 带语法高亮的 TextEditingController
class _HighlightController extends TextEditingController {
  String language;

  _HighlightController({required String content, required this.language})
      : super(text: content);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spans = <TextSpan>[];
    final text = this.text;

    if (language == 'dockerfile') {
      spans.addAll(_highlightDockerfile(text, isDark));
    } else if (language == 'yaml') {
      spans.addAll(_highlightYaml(text, isDark));
    }

    if (spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    return TextSpan(style: style, children: spans);
  }

  List<TextSpan> _highlightDockerfile(String text, bool isDark) {
    final keywordColor = isDark
        ? const Color(0xFF569CD6) // 蓝
        : const Color(0xFF0000FF);
    final commentColor = isDark
        ? const Color(0xFF6A9955) // 绿灰
        : const Color(0xFF008000);
    final defaultColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF333333);

    final spans = <TextSpan>[];
    final keywords = [
      'FROM', 'RUN', 'CMD', 'LABEL', 'MAINTAINER', 'EXPOSE', 'ENV',
      'ADD', 'COPY', 'ENTRYPOINT', 'VOLUME', 'USER', 'WORKDIR',
      'ARG', 'ONBUILD', 'STOPSIGNAL', 'HEALTHCHECK', 'SHELL',
    ];

    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        spans.add(const TextSpan(text: '\n'));
      }

      final line = lines[i];
      final trimmed = line.trimLeft();

      // 注释行
      if (trimmed.startsWith('#')) {
        spans.add(TextSpan(
          text: line,
          style: TextStyle(color: commentColor, fontStyle: FontStyle.italic),
        ));
        continue;
      }

      // 检查是否为指令行
      final upperLine = trimmed.toUpperCase();
      bool matched = false;
      for (final keyword in keywords) {
        if (upperLine.startsWith(keyword)) {
          final prefix = line.substring(0, line.indexOf(trimmed));
          final afterKeyword = trimmed.substring(keyword.length);

          spans.add(TextSpan(text: prefix));
          spans.add(TextSpan(
            text: keyword,
            style: TextStyle(color: keywordColor, fontWeight: FontWeight.bold),
          ));
          spans.add(_highlightDockerfileValue(afterKeyword, isDark));
          matched = true;
          break;
        }
      }

      if (!matched) {
        spans.add(TextSpan(text: line, style: TextStyle(color: defaultColor)));
      }
    }

    return spans;
  }

  TextSpan _highlightDockerfileValue(String text, bool isDark) {
    final stringColor = isDark
        ? const Color(0xFFCE9178)
        : const Color(0xFFA31515);
    final defaultColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF333333);

    final children = <TextSpan>[];
    final regex = RegExp(r'''(["'])(?:\\.|[^\\])*?\1|(\S+)''');
    final matches = regex.allMatches(text);

    for (final match in matches) {
      if (match.group(1) != null) {
        children.add(TextSpan(
          text: match.group(0),
          style: TextStyle(color: stringColor),
        ));
      } else {
        children.add(TextSpan(
          text: match.group(0),
          style: TextStyle(color: defaultColor),
        ));
      }
    }

    return TextSpan(children: children);
  }

  List<TextSpan> _highlightYaml(String text, bool isDark) {
    final keyColor = isDark
        ? const Color(0xFF9CDCFE) // 浅蓝
        : const Color(0xFF0000FF);
    final stringColor = isDark
        ? const Color(0xFFCE9178) // 橙
        : const Color(0xFFA31515);
    final commentColor = isDark
        ? const Color(0xFF6A9955)
        : const Color(0xFF008000);
    final defaultColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF333333);
    final numberColor = isDark
        ? const Color(0xFFB5CEA8)
        : const Color(0xFF098658);

    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        spans.add(const TextSpan(text: '\n'));
      }

      final line = lines[i];
      final trimmed = line.trimLeft();

      // 注释
      if (trimmed.startsWith('#')) {
        spans.add(TextSpan(
          text: line,
          style: TextStyle(color: commentColor, fontStyle: FontStyle.italic),
        ));
        continue;
      }

      // 列表项
      if (trimmed.startsWith('- ')) {
        spans.add(_parseYamlListItem(line, trimmed, keyColor, stringColor,
            numberColor, defaultColor, isDark));
        continue;
      }

      // Key: Value 行 (非列表)
      if (trimmed.contains(':')) {
        spans.add(_parseYamlKeyValue(line, trimmed, keyColor, stringColor,
            numberColor, defaultColor, isDark));
        continue;
      }

      spans.add(TextSpan(text: line, style: TextStyle(color: defaultColor)));
    }

    return spans;
  }

  TextSpan _parseYamlKeyValue(String line, String trimmed, Color keyColor,
      Color stringColor, Color numberColor, Color defaultColor, bool isDark) {
    final prefix = line.substring(0, line.indexOf(trimmed));
    final colonIdx = trimmed.indexOf(':');
    final key = trimmed.substring(0, colonIdx);
    final after = trimmed.substring(colonIdx + 1);

    return TextSpan(children: [
      TextSpan(text: prefix),
      TextSpan(
        text: key,
        style: TextStyle(color: keyColor),
      ),
      const TextSpan(text: ':'),
      _highlightYamlValue(after, stringColor, numberColor, defaultColor),
    ]);
  }

  TextSpan _parseYamlListItem(String line, String trimmed, Color keyColor,
      Color stringColor, Color numberColor, Color defaultColor, bool isDark) {
    final prefix = line.substring(0, line.indexOf(trimmed));
    final afterDash = trimmed.substring(2);

    // - key: value
    if (afterDash.contains(':')) {
      final colonIdx = afterDash.indexOf(':');
      final key = afterDash.substring(0, colonIdx);
      final value = afterDash.substring(colonIdx + 1);

      return TextSpan(children: [
        TextSpan(text: prefix),
        const TextSpan(text: '- '),
        TextSpan(
          text: key,
          style: TextStyle(color: keyColor),
        ),
        const TextSpan(text: ':'),
        _highlightYamlValue(value, stringColor, numberColor, defaultColor),
      ]);
    }

    // - "string value"
    return TextSpan(children: [
      TextSpan(text: prefix),
      const TextSpan(text: '- '),
      _highlightYamlValue(afterDash, stringColor, numberColor, defaultColor),
    ]);
  }

  TextSpan _highlightYamlValue(
      String text, Color stringColor, Color numberColor, Color defaultColor) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return TextSpan(text: text, style: TextStyle(color: defaultColor));
    }

    // 引号字符串
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return TextSpan(text: text, style: TextStyle(color: stringColor));
    }

    // 布尔值
    if (trimmed == 'true' || trimmed == 'false' || trimmed == 'yes' || trimmed == 'no') {
      return TextSpan(
        text: text,
        style: TextStyle(color: numberColor, fontWeight: FontWeight.bold),
      );
    }

    // 数字
    if (double.tryParse(trimmed) != null) {
      return TextSpan(text: text, style: TextStyle(color: numberColor));
    }

    return TextSpan(text: text, style: TextStyle(color: defaultColor));
  }
}
