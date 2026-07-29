class DockerContainer {
  final String id;
  final String name;
  final String status;
  final String stack;
  final String image;
  final String ports;
  final bool isSelf;

  DockerContainer({
    required this.id,
    required this.name,
    required this.status,
    required this.stack,
    required this.image,
    required this.ports,
    required this.isSelf,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    // Helper to get value from multiple possible keys
    String getString(List<String> keys) {
      for (final key in keys) {
        if (json[key] != null && json[key] is String) {
          return json[key] as String;
        }
      }
      return '';
    }

    // Try to get status from 'State' (machine readable) first, then 'status'
    // Normalize status to lowercase for consistency
    String status = getString(['State', 'status', 'Status']).toLowerCase();

    return DockerContainer(
      id: getString(['id', 'Id', 'ID']),
      name: getString(['name', 'Name', 'Names']), // Names is usually array, but handle string case just in case
      status: status,
      stack: getString(['stack', 'Stack', 'com.docker.compose.project']),
      image: getString(['image', 'Image']),
      ports: getString(['ports', 'Ports']),
      isSelf: json['is_self'] as bool? ?? false,
    );
  }

  DockerContainer copyWith({
    String? id,
    String? name,
    String? status,
    String? stack,
    String? image,
    String? ports,
    bool? isSelf,
  }) {
    return DockerContainer(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      stack: stack ?? this.stack,
      image: image ?? this.image,
      ports: ports ?? this.ports,
      isSelf: isSelf ?? this.isSelf,
    );
  }
}
