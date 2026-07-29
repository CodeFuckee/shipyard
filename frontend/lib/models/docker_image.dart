class DockerImage {
  final String id;
  final List<String> repoTags;
  final int created;
  final int size;
  final int virtualSize;
  final bool inUse;

  DockerImage({
    required this.id,
    required this.repoTags,
    required this.created,
    required this.size,
    required this.virtualSize,
    required this.inUse,
  });

  factory DockerImage.fromJson(Map<String, dynamic> json) {
    // Handle tags/RepoTags
    final tagsData = json['tags'] ?? json['RepoTags'];
    final List<String> tags = tagsData != null ? List<String>.from(tagsData) : [];

    // Handle created date (can be ISO string or int timestamp)
    int createdTimestamp = 0;
    final createdData = json['created'] ?? json['Created'];
    if (createdData is String) {
      try {
        createdTimestamp = DateTime.parse(createdData).millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        // Ignore parse error
      }
    } else if (createdData is int) {
      createdTimestamp = createdData;
    }

    return DockerImage(
      id: json['id'] ?? json['Id'] ?? '',
      repoTags: tags,
      created: createdTimestamp,
      size: json['size'] ?? json['Size'] ?? 0,
      virtualSize: json['virtualSize'] ?? json['VirtualSize'] ?? json['size'] ?? json['Size'] ?? 0,
      inUse: json['in_use'] ?? false,
    );
  }
}
