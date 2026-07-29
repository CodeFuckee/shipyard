class Project {
  final String id;
  final String name;
  final String description;
  final String status; // 'idle', 'building', 'running', 'failed'
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.status = 'idle',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    String getString(List<String> keys) {
      for (final key in keys) {
        final val = json[key];
        if (val != null && val is String) {
          return val;
        }
      }
      return '';
    }

    DateTime parseDateTime(List<String> keys) {
      for (final key in keys) {
        final val = json[key];
        if (val != null) {
          if (val is String) {
            return DateTime.tryParse(val) ?? DateTime.now();
          }
        }
      }
      return DateTime.now();
    }

    return Project(
      id: getString(['id', 'Id', 'ID']),
      name: getString(['name', 'Name']),
      description: getString(['description', 'Description']),
      status: getString(['status', 'Status']),
      createdAt: parseDateTime(['createdAt', 'created_at', 'CreatedAt', 'Created']),
      updatedAt: parseDateTime(['updatedAt', 'updated_at', 'UpdatedAt', 'Updated']),
    );
  }
}
