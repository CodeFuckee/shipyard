import 'dart:async';

import 'package:flutter/material.dart';
import '../models/build_log.dart';

/// 构建日志实时显示组件
class BuildLogView extends StatefulWidget {
  final Stream<BuildLog> logStream;
  final VoidCallback? onBuildComplete;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const BuildLogView({
    super.key,
    required this.logStream,
    this.onBuildComplete,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<BuildLogView> createState() => _BuildLogViewState();
}

class _BuildLogViewState extends State<BuildLogView> {
  final ScrollController _scrollController = ScrollController();
  final List<BuildLog> _logs = [];
  bool _isBuilding = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isBuilding = true;
    widget.logStream.listen(
      _onLogReceived,
      onError: (error) {
        if (mounted) {
          setState(() {
            _isBuilding = false;
            _errorMessage = error.toString();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isBuilding = false;
          });
        }
      },
    );
  }

  void _onLogReceived(BuildLog log) {
    if (!mounted) return;
    setState(() {
      _logs.add(log);
      if (log.isDone) {
        _isBuilding = false;
        if (log.error != null) {
          _errorMessage = log.error;
        }
        widget.onBuildComplete?.call();
      }
    });

    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFF1A1A1A);
    final headerBg = isDark ? const Color(0xFF2D2D2D) : const Color(0xFF333333);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 日志头部
        GestureDetector(
          onTap: widget.onToggleCollapse,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: headerBg,
            child: Row(
              children: [
                Icon(
                  _isBuilding ? Icons.sync : (_errorMessage != null ? Icons.error : Icons.check_circle),
                  size: 16,
                  color: _isBuilding
                      ? Colors.orange
                      : (_errorMessage != null ? Colors.red : Colors.green),
                ),
                const SizedBox(width: 8),
                Text(
                  _isBuilding
                      ? 'Building...'
                      : (_errorMessage != null ? 'Build Failed' : 'Build Complete'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (widget.onToggleCollapse != null)
                  Icon(
                    widget.isCollapsed ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        // 日志内容
        if (!widget.isCollapsed)
          Container(
            height: 200,
            color: logBg,
            child: _logs.isEmpty && _isBuilding
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _logs.isEmpty
                    ? const Center(
                        child: Text(
                          'No build logs yet',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return _buildLogLine(_logs[index], isDark);
                        },
                      ),
          ),
      ],
    );
  }

  Widget _buildLogLine(BuildLog log, bool isDark) {
    final Color textColor;
    String text;

    if (log.error != null) {
      textColor = const Color(0xFFF44747);
      text = log.error!;
    } else if (log.stream != null) {
      textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFFCCCCCC);
      text = log.stream!;
    } else if (log.status != null) {
      textColor = isDark ? const Color(0xFF4EC9B0) : const Color(0xFF4EC9B0);
      text = log.status!;
    } else if (log.rawMessage != null) {
      textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFFCCCCCC);
      text = log.rawMessage!;
    } else {
      textColor = Colors.grey;
      text = '';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: textColor,
        ),
      ),
    );
  }
}
