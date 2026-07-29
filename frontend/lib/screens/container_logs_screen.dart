import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:flutter/services.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'dart:async';
import '../services/docker_service.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';

class ContainerLogsScreen extends StatefulWidget {
  final String containerId;
  final String containerName;
  final String apiUrl;
  final String apiKey;
  final bool isEmbedded;
  final bool ignoreSsl;

  const ContainerLogsScreen({
    super.key,
    required this.containerId,
    required this.containerName,
    required this.apiUrl,
    required this.apiKey,
    this.isEmbedded = false,
    this.ignoreSsl = false,
  });

  @override
  State<ContainerLogsScreen> createState() => _ContainerLogsScreenState();
}

class _ContainerLogsScreenState extends State<ContainerLogsScreen> {
  List<String> _logLines = [];
  bool _isLoading = true;
  String? _error;
  bool _isPaused = false;
  
  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<int> _searchResults = [];
  int _currentSearchIndex = 0;

  // View settings
  bool _showTimestamps = true;
  double _fontSize = 13.0;
  
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  Timer? _refreshTimer;
  final FocusNode _searchFocusNode = FocusNode();

  double get _itemHeight => _fontSize * 1.5 + 4; // Dynamic item height based on font size
  double _contentWidth = 0;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isPaused) {
        _fetchLogs(isBackground: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _calculateContentWidth() {
    if (_logLines.isEmpty) {
      _contentWidth = 0;
      return;
    }
    int maxLen = 0;
    for (var line in _logLines) {
      if (line.length > maxLen) maxLen = line.length;
    }

    final TextPainter textPainter = TextPainter(
      text: TextSpan(
          text: 'A',
          style: TextStyle(fontFamily: 'monospace', fontSize: _fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();

    // Estimate width: maxLen * charWidth + padding
    _contentWidth = maxLen * textPainter.width + 60;
  }

  Future<void> _fetchLogs({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final service = DockerService(baseUrl: widget.apiUrl, apiKey: widget.apiKey, ignoreSsl: widget.ignoreSsl);
    try {
      final logs = await service.getContainerLogs(widget.containerId);
      if (mounted) {
        setState(() {
          if (logs.isEmpty) {
            _logLines = ["No logs found."];
          } else {
            _logLines = logs.split('\n');
            if (_logLines.last.isEmpty) {
              _logLines.removeLast();
            }
          }
          _calculateContentWidth();
          _isLoading = false;
        });
        
        // Re-run search if active
        if (_isSearching && _searchController.text.isNotEmpty) {
           _performSearch(_searchController.text, keepIndex: true);
        }

        // Scroll to bottom on initial load only
        if (!isBackground && !_isSearching) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          ApiErrorHandler.show(context, e);
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _logLines.isNotEmpty) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _performSearch(String query, {bool keepIndex = false}) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = 0;
      });
      return;
    }

    final List<int> results = [];
    final lowerQuery = query.toLowerCase();

    for (int i = 0; i < _logLines.length; i++) {
      if (_logLines[i].toLowerCase().contains(lowerQuery)) {
        results.add(i);
      }
    }

    setState(() {
      _searchResults = results;
      if (!keepIndex || _currentSearchIndex >= results.length) {
        _currentSearchIndex = 0;
      }
    });

    if (results.isNotEmpty && !keepIndex) {
      _scrollToMatch(_currentSearchIndex);
    }
  }

  void _scrollToMatch(int index) {
    if (index >= 0 && index < _searchResults.length) {
      final targetLineIndex = _searchResults[index];
      // Scroll to the line. 
      // We use jumpTo for instant navigation, or animateTo for smooth.
      // Since itemExtent is fixed, we can calculate offset.
      final offset = targetLineIndex * _itemHeight;
      
      // Ensure offset is within bounds
      final maxOffset = _scrollController.position.maxScrollExtent;
      final safeOffset = offset > maxOffset ? maxOffset : offset;

      _scrollController.animateTo(
        safeOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextMatch() {
    if (_searchResults.isEmpty) return;
    setState(() {
      if (_currentSearchIndex < _searchResults.length - 1) {
        _currentSearchIndex++;
      } else {
        _currentSearchIndex = 0; // Loop back to start
      }
    });
    _scrollToMatch(_currentSearchIndex);
  }

  void _prevMatch() {
    if (_searchResults.isEmpty) return;
    setState(() {
      if (_currentSearchIndex > 0) {
        _currentSearchIndex--;
      } else {
        _currentSearchIndex = _searchResults.length - 1; // Loop to end
      }
    });
    _scrollToMatch(_currentSearchIndex);
  }

  List<Widget> _buildActionButtons() {
    final t = AppLocalizations.of(context)!;
    return [
      IconButton(
        icon: const Icon(RemixIcon.searchLine),
        onPressed: () {
          setState(() {
            _isSearching = true;
          });
          // Focus after rebuild
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _searchFocusNode.requestFocus();
          });
        },
      ),
      IconButton(
        icon: Icon(_isPaused ? RemixIcon.playLine : RemixIcon.pauseLine),
        tooltip: _isPaused ? t.actionResume : t.actionPause,
        onPressed: () {
          setState(() {
            _isPaused = !_isPaused;
          });
          if (!_isPaused) {
            _fetchLogs();
          }
        },
      ),
      IconButton(
        icon: Icon(_showTimestamps ? RemixIcon.timeFill : RemixIcon.timeLine),
        tooltip: _showTimestamps ? 'Hide Timestamps' : 'Show Timestamps',
        onPressed: () {
          setState(() {
            _showTimestamps = !_showTimestamps;
          });
        },
      ),
      IconButton(
        icon: const Icon(RemixIcon.refreshLine),
        onPressed: _fetchLogs,
      ),
      IconButton(
        icon: const Icon(RemixIcon.fileCopyLine),
        onPressed: _logLines.isEmpty ? null : () {
          Clipboard.setData(ClipboardData(text: _logLines.join('\n')));
          NotifyUtils.showNotify(context, 'Logs copied to clipboard');
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actionButtons = _buildActionButtons();
    
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isEmbedded,
        titleSpacing: widget.isEmbedded && !_isSearching ? 0 : NavigationToolbar.kMiddleSpacing,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                onChanged: (value) => _performSearch(value),
                onSubmitted: (_) => _nextMatch(),
                textInputAction: TextInputAction.search,
              )
            : (widget.isEmbedded 
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: actionButtons,
                  ) 
                : Text('${widget.containerName} Logs')),
        elevation: 0,
        actions: [
          if (_isSearching) ...[
             Center(
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 8.0),
                 child: Text(
                   _searchResults.isNotEmpty 
                     ? '${_currentSearchIndex + 1}/${_searchResults.length}' 
                     : '0/0',
                   style: const TextStyle(fontSize: 14),
                 ),
               ),
             ),
             IconButton(
               icon: const Icon(RemixIcon.arrowUpSLine),
               onPressed: _prevMatch,
               tooltip: 'Previous',
             ),
             IconButton(
               icon: const Icon(RemixIcon.arrowDownSLine),
               onPressed: _nextMatch,
               tooltip: 'Next',
             ),
             IconButton(
               icon: const Icon(RemixIcon.closeLine),
               onPressed: () {
                 setState(() {
                   _isSearching = false;
                   _searchController.clear();
                   _searchResults = [];
                 });
               },
             ),
          ] else if (!widget.isEmbedded) ...actionButtons,
        ],
      ),
      body: _isLoading
          ? const LoadingView(type: LoadingType.card)
          : _error != null
              ? ErrorView(
                  message: _error!,
                  onRetry: _fetchLogs,
                  retryLabel: 'Retry',
                )
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: SizedBox(
                              width: _contentWidth > constraints.maxWidth
                                  ? _contentWidth
                                  : constraints.maxWidth,
                              child: SelectionArea(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemCount: _logLines.length,
                                  itemExtent: _itemHeight,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemBuilder: (context, index) {
                                    final line = _logLines[index];
                                    final isMatch =
                                        _searchResults.contains(index);
                                    final isCurrentMatch = isMatch &&
                                        _searchResults.isNotEmpty &&
                                        _searchResults[_currentSearchIndex] ==
                                            index;

                                    return Container(
                                      height: _itemHeight,
                                      color: isCurrentMatch
                                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0),
                                      alignment: Alignment.centerLeft,
                                      child: RichText(
                                        text: TextSpan(
                                          children: _buildLogLineSpans(
                                              line, _searchController.text),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: _fontSize,
                                            height: 1.5,
                                            color: const Color(0xFFD4D4D4),
                                          ),
                                        ),
                                        overflow: TextOverflow.visible,
                                        softWrap: false,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "zoom_in",
            mini: true,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Icon(RemixIcon.addLine, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              setState(() {
                if (_fontSize < 30) {
                  _fontSize += 2;
                  _calculateContentWidth();
                }
              });
            },
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "zoom_out",
            mini: true,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Icon(RemixIcon.indeterminateCircleLine, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              setState(() {
                if (_fontSize > 8) {
                  _fontSize -= 2;
                  _calculateContentWidth();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildLogLineSpans(String line, String searchQuery) {
    // 1. Determine syntax coloring parts
    final timestampRegex = RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s?(.*)$');
    final match = timestampRegex.firstMatch(line);
    
    List<TextSpan> baseSpans = [];

    final cs = Theme.of(context).colorScheme;

    if (match != null) {
      final timestamp = match.group(1)!;
      final content = match.group(2) ?? '';

      if (_showTimestamps) {
        baseSpans.add(TextSpan(
          text: '$timestamp ',
          style: TextStyle(color: cs.primary),
        ));
      }

      Color contentColor = cs.onSurface;
      if (content.contains('ERROR') || content.contains('Exception') || content.contains('fail')) {
        contentColor = cs.error;
      } else if (content.contains('WARN')) {
        contentColor = cs.tertiary;
      } else if (content.contains('INFO')) {
        contentColor = cs.primary;
      }

      baseSpans.add(TextSpan(
        text: content,
        style: TextStyle(color: contentColor),
      ));
    } else {
      Color lineColor = cs.onSurface;
      if (line.contains('ERROR') || line.contains('Exception') || line.contains('fail')) {
        lineColor = cs.error;
      } else if (line.contains('WARN')) {
        lineColor = cs.tertiary;
      }

      baseSpans.add(TextSpan(
        text: line,
        style: TextStyle(color: lineColor),
      ));
    }

    // 2. Apply search highlighting
    if (searchQuery.isEmpty) return baseSpans;

    final List<TextSpan> finalSpans = [];
    final lowerQuery = searchQuery.toLowerCase();

    for (var span in baseSpans) {
      final text = span.text!;
      final lowerText = text.toLowerCase();
      int start = 0;
      int indexOfMatch;

      while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
        // Text before match
        if (indexOfMatch > start) {
          finalSpans.add(TextSpan(
            text: text.substring(start, indexOfMatch),
            style: span.style,
          ));
        }

        // Matched text
        finalSpans.add(TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + lowerQuery.length),
          style: span.style?.copyWith(
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ) ?? TextStyle(backgroundColor: Theme.of(context).colorScheme.tertiaryContainer, color: Theme.of(context).colorScheme.onTertiaryContainer),
        ));

        start = indexOfMatch + lowerQuery.length;
      }

      // Remaining text
      if (start < text.length) {
        finalSpans.add(TextSpan(
          text: text.substring(start),
          style: span.style,
        ));
      }
    }

    return finalSpans;
  }
}
