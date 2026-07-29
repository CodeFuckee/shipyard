class DockerNetwork {
  final String id;
  final String name;
  final String driver;
  final String shortId;
  final String created;

  DockerNetwork({
    required this.id,
    required this.name,
    required this.driver,
    required this.shortId,
    required this.created,
  });

  factory DockerNetwork.fromJson(Map<String, dynamic> json) {
    return DockerNetwork(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      driver: json['driver'] ?? '',
      shortId: json['short_id'] ?? '',
      created: json['created'] ?? '',
    );
  }
}
