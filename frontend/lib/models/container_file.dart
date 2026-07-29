class ContainerFile {
  final String name;
  final String type;
  final int size;
  final double modified;
  final bool isSymlink;
  final bool isMounted;

  ContainerFile({
    required this.name,
    required this.type,
    required this.size,
    required this.modified,
    required this.isSymlink,
    required this.isMounted,
  });

  factory ContainerFile.fromJson(Map<String, dynamic> json) {
    return ContainerFile(
      name: json['name'] ?? '',
      type: json['type'] ?? 'file',
      size: (json['size'] ?? 0).toInt(),
      modified: (json['modified'] ?? 0).toDouble(),
      isSymlink: json['is_symlink'] ?? false,
      isMounted: json['is_mounted'] ?? false,
    );
  }

  bool get isDirectory => type == 'directory';
  DateTime get modifiedDate => DateTime.fromMillisecondsSinceEpoch((modified * 1000).toInt());
}
