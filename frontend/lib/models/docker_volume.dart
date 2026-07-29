class DockerVolume {
  final String id;
  final String name;
  final String driver;
  final String mountpoint;
  final String created;
  final Map<String, String> labels;
  final bool inUse;

  DockerVolume({
    required this.id,
    required this.name,
    required this.driver,
    required this.mountpoint,
    required this.created,
    required this.labels,
    required this.inUse,
  });

  factory DockerVolume.fromJson(Map<String, dynamic> json) {
    return DockerVolume(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      driver: json['driver'] ?? '',
      mountpoint: json['mountpoint'] ?? '',
      created: json['created'] ?? '',
      labels: (json['labels'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value.toString()),
          ) ??
          {},
      inUse: json['in_use'] ?? false,
    );
  }
}
