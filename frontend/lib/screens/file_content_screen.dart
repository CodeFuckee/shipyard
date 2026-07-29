import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import '../services/docker_service.dart';

class FileContentScreen extends StatefulWidget {
  final String containerId;
  final String filePath;
  final String initialContent;
  final String apiUrl;
  final String? apiKey;
  final bool ignoreSsl;

  const FileContentScreen({
    super.key,
    required this.containerId,
    required this.filePath,
    required this.initialContent,
    required this.apiUrl,
    this.apiKey,
    this.ignoreSsl = false,
  });

  @override
  State<FileContentScreen> createState() => _FileContentScreenState();
}

class _FileContentScreenState extends State<FileContentScreen> {
  late TextEditingController _contentController;
  bool _isEditing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveFile() async {
    setState(() {
      _isLoading = true;
    });

    final service = DockerService(
      baseUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );

    final t = AppLocalizations.of(context)!;

    try {
      await service.updateContainerFile(
        widget.containerId,
        widget.filePath,
        _contentController.text,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isEditing = false;
      });

      NotifyUtils.showNotify(context, t.msgFileSaved);
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });

      NotifyUtils.showNotify(context, t.msgErrorSavingFile(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filePath.split('/').last),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(RemixIcon.editLine),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(RemixIcon.saveLine),
              onPressed: _isLoading ? null : _saveFile,
            ),
            IconButton(
              icon: const Icon(RemixIcon.closeLine),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _contentController.text = widget.initialContent; // Reset content
                });
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _isEditing
                  ? TextField(
                      controller: _contentController,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14.0,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    )
                  : SelectableText(
                      _contentController.text, // Show current text (could be edited but not saved? No, reset on cancel)
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14.0,
                      ),
                    ),
            ),
    );
  }
}
