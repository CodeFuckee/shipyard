class BuildLog {
  final String? stream;
  final String? status;
  final String? error;
  final String? imageId;
  final bool isDone;
  final String? rawMessage;

  BuildLog({
    this.stream,
    this.status,
    this.error,
    this.imageId,
    this.isDone = false,
    this.rawMessage,
  });

  factory BuildLog.fromJson(Map<String, dynamic> json) {
    String? getNullableString(List<String> keys) {
      for (final key in keys) {
        final val = json[key];
        if (val != null && val is String && val.isNotEmpty) {
          return val;
        }
      }
      return null;
    }

    bool getBool(List<String> keys) {
      for (final key in keys) {
        final val = json[key];
        if (val != null) {
          if (val is bool) return val;
          if (val is String) return val.toLowerCase() == 'true';
        }
      }
      return false;
    }

    return BuildLog(
      stream: getNullableString(['stream', 'Stream']),
      status: getNullableString(['status', 'Status']),
      error: getNullableString(['error', 'Error', 'errorDetail']),
      imageId: getNullableString(['imageId', 'image_id', 'ImageId']),
      isDone: getBool(['isDone', 'is_done', 'done', 'Done']),
      rawMessage: getNullableString(['message', 'rawMessage', 'raw_message']),
    );
  }
}
